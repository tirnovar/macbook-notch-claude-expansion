import AppKit
import SwiftUI

final class NotchWindowController: NSObject {
    private var window: NSWindow!

    // Notch dimensions in points (logical coords, not retina pixels)
    private let notchW: CGFloat  = 198
    private let notchH: CGFloat  = 37
    private let barW: CGFloat    = 400
    private let cardW: CGFloat   = 460
    private let cardH: CGFloat   = 260

    private var screen: NSScreen {
        // Prefer the built-in display that has a notch (auxiliaryTopLeftArea non-nil)
        NSScreen.screens.first { $0.auxiliaryTopLeftArea != nil } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    @MainActor func setup() {
        let initial = notchFrame()

        window = NSWindow(
            contentRect: initial,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // Must be above the menu bar (mainMenu = 24, statusBar = 25) to receive clicks in the notch area
        window.level = NSWindow.Level(rawValue: Int(NSWindow.Level.statusBar.rawValue) + 1)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false

        let root = NotchContentView()
            .environmentObject(AppState.shared)
        window.contentView = NSHostingView(rootView: root)
        window.orderFrontRegardless()
    }

    @MainActor func transition(to state: NotchExpansionState) {
        switch state {
        case .collapsed:
            animate(to: notchFrame())
        case .horizontalBar:
            animate(to: barFrame())
        case .permissionCard:
            animate(to: cardFrame(), duration: 0.25)
        }
        // Pass mouse events through when collapsed — no content to click
        window.ignoresMouseEvents = (state == .collapsed)
    }

    // MARK: - Frame helpers

    private func notchFrame() -> NSRect {
        let s = screen.frame
        return NSRect(x: s.midX - notchW / 2, y: s.maxY - notchH, width: notchW, height: notchH)
    }

    private func barFrame() -> NSRect {
        let s = screen.frame
        return NSRect(x: s.midX - barW / 2, y: s.maxY - notchH, width: barW, height: notchH)
    }

    private func cardFrame() -> NSRect {
        let s = screen.frame
        return NSRect(x: s.midX - cardW / 2, y: s.maxY - cardH, width: cardW, height: cardH)
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
