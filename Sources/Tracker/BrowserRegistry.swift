import AppKit

/// Discovers registered HTTP/HTTPS handlers without launching them. Unknown browsers use AX only.
final class BrowserRegistry: @unchecked Sendable {
    enum Scripting: String { case safari, chromium, accessibility }
    struct Entry { let id: String; let name: String; let scripting: Scripting; let embedded: Bool }
    static let shared = BrowserRegistry()
    private let lock = NSLock()
    @MainActor private var lastRefresh = Date.distantPast
    private var entries: [String: Entry] = [:]
    private static let known: [String: Scripting] = [
        "com.apple.Safari": .safari, "com.apple.SafariTechnologyPreview": .safari,
        "com.google.Chrome": .chromium, "com.google.Chrome.canary": .chromium,
        "org.chromium.Chromium": .chromium, "com.microsoft.edgemac": .chromium,
        "com.brave.Browser": .chromium, "com.operasoftware.Opera": .chromium,
        "com.operasoftware.OperaGX": .chromium, "com.vivaldi.Vivaldi": .chromium,
        "com.google.Chrome.beta": .chromium, "com.google.Chrome.dev": .chromium,
        "org.mozilla.firefox": .accessibility, "org.mozilla.nightly": .accessibility,
        "org.mozilla.firefoxdeveloperedition": .accessibility, "app.zen-browser.zen": .accessibility,
        "io.gitlab.librewolf-community": .accessibility, "company.thebrowser.Browser": .accessibility
    ]
    var ids: Set<String> {
        lock.lock(); defer { lock.unlock() }
        return Set(Self.known.keys).union(entries.keys)
    }
    var installed: [Entry] {
        lock.lock(); defer { lock.unlock() }
        return entries.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func scripting(_ id: String) -> Scripting {
        lock.lock(); defer { lock.unlock() }
        return entries[id]?.scripting ?? Self.known[id] ?? .accessibility
    }
    @MainActor func refresh() {
        guard Date().timeIntervalSince(lastRefresh) > 60 else { return }
        lastRefresh = Date()
        var urls = Set<URL>()
        for scheme in ["https://example.com", "http://example.com"] {
            urls.formUnion(NSWorkspace.shared.urlsForApplications(toOpen: URL(string: scheme)!))
        }
        for url in urls { register(url) }
    }
    @MainActor func register(_ url: URL) {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
              id != Bundle.main.bundleIdentifier else { return }
        lock.lock(); let exists = entries[id] != nil; lock.unlock()
        guard !exists else { return }
        let schemes = (bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? [])
            .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }.map { $0.lowercased() }
        guard Self.known[id] != nil || schemes.contains("http") || schemes.contains("https") else { return }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent
        var scripting = Self.known[id] ?? .accessibility
        // Inspect the declared dictionary; never assume an unknown browser understands Chrome's commands.
        if scripting == .accessibility,
           let file = bundle.object(forInfoDictionaryKey: "OSAScriptingDefinition") as? String,
           let dictionary = bundle.url(forResource: (file as NSString).deletingPathExtension, withExtension: (file as NSString).pathExtension),
           let size = try? dictionary.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 1_000_000,
           let text = try? String(contentsOf: dictionary, encoding: .utf8) {
            scripting = Self.dictionaryScripting(text)
        }
        let documents = bundle.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]] ?? []
        let opensHTML = documents.contains { type in
            let values = (type["LSItemContentTypes"] as? [String] ?? []) +
                (type["CFBundleTypeExtensions"] as? [String] ?? []) +
                (type["CFBundleTypeMIMETypes"] as? [String] ?? [])
            return values.contains { ["public.html", "html", "htm", "text/html"].contains($0.lowercased()) }
        }
        let embedded = Self.known[id] == nil && scripting == .accessibility && !opensHTML
        lock.lock(); entries[id] = Entry(id: id, name: name, scripting: scripting, embedded: embedded); lock.unlock()
    }
    static func dictionaryScripting(_ text: String) -> Scripting {
        let delegate = BrowserDictionaryCapabilities()
        let parser = XMLParser(data: Data(text.utf8))
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.url, delegate.close else { return .accessibility }
        if delegate.currentTab { return .safari }
        if delegate.activeTab { return .chromium }
        return .accessibility
    }
}

private final class BrowserDictionaryCapabilities: NSObject, XMLParserDelegate {
    var activeTab = false
    var currentTab = false
    var url = false
    var close = false
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        let name = attributes["name"]?.lowercased()
        if elementName == "property" {
            if name == "active tab" { activeTab = true }
            if name == "current tab" { currentTab = true }
            if name == "url" { url = true }
        }
        if elementName == "command", name == "close" { close = true }
        if elementName.hasSuffix("include"), attributes["href"]?.lowercased().contains("cocoastandard.sdef") == true { close = true }
    }
}
