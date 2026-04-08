import Foundation

/// Reads Claude Code OAuth credentials without triggering Keychain popups.
/// Uses the `security` CLI tool instead of Security framework to avoid auth dialogs.
enum KeychainReader {
    private static let serviceName = "Claude Code-credentials"
    private static let fallbackPath = "~/.claude/.credentials.json"

    struct ClaudeCredentials: Sendable {
        let subscriptionType: String
        let rateLimitTier: String
        let accessToken: String
        let expiresAt: Date?
    }

    /// Read credentials via `security` CLI (no popup), then fallback file.
    static func readCredentials() -> ClaudeCredentials? {
        if let creds = readViaSecurityCLI() {
            return creds
        }
        if let creds = readFromFile() {
            return creds
        }
        NSLog("[ClaudeBar] Could not read credentials")
        return nil
    }

    /// Detect the Claude plan from credentials.
    static func detectPlan() -> ClaudePlan? {
        guard let creds = readCredentials() else { return nil }

        let tier = creds.rateLimitTier.lowercased()
        let sub = creds.subscriptionType.lowercased()

        if tier.contains("max_20x") {
            return .maxTwenty
        } else if tier.contains("max_5x") || tier.contains("max5") {
            return .maxFive
        } else if tier.contains("max") {
            return sub == "max" ? .maxTwenty : .maxFive
        } else if tier.contains("pro") || sub == "pro" {
            return .pro
        }

        switch sub {
        case "max": return .maxTwenty
        case "pro": return .pro
        default: return nil
        }
    }

    // MARK: - security CLI (no popup)

    private static func readViaSecurityCLI() -> ClaudeCredentials? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", serviceName, "-w"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("[ClaudeBar] Failed to run security CLI: \(error)")
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        // security CLI outputs the password string followed by newline
        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let jsonData = raw.data(using: .utf8)
        else { return nil }

        return parseCredentialData(jsonData, source: "Keychain(CLI)")
    }

    // MARK: - File fallback

    private static func readFromFile() -> ClaudeCredentials? {
        let path = NSString(string: fallbackPath).expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return parseCredentialData(data, source: "file")
    }

    // MARK: - Parse

    private static func parseCredentialData(_ data: Data, source: String) -> ClaudeCredentials? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any]
        else { return nil }

        let subscriptionType = oauth["subscriptionType"] as? String ?? "unknown"
        let rateLimitTier = oauth["rateLimitTier"] as? String ?? ""
        let accessToken = oauth["accessToken"] as? String ?? ""

        var expiresAt: Date?
        if let expiresMs = oauth["expiresAt"] as? Double {
            expiresAt = Date(timeIntervalSince1970: expiresMs / 1000)
        }

        NSLog("[ClaudeBar] Credentials from \(source): subscription=\(subscriptionType), tier=\(rateLimitTier)")

        return ClaudeCredentials(
            subscriptionType: subscriptionType,
            rateLimitTier: rateLimitTier,
            accessToken: accessToken,
            expiresAt: expiresAt
        )
    }
}
