import Foundation

/// Fetches real-time usage data and profile from Claude's OAuth API.
struct UsageAPI: Sendable {
    struct UsageData: Sendable {
        struct Window: Sendable {
            let utilization: Double
            let resetsAt: Date?
        }
        let fiveHour: Window?
        let sevenDay: Window?
        let sevenDaySonnet: Window?
        let sevenDayOpus: Window?
        let extraUsage: ExtraUsage?
    }

    struct ExtraUsage: Sendable {
        let isEnabled: Bool
        let monthlyLimit: Int
        let usedCredits: Double
        let utilization: Double
    }

    struct ProfileData: Sendable {
        let displayName: String
        let email: String
        let organizationType: String
        let billingType: String
        let rateLimitTier: String
        let subscriptionStatus: String
    }

    // MARK: - Shared

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        return URLSession(configuration: config)
    }

    private static func makeRequest(path: String, token: String) -> URLRequest? {
        guard let url = URL(string: "https://api.anthropic.com\(path)") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("ClaudeBar/1.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        return req
    }

    // MARK: - Usage

    static func fetchUsage() async -> UsageData? {
        guard let creds = KeychainReader.readCredentials(), !creds.accessToken.isEmpty else { return nil }
        guard let request = makeRequest(path: "/api/oauth/usage", token: creds.accessToken) else { return nil }

        let session = makeSession()
        defer { session.invalidateAndCancel() }

        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return parseUsageResponse(json)
        } catch { return nil }
    }

    // MARK: - Profile

    static func fetchProfile() async -> ProfileData? {
        guard let creds = KeychainReader.readCredentials(), !creds.accessToken.isEmpty else { return nil }
        guard let request = makeRequest(path: "/api/oauth/profile", token: creds.accessToken) else { return nil }

        let session = makeSession()
        defer { session.invalidateAndCancel() }

        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return parseProfileResponse(json)
        } catch { return nil }
    }

    // MARK: - Parse

    private static func parseUsageResponse(_ json: [String: Any]) -> UsageData {
        func parseWindow(_ key: String) -> UsageData.Window? {
            guard let w = json[key] as? [String: Any] else { return nil }
            let util = w["utilization"] as? Double ?? 0
            var resetsAt: Date?
            if let rs = w["resets_at"] as? String {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                resetsAt = f.date(from: rs)
                if resetsAt == nil {
                    f.formatOptions = [.withInternetDateTime]
                    resetsAt = f.date(from: rs)
                }
            }
            return UsageData.Window(utilization: util, resetsAt: resetsAt)
        }

        var extraUsage: ExtraUsage?
        if let eu = json["extra_usage"] as? [String: Any] {
            extraUsage = ExtraUsage(
                isEnabled: eu["is_enabled"] as? Bool ?? false,
                monthlyLimit: eu["monthly_limit"] as? Int ?? 0,
                usedCredits: eu["used_credits"] as? Double ?? 0,
                utilization: eu["utilization"] as? Double ?? 0
            )
        }

        return UsageData(
            fiveHour: parseWindow("five_hour"),
            sevenDay: parseWindow("seven_day"),
            sevenDaySonnet: parseWindow("seven_day_sonnet"),
            sevenDayOpus: parseWindow("seven_day_opus"),
            extraUsage: extraUsage
        )
    }

    private static func parseProfileResponse(_ json: [String: Any]) -> ProfileData {
        let account = json["account"] as? [String: Any] ?? [:]
        let org = json["organization"] as? [String: Any] ?? [:]
        return ProfileData(
            displayName: account["display_name"] as? String ?? "",
            email: account["email"] as? String ?? "",
            organizationType: org["organization_type"] as? String ?? "",
            billingType: org["billing_type"] as? String ?? "",
            rateLimitTier: org["rate_limit_tier"] as? String ?? "",
            subscriptionStatus: org["subscription_status"] as? String ?? ""
        )
    }
}
