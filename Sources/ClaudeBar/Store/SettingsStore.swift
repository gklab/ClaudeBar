import Foundation
import Observation

/// Persisted user preferences.
@MainActor
@Observable
final class SettingsStore {
    var plan: ClaudePlan {
        didSet { save() }
    }

    var customTokenLimit: Int {
        didSet { save() }
    }

    var refreshIntervalSeconds: Int {
        didSet { save() }
    }

    /// Data directory path (default: ~/.claude/projects).
    var dataPath: String {
        didSet { save() }
    }

    var tokenLimit: Int {
        plan == .custom ? customTokenLimit : plan.tokenLimit
    }

    var costLimit: Double {
        plan.costLimit
    }

    private static let defaults = UserDefaults.standard
    private static let planKey = "claudebar_plan"
    private static let customTokenLimitKey = "claudebar_custom_token_limit"
    private static let refreshIntervalKey = "claudebar_refresh_interval"
    private static let dataPathKey = "claudebar_data_path"

    /// Detected subscription info from Keychain.
    private(set) var detectedSubscriptionType: String = ""
    private(set) var detectedRateLimitTier: String = ""
    private(set) var planAutoDetected: Bool = false

    init() {
        self.customTokenLimit = Self.defaults.integer(forKey: Self.customTokenLimitKey).nonZero ?? 50_000
        self.refreshIntervalSeconds = Self.defaults.integer(forKey: Self.refreshIntervalKey).nonZero ?? 30
        self.dataPath = Self.defaults.string(forKey: Self.dataPathKey)
            ?? "~/.claude/projects"

        // Try auto-detect from Keychain first, fallback to saved setting
        if let creds = KeychainReader.readCredentials() {
            self.detectedSubscriptionType = creds.subscriptionType
            self.detectedRateLimitTier = creds.rateLimitTier
            NSLog("[ClaudeBar] Keychain: subscriptionType=\(creds.subscriptionType), rateLimitTier=\(creds.rateLimitTier)")
        }

        if let detected = KeychainReader.detectPlan() {
            self.plan = detected
            self.planAutoDetected = true
            NSLog("[ClaudeBar] Auto-detected plan: \(detected.rawValue)")
        } else {
            let planRaw = Self.defaults.string(forKey: Self.planKey) ?? ClaudePlan.pro.rawValue
            self.plan = ClaudePlan(rawValue: planRaw) ?? .pro
        }
    }

    private func save() {
        Self.defaults.set(plan.rawValue, forKey: Self.planKey)
        Self.defaults.set(customTokenLimit, forKey: Self.customTokenLimitKey)
        Self.defaults.set(refreshIntervalSeconds, forKey: Self.refreshIntervalKey)
        Self.defaults.set(dataPath, forKey: Self.dataPathKey)
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
