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

struct TMDBTVEpisodeResult: Decodable, Identifiable, Hashable {
    let id: Int
    let showId: Int?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let name: String?
    let stillPath: String?
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
    let lastEpisodeToAir: TMDBEpisodeSummary?
    let nextEpisodeToAir: TMDBEpisodeSummary?
    let numberOfSeasons: Int
    let numberOfEpisodes: Int
    let status: String?
    let tagline: String?
    let voteAverage: Double
    let voteCount: Int
    let genres: [TMDBGenre]
    let seasons: [TMDBTVSeasonSummary]
}

struct TMDBEpisodeSummary: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let seasonNumber: Int
    let episodeNumber: Int
    let airDate: String?
    let overview: String?
    let stillPath: String?
    let voteAverage: Double?
    let voteCount: Int?
    let runtime: Int?
}

struct TMDBTVSeasonSummary: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let seasonNumber: Int
    let episodeCount: Int
    let airDate: String?
    let overview: String?
    let posterPath: String?
}

struct TMDBTVSeasonDetail: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let seasonNumber: Int
    let airDate: String?
    let overview: String?
    let posterPath: String?
    let episodes: [TMDBEpisode]
}

struct TMDBEpisode: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let episodeNumber: Int
    let airDate: String?
    let overview: String?
    let stillPath: String?
    let voteAverage: Double?
    let voteCount: Int?
    let runtime: Int?
}

struct TMDBEpisodeDetail: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let seasonNumber: Int?
    let episodeNumber: Int?
    let airDate: String?
    let overview: String?
    let stillPath: String?
    let voteAverage: Double?
    let voteCount: Int?
    let runtime: Int?
}

struct TMDBEpisodeCredits: Decodable, Hashable {
    let id: Int
    let cast: [TMDBCastMember]
    let crew: [TMDBCrewMember]
    let guestStars: [TMDBCastMember]?
}

extension TMDBEpisodeCredits {
    func dedupingPeople() -> TMDBEpisodeCredits {
        TMDBEpisodeCredits(
            id: id,
            cast: TMDBCastMember.dedupingPrimary(cast),
            crew: TMDBCrewMember.dedupingPrimary(crew),
            guestStars: guestStars.map { TMDBCastMember.dedupingPrimary($0) }
        )
    }
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

extension TMDBCredits {
    func dedupingPeople() -> TMDBCredits {
        TMDBCredits(
            id: id,
            cast: TMDBCastMember.dedupingPrimary(cast),
            crew: TMDBCrewMember.dedupingPrimary(crew)
        )
    }
}

struct TMDBCastMember: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let originalName: String?
    let profilePath: String?
    let character: String?
    let order: Int?
}

extension TMDBCastMember {
    static func dedupingPrimary(_ cast: [TMDBCastMember]) -> [TMDBCastMember] {
        var seen = Set<Int>()
        return cast.filter { member in
            let trimmedName = member.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { return false }
            guard !seen.contains(member.id) else { return false }
            seen.insert(member.id)
            return true
        }
    }
}

struct TMDBCrewMember: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let originalName: String?
    let profilePath: String?
    let job: String?
    let department: String?
}

extension TMDBCrewMember {
    static func dedupingPrimary(_ crew: [TMDBCrewMember]) -> [TMDBCrewMember] {
        var seen = Set<Int>()
        return crew.filter { member in
            let trimmedName = member.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { return false }
            guard !seen.contains(member.id) else { return false }
            seen.insert(member.id)
            return true
        }
    }
}

struct TMDBCombinedCredits: Decodable, Hashable {
    let id: Int
    let cast: [TMDBMediaCredit]
    let crew: [TMDBMediaCredit]
}

struct TMDBPersonTVCredits: Decodable, Hashable {
    let cast: [TMDBPersonTVCredit]
    let crew: [TMDBPersonTVCredit]
}

struct TMDBPersonTVCredit: Decodable, Hashable {
    let id: Int
    let episodeCount: Int?
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
    let lastAirDate: String?
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
    let stillSizes: [String]?
}

struct TMDBVideoList: Decodable, Hashable {
    let id: Int
    let results: [TMDBVideo]
}

struct TMDBVideo: Decodable, Identifiable, Hashable {
    let id: String
    let key: String
    let name: String
    let site: String
    let type: String
    let official: Bool?
    let publishedAt: String?
}
