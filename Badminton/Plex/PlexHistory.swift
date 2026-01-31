import Foundation

struct PlexHistoryResponse: Decodable {
    let items: [PlexHistoryItem]

    private enum RootKeys: String, CodingKey {
        case items
        case mediaContainer = "MediaContainer"
    }

    private struct MediaContainer: Decodable {
        let metadata: [PlexHistoryItem]?

        private enum CodingKeys: String, CodingKey {
            case metadata = "Metadata"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: RootKeys.self)
        if let items = try? container.decode([PlexHistoryItem].self, forKey: .items) {
            self.items = items
            return
        }
        if let media = try? container.decode(MediaContainer.self, forKey: .mediaContainer),
           let metadata = media.metadata {
            self.items = metadata
            return
        }
        self.items = []
    }
}

struct PlexHistoryItem: Decodable, Identifiable {
    let id: String
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

    private enum CodingKeys: String, CodingKey {
        case id
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let ratingKey = try? container.decode(String.self, forKey: .ratingKey) {
            id = ratingKey
        } else if let ratingKeyInt = try? container.decode(Int.self, forKey: .ratingKey) {
            id = String(ratingKeyInt)
        } else if let rawID = try? container.decode(String.self, forKey: .id) {
            id = rawID
        } else if let rawIDInt = try? container.decode(Int.self, forKey: .id) {
            id = String(rawIDInt)
        } else {
            id = UUID().uuidString
        }

        type = (try? container.decode(String.self, forKey: .type)) ?? "unknown"
        title = (try? container.decode(String.self, forKey: .title)) ?? ""
        grandparentTitle = try? container.decode(String.self, forKey: .grandparentTitle)
        parentTitle = try? container.decode(String.self, forKey: .parentTitle)
        index = try? container.decode(Int.self, forKey: .index)
        parentIndex = try? container.decode(Int.self, forKey: .parentIndex)
        year = try? container.decode(Int.self, forKey: .year)
        thumb = try? container.decode(String.self, forKey: .thumb)
        parentThumb = try? container.decode(String.self, forKey: .parentThumb)
        grandparentThumb = try? container.decode(String.self, forKey: .grandparentThumb)
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
