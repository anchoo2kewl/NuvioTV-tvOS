import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var authStore: AuthStore
    let openDetails: (NuvioCatalogItem) -> Void
    private let heroTimer = Timer.publish(every: 8, on: .main, in: .common).autoconnect()

    var body: some View {
        PageScaffold(
            title: "Nuvio",
            subtitle: "Synced sources and library.",
            backdropURL: homeHero?.backdropURL,
            showsHeader: false
        ) {
            VStack(alignment: .leading, spacing: 38) {
                if let homeHero {
                    HomeHero(
                        item: homeHero,
                        canMove: store.featuredItems.count > 1,
                        openDetails: openDetails
                    )
                }

                if authStore.isSignedIn {
                    HStack(spacing: 18) {
                        Button {
                            syncNuvio()
                        } label: {
                            Label("Sync Nuvio", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)

                        if store.isLoadingSources || authStore.isLoading {
                            ProgressView()
                        }
                    }
                } else if homeHero == nil {
                    InfoPanel(
                        title: "Sign in to Nuvio",
                        message: "Use Account to sign in and sync your library, add-ons, and plugin repositories."
                    )
                }

                if store.installedAddons.isEmpty {
                    InfoPanel(
                        title: "No Nuvio sources installed",
                        message: "Open Add-ons to add a manifest URL, or sign in and sync sources from your Nuvio account."
                    )
                } else if store.contentSources.isEmpty {
                    InfoPanel(
                        title: "No sources can show content",
                        message: "Your installed sources do not expose browsable catalogs. Add or sync a Nuvio source with catalog support."
                    )
                } else if store.homeRows.isEmpty && store.isLoadingSources {
                    ProgressView("Loading catalogs")
                } else {
                    SourcePicker(
                        title: "Browse source",
                        sources: store.contentSources,
                        selection: $store.selectedContentSourceID
                    )

                    ForEach(store.filteredHomeRows) { row in
                        CatalogRowView(row: row, openDetails: openDetails)
                    }
                }

                if authStore.isSignedIn {
                    SyncedLibraryRow(openDetails: openDetails)
                }
            }
        }
        .onChange(of: store.selectedContentSourceID) {
            store.selectedHeroIndex = 0
        }
        .onReceive(heroTimer) { _ in
            guard store.featuredItems.count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.55)) {
                store.showNextFeatured()
            }
        }
    }

    private var homeHero: NuvioCatalogItem? {
        store.heroItem ?? authStore.syncedLibrary.first?.catalogItem
    }

    private func syncNuvio() {
        authStore.sync()
        Task {
            if let session = try? await authStore.freshSessionForExternalSync() {
                store.syncSources(session: session, config: authStore.config)
            }
        }
    }
}

struct SearchView: View {
    @EnvironmentObject private var store: LibraryStore
    let openDetails: (NuvioCatalogItem) -> Void

    var body: some View {
        PageScaffold(title: "Search", subtitle: "Find movies and series.") {
            VStack(alignment: .leading, spacing: 28) {
                if !store.searchSources.isEmpty {
                    SourcePicker(
                        title: "Search source",
                        sources: store.searchSources,
                        selection: $store.selectedSearchSourceID
                    )
                }

                HStack(spacing: 18) {
                    TextField("Search movies or series", text: $store.searchQuery)
                        .nuvioTextField()
                        .onSubmit { store.search() }

                    Button {
                        store.search()
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .frame(maxWidth: 1180)

                if store.isSearching {
                    ProgressView("Searching Nuvio sources")
                }

                if !store.searchResults.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(220), spacing: 28), count: 5), spacing: 34) {
                        ForEach(store.searchResults) { item in
                            CatalogPosterButton(item: item) {
                                openDetails(item)
                            }
                        }
                    }
                } else if !store.isSearching {
                    InfoPanel(
                        title: "Search needs enabled sources",
                        message: store.searchSources.isEmpty ? "Install or sync a Nuvio source with searchable catalogs first." : "Enter a title and search the selected source."
                    )
                }
            }
        }
    }
}

