import Combine
import Kingfisher
import SwiftUI

struct TVDetailView: View {
    let tvID: Int
    let titleFallback: String?
    let posterPathFallback: String?

    @StateObject private var viewModel: TVDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var lightboxItem: ImageLightboxItem?

    init(tvID: Int, title: String? = nil, posterPath: String? = nil) {
        self.tvID = tvID
        self.titleFallback = title
        self.posterPathFallback = posterPath
        _viewModel = StateObject(wrappedValue: TVDetailViewModel(tvID: tvID))
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
                    ProgressView("Loading show details…")
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if let detail = viewModel.detail {
                    overviewSection(detail: detail)
                    infoSection(detail: detail)
                    latestEpisodeSection(detail: detail)
                    seasonsSection(detail: detail)
                    castSection
                }
            }
            .padding()
        }
        .navigationTitle(viewModel.title ?? titleFallback ?? "TV Show")
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
                if let date = viewModel.detail?.firstAirDate, !date.isEmpty {
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
            FlowLayout(spacing: 6) {
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

    private func overviewSection(detail: TMDBTVSeriesDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overview")
                .font(.headline)
            Text(detail.overview)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private func infoSection(detail: TMDBTVSeriesDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Info")
                .font(.headline)
            infoRow(label: "Seasons", value: String(detail.numberOfSeasons))
            infoRow(label: "Episodes", value: String(detail.numberOfEpisodes))
            infoRow(label: "Status", value: detail.status ?? "")
            if let lastAir = detail.lastAirDate, !lastAir.isEmpty {
                infoRow(label: "Last Air Date", value: lastAir)
            }
        }
    }

    private func seasonsSection(detail: TMDBTVSeriesDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Seasons")
                .font(.headline)

            if detail.seasons.isEmpty {
                Text("No seasons available")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(detail.seasons, id: \.id) { season in
                        NavigationLink {
                            TVSeasonDetailView(
                                tvID: tvID,
                                seasonNumber: season.seasonNumber,
                                seasonName: season.name,
                                posterPath: season.posterPath
                            )
                        } label: {
                            SeasonRow(
                                season: season,
                                imageURL: viewModel.posterURL(path: season.posterPath),
                                onImageTap: {
                                    if let url = viewModel.posterURL(path: season.posterPath) {
                                        showLightbox(url: url, title: season.name)
                                    }
                                }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func latestEpisodeSection(detail: TMDBTVSeriesDetail) -> some View {
        if !viewModel.latestEpisodes.isEmpty || detail.lastEpisodeToAir != nil {
            VStack(alignment: .leading, spacing: 12) {
                Text("Latest episodes")
                    .font(.headline)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        if !viewModel.latestEpisodes.isEmpty {
                            ForEach(viewModel.latestEpisodes.prefix(10)) { episode in
                                EpisodeCard(
                                    title: episode.name,
                                    subtitle: episodeSubtitle(episode, fallbackSeason: detail.lastEpisodeToAir?.seasonNumber),
                                    overview: episode.overview,
                                    imageURL: viewModel.stillURL(path: episode.stillPath),
                                    onImageTap: {
                                        if let url = viewModel.stillURL(path: episode.stillPath) {
                                            showLightbox(url: url, title: episode.name)
                                        }
                                    }
                                )
                            }
                        } else if let lastEpisode = detail.lastEpisodeToAir {
                            EpisodeCard(
                                title: lastEpisode.name,
                                subtitle: episodeSubtitle(lastEpisode),
                                overview: lastEpisode.overview,
                                imageURL: viewModel.stillURL(path: lastEpisode.stillPath),
                                onImageTap: {
                                    if let url = viewModel.stillURL(path: lastEpisode.stillPath) {
                                        showLightbox(url: url, title: lastEpisode.name)
                                    }
                                }
                            )
                        }

                        if let nextEpisode = detail.nextEpisodeToAir {
                            EpisodeCard(
                                title: "Up next: \(nextEpisode.name)",
                                subtitle: episodeSubtitle(nextEpisode),
                                overview: nextEpisode.overview,
                                imageURL: viewModel.stillURL(path: nextEpisode.stillPath),
                                onImageTap: {
                                    if let url = viewModel.stillURL(path: nextEpisode.stillPath) {
                                        showLightbox(url: url, title: nextEpisode.name)
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    private func episodeSubtitle(_ episode: TMDBEpisodeSummary) -> String {
        var parts: [String] = []
        parts.append("S\(episode.seasonNumber) · E\(episode.episodeNumber)")
        if let airDate = episode.airDate, !airDate.isEmpty {
            parts.append(airDate)
        }
        return parts.joined(separator: " • ")
    }

    private func episodeSubtitle(_ episode: TMDBEpisode, fallbackSeason: Int?) -> String {
        var parts: [String] = []
        if let season = fallbackSeason {
            parts.append("S\(season) · E\(episode.episodeNumber)")
        } else {
            parts.append("E\(episode.episodeNumber)")
        }
        if let airDate = episode.airDate, !airDate.isEmpty {
            parts.append(airDate)
        }
        return parts.joined(separator: " • ")
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

private struct SeasonRow: View {
    let season: TMDBTVSeasonSummary
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
            .frame(width: 70, height: 105)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .highPriorityGesture(
                TapGesture().onEnded {
                    if imageURL != nil {
                        onImageTap()
                    }
                }
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(season.name)
                    .font(.subheadline.weight(.semibold))
                if let airDate = season.airDate, !airDate.isEmpty {
                    Text(airDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(season.episodeCount) episodes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let overview = season.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct EpisodeCard: View {
    let title: String
    let subtitle: String
    let overview: String?
    let imageURL: URL?
    let onImageTap: () -> Void

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
            .frame(width: 220, height: 124)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .onTapGesture {
                if imageURL != nil {
                    onImageTap()
                }
            }

            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let overview, !overview.isEmpty {
                Text(overview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(width: 220, alignment: .leading)
    }
}

@MainActor
final class TVDetailViewModel: ObservableObject {
    @Published var detail: TMDBTVSeriesDetail?
    @Published var credits: TMDBCredits?
    @Published private(set) var latestEpisodes: [TMDBEpisode] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    let tvID: Int

    private let client: TMDBAPIClient
    private var imageConfig: TMDBImageConfigValues?
    private var hasLoaded = false

    init(tvID: Int, client: TMDBAPIClient = TMDBAPIClient()) {
        self.tvID = tvID
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
            async let detail: TMDBTVSeriesDetail = client.getV3(path: "/3/tv/\(tvID)")
            async let credits: TMDBCredits = client.getV3(path: "/3/tv/\(tvID)/credits")

            let (configResponse, detailResponse, creditsResponse) = try await (config, detail, credits)
            imageConfig = configResponse.images
            self.detail = detailResponse
            self.credits = creditsResponse
            latestEpisodes = []

            if let seasonNumber = latestSeasonNumber(from: detailResponse) {
                if let seasonDetail: TMDBTVSeasonDetail = try? await client.getV3(path: "/3/tv/\(tvID)/season/\(seasonNumber)") {
                    latestEpisodes = latestEpisodes(from: seasonDetail)
                }
            }

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

    private func latestSeasonNumber(from detail: TMDBTVSeriesDetail) -> Int? {
        if let last = detail.lastEpisodeToAir?.seasonNumber {
            return last
        }
        return detail.seasons
            .filter { $0.seasonNumber > 0 }
            .map(\.seasonNumber)
            .max()
    }

    private func latestEpisodes(from season: TMDBTVSeasonDetail) -> [TMDBEpisode] {
        let sorted = season.episodes.sorted { lhs, rhs in
            switch (lhs.airDate, rhs.airDate) {
            case let (l?, r?):
                if l == r { return lhs.episodeNumber > rhs.episodeNumber }
                return l > r
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            default:
                return lhs.episodeNumber > rhs.episodeNumber
            }
        }
        return sorted
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = makeRows(subviews: subviews, maxWidth: maxWidth)
        let rowHeights = rows.map { row in
            row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        }
        let rowWidths = rows.map { row in
            row.enumerated().reduce(CGFloat(0)) { partial, entry in
                let (index, subview) = entry
                let size = subview.sizeThatFits(.unspecified)
                return partial + size.width + (index == 0 ? 0 : spacing)
            }
        }
        let totalHeight = rowHeights.reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = (proposal.width ?? rowWidths.max()) ?? 0
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = makeRows(subviews: subviews, maxWidth: bounds.width)
        let rowHeights = rows.map { row in
            row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        }

        var y = bounds.minY
        for (rowIndex, row) in rows.enumerated() {
            var x = bounds.minX
            let rowHeight = rowHeights[rowIndex]
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y + (rowHeight - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func makeRows(subviews: Subviews, maxWidth: CGFloat) -> [[LayoutSubviews.Element]] {
        var rows: [[LayoutSubviews.Element]] = [[]]
        var currentRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let itemWidth = size.width + (rows.last?.isEmpty == false ? spacing : 0)
            if currentRowWidth + itemWidth > maxWidth, !rows.last!.isEmpty {
                rows.append([subview])
                currentRowWidth = size.width
            } else {
                rows[rows.count - 1].append(subview)
                currentRowWidth += itemWidth
            }
        }

        return rows
    }
}

#Preview {
    NavigationStack {
        TVDetailView(tvID: 1399, title: "Game of Thrones")
    }
}
