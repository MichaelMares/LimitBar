import Foundation
import UserNotifications

/// Posts a local notification when a rate-limit window you'd heavily used rolls over
/// ("your Claude 5h window has refreshed — get back to vibecoding").
///
/// A window has reset when the provider reports a later `resetsAt` than the one we last saw for
/// it. We only notify if the *previous* usage was high enough to have mattered, so you don't get
/// pinged every 5 hours when you were barely using the limit. Baselines persist across launches
/// so a reset isn't re-announced.
@MainActor
final class Notifier {
    static let shared = Notifier()

    /// Only notify if you'd used at least this much of the window before it reset.
    private let notifyThreshold = 80.0

    private struct Baseline: Codable { var reset: Double; var used: Double }
    private var baselines: [String: Baseline] = [:]
    private static let storeKey = "windowResetBaselines"

    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    private init() { load() }

    /// Ask for permission (no-op if already decided). Call when the user enables the feature.
    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Inspect the latest statuses and fire notifications for windows that just rolled over.
    /// `enabled` gates everything; baselines are still maintained so toggling on later doesn't
    /// immediately fire for an old reset.
    func process(statuses: [ProviderStatus], enabled: Bool) {
        for status in statuses {
            for window in status.windows {
                guard let reset = window.resetsAt else { continue }
                let id = "\(status.key)|\(window.label)"
                let newReset = reset.timeIntervalSince1970

                if let prev = baselines[id], newReset > prev.reset + 60 {
                    // The window rolled over (its reset time jumped forward).
                    if enabled, prev.used >= notifyThreshold {
                        notify(provider: status.displayName, window: window.label)
                    }
                }
                baselines[id] = Baseline(reset: newReset, used: window.usedPercent)
            }
        }
        save()
    }

    private func notify(provider: String, window: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(provider): \(window) limit refreshed"
        content.body = "Your \(window) window is back to full — get back to vibecoding!"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "limitbar.reset.\(provider).\(window).\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil // deliver immediately
        )
        center.add(request)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storeKey),
              let decoded = try? JSONDecoder().decode([String: Baseline].self, from: data) else { return }
        baselines = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(baselines) {
            UserDefaults.standard.set(data, forKey: Self.storeKey)
        }
    }
}
