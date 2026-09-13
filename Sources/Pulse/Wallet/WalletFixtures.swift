import Foundation

/// DEBUG / Preview-only wallet samples. Never written to the cache, never
/// shown in Release, never treated as a signed-in account.
enum WalletFixtures {
    static var isEnabled: Bool {
        #if DEBUG
        // Fixtures exercise states that no one account normally has, but
        // placing them beside real providers makes sample dollars and credits
        // look like an account reading. They are opt-in even in DEBUG.
        CommandLine.arguments.contains("--wallet-fixtures")
        #else
        false
        #endif
    }

    static var count: Int { isEnabled ? usages.count : 0 }

    static let slotPrefix = "wallet-fixture"

    static func isFixture(_ account: AccountKey) -> Bool {
        account.slot.hasPrefix(slotPrefix)
    }

    /// ProviderUsage rows the rail can draw without adding Provider cases.
    /// Icons reuse nearby Pulse marks; the title always says "fixture".
    static var usages: [ProviderUsage] {
        #if DEBUG
        [codex, qoder, openAI, deepSeek, comfy]
        #else
        []
        #endif
    }

    static var snapshots: [WalletSnapshot] {
        #if DEBUG
        usages.map { usage in
            switch usage.account.slot {
            case "\(slotPrefix)-qoder": qoderSnapshot(from: usage)
            case "\(slotPrefix)-openai": openAISnapshot(from: usage)
            case "\(slotPrefix)-comfy": comfySnapshot(from: usage)
            default:
                WalletAdapter.snapshot(
                    from: usage,
                    title: usage.plan ?? usage.provider.displayName,
                    isFixture: true
                )
            }
        }
        #else
        []
        #endif
    }

    #if DEBUG
    private static var calendar: Calendar { Calendar(identifier: .gregorian) }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        return calendar.date(from: parts) ?? Date().addingTimeInterval(3_600)
    }

    private static var codex: ProviderUsage {
        ProviderUsage(
            account: AccountKey(.codex, slot: "\(slotPrefix)-codex"),
            windows: [
                UsageWindow(
                    id: "fixture-5h",
                    kind: .fiveHour,
                    scope: nil,
                    usedFraction: 0,
                    windowSeconds: 5 * 3_600,
                    resetsAt: date(2026, 9, 12, 21, 18)
                ),
                UsageWindow(
                    id: "fixture-week",
                    kind: .weekly,
                    scope: nil,
                    usedFraction: 0.33,
                    windowSeconds: 7 * 86_400,
                    resetsAt: date(2026, 9, 10, 18, 46)
                )
            ],
            observedAt: Date(),
            state: .live,
            plan: "Codex · fixture",
            creditBalance: nil
        )
    }

    /// 300 credits remaining, one ring. Not a Pulse provider.
    private static var qoder: ProviderUsage {
        ProviderUsage(
            account: AccountKey(.commandCode, slot: "\(slotPrefix)-qoder"),
            windows: [],
            observedAt: Date(),
            state: .live,
            plan: "Qoder · fixture",
            creditBalance: "300 cr"
        )
    }

    private static var openAI: ProviderUsage {
        ProviderUsage(
            account: AccountKey(.openAI, slot: "\(slotPrefix)-openai"),
            windows: [
                UsageWindow(
                    id: "fixture-openai-spend",
                    kind: .spend,
                    scope: "OpenAI API",
                    usedFraction: 0.1068,
                    windowSeconds: 30 * 86_400,
                    resetsAt: date(2026, 10, 1, 0, 0)
                )
            ],
            observedAt: Date(),
            state: .live,
            plan: "OpenAI API · fixture",
            creditBalance: "$10.68",
            creditRemaining: .init(amount: 100, currency: "USD")
        )
    }

    private static var deepSeek: ProviderUsage {
        var usage = ProviderUsage(
            account: AccountKey(.deepSeek, slot: "\(slotPrefix)-deepseek"),
            windows: [],
            observedAt: Date(),
            state: .live,
            plan: "DeepSeek · fixture",
            creditBalance: "$7.31"
        )
        usage.creditRemaining = .init(amount: 7.31, currency: "USD")
        return usage
    }

    private static var comfy: ProviderUsage {
        var usage = ProviderUsage(
            account: AccountKey(.openCodeGo, slot: "\(slotPrefix)-comfy"),
            windows: [],
            observedAt: Date(),
            state: .live,
            plan: "Comfy · fixture",
            creditBalance: "1,240 cr"
        )
        usage.creditRemaining = .init(amount: 1_240, currency: "USD")
        return usage
    }

    private static func qoderSnapshot(from usage: ProviderUsage) -> WalletSnapshot {
        WalletSnapshot(
            mode: .singleQuota,
            displayName: "Qoder · fixture",
            iconResource: nil,
            shortQuota: nil,
            longQuota: nil,
            singleQuota: nil,
            prepaid: nil,
            creditCount: 300,
            periodSpend: nil,
            extras: [
                .init(
                    title: String.localized("Subscription cycle"),
                    value: String.localized("Resets \("Sep 26")")
                )
            ],
            updatedAt: usage.observedAt,
            isFixture: true
        )
    }

    private static func openAISnapshot(from usage: ProviderUsage) -> WalletSnapshot {
        let spend = usage.windows.first { if case .spend = $0.kind { true } else { false } }
        return WalletSnapshot(
            mode: .money(.periodSpend),
            displayName: "OpenAI API · fixture",
            iconResource: nil,
            shortQuota: nil,
            longQuota: nil,
            singleQuota: nil,
            prepaid: nil,
            creditCount: nil,
            periodSpend: spend.map {
                WalletSnapshot.PeriodSpend(from: $0, credit: usage.creditRemaining)
            },
            extras: [
                .init(title: String.localized("Tokens"), value: "550,225"),
                .init(title: String.localized("Requests"), value: "579")
            ],
            updatedAt: usage.observedAt,
            isFixture: true
        )
    }

    private static func comfySnapshot(from usage: ProviderUsage) -> WalletSnapshot {
        WalletSnapshot(
            mode: .money(.prepaid),
            displayName: "Comfy · fixture",
            iconResource: "comfy",
            shortQuota: nil,
            longQuota: nil,
            singleQuota: nil,
            prepaid: nil,
            creditCount: 1_240,
            periodSpend: nil,
            extras: [],
            updatedAt: usage.observedAt,
            isFixture: true
        )
    }
    #endif
}