struct AddonsView: View {
    @EnvironmentObject private var store: LibraryStore

    var body: some View {
        PageScaffold(title: "Add-ons", subtitle: "Manage synced source manifests.") {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 18) {
                    TextField("https://addon.example.com/manifest.json", text: $store.addonManifestURL)
                        .nuvioTextField()
                        .keyboardType(.URL)
                        .onSubmit { store.installAddonFromField() }

                    Button {
                        store.installAddonFromField()
                    } label: {
                        Label("Install", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.addonManifestURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .frame(maxWidth: 1240)

                if store.isLoadingSources {
                    ProgressView("Loading Nuvio sources")
                }

                if store.installedAddons.isEmpty {
                    InfoPanel(
                        title: "No add-ons installed",
                        message: "Sign in and sync your Nuvio account, or enter a manifest URL from a source you use."
                    )
                } else {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(store.installedAddons) { addon in
                            AddonPanel(addon: addon)
                        }
                    }
                    .focusSection()
                }
            }
        }
    }
}

struct PluginsView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var authStore: AuthStore

    var body: some View {
        PageScaffold(title: "Plugins", subtitle: "Synced repositories.") {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 18) {
                    Button {
                        Task {
                            if let session = try? await authStore.freshSessionForExternalSync() {
                                store.syncSources(session: session, config: authStore.config)
                            }
                        }
                    } label: {
                        Label("Sync plugins", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!authStore.isSignedIn)

                    if store.isLoadingSources {
                        ProgressView()
                    }
                }

                if store.syncedPlugins.isEmpty {
                    InfoPanel(
                        title: "No plugin repositories synced",
                        message: "Login to Nuvio and sync. This tvOS build lists plugin repos; native JS plugin execution is not enabled yet, so playback uses add-on/direct streams."
                    )
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(store.syncedPlugins) { plugin in
                            PluginPanel(plugin: plugin)
                        }
                    }
                }
            }
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var authStore: AuthStore
    let openDetails: (NuvioCatalogItem) -> Void

    var body: some View {
        PageScaffold(title: "Library", subtitle: "Your Nuvio collection.") {
            VStack(alignment: .leading, spacing: 34) {
                HStack(spacing: 18) {
                    Button {
                        syncNuvio()
                    } label: {
                        Label("Sync now", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!authStore.isSignedIn || authStore.isLoading)

                    if authStore.isLoading || store.isLoadingSources {
                        ProgressView()
                    }
                }

                if authStore.isSignedIn {
                    SyncedLibraryRow(openDetails: openDetails)
                } else {
                    InfoPanel(title: "Sign in required", message: "Open Account to sync your Nuvio library, progress, add-ons, and plugin repositories.")
                }

                DirectStreamPanel()
            }
        }
    }

    private func syncNuvio() {
        authStore.sync()
        Task {
            if let session = try? await authStore.freshSessionForExternalSync() {
                store.syncSources(session: session, config: authStore.config)
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var authStore: AuthStore

    var body: some View {
        PageScaffold(title: "Settings", subtitle: "Backend and sideload configuration.") {
            VStack(alignment: .leading, spacing: 24) {
                TextField("Supabase URL", text: $authStore.config.supabaseURL)
                    .nuvioTextField()
                    .keyboardType(.URL)

                SecureField("Supabase anon key", text: $authStore.config.anonKey)
                    .nuvioTextField()

                TextField("TV login redirect URL", text: $authStore.config.tvLoginRedirectBaseURL)
                    .nuvioTextField()
                    .keyboardType(.URL)

                Button {
                    authStore.saveConfig()
                } label: {
                    Label("Save backend settings", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)

                InfoPanel(
                    title: "Playback support",
                    message: "Apple TV can play direct HTTP/HLS sources. Torrent, magnet, and native JS plugin execution require a resolver/debrid path before AVPlayer can open them."
                )
            }
        }
    }
}

struct DetailView: View {
    @EnvironmentObject private var store: LibraryStore
    let item: NuvioCatalogItem

    var body: some View {
        PageScaffold(title: item.name, subtitle: item.subtitle.isEmpty ? item.addonName : item.subtitle) {
            VStack(alignment: .leading, spacing: 32) {
                HStack(alignment: .top, spacing: 34) {
                    RemotePoster(url: item.posterURL)
                        .frame(width: 250, height: 375)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 20) {
                        Text(item.description ?? "No description returned by this Nuvio source.")
                            .font(.system(size: 25, weight: .regular))
                            .foregroundStyle(.white.opacity(0.74))
                            .lineLimit(7)
                            .frame(maxWidth: 1050, alignment: .leading)

                        Text("Source: \(item.addonName)")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.white.opacity(0.52))

                        HStack(spacing: 16) {
                            Button {
                                Task { await store.resolveStreams(for: item) }
                            } label: {
                                Label("Refresh streams", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.borderedProminent)

                            if store.isResolvingStreams {
                                ProgressView()
                            }
                        }
                    }
                }

                if store.isLoadingDetails {
                    ProgressView("Loading episodes")
                }

                if !store.videos.isEmpty {
                    EpisodePicker(item: item)
                }

                if store.streams.isEmpty && !store.isResolvingStreams {
                    InfoPanel(title: "No streams loaded", message: "No enabled Nuvio add-on returned a stream for this item.")
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        RowHeader(title: "Streams")
                        StreamSourcePicker()
                        ForEach(store.filteredStreams) { stream in
                            StreamButton(stream: stream, item: item)
                        }
                    }
                }
            }
        }
        .onAppear {
            if store.selectedItem != item {
                store.openDetails(item)
            }
        }
    }
}

struct Header: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 48, weight: .medium))
                .lineLimit(2)
            Text(subtitle)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.white.opacity(0.52))
        }
    }
}

