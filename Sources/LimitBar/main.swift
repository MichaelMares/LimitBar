import Foundation

// `LimitBar --check [claude,codex,openrouter,live]` runs a one-shot fetch and prints
// results to stdout — used for debugging without launching the menu bar UI.
if let idx = CommandLine.arguments.firstIndex(of: "--check") {
    let filter: Set<String>? = CommandLine.arguments.indices.contains(idx + 1)
        ? Set(CommandLine.arguments[idx + 1].split(separator: ",").map(String.init))
        : nil
    runCheck(filter: filter)
    exit(0)
} else if let idx = CommandLine.arguments.firstIndex(of: "--render-bar") {
    let path = CommandLine.arguments.indices.contains(idx + 1)
        ? CommandLine.arguments[idx + 1] : "/tmp/limitbar-preview.png"
    renderBarPreview(to: path)
    exit(0)
} else {
    LimitBarApp.main()
}

/// Fetches real provider data and writes a high-res PNG of the menu bar artwork — lets us
/// preview the look without the menu bar's screenshot restrictions.
func renderBarPreview(to path: String) {
    let providers: [any UsageProvider] = [ClaudeProvider(), CodexProvider(), OpenRouterProvider()]
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        var statuses: [ProviderStatus] = []
        for provider in providers where provider.isConfigured() {
            statuses.append(await provider.fetch())
        }
        let live = LiveTokenMonitor().sample()
        // Synthetic waterfall so the preview shows the scrolling shape.
        let base = max(live.freshTokensPerMinute, 1)
        let samples = (0..<48).map { i in base * (0.35 + 0.65 * abs(sin(Double(i) * 0.4))) }
        if let data = MenuBarRenderer.png(statuses: statuses, live: live, waterfall: samples, frame: 8) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("Wrote preview to \(path)")
        } else {
            print("Failed to render preview")
        }
        semaphore.signal()
    }
    semaphore.wait()
}

func runCheck(filter: Set<String>?) {
    let providers: [any UsageProvider] = [ClaudeProvider(), CodexProvider(), OpenRouterProvider()]
    let semaphore = DispatchSemaphore(value: 0)

    Task {
        for provider in providers {
            guard filter == nil || filter!.contains(provider.key) else { continue }
            guard provider.isConfigured() else {
                print("== \(provider.displayName): not configured, skipping")
                continue
            }
            let status = await provider.fetch()
            print("== \(status.displayName) ==\(status.subtitle.map { "  (\($0))" } ?? "")")
            if let error = status.error { print("   ERROR: \(error)") }
            for window in status.windows {
                let resets = window.resetsAt.map { "   resets \($0)" } ?? ""
                print(String(format: "   %@: %.1f%% used%@", window.label, window.usedPercent, resets))
            }
        }
        if filter == nil || filter!.contains("live") {
            let live = LiveTokenMonitor().sample()
            print("== Live ==")
            print("   active: \(live.isActive)  fresh/min: \(Util.formatTokens(live.freshTokensPerMinute))  total/min: \(Util.formatTokens(live.tokensPerMinute))  sources: \(live.sources.joined(separator: ", "))")
        }
        semaphore.signal()
    }
    semaphore.wait()
}
