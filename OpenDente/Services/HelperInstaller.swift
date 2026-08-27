import Foundation
import ServiceManagement
import os.log

private let log = Logger(subsystem: "com.opendente.app", category: "HelperInstaller")

/// Manages registration of the privileged helper daemon via SMAppService.
/// Uses the modern SMAppService.daemon() API (macOS 13+), no SMJobBless needed.
@MainActor
enum HelperInstaller {

    private static var service: SMAppService {
        SMAppService.daemon(plistName: HelperConstants.launchdPlistName)
    }

    /// Current registration status
    static var status: SMAppService.Status {
        service.status
    }

    /// Whether the helper is registered and enabled
    static var isRegistered: Bool {
        service.status == .enabled
    }

    /// Register the helper daemon. Returns true if registration succeeded.
    /// When status is `.requiresApproval`, register() can't help — the user must
    /// toggle the helper ON in System Settings > General > Login Items.
    @discardableResult
    static func register() -> Bool {
        let currentStatus = service.status

        if currentStatus == .requiresApproval {
            log.info("Helper requires approval — opening System Settings")
            openSystemSettings()
            return false
        }

        log.notice("Helper status before register: \(String(describing: currentStatus), privacy: .public)")
        do {
            try service.register()
            log.notice("Helper daemon registered successfully (status now: \(String(describing: service.status), privacy: .public))")
            return service.status == .enabled
        } catch {
            log.error("Failed to register helper daemon: \(error, privacy: .public)")
            return false
        }
    }

    /// Unregister the helper daemon
    static func unregister() {
        do {
            try service.unregister()
            log.info("Helper daemon unregistered")
        } catch {
            log.error("Failed to unregister helper daemon: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Open System Settings to the Login Items pane where the user can toggle the helper
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Human-readable status description
    static var statusDescription: String {
        switch service.status {
        case .enabled:          return "Enabled"
        case .notRegistered:    return "Not installed"
        case .requiresApproval: return "Needs approval"
        case .notFound:         return installedOutsideApplications
            ? "Move the app to Applications"
            : "Missing from the app"
        @unknown default:       return "Unknown"
        }
    }

    /// SMAppService often reports `.notFound` when the app is launched from a
    /// non-standard location (external volume, downloads, build folder).
    static var installedOutsideApplications: Bool {
        let path = Bundle.main.bundlePath
        return !path.hasPrefix("/Applications/")
            && service.status == .notFound
    }

    /// Short guidance for the popover when charging controls cannot run.
    static var controlBlockedTitle: String {
        switch service.status {
        case .requiresApproval: return "Approve the helper"
        case .notRegistered:    return "Install the helper"
        case .notFound:         return installedOutsideApplications
            ? "Move just-right to Applications"
            : "Helper is missing"
        case .enabled:          return "Helper ready"
        @unknown default:       return "Helper unavailable"
        }
    }

    static var controlBlockedDetail: String {
        switch service.status {
        case .requiresApproval:
            return "Turn on just-right under Allow in the Background so charging controls can run."
        case .notRegistered:
            return "Charging controls need the privileged helper."
        case .notFound:
            return installedOutsideApplications
                ? "macOS only registers the helper when just-right lives in Applications."
                : "This build is missing the privileged helper."
        case .enabled:
            return ""
        @unknown default:
            return "Charging controls need the privileged helper."
        }
    }
}
