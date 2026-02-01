import Foundation

#if os(iOS)
import ActivityKit

struct PlaybackActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let title: String
        let subtitle: String
        let progress: Double
        let updatedAt: Date
    }

    let id: String
}
#endif
