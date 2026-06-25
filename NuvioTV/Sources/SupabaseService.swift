import Foundation

enum NuvioServiceError: LocalizedError, Equatable {
    case invalidConfiguration
    case invalidResponse
    case httpStatus(Int, String)
    case missingSession

    var statusCode: Int? {
        if case let .httpStatus(status, _) = self {
            return status
        }
        return nil
    }

    var shouldRefreshSession: Bool {
        statusCode == 401 || statusCode == 403
    }

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            "Nuvio backend settings are incomplete."
        case .invalidResponse:
            "Nuvio returned an unexpected response."
        case let .httpStatus(status, body):
            body.isEmpty ? "Nuvio request failed with HTTP \(status)." : "Nuvio request failed with HTTP \(status): \(body)"
        case .missingSession:
            "Sign in before syncing."
        }
    }
}

actor SupabaseService {
    private let urlSession: URLSession
    private let decoder: JSONDecoder

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        self.decoder = JSONDecoder()
    }

    func signIn(email: String, password: String, config: NuvioBackendConfig) async throws -> AuthSession {
        let response: LoginSessionResponse = try await request(
            path: "/auth/v1/token",
            query: "grant_type=password",
            method: "POST",
            config: config,
            bearerToken: nil,
            body: ["email": email, "password": password]
        )
        return response.authSession()
    }

    func signInAnonymously(config: NuvioBackendConfig) async throws -> AuthSession {
        let response: LoginSessionResponse = try await request(
            path: "/auth/v1/signup",
            method: "POST",
            config: config,
            bearerToken: nil,
            body: ["data": ["device": "tvos"]]
        )
        return response.authSession()
    }

    func refresh(session: AuthSession, config: NuvioBackendConfig) async throws -> AuthSession {
        let response: LoginSessionResponse = try await request(
            path: "/auth/v1/token",
            query: "grant_type=refresh_token",
            method: "POST",
            config: config,
            bearerToken: nil,
            body: ["refresh_token": session.refreshToken]
        )
        return response.authSession(fallbackEmail: session.email, fallbackUserId: session.userId)
    }

    func startTvLogin(session: AuthSession, deviceNonce: String, config: NuvioBackendConfig) async throws -> TvLoginStartResponse {
        let rows: [TvLoginStartResponse] = try await rpc(
            "start_tv_login_session",
            config: config,
            session: session,
            body: [
                "p_device_nonce": deviceNonce,
                "p_redirect_base_url": config.tvLoginRedirectBaseURL,
                "p_device_name": "Apple TV"
            ]
        )
        guard let first = rows.first else { throw NuvioServiceError.invalidResponse }
        return first
    }

    func pollTvLogin(code: String, deviceNonce: String, session: AuthSession, config: NuvioBackendConfig) async throws -> TvLoginPollResponse {
        let rows: [TvLoginPollResponse] = try await rpc(
            "poll_tv_login_session",
            config: config,
            session: session,
            body: ["p_code": code, "p_device_nonce": deviceNonce]
        )
        guard let first = rows.first else { throw NuvioServiceError.invalidResponse }
        return first
    }

    func exchangeTvLogin(code: String, deviceNonce: String, session: AuthSession, config: NuvioBackendConfig) async throws -> AuthSession {
        let response: LoginSessionResponse = try await request(
            path: "/functions/v1/tv-logins-exchange",
            method: "POST",
            config: config,
            bearerToken: session.accessToken,
            body: ["code": code, "device_nonce": deviceNonce]
        )
        return response.authSession()
    }

    func syncOverview(session: AuthSession, config: NuvioBackendConfig) async throws -> SyncOverview {
        try await rpcObject("get_sync_overview", config: config, session: session, body: [:])
    }

    func pullLibrary(profileId: Int, session: AuthSession, config: NuvioBackendConfig) async throws -> [SyncedLibraryItem] {
        try await rpc(
            "sync_pull_library",
            config: config,
            session: session,
            body: ["p_profile_id": profileId, "p_limit": 500, "p_offset": 0]
        )
    }

    func effectiveUserId(session: AuthSession, config: NuvioBackendConfig) async throws -> String {
        do {
            let owner: String = try await rpc("get_sync_owner", config: config, session: session, body: [:])
            return owner
        } catch {
            if let userId = session.userId, !userId.isEmpty {
                return userId
            }
            throw error
        }
    }

    func pullAddonRows(profileId: Int, session: AuthSession, config: NuvioBackendConfig) async throws -> [RemoteAddonRow] {
        let userId = try await effectiveUserId(session: session, config: config)
        let rows: [RemoteAddonRow] = try await restSelect(
            path: "/rest/v1/addons",
            queryItems: [
                URLQueryItem(name: "select", value: "url,name,enabled,sort_order,profile_id"),
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                URLQueryItem(name: "profile_id", value: "eq.\(profileId)"),
                URLQueryItem(name: "order", value: "sort_order.asc")
            ],
            config: config,
            session: session
        )
        if !rows.isEmpty { return rows }
        return try await pullAddonRowsForAllProfiles(userId: userId, session: session, config: config)
    }

    func pullPluginRows(profileId: Int, session: AuthSession, config: NuvioBackendConfig) async throws -> [RemotePluginRow] {
        let userId = try await effectiveUserId(session: session, config: config)
        let rows: [RemotePluginRow] = try await restSelect(
            path: "/rest/v1/plugins",
            queryItems: [
                URLQueryItem(name: "select", value: "url,name,enabled,sort_order,repo_type,profile_id"),
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                URLQueryItem(name: "profile_id", value: "eq.\(profileId)"),
                URLQueryItem(name: "order", value: "sort_order.asc")
            ],
            config: config,
            session: session
        )
        if !rows.isEmpty { return rows }
        return try await pullPluginRowsForAllProfiles(userId: userId, session: session, config: config)
    }

    private func pullAddonRowsForAllProfiles(userId: String, session: AuthSession, config: NuvioBackendConfig) async throws -> [RemoteAddonRow] {
        try await restSelect(
            path: "/rest/v1/addons",
            queryItems: [
                URLQueryItem(name: "select", value: "url,name,enabled,sort_order,profile_id"),
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                URLQueryItem(name: "order", value: "profile_id.asc,sort_order.asc")
            ],
            config: config,
            session: session
        )
    }

    private func pullPluginRowsForAllProfiles(userId: String, session: AuthSession, config: NuvioBackendConfig) async throws -> [RemotePluginRow] {
        try await restSelect(
            path: "/rest/v1/plugins",
            queryItems: [
                URLQueryItem(name: "select", value: "url,name,enabled,sort_order,repo_type,profile_id"),
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                URLQueryItem(name: "order", value: "profile_id.asc,sort_order.asc")
            ],
            config: config,
            session: session
        )
    }

    private func rpc<T: Decodable>(
        _ name: String,
        config: NuvioBackendConfig,
        session: AuthSession,
        body: [String: Any]
    ) async throws -> T {
        try await request(
            path: "/rest/v1/rpc/\(name)",
            method: "POST",
            config: config,
            bearerToken: session.accessToken,
            body: body
        )
    }

    private func rpcObject<T: Decodable>(
        _ name: String,
        config: NuvioBackendConfig,
        session: AuthSession,
        body: [String: Any]
    ) async throws -> T {
        try await rpc(name, config: config, session: session, body: body)
    }

    private func request<T: Decodable>(
        path: String,
        query: String? = nil,
        method: String,
        config: NuvioBackendConfig,
        bearerToken: String?,
        body: [String: Any]
    ) async throws -> T {
        guard !config.normalizedSupabaseURL.isEmpty, !config.anonKey.isEmpty else {
            throw NuvioServiceError.invalidConfiguration
        }

        var components = URLComponents(string: config.normalizedSupabaseURL + path)
        components?.percentEncodedQuery = query
        guard let url = components?.url else {
            throw NuvioServiceError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NuvioServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NuvioServiceError.httpStatus(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        return try decoder.decode(T.self, from: data)
    }

    private func restSelect<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem],
        config: NuvioBackendConfig,
        session: AuthSession
    ) async throws -> T {
        guard !config.normalizedSupabaseURL.isEmpty, !config.anonKey.isEmpty else {
            throw NuvioServiceError.invalidConfiguration
        }

        var components = URLComponents(string: config.normalizedSupabaseURL + path)
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw NuvioServiceError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NuvioServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NuvioServiceError.httpStatus(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try decoder.decode(T.self, from: data)
    }
}

private extension LoginSessionResponse {
    func authSession(fallbackEmail: String? = nil, fallbackUserId: String? = nil) -> AuthSession {
        AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresIn.map { Date().addingTimeInterval($0) },
            email: user?.email ?? fallbackEmail,
            userId: user?.id ?? fallbackUserId
        )
    }
}
