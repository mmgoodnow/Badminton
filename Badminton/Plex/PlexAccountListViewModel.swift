import Combine
import Foundation

struct PlexAccountOption: Identifiable, Hashable {
    let id: Int
    let count: Int
    let lastViewedAt: Int?

    var displayName: String {
        let suffix = count == 1 ? "play" : "plays"
        return "Account \(id) · \(count) \(suffix)"
    }
}

@MainActor
final class PlexAccountListViewModel: ObservableObject {
    @Published var accounts: [PlexAccountOption] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let client: PlexAPIClient
    private var lastToken: String?
    private var lastServerID: String?

    init(client: PlexAPIClient = PlexAPIClient()) {
        self.client = client
    }

    func load(token: String?, preferredServerID: String?, force: Bool = false) async {
        guard let token, !token.isEmpty else {
            accounts = []
            lastToken = nil
            lastServerID = nil
            return
        }

        guard force || lastToken != token || lastServerID != preferredServerID || accounts.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        do {
            let result = try await client.fetchRecentlyWatched(
                token: token,
                size: 500,
                preferredServerID: preferredServerID
            )
            var counts: [Int: (count: Int, lastViewedAt: Int?)] = [:]
            for item in result.items {
                guard let accountID = item.accountID else { continue }
                var entry = counts[accountID] ?? (0, nil)
                entry.count += 1
                if let viewedAt = item.viewedAt {
                    entry.lastViewedAt = max(entry.lastViewedAt ?? 0, viewedAt)
                }
                counts[accountID] = entry
            }
            accounts = counts
                .map { PlexAccountOption(id: $0.key, count: $0.value.count, lastViewedAt: $0.value.lastViewedAt) }
                .sorted { lhs, rhs in
                    if lhs.count == rhs.count {
                        return (lhs.lastViewedAt ?? 0) > (rhs.lastViewedAt ?? 0)
                    }
                    return lhs.count > rhs.count
                }
            lastToken = token
            lastServerID = preferredServerID
        } catch {
            accounts = []
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
