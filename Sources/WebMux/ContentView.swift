import SwiftUI

struct ContentView: View {
    @Bindable var store: ServiceStore
    @State private var selection: UUID?
    @State private var webViewManager = WebViewManager()
    @State private var showingAddSheet = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(store.services) { service in
                    Label {
                        Text(service.name)
                    } icon: {
                        faviconImage(for: service)
                            .frame(width: 20, height: 20)
                    }
                    .tag(service.id)
                    .contextMenu {
                        Button("Remove", role: .destructive) {
                            webViewManager.removeWebView(for: service.id)
                            if selection == service.id { selection = nil }
                            store.remove(id: service.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 160)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: { showingAddSheet = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddServiceView(store: store)
            }
        } detail: {
            if let id = selection, let service = store.services.first(where: { $0.id == id }) {
                WebViewContainer(webView: webViewManager.webView(for: service))
                    .id(id)
            } else {
                Text("Select a service")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if selection == nil { selection = store.services.first?.id }
        }
    }

    @ViewBuilder
    private func faviconImage(for service: Service) -> some View {
        if let path = service.faviconPath, let nsImage = NSImage(contentsOfFile: path) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "globe")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}
