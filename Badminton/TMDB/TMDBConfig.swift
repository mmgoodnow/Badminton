import Foundation

enum TMDBConfig {
    static let apiBaseURL = URL(string: "https://api.themoviedb.org")!
    static let apiKey = stringValue(for: "TMDB_API_KEY")
    static let readAccessToken = stringValue(for: "TMDB_READ_ACCESS_TOKEN")
    static let redirectURI = stringValue(for: "TMDB_REDIRECT_URI")
    static let authBaseURL = stringValue(for: "TMDB_AUTH_BASE_URL", defaultValue: "https://www.themoviedb.org/auth/access")

    private static func stringValue(for key: String, defaultValue: String = "") -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? defaultValue
    }
}
