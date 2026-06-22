import Foundation
import Combine

/// User-selectable settings, persisted to UserDefaults. Currently just which providers to show.
@MainActor
final class AppSettings: ObservableObject {
    private static let enabledKey = "enabledProviders"
    /// Key gating whether providers may read the macOS Keychain. Read directly by
    /// `ClaudeProvider` (off the main actor), so it lives as a shared constant here.
    nonisolated static let allowKeychainKey = "allowKeychain"

    @Published var enabled: Set<String> {
        didSet { UserDefaults.standard.set(Array(enabled), forKey: Self.enabledKey) }
    }

    /// When false, no provider touches the Keychain — this is the in-app "revoke access" switch.
    /// Defaults to true (read access enabled) on first launch.
    @Published var allowKeychain: Bool {
        didSet { UserDefaults.standard.set(allowKeychain, forKey: Self.allowKeychainKey) }
    }

    init() {
        if let saved = UserDefaults.standard.array(forKey: Self.enabledKey) as? [String] {
            enabled = Set(saved)
        } else {
            enabled = Set(ProviderRegistry.all.filter(\.defaultOn).map(\.key))
        }
        allowKeychain = (UserDefaults.standard.object(forKey: Self.allowKeychainKey) as? Bool) ?? true
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
