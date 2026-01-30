import Combine
import Kingfisher
import SwiftUI

struct TVSeasonDetailView: View {
    let tvID: Int
    let seasonNumber: Int
    let seasonName: String
    let posterPath: String?

    @StateObject private var viewModel: TVSeasonDetailViewModel
    @State private var lightboxItem: ImageLightboxItem?

    init(tvID: Int, seasonNumber: Int, seasonName: String, posterPath: String? = nil) {
        self.tvID = tvID
        self.seasonNumber = seasonNumber
        self.seasonName = seasonName
        self.posterPath = posterPath
        _viewModel = StateObject(wrappedValue: TVSeasonDetailViewModel(tvID: tvID, seasonNumber: seasonNumber))
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
                    ProgressView("Loading season…")
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if let detail = viewModel.detail {
                    if let overview = detail.overview, !overview.isEmpty {
                        Text("Overview")
                            .font(.headline)
                        Text(overview)
                            .foregroundStyle(.secondary)
                    }

                    Text("Episodes")
                        .font(.headline)
                    if detail.episodes.isEmpty {
                        Text("No episodes available")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(detail.episodes) { episode in
                                EpisodeRow(
                                    episode: episode,
                                    imageURL: viewModel.stillURL(path: episode.stillPath),
                                    onImageTap: {
                                        if let url = viewModel.stillURL(path: episode.stillPath) {
                                            showLightbox(url: url, title: episode.name)
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(viewModel.title ?? seasonName)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .sheet(item: $lightboxItem) { item in
            ImageLightboxView(item: item)
        }
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load(force: true)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                if let url = viewModel.posterURL(path: viewModel.detail?.posterPath ?? posterPath) {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: 120, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture {
                if let url = viewModel.posterURL(path: viewModel.detail?.posterPath ?? posterPath) {
                    showLightbox(url: url, title: viewModel.title ?? seasonName)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.title ?? seasonName)
                    .font(.title.bold())
                if let airDate = TMDBDateFormatter.format(viewModel.detail?.airDate) {
                    Text(airDate)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let count = viewModel.detail?.episodes.count {
                    Text("\(count) episodes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func showLightbox(url: URL, title: String) {
        lightboxItem = ImageLightboxItem(url: url, title: title)
    }
}

private struct EpisodeRow: View {
    let episode: TMDBEpisode
    let imageURL: URL?
    let onImageTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                if let imageURL {
                    KFImage(imageURL)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: 90, height: 54)
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
                Text("E\(episode.episodeNumber) · \(episode.name)")
                    .font(.subheadline.weight(.semibold))
                if let overview = episode.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let airDate = TMDBDateFormatter.format(episode.airDate) {
                    Text(airDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

@MainActor
final class TVSeasonDetailViewModel: ObservableObject {
    @Published var detail: TMDBTVSeasonDetail?
    @Published var isLoading = false
    @Published var errorMessage: String?

    let tvID: Int
    let seasonNumber: Int

    private let client: TMDBAPIClient
    private var imageConfig: TMDBImageConfigValues?
    private var hasLoaded = false

    init(tvID: Int, seasonNumber: Int, client: TMDBAPIClient = TMDBAPIClient()) {
        self.tvID = tvID
        self.seasonNumber = seasonNumber
        self.client = client
    }

    var title: String? {
        detail?.name
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
            async let detail: TMDBTVSeasonDetail = client.getV3(path: "/3/tv/\(tvID)/season/\(seasonNumber)")
            let (configResponse, detailResponse) = try await (config, detail)
            imageConfig = configResponse.images
            self.detail = detailResponse
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func posterURL(path: String?) -> URL? {
        imageURL(path: path, sizes: imageConfig?.posterSizes, fallback: "w342")
    }

    func stillURL(path: String?) -> URL? {
        imageURL(path: path, sizes: imageConfig?.stillSizes, fallback: "w300")
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
        TVSeasonDetailView(tvID: 1399, seasonNumber: 1, seasonName: "Season 1")
    }
}
