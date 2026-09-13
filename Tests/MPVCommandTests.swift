import XCTest
@testable import PlaybackEngine

final class MPVCommandTests: XCTestCase {

    private func decode(_ data: Data?) throws -> [String: Any] {
        let data = try XCTUnwrap(data)
        // Every IPC line must be newline-terminated.
        XCTAssertEqual(data.last, 0x0A)
        let obj = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(obj as? [String: Any])
    }

    func testEncodeCommandShape() throws {
        let dict = try decode(MPVIPC.encodeCommand(["cycle", "pause"], requestId: 7))
        XCTAssertEqual(dict["request_id"] as? Int, 7)
        let args = try XCTUnwrap(dict["command"] as? [Any])
        XCTAssertEqual(args.count, 2)
        XCTAssertEqual(args[0] as? String, "cycle")
        XCTAssertEqual(args[1] as? String, "pause")
    }

    func testLoadFileArgsWithResume() {
        let args = MPVIPC.loadFileArgs(url: "http://x/stream.mkv", startSeconds: 2165.2)
        XCTAssertEqual(args[0] as? String, "loadfile")
        XCTAssertEqual(args[1] as? String, "http://x/stream.mkv")
        XCTAssertEqual(args[2] as? String, "replace")
        XCTAssertEqual(args[3] as? Int, 0)
        XCTAssertEqual(args[4] as? String, "start=2165")   // truncated to whole seconds
    }

    func testLoadFileArgsNoResume() {
        let zero = MPVIPC.loadFileArgs(url: "u", startSeconds: 0)
        let nilStart = MPVIPC.loadFileArgs(url: "u", startSeconds: nil)
        XCTAssertEqual(zero.count, 3)     // no start= option when position is 0
        XCTAssertEqual(nilStart.count, 3)
    }

    func testObservePropertyEncodes() throws {
        // observe_property command form: ["observe_property", id, name]
        let dict = try decode(MPVIPC.encodeCommand(["observe_property", 1, "time-pos"], requestId: 3))
        let args = try XCTUnwrap(dict["command"] as? [Any])
        XCTAssertEqual(args[0] as? String, "observe_property")
        XCTAssertEqual(args[1] as? Int, 1)
        XCTAssertEqual(args[2] as? String, "time-pos")
    }

    func testAddSubtitleArgsDoNotAutoSelectAndPreserveMetadata() {
        let args = MPVIPC.addSubtitleArgs(
            url: "http://server/sub.srt?api_key=token",
            title: "English SDH", language: "eng")
        XCTAssertEqual(args[0] as? String, "sub-add")
        XCTAssertEqual(args[1] as? String, "http://server/sub.srt?api_key=token")
        XCTAssertEqual(args[2] as? String, "auto")
        XCTAssertEqual(args[3] as? String, "English SDH")
        XCTAssertEqual(args[4] as? String, "eng")
    }
}
