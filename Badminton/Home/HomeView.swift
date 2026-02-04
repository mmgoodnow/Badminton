import Combine
import os
import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @StateObject private var searchModel = SearchViewModel()
    @EnvironmentObject private var plexAuthManager: PlexAuthManager
    @EnvironmentObject private var overseerrAuthManager: OverseerrAuthManager
    @EnvironmentObject private var overseerrLibraryIndex: OverseerrLibraryIndex
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSettings = false
    @State private var navigationPath = NavigationPath()
    @State private var plexResolvingItem: PlexRecentlyWatchedItem?
    @State private var plexFailureContext: PlexResolveFailureContext?
    @State private var lastPlexVisibilityRefresh = Date.distantPast

    var body: some View {
        NavigationStack(path: $navigationPath) {
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
            .navigationDestination(for: TMDBNavigationRoute.self) { route in
                switch route {
                case .movie(let id, let title, let posterPath):
                    MovieDetailView(movieID: id, title: title, posterPath: posterPath)
                case .tv(let id, let title, let posterPath):
                    TVDetailView(tvID: id, title: title, posterPath: posterPath)
                case .person(let id, let name, let profilePath):
                    PersonDetailView(personID: id, name: name, profilePath: profilePath)
                }
            }
            .navigationDestination(for: PlexNavigationRoute.self) { route in
                switch route {
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
            }
            .task {
                await viewModel.load()
                await overseerrLibraryIndex.refreshIfNeeded(
                    baseURL: overseerrAuthManager.baseURL,
                    cookie: overseerrAuthManager.authCookie()
                )
            }
            .task(id: overseerrAuthManager.isAuthenticated) {
                await overseerrLibraryIndex.refreshIfNeeded(
                    baseURL: overseerrAuthManager.baseURL,
                    cookie: overseerrAuthManager.authCookie()
                )
            }
            .task(id: overseerrAuthManager.baseURLString) {
                await overseerrLibraryIndex.refreshIfNeeded(
                    baseURL: overseerrAuthManager.baseURL,
                    cookie: overseerrAuthManager.authCookie()
                )
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
                await refreshAll(force: true)
            }
#if os(macOS) || targetEnvironment(macCatalyst)
            .focusedSceneValue(\.badmintonRefreshAction) {
                await refreshAll(force: true)
            }
#endif
            .onChange(of: scenePhase) { newPhase in
                guard newPhase == .active else { return }
                let now = Date()
                guard now.timeIntervalSince(lastPlexVisibilityRefresh) > 1 else { return }
                lastPlexVisibilityRefresh = now
                Task {
                    await viewModel.refreshPlexNowPlaying(
                        token: plexAuthManager.authToken,
                        preferredServerID: plexAuthManager.preferredServerID,
                        preferredAccountIDs: plexAuthManager.preferredAccountIDs
                    )
                    await overseerrLibraryIndex.refreshIfNeeded(
                        baseURL: overseerrAuthManager.baseURL,
                        cookie: overseerrAuthManager.authCookie()
                    )
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(item: $plexFailureContext) { context in
                PlexResolveFailureSheet(
                    item: context.item,
                    failure: context.failure
                ) {
                    let fallbackQuery = context.item.seriesTitle ?? context.item.title
                    searchModel.query = fallbackQuery
                }
            }
            .overlay {
                if let plexResolvingItem {
                    PlexResolveOverlay(item: plexResolvingItem)
                }
            }
        }
    }

    @MainActor
    private func refreshAll(force: Bool) async {
        await viewModel.load(force: force)
        await viewModel.loadPlexHistory(
            token: plexAuthManager.authToken,
            preferredServerID: plexAuthManager.preferredServerID,
            preferredAccountIDs: plexAuthManager.preferredAccountIDs,
            force: force
        )
        await overseerrLibraryIndex.refresh(
            baseURL: overseerrAuthManager.baseURL,
            cookie: overseerrAuthManager.authCookie(),
            force: force
        )
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
                let nowPlaying = viewModel.plexNowPlaying
                let recent = viewModel.plexRecent
                let hasItems = !nowPlaying.isEmpty || !recent.isEmpty

                if viewModel.plexIsLoading && !hasItems {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 24) {
                            plexColumnSkeleton(title: "Now Playing")
                            plexColumnSkeleton(title: "Recent")
                        }
                        .padding(.vertical, 4)
                    }
                } else if !nowPlaying.isEmpty && !recent.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 24) {
                            plexRailColumn(title: "Now Playing", items: nowPlaying)
                            plexRailColumn(title: "Recent", items: recent)
                        }
                        .padding(.vertical, 4)
                    }
                } else if !nowPlaying.isEmpty {
                    plexRailColumn(title: "Now Playing", items: nowPlaying)
                } else if !recent.isEmpty {
                    plexRailColumn(title: "Recent", items: recent)
                }
            }
        }
    }

    private func plexRailColumn(title: String, items: [PlexRecentlyWatchedItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(items) { item in
                        Button {
                            handlePlexSelection(item)
                        } label: {
                            ListPosterCard(
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func plexColumnSkeleton(title: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())
                .redacted(reason: .placeholder)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(0..<6, id: \.self) { _ in
                        PlexPosterSkeleton()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func trendingSection(title: String, items: [HomeMediaItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.bold())

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(items, id: \.id) { item in
                        Button {
                            switch item {
                            case .tv:
                                Signpost.event(
                                    "TMDBTVTap",
                                    log: SignpostLog.navigation,
                                    "id=%{public}d title=%{public}@",
                                    item.id,
                                    item.displayTitle
                                )
                                AppLog.navigation.info(
                                    "TMDBTVTap id=\(item.id, privacy: .public) title=\(item.displayTitle, privacy: .public)"
                                )
                                navigationPath.append(
                                    TMDBNavigationRoute.tv(
                                        id: item.id,
                                        title: item.displayTitle,
                                        posterPath: item.posterPath
                                    )
                                )
                            case .movie:
                                navigationPath.append(
                                    TMDBNavigationRoute.movie(
                                        id: item.id,
                                        title: item.displayTitle,
                                        posterPath: item.posterPath
                                    )
                                )
                            }
                        } label: {
                            ListPosterCard(
                                title: item.displayTitle,
                                subtitle: item.subtitle,
                                imageURL: viewModel.posterURL(path: item.posterPath),
                                showDogEar: overseerrLibraryIndex.isAvailable(tmdbID: item.id)
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
                            Button {
                                navigationPath.append(
                                    TMDBNavigationRoute.person(
                                        id: person.id,
                                        name: person.name,
                                        profilePath: person.profilePath
                                    )
                                )
                            } label: {
                                ListPosterCard(
                                    title: person.name,
                                    subtitle: person.knownForDepartment ?? "",
                                    imageURL: viewModel.profileURL(path: person.profilePath),
                                    posterSize: CGSize(width: 140, height: 200),
                                    posterCornerRadius: 16
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

    private func handlePlexSelection(_ item: PlexRecentlyWatchedItem) {
        guard plexResolvingItem == nil else { return }
        if let cachedRoute = viewModel.cachedPlexRoute(for: item) {
            navigationPath.append(cachedRoute)
            return
        }
        guard let token = plexAuthManager.authToken, !token.isEmpty else {
            plexFailureContext = PlexResolveFailureContext(
                item: item,
                failure: PlexResolveFailure(
                    step: .missingToken,
                    reason: "Missing or expired Plex auth token.",
                    notes: []
                )
            )
            return
        }
        plexResolvingItem = item
        Task {
            let result = await viewModel.resolvePlexRoute(
                for: item,
                token: token,
                preferredServerID: plexAuthManager.preferredServerID
            )
            await MainActor.run {
                plexResolvingItem = nil
                switch result {
                case .success(let route):
                    navigationPath.append(route)
                case .failure(let failure):
                    plexFailureContext = PlexResolveFailureContext(item: item, failure: failure)
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

private enum TMDBNavigationRoute: Hashable {
    case movie(id: Int, title: String?, posterPath: String?)
    case tv(id: Int, title: String?, posterPath: String?)
    case person(id: Int, name: String?, profilePath: String?)
}

struct PlexRecentlyWatchedItem: Identifiable, Hashable {
    let id: String
    let ratingKey: String
    let type: String?
    let title: String
    let subtitle: String
    let detailSubtitle: String
    let imageURL: URL
    let tmdbPosterFileName: String?
    let seriesTitle: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let year: Int?
    let originallyAvailableAt: String?
    let showRatingKey: String?
    let sessionKey: String?
    let viewOffset: Int?
    let duration: Int?

    var isEpisode: Bool {
        type?.lowercased() == "episode"
            || (seasonNumber != nil && episodeNumber != nil && seriesTitle != nil)
    }

    var progress: Double? {
        guard let viewOffset, let duration, duration > 0 else { return nil }
        let fraction = Double(viewOffset) / Double(duration)
        return min(max(fraction, 0), 1)
    }

    var liveActivityID: String {
        "plex-\(sessionKey ?? ratingKey)"
    }

    func settingTMDBPosterFileName(_ fileName: String?) -> PlexRecentlyWatchedItem {
        PlexRecentlyWatchedItem(
            id: id,
            ratingKey: ratingKey,
            type: type,
            title: title,
            subtitle: subtitle,
            detailSubtitle: detailSubtitle,
            imageURL: imageURL,
            tmdbPosterFileName: fileName,
            seriesTitle: seriesTitle,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            year: year,
            originallyAvailableAt: originallyAvailableAt,
            showRatingKey: showRatingKey,
            sessionKey: sessionKey,
            viewOffset: viewOffset,
            duration: duration
        )
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

struct PlexResolveFailureContext: Identifiable {
    let id = UUID()
    let item: PlexRecentlyWatchedItem
    let failure: PlexResolveFailure
}

enum PlexResolveResult: Hashable {
    case success(PlexNavigationRoute)
    case failure(PlexResolveFailure)
}

private struct PlexExternalIDs {
    var tmdbID: Int?
}

private struct PlexResolveFailureSheet: View {
    let item: PlexRecentlyWatchedItem
    let failure: PlexResolveFailure
    let onSearch: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
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

            VStack(spacing: 4) {
                Text("Failed at: \(failure.step.label)")
                    .font(.footnote.weight(.semibold))
                if let reason = failure.reason {
                    Text(reason)
                        .font(.footnote)
                }
                ForEach(failure.notes, id: \.self) { note in
                    Text(note)
                        .font(.footnote)
                }
            }
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Close") {
                    dismiss()
                }
                Button("Search TMDB") {
                    onSearch()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 320)
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

private struct PlexResolveOverlay: View {
    let item: PlexRecentlyWatchedItem

    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text("Resolving \(item.title)…")
                    .font(.headline)
            }
            .padding(20)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .transition(.opacity)
    }
}

private struct PlexPosterSkeleton: View {
    @Environment(\.listItemStyle) private var style

    var body: some View {
        let posterSize = style.cardPosterSize
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
                .frame(width: posterSize.width, height: posterSize.height)

            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.2))
                .frame(width: posterSize.width * 0.85, height: 14)

            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.2))
                .frame(width: posterSize.width * 0.65, height: 12)
        }
        .redacted(reason: .placeholder)
        .frame(width: posterSize.width, alignment: .leading)
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
    @Published var plexNowPlaying: [PlexRecentlyWatchedItem] = []
    @Published var plexRecent: [PlexRecentlyWatchedItem] = []
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
    private var plexPrefetchedKeys: Set<String> = []
    private var plexPrefetchTask: Task<Void, Never>?
    private var plexTMDBPosterCache: [String: String] = [:]
    private var plexTMDBPosterFailures: Set<String> = []
    private var plexNowPlayingArtworkTask: Task<Void, Never>?
    private let plexAccountResolver = PlexAccountResolver.shared
#if os(iOS)
    private let plexLiveActivityManager = PlexNowPlayingLiveActivityManager()
#endif

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
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func loadPlexHistory(
        token: String?,
        preferredServerID: String?,
        preferredAccountIDs: Set<Int>,
        force: Bool = false
    ) async {
        guard let token, !token.isEmpty else {
            plexNowPlaying = []
            plexRecent = []
            plexTokenLoaded = nil
            plexPreferredServerLoaded = nil
            plexPreferredAccountLoaded = []
            plexNowPlayingArtworkTask?.cancel()
#if os(iOS)
            plexLiveActivityManager.sync(nowPlaying: plexNowPlaying)
#endif
            return
        }

        if !force {
            guard plexTokenLoaded != token
                || plexPreferredServerLoaded != preferredServerID
                || plexPreferredAccountLoaded != preferredAccountIDs
                || (plexNowPlaying.isEmpty && plexRecent.isEmpty)
            else { return }
        }

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
            let historyAccountIDs = Set(result.items.compactMap { $0.accountID ?? $0.userID })
            let nowPlayingAccountIDs = Set((nowPlayingResult?.items ?? []).compactMap { $0.accountID ?? $0.userID })
            let candidateAccountIDs = historyAccountIDs.union(nowPlayingAccountIDs)
            let matchesPreferredAccount = await preferredAccountMatcher(
                token: token,
                preferredAccountIDs: preferredAccountIDs,
                candidateAccountIDs: candidateAccountIDs
            )
            let filteredItems = result.items.filter { item in
                matchesPreferredAccount(item)
            }
            let nowPlayingItems = (nowPlayingResult?.items ?? []).filter { item in
                matchesPreferredAccount(item)
            }
            var seenRatingKeys = Set<String>()
            let uniqueFilteredItems = filteredItems.filter { seenRatingKeys.insert($0.id).inserted }
            let limitedFilteredItems = limitRecentEpisodes(items: uniqueFilteredItems)
            var seenNowPlaying = Set<String>()
            let uniqueNowPlayingItems = nowPlayingItems.filter { item in
                let key = item.sessionKey ?? item.id
                return seenNowPlaying.insert(key).inserted
            }

            let nowPlayingBaseURL = nowPlayingResult?.serverBaseURL ?? result.serverBaseURL
            let nowPlayingToken = nowPlayingResult?.serverToken ?? result.serverToken
            let nowPlayingPayload = mapNowPlayingItems(
                items: uniqueNowPlayingItems,
                serverBaseURL: nowPlayingBaseURL,
                serverToken: nowPlayingToken
            )

            let recentMapped: [PlexRecentlyWatchedItem] = limitedFilteredItems.compactMap { item in
                guard let imageURL = item.imageURL(serverBaseURL: result.serverBaseURL, token: result.serverToken) else {
                    return nil
                }
                let display = plexDisplayInfo(for: item)
                let showRatingKey = parseRatingKey(from: item.grandparentKey)
                return PlexRecentlyWatchedItem(
                    id: item.id,
                    ratingKey: item.id,
                    type: item.type,
                    title: display.title,
                    subtitle: display.subtitle,
                    detailSubtitle: display.subtitle,
                    imageURL: imageURL,
                    tmdbPosterFileName: nil,
                    seriesTitle: item.grandparentTitle,
                    seasonNumber: item.parentIndex,
                    episodeNumber: item.index,
                    year: item.year,
                    originallyAvailableAt: item.originallyAvailableAt,
                    showRatingKey: showRatingKey,
                    sessionKey: nil,
                    viewOffset: nil,
                    duration: nil
                )
            }
            plexNowPlaying = nowPlayingPayload.items
            plexRecent = recentMapped.filter { !nowPlayingPayload.sourceIDs.contains($0.id) }
            plexTokenLoaded = token
            plexPreferredServerLoaded = preferredServerID
            plexPreferredAccountLoaded = preferredAccountIDs
            startPlexPrefetch(token: token, preferredServerID: preferredServerID)
            startPlexNowPlayingArtworkResolution(
                items: plexNowPlaying,
                token: token,
                preferredServerID: preferredServerID
            )
#if os(iOS)
            plexLiveActivityManager.sync(nowPlaying: plexNowPlaying)
#endif
        } catch is CancellationError {
            plexIsLoading = false
            return
        } catch let error as URLError where error.code == .cancelled {
            plexIsLoading = false
            return
        } catch {
            plexNowPlaying = []
            plexRecent = []
            print("Plex history error: \(error)")
#if os(iOS)
            plexLiveActivityManager.sync(nowPlaying: plexNowPlaying)
#endif
        }
        plexIsLoading = false
    }

    func refreshPlexNowPlaying(
        token: String?,
        preferredServerID: String?,
        preferredAccountIDs: Set<Int>
    ) async {
        guard let token, !token.isEmpty else {
            plexNowPlaying = []
            plexNowPlayingArtworkTask?.cancel()
#if os(iOS)
            plexLiveActivityManager.sync(nowPlaying: plexNowPlaying)
#endif
            return
        }

        if plexTokenLoaded != token
            || plexPreferredServerLoaded != preferredServerID
            || plexPreferredAccountLoaded != preferredAccountIDs
            || plexRecent.isEmpty {
            await loadPlexHistory(
                token: token,
                preferredServerID: preferredServerID,
                preferredAccountIDs: preferredAccountIDs,
                force: true
            )
            return
        }

        do {
            let nowPlayingResult = try await plexClient.fetchNowPlaying(
                token: token,
                preferredServerID: preferredServerID
            )
            let candidateAccountIDs = Set(nowPlayingResult.items.compactMap { $0.accountID ?? $0.userID })
            let matchesPreferredAccount = await preferredAccountMatcher(
                token: token,
                preferredAccountIDs: preferredAccountIDs,
                candidateAccountIDs: candidateAccountIDs
            )
            let nowPlayingItems = nowPlayingResult.items.filter { item in
                matchesPreferredAccount(item)
            }
            var seenNowPlaying = Set<String>()
            let uniqueNowPlayingItems = nowPlayingItems.filter { item in
                let key = item.sessionKey ?? item.id
                return seenNowPlaying.insert(key).inserted
            }
            let nowPlayingPayload = mapNowPlayingItems(
                items: uniqueNowPlayingItems,
                serverBaseURL: nowPlayingResult.serverBaseURL,
                serverToken: nowPlayingResult.serverToken
            )
            plexNowPlaying = nowPlayingPayload.items
            plexRecent = plexRecent.filter { !nowPlayingPayload.sourceIDs.contains($0.id) }
            startPlexNowPlayingArtworkResolution(
                items: plexNowPlaying,
                token: token,
                preferredServerID: preferredServerID
            )
#if os(iOS)
            plexLiveActivityManager.sync(nowPlaying: plexNowPlaying)
#endif
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            print("Plex now playing error: \(error)")
        }
    }

    private func preferredAccountMatcher(
        token: String,
        preferredAccountIDs: Set<Int>,
        candidateAccountIDs: Set<Int>
    ) async -> (PlexHistoryItem) -> Bool {
        guard !preferredAccountIDs.isEmpty else {
            return { _ in true }
        }

        let homeUsers = (try? await plexClient.fetchHomeUsers(token: token)) ?? []
        let criteria = await plexAccountResolver.matchCriteria(
            preferredHomeUserIDs: preferredAccountIDs,
            homeUsers: homeUsers,
            candidateAccountIDs: candidateAccountIDs,
            token: token
        )

        return { item in
            if let accountID = item.accountID ?? item.userID,
               criteria.matchingAccountIDs.contains(accountID) {
                return true
            }
            if criteria.matches(userTitle: item.userTitle) {
                return true
            }
            return false
        }
    }

    private func mapNowPlayingItems(
        items: [PlexHistoryItem],
        serverBaseURL: URL,
        serverToken: String
    ) -> (items: [PlexRecentlyWatchedItem], sourceIDs: Set<String>) {
        var sourceIDs: Set<String> = []
        let mapped = items.compactMap { item -> PlexRecentlyWatchedItem? in
            guard let imageURL = item.imageURL(serverBaseURL: serverBaseURL, token: serverToken) else {
                return nil
            }
            sourceIDs.insert(item.id)
            let display = plexDisplayInfo(for: item)
            let subtitle = display.subtitle.isEmpty ? "Now Playing" : "Now Playing • \(display.subtitle)"
            let showRatingKey = parseRatingKey(from: item.grandparentKey)
            return PlexRecentlyWatchedItem(
                id: "now-\(item.sessionKey ?? item.id)",
                ratingKey: item.id,
                type: item.type,
                title: display.title,
                subtitle: subtitle,
                detailSubtitle: display.subtitle,
                imageURL: imageURL,
                tmdbPosterFileName: nil,
                seriesTitle: item.grandparentTitle,
                seasonNumber: item.parentIndex,
                episodeNumber: item.index,
                year: item.year,
                originallyAvailableAt: item.originallyAvailableAt,
                showRatingKey: showRatingKey,
                sessionKey: item.sessionKey,
                viewOffset: item.viewOffset,
                duration: item.duration
            )
        }
        return (mapped, sourceIDs)
    }

    private func startPlexNowPlayingArtworkResolution(
        items: [PlexRecentlyWatchedItem],
        token: String,
        preferredServerID: String?
    ) {
        plexNowPlayingArtworkTask?.cancel()
        guard !items.isEmpty else { return }
        plexNowPlayingArtworkTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.resolveNowPlayingTMDBArtwork(
                items: items,
                token: token,
                preferredServerID: preferredServerID
            )
        }
    }

    private func resolveNowPlayingTMDBArtwork(
        items: [PlexRecentlyWatchedItem],
        token: String,
        preferredServerID: String?
    ) async {
        guard !items.isEmpty else { return }
        var updates: [String: String] = [:]

        for item in items {
            if Task.isCancelled { return }
            if item.tmdbPosterFileName != nil {
                continue
            }
            if let cached = plexTMDBPosterCache[item.ratingKey] {
                updates[item.ratingKey] = cached
                continue
            }
            if plexTMDBPosterFailures.contains(item.ratingKey) {
                continue
            }
            if let url = await resolveTMDBPosterURL(
                for: item,
                token: token,
                preferredServerID: preferredServerID
            ) {
                if let fileName = await storeTMDBPoster(url, for: item) {
                    updates[item.ratingKey] = fileName
                } else {
                    plexTMDBPosterFailures.insert(item.ratingKey)
                    print("TMDB artwork download failed for \(item.title)")
                }
            } else {
                plexTMDBPosterFailures.insert(item.ratingKey)
                print("TMDB artwork unavailable for \(item.title)")
            }
        }

        guard !updates.isEmpty else { return }
        plexTMDBPosterCache.merge(updates) { _, new in new }
        let updatedNowPlaying = plexNowPlaying.map { item in
            guard item.tmdbPosterFileName == nil, let fileName = updates[item.ratingKey] else { return item }
            return item.settingTMDBPosterFileName(fileName)
        }
        plexNowPlaying = updatedNowPlaying
#if os(iOS)
        plexLiveActivityManager.sync(nowPlaying: plexNowPlaying)
#endif
    }

    private func resolveTMDBPosterURL(
        for item: PlexRecentlyWatchedItem,
        token: String,
        preferredServerID: String?
    ) async -> URL? {
        let typeHint = item.type?.lowercased()
        let isEpisode = item.isEpisode || typeHint == "episode"
        var tmdbID: Int?
        var tmdbType: String?
        var posterPath: String?

        if let cachedRoute = plexRouteCache[item.ratingKey] {
            switch cachedRoute {
            case .movie(let id, _, let cachedPosterPath):
                tmdbID = id
                tmdbType = "movie"
                posterPath = cachedPosterPath
            case .tv(let id, _, let cachedPosterPath):
                tmdbID = id
                tmdbType = "tv"
                posterPath = cachedPosterPath
            case .episode(let tvID, _, _, _, _):
                tmdbID = tvID
                tmdbType = "tv"
            }
        }

        if isEpisode,
           tmdbID == nil,
           let showRatingKey = item.showRatingKey,
           let cachedShowID = plexShowIDCache[showRatingKey] {
            tmdbID = cachedShowID
            tmdbType = "tv"
        }

        if posterPath == nil {
            var metadata: PlexMetadataItem?
            do {
                metadata = try await plexClient.fetchMetadata(
                    ratingKey: item.ratingKey,
                    token: token,
                    preferredServerID: preferredServerID
                )
            } catch {
                print("TMDB artwork Plex metadata failed for \(item.title): \(error)")
            }

            let metadataType = metadata?.type?.lowercased()
            if tmdbType == nil {
                switch metadataType {
                case "movie":
                    tmdbType = "movie"
                case "show", "episode":
                    tmdbType = "tv"
                default:
                    if typeHint == "movie" {
                        tmdbType = "movie"
                    } else if isEpisode || typeHint == "show" {
                        tmdbType = "tv"
                    }
                }
            }

            let guidValues = Self.extractGuids(from: metadata)
            if let parsedID = Self.parseExternalIDs(from: guidValues).tmdbID {
                tmdbID = parsedID
                if let tmdbType, !isEpisode, plexRouteCache[item.ratingKey] == nil {
                    let route: PlexNavigationRoute = tmdbType == "movie"
                    ? .movie(id: parsedID, title: item.title, posterPath: nil)
                    : .tv(id: parsedID, title: item.seriesTitle ?? item.title, posterPath: nil)
                    plexRouteCache[item.ratingKey] = route
                }
            }

            if isEpisode, tmdbID == nil {
                let showRatingKey = item.showRatingKey ?? metadata?.grandparentRatingKey
                if let showRatingKey {
                    do {
                        let showMetadata = try await plexClient.fetchMetadata(
                            ratingKey: showRatingKey,
                            token: token,
                            preferredServerID: preferredServerID
                        )
                        let showGuids = Self.extractGuids(from: showMetadata)
                        if let showTMDB = Self.parseExternalIDs(from: showGuids).tmdbID {
                            tmdbID = showTMDB
                            tmdbType = "tv"
                            plexShowIDCache[showRatingKey] = showTMDB
                        }
                    } catch {
                        print("TMDB artwork show metadata failed for \(item.title): \(error)")
                    }
                }
            }
        }

        if posterPath == nil, let tmdbID, let tmdbType {
            do {
                if tmdbType == "movie" {
                    let detail: TMDBMovieDetail = try await client.getV3(path: "/3/movie/\(tmdbID)")
                    posterPath = detail.posterPath
                } else {
                    let detail: TMDBTVSeriesDetail = try await client.getV3(path: "/3/tv/\(tmdbID)")
                    posterPath = detail.posterPath
                }
            } catch {
                print("TMDB artwork detail fetch failed for \(item.title): \(error)")
            }
        }

        if posterPath == nil {
            do {
                if tmdbType == "movie" || typeHint == "movie" {
                    let response: TMDBPagedResults<TMDBMovieSummary> = try await client.getV3(
                        path: "/3/search/movie",
                        queryItems: movieSearchQueryItems(title: item.title, year: item.year)
                    )
                    if let movie = response.results.first {
                        posterPath = movie.posterPath
                        if plexRouteCache[item.ratingKey] == nil {
                            plexRouteCache[item.ratingKey] = .movie(
                                id: movie.id,
                                title: movie.title,
                                posterPath: movie.posterPath
                            )
                        }
                    }
                } else {
                    let query = item.seriesTitle ?? item.title
                    let response: TMDBPagedResults<TMDBTVSeriesSummary> = try await client.getV3(
                        path: "/3/search/tv",
                        queryItems: tvSearchQueryItems(title: query, year: inferredYear(from: item))
                    )
                    if let tv = response.results.first {
                        posterPath = tv.posterPath
                        if isEpisode, let showRatingKey = item.showRatingKey {
                            plexShowIDCache[showRatingKey] = tv.id
                        } else if plexRouteCache[item.ratingKey] == nil {
                            plexRouteCache[item.ratingKey] = .tv(
                                id: tv.id,
                                title: tv.name,
                                posterPath: tv.posterPath
                            )
                        }
                    }
                }
            } catch {
                print("TMDB artwork search failed for \(item.title): \(error)")
            }
        }

        guard let posterPath else { return nil }
        return posterURL(path: posterPath)
    }

    private func storeTMDBPoster(_ url: URL, for item: PlexRecentlyWatchedItem) async -> String? {
        let safeKey = item.ratingKey.replacingOccurrences(of: "/", with: "-")
        let fileName = "tmdb-\(safeKey)-\(url.lastPathComponent)"
        if let existingURL = LiveActivityArtworkStore.fileURL(for: fileName),
           FileManager.default.fileExists(atPath: existingURL.path) {
            return fileName
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            guard LiveActivityArtworkStore.store(data: data, fileName: fileName) != nil else {
                return nil
            }
            return fileName
        } catch {
            print("TMDB artwork download error for \(item.title): \(error)")
            return nil
        }
    }

    func resolvePlexRoute(for item: PlexRecentlyWatchedItem, token: String, preferredServerID: String?) async -> PlexResolveResult {
        if let cached = plexRouteCache[item.ratingKey] {
            return .success(cached)
        }

        if item.isEpisode,
           let showRatingKey = item.showRatingKey,
           let cachedShowID = plexShowIDCache[showRatingKey],
           let seasonNumber = item.seasonNumber,
           let episodeNumber = item.episodeNumber {
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
        let isEpisode = typeHint == "episode" || item.isEpisode
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

        let guidValues = Self.extractGuids(from: metadata)
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
        let showRatingKey = item.showRatingKey ?? metadata?.grandparentRatingKey
        if let showRatingKey,
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
        if let showRatingKey {
            do {
                let showMetadata = try await plexClient.fetchMetadata(
                    ratingKey: showRatingKey,
                    token: token,
                    preferredServerID: preferredServerID
                )
                showGuids = Self.extractGuids(from: showMetadata)
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
        let parsed = Self.parseExternalIDs(from: guids)
        if let tmdbID = parsed.tmdbID, !isEpisode {
            if typeHint == "movie" {
                return .movie(id: tmdbID, title: item.title, posterPath: nil)
            }
            return .tv(id: tmdbID, title: item.seriesTitle ?? item.title, posterPath: nil)
        }

        return nil
    }

    private func resolveShowID(from guids: [String]) async throws -> Int? {
        let parsed = Self.parseExternalIDs(from: guids)
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

    private static func parseExternalIDs(from guids: [String]) -> PlexExternalIDs {
        var result = PlexExternalIDs()
        for guid in guids {
            if let tmdbID = extractExternalID(from: guid, prefixes: ["com.plexapp.agents.themoviedb://", "themoviedb://", "tmdb://"]) {
                result.tmdbID = Int(tmdbID)
            }
        }
        return result
    }

    private static func extractGuids(from metadata: PlexMetadataItem?) -> [String] {
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

    private static func extractExternalID(from guid: String, prefixes: [String]) -> String? {
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

    private func parseRatingKey(from key: String?) -> String? {
        guard let key else { return nil }
        let trimmed = key.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = trimmed.split(separator: "/")
        return parts.last.map(String.init)
    }

    private func limitRecentEpisodes(items: [PlexHistoryItem], limitPerShow: Int = 3) -> [PlexHistoryItem] {
        var episodeCounts: [String: Int] = [:]
        return items.filter { item in
            guard item.type?.lowercased() == "episode" else { return true }
            let key = item.grandparentKey
                ?? item.grandparentTitle
                ?? item.parentTitle
                ?? item.title
                ?? item.id
            let count = episodeCounts[key, default: 0]
            guard count < limitPerShow else { return false }
            episodeCounts[key] = count + 1
            return true
        }
    }

    private func plexDisplayInfo(for item: PlexHistoryItem) -> (title: String, subtitle: String) {
        if item.type?.lowercased() == "episode" {
            let showTitle = item.grandparentTitle ?? item.parentTitle ?? item.title ?? "Untitled"
            var titleParts = [showTitle]
            if let season = item.parentIndex, let episode = item.index {
                titleParts.append("S\(season)E\(episode)")
            }
            let title = titleParts.joined(separator: " • ")
            let subtitle = item.title ?? ""
            return (title: title, subtitle: subtitle)
        }
        return (title: item.displayTitle, subtitle: item.displaySubtitle)
    }

    private func startPlexPrefetch(token: String, preferredServerID: String?) {
        let combined = plexNowPlaying + plexRecent
        guard !token.isEmpty, !combined.isEmpty else { return }
        let candidates = Array(combined.prefix(25))
        var itemsToPrefetch: [PlexRecentlyWatchedItem] = []
        for item in candidates where !plexPrefetchedKeys.contains(item.ratingKey) {
            plexPrefetchedKeys.insert(item.ratingKey)
            itemsToPrefetch.append(item)
        }
        guard !itemsToPrefetch.isEmpty else { return }

        let client = plexClient
        plexPrefetchTask?.cancel()
        plexPrefetchTask = Task(priority: .utility) {
            for item in itemsToPrefetch {
                guard !Task.isCancelled else { return }
                do {
                    if item.isEpisode, let showRatingKey = item.showRatingKey {
                        let showMetadata = try await client.fetchMetadata(
                            ratingKey: showRatingKey,
                            token: token,
                            preferredServerID: preferredServerID
                        )
                        let guids = Self.extractGuids(from: showMetadata)
                        if let tmdbID = Self.parseExternalIDs(from: guids).tmdbID {
                            plexShowIDCache[showRatingKey] = tmdbID
                        }
                        continue
                    }

                    guard let typeHint = item.type?.lowercased(),
                          typeHint == "movie" || typeHint == "show" else { continue }
                    let metadata = try await client.fetchMetadata(
                        ratingKey: item.ratingKey,
                        token: token,
                        preferredServerID: preferredServerID
                    )
                    let guids = Self.extractGuids(from: metadata)
                    if let tmdbID = Self.parseExternalIDs(from: guids).tmdbID {
                        let route: PlexNavigationRoute = typeHint == "movie"
                        ? .movie(id: tmdbID, title: item.title, posterPath: nil)
                        : .tv(id: tmdbID, title: item.seriesTitle ?? item.title, posterPath: nil)
                        plexRouteCache[item.ratingKey] = route
                    }
                } catch {
                    continue
                }
            }
        }
    }

    private func parseYear(from dateString: String?) -> Int? {
        guard let dateString, dateString.count >= 4 else { return nil }
        let prefix = dateString.prefix(4)
        return Int(prefix)
    }

    func cachedPlexRoute(for item: PlexRecentlyWatchedItem) -> PlexNavigationRoute? {
        if let cached = plexRouteCache[item.ratingKey] {
            return cached
        }

        if item.isEpisode,
           let showRatingKey = item.showRatingKey,
           let cachedShowID = plexShowIDCache[showRatingKey],
           let seasonNumber = item.seasonNumber,
           let episodeNumber = item.episodeNumber {
            let route = PlexNavigationRoute.episode(
                tvID: cachedShowID,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber,
                title: item.title,
                stillPath: nil
            )
            plexRouteCache[item.ratingKey] = route
            return route
        }

        return nil
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

private enum LiveActivityArtworkStore {
    private static let appGroupID = "group.com.bebopbeluga.Badminton"
    private static let directoryName = "LiveActivityArt"

    static func fileURL(for fileName: String) -> URL? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }
        let directoryURL = containerURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
        return directoryURL.appendingPathComponent(fileName)
    }

    static func store(data: Data, fileName: String) -> URL? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }
        let directoryURL = containerURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let fileURL = directoryURL.appendingPathComponent(fileName)
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            print("Live Activity artwork store failed: \(error)")
            return nil
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(PlexAuthManager())
        .environmentObject(OverseerrAuthManager())
        .environmentObject(OverseerrLibraryIndex())
}
