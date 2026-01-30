import Foundation

struct TMDBPagedResults<T: Decodable & Hashable>: Decodable, Hashable {
    let page: Int
    let results: [T]
    let totalPages: Int
    let totalResults: Int
}

enum TMDBMediaType: String, Decodable {
    case movie
    case tv
    case person
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self)) ?? ""
        self = TMDBMediaType(rawValue: rawValue) ?? .unknown
    }
}

struct TMDBSearchResultItem: Decodable, Identifiable, Hashable {
    let id: Int
    let mediaType: TMDBMediaType
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let profilePath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let voteCount: Int?
    let popularity: Double?
    let genreIds: [Int]?
    let knownForDepartment: String?
    let knownFor: [TMDBMediaSummary]?

    var displayTitle: String {
        title ?? name ?? ""
    }
}

struct TMDBMediaSummary: Decodable, Identifiable, Hashable {
    let id: Int
    let mediaType: TMDBMediaType
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let voteCount: Int?
    let popularity: Double?

    var displayTitle: String {
        title ?? name ?? ""
    }
}

struct TMDBMovieSummary: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String
    let overview: String
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let voteAverage: Double
    let voteCount: Int
    let popularity: Double
}

struct TMDBTVSeriesSummary: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let overview: String
    let posterPath: String?
    let backdropPath: String?
    let firstAirDate: String?
    let voteAverage: Double
    let voteCount: Int
    let popularity: Double
    let originCountry: [String]?
}

struct TMDBPersonSummary: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let profilePath: String?
    let knownForDepartment: String?
    let popularity: Double?
    let knownFor: [TMDBMediaSummary]?
}

struct TMDBMovieDetail: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String
    let overview: String
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let runtime: Int?
    let tagline: String?
    let status: String?
    let voteAverage: Double
    let voteCount: Int
    let genres: [TMDBGenre]
}

struct TMDBTVSeriesDetail: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let overview: String
    let posterPath: String?
    let backdropPath: String?
    let firstAirDate: String?
    let lastAirDate: String?
    let numberOfSeasons: Int
    let numberOfEpisodes: Int
    let status: String?
    let tagline: String?
    let voteAverage: Double
    let voteCount: Int
    let genres: [TMDBGenre]
}

struct TMDBPersonDetail: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let biography: String
    let birthday: String?
    let deathday: String?
    let placeOfBirth: String?
    let knownForDepartment: String?
    let profilePath: String?
}

struct TMDBGenre: Decodable, Hashable {
    let id: Int
    let name: String
}

struct TMDBCredits: Decodable, Hashable {
    let id: Int
    let cast: [TMDBCastMember]
    let crew: [TMDBCrewMember]
}

struct TMDBCastMember: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let originalName: String?
    let profilePath: String?
    let character: String?
    let order: Int?
}

struct TMDBCrewMember: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let originalName: String?
    let profilePath: String?
    let job: String?
    let department: String?
}

struct TMDBCombinedCredits: Decodable, Hashable {
    let id: Int
    let cast: [TMDBMediaCredit]
    let crew: [TMDBMediaCredit]
}

struct TMDBMediaCredit: Decodable, Identifiable, Hashable {
    let id: Int
    let mediaType: TMDBMediaType
    let title: String?
    let name: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let character: String?
    let job: String?
    let department: String?
    let voteAverage: Double?
    let voteCount: Int?
    let popularity: Double?

    var displayTitle: String {
        title ?? name ?? ""
    }
}

struct TMDBImageConfiguration: Decodable, Hashable {
    let images: TMDBImageConfigValues
}

struct TMDBImageConfigValues: Decodable, Hashable {
    let secureBaseUrl: String
    let posterSizes: [String]
    let backdropSizes: [String]
    let profileSizes: [String]
}
