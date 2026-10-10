import Foundation
import SweetCookieKit

/// Reads only the DeepSeek platform origin and its userToken key. Credentials
/// stay in memory and are sent only to platform.deepseek.com.
enum DeepSeekWebLogin {
    static func tokens() -> [String] {
        let root = URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: "Library/Application Support/Google/Chrome")
        let profiles = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil)) ?? []
        return Array(Set(profiles.filter {
            $0.lastPathComponent == "Default" || $0.lastPathComponent.hasPrefix("Profile ")
        }.compactMap { profile in
            ChromiumLocalStorageReader.readEntries(
                for: "https://platform.deepseek.com",
                in: profile.appending(path: "Local Storage/leveldb")
            ).first(where: { $0.key == "userToken" }).flatMap { token(from: $0.value) }
        }))
    }

    static func token(from raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = value.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) {
            if let string = object as? String { value = string }
            else if let fields = object as? [String: Any] {
                guard let string = ["value", "token", "access_token", "accessToken", "userToken"]
                    .compactMap({ fields[$0] as? String }).first else { return nil }
                value = string
            } else { return nil }
        }
        return value.count >= 20 && !value.contains(where: \.isWhitespace) ? value : nil
    }
}
