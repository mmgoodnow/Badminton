import Combine
import Kingfisher
import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @StateObject private var searchModel = SearchViewModel()
    @EnvironmentObject private var plexAuthManager: PlexAuthManager
    @State private var showingSettings = false
    @State private var navigationPath = NavigationPath()
    @State private var resolvingPlexIDs: Set<String> = []

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
                                Button {
                                    Task { await resolvePlexItem(item) }
                                } label: {
                                    PosterCardView(
                                        title: item.title,
                                        subtitle: item.subtitle,
                                        imageURL: item.imageURL
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(resolvingPlexIDs.contains(item.id))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    @MainActor
    private func resolvePlexItem(_ item: PlexRecentlyWatchedItem) async {
        guard let token = plexAuthManager.authToken, !token.isEmpty else { return }
        guard !resolvingPlexIDs.contains(item.id) else { return }
        resolvingPlexIDs.insert(item.id)
        defer { resolvingPlexIDs.remove(item.id) }

        if let route = await viewModel.resolvePlexRoute(
            for: item,
            token: token,
            preferredServerID: plexAuthManager.preferredServerID
        ) {
            navigationPath.append(route)
        } else {
            let fallbackQuery = item.seriesTitle ?? item.title
            await MainActor.run {
                searchModel.query = fallbackQuery
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

struct PlexRecentlyWatchedItem: Identifiable {
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

enum PlexNavigationRoute: Hashable {
    case movie(id: Int, title: String?, posterPath: String?)
    case tv(id: Int, title: String?, posterPath: String?)
    case episode(tvID: Int, seasonNumber: Int, episodeNumber: Int, title: String?, stillPath: String?)
}

private struct PlexExternalIDs {
    var tmdbID: Int?
    var imdbID: String?
    var tvdbID: String?
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

            var nowPlayingSourceIDs: Set<String> = []
            let nowPlayingMapped: [PlexRecentlyWatchedItem] = nowPlayingItems.compactMap { item in
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

            let recentMapped: [PlexRecentlyWatchedItem] = filteredItems.compactMap { item in
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

    func resolvePlexRoute(for item: PlexRecentlyWatchedItem, token: String, preferredServerID: String?) async -> PlexNavigationRoute? {
        if let cached = plexRouteCache[item.ratingKey] {
            return cached
        }

        let metadata = try? await plexClient.fetchMetadata(
            ratingKey: item.ratingKey,
            token: token,
            preferredServerID: preferredServerID
        )
        let typeHint = (metadata?.type ?? item.type)?.lowercased()
        let isEpisode = typeHint == "episode"
            || (item.seasonNumber != nil && item.episodeNumber != nil && item.seriesTitle != nil)
        var guidValues: [String] = []
        if let guid = metadata?.guid {
            guidValues.append(guid)
        }
        if let guids = metadata?.guids {
            guidValues.append(contentsOf: guids.map(\.id))
        }

        if let route = try? await resolveViaGuids(
            guidValues,
            typeHint: typeHint,
            isEpisode: isEpisode,
            item: item
        ) {
            plexRouteCache[item.ratingKey] = route
            return route
        }

        if let route = try? await resolveViaSearch(typeHint: typeHint, item: item) {
            plexRouteCache[item.ratingKey] = route
            return route
        }

        return nil
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

        if let imdbID = parsed.imdbID {
            if let route = try await resolveWithFind(externalID: imdbID, source: "imdb_id", typeHint: typeHint, item: item) {
                return route
            }
        }

        if let tvdbID = parsed.tvdbID {
            if let route = try await resolveWithFind(externalID: tvdbID, source: "tvdb_id", typeHint: typeHint, item: item) {
                return route
            }
        }

        return nil
    }

    private func resolveWithFind(
        externalID: String,
        source: String,
        typeHint: String?,
        item: PlexRecentlyWatchedItem
    ) async throws -> PlexNavigationRoute? {
        let response: TMDBFindResponse = try await client.getV3(
            path: "/3/find/\(externalID)",
            queryItems: [URLQueryItem(name: "external_source", value: source)]
        )
        if typeHint == "movie", let movie = response.movieResults.first {
            return .movie(id: movie.id, title: movie.title, posterPath: movie.posterPath)
        }
        let hasEpisodeNumbers = item.seasonNumber != nil && item.episodeNumber != nil
        if (typeHint == "episode" || hasEpisodeNumbers),
           let episode = response.tvEpisodeResults.first,
           let showId = episode.showId,
           let seasonNumber = episode.seasonNumber ?? item.seasonNumber,
           let episodeNumber = episode.episodeNumber ?? item.episodeNumber {
            return .episode(
                tvID: showId,
                seasonNumber: seasonNumber,
                episodeNumber: episodeNumber,
                title: episode.name ?? item.title,
                stillPath: episode.stillPath
            )
        }
        if (typeHint == "episode" || hasEpisodeNumbers),
           let tv = response.tvResults.first,
           let seasonNumber = item.seasonNumber,
           let episodeNumber = item.episodeNumber {
            return .episode(tvID: tv.id, seasonNumber: seasonNumber, episodeNumber: episodeNumber, title: item.title, stillPath: nil)
        }
        if let tv = response.tvResults.first {
            return .tv(id: tv.id, title: tv.name, posterPath: tv.posterPath)
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
            } else if let imdbID = extractExternalID(from: guid, prefixes: ["imdb://", "com.plexapp.agents.imdb://"]) {
                result.imdbID = imdbID
            } else if let tvdbID = extractExternalID(from: guid, prefixes: ["thetvdb://", "tvdb://", "com.plexapp.agents.thetvdb://"]) {
                result.tvdbID = tvdbID
            }
        }
        return result
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
