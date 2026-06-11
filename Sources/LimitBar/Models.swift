import Foundation

/// One rate-limit window for a provider (e.g. Claude's 5-hour window, Codex's weekly window).
struct RateWindow: Identifiable {
    var id: String { label }
    let label: String
    /// 0...100
    let usedPercent: Double
    let resetsAt: Date?

    var remainingPercent: Double { max(0, 100 - usedPercent) }
}

/// Live token throughput observed from local session transcripts.
struct LiveActivity {
    /// All tokens processed in the last minute, including cache reads.
    let tokensPerMinute: Double
    /// Tokens that actually burn rate limits: input + output + cache writes (no cache reads).
    let freshTokensPerMinute: Double
    /// True if a transcript file was written to in the last few seconds.
    let isActive: Bool
    /// Where the activity came from (e.g. "claude", "codex", "openclaw").
    let sources: [String]

    static let idle = LiveActivity(tokensPerMinute: 0, freshTokensPerMinute: 0, isActive: false, sources: [])
}

/// Snapshot of one provider's current limits.
struct ProviderStatus: Identifiable {
    var id: String { key }
    /// Stable key: "claude", "codex", ...
    let key: String
    let displayName: String
    /// Short code for the menu bar title, e.g. "CL", "CX".
    let shortCode: String
    /// Secondary line under the provider name, e.g. "pro · local data from 19h ago".
    let subtitle: String?
    let windows: [RateWindow]
    let error: String?
    let fetchedAt: Date

    /// The most constrained window drives the headline number.
    var worstWindow: RateWindow? {
        windows.max(by: { $0.usedPercent < $1.usedPercent })
    }
}

protocol UsageProvider: Sendable {
    var key: String { get }
    var displayName: String { get }
    var shortCode: String { get }
    /// True if credentials/config for this provider exist on this machine.
    func isConfigured() -> Bool
    func fetch() async -> ProviderStatus
}
