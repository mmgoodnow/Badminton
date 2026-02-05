import Combine
import Foundation

@MainActor
final class OverseerrLibraryIndex: ObservableObject {
    @Published private(set) var availableTMDBIDs: Set<Int>
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false

    private let client: OverseerrAPIClient
    private let storage = OverseerrLibraryStore()
    private let ttl: TimeInterval = 6 * 60 * 60

    init(client: OverseerrAPIClient = OverseerrAPIClient()) {
        self.client = client
        let cachedIDs = storage.readIDs()
        self.availableTMDBIDs = Set(cachedIDs)
        self.lastUpdated = storage.readLastUpdated()
    }

    func isAvailable(tmdbID: Int) -> Bool {
        availableTMDBIDs.contains(tmdbID)
    }

    func refreshIfNeeded(baseURL: URL?, cookie: String?) async {
        guard let lastUpdated else {
            await refresh(baseURL: baseURL, cookie: cookie, force: true)
            return
        }
        let elapsed = Date().timeIntervalSince(lastUpdated)
        guard elapsed >= ttl else { return }
        await refresh(baseURL: baseURL, cookie: cookie, force: true)
    }

    func refresh(baseURL: URL?, cookie: String?, force: Bool = false) async {
        guard !isRefreshing else { return }
        guard let baseURL, let cookie else { return }
        if !force, let lastUpdated, Date().timeIntervalSince(lastUpdated) < ttl {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        var allIDs: Set<Int> = []
        let pageSize = 100
        var currentPage = 1
        var totalPages = 1

        do {
            while currentPage <= totalPages {
                let response = try await client.getMediaPage(
                    baseURL: baseURL,
                    filter: "allavailable",
                    take: pageSize,
                    skip: (currentPage - 1) * pageSize,
                    cookie: cookie
                )
                totalPages = response.pageInfo.pages
                for item in response.results {
                    allIDs.insert(item.tmdbId)
                }
                currentPage += 1
            }

            availableTMDBIDs = allIDs
            lastUpdated = Date()
            storage.save(ids: Array(allIDs))
            storage.saveLastUpdated(lastUpdated)
        } catch {
        }
    }

    func updateAvailability(tmdbID: Int, status: OverseerrMediaStatus?) {
        guard let status else { return }
        let isAvailable = status == .available || status == .partiallyAvailable
        if isAvailable {
            if !availableTMDBIDs.contains(tmdbID) {
                availableTMDBIDs.insert(tmdbID)
                storage.save(ids: Array(availableTMDBIDs))
            }
        } else if availableTMDBIDs.contains(tmdbID) {
            availableTMDBIDs.remove(tmdbID)
            storage.save(ids: Array(availableTMDBIDs))
        }
    }
}

private struct OverseerrLibraryStore {
    private enum Key {
        static let availableIDs = "overseerr.library.available.tmdb"
        static let lastUpdated = "overseerr.library.available.updated"
    }

    func save(ids: [Int]) {
        if let data = try? JSONEncoder().encode(ids) {
            UserDefaults.standard.set(data, forKey: Key.availableIDs)
        }
    }

    func readIDs() -> [Int] {
        guard let data = UserDefaults.standard.data(forKey: Key.availableIDs),
              let ids = try? JSONDecoder().decode([Int].self, from: data)
        else { return [] }
        return ids
    }

    func saveLastUpdated(_ date: Date?) {
        UserDefaults.standard.set(date, forKey: Key.lastUpdated)
    }

    func readLastUpdated() -> Date? {
        UserDefaults.standard.object(forKey: Key.lastUpdated) as? Date
    }
}
