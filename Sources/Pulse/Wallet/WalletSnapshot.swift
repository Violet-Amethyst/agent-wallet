import Foundation

/// Wallet-facing reading for one rail slot.
///
/// Pulse still fetches `ProviderUsage`. Agent Wallet decides what that means
/// — remaining vs used, short vs long, quota vs money — here, so the rail is
/// not locked to Pulse's "tightest window on the outer ring" rule.
struct WalletSnapshot: Equatable, Sendable {
    /// Money-balance rails use a simple fixed face value: one full loop means
    /// 100 units of the displayed currency remain. A ¥90.07 DeepSeek balance
    /// therefore draws a 90.07% remaining arc, leaving the small used gap the
    /// user expects to see at a glance.
    private static let prepaidMoneyFullRingAmount = 100.0

    enum Mode: Equatable, Sendable {
        /// Short inner ring + long outer ring, both remaining.
        case dualQuota
        /// One quota ring, remaining.
        case singleQuota
        /// Prepaid cash/credits, or a period spend against a budget.
        case money(MoneyKind)
    }

    enum MoneyKind: Equatable, Sendable {
        /// Cash or credits sitting in an account. DeepSeek, plus preview-only
        /// adapters until a provider has a verified account route.
        case prepaid
        /// Spend so far against a budget. OpenAI Admin is this, not a balance.
        case periodSpend
    }

    struct ExtraMetric: Equatable, Sendable {
        let title: String
        let value: String
    }

    struct PeriodSpend: Equatable, Sendable {
        let spent: Double
        let budget: Double
        let currency: String
        /// Shorter period inside the budget, when the provider reports one.
        let secondarySpent: Double?
        let secondaryTitle: String?

        var usedFraction: Double {
            guard budget > 0, budget.isFinite, spent.isFinite else { return 0 }
            return min(max(spent / budget, 0), 1)
        }

        var spentText: String {
            if currency.isEmpty {
                return UsageWindow(
                    id: "spend",
                    kind: .spend,
                    scope: nil,
                    usedFraction: usedFraction,
                    windowSeconds: 1,
                    resetsAt: nil
                ).percentText(remaining: false)
            }
            return ProviderUsage.CreditAmount(amount: spent, currency: currency).railText()
        }

        var budgetText: String {
            ProviderUsage.CreditAmount(amount: budget, currency: currency).railText()
        }

        var remainingText: String {
            ProviderUsage.CreditAmount(amount: max(budget - spent, 0), currency: currency).railText()
        }
    }

    let mode: Mode
    let displayName: String
    /// Optional resource override for preview-only or future providers whose
    /// Pulse backing case is only a temporary adapter (for example Comfy).
    let iconResource: String?
    /// Inner ring: 5h / session. Nil when this is not a dual quota.
    let shortQuota: UsageWindow?
    /// Outer ring: weekly / monthly. Nil when this is not a dual quota.
    let longQuota: UsageWindow?
    /// The only quota ring when `mode == .singleQuota`.
    let singleQuota: UsageWindow?
    let prepaid: ProviderUsage.CreditAmount?
    /// Remaining credits with no ISO currency, e.g. "300 cr".
    let creditCount: Int?
    let periodSpend: PeriodSpend?
    let extras: [ExtraMetric]
    let updatedAt: Date?
    /// Whether `periodSpend` is interpreted as “spend against budget” (used
    /// fraction) or “remaining budget” (remaining fraction).
    let periodSpendShowsRemaining: Bool
    /// True for DEBUG/Preview samples. Never persisted.
    let isFixture: Bool

    init(
        mode: Mode,
        displayName: String,
        iconResource: String?,
        shortQuota: UsageWindow?,
        longQuota: UsageWindow?,
        singleQuota: UsageWindow?,
        prepaid: ProviderUsage.CreditAmount?,
        creditCount: Int?,
        periodSpend: PeriodSpend?,
        extras: [ExtraMetric],
        updatedAt: Date?,
        periodSpendShowsRemaining: Bool = false,
        isFixture: Bool
    ) {
        self.mode = mode
        self.displayName = displayName
        self.iconResource = iconResource
        self.shortQuota = shortQuota
        self.longQuota = longQuota
        self.singleQuota = singleQuota
        self.prepaid = prepaid
        self.creditCount = creditCount
        self.periodSpend = periodSpend
        self.extras = extras
        self.updatedAt = updatedAt
        self.periodSpendShowsRemaining = periodSpendShowsRemaining
        self.isFixture = isFixture
    }

