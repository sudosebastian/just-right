import AppKit
import Foundation
import Sparkle

/// Owns Sparkle's lifecycle so update behavior stays out of SwiftUI views.
@MainActor
final class MacSparkleUpdater {
    static let shared = MacSparkleUpdater()

    /// A Debug or forked build can use this value to disable updates safely.
    static let publicKeyPlaceholder = "PLACEHOLDER_SPARKLE_PUBLIC_ED25519_KEY"

    private static let automaticCheckInterval: TimeInterval = 24 * 60 * 60

    private let updaterController: SPUStandardUpdaterController
    private var isStarted = false

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Whether the app has enough trustworthy configuration to expose update actions.
    var isAvailable: Bool { hasUsableConfiguration }

    func start() {
        guard !isStarted else { return }
        guard hasUsableConfiguration else {
            NSLog("OpenDente: Sparkle not started because its feed or public key is missing.")
            return
        }

        let updater = updaterController.updater
        updater.updateCheckInterval = Self.automaticCheckInterval
        updater.automaticallyChecksForUpdates = true
        updaterController.startUpdater()
        isStarted = true

        let shouldCatchUp = updater.lastUpdateCheckDate
            .map { Date().timeIntervalSince($0) >= Self.automaticCheckInterval } ?? true
        if shouldCatchUp {
            updater.checkForUpdatesInBackground()
        }
    }

    func checkForUpdates() {
        guard isStarted else {
            NSLog("OpenDente: Check for Updates ignored because Sparkle is not configured.")
            return
        }
        updaterController.checkForUpdates(nil)
    }

    private var hasUsableConfiguration: Bool {
        guard
            let feed = infoString("SUFeedURL"),
            let url = URL(string: feed),
            url.scheme == "https",
            url.host != nil
        else {
            return false
        }

        guard
            let key = infoString("SUPublicEDKey"),
            key != Self.publicKeyPlaceholder,
            Data(base64Encoded: key)?.count == 32
        else {
            return false
        }

        return true
    }

    private func infoString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
