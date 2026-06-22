import SwiftUI
import AppKit

struct MenuView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if showingSettings {
                SettingsPane(settings: settings)
            } else {
                usage
            }
        }
        .padding(14)
        .frame(width: 304)
        .animation(.snappy(duration: 0.28), value: showingSettings)
        // The pop-over is mouse-driven; suppress the keyboard focus ring that otherwise lands on
        // the first button when the pop-over becomes the key window.
        .focusEffectDisabled()
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.headline)
                .foregroundStyle(.tint)
            Text(showingSettings ? "Settings" : "LimitBar")
                .font(.headline)
                .contentTransition(.identity)

            Spacer()

            if !showingSettings {
                if store.isRefreshing {
                    ProgressView().controlSize(.small)
                } else if let last = store.lastRefresh {
                    Text(last, style: .time)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                HeaderButton(system: "arrow.clockwise", help: "Refresh now") {
                    Task { await store.refresh() }
                }
                .disabled(store.isRefreshing)
            }
            HeaderButton(system: showingSettings ? "chevron.backward" : "slider.horizontal.3",
                         help: showingSettings ? "Back" : "Settings") {
                showingSettings.toggle()
            }
        }
    }

    // MARK: - Usage

    private var usage: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.statuses.isEmpty {
                EmptyStateCard()
            } else {
                ForEach(store.statuses) { status in
                    ProviderCard(status: status)
                }
            }
            LiveCard(live: store.live)
            footer
        }
    }

    private var footer: some View {
        HStack {
            Text("Updates every minute")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }
}

// MARK: - Reusable chrome

/// Borderless icon button with a soft hover background — used in the header.
private struct HeaderButton: View {
    let system: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(Color.primary.opacity(hovering ? 0.10 : 0), in: .rect(cornerRadius: 6))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Card container shared by every section in the popover.
private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.045), in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.07)))
    }
}

/// Small rounded brand swatch used as a provider's identity chip.
private struct BrandChip: View {
    let key: String
    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Brand.swiftUI(key))
            .frame(width: 18, height: 11)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.primary.opacity(0.25), lineWidth: 0.5))
    }
}

// MARK: - Provider card

private struct ProviderCard: View {
    let status: ProviderStatus
    private var brand: Color { Brand.swiftUI(status.key) }
    private var hasError: Bool { status.error != nil && status.windows.isEmpty }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .center, spacing: 8) {
                    BrandChip(key: status.key)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(status.displayName).font(.subheadline.bold())
                        if let subtitle = status.subtitle {
                            Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    headline
                }

                if hasError, let error = status.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(WarningLabelStyle())
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(status.windows) { window in
                        WindowRow(window: window, brand: brand)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var headline: some View {
        if hasError {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else if let worst = status.worstWindow {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(worst.remainingPercent.rounded()))")
                    .font(.title3.bold().monospacedDigit())
                    .contentTransition(.numericText())
                Text("%")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(brandReadable)
        }
    }

    /// Brand color is the accent, but fall back to primary when it'd be illegible on the card.
    private var brandReadable: Color { .primary }
}

private struct WindowRow: View {
    let window: RateWindow
    let brand: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(window.label).font(.caption).foregroundStyle(.secondary)
                if let resets = window.resetsAt {
                    Text("· resets \(resets, format: .relative(presentation: .named))")
                        .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
                Spacer(minLength: 6)
                Text("\(Int(window.usedPercent.rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            BatteryGauge(remaining: window.remainingPercent / 100, color: brand, height: 13)
        }
    }
}

private struct WarningLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            configuration.icon.foregroundStyle(.orange)
            configuration.title
        }
    }
}

// MARK: - Live activity card

private struct LiveCard: View {
    let live: LiveActivity

    var body: some View {
        Card {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(live.isActive ? Color.yellow.opacity(0.18) : Color.primary.opacity(0.06))
                        .frame(width: 30, height: 30)
                    Image(systemName: live.isActive ? "bolt.fill" : "bolt.slash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(live.isActive ? .yellow : .secondary)
                        .symbolEffect(.pulse, options: .repeating, isActive: live.isActive)
                }

                if live.isActive {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(Util.formatTokens(live.freshTokensPerMinute))
                                .font(.callout.bold().monospacedDigit())
                                .contentTransition(.numericText())
                            Text("tok/min")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Text("\(Util.formatTokens(live.tokensPerMinute)) with cache reads")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if !live.sources.isEmpty {
                        Text(live.sources.joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.primary.opacity(0.06), in: .capsule)
                    }
                } else {
                    Text("No active sessions")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .help("Rate-limit-burning tokens per minute (input + output + cache writes)")
    }
}

private struct EmptyStateCard: View {
    var body: some View {
        Card {
            HStack(spacing: 10) {
                Image(systemName: "tray")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("No providers selected").font(.subheadline.weight(.medium))
                    Text("Open Settings to choose what to show.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }
}

// MARK: - Settings pane

private struct SettingsPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            providerSection
            notificationsSection
            keychainSection
            HStack {
                Text("Fill color = provider · width = remaining")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Show in menu bar")
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(ProviderRegistry.all.enumerated()), id: \.element.id) { index, info in
                        let configured = info.isConfigured()
                        Toggle(isOn: Binding(
                            get: { settings.isEnabled(info.key) },
                            set: { settings.setEnabled(info.key, $0) }
                        )) {
                            HStack(spacing: 8) {
                                BrandChip(key: info.key)
                                Text(info.displayName)
                                if !configured {
                                    Text("not detected").font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .disabled(!configured)
                        if index < ProviderRegistry.all.count - 1 {
                            Divider().opacity(0.4)
                        }
                    }
                }
            }
        }
    }

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Notifications")
            Card {
                Toggle(isOn: $settings.notifyOnReset) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Remind me when a limit refreshes").font(.subheadline)
                        Text("Get a notification when a window you'd nearly maxed out rolls over — time to get back to vibecoding.")
                            .font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
        }
    }

    private var keychainSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Keychain access")
            Card {
                VStack(alignment: .leading, spacing: 9) {
                    Toggle(isOn: $settings.allowKeychain) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Allow reading the Keychain").font(.subheadline)
                            Text("Claude usage is read from your login Keychain. LimitBar only reads — it never writes or refreshes tokens.")
                                .font(.caption2).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                    Divider().opacity(0.4)

                    Button {
                        openKeychainAccess()
                    } label: {
                        Label("Open Keychain Access…", systemImage: "key.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)

                    Text("To fully revoke OS-level access, open the “Claude Code-credentials” item there → Access Control and remove LimitBar.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func openKeychainAccess() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Keychain Access.app")
        NSWorkspace.shared.open(url)
    }
}

private struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .tracking(0.4)
    }
}
