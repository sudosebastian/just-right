import SwiftUI

@main
struct OpenDenteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    MacSparkleUpdater.shared.checkForUpdates()
                }
                .disabled(!MacSparkleUpdater.shared.isAvailable)
            }
        }
    }
}
