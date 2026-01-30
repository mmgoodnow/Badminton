import Combine
import Kingfisher
import SwiftUI

struct PersonDetailView: View {
    let personID: Int
    let nameFallback: String?
    let profilePathFallback: String?

    @StateObject private var viewModel: PersonDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var lightboxItem: ImageLightboxItem?

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
                    infoSection(detail: detail)
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
        .navigationDestination(for: TMDBMediaCredit.self) { credit in
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
        .imageLightbox(item: $lightboxItem)
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
                if let department = viewModel.detail?.knownForDepartment, !department.isEmpty {
                    Text(department)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let birthday = TMDBDateFormatter.format(viewModel.detail?.birthday) {
                    Text("Born \(birthday)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let place = viewModel.detail?.placeOfBirth, !place.isEmpty {
                    Text(place)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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

    private func infoSection(detail: TMDBPersonDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Info")
                .font(.headline)
            if let deathday = TMDBDateFormatter.format(detail.deathday) {
                infoRow(label: "Died", value: deathday)
            }
            if let department = detail.knownForDepartment, !department.isEmpty {
                infoRow(label: "Known for", value: department)
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
                    HStack(spacing: 16) {
                        ForEach(viewModel.knownFor) { credit in
                            let card = CreditCardView(
                                title: credit.displayTitle,
                                subtitle: viewModel.creditSubtitle(credit),
                                imageURL: viewModel.posterURL(path: credit.posterPath)
                            )
                            if credit.mediaType == .movie || credit.mediaType == .tv {
                                NavigationLink(value: credit) {
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
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.credits) { credit in
                        let row = CreditRowView(
                            title: credit.displayTitle,
                            subtitle: viewModel.creditSubtitle(credit),
                            imageURL: viewModel.posterURL(path: credit.posterPath)
                        )
                        if credit.mediaType == .movie || credit.mediaType == .tv {
                            NavigationLink(value: credit) {
                                row
                            }
                            .buttonStyle(.plain)
                        } else {
                            row
                        }
                    }
                }
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

private struct CreditCardView: View {
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

private struct CreditRowView: View {
    let title: String
    let subtitle: String
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
            .frame(width: 70, height: 105)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if !subtitle.isEmpty {
                    Text(subtitle)
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

            let (configResponse, detailResponse, creditsResponse) = try await (config, detail, credits)
            imageConfig = configResponse.images
            self.detail = detailResponse
            applyCredits(cast: creditsResponse.cast, crew: creditsResponse.crew)
            hasLoaded = true
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

    func creditSubtitle(_ credit: TMDBMediaCredit) -> String {
        var parts: [String] = []
        if let role = credit.character, !role.isEmpty {
            parts.append(role)
        } else if let job = credit.job, !job.isEmpty {
            parts.append(job)
        }
        if let date = credit.releaseDate ?? credit.firstAirDate, !date.isEmpty {
            parts.append(String(date.prefix(4)))
        }
        return parts.joined(separator: " • ")
    }

    private func applyCredits(cast: [TMDBMediaCredit], crew: [TMDBMediaCredit]) {
        let castKeys = Set(cast.map { "\($0.mediaType.rawValue):\($0.id)" })
        let merged = cast + crew.filter { !castKeys.contains("\($0.mediaType.rawValue):\($0.id)") }
        let sorted = merged.sorted { (lhs, rhs) in
            (lhs.popularity ?? 0) > (rhs.popularity ?? 0)
        }
        credits = Array(sorted.prefix(40))
        knownFor = Array(sorted.prefix(12))
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
}
