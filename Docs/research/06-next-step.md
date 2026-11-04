# 06 — Next step (stop here)

This phase is finished. **Do not start Phase 3 until you ask for it.**

## What is done

- Two remotes cloned, histories intact, no source edits
- Repo status, licenses, structure recorded (`01-baseline.md`)
- Pulse and CodexBar architectures mapped to real paths (`02`, `03`)
- Provider table from enums/manifests (`04`)
- Reuse / Comfy placement / architecture call (`05`)
- Builds attempted without changing source

## What is blocked on this Mac

Install **Xcode** (not only Command Line Tools) and point `xcode-select` at it. Until then:

- Pulse cannot `swift build` (`#Preview` / SwiftUI macros)
- CodexBar **app** cannot `swift build` (`actool`)
- `swift test` for both packages cannot finish planning

CodexBarCLI already works and can fetch JSON for Qoder/OpenAI/DeepSeek once credentials exist.

## Recommended Phase 3 (environment + contract only)

Still no merge, no Qoder/Comfy implementation, no new shipping app name/bundle.

1. Install Xcode; `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
2. Re-run:
   - `swift build` and `swift test` in `Pulse/`
   - `swift build --product CodexBar` and `make test` (or a named filter) in `CodexBar/`
3. Write a **Provider Core contract** document (types only): Pulse `ProviderUsage` as the UI model; CodexBar fetchers as the data recipe
4. Optional: one **read-only** CLI-bridge spike that maps `codexbar usage --format json --provider qoder` → a printed `ProviderUsage`-shaped fixture — delete or keep as a script, do not fold into Pulse

Phase 3 is **verify + contract**. Phase 4 would be the first native provider (Qoder) if you still want Pulse as the shell.

## Risks to carry forward

1. No Xcode → cannot prove the UI you want to keep
2. Pulse provider enum tax — every new provider touches many switches
3. Cookie providers (Qoder, likely Comfy) break when sites change headers/`Bx-V`
4. Codex vs OpenAI Admin are easy to conflate
5. Two secret stores (Pulse `LocalSecrets` vs CodexBar config/Keychain) if you CLI-bridge too long
6. License mix is fine for private use (Apache-2.0 + MIT) but keep upstream trees unmodified so you can pull

## Out of scope until you say so

- Modifying Pulse or CodexBar
- Copying provider folders
- New Xcode project / Bundle ID
- Implementing Qoder or Comfy
- Git commit / remote
