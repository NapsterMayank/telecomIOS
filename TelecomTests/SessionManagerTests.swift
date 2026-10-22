import XCTest
@testable import Learning

final class InMemoryKeychain: KeychainManaging {
    private var store: [String: String] = [:]

    func set(_ value: String, forKey key: String) throws {
        store[key] = value
    }

    func string(forKey key: String) throws -> String? {
        store[key]
    }

    func delete(forKey key: String) throws {
        store.removeValue(forKey: key)
    }

    func deleteAll(matchingPrefix prefix: String) throws {
        store = store.filter { !$0.key.hasPrefix(prefix) }
    }
}

final class SessionManagerTests: XCTestCase {
    func testSaveAndClearSession() throws {
        let keychain = InMemoryKeychain()
        let session = SessionManager(keychain: keychain)

        try session.saveSession(token: "token-123", username: "shost")
        XCTAssertEqual(session.accessToken, "token-123")
        XCTAssertEqual(session.username, "shost")
        XCTAssertTrue(session.isLoggedIn)

        session.logout()
        XCTAssertNil(session.accessToken)
        XCTAssertNil(session.username)
        XCTAssertFalse(session.isLoggedIn)
    }
}
