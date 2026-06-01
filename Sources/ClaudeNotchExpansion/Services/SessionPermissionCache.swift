import Foundation

actor SessionPermissionCache {
    static let shared = SessionPermissionCache()

    private var cache: [String: Set<String>] = [:]  // sessionId → Set<toolKey>

    private init() {}

    func isAllowed(sessionId: String, toolKey: String) -> Bool {
        guard let keys = cache[sessionId] else { return false }
        return keys.contains { cached in
            cached == toolKey || wildcardMatches(toolKey: toolKey, pattern: cached)
        }
    }

    // "Bash(cd:*)" matches "Bash(cd /path:*)" — prefix must be followed by space, colon, or closing paren
    private func wildcardMatches(toolKey: String, pattern: String) -> Bool {
        guard pattern.hasSuffix(":*)") else { return false }
        let base = String(pattern.dropLast(3))
        guard toolKey.hasPrefix(base) else { return false }
        let after = toolKey.dropFirst(base.count)
        return after.hasPrefix(" ") || after.hasPrefix(":") || after.hasPrefix(")")
    }

    func addAllowance(sessionId: String, toolKey: String) {
        if cache[sessionId] == nil { cache[sessionId] = [] }
        cache[sessionId]!.insert(toolKey)
        persistToDisk(sessionId: sessionId)
    }

    func clearSession(sessionId: String) {
        cache.removeValue(forKey: sessionId)
        let url = URL(fileURLWithPath: "/tmp/claude-notch-session-\(sessionId).json")
        try? FileManager.default.removeItem(at: url)
    }

    // Write to /tmp so the hook script can do a fast cache check without socket round-trip
    private func persistToDisk(sessionId: String) {
        guard let keys = cache[sessionId] else { return }
        let payload = ["allowed_keys": Array(keys)]
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let url = URL(fileURLWithPath: "/tmp/claude-notch-session-\(sessionId).json")
        try? data.write(to: url, options: .atomic)
    }
}
