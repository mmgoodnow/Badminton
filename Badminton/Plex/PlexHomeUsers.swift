import Foundation

struct PlexHomeUsersResponse: Decodable {
    let users: [PlexHomeUser]
}

struct PlexHomeUser: Identifiable, Hashable, Decodable {
    let id: Int
    let title: String?
    let username: String?
    let friendlyName: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case username
        case friendlyName
    }

    var displayName: String {
        if let friendlyName, !friendlyName.isEmpty {
            return friendlyName
        }
        if let title, !title.isEmpty {
            return title
        }
        if let username, !username.isEmpty {
            return username
        }
        return "Account \(id)"
    }
}
