import Combine
import Kingfisher
import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @StateObject private var searchModel = SearchViewModel()
    @EnvironmentObject private var plexAuthManager: PlexAuthManager
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
            .focusedSceneValue(\.badmintonRefreshAction) {
                await refreshAll(force: true)
            }
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

    private func handlePlexSelection(_ item: PlexRecentlyWatchedItem) {
        guard plexResolvingItem == nil else { return }
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

struct PlexRecentlyWatchedItem: Identifiable, Hashable {
    let id: String
    let ratingKey: String
    let type: String?
    let title: String
    let subtitle: String
    let detailSubtitle: String
    let imageURL: URL
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
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 140, height: 210)

            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 120, height: 14)

            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 90, height: 12)
        }
        .redacted(reason: .placeholder)
        .frame(width: 140, alignment: .leading)
    }
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
#if os(iOS)
            plexLiveActivityManager.sync(nowPlaying: plexNowPlaying)
#endif
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
#if os(iOS)
            plexLiveActivityManager.sync(nowPlaying: plexNowPlaying)
#endif
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
