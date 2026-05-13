import Foundation

enum SessionState: Equatable {
    case active
    case waitingForPermission(requestId: String)
    case idle
    case finished
}

struct ClaudeSession: Identifiable, Equatable {
    let id: String          // sessionId from pid.json
    let pid: Int32
    let cwd: String
    let startedAt: Date
    let version: String
    let entrypoint: String
    var state: SessionState
    var lastActivityAt: Date

    var displayName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }

    var isTerminated: Bool {
        state == .finished
    }

    static func == (lhs: ClaudeSession, rhs: ClaudeSession) -> Bool {
        lhs.id == rhs.id && lhs.state == rhs.state && lhs.lastActivityAt == rhs.lastActivityAt
    }
}

// MARK: - Raw session file from ~/.claude/sessions/{pid}.json

struct SessionFile: Decodable {
    let pid: Int
    let sessionId: String
    let cwd: String
    let startedAt: Double   // unix ms
    let version: String
    let entrypoint: String?
}

extension ClaudeSession {
    init(from file: SessionFile) {
        self.id = file.sessionId
        self.pid = Int32(file.pid)
        self.cwd = file.cwd
        self.startedAt = Date(timeIntervalSince1970: file.startedAt / 1000)
        self.version = file.version
        self.entrypoint = file.entrypoint ?? "claude"
        self.state = .idle
        self.lastActivityAt = Date()
    }
}
