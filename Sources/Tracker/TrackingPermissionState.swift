import AppKit
import ApplicationServices

struct TrackingPermissionState: Equatable {
    var accessibility: Bool
    var screen: Bool
    var browser: Bool
    var allowed: Bool { accessibility && screen && browser }
    static let denied = TrackingPermissionState(accessibility: false, screen: false, browser: false)
    @MainActor static func current() -> TrackingPermissionState {
        TrackingPermissionState(accessibility: AXIsProcessTrusted(), screen: CGPreflightScreenCaptureAccess(),
                                browser: BrowserAccess.trackingAccessAllowed())
    }
}
