import Foundation

/// OpenRouter pay-as-you-go credits (used by OpenClaw's openrouter:default profile).
/// Key comes from the OPENROUTER_KEY env var, or parsed from ~/.zshenv when the app
/// is launched from Finder (no shell environment).
struct OpenRouterProvider: UsageProvider {
    let key = "openrouter"
    let displayName = "OpenRouter"
    let shortCode = "OR"

    private static let creditsURL = URL(string: "https://openrouter.ai/api/v1/credits")!

    func isConfigured() -> Bool {
        Self.apiKey() != nil
    }

    func fetch() async -> ProviderStatus {
        guard let apiKey = Self.apiKey() else {
            return status(windows: [], subtitle: nil, error: "OPENROUTER_KEY not found")
        }
        var request = URLRequest(url: Self.creditsURL, timeoutInterval: 15)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let payload = json["data"] as? [String: Any],
                  let total = (payload["total_credits"] as? NSNumber)?.doubleValue,
                  let used = (payload["total_usage"] as? NSNumber)?.doubleValue else {
                return status(windows: [], subtitle: nil, error: "HTTP \(code) from credits endpoint")
            }
            let percent = total > 0 ? used / total * 100 : 0
            let window = RateWindow(label: "Credits", usedPercent: percent, resetsAt: nil)
            let subtitle = String(format: "$%.2f of $%.2f left", total - used, total)
            return status(windows: [window], subtitle: subtitle, error: nil)
        } catch {
            return status(windows: [], subtitle: nil, error: error.localizedDescription)
        }
    }

    private func status(windows: [RateWindow], subtitle: String?, error: String?) -> ProviderStatus {
        ProviderStatus(key: key, displayName: displayName, shortCode: shortCode,
                       subtitle: subtitle, windows: windows, error: error, fetchedAt: Date())
    }

    private static func apiKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["OPENROUTER_KEY"], !env.isEmpty {
            return env
        }
        guard let text = try? String(contentsOf: Util.home.appendingPathComponent(".zshenv"), encoding: .utf8) else {
            return nil
        }
        let pattern = "export\\s+OPENROUTER_KEY=[\"']?([^\"'\\s#]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
