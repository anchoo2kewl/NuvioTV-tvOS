import SwiftUI

@main
struct NuvioTVApp: App {
    @StateObject private var store = LibraryStore()
    @StateObject private var authStore = AuthStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(authStore)
        }
    }
}
