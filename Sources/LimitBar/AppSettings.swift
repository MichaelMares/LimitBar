import Foundation
import Combine

/// User-selectable settings, persisted to UserDefaults. Currently just which providers to show.
@MainActor
final class AppSettings: ObservableObject {
    private static let enabledKey = "enabledProviders"

    @Published var enabled: Set<String> {
        didSet { UserDefaults.standard.set(Array(enabled), forKey: Self.enabledKey) }
    }

    init() {
        if let saved = UserDefaults.standard.array(forKey: Self.enabledKey) as? [String] {
            enabled = Set(saved)
        } else {
            enabled = Set(ProviderRegistry.all.filter(\.defaultOn).map(\.key))
        }
    }

    func isEnabled(_ key: String) -> Bool { enabled.contains(key) }

    func setEnabled(_ key: String, _ on: Bool) {
        if on { enabled.insert(key) } else { enabled.remove(key) }
    }

    /// Registry providers that have credentials/config present on this machine.
    var availableProviders: [ProviderInfo] {
        ProviderRegistry.all.filter { $0.isConfigured() }
    }
}