private struct CatalogRowView: View {
    let row: NuvioCatalogRow
    let openDetails: (NuvioCatalogItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            RowHeader(title: row.title, subtitle: row.addonName)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(row.items) { item in
                        CatalogPosterButton(item: item) {
                            openDetails(item)
                        }
                    }
                }
                .padding(.vertical, 16)
                .padding(.trailing, 60)
            }
        }
    }
}

private struct HomeHero: View {
    @EnvironmentObject private var store: LibraryStore
    let item: NuvioCatalogItem
    let canMove: Bool
    let openDetails: (NuvioCatalogItem) -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: item.backdropURL) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    LinearGradient(
                        colors: [
                            Color(red: 0.13, green: 0.16, blue: 0.19),
                            Color(red: 0.025, green: 0.028, blue: 0.032)
                        ],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                }
            }
            .frame(maxWidth: .infinity, minHeight: 720, maxHeight: 720)
            .clipped()

            LinearGradient(
                colors: [.black.opacity(0.0), .black.opacity(0.28), .black.opacity(0.96)],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                colors: [.black.opacity(0.88), .black.opacity(0.50), .black.opacity(0.06), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )

            LinearGradient(
                colors: [.black.opacity(0.74), .black.opacity(0.18), .clear],
                startPoint: .top,
                endPoint: .center
            )

            LinearGradient(
                colors: [.clear, .black.opacity(0.20), .black.opacity(0.58)],
                startPoint: .center,
                endPoint: .trailing
            )

            VStack {
                HStack(spacing: 12) {
                    Image("app_logo_mark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 34, height: 34)
                        .opacity(0.88)

                    Text("Nuvio")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))

                    Text(item.addonName)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white.opacity(0.58))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.white.opacity(0.07), in: Capsule())
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 150)
                .padding(.top, 44)

                Spacer()
            }

            HStack(alignment: .bottom, spacing: 34) {
                RemotePoster(url: item.posterURL)
                    .frame(width: 180, height: 270)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white.opacity(0.16), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.55), radius: 24, x: 0, y: 14)

                VStack(alignment: .leading, spacing: 17) {
                    Text(item.name)
                        .font(.system(size: 58, weight: .medium))
                        .lineLimit(2)
                        .frame(maxWidth: 980, alignment: .leading)

                    if !heroBadges.isEmpty {
                        HStack(spacing: 10) {
                            ForEach(heroBadges, id: \.self) { badge in
                                HeroBadge(title: badge)
                            }
                        }
                    }

                    Text(item.description ?? "Open details to resolve streams from your Nuvio sources.")
                        .font(.system(size: 25, weight: .regular))
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(3)
                        .frame(maxWidth: 940, alignment: .leading)

                    HStack(spacing: 16) {
                        if canMove {
                            Button {
                                store.showPreviousFeatured()
                            } label: {
                                Label("Previous", systemImage: "chevron.left")
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(GlassIconButtonStyle())
                        }

                        Button {
                            openDetails(item)
                        } label: {
                            Label("View Details", systemImage: "play.circle.fill")
                        }
                        .buttonStyle(HeroPrimaryButtonStyle())

                        if canMove {
                            Button {
                                store.showNextFeatured()
                            } label: {
                                Label("Next", systemImage: "chevron.right")
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(GlassIconButtonStyle())
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 150)
            .padding(.bottom, 56)

            if canMove {
                HStack(spacing: 8) {
                    ForEach(store.featuredItems.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == store.selectedHeroIndex ? .white : .white.opacity(0.36))
                            .frame(width: index == store.selectedHeroIndex ? 34 : 10, height: 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 42)
                .padding(.bottom, 58)
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .padding(.horizontal, -160)
        .padding(.top, -72)
    }

    private var heroBadges: [String] {
        [item.releaseInfo, item.imdbRating.map { "IMDb \($0)" }, item.genres?.prefix(3).joined(separator: " / ")]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
    }
}

private struct HeroBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(.white.opacity(0.78))
            .lineLimit(1)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(.white.opacity(0.070), in: Capsule())
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            )
    }
}

private struct SyncedLibraryRow: View {
    @EnvironmentObject private var authStore: AuthStore
    let openDetails: (NuvioCatalogItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            RowHeader(title: "Synced Library")

            if authStore.syncedLibrary.isEmpty {
                InfoPanel(title: "No synced items loaded", message: "Use Sync now from Library or Account to pull your Nuvio content.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 24) {
                        ForEach(authStore.syncedLibrary.prefix(50)) { item in
                            CatalogPosterButton(item: item.catalogItem) {
                                openDetails(item.catalogItem)
                            }
                        }
                    }
                    .padding(.vertical, 16)
                    .padding(.trailing, 60)
                }
            }
        }
    }
}

