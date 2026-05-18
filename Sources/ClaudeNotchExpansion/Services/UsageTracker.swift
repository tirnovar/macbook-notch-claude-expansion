import Foundation
import Security
import OSLog

private let logger = Logger(subsystem: "cz.databrothers.claude-notch", category: "UsageTracker")

actor UsageTracker {
    static let shared = UsageTracker()

    private var pollingTask: Task<Void, Never>?

    private init() {}

    func start() {
        pollingTask = Task {
            while !Task.isCancelled {
                await fetch()
                // 15 min — usage doesn't change faster than that
                try? await Task.sleep(for: .seconds(900))
            }
        }
    }

    func fetchNow() async {
        await fetch()
    }

    // MARK: - Fetch cycle

    private func fetch() async {
        guard let token = readAccessToken() else {
            logger.debug("no token found")
            return
        }
        logger.debug("fetching via Messages API…")
        do {
            let usage = try await fetchViaMessagesAPI(token: token)
            logger.debug("5h=\(usage.fiveHourPct)% 7d=\(usage.sevenDayPct)%")
            await MainActor.run { AppState.shared.usage = usage }
        } catch {
            logger.debug("error: \(error)")
        }
    }

    // MARK: - Messages API probe (reads rate-limit utilization headers)

    private func fetchViaMessagesAPI(token: String) async throws -> ClaudeUsage {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)",      forHTTPHeaderField: "Authorization")
        req.setValue("2023-06-01",           forHTTPHeaderField: "anthropic-version")
        req.setValue("oauth-2025-04-20",     forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json",     forHTTPHeaderField: "Content-Type")
        req.setValue("claude-code/1.0",      forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "."]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw UsageError.apiError }

        logger.debug("Messages API HTTP \(http.statusCode)")

        // Rate-limit headers arrive on any response (200 or 4xx)
        let headers = http.allHeaderFields
        logger.debug("headers: \(headers.keys.filter { ($0 as? String)?.contains("ratelimit") == true })")

        let fiveHourPct  = utilization(headers["anthropic-ratelimit-unified-5h-utilization"])
        let sevenDayPct  = utilization(headers["anthropic-ratelimit-unified-7d-utilization"])
        let fiveHourReset = resetDate(headers["anthropic-ratelimit-unified-5h-reset"])
        let sevenDayReset = resetDate(headers["anthropic-ratelimit-unified-7d-reset"])

        _ = sevenDayReset // stored for potential future use

        guard fiveHourPct > 0 || sevenDayPct > 0 else {
            logger.debug("no utilization headers in response — plan may not support it")
            throw UsageError.noData
        }

        return ClaudeUsage(
            fiveHourPct:     fiveHourPct,
            fiveHourResetAt: fiveHourReset,
            sevenDayPct:     sevenDayPct,
            opusPct:         0,
            costUsed:        nil,
            costLimit:       nil,
            lastUpdated:     Date()
        )
    }

    // MARK: - Header parsing

    private func utilization(_ raw: Any?) -> Double {
        guard let str = raw as? String, let d = Double(str) else { return 0 }
        return d > 1 ? d : d * 100   // normalise 0-1 → 0-100 if needed
    }

    private func resetDate(_ raw: Any?) -> Date? {
        guard let str = raw as? String else { return nil }
        return ISO8601DateFormatter().date(from: str)
    }

    // MARK: - Credentials (Keychain primary, file fallback)

    private func readAccessToken() -> String? {
        if let t = readFromKeychain() { return t }

        let home = FileManager.default.homeDirectoryForCurrentUser
        for path in ["~/.claude/.credentials.json", "~/.claude/credentials.json"].map({
            home.appendingPathComponent(String($0.dropFirst(2)))
        }) {
            guard
                let data = try? Data(contentsOf: path),
                let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let oauth = root["claudeAiOauth"] as? [String: Any],
                let token = oauth["accessToken"] as? String, !token.isEmpty
            else { continue }
            return token
        }
        return nil
    }

    private func readFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }
        return token
    }
}

enum UsageError: Error {
    case apiError, noData
}
