import Combine
import Kingfisher
import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if viewModel.isSearching {
                        ProgressView("Searching…")
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if viewModel.query.isEmpty {
                        emptyState
                    } else if viewModel.results.isEmpty {
                        Text("No results")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(viewModel.results) { item in
                                NavigationLink(value: item) {
                                    SearchResultRow(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Search")
            .searchable(text: $viewModel.query, placement: .toolbar, prompt: "Movies, TV, people")
            .navigationDestination(for: TMDBSearchResultItem.self) { item in
                switch item.mediaType {
                case .tv:
                    TVDetailView(tvID: item.id, title: item.displayTitle, posterPath: item.posterPath)
                case .movie:
                    MovieDetailView(movieID: item.id, title: item.displayTitle, posterPath: item.posterPath)
                case .person:
                    PlaceholderDetailView(title: item.displayTitle, subtitle: "Person details coming soon.")
                case .unknown:
                    PlaceholderDetailView(title: "Details", subtitle: "Details coming soon.")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Search TMDB")
                    .font(.title2.bold())
                Text("Find movies, TV shows, and people.")
                    .foregroundStyle(.secondary)
            }

            if !viewModel.history.isEmpty {
                historySection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent searches")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    viewModel.clearHistory()
                }
                .buttonStyle(.borderless)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(viewModel.history, id: \.self) { item in
                    Button {
                        viewModel.query = item
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "clock")
                                .foregroundStyle(.secondary)
                            Text(item)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct SearchResultRow: View {
    let item: TMDBSearchResultItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PosterThumb(url: posterURL)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(item.displayTitle)
                        .font(.headline)
                    if item.mediaType != .unknown {
                        Text(item.mediaType.rawValue.uppercased())
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Text(item.subtitleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    private var posterURL: URL? {
        if let profile = item.profilePath {
            return SearchViewModel.posterURL(path: profile, size: "w185")
        }
        if let poster = item.posterPath {
            return SearchViewModel.posterURL(path: poster, size: "w185")
        }
        return nil
    }
}

private struct PosterThumb: View {
    let url: URL?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
            if let url {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: 72, height: 108)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct PlaceholderDetailView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.largeTitle.bold())
            Text(subtitle)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding()
    }
}

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published private(set) var results: [TMDBSearchResultItem] = []
    @Published private(set) var isSearching = false
    @Published private(set) var history: [String] = []

    private let client: TMDBAPIClient
    private var cancellables = Set<AnyCancellable>()
    private let historyKey = "tmdb.search.history"

    init(client: TMDBAPIClient = TMDBAPIClient()) {
        self.client = client
        history = UserDefaults.standard.stringArray(forKey: historyKey) ?? []

        $query
            .removeDuplicates()
            .debounce(for: .milliseconds(350), scheduler: DispatchQueue.main)
            .sink { [weak self] value in
                Task { await self?.search(query: value) }
            }
            .store(in: &cancellables)
    }

    func search(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }

        isSearching = true
        defer { isSearching = false }

        do {
            let response: TMDBPagedResults<TMDBSearchResultItem> = try await client.getV3(
                path: "/3/search/multi",
                queryItems: [
                    URLQueryItem(name: "query", value: query),
                    URLQueryItem(name: "include_adult", value: "false"),
                ]
            )
            guard query == self.query else { return }
            results = response.results
            addToHistory(trimmed)
        } catch {
            results = []
        }
    }

    func clearHistory() {
        history = []
        UserDefaults.standard.removeObject(forKey: historyKey)
    }

    private func addToHistory(_ query: String) {
        guard query.count >= 2 else { return }
        let updated = [query] + history.filter { $0.caseInsensitiveCompare(query) != .orderedSame }
        history = Array(updated.prefix(12))
        UserDefaults.standard.set(history, forKey: historyKey)
    }

    static func posterURL(path: String, size: String) -> URL? {
        let cleanedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "https://image.tmdb.org/t/p/")?.appendingPathComponent(size).appendingPathComponent(cleanedPath)
    }
}

private extension TMDBSearchResultItem {
    var subtitleText: String {
        if let date = releaseDate, !date.isEmpty { return date }
        if let date = firstAirDate, !date.isEmpty { return date }
        if let department = knownForDepartment, !department.isEmpty { return department }
        return ""
    }
}

#Preview {
    SearchView()
}
