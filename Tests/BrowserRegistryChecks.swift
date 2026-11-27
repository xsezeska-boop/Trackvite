import AppKit
@main struct BrowserRegistryChecks {
    @MainActor static func main() {
        let registry = BrowserRegistry.shared
        assert(registry.scripting("com.apple.Safari") == .safari)
        assert(registry.scripting("com.google.Chrome.beta") == .chromium)
        assert(registry.scripting("app.zen-browser.zen") == .accessibility)
        assert(registry.scripting("unknown.application") == .accessibility)
        assert(BrowserRegistry.dictionaryScripting("<dictionary><property name=\"active tab\"/><property name=\"URL\"/><command name=\"close\"/></dictionary>") == .chromium)
        assert(BrowserRegistry.dictionaryScripting("<dictionary><property name=\"active tab\"/></dictionary>") == .accessibility)
        assert(BrowserRegistry.dictionaryScripting("<dictionary><property name='current tab'/><property name='URL'/><command name='close'/></dictionary>") == .safari)
        registry.refresh()
        let installed = registry.installed
        assert(Set(installed.map(\.id)).count == installed.count)
        for entry in installed {
            assert(registry.ids.contains(entry.id))
            assert(!entry.name.isEmpty)
            if ["com.openai.codex", "com.openai.chat", "com.openai.ChatGPT"].contains(entry.id) { assert(entry.embedded) }
            if entry.id == "com.apple.Safari" { assert(!entry.embedded) }
        }
        print("PASS: installed browser discovery, per-engine capabilities, unknown browsers use AX safely; detected: " + installed.map(\.name).joined(separator: ", "))
    }
}
