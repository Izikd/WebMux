import SwiftUI
import SwiftSoup
import FaviconFinder
import AppKit

struct ServiceTemplate: Identifiable {
    let id = UUID()
    let name: String
    let url: String
    let category: String
}

let serviceCatalog: [ServiceTemplate] = [
    .init(name: "WhatsApp", url: "https://web.whatsapp.com", category: "Messaging"),
    .init(name: "Telegram", url: "https://web.telegram.org", category: "Messaging"),
    .init(name: "Google Messages", url: "https://messages.google.com/web", category: "Messaging"),
    .init(name: "Signal", url: "https://signal.org/en/", category: "Messaging"),
    .init(name: "Discord", url: "https://discord.com/app", category: "Messaging"),
    .init(name: "Slack", url: "https://app.slack.com", category: "Messaging"),
    .init(name: "Microsoft Teams", url: "https://teams.microsoft.com", category: "Messaging"),
    .init(name: "Messenger", url: "https://www.messenger.com", category: "Messaging"),
    .init(name: "Skype", url: "https://web.skype.com", category: "Messaging"),
    .init(name: "Google Chat", url: "https://chat.google.com", category: "Messaging"),
    .init(name: "Element (Matrix)", url: "https://app.element.io", category: "Messaging"),
    .init(name: "Wire", url: "https://app.wire.com", category: "Messaging"),
    .init(name: "Gmail", url: "https://mail.google.com", category: "Email"),
    .init(name: "Outlook", url: "https://outlook.live.com", category: "Email"),
    .init(name: "ProtonMail", url: "https://mail.proton.me", category: "Email"),
    .init(name: "Yahoo Mail", url: "https://mail.yahoo.com", category: "Email"),
    .init(name: "Fastmail", url: "https://app.fastmail.com", category: "Email"),
    .init(name: "Twitter / X", url: "https://x.com", category: "Social"),
    .init(name: "Instagram", url: "https://www.instagram.com", category: "Social"),
    .init(name: "Facebook", url: "https://www.facebook.com", category: "Social"),
    .init(name: "LinkedIn", url: "https://www.linkedin.com", category: "Social"),
    .init(name: "Reddit", url: "https://www.reddit.com", category: "Social"),
    .init(name: "Mastodon", url: "https://mastodon.social", category: "Social"),
    .init(name: "Threads", url: "https://www.threads.net", category: "Social"),
    .init(name: "Notion", url: "https://www.notion.so", category: "Productivity"),
    .init(name: "Google Calendar", url: "https://calendar.google.com", category: "Productivity"),
    .init(name: "Google Drive", url: "https://drive.google.com", category: "Productivity"),
    .init(name: "Trello", url: "https://trello.com", category: "Productivity"),
    .init(name: "Todoist", url: "https://app.todoist.com", category: "Productivity"),
    .init(name: "Asana", url: "https://app.asana.com", category: "Productivity"),
    .init(name: "Linear", url: "https://linear.app", category: "Productivity"),
    .init(name: "GitHub", url: "https://github.com", category: "Productivity"),
    .init(name: "ChatGPT", url: "https://chat.openai.com", category: "Productivity"),
    .init(name: "YouTube", url: "https://www.youtube.com", category: "Media"),
    .init(name: "Spotify", url: "https://open.spotify.com", category: "Media"),
    .init(name: "YouTube Music", url: "https://music.youtube.com", category: "Media"),
    .init(name: "Twitch", url: "https://www.twitch.tv", category: "Media"),
]

@MainActor
final class ServiceEditorModel: ObservableObject {
    @Published var name = ""
    @Published var urlString = ""
    @Published var icons: [IconOption] = []
    @Published var selectedIconID: UUID?
    @Published var isLoadingIcons = false
    @Published var catalogQuery = ""

    let editingService: Service? // nil = adding new

    struct IconOption: Identifiable {
        let id = UUID()
        let image: NSImage
        let data: Data
        let size: CGSize
        let label: String
        let sourceURL: String
    }

    var filteredCatalog: [ServiceTemplate] {
        if catalogQuery.isEmpty { return serviceCatalog }
        return serviceCatalog.filter { $0.name.localizedCaseInsensitiveContains(catalogQuery) }
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && URL(string: normalizedURL) != nil
    }

    var normalizedURL: String {
        var raw = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty && !raw.hasPrefix("http://") && !raw.hasPrefix("https://") { raw = "https://" + raw }
        return raw
    }

    init(editing service: Service? = nil) {
        self.editingService = service
        if let service {
            name = service.name
            urlString = service.url.absoluteString
        }
    }

