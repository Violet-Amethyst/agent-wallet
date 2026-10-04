import Foundation
import Testing
@testable import Pulse

@Suite("xAI Platform usage and balance")
struct XAIUsageTests {

    // MARK: - Balance Parsing

    @Test("xAI prepaid balance converts inverted cents to USD")
    func balanceParsingFromInvertedCents() {
        // -500 cents is +$5.00
        #expect(XAIUsageService.parseBalance(from: "-500") == 5.0)
        // -1250 cents is +$12.50
        #expect(XAIUsageService.parseBalance(from: "-1250") == 12.5)
        // 0 cents is $0.00
        #expect(XAIUsageService.parseBalance(from: "0") == 0.0)
        // Positive cents (debt/exhausted) clamps to 0
        #expect(XAIUsageService.parseBalance(from: "500") == 0.0)
        // Whitespace trimmed
        #expect(XAIUsageService.parseBalance(from: "  -2500 \n") == 25.0)
    }

    @Test("Absent or malformed balance returns nil")
    func invalidBalanceReturnsNil() {
        #expect(XAIUsageService.parseBalance(from: nil) == nil)
        #expect(XAIUsageService.parseBalance(from: "") == nil)
        #expect(XAIUsageService.parseBalance(from: "   ") == nil)
        #expect(XAIUsageService.parseBalance(from: "invalid") == nil)
    }

    @Test("xAI parseCents handles positive and negative cent strings to USD")
    func parseCentsFromStrings() {
        #expect(XAIUsageService.parseCents(from: "-125") == 1.25)
        #expect(XAIUsageService.parseCents(from: "125") == 1.25)
        #expect(XAIUsageService.parseCents(from: "0") == 0.0)
        #expect(XAIUsageService.parseCents(from: "  500 \n") == 5.0)
        #expect(XAIUsageService.parseCents(from: nil) == nil)
        #expect(XAIUsageService.parseCents(from: "") == nil)
    }

    @Test("Invoice preview decodes in-cycle usage correctly")
    func invoicePreviewDecoding() throws {
        let json = """
        {
          "coreInvoice": {
            "totalWithCorr": {"val": "125"},
            "prepaidCredits": {"val": "-500"},
            "prepaidCreditsUsed": {"val": "-125"}
          }
        }
        """
        let reply = try JSONDecoder().decode(XAIUsageService.InvoicePreviewReply.self, from: Data(json.utf8))
        let core = try #require(reply.coreInvoice)
        let total = XAIUsageService.parseBalance(from: core.prepaidCredits?.val)
        let used = XAIUsageService.parseCents(from: core.prepaidCreditsUsed?.val)
        #expect(total == 5.0)
        #expect(used == 1.25)
        #expect(max((total ?? 0) - (used ?? 0), 0.0) == 3.75)
    }

    // MARK: - Web Cookie Normalization & Team ID

    @Test("Normalizes cookies and preserves vital authentication tokens")
    func cookieNormalization() {
        let raw = "Cookie: sso=sso_token_123; tracking_id=ignore_me; last-team-id=team-uuid-456; cf_clearance=cf_789; extra=drop"
        let normalized = XAIWebLogin.normalize(raw)
        #expect(normalized != nil)
        #expect(normalized!.contains("sso=sso_token_123"))
        #expect(normalized!.contains("last-team-id=team-uuid-456"))
        #expect(normalized!.contains("cf_clearance=cf_789"))
        #expect(!normalized!.contains("tracking_id"))
        #expect(!normalized!.contains("extra"))
    }

    @Test("Rejects cookie string without sso or sso-rw")
    func rejectsCookieWithoutSSO() {
        let raw = "last-team-id=team-uuid-456; cf_clearance=cf_789"
        #expect(XAIWebLogin.normalize(raw) == nil)
    }

    @Test("Extracts team ID from cookie header")
    func extractsTeamId() {
        let cookie = "sso=abc; last-team-id=e5443b57-7f7b-430f-80a7-3559b8ab8719; cf_clearance=xyz"
        #expect(XAIWebLogin.teamId(from: cookie) == "e5443b57-7f7b-430f-80a7-3559b8ab8719")

        let cookieWithoutTeam = "sso=abc; cf_clearance=xyz"
        #expect(XAIWebLogin.teamId(from: cookieWithoutTeam) == nil)
    }

    // MARK: - Spend History Parsing

