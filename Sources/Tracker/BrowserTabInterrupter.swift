import AppKit

/// Uses browser scripting to replace just the verified active page, never the browser window.
enum BrowserTabInterrupter {
    enum Result { case changed, stale, denied, unsupported, failed }
    struct Page { let url: String }
    static func supported(_ bundle: String) -> Bool {
        BrowserRegistry.shared.scripting(bundle) != .accessibility
    }
    static func quote(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\n", with: "\\n") + "\""
    }
    static func tab(_ bundle: String) -> String {
        BrowserRegistry.shared.scripting(bundle) == .safari ? "current tab of front window" : "active tab of front window"
    }
    static func read(_ bundle: String) -> (Page?, Result) {
        guard supported(bundle) else { return (nil, .unsupported) }
        var error: NSDictionary?
        let script = "with timeout of 2 seconds\ntell application id \(quote(bundle))\nif not frontmost then return \"\"\nif (count of windows) is 0 then return \"\"\nreturn URL of \(tab(bundle))\nend tell\nend timeout"
        let value = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue
        if (error?[NSAppleScript.errorNumber] as? Int) == -1743 { return (nil, .denied) }
        guard error == nil, let value, !value.isEmpty else { return (nil, .failed) }
        return (Page(url: value), .stale)
    }
    static func closeTab(_ bundle: String, expected: String) -> Result {
        guard supported(bundle), expected.count <= 8192 else { return .unsupported }
        var error: NSDictionary?
        let script = closingScript(bundle, expected: expected)
        let value = NSAppleScript(source: script)?.executeAndReturnError(&error)
        if (error?[NSAppleScript.errorNumber] as? Int) == -1743 { return .denied }
        guard error == nil else { return .failed }
        return value?.booleanValue == true ? .changed : .stale
    }
    static func closingScript(_ bundle: String, expected: String) -> String {
        "with timeout of 2 seconds\ntell application id \(quote(bundle))\nif not frontmost then return false\nif (count of windows) is 0 then return false\nset t to \(tab(bundle))\nif (URL of t) is not \(quote(expected)) then return false\nif (count of tabs of front window) is 1 then\nmake new tab at end of tabs of front window with properties {URL:\"about:blank\"}\nend if\nclose t\nreturn true\nend tell\nend timeout"
    }

}
