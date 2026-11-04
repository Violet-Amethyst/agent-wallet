# 03 — CodexBar architecture

All paths are relative to `CodexBar/`.

## 1. Target layout

From `Package.swift`:

| Target | Path | Role |
| --- | --- | --- |
| `CodexBarCore` | `Sources/CodexBarCore/` | Providers, HTTP, cookies, cost store, snapshots |
| `CodexBarCLI` | `Sources/CodexBarCLI/` | `codexbar` CLI |
| `CodexBar` | `Sources/CodexBar/` | macOS menu-bar app |
| `CodexBarWidget` | `Sources/CodexBarWidget/` | WidgetKit sources |
| Widget `.appex` | `WidgetExtension/CodexBarWidgetExtension.xcodeproj` | Shipping macOS widget plugin |
| `AdaptiveRefreshCore` | `Sources/AdaptiveRefreshCore/` | Refresh decision table |
| Tests | `Tests/`, `TestsLinux/`, `TestsPlugin/` | Swift Testing |

Core is the reusable piece. The app and CLI both consume `ProviderDescriptor` + fetch plans.

## 2. Provider architecture

Closed enum of ids: `Sources/CodexBarCore/Providers/Providers.swift` — `enum UsageProvider` (**69** cases including `qoder`, `openai`, `deepseek`, `bedrock`, `openrouter`, `gemini`, `elevenlabs`, `xai`, `grok`). Optional JS strategies live in `Sources/CodexBarCore/Resources/Plugins/` (e.g. `qoder.js`, `openai.js`) and can prepend `ScriptFetchStrategy` before native Swift.

Abstraction: `Sources/CodexBarCore/Providers/ProviderDescriptor.swift`

A descriptor bundles:

- `id`, settings section, credentials (`ProviderCredentialAdapter`)
- `ProviderMetadata`, `ProviderBranding`
- `ProviderFetchPlan` (source modes + strategy pipeline)
- CLI config, token-cost config, presentation

Bootstrap list (generated): `Sources/CodexBarCore/Providers/ProviderManifest.swift`  
`Scripts/regenerate-provider-manifests.sh` — do not hand-edit the list.

Runtime registration: `ProviderDescriptorRegistry.register(_:)` (comment on the manifest).

Fetch: `ProviderFetchPlan` → strategies (`QoderWebFetchStrategy`, OAuth, CLI, script/plugin).  
HTTP: `ProviderHTTPTransport` / `ProviderHTTPClient.shared`.

This is still a closed enum, but **new work is mostly a new folder + descriptor**, not a 15-way switch inside the UI store.

## 3. How to add a provider (CodexBar pattern)

Typical set:

1. `case` on `UsageProvider` in `Providers.swift`
2. Folder `Sources/CodexBarCore/Providers/<Name>/` — exactly one `*ProviderDescriptor.swift` plus fetcher/settings/cookie importer
3. App layer: `Sources/CodexBar/Providers/<Name>/*ProviderImplementation.swift` (`let id: UsageProvider = .<case>`)
4. Run `Scripts/regenerate-provider-manifests.sh` (writes `ProviderManifest.swift`, `ProviderImplementationManifest.swift`, `ProviderInstanceIDAliases.generated.swift`, `docs/provider-ids.md`)
5. Icon `Sources/CodexBar/Resources/ProviderIcon-<id>.svg`
6. `docs/<name>.md`
7. Tests under `Tests/CodexBarTests/`

## 4. Qoder — identity, credits, parse, refresh

**Files**

- `Sources/CodexBarCore/Providers/Qoder/QoderProviderDescriptor.swift`
- `Sources/CodexBarCore/Providers/Qoder/QoderCookieImporter.swift`
- `Sources/CodexBarCore/Providers/Qoder/QoderUsageFetcher.swift`
- `Sources/CodexBarCore/Providers/Qoder/QoderUsageSnapshot.swift`
- `Sources/CodexBarCore/Providers/Qoder/QoderUsageError.swift`
- `Sources/CodexBarCore/Providers/Qoder/QoderProviderSettings.swift`
- Docs: `docs/qoder.md`
- Tests: `Tests/CodexBarTests/Qoder*.swift`

