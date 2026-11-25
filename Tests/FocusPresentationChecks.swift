@main
struct FocusPresentationChecks {
    static func main() {
        var state = FocusPresentationState()
        assert(state.set(nil) == .none)
        assert(state.set("session:browser:youtube.com") == .show)
        for _ in 0..<1000 { assert(state.set("session:browser:youtube.com") == .none) }
        assert(state.set("session:browser:vk.com") == .update)
        assert(state.set(nil) == .hide)
        for _ in 0..<1000 { assert(state.set(nil) == .none) }
        assert(state.set("session:browser:youtube.com") == .show)
        assert(state.set("new-session:browser:youtube.com") == .update)
        print("PASS: repeated block callbacks do not rebuild shields, target update, release, new session")
    }
}
