# 04 — Provider coverage (source, not README)

Legend:

- **Pulse** = `enum Provider` in `Pulse/Sources/Pulse/Usage/UsageProvider.swift` plus a `*UsageService` under `Pulse/Sources/Pulse/Providers/`
- **CodexBar** = `enum UsageProvider` in `CodexBar/Sources/CodexBarCore/Providers/Providers.swift` plus a folder under `CodexBar/Sources/CodexBarCore/Providers/` and an entry in `ProviderManifest.swift`

Comfy / ComfyUI: **neither tree contains a match** (`find` over `agent-wallet` for `*Comfy*` = 0).

## Priority providers

| Provider | Pulse | CodexBar | Recommend for Agent Wallet |
| --- | --- | --- | --- |
| Codex (ChatGPT coding plan) | Yes — `Providers/CodexUsageService.swift`, `CodexAppServer.swift` | Yes — `Providers/Codex/` (OAuth, PAT, CLI, web dashboard) | **Pulse for ring UX**; **CodexBar for billing extras / multi-route**. Do not treat them as the same fetcher. |
| OpenAI API (Admin / platform spend) | **No** (Codex icon is OpenAI, but no Admin costs client) | Yes — `Providers/OpenAI/OpenAIAPIUsageFetcher.swift` | **CodexBar only** |
| Claude / Claude Code | Yes — Claude Code + Desktop session + OAuth extras | Yes — `Providers/Claude/` (API, cookies, CLI scrape) | Overlap. Pulse is Claude Code–centric; CodexBar is broader. |
| Cursor | Yes — `CursorUsageService.swift` | Yes — `Providers/Cursor/` | Either. Pulse is enough for quota rings; CodexBar if you want billing cookies. |
| DeepSeek | Yes — `DeepSeekUsageService.swift` (`GET /user/balance`) | Yes — `Providers/DeepSeek/` (balance + platform wallets + cost parser) | **Pulse is enough for a balance ring**; CodexBar if you want platform wallets / cost. |
| Qoder | **No** | Yes — `Providers/Qoder/` | **CodexBar only** (port or CLI-bridge) |
| OpenRouter | **No** | Yes — `Providers/OpenRouter/` | **CodexBar** |
| Gemini | **No** | Yes — `Providers/Gemini/` | **CodexBar** |
| xAI / Grok | Yes — `GrokUsageService.swift` + `GrokBotUsageService.swift` | Yes — `Providers/XAI/` + `Providers/Grok/` (separate cases `xai`, `grok`) | Pulse covers Grok + Cursor-billed Grok Bot. CodexBar splits xAI vs Grok more finely. |
| GitHub Copilot | Yes — `CopilotUsageService.swift` + device flow | Yes — `Providers/Copilot/` | Either |
| ElevenLabs | **No** | Yes — `Providers/ElevenLabs/` | **CodexBar** |
| AWS Bedrock | **No** | Yes — `Providers/Bedrock/` | **CodexBar** |
| Comfy Credits | **No** | **No** | New work. See `05` / `07` notes in `05-integration-strategy.md` |

## Other providers present in source

### Pulse only (vs CodexBar naming)

Pulse `glmCoding` (Zhipu / 清言) and `minimaxCN` are first-class enum cases. CodexBar folds some of this into region/settings on a single provider.

### CodexBar only (id → folder)

From `UsageProvider` + `ProviderManifest.allDescriptors` (not guessed):

`azureopenai`, `clinepass`, `opencode`, `alibaba`, `alibabatokenplan`, `qwencloud`, `factory`, `fireworks`, `gemini`, `devin`, `manus`, `kilo`, `kiro`, `vertexai`, `augment`, `jetbrains`, `moonshot`, `amp`, `t3chat`, `synthetic`, `openrouter`, `elevenlabs`, `warp`, `windsurf`, `zed`, `perplexity`, `mimo`, `doubao`, `sakana`, `abacus`, `mistral`, `deepinfra`, `codebuff`, `crof`, `venice`, `qoder`, `stepfun`, `bedrock`, `groq`, `llmproxy`, `litellm`, `deepgram`, `poe`, `chutes`, `neuralwatt`, `clawrouter`, `longcat`, `sub2api`, `wayfinder`, `zenmux`, `aiand`, `zoommate`, `xai`, `notion`, `ibmbob`

Plus shared-with-Pulse: `codex`, `claude`, `cursor`, `opencodego`, `antigravity`, `copilot`, `zai`, `minimax`, `kimi`, `ollama`, `commandcode`, `deepseek`, `grok`

`UsageProvider` has **69** cases. xAI and Grok are separate (`xai`, `grok`). OpenAI Admin (`openai`) is not Codex.

### Both (same product, different code)

Claude Code / Claude, Codex, Cursor, Copilot, Grok, MiniMax, z.ai, Kimi, Ollama Cloud, OpenCode Go, Command Code, DeepSeek, Antigravity.

Implementations are **not interchangeable**. Pulse services return `ProviderUsage`; CodexBar fetchers return `UsageSnapshot`.

## Auth-method coverage (source)

| Method | Pulse | CodexBar |
| --- | --- | --- |
| Pasted API key | Yes (`APIKeyStore` + `LocalSecrets`) | Yes (`ProviderCredentialAdapter.apiKey`) |
| Browser cookies | Thin (Ollama Cloud + Chromium unlock) | First-class (`SweetCookieKit`, many `*CookieImporter`s) |
| OAuth / device flow | Claude/Codex/Grok extras; Copilot device | Many providers, per-folder |
| Local CLI session | Claude, Codex, Volcengine `arkcli`, Grok CLI | Codex, Claude, Gemini, Kilo, Antigravity `agy`, … |
| Keychain | Read Claude Desktop / browser Safe Storage | Read Zed, Chromium, Claude compare |
| WKWebView scrape | No | Yes (`Sources/CodexBarCore/OpenAIWeb/`) |

## Implication

Pulse is a **17-provider rail**. CodexBar is a **70+ provider data plane**. Agent Wallet’s listed future set (Codex/OpenAI, DeepSeek, Qoder, Comfy, plus “whatever they already support”) is **not implementable from Pulse alone** — Qoder and OpenAI Admin API exist only in CodexBar; Comfy exists in neither.
