import Foundation

enum CacheAction: String, Codable {
    case session    // cache for this session only
    case permanent  // write to ~/.claude/settings.json
}

struct PendingPermission: Identifiable, Equatable {
    let id: String              // requestId from hook
    let sessionId: String
    let toolName: String
    let toolInput: [String: AnyCodable]
    let receivedAt: Date
    let timeoutAt: Date

    var toolSummary: String {
        switch toolName {
        case "Bash":
            return (toolInput["command"]?.value as? String ?? "").prefix(120).description
        case "Write", "Edit", "MultiEdit":
            return toolInput["file_path"]?.value as? String ?? ""
        case "Read":
            return toolInput["file_path"]?.value as? String ?? ""
        default:
            return toolName
        }
    }

    var toolIcon: String {
        switch toolName {
        case "Bash":         return "terminal"
        case "Write":        return "doc.badge.plus"
        case "Edit",
             "MultiEdit":    return "pencil.and.list.clipboard"
        case "Read":         return "doc.text.magnifyingglass"
        default:             return "questionmark.circle"
        }
    }

    // Returns a more permissive session-cache key using only the first word of the bash command.
    // e.g. "Bash(cd /Users/foo:*)" → "Bash(cd:*)". nil when key would be identical (single-word cmd).
    var wildcardSessionKey: String? {
        guard toolName == "Bash" else { return nil }
        let cmd = toolInput["command"]?.value as? String ?? ""
        guard let firstWord = cmd.split(separator: " ").first.map(String.init) else { return nil }
        let wildcardKey = "Bash(\(firstWord):*)"
        let standardKey = makeToolKey(name: toolName, input: toolInput)
        return wildcardKey != standardKey ? wildcardKey : nil
    }

    var wildcardFirstWord: String? {
        guard wildcardSessionKey != nil else { return nil }
        let cmd = toolInput["command"]?.value as? String ?? ""
        return cmd.split(separator: " ").first.map(String.init)
    }

    static func == (lhs: PendingPermission, rhs: PendingPermission) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - AnyCodable helper for arbitrary JSON values

struct AnyCodable: Codable, Equatable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self)  { value = v; return }
        if let v = try? container.decode(Int.self)     { value = v; return }
        if let v = try? container.decode(Double.self)  { value = v; return }
        if let v = try? container.decode(Bool.self)    { value = v; return }
        if let v = try? container.decode([String: AnyCodable].self) { value = v; return }
        if let v = try? container.decode([AnyCodable].self)         { value = v; return }
        value = NSNull()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as String:                       try container.encode(v)
        case let v as Int:                          try container.encode(v)
        case let v as Double:                       try container.encode(v)
        case let v as Bool:                         try container.encode(v)
        case let v as [String: AnyCodable]:         try container.encode(v)
        case let v as [AnyCodable]:                 try container.encode(v)
        default:                                    try container.encodeNil()
        }
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        // Equality only matters for basic types used in tool summaries
        switch (lhs.value, rhs.value) {
        case (let l as String, let r as String):   return l == r
        case (let l as Int, let r as Int):         return l == r
        case (let l as Double, let r as Double):   return l == r
        case (let l as Bool, let r as Bool):       return l == r
        default: return false
        }
    }
}
