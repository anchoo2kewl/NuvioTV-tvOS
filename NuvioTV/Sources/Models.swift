import Foundation

struct MediaSource: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let subtitle: String
    let url: URL
    let playbackEngine: PlaybackEngine
}

enum PlaybackEngine: String, Codable, Equatable {
    case native
    case vlc
}

enum NavigationSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case search = "Search"
    case account = "Account"
    case addons = "Add-ons"
    case plugins = "Plugins"
    case library = "Library"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .search: "magnifyingglass"
        case .account: "person.crop.circle.fill"
        case .addons: "square.grid.2x2.fill"
        case .plugins: "puzzlepiece.extension.fill"
        case .library: "play.rectangle.on.rectangle.fill"
        case .settings: "gearshape.fill"
        }
    }
}

struct NuvioAddon: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let version: String
    let description: String?
    let logo: String?
    let background: String?
    let catalogs: [NuvioCatalogDescriptor]
    let resources: [NuvioAddonResource]
    let types: [String]
    let idPrefixes: [String]
    var baseURL: String
    var enabled: Bool = true
    var userName: String?

    var displayName: String {
        let trimmed = (userName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? name : trimmed
    }

    var manifestURL: String {
        baseURL.normalizedAddonManifestURL()
    }

    var contentCatalogs: [NuvioCatalogDescriptor] {
        catalogs.filter { !$0.requiresSearch }
    }

    var searchableCatalogs: [NuvioCatalogDescriptor] {
        catalogs.filter(\.supportsSearch)
    }

    var canShowContent: Bool {
        enabled && !contentCatalogs.isEmpty
    }

    var canSearchContent: Bool {
        enabled && !searchableCatalogs.isEmpty
    }

    var supportsCatalogResource: Bool {
        resources.isEmpty || resources.contains { $0.name == "catalog" }
    }

    func supportsStreams(type: String, id: String) -> Bool {
        guard enabled else { return false }
        let hasStream = resources.contains { resource in
            resource.name == "stream" && (resource.types.isEmpty || resource.types.contains(type))
        }
        guard hasStream else { return false }
        guard !idPrefixes.isEmpty else { return true }
        return idPrefixes.contains { id.hasPrefix($0) }
    }

    func supportsMeta(type: String) -> Bool {
        guard enabled else { return false }
        return resources.contains { resource in
            resource.name == "meta" && (resource.types.isEmpty || resource.types.contains(type))
        }
    }
}

struct NuvioCatalogDescriptor: Codable, Identifiable, Hashable {
    let type: String
    let id: String
    let name: String
    let extra: [NuvioCatalogExtra]
    let pageSize: Int?
    let extraSupported: [String]
    let extraRequired: [String]

    var supportsSearch: Bool {
        extra.contains { $0.name.caseInsensitiveCompare("search") == .orderedSame } ||
        extraSupported.contains { $0.caseInsensitiveCompare("search") == .orderedSame }
    }

    var requiresSearch: Bool {
        extra.contains { $0.name.caseInsensitiveCompare("search") == .orderedSame && $0.isRequired } ||
        extraRequired.contains { $0.caseInsensitiveCompare("search") == .orderedSame }
    }
}

struct NuvioCatalogExtra: Codable, Hashable {
    let name: String
    let isRequired: Bool
    let options: [String]?
    let defaultValue: String?

    enum CodingKeys: String, CodingKey {
        case name
        case isRequired = "isRequired"
        case options
        case defaultValue = "default"
    }
}

struct NuvioAddonResource: Codable, Hashable {
    let name: String
    let types: [String]
    let idPrefixes: [String]?
}

struct NuvioCatalogItem: Codable, Identifiable, Hashable {
    let id: String
    let type: String
    let name: String
    let poster: String?
    let background: String?
    let logo: String?
    let description: String?
    let releaseInfo: String?
    let imdbRating: String?
    let genres: [String]?
    let runtime: String?
    let addonBaseURL: String
    let addonName: String

    var posterURL: URL? { poster.flatMap(URL.init(string:)) }
    var backdropURL: URL? { (background ?? poster).flatMap(URL.init(string:)) }
    var subtitle: String {
        [releaseInfo, imdbRating.map { "IMDb \($0)" }, genres?.prefix(2).joined(separator: " / ")]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "  ")
    }
}

struct NuvioVideo: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let released: String?
    let season: Int?
    let episode: Int?
    let thumbnail: String?
    let description: String?

    var displayTitle: String {
        if let season, let episode {
            return "S\(season) E\(episode)  \(title)"
        }
        return title
    }
}