    /// What the rail prints under the ring: short remaining only.
    var railCaption: String {
        switch mode {
        case .dualQuota:
            return (shortQuota ?? longQuota)?.percentText(remaining: true) ?? "—"
        case .singleQuota:
            if let creditCount {
                return "\(creditCount) cr"
            }
            if let singleQuota {
                return singleQuota.percentText(remaining: true)
            }
            return prepaid?.railText() ?? "—"
        case .money(.prepaid):
            if let creditCount { return "\(creditCount) cr" }
            return prepaid?.railText() ?? "—"
        case .money(.periodSpend):
            guard let periodSpend else { return "—" }
            return periodSpendShowsRemaining ? periodSpend.remainingText : periodSpend.spentText
        }
    }

    /// Inner (or only) usage fraction, still counted as used so tint stays
    /// "how close to empty". The arc itself is flipped to remaining in the view.
    var innerUsedFraction: Double? {
        switch mode {
        case .dualQuota: shortQuota?.usedFraction
        case .singleQuota: singleQuota?.usedFraction
        case .money(.prepaid): prepaidMoneyUsedFraction
        case .money(.periodSpend): periodSpend?.usedFraction
        }
    }

    /// Outer long-quota usage. Nil draws a single ring.
    var outerUsedFraction: Double? {
        guard mode == .dualQuota else { return nil }
        return longQuota?.usedFraction
    }

    var innerIsSpent: Bool {
        switch mode {
        case .money(.prepaid):
            prepaidMoneyUsedFraction.map { $0 >= 1 } ?? false
        default:
            UsageTint.isSpent(shortQuota ?? singleQuota)
        }
    }

    var outerIsSpent: Bool { UsageTint.isSpent(longQuota) }

    /// Quota rows the hover card should lead with: short, then long.
    var primaryWindows: [UsageWindow] {
        switch mode {
        case .dualQuota:
            return [shortQuota, longQuota].compactMap { $0 }
        case .singleQuota:
            return [singleQuota].compactMap { $0 }
        case .money:
            return []
        }
    }

    /// Remaining is the rail language except for period spend, which can be
    /// interpreted from either side.
    var showsRemainingOnRing: Bool {
        if case .money(.periodSpend) = mode { return periodSpendShowsRemaining }
        return true
    }

    /// Currency balances are shown with a money-coloured ring instead
    /// of the quota traffic-light tint.
    var prefersMoneyRingTint: Bool {
        if case .money = mode, (prepaid != nil || periodSpend != nil) { return true }
        return false
    }

    var hasReading: Bool {
        switch mode {
        case .dualQuota: shortQuota != nil || longQuota != nil
        case .singleQuota: singleQuota != nil || prepaid != nil || creditCount != nil
        case .money(.prepaid): prepaid != nil || creditCount != nil
        case .money(.periodSpend): periodSpend != nil
        }
    }

    private var prepaidMoneyUsedFraction: Double? {
        guard case .money(.prepaid) = mode,
              let amount = prepaid?.amount,
              amount.isFinite
        else { return nil }
        let remaining = min(max(amount / Self.prepaidMoneyFullRingAmount, 0), 1)
        return 1 - remaining
    }
}

/// Turns a Pulse reading into a wallet snapshot using window kinds, not
/// `if provider == .codex`.
enum WalletAdapter {
    /// Windows shorter than this count as the inner (session) ring.
    private static let shortCeiling = 12 * 3_600

