import Combine
import Kingfisher
import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @StateObject private var searchModel = SearchViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    if searchModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }

                        if viewModel.isLoading && viewModel.trendingMovies.isEmpty && viewModel.trendingTV.isEmpty {
                            ProgressView("Loading trending titles…")
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            trendingSection(title: "Trending Movies", items: viewModel.trendingMovies.map { .movie($0) })
                            trendingSection(title: "Trending TV", items: viewModel.trendingTV.map { .tv($0) })
                        }
                    } else {
                        searchResultsSection
                    }
                }
                .padding()
            }
            .navigationTitle("Home")
            .searchable(text: $searchModel.query, placement: .toolbar, prompt: "Movies, TV, people")
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
            .refreshable {
                await viewModel.load(force: true)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Home")
                .font(.largeTitle.bold())
        }
    }

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if searchModel.isSearching {
                ProgressView("Searching…")
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if searchModel.results.isEmpty {
                Text("No results")
                    .font(.headline)
                    .foregroundStyle(.secondary)
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
            return movie.releaseDate ?? ""
        case .tv(let tv):
            return tv.firstAirDate ?? ""
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
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
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
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let client: TMDBAPIClient
    private var imageConfig: TMDBImageConfigValues?
    private var hasLoaded = false

    init(client: TMDBAPIClient = TMDBAPIClient()) {
        self.client = client
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

            let (configResponse, moviesResponse, tvResponse) = try await (config, movies, tv)
            imageConfig = configResponse.images
            trendingMovies = moviesResponse.results
            trendingTV = tvResponse.results
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func posterURL(path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        let cleanedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let baseURL = imageConfig?.secureBaseUrl ?? "https://image.tmdb.org/t/p/"
        let size = preferredSize(from: imageConfig?.posterSizes, fallback: "w342")
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
