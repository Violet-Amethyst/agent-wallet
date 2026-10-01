import Foundation

/// The coding agents Pulse tracks.
///
/// Each reports its own usage, by routes that have almost nothing in common —
/// see `ClaudeCodeUsageService`, `CodexUsageService`, `AntigravityUsageService`,
/// `CursorUsageService` and the key-based ones.
enum Provider: String, CaseIterable, Identifiable, Codable, Sendable {
    case claudeCode
    case codex
    case openAI
    case kiro
    case antigravity
    case cursor
    case openCodeGo
    case kimiCode
    case ollamaCloud
    case zai
    case glmCoding
    case minimax
    case minimaxCN
    case copilot
    case grok
    case grokBot
    case volcengine
    case commandCode
    case deepSeek
    case devin
    case xiaomiMiMo
    case sub2api
    case newAPI
    case v2ex
    case qoder
    case stepFun
    case xai

    // Providers described by a `ProviderProfile`, each in its own file under
    // `Providers/Profiled/`. Every switch below hands them to that profile.
    case clinePass
    case alibabaCodingPlan
    case alibabaTokenPlan
    case qwenCloud
    case factory
    case gemini
    case kiloCode
    case augment
    case jetBrainsAI
    case t3Chat
    case synthetic
    case elevenLabs
    case warp
    case windsurf
    case bifrost
    case chutes
    case longCat
    case zoomMate
    case notionAI
    case ibmBob
    case nousPortal
    case raycastAI
    case gitKraken
    case xKiro
    case abacus
    case moonshot
    case hyper
    case atlasCloud
    case poe
    case venice
    case openAIPlatform
    case amp
    case zed
    case sakana
    case mistral
    case codebuff
    case llmProxy
    case liteLLM
    case aixy
    case neuralwatt
    case clawRouter
    case zenMux
    case v0
    case devPass
    case perplexity
    case manus
    case huggingFace
    case deepInfra
    case xaiAPI
    case replicate
    case typeSafe
    case vercelAIGateway

    /// **Not one provider: every program in the extensions folder.** Each
    /// extension is an account of this one — `AccountKey(.pulseExtension,
    /// slot: <the extension's id>)` — so the rail, the cache, the settings
    /// panes and `--json` carry it the way they carry an added account,
    /// without a case per program. There is never a primary account of it,
    /// and it is left out of `builtIn`, which is what every list of "the
    /// providers" means. See `PulseExtension` and Docs/extensions.md.
    case pulseExtension = "extension"

    /// The providers Pulse ships, which is what the chooser, the defaults and
    /// every "each provider's first account" list are built from.
    static let builtIn = allCases.filter { $0 != .pulseExtension }

    /// The providers written case by case, and the extension type: everything
    /// `Provider` has that is not a `ProviderProfile`. Switches that need a
    /// case-by-case answer switch over this, so a profiled provider —
    /// answered from its profile — is named in none of them. Raw values are
    /// identical to `Provider`'s, which is what lets `handWritten` below be a
    /// plain `init(rawValue:)`.
    enum HandWrittenProvider: String, CaseIterable, Sendable {
        case claudeCode
        case codex
        case openAI
        case kiro
        case antigravity
        case cursor
        case openCodeGo
        case kimiCode
        case ollamaCloud
        case zai
        case glmCoding
        case minimax
        case minimaxCN
        case copilot
        case grok
        case grokBot
        case volcengine
        case commandCode
        case deepSeek
        case devin
        case xiaomiMiMo
        case sub2api
        case newAPI
        case v2ex
        case qoder
        case stepFun
        case xai
        case pulseExtension = "extension"
    }

    /// This provider's hand-written case, or nil when it is answered by a
    /// `ProviderProfile` instead. Exactly one of `handWritten` and `profile`
    /// is non-nil for every case.
    var handWritten: HandWrittenProvider? { HandWrittenProvider(rawValue: rawValue) }

    /// How an account is paid for, which is what Pulse sorts providers by.
    ///
    /// **Two kinds of account, and they want different things from Pulse.** A
    /// subscription sells a plan with limits that turn over on a clock, and
    /// its figure is a percentage the provider states. An API account is
    /// money put in and drawn down by the call, with no allowance at all: its
    /// figure is a balance or a spend, and its ring only exists against a
    /// denominator Pulse watched or the reader typed.
    enum Billing: String, Sendable, CaseIterable {
        case subscription
        case api

