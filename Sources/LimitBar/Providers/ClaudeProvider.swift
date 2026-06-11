import Foundation

/// Fetches Claude subscription rate limits via the Anthropic OAuth usage endpoint,
/// using the Claude Code OAuth token stored in the macOS Keychain.
///
/// LimitBar never refreshes the token itself: Claude Code rotates refresh tokens, and a
/// third-party refresh would invalidate the CLI's session. The CLI (and OpenClaw, which
/// spawns it constantly) keeps the Keychain item fresh; we just re-read it on every fetch.
struct ClaudeProvider: UsageProvider {
    let key = "claude"
    let displayName = "Claude"
    let shortCode = "CL"

    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let keychainService = "Claude Code-credentials"

    func isConfigured() -> Bool {
        // Presence of Claude Code state — checking the Keychain here would prompt too early.
        FileManager.default.fileExists(atPath: Util.home.appendingPathComponent(".claude.json").path)
    }

    func fetch() async -> ProviderStatus {
        guard let creds = Self.readCredentials() else {
            return status(windows: [], subtitle: nil,
                          error: "Keychain item \"\(Self.keychainService)\" missing or access denied")
        }
        if let expires = creds.expiresAt, expires < Date() {
            return status(windows: [], subtitle: creds.subscriptionType,
                          error: "OAuth token expired \(Util.ago(expires)) — run `claude` once to refresh it")
        }

        var request = URLRequest(url: Self.usageURL, timeoutInterval: 15)
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("claude-code/\(Self.claudeCLIVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch code {
            case 200:
                return parse(data: data, subscription: creds.subscriptionType)
            case 401:
                return status(windows: [], subtitle: creds.subscriptionType,
                              error: "401 — token rejected; run `claude` once to refresh it")
            case 429:
                return status(windows: [], subtitle: creds.subscriptionType,
                              error: "429 — usage endpoint rate-limited, will retry")
            default:
                return status(windows: [], subtitle: creds.subscriptionType, error: "HTTP \(code) from usage endpoint")
            }
        } catch {
            return status(windows: [], subtitle: creds.subscriptionType, error: error.localizedDescription)
        }
    }

    private func parse(data: Data, subscription: String?) -> ProviderStatus {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return status(windows: [], subtitle: subscription, error: "Unparseable usage response")
        }
        var windows: [RateWindow] = []
        let mapping: [(String, String)] = [
            ("five_hour", "5h"),
            ("seven_day", "Week"),
            ("seven_day_opus", "Week · Opus"),
            ("seven_day_sonnet", "Week · Sonnet"),
        ]
        for (field, label) in mapping {
            guard let w = json[field] as? [String: Any],
                  let utilization = (w["utilization"] as? NSNumber)?.doubleValue else { continue }
            windows.append(RateWindow(
                label: label,
                usedPercent: utilization,
                resetsAt: Util.parseTimestamp(w["resets_at"])
            ))
        }
        if let extra = json["extra_usage"] as? [String: Any],
           extra["is_enabled"] as? Bool == true,
           let utilization = (extra["utilization"] as? NSNumber)?.doubleValue {
            windows.append(RateWindow(label: "Extra usage", usedPercent: utilization, resetsAt: nil))
        }
        let error = windows.isEmpty ? "Usage response had no rate windows" : nil
        return status(windows: windows, subtitle: subscription, error: error)
    }

    private func status(windows: [RateWindow], subtitle: String?, error: String?) -> ProviderStatus {
        ProviderStatus(key: key, displayName: displayName, shortCode: shortCode,
                       subtitle: subtitle, windows: windows, error: error, fetchedAt: Date())
    }

    // MARK: - Credentials

    private struct Credentials {
        let accessToken: String
        let expiresAt: Date?
        let subscriptionType: String?
    }

    private static func readCredentials() -> Credentials? {
        guard let raw = Keychain.readGenericPassword(service: keychainService),
              let json = Util.jsonLine(raw),
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else { return nil }
        var subtitle = oauth["subscriptionType"] as? String
        if let tier = oauth["rateLimitTier"] as? String, subtitle != nil, !tier.isEmpty, tier != subtitle {
            subtitle = "\(subtitle!) · \(tier)"
        }
        return Credentials(
            accessToken: token,
            expiresAt: Util.parseTimestamp(oauth["expiresAt"]),
            subscriptionType: subtitle
        )
    }

    /// The usage endpoint expects a claude-code User-Agent; read the real CLI version from the
    /// newest local transcript (each line carries a "version" field), with a static fallback.
    private static let claudeCLIVersion: String = {
        let projects = Util.home.appendingPathComponent(".claude/projects")
        let newest = Util.recentFiles(under: projects, ext: "jsonl", modifiedWithin: nil, limit: 1)
        if let url = newest.first?.url {
            for line in Util.tailLines(of: url, maxBytes: 16_384).reversed() {
                if let json = Util.jsonLine(line), let version = json["version"] as? String {
                    return version
                }
            }
        }
        return "2.1.0"
    }()
}
