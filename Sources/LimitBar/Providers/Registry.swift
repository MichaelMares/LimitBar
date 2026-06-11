import AppKit
import SwiftUI

/// Brand colors used both for the menu bar battery fill and the dropdown gauges.
/// The fill color is the provider's identity (Mac-battery style), not a usage traffic light.
enum Brand {
    static func ns(_ key: String) -> NSColor {
        switch key {
        case "claude": return NSColor(srgbRed: 0.91, green: 0.49, blue: 0.26, alpha: 1)   // orange
        case "codex": return NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1)     // white (OpenAI)
        case "openrouter": return NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1) // black
        case "gemini": return NSColor(srgbRed: 0.25, green: 0.52, blue: 0.96, alpha: 1)     // blue
        default: return NSColor.systemGray
        }
    }
    static func swiftUI(_ key: String) -> Color { Color(nsColor: ns(key)) }
}

/// Static description of a provider LimitBar knows how to read.
struct ProviderInfo: Identifiable {
    let key: String
    let displayName: String
    /// Enabled by default in a fresh install?
    let defaultOn: Bool
    let make: () -> any UsageProvider

    var id: String { key }
    var brandColor: Color { Brand.swiftUI(key) }
    func isConfigured() -> Bool { make().isConfigured() }
}

enum ProviderRegistry {
    /// Order here is the display order in the menu bar and dropdown.
    static let all: [ProviderInfo] = [
        ProviderInfo(key: "claude", displayName: "Claude", defaultOn: true) { ClaudeProvider() },
        ProviderInfo(key: "codex", displayName: "Codex", defaultOn: true) { CodexProvider() },
        ProviderInfo(key: "openrouter", displayName: "OpenRouter", defaultOn: true) { OpenRouterProvider() },
        ProviderInfo(key: "gemini", displayName: "Gemini", defaultOn: false) { GeminiProvider() },
    ]

    static func info(for key: String) -> ProviderInfo? { all.first { $0.key == key } }
}
