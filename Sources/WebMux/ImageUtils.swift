import AppKit

enum ImageUtils {
    static func resize(_ image: NSImage, to size: Int) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let ctx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        guard let ctx else { return nil }

        ctx.interpolationQuality = .high
        ctx.setShouldAntialias(true)
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        guard let scaled = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: scaled)
        return rep.representation(using: .png, properties: [.interlaced: false])
    }
}
