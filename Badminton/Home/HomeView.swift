import Combine
import Kingfisher
import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @StateObject private var searchModel = SearchViewModel()
    @EnvironmentObject private var plexAuthManager: PlexAuthManager
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    plexRecentlyWatchedSection
                    if searchModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }

                        if viewModel.isLoading && viewModel.trendingMovies.isEmpty && viewModel.trendingTV.isEmpty {
                            ProgressView("Loading titles…")
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            trendingSection(title: "Trending Movies", items: viewModel.trendingMovies.map { .movie($0) })
                            trendingSection(title: "Trending TV", items: viewModel.trendingTV.map { .tv($0) })
                            trendingSection(title: "Now Playing", items: viewModel.nowPlayingMovies.map { .movie($0) })
                            trendingSection(title: "Upcoming", items: viewModel.upcomingMovies.map { .movie($0) })
                            trendingSection(title: "On the Air", items: viewModel.onTheAirTV.map { .tv($0) })
                            trendingSection(title: "Airing Today", items: viewModel.airingTodayTV.map { .tv($0) })
                            peopleSection(title: "Popular People", items: viewModel.popularPeople)
                        }
                    } else {
                        searchResultsSection
                    }
                }
                .padding()
            }
            .navigationTitle("Badminton")
            .searchable(text: $searchModel.query, placement: .toolbar, prompt: "Movies, TV, people")
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                #else
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                #endif
            }
            .searchSuggestions {
                let trimmed = searchModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty, !searchModel.history.isEmpty {
                    Section("Recent searches") {
                        ForEach(searchModel.history, id: \.self) { item in
                            Text(item)
                                .searchCompletion(item)
                        }
                        Button("Clear Recent Searches") {
                            searchModel.clearHistory()
                        }
                    }
                }
            }
            .navigationDestination(for: TMDBSearchResultItem.self) { item in
                switch item.mediaType {
                case .tv:
                    TVDetailView(tvID: item.id, title: item.displayTitle, posterPath: item.posterPath)
                case .movie:
                    MovieDetailView(movieID: item.id, title: item.displayTitle, posterPath: item.posterPath)
                case .person:
                    PersonDetailView(personID: item.id, name: item.displayTitle, profilePath: item.profilePath)
                case .unknown:
                    Text("Details coming soon.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
            .task {
                await viewModel.load()
            }
            .task(id: plexAuthManager.authToken) {
                await viewModel.loadPlexHistory(
                    token: plexAuthManager.authToken,
                    preferredServerID: plexAuthManager.preferredServerID,
                    preferredAccountIDs: plexAuthManager.preferredAccountIDs
                )
            }
            .task(id: plexAuthManager.preferredServerID) {
                await viewModel.loadPlexHistory(
                    token: plexAuthManager.authToken,
                    preferredServerID: plexAuthManager.preferredServerID,
                    preferredAccountIDs: plexAuthManager.preferredAccountIDs
                )
            }
            .task(id: plexAuthManager.preferredAccountIDs) {
                await viewModel.loadPlexHistory(
                    token: plexAuthManager.authToken,
                    preferredServerID: plexAuthManager.preferredServerID,
                    preferredAccountIDs: plexAuthManager.preferredAccountIDs
                )
            }
            .refreshable {
                await viewModel.load(force: true)
            }
            .focusedSceneValue(\.badmintonRefreshAction) {
                await viewModel.load(force: true)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if searchModel.isSearching {
                ProgressView("Searching…")
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if searchModel.results.isEmpty {
                VStack {
                    Text("No results")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(searchModel.results) { item in
                        NavigationLink(value: item) {
                            SearchResultRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var plexRecentlyWatchedSection: some View {
        if searchModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           plexAuthManager.isAuthenticated {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recently Watched on Plex")
                    .font(.title2.bold())

                if viewModel.plexIsLoading && viewModel.plexRecentlyWatched.isEmpty {
                    ProgressView("Loading Plex history…")
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if !viewModel.plexRecentlyWatched.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(viewModel.plexRecentlyWatched) { item in
                                NavigationLink {
                                    PlexResolveView(
                                        item: item,
                                        viewModel: viewModel,
                                        searchModel: searchModel,
                                        token: plexAuthManager.authToken,
                                        preferredServerID: plexAuthManager.preferredServerID
                                    )
                                } label: {
                                    PosterCardView(
                                        title: item.title,
                                        subtitle: item.subtitle,
                                        imageURL: item.imageURL
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func trendingSection(title: String, items: [HomeMediaItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(items, id: \.id) { item in
                        NavigationLink {
                            switch item {
                            case .tv:
                                TVDetailView(tvID: item.id, title: item.displayTitle, posterPath: item.posterPath)
                            case .movie:
                                MovieDetailView(movieID: item.id, title: item.displayTitle, posterPath: item.posterPath)
                            }
                        } label: {
                            PosterCardView(
                                title: item.displayTitle,
                                subtitle: item.subtitle,
                                imageURL: viewModel.posterURL(path: item.posterPath)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func peopleSection(title: String, items: [TMDBPersonSummary]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.title2.bold())

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(items) { person in
                            NavigationLink {
                                PersonDetailView(personID: person.id, name: person.name, profilePath: person.profilePath)
                            } label: {
                                PersonCardView(
                                    name: person.name,
                                    subtitle: person.knownForDepartment ?? "",
                                    imageURL: viewModel.profileURL(path: person.profilePath)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

private enum HomeMediaItem {
    case movie(TMDBMovieSummary)
    case tv(TMDBTVSeriesSummary)

    var id: Int {
        switch self {
        case .movie(let movie):
            return movie.id
        case .tv(let tv):
            return tv.id
        }
    }

    var displayTitle: String {
        switch self {
        case .movie(let movie):
            return movie.title
        case .tv(let tv):
            return tv.name
        }
    }

    var subtitle: String {
        switch self {
        case .movie(let movie):
            return TMDBDateFormatter.format(movie.releaseDate) ?? movie.releaseDate ?? ""
        case .tv(let tv):
            return TMDBDateFormatter.format(tv.firstAirDate) ?? tv.firstAirDate ?? ""
        }
    }

    var posterPath: String? {
        switch self {
        case .movie(let movie):
            return movie.posterPath
        case .tv(let tv):
            return tv.posterPath
        }
    }

}

struct PlexRecentlyWatchedItem: Identifiable, Hashable {
    let id: String
    let ratingKey: String
    let type: String?
    let title: String
    let subtitle: String
    let imageURL: URL
    let seriesTitle: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let year: Int?
    let originallyAvailableAt: String?
}

private struct PlexResolveView: View {
    let item: PlexRecentlyWatchedItem
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject var searchModel: SearchViewModel
    let token: String?
    let preferredServerID: String?

    @Environment(\.dismiss) private var dismiss
    @State private var resolvedRoute: PlexNavigationRoute?
    @State private var didFail = false
    @State private var failureDetail: PlexResolveFailure?

    var body: some View {
        Group {
            if let resolvedRoute {
                switch resolvedRoute {
                case .movie(let id, let title, let posterPath):
                    MovieDetailView(movieID: id, title: title, posterPath: posterPath)
                case .tv(let id, let title, let posterPath):
                    TVDetailView(tvID: id, title: title, posterPath: posterPath)
                case .episode(let tvID, let seasonNumber, let episodeNumber, let title, _):
                    EpisodeDetailView(
                        tvID: tvID,
                        seasonNumber: seasonNumber,
                        episodeNumber: episodeNumber,
                        title: title,
                        stillPath: nil
                    )
                }
            } else if didFail {
                VStack(spacing: 12) {
                    Text("Couldn’t resolve this Plex item.")
                        .font(.headline)
                    VStack(spacing: 4) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                        if !item.subtitle.isEmpty {
                            Text(item.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text(unresolvedDetailLine)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    if let failureDetail {
                        VStack(spacing: 4) {
                            Text("Failed at: \(failureDetail.step.label)")
                                .font(.footnote.weight(.semibold))
                            if let reason = failureDetail.reason {
                                Text(reason)
                                    .font(.footnote)
                            }
                            ForEach(failureDetail.notes, id: \.self) { note in
                                Text(note)
                                    .font(.footnote)
                            }
                        }
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    } else {
                        Text("Try searching TMDB or check the Plex metadata.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button("Search TMDB") {
                        let fallbackQuery = item.seriesTitle ?? item.title
                        searchModel.query = fallbackQuery
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ProgressView("Resolving Plex item…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .macOSSwipeToDismiss { dismiss() }
        .task {
            await resolve()
        }
    }

    private func resolve() async {
        guard resolvedRoute == nil, !didFail else { return }
        guard let token, !token.isEmpty else {
            failureDetail = PlexResolveFailure(
                step: .missingToken,
                reason: "Missing or expired Plex auth token.",
                notes: []
            )
            didFail = true
            return
        }
        let result = await viewModel.resolvePlexRoute(
            for: item,
            token: token,
            preferredServerID: preferredServerID
        )
        switch result {
        case .success(let route):
            resolvedRoute = route
        case .failure(let failure):
            failureDetail = failure
            didFail = true
        }
    }

    private var unresolvedDetailLine: String {
        var parts: [String] = []
        if let seriesTitle = item.seriesTitle {
            parts.append(seriesTitle)
        }
        if let season = item.seasonNumber, let episode = item.episodeNumber {
            parts.append("S\(season)E\(episode)")
        }
        if let year = item.year {
            parts.append(String(year))
        }
        if parts.isEmpty {
            return "No additional metadata available."
        }
        return parts.joined(separator: " • ")
    }
}

enum PlexNavigationRoute: Hashable {
    case movie(id: Int, title: String?, posterPath: String?)
    case tv(id: Int, title: String?, posterPath: String?)
    case episode(tvID: Int, seasonNumber: Int, episodeNumber: Int, title: String?, stillPath: String?)
}

enum PlexResolveStep: String, Hashable {
    case missingToken
    case fetchMetadata
    case resolveGuids
    case resolveSearch

    var label: String {
        switch self {
        case .missingToken:
            return "Plex authentication"
        case .fetchMetadata:
            return "Fetch Plex metadata"
        case .resolveGuids:
            return "Resolve external IDs"
        case .resolveSearch:
            return "Search TMDB"
        }
    }
}

struct PlexResolveFailure: Hashable {
    let step: PlexResolveStep
    let reason: String?
    let notes: [String]
}

enum PlexResolveResult: Hashable {
    case success(PlexNavigationRoute)
    case failure(PlexResolveFailure)
}

private struct PlexExternalIDs {
    var tmdbID: Int?
}

private struct PosterCardView: View {
    let title: String
    let subtitle: String
    let imageURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))

                if let imageURL {
                    KFImage(imageURL)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: 140, height: 210)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(title)
                .font(.body.weight(.semibold))
                .lineLimit(2)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 140, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct PersonCardView: View {
    let name: String
    let subtitle: String
    let imageURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.2))

                if let imageURL {
                    KFImage(imageURL)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: 140, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Text(name)
                .font(.body.weight(.semibold))
                .lineLimit(2)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 140, alignment: .leading)
    }
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var trendingMovies: [TMDBMovieSummary] = []
    @Published var trendingTV: [TMDBTVSeriesSummary] = []
    @Published var nowPlayingMovies: [TMDBMovieSummary] = []
    @Published var upcomingMovies: [TMDBMovieSummary] = []
    @Published var onTheAirTV: [TMDBTVSeriesSummary] = []
    @Published var airingTodayTV: [TMDBTVSeriesSummary] = []
    @Published var popularPeople: [TMDBPersonSummary] = []
    @Published var plexRecentlyWatched: [PlexRecentlyWatchedItem] = []
    @Published var plexIsLoading = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let client: TMDBAPIClient
    private let plexClient: PlexAPIClient
    private var imageConfig: TMDBImageConfigValues?
    private var hasLoaded = false
    private var plexTokenLoaded: String?
    private var plexPreferredServerLoaded: String?
    private var plexPreferredAccountLoaded: Set<Int> = []
    private var plexRouteCache: [String: PlexNavigationRoute] = [:]
    private var plexShowIDCache: [String: Int] = [:]

    init(client: TMDBAPIClient = TMDBAPIClient(), plexClient: PlexAPIClient = PlexAPIClient()) {
        self.client = client
        self.plexClient = plexClient
    }

    func load(force: Bool = false) async {
        guard !hasLoaded || force else { return }
        guard !TMDBConfig.apiKey.isEmpty else {
            errorMessage = "Missing TMDB_API_KEY."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            async let config = client.getImageConfiguration()
            async let movies: TMDBPagedResults<TMDBMovieSummary> = client.getV3(path: "/3/trending/movie/day")
            async let tv: TMDBPagedResults<TMDBTVSeriesSummary> = client.getV3(path: "/3/trending/tv/day")
            async let nowPlaying: TMDBPagedResults<TMDBMovieSummary> = client.getV3(path: "/3/movie/now_playing")
            async let upcoming: TMDBPagedResults<TMDBMovieSummary> = client.getV3(path: "/3/movie/upcoming")
            async let onTheAir: TMDBPagedResults<TMDBTVSeriesSummary> = client.getV3(path: "/3/tv/on_the_air")
            async let airingToday: TMDBPagedResults<TMDBTVSeriesSummary> = client.getV3(path: "/3/tv/airing_today")
            async let popularPeople: TMDBPagedResults<TMDBPersonSummary> = client.getV3(path: "/3/person/popular")

            let (configResponse,
                 moviesResponse,
                 tvResponse,
                 nowPlayingResponse,
                 upcomingResponse,
                 onTheAirResponse,
                 airingTodayResponse,
                 popularPeopleResponse) = try await (
                    config,
                    movies,
                    tv,
                    nowPlaying,
                    upcoming,
                    onTheAir,
                    airingToday,
                    popularPeople
                 )
            imageConfig = configResponse.images
            trendingMovies = moviesResponse.results
            trendingTV = tvResponse.results
            nowPlayingMovies = nowPlayingResponse.results
            upcomingMovies = upcomingResponse.results
            onTheAirTV = onTheAirResponse.results
            airingTodayTV = airingTodayResponse.results
            self.popularPeople = popularPeopleResponse.results
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func loadPlexHistory(token: String?, preferredServerID: String?, preferredAccountIDs: Set<Int>) async {
        guard let token, !token.isEmpty else {
            plexRecentlyWatched = []
            plexTokenLoaded = nil
            return
        }

        guard plexTokenLoaded != token
            || plexPreferredServerLoaded != preferredServerID
            || plexPreferredAccountLoaded != preferredAccountIDs
            || plexRecentlyWatched.isEmpty
        else { return }

        plexIsLoading = true
        do {
            let result = try await plexClient.fetchRecentlyWatched(
                token: token,
                size: 500,
                preferredServerID: preferredServerID
            )
            let nowPlayingResult = try? await plexClient.fetchNowPlaying(
                token: token,
                preferredServerID: preferredServerID
            )
            let filteredItems = result.items.filter { item in
                guard !preferredAccountIDs.isEmpty else { return true }
                guard let accountID = item.accountID else { return false }
                return preferredAccountIDs.contains(accountID)
            }
            let nowPlayingItems = (nowPlayingResult?.items ?? []).filter { item in
                guard !preferredAccountIDs.isEmpty else { return true }
                guard let accountID = item.accountID else { return false }
                return preferredAccountIDs.contains(accountID)
            }
            var seenRatingKeys = Set<String>()
            let uniqueFilteredItems = filteredItems.filter { seenRatingKeys.insert($0.id).inserted }
            var seenNowPlaying = Set<String>()
            let uniqueNowPlayingItems = nowPlayingItems.filter { seenNowPlaying.insert($0.id).inserted }

            var nowPlayingSourceIDs: Set<String> = []
            let nowPlayingMapped: [PlexRecentlyWatchedItem] = uniqueNowPlayingItems.compactMap { item in
                guard let imageURL = item.imageURL(serverBaseURL: result.serverBaseURL, token: result.serverToken) else {
                    return nil
                }
                nowPlayingSourceIDs.insert(item.id)
                let subtitle = item.displaySubtitle.isEmpty ? "Now Playing" : "Now Playing • \(item.displaySubtitle)"
                return PlexRecentlyWatchedItem(
                    id: "now-\(item.id)",
                    ratingKey: item.id,
                    type: item.type,
                    title: item.displayTitle,
                    subtitle: subtitle,
                    imageURL: imageURL,
                    seriesTitle: item.grandparentTitle,
                    seasonNumber: item.parentIndex,
                    episodeNumber: item.index,
                    year: item.year,
                    originallyAvailableAt: item.originallyAvailableAt
                )
            }

            let recentMapped: [PlexRecentlyWatchedItem] = uniqueFilteredItems.compactMap { item in
                guard let imageURL = item.imageURL(serverBaseURL: result.serverBaseURL, token: result.serverToken) else {
                    return nil
                }
                return PlexRecentlyWatchedItem(
                    id: item.id,
                    ratingKey: item.id,
                    type: item.type,
                    title: item.displayTitle,
                    subtitle: item.displaySubtitle,
                    imageURL: imageURL,
                    seriesTitle: item.grandparentTitle,
                    seasonNumber: item.parentIndex,
                    episodeNumber: item.index,
                    year: item.year,
                    originallyAvailableAt: item.originallyAvailableAt
                )
            }
            plexRecentlyWatched = nowPlayingMapped + recentMapped.filter { !nowPlayingSourceIDs.contains($0.id) }
            plexTokenLoaded = token
            plexPreferredServerLoaded = preferredServerID
            plexPreferredAccountLoaded = preferredAccountIDs
        } catch {
            plexRecentlyWatched = []
            print("Plex history error: \(error)")
        }
        plexIsLoading = false
    }

    func resolvePlexRoute(for item: PlexRecentlyWatchedItem, token: String, preferredServerID: String?) async -> PlexResolveResult {
        if let cached = plexRouteCache[item.ratingKey] {
            return .success(cached)
        }

        var metadata: PlexMetadataItem?
        var metadataError: String?
        do {
            metadata = try await plexClient.fetchMetadata(
                ratingKey: item.ratingKey,
                token: token,
                preferredServerID: preferredServerID
            )
        } catch {
            metadataError = error.localizedDescription
        }
        let typeHint = (metadata?.type ?? item.type)?.lowercased()
        let isEpisode = typeHint == "episode"
            || (item.seasonNumber != nil && item.episodeNumber != nil && item.seriesTitle != nil)
        var notes: [String] = []
        if let metadataError {
            notes.append("Plex metadata: \(metadataError)")
        }

        if isEpisode {
            return await resolveEpisodeRoute(
                item: item,
                metadata: metadata,
                token: token,
                preferredServerID: preferredServerID,
                notes: notes
            )
        }

        let guidValues = extractGuids(from: metadata)
        if !guidValues.isEmpty {
            do {
                if let route = try await resolveViaGuids(
                    guidValues,
                    typeHint: typeHint,
                    isEpisode: false,
                    item: item
                ) {
                    plexRouteCache[item.ratingKey] = route
                    return .success(route)
                }
                notes.append("External IDs: No TMDB match for this item.")
            } catch {
                return .failure(PlexResolveFailure(
                    step: .resolveGuids,
                    reason: error.localizedDescription,
                    notes: notes
                ))
            }
        } else {
            notes.append("External IDs: None found in Plex metadata.")
        }

        do {
            if let route = try await resolveViaSearch(typeHint: typeHint, item: item) {
                plexRouteCache[item.ratingKey] = route
                return .success(route)
            }
            return .failure(PlexResolveFailure(
                step: .resolveSearch,
                reason: "No TMDB matches for this title.",
                notes: notes
            ))
        } catch {
            return .failure(PlexResolveFailure(
                step: .resolveSearch,
                reason: error.localizedDescription,
                notes: notes
            ))
        }
    }

    private func resolveEpisodeRoute(
        item: PlexRecentlyWatchedItem,
        metadata: PlexMetadataItem?,
        token: String,
        preferredServerID: String?,
        notes: [String]
    ) async -> PlexResolveResult {
        var episodeNotes = notes
        guard let seasonNumber = item.seasonNumber, let episodeNumber = item.episodeNumber else {
            episodeNotes.append("Episode numbers missing in Plex history.")
            return await resolveEpisodeFallback(item: item, notes: episodeNotes)
        }
        if let showRatingKey = metadata?.grandparentRatingKey,
           let cachedShowID = plexShowIDCache[showRatingKey] {
            let route = PlexNavigationRoute.episode(
                tvID: cachedShowID,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber,
                title: item.title,
                stillPath: nil
            )
            plexRouteCache[item.ratingKey] = route
            return .success(route)
        }

        var showGuids: [String] = []
        var showRatingKey: String?
        if let grandparentRatingKey = metadata?.grandparentRatingKey {
            showRatingKey = grandparentRatingKey
            do {
                let showMetadata = try await plexClient.fetchMetadata(
                    ratingKey: grandparentRatingKey,
                    token: token,
                    preferredServerID: preferredServerID
                )
                showGuids = extractGuids(from: showMetadata)
            } catch {
                episodeNotes.append("Show metadata: \(error.localizedDescription)")
            }
        } else {
            episodeNotes.append("Show metadata: Missing grandparent ratingKey.")
        }

        if !showGuids.isEmpty {
            do {
                if let tvID = try await resolveShowID(from: showGuids) {
                    if let showRatingKey {
                        plexShowIDCache[showRatingKey] = tvID
                    }
                    let route = PlexNavigationRoute.episode(
                        tvID: tvID,
                        seasonNumber: seasonNumber,
                        episodeNumber: episodeNumber,
                        title: item.title,
                        stillPath: nil
                    )
                    plexRouteCache[item.ratingKey] = route
                    return .success(route)
                }
                episodeNotes.append("External IDs: No TMDB match for show.")
            } catch {
                return .failure(PlexResolveFailure(
                    step: .resolveGuids,
                    reason: error.localizedDescription,
                    notes: episodeNotes
                ))
            }
        } else {
            episodeNotes.append("External IDs: None found on show.")
        }

        return await resolveEpisodeFallback(item: item, notes: episodeNotes)
    }

    private func resolveEpisodeFallback(item: PlexRecentlyWatchedItem, notes: [String]) async -> PlexResolveResult {
        do {
            if let route = try await resolveViaSearch(typeHint: "episode", item: item) {
                plexRouteCache[item.ratingKey] = route
                return .success(route)
            }
            return .failure(PlexResolveFailure(
                step: .resolveSearch,
                reason: "No TMDB matches for this title.",
                notes: notes
            ))
        } catch {
            return .failure(PlexResolveFailure(
                step: .resolveSearch,
                reason: error.localizedDescription,
                notes: notes
            ))
        }
    }

    private func resolveViaGuids(
        _ guids: [String],
        typeHint: String?,
        isEpisode: Bool,
        item: PlexRecentlyWatchedItem
    ) async throws -> PlexNavigationRoute? {
        let parsed = parseExternalIDs(from: guids)
        if let tmdbID = parsed.tmdbID, !isEpisode {
            if typeHint == "movie" {
                return .movie(id: tmdbID, title: item.title, posterPath: nil)
            }
            return .tv(id: tmdbID, title: item.seriesTitle ?? item.title, posterPath: nil)
        }

        return nil
    }

    private func resolveShowID(from guids: [String]) async throws -> Int? {
        let parsed = parseExternalIDs(from: guids)
        if let tmdbID = parsed.tmdbID {
            return tmdbID
        }
        return nil
    }

    private func resolveViaSearch(typeHint: String?, item: PlexRecentlyWatchedItem) async throws -> PlexNavigationRoute? {
        if typeHint == "movie" {
            let response: TMDBPagedResults<TMDBMovieSummary> = try await client.getV3(
                path: "/3/search/movie",
                queryItems: movieSearchQueryItems(title: item.title, year: item.year)
            )
            if let movie = response.results.first {
                return .movie(id: movie.id, title: movie.title, posterPath: movie.posterPath)
            }
            return nil
        }

        let query = item.seriesTitle ?? item.title
        let response: TMDBPagedResults<TMDBTVSeriesSummary> = try await client.getV3(
            path: "/3/search/tv",
            queryItems: tvSearchQueryItems(title: query, year: inferredYear(from: item))
        )
        guard let tv = response.results.first else { return nil }
        if let seasonNumber = item.seasonNumber,
           let episodeNumber = item.episodeNumber {
            return .episode(tvID: tv.id, seasonNumber: seasonNumber, episodeNumber: episodeNumber, title: item.title, stillPath: nil)
        }
        return .tv(id: tv.id, title: tv.name, posterPath: tv.posterPath)
    }

    private func inferredYear(from item: PlexRecentlyWatchedItem) -> Int? {
        if let year = item.year { return year }
        return parseYear(from: item.originallyAvailableAt)
    }

    private func movieSearchQueryItems(title: String, year: Int?) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "query", value: title),
            URLQueryItem(name: "include_adult", value: "false")
        ]
        if let year {
            items.append(URLQueryItem(name: "year", value: String(year)))
        }
        return items
    }

    private func tvSearchQueryItems(title: String, year: Int?) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "query", value: title),
            URLQueryItem(name: "include_adult", value: "false")
        ]
        if let year {
            items.append(URLQueryItem(name: "first_air_date_year", value: String(year)))
        }
        return items
    }

    private func parseExternalIDs(from guids: [String]) -> PlexExternalIDs {
        var result = PlexExternalIDs()
        for guid in guids {
            if let tmdbID = extractExternalID(from: guid, prefixes: ["com.plexapp.agents.themoviedb://", "themoviedb://", "tmdb://"]) {
                result.tmdbID = Int(tmdbID)
            }
        }
        return result
    }

    private func extractGuids(from metadata: PlexMetadataItem?) -> [String] {
        guard let metadata else { return [] }
        var guidValues: [String] = []
        if let guid = metadata.guid {
            guidValues.append(guid)
        }
        if let guids = metadata.guids {
            guidValues.append(contentsOf: guids.map(\.id))
        }
        return guidValues
    }

    private func extractExternalID(from guid: String, prefixes: [String]) -> String? {
        let lower = guid.lowercased()
        for prefix in prefixes {
            if let range = lower.range(of: prefix) {
                let original = lower[range.upperBound...]
                let trimmed = original.split(separator: "?").first ?? original[...]
                let value = trimmed.split(separator: "/").first.map(String.init) ?? String(trimmed)
                if !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    private func parseYear(from dateString: String?) -> Int? {
        guard let dateString, dateString.count >= 4 else { return nil }
        let prefix = dateString.prefix(4)
        return Int(prefix)
    }

    func posterURL(path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        let cleanedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let baseURL = imageConfig?.secureBaseUrl ?? "https://image.tmdb.org/t/p/"
        let size = preferredSize(from: imageConfig?.posterSizes, fallback: "w342")
        return URL(string: baseURL)?.appendingPathComponent(size).appendingPathComponent(cleanedPath)
    }

    func profileURL(path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        let cleanedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let baseURL = imageConfig?.secureBaseUrl ?? "https://image.tmdb.org/t/p/"
        let size = preferredSize(from: imageConfig?.profileSizes, fallback: "w185")
        return URL(string: baseURL)?.appendingPathComponent(size).appendingPathComponent(cleanedPath)
    }

    private func preferredSize(from sizes: [String]?, fallback: String) -> String {
        guard let sizes, !sizes.isEmpty else { return fallback }
        if sizes.contains(fallback) {
            return fallback
        }
        return sizes.last ?? fallback
    }
}

#Preview {
    HomeView()
}
