import SwiftUI

struct MenuView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            if store.statuses.isEmpty {
                Text("No providers configured")
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
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Text("LimitBar").font(.headline)
            Spacer()
            if store.isRefreshing {
                ProgressView().controlSize(.small)
            } else if let last = store.lastRefresh {
                Text(last, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh now")
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

private struct ProviderSection: View {
    let status: ProviderStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(status.displayName).font(.subheadline.bold())
                if let subtitle = status.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if let error = status.error {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(error)
                }
            }
            if let error = status.error, status.windows.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            ForEach(status.windows) { window in
                WindowRow(window: window)
            }
        }
    }
}

private struct WindowRow: View {
    let window: RateWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(window.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(window.usedPercent.rounded()))% used")
                    .font(.caption.monospacedDigit())
                if let resets = window.resetsAt {
                    Text("· resets \(resets, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: min(window.usedPercent, 100), total: 100)
                .tint(tint)
                .controlSize(.small)
        }
    }

    private var tint: Color {
        switch window.usedPercent {
        case ..<60: .green
        case ..<85: .yellow
        default: .red
        }
    }
}
