import Foundation
import Observation
import ServiceManagement

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

    /// Fixed at 30 seconds.
    let refreshIntervalSeconds: Int = 30

    /// Data directory path.
    let dataPath: String = "~/.claude/projects"

    var tokenLimit: Int {
        plan == .custom ? customTokenLimit : plan.tokenLimit
    }

    var costLimit: Double { plan.costLimit }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("[ClaudeBar] Launch at login error: \(error)")
            }
        }
    }

    private static let defaults = UserDefaults.standard
    private static let planKey = "claudebar_plan"
    private static let customTokenLimitKey = "claudebar_custom_token_limit"

    /// Detected subscription info from Keychain.
    private(set) var detectedSubscriptionType: String = ""
    private(set) var detectedRateLimitTier: String = ""
    private(set) var planAutoDetected: Bool = false

    init() {
        self.customTokenLimit = Self.defaults.integer(forKey: Self.customTokenLimitKey).nonZero ?? 50_000

        // Auto-detect plan from Keychain
        if let creds = KeychainReader.readCredentials() {
            self.detectedSubscriptionType = creds.subscriptionType
            self.detectedRateLimitTier = creds.rateLimitTier
        }

        if let detected = KeychainReader.detectPlan() {
            self.plan = detected
            self.planAutoDetected = true
            // Plan auto-detected
        } else {
            let planRaw = Self.defaults.string(forKey: Self.planKey) ?? ClaudePlan.pro.rawValue
            self.plan = ClaudePlan(rawValue: planRaw) ?? .pro
        }
    }

    private func save() {
        Self.defaults.set(plan.rawValue, forKey: Self.planKey)
        Self.defaults.set(customTokenLimit, forKey: Self.customTokenLimitKey)
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
