import Foundation

#if os(iOS)
import ActivityKit

@MainActor
final class PlexNowPlayingLiveActivityManager {
    private var activities: [String: Activity<PlaybackActivityAttributes>] = [:]

    func sync(nowPlaying: [PlexRecentlyWatchedItem]) {
        guard #available(iOS 16.1, *) else { return }

        for activity in Activity<PlaybackActivityAttributes>.activities {
            activities[activity.attributes.id] = activity
        }

        let desiredIDs = Set(nowPlaying.map { $0.liveActivityID })
        if desiredIDs.isEmpty, activities.isEmpty {
            return
        }

        for (id, activity) in activities where !desiredIDs.contains(id) {
            endActivity(activity, id: id)
        }

        for item in nowPlaying {
            let activityID = item.liveActivityID
            let subtitle = item.detailSubtitle.isEmpty ? "Now Playing" : item.detailSubtitle
            let state = PlaybackActivityAttributes.ContentState(
                title: item.title,
                subtitle: subtitle,
                artworkURLString: item.imageURL.absoluteString,
                progress: item.progress,
                updatedAt: Date()
            )
            let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(10 * 60))

            if let activity = activities[activityID] {
                Task {
                    await activity.update(content)
                    print("Live Activity updated: \(activityID)")
                }
            } else {
                let attributes = PlaybackActivityAttributes(id: activityID)
                do {
                    let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
                    activities[activityID] = activity
                    print("Live Activity started: \(activityID)")
                } catch {
                    print("Live Activity start failed for \(activityID): \(error)")
                }
            }
        }
    }

    private func endActivity(_ activity: Activity<PlaybackActivityAttributes>, id: String) {
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
            print("Live Activity ended: \(id)")
        }
        activities[id] = nil
    }
}
#else
final class PlexNowPlayingLiveActivityManager {
    func sync(nowPlaying: [PlexRecentlyWatchedItem]) {}
}
#endif
