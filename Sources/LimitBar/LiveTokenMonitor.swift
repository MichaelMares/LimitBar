import Foundation

/// Computes live token throughput by tailing the session transcripts that Claude Code,
/// Codex, and OpenClaw append to in real time. Stateless: every sample re-reads the tails
/// of recently modified files and sums token events from the last 60 seconds.
///
/// Double-counting note: OpenClaw runs Anthropic models by spawning the real `claude` CLI,
/// whose token counts land in ~/.claude/projects (OpenClaw's own transcript logs zeros for
/// those turns), so summing all three sources stays accurate.
final class LiveTokenMonitor: Sendable {
    /// Token events older than this are ignored; the sum is per-minute by construction.
    private static let window: TimeInterval = 60
    /// Only files touched this recently are read at all.
    private static let fileCutoff: TimeInterval = 180
    /// A source counts as "active" if one of its files was written this recently.
    private static let activeCutoff: TimeInterval = 20

    private struct Tally {
        var total: Double = 0
        /// Excludes cache reads — the part that actually burns rate limits.
        var fresh: Double = 0
    }

    func sample() -> LiveActivity {
        let now = Date()
        var tallies: [String: Tally] = [:]
        var active: Set<String> = []

        sampleClaude(now: now, tallies: &tallies, active: &active)
        sampleCodex(now: now, tallies: &tallies, active: &active)
        sampleOpenClaw(now: now, tallies: &tallies, active: &active)

        let sources = Set(tallies.filter { $0.value.total > 0 }.keys).union(active).sorted()
        return LiveActivity(
            tokensPerMinute: tallies.values.reduce(0) { $0 + $1.total },
            freshTokensPerMinute: tallies.values.reduce(0) { $0 + $1.fresh },
            isActive: !active.isEmpty,
            sources: sources
        )
    }

    private static func number(_ dict: [String: Any], _ key: String) -> Double {
        (dict[key] as? NSNumber)?.doubleValue ?? 0
    }

    // MARK: - Claude Code (also carries OpenClaw's Anthropic turns)

    private func sampleClaude(now: Date, tallies: inout [String: Tally], active: inout Set<String>) {
        let root = Util.home.appendingPathComponent(".claude/projects")
        for (url, mtime) in Util.recentFiles(under: root, ext: "jsonl", modifiedWithin: Self.fileCutoff) {
            let source = url.path.contains("-openclaw") ? "openclaw" : "claude"
            if now.timeIntervalSince(mtime) < Self.activeCutoff { active.insert(source) }

            for line in Util.tailLines(of: url) {
                guard let json = Util.jsonLine(line),
                      json["type"] as? String == "assistant",
                      let ts = Util.parseTimestamp(json["timestamp"]),
                      now.timeIntervalSince(ts) < Self.window,
                      let message = json["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any] else { continue }
                let fresh = Self.number(usage, "input_tokens")
                    + Self.number(usage, "output_tokens")
                    + Self.number(usage, "cache_creation_input_tokens")
                tallies[source, default: Tally()].fresh += fresh
                tallies[source, default: Tally()].total += fresh + Self.number(usage, "cache_read_input_tokens")
            }
        }
    }

    // MARK: - Codex

    private func sampleCodex(now: Date, tallies: inout [String: Tally], active: inout Set<String>) {
        let root = Util.home.appendingPathComponent(".codex/sessions")
        for (url, mtime) in Util.recentFiles(under: root, ext: "jsonl", modifiedWithin: Self.fileCutoff) {
            guard url.lastPathComponent.hasPrefix("rollout-") else { continue }
            if now.timeIntervalSince(mtime) < Self.activeCutoff { active.insert("codex") }

            for line in Util.tailLines(of: url) {
                guard let json = Util.jsonLine(line),
                      json["type"] as? String == "event_msg",
                      let payload = json["payload"] as? [String: Any],
                      payload["type"] as? String == "token_count",
                      let ts = Util.parseTimestamp(json["timestamp"]),
                      now.timeIntervalSince(ts) < Self.window,
                      let info = payload["info"] as? [String: Any],
                      let last = info["last_token_usage"] as? [String: Any] else { continue }
                let total = Self.number(last, "total_tokens")
                tallies["codex", default: Tally()].total += total
                tallies["codex", default: Tally()].fresh += total - Self.number(last, "cached_input_tokens")
            }
        }
    }

    // MARK: - OpenClaw (OpenRouter/OpenAI turns; its Anthropic turns log zeros here)

    private func sampleOpenClaw(now: Date, tallies: inout [String: Tally], active: inout Set<String>) {
        let root = Util.home.appendingPathComponent(".openclaw/agents")
        for (url, mtime) in Util.recentFiles(under: root, ext: "jsonl", modifiedWithin: Self.fileCutoff) {
            guard url.deletingLastPathComponent().lastPathComponent == "sessions",
                  !url.lastPathComponent.contains(".trajectory") else { continue }
            if now.timeIntervalSince(mtime) < Self.activeCutoff { active.insert("openclaw") }

            for line in Util.tailLines(of: url) {
                guard let json = Util.jsonLine(line),
                      json["type"] as? String == "message",
                      let message = json["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any],
                      let total = (usage["totalTokens"] as? NSNumber)?.doubleValue,
                      total > 0 else { continue }
                let ts = Util.parseTimestamp(json["timestamp"]) ?? Util.parseTimestamp(message["timestamp"])
                guard let ts, now.timeIntervalSince(ts) < Self.window else { continue }
                tallies["openclaw", default: Tally()].total += total
                tallies["openclaw", default: Tally()].fresh += total - Self.number(usage, "cacheRead")
            }
        }
    }
}
