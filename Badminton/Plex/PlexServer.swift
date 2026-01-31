import Foundation

struct PlexServer: Identifiable, Hashable {
    let id: String
    let name: String
    let product: String?
    let platform: String?
    let owned: Bool
    let lastSeenAt: String?

    var displayName: String {
        if let product, !product.isEmpty {
            return "\(name) · \(product)"
        }
        return name
    }
}
