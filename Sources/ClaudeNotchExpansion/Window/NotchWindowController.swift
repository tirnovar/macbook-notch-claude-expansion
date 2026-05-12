import AppKit
import SwiftUI

final class NotchWindowController: NSObject {
    private var window: NSWindow!

    private let notchW: CGFloat      = 198
    private let barW: CGFloat        = 300
    private let detailW: CGFloat     = 360
    private let detailBelowH: CGFloat = 260
    private let cardW: CGFloat       = 460
    private let cardBelowH: CGFloat  = 224

    private var screen: NSScreen {
        NSScreen.screens.first { $0.auxiliaryTopLeftArea != nil } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    // visibleFrame.maxY is the bottom of the menu-bar/notch region — reliable on all Dock positions.
    // frame.maxY is the physical screen top edge.
    // Their difference is the true hardware notch height.
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

    @MainActor func transition(to state: NotchExpansionState) {
        switch state {
        case .collapsed:
            animate(to: notchFrame())
            window.ignoresMouseEvents = true
        case .horizontalBar:
            animate(to: barFrame())
            window.ignoresMouseEvents = false  // wand icon is clickable
        case .horizontalBarWithDetail:
            animate(to: barDetailFrame(), duration: 0.25)
            window.ignoresMouseEvents = false
        case .permissionCard:
            animate(to: cardFrame(), duration: 0.25)
            window.ignoresMouseEvents = false
        }
    }

    // MARK: - Frame helpers

    private func notchFrame() -> NSRect {
        let s = screen.frame
        return NSRect(x: s.midX - notchW / 2, y: notchAreaY - 1, width: notchW, height: 1)
    }

    private func barFrame() -> NSRect {
        let s = screen.frame
        return NSRect(x: s.midX - barW / 2, y: notchAreaY, width: barW, height: notchAreaHeight)
    }

    private func barDetailFrame() -> NSRect {
        let s = screen.frame
        return NSRect(
            x: s.midX - detailW / 2,
            y: notchAreaY - detailBelowH,
            width: detailW,
            height: notchAreaHeight + detailBelowH
        )
    }

    private func cardFrame() -> NSRect {
        let s = screen.frame
        return NSRect(x: s.midX - cardW / 2, y: notchAreaY - cardBelowH, width: cardW, height: cardBelowH)
    }

    private func animate(to frame: NSRect, duration: TimeInterval = 0.28) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            window.animator().setFrame(frame, display: true)
        }
    }
}
