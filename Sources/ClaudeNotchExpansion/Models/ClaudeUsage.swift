import Foundation

struct ClaudeUsage: Equatable {
    var fiveHourPct: Double
    var fiveHourResetAt: Date?
    var sevenDayPct: Double
    var opusPct: Double
    var costUsed: Double?
    var costLimit: Double?
    var lastUpdated: Date

    var primaryPct: Double { max(fiveHourPct, sevenDayPct) }

    var severity: UsageSeverity {
        switch primaryPct {
        case ..<50:  return .low
        case 50..<80: return .moderate
        default:     return .high
        }
    }
}

enum UsageSeverity {
    case low, moderate, high
}
