# 05 — Integration strategy

Do not copy code in this phase. This is a reuse map if Pulse remains the visible app.

## A. Reimplement in a Pulse-shaped app

Worth rewriting to match Pulse’s `ProviderUsage` / ring model:

- DeepSeek official balance (Pulse already has this)
- Simple API-key providers (OpenRouter, ElevenLabs) — small fetchers
- Pulse’s own ring, dock, alerts, burn-rate, settings chrome

## B. Reference implementation (read CodexBar, write Pulse-native)

Highest value:

| Capability | CodexBar source | Why reference, not copy wholesale |
| --- | --- | --- |
| Qoder cookies + credits API | `Sources/CodexBarCore/Providers/Qoder/` | Pulse has no Qoder; the HTTP/cookie contract is small and testable (`QoderUsageFetcherTests`) |
| OpenAI Admin spend | `Sources/CodexBarCore/Providers/OpenAI/` | Different product from Pulse Codex; needs Admin key + pagination |
| Provider descriptor / fetch plan | `ProviderDescriptor.swift`, `ProviderFetchPlan.swift` | Pulse’s closed `switch` will not scale to Qoder+Comfy+OpenAI+… |
| Cookie import discipline | `QoderCookieImporter` (Chrome-only) | Pulse `BrowserCookies.swift` is Ollama-specific |
| Codex multi-route | `Providers/Codex/` | Pulse Codex is one client + `codex app-server` fallback |

## C. Temporary CodexBar CLI bridge

CLI **builds and runs on this Mac today**.

```text
CodexBar/.build/out/Products/Debug/CodexBarCLI usage --format json --provider qoder
CodexBar/.build/out/Products/Debug/CodexBarCLI usage --format json --provider openai
```

Good for:

- Qoder and OpenAI API **before** Pulse can compile (no Xcode yet)
- Proving cookie/Admin-key setups without merging Swift modules
- A Pulse “external source” that shells out and maps JSON → `ProviderUsage`

Bad as a long-term architecture: two processes, two configs (`~/.config/codexbar/config.json` vs Pulse `UserDefaults` / `LocalSecrets`), two caches.

Use as a **Phase 3/4 probe**, not the shipping wallet.

## D. Do not migrate

| Item | Reason |
| --- | --- |
| CodexBar menu-bar tiles / Merge Icons | Pulse already chose a floating rail |
| Linux Qt desktop (`Integrations/Linux/`) | Out of scope for a private macOS wallet |
| Vortex confetti, KeyboardShortcuts, Sparkle-from-CodexBar | Pulse has its own updater (`AppUpdate.swift` + Sparkle) |
| Full 70-provider catalog | You listed a short personal set |
| CQuickJS / provider JS plugins | Extra runtime; Qoder already has a Swift strategy |
| CodexBar Widget | Optional later; not needed to validate the wallet |
| Cost-store crash probe / AdaptiveReplay CLI | Research tools, not product |

## Capability verdicts (requested)

| Capability | Verdict |
| --- | --- |
| Qoder | **B then A**. Reference `QoderUsageFetcher` + Chrome cookie import. Optionally **C** until Xcode exists. |
| OpenAI API | **B**. Port Admin costs/completions fetchers into a Pulse-shaped `OpenAIAPIUsageService`. Keep Codex as a separate provider (Pulse already has Codex). |
| Browser Cookie | **B**. Reuse the *pattern* (SweetCookieKit or Pulse `BrowserCookies`) per site; do not import every CodexBar importer. |
| Keychain | **D** for storing Agent Wallet secrets (Pulse `LocalSecrets` is enough for a single-user Mac). **B** only when reading another app’s session (Claude Desktop, Chrome Safe Storage). |
| OAuth | **B** only for providers that already need it (Codex extras, Copilot). Qoder/DeepSeek/Comfy-if-cookie do not. |
| Cost history | Pulse ledger (`UsageLedger.swift`) for CLI transcripts; CodexBar Admin API history for OpenAI $. Don’t merge stores. |
| CLI JSON | **C** now; **D** later once native providers exist. Pulse already has `Pulse --json`. |
| WebView scrape | **D** unless a provider has no JSON. CodexBar uses it for OpenAI *dashboard extras*, not for Qoder (Qoder is plain HTTP + cookie). |