**Find login**

`QoderCookieImporter.importSessions` + `QoderWebFetchStrategy.resolveCookieHeader`

- Chrome only (`browserCookieOrder: [.chrome]`) via `SweetCookieKit` / `BrowserCookieClient`
- Domains: `qoder.com` / `www.qoder.com` or `qoder.com.cn` / `www.qoder.com.cn`
- Manual: paste `Cookie:` header or cURL; China vs intl inferred from URL/Host
- Cache: `CookieHeaderCache` (Keychain-backed). 401/403 clears cache and retries another browser/site label
- **No account email/org.** `QoderUsageSnapshot.toUsageSnapshot()` sets `accountEmail` / `loginMethod` to nil — identity is the cookie session only

There is **no Qoder API key** and **no local Qoder CLI credential** in this tree.

**Fetch credits**

`QoderUsageFetcher.fetchUsage(cookieHeader:site:)`

```text
GET https://qoder.com/api/v2/me/usages/big_model_credits
GET https://qoder.com.cn/api/v2/me/usages/big_model_credits
```

Headers: `Cookie`, browser UA, `Origin`, `Referer` (`…/account/usage`), `X-Requested-With: XMLHttpRequest`, `Bx-V: 2.5.35`

401/403 → `QoderUsageError.invalidCredentials`

**Parse**

`parseUsage` decodes `QoderUsageResponse`, requires `totalQuota.quotaSummary`, merges `sharedQuota` when present. Snapshot fields: used / total / remaining credits, usage %, optional `nextResetAt`.

`QoderUsageSnapshot.toUsageSnapshot()` maps that onto CodexBar’s generic `UsageSnapshot` + `RateWindow`.

**Refresh**

Descriptor `fetchPlan`: source modes `[.auto, .web]`, pipeline `QoderWebFetchStrategy` (optional `qoder.js` plugin first). Same HTTP fetch on each refresh; cookie re-import when auto and cache is dead.

CLI: `codexbar usage --provider qoder` (`docs/qoder.md`).

## 5. OpenAI — usage, spend, vs Codex

**OpenAI API (platform / Admin)** — `Sources/CodexBarCore/Providers/OpenAI/`

| File | Role |
| --- | --- |
| `OpenAIAPIProviderDescriptor.swift` | `UsageProvider.openai`, Admin API key, dashboard `platform.openai.com/usage` |
| `OpenAIAPIUsageFetcher.swift` | `GET https://api.openai.com/v1/organization/costs` and `…/v1/organization/usage/completions` |
| `OpenAIAPICreditBalanceFetcher.swift` | Legacy credit grants (`total_granted` / `total_used` / `total_available`) |
| `OpenAIAPISettingsReader.swift` | Admin key + optional project id |
| `OpenAIAPIUsageSnapshot.swift` | Spend / request history mapping |

This is **organization Admin API spend**, not ChatGPT/Codex subscription quota.

**Codex (ChatGPT coding plan)** — `Sources/CodexBarCore/Providers/Codex/`

Separate id: `UsageProvider.codex`. Routes include:

- OAuth: `CodexOAuth/CodexOAuthUsageFetcher.swift`, `CodexTokenRefresher.swift`
- PAT: `CodexPAT/CodexPATUsageFetcher.swift`
- Local CLI: `CodexCLISession.swift`, `CodexStatusProbe.swift`
- Web dashboard extras: `CodexWebDashboardStrategy.swift` + `Sources/CodexBarCore/OpenAIWeb/` (`WKWebView` scrape, cookie extras)

`CodexProviderDescriptor.resolveStrategies` (source order):

- `.auto` (no managed workspace): PAT → OAuth → CLI
- `.auto` (managed workspace): PAT → OAuth
- `.oauth` / `.cli` / `.api` / `.web`: the matching single strategy (`CodexWebDashboardStrategy` for web)

OAuth hits `https://chatgpt.com/backend-api/wham/usage` via `CodexOAuthUsageFetcher` / `OpenAIDashboardFetcher.dashboardUsageAPIURL`.

