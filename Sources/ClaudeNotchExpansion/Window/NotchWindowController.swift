import AppKit
import SwiftUI

final class NotchWindowController: NSObject {
    private var window: NSWindow!

    private let notchW: CGFloat    = 198
    private let barW: CGFloat      = 400
    private let barBelowH: CGFloat = 36   // visible content height below the hardware notch
    private let cardW: CGFloat     = 460
    private let cardH: CGFloat     = 260

    private var screen: NSScreen {
        NSScreen.screens.first { $0.auxiliaryTopLeftArea != nil } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private var notchAreaY: CGFloat      { screen.auxiliaryTopLeftArea?.minY ?? screen.frame.maxY - 37 }
    private var notchAreaHeight: CGFloat { screen.auxiliaryTopLeftArea?.height ?? 37 }

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
            window.ignoresMouseEvents = true   // bar is informational — clicks pass through
        case .permissionCard:
            animate(to: cardFrame(), duration: 0.25)
            window.ignoresMouseEvents = false  // card has buttons
        }
    }

    // MARK: - Frame helpers

    private func notchFrame() -> NSRect {
        let s = screen.frame
        return NSRect(x: s.midX - notchW / 2, y: notchAreaY, width: notchW, height: notchAreaHeight)
    }

    private func barFrame() -> NSRect {
        let s = screen.frame
        // Extends notchAreaHeight above + barBelowH below the notch bottom edge
        return NSRect(
            x: s.midX - barW / 2,
            y: notchAreaY - barBelowH,
            width: barW,
            height: notchAreaHeight + barBelowH
        )
    }

    private func cardFrame() -> NSRect {
        let s = screen.frame
        // Top of window == top of screen; extends cardH downward
        return NSRect(
            x: s.midX - cardW / 2,
            y: notchAreaY + notchAreaHeight - cardH,
            width: cardW,
            height: cardH
        )
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
