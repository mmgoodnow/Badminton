import Foundation

@MainActor
final class OverseerrRequestViewModel: ObservableObject {
    @Published private(set) var statusText: String = "Not requested"
    @Published private(set) var requestStatus: OverseerrRequestStatus?
    @Published private(set) var mediaStatus: OverseerrMediaStatus?
    @Published private(set) var seasonStatuses: [Int: OverseerrMediaStatus] = [:]
    @Published private(set) var partialRequestsEnabled: Bool = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let client: OverseerrAPIClient
    private let mediaType: OverseerrMediaType
    private let tmdbID: Int

    init(mediaType: OverseerrMediaType, tmdbID: Int, client: OverseerrAPIClient = OverseerrAPIClient()) {
        self.mediaType = mediaType
        self.tmdbID = tmdbID
        self.client = client
    }

    func load(baseURL: URL?, cookie: String?) async {
        guard let baseURL, let cookie else {
            resetState()
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            async let settings = client.getPublicSettings(baseURL: baseURL)
            async let mediaInfo: OverseerrMediaInfo? = fetchMediaInfo(baseURL: baseURL, cookie: cookie)

            let (settingsResponse, mediaInfoResponse) = try await (settings, mediaInfo)
            partialRequestsEnabled = settingsResponse.partialRequestsEnabled
            apply(mediaInfoResponse)
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func request(seasons: [Int]? = nil, baseURL: URL?, cookie: String?) async {
        guard let baseURL, let cookie else {
            errorMessage = "Connect Overseerr first."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let body = OverseerrRequestBody(mediaType: mediaType, mediaId: tmdbID, seasons: seasons?.isEmpty == true ? nil : seasons)
            _ = try await client.requestMedia(baseURL: baseURL, body: body, cookie: cookie)
            await load(baseURL: baseURL, cookie: cookie)
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func seasonStatusText(for seasonNumber: Int) -> String? {
        seasonStatuses[seasonNumber]?.displayText
    }

    var canRequest: Bool {
        guard let status = mediaStatus else { return true }
        switch status {
        case .available:
            return false
        case .partiallyAvailable:
            return mediaType == .tv
        case .unknown, .pending, .processing, .deleted:
            return true
        }
    }

    private func fetchMediaInfo(baseURL: URL, cookie: String) async throws -> OverseerrMediaInfo? {
        switch mediaType {
        case .movie:
            let response = try await client.getMovie(baseURL: baseURL, tmdbID: tmdbID, cookie: cookie)
            return response.mediaInfo
        case .tv:
            let response = try await client.getTV(baseURL: baseURL, tmdbID: tmdbID, cookie: cookie)
            return response.mediaInfo
        }
    }

    private func apply(_ mediaInfo: OverseerrMediaInfo?) {
        mediaStatus = mediaInfo?.status
        requestStatus = mediaInfo?.requests?.compactMap { $0.status }.sorted(by: { $0.rawValue < $1.rawValue }).last
        seasonStatuses = Dictionary(uniqueKeysWithValues: (mediaInfo?.seasons ?? []).compactMap { season in
            guard let status = season.status else { return nil }
            return (season.seasonNumber, status)
        })

        if let status = mediaInfo?.status {
            statusText = status.displayText
        } else if let requestStatus {
            statusText = requestStatus.displayText
        } else {
            statusText = "Not requested"
        }
    }

    private func resetState() {
        statusText = "Not requested"
        requestStatus = nil
        mediaStatus = nil
        seasonStatuses = [:]
        partialRequestsEnabled = false
        errorMessage = nil
        isLoading = false
    }
}
