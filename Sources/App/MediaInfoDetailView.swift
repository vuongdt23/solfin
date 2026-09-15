import SwiftUI
import JellyfinKit

struct MediaInfoDetailView: View {
    let item: BaseItem
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Media information").font(.title2.bold()); Spacer(); Button("Done") { dismiss() } }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    info("Container", source?.container)
                    info("Path", source?.path, multiline: true)
                    info("Size", source?.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) })
                    info("Bitrate", source?.bitrate.map { "\($0 / 1000) kbps" })
                    info("Protocol", source?.protocolName)
                    Divider()
                    Text("Streams").font(.headline)
                    ForEach(Array((source?.mediaStreams ?? []).enumerated()), id: \.offset) { _, stream in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(stream.type ?? "Track")
                                .foregroundStyle(.secondary)
                                .frame(width: 105, alignment: .leading)
                            Text(stream.displayTitle ?? stream.language ?? stream.codec ?? "Unknown")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                            Text(stream.codec ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 90, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .padding(28)
        .frame(width: 900, height: 560)
    }
    private var source: MediaSource? { item.mediaSources?.first }
    private func info(_ title: String, _ value: String?, multiline: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(title).foregroundStyle(.secondary).frame(width: 105, alignment: .leading)
            Text(value ?? "Unknown")
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
                .lineLimit(multiline ? nil : 1)
                .textSelection(.enabled)
        }
    }
}
