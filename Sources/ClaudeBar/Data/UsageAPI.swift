import Foundation

/// Fetches real-time usage data from Claude's OAuth API.
/// Returns the official utilization percentages directly from Anthropic.
struct UsageAPI: Sendable {
    struct UsageData: Sendable {
        struct Window: Sendable {
            let utilization: Double  // 0-100 percent
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

    /// Fetch usage from Claude API using the OAuth access token from Keychain.
    static func fetchUsage() async -> UsageData? {
        guard let creds = KeychainReader.readCredentials(),
              !creds.accessToken.isEmpty
        else {
            NSLog("[ClaudeBar] No access token for API")
            return nil
        }

        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1

            guard status == 200 else {
                NSLog("[ClaudeBar] API status: \(status)")
                return nil
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            return parseUsageResponse(json)
        } catch {
            NSLog("[ClaudeBar] API error: \(error.localizedDescription)")
            return nil
        }
    }

    private static func parseUsageResponse(_ json: [String: Any]) -> UsageData {
        func parseWindow(_ key: String) -> UsageData.Window? {
            guard let w = json[key] as? [String: Any] else { return nil }
            let util = w["utilization"] as? Double ?? 0
            var resetsAt: Date?
            if let rs = w["resets_at"] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                resetsAt = formatter.date(from: rs)
                if resetsAt == nil {
                    formatter.formatOptions = [.withInternetDateTime]
                    resetsAt = formatter.date(from: rs)
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
}