private struct CatalogPosterButton: View {
    let item: NuvioCatalogItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .bottomLeading) {
                    RemotePoster(url: item.posterURL)
                        .frame(width: 210, height: 315)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.72)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.74))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 6))
                            .padding(10)
                    }
                }

                Text(item.name)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(2)
                    .frame(width: 210, alignment: .leading)
            }
        }
        .buttonStyle(PosterButtonStyle())
    }
}

private struct SourcePicker: View {
    let title: String
    let sources: [NuvioAddon]
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.white.opacity(0.54))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    SourceChip(title: "All Sources", isSelected: selection == SourceSelection.all) {
                        selection = SourceSelection.all
                    }

                    ForEach(sources) { source in
                        SourceChip(title: source.displayName, isSelected: selection == source.baseURL) {
                            selection = source.baseURL
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
}

private struct StreamSourcePicker: View {
    @EnvironmentObject private var store: LibraryStore

    var body: some View {
        if !store.streamSourceNames.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Play source")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white.opacity(0.54))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        SourceChip(title: "All Streams", isSelected: store.selectedStreamSourceName == SourceSelection.all) {
                            store.selectedStreamSourceName = SourceSelection.all
                        }

                        ForEach(store.streamSourceNames, id: \.self) { sourceName in
                            SourceChip(title: sourceName, isSelected: store.selectedStreamSourceName == sourceName) {
                                store.selectedStreamSourceName = sourceName
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

private struct SourceChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 19, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .buttonStyle(SourceChipButtonStyle(isSelected: isSelected))
    }
}

private struct AddonPanel: View {
    @EnvironmentObject private var store: LibraryStore
    let addon: NuvioAddon

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 22) {
                RemotePoster(url: addon.logo.flatMap(URL.init(string:)))
                    .frame(width: 90, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 8) {
                    Text(addon.displayName)
                        .font(.system(size: 25, weight: .medium))
                    Text(addon.description ?? addon.baseURL)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.60))
                        .lineLimit(2)
                    Text("\(addon.catalogs.count) catalogs - \(addon.resources.count) resources - \(addon.enabled ? "Enabled" : "Disabled")")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.48))
                    Text(addon.manifestURL)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }

                Spacer()
            }

            HStack(spacing: 14) {
                Button {
                    store.toggleAddon(addon)
                } label: {
                    Label(addon.enabled ? "Disable" : "Enable", systemImage: addon.enabled ? "pause.fill" : "play.fill")
                }
                .buttonStyle(AddonActionButtonStyle(tint: addon.enabled ? .orange : .green))

                Button {
                    store.editAddon(addon)
                } label: {
                    Label("Edit URL", systemImage: "pencil")
                }
                .buttonStyle(AddonActionButtonStyle(tint: .cyan))

                Button {
                    store.reloadAddon(addon)
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .buttonStyle(AddonActionButtonStyle(tint: .cyan))

                Button {
                    store.removeAddon(addon)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .buttonStyle(AddonActionButtonStyle(tint: .red, isDestructive: true))
            }
        }
        .frame(maxWidth: 1180, alignment: .leading)
        .padding(.vertical, 22)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
    }
}

