import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    var notchController: NotchWindowController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        notchController = NotchWindowController()
        notchController?.setup()

        Task {
            try? HookInstaller.shared.installIfNeeded()
            await SessionMonitor.shared.start()
            await PermissionServer.shared.start()
        }

        AppState.shared.$notchExpansionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.notchController?.transition(to: state)
            }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        try? FileManager.default.removeItem(atPath: PermissionServer.socketPath)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
