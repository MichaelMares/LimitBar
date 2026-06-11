import AppKit
import SwiftUI

/// Owns the NSStatusItem, drives the menu bar animation, and shows the SwiftUI panel
/// in a transient popover on click.
@MainActor
final class StatusItemController: NSObject {
    private let store: UsageStore
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var timer: Timer?
    private var frame = 0

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

        let host = NSHostingController(rootView: MenuView(store: store, settings: store.settings))
        host.sizingOptions = [.preferredContentSize]
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = host

        // ~8fps is plenty for the bolt pulse; the batteries only change on refresh.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 8.0, repeats: true) { [weak self] _ in
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
        let isDark = statusItem.button?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) != .aqua
        statusItem.button?.image = MenuBarRenderer.render(
            statuses: store.statuses,
            live: store.live,
            frame: frame,
            isDark: isDark
        )
    }
}
