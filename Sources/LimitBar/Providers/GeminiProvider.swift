import Foundation

/// Gemini CLI (Google Code Assist) free-tier quota via `cloudcode-pa.googleapis.com`.
/// Like the other providers, LimitBar reads the OAuth token read-only and does not refresh it —
/// if it's expired, the chip shows an error until you run `gemini` once.
struct GeminiProvider: UsageProvider {
    let key = "gemini"
    let displayName = "Gemini"
    let shortCode = "GM"

    private static let quotaURL = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")!
    private static var credsURL: URL { Util.home.appendingPathComponent(".gemini/oauth_creds.json") }
    private static var projectsURL: URL { Util.home.appendingPathComponent(".gemini/projects.json") }

    func isConfigured() -> Bool {
        FileManager.default.fileExists(atPath: Self.credsURL.path)
    }

    func fetch() async -> ProviderStatus {
        guard let creds = Self.readCreds() else {
            return status(windows: [], error: "Could not read ~/.gemini/oauth_creds.json")
        }
        if let expiry = creds.expiry, expiry < Date() {
            return status(windows: [], error: "OAuth token expired — run `gemini` once to refresh it")
        }

        var request = URLRequest(url: Self.quotaURL, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let projectId = Self.readProjectId()
        if let projectId { request.setValue(projectId, forHTTPHeaderField: "x-goog-user-project") }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["project": projectId ?? ""])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch code {
            case 200: return parse(data: data)
            case 401, 403: return status(windows: [], error: "\(code) — token rejected; run `gemini` once to refresh it")
            default: return status(windows: [], error: "HTTP \(code) from quota endpoint")
            }
        } catch {
            return status(windows: [], error: error.localizedDescription)
        }
    }

    /// The response carries quota buckets keyed by model; each has remainingFraction + resetTime.
    /// Buckets can appear at the top level or nested, so search recursively and keep the worst few.
    private func parse(data: Data) -> ProviderStatus {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return status(windows: [], error: "Unparseable quota response")
        }
        var buckets: [(label: String, used: Double, resets: Date?)] = []
        Self.collectBuckets(json, into: &buckets)
        guard !buckets.isEmpty else {
            return status(windows: [], error: "Quota response had no usable buckets")
        }
        // Most-constrained first, cap to keep the panel tidy.
        buckets.sort { $0.used > $1.used }
        let windows = buckets.prefix(3).map { RateWindow(label: $0.label, usedPercent: $0.used, resetsAt: $0.resets) }
        return status(windows: Array(windows), error: nil)
    }

    private static func collectBuckets(_ node: Any, into out: inout [(label: String, used: Double, resets: Date?)]) {
        if let dict = node as? [String: Any] {
            if let fraction = (dict["remainingFraction"] as? NSNumber)?.doubleValue {
                let model = (dict["modelId"] as? String) ?? (dict["model"] as? String) ?? "Quota"
                let tokenType = (dict["tokenType"] as? String).map { " \($0.lowercased())" } ?? ""
                out.append((
                    label: shortModel(model) + tokenType,
                    used: max(0, min(100, (1 - fraction) * 100)),
                    resets: Util.parseTimestamp(dict["resetTime"])
                ))
            }
            for value in dict.values { collectBuckets(value, into: &out) }
        } else if let array = node as? [Any] {
            for value in array { collectBuckets(value, into: &out) }
        }
    }

    private static func shortModel(_ id: String) -> String {
        id.replacingOccurrences(of: "-preview", with: "")
            .replacingOccurrences(of: "models/", with: "")
            .replacingOccurrences(of: "gemini-", with: "Gemini ")
    }

    private func status(windows: [RateWindow], error: String?) -> ProviderStatus {
        ProviderStatus(key: key, displayName: displayName, shortCode: shortCode,
                       subtitle: nil, windows: windows, error: error, fetchedAt: Date())
    }

    private static func readCreds() -> (accessToken: String, expiry: Date?)? {
        guard let data = try? Data(contentsOf: credsURL),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let token = json["access_token"] as? String else { return nil }
        return (token, Util.parseTimestamp(json["expiry_date"]))
    }

    private static func readProjectId() -> String? {
        guard let data = try? Data(contentsOf: projectsURL),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        // projects.json maps a path → { ... project id ... }; find the first plausible id string.
        let projects = (json["projects"] as? [String: Any]) ?? json
        for value in projects.values {
            if let id = value as? String, !id.isEmpty { return id }
            if let obj = value as? [String: Any] {
                for v in obj.values where (v as? String)?.isEmpty == false {
                    if let s = v as? String { return s }
                }
            }
        }
        return nil
    }
}
