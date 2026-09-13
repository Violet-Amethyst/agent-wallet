import Foundation
import SwiftUI
import Testing
@testable import Pulse

@Suite("Wallet snapshot")
struct WalletSnapshotTests {
    @Test("Quota colours follow remaining allowance, including the 50% boundary",
          arguments: [0.0, 0.01, 0.02, 0.24, 0.5, 0.5001, 0.68, 1.0])
    func remainingQuotaColour(used: Double) {
        let expected: Color = used >= 1 ? .pulseExhausted : (used <= 0.5 ? .pulseGood : .pulseCaution)
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
