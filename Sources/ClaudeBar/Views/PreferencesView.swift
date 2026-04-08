import SwiftUI

/// Settings window for configuring ClaudeBar.
struct PreferencesView: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section("Plan") {
                if settings.planAutoDetected {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Auto-detected from Keychain")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("Subscription Plan", selection: $settings.plan) {
                    ForEach(ClaudePlan.allCases, id: \.self) { plan in
                        Text(plan.rawValue).tag(plan)
                    }
                }
                .pickerStyle(.segmented)

                if settings.plan == .custom {
                    HStack {
                        Text("Custom Token Limit")
                        Spacer()
                        TextField("Tokens", value: $settings.customTokenLimit, format: .number)
                            .frame(width: 100)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                HStack {
                    Text("Token Limit")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatTokens(settings.tokenLimit))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Cost Limit")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "$%.2f", settings.costLimit))
                        .foregroundStyle(.secondary)
                }

                if !settings.detectedRateLimitTier.isEmpty {
                    HStack {
                        Text("Rate Limit Tier")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(settings.detectedRateLimitTier)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Refresh") {
                Picker("Refresh Interval", selection: $settings.refreshIntervalSeconds) {
                    Text("10s").tag(10)
                    Text("30s").tag(30)
                    Text("1m").tag(60)
                    Text("2m").tag(120)
                    Text("5m").tag(300)
                }
            }

            Section("Data") {
                HStack {
                    Text("Data Path")
                    Spacer()
                    TextField("Path", text: $settings.dataPath)
                        .frame(width: 200)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section("About") {
                HStack {
                    Text("ClaudeBar")
                        .font(.headline)
                    Spacer()
                    Text("v1.0.0")
                        .foregroundStyle(.secondary)
                }
                Text("macOS menu bar utility for monitoring Claude Code usage statistics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 400)
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000 {
            return String(format: "%dK", count / 1_000)
        }
        return "\(count)"
    }
}
