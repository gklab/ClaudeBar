import SwiftUI

struct PreferencesView: View {
    @Bindable var settings: SettingsStore
    @State private var cacheSize: String = "..."
    @State private var showCacheCleared = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            dataTab
                .tabItem { Label("Data", systemImage: "externaldrive") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 420, height: 320)
        .onAppear { updateCacheSize() }
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section {
                LabeledContent("Plan") {
                    HStack(spacing: 6) {
                        Text(settings.plan.rawValue)
                            .fontWeight(.medium)
                        if settings.planAutoDetected {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                                .help("Auto-detected from Claude Code credentials")
                        }
                    }
                }

                if !settings.detectedRateLimitTier.isEmpty {
                    LabeledContent("Rate Limit Tier") {
                        Text(settings.detectedRateLimitTier)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Data

    private var dataTab: some View {
        Form {
            Section("Data Source") {
                LabeledContent("Path") {
                    Text(settings.dataPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Section("Cache") {
                LabeledContent("Disk Cache") {
                    Text(cacheSize)
                        .foregroundStyle(.secondary)
                }

                Button("Clear Cache") {
                    clearCache()
                }
                .help("Removes cached history. Data will be re-scanned on next launch.")

                if showCacheCleared {
                    Text("Cache cleared. Restart to re-scan.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "chart.bar.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("ClaudeBar")
                .font(.title2.weight(.semibold))

            Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
                .foregroundStyle(.secondary)

            Text("macOS menu bar utility for monitoring\nClaude Code usage and costs.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            HStack(spacing: 16) {
                Link("GitHub", destination: URL(string: "https://github.com/gklab/ClaudeBar")!)
                    .font(.caption)
            }
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func updateCacheSize() {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/claudebar-cache.json")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
           let size = attrs[.size] as? Int {
            if size >= 1_000_000 {
                cacheSize = String(format: "%.1f MB", Double(size) / 1_000_000)
            } else {
                cacheSize = String(format: "%d KB", size / 1024)
            }
        } else {
            cacheSize = "None"
        }
    }

    private func clearCache() {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/claudebar-cache.json")
        try? FileManager.default.removeItem(at: path)
        showCacheCleared = true
        updateCacheSize()
    }
}
