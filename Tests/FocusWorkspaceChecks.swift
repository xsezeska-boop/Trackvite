import Foundation

@main
struct FocusWorkspaceChecks {
    static func main() {
        let file = URL(fileURLWithPath: "/tmp/project")
        var plan = FocusPlan(title: "Прототип", detail: "Готов главный экран", start: .distantFuture, minutes: 75,
            daily: false, blockedApps: ["editor", "chat", "chat"], blockedSites: ["youtube.com"],
            workApps: ["editor", "browser", "editor"], materials: [file, file, URL(string: "https://example.com")!])
        plan.normalizeWorkspace()
        assert(plan.title == "Прототип" && plan.detail == "Готов главный экран")
        assert(plan.workApps == ["browser", "editor"])
        assert(plan.blockedApps == ["chat"])
        assert(plan.materials == [file])
        assert(plan.blockedSites == ["youtube.com"])
        plan.workApps = (0..<30).map { "app\($0)" }
        plan.materials = (0..<20).map { URL(fileURLWithPath: "/tmp/project\($0)") }
        plan.normalizeWorkspace()
        assert(plan.workApps.count == 20)
        assert(plan.materials.count == 10)
        print("PASS: multi-app workspace, task result, resource deduplication, work/block conflicts, memory bounds")
    }
}