    func prefill(from template: ServiceTemplate) {
        name = template.name
        urlString = template.url
        catalogQuery = ""
        fetchIcons()
    }

    private var iconTask: Task<Void, Never>?

    func fetchIcons() {
        iconTask?.cancel()
        guard let url = URL(string: normalizedURL) else { return }
        icons = []
        selectedIconID = nil
        isLoadingIcons = true
        iconTask = Task {
            var iconURLs: [(url: URL, label: String)] = []

            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            if let (data, response) = try? await URLSession.shared.data(for: request),
               let html = String(data: data, encoding: .utf8),
               let finalURL = (response as? HTTPURLResponse)?.url ?? response.url,
               let doc = try? SwiftSoup.parse(html, finalURL.absoluteString) {

                let iconLinks = try? doc.select("link[rel~=icon], link[rel*=icon], link[rel*=apple-touch], link[rel*=msapplication]")
                for link in iconLinks ?? Elements() {
                    guard let href = try? link.attr("abs:href"), !href.isEmpty,
                          let resolved = URL(string: href) else { continue }
                    let rel = (try? link.attr("rel")) ?? "icon"
                    iconURLs.append((resolved, "HTML · \(rel)"))
                }

                if let manifestHref = try? doc.select("link[rel=manifest]").first()?.attr("abs:href"),
                   !manifestHref.isEmpty, let manifestURL = URL(string: manifestHref) {
                    iconURLs += await fetchManifestIcons(manifestURL: manifestURL)
                }
            }

            if let urls = try? await FaviconFinder(url: url).fetchFaviconURLs() {
                for u in urls {
                    let label = switch u.sourceType {
                    case .html: "HTML"
                    case .ico: "ICO"
                    case .webApplicationManifestFile: "Manifest"
                    case .mock: "Mock"
                    }
                    iconURLs.append((u.source, label))
                }
            }

            if let host = url.host, let icoURL = URL(string: "\(url.scheme ?? "https")://\(host)/favicon.ico") {
                iconURLs.append((icoURL, "ICO"))
            }

            guard !Task.isCancelled else { return }

            var results: [IconOption] = []
            var seen = Set<String>()
            for entry in iconURLs {
                guard seen.insert(entry.url.absoluteString).inserted else { continue }
                guard let (data, _) = try? await URLSession.shared.data(from: entry.url),
                      let img = NSImage(data: data), !Task.isCancelled else { continue }
                let w = Int(img.size.width), h = Int(img.size.height)
                results.append(IconOption(image: img, data: data, size: img.size, label: "\(entry.label) · \(w)×\(h)", sourceURL: entry.url.absoluteString))
            }

            icons = results.sorted { scoreIcon($0) > scoreIcon($1) }
            // Pre-select: match saved icon when editing, otherwise best scored
            if let savedURL = editingService?.faviconSourceURL,
               let match = icons.first(where: { $0.sourceURL == savedURL }) {
                selectedIconID = match.id
            } else {
                selectedIconID = icons.first?.id
            }
            isLoadingIcons = false
        }
    }

    private func scoreIcon(_ icon: IconOption) -> Int {
        var score = 0
        let label = icon.label.lowercased()
        let dim = Int(max(icon.size.width, icon.size.height))

        // Source type bonus
        if label.contains("manifest")    { score += 500 }
        else if label.contains("apple-touch") { score += 400 }
        else if label.contains("html")   { score += 200 }
        else if label.contains("ico")    { score += 50 }

        // Size bonus — prefer icons closest to 128-512px range
        if dim >= 128 && dim <= 512      { score += 300 }
        else if dim >= 64                { score += 150 }
        else if dim >= 32                { score += 50 }

        // Larger is generally better (diminishing returns)
        score += min(dim, 512)

        // Penalize very small icons
        if dim < 32 { score -= 200 }

        return score
    }

    private func fetchManifestIcons(manifestURL: URL) async -> [(url: URL, label: String)] {
        guard let (data, _) = try? await URLSession.shared.data(from: manifestURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let icons = json["icons"] as? [[String: Any]] else { return [] }
        return icons.compactMap { icon in
            guard let src = icon["src"] as? String else { return nil }
            let resolved: URL? = if src.hasPrefix("//") { URL(string: "https:" + src) }
                else if src.hasPrefix("http") { URL(string: src) }
                else { URL(string: src, relativeTo: manifestURL)?.absoluteURL }
            guard let url = resolved else { return nil }
            return (url, "Manifest · \((icon["sizes"] as? String) ?? "?")")
        }
    }
}

struct ServiceEditorView: View {
    @StateObject var model: ServiceEditorModel
    var store: ServiceStore
    var onSave: (() -> Void)?
    var onRemove: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var showRemoveConfirmation = false
    @State private var originalFaviconPath: String?
    @State private var originalFaviconSourceURL: String?

