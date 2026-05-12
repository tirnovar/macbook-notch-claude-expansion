import SwiftUI

struct SessionBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.notchHeight) var notchHeight

    var body: some View {
        VStack(spacing: 0) {
            // Transparent area that sits behind the hardware notch (camera housing)
            Color.clear.frame(height: notchHeight)

            // Pill content rendered below the hardware notch
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.claudePurple)

                Divider()
                    .frame(height: 14)
                    .overlay(Color.white.opacity(0.15))

                HStack(spacing: 6) {
                    if appState.activeCount > 0 {
                        SessionDot(count: appState.activeCount, color: .claudePurple, label: "active")
                    }
                    if appState.waitingCount > 0 {
                        SessionDot(count: appState.waitingCount, color: .claudeAmber, label: "waiting")
                            .symbolEffect(.pulse)
                    }
                    if appState.finishedCount > 0 {
                        SessionDot(count: appState.finishedCount, color: .claudeGreen, label: "done")
                    }
                }

                if !appState.sessions.filter({ !$0.isTerminated }).isEmpty {
                    Divider()
                        .frame(height: 14)
                        .overlay(Color.white.opacity(0.15))

                    Text(appState.sessions.filter({ !$0.isTerminated }).first?.displayName ?? "")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(
                Capsule()
                    .fill(Color.notchBG)
            )
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct SessionDot: View {
    let count: Int
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            if count > 1 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
            }
        }
        .accessibilityLabel("\(count) \(label)")
    }
}
