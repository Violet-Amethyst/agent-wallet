import Foundation

/// Qoder CN desktop's own read-only quota endpoint. No API key is needed;
/// Qoder remains responsible for renewing its encrypted login.
struct QoderCNUsageService: Sendable {
    static var authFile: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: "Library/Application Support/com.qodercn.app.stable/auth.v1.dat")
    }

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: authFile.path) }

    func fetch() async -> ProviderUsage {
        let session = QoderCNSession()
        guard let token = session.token() else {
            return .unavailable(.qoderCN, reason: .qoderLoginRequired).recording(.desktopSession)
        }
        var request = URLRequest(url: URL(string: "https://openapi.qoder.com.cn/sash/api/v2/me/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("10", forHTTPHeaderField: "Cosy-ClientType")
        request.setValue("Qoder", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        guard let (reply, response) = try? await URLSession.shared.data(for: request) else {
            return .unavailable(.qoderCN, reason: .unreachable).recording(.endpoint)
        }
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: return Self.parse(reply).recording(.endpoint)
        case 401, 403:
            session.invalidate()
            return .unavailable(.qoderCN, reason: .qoderLoginRequired).recording(.endpoint)
        case 429: return .unavailable(.qoderCN, reason: .rateLimited).recording(.endpoint)
        default: return .unavailable(.qoderCN, reason: .serverError).recording(.endpoint)
        }
    }

    static func parse(_ data: Data, now: Date = Date()) -> ProviderUsage {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["displayMode"] as? String == "qoder",
              let usage = root["qoderUsage"] as? [String: Any] else {
            return .unavailable(.qoderCN, reason: .unreadableReply)
        }
        let expiry = (usage["expiresAt"] as? Double).flatMap { value -> Date? in
            guard value > 0, value.isFinite else { return nil }
            return Date(timeIntervalSince1970: value > 1e12 ? value / 1000 : value)
        }
        var windows: [UsageWindow] = []
        var remaining = 0.0
        for (field, label) in [("userQuota", "Plan credits"), ("addOnQuota", "Add-on credits")] {
            guard let pool = usage[field] as? [String: Any] else { continue }
            guard let total = pool["total"] as? Double, let used = pool["used"] as? Double,
                  total.isFinite, used.isFinite, total >= 0, used >= 0 else {
                return .unavailable(.qoderCN, reason: .unreadableReply)
            }
            if total == 0 { continue }
            remaining += max(0, total - used)
            windows.append(UsageWindow(id: field, kind: .monthly, scope: label,
                usedFraction: used / total, windowSeconds: 30 * 86400,
                resetsAt: field == "userQuota" ? expiry : nil,
                reportsLength: false, isExhausted: used >= total))
        }
        guard !windows.isEmpty else { return .unavailable(.qoderCN, reason: .noLimitsReported) }
        return ProviderUsage(account: AccountKey(.qoderCN), windows: windows,
            observedAt: now, state: .live, plan: nil,
            creditBalance: String(format: "%.0f cr", remaining))
    }
}
