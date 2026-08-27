import Foundation
import os.log

private let log = Logger(subsystem: "com.opendente.app", category: "HelperClient")

/// XPC client that communicates with the privileged helper daemon.
/// Not @MainActor — XPC callbacks arrive on background threads.
/// Reachability updates are dispatched to main.
final class HelperClient: @unchecked Sendable {

    static let shared = HelperClient()

    private var connection: NSXPCConnection?
    private var heartbeatTimer: Timer?
    private let lock = NSLock()
    private var isIntentionalDisconnect = false
    private var reconnectAttempts = 0
    private static let maxReconnectAttempts = 5
    private static let reconnectDelays: [TimeInterval] = [1, 2, 5, 10, 30]

    /// True only after a successful XPC reply (version/heartbeat/command).
    /// SMAppService can report `.enabled` while Background Items still blocks the daemon.
    private(set) var isReachable = false

    /// Called when the helper process restarts (crash/interruption) or after
    /// successful reconnection. ChargingManager uses this to resync charging state.
    var onHelperRestarted: (() -> Void)?

    /// Called on the main queue whenever live XPC reachability changes.
    var onReachabilityChanged: ((Bool) -> Void)?

    // MARK: - Connection

    /// Establish XPC connection to the helper daemon.
    /// Safe to call multiple times — disconnects existing connection first.
    /// Pass `resetBackoff: false` for automatic reconnect so attempt counting continues.
    @MainActor
    func connect(resetBackoff: Bool = true) {
        // Disconnect existing connection to avoid leaking XPC connections
        lock.lock()
        let existing = connection
        connection = nil
        isIntentionalDisconnect = false
        if resetBackoff {
            reconnectAttempts = 0
        }
        lock.unlock()
        if existing != nil {
            stopHeartbeat()
            existing?.invalidate()
        }
        setReachable(false)

        let conn = NSXPCConnection(
            machServiceName: HelperConstants.machServiceName,
            options: .privileged
        )
        conn.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)

        conn.invalidationHandler = { [weak self] in
            guard let self else { return }
            log.notice("XPC connection invalidated")
            self.lock.lock()
            self.connection = nil
            let intentional = self.isIntentionalDisconnect
            self.lock.unlock()
            self.setReachable(false)

            guard !intentional else { return }

            // Connection permanently lost — attempt reconnection with backoff.
            Task { @MainActor in
                self.stopHeartbeat()
                self.scheduleReconnect()
            }
        }

        conn.interruptionHandler = { [weak self] in
            guard let self else { return }
            log.warning("XPC connection interrupted — helper crashed, will auto-reconnect")
            self.setReachable(false)
            Task { @MainActor in
                self.onHelperRestarted?()
            }
        }

        conn.resume()
        lock.lock()
        connection = conn
        lock.unlock()
        startHeartbeat()
        log.notice("Opening XPC connection to helper")

