import Foundation
import AppKit

final class HookInstaller {
    static let shared = HookInstaller()

    private let settingsURL: URL
    private let launchAgentURL: URL
    private let bundleID = "cz.databrothers.claude-notch-expansion"

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        settingsURL = home.appendingPathComponent(".claude/settings.json")
        launchAgentURL = home
            .appendingPathComponent("Library/LaunchAgents/\(bundleID).plist")
    }

    func installIfNeeded() throws {
        try installHook()
        installLaunchAgent()
    }

    // MARK: - Hook

    private func installHook() throws {
        guard let hookSrc = Bundle.main.url(forResource: "claude-notch-hook", withExtension: "py") else {
            return // not in bundle (dev mode), skip
        }

        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o755)],
            ofItemAtPath: hookSrc.path
        )

        let hookPath = hookSrc.path

        guard let data = try? Data(contentsOf: settingsURL),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            showAlert("ClaudeNotchExpansion could not read ~/.claude/settings.json")
            return
        }

        // Already pointing at current path — nothing to do
        if isHookInstalled(in: root, hookPath: hookPath) { return }

        // Remove any stale notch hook entries (app was moved or reinstalled)
        let hadStale = hasStaleHook(in: root)
        root = removingStaleHooks(from: root)

        // Add fresh entry for current bundle path
        let hookEntry: [String: Any] = ["type": "command", "command": hookPath, "timeout": 95]
        let hookMatcher: [String: Any] = ["matcher": "", "hooks": [hookEntry]]

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var preToolUse = hooks["PreToolUse"] as? [[String: Any]] ?? []
        preToolUse.append(hookMatcher)
        hooks["PreToolUse"] = preToolUse
        root["hooks"] = hooks

        let updated = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        let tmpURL = settingsURL.deletingLastPathComponent()
            .appendingPathComponent(".settings.json.tmp")
        try updated.write(to: tmpURL, options: .atomic)
        try FileManager.default.replaceItem(
            at: settingsURL, withItemAt: tmpURL,
            backupItemName: nil, options: [], resultingItemURL: nil
        )

        if !hadStale {
            showAlert("ClaudeNotchExpansion registered a PreToolUse hook in ~/.claude/settings.json")
        }
        // Silent update when path just changed (app was moved)
    }

    private func isHookInstalled(in root: [String: Any], hookPath: String) -> Bool {
        guard
            let hooks = root["hooks"] as? [String: Any],
            let preToolUse = hooks["PreToolUse"] as? [[String: Any]]
        else { return false }
        return preToolUse.contains { matcher in
            guard let hooksList = matcher["hooks"] as? [[String: Any]] else { return false }
            return hooksList.contains { $0["command"] as? String == hookPath }
        }
    }

    private func hasStaleHook(in root: [String: Any]) -> Bool {
        guard
            let hooks = root["hooks"] as? [String: Any],
            let preToolUse = hooks["PreToolUse"] as? [[String: Any]]
        else { return false }
        return preToolUse.contains { matcher in
            guard let hooksList = matcher["hooks"] as? [[String: Any]] else { return false }
            return hooksList.contains { entry in
                (entry["command"] as? String ?? "").hasSuffix("/claude-notch-hook.py")
            }
        }
    }

    private func removingStaleHooks(from root: [String: Any]) -> [String: Any] {
        var root = root
        guard var hooks = root["hooks"] as? [String: Any],
              var preToolUse = hooks["PreToolUse"] as? [[String: Any]]
        else { return root }

        preToolUse = preToolUse.filter { matcher in
            guard let hooksList = matcher["hooks"] as? [[String: Any]] else { return true }
            return !hooksList.contains { entry in
                (entry["command"] as? String ?? "").hasSuffix("/claude-notch-hook.py")
            }
        }

        hooks["PreToolUse"] = preToolUse
        root["hooks"] = hooks
        return root
    }

    // MARK: - LaunchAgent

    private func installLaunchAgent() {
        guard let appPath = Bundle.main.bundlePath as String? else { return }

        let plist: [String: Any] = [
            "Label": bundleID,
            "ProgramArguments": ["\(appPath)/Contents/MacOS/ClaudeNotchExpansion"],
            "RunAtLoad": true,
            "KeepAlive": true
        ]

        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0
        ) else { return }

        try? FileManager.default.createDirectory(
            at: launchAgentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Always write — handles both first install and path/config updates
        let existing = try? Data(contentsOf: launchAgentURL)
        guard data != existing else { return }

        try? data.write(to: launchAgentURL, options: .atomic)

        // Reload: bootout (ignore error if not loaded), then bootstrap
        let bootout = Process()
        bootout.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootout.arguments = ["bootout", "gui/\(getuid())/\(bundleID)"]
        try? bootout.run()
        bootout.waitUntilExit()

        let bootstrap = Process()
        bootstrap.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        bootstrap.arguments = ["bootstrap", "gui/\(getuid())", launchAgentURL.path]
        try? bootstrap.run()
    }

    // MARK: - Helpers

    private func showAlert(_ message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Claude Notch"
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
