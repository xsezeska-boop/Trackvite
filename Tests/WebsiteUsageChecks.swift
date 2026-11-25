@main
struct WebsiteUsageChecks {
    static func main() {
        assert(WebsiteLedger.domain("https://WWW.Example.com/a?secret=123#fragment") == "example.com")
        assert(WebsiteLedger.domain("https://user:password@example.com/private") == "example.com")
        assert(WebsiteLedger.domain("http://localhost:3000/path") == "localhost")
        assert(WebsiteLedger.domain("file:///private/file") == nil)
        assert(WebsiteLedger.domain("chrome://settings") == nil)
        assert(WebsiteLedger.domain("https://some search text") == nil)
        assert(WebsiteLedger.domain("not a URL") == nil)
        var ledger = WebsiteLedger()
        let first = BrowserPage.parse("https://example.com/page?token=secret", title: "First tab")!
        let second = BrowserPage.parse("https://example.com/other", title: "Second tab")!
        assert(!first.id.contains("secret"))
        assert(first.id != second.id)
        assert(first.id == BrowserPage.parse("https://example.com/page?other=123#fragment", title: "New title")!.id)
        ledger.add(first, seconds: 2)
        ledger.add(second, seconds: 4)
        ledger.add(first, seconds: 3)
        assert(ledger.rows.count == 2)
        assert(ledger.totals[first.id]?.seconds == 5)
        ledger.add(first, seconds: -.infinity)
        assert(ledger.totals[first.id]?.seconds == 5)
        for i in 0..<300 { ledger.add(BrowserPage.parse("https://example.com/\(i)", title: "tab")!, seconds: 1) }
        assert(ledger.rows.count == 256)
        ledger.add(first, seconds: 1)
        assert(ledger.totals[first.id]?.seconds == 6)
        ledger.clear()
        assert(ledger.rows.isEmpty)
        print("PASS: page identity, separate tabs, repeat visits, query/credential removal, bounded storage, clearing")
    }
}
