import Foundation

/// OpenAI API Platform billing, deliberately separate from Codex.
///
/// Codex reads ChatGPT/Codex rate-limit windows. OpenAI reads the API
/// Platform Costs API with an Admin Key, so the rail answers "how much has
/// this billing period spent?" — the figure the Platform dashboard can expose
/// programmatically today.
struct OpenAIUsageService: Sendable {
    let adminKey: String?
    let billingTotal: Double?

    private static let costsURL = URL(string: "https://api.openai.com/v1/organization/costs")!
    static let defaultBillingTotal = 100.0

    func fetch(now: Date = Date()) async -> ProviderUsage {
        guard let key = Self.key(from: adminKey) else {
            return .unavailable(.openAI, reason: .apiKeyMissing).recording(.endpoint)
        }

        let period = Self.month(containing: now)
        var components = URLComponents(url: Self.costsURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "start_time", value: String(Int(period.start.timeIntervalSince1970))),
            URLQueryItem(name: "end_time", value: String(Int(now.timeIntervalSince1970))),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: "31"),
        ]

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return .unavailable(.openAI, reason: .unreachable).recording(.endpoint)
        }

        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: break
        case 401, 403: return .unavailable(.openAI, reason: .apiKeyRefused).recording(.endpoint)
        case 429: return .unavailable(.openAI, reason: .rateLimited).recording(.endpoint)
        default: return .unavailable(.openAI, reason: .serverError).recording(.endpoint)
        }

        guard let reply = try? JSONDecoder().decode(CostsReply.self, from: data) else {
            return .unavailable(.openAI, reason: .unreadableReply).recording(.endpoint)
        }

        let (spent, currency) = Self.totalSpend(from: reply)
        let hasBillingTotal = billingTotal != nil
        let budget = Self.budget(from: billingTotal)
        let window = UsageWindow(
            id: "openai.monthly_spend",
            kind: .spend,
            scope: "OpenAI API",
            usedFraction: min(max(spent / budget, 0), 1),
            windowSeconds: Int(period.length),
            resetsAt: period.end,
            estimate: hasBillingTotal ? .yourBudget : nil
        )

        let usage = ProviderUsage(
            account: AccountKey(.openAI),
            windows: [window],
            observedAt: now,
            state: .live,
            plan: "OpenAI API",
            creditBalance: ProviderUsage.CreditAmount(amount: spent, currency: currency).railText(),
            creditRemaining: .init(amount: budget, currency: currency)
        )
        return usage.recording(UsageRoute.endpoint)
    }

    private static func budget(from input: Double?) -> Double {
        guard let input, input.isFinite, input > 0 else { return defaultBillingTotal }
        return input
    }

    private static func key(from input: String?) -> String? {
        let key = input?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else { return nil }
        if key.lowercased().hasPrefix("cookie:") || key.contains(";") { return nil }
        return key
    }

    private static func month(containing date: Date) -> (start: Date, end: Date, length: TimeInterval) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? date.addingTimeInterval(30 * 86_400)
        return (start, end, end.timeIntervalSince(start))
    }

    private static func totalSpend(from reply: CostsReply) -> (Double, String) {
        var currency = "USD"
        let total = reply.data.reduce(0.0) { bucketTotal, bucket in
            bucketTotal + bucket.results.reduce(0.0) { resultTotal, result in
                if let reported = result.amount.currency, !reported.isEmpty {
                    currency = reported.uppercased()
                }
                return resultTotal + max(result.amount.value, 0)
            }
        }
        return (total, currency)
    }

    struct CostsReply: Decodable {
        let data: [Bucket]

        struct Bucket: Decodable {
            let results: [Result]
        }

        struct Result: Decodable {
            let amount: Amount
        }

        struct Amount: Decodable {
            let value: Double
            let currency: String?
        }
    }
}

enum OpenAIBillingPage {
    static func availableBalance(in html: String) -> Double? {
        guard html.count < 5_000_000,
              !html.localizedCaseInsensitiveContains("<!ENTITY")
        else { return nil }

        let text = html
            .replacingOccurrences(of: #"<script[\s\S]*?</script>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<style[\s\S]*?</style>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")

        let patterns = [
            #"API\s+credit\s+balance\s*\$([0-9]+(?:\.[0-9]+)?)"#,
            #"credit\s+balance\s*\$([0-9]+(?:\.[0-9]+)?)"#,
            #"\$([0-9]+(?:\.[0-9]+)?)\s*(?:Auto-reload|Buy credits|Payment methods)"#
        ]
        for pattern in patterns {
            if let value = firstNumber(in: text, matching: pattern) { return value }
        }
        return nil
    }

    private static func firstNumber(in text: String, matching pattern: String) -> Double? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = expression.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return Double(text[valueRange])
    }
}

enum OpenAIPlatformSession {
    /// Retain only cookies scoped to OpenAI's own web login. This is not an API
    /// key: the billing balance visible at platform.openai.com is answered by
    /// the web session, while Admin Keys are for documented organization APIs.
    static func normalize(_ input: String) throws -> String {
        guard !input.unicodeScalars.contains(where: { $0.value < 32 || $0.value > 126 }) else {
            throw OpenAISessionError.invalidCookie
        }
        var header = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if header.lowercased().hasPrefix("cookie:") {
            header = String(header.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }
        guard !header.isEmpty else { throw OpenAISessionError.missingCookie }
        guard header.utf8.count <= 64_000 else { throw OpenAISessionError.invalidCookie }

        let importantFragments = [
            "session",
            "usc_",
            "auth",
            "csrf",
            "oai",
            "cf_",
            "cf-",
            "intercom",
            "stripe"
        ]
        var found: [String] = []
        var seen = Set<String>()
        for pair in header.split(separator: ";") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { throw OpenAISessionError.invalidCookie }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            let lowered = name.lowercased()
            guard importantFragments.contains(where: lowered.contains) else { continue }
            guard !value.isEmpty, !value.contains("\""), !value.contains("\\") else {
                throw OpenAISessionError.invalidCookie
            }
            guard seen.insert(name).inserted else { continue }
            found.append("\(name)=\(value)")
        }
        guard !found.isEmpty else { throw OpenAISessionError.invalidCookie }
        return found.joined(separator: "; ")
    }
}

enum OpenAISessionError: Error {
    case missingCookie
    case invalidCookie
}
