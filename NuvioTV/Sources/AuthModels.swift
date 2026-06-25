import Foundation

struct NuvioBackendConfig: Equatable {
    var supabaseURL: String
    var anonKey: String
    var tvLoginRedirectBaseURL: String

    static let hosted = NuvioBackendConfig(
        supabaseURL: "https://dpyhjjcoabcglfmgecug.supabase.co",
        anonKey: "",
        tvLoginRedirectBaseURL: "https://nuvio.tv/tv-login"
    )

    static let hostedEnvironmentURL = URL(string: "https://web.nuvioapp.space/nuvio.env.js")!

    var normalizedSupabaseURL: String {
        supabaseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmedTrailingSlash()
    }
}

struct HostedEnvironmentConfig {
    let supabaseURL: String?
    let anonKey: String?
    let tvLoginRedirectBaseURL: String?
}

struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date?
    let email: String?
    let userId: String?

    var isRefreshable: Bool {
        !refreshToken.isEmpty
    }
}

struct LoginSessionResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval?
    let user: SupabaseUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

struct SupabaseUser: Decodable, Equatable {
    let id: String
    let email: String?
}

struct TvLoginStartResponse: Decodable, Equatable {
    let code: String
    let webURL: String
    let expiresAt: String
    let pollIntervalSeconds: Int

    enum CodingKeys: String, CodingKey {
        case code
        case webURL = "web_url"
        case expiresAt = "expires_at"
        case pollIntervalSeconds = "poll_interval_seconds"
    }
}

struct TvLoginPollResponse: Decodable, Equatable {
    let status: String
    let expiresAt: String?
    let pollIntervalSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case expiresAt = "expires_at"
        case pollIntervalSeconds = "poll_interval_seconds"
    }
}

struct SyncOverview: Decodable, Equatable {
    let addons: [String: Int]
    let plugins: [String: Int]
    let libraryItems: [String: Int]
    let watchProgress: [String: Int]
    let watchedItems: [String: Int]
    let profiles: [String: ProfileInfo]

    struct ProfileInfo: Decodable, Equatable {
        let name: String
        let color: String
    }

    enum CodingKeys: String, CodingKey {
        case addons
        case plugins
        case libraryItems = "library_items"
        case watchProgress = "watch_progress"
        case watchedItems = "watched_items"
        case profiles
    }

    var totalLibraryItems: Int {
        libraryItems.values.reduce(0, +)
    }

    var totalWatchProgress: Int {
        watchProgress.values.reduce(0, +)
    }

    var totalWatchedItems: Int {
        watchedItems.values.reduce(0, +)
    }
}

struct SyncedLibraryItem: Decodable, Identifiable, Equatable {
    let id: String?
    let contentId: String
    let contentType: String
    let name: String
    let poster: String?
    let posterShape: String?
    let background: String?
    let description: String?
    let releaseInfo: String?
    let imdbRating: Double?
    let genres: [String]?
    let addonBaseURL: String?
    let addedAt: Int64?
    let profileId: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case contentId = "content_id"
        case contentType = "content_type"
        case name
        case poster
        case posterShape = "poster_shape"
        case background
        case description
        case releaseInfo = "release_info"
        case imdbRating = "imdb_rating"
        case genres
        case addonBaseURL = "addon_base_url"
        case addedAt = "added_at"
        case profileId = "profile_id"
    }
}

struct RemoteAddonRow: Decodable, Equatable {
    let url: String
    let name: String?
    let enabled: Bool?
    let sortOrder: Int?
    let profileId: Int?

    enum CodingKeys: String, CodingKey {
        case url
        case name
        case enabled
        case sortOrder = "sort_order"
        case profileId = "profile_id"
    }
}

struct RemotePluginRow: Decodable, Equatable {
    let url: String
    let name: String?
    let enabled: Bool?
    let sortOrder: Int?
    let repoType: String?
    let profileId: Int?

    enum CodingKeys: String, CodingKey {
        case url
        case name
        case enabled
        case sortOrder = "sort_order"
        case repoType = "repo_type"
        case profileId = "profile_id"
    }
}

extension String {
    fileprivate func trimmedTrailingSlash() -> String {
        var value = self
        while value.last == "/" {
            value.removeLast()
        }
        return value
    }
}
