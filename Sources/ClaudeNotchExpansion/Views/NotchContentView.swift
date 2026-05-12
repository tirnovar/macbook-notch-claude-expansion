import SwiftUI

extension Color {
    static let claudePurple    = Color(red: 0.486, green: 0.231, blue: 0.929) // #7C3AED
    static let claudePurpleDim = Color(red: 0.298, green: 0.114, blue: 0.584) // #4C1D95
    static let claudeAmber     = Color(red: 0.961, green: 0.620, blue: 0.043) // #F59E0B
    static let claudeGreen     = Color(red: 0.063, green: 0.722, blue: 0.506) // #10B981
    static let claudeRed       = Color(red: 0.937, green: 0.267, blue: 0.267) // #EF4444
    static let notchBG         = Color(red: 0.055, green: 0.055, blue: 0.055, opacity: 0.97)
}

// MARK: - Environment key for the hardware notch height

private struct NotchHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 37
}

extension EnvironmentValues {
    var notchHeight: CGFloat {
        get { self[NotchHeightKey.self] }
        set { self[NotchHeightKey.self] = newValue }
    }
}

// MARK: - Root view

struct NotchContentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.notchHeight) var notchHeight

    var body: some View {
        switch appState.notchExpansionState {
        case .collapsed:
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        // Both bar states use the SAME SwiftUI view tree so the bar itself
        // never re-transitions — only the detail panel slides in/out.
        case .horizontalBar, .horizontalBarWithDetail:
            VStack(spacing: 0) {
                SessionBarView()
                    .frame(height: notchHeight)
                if appState.isDetailOpen {
                    DetailPanelView()
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
            }
            .animation(.easeOut(duration: 0.22), value: appState.isDetailOpen)
            .transition(.scale(scale: 0.85, anchor: .top).combined(with: .opacity))

        case .permissionCard(let permission):
            PermissionCardView(permission: permission)
                .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
        }
    }
}
