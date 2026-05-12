import Foundation
import CoreServices

actor SessionMonitor {
    static let shared = SessionMonitor()

    private let sessionsDir: URL
    private var activeSessions: [String: ClaudeSession] = [:]   // sessionId → session
    private var eventStream: FSEventStreamRef?
    private var idleTimers: [String: Task<Void, Never>] = [:]

    private init() {
        sessionsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions")
    }

    // MARK: - Start

    func start() async {
        loadExisting()
        startFSEvents()
    }

    // MARK: - Load sessions that existed before app launch

    private func loadExisting() {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: sessionsDir,
            includingPropertiesForKeys: nil
        ) else { return }

        var loaded: [ClaudeSession] = []
        for url in items where url.pathExtension == "json" {
            guard
                let data = try? Data(contentsOf: url),
                let file = try? JSONDecoder().decode(SessionFile.self, from: data),
                isAlive(Int32(file.pid), startedAt: Date(timeIntervalSince1970: file.startedAt / 1000))
            else { continue }

            let session = ClaudeSession(from: file)
            activeSessions[session.id] = session
            loaded.append(session)
        }

        let snapshot = Array(activeSessions.values)
        Task { @MainActor in
            AppState.shared.updateSessions(snapshot)
        }
    }

    // MARK: - FSEvents

    private func startFSEvents() {
        let path = sessionsDir.path as CFString
        let paths = [path] as CFArray
        let interval: CFTimeInterval = 0.5

        let ctx = Unmanaged.passRetained(self).toOpaque()

        var context = FSEventStreamContext(
            version: 0,
            info: ctx,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, _, eventPaths, _, _ in
                let monitor = Unmanaged<SessionMonitor>.fromOpaque(info!).takeUnretainedValue()
                Task { await monitor.refreshSessions() }
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            interval,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )

        guard let stream else { return }
        eventStream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    // MARK: - Refresh on filesystem change

    private func refreshSessions() {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: sessionsDir,
            includingPropertiesForKeys: nil
        ) else { return }

        let currentFiles = Set(
            items.filter { $0.pathExtension == "json" }
                 .compactMap { url -> String? in
                     guard
                         let data = try? Data(contentsOf: url),
                         let file = try? JSONDecoder().decode(SessionFile.self, from: data)
                     else { return nil }
                     return file.sessionId
                 }
        )

        // Remove sessions whose files disappeared
        for (id, _) in activeSessions where !currentFiles.contains(id) {
            markFinished(id: id)
        }

        // Add new sessions
        for url in items where url.pathExtension == "json" {
            guard
                let data = try? Data(contentsOf: url),
                let file = try? JSONDecoder().decode(SessionFile.self, from: data),
                activeSessions[file.sessionId] == nil,
                isAlive(Int32(file.pid), startedAt: Date(timeIntervalSince1970: file.startedAt / 1000))
            else { continue }

            let session = ClaudeSession(from: file)
            activeSessions[session.id] = session
        }

        publish()
    }

    // MARK: - Public API for PermissionServer

    func markWaiting(sessionId: String, requestId: String) {
        activeSessions[sessionId]?.state = .waitingForPermission(requestId: requestId)
        publish()
    }

    func markActive(sessionId: String) {
        guard activeSessions[sessionId] != nil else { return }
        activeSessions[sessionId]?.state = .active
        activeSessions[sessionId]?.lastActivityAt = Date()
        publish()
        scheduleIdleTimer(for: sessionId)
    }

    // MARK: - Idle detection

    private func scheduleIdleTimer(for sessionId: String) {
        idleTimers[sessionId]?.cancel()
        idleTimers[sessionId] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            await self?.setIdle(sessionId: sessionId)
        }
    }

    private func setIdle(sessionId: String) {
        guard case .active = activeSessions[sessionId]?.state else { return }
        activeSessions[sessionId]?.state = .idle
        publish()
    }

    // MARK: - Helpers

    private func markFinished(id: String) {
        idleTimers[id]?.cancel()
        idleTimers.removeValue(forKey: id)
        activeSessions[id]?.state = .finished
        // Auto-remove finished sessions after 5s
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            await self?.removeSession(id: id)
        }
    }

    private func removeSession(id: String) {
        activeSessions.removeValue(forKey: id)
        publish()
    }

    private func publish() {
        let snapshot = Array(activeSessions.values)
        Task { @MainActor in
            AppState.shared.updateSessions(snapshot)
        }
    }

    private func isAlive(_ pid: Int32, startedAt: Date? = nil) -> Bool {
        guard kill(pid, 0) == 0 || errno == EPERM else { return false }
        guard let expected = startedAt else { return true }

        // Guard against PID reuse: compare kernel process start time with session file timestamp
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return true }

        let procStartSec = Double(info.kp_proc.p_starttime.tv_sec)
        guard procStartSec > 0 else { return true }
        // A reused PID has a start time AFTER the session file was written.
        // Real sessions always start before or around when the file is created.
        return procStartSec <= expected.timeIntervalSince1970 + 5
    }
}
