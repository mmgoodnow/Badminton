import ActivityKit
import SwiftUI
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
                    Text("\(Int(context.state.progress * 100))%")
                        .font(.caption)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.subtitle)
                        .font(.caption2)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "play.fill")
            } compactTrailing: {
                Text("\(Int(context.state.progress * 100))%")
                    .font(.caption2)
            } minimal: {
                Image(systemName: "play.fill")
            }
        }
    }
}

private struct LiveActivityContentView: View {
    let context: ActivityViewContext<PlaybackActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(context.state.title)
                .font(.headline)
                .lineLimit(1)
            Text(context.state.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            ProgressView(value: context.state.progress)
                .progressViewStyle(.linear)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
