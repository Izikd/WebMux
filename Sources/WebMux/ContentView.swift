import SwiftUI

struct ContentView: View {
    @Bindable var store: ServiceStore
    @State private var selection: UUID?
    @State private var webViewManager = WebViewManager()
    @State private var showingAddSheet = false
    @State private var showingSettings = false
    @State private var editingService: Service?
    @State private var draggedService: UUID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                Spacer().frame(height: 4)

                ForEach(store.services) { service in
                    sidebarIcon(for: service)
                        .onDrag {
                            draggedService = service.id
                            return NSItemProvider(object: service.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: ServiceDropDelegate(
                            service: service, store: store, draggedService: $draggedService
                        ))
                }

                Spacer()

                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

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

            Group {
                if let id = selection, let service = store.services.first(where: { $0.id == id }) {
                    WebViewContainer(webView: webViewManager.webView(for: service))
                        .id(id)
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { webViewManager.contentSize = geo.size }
                    .onChange(of: geo.size) { _, size in webViewManager.contentSize = size }
            })
        }
        .sheet(isPresented: $showingAddSheet) {
            ServiceEditorView(model: ServiceEditorModel(), store: store)
        }
        .sheet(item: $editingService) { service in
            ServiceEditorView(model: ServiceEditorModel(editing: service), store: store, onRemove: {
                webViewManager.removeWebView(for: service.id)
                if selection == service.id {
                    selection = store.services.first(where: { $0.id != service.id })?.id
                }
                store.remove(id: service.id)
            })
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(webViewManager: webViewManager)
        }
        .onAppear {
            if selection == nil { selection = store.services.first?.id }
        }
        .task {
            guard GeneralSettings.shared.preloadServices else { return }
            // Selected service first, then the rest in sidebar order.
            let selected = store.services.filter { $0.id == selection }
            let others = store.services.filter { $0.id != selection }
            await webViewManager.preload(selected + others)
        }
        .alert(
            "Couldn't Load Your Services",
            isPresented: Binding(
                get: { store.loadFailure != nil },
                set: { if !$0 { store.loadFailure = nil } }
            ),
            presenting: store.loadFailure
        ) { failure in
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([failure.fileURL])
            }
            Button("OK", role: .cancel) {}
        } message: { failure in
            Text(loadFailureMessage(failure))
        }
    }

    private func loadFailureMessage(_ failure: ServiceLoadFailure) -> String {
        if failure.movedToBackup {
            return """
                WebMux couldn't read your saved services file, so it started with an empty list. \
                The original file was kept as "\(failure.fileURL.lastPathComponent)".

                \(failure.errorDescription)
                """
        }
        return """
            WebMux couldn't read your saved services file and couldn't back it up, so it started \
            with an empty list. To protect the original file, changes won't be saved until you \
            restart WebMux.

            \(failure.errorDescription)
            """
    }

    private func sidebarIcon(for service: Service) -> some View {
        Button(action: { selection = service.id }) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(selection == service.id ? Color.accentColor.opacity(0.2) : Color.clear)
                    .frame(width: 44, height: 44)
                faviconImage(for: service)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
        }
        .buttonStyle(.plain)
        .help(service.name)
        .onHover { if $0 { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
        .contextMenu {
            Button("Refresh") { webViewManager.reload(for: service.id) }
            Button("Edit...") { editingService = service }
        }
    }

    @ViewBuilder
    private func faviconImage(for service: Service) -> some View {
        if let path = service.faviconPath, let nsImage = NSImage(contentsOfFile: path) {
            Image(nsImage: nsImage).resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "globe").font(.system(size: 18)).foregroundStyle(.secondary)
        }
    }
}

struct ServiceDropDelegate: DropDelegate {
    let service: Service
    let store: ServiceStore
    @Binding var draggedService: UUID?

    func performDrop(info: DropInfo) -> Bool { draggedService = nil; return true }

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedService, dragged != service.id,
              let from = store.services.firstIndex(where: { $0.id == dragged }),
              let to = store.services.firstIndex(where: { $0.id == service.id }) else { return }
        withAnimation { store.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
}
