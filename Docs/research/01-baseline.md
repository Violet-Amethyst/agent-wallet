# 01 — Baseline

Date: 2026-09-12  
Workspace: `/Users/richard_seong/Developer/Personal/agent-wallet`  
Host: macOS, Apple Swift 6.4, `xcode-select` → `/Library/Developer/CommandLineTools`  
Xcode.app: **not installed**

No Pulse or CodexBar source files were modified. No commit, push, fork, or merge.

## Pulse

| Field | Value |
| --- | --- |
| Path | `Pulse/` |
| Branch | `main` (clean, tracking `origin/main`) |
| Origin | `https://github.com/qunqin24/Pulse.git` |
| Latest commit | `5f27ae864720786165af560ebffa93bc324ae887` — *Document the integrations and diagnostics; correct stale facts* (2026-09-10) |
| License | Apache License 2.0 (`Pulse/LICENSE`) |
| Toolchain | Swift tools 6.0, SwiftUI, SwiftPM executable |
| Platforms | `.macOS(.v14)` in `Pulse/Package.swift` |
| Products | executable `Pulse` only |
| Tests | yes — `Pulse/Tests/PulseTests/` (18 test files) |
| CLI | same binary: `Pulse --json` in `Pulse/Sources/Pulse/Usage/UsageReport.swift` |
| Widget Extension | no |
| Persistence | `UsageCache`, `UsageLedger`, `APIKeyStore` + `LocalSecrets` (AES-GCM, machine-bound), `UserDefaults` via `AppSettings` |
| Auth | OAuth (`Auth/OAuthLogin.swift`), GitHub device flow, Cursor login, browser cookies, encrypted local API keys. Limited Keychain *reads* for Claude Desktop / Chromium cookies — Pulse does **not** store its own keys in Keychain. |

### Pulse build

Command: `swift build` in `Pulse/` (README: `swift run Pulse` / `swift build`)

Result: **FAIL — environment, not source**

Cause matches `Pulse/Docs/build-from-source.md`:

- `xcode-select` points at Command Line Tools, not Xcode
- Errors: `SwiftUIMacros.StateMacro` / `PreviewsMacros.SwiftUIView` plugin not found
- Docs say: *“`xcode-select` must point at Xcode. The `#Preview` macro is expanded by a plugin that ships with Xcode.”*

Tests (`swift test`) were not runnable for the same reason. Not executed as a green/red suite.

## CodexBar

| Field | Value |
| --- | --- |
| Path | `CodexBar/` |
| Branch | `main` (clean, tracking `origin/main`) |
| Origin | `https://github.com/steipete/CodexBar.git` |
| Latest commit | `8b254dbec11ddd5c5547878d9640e4e965306c71` — *Document Linux desktop and Omarchy installation* (2026-09-11) |
| License | MIT (`CodexBar/LICENSE`) |
| Toolchain | Swift tools 6.2, SwiftPM + Makefile |
| Platforms | `.macOS(.v14)` in `CodexBar/Package.swift` |
| Products | `CodexBarCore` library, `CodexBarCLI`, `CodexBar` app, `CodexBarWidget`, watchdogs/probes, Linux Qt desktop under `Integrations/Linux/` |
| Tests | yes — `Tests/`, `TestsLinux/`, `TestsPlugin/`, AdaptiveReplay tests |
| CLI | yes — `Sources/CodexBarCLI/` (`codexbar usage --format json`) |
| Widget Extension | yes — `Sources/CodexBarWidget/` (`CodexBarWidgetProvider.swift`, `BurnDownWidgetProvider.swift`) |
| Persistence | config JSON (`~/.config/codexbar/config.json`), cost store, cookie caches, Keychain reads |
| Auth | OAuth, device flow, API keys, browser cookies (`SweetCookieKit`), Keychain, WebView dashboard scrape, local CLI credentials |

### CodexBar build

| Target | Command | Result |
| --- | --- | --- |
| CLI | `swift build --product CodexBarCLI` | **SUCCESS** (~30s). Binary: `CodexBar/.build/out/Products/Debug/CodexBarCLI`. `--help` and `usage --help` run. |
| App | `swift build --product CodexBar` | **FAIL — environment**. `actool` requires Xcode; CLT cannot compile asset catalogs. |
| Tests | `swift test --filter AdaptiveReplayKitTests` | **FAIL — environment**. `swift test` still plans the app target and hits the same `actool` error. |

This is not a source defect. The CLI target does not need `actool`; the macOS app and the full test graph do.

## Structure (two levels)

```text
Pulse/
├── Package.swift
├── Sources/Pulse/{App,Auth,Panel,Providers,Settings,Usage,Resources}
├── Tests/PulseTests/
├── Docs/
└── Scripts/

CodexBar/
├── Package.swift
├── Sources/{CodexBar,CodexBarCore,CodexBarCLI,CodexBarWidget,...}
├── Tests/
├── docs/
└── Integrations/
```

## Immediate implication

This Mac cannot compile either SwiftUI app until Xcode is installed and `xcode-select` points at it. CodexBarCLI is already a usable local tool for provider JSON. Pulse cannot be launched from this toolchain at all.
