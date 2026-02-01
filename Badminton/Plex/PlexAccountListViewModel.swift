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
    private var accountNameCache: [Int: PlexUserAccount] = [:]
    private var currentUserCache: PlexUserAccount?

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

        if lastToken != token {
            accountNameCache = [:]
            currentUserCache = nil
        }

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
                guard let accountID = item.accountID ?? item.userID else { continue }
                var entry = counts[accountID] ?? (0, nil)
                entry.count += 1
                if let viewedAt = item.viewedAt {
                    entry.lastViewedAt = max(entry.lastViewedAt ?? 0, viewedAt)
                }
                counts[accountID] = entry
            }
            let accountNameVariants = await resolveAccountNameVariants(
                accountIDs: Array(counts.keys),
                token: token
            )
            accounts = homeUsers.values
                .map { user in
                    let userNames = normalizedNames(for: user)
                    let matchedAccountIDs = accountNameVariants.compactMap { (accountID, names) in
                        names.isDisjoint(with: userNames) ? nil : accountID
                    }
                    let count = matchedAccountIDs.reduce(0) { sum, accountID in
                        sum + (counts[accountID]?.count ?? 0)
                    }
                    let lastViewedAt = matchedAccountIDs.compactMap { counts[$0]?.lastViewedAt }.max()
                    return PlexAccountOption(
                        id: user.id,
                        count: count,
                        lastViewedAt: lastViewedAt
                    )
                }
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

    private func resolveAccountNameVariants(accountIDs: [Int], token: String) async -> [Int: Set<String>] {
        guard !accountIDs.isEmpty else { return [:] }

        var resolved: [Int: PlexUserAccount] = [:]
        var pending: [Int] = []

        for accountID in accountIDs {
            if let cached = accountNameCache[accountID] {
                resolved[accountID] = cached
            } else {
                pending.append(accountID)
            }
        }

        if pending.contains(1) {
            if let cachedCurrent = currentUserCache {
                let mapped = PlexUserAccount(id: 1, title: cachedCurrent.title, username: cachedCurrent.username)
                resolved[1] = mapped
                accountNameCache[1] = mapped
                pending.removeAll { $0 == 1 }
            } else if let currentUser = try? await client.fetchCurrentUser(token: token) {
                currentUserCache = currentUser
                let mapped = PlexUserAccount(id: 1, title: currentUser.title, username: currentUser.username)
                resolved[1] = mapped
                accountNameCache[1] = mapped
                pending.removeAll { $0 == 1 }
            }
        }

        if !pending.isEmpty {
            await withTaskGroup(of: (Int, PlexUserAccount?).self) { group in
                for accountID in pending {
                    group.addTask { [client] in
                        let account = try? await client.fetchUserAccount(id: accountID, token: token)
                        return (accountID, account)
                    }
                }
                for await (accountID, account) in group {
                    if let account {
                        resolved[accountID] = account
                        accountNameCache[accountID] = account
                    }
                }
            }
        }

        let unresolved = Set(accountIDs).subtracting(resolved.keys)
        if !unresolved.isEmpty {
            print("Plex account name lookup missing for accountIDs: \(unresolved.sorted())")
        }

        var variants: [Int: Set<String>] = [:]
        for (accountID, account) in resolved {
            let names = normalizedNames(for: account)
            if !names.isEmpty {
                variants[accountID] = names
            }
        }
        return variants
    }

    private func normalizedNames(for user: PlexHomeUser) -> Set<String> {
        var names: Set<String> = []
        if let friendlyName = user.friendlyName, !friendlyName.isEmpty {
            names.insert(normalizeName(friendlyName))
        }
        if let title = user.title, !title.isEmpty {
            names.insert(normalizeName(title))
        }
        if let username = user.username, !username.isEmpty {
            names.insert(normalizeName(username))
        }
        return names
    }

    private func normalizedNames(for account: PlexUserAccount) -> Set<String> {
        return Set(account.nameVariants.map(normalizeName))
    }

    private func normalizeName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
