import Foundation
import Testing
@testable import Pulse

struct WalletConnectionTests {
    @Test func qoderExhaustion() throws {
        let data = Data(#"{"displayMode":"qoder","qoderUsage":{"userType":"free","expiresAt":1790380800000,"userQuota":{"total":300,"used":300,"percentage":1}}}"#.utf8)
        let usage = QoderCNUsageService.parse(data)
        let window = try #require(usage.windows.first)
        #expect(window.usedFraction == 1)
        #expect(window.isExhausted)
        #expect(usage.creditBalance == "0 cr")
        #expect(window.percentText(remaining: true) == "0%")
        #expect(window.resetsAt == Date(timeIntervalSince1970: 1790380800))
        #expect(!window.reportsLength)
    }

    @Test func malformedQuotaIsNotZero() {
        let data = Data(#"{"displayMode":"qoder","qoderUsage":{"userQuota":{"total":300}}}"#.utf8)
        #expect(QoderCNUsageService.parse(data).state == .unavailable(.unreadableReply))
    }

    @Test func webBalanceKeepsCurrenciesSeparate() throws {
        let data = Data(#"{"code":0,"data":{"biz_code":0,"biz_data":{"normal_wallets":[{"currency":"USD","balance":"0.00"},{"currency":"CNY","balance":90.35}],"bonus_wallets":[]}}}"#.utf8)
        let purses = try #require(DeepSeekUsageService.platformPurses(data))
        #expect(purses.count == 2)
        let selected = try #require(DeepSeekUsageService.purse(from: purses, preferring: nil))
        #expect(selected.currency == "CNY")
        #expect(selected.total == 90.35)
        #expect(DeepSeekUsageService.platformPurses(Data(#"{"code":40003}"#.utf8)) == nil)
    }

    /// Opt-in only: prints balances/status, never credentials or response bodies.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["AGENT_WALLET_LIVE_CHECK"] == "1"))
    func liveConnections() async {
        let deepSeek = await DeepSeekUsageService(enteredKey: nil, basis: .balanceOnly,
            budget: nil, currency: nil).fetch()
        print("DeepSeek: \(deepSeek.state); balance=\(deepSeek.creditBalance ?? "unavailable")")
        #expect(deepSeek.state == .live)
        let qoder = await QoderCNUsageService().fetch()
        print("Quota CN: \(qoder.state); balance=\(qoder.creditBalance ?? "unavailable"); used=\(qoder.windows.first?.usedFraction ?? -1)")
        #expect(qoder.state == .live)
    }
}
