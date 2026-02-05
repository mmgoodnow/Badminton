import Combine
import Kingfisher
import SwiftUI

struct PersonDetailView: View {
    let personID: Int
    let nameFallback: String?
    let profilePathFallback: String?

    @StateObject private var viewModel: PersonDetailViewModel
    @State private var lightboxItem: ImageLightboxItem?
    @Environment(\.listItemStyle) private var listItemStyle
    @EnvironmentObject private var overseerrLibraryIndex: OverseerrLibraryIndex

    init(personID: Int, name: String? = nil, profilePath: String? = nil) {
        self.personID = personID
        self.nameFallback = name
        self.profilePathFallback = profilePath
        _viewModel = StateObject(wrappedValue: PersonDetailViewModel(personID: personID))
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
                    ProgressView("Loading profile…")
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if let detail = viewModel.detail {
                    biographySection(detail: detail)
                    knownForSection
                    creditsSection
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(viewModel.name ?? nameFallback ?? "Person")
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
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                if let url = viewModel.profileURL(path: viewModel.detail?.profilePath ?? profilePathFallback) {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: 140, height: 210)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture {
                if let url = viewModel.profileURL(path: viewModel.detail?.profilePath ?? profilePathFallback) {
                    showLightbox(url: url, title: viewModel.name ?? nameFallback ?? "Profile")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.name ?? nameFallback ?? "")
                    .font(.title.bold())
                if let detail = viewModel.detail {
                    headerInfo(detail: detail)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func biographySection(detail: TMDBPersonDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Biography")
                .font(.headline)
            Text(detail.biography.isEmpty ? "No biography available" : detail.biography)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private func headerInfo(detail: TMDBPersonDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let department = detail.knownForDepartment, !department.isEmpty {
                infoStack(label: "Known for", value: department)
            }
            if let bornValue = bornValue(for: detail, place: detail.placeOfBirth) {
                infoStack(label: "Born", value: bornValue)
            }
            if let diedValue = diedValue(for: detail) {
                infoStack(label: "Died", value: diedValue)
            }
        }
    }

    private var knownForSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Known for")
                .font(.headline)

            if viewModel.knownFor.isEmpty {
                Text("No credits available")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(viewModel.knownFor) { credit in
                            let card = ListPosterCard(
                                title: credit.displayTitle,
                                subtitle: viewModel.creditSubtitle(credit, includeAge: false, lineBreaks: false),
                                imageURL: viewModel.posterURL(path: credit.posterPath),
                                showDogEar: hasDogEar(for: credit)
                            )
                            if credit.mediaType == .movie || credit.mediaType == .tv {
                                NavigationLink {
                                    creditDestination(credit)
                                } label: {
                                    card
                                }
                                .buttonStyle(.plain)
                            } else {
                                card
                            }
                        }
                    }
                }
            }
        }
    }

    private var creditsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Credits")
                .font(.headline)

            if viewModel.credits.isEmpty {
                Text("No credits available")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
#if os(macOS)
                LazyVGrid(
                    columns: gridColumns,
                    alignment: .leading,
                    spacing: 16
                ) {
                    ForEach(viewModel.credits) { credit in
                        let isTappable = credit.mediaType == .movie || credit.mediaType == .tv
                        let subtitleLines = viewModel.creditSubtitle(
                            credit,
                            includeYear: true,
                            includeAge: true,
                            lineBreaks: true
                        )
                        .split(separator: "\n")
                        .map(String.init)
                        let card = ListPosterGridItem(
                            title: credit.displayTitle,
                            subtitleLines: subtitleLines,
                            imageURL: viewModel.posterURL(path: credit.posterPath),
                            showDogEar: hasDogEar(for: credit)
                        )
                        if isTappable {
                            NavigationLink {
                                creditDestination(credit)
                            } label: {
                                card
                            }
                            .buttonStyle(.plain)
                        } else {
                            card
                        }
                    }
                }
#else
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.credits) { credit in
                        let isTappable = credit.mediaType == .movie || credit.mediaType == .tv
                        let row = ListItemRow(
                            title: credit.displayTitle,
                            subtitle: viewModel.creditSubtitle(
                                credit,
                                includeYear: true,
                                includeAge: true,
                                lineBreaks: true
                            ),
                            imageURL: viewModel.posterURL(path: credit.posterPath),
                            showDogEar: hasDogEar(for: credit),
                            showChevron: isTappable
                        )
                        if isTappable {
                            NavigationLink {
                                creditDestination(credit)
                            } label: {
                                row
                            }
                            .buttonStyle(.plain)
                        } else {
                            row
                        }
                    }
                }
