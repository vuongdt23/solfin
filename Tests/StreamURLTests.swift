import XCTest
@testable import JellyfinKit

final class StreamURLTests: XCTestCase {
    private func makeClient(token: String? = "TESTTOKEN") -> APIClient {
        let base = URL(string: "http://localhost:8096")!
        let info = ClientInfo(deviceId: "DEV123")
        let session = token.map {
            ServerSession(serverURL: base, userId: "u1", userName: "admin", accessToken: $0)
        }
        return APIClient(baseURL: base, clientInfo: info, session: session)
    }

    func testDirectStreamURLUsesFirstContainerToken() throws {
        let client = makeClient()
        let url = try XCTUnwrap(client.directStreamURL(
            itemId: "ITEM1", mediaSourceId: "MS1",
            container: "mov,mp4,m4a,3gp,3g2,mj2"))
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        // Only the first token becomes the extension — no comma-list in the path.
        XCTAssertEqual(comps.path, "/Videos/ITEM1/stream.mov")
        XCTAssertFalse(comps.path.contains(","))
    }

    func testDirectStreamURLQueryItems() throws {
        let client = makeClient(token: "ABC")
        let url = try XCTUnwrap(client.directStreamURL(
            itemId: "ITEM1", mediaSourceId: "MS1", container: "mkv"))
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let q = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(comps.path, "/Videos/ITEM1/stream.mkv")
        XCTAssertEqual(q["static"], "true")
        XCTAssertEqual(q["mediaSourceId"], "MS1")
        XCTAssertEqual(q["api_key"], "ABC")
    }

    func testDirectStreamURLNoContainer() throws {
        let client = makeClient()
        let url = try XCTUnwrap(client.directStreamURL(
            itemId: "ITEM1", mediaSourceId: "MS1", container: nil))
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)!.path,
                       "/Videos/ITEM1/stream")
    }

    func testPrimaryImageURLNilWithoutTag() throws {
        let client = makeClient()
        let item = try decodeItem(#"{"Id":"i1","Name":"No Image"}"#)
        XCTAssertNil(client.primaryImageURL(for: item))
    }

    func testPrimaryImageURLWithTag() throws {
        let client = makeClient()
        let item = try decodeItem(#"{"Id":"i1","Name":"Movie","ImageTags":{"Primary":"tagABC"}}"#)
        let url = try XCTUnwrap(client.primaryImageURL(for: item, maxHeight: 300))
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let q = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(comps.path, "/Items/i1/Images/Primary")
        XCTAssertEqual(q["tag"], "tagABC")
        XCTAssertEqual(q["fillHeight"], "300")
    }

    private func decodeItem(_ json: String) throws -> BaseItem {
        try JSONDecoder().decode(BaseItem.self, from: Data(json.utf8))
    }
}
