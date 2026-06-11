import SwiftUI

struct MenuView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            if showingSettings {
                ProviderSettings(settings: settings)
            } else {
                usage
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("LimitBar").font(.headline)
            Spacer()
            if showingSettings {
                Text("Providers").font(.caption).foregroundStyle(.secondary)
            } else {
                if store.isRefreshing {
                    ProgressView().controlSize(.small)
                } else if let last = store.lastRefresh {
                    Text(last, style: .time).font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh now")
            }
            Button {
                showingSettings.toggle()
            } label: {
                Image(systemName: showingSettings ? "chevron.backward" : "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .help(showingSettings ? "Back" : "Choose providers")
        }
    }

    // MARK: - Usage

    private var usage: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.statuses.isEmpty {
                Text("No providers selected")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            ForEach(store.statuses) { status in
                ProviderSection(status: status)
            }
            Divider()
            liveRow
            Divider()
            footer
        }
    }

    private var liveRow: some View {
        HStack(spacing: 6) {
            Image(systemName: store.live.isActive ? "bolt.fill" : "bolt.slash")
                .foregroundStyle(store.live.isActive ? .yellow : .secondary)
            if store.live.isActive {
                Text("\(Util.formatTokens(store.live.freshTokensPerMinute))/min")
                    .font(.callout.monospacedDigit())
                    .help("Rate-limit-burning tokens per minute (input + output + cache writes)")
                Text("· \(Util.formatTokens(store.live.tokensPerMinute)) w/ cache")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(store.live.sources.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No active sessions")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Refreshes every minute")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .font(.caption)
        }
    }
}

// MARK: - Provider section

private struct ProviderSection: View {
    let status: ProviderStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Circle()
                    .fill(Brand.swiftUI(status.key))
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(.primary.opacity(0.25), lineWidth: 0.5))
                Text(status.displayName).font(.subheadline.bold())
                if let subtitle = status.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if let error = status.error {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(error)
                }
            }
            if let error = status.error, status.windows.isEmpty {
                Text(error).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            ForEach(status.windows) { window in
                WindowRow(window: window, brand: Brand.swiftUI(status.key))
            }
        }
    }
}

private struct WindowRow: View {
    let window: RateWindow
    let brand: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(window.label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(window.usedPercent.rounded()))% used")
                    .font(.caption.monospacedDigit())
                if let resets = window.resetsAt {
                    Text("· resets \(resets, format: .relative(presentation: .named))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            BatteryGauge(remaining: window.remainingPercent / 100, color: brand, height: 13)
        }
    }
}

// MARK: - Provider selection

private struct ProviderSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Show in menu bar")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(ProviderRegistry.all) { info in
                let configured = info.isConfigured()
                Toggle(isOn: Binding(
                    get: { settings.isEnabled(info.key) },
                    set: { settings.setEnabled(info.key, $0) }
                )) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(info.brandColor)
                            .frame(width: 22, height: 11)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.primary.opacity(0.3), lineWidth: 0.5))
                        Text(info.displayName)
                        if !configured {
                            Text("not detected").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(!configured)
            }
            Divider()
            HStack {
                Text("Color = provider")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.font(.caption)
            }
        }
    }
}
