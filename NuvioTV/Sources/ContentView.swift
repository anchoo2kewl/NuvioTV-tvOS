import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var authStore: AuthStore
    @State private var selection: NavigationSection = .home
    @State private var detailItem: NuvioCatalogItem?

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                HomeView(openDetails: openDetails)
                    .tabItem { Label("Home", systemImage: NavigationSection.home.systemImage) }
                    .tag(NavigationSection.home)

                SearchView(openDetails: openDetails)
                    .tabItem { Label("Search", systemImage: NavigationSection.search.systemImage) }
                    .tag(NavigationSection.search)

                LibraryView(openDetails: openDetails)
                    .tabItem { Label("Library", systemImage: NavigationSection.library.systemImage) }
                    .tag(NavigationSection.library)

                AddonsView()
                    .tabItem { Label("Add-ons", systemImage: NavigationSection.addons.systemImage) }
                    .tag(NavigationSection.addons)

                PluginsView()
                    .tabItem { Label("Plugins", systemImage: NavigationSection.plugins.systemImage) }
                    .tag(NavigationSection.plugins)

                AccountView()
                    .tabItem { Label("Account", systemImage: NavigationSection.account.systemImage) }
                    .tag(NavigationSection.account)

                SettingsView()
                    .tabItem { Label("Settings", systemImage: NavigationSection.settings.systemImage) }
                    .tag(NavigationSection.settings)
            }
            .navigationDestination(item: $detailItem) { item in
                DetailView(item: item)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await store.loadHomeCatalogs()
            if authStore.isSignedIn {
                authStore.sync()
                if let session = try? await authStore.freshSessionForExternalSync() {
                    store.syncSources(session: session, config: authStore.config)
                }
            }
        }
        .onChange(of: authStore.session) { _, session in
            store.syncSources(session: session, config: authStore.config)
        }
        .fullScreenCover(item: $store.selectedSource) { source in
            PlayerView(source: source)
        }
    }

    private func openDetails(_ item: NuvioCatalogItem) {
        store.openDetails(item)
        detailItem = item
    }
}
