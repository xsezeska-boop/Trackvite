import Foundation

struct BrowserPage: Equatable {
    let id: String
    let domain: String
    let title: String
    static func parse(_ raw: String, title: String) -> BrowserPage? {
        guard let domain = WebsiteLedger.domain(raw), var url = URLComponents(string: raw) else { return nil }
        url.user = nil; url.password = nil; url.query = nil; url.fragment = nil
        url.host = domain
        let identity = (url.string ?? domain)
        guard identity.count <= 2048 else { return nil }
        return BrowserPage(id: identity, domain: domain,
            title: String((title.isEmpty ? domain : title).prefix(256)))
    }
}

struct WebsiteUsage: Identifiable {
    let page: BrowserPage
    var id: String { page.id }
    var seconds: Double
}

struct WebsiteLedger {
    private(set) var totals: [String: WebsiteUsage] = [:]
    static func domain(_ raw: String) -> String? {
        guard raw.count <= 8192, let url = URLComponents(string: raw),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              var host = url.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        if host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty, !host.contains(where: { $0.isWhitespace }),
              host.contains(".") || host == "localhost" || host.contains(":") else { return nil }
        return host
    }
    mutating func add(_ page: BrowserPage, seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        if totals[page.id] == nil && totals.count >= 256 { return }
        totals[page.id] = WebsiteUsage(page: page, seconds: (totals[page.id]?.seconds ?? 0) + seconds)
    }
    mutating func clear() { totals.removeAll() }
    var rows: [WebsiteUsage] {
        totals.values.sorted { $0.page.title == $1.page.title ? $0.id < $1.id : $0.page.title < $1.page.title }
    }
}