private struct EpisodePicker: View {
    @EnvironmentObject private var store: LibraryStore
    let item: NuvioCatalogItem

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RowHeader(title: "Episodes")

            if store.seasonNumbers.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(store.seasonNumbers, id: \.self) { season in
                            SourceChip(title: "Season \(season)", isSelected: store.selectedSeason == season) {
                                store.selectSeason(season, for: item)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(store.filteredVideos) { video in
                        EpisodeCard(video: video, isSelected: store.selectedVideoID == video.id) {
                            store.selectVideo(video, for: item)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
}

private struct EpisodeCard: View {
    let video: NuvioVideo
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .bottomLeading) {
                    RemotePoster(url: video.thumbnail.flatMap(URL.init(string:)))
                        .frame(width: 310, height: 174)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    if let episodeNumber = video.episode {
                        Text("E\(episodeNumber)")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.72), in: Capsule())
                            .padding(10)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(video.title)
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(2)

                    if let description = video.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.50))
                            .lineLimit(2)
                    }
                }
                .frame(width: 310, alignment: .leading)
            }
        }
        .buttonStyle(EpisodeCardButtonStyle(isSelected: isSelected))
    }
}

private struct PluginPanel: View {
    let plugin: NuvioPluginRepo

    var body: some View {
        HStack(spacing: 22) {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.system(size: 42, weight: .semibold))
                .frame(width: 86, height: 86)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 8) {
                Text(plugin.name ?? plugin.url)
                    .font(.system(size: 25, weight: .medium))
                    .lineLimit(1)
                Text(plugin.url)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.60))
                    .lineLimit(2)
                Text("\(plugin.repoType ?? "repository") - \(plugin.enabled ? "Enabled" : "Disabled")")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.48))
            }
        }
        .padding(24)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct StreamButton: View {
    @EnvironmentObject private var store: LibraryStore
    let stream: NuvioStream
    let item: NuvioCatalogItem

    var body: some View {
        Button {
            store.play(stream, for: item)
        } label: {
            HStack(spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(stream.isPlayableOnTV ? Color.cyan.opacity(0.14) : Color.yellow.opacity(0.14))
                    Image(systemName: stream.isPlayableOnTV ? "play.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(stream.isPlayableOnTV ? Color.cyan.opacity(0.92) : Color.yellow.opacity(0.92))
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 6) {
                    Text(stream.displayTitle)
                        .font(.system(size: 22, weight: .medium))
                        .lineLimit(2)
                    Text(stream.isPlayableOnTV ? stream.addonName : "\(stream.addonName) - no direct playable URL")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(1)
                    if !stream.metadataBadges.isEmpty {
                        HStack(spacing: 10) {
                            ForEach(stream.metadataBadges, id: \.self) { badge in
                                Text(badge)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.78))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(streamBadgeTint(for: badge), in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                    if let filename = stream.filename, !filename.isEmpty {
                        Text(filename)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.52))
                            .lineLimit(1)
                    }
                }
                Spacer()

                Image(systemName: stream.preferredPlaybackEngine == .vlc ? "play.rectangle.on.rectangle.fill" : "appletv.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
            }
            .frame(maxWidth: 1180, alignment: .leading)
        }
        .buttonStyle(MediaPanelButtonStyle())
    }

    private func streamBadgeTint(for badge: String) -> Color {
        let lowercased = badge.lowercased()
        if lowercased.contains("dolby") || lowercased.contains("hdr") || lowercased.contains("4k") || lowercased.contains("2160") {
            return Color.cyan.opacity(0.16)
        }
        if lowercased.contains("size") {
            return Color.indigo.opacity(0.18)
        }
        if lowercased.contains("seed") {
            return Color.green.opacity(0.16)
        }
        if lowercased.contains("need") || lowercased.contains("no direct") {
            return Color.yellow.opacity(0.14)
        }
        return Color.white.opacity(0.10)
    }
}

private struct DirectStreamPanel: View {
    @EnvironmentObject private var store: LibraryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            RowHeader(title: "Direct Stream")

            HStack(spacing: 18) {
                TextField("https://example.com/master.m3u8", text: $store.directStreamURL)
                    .nuvioTextField()
                    .keyboardType(.URL)

                Button {
                    store.playDirectStream()
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: 1180)
        }
    }
}

