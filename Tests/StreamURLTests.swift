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

    func testRelativeSubtitleDeliveryURLIsAuthenticated() throws {
        let client = makeClient(token: "ABC")
        let stream = try decodeStream("""
        {"Type":"Subtitle","Index":4,"Codec":"subrip","IsExternal":true,
         "DeliveryMethod":"External",
         "DeliveryUrl":"/Videos/ITEM1/MS1/Subtitles/4/0/Stream.srt"}
        """)
        let url = try XCTUnwrap(client.subtitleURL(
            for: stream, itemId: "ITEM1", mediaSourceId: "MS1"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/Videos/ITEM1/MS1/Subtitles/4/0/Stream.srt")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "api_key" })?.value,
                       "ABC")
    }

    func testAbsoluteThirdPartySubtitleDoesNotLeakToken() throws {
        let client = makeClient(token: "SECRET")
        let stream = try decodeStream("""
        {"Type":"Subtitle","Index":7,"Codec":"ass","IsExternal":true,
         "DeliveryMethod":"External","IsExternalUrl":true,
         "DeliveryUrl":"https://subs.example.test/movie.ass?signature=x"}
        """)
        let url = try XCTUnwrap(client.subtitleURL(
            for: stream, itemId: "ITEM1", mediaSourceId: "MS1"))
        XCTAssertEqual(url.host, "subs.example.test")
        XCTAssertFalse(url.absoluteString.contains("SECRET"))
        XCTAssertFalse(url.absoluteString.contains("api_key"))
    }

    func testExternalSubtitleFallbackUsesCanonicalEndpoint() throws {
        let client = makeClient(token: "ABC")
        let stream = try decodeStream(
            #"{"Type":"Subtitle","Index":9,"Codec":"subrip","IsExternal":true}"#)
        let url = try XCTUnwrap(client.subtitleURL(
            for: stream, itemId: "ITEM1", mediaSourceId: "MS1"))
        XCTAssertEqual(url.path, "/Videos/ITEM1/MS1/Subtitles/9/Stream.srt")
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
        XCTAssertEqual(q["maxHeight"], "300")
        XCTAssertEqual(q["quality"], "96")
    }

    func testOriginalResolutionImageURLsOmitResizeParameters() throws {
        let client = makeClient()
        let item = try decodeItem(#"{"Id":"i1","Name":"Movie","ImageTags":{"Primary":"p"},"BackdropImageTags":["b"]}"#)

        let poster = try XCTUnwrap(client.primaryImageURL(for: item, maxHeight: nil, quality: 100))
        let backdrop = try XCTUnwrap(client.backdropImageURL(for: item, maxWidth: nil))
        let posterQuery = Dictionary(uniqueKeysWithValues: (URLComponents(url: poster, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value) })
        let backdropQuery = Dictionary(uniqueKeysWithValues: (URLComponents(url: backdrop, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertNil(posterQuery["maxHeight"])
        XCTAssertNil(posterQuery["fillHeight"])
        XCTAssertEqual(posterQuery["quality"], "100")
        XCTAssertNil(backdropQuery["maxWidth"])
        XCTAssertEqual(backdropQuery["quality"], "100")
    }

    private func decodeItem(_ json: String) throws -> BaseItem {
        try JSONDecoder().decode(BaseItem.self, from: Data(json.utf8))
    }

    private func decodeStream(_ json: String) throws -> MediaStream {
        try JSONDecoder().decode(MediaStream.self, from: Data(json.utf8))
    }
}
