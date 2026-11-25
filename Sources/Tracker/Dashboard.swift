import SwiftUI

private let accent = Color(red: 0.65, green: 0.88, blue: 0.49)
private let surface = Color(red: 0.105, green: 0.12, blue: 0.135)

struct Dashboard: View {
    @ObservedObject var focus: FocusManager
    @EnvironmentObject private var tracker: ActivityTracker
    @State private var now = Date()
    @State private var section = "Tasks"
    @State private var windowVisible = false
    private let sections = [("Tasks", "scope"), ("Screen Time", "hourglass"), ("Settings", "slider.horizontal.3")]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    switch section {
                    case "Screen Time": screenTime
                    case "Settings": SettingsView(tracker: tracker)
                    default: TasksHomeView(focus: focus, tracker: tracker, now: now)
                    }

                }.padding(32)
            }.background(Color(red: 0.065, green: 0.075, blue: 0.085))
        }
        .overlay(alignment: .topTrailing) {
            if let notice = tracker.notice {
                InAppNoticeView(notice: notice) { tracker.dismissNotice(notice.id) }
                    .padding(24)
                    .id(notice.id)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: tracker.notice?.id)
        .task(id: tracker.notice?.id) {
            guard let id = tracker.notice?.id else { return }
            do { try await Task.sleep(nanoseconds: 4_000_000_000) } catch { return }
            tracker.dismissNotice(id)
        }
        .font(.system(size: 14))
        .tint(accent)
        .onAppear {
            updateVisibility()
            if CommandLine.arguments.contains("--settings") { section = "Settings" }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { _ in
            updateVisibility()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMiniaturizeNotification)) { _ in
            updateVisibility()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didDeminiaturizeNotification)) { _ in
            updateVisibility()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
            // Evaluate after the window has actually closed.
            DispatchQueue.main.async { updateVisibility() }
        }
        .task(id: windowVisible && (tracker.isTracking || !focus.active.isEmpty)) {
            guard windowVisible, tracker.isTracking || !focus.active.isEmpty else { return }
            while !Task.isCancelled {
                now = Date()
                tracker.refreshLiveDisplay()
                do { try await Task.sleep(nanoseconds: 1_000_000_000) }
                catch { return }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            tracker.refreshPermissions()
            tracker.refreshEnvironment()
        }

    }

    private func updateVisibility() {
        windowVisible = NSApplication.shared.windows.contains {
            $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 11) {
                Image(systemName: "waveform.path.ecg").font(.title2).foregroundStyle(accent)
                Text("Trackvite").font(.system(size: 25, weight: .semibold, design: .rounded))
            }.padding(.top, 20)
            VStack(spacing: 6) {
                ForEach(sections, id: \.0) { item in
                    Button { section = item.0 } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.1).frame(width: 18)
                            Text(item.0)
                            Spacer()
                        }
                        .padding(12)
                        .foregroundStyle(section == item.0 ? accent : .secondary)
                        .background(section == item.0 ? accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(ClickTargetButtonStyle())
                }
            }
            Spacer()

        }.padding(20).frame(width: 205).background(Color(red: 0.08, green: 0.09, blue: 0.10))
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(Locale(identifier: "en_GB"))).uppercased())
                    .font(.system(size: 10, weight: .medium)).tracking(1.4).foregroundStyle(.secondary)
                Text(section)
                    .font(.system(size: 29, weight: .semibold))
            }
            Spacer()

        }
    }

    private var screenTime: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tracker.isTracking ? "Tracking is on" : "Tracking is paused").font(.headline)
                    Text("Your app and website usage, separate from tasks.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { tracker.toggle() } label: {
                    Label(tracker.isTracking ? "Pause tracking" : "Start tracking", systemImage: tracker.isTracking ? "stop.fill" : "play.fill")
                        .padding(.horizontal, 14).padding(.vertical, 10).foregroundStyle(.black).background(accent, in: Capsule())
                }.buttonStyle(ClickTargetButtonStyle())
            }
            ScreenTimeLimitsView(limits: tracker.limits, tracking: tracker.isTracking)
            activity
        }
    }

    private var activity: some View {
        panel {
            title("Activity", subtitle: "App and website usage")
            DisclosureGroup("Summary") {
                HStack(spacing: 14) {
                    metric("ACTIVE", value: duration(tracker.activeSeconds), icon: "timer", note: "Excluding idle time")
                    metric("SWITCHES", value: "\(tracker.switches)", icon: "arrow.left.arrow.right", note: "Between apps")
                    metric("IDLE", value: duration(tracker.idleSeconds), icon: "moon", note: "No input for 60 seconds")
                }.padding(.vertical, 12)
            }.font(.callout)
            if tracker.applicationActivity.isEmpty && tracker.websites.isEmpty { empty("Start tracking to see your activity", icon: "clock") }
            ForEach(tracker.applicationActivity) { app in
                HStack(spacing: 18) {
                    ApplicationIcon(bundleID: app.id, name: app.name)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(app.name).fontWeight(.medium)
                            if tracker.isTracking && app.id == tracker.currentBundleID {
                                Text("NOW").font(.system(size: 9, weight: .bold)).foregroundStyle(accent)
                            }
                        }
                        Text("Active: \(elapsed(app.active)) · Idle: \(elapsed(app.idle))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(elapsed(app.total)).monospacedDigit().fontWeight(.medium)
                }.padding(.vertical, 10)
                Divider().opacity(0.5)
            }
            Divider().padding(.vertical, 10)
            title("Websites", subtitle: "Visited pages and time spent")
            
            if tracker.websites.isEmpty {
                HStack {
                    Text("Open a website in your connected browser.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Browser settings") { section = "Settings" }.font(.caption)
                }
            }
            ForEach(tracker.websites) { site in
                HStack {
                    WebsiteIcon(domain: site.page.domain)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(site.page.title).lineLimit(1)
                        Text(site.page.domain).font(.caption).foregroundStyle(.secondary)

                    }
                    if tracker.isTracking && tracker.currentPage?.id == site.id {
                        Text("NOW").font(.system(size: 9, weight: .bold)).foregroundStyle(accent)
                    }
                    Spacer()
                    Text(elapsed(site.seconds)).monospacedDigit()
                }.padding(.vertical, 8)
            }
        }
    }

    private func elapsed(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        if total >= 3600 { return "\(total / 3600)h \((total / 60) % 60)m \(total % 60)s" }
        if total >= 60 { return "\(total / 60)m \(total % 60)s" }
        return "\(total)s"
    }

    private func metric(_ label: String, value: String, icon: String, note: String) -> some View {
        panel {
            HStack { Text(label).font(.system(size: 10, weight: .bold)).tracking(1); Spacer(); Image(systemName: icon).foregroundStyle(accent) }.foregroundStyle(.secondary)
            Text(value).font(.system(size: 32, weight: .medium, design: .rounded)).padding(.vertical, 5)
            Text(note).font(.system(size: 10)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }

    private func title(_ name: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(name).font(.system(size: 16, weight: .semibold))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }.padding(.bottom, 10)
    }

    private func empty(_ text: String, icon: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 28)).foregroundStyle(accent.opacity(0.5))
            Text(text).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, minHeight: 190)
    }

    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13, content: content)
            .padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.045)))
    }

    private func duration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : minutes > 0 ? "\(minutes)m" : "\(Int(seconds))s"
    }
}