private struct RowHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title)
                .font(.system(size: 27, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.white.opacity(0.44))
                    .lineLimit(1)
            }
        }
    }
}

private struct RemotePoster: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.13, green: 0.15, blue: 0.17),
                            Color(red: 0.03, green: 0.04, blue: 0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image("app_logo_mark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64)
                        .opacity(0.55)
                }
            }
        }
        .clipped()
    }
}

private struct PageScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    let backdropURL: URL?
    let showsHeader: Bool
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String,
        backdropURL: URL? = nil,
        showsHeader: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.backdropURL = backdropURL
        self.showsHeader = showsHeader
        self.content = content()
    }

    var body: some View {
        ZStack {
            BackdropLayer(url: backdropURL)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 38) {
                    if showsHeader {
                        Header(title: title, subtitle: subtitle)
                    }
                    content

                    if let errorMessage = currentError {
                        Text(errorMessage)
                            .font(.headline)
                            .foregroundStyle(.red)
                            .frame(maxWidth: 1180, alignment: .leading)
                    }
                }
                .padding(.horizontal, 82)
                .padding(.top, showsHeader ? 70 : 0)
                .padding(.bottom, 90)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var authStore: AuthStore

    private var currentError: String? {
        store.errorMessage ?? authStore.errorMessage
    }
}

private struct BackdropLayer: View {
    let url: URL?

    var body: some View {
        ZStack {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                        .opacity(0.34)
                default:
                    LinearGradient(
                        colors: [
                            Color(red: 0.035, green: 0.04, blue: 0.048),
                            Color(red: 0.075, green: 0.085, blue: 0.10),
                            .black
                        ],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                }
            }
            .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.82), .black.opacity(0.68), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [.clear, Color.cyan.opacity(0.035), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}

private struct InfoPanel: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 25, weight: .medium))
            Text(message)
                .font(.body)
                .foregroundStyle(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 980, alignment: .leading)
        .padding(.vertical, 18)
        .padding(.horizontal, 2)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(Color.cyan.opacity(0.30))
                .frame(width: 4)
                .padding(.vertical, 10)
                .offset(x: -16)
        }
    }
}

