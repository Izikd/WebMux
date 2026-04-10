import SwiftUI

struct ContentView: View {
    @Bindable var store: ServiceStore
    @State private var selection: UUID?
    @State private var webViewManager = WebViewManager()
    @State private var showingAddSheet = false

    @State private var draggedService: UUID?

    var body: some View {
        HStack(spacing: 0) {
            // Icon strip sidebar
            VStack(spacing: 4) {
                Spacer().frame(height: 4)

                ForEach(store.services) { service in
                    sidebarIcon(for: service)
                        .onDrag {
                            draggedService = service.id
                            return NSItemProvider(object: service.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: ServiceDropDelegate(
                            service: service,
                            store: store,
                            draggedService: $draggedService
                        ))
                }

                Spacer()

                Button(action: { showingAddSheet = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 8)
            }
            .frame(width: 52)
            .background(.bar)

            Divider()

            // Webview area
            if let id = selection, let service = store.services.first(where: { $0.id == id }) {
                WebViewContainer(webView: webViewManager.webView(for: service))
                    .id(id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddServiceView(store: store)
        }
        .onAppear {
            if selection == nil { selection = store.services.first?.id }
        }
    }

    private func sidebarIcon(for service: Service) -> some View {
        Button(action: { selection = service.id }) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(selection == service.id ? Color.accentColor.opacity(0.2) : Color.clear)
                    .frame(width: 40, height: 40)

                faviconImage(for: service)
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Remove", role: .destructive) {
                webViewManager.removeWebView(for: service.id)
                if selection == service.id {
                    selection = store.services.first(where: { $0.id != service.id })?.id
                }
                store.remove(id: service.id)
            }
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
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
        }
    }
}

struct ServiceDropDelegate: DropDelegate {
    let service: Service
    let store: ServiceStore
    @Binding var draggedService: UUID?

    func performDrop(info: DropInfo) -> Bool {
        draggedService = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedService,
              dragged != service.id,
              let from = store.services.firstIndex(where: { $0.id == dragged }),
              let to = store.services.firstIndex(where: { $0.id == service.id }) else { return }
        withAnimation(.default) {
            store.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
