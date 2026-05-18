import SwiftUI

// MARK: - Compact usage ring

private struct UsageRingView: View {
    let pct: Double

    private var ringColor: Color {
        switch pct {
        case ..<50:   return .claudeGreen
        case 50..<80: return .claudeAmber
        default:      return .claudeRed
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 2)
            Circle()
                .trim(from: 0, to: CGFloat(min(pct / 100, 1)))
                .stroke(ringColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: pct)
        }
        .frame(width: 13, height: 13)
    }
}

// MARK: - Pulsing dot (isolated so its @State never re-renders the parent)

private struct PulsingDot: View {
    let color: Color
    let isActive: Bool

    @State private var opacity: CGFloat = 1.0

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .opacity(opacity)
            .task(id: isActive) {
                guard isActive else {
                    withAnimation(.easeOut(duration: 0.3)) { opacity = 1.0 }
                    return
                }
                while !Task.isCancelled {
                    withAnimation(.easeInOut(duration: 0.7)) { opacity = 0.25 }
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.7)) { opacity = 1.0 }
                    try? await Task.sleep(nanoseconds: 700_000_000)
                }
            }
    }
}

// MARK: - Session bar

struct SessionBarView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("permissionTimeoutAction") private var timeoutAction: String = "wait"

    private var isActive: Bool { appState.activeCount > 0 || appState.waitingCount > 0 }
    private var totalCount: Int { appState.sessions.filter { !$0.isTerminated }.count }
    private var dotColor: Color {
        if appState.waitingCount > 0 { return .claudeAmber }
        if appState.activeCount > 0  { return .claudeAmber }
        return .white.opacity(0.35)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left of camera: session count + status dot
            HStack(spacing: 5) {
                PulsingDot(color: dotColor, isActive: isActive)
                Text("\(totalCount)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.leading, 14)

            Spacer()

            // Right of camera: usage ring + expand chevron
            HStack(spacing: 7) {
                if let usage = appState.usage {
                    UsageRingView(pct: usage.primaryPct)
                }
                Image(systemName: appState.isDetailOpen ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(appState.isDetailOpen ? Color.white.opacity(0.9) : Color.claudeAmber)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle().inset(by: -8))
                    .onTapGesture { appState.toggleDetail() }
            }
            .padding(.trailing, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: appState.isDetailOpen ? 0 : 14,
                bottomTrailingRadius: appState.isDetailOpen ? 0 : 14,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(Color.notchBG)
        )
        .contextMenu {
            Picker("On permission timeout", selection: $timeoutAction) {
                Text("Allow after 90 s").tag("allow")
                Text("Deny after 90 s").tag("deny")
                Text("Keep waiting").tag("wait")
            }
            .pickerStyle(.inline)

            Divider()
            Button("Quit Claude Notch") { NSApplication.shared.terminate(nil) }
        }
    }
}
