import SwiftUI
import AppKit

@main
struct TrackviteApp: App {
    @StateObject private var tracker = ActivityTracker()

    var body: some Scene {
        WindowGroup {
            Dashboard(focus: tracker.focus).environmentObject(tracker)
                .frame(minWidth: 1060, minHeight: 730)
                .preferredColorScheme(.dark)
                .environment(\.locale, Locale(identifier: "en_GB"))
        }
        .windowStyle(.hiddenTitleBar)
        MenuBarExtra("Trackvite", systemImage: "waveform.path.ecg") {
            TrackerMenu(tracker: tracker, focus: tracker.focus)
        }
    }
}

private struct TrackerMenu: View {
    @ObservedObject var tracker: ActivityTracker
    @ObservedObject var focus: FocusManager
    var body: some View {
        if let plan = focus.active.first {
            Text(plan.title)
            let stats = focus.activity[plan.id] ?? FocusActivityTotals()
            Text("Focused: \(Int(stats.work / 60))m · distracted: \(Int(stats.distraction / 60))m")
            Button("Finish task") { focus.finishTask(plan.id) }
            Divider()
        } else { Text("No active task") }
        Button(tracker.isTracking ? "Pause Screen Time" : "Start tracking") { tracker.toggle() }
        Divider()
        Button("Quit Trackvite") { NSApplication.shared.terminate(nil) }
    }
}