    var isAdding: Bool { model.editingService == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isAdding ? "Add Service" : "Edit Service").font(.headline)

            // Catalog search (add mode only)
            if isAdding {
                TextField("Search known services...", text: $model.catalogQuery)
                    .textFieldStyle(.roundedBorder)

                if !model.catalogQuery.isEmpty {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(model.filteredCatalog) { template in
                                Button { model.prefill(from: template) } label: {
                                    HStack {
                                        Text(template.name)
                                        Spacer()
                                        Text(template.category).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 5)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Divider()
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                    .background(.quaternary.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            // Name + URL
            TextField("Name", text: $model.name)
                .textFieldStyle(.roundedBorder)
            HStack {
                TextField("URL", text: $model.urlString)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.fetchIcons() }
                Button("Fetch Icons") { model.fetchIcons() }
                    .disabled(model.urlString.isEmpty)
            }

            // Icon picker
            if model.isLoadingIcons {
                HStack { Spacer(); ProgressView().controlSize(.small); Text("Loading icons...").font(.caption); Spacer() }
            }
            if !model.icons.isEmpty {
                Text("Select icon:").font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(model.icons) { icon in
                            IconRow(icon: icon, isSelected: model.selectedIconID == icon.id) {
                                model.selectedIconID = icon.id
                                if !isAdding, let service = model.editingService {
                                    previewIcon(icon, for: service.id)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
            }

            Divider()

            HStack {
                if !isAdding {
                    Button("Remove Service") { showRemoveConfirmation = true }
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel") { cancelEdit() }
                    .keyboardShortcut(.cancelAction)
                Button(isAdding ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.isValid)
            }
        }
        .padding()
        .frame(width: 440)
        .onAppear {
            if !isAdding {
                originalFaviconPath = model.editingService?.faviconPath
                originalFaviconSourceURL = model.editingService?.faviconSourceURL
                model.fetchIcons()
            }
        }
        .alert("Remove Service", isPresented: $showRemoveConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                onRemove?()
                dismiss()
            }
        } message: {
            Text("Are you sure you want to remove \"\(model.name)\"? This cannot be undone.")
        }
    }

    private func save() {
        guard let url = URL(string: model.normalizedURL) else { return }
        let trimmedName = model.name.trimmingCharacters(in: .whitespaces)

        if let existing = model.editingService {
            // Update existing
            if let i = store.services.firstIndex(where: { $0.id == existing.id }) {
                store.services[i].name = trimmedName
                store.services[i].url = url
                saveIcon(for: existing.id)
                store.save()
            }
        } else {
            // Add new
            let service = Service(id: UUID(), name: trimmedName, url: url)
            store.add(service)
            saveIcon(for: service.id)
        }
        onSave?()
        dismiss()
    }

    private func previewIcon(_ icon: ServiceEditorModel.IconOption, for id: UUID) {
        saveIconFile(icon, for: id)
        store.updateFaviconPath(for: id, path: iconPath(for: id).path)
    }

    private func cancelEdit() {
        // Restore original icon if we previewed a different one
        if let service = model.editingService, let origPath = originalFaviconPath {
            if let i = store.services.firstIndex(where: { $0.id == service.id }) {
                store.services[i].faviconPath = origPath
                store.services[i].faviconSourceURL = originalFaviconSourceURL
                store.save()
            }
        }
        dismiss()
    }

    private func iconPath(for id: UUID) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WebMux/favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(id.uuidString).png")
    }

    private func saveIconFile(_ icon: ServiceEditorModel.IconOption, for id: UUID) {
        let path = iconPath(for: id)
        if let png = ImageUtils.resize(icon.image, to: 64) {
            try? png.write(to: path)
        } else {
            try? icon.data.write(to: path)
        }
    }

    private func saveIcon(for id: UUID) {
        guard let selectedID = model.selectedIconID,
              let icon = model.icons.first(where: { $0.id == selectedID }) else { return }
        saveIconFile(icon, for: id)
        let path = iconPath(for: id)
        store.updateFaviconPath(for: id, path: path.path)
        if let i = store.services.firstIndex(where: { $0.id == id }) {
            store.services[i].faviconSourceURL = icon.sourceURL
            store.save()
        }
    }
}

private struct IconRow: View {
    let icon: ServiceEditorModel.IconOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                iconImage
                Text(icon.label).font(.caption).lineLimit(1)
                Spacer()
            }
            .padding(6)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var iconImage: some View {
        Image(nsImage: icon.image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
