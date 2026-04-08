import Foundation

/// Calculates costs based on model-specific token pricing (per 1M tokens).
struct CostCalculator: Sendable {
    struct ModelPricing: Sendable {
        let input: Double
        let output: Double
        let cacheCreation: Double
        let cacheRead: Double
    }

    static let pricing: [String: ModelPricing] = [
        "opus": ModelPricing(input: 15.0, output: 75.0, cacheCreation: 18.75, cacheRead: 1.5),
        "sonnet": ModelPricing(input: 3.0, output: 15.0, cacheCreation: 3.75, cacheRead: 0.3),
        "haiku": ModelPricing(input: 0.25, output: 1.25, cacheCreation: 0.3, cacheRead: 0.03),
    ]

    static func calculateCost(
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheCreationTokens: Int,
        cacheReadTokens: Int
    ) -> Double {
        let p = pricingForModel(model)
        let cost = (Double(inputTokens) * p.input
            + Double(outputTokens) * p.output
            + Double(cacheCreationTokens) * p.cacheCreation
            + Double(cacheReadTokens) * p.cacheRead) / 1_000_000
        return (cost * 1_000_000).rounded() / 1_000_000
    }

    private static func pricingForModel(_ model: String) -> ModelPricing {
        let lower = model.lowercased()
        if lower.contains("opus") {
            return pricing["opus"]!
        } else if lower.contains("haiku") {
            return pricing["haiku"]!
        }
        // Default to sonnet pricing
        return pricing["sonnet"]!
    }
}
