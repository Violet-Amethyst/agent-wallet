import Foundation
import Testing
@testable import Pulse

@Suite("OpenAI API Platform usage")
struct OpenAIUsageServiceTests {
    @Test("Costs expose billing spend")
    func costsExposeBillingSpend() throws {
        let data = Data("""
        {
          "object": "page",
          "data": [
            {
              "object": "bucket",
              "start_time": 1788566400,
              "end_time": 1788652800,
              "results": [
                {
                  "object": "organization.costs.result",
                  "amount": { "value": 4.56, "currency": "usd" }
                }
              ]
            },
            {
              "object": "bucket",
              "start_time": 1788652800,
              "end_time": 1788739200,
              "results": [
                {
                  "object": "organization.costs.result",
                  "amount": { "value": 6.12, "currency": "usd" }
                }
              ]
            }
          ]
        }
        """.utf8)

        let reply = try JSONDecoder().decode(OpenAIUsageService.CostsReply.self, from: data)
        let total = reply.data.flatMap(\.results).reduce(0.0) { $0 + $1.amount.value }

        #expect(abs(total - 10.68) < 0.000_001)
    }

    @Test("Billing overview page exposes the API credit balance")
    func billingPageBalanceIsAvailableMoney() throws {
        let html = """
        <main>
          <h1>Billing</h1>
          <section>
            <div>Pay as you go</div>
            <div>API credit balance</div>
            <div>$9.32</div>
            <div>Auto-reload is OFF</div>
          </section>
        </main>
        """

        #expect(OpenAIBillingPage.availableBalance(in: html) == 9.32)
    }

    @Test("Unified session cookies are retained")
    func unifiedSessionCookieIsKept() throws {
        let header = [
            "usc_example=live-session",
            "unrelated=value",
            "oai-client-auth-info=client",
            "unified_session_manifest=manifest",
        ].joined(separator: "; ")

        let normalized = try OpenAIPlatformSession.normalize(header)

        #expect(normalized.contains("usc_example=live-session"))
        #expect(normalized.contains("unified_session_manifest=manifest"))
        #expect(!normalized.contains("unrelated=value"))
    }
}
