import Foundation
import SwiftUI
import Combine

@MainActor
final class UsageStore: ObservableObject {
    @Published var statuses: [ProviderStatus] = []
    @Published var live: LiveActivity = .idle
    @Published var isRefreshing = false
    @Published var lastRefresh: Date?

    let settings: AppSettings
    private let liveMonitor: LiveTokenMonitor
    private var refreshTimer: Timer?
    private var liveTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    /// Limits refresh cadence (network). Live activity is sampled much more often (local files).
    private let refreshInterval: TimeInterval = 60
    private let liveInterval: TimeInterval = 3

    init(settings: AppSettings, liveMonitor: LiveTokenMonitor) {
        self.settings = settings
        self.liveMonitor = liveMonitor
        start()
    }

    /// Active = enabled by the user AND actually configured on this machine, in registry order.
    private func activeProviders() -> [any UsageProvider] {
        ProviderRegistry.all
            .filter { settings.isEnabled($0.key) }
            .map { $0.make() }
            .filter { $0.isConfigured() }
    }

    func start() {
        Task { await refresh() }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        liveTimer = Timer.scheduledTimer(withTimeInterval: liveInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.sampleLive() }
        }
        if let t = refreshTimer { RunLoop.main.add(t, forMode: .common) }
        if let t = liveTimer { RunLoop.main.add(t, forMode: .common) }

        // Re-fetch (and prune disabled providers) whenever the selection changes.
        settings.$enabled
            .dropFirst()
            .sink { [weak self] _ in Task { @MainActor in await self?.refresh() } }
            .store(in: &cancellables)

        // Toggling Keychain access changes what Claude can return — refresh immediately.
        settings.$allowKeychain
            .dropFirst()
            .sink { [weak self] _ in Task { @MainActor in await self?.refresh() } }
            .store(in: &cancellables)
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let providers = activeProviders()
        var results: [ProviderStatus] = []
        await withTaskGroup(of: ProviderStatus.self) { group in
            for provider in providers {
                group.addTask { await provider.fetch() }
            }
            for await status in group { results.append(status) }
        }
        // Preserve registry order.
        let order = Dictionary(uniqueKeysWithValues: ProviderRegistry.all.enumerated().map { ($1.key, $0) })
        results.sort { (order[$0.key] ?? 99) < (order[$1.key] ?? 99) }
        statuses = results
        lastRefresh = Date()
    }

    func sampleLive() async {
        let monitor = liveMonitor
        live = await Task.detached(priority: .utility) { monitor.sample() }.value
    }
}
