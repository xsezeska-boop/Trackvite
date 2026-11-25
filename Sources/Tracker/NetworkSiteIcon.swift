import Foundation
import ImageIO

private actor IconRequests {
    static let shared = IconRequests()
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func enter() async {
        if active < 2 { active += 1; return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func leave() {
        if waiting.isEmpty { active -= 1 } else { waiting.removeFirst().resume() }
    }
}

private final class IconRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" && task.countOfBytesReceived < 262_144 ? request : nil)
    }
}

enum NetworkSiteIcon {
    static let byteLimit = 262_144
    static let htmlLimit = 65_536
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 8
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config)
    }()

    static func image(domain: String) async -> CGImage? {
        guard WebsiteLedger.domain("https://" + domain) == domain,
              let root = URL(string: "https://\(domain)/") else { return nil }
        await IconRequests.shared.enter()
        let image = await load(root: root)
        await IconRequests.shared.leave()
        return image
    }

    private static func load(root: URL) async -> CGImage? {
        guard !Task.isCancelled else { return nil }
        // The normal favicon location avoids downloading page HTML for most sites.
        if let result = await bytes(root.appendingPathComponent("favicon.ico"), limit: byteLimit),
           let image = decode(result.data) { return image }
        guard !Task.isCancelled,
              let page = await bytes(root, limit: htmlLimit, prefix: true),
              let html = String(data: page.data, encoding: .utf8) else { return nil }
        for url in candidates(html: html, base: page.url).prefix(3) {
            guard !Task.isCancelled else { return nil }
            if let result = await bytes(url, limit: byteLimit), let image = decode(result.data) { return image }
        }
        return nil
    }

    private static func bytes(_ url: URL, limit: Int, prefix: Bool = false) async -> (data: Data, url: URL)? {
        guard url.scheme == "https", url.user == nil, url.password == nil else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)
        request.setValue(prefix ? "text/html" : "image/*", forHTTPHeaderField: "Accept")
        do {
            let (stream, response) = try await session.bytes(for: request, delegate: IconRedirects())
            defer { stream.task.cancel() }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  prefix || response.expectedContentLength <= Int64(limit) else { return nil }
            var data = Data()
            data.reserveCapacity(min(limit, 16_384))
            for try await byte in stream {
                try Task.checkCancellation()
                if data.count == limit { return prefix ? (data, response.url ?? url) : nil }
                data.append(byte)
                if prefix && data.count % 1024 == 0,
                   String(decoding: data.suffix(2048), as: UTF8.self).lowercased().contains("</head>") { break }
            }
            return (data, response.url ?? url)
        } catch { return nil }
    }

    static func decode(_ data: Data) -> CGImage? {
        guard !data.isEmpty, data.count <= byteLimit,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 32,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }

    /// Only advertised icon links, never scripts, images from page content or a third-party icon service.
    static func candidates(html: String, base: URL) -> [URL] {
        guard let links = try? NSRegularExpression(pattern: "<link\\b[^>]{0,4096}>", options: .caseInsensitive),
              let attributes = try? NSRegularExpression(pattern: "([a-zA-Z-]+)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))") else { return [] }
        var result: [URL] = []
        let text = html as NSString
        for match in links.matches(in: html, range: NSRange(location: 0, length: text.length)).prefix(64) {
            let tag = text.substring(with: match.range) as NSString
            var values: [String: String] = [:]
            for attribute in attributes.matches(in: tag as String, range: NSRange(location: 0, length: tag.length)) {
                let key = tag.substring(with: attribute.range(at: 1)).lowercased()
                for index in 2...4 where attribute.range(at: index).location != NSNotFound {
                    values[key] = tag.substring(with: attribute.range(at: index))
                }
            }
            let rel = (values["rel"] ?? "").lowercased().split(whereSeparator: { $0.isWhitespace })
            guard rel.contains("icon") || rel.contains("apple-touch-icon"),
                  let href = values["href"]?.replacingOccurrences(of: "&amp;", with: "&"),
                  let url = URL(string: href, relativeTo: base)?.absoluteURL,
                  url.scheme == "https", url.user == nil, url.password == nil,
                  !result.contains(url), url.pathExtension.lowercased() != "svg" else { continue }
            result.append(url)
        }
        return result
    }
}
