import SwiftUI

struct DetailPanelView: View {
    @EnvironmentObject var appState: AppState

    private var activeSessions: [ClaudeSession] {
        appState.sessions.filter { !$0.isTerminated }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(activeSessions.enumerated()), id: \.element.id) { idx, session in
                SessionRowView(session: session)
                if idx < activeSessions.count - 1 {
                    Divider().overlay(Color.white.opacity(0.07))
                }
            }

            if activeSessions.isEmpty {
                Text("No active sessions")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
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
        .contentShape(Rectangle())
        .onTapGesture { appState.closeDetail() }
    }
}

private struct SessionRowView: View {
    let session: ClaudeSession
    @State private var elapsed: TimeInterval = 0
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var stateColor: Color {
        switch session.state {
        case .active:                return .claudeAmber
        case .waitingForPermission:  return .claudeAmber
        case .idle:                  return Color.white.opacity(0.35)
        case .finished:              return .claudeGreen
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

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(stateColor)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
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
        .onAppear {
            elapsed = Date().timeIntervalSince(session.startedAt)
        }
        .onReceive(timer) { _ in
            elapsed = Date().timeIntervalSince(session.startedAt)
        }
    }
}
