import Foundation
import JellyfinKit
import PlaybackEngine

// Headless test harness for JellyfinKit + PlaybackEngine against a real server.
//
// Env:  SOLFIN_SERVER (default http://localhost:8096), SOLFIN_USER, SOLFIN_PASS
// Usage: solfin-probe <info|login|browse|plan <itemId>|play <itemId>>

@main
struct Probe {
    static func env(_ k: String, _ dflt: String? = nil) -> String? {
        ProcessInfo.processInfo.environment[k] ?? dflt
    }

    static func makeClient() -> APIClient {
        let server = env("SOLFIN_SERVER", "http://localhost:8096")!
        let store = CredentialStore()
        let info = ClientInfo(deviceId: store.deviceId)
        return APIClient(baseURL: URL(string: server)!, clientInfo: info)
    }

    static func signedIn() async throws -> APIClient {
        let client = makeClient()
        guard let user = env("SOLFIN_USER"), let pass = env("SOLFIN_PASS") else {
            FileHandle.standardError.write(Data("Set SOLFIN_USER and SOLFIN_PASS.\n".utf8))
            exit(2)
        }
        let session = try await client.login(username: user, password: pass)
        return client.authenticated(with: session)
    }

    /// Depth-first search for the first playable video item under the user's views.
    static func firstVideo(_ api: APIClient) async throws -> BaseItem? {
        let views = try await api.views()
        for view in views where view.collectionType == "movies" || view.collectionType == "tvshows" {
            let resp = try await api.items(parentId: view.id, limit: 5,
                                           includeItemTypes: "Movie,Episode")
            if let first = resp.items.first { return try await api.item(id: first.id) }
        }
        return nil
    }

    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        let cmd = args.first ?? "info"
        do {
            switch cmd {
            case "info":
                let info = try await makeClient().publicSystemInfo()
                print("Server: \(info.serverName)  version \(info.version)  id \(info.id)")

            case "login":
                let api = try await signedIn()
                print("Logged in as \(api.session!.userName)  userId=\(api.session!.userId)")
                print("Token: \(api.session!.accessToken.prefix(8))…")

            case "browse":
                let api = try await signedIn()
                let views = try await api.views()
                print("Libraries (\(views.count)):")
                for v in views { print("  • \(v.name)  [\(v.collectionType ?? v.type ?? "?")]  id=\(v.id)") }
                let resume = try await api.resumeItems()
                print("Continue Watching (\(resume.count)):")
                for r in resume {
                    let pct = r.userData?.playedPercentage.map { String(format: "%.0f%%", $0) } ?? "-"
                    print("  • \(r.name)  \(pct)")
                }

            case "plan":
                let api = try await signedIn()
                let item: BaseItem
                if args.count > 1 { item = try await api.item(id: args[1]) }
                else if let v = try await firstVideo(api) { item = v }
                else { print("No video found."); return }
                let plan = try await api.directPlayPlan(for: item)
                print("Item: \(item.name)")
                print("MediaSourceId: \(plan.mediaSourceId)")
                print("Resume: \(String(format: "%.1f", plan.resumeSeconds))s")
                print("Direct stream URL:\n  \(plan.streamURL.absoluteString)")

            case "play":
                let api = try await signedIn()
                let item: BaseItem
                if args.count > 1 { item = try await api.item(id: args[1]) }
                else if let v = try await firstVideo(api) { item = v }
                else { print("No video found."); return }

                print("Playing \(item.name) in mpv… (Ctrl-C or quit mpv to stop)")
                let cfg = PlaybackController.Config(configDir: env("SOLFIN_MPV_CONFIG"))
                let controller = PlaybackController(api: api, item: item, config: cfg)
                let done = DispatchSemaphore(value: 0)
                controller.onStateChange = { state, pos in
                    print("  [\(state.rawValue)] pos=\(String(format: "%.1f", pos))s")
                    if state == .stopped { done.signal() }
                }
                controller.onError = { err in
                    print("  ERROR: \(err.localizedDescription)"); done.signal()
                }
                controller.start()
                done.wait()
                print("Done.")

            case "seasons":
                let api = try await signedIn()
                guard args.count > 1 else { print("usage: seasons <seriesId>"); return }
                let seasons = try await api.seasons(seriesId: args[1])
                print("Seasons (\(seasons.count)):")
                for s in seasons { print("  • \(s.name)  id=\(s.id)  episodes=\(s.childCount ?? -1)") }

            case "episodes":
                let api = try await signedIn()
                guard args.count > 1 else { print("usage: episodes <seriesId> [seasonId]"); return }
                let eps = try await api.episodes(seriesId: args[1],
                                                 seasonId: args.count > 2 ? args[2] : nil)
                print("Episodes (\(eps.count)):")
                for e in eps.prefix(12) {
                    let s = e.parentIndexNumber.map { "S\($0)" } ?? ""
                    let n = e.indexNumber.map { "E\($0)" } ?? ""
                    print("  • \(s)\(n)  \(e.name)  id=\(e.id)")
                }

            case "next":
                let api = try await signedIn()
                guard args.count > 1 else { print("usage: next <episodeId>"); return }
                let ep = try await api.item(id: args[1])
                print("Current: \(ep.name)  (seriesId=\(ep.seriesId ?? "nil"))")
                if let nextEp = try await api.nextEpisode(after: ep) {
                    let s = nextEp.parentIndexNumber.map { "S\($0)" } ?? ""
                    let n = nextEp.indexNumber.map { "E\($0)" } ?? ""
                    print("Next:    \(s)\(n)  \(nextEp.name)  id=\(nextEp.id)")
                } else {
                    print("Next:    (none — last episode)")
                }

            default:
                print("Unknown command '\(cmd)'. Use: info | login | browse | plan | play | seasons | episodes | next")
            }
        } catch {
            FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