    @Test("Parses 30-day spend time series aggregation")
    func spendTimeSeriesParsing() throws {
        let json = """
        {
            "timeSeries": [
                {
                    "dataPoints": [
                        { "timestamp": "2026-03-01T00:00:00Z", "values": [0.45] },
                        { "timestamp": "2026-03-02T00:00:00Z", "values": [1.25] },
                        { "timestamp": "2026-03-03T00:00:00Z", "values": [0.0] }
                    ]
                }
            ],
            "limitReached": false
        }
        """.data(using: .utf8)!

        let reply = try JSONDecoder().decode(XAIUsageService.UsageReply.self, from: json)
        let (total, points) = XAIUsageService.parseSpend(from: reply)

        #expect(abs(total - 1.70) < 0.001)
        #expect(points.count == 2)
        #expect(points[0].value == 0.45)
        #expect(points[1].value == 1.25)
    }

    // MARK: - Provider Metadata & Snapshot

    @Test("xAI provider metadata and configuration")
    func providerMetadata() {
        let p = Provider.xai
        #expect(p.displayName == "xAI")
        #expect(p.iconResource == "xai")
        #expect(p.reportsSpendableBalance == true)
        #expect(p.readsBrowserStorage == true)
        #expect(p.usesAPIKey == true)
        #expect(p.hasSourceChoice == false)
    }

    @Test("WalletSnapshot renders xAI prepaid balance when budget is unset")
    func walletSnapshotPrepaidMode() {
        let usage = ProviderUsage(
            account: AccountKey(.xai),
            windows: [],
            observedAt: Date(),
            state: .live,
            plan: "xAI API",
            creditBalance: "$5.00",
            creditRemaining: .init(amount: 5.0, currency: "USD")
        )

        let snapshot = WalletAdapter.snapshot(from: usage, title: "xAI")
        #expect(snapshot.railCaption == "$5")
        if case .money(.prepaid) = snapshot.mode {
            // expected
        } else {
            Issue.record("Expected mode to be .money(.prepaid), got \(String(describing: snapshot.mode))")
        }
    }

    @Test("WalletSnapshot renders xAI period spend when budget is set")
    func walletSnapshotPeriodSpendMode() {
        let window = UsageWindow(
            id: "xai.30d_spend",
            kind: .spend,
            scope: "xAI API",
            usedFraction: 0.2,
            windowSeconds: 30 * 86_400,
            resetsAt: nil,
            estimate: .yourBudget
        )
        let usage = ProviderUsage(
            account: AccountKey(.xai),
            windows: [window],
            observedAt: Date(),
            state: .live,
            plan: "xAI API",
            creditBalance: "$5.00",
            creditRemaining: .init(amount: 5.0, currency: "USD")
        )

        let snapshot = WalletAdapter.snapshot(from: usage, title: "xAI")
        #expect(snapshot.periodSpendShowsRemaining == true)
        if case .money(.periodSpend) = snapshot.mode {
            // expected
        } else {
            Issue.record("Expected mode to be .money(.periodSpend), got \(String(describing: snapshot.mode))")
        }
    }

    @Test("WalletSnapshot carries extra metrics like monthly spend")
    func walletSnapshotCarriesExtras() {
        var usage = ProviderUsage(
            account: AccountKey(.xai),
            windows: [],
            observedAt: Date(),
            state: .live,
            plan: "xAI API",
            creditBalance: "$7.05",
            creditRemaining: .init(amount: 7.05, currency: "USD")
        )
        usage.extras = [
            .init(title: "Monthly spend", value: "$7.95")
        ]

        let snapshot = WalletAdapter.snapshot(from: usage, title: "xAI")
        #expect(snapshot.extras.count == 1)
        #expect(snapshot.extras[0].title == "Monthly spend")
        #expect(snapshot.extras[0].value == "$7.95")
    }

    @Test("Live Edge session discovery and balance test")
    func liveSessionDiscovery() async {
        guard let session = XAIWebLogin.session() else { return }
        #expect(session.browser == .edge || session.browser == .chrome)
        #expect(session.teamId == "e5443b57-7f7b-430f-80a7-3559b8ab8719")
        let service = XAIUsageService(teamId: session.teamId)
        let usage = await service.fetch()
        #expect(usage.state == .live)
        #expect(usage.creditRemaining?.amount == 5.0)
    }
}
