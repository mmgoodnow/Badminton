import Combine
import Foundation

#if os(iOS)
import ActivityKit

@MainActor
final class PlaybackLiveActivityManager: ObservableObject {
    @Published private(set) var status: String = "Idle"

    private var activity: Activity<PlaybackActivityAttributes>?
    private var progress: Double = 0.1

    private func resolveActivity() -> Activity<PlaybackActivityAttributes>? {
        if let activity {
            return activity
        }
        let existing = Activity<PlaybackActivityAttributes>.activities.first
        if let existing {
            activity = existing
        }
        return existing
    }

    func startSample() {
        guard #available(iOS 16.1, *) else {
            status = "Live Activities require iOS 16.1+"
            return
        }

        let authorization = ActivityAuthorizationInfo()
        guard authorization.areActivitiesEnabled else {
            status = "Live Activities disabled in system settings"
            return
        }

        let attributes = PlaybackActivityAttributes(id: UUID().uuidString)
        let state = PlaybackActivityAttributes.ContentState(
            title: "Badminton",
            subtitle: "Client-only Live Activity",
            artworkFileName: nil,
            progress: progress,
            updatedAt: Date()
        )
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(10 * 60))

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            self.activity = activity
            status = "Started activity \(activity.id)"
            print("Live Activity started: \(activity.id)")
        } catch {
            status = "Start failed: \(error.localizedDescription)"
            print("Live Activity start failed: \(error)")
        }
    }

    func updateSample() {
        guard #available(iOS 16.1, *) else {
            status = "Live Activities require iOS 16.1+"
            return
        }
        guard let activity = resolveActivity() else {
            status = "No active Live Activity"
            return
        }

        progress = min(progress + 0.15, 1.0)
        let state = PlaybackActivityAttributes.ContentState(
            title: "Badminton",
            subtitle: "Progress \(Int(progress * 100))%",
            artworkFileName: nil,
            progress: progress,
            updatedAt: Date()
        )
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(10 * 60))

        Task {
            await activity.update(content)
            status = "Updated activity \(activity.id)"
            print("Live Activity updated: \(activity.id)")
        }
    }

    func endSample() {
        guard #available(iOS 16.1, *) else {
            status = "Live Activities require iOS 16.1+"
            return
        }
        guard let activity = resolveActivity() else {
            status = "No active Live Activity"
            return
        }

        let state = PlaybackActivityAttributes.ContentState(
            title: "Badminton",
            subtitle: "Ended",
            artworkFileName: nil,
            progress: progress,
            updatedAt: Date()
        )
        let content = ActivityContent(state: state, staleDate: nil)

        Task {
            await activity.end(content, dismissalPolicy: .immediate)
            status = "Ended activity \(activity.id)"
            print("Live Activity ended: \(activity.id)")
            self.activity = nil
        }
    }
}
#else
@MainActor
final class PlaybackLiveActivityManager: ObservableObject {
    @Published private(set) var status: String = "Live Activities unavailable on this platform"

    func startSample() {}
    func updateSample() {}
    func endSample() {}
}
#endif
