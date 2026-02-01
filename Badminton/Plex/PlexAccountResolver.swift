import Foundation

struct PlexAccountMatchCriteria: Sendable {
    let matchingAccountIDs: Set<Int>
    let preferredNames: Set<String>

    func matches(userTitle: String?) -> Bool {
        guard let userTitle else { return false }
        return preferredNames.contains(PlexAccountResolver.normalizeName(userTitle))
    }
}

actor PlexAccountResolver {
    static let shared = PlexAccountResolver()

    private let client: PlexAPIClient
    private var accountNameCache: [Int: PlexUserAccount] = [:]
    private var currentUserCache: PlexUserAccount?
    private var lastToken: String?

    init(client: PlexAPIClient = PlexAPIClient()) {
        self.client = client
    }

    func matchCriteria(
        preferredHomeUserIDs: Set<Int>,
        homeUsers: [PlexHomeUser],
        candidateAccountIDs: Set<Int>,
        token: String
    ) async -> PlexAccountMatchCriteria {
        guard !preferredHomeUserIDs.isEmpty else {
            return PlexAccountMatchCriteria(matchingAccountIDs: preferredHomeUserIDs, preferredNames: [])
        }

        resetIfNeeded(token: token)

        var preferredNames: Set<String> = []
        for user in homeUsers where preferredHomeUserIDs.contains(user.id) {
            preferredNames.formUnion(normalizedNames(for: user))
        }

        var matchingAccountIDs = preferredHomeUserIDs
        if !preferredNames.isEmpty {
            let resolved = await resolveAccountNameVariants(
                accountIDs: candidateAccountIDs,
                token: token
            )
            for (accountID, names) in resolved {
                if !names.isDisjoint(with: preferredNames) {
                    matchingAccountIDs.insert(accountID)
                }
            }
        }

        return PlexAccountMatchCriteria(
            matchingAccountIDs: matchingAccountIDs,
            preferredNames: preferredNames
        )
    }

    func mapHomeUsersToAccountIDs(
        homeUsers: [PlexHomeUser],
        candidateAccountIDs: Set<Int>,
        token: String
    ) async -> [Int: Set<Int>] {
        guard !homeUsers.isEmpty else { return [:] }

        resetIfNeeded(token: token)

        let resolved = await resolveAccountNameVariants(
            accountIDs: candidateAccountIDs,
            token: token
        )

        var mapping: [Int: Set<Int>] = [:]
        for user in homeUsers {
            let nameSet = normalizedNames(for: user)
            var matched: Set<Int> = []
            if !nameSet.isEmpty {
                for (accountID, names) in resolved {
                    if !names.isDisjoint(with: nameSet) {
                        matched.insert(accountID)
                    }
                }
            }
            if matched.isEmpty, candidateAccountIDs.contains(user.id) {
                matched.insert(user.id)
            }
            mapping[user.id] = matched
        }
        return mapping
    }

    private func resolveAccountNameVariants(
        accountIDs: Set<Int>,
        token: String
    ) async -> [Int: Set<String>] {
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
                let mapped = PlexUserAccount(
                    id: 1,
                    title: cachedCurrent.title,
                    username: cachedCurrent.username
                )
                resolved[1] = mapped
                accountNameCache[1] = mapped
                pending.removeAll { $0 == 1 }
            } else if let currentUser = try? await client.fetchCurrentUser(token: token) {
                currentUserCache = currentUser
                let mapped = PlexUserAccount(
                    id: 1,
                    title: currentUser.title,
                    username: currentUser.username
                )
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

        let unresolved = accountIDs.subtracting(resolved.keys)
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

    private func resetIfNeeded(token: String) {
        if lastToken != token {
            accountNameCache = [:]
            currentUserCache = nil
            lastToken = token
        }
    }

    private func normalizedNames(for user: PlexHomeUser) -> Set<String> {
        var names: Set<String> = []
        if let friendlyName = user.friendlyName, !friendlyName.isEmpty {
            names.insert(Self.normalizeName(friendlyName))
        }
        if let title = user.title, !title.isEmpty {
            names.insert(Self.normalizeName(title))
        }
        if let username = user.username, !username.isEmpty {
            names.insert(Self.normalizeName(username))
        }
        return names
    }

    private func normalizedNames(for account: PlexUserAccount) -> Set<String> {
        Set(account.nameVariants.map(Self.normalizeName))
    }

    nonisolated static func normalizeName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
