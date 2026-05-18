import AppKit
import SwiftUI

struct DetailPanelView: View {
    @EnvironmentObject var appState: AppState

    private var activeSessions: [ClaudeSession] {
        appState.sessions.filter { !$0.isTerminated }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
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
            }

            Divider().overlay(Color.white.opacity(0.07))
            if let usage = appState.usage {
                UsageFooterView(usage: usage)
                Divider().overlay(Color.white.opacity(0.07))
            }
            LegendFooterView()
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
    private let timer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()
    @State private var isHovered = false

    private var stateColor: Color {
        switch session.state {
        case .active:               return .claudeAmber
        case .waitingForPermission: return .claudeAmber
        case .idle:
            return Date().timeIntervalSince(session.lastActivityAt) < 300
                ? .claudeGreen
                : Color.white.opacity(0.35)
        case .finished:             return .claudeGreen
        }
    }

    private var stateLabel: String {
        switch session.state {
        case .active:               return "working"
        case .waitingForPermission: return "waiting"
        case .idle:
            return Date().timeIntervalSince(session.lastActivityAt) < 300 ? "done" : "idle"
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

    // Walk the process tree from the session PID upward, find the owning terminal app,
    // and activate it. Falls back to opening a new terminal window if nothing is found.
    private func focusTerminalSession(_ session: ClaudeSession) {
        let terminalBundleIds: Set<String> = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "dev.warp.desktop",
            "com.github.wez.wezterm",
            "net.kovidgoyal.kitty",
            "co.zeit.hyper",
        ]

        var pid = session.pid
        for _ in 0..<10 {
            guard let ppid = parentPID(of: pid), ppid > 1 else { break }
            if let app = NSRunningApplication(processIdentifier: ppid),
               let bundleId = app.bundleIdentifier,
               terminalBundleIds.contains(bundleId) {
                app.activate(options: .activateIgnoringOtherApps)
                return
            }
            pid = ppid
        }
        // Fallback: couldn't find the owning terminal, open new window
        openNewTerminalAt(session.cwd)
    }

    private func parentPID(of pid: Int32) -> Int32? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let ppid = info.kp_eproc.e_ppid
        return ppid > 0 ? ppid : nil
    }

    private func openNewTerminalAt(_ cwd: String) {
        let p = Process()
        p.launchPath = "/usr/bin/open"
        p.arguments = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.googlecode.iterm2"
        ) != nil ? ["-a", "iTerm", cwd] : ["-a", "Terminal", cwd]
        try? p.run()
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
            focusTerminalSession(session)
        }
    }
}

// MARK: - Usage footer

private struct UsageFooterView: View {
    let usage: ClaudeUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("USAGE")
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.25))
                .tracking(0.8)

            UsageBarRow(label: "5h window", pct: usage.fiveHourPct, resetAt: usage.fiveHourResetAt)
            UsageBarRow(label: "7-day", pct: usage.sevenDayPct, resetAt: nil)

            if usage.opusPct > 0 {
                UsageBarRow(label: "Opus 7d", pct: usage.opusPct, resetAt: nil)
            }

            if let used = usage.costUsed, let limit = usage.costLimit {
                HStack(spacing: 4) {
                    Text("Overage")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.5))
                    Spacer()
                    Text("$\(String(format: "%.2f", used)) / $\(String(format: "%.2f", limit))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(used > 0 ? Color.claudeAmber : Color.white.opacity(0.38))
                }
            }

            HStack(spacing: 5) {
                Spacer()
                Text("updated \(usage.lastUpdated.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white.opacity(0.2))
                Button {
                    Task { await UsageTracker.shared.fetchNow() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct UsageBarRow: View {
    let label: String
    let pct: Double
    let resetAt: Date?

    @State private var now = Date()
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var barColor: Color {
        switch pct {
        case ..<50:  return .claudeGreen
        case 50..<80: return .claudeAmber
        default:     return .claudeRed
        }
    }

    private var resetLabel: String? {
        guard let resetAt else { return nil }
        let remaining = resetAt.timeIntervalSince(now)
        guard remaining > 0 else { return nil }
        let mins = Int(remaining / 60)
        if mins < 60 { return "resets \(mins)m" }
        return "resets \(mins / 60)h\((mins % 60) > 0 ? " \(mins % 60)m" : "")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.5))
                Spacer()
                if let reset = resetLabel {
                    Text(reset)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.white.opacity(0.28))
                }
                Text("\(Int(pct.rounded()))%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(barColor)
                    .frame(minWidth: 30, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor.opacity(0.85))
                        .frame(width: geo.size.width * CGFloat(min(pct / 100, 1)), height: 3)
                        .animation(.easeInOut(duration: 0.4), value: pct)
                }
            }
            .frame(height: 3)
        }
        .onReceive(timer) { now = $0 }
    }
}

// MARK: - Legend footer

private struct LegendFooterView: View {
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("Right-click bar for settings")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white.opacity(0.2))
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { isExpanded.toggle() }
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(isExpanded ? Color.white.opacity(0.7) : Color.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            if isExpanded {
                VStack(alignment: .leading, spacing: 5) {
                    LegendGroup(title: "Status indicator") {
                        LegendItem(symbol: "circle.fill",       color: .claudeAmber,              label: "all sessions running")
                        LegendItem(symbol: "circle.fill",       color: .claudeGreen,              label: "done (last activity < 5 min)")
                        LegendItem(symbol: "circle.fill",       color: Color.white.opacity(0.35), label: "idle (no activity > 5 min)")
                        LegendItem(symbol: "rectangle.lefthalf.filled", color: .claudeAmber,      label: "left = running, right = done/idle")
                    }
                    LegendGroup(title: "Icon") {
                        LegendItem(symbol: "terminal",      color: Color.white.opacity(0.45), label: "Claude CLI (terminal)")
                        LegendItem(symbol: "curlybraces",   color: Color.white.opacity(0.45), label: "VS Code / Cursor extension")
                        LegendItem(symbol: "sparkles",      color: Color.white.opacity(0.45), label: "Claude Desktop app")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
    }
}

private struct LegendGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.25))
                .tracking(0.8)
            content()
        }
    }
}

private struct LegendItem: View {
    let symbol: String
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 9))
                .foregroundStyle(color)
                .frame(width: 12)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.5))
        }
    }
}
