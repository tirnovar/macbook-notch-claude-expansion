import Foundation

// MARK: - Wire types

struct PermissionRequestMessage: Codable {
    let messageType: String
    let requestId: String
    let sessionId: String
    let pid: Int
    let toolName: String
    let toolInput: [String: AnyCodable]
    let timestamp: Double

    enum CodingKeys: String, CodingKey {
        case messageType = "message_type"
        case requestId   = "request_id"
        case sessionId   = "session_id"
        case pid, toolName = "tool_name", toolInput = "tool_input", timestamp
    }
}

struct PermissionResponseMessage: Codable {
    let messageType: String
    let requestId: String
    let decision: PermissionDecision
    let cacheAction: String?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case messageType = "message_type"
        case requestId   = "request_id"
        case decision
        case cacheAction = "cache_action"
        case reason
    }
}

// MARK: - Server

actor PermissionServer {
    static let shared = PermissionServer()
    static let socketPath = "/tmp/claude-notch-monitor.sock"

    private var pendingContinuations: [String: CheckedContinuation<PermissionResponseMessage, Error>] = [:]
    private var serverTask: Task<Void, Never>?

    private init() {}

    func start() async {
        cleanup()
        serverTask = Task { await runServer() }
    }

    private func cleanup() {
        try? FileManager.default.removeItem(atPath: Self.socketPath)
    }

    // MARK: - TCP-style Unix socket server

    private func runServer() async {
        let serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else { return }
        defer { close(serverFD) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = Self.socketPath
        withUnsafeMutablePointer(to: &addr.sun_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: 108) { ptr in
                _ = strncpy(ptr, path, 107)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else { return }
        guard listen(serverFD, 32) == 0 else { return }

        while !Task.isCancelled {
            let clientFD = accept(serverFD, nil, nil)
            guard clientFD >= 0 else { continue }
            Task { await self.handleClient(clientFD: clientFD) }
        }
    }

    private func handleClient(clientFD: Int32) async {
        defer { close(clientFD) }

        do {
            let request = try readFramed(fd: clientFD, as: PermissionRequestMessage.self)

            // Notify session monitor
            await SessionMonitor.shared.markWaiting(
                sessionId: request.sessionId,
                requestId: request.requestId
            )

            // Check session cache first
            let toolKey = makeToolKey(name: request.toolName, input: request.toolInput)
            let cached = await SessionPermissionCache.shared.isAllowed(
                sessionId: request.sessionId,
                toolKey: toolKey
            )

            if cached {
                let response = PermissionResponseMessage(
                    messageType: "permission_response",
                    requestId: request.requestId,
                    decision: .allow,
                    cacheAction: nil,
                    reason: "session cache"
                )
                try writeFramed(fd: clientFD, message: response)
                await SessionMonitor.shared.markActive(sessionId: request.sessionId)
                return
            }

            // Show UI — block until user decides
            let pending = await buildPending(from: request)
            let response = try await withTimeout(seconds: 90) {
                try await withCheckedThrowingContinuation { continuation in
                    Task { await self.registerContinuation(id: request.requestId, cont: continuation) }

                    Task { @MainActor in
                        AppState.shared.addPermission(pending)
                    }
                }
            } fallback: {
                // Timeout → allow (user preference)
                PermissionResponseMessage(
                    messageType: "permission_response",
                    requestId: request.requestId,
                    decision: .allow,
                    cacheAction: nil,
                    reason: "timeout"
                )
            }

            try writeFramed(fd: clientFD, message: response)
            await SessionMonitor.shared.markActive(sessionId: request.sessionId)

        } catch {
            let deny = PermissionResponseMessage(
                messageType: "permission_response",
                requestId: UUID().uuidString,
                decision: .deny,
                cacheAction: nil,
                reason: "internal error"
            )
            try? writeFramed(fd: clientFD, message: deny)
        }
    }

    private func registerContinuation(
        id: String,
        cont: CheckedContinuation<PermissionResponseMessage, Error>
    ) {
        pendingContinuations[id] = cont
    }

    // MARK: - Public: UI calls this

    func submitDecision(
        requestId: String,
        decision: PermissionDecision,
        cacheAction: CacheAction?
    ) async {
        guard let cont = pendingContinuations.removeValue(forKey: requestId) else { return }

        // Handle cache side effects
        if let cacheAction {
            // Retrieve the pending permission to get sessionId + toolKey
            let pending = await MainActor.run {
                AppState.shared.pendingPermissions.first { $0.id == requestId }
            }
            if let pending {
                let toolKey = makeToolKey(name: pending.toolName, input: pending.toolInput)
                switch cacheAction {
                case .session:
                    await SessionPermissionCache.shared.addAllowance(
                        sessionId: pending.sessionId, toolKey: toolKey
                    )
                case .permanent:
                    try? PermanentCacheManager.shared.addAllowance(toolKey: toolKey)
                }
            }
        }

        let response = PermissionResponseMessage(
            messageType: "permission_response",
            requestId: requestId,
            decision: decision,
            cacheAction: cacheAction?.rawValue,
            reason: nil
        )
        cont.resume(returning: response)
    }

    // MARK: - Framing helpers (4-byte big-endian length prefix)

    private func readFramed<T: Decodable>(fd: Int32, as type: T.Type) throws -> T {
        var header = Data(count: 4)
        try header.withUnsafeMutableBytes { ptr in
            var received = 0
            while received < 4 {
                let n = read(fd, ptr.baseAddress!.advanced(by: received), 4 - received)
                guard n > 0 else { throw CocoaError(.fileReadUnknown) }
                received += n
            }
        }
        let length = header.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

        var body = Data(count: Int(length))
        try body.withUnsafeMutableBytes { ptr in
            var received = 0
            while received < Int(length) {
                let n = read(fd, ptr.baseAddress!.advanced(by: received), Int(length) - received)
                guard n > 0 else { throw CocoaError(.fileReadUnknown) }
                received += n
            }
        }
        return try JSONDecoder().decode(T.self, from: body)
    }

    private func writeFramed<T: Encodable>(fd: Int32, message: T) throws {
        let body = try JSONEncoder().encode(message)
        var length = UInt32(body.count).bigEndian
        let header = Data(bytes: &length, count: 4)
        let payload = header + body
        try payload.withUnsafeBytes { ptr in
            var sent = 0
            while sent < payload.count {
                let n = write(fd, ptr.baseAddress!.advanced(by: sent), payload.count - sent)
                guard n > 0 else { throw CocoaError(.fileWriteUnknown) }
                sent += n
            }
        }
    }

    // MARK: - Build PendingPermission from wire request

    private func buildPending(from req: PermissionRequestMessage) async -> PendingPermission {
        PendingPermission(
            id: req.requestId,
            sessionId: req.sessionId,
            toolName: req.toolName,
            toolInput: req.toolInput,
            receivedAt: Date(),
            timeoutAt: Date().addingTimeInterval(90)
        )
    }
}

// MARK: - Tool key normalization

func makeToolKey(name: String, input: [String: AnyCodable]) -> String {
    switch name {
    case "Bash":
        let cmd = input["command"]?.value as? String ?? ""
        let parts = cmd.split(separator: " ", maxSplits: 2)
        let base = parts.prefix(2).joined(separator: " ")
        return "Bash(\(base):*)"
    case "Write", "Edit", "MultiEdit":
        let fp = input["file_path"]?.value as? String ?? ""
        let ext = (fp as NSString).pathExtension
        return ext.isEmpty ? "\(name)(\(fp))" : "\(name)(**/*.\(ext))"
    case "Read":
        let fp = input["file_path"]?.value as? String ?? ""
        return "Read(\(fp))"
    default:
        return name
    }
}

// MARK: - Timeout helper

private func withTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async throws -> T,
    fallback: @escaping @Sendable () -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            return fallback()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
