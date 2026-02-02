import Combine
import Kingfisher
import SwiftUI

struct EpisodeDetailView: View {
    let tvID: Int
    let seasonNumber: Int
    let episodeNumber: Int
    let titleFallback: String?
    let stillPathFallback: String?

    @StateObject private var viewModel: EpisodeDetailViewModel
    @State private var lightboxItem: ImageLightboxItem?

    init(tvID: Int,
         seasonNumber: Int,
         episodeNumber: Int,
         title: String? = nil,
         stillPath: String? = nil) {
        self.tvID = tvID
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.titleFallback = title
        self.stillPathFallback = stillPath
        _viewModel = StateObject(wrappedValue: EpisodeDetailViewModel(
            tvID: tvID,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber
        ))
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
                    ProgressView("Loading episode…")
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if let detail = viewModel.detail {
                    overviewSection(detail: detail)
                    infoSection(detail: detail)
                    castSection
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(viewModel.title ?? titleFallback ?? "Episode")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .imageLightbox(item: $lightboxItem)
        .macOSSwipeToDismiss()
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load(force: true)
        }
#if os(macOS) || targetEnvironment(macCatalyst)
        .focusedSceneValue(\.badmintonRefreshAction) {
            await viewModel.load(force: true)
        }
#endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            stillView
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.title ?? titleFallback ?? "")
                    .font(.title.bold())
                Text("Season \(seasonNumber) · Episode \(episodeNumber)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let date = TMDBDateFormatter.format(viewModel.detail?.airDate) {
                    Text(date)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let runtime = viewModel.runtimeText {
                    Text(runtime)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var stillView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
            if let url = viewModel.stillURL(path: viewModel.detail?.stillPath ?? stillPathFallback) {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            if let url = viewModel.stillURL(path: viewModel.detail?.stillPath ?? stillPathFallback) {
                showLightbox(url: url, title: viewModel.title ?? titleFallback ?? "Still")
            }
        }
    }

    private func overviewSection(detail: TMDBEpisodeDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overview")
                .font(.headline)
            if let overview = detail.overview, !overview.isEmpty {
                Text(overview)
                    .foregroundStyle(.secondary)
            } else {
                Text("No overview available")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func infoSection(detail: TMDBEpisodeDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Info")
                .font(.headline)
            if let rating = detail.voteAverage {
                infoRow(label: "Rating", value: String(format: "%.1f", rating))
            }
            if let votes = detail.voteCount {
                infoRow(label: "Votes", value: "\(votes)")
            }
            if let runtime = viewModel.runtimeText {
                infoRow(label: "Runtime", value: runtime)
            }
        }
    }

    private var castSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cast")
                .font(.headline)
            if !viewModel.castMembers.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.castMembers.prefix(12)) { member in
                        NavigationLink {
                            PersonDetailView(personID: member.id, name: member.name, profilePath: member.profilePath)
                        } label: {
                            EpisodeCastRow(
                                member: member,
                                imageURL: viewModel.profileURL(path: member.profilePath)
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

private struct EpisodeCastRow: View {
    let member: TMDBCastMember
    let imageURL: URL?

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
            .frame(width: 96, height: 144)
            .clipShape(RoundedRectangle(cornerRadius: 8))

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

@MainActor
final class EpisodeDetailViewModel: ObservableObject {
    @Published var detail: TMDBEpisodeDetail?
    @Published var credits: TMDBEpisodeCredits?
    @Published var isLoading = false
    @Published var errorMessage: String?

    let tvID: Int
    let seasonNumber: Int
    let episodeNumber: Int

    private let client: TMDBAPIClient
    private var imageConfig: TMDBImageConfigValues?
    private var hasLoaded = false

    init(tvID: Int,
         seasonNumber: Int,
         episodeNumber: Int,
         client: TMDBAPIClient = TMDBAPIClient()) {
        self.tvID = tvID
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.client = client
    }

    var title: String? {
        detail?.name
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

    var castMembers: [TMDBCastMember] {
        let combined = (credits?.cast ?? []) + (credits?.guestStars ?? [])
        var seen = Set<Int>()
        return combined.filter { seen.insert($0.id).inserted }
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
            async let detail: TMDBEpisodeDetail = client.getV3(
                path: "/3/tv/\(tvID)/season/\(seasonNumber)/episode/\(episodeNumber)"
            )
            async let credits: TMDBEpisodeCredits = client.getV3(
                path: "/3/tv/\(tvID)/season/\(seasonNumber)/episode/\(episodeNumber)/credits"
            )

            let (configResponse, detailResponse, creditsResponse) = try await (config, detail, credits)
            imageConfig = configResponse.images
            self.detail = detailResponse
            self.credits = creditsResponse
            hasLoaded = true
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func stillURL(path: String?) -> URL? {
        imageURL(path: path, sizes: imageConfig?.stillSizes, fallback: "w780")
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
        EpisodeDetailView(tvID: 1399, seasonNumber: 1, episodeNumber: 1, title: "Winter Is Coming")
    }
}
