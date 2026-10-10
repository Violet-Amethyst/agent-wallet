import Foundation
import Testing
@testable import Pulse

struct CodexHeadlineTests {
    @Test func cachedSparkIsHiddenAndNeverBecomesGeneralHeadline() {
        let weekly = UsageWindow(id: "codex.primary", kind: .weekly, scope: nil,
            usedFraction: 0.13, windowSeconds: 604800, resetsAt: nil)
        let spark = UsageWindow(id: "codex_bengalfox.primary", kind: .fiveHour,
            scope: "GPT-5.3-Codex-Spark", usedFraction: 0, windowSeconds: 18000, resetsAt: nil)
        let raw = ProviderUsage(account: AccountKey(.codex), windows: [spark, weekly],
            observedAt: Date(timeIntervalSince1970: 100), state: .live, plan: nil, creditBalance: nil)
        let hidden = CodexDisplay.reading(raw, showsSpark: false)
        #expect(hidden.windows == [weekly])
        #expect(hidden.observedAt == raw.observedAt)
        let visible = CodexDisplay.reading(raw, showsSpark: true)
        #expect(visible.windows == [weekly, spark])
        let wallet = WalletAdapter.snapshot(from: visible, title: "Codex")
        #expect(wallet.mode == .singleQuota)
        #expect(wallet.railCaption == "87%")
        #expect(wallet.primaryWindows == [weekly])
    }
    @Test func CodexDefaultsToAccountWideLimit() {
        let general = UsageWindow(id: "general", kind: .weekly, scope: nil,
            usedFraction: 0.12, windowSeconds: 604800, resetsAt: nil)
        let spark = UsageWindow(id: "spark", kind: .fiveHour,
            scope: "GPT-5.3-Codex-Spark", usedFraction: 1,
            windowSeconds: 18000, resetsAt: nil)
        let usage = ProviderUsage(account: AccountKey(.codex),
            windows: [general, spark], observedAt: Date(), state: .live,
            plan: nil, creditBalance: nil)

        #expect(usage.headlineWindow()?.id == "general")
        #expect(usage.secondWindow() == nil)
        #expect(usage.headlineWindow(preferring: "spark")?.id == "spark")
    }
}
