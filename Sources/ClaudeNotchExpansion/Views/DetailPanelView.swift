import AppKit
import SwiftUI

struct DetailPanelView: View {
    @EnvironmentObject var appState: AppState

    private var activeSessions: [ClaudeSession] {
        appState.sessions.filter { !$0.isTerminated }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if activeSessions.isEmpty {
                Text("No active sessions")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(Array(activeSessions.enumerated()), id: \.element.id) { idx, session in
                    SessionRowView(session: session)
                    if idx < activeSessions.count - 1 {
                        Divider().overlay(Color.white.opacity(0.07))
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 16,
                bottomTrailingRadius: 16,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(Color.notchBG)
        )
        .padding(.horizontal, 4)
    }
}

private struct SessionRowView: View {
    let session: ClaudeSession
    @State private var elapsed: TimeInterval = 0
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    @State private var isHovered = false

    private var stateColor: Color {
        switch session.state {
        case .active:               return .claudeAmber
        case .waitingForPermission: return .claudeAmber
        case .idle:                 return Color.white.opacity(0.35)
        case .finished:             return .claudeGreen
        }
    }

    private var stateLabel: String {
        switch session.state {
        case .active:               return "working"
        case .waitingForPermission: return "waiting"
        case .idle:                 return "idle"
        case .finished:             return "done"
        }
    }

    private var durationLabel: String {
        let secs = Int(elapsed)
        if secs < 3600 { return "\(secs / 60)m" }
        return "\(secs / 3600)h \((secs % 3600) / 60)m"
    }

    private var entrypointIcon: String {
        switch session.entrypoint {
        case "claude-desktop": return "sparkles"
        case "claude-vscode":  return "curlybraces"
        default:               return "terminal"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(stateColor)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: entrypointIcon)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.45))
                    Text(session.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Text(session.cwd)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.38))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(stateLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(stateColor)
                Text(durationLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.38))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(isHovered ? Color.white.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { focusSession(session) }
        .onAppear { elapsed = Date().timeIntervalSince(session.startedAt) }
        .onReceive(timer) { _ in elapsed = Date().timeIntervalSince(session.startedAt) }
    }

    private func focusSession(_ session: ClaudeSession) {
        AppState.shared.closeDetail()

        switch session.entrypoint {
        case "claude-desktop":
            // Activate the Claude Desktop app that owns this session
            if let app = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.anthropic.claudefordesktop"
            ).first {
                app.activate()
            }

        case "claude-vscode":
            // Find a running VS Code / Cursor instance and activate it.
            // We use the session PID's parent to find the right app process.
            let editorBundleIds = [
                "com.microsoft.VSCode",
                "com.todesktop.230313mzl4w4u92",   // Cursor
                "com.vscodium.codium",
                "com.microsoft.VSCodeInsiders",
            ]
            if let app = editorBundleIds.compactMap({
                NSRunningApplication.runningApplications(withBundleIdentifier: $0).first
            }).first {
                app.activate()
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: session.cwd))
            }

        default:
            NSWorkspace.shared.open(URL(fileURLWithPath: session.cwd))
        }
    }
}
