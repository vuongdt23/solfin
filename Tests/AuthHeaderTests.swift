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

    func testHeaderWithToken() {
        let session = ServerSession(serverURL: base, userId: "u1", userName: "admin",
                                    accessToken: "Tok42")
        let client = APIClient(baseURL: base,
                               clientInfo: ClientInfo(deviceId: "DEV1"),
                               session: session)
        XCTAssertTrue(client.authorizationHeaderValue.contains(#"Token="Tok42""#))
    }
}
