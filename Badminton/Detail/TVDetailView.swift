import Combine
import Kingfisher
import SwiftUI

struct TVDetailView: View {
    let tvID: Int
    let titleFallback: String?
    let posterPathFallback: String?

    @StateObject private var viewModel: TVDetailViewModel
    @State private var lightboxItem: ImageLightboxItem?
    @Environment(\.openURL) private var openURL

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
                    trailersSection
                    latestEpisodeSection(detail: detail)
                    seasonsSection(detail: detail)
                    castSection
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(viewModel.title ?? titleFallback ?? "TV Show")
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
                if let date = TMDBDateFormatter.format(viewModel.detail?.firstAirDate) {
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
            infoRow(label: "Episodes", value: String(detail.numberOfEpisodes))
            infoRow(label: "Status", value: detail.status ?? "")
            if let lastAir = TMDBDateFormatter.format(detail.lastAirDate) {
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
                let seasons = detail.seasons.sorted { $0.seasonNumber > $1.seasonNumber }
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(seasons, id: \.id) { season in
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
                                imageURL: viewModel.posterURL(path: season.posterPath)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
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

    @ViewBuilder
    private func latestEpisodeSection(detail: TMDBTVSeriesDetail) -> some View {
        if let nextEpisode = detail.nextEpisodeToAir {
            NavigationLink {
                EpisodeDetailView(
                    tvID: tvID,
                    seasonNumber: nextEpisode.seasonNumber,
                    episodeNumber: nextEpisode.episodeNumber,
                    title: nextEpisode.name,
                    stillPath: nextEpisode.stillPath
                )
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Up next")
                        .font(.headline)
                    Text(nextEpisode.name)
                        .font(.subheadline.weight(.semibold))
                    Text(episodeSubtitle(nextEpisode))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let overview = nextEpisode.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        if !viewModel.latestEpisodes.isEmpty || detail.lastEpisodeToAir != nil {
            VStack(alignment: .leading, spacing: 12) {
                Text("Latest episodes")
                    .font(.headline)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        if !viewModel.latestEpisodes.isEmpty {
                            ForEach(viewModel.latestEpisodes.prefix(10)) { episode in
                                if let seasonNumber = viewModel.latestSeasonNumber ?? detail.lastEpisodeToAir?.seasonNumber {
                                    NavigationLink {
                                        EpisodeDetailView(
                                            tvID: tvID,
                                            seasonNumber: seasonNumber,
                                            episodeNumber: episode.episodeNumber,
                                            title: episode.name,
                                            stillPath: episode.stillPath
                                        )
                                    } label: {
                                        EpisodeCard(
                                            title: episode.name,
                                            subtitle: episodeSubtitle(episode, fallbackSeason: detail.lastEpisodeToAir?.seasonNumber),
                                            overview: episode.overview,
                                            imageURL: viewModel.stillURL(path: episode.stillPath)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    EpisodeCard(
                                        title: episode.name,
                                        subtitle: episodeSubtitle(episode, fallbackSeason: detail.lastEpisodeToAir?.seasonNumber),
                                        overview: episode.overview,
                                        imageURL: viewModel.stillURL(path: episode.stillPath)
                                    )
                                }
                            }
                        } else if let lastEpisode = detail.lastEpisodeToAir {
                            NavigationLink {
                                EpisodeDetailView(
                                    tvID: tvID,
                                    seasonNumber: lastEpisode.seasonNumber,
                                    episodeNumber: lastEpisode.episodeNumber,
                                    title: lastEpisode.name,
                                    stillPath: lastEpisode.stillPath
                                )
                            } label: {
                                EpisodeCard(
                                    title: lastEpisode.name,
                                    subtitle: episodeSubtitle(lastEpisode),
                                    overview: lastEpisode.overview,
                                    imageURL: viewModel.stillURL(path: lastEpisode.stillPath)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func episodeSubtitle(_ episode: TMDBEpisodeSummary) -> String {
        var parts: [String] = []
        parts.append("S\(episode.seasonNumber) · E\(episode.episodeNumber)")
        if let airDate = TMDBDateFormatter.format(episode.airDate) {
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
        if let airDate = TMDBDateFormatter.format(episode.airDate) {
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

private struct CastRow: View {
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

private struct SeasonRow: View {
    let season: TMDBTVSeasonSummary
    let imageURL: URL?

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
            .frame(width: 96, height: 144)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text(season.name)
                    .font(.subheadline.weight(.semibold))
                if let airDate = TMDBDateFormatter.format(season.airDate) {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct EpisodeCard: View {
    let title: String
    let subtitle: String
    let overview: String?
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
            .frame(width: 220, height: 124)
            .clipShape(RoundedRectangle(cornerRadius: 12))

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
    @Published private(set) var latestSeasonNumber: Int?
    @Published private(set) var trailers: [TMDBVideo] = []
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
            async let videos: TMDBVideoList = client.getV3(path: "/3/tv/\(tvID)/videos")

            let (configResponse, detailResponse, creditsResponse, videosResponse) = try await (config, detail, credits, videos)
            imageConfig = configResponse.images
            self.detail = detailResponse
            self.credits = creditsResponse
            latestEpisodes = []
            latestSeasonNumber = nil
            trailers = videosResponse.results.filter { $0.type == "Trailer" }

            if let seasonNumber = latestSeasonNumber(from: detailResponse) {
                latestSeasonNumber = seasonNumber
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
        return sorted.filter { !isFutureEpisode($0.airDate) }
    }

    func isFutureEpisode(_ airDate: String?) -> Bool {
        guard let airDate, let date = TMDBDateFormatter.input.date(from: airDate) else {
            return false
        }
        return date > Date()
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
