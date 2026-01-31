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
                        HStack(spacing: 16) {
                            ForEach(viewModel.plexRecentlyWatched) { item in
                                PosterCardView(
                                    title: item.title,
                                    subtitle: item.subtitle,
                                    imageURL: item.imageURL
                                )
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
                HStack(spacing: 16) {
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
                    HStack(spacing: 16) {
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
    let title: String
    let subtitle: String
    let imageURL: URL
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

            let nowPlayingIDs = Set(nowPlayingItems.map { $0.id })
            let nowPlayingMapped: [PlexRecentlyWatchedItem] = nowPlayingItems.compactMap { item in
                guard let imageURL = item.imageURL(serverBaseURL: result.serverBaseURL, token: result.serverToken) else {
                    return nil
                }
                let subtitle = item.displaySubtitle.isEmpty ? "Now Playing" : "Now Playing • \(item.displaySubtitle)"
                return PlexRecentlyWatchedItem(
                    id: "now-\(item.id)",
                    title: item.displayTitle,
                    subtitle: subtitle,
                    imageURL: imageURL
                )
            }

            let recentMapped: [PlexRecentlyWatchedItem] = filteredItems.compactMap { item in
                guard let imageURL = item.imageURL(serverBaseURL: result.serverBaseURL, token: result.serverToken) else {
                    return nil
                }
                return PlexRecentlyWatchedItem(
                    id: item.id,
                    title: item.displayTitle,
                    subtitle: item.displaySubtitle,
                    imageURL: imageURL
                )
            }
            plexRecentlyWatched = nowPlayingMapped + recentMapped.filter { !nowPlayingIDs.contains($0.id) }
            plexTokenLoaded = token
            plexPreferredServerLoaded = preferredServerID
            plexPreferredAccountLoaded = preferredAccountIDs
        } catch {
            plexRecentlyWatched = []
            print("Plex history error: \(error)")
        }
        plexIsLoading = false
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
