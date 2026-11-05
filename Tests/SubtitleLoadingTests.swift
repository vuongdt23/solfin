import XCTest
@testable import JellyfinKit
@testable import PlaybackEngine

final class SubtitleLoadingTests: XCTestCase {
    private final class Fixture {
        var commands: [(args: [Any], id: Int)] = []
        let controller: PlaybackController
        let subtitleURL = "http://localhost:8096/Videos/item/source/Subtitles/0/Stream.vtt?api_key=token"

        init() throws {
            let item = try JSONDecoder().decode(BaseItem.self, from: Data(#"{"Id":"item","Name":"Episode"}"#.utf8))
            let subtitle = ExternalSubtitle(streamIndex: 0, url: URL(string: subtitleURL)!,
                                            title: "Vietnamese", language: "vie",
                                            isDefault: true, isForced: false)
            let plan = DirectPlayPlan(itemId: "item", mediaSourceId: "source", playSessionId: nil,
                                      streamURL: URL(string: "http://localhost:8096/video.mkv")!,
                                      resumeSeconds: 0, defaultSubtitleStreamIndex: 0,
                                      externalSubtitles: [subtitle])
            let api = APIClient(baseURL: URL(string: "http://localhost:8096")!,
                                clientInfo: ClientInfo(deviceId: "test"))
            var record: (([Any], Int) -> Void)?
            let ipc = MPVIPC(commandHandler: { args, id in record?(args, id) })
            controller = PlaybackController(api: api, item: item, plan: plan, ipc: ipc)
            record = { [weak self] args, id in self?.commands.append((args, id)) }
        }

        func flush() { controller.queue.sync {} }
        func send(_ message: [String: Any]) { controller.handle(message); flush() }
        var additions: [(args: [Any], id: Int)] { commands.filter { $0.args.first as? String == "sub-add" } }
        var selectedIDs: [Any] {
            commands.filter { $0.args.first as? String == "set_property" && $0.args[1] as? String == "sid" }
                .map { $0.args[2] }
        }
        func mapTrack() {
            send(["event": "property-change", "id": 5, "data": [
                ["type": "sub", "external": true, "id": 4, "external-filename": subtitleURL]
            ]])
        }
    }

    func testEarlySelectionWaitsForFileLoadedAndMapsAssignedID() throws {
        let f = try Fixture()
        f.controller.selectSubtitleTrack(id: 0)
        f.flush()
        XCTAssertTrue(f.commands.isEmpty, "IPC connectivity alone must not trigger sub-add")
        f.send(["event": "property-change", "id": 1]) // unavailable time-pos during loading
        XCTAssertTrue(f.additions.isEmpty)
        f.send(["event": "file-loaded"])
        XCTAssertEqual(f.additions.count, 1)
        f.mapTrack()
        XCTAssertEqual(f.selectedIDs.last as? Int, 4)
        f.send(["event": "file-loaded"])
        XCTAssertEqual(f.additions.count, 1, "Do not duplicate an already loaded sidecar")
    }

    func testLateIPCConnectionRecoversFromPausedTimePositionSnapshot() throws {
        let f = try Fixture()
        f.send(["event": "property-change", "id": 2, "data": true])
        XCTAssertTrue(f.additions.isEmpty)
        // file-loaded happened before IPC connected, but a paused file has time-pos.
        f.send(["event": "property-change", "id": 1, "data": 0.0])
        XCTAssertEqual(f.additions.count, 1)
        f.send(["event": "property-change", "id": 1, "data": 1.0])
        XCTAssertEqual(f.additions.count, 1)
    }

    func testFailedCommandCanBeRetriedBySelectingSubtitleAgain() throws {
        let f = try Fixture()
        f.send(["event": "file-loaded"])
        let request = try XCTUnwrap(f.additions.first?.id)
        f.send(["request_id": request, "error": "error loading file"])
        f.controller.selectSubtitleTrack(id: 0)
        f.flush()
        XCTAssertEqual(f.additions.count, 2, "A failed request must not remain permanently loading")
        f.send(["request_id": f.additions[1].id, "error": "success"])
        f.mapTrack()
        XCTAssertEqual(f.selectedIDs.last as? Int, 4)
    }

    func testTurningSubtitlesOffWhileLoadingDoesNotSelectCompletedSidecar() throws {
        let f = try Fixture()
        f.send(["event": "file-loaded"])
        f.controller.selectSubtitleTrack(id: nil)
        f.flush()
        f.mapTrack()
        XCTAssertEqual(f.selectedIDs.last as? String, "no")
        XCTAssertFalse(f.selectedIDs.contains { $0 as? Int == 4 })
    }
}
