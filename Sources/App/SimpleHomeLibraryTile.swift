import SwiftUI
import JellyfinKit

struct SimpleHomeLibraryTile: View {
    let item: BaseItem

    private var icon: String {
        item.isHomeVideoLibrary ? "video" : "folder"
    }

    var body: some View {
        NavigationLink(value: item) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(SolfinDesign.solarGold)
                    .frame(width: 52, height: 52)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.name).font(.headline).foregroundStyle(.white).lineLimit(1)
                    Text(item.isHomeVideoLibrary ? "Home Videos" : "Browse library")
                        .font(.caption).foregroundStyle(.white.opacity(0.58))
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.42))
            }
            .padding(16)
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.09)) }
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(item.name)")
    }
}
