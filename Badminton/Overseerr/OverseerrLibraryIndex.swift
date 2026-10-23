import Combine
import CryptoKit
import Foundation
import os

struct OverseerrMediaKey: Codable, Hashable {
    let tmdbID: Int
    let mediaType: OverseerrMediaType
}

@MainActor
final class OverseerrLibraryIndex: ObservableObject {
    @Published private(set) var availableMedia: Set<OverseerrMediaKey> = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?

    private let client: OverseerrAPIClient
    private let defaults: UserDefaults
    private let cacheKey = "overseerr.library.v2"
    private var scope: String?
    private var generation = UUID()
    private let ttl: TimeInterval = 6 * 60 * 60

    init(client: OverseerrAPIClient = OverseerrAPIClient(), defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
    }

    func isAvailable(tmdbID: Int, mediaType: OverseerrMediaType) -> Bool {
        availableMedia.contains(OverseerrMediaKey(tmdbID: tmdbID, mediaType: mediaType))
    }

    func refreshIfNeeded(authManager: OverseerrAuthManager, plexToken: String?) async {
        await refresh(authManager: authManager, plexToken: plexToken)
    }

    func refresh(authManager: OverseerrAuthManager, plexToken: String?, force: Bool = false) async {
        guard let baseURL = authManager.baseURL, let cookie = authManager.authCookie() else {
            reset(scope: nil)
            return
        }
        // Scope cached availability to the server and signed-in session, without persisting the cookie.
        let newScope = SHA256.hash(data: Data((baseURL.absoluteString + "|" + cookie).utf8))
            .map { String(format: "%02x", $0) }.joined()
        if scope != newScope {
            reset(scope: newScope)
            if let data = defaults.data(forKey: cacheKey),
               let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data), snapshot.scope == newScope {
                availableMedia = snapshot.media
                lastUpdated = snapshot.updated
            }
        }
        guard !isRefreshing else { return }
        if !force, let lastUpdated, Date().timeIntervalSince(lastUpdated) < ttl { return }
        let requestGeneration = generation
        isRefreshing = true
        errorMessage = nil
        defer { if generation == requestGeneration { isRefreshing = false } }
        do {
            let allMedia = try await authManager.withSession(plexToken: plexToken) { url, cookie in
                var media: Set<OverseerrMediaKey> = []
                var page = 1
                var totalPages = 1
                while page <= totalPages {
                    try Task.checkCancellation()
                    let response = try await self.client.getMediaPage(baseURL: url, filter: "allavailable",
                        take: 100, skip: (page - 1) * 100, cookie: cookie)
                    totalPages = response.pageInfo.pages
                    for item in response.results {
                        media.insert(OverseerrMediaKey(tmdbID: item.tmdbId, mediaType: item.mediaType))
                    }
                    page += 1
                }
                return media
            }
            try Task.checkCancellation()
            guard generation == requestGeneration else { return }
            availableMedia = allMedia
            lastUpdated = Date()
            save()
        } catch is CancellationError {
        } catch {
            guard generation == requestGeneration else { return }
            errorMessage = error.localizedDescription
            AppLog.overseerr.error("Library availability refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func updateAvailability(tmdbID: Int, mediaType: OverseerrMediaType, status: OverseerrMediaStatus?) {
        guard let status, scope != nil else { return }
        let key = OverseerrMediaKey(tmdbID: tmdbID, mediaType: mediaType)
        if status == .available || status == .partiallyAvailable { availableMedia.insert(key) }
        else { availableMedia.remove(key) }
        save()
    }

    private func reset(scope: String?) {
        generation = UUID()
        self.scope = scope
        availableMedia = []
        lastUpdated = nil
        isRefreshing = false
        errorMessage = nil
    }

    private func save() {
        guard let scope, let lastUpdated,
              let data = try? JSONEncoder().encode(Snapshot(scope: scope, media: availableMedia, updated: lastUpdated)) else { return }
        defaults.set(data, forKey: cacheKey)
    }

    private struct Snapshot: Codable {
        let scope: String
        let media: Set<OverseerrMediaKey>
        let updated: Date
    }
}