private struct PosterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FocusedPosterButton(label: configuration.label, isPressed: configuration.isPressed)
    }

    private struct FocusedPosterButton<Label: View>: View {
        @Environment(\.isFocused) private var isFocused
        let label: Label
        let isPressed: Bool

        var body: some View {
            label
                .foregroundStyle(.white)
                .overlay(alignment: .bottomLeading) {
                    Capsule()
                        .fill(isFocused ? Color.cyan.opacity(0.90) : .clear)
                        .frame(width: 64, height: 4)
                        .offset(y: 12)
                }
                .shadow(color: isFocused ? Color.cyan.opacity(0.18) : .clear, radius: 20, x: 0, y: 0)
                .shadow(color: isFocused ? .black.opacity(0.50) : .clear, radius: 16, x: 0, y: 10)
                .scaleEffect(isPressed ? 0.98 : (isFocused ? 1.035 : 1))
                .animation(.easeOut(duration: 0.14), value: isFocused)
        }
    }
}

private struct EpisodeCardButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        FocusedEpisodeCard(label: configuration.label, isPressed: configuration.isPressed, isSelected: isSelected)
    }

    private struct FocusedEpisodeCard<Label: View>: View {
        @Environment(\.isFocused) private var isFocused
        let label: Label
        let isPressed: Bool
        let isSelected: Bool

        var body: some View {
            label
                .padding(8)
                .background(.white.opacity(isSelected ? 0.055 : 0.0), in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .bottomLeading) {
                    Capsule()
                        .fill(isFocused ? Color.cyan.opacity(0.86) : (isSelected ? .white.opacity(0.28) : .clear))
                        .frame(width: 58, height: isFocused ? 4 : 2)
                        .offset(x: 8, y: 6)
                }
                .shadow(color: isFocused ? Color.cyan.opacity(0.16) : .clear, radius: 18, x: 0, y: 0)
                .scaleEffect(isPressed ? 0.98 : (isFocused ? 1.026 : 1))
                .animation(.easeOut(duration: 0.14), value: isFocused)
        }
    }
}

private struct MediaPanelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FocusedMediaPanel(label: configuration.label, isPressed: configuration.isPressed)
    }

    private struct FocusedMediaPanel<Label: View>: View {
        @Environment(\.isFocused) private var isFocused
        let label: Label
        let isPressed: Bool

        var body: some View {
            label
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
                .background(.white.opacity(isPressed || isFocused ? 0.105 : 0.030), in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(isFocused ? Color.cyan.opacity(0.86) : .clear)
                        .frame(width: 4)
                        .padding(.vertical, 18)
                }
                .shadow(color: isFocused ? Color.cyan.opacity(0.16) : .clear, radius: 18, x: 0, y: 0)
                .scaleEffect(isPressed ? 0.99 : (isFocused ? 1.012 : 1))
                .animation(.easeOut(duration: 0.14), value: isFocused)
        }
    }
}

private struct SourceChipButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        FocusedSourceChip(label: configuration.label, isPressed: configuration.isPressed, isSelected: isSelected)
    }

    private struct FocusedSourceChip<Label: View>: View {
        @Environment(\.isFocused) private var isFocused
        let label: Label
        let isPressed: Bool
        let isSelected: Bool

        var body: some View {
            label
                .foregroundStyle(isSelected || isFocused ? .black : .white.opacity(0.82))
                .background {
                    Capsule()
                        .fill(isSelected || isFocused ? Color.cyan.opacity(0.92) : .white.opacity(0.050))
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .overlay {
                    Capsule()
                        .stroke(isFocused ? Color.white.opacity(0.72) : .white.opacity(0.08), lineWidth: isFocused ? 2 : 1)
                }
                .shadow(color: isFocused ? Color.cyan.opacity(0.18) : .clear, radius: 16, x: 0, y: 0)
                .scaleEffect(isPressed ? 0.98 : (isFocused ? 1.025 : 1))
                .animation(.easeOut(duration: 0.14), value: isFocused)
        }
    }
}