        var sectionTitle: String {
            switch self {
            case .subscription:
                return String.localized("Subscription Plans")
            case .api:
                return String.localized("Pay-as-you-go Wallets")
            }
        }
    }

    var billing: Billing {
        if let profile { return profile.billing }
        switch self {
        case .deepSeek, .sub2api, .newAPI, .openAI, .xai: return .api
        default: return .subscription
        }
    }

    var id: String { rawValue }

    /// Product names, left untranslated.
    var displayName: String {
        guard let written = handWritten else { return profile?.displayName ?? rawValue }
        return switch written {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .openAI: "OpenAI"
        case .kiro: "Kiro"
        case .antigravity: "Antigravity"
        case .cursor: "Cursor"
        case .openCodeGo: "OpenCode Go"
        case .kimiCode: "Kimi Code"
        case .ollamaCloud: "Ollama Cloud"
        case .zai: "z.ai"
        case .glmCoding: "Zhipu"
        case .minimax: "MiniMax"
        case .minimaxCN: "MiniMax CN"
        case .copilot: "GitHub Copilot"
        case .grok: "Grok"
        case .grokBot: "Grok Bot"
        case .volcengine: "Volcengine"
        case .commandCode: "Command Code"
        case .deepSeek: "DeepSeek"
        case .devin: "Devin"
        case .xiaomiMiMo: "Xiaomi Coding Plan"
        case .sub2api: "sub2api"
        case .newAPI: "New API"
        case .v2ex: "V2EX"
        case .qoder: "Qoder"
        case .stepFun: "StepFun"
        case .xai: "xAI"
        case .pulseExtension: "Extension"
        }
    }

    /// The parent brand's mark rather than the CLI-specific one — these read
    /// better at ring size and are what people recognise.
    var iconResource: String {
        guard let written = handWritten else { return profile?.iconResource ?? "extension" }
        return switch written {
        case .claudeCode: "claude"
        case .codex, .openAI: "openai"
        case .kiro: "kiro"
        case .antigravity: "antigravity"
        case .cursor: "cursor"
        case .openCodeGo: "opencode"
        case .kimiCode: "kimi"
        case .ollamaCloud: "ollama"
        case .zai, .glmCoding: "zai"
        case .minimax, .minimaxCN: "minimax"
        case .copilot: "github"
        case .grok: "grok"
        case .grokBot, .xai: "xai"
        case .volcengine: "volcengine"
        case .commandCode: "commandcode"
        case .deepSeek: "deepseek"
        case .devin: "devin"
        case .xiaomiMiMo: "xiaomimimo"
        case .sub2api: "sub2api"
        case .newAPI: "newapi"
        case .v2ex: "v2ex"
        case .qoder: "qoder"
        case .stepFun: "stepfun"
        case .pulseExtension: "extension"
        }
    }

    /// Whether this agent leaves transcripts on disk that Pulse can read.
    var keepsLocalTranscripts: Bool {
        guard let written = handWritten else { return false }
        return switch written {
        case .claudeCode, .codex: true
        case .openAI, .kiro, .antigravity, .cursor, .openCodeGo, .kimiCode, .ollamaCloud,
             .zai, .glmCoding, .minimax, .minimaxCN, .copilot, .grok, .grokBot,
             .volcengine, .commandCode, .deepSeek, .devin, .xiaomiMiMo, .sub2api,
             .newAPI, .v2ex, .qoder, .stepFun, .xai, .pulseExtension: false
        }
    }

    /// Whether Pulse can determine that this provider's local agent is in the
    /// middle of a turn.
    var supportsLocalActivity: Bool {
        guard let written = handWritten else { return false }
        return switch written {
        case .claudeCode, .codex, .kiro, .zai, .glmCoding: true
        case .openAI, .antigravity, .cursor, .openCodeGo, .kimiCode, .ollamaCloud,
             .minimax, .minimaxCN, .copilot, .grok, .grokBot, .volcengine,
             .commandCode, .deepSeek, .devin, .xiaomiMiMo,
             .sub2api, .newAPI, .v2ex, .qoder, .stepFun, .xai, .pulseExtension: false
        }
    }

    /// Whether this provider's limits can be drawn as one ring per model group.
    var splitsByModelGroup: Bool { self == .antigravity }

