import Foundation

@MainActor
final class AuthStore: ObservableObject {
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var config: NuvioBackendConfig
    @Published private(set) var session: AuthSession?
    @Published private(set) var overview: SyncOverview?
    @Published private(set) var syncedLibrary: [SyncedLibraryItem] = []
    @Published private(set) var tvLogin: TvLoginStartResponse?
    @Published private(set) var tvLoginStatus: String?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let service: SupabaseService
    private let hostedEnvironmentService: HostedEnvironmentService
    private let defaults: UserDefaults
    private var tvLoginNonce: String?
    private var isLoadingHostedEnvironment = false

    init(
        service: SupabaseService = SupabaseService(),
        hostedEnvironmentService: HostedEnvironmentService = HostedEnvironmentService(),
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.hostedEnvironmentService = hostedEnvironmentService
        self.defaults = defaults
        self.config = NuvioBackendConfig(
            supabaseURL: defaults.string(forKey: Keys.supabaseURL) ?? NuvioBackendConfig.hosted.supabaseURL,
            anonKey: defaults.string(forKey: Keys.anonKey) ?? NuvioBackendConfig.hosted.anonKey,
            tvLoginRedirectBaseURL: defaults.string(forKey: Keys.tvLoginRedirectBaseURL) ?? NuvioBackendConfig.hosted.tvLoginRedirectBaseURL
        )
        self.session = defaults.data(forKey: Keys.session)
            .flatMap { try? JSONDecoder().decode(AuthSession.self, from: $0) }
        Task { await loadHostedEnvironmentIfNeeded() }
    }

    var isSignedIn: Bool {
        session?.userId?.isEmpty == false || session?.email?.isEmpty == false
    }

    func saveConfig() {
        defaults.set(config.supabaseURL, forKey: Keys.supabaseURL)
        defaults.set(config.anonKey, forKey: Keys.anonKey)
        defaults.set(config.tvLoginRedirectBaseURL, forKey: Keys.tvLoginRedirectBaseURL)
    }

    func signIn() {
        Task {
            await self.run {
                try await self.ensureHostedEnvironment()
                let signedIn = try await self.service.signIn(
                    email: self.email.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: self.password,
                    config: self.config
                )
                self.setSession(signedIn)
                self.password = ""
                try await self.syncWithCurrentSession()
            }
        }
    }

    func signOut() {
        session = nil
        overview = nil
        syncedLibrary = []
        tvLogin = nil
        tvLoginNonce = nil
        tvLoginStatus = nil
        defaults.removeObject(forKey: Keys.session)
    }

    func refreshSessionIfPossible() {
        Task {
            guard let session = self.session, session.isRefreshable else { return }
            await self.run {
                try await self.ensureHostedEnvironment()
                self.setSession(try await self.service.refresh(session: session, config: self.config))
            }
        }
    }

    func startTvLogin() {
        Task {
            await self.run {
                try await self.ensureHostedEnvironment()
                let anonymous = try await self.service.signInAnonymously(config: self.config)
                let nonce = Self.makeNonce()
                let login = try await self.service.startTvLogin(session: anonymous, deviceNonce: nonce, config: self.config)
                self.setSession(anonymous)
                self.tvLoginNonce = nonce
                self.tvLogin = login
                self.tvLoginStatus = "Open the URL on your phone, approve login, then choose Check status."
            }
        }
    }

    func pollTvLogin() {
        Task {
            await self.run {
                try await self.ensureHostedEnvironment()
                guard let session = self.session, let tvLogin = self.tvLogin, let tvLoginNonce = self.tvLoginNonce else {
                    throw NuvioServiceError.missingSession
                }
                let result = try await self.service.pollTvLogin(
                    code: tvLogin.code,
                    deviceNonce: tvLoginNonce,
                    session: session,
                    config: self.config
                )
                self.tvLoginStatus = "Status: \(result.status)"
                if result.status.lowercased() == "approved" {
                    let exchanged = try await self.service.exchangeTvLogin(
                        code: tvLogin.code,
                        deviceNonce: tvLoginNonce,
                        session: session,
                        config: self.config
                    )
                    self.setSession(exchanged)
                    self.tvLoginStatus = "Signed in. Syncing content..."
                    try await self.syncWithCurrentSession()
                }
            }
        }
    }

