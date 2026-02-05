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
    @Environment(\.listItemStyle) private var listItemStyle

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
                    creditsSection
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
                if let detail = viewModel.detail {
                    quickFacts(detail: detail)
                } else {
                    Text("Season \(seasonNumber) · Episode \(episodeNumber)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let show = viewModel.parentShow {
                    NavigationLink {
                        TVDetailView(tvID: show.id, title: show.name, posterPath: show.posterPath)
                    } label: {
                        HStack(spacing: 6) {
                            Text(show.name)
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
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

    private func quickFacts(detail: TMDBEpisodeDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            infoStack(label: "Episode", value: "Season \(seasonNumber) · Episode \(episodeNumber)")
            if let date = TMDBDateFormatter.format(detail.airDate) {
                infoStack(label: "Released", value: date)
            }
            if let runtime = viewModel.runtimeText {
                infoStack(label: "Runtime", value: runtime)
            }
            if let score = detail.voteAverage {
                infoStack(label: "Score", value: scoreText(from: score))
            }
        }
    }

    private var creditsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !viewModel.castMembers.isEmpty {
                creditsList(title: "Cast", members: viewModel.castMembers) { member in
                    ListItemRow(
                        title: member.name,
                        subtitle: member.character ?? "",
                        imageURL: viewModel.profileURL(path: member.profilePath),
                        showChevron: true
                    )
                }
            }

            if !viewModel.guestStars.isEmpty {
                creditsList(title: "Guests", members: viewModel.guestStars) { member in
                    ListItemRow(
                        title: member.name,
                        subtitle: member.character ?? "",
                        imageURL: viewModel.profileURL(path: member.profilePath),
                        showChevron: true
                    )
                }
            }

            if !viewModel.crewMembers.isEmpty {
                creditsList(title: "Crew", members: viewModel.crewMembers) { member in
                    ListItemRow(
                        title: member.name,
                        subtitle: member.job ?? "",
                        imageURL: viewModel.profileURL(path: member.profilePath),
                        showChevron: true
                    )
                }
            }

            if viewModel.guestStars.isEmpty && viewModel.castMembers.isEmpty && viewModel.crewMembers.isEmpty {
                Text("No credits available")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func creditsList<T: Identifiable>(
        title: String,
        members: [T],
        @ViewBuilder row: @escaping (T) -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            #if os(macOS)
            LazyVGrid(
                columns: gridColumns,
                alignment: .leading,
                spacing: 16
            ) {
                ForEach(Array(members.enumerated()), id: \.offset) { _, member in
                    if let cast = member as? TMDBCastMember {
                        NavigationLink {
                            PersonDetailView(personID: cast.id, name: cast.name, profilePath: cast.profilePath)
                        } label: {
                            ListPosterGridItem(
                                title: cast.name,
                                subtitle: cast.character ?? "",
                                imageURL: viewModel.profileURL(path: cast.profilePath)
                            )
                        }
                        .buttonStyle(.plain)
                    } else if let crew = member as? TMDBCrewMember {
                        NavigationLink {
                            PersonDetailView(personID: crew.id, name: crew.name, profilePath: crew.profilePath)
                        } label: {
                            ListPosterGridItem(
                                title: crew.name,
                                subtitle: crew.job ?? "",
                                imageURL: viewModel.profileURL(path: crew.profilePath)
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        row(member)
                    }
                }
            }
            #else
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(members.enumerated()), id: \.offset) { _, member in
                    if let cast = member as? TMDBCastMember {
                        NavigationLink {
                            PersonDetailView(personID: cast.id, name: cast.name, profilePath: cast.profilePath)
                        } label: {
                            row(member)
                        }
                        .buttonStyle(.plain)
                    } else if let crew = member as? TMDBCrewMember {
                        NavigationLink {
                            PersonDetailView(personID: crew.id, name: crew.name, profilePath: crew.profilePath)
                        } label: {
                            row(member)
                        }
                        .buttonStyle(.plain)
                    } else {
                        row(member)
                    }
                }
            }
            #endif
        }
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

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: listItemStyle.rowPosterSize.width, maximum: listItemStyle.rowPosterSize.width), spacing: 16, alignment: .top)]
    }

    private func showLightbox(url: URL, title: String) {
        lightboxItem = ImageLightboxItem(url: url, title: title)
    }
}

@MainActor
final class EpisodeDetailViewModel: ObservableObject {
    @Published var detail: TMDBEpisodeDetail?
    @Published var credits: TMDBEpisodeCredits?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var parentShow: TMDBTVSeriesDetail?

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

    var guestStars: [TMDBCastMember] {
        credits?.guestStars ?? []
    }

    var castMembers: [TMDBCastMember] {
        credits?.cast ?? []
    }

    var crewMembers: [TMDBCrewMember] {
        credits?.crew ?? []
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
            async let show: TMDBTVSeriesDetail = client.getV3(
                path: "/3/tv/\(tvID)"
            )

            let (configResponse, detailResponse, creditsResponse, showResponse) = try await (config, detail, credits, show)
            imageConfig = configResponse.images
            self.detail = detailResponse
            self.credits = creditsResponse.dedupingPeople()
            self.parentShow = showResponse
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
