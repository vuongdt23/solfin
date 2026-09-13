import SwiftUI
import JellyfinKit

struct ItemDetailView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var nowPlaying: NowPlaying
    let itemId: String

    @State private var item: BaseItem?
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            if let item {
              VStack(alignment: .leading, spacing: 0) {
                let backdrop = appState.api.backdropImageURL(for: item)
                BackdropHero(url: backdrop, height: 300)
                HStack(alignment: .top, spacing: 24) {
                    PosterImage(url: appState.api.primaryImageURL(for: item, maxHeight: 600))
                        .frame(width: 220, height: 330)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(title(for: item)).font(.largeTitle.bold())
                        HStack(spacing: 12) {
                            if let year = item.productionYear { Text(String(year)) }
                            if let rt = item.runTimeTicks {
                                Text("\(Int(Ticks.toSeconds(rt) / 60)) min")
                            }
                            if item.userData?.played == true {
                                Label("Watched", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .foregroundStyle(.secondary)

                        if let overview = item.overview {
                            Text(overview).font(.body).foregroundStyle(.primary.opacity(0.9))
                        }

                        streamInfo(for: item)

                        HStack(spacing: 12) {
                            Button {
                                play(item)
                            } label: {
                                Label(playLabel(for: item), systemImage: "play.fill")
                                    .frame(minWidth: 120)
                            }
                            .buttonStyle(.borderedProminent)

                            if resumeSeconds(item) > 0 {
                                Button {
                                    playFromStart(item)
                                } label: {
                                    Label("Start Over", systemImage: "gobackward")
                                }
                            }
                        }
                        .padding(.top, 8)

                        if let err = appState.playbackError {
                            Text(err).foregroundStyle(.red).font(.callout)
                        }
                    }
                    Spacer()
                }
                .padding(24)
                .offset(y: backdrop == nil ? 0 : -70)
                .padding(.bottom, backdrop == nil ? 0 : -70)
              }
            } else if let err = loadError {
                Text(err).foregroundStyle(.red).padding()
            } else {
                ProgressView().padding(40)
            }
        }
        .task { await load() }
    }

    private func title(for item: BaseItem) -> String {
        if item.type == "Episode", let series = item.seriesName {
            let s = item.parentIndexNumber.map { "S\($0)" } ?? ""
            let e = item.indexNumber.map { "E\($0)" } ?? ""
            return "\(series) · \(s)\(e) · \(item.name)"
        }
        return item.name
    }

    private func resumeSeconds(_ item: BaseItem) -> Double {
        Ticks.toSeconds(item.userData?.playbackPositionTicks)
    }

    private func playLabel(for item: BaseItem) -> String {
        resumeSeconds(item) > 0 ? "Resume" : "Play in mpv"
    }

    @ViewBuilder
    private func streamInfo(for item: BaseItem) -> some View {
        if let source = item.mediaSources?.first {
            VStack(alignment: .leading, spacing: 2) {
                if let container = source.container {
                    Text("Container: \(container.uppercased())").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array((source.mediaStreams ?? []).enumerated()), id: \.offset) { _, s in
                    if let title = s.displayTitle {
                        Text("\(s.type ?? "?"): \(title)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func play(_ item: BaseItem, startOver: Bool = false) {
        appState.playbackError = nil
        nowPlaying.play(item: item, api: appState.api, config: appState.makePlaybackConfig(),
                        startOver: startOver) {
            appState.playbackError = $0
        }
    }

    private func playFromStart(_ item: BaseItem) {
        play(item, startOver: true)
    }

    private func load() async {
        do { item = try await appState.api.item(id: itemId) }
        catch { loadError = error.localizedDescription }
    }
}
