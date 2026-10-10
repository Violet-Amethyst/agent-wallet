import Foundation
import SwiftUI
import Testing
@testable import Pulse

@Suite("Wallet snapshot")
struct WalletSnapshotTests {
    @Test("Quota colours follow remaining allowance, including the 50% boundary",
          arguments: [0.0, 0.01, 0.02, 0.24, 0.49, 0.5, 0.5001, 0.68, 1.0])
    func remainingQuotaColour(used: Double) {
        let expected: Color = used >= 1 ? .pulseExhausted : (used < 0.5 ? .pulseGood : .pulseCaution)
        #expect(UsageTint.color(for: used) == expected)
        #expect(UsageTint.color(for: used, isExhausted: true) == .pulseExhausted)
    }

    private static func window(
        _ id: String,
        kind: UsageWindow.Kind,
        used: Double,
        seconds: Int
    ) -> UsageWindow {
        UsageWindow(
            id: id,
            kind: kind,
            scope: nil,
            usedFraction: used,
            windowSeconds: seconds,
            resetsAt: nil
        )
    }

    private static func usage(
        _ provider: Provider,
        windows: [UsageWindow],
        credit: ProviderUsage.CreditAmount? = nil
    ) -> ProviderUsage {
        var reading = ProviderUsage(
            account: AccountKey(provider),
            windows: windows,
            observedAt: Date(),
            state: .live,
            plan: nil,
            creditBalance: credit.map { $0.railText() }
        )
        reading.creditRemaining = credit
        return reading
    }

    @Test("Claude pairs general windows; Codex defaults to the general weekly quota")
    func dualQuotaFromWindowKinds() {
        let claude = WalletAdapter.snapshot(
            from: Self.usage(
                .claudeCode,
                windows: [
                    Self.window("5h", kind: .fiveHour, used: 0, seconds: 5 * 3_600),
                    Self.window("week", kind: .weekly, used: 0.33, seconds: 7 * 86_400)
                ]
            ),
            title: "Claude Code"
        )
        #expect(claude.mode == .dualQuota)
        #expect(claude.showsRemainingOnRing)
        #expect(claude.railCaption == "100%")
        #expect(claude.innerUsedFraction == 0)
        #expect(claude.outerUsedFraction == 0.33)
        #expect(claude.shortQuota?.kind == .fiveHour)
        #expect(claude.longQuota?.kind == .weekly)

        let codex = WalletAdapter.snapshot(
            from: Self.usage(
                .codex,
                windows: [
                    Self.window("5h", kind: .fiveHour, used: 0, seconds: 5 * 3_600),
                    Self.window("week", kind: .weekly, used: 0.33, seconds: 7 * 86_400)
                ]
            ),
            title: "Codex"
        )
        #expect(codex.mode == .singleQuota)
        #expect(codex.showsRemainingOnRing)
        #expect(codex.railCaption == "67%")
        #expect(codex.singleQuota?.kind == .weekly)
    }

    @Test("A single quota window is one ring, remaining on the rail")
    func singleQuotaRemaining() {
        let snapshot = WalletAdapter.snapshot(
            from: Self.usage(
                .cursor,
                windows: [Self.window("week", kind: .weekly, used: 0.2, seconds: 7 * 86_400)]
            ),
            title: "Cursor"
        )
        #expect(snapshot.mode == .singleQuota)
        #expect(snapshot.outerUsedFraction == nil)
        #expect(snapshot.railCaption == "80%")
        #expect(snapshot.showsRemainingOnRing)
    }

    @Test("Prepaid credit without a quota is money, not a fake remaining percentage")
    func prepaidMoney() {
        let snapshot = WalletAdapter.snapshot(
            from: Self.usage(
                .deepSeek,
                windows: [],
                credit: .init(amount: 7.31, currency: "USD")
            ),
            title: "DeepSeek"
        )
        #expect(snapshot.mode == .money(.prepaid))
        #expect(snapshot.showsRemainingOnRing)
        #expect(snapshot.prefersMoneyRingTint)
        #expect(abs((snapshot.innerUsedFraction ?? -1) - 0.9269) < 0.0001)
        #expect(snapshot.railCaption.contains("7.31"))
    }

