import Foundation
import CoreServices

actor SessionMonitor {
    static let shared = SessionMonitor()

    private let claudeDir:    URL
    private let sessionsDir:  URL
    private let projectsDir:  URL
    private var activeSessions: [String: ClaudeSession] = [:]
    private var eventStream: FSEventStreamRef?
    private var idleTimers: [String: Task<Void, Never>] = [:]
    private var livenessTimer: Task<Void, Never>?

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        claudeDir   = home.appendingPathComponent(".claude")
        sessionsDir = home.appendingPathComponent(".claude/sessions")
        projectsDir = home.appendingPathComponent(".claude/projects")
    }

    // MARK: - Start

    func start() async {
        loadExisting()
        startFSEvents()
        startLivenessTimer()
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

    // MARK: - FSEvents (watch entire ~/.claude/ to catch both session files and transcripts)

    private func startFSEvents() {
        let path = claudeDir.path as CFString
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
                guard let info else { return }
                let cfArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
                // CFArray of CFString bridges cleanly to [String] via toll-free bridging
                let paths = cfArray as! [String]
                let monitor = Unmanaged<SessionMonitor>.fromOpaque(info).takeUnretainedValue()
                Task { await monitor.handleFSEvents(paths: paths) }
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

    // MARK: - Dispatch FSEvents by directory

    private func handleFSEvents(paths: [String]) {
        let sessionsPfx = sessionsDir.path
        let projectsPfx = projectsDir.path

        var needsSessionRefresh = false
        for path in paths {
            if path.hasPrefix(sessionsPfx) {
                needsSessionRefresh = true
            } else if path.hasPrefix(projectsPfx) {
                markActiveForProjectPath(path)
            }
        }
        if needsSessionRefresh { refreshSessions() }
    }

    // MARK: - Transcript activity → mark session active

    private func markActiveForProjectPath(_ path: String) {
        // Path: ~/.claude/projects/{encodedCwd}/...
        let prefix = projectsDir.path + "/"
        guard path.hasPrefix(prefix) else { return }
        let rest = String(path.dropFirst(prefix.count))
        guard let encodedDir = rest.components(separatedBy: "/").first, !encodedDir.isEmpty else { return }

        for (id, session) in activeSessions {
            if case .finished = session.state { continue }
            if case .waitingForPermission = session.state { continue }

            // Encode cwd the same way Claude Code does: replace "/" with "-"
            let encoded = "-" + String(session.cwd.dropFirst())
                .replacingOccurrences(of: "/", with: "-")

            if encodedDir == encoded {
                markActive(sessionId: id)
                return
            }
        }
    }

    // MARK: - Refresh on session file change

    private func refreshSessions() {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: sessionsDir,
            includingPropertiesForKeys: nil
        ) else { return }

        // Build map sessionId → file so we can check PID liveness per-session
        var fileMap: [String: SessionFile] = [:]
        for url in items where url.pathExtension == "json" {
            guard
                let data = try? Data(contentsOf: url),
                let file = try? JSONDecoder().decode(SessionFile.self, from: data)
            else { continue }
            fileMap[file.sessionId] = file
        }

        // Finish sessions whose file is gone OR whose PID died
        for (id, _) in activeSessions {
            if let file = fileMap[id] {
                if !isAlive(Int32(file.pid), startedAt: Date(timeIntervalSince1970: file.startedAt / 1000)) {
                    markFinished(id: id)
                }
            } else {
                markFinished(id: id)
            }
        }

        // Add new live sessions
        for (sessionId, file) in fileMap {
            guard
                activeSessions[sessionId] == nil,
                isAlive(Int32(file.pid), startedAt: Date(timeIntervalSince1970: file.startedAt / 1000))
            else { continue }
            let session = ClaudeSession(from: file)
            activeSessions[session.id] = session
        }

        publish()
    }

    // MARK: - Periodic liveness check (catches dead sessions with no FSEvent)

    private func startLivenessTimer() {
        livenessTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                await self?.refreshSessions()
            }
        }
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
            // 120s: long enough to cover pauses between tool uses during active work
            try? await Task.sleep(for: .seconds(120))
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

        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return true }

        let procStartSec = Double(info.kp_proc.p_starttime.tv_sec)
        guard procStartSec > 0 else { return true }
        return procStartSec <= expected.timeIntervalSince1970 + 5
    }
}
