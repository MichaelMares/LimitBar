import Foundation

/// Codex (ChatGPT subscription) rate limits.
///
/// Primary source: GET https://chatgpt.com/backend-api/wham/usage with the OAuth access token
/// from ~/.codex/auth.json. Fallback (offline / expired token): the last `token_count` event in
/// the newest ~/.codex/sessions rollout JSONL — Codex pushes server-side used_percent there on
/// every turn, so it stays valid after the session ends (only its age matters).
struct CodexProvider: UsageProvider {
    let key = "codex"
    let displayName = "Codex"
    let shortCode = "CX"

    private static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private static var authURL: URL { Util.home.appendingPathComponent(".codex/auth.json") }
    private static var sessionsURL: URL { Util.home.appendingPathComponent(".codex/sessions") }

    func isConfigured() -> Bool {
        FileManager.default.fileExists(atPath: Self.authURL.path)
    }

    func fetch() async -> ProviderStatus {
        var remoteError: String?
        if let auth = Self.readAuth() {
            do {
                return try await fetchRemote(auth: auth)
            } catch {
                remoteError = error.localizedDescription
            }
        } else {
            remoteError = "Could not read tokens from ~/.codex/auth.json"
        }

        if let local = fetchFromLocalSessions(note: remoteError) {
            return local
        }
        return status(windows: [], subtitle: nil,
                      error: remoteError ?? "No usable Codex data (no auth, no local sessions)")
    }

    // MARK: - Remote

    private struct CodexError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private func fetchRemote(auth: (accessToken: String, accountId: String?)) async throws -> ProviderStatus {
        var request = URLRequest(url: Self.usageURL, timeoutInterval: 15)
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountId = auth.accountId {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            throw CodexError(message: code == 401 || code == 403
                ? "\(code) — token expired; run `codex` once to refresh it"
                : "HTTP \(code) from wham/usage")
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw CodexError(message: "Unparseable wham/usage response")
        }

        var windows: [RateWindow] = []
        if let rateLimit = json["rate_limit"] as? [String: Any] {
            if let w = Self.window(from: rateLimit["primary_window"], fallbackLabel: "5h") {
                windows.append(w)
            }
            if let w = Self.window(from: rateLimit["secondary_window"], fallbackLabel: "Week") {
                windows.append(w)
            }
        }
        guard !windows.isEmpty else {
            throw CodexError(message: "wham/usage response had no rate windows")
        }

        var subtitle = (json["plan_type"] as? String).map { "plan \($0)" }
        if let credits = json["credits"] as? [String: Any],
           credits["has_credits"] as? Bool == true,
           let balance = credits["balance"] {
            subtitle = [subtitle, "credits \(balance)"].compactMap { $0 }.joined(separator: " · ")
        }
        return status(windows: windows, subtitle: subtitle, error: nil)
    }

    /// Parses both remote shape {used_percent, reset_at, limit_window_seconds}
    /// and local shape {used_percent, resets_at, window_minutes}.
    private static func window(from value: Any?, fallbackLabel: String) -> RateWindow? {
        guard let dict = value as? [String: Any],
              let used = (dict["used_percent"] as? NSNumber)?.doubleValue else { return nil }

        var minutes: Double?
        if let s = (dict["limit_window_seconds"] as? NSNumber)?.doubleValue { minutes = s / 60 }
        if let m = (dict["window_minutes"] as? NSNumber)?.doubleValue { minutes = m }

        let label: String
        switch minutes {
        case .some(let m) where abs(m - 300) < 1: label = "5h"
        case .some(let m) where abs(m - 10080) < 1: label = "Week"
        case .some(let m) where m >= 1440: label = "\(Int((m / 1440).rounded()))d"
        case .some(let m): label = "\(Int((m / 60).rounded()))h"
        case .none: label = fallbackLabel
        }
        let resets = Util.parseTimestamp(dict["reset_at"]) ?? Util.parseTimestamp(dict["resets_at"])
        return RateWindow(label: label, usedPercent: used, resetsAt: resets)
    }

    // MARK: - Local fallback

    private func fetchFromLocalSessions(note: String?) -> ProviderStatus? {
        // Newest few rollout files; the freshest one may predate the first token_count event.
        let files = Util.recentFiles(under: Self.sessionsURL, ext: "jsonl", modifiedWithin: nil, limit: 3)
        for (url, _) in files {
            guard url.lastPathComponent.hasPrefix("rollout-") else { continue }
            let lines = Util.tailLines(of: url, maxBytes: 1_048_576)
            for line in lines.reversed() {
                guard let json = Util.jsonLine(line),
                      json["type"] as? String == "event_msg",
                      let payload = json["payload"] as? [String: Any],
                      payload["type"] as? String == "token_count",
                      let rateLimits = payload["rate_limits"] as? [String: Any] else { continue }

                var windows: [RateWindow] = []
                if let w = Self.window(from: rateLimits["primary"], fallbackLabel: "5h") { windows.append(w) }
                if let w = Self.window(from: rateLimits["secondary"], fallbackLabel: "Week") { windows.append(w) }
                guard !windows.isEmpty else { continue }

                var parts: [String] = []
                if let plan = rateLimits["plan_type"] as? String { parts.append("plan \(plan)") }
                if let ts = Util.parseTimestamp(json["timestamp"]) {
                    parts.append("local data \(Util.ago(ts))")
                }
                if note != nil { parts.append("offline") }
                return status(windows: windows, subtitle: parts.joined(separator: " · "), error: nil)
            }
        }
        return nil
    }

    private func status(windows: [RateWindow], subtitle: String?, error: String?) -> ProviderStatus {
        ProviderStatus(key: key, displayName: displayName, shortCode: shortCode,
                       subtitle: subtitle, windows: windows, error: error, fetchedAt: Date())
    }

    private static func readAuth() -> (accessToken: String, accountId: String?)? {
        guard let data = try? Data(contentsOf: authURL),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String else { return nil }
        return (access, tokens["account_id"] as? String)
    }
}
