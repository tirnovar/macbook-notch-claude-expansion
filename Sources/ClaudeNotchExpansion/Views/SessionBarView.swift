import SwiftUI

struct SessionBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var pulseOpacity: CGFloat = 1.0

    private var isActive: Bool { appState.activeCount > 0 || appState.waitingCount > 0 }
    private var totalCount: Int { appState.sessions.filter { !$0.isTerminated }.count }
    private var dotColor: Color {
        appState.waitingCount > 0 ? .claudeAmber : .claudePurple
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left of camera housing: session count + status dot
            HStack(spacing: 5) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
                    .opacity(pulseOpacity)
                Text("\(totalCount)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.leading, 14)

            Spacer()

            // Right of camera housing: Claude icon
            Image(systemName: "wand.and.stars")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.claudePurple)
                .padding(.trailing, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 14,
                bottomTrailingRadius: 14,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(Color.notchBG)
        )
        .task(id: isActive) {
            guard isActive else {
                withAnimation(.easeOut(duration: 0.3)) { pulseOpacity = 1.0 }
                return
            }
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.7)) { pulseOpacity = 0.25 }
                try? await Task.sleep(nanoseconds: 700_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.7)) { pulseOpacity = 1.0 }
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
        }
    }
}
