import Combine
import Kingfisher
import SwiftUI

struct MovieDetailView: View {
    let movieID: Int
    let titleFallback: String?
    let posterPathFallback: String?

    @StateObject private var viewModel: MovieDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var lightboxItem: ImageLightboxItem?

    init(movieID: Int, title: String? = nil, posterPath: String? = nil) {
        self.movieID = movieID
        self.titleFallback = title
        self.posterPathFallback = posterPath
        _viewModel = StateObject(wrappedValue: MovieDetailViewModel(movieID: movieID))
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
                    infoSection(detail: detail)
                    castSection
                }
            }
            .padding()
        }
        .navigationTitle(viewModel.title ?? titleFallback ?? "Movie")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .sheet(item: $lightboxItem) { item in
            ImageLightboxView(item: item)
        }
        .macOSSwipeToDismiss { dismiss() }
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load(force: true)
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
                if let date = TMDBDateFormatter.format(viewModel.detail?.releaseDate) {
                    Text(date)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                genreChips
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

    private func infoSection(detail: TMDBMovieDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Info")
                .font(.headline)
            if let runtime = viewModel.runtimeText, !runtime.isEmpty {
                infoRow(label: "Runtime", value: runtime)
            }
            infoRow(label: "Status", value: detail.status ?? "")
            infoRow(label: "Rating", value: String(format: "%.1f", detail.voteAverage))
            infoRow(label: "Votes", value: "\(detail.voteCount)")
        }
    }

    private var castSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Cast")
                .font(.headline)
            if let cast = viewModel.credits?.cast, !cast.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(cast.prefix(10)) { member in
                        NavigationLink {
                            PersonDetailView(personID: member.id, name: member.name, profilePath: member.profilePath)
                        } label: {
                            CastRow(
                                member: member,
                                imageURL: viewModel.profileURL(path: member.profilePath),
                                onImageTap: {
                                    if let url = viewModel.profileURL(path: member.profilePath) {
                                        showLightbox(url: url, title: member.name)
                                    }
                                }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Text("No cast available")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func showLightbox(url: URL, title: String) {
        lightboxItem = ImageLightboxItem(url: url, title: title)
    }
}

private struct CastRow: View {
    let member: TMDBCastMember
    let imageURL: URL?
    let onImageTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                if let imageURL {
                    KFImage(imageURL)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: 44, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .highPriorityGesture(
                TapGesture().onEnded {
                    if imageURL != nil {
                        onImageTap()
                    }
                }
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(member.name)
                    .font(.subheadline.weight(.semibold))
                if let character = member.character, !character.isEmpty {
                    Text(character)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

@MainActor
final class MovieDetailViewModel: ObservableObject {
    @Published var detail: TMDBMovieDetail?
    @Published var credits: TMDBCredits?
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

            let (configResponse, detailResponse, creditsResponse) = try await (config, detail, credits)
            imageConfig = configResponse.images
            self.detail = detailResponse
            self.credits = creditsResponse
            hasLoaded = true
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
}