private struct AddonActionButtonStyle: ButtonStyle {
    let tint: Color
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        FocusedAddonAction(label: configuration.label, isPressed: configuration.isPressed, tint: tint, isDestructive: isDestructive)
    }

    private struct FocusedAddonAction<Label: View>: View {
        @Environment(\.isFocused) private var isFocused
        let label: Label
        let isPressed: Bool
        let tint: Color
        let isDestructive: Bool

        var body: some View {
            label
                .font(.callout.weight(.medium))
                .foregroundStyle(isFocused ? .black : (isDestructive ? Color(red: 1.0, green: 0.56, blue: 0.56) : .white.opacity(0.82)))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background {
                    Capsule()
                        .fill(isFocused ? tint.opacity(0.92) : tint.opacity(isDestructive ? 0.16 : 0.10))
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .overlay {
                    Capsule()
                        .stroke(isFocused ? .white.opacity(0.70) : tint.opacity(isDestructive ? 0.36 : 0.20), lineWidth: isFocused ? 2 : 1)
                }
                .shadow(color: isFocused ? tint.opacity(0.20) : .clear, radius: 16, x: 0, y: 0)
                .scaleEffect(isPressed ? 0.97 : (isFocused ? 1.025 : 1))
                .animation(.easeOut(duration: 0.14), value: isFocused)
        }
    }
}

private struct HeroPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FocusedHeroPrimary(label: configuration.label, isPressed: configuration.isPressed)
    }

    private struct FocusedHeroPrimary<Label: View>: View {
        @Environment(\.isFocused) private var isFocused
        let label: Label
        let isPressed: Bool

        var body: some View {
            label
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(isFocused ? .black : .white.opacity(0.88))
                .padding(.horizontal, 28)
                .padding(.vertical, 15)
                .background {
                    Capsule()
                        .fill(isFocused ? Color.cyan.opacity(0.94) : .white.opacity(0.12))
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .overlay {
                    Capsule()
                        .stroke(isFocused ? .white.opacity(0.74) : .white.opacity(0.12), lineWidth: isFocused ? 2 : 1)
                }
                .shadow(color: isFocused ? Color.cyan.opacity(0.24) : .black.opacity(0.24), radius: isFocused ? 22 : 10, x: 0, y: isFocused ? 0 : 8)
                .scaleEffect(isPressed ? 0.97 : (isFocused ? 1.025 : 1))
                .animation(.easeOut(duration: 0.14), value: isFocused)
        }
    }
}

private struct GlassIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FocusedGlassIcon(label: configuration.label, isPressed: configuration.isPressed)
    }

    private struct FocusedGlassIcon<Label: View>: View {
        @Environment(\.isFocused) private var isFocused
        let label: Label
        let isPressed: Bool

        var body: some View {
            label
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(isFocused ? .black : .white.opacity(0.82))
                .frame(width: 52, height: 52)
                .background(isFocused ? Color.cyan.opacity(0.94) : .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isFocused ? Color.white.opacity(0.78) : .white.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: isFocused ? Color.cyan.opacity(0.20) : .clear, radius: 18, x: 0, y: 0)
                .scaleEffect(isPressed ? 0.96 : (isFocused ? 1.04 : 1))
                .animation(.easeOut(duration: 0.14), value: isFocused)
        }
    }
}

extension View {
    func nuvioTextField() -> some View {
        self
            .textFieldStyle(.plain)
            .font(.system(size: 23, weight: .regular))
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            )
    }
}

private extension SyncedLibraryItem {
    var catalogItem: NuvioCatalogItem {
        NuvioCatalogItem(
            id: contentId,
            type: contentType,
            name: name.isEmpty ? contentId : name,
            poster: poster,
            background: background,
            logo: nil,
            description: description,
            releaseInfo: releaseInfo,
            imdbRating: imdbRating.map { "\($0)" },
            genres: genres,
            runtime: nil,
            addonBaseURL: addonBaseURL ?? "",
            addonName: "Nuvio Library"
        )
    }
}
