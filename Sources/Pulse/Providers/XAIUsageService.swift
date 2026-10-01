import Foundation

/// Reads the xAI Developer Platform prepaid balance and usage.
///
/// Distinct from consumer Grok (CLI / SuperGrok) and Grok Bot (Cursor):
/// xAI tracks developer platform prepaid credits and usage via the documented
/// Management API:
///   GET  https://management-api.x.ai/v1/billing/teams/{team_id}/prepaid/balance
///   POST https://management-api.x.ai/v1/billing/teams/{team_id}/usage
///
/// Authentication accepts:
/// 1. A Management API Key (Bearer token) generated at console.x.ai -> Settings -> Management Keys.
/// 2. Or a signed-in browser session (Edge / Chrome) with `sso` and `last-team-id` cookies.
struct XAIUsageService: Sendable {
    let managementKey: String?
    let teamId: String?
    let budget: Double?
    let browser: BrowserCookies.Browser?

    private static let baseURL = "https://management-api.x.ai/v1/billing/teams"

    init(
        managementKey: String? = nil,
        teamId: String? = nil,
        budget: Double? = nil,
        browser: BrowserCookies.Browser? = nil
    ) {
        self.managementKey = managementKey
        self.teamId = teamId
        self.budget = budget
        self.browser = browser
    }

    func fetch(now: Date = Date()) async -> ProviderUsage {
        let trimmedKey = managementKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasDirectKey = trimmedKey != nil && !trimmedKey!.isEmpty

        // Check if entered key is a cookie string
        let isCookieKey = hasDirectKey && (trimmedKey!.contains("sso=") || trimmedKey!.lowercased().hasPrefix("cookie:"))

        let authHeader: (name: String, value: String)?
        let effectiveTeamId: String
        let route: UsageRoute

        if hasDirectKey && !isCookieKey {
            authHeader = ("Authorization", "Bearer \(trimmedKey!)")
            effectiveTeamId = teamId?.trimmingCharacters(in: .whitespacesAndNewlines).nilWhenEmpty ?? "default"
            route = .endpoint
        } else if let cookie = isCookieKey ? XAIWebLogin.normalize(trimmedKey!) : nil {
            authHeader = ("Cookie", cookie)
            effectiveTeamId = teamId?.trimmingCharacters(in: .whitespacesAndNewlines).nilWhenEmpty
                ?? XAIWebLogin.teamId(from: cookie)
                ?? "default"
            route = .webSession
        } else if let session = XAIWebLogin.session(browser: browser) {
            authHeader = ("Cookie", session.cookie)
            effectiveTeamId = teamId?.trimmingCharacters(in: .whitespacesAndNewlines).nilWhenEmpty
                ?? session.teamId
                ?? "default"
            route = .webSession
        } else {
            return .unavailable(.xai, reason: .xaiWebLoginRequired).recording(.endpoint)
        }

        guard let auth = authHeader else {
            return .unavailable(.xai, reason: .xaiWebLoginRequired).recording(.endpoint)
        }

        guard let balanceURL = URL(string: "\(Self.baseURL)/\(effectiveTeamId)/prepaid/balance") else {
            return .unavailable(.xai, reason: .unreadableReply).recording(route)
        }

        var balanceReq = URLRequest(url: balanceURL)
        balanceReq.timeoutInterval = 15
        balanceReq.setValue(auth.value, forHTTPHeaderField: auth.name)
        balanceReq.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await NetworkSession.shared.data(for: balanceReq) else {
            return .unavailable(.xai, reason: .unreachable).recording(route)
        }

        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        case 401, 403:
            let reason: ProviderUsage.Unavailability = (route == .webSession) ? .xaiWebLoginRequired : .apiKeyRefused
            return .unavailable(.xai, reason: reason).recording(route)
        case 404: return .unavailable(.xai, reason: .serverError).recording(route)
        case 429: return .unavailable(.xai, reason: .rateLimited).recording(route)
        default: return .unavailable(.xai, reason: .serverError).recording(route)
        }

        guard let reply = try? JSONDecoder().decode(BalanceReply.self, from: data),
              let balanceUSD = Self.parseBalance(from: reply.total?.val) else {
            return .unavailable(.xai, reason: .unreadableReply).recording(route)
        }

        // Deduct in-cycle usage from invoice preview if available, as /prepaid/balance
        // total reflects cumulative top-up deposits without in-cycle usage deductions.
        async let invoiceTask = fetchInvoicePreview(teamId: effectiveTeamId, auth: auth)
        async let spendTask = fetchSpendHistory(teamId: effectiveTeamId, auth: auth, now: now)

        let (invoicePrepaid, invoiceUsed) = await invoiceTask
        let (spend30d, _) = await spendTask

