# 07 — Xcode and build validation

Date: 2026-09-12  
Workspace: `/Users/richard_seong/Developer/Personal/agent-wallet`

No files in `Pulse/` or `CodexBar/` were modified.

## Environment

| Field | Value |
| --- | --- |
| macOS | 26.6.2 (25G83) |
| Xcode | 26.6 (17F113) at `/Applications/Xcode.app` |
| `xcode-select -p` | `/Applications/Xcode.app/Contents/Developer` |
| `xcodebuild -checkFirstLaunchStatus` | 0 (license accepted) |
| Swift | 6.3.3 (`swiftlang-6.3.3.1.3`) from Xcode, not CLT |
| Disk | ~643 GB free at the start of this phase |

Earlier Phase 2 builds failed because only Command Line Tools were installed (`PreviewsMacros` / `actool`). That is resolved.

## Pulse (`Pulse/`)

Commands, from `Pulse/`, source untouched:

- `swift build -Xswiftc -swift-version -Xswiftc 6` — **success** (~16 s)
- `swift test` — **248 tests / 26 suites passed**
- Launch: debug binary  
  `Pulse/.build/arm64-apple-macosx/debug/Pulse`

`./Scripts/bundle.sh` (official `Pulse.app`) was not required for this gate; the debug executable ran as a menu-bar / edge-rail accessory.

The first on-screen launch needed a restart (user: the apps were already open). After kill + relaunch the process started again. CodexBar is a menu-bar accessory; Pulse is an edge rail. A full-desktop screenshot is at `research/screenshots/phase3/pulse-and-codexbar-relaunch.png` — the rail is easy to miss on a busy desktop; hover the **right screen edge**.

## CodexBar (`CodexBar/`)

Commands, from `CodexBar/`, source untouched:

- `swift build --product CodexBarCLI` — **success**
- `swift build --product CodexBar` — **success** (debug app)
- `swift test --filter QoderUsageFetcherTests --filter DeepSeekUsageFetcherTests --filter AdaptiveReplayKitTests` — **119 tests passed**

Not finished:

- `make test` / `./Scripts/compile_and_run.sh` (release package → `CodexBar.app`) was interrupted; a release WMO compile was killed. Debug `CodexBar/.build/debug/CodexBar` is enough to prove the app target builds and runs.

`codexbar usage --format json --json-only --provider all` returned a JSON list of 69 providers and **exit 1**. The payload matched secret-like patterns and was **not** copied into research notes. `/tmp/codexbar-usage.json` was deleted.

## AgentWallet (`AgentWallet/`)

Clone of local `Pulse/` (see `08-agentwallet-v0.md`). From `AgentWallet/`:

- `swift build -Xswiftc -swift-version -Xswiftc 6` — **success**
- `swift test` — **256 tests / 28 suites passed** (Pulse’s 248 plus wallet suites)
- `./Scripts/check-localization.sh` — 383 keys, source and `.strings` agree
- Launch:  
  `AgentWallet/.build/arm64-apple-macosx/debug/Pulse`  
  still named `Pulse` (no bundle-id / branding pass this phase)

DEBUG builds prepend five labelled fixtures on the rail (`Codex · fixture`, `Qoder · fixture`, `OpenAI API · fixture`, `DeepSeek · fixture`, `Comfy · fixture`). They are not persisted and are compiled out of Release.

## Issues encountered

1. **CLT-only toolchain** (Phase 2) — SwiftUI macros / `actool` missing until Xcode 26.6 was installed and `xcode-select` pointed at it.
2. **Pulse Swift 6** — `Package.swift` comments expect `-Xswiftc -swift-version -Xswiftc 6`.
3. **CodexBar release bundle** — `compile_and_run.sh` is slow (whole-module optimization). Debug product is the validation used here.
4. **CLI JSON** — CodexBar `--provider all` can print live credentials. Do not log it.
5. **Screenshots** — automatic full-desktop captures do not reliably show a collapsed edge sliver or a hover card. The app is launched for manual inspection.
6. **Bare `swift run` binary** — Pulse writes `~/Library/LaunchAgents/com.pulse.launch-at-login.plist` for login start. After AgentWallet’s first run that agent pointed at the AgentWallet debug binary. Same bundle id / defaults as Pulse, by design of the clone.

## Gate

Xcode works. Pulse built, tested, and ran. CodexBar CLI + debug app built, a named test filter passed, and the debug app ran. AgentWallet built, tested, and launched. Upstream trees stayed clean.
