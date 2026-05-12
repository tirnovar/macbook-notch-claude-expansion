import SwiftUI

struct SessionBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.claudePurple)

            Divider()
                .frame(height: 14)
                .overlay(Color.white.opacity(0.2))

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

            if let name = appState.sessions.first(where: { !$0.isTerminated })?.displayName {
                Divider()
                    .frame(height: 14)
                    .overlay(Color.white.opacity(0.2))
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        // Content sits in the left visible zone (left of hardware camera).
        // Left-aligned so it avoids the center camera zone naturally.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            // Flat top (flush with hardware notch bottom), rounded bottom corners
            UnevenRoundedRectangle(
                topLeadingRadius: 8,
                bottomLeadingRadius: 14,
                bottomTrailingRadius: 14,
                topTrailingRadius: 8,
                style: .continuous
            )
            .fill(Color.notchBG)
        )
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