    @Test("A spend window is period spend, not a cash balance")
    func periodSpendIsNotABalance() {
        let snapshot = WalletAdapter.snapshot(
            from: Self.usage(
                .codex,
                windows: [Self.window("spend", kind: .spend, used: 0.1068, seconds: 30 * 86_400)],
                credit: .init(amount: 100, currency: "USD")
            ),
            title: "OpenAI"
        )
        #expect(snapshot.mode == .money(.periodSpend))
        #expect(snapshot.showsRemainingOnRing == false)
        #expect(snapshot.railCaption.contains("10.68") || snapshot.railCaption.contains("10.6"))
        #expect(!snapshot.railCaption.contains("89"))
    }

    @Test("Weekly without a five-hour window stays a single outer-less ring")
    func longOnlyIsSingle() {
        let snapshot = WalletAdapter.snapshot(
            from: Self.usage(
                .kimiCode,
                windows: [Self.window("month", kind: .monthly, used: 0.4, seconds: 30 * 86_400)]
            ),
            title: "Kimi"
        )
        #expect(snapshot.mode == .singleQuota)
        #expect(snapshot.railCaption == "60%")
    }

    @Test("Cursor with cursorModels and otherModels maps inner ring to Cursor Models and outer ring to Other Models")
    func cursorDualModelRings() {
        let usage = Self.usage(
            .cursor,
            windows: [
                UsageWindow(id: "cursorModels", kind: .monthly, scope: "Cursor Models", usedFraction: 0.08, windowSeconds: 30 * 86_400, resetsAt: nil),
                UsageWindow(id: "otherModels", kind: .monthly, scope: "Other Models", usedFraction: 0.62, windowSeconds: 30 * 86_400, resetsAt: nil)
            ]
        )
        let snapshot = WalletAdapter.snapshot(from: usage, title: "Cursor")
        #expect(snapshot.mode == .dualQuota)
        #expect(snapshot.innerUsedFraction == 0.08)
        #expect(snapshot.outerUsedFraction == 0.62)
        #expect(snapshot.railCaption == "92%")
        #expect(snapshot.shortQuota?.id == "cursorModels")
        #expect(snapshot.longQuota?.id == "otherModels")
    }

    @Test("Cursor respects pinned window for inner ring")
    func cursorPinnedWindow() {
        let usage = Self.usage(
            .cursor,
            windows: [
                UsageWindow(id: "cursorModels", kind: .monthly, scope: "Cursor Models", usedFraction: 0.08, windowSeconds: 30 * 86_400, resetsAt: nil),
                UsageWindow(id: "otherModels", kind: .monthly, scope: "Other Models", usedFraction: 0.62, windowSeconds: 30 * 86_400, resetsAt: nil)
            ]
        )
        let snapshot = WalletAdapter.snapshot(from: usage, title: "Cursor", pinnedWindow: "otherModels")
        #expect(snapshot.mode == .dualQuota)
        #expect(snapshot.innerUsedFraction == 0.62)
        #expect(snapshot.outerUsedFraction == 0.08)
        #expect(snapshot.railCaption == "38%")
        #expect(snapshot.shortQuota?.id == "otherModels")
        #expect(snapshot.longQuota?.id == "cursorModels")
    }

    @Test("Antigravity maps Gemini to inner ring and Claude/GPT to outer ring with weekly/exhausted quotas")
    func antigravityDualModelRings() {
        let usage = Self.usage(
            .antigravity,
            windows: [
                UsageWindow(id: "gemini-5h", kind: .fiveHour, scope: "Gemini", usedFraction: 0.19, windowSeconds: 5 * 3_600, resetsAt: nil),
                UsageWindow(id: "gemini-weekly", kind: .weekly, scope: "Gemini", usedFraction: 0.26, windowSeconds: 7 * 86_400, resetsAt: nil),
                UsageWindow(id: "3p-5h", kind: .fiveHour, scope: "Claude and GPT", usedFraction: 0.0, windowSeconds: 5 * 3_600, resetsAt: nil),
                UsageWindow(id: "3p-weekly", kind: .weekly, scope: "Claude and GPT", usedFraction: 1.0, windowSeconds: 7 * 86_400, resetsAt: nil, isExhausted: true)
            ]
        )
        let snapshot = WalletAdapter.snapshot(from: usage, title: "Antigravity")
        #expect(snapshot.mode == .dualQuota)
        #expect(snapshot.shortQuota?.id == "gemini-weekly")
        #expect(snapshot.longQuota?.id == "3p-weekly")
        #expect(snapshot.innerUsedFraction == 0.26)
        #expect(snapshot.outerUsedFraction == 1.0)
        #expect(snapshot.outerIsSpent == true)
        #expect(snapshot.railCaption == "74%")
    }

