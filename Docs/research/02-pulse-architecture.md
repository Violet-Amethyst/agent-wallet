# 02 — Pulse architecture

All paths are relative to `Pulse/`.

## 1. App entry

`Sources/Pulse/App/PulseApp.swift`

- `@main enum PulseMain` intercepts CLI modes **before** SwiftUI starts:
  - Claude status-line hook (`StatusLineHook`)
  - `--install-statusline` / `--uninstall-statusline`
  - `Pulse --json` → `UsageReport.run()` (`Sources/Pulse/Usage/UsageReport.swift`)
- Then `PulseApp: App` with `MenuBarExtra` + `AppDelegate`.

`Sources/Pulse/App/AppDelegate.swift`

- Accessory app (`setActivationPolicy(.accessory)`)
- Owns `AppSettings`, `UsageStore`, `UsageAlerts`, `FloatingPanelController`
- Login item, Sparkle (`AppUpdate.swift`), storage cleanup

## 2. Floating / edge panel

- Controller: `Sources/Pulse/Panel/FloatingPanelController.swift`  
  Fixed-size transparent `NSPanel`. **Does not grow when the detail card opens** (avoids the rail jumping). Size from `DockLayout` + `DetailCardLayout`.
- View: `Sources/Pulse/Panel/FloatingUsagePanelView.swift`
- Dock rail: `Sources/Pulse/Panel/UsageDockView.swift`
- Placement: `Sources/Pulse/Panel/PanelPlacement.swift`, `PanelScreen.swift`, `ActiveDisplayFollower.swift`
- Pointer / hover: `PanelPointerWatcher.swift`, `PointerEntryReporter.swift`
- Surface: `PanelSurface.swift` (obsidian / Liquid Glass)

## 3. Ring UI

`Sources/Pulse/Panel/UsageRingView.swift`

- Spent vs remaining (countdown mode)
- Color via `UsageTint.swift`
- Optional elapsed-window outer arc
- Active-turn revolving dot (`AgentActivity.swift`)

Detail card: `UsageDetailCard.swift`, `AccountUsageCard.swift`, `UsageBubbleShape.swift`

## 4. Hover / expand / collapse

`UsageDockView.swift` + `FloatingUsagePanelView.swift`

- Idle auto-collapse to a thin sliver
- Hover expands rings and shows the detail card beside the rail
- Hover can force a refresh (`UsageStore.lastLookRefresh`, 30s cooldown)

## 5. Provider architecture

Pulse does **not** have a plugin registry.

Closed enum: `Sources/Pulse/Usage/UsageProvider.swift` — `enum Provider: String, CaseIterable`

Current cases (source, not README):

`claudeCode`, `codex`, `antigravity`, `cursor`, `openCodeGo`, `kimiCode`, `ollamaCloud`, `zai`, `glmCoding`, `minimax`, `minimaxCN`, `copilot`, `grok`, `grokBot`, `volcengine`, `commandCode`, `deepSeek`

Each provider is a `*UsageService` in `Sources/Pulse/Providers/`.  
`UsageStore` switches on `Provider` to call `fetch()`.

Adding a provider means extending the enum **and every exhaustive switch** on it. Pulse comments call this out as intentional (e.g. `soleRoute`).

## 6. Provider model

`Sources/Pulse/Usage/ProviderUsage.swift`

- `UsageWindow` with kinds: `fiveHour`, `weekly`, `spend`, `balance`, `monthly`, `other`
- Pulse **never invents a used %** — only what the provider reported
- `ProviderUsage` is the rail/card input
- DeepSeek is a prepaid `balance` with no allowance; denominator comes from `DeepSeekBalanceBasis.swift`

## 7. Refresh flow

`Sources/Pulse/Usage/UsageStore.swift`

- `@MainActor @Observable`
- Keyed by `AccountKey.id`, not by provider alone
- Per-account fetch + generation token so stale passes cannot overwrite a newer click-refresh
- Interval from `AdaptiveRefresh.swift`
- Cache reconcile: `UsageCache.swift`
- Route choice (Claude / Codex / Volcengine): `UsageRoute.swift`, `UsageSource.swift`

## 8. Authentication

| Mechanism | Files |
| --- | --- |
| Encrypted local keys | `Auth/APIKeyStore.swift`, `Auth/LocalSecrets.swift` (AES-GCM from IOPlatform UUID; **not Keychain**) |
| Extra OAuth accounts | `Auth/AccountCredentials.swift`, `Auth/OAuthLogin.swift`, `Auth/LoopbackCallback.swift` |
| GitHub device flow | `Auth/GitHubDeviceLogin.swift` |
| Cursor | `Auth/CursorAppLogin.swift`, `Auth/CursorWebLogin.swift` |
| Browser cookies | `Auth/BrowserCookies.swift` (Ollama Cloud; Keychain used to unlock Chromium Safe Storage) |
| Claude Desktop Keychain read | `Providers/ClaudeDesktopSession.swift`, `ClaudeCodeUsageService.readKeychainCredentials()` |

