import Combine
import Foundation

@MainActor
final class PlexServerListViewModel: ObservableObject {
    @Published var servers: [PlexServer] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let client: PlexAPIClient
    private var lastToken: String?

    init(client: PlexAPIClient = PlexAPIClient()) {
        self.client = client
    }

    func load(token: String?, force: Bool = false) async {
        guard let token, !token.isEmpty else {
            servers = []
            lastToken = nil
            return
        }

        guard force || lastToken != token || servers.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        do {
            servers = try await client.fetchServers(token: token)
            lastToken = token
        } catch {
            servers = []
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func name(for id: String?) -> String? {
        guard let id else { return nil }
        return servers.first(where: { $0.id == id })?.name
    }
}
