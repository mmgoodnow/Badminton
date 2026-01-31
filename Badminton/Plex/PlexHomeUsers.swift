import Foundation

struct PlexHomeUser: Identifiable, Hashable {
    let id: Int
    let title: String?
    let username: String?
    let friendlyName: String?

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

enum PlexHomeUsersXMLParser {
    static func parse(data: Data) -> [PlexHomeUser] {
        let parser = XMLParser(data: data)
        let delegate = Delegate()
        parser.delegate = delegate
        parser.parse()
        return delegate.users
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var users: [PlexHomeUser] = []

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String]
        ) {
            guard elementName == "user" else { return }
            guard let idString = attributeDict["id"], let id = Int(idString) else { return }
            let title = attributeDict["title"]
            let username = attributeDict["username"]
            let friendlyName = attributeDict["friendlyName"]
            users.append(PlexHomeUser(id: id, title: title, username: username, friendlyName: friendlyName))
        }
    }
}
