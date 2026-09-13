import CryptoKit
import Foundation
import Testing
@testable import Pulse

struct QoderSessionTests {
    private func sandbox() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "qoder-session-test-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func session(in directory: URL) -> QoderCNSession {
        let key = SymmetricKey(data: Data(repeating: 42, count: 32))
        return QoderCNSession(file: directory.appending(path: "session.dat"),
            authFile: directory.appending(path: "auth.dat"),
            seal: { try? AES.GCM.seal($0, using: key).combined },
            open: {
                guard let box = try? AES.GCM.SealedBox(combined: $0) else { return nil }
                return try? AES.GCM.open(box, using: key)
            }, readKey: { _ in Data(repeating: 0, count: 16) })
    }

    @Test func relaunchReusesEncryptedSessionWithoutKeychain() throws {
        let directory = try sandbox()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = session(in: directory)
        let now = Date()
        try Data(#"{"token":"test-qoder-session"}"#.utf8).write(to: first.authFile)
        #expect(first.token(allowInteraction: true, now: now) == "test-qoder-session")
        let saved = try Data(contentsOf: first.file)
        #expect(saved.range(of: Data("test-qoder-session".utf8)) == nil)
        let attributes = try FileManager.default.attributesOfItem(atPath: first.file.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        var restarted = session(in: directory)
        restarted.readKey = { _ in
            Issue.record("A relaunch must reuse the session without reading Keychain")
            return nil
        }
        #expect(restarted.token(now: now.addingTimeInterval(60)) == "test-qoder-session")
    }

    @Test func expiredChangedRevokedAndLoggedOutSessionsAreNotReused() throws {
        let directory = try sandbox()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = session(in: directory)
        let now = Date()
        try Data(#"{"token":"test-first-account"}"#.utf8).write(to: first.authFile)
        #expect(first.token(now: now) == "test-first-account")
        var silent = session(in: directory)
        silent.readKey = { allowsUI in
            #expect(!allowsUI, "Background renewal must never prompt")
            return nil
        }
        #expect(silent.token(now: now.addingTimeInterval(7 * 86400)) == nil)
        try Data(#"{"token":"test-other-account"}"#.utf8).write(to: first.authFile)
        #expect(silent.token(now: now) == nil)
        #expect(first.token(now: now) == "test-other-account")
        first.invalidate()
        #expect(silent.token(now: now) == nil)
        #expect(first.token(now: now) == "test-other-account")
        try FileManager.default.removeItem(at: first.authFile)
        #expect(silent.token(now: now) == nil)
    }
}
