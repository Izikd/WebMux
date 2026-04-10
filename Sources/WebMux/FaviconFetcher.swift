import Foundation
import FaviconFinder

enum FaviconFetcher {
    private static var cacheDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WebMux/favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @MainActor
    static func fetch(for service: Service, store: ServiceStore) async {
        do {
            let favicon = try await FaviconFinder(url: service.url)
                .fetchFaviconURLs()
                .download()
                .first
            guard let data = favicon?.image?.data else { return }
            let path = cacheDir.appendingPathComponent("\(service.id.uuidString).png")
            try data.write(to: path)
            store.updateFaviconPath(for: service.id, path: path.path)
        } catch {
            // Favicon fetch failed — service will use globe icon
        }
    }

    @MainActor
    static func fetchAll(store: ServiceStore) async {
        for service in store.services where service.faviconPath == nil {
            await fetch(for: service, store: store)
        }
    }
}