    func sync() {
        Task {
            await self.run {
                try await self.ensureHostedEnvironment()
                try await self.syncWithCurrentSession()
            }
        }
    }

    private func syncWithCurrentSession() async throws {
        try await ensureHostedEnvironment()
        _ = try await ensureFreshSession()
        overview = try await retryWithFreshSession {
            try await self.service.syncOverview(session: $0, config: self.config)
        }
        syncedLibrary = try await retryWithFreshSession {
            try await self.service.pullLibrary(profileId: 1, session: $0, config: self.config)
        }
    }

    func freshSessionForExternalSync() async throws -> AuthSession {
        try await ensureFreshSession()
    }

    private func ensureFreshSession() async throws -> AuthSession {
        try await ensureHostedEnvironment()
        guard let session else { throw NuvioServiceError.missingSession }
        guard session.isRefreshable else { return session }
        if let expiresAt = session.expiresAt, expiresAt > Date().addingTimeInterval(120) {
            return session
        }
        let refreshed = try await service.refresh(session: session, config: config)
        setSession(refreshed)
        return refreshed
    }

    private func retryWithFreshSession<T>(_ operation: @escaping (AuthSession) async throws -> T) async throws -> T {
        do {
            return try await operation(try await ensureFreshSession())
        } catch {
            if let serviceError = error as? NuvioServiceError, serviceError.shouldRefreshSession {
                guard let session, session.isRefreshable else { throw error }
                let refreshed = try await service.refresh(session: session, config: config)
                setSession(refreshed)
                return try await operation(refreshed)
            }
            throw error
        }
    }

    private func run(_ operation: @escaping () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func setSession(_ session: AuthSession) {
        self.session = session
        if let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: Keys.session)
        }
    }

    private func loadHostedEnvironmentIfNeeded() async {
        do {
            try await ensureHostedEnvironment()
        } catch {
            if config.anonKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func ensureHostedEnvironment() async throws {
        let hasURL = !config.supabaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAnonKey = !config.anonKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard !hasURL || !hasAnonKey else { return }
        if isLoadingHostedEnvironment {
            while isLoadingHostedEnvironment {
                try await Task.sleep(for: .milliseconds(100))
            }
            if !config.supabaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !config.anonKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return
            }
        }

        isLoadingHostedEnvironment = true
        defer { isLoadingHostedEnvironment = false }

        let hosted = try await hostedEnvironmentService.fetch()
        if !hasURL, let supabaseURL = hosted.supabaseURL, !supabaseURL.isEmpty {
            config.supabaseURL = supabaseURL
        }
        if !hasAnonKey, let anonKey = hosted.anonKey, !anonKey.isEmpty {
            config.anonKey = anonKey
        }
        if let redirectURL = hosted.tvLoginRedirectBaseURL, !redirectURL.isEmpty {
            config.tvLoginRedirectBaseURL = redirectURL
        }
        saveConfig()
    }

    private static func makeNonce() -> String {
        let bytes = (0..<24).map { _ in UInt8.random(in: UInt8.min...UInt8.max) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private enum Keys {
    static let supabaseURL = "auth.supabaseURL"
    static let anonKey = "auth.anonKey"
    static let tvLoginRedirectBaseURL = "auth.tvLoginRedirectBaseURL"
    static let session = "auth.session"
}

struct HostedEnvironmentService {
    func fetch() async throws -> HostedEnvironmentConfig {
        let (data, _) = try await URLSession.shared.data(from: NuvioBackendConfig.hostedEnvironmentURL)
        guard let body = String(data: data, encoding: .utf8) else {
            throw NuvioServiceError.invalidResponse
        }

        return HostedEnvironmentConfig(
            supabaseURL: Self.value(named: "SUPABASE_URL", in: body),
            anonKey: Self.value(named: "SUPABASE_ANON_KEY", in: body),
            tvLoginRedirectBaseURL: Self.value(named: "TV_LOGIN_REDIRECT_BASE_URL", in: body)
        )
    }

    private static func value(named key: String, in body: String) -> String? {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        let pattern = "\"\(escapedKey)\"\\s*:\\s*\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        guard let match = regex.firstMatch(in: body, range: range),
              let valueRange = Range(match.range(at: 1), in: body) else {
            return nil
        }
        return String(body[valueRange])
    }
}