    /// How many rings a split account can produce.
    var modelGroupCount: Int { splitsByModelGroup ? 2 : 1 }

    /// Whether a spending history can be shown for this provider at all.
    var providesHistory: Bool { keepsLocalTranscripts || self == .zai || self == .glmCoding }

    /// Whether the route to this provider's figures is a choice.
    var hasSourceChoice: Bool {
        guard let written = handWritten else { return false }
        return switch written {
        case .claudeCode, .codex, .volcengine, .devin: true
        case .openAI, .kiro, .antigravity, .cursor, .openCodeGo, .kimiCode, .ollamaCloud,
             .zai, .glmCoding, .minimax, .minimaxCN, .copilot, .grok, .grokBot,
             .commandCode, .deepSeek, .xiaomiMiMo, .sub2api, .newAPI, .v2ex, .qoder, .stepFun,
             .xai, .pulseExtension: false
        }
    }

    /// The one route this provider has, named for the settings row.
    var soleRoute: (name: String, note: String)? {
        guard let written = handWritten else { return profile?.soleRoute?() }
        return switch written {
        case .antigravity:
            (String.localized("Antigravity's language server"),
             String.localized("Only while Antigravity is open."))
        case .cursor:
            (String.localized("Cursor's own login"),
             String.localized("Uses the login Cursor already saved."))
        case .grok:
            (String.localized("Grok's own login"),
             String.localized("Uses the login Grok's CLI already saved."))
        case .grokBot:
            (String.localized("Cursor's own login"),
             String.localized("Grok Bot is billed to your Cursor account."))
        case .kiro:
            (String.localized("Kiro CLI ACP"),
             String.localized("Uses Kiro CLI's signed-in session without reading its credentials."))
        case .claudeCode, .codex, .openAI, .openCodeGo, .kimiCode, .ollamaCloud,
             .zai, .glmCoding, .minimax, .minimaxCN, .copilot, .volcengine,
             .commandCode, .deepSeek, .devin, .xiaomiMiMo, .sub2api, .newAPI, .v2ex, .qoder, .stepFun, .xai,
             .pulseExtension:
            nil
        }
    }

    /// Whether Pulse needs an API key from the user for this one.
    var usesAPIKey: Bool {
        if let profile { return profile.credential != .localLogin }
        return [.openAI, .openCodeGo, .kimiCode, .ollamaCloud, .zai, .glmCoding, .minimax, .minimaxCN, .volcengine,
         .commandCode, .deepSeek, .devin, .xiaomiMiMo, .sub2api, .newAPI,
         .v2ex, .qoder, .stepFun, .xai].contains(self)
    }

    /// Whether this Mac can see the thing this provider is billing for.
    var spendingIsWatchedLocally: Bool {
        if let profile { return profile.spendingIsWatchedLocally && !profile.reportsSpendableBalance }
        if reportsSpendableBalance { return false }
        return self != .v2ex
    }

    /// Whether this provider reports a prepaid balance that can be compared
    /// against a figure — so a "warn me below" line is worth offering.
    var reportsSpendableBalance: Bool {
        profile?.reportsSpendableBalance ?? [.deepSeek, .commandCode, .sub2api, .newAPI, .openAI, .xai].contains(self)
    }

    /// Whether this provider is somebody's own deployment, so Pulse has to be
    /// told where it is.
    var usesServerAddress: Bool {
        if let profile { return profile.credential == .keyAndAddress }
        return [.sub2api, .newAPI].contains(self)
    }

    /// Whether the pasted credential is a pair rather than one token.
    var usesKeyPair: Bool { self == .volcengine }

    /// Whether what the user pastes is a browser session rather than an API key.
    var usesSessionCookie: Bool {
        if case .sessionCookie = profile?.credential { return true }
        return [.ollamaCloud, .xiaomiMiMo, .qoder, .stepFun].contains(self)
    }

    /// Whether this provider's credential is read out of a browser rather than
    /// out of another tool's files.
    var readsBrowserStorage: Bool {
        if case .browserStorage = profile?.credential { return true }
        return usesSessionCookie || self == .devin || self == .xai
    }

    /// Whether Pulse holds a credential of its own for this provider.
    var keepsOwnCredential: Bool { usesAPIKey || self == .copilot }
}
