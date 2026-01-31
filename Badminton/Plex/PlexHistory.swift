import Foundation

struct PlexHistoryResponse: Decodable {
    let items: [PlexHistoryItem]

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }

    private struct MediaContainer: Decodable {
        let metadata: [PlexHistoryItem]?

        private enum CodingKeys: String, CodingKey {
            case metadata = "Metadata"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mediaContainer = try container.decode(MediaContainer.self, forKey: .mediaContainer)
        items = mediaContainer.metadata ?? []
    }
}

struct PlexHistoryItem: Decodable, Identifiable {
    let ratingKey: String
    let type: String?
    let title: String?
    let grandparentTitle: String?
    let parentTitle: String?
    let index: Int?
    let parentIndex: Int?
    let year: Int?
    let originallyAvailableAt: String?
    let viewedAt: Int?
    let accountID: Int?
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
        case originallyAvailableAt
        case viewedAt
        case accountID
        case thumb
        case parentThumb
        case grandparentThumb
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let ratingKey = try? container.decode(String.self, forKey: .ratingKey) {
            self.ratingKey = ratingKey
        } else if let ratingKeyInt = try? container.decode(Int.self, forKey: .ratingKey) {
            self.ratingKey = String(ratingKeyInt)
        } else {
            self.ratingKey = UUID().uuidString
        }
        type = try? container.decode(String.self, forKey: .type)
        title = try? container.decode(String.self, forKey: .title)
        grandparentTitle = try? container.decode(String.self, forKey: .grandparentTitle)
        parentTitle = try? container.decode(String.self, forKey: .parentTitle)
        index = try? container.decode(Int.self, forKey: .index)
        parentIndex = try? container.decode(Int.self, forKey: .parentIndex)
        year = try? container.decode(Int.self, forKey: .year)
        originallyAvailableAt = try? container.decode(String.self, forKey: .originallyAvailableAt)
        if let viewedAt = try? container.decode(Int.self, forKey: .viewedAt) {
            self.viewedAt = viewedAt
        } else if let viewedAtString = try? container.decode(String.self, forKey: .viewedAt) {
            self.viewedAt = Int(viewedAtString)
        } else {
            viewedAt = nil
        }
        if let accountID = try? container.decode(Int.self, forKey: .accountID) {
            self.accountID = accountID
        } else if let accountIDString = try? container.decode(String.self, forKey: .accountID) {
            self.accountID = Int(accountIDString)
        } else {
            accountID = nil
        }
        thumb = try? container.decode(String.self, forKey: .thumb)
        parentThumb = try? container.decode(String.self, forKey: .parentThumb)
        grandparentThumb = try? container.decode(String.self, forKey: .grandparentThumb)
    }

    var displayTitle: String {
        switch type?.lowercased() ?? "" {
        case "episode":
            return title ?? grandparentTitle ?? parentTitle ?? "Untitled"
        default:
            return title ?? grandparentTitle ?? parentTitle ?? "Untitled"
        }
    }

    var displaySubtitle: String {
        switch type?.lowercased() ?? "" {
        case "episode":
            var parts: [String] = []
            if let parentIndex, let index {
                parts.append("S\(parentIndex)E\(index)")
            }
            if let title, !title.isEmpty {
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

struct PlexMetadataResponse: Decodable {
    let items: [PlexMetadataItem]

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }

    private struct MediaContainer: Decodable {
        let metadata: [PlexMetadataItem]?

        private enum CodingKeys: String, CodingKey {
            case metadata = "Metadata"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mediaContainer = try container.decode(MediaContainer.self, forKey: .mediaContainer)
        items = mediaContainer.metadata ?? []
    }
}

struct PlexMetadataItem: Decodable {
    let ratingKey: String?
    let parentRatingKey: String?
    let grandparentRatingKey: String?
    let guid: String?
    let type: String?
    let title: String?
    let grandparentTitle: String?
    let parentIndex: Int?
    let index: Int?
    let year: Int?
    let originallyAvailableAt: String?
    let guids: [PlexMetadataGuid]?

    private enum CodingKeys: String, CodingKey {
        case ratingKey
        case parentRatingKey
        case grandparentRatingKey
        case guid
        case type
        case title
        case grandparentTitle
        case parentIndex
        case index
        case year
        case originallyAvailableAt
        case guids = "Guid"
    }
}

struct PlexMetadataGuid: Decodable {
    let id: String
}
