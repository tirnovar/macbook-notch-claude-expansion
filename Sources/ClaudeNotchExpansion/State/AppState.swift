import Foundation
import Combine

enum NotchExpansionState: Equatable {
    case collapsed
    case horizontalBar
    case permissionCard(PendingPermission)

    static func == (lhs: NotchExpansionState, rhs: NotchExpansionState) -> Bool {
        switch (lhs, rhs) {
        case (.collapsed, .collapsed):             return true
        case (.horizontalBar, .horizontalBar):     return true
        case (.permissionCard(let l), .permissionCard(let r)): return l == r
        default: return false
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var sessions: [ClaudeSession] = []
    @Published var pendingPermissions: [PendingPermission] = []
    @Published var notchExpansionState: NotchExpansionState = .collapsed

    private init() {}

    // MARK: - Session updates

    func updateSessions(_ updated: [ClaudeSession]) {
        sessions = updated
        recalcState()
    }

    func updateSessionState(id: String, state: SessionState) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].state = state
        sessions[idx].lastActivityAt = Date()
        recalcState()
    }

    // MARK: - Permission updates

    func addPermission(_ permission: PendingPermission) {
        pendingPermissions.append(permission)
        recalcState()
    }

    func removePermission(id: String) {
        pendingPermissions.removeAll { $0.id == id }
        recalcState()
    }

    // MARK: - Derived state

    var activeCount: Int {
        sessions.filter {
            switch $0.state {
            case .active, .idle: return true
            default: return false
            }
        }.count
    }

    var waitingCount: Int {
        sessions.filter {
            if case .waitingForPermission = $0.state { return true }
            return false
        }.count
    }

    var finishedCount: Int {
        sessions.filter { $0.state == .finished }.count
    }

    // MARK: - State machine

    private func recalcState() {
        if let top = pendingPermissions.first {
            notchExpansionState = .permissionCard(top)
        } else if sessions.contains(where: { !$0.isTerminated }) {
            notchExpansionState = .horizontalBar
        } else {
            notchExpansionState = .collapsed
        }
    }
}
