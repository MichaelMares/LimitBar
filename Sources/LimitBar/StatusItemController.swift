import AppKit
import SwiftUI

/// Owns the NSStatusItem, drives the ~12fps menu bar animation, and shows the SwiftUI panel
/// in a transient popover on click.
@MainActor
final class StatusItemController: NSObject {
    private let store: UsageStore
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var timer: Timer?
    private var frame = 0

    /// Rolling history of live throughput samples that the waterfall scrolls through.
    private var waterfall = [Double](repeating: 0, count: 48)

    init(store: UsageStore) {
        self.store = store
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.toolTip = "LimitBar — AI usage"
        }

        let host = NSHostingController(rootView: MenuView(store: store))
        host.sizingOptions = [.preferredContentSize]
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = host

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        tick()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func tick() {
        frame &+= 1
        waterfall.removeFirst()
        waterfall.append(store.live.freshTokensPerMinute)
        statusItem.button?.image = MenuBarRenderer.render(
            statuses: store.statuses,
            live: store.live,
            waterfall: waterfall,
            frame: frame
        )
    }
}
