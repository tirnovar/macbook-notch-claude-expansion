import SwiftUI

struct SessionBarView: View {
    @EnvironmentObject var appState: AppState
    @State private var pulseOpacity: CGFloat = 1.0

    private var isActive: Bool { appState.activeCount > 0 || appState.waitingCount > 0 }
    private var totalCount: Int { appState.sessions.filter { !$0.isTerminated }.count }

    var body: some View {
        HStack(spacing: 0) {
            // Left of camera: session count + amber status dot
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.claudeAmber)
                    .frame(width: 7, height: 7)
                    .opacity(pulseOpacity)
                Text("\(totalCount)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.leading, 14)

            Spacer()

            // Right of camera: expand/collapse chevron
            Image(systemName: appState.isDetailOpen ? "chevron.up" : "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(appState.isDetailOpen ? Color.white.opacity(0.9) : Color.claudeAmber)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle().inset(by: -8))
                .onTapGesture { appState.toggleDetail() }
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
