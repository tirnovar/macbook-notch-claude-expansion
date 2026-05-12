import Foundation

// Mirrors the relevant parts of ~/.claude/settings.json
private struct ClaudePermissions: Codable {
    var allow: [String]
    var deny: [String]
}

private struct ClaudeSettings: Codable {
    var permissions: ClaudePermissions
    // Keep all other keys intact via a passthrough encoder strategy
}

final class PermanentCacheManager {
    static let shared = PermanentCacheManager()

    private let settingsURL: URL

    private init() {
        settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    func addAllowance(toolKey: String) throws {
        let data = try Data(contentsOf: settingsURL)

        // Use JSONSerialization for a round-trip that preserves unknown keys
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var permissions = root["permissions"] as? [String: Any] ?? [:]
        var allow = permissions["allow"] as? [String] ?? []

        guard !allow.contains(toolKey) else { return }
        allow.append(toolKey)
        permissions["allow"] = allow
        root["permissions"] = permissions

        let updated = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])

        // Atomic write via temp file + rename
        let tmpURL = settingsURL.deletingLastPathComponent()
            .appendingPathComponent(".settings.json.tmp")
        try updated.write(to: tmpURL, options: .atomic)
        try FileManager.default.replaceItem(
            at: settingsURL,
            withItemAt: tmpURL,
            backupItemName: nil,
            options: [],
            resultingItemURL: nil
        )
    }

    func isAllowed(toolKey: String) -> Bool {
        guard
            let data = try? Data(contentsOf: settingsURL),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let permissions = root["permissions"] as? [String: Any],
            let allow = permissions["allow"] as? [String]
        else { return false }
        return allow.contains(toolKey)
    }
}
