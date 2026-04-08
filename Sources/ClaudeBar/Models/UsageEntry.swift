import Foundation

/// Individual usage record parsed from Claude JSONL data.
struct UsageEntry: Sendable {
    let timestamp: Date
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let costUSD: Double
    let model: String
    let messageId: String
    let requestId: String
    let sessionId: String

    /// Tokens that count toward the usage limit (input + output only, cache excluded).
    var billableTokens: Int {
        inputTokens + outputTokens
    }

    /// All tokens including cache (for display purposes).
    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }
}