        let totalDeposit = invoicePrepaid ?? balanceUSD
        let usedCredits = invoiceUsed ?? 0.0
        let effectiveBalance = max(totalDeposit - usedCredits, 0.0)

        let windows: [UsageWindow]
        if let budget, budget > 0 {
            let window = UsageWindow(
                id: "xai.30d_spend",
                kind: .spend,
                scope: "xAI API",
                usedFraction: min(max(spend30d / budget, 0), 1),
                windowSeconds: 30 * 86_400,
                resetsAt: nil,
                estimate: .yourBudget
            )
            windows = [window]
        } else {
            windows = []
        }

        let usage = ProviderUsage(
            account: AccountKey(.xai),
            windows: windows,
            observedAt: now,
            state: .live,
            plan: "xAI API",
            creditBalance: ProviderUsage.CreditAmount(amount: effectiveBalance, currency: "USD").railText(),
            creditRemaining: .init(amount: effectiveBalance, currency: "USD")
        )

        return usage.recording(route)
    }

    private func fetchInvoicePreview(teamId: String, auth: (name: String, value: String)) async -> (prepaidTotal: Double?, prepaidUsed: Double?) {
        guard let url = URL(string: "\(Self.baseURL)/\(teamId)/postpaid/invoice/preview") else { return (nil, nil) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue(auth.value, forHTTPHeaderField: auth.name)
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await NetworkSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let reply = try? JSONDecoder().decode(InvoicePreviewReply.self, from: data),
              let core = reply.coreInvoice else {
            return (nil, nil)
        }

        let total = Self.parseBalance(from: core.prepaidCredits?.val)
        let used = Self.parseCents(from: core.prepaidCreditsUsed?.val)
            ?? core.totalWithCorr?.val.flatMap(Self.parseCents)
        return (total, used)
    }

    private func fetchSpendHistory(teamId: String, auth: (name: String, value: String), now: Date) async -> (Double, [UsagePoint]) {
        guard let url = URL(string: "\(Self.baseURL)/\(teamId)/usage") else { return (0, []) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue(auth.value, forHTTPHeaderField: auth.name)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let start = now.addingTimeInterval(-29 * 86_400)
        let bodyJSON: [String: Any] = [
            "analyticsRequest": [
                "timeRange": [
                    "startTime": formatter.string(from: start),
                    "endTime": formatter.string(from: now),
                    "timezone": "Etc/GMT"
                ],
                "timeUnit": "TIME_UNIT_DAY",
                "values": [
                    ["name": "usd", "aggregation": "AGGREGATION_SUM"]
                ]
            ]
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyJSON) else { return (0, []) }
        req.httpBody = bodyData

        guard let (data, response) = try? await NetworkSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let reply = try? JSONDecoder().decode(UsageReply.self, from: data) else {
            return (0, [])
        }

        return Self.parseSpend(from: reply)
    }

    static func parseBalance(from val: String?) -> Double? {
        guard let totalStr = val?.trimmingCharacters(in: .whitespacesAndNewlines),
              let rawCents = Double(totalStr),
              rawCents.isFinite else {
            return nil
        }
        // xAI ledger is inverted cents: -500 val means +$5.00 balance
        return max(-rawCents / 100.0, 0.0)
    }

    static func parseSpend(from reply: UsageReply) -> (Double, [UsagePoint]) {
        var total = 0.0
        var points: [UsagePoint] = []
        for series in reply.timeSeries ?? [] {
            for dp in series.dataPoints ?? [] {
                if let val = dp.values?.first, val.isFinite, val > 0 {
                    total += val
                    points.append(UsagePoint(timestamp: dp.timestamp ?? "", value: val))
                }
            }
        }
        return (total, points)
    }

    static func parseCents(from val: String?) -> Double? {
        guard let str = val?.trimmingCharacters(in: .whitespacesAndNewlines),
              let cents = Double(str),
              cents.isFinite else {
            return nil
        }
        return abs(cents) / 100.0
    }

    struct UsagePoint: Sendable {
        let timestamp: String
        let value: Double
    }

    struct BalanceReply: Decodable {
        struct Total: Decodable {
            let val: String?
        }
        let total: Total?
    }

    struct InvoicePreviewReply: Decodable {
        struct CoreInvoice: Decodable {
            struct Value: Decodable {
                let val: String?
            }
            let prepaidCredits: Value?
            let prepaidCreditsUsed: Value?
            let totalWithCorr: Value?
        }
        let coreInvoice: CoreInvoice?
    }

    struct UsageReply: Decodable {
        struct Series: Decodable {
            struct DataPoint: Decodable {
                let timestamp: String?
                let values: [Double]?
            }
            let dataPoints: [DataPoint]?
        }
        let timeSeries: [Series]?
        let limitReached: Bool?
    }
}

private extension String {
    var nilWhenEmpty: String? { isEmpty ? nil : self }
}
