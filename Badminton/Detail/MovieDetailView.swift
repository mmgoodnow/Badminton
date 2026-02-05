import Combine
import Kingfisher
import SwiftUI

struct MovieDetailView: View {
    let movieID: Int
    let titleFallback: String?
    let posterPathFallback: String?

    @StateObject private var viewModel: MovieDetailViewModel
    @StateObject private var overseerrRequest: OverseerrRequestViewModel
    @State private var lightboxItem: ImageLightboxItem?
    @Environment(\.openURL) private var openURL
    @Environment(\.listItemStyle) private var listItemStyle
    @EnvironmentObject private var overseerrAuthManager: OverseerrAuthManager
    @EnvironmentObject private var overseerrLibraryIndex: OverseerrLibraryIndex

    init(movieID: Int, title: String? = nil, posterPath: String? = nil) {
        self.movieID = movieID
        self.titleFallback = title
        self.posterPathFallback = posterPath
        _viewModel = StateObject(wrappedValue: MovieDetailViewModel(movieID: movieID))
        _overseerrRequest = StateObject(wrappedValue: OverseerrRequestViewModel(mediaType: .movie, tmdbID: movieID))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if viewModel.isLoading && viewModel.detail == nil {
                    ProgressView("Loading movie…")
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if let detail = viewModel.detail {
                    overviewSection(detail: detail)
                    trailersSection
                    creditsSection
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(viewModel.title ?? titleFallback ?? "Movie")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .imageLightbox(item: $lightboxItem)
        .macOSSwipeToDismiss()
        .task {
            await viewModel.load()
            await refreshOverseerr()
        }
        .refreshable {
            await viewModel.load(force: true)
            await refreshOverseerr()
        }
#if os(macOS) || targetEnvironment(macCatalyst)
        .focusedSceneValue(\.badmintonRefreshAction) {
            await viewModel.load(force: true)
            await refreshOverseerr()
        }
#endif
        .task(id: overseerrAuthManager.isAuthenticated) {
            await refreshOverseerr()
        }
        .task(id: overseerrAuthManager.baseURLString) {
            await refreshOverseerr()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            posterView
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.title ?? titleFallback ?? "")
                    .font(.title.bold())
                if let tagline = viewModel.detail?.tagline, !tagline.isEmpty {
                    Text(tagline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let detail = viewModel.detail {
                    quickFacts(detail: detail)
                    overseerrControls
                    genreChips
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var posterView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
            if let url = viewModel.posterURL(path: viewModel.detail?.posterPath ?? posterPathFallback) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: 140, height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            if let url = viewModel.posterURL(path: viewModel.detail?.posterPath ?? posterPathFallback) {
                showLightbox(url: url, title: viewModel.title ?? titleFallback ?? "Poster")
            }
        }
    }

    @ViewBuilder
    private var genreChips: some View {
        if let genres = viewModel.detail?.genres, !genres.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(genres, id: \.id) { genre in
                        Text(genre.name)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                .padding(.trailing, 2)
            }
        }
    }

    private func overviewSection(detail: TMDBMovieDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overview")
                .font(.headline)
            Text(detail.overview)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var trailersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !viewModel.trailers.isEmpty {
                Text("Trailers")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.trailers) { trailer in
                        if let url = viewModel.videoURL(for: trailer) {
                            Button {
                                openURL(url)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.circle.fill")
                                        .foregroundStyle(.secondary)
                                    Text(trailer.name)
                                        .font(.subheadline.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func quickFacts(detail: TMDBMovieDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let releaseDate = TMDBDateFormatter.format(detail.releaseDate) {
                infoStack(label: "Released", value: releaseDate)
            }
            if let runtime = viewModel.runtimeText, !runtime.isEmpty {
                infoStack(label: "Runtime", value: runtime)
            }
            infoStack(label: "Score", value: scoreText(from: detail.voteAverage))
            if let status = detail.status, !status.isEmpty {
                infoStack(label: "Status", value: status)
            }
        }
    }

    private var overseerrControls: some View {
        Group {
            if overseerrAuthManager.isAuthenticated && overseerrAuthManager.baseURL != nil {
                VStack(alignment: .leading, spacing: 8) {
                    infoStack(
                        label: "Plex",
                        value: overseerrRequest.isLoading ? "Loading…" : overseerrRequest.statusText
                    )
                    if overseerrRequest.isLoading {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 120, height: 28)
                            .redacted(reason: .placeholder)
                    } else if overseerrRequest.canRequest {
                        let hasRequested = overseerrRequest.requestStatus != nil
                            || (overseerrRequest.mediaStatus != nil
                                && overseerrRequest.mediaStatus != .unknown
                                && overseerrRequest.mediaStatus != .deleted)
                        let buttonTitle = hasRequested ? "Requested" : "Request"
                        Button(buttonTitle) {
                            Task {
                                await overseerrRequest.request(
                                    baseURL: overseerrAuthManager.baseURL,
                                    cookie: overseerrAuthManager.authCookie()
                                )
                                overseerrLibraryIndex.updateAvailability(
                                    tmdbID: movieID,
                                    status: overseerrRequest.mediaStatus
                                )
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(hasRequested)
                    }
                }
                if let errorMessage = overseerrRequest.errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func refreshOverseerr() async {
        await overseerrRequest.load(
            baseURL: overseerrAuthManager.baseURL,
            cookie: overseerrAuthManager.authCookie()
        )
        overseerrLibraryIndex.updateAvailability(
            tmdbID: movieID,
            status: overseerrRequest.mediaStatus
        )
    }

    private var creditsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let cast = viewModel.credits?.cast, !cast.isEmpty {
                creditsList(title: "Cast", members: Array(cast.prefix(12)))
            }

            if let crew = viewModel.credits?.crew, !crew.isEmpty {
                creditsList(title: "Crew", members: Array(crew.prefix(12)))
            }

            if viewModel.credits == nil || (viewModel.credits?.cast.isEmpty == true && viewModel.credits?.crew.isEmpty == true) {
                Text("No credits available")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func creditsList(title: String, members: [TMDBCastMember]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            #if os(macOS)
            LazyVGrid(
                columns: gridColumns,
                alignment: .leading,
                spacing: 16
            ) {
                ForEach(members) { member in
                    NavigationLink {
                        PersonDetailView(personID: member.id, name: member.name, profilePath: member.profilePath)
                    } label: {
                        ListPosterGridItem(
                            title: member.name,
                            subtitle: member.character ?? "",
                            imageURL: viewModel.profileURL(path: member.profilePath)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            #else
            VStack(alignment: .leading, spacing: 12) {
                ForEach(members) { member in
                    NavigationLink {
                        PersonDetailView(personID: member.id, name: member.name, profilePath: member.profilePath)
                    } label: {
                        ListItemRow(
                            title: member.name,
                            subtitle: member.character ?? "",
                            imageURL: viewModel.profileURL(path: member.profilePath),
                            showChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            #endif
        }
    }

    private func creditsList(title: String, members: [TMDBCrewMember]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            #if os(macOS)
            LazyVGrid(
                columns: gridColumns,
                alignment: .leading,
                spacing: 16
            ) {
                ForEach(members) { member in
                    NavigationLink {
                        PersonDetailView(personID: member.id, name: member.name, profilePath: member.profilePath)
                    } label: {
                        ListPosterGridItem(
                            title: member.name,
                            subtitle: member.job ?? "",
                            imageURL: viewModel.profileURL(path: member.profilePath)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            #else
            VStack(alignment: .leading, spacing: 12) {
                ForEach(members) { member in
                    NavigationLink {
                        PersonDetailView(personID: member.id, name: member.name, profilePath: member.profilePath)
                    } label: {
                        ListItemRow(
                            title: member.name,
                            subtitle: member.job ?? "",
                            imageURL: viewModel.profileURL(path: member.profilePath),
                            showChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            #endif
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: listItemStyle.rowPosterSize.width, maximum: listItemStyle.rowPosterSize.width), spacing: 16, alignment: .top)]
    }

    private func infoStack(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
        }
    }

    private func scoreText(from score: Double) -> String {
        "\(Int((score * 10).rounded()))%"
    }

    private func showLightbox(url: URL, title: String) {
        lightboxItem = ImageLightboxItem(url: url, title: title)
    }
}

@MainActor
final class MovieDetailViewModel: ObservableObject {
    @Published var detail: TMDBMovieDetail?
    @Published var credits: TMDBCredits?
    @Published private(set) var trailers: [TMDBVideo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    let movieID: Int

    private let client: TMDBAPIClient
    private var imageConfig: TMDBImageConfigValues?
    private var hasLoaded = false

    init(movieID: Int, client: TMDBAPIClient = TMDBAPIClient()) {
        self.movieID = movieID
        self.client = client
    }

    var title: String? {
        detail?.title
    }

    var runtimeText: String? {
        guard let runtime = detail?.runtime else { return nil }
        let hours = runtime / 60
        let minutes = runtime % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
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
            async let detail: TMDBMovieDetail = client.getV3(path: "/3/movie/\(movieID)")
            async let credits: TMDBCredits = client.getV3(path: "/3/movie/\(movieID)/credits")
            async let videos: TMDBVideoList = client.getV3(path: "/3/movie/\(movieID)/videos")

            let (configResponse, detailResponse, creditsResponse, videosResponse) = try await (config, detail, credits, videos)
            imageConfig = configResponse.images
            self.detail = detailResponse
            self.credits = creditsResponse
            trailers = videosResponse.results.filter { $0.type == "Trailer" }
            hasLoaded = true
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func posterURL(path: String?) -> URL? {
        imageURL(path: path, sizes: imageConfig?.posterSizes, fallback: "w342")
    }

    func profileURL(path: String?) -> URL? {
        imageURL(path: path, sizes: imageConfig?.profileSizes, fallback: "w185")
    }

    func videoURL(for video: TMDBVideo) -> URL? {
        if video.site.lowercased() == "youtube" {
            return URL(string: "https://www.youtube.com/watch?v=\(video.key)")
        }
        return nil
    }

    private func imageURL(path: String?, sizes: [String]?, fallback: String) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        let cleanedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let baseURL = imageConfig?.secureBaseUrl ?? "https://image.tmdb.org/t/p/"
        let size = preferredSize(from: sizes, fallback: fallback)
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
    NavigationStack {
        MovieDetailView(movieID: 550, title: "Fight Club")
    }
    .environmentObject(OverseerrAuthManager())
    .environmentObject(OverseerrLibraryIndex())
}
