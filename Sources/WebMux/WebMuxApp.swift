import SwiftUI

@main
struct WebMuxApp: App {
    @State private var store = ServiceStore()
    @State private var showingAbout = false

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .task { await FaviconFetcher.fetchAll(store: store) }
                .sheet(isPresented: $showingAbout) { AboutView() }
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About WebMux") { showingAbout = true }
            }
        }
    }
}