    static func snapshot(
        from usage: ProviderUsage,
        title: String,
        isFixture: Bool = false,
        pinnedWindow: String? = nil
    ) -> WalletSnapshot {
        if usage.provider == .codex, !isFixture, usage.windows.contains(where: isQuota) {
            return WalletSnapshot(
                mode: .singleQuota, displayName: title, iconResource: nil,
                shortQuota: nil, longQuota: nil,
                singleQuota: usage.headlineWindow(preferring: pinnedWindow),
                prepaid: nil, creditCount: nil, periodSpend: nil, extras: [],
                updatedAt: usage.observedAt, isFixture: isFixture
            )
        }
        let quotas = usage.windows.filter(isQuota)
        let short = quotas.filter(isShort).min { $0.windowSeconds < $1.windowSeconds }
        let long = quotas.filter(isLong).max { $0.windowSeconds < $1.windowSeconds }
        let spendWindows = usage.windows.filter { if case .spend = $0.kind { true } else { false } }

        if let short, let long, short.id != long.id {
            return WalletSnapshot(
                mode: .dualQuota,
                displayName: title,
                iconResource: nil,
                shortQuota: short,
                longQuota: long,
                singleQuota: nil,
                prepaid: usage.creditRemaining,
                creditCount: nil,
                periodSpend: nil,
                extras: [],
                updatedAt: usage.observedAt,
                periodSpendShowsRemaining: false,
                isFixture: isFixture
            )
        }

        if let quota = short ?? long ?? quotas.first {
            return WalletSnapshot(
                mode: .singleQuota,
                displayName: title,
                iconResource: nil,
                shortQuota: nil,
                longQuota: nil,
                singleQuota: quota,
                prepaid: usage.creditRemaining,
                creditCount: nil,
                periodSpend: nil,
                extras: [],
                updatedAt: usage.observedAt,
                periodSpendShowsRemaining: false,
                isFixture: isFixture
            )
        }

        if let spend = spendWindows.first {
            let showsRemaining = usage.provider == .openAI && spend.estimate == .yourBudget
            return WalletSnapshot(
                mode: .money(.periodSpend),
                displayName: title,
                iconResource: nil,
                shortQuota: nil,
                longQuota: nil,
                singleQuota: nil,
                prepaid: nil,
                creditCount: nil,
                periodSpend: WalletSnapshot.PeriodSpend(
                    from: spend,
                    credit: usage.creditRemaining
                ),
                extras: [],
                updatedAt: usage.observedAt,
                periodSpendShowsRemaining: showsRemaining,
                isFixture: isFixture
            )
        }

        return WalletSnapshot(
            mode: .money(.prepaid),
            displayName: title,
            iconResource: nil,
            shortQuota: nil,
            longQuota: nil,
            singleQuota: nil,
            prepaid: usage.creditRemaining,
            creditCount: nil,
            periodSpend: nil,
            extras: [],
            updatedAt: usage.observedAt,
            periodSpendShowsRemaining: false,
            isFixture: isFixture
        )
    }

    private static func isQuota(_ window: UsageWindow) -> Bool {
        switch window.kind {
        case .fiveHour, .weekly, .monthly, .other: true
        case .spend, .balance: false
        }
    }

    private static func isShort(_ window: UsageWindow) -> Bool {
        switch window.kind {
        case .fiveHour: true
        case .other(let seconds): seconds <= shortCeiling
        case .weekly, .monthly, .spend, .balance: false
        }
    }

    private static func isLong(_ window: UsageWindow) -> Bool {
        switch window.kind {
        case .weekly, .monthly: true
        case .other(let seconds): seconds > shortCeiling
        case .fiveHour, .spend, .balance: false
        }
    }
}

extension WalletSnapshot.PeriodSpend {
    /// Pulse spend windows only carry a fraction. Absolute dollars, when we
    /// have them, come from fixtures or from `creditRemaining` as a budget.
    init(from window: UsageWindow, credit: ProviderUsage.CreditAmount?) {
        if let credit, credit.amount > 0 {
            self.init(
                spent: window.usedFraction * credit.amount,
                budget: credit.amount,
                currency: credit.currency,
                secondarySpent: nil,
                secondaryTitle: nil
            )
        } else {
            self.init(
                spent: window.usedFraction,
                budget: 1,
                currency: "",
                secondarySpent: nil,
                secondaryTitle: nil
            )
        }
    }
}
