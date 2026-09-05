import AppKit

/// A file or folder held by a bin.
///
/// A bookmark is stored alongside the path so an item keeps working when the
/// underlying file is moved or renamed — the path alone would silently rot.
/// The path is the fallback for when a bookmark can't be resolved.
struct BinItem: Codable, Equatable, Identifiable {
    var id: UUID
    var path: String
    var bookmark: Data?

    /// True when this app hid the file so its desktop icon would disappear.
    /// Tracked so it can be put back exactly when the item leaves the bin —
    /// files hidden by anything else must be left alone.
    var didHideOriginal: Bool

    init(id: UUID = UUID(), url: URL, didHideOriginal: Bool = false) {
        self.id = id
        self.path = url.path
        self.bookmark = try? url.bookmarkData(options: [.suitableForBookmarkFile], includingResourceValuesForKeys: nil, relativeTo: nil)
        self.didHideOriginal = didHideOriginal
    }

    private enum CodingKeys: String, CodingKey {
        case id, path, bookmark, didHideOriginal
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        path = try c.decode(String.self, forKey: .path)
        bookmark = try c.decodeIfPresent(Data.self, forKey: .bookmark)
        didHideOriginal = try c.decodeIfPresent(Bool.self, forKey: .didHideOriginal) ?? false
    }

    /// Resolves to the item's current location, following the file if it moved.
    /// Returns nil when it no longer exists.
    func resolveURL() -> URL? {
        if let bookmark {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale),
               FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }

    var displayName: String {
        let url = resolveURL() ?? URL(fileURLWithPath: path)
        return FileManager.default.displayName(atPath: url.path)
    }

    var icon: NSImage {
        guard let url = resolveURL() else {
            return NSWorkspace.shared.icon(for: .item)
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    var isMissing: Bool { resolveURL() == nil }
}
