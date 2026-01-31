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
    @Published var homeUsers: [Int: PlexHomeUser] = [:]

    private let client: PlexAPIClient
    private var lastToken: String?
    private var lastServerID: String?

    init(client: PlexAPIClient = PlexAPIClient()) {
        self.client = client
    }

    func load(token: String?, preferredServerID: String?, force: Bool = false) async {
        guard let token, !token.isEmpty else {
            accounts = []
            homeUsers = [:]
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
            do {
                let users = try await client.fetchHomeUsers(token: token)
                homeUsers = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
            } catch {
                homeUsers = [:]
            }
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
            let allowedIDs = Set(homeUsers.keys)
            accounts = counts
                .filter { allowedIDs.contains($0.key) }
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
            homeUsers = [:]
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func name(for id: Int?) -> String? {
        guard let id else { return nil }
        return homeUsers[id]?.displayName
    }
}
