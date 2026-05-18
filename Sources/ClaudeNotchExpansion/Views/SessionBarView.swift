import SwiftUI

// MARK: - Usage pill (progress fill, identical shape to SessionStatusIndicator)

private struct UsagePillView: View {
    let pct: Double

    private var fillColor: Color {
        switch pct {
        case ..<50:   return .claudeGreen
        case 50..<80: return .claudeAmber
        default:      return .claudeRed
        }
    }

    var body: some View {
        Capsule()
            .fill(LinearGradient(
                stops: [
                    .init(color: fillColor.opacity(0.85), location: 0),
                    .init(color: fillColor.opacity(0.85), location: max(0, CGFloat(pct / 100) - 0.01)),
                    .init(color: Color.white.opacity(0.1), location: CGFloat(pct / 100)),
                    .init(color: Color.white.opacity(0.1), location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            ))
            .frame(width: 22, height: 7)
            .animation(.easeInOut(duration: 0.4), value: pct)
    }
}

// MARK: - Session status pill
// Capsule with a hard gradient stop: leading = running state, trailing = done/idle state.
// Wider than a dot so the split is actually legible.

private struct SessionStatusIndicator: View {
    let sessions: [ClaudeSession]

    @State private var pulseOpacity: CGFloat = 1.0
    @State private var tick = 0

    private let colorTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    // MARK: State classification

    private enum Category { case running, done, idle }

    private func category(_ s: ClaudeSession) -> Category {
        switch s.state {
        case .active, .waitingForPermission: return .running
        case .finished:                      return .done
        case .idle:
            return Date().timeIntervalSince(s.lastActivityAt) < 300 ? .done : .idle
        }
    }

    private var hasRunning: Bool { sessions.contains { category($0) == .running } }
    private var hasDone:    Bool { sessions.contains { category($0) == .done    } }
    private var isSplit:    Bool { hasRunning && sessions.contains { category($0) != .running } }
    private var isActive:   Bool { hasRunning }

    private var solidColor: Color {
        if hasRunning { return .claudeAmber }
        if hasDone    { return .claudeGreen }
        return .white.opacity(0.35)
    }

    // Trailing (right) half: green if any session is "done", grey if all idle
    private var trailingColor: Color { hasDone ? .claudeGreen : .white.opacity(0.35) }

    // MARK: Body

    var body: some View {
        Capsule()
            .fill(fill)
            .frame(width: 22, height: 7)
            .opacity(pulseOpacity)
            .animation(.easeInOut(duration: 0.35), value: isSplit)
            .onReceive(colorTimer) { _ in tick += 1 }
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

    // Hard stop at 0.5 — leading = orange (running), trailing = done/idle
    private var fill: AnyShapeStyle {
        if isSplit {
            AnyShapeStyle(LinearGradient(
                stops: [
                    .init(color: .claudeAmber,  location: 0),
                    .init(color: .claudeAmber,  location: 0.5),
                    .init(color: trailingColor, location: 0.5),
                    .init(color: trailingColor, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            ))
        } else {
            AnyShapeStyle(solidColor)
        }
    }
}

// MARK: - Session bar

struct SessionBarView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("permissionTimeoutAction") private var timeoutAction: String = "wait"

    private var activeSessions: [ClaudeSession] { appState.sessions.filter { !$0.isTerminated } }
    private var totalCount: Int { activeSessions.count }

    var body: some View {
        HStack(spacing: 0) {
            // Left: status pill + session count
            HStack(spacing: 5) {
                SessionStatusIndicator(sessions: activeSessions)
                Text("\(totalCount)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .padding(.leading, 14)

            Spacer()

            // Right: usage % label + usage pill (same inset from edge as left)
            HStack(spacing: 5) {
                if let usage = appState.usage {
                    Text("\(Int(usage.primaryPct.rounded()))%")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.55))
                    UsagePillView(pct: usage.primaryPct)
                }
            }
            .padding(.trailing, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { appState.toggleDetail() }
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