struct NuvioStream: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String?
    let title: String?
    let description: String?
    let url: String?
    let externalURL: String?
    let infoHash: String?
    let addonName: String
    let addonLogo: String?
    let notWebReady: Bool
    let filename: String?
    let videoSize: Int64?

    init(
        id: UUID = UUID(),
        name: String?,
        title: String?,
        description: String?,
        url: String?,
        externalURL: String?,
        infoHash: String?,
        addonName: String,
        addonLogo: String?,
        notWebReady: Bool,
        filename: String? = nil,
        videoSize: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.title = title
        self.description = description
        self.url = url
        self.externalURL = externalURL
        self.infoHash = infoHash
        self.addonName = addonName
        self.addonLogo = addonLogo
        self.notWebReady = notWebReady
        self.filename = filename
        self.videoSize = videoSize
    }

    var displayTitle: String {
        let candidates = [title, name, description, url, externalURL]
        return candidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? "Stream"
    }

    var playableURL: URL? {
        [url, externalURL]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap { URL(string: $0) ?? URL(string: $0.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? "") }
            .first { ["http", "https"].contains($0.scheme?.lowercased()) }
    }

    var isPlayableOnTV: Bool {
        playableURL != nil
    }

    var displaySize: String? {
        if let videoSize, videoSize > 0 {
            return ByteCountFormatter.string(fromByteCount: videoSize, countStyle: .file)
        }
        return Self.firstMatch(in: metadataText, pattern: #"(?i)(\d+(?:\.\d+)?)\s*(GB|GiB|MB|MiB)"#)
    }

    var seedInfo: String? {
        Self.firstMatch(in: metadataText, pattern: #"(?i)(?:seeders|seeds|seed|👤|👥)\s*:?\s*(\d+)"#)
    }

    var qualityInfo: String? {
        Self.firstMatch(in: metadataText, pattern: #"(?i)(2160p|1080p|720p|480p|4K|HDR|DV|Dolby Vision|HEVC|x265|x264)"#)
    }

    var metadataBadges: [String] {
        [
            qualityInfo,
            containerInfo,
            displaySize.map { "Size \($0)" },
            seedInfo.map { "Seeds \($0)" },
            needsNativeTranscode ? "Needs MP4/HLS" : nil,
            notWebReady ? "May need native player" : nil,
            playableURL == nil ? "No direct URL" : nil
        ]
        .compactMap { $0 }
    }

    private var metadataText: String {
        [title, name, description, filename]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    var containerInfo: String? {
        let candidates = [filename, url, externalURL, title, name, description]
            .compactMap { $0?.lowercased() }
        let known = ["m3u8", "mp4", "m4v", "mov", "mkv", "webm", "avi", "ts"]
        for candidate in candidates {
            for ext in known where candidate.contains(".\(ext)") || candidate.contains(" \(ext)") {
                return ext.uppercased()
            }
        }
        return nil
    }

    var needsNativeTranscode: Bool {
        guard let containerInfo else { return false }
        return ["MKV", "WEBM", "AVI"].contains(containerInfo)
    }

    var preferredPlaybackEngine: PlaybackEngine {
        needsNativeTranscode || notWebReady ? .vlc : .native
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        if match.numberOfRanges > 1, let capture = Range(match.range(at: 1), in: text) {
            if match.numberOfRanges > 2, let unit = Range(match.range(at: 2), in: text) {
                return "\(text[capture]) \(text[unit])"
            }
            return String(text[capture])
        }
        guard let full = Range(match.range, in: text) else { return nil }
        return String(text[full])
    }
}

struct NuvioPluginRepo: Codable, Identifiable, Hashable {
    var id: String { url }
    let url: String
    let name: String?
    let enabled: Bool
    let repoType: String?
}

extension String {
    func normalizedAddonBaseURL() -> String {
        let normalized = normalizedAddonInput()
        let parts = normalized.addonURLParts()
        var path = parts.path
        while path.last == "/" {
            path.removeLast()
        }
        if path.lowercased().hasSuffix("/manifest.json") {
            path.removeLast("/manifest.json".count)
        }
        return path + parts.query
    }

    func normalizedAddonManifestURL() -> String {
        let base = normalizedAddonBaseURL()
        let parts = base.addonURLParts()
        return parts.path + "/manifest.json" + parts.query
    }

    fileprivate func normalizedAddonInput() -> String {
        var value = trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("stremio://") {
            value = "https://" + value.dropFirst("stremio://".count)
        }
        return value
    }

    fileprivate func addonURLParts() -> (path: String, query: String) {
        guard let queryStart = firstIndex(of: "?") else {
            return (self, "")
        }
        return (String(self[..<queryStart]), String(self[queryStart...]))
    }
}
