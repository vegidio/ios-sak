import Foundation

struct CacheEntry {
    let data: Data
    let httpResponse: HTTPURLResponse
    /// `nil` means the entry never expires (cache kept until evicted by `maxEntries`).
    let expiresAt: Date?

    var isExpired: Bool {
        expiresAt.map { Date() >= $0 } ?? false
    }
}

/// NSCache requires AnyObject values; this box wraps the Sendable CacheEntry.
private final class CacheEntryBox: @unchecked Sendable {
    let entry: CacheEntry
    init(_ entry: CacheEntry) {
        self.entry = entry
    }
}

actor ResponseCache {
    private let storage = NSCache<NSString, CacheEntryBox>()

    /// - Parameter maxEntries: Upper bound on the number of cached responses. `nil` means no
    ///   limit (NSCache `countLimit` of 0).
    init(maxEntries: Int? = nil) {
        storage.countLimit = maxEntries ?? 0
    }

    func store(_ data: Data, httpResponse: HTTPURLResponse, forKey key: String, ttl: TimeInterval?) {
        let expiresAt = ttl.map { Date().addingTimeInterval($0) }
        let entry = CacheEntry(data: data, httpResponse: httpResponse, expiresAt: expiresAt)
        storage.setObject(CacheEntryBox(entry), forKey: key as NSString)
    }

    func retrieve(forKey key: String) -> CacheEntry? {
        guard let box = storage.object(forKey: key as NSString) else { return nil }
        if box.entry.isExpired {
            storage.removeObject(forKey: key as NSString)
            return nil
        }
        return box.entry
    }

    func invalidate(forKey key: String) {
        storage.removeObject(forKey: key as NSString)
    }

    static func makeKey(url: String, queryParams: [String: String]) -> String {
        guard !queryParams.isEmpty else { return url }
        let sorted = queryParams.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        return "\(url)?\(sorted)"
    }
}