#endif
            }
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

    private func showLightbox(url: URL, title: String) {
        lightboxItem = ImageLightboxItem(url: url, title: title)
    }

    private func ageString(birthday: String?, reference: String?) -> String? {
        guard let birthday,
              let birthDate = TMDBDateFormatter.input.date(from: birthday) else { return nil }
        let referenceDate: Date
        if let reference, let referenceParsed = TMDBDateFormatter.input.date(from: reference) {
            referenceDate = referenceParsed
        } else {
            referenceDate = Date()
        }
        let years = Calendar.current.dateComponents([.year], from: birthDate, to: referenceDate).year
        guard let years else { return nil }
        return "\(years) years old"
    }

    private func bornValue(for detail: TMDBPersonDetail, place: String?) -> String? {
        guard let birthday = TMDBDateFormatter.format(detail.birthday) else { return nil }
        var line1 = birthday
        if detail.deathday == nil, let age = ageString(birthday: detail.birthday, reference: nil) {
            line1 += " · \(age)"
        }
        if let place, !place.isEmpty {
            return "\(line1)\n\(place)"
        }
        return line1
    }

    private func diedValue(for detail: TMDBPersonDetail) -> String? {
        guard let deathday = TMDBDateFormatter.format(detail.deathday) else { return nil }
        if let ageAtDeath = ageString(birthday: detail.birthday, reference: detail.deathday) {
            return "\(deathday) · \(ageAtDeath)"
        }
        return deathday
    }

    @ViewBuilder
    private func creditDestination(_ credit: TMDBMediaCredit) -> some View {
        switch credit.mediaType {
        case .movie:
            MovieDetailView(movieID: credit.id, title: credit.displayTitle, posterPath: credit.posterPath)
        case .tv:
            TVDetailView(tvID: credit.id, title: credit.displayTitle, posterPath: credit.posterPath)
        case .person, .unknown:
            Text("Details coming soon.")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private func hasDogEar(for credit: TMDBMediaCredit) -> Bool {
        guard credit.mediaType == .movie || credit.mediaType == .tv else { return false }
        return overseerrLibraryIndex.isAvailable(tmdbID: credit.id)
    }
}

@MainActor
final class PersonDetailViewModel: ObservableObject {
    @Published var detail: TMDBPersonDetail?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var knownFor: [TMDBMediaCredit] = []
    @Published private(set) var credits: [TMDBMediaCredit] = []

    let personID: Int

    private let client: TMDBAPIClient
    private var imageConfig: TMDBImageConfigValues?
    private var hasLoaded = false
    private var tvEpisodeCounts: [Int: Int] = [:]

    init(personID: Int, client: TMDBAPIClient = TMDBAPIClient()) {
        self.personID = personID
        self.client = client
    }

    var name: String? {
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
            async let detail: TMDBPersonDetail = client.getV3(path: "/3/person/\(personID)")
            async let credits: TMDBCombinedCredits = client.getV3(path: "/3/person/\(personID)/combined_credits")
            async let tvCredits: TMDBPersonTVCredits = client.getV3(path: "/3/person/\(personID)/tv_credits")

            let (configResponse, detailResponse, creditsResponse) = try await (config, detail, credits)
            imageConfig = configResponse.images
            self.detail = detailResponse
            let tvCreditsResponse = try? await tvCredits
            tvEpisodeCounts = Self.buildEpisodeCounts(from: tvCreditsResponse)
            applyCredits(cast: creditsResponse.cast, crew: creditsResponse.crew)
            hasLoaded = true
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func profileURL(path: String?) -> URL? {
        imageURL(path: path, sizes: imageConfig?.profileSizes, fallback: "w342")
    }

    func posterURL(path: String?) -> URL? {
        imageURL(path: path, sizes: imageConfig?.posterSizes, fallback: "w342")
    }

    func creditSubtitle(
        _ credit: TMDBMediaCredit,
        includeYear: Bool = true,
        includeAge: Bool = false,
        lineBreaks: Bool = false
    ) -> String {
        var parts: [String] = []
        if let role = credit.character, !role.isEmpty {
            parts.append(role)
        } else if let job = credit.job, !job.isEmpty {
            parts.append(job)
        }
        if credit.mediaType == .tv, let episodeCount = tvEpisodeCounts[credit.id], episodeCount > 0 {
            let suffix = episodeCount == 1 ? "episode" : "episodes"
            parts.append("\(episodeCount) \(suffix)")
        }
        let appearanceDateValue = appearanceDateValue(for: credit)
        let appearanceYear = yearString(from: appearanceDate(for: credit))
        if includeYear {
            if includeAge,
               let appearanceDateValue,
               let age = age(at: appearanceDateValue, birthday: detail?.birthday) {
                if let appearanceYear {
                    parts.append("\(appearanceYear) · age \(age)")
                } else {
                    parts.append("age \(age)")
                }
            } else if let appearanceYear {
                parts.append(appearanceYear)
            }
        }
        if credit.mediaType == .tv {
            if let startYear = yearString(from: credit.firstAirDate),
               startYear != appearanceYear {
                parts.append("started \(startYear)")
            }
        }
        let separator = lineBreaks ? "\n" : " • "
        return parts.joined(separator: separator)
    }

    private func applyCredits(cast: [TMDBMediaCredit], crew: [TMDBMediaCredit]) {
        let castKeys = Set(cast.map { "\($0.mediaType.rawValue):\($0.id)" })
        let merged = cast + crew.filter { !castKeys.contains("\($0.mediaType.rawValue):\($0.id)") }
        sortCredits(from: merged)
    }

    private func sortCredits(from creditsSource: [TMDBMediaCredit]) {
        let sorted = creditsSource.sorted { (lhs, rhs) in
            let lhsIsSelf = isSelfRole(lhs)
            let rhsIsSelf = isSelfRole(rhs)
            if lhsIsSelf != rhsIsSelf {
                return !lhsIsSelf
            }
            let lhsDate = appearanceDate(for: lhs) ?? ""
            let rhsDate = appearanceDate(for: rhs) ?? ""
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            let lhsPopularity = lhs.popularity ?? 0
            let rhsPopularity = rhs.popularity ?? 0
            if lhsPopularity != rhsPopularity {
                return lhsPopularity > rhsPopularity
            }
            return lhs.displayTitle < rhs.displayTitle
        }
        let deduped = dedupeCredits(sorted)
        credits = Array(deduped.prefix(40))
        let knownForCandidates = sorted.filter { !isSelfRole($0) }
        let knownForSource = knownForCandidates.isEmpty ? sorted : knownForCandidates
        let knownForUnique = dedupeCredits(knownForSource)
        knownFor = Array(knownForUnique.prefix(12))
    }

    private func dedupeCredits(_ credits: [TMDBMediaCredit]) -> [TMDBMediaCredit] {
        var seen = Set<String>()
        return credits.filter { credit in
            let key = "\(credit.mediaType.rawValue):\(credit.id)"
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private func appearanceDate(for credit: TMDBMediaCredit) -> String? {
        switch credit.mediaType {
        case .tv:
            return credit.lastAirDate ?? credit.firstAirDate
        case .movie:
            return credit.releaseDate ?? credit.firstAirDate ?? credit.lastAirDate
        case .person, .unknown:
            return credit.releaseDate ?? credit.firstAirDate ?? credit.lastAirDate
        }
    }

    private func appearanceDateValue(for credit: TMDBMediaCredit) -> Date? {
        guard let dateString = appearanceDate(for: credit) else { return nil }
        return TMDBDateFormatter.input.date(from: dateString)
    }

    private func age(at referenceDate: Date, birthday: String?) -> Int? {
        guard let birthday,
              let birthDate = TMDBDateFormatter.input.date(from: birthday) else { return nil }
        return Calendar.current.dateComponents([.year], from: birthDate, to: referenceDate).year
    }

    private static func buildEpisodeCounts(from credits: TMDBPersonTVCredits?) -> [Int: Int] {
        guard let credits else { return [:] }
        var counts: [Int: Int] = [:]
        for credit in credits.cast + credits.crew {
            guard let episodeCount = credit.episodeCount, episodeCount > 0 else { continue }
            counts[credit.id] = max(counts[credit.id] ?? 0, episodeCount)
        }
        return counts
    }

    private func yearString(from dateString: String?) -> String? {
        guard let dateString, dateString.count >= 4 else { return nil }
        return String(dateString.prefix(4))
    }

    private func isSelfRole(_ credit: TMDBMediaCredit) -> Bool {
        guard let character = credit.character, !character.isEmpty else { return false }
        return character.range(of: "self", options: [.caseInsensitive, .diacriticInsensitive]) != nil
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
        PersonDetailView(personID: 287, name: "Brad Pitt")
    }
    .environmentObject(OverseerrLibraryIndex())
}
