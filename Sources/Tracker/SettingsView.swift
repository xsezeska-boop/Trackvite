import SwiftUI

struct SettingsView: View {
    @ObservedObject var tracker: ActivityTracker
    @StateObject private var access = BrowserAccess()
    @State private var confirmRestart = false
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            group("Access") {
                row("Window & tab tracking", detail: "Accessibility", allowed: tracker.accessibilityGranted) {
                    tracker.requestAccessibility()
                }
                Divider()
                row("Screen text", detail: "Screen Recording · optional", allowed: tracker.screenGranted) {
                    tracker.requestScreen()
                }
                if !tracker.accessibilityGranted || !tracker.screenGranted {
                    Text("Allow Trackvite in macOS, rather than an older Tracker entry.").font(.caption).foregroundStyle(.secondary)
                }
                if !tracker.permissionHelp.isEmpty {
                    Text(tracker.permissionHelp).font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Button("Show app") { tracker.showApplication() }
                    Spacer()
                    Button("Check again") { tracker.retryBrowserAccess(); access.refresh() }
                    Button("Restart Trackvite") { confirmRestart = true }
                }
            }
            group("Browsers") {
                if access.browsers.isEmpty {
                    Text("Open Safari or a Chrome-based browser to connect it.").foregroundStyle(.secondary).font(.callout)
                }
                ForEach(access.browsers) { browser in
                    HStack(spacing: 12) {
                        ApplicationIcon(bundleID: browser.id, name: browser.name)
                        Text(browser.name)
                        Spacer()
                        Text(browser.label).font(.caption).foregroundStyle(browser.allowed ? .green : .secondary)
                        Button(browser.allowed ? "Manage" : "Connect") {
                            if browser.allowed || browser.code == -1743 { tracker.openPrivacy("Automation") }
                            else { access.connect(browser.id) { tracker.retryBrowserAccess() } }
                        }
                    }.padding(.vertical, 4)
                }
                Text("Browser access enables tab tracking and website limits.").font(.caption).foregroundStyle(.secondary)
            }
            group("Screen text") {
                Toggle("Read visible text", isOn: $tracker.screenEnabled).toggleStyle(.switch)
                Text(tracker.screenEnabled ? (tracker.isTracking ? tracker.screenStats : "Starts when Screen Time is tracking.") : "Optional. App and website tracking work without it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            group("Data") {
                Button("Clear cache") { tracker.clearCache() }
            }
        }
        .task {
            // Only the visible Settings page polls. No background permission timer or prompts.
            tracker.refreshPermissions(); access.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
                if NSApplication.shared.isActive,
                   NSApplication.shared.windows.contains(where: { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) }) {
                    tracker.refreshPermissions(); access.refresh()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            tracker.retryBrowserAccess(); access.refresh()
        }
        .alert("Restart Trackvite?", isPresented: $confirmRestart) {
            Button("Cancel", role: .cancel) {}
            Button("Restart") { tracker.restartApplication() }
        } message: { Text("Current tasks and activity will clear. Newly granted permissions will be checked on launch.") }

    }
    private func row(_ name: String, detail: String, allowed: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) { Text(name); Text(detail).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Label(allowed ? "Allowed" : "Not allowed", systemImage: allowed ? "checkmark.circle.fill" : "circle")
                .font(.caption).foregroundStyle(allowed ? .green : .secondary)
            Button(allowed ? "Manage" : "Allow") {
                if allowed { tracker.openPrivacy(detail == "Accessibility" ? "Accessibility" : "ScreenCapture") }
                else { action() }
            }
        }.padding(.vertical, 5)
    }
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            content()
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.105, green: 0.12, blue: 0.135), in: RoundedRectangle(cornerRadius: 16))
    }
}
