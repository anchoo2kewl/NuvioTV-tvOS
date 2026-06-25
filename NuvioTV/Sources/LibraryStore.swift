import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    @Published var directStreamURL: String {
        didSet { defaults.set(directStreamURL, forKey: Keys.directStreamURL) }
    }

    @Published var addonManifestURL: String {
        didSet { defaults.set(addonManifestURL, forKey: Keys.addonManifestURL) }
    }

    @Published var selectedSource: MediaSource?
    @Published var errorMessage: String?
    @Published var installedAddons: [NuvioAddon] = []
    @Published var syncedPlugins: [NuvioPluginRepo] = []
    @Published var searchQuery: String = ""
    @Published var searchResults: [NuvioCatalogItem] = []
    @Published var homeRows: [NuvioCatalogRow] = []
    @Published var streams: [NuvioStream] = []
    @Published var videos: [NuvioVideo] = []
    @Published var selectedItem: NuvioCatalogItem?
    @Published var selectedVideoID: String?
    @Published var selectedContentSourceID: String = SourceSelection.all
    @Published var selectedSearchSourceID: String = SourceSelection.all
    @Published var selectedStreamSourceName: String = SourceSelection.all
    @Published var selectedHeroIndex = 0
    @Published var isLoadingSources = false
    @Published var isSearching = false
    @Published var isLoadingDetails = false
    @Published var isResolvingStreams = false

    let featuredSources: [MediaSource] = [
        MediaSource(
            title: "Apple HLS sample",
            subtitle: "Network playback smoke test",
            url: URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8")!,
            playbackEngine: .native
        )
    ]

    private let defaults: UserDefaults
    private let sourceService = NuvioSourceService()
    private let supabaseService = SupabaseService()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.directStreamURL = defaults.string(forKey: Keys.directStreamURL) ?? ""
        self.addonManifestURL = defaults.string(forKey: Keys.addonManifestURL) ?? ""
        self.installedAddons = Self.decode([NuvioAddon].self, from: defaults.data(forKey: Keys.installedAddons)) ?? []
        self.syncedPlugins = Self.decode([NuvioPluginRepo].self, from: defaults.data(forKey: Keys.syncedPlugins)) ?? []
    }

    func playDirectStream() {
        do {
            selectedSource = try URLValidator.mediaSource(from: directStreamURL, title: "Direct stream")
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func open(_ source: MediaSource) {
        selectedSource = source
        errorMessage = nil
    }

    func closePlayer() {
        selectedSource = nil
    }

    func installAddonFromField() {
        let url = addonManifestURL
        Task { await installAddon(url: url) }
    }

    func editAddon(_ addon: NuvioAddon) {
        addonManifestURL = addon.manifestURL
    }

    func reloadAddon(_ addon: NuvioAddon) {
        Task { await installAddon(url: addon.manifestURL, userName: addon.userName, enabled: addon.enabled) }
    }

    func installAddon(url: String, userName: String? = nil, enabled: Bool = true) async {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isLoadingSources = true
        defer { isLoadingSources = false }

        do {
            var addon = try await sourceService.fetchAddon(from: trimmed)
            addon.enabled = enabled
            addon.userName = userName
            upsertAddon(addon)
            addonManifestURL = ""
            errorMessage = nil
            await loadHomeCatalogs()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeAddon(_ addon: NuvioAddon) {
        installedAddons.removeAll { $0.baseURL == addon.baseURL }
        if selectedContentSourceID == addon.baseURL { selectedContentSourceID = SourceSelection.all }
        if selectedSearchSourceID == addon.baseURL { selectedSearchSourceID = SourceSelection.all }
        persistAddons()
        Task { await loadHomeCatalogs() }
    }

    func toggleAddon(_ addon: NuvioAddon) {
        guard let index = installedAddons.firstIndex(where: { $0.baseURL == addon.baseURL }) else { return }
        installedAddons[index].enabled.toggle()
        persistAddons()
        Task { await loadHomeCatalogs() }
    }

    func syncSources(session: AuthSession?, config: NuvioBackendConfig) {
        guard let session else { return }
        Task {
            await syncSources(profileId: 1, session: session, config: config)
        }
    }

    func syncSources(profileId: Int, session: AuthSession, config: NuvioBackendConfig) async {
        isLoadingSources = true
        defer { isLoadingSources = false }

        do {
            let addonRows = try await supabaseService.pullAddonRows(profileId: profileId, session: session, config: config)
            for row in addonRows {
                await installAddon(url: row.url, userName: row.name, enabled: row.enabled ?? true)
            }

            let pluginRows = try await supabaseService.pullPluginRows(profileId: profileId, session: session, config: config)
            syncedPlugins = pluginRows.map {
                NuvioPluginRepo(url: $0.url, name: $0.name, enabled: $0.enabled ?? true, repoType: $0.repoType)
            }
            persistPlugins()
            errorMessage = nil
        } catch {
            errorMessage = "Nuvio source sync failed: \(error.localizedDescription)"
        }
    }

    func loadHomeCatalogs() async {
        let contentAddons = installedAddons.filter { $0.canShowContent && $0.supportsCatalogResource }
        guard !contentAddons.isEmpty else {
            homeRows = []
            return
        }

        isLoadingSources = true
        defer { isLoadingSources = false }
        var rows: [NuvioCatalogRow] = []

        for addon in contentAddons {
            let catalogs = addon.contentCatalogs.prefix(5)
            for catalog in catalogs {
                do {
                    let items = try await sourceService.fetchCatalog(addon: addon, catalog: catalog, search: nil, skip: 0)
                    if !items.isEmpty {
                        rows.append(
                            NuvioCatalogRow(
                                id: "\(addon.id)-\(catalog.type)-\(catalog.id)",
                                title: catalog.name,
                                addonName: addon.displayName,
                                addonBaseURL: addon.baseURL,
                                items: Array(items.prefix(20))
                            )
                        )
                    }
                } catch {
                    continue
                }
            }
        }

        homeRows = rows
        if selectedHeroIndex >= featuredItems.count {
            selectedHeroIndex = 0
        }
    }

    func search() {
        Task { await runSearch() }
    }

    func runSearch() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        isSearching = true
        defer { isSearching = false }
        var results: [NuvioCatalogItem] = []

        for addon in searchAddons {
            for catalog in addon.searchableCatalogs {
                do {
                    let items = try await sourceService.fetchCatalog(addon: addon, catalog: catalog, search: query)
                    results.append(contentsOf: items)
                } catch {
                    continue
                }
            }
        }

        var seen = Set<String>()
        searchResults = results.filter { item in
            let key = "\(item.type):\(item.id)"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
        errorMessage = searchResults.isEmpty ? "No Nuvio source returned results for \(query)." : nil
    }

    func openDetails(_ item: NuvioCatalogItem) {
        selectedItem = item
        streams = []
        videos = []
        selectedVideoID = nil
        selectedStreamSourceName = SourceSelection.all
        Task {
            await loadDetails(for: item)
            await resolveStreams(for: item)
        }
    }

    func selectVideo(_ video: NuvioVideo, for item: NuvioCatalogItem) {
        selectedVideoID = video.id
        Task { await resolveStreams(for: item) }
    }

    func loadDetails(for item: NuvioCatalogItem) async {
        guard item.type.caseInsensitiveCompare("series") == .orderedSame else { return }
        guard let addon = metaAddon(for: item) else { return }

        isLoadingDetails = true
        defer { isLoadingDetails = false }

        do {
            let meta = try await sourceService.fetchMeta(addon: addon, item: item)
            videos = meta.videos
            if selectedVideoID == nil {
                selectedVideoID = meta.videos.first?.id
            }
        } catch {
            videos = []
        }
    }

    func resolveStreams(for item: NuvioCatalogItem) async {
        isResolvingStreams = true
        defer { isResolvingStreams = false }
        var resolved: [NuvioStream] = []
        let targetID = streamTargetID(for: item)

        for addon in installedAddons where addon.supportsStreams(type: item.type, id: targetID) {
            do {
                resolved.append(contentsOf: try await sourceService.fetchStreams(addon: addon, type: item.type, id: targetID))
            } catch {
                continue
            }
        }

        streams = resolved
        if selectedStreamSourceName != SourceSelection.all && !streamSourceNames.contains(selectedStreamSourceName) {
            selectedStreamSourceName = SourceSelection.all
        }
        if resolved.isEmpty {
            let episodeText = item.type.caseInsensitiveCompare("series") == .orderedSame && selectedVideoID == nil ? " Select an episode if the source requires one." : ""
            errorMessage = "No streams were returned by your enabled Nuvio add-ons for \(item.name).\(episodeText)"
        } else {
            errorMessage = nil
        }
    }

    func play(_ stream: NuvioStream, for item: NuvioCatalogItem) {
        guard let url = stream.playableURL, stream.isPlayableOnTV else {
            errorMessage = "This stream is not directly playable on Apple TV. Choose an HTTP/HLS source or a debrid/direct source."
            return
        }
        selectedSource = MediaSource(
            title: item.name,
            subtitle: "\(stream.addonName) - \(stream.displayTitle)",
            url: url,
            playbackEngine: stream.preferredPlaybackEngine
        )
        errorMessage = nil
    }

    private func upsertAddon(_ addon: NuvioAddon) {
        installedAddons.removeAll { $0.baseURL.normalizedAddonBaseURL() == addon.baseURL.normalizedAddonBaseURL() }
        installedAddons.append(addon)
        persistAddons()
    }

    var contentSources: [NuvioAddon] {
        installedAddons.filter { $0.canShowContent && $0.supportsCatalogResource }
    }

    var searchSources: [NuvioAddon] {
        installedAddons.filter(\.canSearchContent)
    }

    var filteredHomeRows: [NuvioCatalogRow] {
        guard selectedContentSourceID != SourceSelection.all else { return homeRows }
        return homeRows.filter { $0.addonBaseURL == selectedContentSourceID }
    }

    var heroItem: NuvioCatalogItem? {
        featuredItem ?? filteredHomeRows.first?.items.first ?? homeRows.first?.items.first
    }

    var featuredItems: [NuvioCatalogItem] {
        var seen = Set<String>()
        let rows = filteredHomeRows.isEmpty ? homeRows : filteredHomeRows
        return rows
            .flatMap(\.items)
            .filter { item in
                let key = "\(item.type):\(item.id)"
                if seen.contains(key) { return false }
                seen.insert(key)
                return true
            }
            .prefix(12)
            .map { $0 }
    }

    var featuredItem: NuvioCatalogItem? {
        guard !featuredItems.isEmpty else { return nil }
        return featuredItems[min(selectedHeroIndex, featuredItems.count - 1)]
    }

    func showPreviousFeatured() {
        guard !featuredItems.isEmpty else { return }
        selectedHeroIndex = selectedHeroIndex == 0 ? featuredItems.count - 1 : selectedHeroIndex - 1
    }

    func showNextFeatured() {
        guard !featuredItems.isEmpty else { return }
        selectedHeroIndex = (selectedHeroIndex + 1) % featuredItems.count
    }

    var searchAddons: [NuvioAddon] {
        guard selectedSearchSourceID != SourceSelection.all else { return searchSources }
        return searchSources.filter { $0.baseURL == selectedSearchSourceID }
    }

    var streamSourceNames: [String] {
        Array(Set(streams.map(\.addonName))).sorted()
    }

    var filteredStreams: [NuvioStream] {
        guard selectedStreamSourceName != SourceSelection.all else { return streams }
        return streams.filter { $0.addonName == selectedStreamSourceName }
    }

    private func metaAddon(for item: NuvioCatalogItem) -> NuvioAddon? {
        if let sourceAddon = installedAddons.first(where: { $0.baseURL == item.addonBaseURL && $0.supportsMeta(type: item.type) }) {
            return sourceAddon
        }
        return installedAddons.first { addon in
            addon.supportsMeta(type: item.type) &&
            (addon.idPrefixes.isEmpty || addon.idPrefixes.contains { item.id.hasPrefix($0) })
        }
    }

    private func streamTargetID(for item: NuvioCatalogItem) -> String {
        guard item.type.caseInsensitiveCompare("series") == .orderedSame else {
            return item.id
        }
        return selectedVideoID ?? videos.first?.id ?? item.id
    }

    private func persistAddons() {
        defaults.set(Self.encode(installedAddons), forKey: Keys.installedAddons)
    }

    private func persistPlugins() {
        defaults.set(Self.encode(syncedPlugins), forKey: Keys.syncedPlugins)
    }

    private static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

private enum Keys {
    static let directStreamURL = "directStreamURL"
    static let addonManifestURL = "addonManifestURL"
    static let installedAddons = "installedAddons"
    static let syncedPlugins = "syncedPlugins"
}

struct NuvioCatalogRow: Identifiable, Hashable {
    let id: String
    let title: String
    let addonName: String
    let addonBaseURL: String
    let items: [NuvioCatalogItem]
}

enum SourceSelection {
    static let all = "all"
}
