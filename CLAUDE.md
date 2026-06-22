# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

LimitBar is a macOS menu bar app (Swift Package Manager, no Xcode project) that shows remaining AI-provider quota as horizontal "battery" gauges plus a bolt that lights up while local sessions are processing tokens. It runs as an `LSUIElement`/`.accessory` agent — no Dock icon, no main window; the entire UI is the `NSStatusItem` and a transient SwiftUI popover.

## Build & run

```sh
swift build                    # debug build → .build/debug/LimitBar
./scripts/bundle.sh            # release build wrapped into LimitBar.app (codesigns ad-hoc)
open LimitBar.app
```

Debug entry points (in `main.swift`, bypass the menu bar UI):

```sh
./.build/debug/LimitBar --check claude,codex,openrouter,gemini,live   # one-shot text dump of fetches
./.build/debug/LimitBar --render-bar /tmp/preview.png                 # PNG of the menu bar artwork
```

The `--check` flag is the primary way to test provider logic without launching the GUI or fighting the menu bar's screenshot restrictions. There is no test target.

Requires macOS 14+. After editing `bundle.sh`'s Info.plist, note it duplicates `LimitBar.app/Contents/Info.plist` — keep them in sync if it matters.

## Architecture

**Data flow:** `UsageStore` (`@MainActor ObservableObject`) is the single source of truth. It owns three cadences:
- network refresh every 60s (`refresh()` — fans out to providers via a `TaskGroup`, re-sorts into registry order),
- live token sampling every 3s (`sampleLive()` — runs `LiveTokenMonitor.sample()` off the main actor),
- and (separately, in `StatusItemController`) an ~8fps timer that re-renders the menu bar image so the bolt can pulse.

`StatusItemController` renders `store.statuses`/`store.live` into the `NSStatusItem` button image via `MenuBarRenderer`; `MenuView` renders the same data into the popover. Provider selection lives in `AppSettings` (persisted to UserDefaults); changing it publishes `$enabled`, which `UsageStore` observes to re-fetch and prune.

**Providers are the main extension point.** To add a provider:
1. Implement `UsageProvider` (`Models.swift`): `key`, `displayName`, `shortCode`, `isConfigured()`, `fetch() async -> ProviderStatus`.
2. Register it in `ProviderRegistry.all` (`Providers/Registry.swift`) — array order is display order in both the menu bar and the dropdown.
3. Add a brand color case in `Brand.ns(_:)` (same file).

Each provider returns a `ProviderStatus` containing zero or more `RateWindow`s (label, `usedPercent`, optional `resetsAt`). The **most-constrained window** (`worstWindow`, highest `usedPercent`) drives the headline battery fill; the dropdown shows every window. `isConfigured()` should be cheap and side-effect-free (e.g. a file-exists check) — it gates whether the provider appears at all and runs frequently. Specifically, avoid touching the Keychain in `isConfigured()` (it would prompt too early — see `ClaudeProvider`).

**Read-only credentials, never refresh.** Every provider reads existing CLI credentials and never writes or refreshes OAuth tokens — the underlying CLIs (`claude`, `codex`, `gemini`) rotate refresh tokens, and a third-party refresh would invalidate the CLI's session. When a token is expired, providers surface an error telling the user to run the CLI once, rather than attempting recovery. Credential sources per provider:
- Claude → macOS Keychain item `Claude Code-credentials` (configured-check uses `~/.claude.json`); hits `api.anthropic.com/api/oauth/usage` with a `claude-code/<version>` User-Agent (version sniffed from the newest local transcript).
- Codex → `~/.codex/auth.json`; primary `chatgpt.com/backend-api/wham/usage`, with a fallback that reads the last `token_count` event from `~/.codex/sessions` rollout JSONL (stays valid offline since the server pushes `used_percent` into the transcript).
- OpenRouter → `OPENROUTER_KEY` env var, or parsed from `~/.zshenv` when launched from Finder (no shell env).
- Gemini → `~/.gemini/oauth_creds.json`; POSTs to `cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota`.

**Live token monitor** (`LiveTokenMonitor`) is stateless: each `sample()` re-tails recently-modified transcript JSONL from `~/.claude/projects`, `~/.codex/sessions`, and `~/.openclaw/agents`, summing token-usage events from the last 60s. `freshTokensPerMinute` (input + output + cache writes) is the rate-limit-burning figure; `tokensPerMinute` adds cache reads. Note the deliberate non-double-counting: OpenClaw's Anthropic turns log zeros in its own transcripts because it spawns the real `claude` CLI, whose usage lands in `~/.claude/projects` — so summing all three sources stays correct.

**Two parallel renderers, intentionally mirrored.** `MenuBarRenderer` (AppKit `CGContext`, retina-correct bitmap) draws the status-bar batteries + bolt; `BatteryGauge` (SwiftUI `Canvas`) draws the dropdown gauges. Both follow the same convention: **fill color = provider brand identity (not a usage traffic light), fill width = remaining fraction.** `Util.swift` holds the shared parsing helpers (`parseTimestamp`, `tailLines`, `recentFiles`, token formatting) used across providers and the monitor.
