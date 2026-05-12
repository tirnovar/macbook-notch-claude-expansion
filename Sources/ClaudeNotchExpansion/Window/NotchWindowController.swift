import AppKit
import SwiftUI

final class NotchWindowController: NSObject {
    private var window: NSWindow!

    private let notchW: CGFloat    = 198
    private let barW: CGFloat      = 300  // just enough to show content L/R of camera
    private let cardW: CGFloat     = 460
    private let cardBelowH: CGFloat = 224 // card height below the notch

    private var screen: NSScreen {
        NSScreen.screens.first { $0.auxiliaryTopLeftArea != nil } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private var notchAreaY: CGFloat      { screen.auxiliaryTopLeftArea?.minY ?? screen.frame.maxY - 37 }
    // Full notch height = from auxiliaryTopLeftArea.minY (notch bottom) to screen top.
    // auxiliaryTopLeftArea.height is the safe sub-zone height, which is shorter.
    private var notchAreaHeight: CGFloat { screen.frame.maxY - notchAreaY }

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
            window.ignoresMouseEvents = true   // informational — clicks pass through to menu bar
        case .permissionCard:
            animate(to: cardFrame(), duration: 0.25)
            window.ignoresMouseEvents = false  // has buttons
        }
    }

    // MARK: - Frame helpers

    private func notchFrame() -> NSRect {
        let s = screen.frame
        // Collapsed: tiny 1pt window sitting at the notch bottom edge — practically invisible
        return NSRect(x: s.midX - notchW / 2, y: notchAreaY - 1, width: notchW, height: 1)
    }

    private func barFrame() -> NSRect {
        let s = screen.frame
        // Same height as the hardware notch area; content appears left/right of camera
        return NSRect(x: s.midX - barW / 2, y: notchAreaY, width: barW, height: notchAreaHeight)
    }

    private func cardFrame() -> NSRect {
        let s = screen.frame
        // Starts at the notch bottom, extends cardBelowH downward
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