    @Test("Antigravity respects pinned window to set Claude/3P as inner ring")
    func antigravityPinnedWindow() {
        let usage = Self.usage(
            .antigravity,
            windows: [
                UsageWindow(id: "gemini-5h", kind: .fiveHour, scope: "Gemini", usedFraction: 0.19, windowSeconds: 5 * 3_600, resetsAt: nil),
                UsageWindow(id: "gemini-weekly", kind: .weekly, scope: "Gemini", usedFraction: 0.26, windowSeconds: 7 * 86_400, resetsAt: nil),
                UsageWindow(id: "3p-5h", kind: .fiveHour, scope: "Claude and GPT", usedFraction: 0.0, windowSeconds: 5 * 3_600, resetsAt: nil),
                UsageWindow(id: "3p-weekly", kind: .weekly, scope: "Claude and GPT", usedFraction: 1.0, windowSeconds: 7 * 86_400, resetsAt: nil, isExhausted: true)
            ]
        )
        let snapshot = WalletAdapter.snapshot(from: usage, title: "Antigravity", pinnedWindow: "3p-weekly")
        #expect(snapshot.mode == .dualQuota)
        #expect(snapshot.shortQuota?.id == "3p-weekly")
        #expect(snapshot.longQuota?.id == "gemini-weekly")
        #expect(snapshot.innerUsedFraction == 1.0)
        #expect(snapshot.outerUsedFraction == 0.26)
        #expect(snapshot.innerIsSpent == true)
        #expect(snapshot.railCaption == "0%")
    }
}

#if DEBUG
@Suite("Wallet fixtures")
struct WalletFixtureTests {
    @Test("DEBUG fixtures cover quota and balance modes")
    func fixtureModes() {
        let modes = WalletFixtures.snapshots.map(\.mode)
        #expect(modes.contains(.dualQuota))
        #expect(modes.contains(.singleQuota))
        #expect(modes.contains(.money(.prepaid)))
        #expect(WalletFixtures.snapshots.allSatisfy { $0.isFixture })
        #expect(WalletFixtures.usages.allSatisfy { WalletFixtures.isFixture($0.account) })
        #expect(WalletFixtures.snapshots.allSatisfy { $0.displayName.localizedCaseInsensitiveContains("fixture") })
        #expect(WalletFixtures.snapshots.first(where: { $0.displayName.hasPrefix("Comfy") })?.iconResource == "comfy")
    }

    @Test("Fixtures reach the rail only with the explicit development argument")
    func fixturesRequireExplicitArgument() {
        #expect(WalletFixtures.isEnabled == CommandLine.arguments.contains("--wallet-fixtures"))
    }

    @Test("Codex fixture is remaining 100% / 67% on inner / outer")
    func codexFixtureRemaining() {
        let codex = WalletFixtures.snapshots.first { $0.mode == .dualQuota }
        #expect(codex?.railCaption == "100%")
        #expect(codex?.shortQuota?.percentText(remaining: true) == "100%")
        #expect(codex?.longQuota?.percentText(remaining: true) == "67%")
    }

    @Test("OpenAI fixture caption is API billing spend")
    func openAIFixtureIsBillingSpend() {
        let openai = WalletFixtures.snapshots.first { $0.displayName.hasPrefix("OpenAI") }
        #expect(openai?.mode == .money(.periodSpend))
        #expect(openai?.railCaption.contains("10.68") == true)
        #expect(openai?.periodSpend?.budgetText == "$100")
        #expect(openai?.extras.contains { $0.title == String.localized("Tokens") } == true)
    }
}
#endif