## Comfy Credits — where it would sit

No Comfy code exists. Do not probe the live site in this phase.

If Pulse is the shell, the slot is the same as any new Pulse provider:

```text
ComfyProvider (Pulse-shaped)
├── Auth          → Settings row + APIKeyStore or cookie field
├── Balance fetch → new Sources/Pulse/Providers/ComfyUsageService.swift
├── Usage/History → only if an API returns it (Pulse ledger will not invent it)
├── Models        → optional; Pulse rings are account-quota, not model pickers
└── UI            → automatic once enum + UsageStore + icon exist
```

If Agent Wallet grows a CodexBar-style core:

```text
Sources/.../Providers/Comfy/
  ComfyProviderDescriptor.swift
  ComfyUsageFetcher.swift
  ComfyCookieImporter.swift   # only if dashboard-cookie
```

### If Comfy has no public balance API

Pick infrastructure from **what already exists**, not new invention:

| Approach | Best existing home | When |
| --- | --- | --- |
| Browser cookie + dashboard XHR | CodexBar Qoder pattern (`QoderUsageFetcher` + `QoderCookieImporter`) | Credits shown on a logged-in web account page |
| API token | Pulse DeepSeek / CodexBar OpenRouter | Documented `Authorization: Bearer` balance route |
| WKWebView scrape | CodexBar `OpenAIWeb/` | HTML-only page, no stable JSON |
| Local session / CLI | Pulse Codex / Volcengine | Official desktop/CLI stores a usable token |
| Other | — | Don’t start from Pulse Keychain writes; Pulse doesn’t store secrets there |

**Recommendation:** treat Comfy like Qoder until a public API appears — cookie + HTTP to whatever the logged-in account page already calls. That infrastructure is in CodexBar, not Pulse.

## Architecture recommendation

**Still: Pulse = visible product. CodexBar = provider/data reference.**

Why this still holds after reading source:

- Pulse already *is* a personal allowance wallet: edge rail, rings, hover card, burn-rate, low-balance alerts, multi-account, no telemetry.
- CodexBar already *is* a provider SDK: descriptors, cookies, Admin API, Qoder, CLI JSON.

Why the original slogan is incomplete:

- Pulse’s provider layer is a closed enum with many exhaustive switches. Naively “adding Qoder to Pulse” is a wide edit, not a drop-in file.
- CodexBar’s UI (menu bar, widgets, Linux) is the wrong shell for the product you described.
- OpenAI **API spend** and **Codex quota** are different providers in CodexBar. Pulse only has the second.

### Suggested shape (from the two trees, not invented)

```text
Agent Wallet
│
├── App / UI
│   └── Pulse Panel/ + Settings/ + UsageAlerts + BurnRate + RailSlot
│
├── Provider Core          ← new, CodexBar-inspired
│   └── id, fetch, auth kind, map → Pulse ProviderUsage
│
├── Providers
│   ├── Codex              ← start from Pulse/CodexUsageService
│   ├── OpenAI Admin       ← from CodexBar/Providers/OpenAI
│   ├── DeepSeek           ← Pulse service is enough
│   ├── Qoder              ← from CodexBar/Providers/Qoder
│   ├── Comfy              ← new, Qoder-shaped until API exists
│   └── existing Pulse set as needed (Cursor, Copilot, Grok, …)
│
├── Auth
│   ├── LocalSecrets / APIKeyStore   (Pulse)
│   └── Cookie import                (CodexBar pattern)
│
├── Ledger                 ← Pulse UsageLedger + optional Admin spend series
├── Notifications          ← Pulse UsageAlerts
└── Settings               ← Pulse SettingsView, extended per provider
```

Do **not** merge the two packages into one target in Phase 3. Keep `Pulse/` and `CodexBar/` pristine remotes.
