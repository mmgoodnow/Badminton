import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

struct BadmintonLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PlaybackActivityAttributes.self) { context in
            LiveActivityContentView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.title)
                        .font(.caption)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let progress = context.state.progress {
                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.subtitle)
                        .font(.caption2)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "play.fill")
            } compactTrailing: {
                if let progress = context.state.progress {
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                }
            } minimal: {
                Image(systemName: "play.fill")
            }
        }
    }
}

private struct LiveActivityContentView: View {
    let context: ActivityViewContext<PlaybackActivityAttributes>

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ArtworkView(fileName: context.state.artworkFileName)
            VStack(alignment: .leading, spacing: 6) {
                Text(context.state.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(context.state.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let progress = context.state.progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct ArtworkView: View {
    let fileName: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary)

            if let image = loadImage() {
                image
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: 54, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func loadImage() -> Image? {
        guard let fileName,
              let url = LiveActivityFileStore.fileURL(for: fileName),
              let image = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        return Image(uiImage: image)
    }
}

private enum LiveActivityFileStore {
    private static let appGroupID = "group.com.bebopbeluga.Badminton"
    private static let directoryName = "LiveActivityArt"

    static func fileURL(for fileName: String) -> URL? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }
        let directoryURL = containerURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
        return directoryURL.appendingPathComponent(fileName)
    }
}
