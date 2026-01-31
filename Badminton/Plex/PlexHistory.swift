import Foundation

struct PlexHistoryResponse: Decodable {
    let items: [PlexHistoryItem]

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }

    private struct MediaContainer: Decodable {
        let metadata: [PlexHistoryItem]

        private enum CodingKeys: String, CodingKey {
            case metadata = "Metadata"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mediaContainer = try container.decode(MediaContainer.self, forKey: .mediaContainer)
        items = mediaContainer.metadata
    }
}

struct PlexHistoryItem: Decodable, Identifiable {
    let ratingKey: String
    let type: String
    let title: String
    let grandparentTitle: String?
    let parentTitle: String?
    let index: Int?
    let parentIndex: Int?
    let year: Int?
    let thumb: String?
    let parentThumb: String?
    let grandparentThumb: String?

    var id: String { ratingKey }

    private enum CodingKeys: String, CodingKey {
        case ratingKey
        case type
        case title
        case grandparentTitle
        case parentTitle
        case index
        case parentIndex
        case year
        case thumb
        case parentThumb
        case grandparentThumb
    }

    var displayTitle: String {
        switch type.lowercased() {
        case "episode":
            return grandparentTitle ?? title
        default:
            return title
        }
    }

    var displaySubtitle: String {
        switch type.lowercased() {
        case "episode":
            var parts: [String] = []
            if let parentIndex, let index {
                parts.append("S\(parentIndex)E\(index)")
            }
            if !title.isEmpty {
                parts.append(title)
            }
            return parts.joined(separator: " • ")
        case "movie", "show":
            if let year {
                return String(year)
            }
            return ""
        default:
            return ""
        }
    }

    var imageURL: URL? {
        let candidate = thumb ?? grandparentThumb ?? parentThumb
        return PlexHistoryItem.resolveURL(path: candidate)
    }

    func imageURL(serverBaseURL: URL, token: String) -> URL? {
        guard var path = thumb ?? grandparentThumb ?? parentThumb, !path.isEmpty else { return nil }
        if path.hasPrefix("/") {
            path.removeFirst()
        }
        var url = serverBaseURL.appendingPathComponent(path)
        if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            var queryItems = components.queryItems ?? []
            queryItems.append(URLQueryItem(name: "X-Plex-Token", value: token))
            components.queryItems = queryItems
            if let resolved = components.url {
                url = resolved
            }
        }
        return url
    }

    private static func resolveURL(path: String?) -> URL? {
        guard var path, !path.isEmpty else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        if path.hasPrefix("/") {
            path.removeFirst()
        }
        return URL(string: "https://metadata-static.plex.tv")?
            .appendingPathComponent(path)
    }
}
