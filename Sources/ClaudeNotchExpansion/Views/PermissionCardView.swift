import SwiftUI

struct PermissionCardView: View {
    let permission: PendingPermission
    @EnvironmentObject var appState: AppState
    @State private var timeRemaining: Double = 90

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private var session: ClaudeSession? {
        appState.sessions.first { $0.id == permission.sessionId }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                // Session count indicator (mirrors the notch bar pill)
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.claudeAmber)
                        .frame(width: 6, height: 6)
                    Text("\(appState.sessions.filter { !$0.isTerminated }.count)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.claudeAmber)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.claudeAmber.opacity(0.12)))

                Text("Claude needs permission")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                if appState.pendingPermissions.count > 1 {
                    Text("+\(appState.pendingPermissions.count - 1) more")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.claudeAmber)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider().overlay(Color.white.opacity(0.1))

            // Tool info
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: permission.toolIcon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.claudePurple)
                        .frame(width: 20)
                    Text(permission.toolName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    if let session {
                        Text(session.displayName)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                }
                Text(permission.toolSummary)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().overlay(Color.white.opacity(0.1))

            // Action buttons
            HStack(spacing: 8) {
                PermissionButton(label: "Accept Once", style: .primary)   { decide(.allow, cacheAction: nil) }
                PermissionButton(label: "For Session", style: .secondary) { decide(.allow, cacheAction: .session) }
                PermissionButton(label: "Permanently", style: .secondary) { decide(.allow, cacheAction: .permanent) }
                PermissionButton(label: "Decline",     style: .destructive) { decide(.deny, cacheAction: nil) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Timeout progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(timerColor)
                        .frame(width: geo.size.width * CGFloat(timeRemaining / 90))
                        .animation(.linear(duration: 0.5), value: timeRemaining)
                }
            }
            .frame(height: 3)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 18,
                bottomTrailingRadius: 18,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(Color.notchBG)
        )
        .padding(.horizontal, 4)
        .onReceive(timer) { _ in
            let elapsed = Date().timeIntervalSince(permission.receivedAt)
            timeRemaining = max(0, 90 - elapsed)
        }
        .onAppear {
            let elapsed = Date().timeIntervalSince(permission.receivedAt)
            timeRemaining = max(0, 90 - elapsed)
        }
    }

    private var timerColor: Color {
        timeRemaining > 45 ? Color.claudePurple
            : timeRemaining > 20 ? Color.claudeAmber
            : Color.claudeRed
    }

    private func decide(_ decision: PermissionDecision, cacheAction: CacheAction?) {
        Task {
            await PermissionServer.shared.submitDecision(
                requestId: permission.id,
                decision: decision,
                cacheAction: cacheAction
            )
        }
        appState.removePermission(id: permission.id)
        appState.updateSessionState(id: permission.sessionId, state: .active)
    }
}

// MARK: - Button styles

private enum ButtonStyle { case primary, secondary, destructive }

private struct PermissionButton: View {
    let label: String
    let style: ButtonStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(labelColor)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(bgColor))
        }
        .buttonStyle(.plain)
    }

    private var labelColor: Color {
        switch style {
        case .primary:     return .white
        case .secondary:   return Color.white.opacity(0.8)
        case .destructive: return Color.claudeRed
        }
    }

    private var bgColor: Color {
        switch style {
        case .primary:     return Color.claudePurple
        case .secondary:   return Color.white.opacity(0.1)
        case .destructive: return Color.claudeRed.opacity(0.15)
        }
    }
}

enum PermissionDecision: String, Codable {
    case allow
    case deny
}
