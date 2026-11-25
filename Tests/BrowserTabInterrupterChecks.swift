import AppKit
@main
struct BrowserTabInterrupterChecks {
    static func main() {
        assert(BrowserTabInterrupter.supported("com.apple.Safari"))
        assert(BrowserTabInterrupter.supported("com.google.Chrome"))
        assert(!BrowserTabInterrupter.supported("org.mozilla.firefox"))
        assert(!BrowserTabInterrupter.supported("unknown.browser"))
        assert(BrowserTabInterrupter.tab("com.apple.Safari") == "current tab of front window")
        assert(BrowserTabInterrupter.tab("com.google.Chrome") == "active tab of front window")
        assert(BrowserTabInterrupter.quote("a\"b\\c\n") == "\"a\\\"b\\\\c\\n\"")
        let source = BrowserTabInterrupter.closingScript("com.apple.Safari", expected: "https://youtube.com/test")
        assert(source.contains("close t"))
        assert(!source.contains("close window") && !source.contains("quit"))
        assert(source.range(of: "if (URL of t) is not")!.lowerBound < source.range(of: "close t")!.lowerBound)
        assert(source.contains("count of tabs of front window) is 1"))
        var error: NSDictionary?
        let compiled = NSAppleScript(source: source)?.compileAndReturnError(&error)
        assert(compiled == true, "Safari script must compile: \(String(describing: error))")
        print("PASS: supported browsers, active-tab target, safe AppleScript quoting; no user tabs changed")
    }
}
