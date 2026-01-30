import Kingfisher
import SwiftUI

struct SearchResultRow: View {
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
        .contentShape(Rectangle())
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

private extension TMDBSearchResultItem {
    var subtitleText: String {
        if let date = TMDBDateFormatter.format(releaseDate) { return date }
        if let date = TMDBDateFormatter.format(firstAirDate) { return date }
        if let department = knownForDepartment, !department.isEmpty { return department }
        return ""
    }
}
