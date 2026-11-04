# 08 — AgentWallet v0

Date: 2026-09-12  
Workspace: `/Users/richard_seong/Developer/Personal/agent-wallet`

## How AgentWallet was created

From `agent-wallet/`:

```text
git clone /Users/richard_seong/Developer/Personal/agent-wallet/Pulse AgentWallet
cd AgentWallet
git remote rename origin upstream
git remote set-url upstream https://github.com/qunqin24/Pulse.git
git checkout -b feature/wallet-v0
```

Result:

- History is Pulse’s history.
- Remote: **only** `upstream` → `https://github.com/qunqin24/Pulse.git` (fetch + push URL, unused).
- **No** `origin`, no GitHub create, no push.
- Branch: `feature/wallet-v0`.
- `LICENSE` (Apache-2.0) kept.
- CodexBar was **not** copied in.

Layout now:

```text
agent-wallet/
├── Pulse/           # pristine upstream
├── CodexBar/        # pristine upstream
├── AgentWallet/     # product clone; only tree we edit
└── research/
```

`Pulse/` and `CodexBar/` remain `main`, clean, tracking their remotes.

AgentWallet was **not** committed this phase. Working tree on `feature/wallet-v0` holds the Dual Ring / wallet files.

## What this version is

A Pulse shell with Agent Wallet **remaining-first** Dual Ring semantics. Not a provider-integration release. Executable and menu still say **Pulse**.

## Dual Ring

Implemented in:

- `AgentWallet/Sources/Pulse/Panel/UsageRingView.swift`
- `AgentWallet/Sources/Pulse/Panel/UsageDockView.swift` (`DockLayout` inner/outer geometry)

Visual contract (inverted from Pulse):

| Ring | Meaning | Weight |
| --- | --- | --- |
| Outer | Long quota (weekly / monthly) | Thinner (`outerRingLineWidth`) |
| Inner | Short quota (5h / session) | Thicker (`innerRingLineWidth`) |
| Centre | Provider icon | Unchanged language |

Pulse put the **tightest** limit on a thick outer ring and the fullest remaining window on a thin inner ring (`ProviderUsage.headlineWindow` / `secondWindow` in `Pulse/Sources/Pulse/Usage/ProviderUsage.swift`). Agent Wallet maps **kinds**, not “most used”:

- short: `.fiveHour`, or `.other` ≤ 12 h
- long: `.weekly`, `.monthly`, or `.other` > 12 h

Arcs still **tint by used fraction** (urgency). The stroke length and the rail caption count **remaining**, except period-spend (see below).

Geometry constants: `DockLayout.outerRingLineWidth`, `innerRingDiameter`, `innerRingLineWidth` in `UsageDockView.swift`.

## Wallet model

- `AgentWallet/Sources/Pulse/Wallet/WalletSnapshot.swift` — `WalletSnapshot`, `WalletSnapshot.Mode` (`dualQuota` / `singleQuota` / `money(.prepaid|.periodSpend)`), `PeriodSpend`
- Same file: **`WalletAdapter.snapshot(from:title:)`** — `ProviderUsage` → `WalletSnapshot`
- `AgentWallet/Sources/Pulse/Wallet/WalletFixtures.swift` — DEBUG/Preview samples only

Pulse `ProviderUsage` remains the fetch/cache/UI compatibility model. The rail no longer treats it as the long-term source of truth for “which ring is which”.

Wiring:

- `AgentWallet/Sources/Pulse/Panel/FloatingUsagePanelView.swift` — `entry(for:)` builds a snapshot; DEBUG prepends fixtures
- `AgentWallet/Sources/Pulse/Panel/UsageDockView.swift` — `RailEntry.resolvedWallet` drives ring + caption
- `AgentWallet/Sources/Pulse/Panel/UsageDetailCard.swift` — remaining-first rows; spend/budget copy for money

Rail caption is **short remaining only** (`100%`, `300 cr`, `$7.31`). Two percentages never sit on the narrow rail.

