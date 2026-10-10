import Foundation
import os
import WebKit

struct Service: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var url: URL
    var faviconPath: String?
    var faviconSourceURL: String?

    init(id: UUID, name: String, url: URL, faviconPath: String? = nil, faviconSourceURL: String? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.faviconPath = faviconPath
        self.faviconSourceURL = faviconSourceURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(URL.self, forKey: .url)
        faviconPath = try container.decodeIfPresent(String.self, forKey: .faviconPath)
        faviconSourceURL = try container.decodeIfPresent(String.self, forKey: .faviconSourceURL)
    }

    static let defaults: [Service] = []
}

/// Locations of cached service icons: `<id>.png` is the saved icon, and
/// `<id>.preview.png` is a temporary file used while picking an icon in the editor.
enum FaviconFiles {
    static var directory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WebMux/favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).png")
    }

    static func previewURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).preview.png")
    }

    static func removeAll(for id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
        try? FileManager.default.removeItem(at: previewURL(for: id))
    }
}

/// Describes why `services.json` could not be loaded, so the UI can tell the user.
struct ServiceLoadFailure: Identifiable {
    let id = UUID()
    /// The backup file if the unreadable file was moved aside, otherwise the original file left in place.
    let fileURL: URL
    /// `true` if the file was moved to a backup; `false` if the move failed and saving is disabled this session.
    let movedToBackup: Bool
    let errorDescription: String
}

@MainActor @Observable
final class ServiceStore {
    var services: [Service] = []
    /// Set when `services.json` existed but could not be read. The UI clears it after showing an alert.
    var loadFailure: ServiceLoadFailure?

    private static let logger = Logger(subsystem: "com.webmux.app", category: "ServiceStore")

    private let directory: URL
    private var isReadOnlyDueToLoadFailure = false
    /// True only when the service list was decoded from an existing services.json.
    private var loadedFromFile = false

    private var fileURL: URL {
        directory.appendingPathComponent("services.json")
    }

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WebMux", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.directory = dir
        load()
    }

    func load() {
        let fm = FileManager.default
        let url = fileURL

        guard fm.fileExists(atPath: url.path) else {
            // First launch: seed defaults and persist.
            services = Service.defaults
            save()
            return
        }

        do {
            let data = try Data(contentsOf: url)
            services = try JSONDecoder().decode([Service].self, from: data)
            loadedFromFile = true
        } catch {
            Self.logger.error("Failed to load services.json: \(error.localizedDescription, privacy: .public)")

            // Attempt to back up the corrupt file.
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let timestamp = formatter.string(from: Date())
            let backupURL = url.deletingLastPathComponent()
                .appendingPathComponent("services.json.corrupt-\(timestamp)")

            do {
                try fm.moveItem(at: url, to: backupURL)
                Self.logger.info("Backed up corrupt file to \(backupURL.lastPathComponent, privacy: .public)")
                loadFailure = ServiceLoadFailure(
                    fileURL: backupURL, movedToBackup: true, errorDescription: error.localizedDescription
                )
            } catch let moveError {
                Self.logger.error("Could not back up corrupt file: \(moveError.localizedDescription, privacy: .public). Entering read-only mode.")
                isReadOnlyDueToLoadFailure = true
                loadFailure = ServiceLoadFailure(
                    fileURL: url, movedToBackup: false, errorDescription: error.localizedDescription
                )
            }

            services = []
        }
    }

    func save() {
        guard !isReadOnlyDueToLoadFailure else { return }
        do {
            let data = try JSONEncoder().encode(services)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            Self.logger.error("Failed to save services.json: \(error.localizedDescription, privacy: .public)")
        }
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
        FaviconFiles.removeAll(for: id)
        Task { @MainActor in
            await Self.removeWebsiteData(for: id)
        }
    }

    /// Deletes the service's cookies/storage. WebKit refuses while the data store is
    /// still in use, which includes a short period after the last web view using it
    /// is released ("in use by network process"), so retry with backoff.
    private static func removeWebsiteData(for id: UUID) async {
        var delay = Duration.milliseconds(500)
        for attempt in 1...6 {
            try? await Task.sleep(for: delay)
            do {
                try await WKWebsiteDataStore.remove(forIdentifier: id)
                logger.info("Removed website data for \(id.uuidString, privacy: .public)")
                return
            } catch {
                logger.info("Website data removal attempt \(attempt) failed: \(error.localizedDescription, privacy: .public)")
            }
            delay *= 2
        }
        logger.error("Giving up removing website data for \(id.uuidString, privacy: .public)")
    }

    /// Removes website data stores and icon files left behind by services that no longer
    /// exist (e.g. removed by older versions). Safe: those stores have no web views.
    func removeOrphanedServiceData() async {
        // Only trust the list if it was read from an existing services.json. After a load
        // failure (or a deleted file) it is empty and every session would look orphaned.
        guard loadedFromFile else { return }
        let known = Set(services.map(\.id))

        for id in await WKWebsiteDataStore.allDataStoreIdentifiers where !known.contains(id) {
            do {
                try await WKWebsiteDataStore.remove(forIdentifier: id)
                Self.logger.info("Removed orphaned website data \(id.uuidString, privacy: .public)")
            } catch {
                Self.logger.error("Could not remove orphaned website data \(id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        let files = (try? FileManager.default.contentsOfDirectory(
            at: FaviconFiles.directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "png" {
            // "<uuid>.png" or "<uuid>.preview.png"
            let stem = file.lastPathComponent.components(separatedBy: ".").first ?? ""
            guard let id = UUID(uuidString: stem), !known.contains(id) else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    func updateFaviconPath(for id: UUID, path: String) {
        guard let i = services.firstIndex(where: { $0.id == id }) else { return }
        services[i].faviconPath = path
        save()
    }
}
