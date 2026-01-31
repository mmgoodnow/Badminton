import Foundation

@main
struct PlexHistoryCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        var token: String?
        var size = 20
        var jsonOutput = false
        var rawOutput = false
        var rawResourcesOutput = false
        var listServers = false
        var preferredServerID: String?
        var bundleID = "com.bebopbeluga.Badminton"

        var i = 0
        while i < args.count {
            switch args[i] {
            case "--token":
                if i + 1 < args.count {
                    token = args[i + 1]
                    i += 1
                }
            case "--size":
                if i + 1 < args.count {
                    size = Int(args[i + 1]) ?? size
                    i += 1
                }
            case "--bundle-id":
                if i + 1 < args.count {
                    bundleID = args[i + 1]
                    i += 1
                }
            case "--json":
                jsonOutput = true
            case "--raw":
                rawOutput = true
            case "--raw-resources":
                rawResourcesOutput = true
            case "--list-servers":
                listServers = true
            case "--server-id":
                if i + 1 < args.count {
                    preferredServerID = args[i + 1]
                    i += 1
                }
            case "-h", "--help":
                printUsage()
                return
            default:
                break
            }
            i += 1
        }

        let envToken = ProcessInfo.processInfo.environment["PLEX_TOKEN"]
        let storedToken = UserDefaults(suiteName: bundleID)?.string(forKey: "plex.auth.token")
        let plistToken = readTokenFromPlist(bundleID: bundleID)
        guard let authToken = token ?? envToken ?? storedToken ?? plistToken, !authToken.isEmpty else {
            print("Missing Plex token. Use --token or set PLEX_TOKEN.")
            printUsage()
            return
        }

        let client = PlexAPIClient()
        do {
            if listServers {
                let servers = try await client.fetchServers(token: authToken)
                if servers.isEmpty {
                    print("No Plex servers found.")
                } else {
                    for server in servers {
                        let owned = server.owned ? "owned" : "shared"
                        let lastSeen = server.lastSeenAt ?? "unknown"
                        print("\(server.id) — \(server.displayName) (\(owned), last seen \(lastSeen))")
                    }
                }
                return
            }
            if rawResourcesOutput {
                let result = try await client.fetchResourcesRaw(token: authToken)
                let contentType = result.response.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
                print("Resources Content-Type: \(contentType)")
                if let body = String(data: result.data, encoding: .utf8) {
                    print(body)
                } else {
                    print(result.data.base64EncodedString())
                }
                return
            }
            if rawOutput {
                let result = try await client.fetchRecentlyWatchedRaw(
                    token: authToken,
                    size: size,
                    preferredServerID: preferredServerID
                )
                let contentType = result.response.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
                print("Server: \(result.serverBaseURL.absoluteString)")
                print("Content-Type: \(contentType)")
                if let body = String(data: result.data, encoding: .utf8) {
                    print(body)
                } else {
                    print(result.data.base64EncodedString())
                }
                return
            }

            let result = try await client.fetchRecentlyWatched(
                token: authToken,
                size: size,
                preferredServerID: preferredServerID
            )
            if jsonOutput {
                let payload = result.items.map { item in
                    [
                        "id": item.id,
                        "type": item.type as Any,
                        "title": item.displayTitle,
                        "subtitle": item.displaySubtitle,
                        "year": item.year as Any,
                        "thumb": item.thumb as Any
                    ]
                }
                let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
                if let jsonString = String(data: data, encoding: .utf8) {
                    print(jsonString)
                }
            } else {
                print("Server: \(result.serverBaseURL.absoluteString)")
                for item in result.items {
                    let subtitle = item.displaySubtitle.isEmpty ? "" : " — \(item.displaySubtitle)"
                    print("• \(item.displayTitle)\(subtitle)")
                }
            }
        } catch {
            print("Plex history error: \(error)")
        }
    }

    private static func printUsage() {
        print("Usage:\n  swiftc -o /tmp/plex_history \\")
        print("    Badminton/Plex/PlexConfig.swift \\")
        print("    Badminton/Plex/PlexHistory.swift \\")
        print("    Badminton/Plex/PlexAPIClient.swift \\")
        print("    scripts/plex_history.swift\n")
        print("  /tmp/plex_history [--token <PLEX_TOKEN>] [--size N] [--json] [--raw] [--raw-resources] [--list-servers] [--server-id <id>] [--bundle-id <com.app.bundle>]\n")
    }

    private static func readTokenFromPlist(bundleID: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = [
            "\(home)/Library/Containers/\(bundleID)/Data/Library/Preferences/\(bundleID).plist",
            "\(home)/Library/Preferences/\(bundleID).plist"
        ]

        for path in paths {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { continue }
            if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
               let token = plist["plex.auth.token"] as? String,
               !token.isEmpty {
                return token
            }
        }

        return nil
    }
}
