import Foundation
import WebKit

struct Service: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var url: URL
    var faviconPath: String?

    static let defaults: [Service] = [
        Service(id: UUID(), name: "WhatsApp", url: URL(string: "https://web.whatsapp.com")!),
        Service(id: UUID(), name: "Telegram", url: URL(string: "https://web.telegram.org")!),
        Service(id: UUID(), name: "Google Messages", url: URL(string: "https://messages.google.com/web")!),
    ]
}

@MainActor @Observable
final class ServiceStore {
    var services: [Service] = []

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WebMux", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("services.json")
    }

    init() { load() }

    func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let decoded = try? JSONDecoder().decode([Service].self, from: data) else {
            services = Service.defaults
            save()
            return
        }
        services = decoded
    }

    func save() {
        try? JSONEncoder().encode(services).write(to: Self.fileURL)
    }

    func add(_ service: Service) {
        services.append(service)
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        services.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func remove(id: UUID) {
        services.removeAll { $0.id == id }
        save()
        let identifier = id
        Task { @MainActor in
            try? await WKWebsiteDataStore.remove(forIdentifier: identifier)
        }
    }

    func updateFaviconPath(for id: UUID, path: String) {
        guard let i = services.firstIndex(where: { $0.id == id }) else { return }
        services[i].faviconPath = path
        save()
    }
}
