import Foundation
import SwiftUI

@MainActor
final class UsageStore: ObservableObject {
    @Published var statuses: [ProviderStatus] = []
    @Published var live: LiveActivity = .idle
    @Published var isRefreshing = false
    @Published var lastRefresh: Date?

    private let providers: [any UsageProvider]
    private let liveMonitor: LiveTokenMonitor
    private var refreshTimer: Timer?
    private var liveTimer: Timer?

    /// Limits refresh cadence (network). Live activity is sampled much more often (local files).
    private let refreshInterval: TimeInterval = 60
    private let liveInterval: TimeInterval = 3

    init(providers: [any UsageProvider], liveMonitor: LiveTokenMonitor) {
        self.providers = providers.filter { $0.isConfigured() }
        self.liveMonitor = liveMonitor
        start()
    }

    func start() {
        Task { await refresh() }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        liveTimer = Timer.scheduledTimer(withTimeInterval: liveInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.sampleLive() }
        }
        // Keep timers firing while the MenuBarExtra menu is open.
        if let t = refreshTimer { RunLoop.main.add(t, forMode: .common) }
        if let t = liveTimer { RunLoop.main.add(t, forMode: .common) }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var results: [ProviderStatus] = []
        await withTaskGroup(of: ProviderStatus.self) { group in
            for provider in providers {
                group.addTask { await provider.fetch() }
            }
            for await status in group { results.append(status) }
        }
        // Stable order: claude first, then codex, then the rest alphabetically.
        let order = ["claude": 0, "codex": 1, "openrouter": 2]
        results.sort { (order[$0.key] ?? 99, $0.key) < (order[$1.key] ?? 99, $1.key) }
        statuses = results
        lastRefresh = Date()
    }

    func sampleLive() async {
        let monitor = liveMonitor
        live = await Task.detached(priority: .utility) { monitor.sample() }.value
    }

    /// Compact menu bar title, e.g. "CL 42% CX 17%" plus a bolt when tokens are flowing.
    var menuBarTitle: String {
        var parts: [String] = []
        for status in statuses {
            if let worst = status.worstWindow {
                parts.append("\(status.shortCode) \(Int(worst.usedPercent.rounded()))%")
            } else if status.error != nil {
                parts.append("\(status.shortCode) !")
            }
        }
        if parts.isEmpty { parts.append("…") }
        if live.isActive { parts.append("⚡︎") }
        return parts.joined(separator: "  ")
    }
}
