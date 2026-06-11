# LimitBar

A macOS menu bar app that shows your remaining AI provider quota at a glance, plus a live
indicator for when tokens are being processed — across Claude Code, Codex, OpenClaw, the CLIs,
and more.

## What it shows

- **Horizontal "battery" gauges** in the menu bar, one per provider, colored by brand
  (Claude = orange, Codex/OpenAI = white, OpenRouter = black, Gemini = blue). The fill level is
  your *remaining* quota on the most-constrained window.
- A **bolt** that lights up when any local session is actively processing tokens.
- A **dropdown panel** with exact per-window percentages, reset times, and live tokens/min.
- **Provider selection** — choose which providers appear in the menu bar.

## Data sources

| Provider | Source |
|---|---|
| Claude | Keychain OAuth token → `api.anthropic.com/api/oauth/usage` |
| Codex | `~/.codex/auth.json` → `chatgpt.com/backend-api/wham/usage` (local session JSONL fallback) |
| OpenRouter | `OPENROUTER_KEY` → `/api/v1/credits` |
| Gemini | `~/.gemini/oauth_creds.json` → `cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota` |
| Live tokens | Tails Claude / Codex / OpenClaw session transcripts |

LimitBar reads credentials **read-only** and never refreshes tokens itself — the CLIs do that.

## Build & run

```sh
swift build
./scripts/bundle.sh   # produces LimitBar.app
open LimitBar.app
```

Debug helpers:

```sh
./.build/debug/LimitBar --check claude,codex,openrouter,gemini,live   # one-shot text dump
./.build/debug/LimitBar --render-bar /tmp/preview.png                 # render the menu bar art
```
