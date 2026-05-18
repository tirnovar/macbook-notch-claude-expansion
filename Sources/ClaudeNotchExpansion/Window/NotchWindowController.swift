import AppKit
import SwiftUI

final class NotchWindowController: NSObject {
    private var window: NSWindow!

    private let notchW: CGFloat       = 198
    private let barNarrowW: CGFloat   = 320  // bar — 61pt gap each side clears ring+chevron
    private let barW: CGFloat         = 420  // expanded detail panel
    private let detailBelowH: CGFloat = 310
    private let cardW: CGFloat       = 460
    private let cardBelowH: CGFloat  = 224

    private var globalClickMonitor: Any?

    private var screen: NSScreen {
        NSScreen.screens.first { $0.auxiliaryTopLeftArea != nil } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private var notchAreaY: CGFloat      { screen.visibleFrame.maxY }
    private var notchAreaHeight: CGFloat { screen.frame.maxY - screen.visibleFrame.maxY }

    @MainActor func setup() {
        let root = NotchContentView()
            .environmentObject(AppState.shared)
            .environment(\.notchHeight, notchAreaHeight)

        window = NSWindow(
            contentRect: notchFrame(),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = NSWindow.Level(rawValue: Int(NSWindow.Level.statusBar.rawValue) + 1)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: root)
        window.orderFrontRegardless()
    }

    @MainActor func reframe() {
        switch AppState.shared.notchExpansionState {
        case .collapsed:               window.setFrame(notchFrame(), display: true)
        case .horizontalBar:           window.setFrame(barFrame(), display: true)
        case .horizontalBarWithDetail: window.setFrame(barDetailFrame(), display: true)
        case .permissionCard:          window.setFrame(cardFrame(), display: true)
        }
    }

    @MainActor func transition(to state: NotchExpansionState) {
        switch state {
        case .collapsed:
            stopOutsideClickMonitor()
            animate(to: notchFrame())
            window.ignoresMouseEvents = true

        case .horizontalBar:
            stopOutsideClickMonitor()
            animate(to: barFrame(), duration: 0.25, timing: .easeIn)
            window.ignoresMouseEvents = false

        case .horizontalBarWithDetail:
            animate(to: barDetailFrame(), duration: 0.25, timing: .easeOut)
            window.ignoresMouseEvents = false
            startOutsideClickMonitor()

        case .permissionCard:
            stopOutsideClickMonitor()
            animate(to: cardFrame(), duration: 0.25)
            window.ignoresMouseEvents = false
            window.orderFrontRegardless()
        }
    }

    // MARK: - Frame helpers

    private func notchFrame() -> NSRect {
        let s = screen.frame
        return NSRect(x: s.midX - notchW / 2, y: notchAreaY - 1, width: notchW, height: 1)
    }

    private func barFrame() -> NSRect {
        let s = screen.frame
        return NSRect(x: s.midX - barNarrowW / 2, y: notchAreaY, width: barNarrowW, height: notchAreaHeight)
    }

    private func barDetailFrame() -> NSRect {
        let s = screen.frame
        return NSRect(
            x: s.midX - barW / 2,
            y: notchAreaY - detailBelowH,
            width: barW,
            height: notchAreaHeight + detailBelowH
        )
    }

    private func cardFrame() -> NSRect {
        let s = screen.frame
        return NSRect(
            x: s.midX - cardW / 2,
            y: notchAreaY - cardBelowH,
            width: cardW,
            height: notchAreaHeight + cardBelowH
        )
    }

    private func animate(
        to frame: NSRect,
        duration: TimeInterval = 0.25,
        timing: CAMediaTimingFunctionName = .easeOut
    ) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: timing)
            ctx.allowsImplicitAnimation = true
            window.animator().setFrame(frame, display: true)
        }
    }

    // MARK: - Outside-click monitor

    private func startOutsideClickMonitor() {
        guard globalClickMonitor == nil else { return }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            MainActor.assumeIsolated { AppState.shared.closeDetail() }
        }
    }

    private func stopOutsideClickMonitor() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
    }
}
