import Foundation

@main
struct NetworkSiteIconChecks {
    static func main() async {
        let config = NetworkSiteIcon.session.configuration
        assert(config.urlCache == nil)
        assert(config.httpCookieStorage == nil)
        assert(config.urlCredentialStorage == nil)
        assert(!config.httpShouldSetCookies)
        let html = """
        <link href="/brand/icon.png" rel="shortcut icon">
        <link rel='apple-touch-icon' href='https://cdn.example.com/icon.png?a=1&amp;b=2'>
        <link rel=icon href=http://example.com/insecure.ico>
        <link rel=mask-icon href=/mask.svg>
        <link rel=icon href=/brand/icon.png>
        """
        let candidates = NetworkSiteIcon.candidates(html: html, base: URL(string: "https://example.com/")!)
        assert(candidates.map(\.absoluteString) == ["https://example.com/brand/icon.png", "https://cdn.example.com/icon.png?a=1&b=2"])
        assert(NetworkSiteIcon.decode(Data(repeating: 0, count: NetworkSiteIcon.byteLimit + 1)) == nil)
        assert(NetworkSiteIcon.decode(Data()) == nil)
        print("PASS: no disk cache/cookies/credentials, icon discovery, HTTPS, deduplication, size limit")
        if CommandLine.arguments.contains("--live") {
            var found = 0
            for domain in ["youtube.com", "google.com", "github.com"] {
                if let image = await NetworkSiteIcon.image(domain: domain) {
                    assert(image.width <= 32 && image.height <= 32)
                    print("LIVE \(domain): \(image.width)×\(image.height) icon in RAM")
                    found += 1
                } else { print("LIVE \(domain): unavailable") }
            }
            assert(found > 0, "Live network returned no icons")
        }
    }
}
