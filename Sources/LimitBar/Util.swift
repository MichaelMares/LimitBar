import Foundation

enum Util {
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Parses ISO8601 strings (with/without fractional seconds) and epoch numbers (seconds or ms).
    static func parseTimestamp(_ value: Any?) -> Date? {
        switch value {
        case let s as String:
            return isoFractional.date(from: s) ?? isoPlain.date(from: s)
        case let n as NSNumber:
            let d = n.doubleValue
            if d > 1e12 { return Date(timeIntervalSince1970: d / 1000) } // epoch ms
            if d > 1e9 { return Date(timeIntervalSince1970: d) }         // epoch s
            return nil
        default:
            return nil
        }
    }

    /// Reads the last `maxBytes` of a file and returns complete lines.
    static func tailLines(of url: URL, maxBytes: UInt64 = 262_144) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > maxBytes ? size - maxBytes : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd() else { return [] }
        let text = String(decoding: data, as: UTF8.self)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        if offset > 0, !lines.isEmpty { lines.removeFirst() } // first line is likely partial
        return lines
    }

    /// Files with the given extension under `root` (recursive), newest first.
    /// `modifiedWithin` limits results to recently touched files; pass nil for no cutoff.
    static func recentFiles(under root: URL, ext: String, modifiedWithin: TimeInterval?, limit: Int = 50) -> [(url: URL, mtime: Date)] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let cutoff = modifiedWithin.map { Date().addingTimeInterval(-$0) }
        var results: [(URL, Date)] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == ext,
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let mtime = values.contentModificationDate else { continue }
            if let cutoff, mtime < cutoff { continue }
            results.append((url, mtime))
        }
        results.sort { $0.1 > $1.1 }
        if results.count > limit { results.removeLast(results.count - limit) }
        return results
    }

    static func jsonLine(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func formatTokens(_ count: Double) -> String {
        switch count {
        case ..<1_000: return String(Int(count))
        case ..<1_000_000: return String(format: "%.1fk", count / 1_000)
        default: return String(format: "%.2fM", count / 1_000_000)
        }
    }

    /// Short relative description like "3h ago".
    static func ago(_ date: Date) -> String {
        let s = -date.timeIntervalSinceNow
        if s < 90 { return "\(Int(s))s ago" }
        if s < 5400 { return "\(Int(s / 60))m ago" }
        if s < 129_600 { return "\(Int(s / 3600))h ago" }
        return "\(Int(s / 86_400))d ago"
    }

    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
}
