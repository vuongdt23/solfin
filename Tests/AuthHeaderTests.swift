import XCTest
@testable import JellyfinKit

final class AuthHeaderTests: XCTestCase {
    private let base = URL(string: "http://localhost:8096")!

    func testHeaderWithoutToken() {
        let client = APIClient(baseURL: base,
                               clientInfo: ClientInfo(client: "solfin", device: "Mac",
                                                      deviceId: "DEV1", version: "1.2.3"))
        let h = client.authorizationHeaderValue
        XCTAssertTrue(h.hasPrefix("MediaBrowser "))
        XCTAssertTrue(h.contains(#"Client="solfin""#))
        XCTAssertTrue(h.contains(#"Device="Mac""#))
        XCTAssertTrue(h.contains(#"DeviceId="DEV1""#))
        XCTAssertTrue(h.contains(#"Version="1.2.3""#))
        XCTAssertFalse(h.contains("Token="))
    }

    func testSessionIdentitySeparatesServersAndNormalizesURLs() {
        let first = ServerSession(serverURL: URL(string: "HTTP://Media.Example:80/library/")!,
                                  userId: "u1", userName: "user", accessToken: "one")
        let equivalent = ServerSession(serverURL: URL(string: "http://media.example/library")!,
                                       userId: "u1", userName: "user", accessToken: "two")
        let anotherServer = ServerSession(serverURL: URL(string: "http://other.example/library")!,
                                          userId: "u1", userName: "user", accessToken: "three")

        XCTAssertEqual(first.id, equivalent.id)
        XCTAssertNotEqual(first.id, anotherServer.id)
    }

    func testCredentialStoreKeepsTokensPerServerForSameUser() throws {
        let suite = "CredentialStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CredentialStore(defaults: defaults)
        let userId = "credential-test-\(UUID().uuidString)"
        let first = ServerSession(serverURL: URL(string: "http://192.0.2.1:8096")!,
                                  userId: userId, userName: "user", accessToken: "token-first")
        let second = ServerSession(serverURL: URL(string: "http://192.0.2.2:8096")!,
                                   userId: userId, userName: "user", accessToken: "token-second")
        defer {
            store.remove(first)
            store.remove(second)
        }

        try store.save(first)
        try store.save(second)

        let reloaded = CredentialStore(defaults: defaults)
        let sessions = reloaded.loadSessions()
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.first(where: { $0.id == first.id })?.accessToken, "token-first")
        XCTAssertEqual(sessions.first(where: { $0.id == second.id })?.accessToken, "token-second")
        XCTAssertEqual(reloaded.loadSession()?.id, second.id)
    }

    func testHeaderWithToken() {
        let session = ServerSession(serverURL: base, userId: "u1", userName: "admin",
                                    accessToken: "Tok42")
        let client = APIClient(baseURL: base,
                               clientInfo: ClientInfo(deviceId: "DEV1"),
                               session: session)
        XCTAssertTrue(client.authorizationHeaderValue.contains(#"Token="Tok42""#))
    }
}
