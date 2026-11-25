import AppKit
import SwiftUI

/// Read-only access to installed app bundles. No URL loading or disk cache.
@MainActor
private final class AppIconCache {
    static let shared = AppIconCache()
    private let images = NSCache<NSString, NSImage>()

    private init() {
        images.countLimit = 128
        images.totalCostLimit = 128 * 32 * 32 * 4
    }

    func clear() { images.removeAllObjects() }

    func icon(for bundleID: String) -> NSImage? {
        let key = bundleID as NSString
        if let cached = images.object(forKey: key) { return cached }
        let source: NSImage?
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let icon = app.icon {
            source = icon
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            source = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            source = nil
        }
        guard let source,
              let bitmap = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8,
                bytesPerRow: 32 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var bounds = CGRect(x: 0, y: 0, width: 32, height: 32)
        guard let original = source.cgImage(forProposedRect: &bounds, context: nil, hints: nil) else { return nil }
        bitmap.interpolationQuality = .high
        bitmap.draw(original, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        guard let pixels = bitmap.makeImage() else { return nil }
        let icon = NSImage(cgImage: pixels, size: NSSize(width: 32, height: 32))
        images.setObject(icon, forKey: key, cost: 32 * 32 * 4)
        return icon
    }
}

struct ApplicationIcon: View {
    @MainActor static func clearCache() { AppIconCache.shared.clear() }
    let bundleID: String
    let name: String
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: "app.fill").resizable().scaledToFit()
                    .padding(5).foregroundStyle(.secondary)
            }
        }
        .frame(width: 32, height: 32)
        .accessibilityLabel("App icon \(name)")
        // Loading happens once per row identity, not on every live timer update.
        .task(id: bundleID) { icon = AppIconCache.shared.icon(for: bundleID) }
    }
}

/// Real favicon images from the local cache or an ephemeral HTTPS request.
struct WebsiteIcon: View {
    let domain: String
    @ObservedObject private var icons = LocalSiteIcons.shared
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit().padding(4)
            } else {
                Image(systemName: "globe").font(.system(size: 21)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 32, height: 32)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("Website icon \(domain)")
        .help(domain)
        .task(id: "\(domain):\(icons.revision)") {
            image = nil
            image = await icons.icon(domain: domain)
        }
    }
}
