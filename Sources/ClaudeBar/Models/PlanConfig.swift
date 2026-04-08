import Foundation

/// Claude subscription plan configuration.
enum ClaudePlan: String, CaseIterable, Sendable, Codable {
    case pro = "Pro"
    case maxFive = "Max (5x)"
    case maxTwenty = "Max (20x)"
    case custom = "Custom"

    var tokenLimit: Int {
        switch self {
        case .pro: return 19_000
        case .maxFive: return 88_000
        case .maxTwenty: return 220_000
        case .custom: return 50_000 // Default, user can override
        }
    }

    var costLimit: Double {
        switch self {
        case .pro: return 18.0
        case .maxFive: return 35.0
        case .maxTwenty: return 140.0
        case .custom: return 50.0
        }
    }

    /// Session window duration in hours (Claude Code resets every 5 hours).
    static let sessionWindowHours: Int = 5
}
