#if os(macOS)
import AppKit
import SnapgridCore
import UserNotifications

/// Posts "Snapgrid X is available" once per version, with an Install and Restart button.
@MainActor
final class UpdateNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let lastNotifiedKey = "lastNotifiedUpdate"
    private nonisolated static let category = "update", installAction = "install"

    var onInstall: () -> Void = {}
    var onOpen: () -> Void = {}

    /// Notifications need a bundle; `snapgrid run` from a terminal has none.
    private var isAvailable: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    func start() {
        guard isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let install = UNNotificationAction(identifier: Self.installAction, title: "Install and Restart")
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: [install],
                                                                 intentIdentifiers: [])])
    }

    func notify(_ release: Release, current: AppVersion, userInitiated: Bool, autoInstall: Bool) {
        let defaults = UserDefaults.standard
        guard isAvailable, UpdatePolicy.shouldNotify(about: release.version,
                                                     lastNotified: defaults.string(forKey: Self.lastNotifiedKey),
                                                     userInitiated: userInitiated) else { return }
        defaults.set(release.version.description, forKey: Self.lastNotifiedKey)
        let content = UNMutableNotificationContent()
        content.title = "Snapgrid \(release.version) is available"
        content.body = autoInstall
            ? "It installs once your Mac has been idle for \(Int(UpdatePolicy.idleBeforeInstall / 60)) minutes."
            : "You have \(current). Click to see what's new."
        content.categoryIdentifier = Self.category
        let request = UNNotificationRequest(identifier: "update-\(release.version)", content: content, trigger: nil)
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert])) == true else { return }
            try? await center.add(request)
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let install = response.actionIdentifier == Self.installAction
        DispatchQueue.main.async {
            MainActor.assumeIsolated { install ? self.onInstall() : self.onOpen() }
        }
        completionHandler()
    }

    /// Show the banner even if a Snapgrid window happens to be in front.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}
#endif