## Modes

Chosen from **window kinds / metrics**, not `if provider == .codex`:

| Mode | When | Ring | Caption |
| --- | --- | --- | --- |
| `dualQuota` | Short + long quota windows | Inner thick remaining + outer thin remaining | Short remaining % |
| `singleQuota` | One quota, or credits-without-a-pair (Qoder fixture) | One ring | Remaining % or `300 cr` |
| `money(.prepaid)` | Balance / `creditRemaining`, no quota pair (DeepSeek, Comfy fixture) | Empty or money reading | Remaining cash/credits |
| `money(.periodSpend)` | `.spend` window (OpenAI fixture) | Fill = spent/budget | **Spent** (`$10.68`), never leftover `$89.32` |

OpenAI Admin is spend/budget, not a cash purse. That distinction is in the snapshot, not a provider switch.

## What actually has live data

Existing Pulse fetchers still run for enabled accounts: Codex, Claude Code, Cursor, DeepSeek, etc. If a live reading already has 5h + weekly, Dual Ring uses **those windows**.

Not implemented (on purpose):

- Qoder network fetcher
- Comfy
- OpenAI Admin API (distinct from Codex)
- Cookie scraping, new tokens, CodexBar package merge

## Preview / DEBUG fixtures

Compiled only under `#if DEBUG` (`WalletFixtures.isEnabled`). Slot prefix `wallet-fixture`. Titles always include `fixture`. Not written to `UsageCache`. Refresh clicks on fixture slots are ignored.

| Title | Mode | Numbers |
| --- | --- | --- |
| Codex · fixture | dualQuota | 5h remaining 100%, weekly remaining 67% |
| Qoder · fixture | singleQuota | 300 cr, cycle reset Sep 26 |
| OpenAI API · fixture | periodSpend | $10.68 of $100, 7-day $9.14, 550,225 tokens, 579 requests |
| DeepSeek · fixture | prepaid | $7.31 |
| Comfy · fixture | prepaid | 1,240 cr |

Qoder / OpenAI API / Comfy **reuse Pulse icons** (`commandCode`, `codex`/`openai.svg`, `openCodeGo`). No new `Provider` cases.

Release builds: `WalletFixtures.count == 0`, no extra rail slots.

Tests: `AgentWallet/Tests/PulseTests/WalletSnapshotTests.swift` (adapter + `#if DEBUG` fixture suite).

## Other AgentWallet edits

- `AgentWallet/Sources/Pulse/App/AppSettings.swift` — first AgentWallet launch sets remaining + second-ring defaults (`settings.walletV0Applied`); `railSlotCount` includes DEBUG fixtures
- `en.lproj` / `zh-Hans.lproj` — `%@ remaining`, spend/budget, credits strings

Panel / placement / collapse / alerts / burn rate were not rewritten.

## Known limitations

1. Product is still branded Pulse (executable name, menu, bundle id, UserDefaults domain). AgentWallet and Pulse share settings if both run as the same id.
2. Dual Ring icon is slightly smaller when both strokes are drawn; that is the gap + thick inner ring.
3. Fixtures sit **above** real rings in DEBUG, so a long enabled-provider list makes a tall rail.
4. Hover / collapse were not auto-screenshotable; inspect by hovering the right edge.
5. Period-spend without absolute dollars (rare Pulse `.spend` window, no budget) captions a percentage, not `$`.
6. Keychain as canonical secret store is still future work. This clone keeps Pulse `LocalSecrets`.

## Screenshots

`research/screenshots/phase3/`

- `pulse-and-codexbar-relaunch.png` — Phase 3A relaunch
- `dual-ring-collapsed.png` — AgentWallet process up; rail is a collapsed sliver on a busy desktop

Hover / single-ring close-ups were not captured automatically.

## Stop

Do not implement Qoder / Comfy / OpenAI Admin next without an explicit go-ahead. Do not push. Do not create a public GitHub repo.