        // Probe immediately — "Connected" only means the socket opened, not that
        // launchd started a reachable daemon.
        probeReachability()
    }

    /// Disconnect from the helper (intentional — suppresses auto-reconnect)
    @MainActor
    func disconnect() {
        stopHeartbeat()
        lock.lock()
        isIntentionalDisconnect = true
        let conn = connection
        connection = nil
        lock.unlock()
        conn?.invalidate()
        setReachable(false)
        log.info("Disconnected from helper")
    }

    // MARK: - Auto-Reconnect

    @MainActor
    private func scheduleReconnect() {
        guard reconnectAttempts < Self.maxReconnectAttempts else {
            log.notice("XPC reconnect failed after \(Self.maxReconnectAttempts, privacy: .public) attempts — helper may need reinstallation or Background Items approval")
            setReachable(false)
            return
        }

        let delay = Self.reconnectDelays[min(reconnectAttempts, Self.reconnectDelays.count - 1)]
        reconnectAttempts += 1
        log.info("Scheduling XPC reconnect \(self.reconnectAttempts, privacy: .public)/\(Self.maxReconnectAttempts, privacy: .public) in \(delay, privacy: .public)s")

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }

            self.lock.lock()
            let needsReconnect = self.connection == nil && !self.isIntentionalDisconnect
            self.lock.unlock()

            guard needsReconnect else { return }

            log.info("XPC reconnect: attempting...")
            self.connect(resetBackoff: false)
            self.onHelperRestarted?()
        }
    }

    // MARK: - Heartbeat

    @MainActor
    private func startHeartbeat() {
        stopHeartbeat()
        heartbeatTimer = Timer.scheduledTimer(
            withTimeInterval: HelperConstants.heartbeatInterval,
            repeats: true
        ) { [weak self] _ in
            self?.sendHeartbeat()
        }
    }

    @MainActor
    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    func sendHeartbeat() {
        withProxy(onUnavailable: { [weak self] _, _ in
            self?.setReachable(false)
        }) { helper in
            helper.heartbeat { [weak self] success in
                if success {
                    self?.setReachable(true)
                } else {
                    log.warning("Heartbeat failed")
                    self?.setReachable(false)
                }
            }
        }
    }

    private func probeReachability() {
        withProxy(onUnavailable: { [weak self] _, _ in
            self?.setReachable(false)
        }) { helper in
            helper.getVersion { [weak self] version in
                log.notice("Helper reachable — version \(version, privacy: .public)")
                self?.setReachable(true)
            }
        }
    }

    private func setReachable(_ reachable: Bool) {
        lock.lock()
        let changed = isReachable != reachable
        isReachable = reachable
        if reachable {
            reconnectAttempts = 0
        }
        lock.unlock()
        guard changed else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onReachabilityChanged?(reachable)
        }
    }

    // MARK: - Protocol Methods

    func enableCharging(completion: (@Sendable (Bool, String?) -> Void)? = nil) {
        withProxy(onUnavailable: { [weak self] success, error in
            self?.setReachable(false)
            if let completion { DispatchQueue.main.async { completion(success, error) } }
        }) { helper in
            helper.enableCharging { [weak self] success, error in
                if success { self?.setReachable(true) }
                if let error {
                    log.error("enableCharging failed: \(error, privacy: .public)")
                }
                if let completion {
                    DispatchQueue.main.async { completion(success, error) }
                }
            }
        }
    }

    func inhibitCharging(completion: (@Sendable (Bool, String?) -> Void)? = nil) {
        withProxy(onUnavailable: { [weak self] success, error in
            self?.setReachable(false)
            if let completion { DispatchQueue.main.async { completion(success, error) } }
        }) { helper in
            helper.inhibitCharging { [weak self] success, error in
                if success { self?.setReachable(true) }
                if let error {
                    log.error("inhibitCharging failed: \(error, privacy: .public)")
                }
                if let completion {
                    DispatchQueue.main.async { completion(success, error) }
                }
            }
        }
    }

    func forceDischarge(enable: Bool, completion: (@Sendable (Bool, String?) -> Void)? = nil) {
        withProxy(onUnavailable: { [weak self] success, error in
            self?.setReachable(false)
            if let completion { DispatchQueue.main.async { completion(success, error) } }
        }) { helper in
            helper.forceDischarge(enable: enable) { [weak self] success, error in
                if success { self?.setReachable(true) }
                if let error {
                    log.error("forceDischarge failed: \(error, privacy: .public)")
                }
                if let completion {
                    DispatchQueue.main.async { completion(success, error) }
                }
            }
        }
    }

    func resetToDefaults(completion: (@Sendable (Bool, String?) -> Void)? = nil) {
        withProxy(onUnavailable: { [weak self] success, error in
            self?.setReachable(false)
            if let completion { DispatchQueue.main.async { completion(success, error) } }
        }) { helper in
            helper.resetToDefaults { [weak self] success, error in
                if success { self?.setReachable(true) }
                if let error {
                    log.error("resetToDefaults failed: \(error, privacy: .public)")
                }
                if let completion {
                    DispatchQueue.main.async { completion(success, error) }
                }
            }
        }
    }

    func suspendWatchdog() {
        withProxy { helper in
            helper.suspendWatchdog { success in
                if !success {
                    log.warning("suspendWatchdog failed")
                }
            }
        }
    }

    func getVersion(completion: @escaping @Sendable (String) -> Void) {
        withProxy(onUnavailable: { [weak self] _, _ in
            self?.setReachable(false)
        }) { helper in
            helper.getVersion { [weak self] version in
                self?.setReachable(true)
                DispatchQueue.main.async { completion(version) }
            }
        }
    }

    func getChargingAPI(completion: @escaping @Sendable (String) -> Void) {
        withProxy(onUnavailable: { [weak self] _, _ in
            self?.setReachable(false)
        }) { helper in
            helper.getChargingAPI { [weak self] api in
                self?.setReachable(true)
                DispatchQueue.main.async { completion(api) }
            }
        }
    }

    func syncSleepSettings(stopChargingWhenSleeping: Bool, sleepLEDColor: UInt8) {
        withProxy { helper in
            helper.syncSleepSettings(stopChargingWhenSleeping: stopChargingWhenSleeping, sleepLEDColor: sleepLEDColor) { success in
                if !success {
                    log.warning("syncSleepSettings failed")
                }
            }
        }
    }

    func setMagSafeLED(color: UInt8, completion: (@Sendable (Bool, String?) -> Void)? = nil) {
        withProxy(onUnavailable: { success, error in
            if let completion { DispatchQueue.main.async { completion(success, error) } }
        }) { helper in
            helper.setMagSafeLED(color: color) { success, error in
                if let error {
                    log.debug("setMagSafeLED failed: \(error, privacy: .public)")
                }
                if let completion {
                    DispatchQueue.main.async { completion(success, error) }
                }
            }
        }
    }

    /// Synchronous reset with timeout — for use during app termination
    nonisolated func resetToDefaultsSync(timeout: TimeInterval = 2.0) {
        let semaphore = DispatchSemaphore(value: 0)
        // onUnavailable must signal inline — termination can run on the main
        // queue, so hopping to main here would deadlock the wait below.
        withProxy(onUnavailable: { _, _ in semaphore.signal() }) { helper in
            helper.resetToDefaults { _, _ in
                semaphore.signal()
            }
        }
        let result = semaphore.wait(timeout: .now() + timeout)
        if result == .timedOut {
            log.warning("resetToDefaultsSync timed out after \(timeout, privacy: .public)s — helper may not have reset")
        }
    }

    // MARK: - Private

    /// Run `block` with a live helper proxy. If there is no XPC connection,
    /// `onUnavailable` is invoked synchronously so sync callers (termination)
    /// can complete without deadlocking on a main-queue hop.
    private func withProxy(
        onUnavailable: (@Sendable (Bool, String?) -> Void)? = nil,
        block: @escaping (HelperProtocol) -> Void
    ) {
        lock.lock()
        let conn = connection
        lock.unlock()

        // No connection — caller must call connect() first via connectToHelper()
        guard let conn else {
            log.error("XPC unavailable: no helper connection")
            onUnavailable?(false, "Not connected to helper")
            return
        }

        let helper = conn.remoteObjectProxyWithErrorHandler { [weak self] error in
            log.error("XPC proxy error: \(error.localizedDescription, privacy: .public)")
            self?.setReachable(false)
        }

        guard let proxy = helper as? HelperProtocol else {
            log.error("Failed to get HelperProtocol proxy")
            onUnavailable?(false, "Failed to get helper proxy")
            return
        }

        block(proxy)
    }
}
