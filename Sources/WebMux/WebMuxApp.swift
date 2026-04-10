import SwiftUI

@main
struct WebMuxApp: App {
    @State private var store = ServiceStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .task { await FaviconFetcher.fetchAll(store: store) }
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: 1000, height: 700)
    }
}
