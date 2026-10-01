import Foundation

/// Discovers and normalizes xAI Console web sessions stored in Chromium browsers (Edge, Chrome, etc.).
enum XAIWebLogin {
    struct Session: Sendable {
        let cookie: String
        let teamId: String?
        let browser: BrowserCookies.Browser
    }

    /// Read an existing xAI Console session across installed browsers or a specific browser.
    static func session(browser: BrowserCookies.Browser? = nil) -> Session? {
        let browsers = browser.map { [$0] } ?? BrowserCookies.present()
        let hosts = ["x.ai", "console.x.ai"]
        for host in hosts {
            if let found = BrowserCookies.session(forHost: host, allowing: browsers, keep: normalize) {
                let team = teamId(from: found.header)
                return Session(cookie: found.header, teamId: team, browser: found.browser)
            }
        }
        return nil
    }

    /// Retain essential cookies: sso, sso-rw, last-team-id, cf_clearance.
    static func normalize(_ input: String) -> String? {
        var header = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if header.lowercased().hasPrefix("cookie:") {
            header = String(header.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }
        guard !header.isEmpty else { return nil }

        let important = ["sso", "sso-rw", "last-team-id", "cf_clearance", "__cuid"]
        var pairs: [String] = []
        var seen = Set<String>()
        var hasSSO = false

        for part in header.split(separator: ";") {
            let pair = part.trimmingCharacters(in: .whitespaces)
            guard let eq = pair.firstIndex(of: "=") else { continue }
            let name = String(pair[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(pair[pair.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !value.isEmpty else { continue }
            if important.contains(name) || name.hasPrefix("cf_") {
                if name == "sso" || name == "sso-rw" {
                    hasSSO = true
                }
                if seen.insert(name).inserted {
                    pairs.append("\(name)=\(value)")
                }
            }
        }

        guard hasSSO else { return nil }
        return pairs.joined(separator: "; ")
    }

    static func teamId(from cookieHeader: String) -> String? {
        for part in cookieHeader.split(separator: ";") {
            let pair = part.trimmingCharacters(in: .whitespaces)
            if pair.hasPrefix("last-team-id=") {
                let id = String(pair.dropFirst("last-team-id=".count)).trimmingCharacters(in: .whitespaces)
                if !id.isEmpty && !id.contains(";") && !id.contains(" ") {
                    return id
                }
            }
        }
        return nil
    }
}
