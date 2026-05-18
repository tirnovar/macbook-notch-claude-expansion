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

    private init() {}

    static let configPath = "/tmp/claude-notch-config.json"

    func start() async {
        try? FileManager.default.removeItem(atPath: Self.socketPath)
        writeConfig()
        DispatchQueue(label: "notch.socket.accept", qos: .utility).async {
            socketAcceptLoop(server: self)
        }
    }

    // Write hook-readable config so Python can match our timeout setting
    private func writeConfig() {
        let config: [String: Any] = ["response_timeout": Self.timeoutSeconds()]
        guard let data = try? JSONSerialization.data(withJSONObject: config) else { return }
        try? data.write(to: URL(fileURLWithPath: Self.configPath), options: .atomic)
    }

    // MARK: - Called by socket background thread to get a decision

    func processRequest(_ request: PermissionRequestMessage) async -> PermissionResponseMessage {
        defer {
            Task { @MainActor in AppState.shared.removePermission(id: request.requestId) }
        }

        await SessionMonitor.shared.markWaiting(
            sessionId: request.sessionId,
            requestId: request.requestId
        )

        let toolKey = makeToolKey(name: request.toolName, input: request.toolInput)
        let cached = await SessionPermissionCache.shared.isAllowed(
            sessionId: request.sessionId,
            toolKey: toolKey
        )

        if cached {
            await SessionMonitor.shared.markActive(sessionId: request.sessionId)
            return PermissionResponseMessage(
                messageType: "permission_response",
                requestId: request.requestId,
                decision: .allow,
                cacheAction: nil,
                reason: "session cache"
            )
        }

        let pending = PendingPermission(
            id: request.requestId,
            sessionId: request.sessionId,
            toolName: request.toolName,
            toolInput: request.toolInput,
            receivedAt: Date(),
            timeoutAt: Date().addingTimeInterval(90)
        )

        // Show permission card on main thread
        await MainActor.run { AppState.shared.addPermission(pending) }

        // Wait for UI decision — duration and fallback decision are user-configurable
        let response: PermissionResponseMessage
        do {
            let reqId = request.requestId
            response = try await withTimeout(seconds: Self.timeoutSeconds()) {
                try await withCheckedThrowingContinuation { continuation in
                    Task { await self.registerContinuation(id: reqId, cont: continuation) }
                }
            } fallback: {
                PermissionResponseMessage(
                    messageType: "permission_response",
                    requestId: request.requestId,
                    decision: Self.timeoutDecision(),
                    cacheAction: nil,
                    reason: "timeout"
                )
            }
        } catch {
            response = PermissionResponseMessage(
                messageType: "permission_response",
                requestId: request.requestId,
                decision: .deny,
                cacheAction: nil,
                reason: "cancelled"
            )
        }

        await SessionMonitor.shared.markActive(sessionId: request.sessionId)
        return response
    }

    // MARK: - Timeout configuration (reads UserDefaults — safe to call off-actor)

    static func timeoutSeconds() -> Double {
        switch UserDefaults.standard.string(forKey: "permissionTimeoutAction") ?? "wait" {
        case "wait": return 86400   // 24 h — effectively no timeout
        default:     return 90
        }
    }

    static func timeoutDecision() -> PermissionDecision {
        UserDefaults.standard.string(forKey: "permissionTimeoutAction") == "deny" ? .deny : .allow
    }

    private func registerContinuation(
        id: String,
        cont: CheckedContinuation<PermissionResponseMessage, Error>
    ) {
        pendingContinuations[id] = cont
    }

    // MARK: - Called by UI buttons

    func submitDecision(
        requestId: String,
        decision: PermissionDecision,
        cacheAction: CacheAction?,
        sessionId: String,
        toolName: String,
        toolInput: [String: AnyCodable]
    ) async {
        guard let cont = pendingContinuations.removeValue(forKey: requestId) else { return }

        if let cacheAction {
            let toolKey = makeToolKey(name: toolName, input: toolInput)
            switch cacheAction {
            case .session:
                await SessionPermissionCache.shared.addAllowance(
                    sessionId: sessionId, toolKey: toolKey
                )
            case .permanent:
                try? PermanentCacheManager.shared.addAllowance(toolKey: toolKey)
            }
        }

        cont.resume(returning: PermissionResponseMessage(
            messageType: "permission_response",
            requestId: requestId,
            decision: decision,
            cacheAction: cacheAction?.rawValue,
            reason: nil
        ))
    }
}

// MARK: - Socket accept loop (runs on background DispatchQueue, never on actor)

private func socketAcceptLoop(server: PermissionServer) {
    let serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
    guard serverFD >= 0 else { return }
    defer { close(serverFD) }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let path = PermissionServer.socketPath
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
    guard bindResult == 0, listen(serverFD, 32) == 0 else { return }

    while true {
        let clientFD = accept(serverFD, nil, nil)
        guard clientFD >= 0 else { continue }
        DispatchQueue(label: "notch.socket.client", qos: .utility, attributes: .concurrent).async {
            handleConnection(clientFD: clientFD, server: server)
        }
    }
}

// MARK: - Per-connection handler (blocking I/O on background thread)

private func handleConnection(clientFD: Int32, server: PermissionServer) {
    defer { close(clientFD) }

    guard let request = try? readFramed(fd: clientFD, as: PermissionRequestMessage.self) else { return }

    // Bridge async actor decision → synchronous write
    let sema = DispatchSemaphore(value: 0)
    var response: PermissionResponseMessage?

    Task {
        response = await server.processRequest(request)
        sema.signal()
    }

    let socketDeadline: DispatchTime = PermissionServer.timeoutSeconds() > 200
        ? .distantFuture
        : .now() + PermissionServer.timeoutSeconds() + 2
    _ = sema.wait(timeout: socketDeadline)

    if let response, let _ = try? writeFramed(fd: clientFD, message: response) { }
}

// MARK: - Framing helpers (free functions — no actor involvement)

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

@discardableResult
private func writeFramed<T: Encodable>(fd: Int32, message: T) throws -> Bool {
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
    return true
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
