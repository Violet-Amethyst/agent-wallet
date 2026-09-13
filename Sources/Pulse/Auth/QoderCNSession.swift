import CryptoKit
import Foundation

/// Reuses only Qoder's session token across launches, never its Safe Storage
/// master key. Uses the same owner-only encrypted store as entered API keys.
/// Automatic reads must not ask macOS to display authentication UI.
struct QoderCNSession: Sendable {
    var file = PulseStorage.directory.appending(path: "qoder-cn-session.dat")
    var authFile = QoderCNUsageService.authFile
    var seal: @Sendable (Data) -> Data? = { LocalSecrets.seal($0, purpose: "Agent Wallet Qoder CN session v1") }
    var open: @Sendable (Data) -> Data? = { LocalSecrets.open($0, purpose: "Agent Wallet Qoder CN session v1") }
    var readKey: @Sendable (Bool) -> Data? = {
        BrowserCookies.safeStorageKey(service: "Qoder CN App Safe Storage", allowInteraction: $0)
    }

    private struct Saved: Codable {
        let token: String
        let fingerprint: Data
        let savedAt: Date
    }

    func token(allowInteraction: Bool = false, now: Date = Date()) -> String? {
        // No reuse after logout or an account change. The encrypted source is
        // hashed, so neither account identifiers nor a master key are stored.
        guard let encrypted = try? Data(contentsOf: authFile) else { return nil }
        let fingerprint = Data(SHA256.hash(data: encrypted))
        if let blob = try? Data(contentsOf: file), let plain = open(blob),
           let saved = try? JSONDecoder().decode(Saved.self, from: plain),
           saved.fingerprint == fingerprint, !saved.token.isEmpty,
           now >= saved.savedAt, now.timeIntervalSince(saved.savedAt) < 7 * 86400 {
            return saved.token
        }
        guard let key = readKey(allowInteraction),
              let text = BrowserCookies.decrypt(encrypted, with: key),
              let data = text.data(using: .utf8),
              let auth = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = auth["token"] as? String, !token.isEmpty else { return nil }
        let saved = Saved(token: token, fingerprint: fingerprint, savedAt: now)
        if let plain = try? JSONEncoder().encode(saved), let blob = seal(plain) {
            _ = LocalSecrets.write(blob, to: file)
        }
        return token
    }

    func invalidate() {
        // This file contains only the previously imported Qoder session.
        try? FileManager.default.removeItem(at: file)
    }
}