## 9. Persistence / ledger

- Settings: `App/AppSettings.swift` (`UserDefaults`)
- Last readings: `Usage/UsageCache.swift` → `~/Library/Application Support/Pulse/last-readings.json`
- Keys / OAuth extras: `keys.dat`, `accounts.dat` (AES-GCM via `LocalSecrets`)
- Alerts memory: `alerts.json`; DeepSeek peak: `deepseek-baseline.json`
- Historical spend from **local CLI transcripts** + published prices: `Usage/UsageLedger.swift` (`ledger-2-{provider}.json`), `ModelPrices.swift`
- History only where `Provider.providesHistory` is true (Claude/Codex transcripts; z.ai / Zhipu stats)
- Multi-account (`supportsMultipleAccounts`) is only Claude Code, Codex, Grok, Grok Bot

## 10. Notifications

`Sources/Pulse/Usage/UsageAlerts.swift` (`UserNotifications`)

- Default **off**
- Thresholds 75/80/90/95%, exhausted, recovered, stale cache, prepaid low-balance (`reportsSpendableBalance` = DeepSeek + Command Code)
- Each condition said once until reset/worse

## 11. Burn rate / forecast

`Sources/Pulse/Usage/BurnRate.swift`

- Computed from **one reading** (used fraction vs window elapsed)
- Comment: idea from CodexBar; Pulse dropped trailing-sample history as too noisy
- Verdict (“will last”) plus optional ETA

## 12. Multi-account

`Sources/Pulse/Usage/MonitoredAccount.swift`

- `AccountKey(provider, slot)` — first account id == `provider.rawValue` (no settings migration)
- Extra Claude / Codex / Grok / Grok Bot accounts via Pulse-owned OAuth tokens
- `RailSlot` can split one login into multiple rings (Antigravity Gemini vs Claude/GPT)

## 13. Settings

`Sources/Pulse/Settings/`

- `SettingsView.swift` (large; per-provider credential rows, rail order, alerts, integrations)
- `ConnectionDiagnosticsView.swift`
- `DeveloperIntegrationsView.swift` (Raycast / tmux / sketchybar export)

## 14. Icon / branding

- Per-provider `iconResource` in `UsageProvider.swift`
- SVGs: `Sources/Pulse/Resources/{claude,openai,cursor,...}.svg`
- App icon: `AppIcon/`
- No Qoder / Comfy assets

## If we add Qoder later (Pulse)

Must change (minimum):

1. `Sources/Pulse/Usage/UsageProvider.swift` — new `case qoder` and **every** switch (`displayName`, `iconResource`, `keepsLocalTranscripts`, `hasSourceChoice`, `soleRoute`, `usesAPIKey`, `usesSessionCookie`, `keepsOwnCredential`, `reportsSpendableBalance`, `canReportWithoutSetup`, multi-account flags, …)
2. `Sources/Pulse/Usage/UsageStore.swift` — `switch provider` around line 641 and `fetchAdded` around line 736
3. `Sources/Pulse/Usage/UsageRoute.swift`, `UsageSource.swift`, `Providers/ConnectionRemedy.swift` — exhaustive route/help switches
4. **New** `Sources/Pulse/Providers/QoderUsageService.swift` (cookie → `GET …/api/v2/me/usages/big_model_credits`; logic lives in CodexBar today)
5. `Sources/Pulse/Settings/SettingsView.swift` — cookie/manual credential UI
6. `Sources/Pulse/Resources/qoder.svg` + `iconResource`
7. Localization under `Sources/Pulse/Resources/*.lproj`
8. Tests under `Tests/PulseTests/`
9. Likely `Auth/BrowserCookies.swift` or reuse CodexBar’s Chrome-only import
10. Docs under `Docs/providers/` if keeping Pulse’s contributor map

Qoder is cookie-dashboard, not a pasted API key. Pulse’s only session-cookie provider today is Ollama Cloud (`usesSessionCookie`).

## If we add Comfy later (Pulse)

Same file set as Qoder, plus:

- `ComfyUsageService.swift`
- `Resources/comfy.svg`
- Settings row for whatever auth exists (token vs cookie vs scrape)

There is **no Comfy code** in Pulse. The enum/switch tax is the same.

## DeepSeek in Pulse (source)

`Sources/Pulse/Providers/DeepSeekUsageService.swift`

- `GET https://api.deepseek.com/user/balance`
- `Authorization: Bearer <pasted key>`
- Parses `balance_infos[].total_balance` strings
- Ring denominator: `DeepSeekBalanceBasis.swift` (measured peak / none / user budget)
- No usage windows, no official spend history
