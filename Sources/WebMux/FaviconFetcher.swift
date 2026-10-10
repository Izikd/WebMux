import Foundation
import FaviconFinder
import AppKit

enum FaviconFetcher {
    @MainActor
    static func fetch(for service: Service, store: ServiceStore) async {
        do {
            let favicons = try await FaviconFinder(url: service.url)
                .fetchFaviconURLs()
                .download()
            // Pick the largest icon
            guard let best = try? favicons.largest(),
                  let img = best.image else { return }

            let path = FaviconFiles.url(for: service.id)

            guard let nsImg = NSImage(data: img.data) else { return }
            if let png = ImageUtils.resize(nsImg, to: 64) {
                try png.write(to: path)
            } else {
                try img.data.write(to: path)
            }
            store.updateFaviconPath(for: service.id, path: path.path)
        } catch {}
    }

    @MainActor
    static func fetchAll(store: ServiceStore) async {
        for service in store.services where service.faviconPath == nil {
            await fetch(for: service, store: store)
        }
    }
}
