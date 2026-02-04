import Combine
import Kingfisher
import os
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
                    trailersSection
                    latestEpisodeSection(detail: detail)
                    seasonsSection(detail: detail)
                    creditsSection
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
        .onAppear {
            Signpost.event("TVDetailAppear", log: SignpostLog.navigation, "id=%{public}d", tvID)
            AppLog.navigation.info("TVDetailAppear id=\(tvID, privacy: .public)")
        }
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
            #if os(iOS)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 72, maximum: 160), spacing: 6, alignment: .leading)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(genres, id: \.id) { genre in
                    Text(genre.name)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            #else
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
            #endif
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

    private func quickFacts(detail: TMDBTVSeriesDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let releaseDate = TMDBDateFormatter.format(detail.firstAirDate) {
                infoStack(label: "Released", value: releaseDate)
            }
            infoStack(label: "Seasons", value: "\(detail.numberOfSeasons)")
            infoStack(label: "Episodes", value: "\(detail.numberOfEpisodes)")
            infoStack(label: "Score", value: scoreText(from: detail.voteAverage))
            if let status = detail.status, !status.isEmpty {
                infoStack(label: "Status", value: status)
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
            VStack(alignment: .leading, spacing: 12) {
                ForEach(members) { member in
                    NavigationLink {
                        PersonDetailView(personID: member.id, name: member.name, profilePath: member.profilePath)
                    } label: {
                        ListItemRow(
                            title: member.name,
                            subtitle: member.character ?? "",
                            imageURL: viewModel.profileURL(path: member.profilePath)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func creditsList(title: String, members: [TMDBCrewMember]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(members) { member in
                    NavigationLink {
                        PersonDetailView(personID: member.id, name: member.name, profilePath: member.profilePath)
                    } label: {
                        ListItemRow(
                            title: member.name,
                            subtitle: member.job ?? "",
                            imageURL: viewModel.profileURL(path: member.profilePath)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
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

    private func showLightbox(url: URL, title: String) {
        lightboxItem = ImageLightboxItem(url: url, title: title)
    }
}

private struct SeasonRow: View {
    let season: TMDBTVSeasonSummary
    let imageURL: URL?

    var body: some View {
        ListItemRow(
            title: season.name,
            subtitleLines: [
                TMDBDateFormatter.format(season.airDate) ?? "",
                "\(season.episodeCount) episodes",
                season.overview ?? ""
            ],
            imageURL: imageURL,
            subtitleLineLimit: 2
        )
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

        let tvID = self.tvID
        let forceFlag = force
        let signpost = Signpost.begin(
            "TVDetailLoad",
            log: SignpostLog.tmdb,
            "id=%{public}d force=%{public}d",
            tvID,
            forceFlag ? 1 : 0
        )
        AppLog.tmdb.info("TVDetailLoad start id=\(tvID, privacy: .public) force=\(forceFlag, privacy: .public)")
        defer {
            signpost.end()
            AppLog.tmdb.info("TVDetailLoad end id=\(tvID, privacy: .public)")
        }

        isLoading = true
        errorMessage = nil

        do {
            let result = try await Task.detached(priority: .userInitiated) { [tvID] in
                let client = TMDBAPIClient()
                async let config = client.getImageConfiguration()
                async let detail: TMDBTVSeriesDetail = client.getV3(path: "/3/tv/\(tvID)")
                async let credits: TMDBCredits = client.getV3(path: "/3/tv/\(tvID)/credits")
                async let videos: TMDBVideoList = client.getV3(path: "/3/tv/\(tvID)/videos")

                let (configResponse, detailResponse, creditsResponse, videosResponse) = try await (config, detail, credits, videos)
                var latestEpisodes: [TMDBEpisode] = []
                var latestSeasonNumber: Int? = nil
                if let seasonNumber = Self.latestSeasonNumber(from: detailResponse) {
                    latestSeasonNumber = seasonNumber
                    if let seasonDetail: TMDBTVSeasonDetail = try? await client.getV3(path: "/3/tv/\(tvID)/season/\(seasonNumber)") {
                        latestEpisodes = Self.latestEpisodes(from: seasonDetail)
                    }
                }
                let trailers = videosResponse.results.filter { $0.type == "Trailer" }
                return (configResponse.images, detailResponse, creditsResponse, trailers, latestSeasonNumber, latestEpisodes)
            }.value

            imageConfig = result.0
            detail = result.1
            credits = result.2
            trailers = result.3
            latestSeasonNumber = result.4
            latestEpisodes = result.5
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

    private nonisolated static func latestSeasonNumber(from detail: TMDBTVSeriesDetail) -> Int? {
        if let last = detail.lastEpisodeToAir?.seasonNumber {
            return last
        }
        return detail.seasons
            .filter { $0.seasonNumber > 0 }
            .map(\.seasonNumber)
            .max()
    }

    private nonisolated static func latestEpisodes(from season: TMDBTVSeasonDetail) -> [TMDBEpisode] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"

        func isFutureEpisode(_ airDate: String?) -> Bool {
            guard let airDate, let date = formatter.date(from: airDate) else {
                return false
            }
            return date > Date()
        }

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
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let proposedWidth = proposal.width
        let maxWidth = (proposedWidth?.isFinite == true) ? proposedWidth! : .greatestFiniteMagnitude
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
        let width: CGFloat
        if let proposedWidth, proposedWidth.isFinite {
            width = proposedWidth
        } else {
            width = rowWidths.max() ?? 0
        }
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width.isFinite ? bounds.width : .greatestFiniteMagnitude
        let rows = makeRows(subviews: subviews, maxWidth: maxWidth)
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
