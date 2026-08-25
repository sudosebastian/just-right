import SwiftUI

@main
struct JustRightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for updates...") {
                    MacSparkleUpdater.shared.checkForUpdates()
                }
                .disabled(!MacSparkleUpdater.shared.isAvailable)
            }
        }
    }
}
