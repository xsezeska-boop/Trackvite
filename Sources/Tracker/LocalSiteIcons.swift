import AppKit
import Combine
import ImageIO
import SQLite3

/// Local-first favicon images with an authorized RAM-only HTTPS fallback.
@MainActor
final class LocalSiteIcons: ObservableObject {
    static let shared = LocalSiteIcons()
    @Published private(set) var revision = 0
    private var directory: URL?
    private let cache = NSCache<NSString, NSImage>()
    private var missing: [String: String] = [:]
    private var inFlight: [String: Task<Lookup, Never>] = [:]
    private let reader = DispatchQueue(label: "tracker.local-favicons", qos: .background)

    private init() {
        // Try the known local location automatically; macOS access controls still apply.
        directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari/Favicon Cache")
        cache.countLimit = 128
        cache.totalCostLimit = 128 * 32 * 32 * 4
    }

    func clearCache() {
        revision += 1
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
        missing.removeAll()
        cache.removeAllObjects()
    }

    func icon(domain: String) async -> NSImage? {
        if let image = cache.object(forKey: domain as NSString) { return image }
        guard let directory, missing[domain] == nil else { return nil }
        let version = revision
        let task: Task<Lookup, Never>
        if let existing = inFlight[domain] {
            task = existing
        } else {
            let reader = self.reader
            task = Task {
                let local: Lookup = await withCheckedContinuation { continuation in
                    reader.async { continuation.resume(returning: Self.lookup(domain: domain, directory: directory)) }
                }
                if local.image != nil { return local }
                if let pixels = await NetworkSiteIcon.image(domain: domain) {
                    return Lookup(image: pixels, reason: "Website icons are kept in memory.")
                }
                return .failure("Icon unavailable")
            }
            inFlight[domain] = task
        }
        let result = await task.value
        guard version == revision, !Task.isCancelled else { return nil }
        inFlight[domain] = nil
        guard let pixels = result.image else {
            if missing.count < 256 { missing[domain] = result.reason }
            return nil
        }
        let image = NSImage(cgImage: pixels, size: NSSize(width: 32, height: 32))
        cache.setObject(image, forKey: domain as NSString, cost: 32 * 32 * 4)
        return image
    }

    struct Lookup {
        let image: CGImage?
        let reason: String
        static func failure(_ reason: String) -> Lookup { Lookup(image: nil, reason: reason) }
    }
    nonisolated static func read(domain: String, directory: URL) -> CGImage? {
        lookup(domain: domain, directory: directory).image
    }
    nonisolated static func lookup(domain: String, directory: URL) -> Lookup {
        guard WebsiteLedger.domain("https://" + domain) == domain else { return .failure("Icon unavailable") }
        let manager = FileManager.default
        do { _ = try manager.contentsOfDirectory(atPath: directory.path) }
        catch {
            return .failure("Icon unavailable")
        }
        let databases = ["favicons.db", "Favicons.db"]
        guard let file = databases.map({ directory.appendingPathComponent($0) })
            .first(where: { manager.isReadableFile(atPath: $0.path) }) else { return .failure("Icon unavailable") }
        var components = URLComponents(url: file, resolvingAgainstBaseURL: false)
        // Immutable read of the main DB: SQLite cannot create journals/shared-memory files.
        // May miss fresh icons still present only in Safari's WAL.
        components?.queryItems = [URLQueryItem(name: "mode", value: "ro"), URLQueryItem(name: "immutable", value: "1")]
        guard let uri = components?.string else { return .failure("Icon unavailable") }
        var database: OpaquePointer?
        guard sqlite3_open_v2(uri, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let database else { if let database { sqlite3_close(database) }; return .failure("Icon unavailable") }
        defer { sqlite3_close(database) }
        let deadline = UnsafeMutablePointer<Double>.allocate(capacity: 1)
        deadline.initialize(to: CFAbsoluteTimeGetCurrent() + 0.15)
        sqlite3_progress_handler(database, 5000, { pointer in
            guard let pointer else { return 1 }
            return CFAbsoluteTimeGetCurrent() > pointer.assumingMemoryBound(to: Double.self).pointee ? 1 : 0
        }, deadline)
        defer {
            sqlite3_progress_handler(database, 0, nil, nil)
            deadline.deinitialize(count: 1)
            deadline.deallocate()
        }
        // Unknown/changed Safari schemas fail safely, without modifying the DB.
        let sql = "SELECT i.uuid FROM icon_info i JOIN page_url p ON p.uuid=i.uuid WHERE p.url LIKE ? ESCAPE '\\' OR p.url LIKE ? ESCAPE '\\' OR p.url LIKE ? ESCAPE '\\' OR p.url LIKE ? ESCAPE '\\' LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return .failure("Icon unavailable") }
        defer { sqlite3_finalize(statement) }
        let escaped = domain.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
        let values = ["https://\(escaped)/%", "https://www.\(escaped)/%", "http://\(escaped)/%", "http://www.\(escaped)/%"]
        for (index, value) in values.enumerated() {
            value.withCString { _ = sqlite3_bind_text(statement, Int32(index + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        }
        guard sqlite3_step(statement) == SQLITE_ROW, let raw = sqlite3_column_text(statement, 0) else { return .failure("Icon unavailable") }
        let uuid = String(cString: raw)
        guard (32...36).contains(uuid.count), uuid.allSatisfy({ $0.isHexDigit || $0 == "-" }) else { return .failure("Icon unavailable") }
        let folder = directory.appendingPathComponent("favicons", isDirectory: true)
        let names = [uuid, uuid.lowercased(), uuid.uppercased()]
        for name in names {
            for suffix in ["", ".png", ".ico"] {
                let url = folder.appendingPathComponent(name + suffix)
                guard let size = (try? manager.attributesOfItem(atPath: url.path)[.size]) as? NSNumber,
                      size.intValue <= 2_000_000,
                      let data = try? Data(contentsOf: url),
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let pixels = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 32,
                        kCGImageSourceShouldCacheImmediately: true
                      ] as CFDictionary) else { continue }
                return Lookup(image: pixels, reason: "Website icons are kept in memory.")
            }
        }
        return .failure("Icon unavailable")
    }
}
