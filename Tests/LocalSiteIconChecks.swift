import AppKit
import SQLite3

@main
struct LocalSiteIconChecks {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TrackerIconCheck-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("favicons"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let uuid = "11111111-1111-1111-1111-111111111111"
        let pixels = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 64, bitsPerPixel: 32)!
        let image = pixels.representation(using: .png, properties: [:])!
        try image.write(to: directory.appendingPathComponent("favicons/" + uuid))
        var db: OpaquePointer?
        assert(sqlite3_open(directory.appendingPathComponent("favicons.db").path, &db) == SQLITE_OK)
        assert(sqlite3_exec(db, "CREATE TABLE icon_info(uuid TEXT); CREATE TABLE page_url(url TEXT, uuid TEXT); INSERT INTO icon_info VALUES('\(uuid)'); INSERT INTO page_url VALUES('https://example.com/page','\(uuid)');", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        let before = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        let result = LocalSiteIcons.read(domain: "example.com", directory: directory)
        assert(result != nil)
        assert(result!.width <= 32 && result!.height <= 32)
        assert(LocalSiteIcons.read(domain: "missing.example", directory: directory) == nil)
        assert(LocalSiteIcons.read(domain: "../bad", directory: directory) == nil)
        let after = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        assert(before == after, "Reader must not create journals or shared memory files")
        print("PASS: existing favicon, size cap, missing icon, invalid domain, no extra files")
    }
}
