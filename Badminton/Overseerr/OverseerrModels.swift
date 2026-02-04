import Foundation

enum OverseerrMediaType: String, Encodable {
    case movie
    case tv
}

enum OverseerrMediaStatus: Int, Decodable {
    case unknown = 1
    case pending = 2
    case processing = 3
    case partiallyAvailable = 4
    case available = 5
    case deleted = 6

    var displayText: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .pending:
            return "Pending"
        case .processing:
            return "Processing"
        case .partiallyAvailable:
            return "Partial"
        case .available:
            return "Available"
        case .deleted:
            return "Deleted"
        }
    }
}

enum OverseerrRequestStatus: Int, Decodable {
    case pending = 1
    case approved = 2
    case declined = 3
    case failed = 4
    case completed = 5

    var displayText: String {
        switch self {
        case .pending:
            return "Pending"
        case .approved:
            return "Approved"
        case .declined:
            return "Declined"
        case .failed:
            return "Failed"
        case .completed:
            return "Completed"
        }
    }
}

struct OverseerrMediaInfo: Decodable {
    let status: OverseerrMediaStatus?
    let status4k: OverseerrMediaStatus?
    let requests: [OverseerrRequest]?
    let seasons: [OverseerrSeason]?
}

struct OverseerrRequest: Decodable {
    let status: OverseerrRequestStatus?
    let is4k: Bool?
}

struct OverseerrSeason: Decodable {
    let seasonNumber: Int
    let status: OverseerrMediaStatus?
    let status4k: OverseerrMediaStatus?
}

struct OverseerrPublicSettings: Decodable {
    let partialRequestsEnabled: Bool
}

struct OverseerrMovieResponse: Decodable {
    let mediaInfo: OverseerrMediaInfo?
}

struct OverseerrTVResponse: Decodable {
    let mediaInfo: OverseerrMediaInfo?
}

struct OverseerrRequestBody: Encodable {
    let mediaType: OverseerrMediaType
    let mediaId: Int
    let seasons: [Int]?
}

struct OverseerrRequestResponse: Decodable {
    let id: Int?
}

struct OverseerrPageInfo: Decodable {
    let pages: Int
    let page: Int
    let results: Int
    let pageSize: Int
}

struct OverseerrMediaItem: Decodable {
    let tmdbId: Int
}

struct OverseerrMediaPage: Decodable {
    let pageInfo: OverseerrPageInfo
    let results: [OverseerrMediaItem]
}
