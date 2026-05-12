import AppKit
import SwiftUI

final class NotchWindowController: NSObject {
    private var window: NSWindow!

    private let notchW: CGFloat = 198
    private let barW: CGFloat   = 400
    private let cardW: CGFloat  = 460
    private let cardH: CGFloat  = 260

    private var screen: NSScreen {
        NSScreen.screens.first { $0.auxiliaryTopLeftArea != nil } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    // Reads actual notch/menu-bar height and Y origin from the system.
    // auxiliaryTopLeftArea is the safe zone to the left of the camera housing;
    // its height == menu bar height == notch housing height on notch Macs.
    private var notchAreaY: CGFloat      { screen.auxiliaryTopLeftArea?.minY ?? screen.frame.maxY - 37 }
    private var notchAreaHeight: CGFloat { screen.auxiliaryTopLeftArea?.height ?? 37 }

    @MainActor func setup() {
        window = NSWindow(
            contentRect: notchFrame(),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // Must be above statusBar (25) so the window renders over status items in the notch area.
        window.level = NSWindow.Level(rawValue: Int(NSWindow.Level.statusBar.rawValue) + 1)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
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
            window.ignoresMouseEvents = true
        case .horizontalBar:
            animate(to: barFrame())
            window.ignoresMouseEvents = true   // bar is informational — clicks pass through to menu bar
        case .permissionCard:
            animate(to: cardFrame(), duration: 0.25)
            window.ignoresMouseEvents = false  // card has buttons
        }
    }

    // MARK: - Frame helpers

    private func notchFrame() -> NSRect {
        let s = screen.frame
        let h = notchAreaHeight
        return NSRect(x: s.midX - notchW / 2, y: notchAreaY, width: notchW, height: h)
    }

    private func barFrame() -> NSRect {
        let s = screen.frame
        let h = notchAreaHeight
        return NSRect(x: s.midX - barW / 2, y: notchAreaY, width: barW, height: h)
    }

    private func cardFrame() -> NSRect {
        let s = screen.frame
        return NSRect(x: s.midX - cardW / 2, y: notchAreaY - (cardH - notchAreaHeight), width: cardW, height: cardH)
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