CLI help also says Codex auto can prefer the OpenAI **web dashboard** extras and fall back to Codex CLI when cookies are missing.

OpenAI Admin fallback: if costs/completions fail and `allowsLegacyBalanceFallback`, `OpenAIAPICreditBalanceFetcher` reads prepaid grants (source label `billing-api`).

**Distinction in source**

- `openai` = platform Admin API (API usage + $ spend)
- `codex` = Codex/ChatGPT product quota (+ optional dashboard scrape)

Pulse only implements the Codex *product* side (`Providers/CodexUsageService.swift`), not Admin API spend.

## 6. DeepSeek — balance

`Sources/CodexBarCore/Providers/DeepSeek/`

- `DeepSeekUsageFetcher.swift`
  - API: `GET https://api.deepseek.com/user/balance` (`Bearer` API key)
  - Platform: `GET https://platform.deepseek.com/api/v0/users/get_user_summary`
  - Optional month usage/cost: `…/api/v0/usage/amount` and `…/usage/cost`
- `DeepSeekPlatformTokenImporter.swift` — Chrome session → platform token
- `DeepSeekUsageCostParser.swift` — cost parsing beyond Pulse’s balance-only ring
- `DeepSeekProviderDescriptor.swift` — `.api` vs `.web` strategies; optional usage join with a short grace window
- App: `Sources/CodexBar/Providers/DeepSeek/`

Pulse’s DeepSeek is a subset: one documented balance endpoint + pasted key.

## 7. Browser cookies

- Dependency: SweetCookieKit (`Package.swift`)
- Shared: `Providers/ProviderCookieSource.swift`, `ProviderCookieSettings.swift`, `BrowserCookieClient` usage in each `*CookieImporter.swift`
- Qoder is Chrome-only to avoid extra Keychain prompts

## 8. Keychain

Widespread **reads** of other apps’ items (Zed, Chromium Safe Storage, Claude OAuth compare). Gates: `KeychainAccessGate`, `KeychainNoUIQuery`. Not Pulse-style “encrypt keys in the app folder.”

## 9. OAuth

Per-provider, not one generic login:

- Codex: `Providers/Codex/CodexOAuth/`
- Gemini / Vertex / Claude / Copilot device flow, etc.

## 10. HTTP

`ProviderHTTPTransport` / `ProviderHTTPClient` + retry policy (`OpenAIAPIUsageFetcher` uses `ProviderHTTPRetryPolicy.transientIdempotent`).

## 11. WebView scrape

`Sources/CodexBarCore/OpenAIWeb/`

- `OpenAIDashboardWebViewCache.swift`, `OpenAIDashboardWebsiteDataStore.swift`
- Offscreen `WKWebView` for ChatGPT/OpenAI dashboard extras
- Claude CLI TUI scrape is a different path (`ClaudeStatusProbe`)

## 12. Local CLI credentials

Codex, Claude, Gemini CLI, `agy`, `arkcli`-class tools, Kilo CLI fallback. Qoder has none.

## 13. Spend / history

SQLite cost store: `Sources/CodexBarCore/Vendored/CostUsage/CostUsageStore.swift` (`cost-usage.sqlite`, WAL, single-writer). Scanner: `CostUsageScanner.swift`. Crash harness: `CodexBarCostStoreCrashProbe`. OpenAI Admin API is first-class spend. Pulse ledger is local-transcript reconstruction.

## 14. CLI JSON

`Sources/CodexBarCLI/CLIUsageCommand.swift`, `CLIEntry.swift`

```text
codexbar usage --format json --provider all --pretty
codexbar usage --provider qoder --verbose
codexbar usage --provider openai --format json
```

Also: `config`, `cost`, `cookie`, `diagnose`, `dashboard`, `serve`.

## 15. Widget

Shared views: `Sources/CodexBarWidget/`. Shipping plugin: `WidgetExtension/CodexBarWidgetExtension.xcodeproj` → `CodexBarWidget.appex`. Data pipe: app-group `WidgetSnapshot`. Pulse has no equivalent.
