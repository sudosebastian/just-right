import AppKit
import Combine
import SwiftUI
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var lastIconName: String?
    #if DEBUG
    private var uiAuditWindow: NSWindow?
    #endif

    private let battery = BatteryService.shared
    private let charging = ChargingManager.shared
    private let settings = AppSettings.shared

    // MARK: - App Lifecycle

    /// True when the app is launched as a test host by Xcode.
    /// Tests load into the app process for symbol access, but we skip real services
    /// to avoid SMC commands and UserDefaults pollution from the test host.
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
    }

    private static var isRunningUIAudit: Bool {
        #if DEBUG
        CommandLine.arguments.contains("--ui-audit")
        #else
        false
        #endif
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        guard !Self.isRunningTests else { return }

        #if DEBUG
        if Self.isRunningUIAudit {
            NSApp.setActivationPolicy(.regular)
            settings.configureForUIAudit()
            configureUIAuditState()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showUIAuditWindow()
            }
            return
        }
        #endif

        if CommandLine.arguments.contains("--repair-helper") {
            NSLog("[just-right] --repair-helper: re-registering SMAppService daemon")
            _ = HelperInstaller.repair()
            NSLog("[just-right] Helper status after repair: \(HelperInstaller.statusDescription)")
            // Continue launching so the user can approve Background Items if needed.
        }

        MacSparkleUpdater.shared.start()
        battery.start()
        charging.start()

        setupStatusItem()
        setupPopover()
        setupEventMonitor()
        setupSleepWakeNotifications()

        // Check helper status and prompt for registration if needed
        checkHelperStatus()

        // Update status bar reactively when battery state or mode changes
        battery.$batteryState
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusBarText() }
            .store(in: &cancellables)

        charging.$mode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusBarText() }
            .store(in: &cancellables)

        // Notifications
        NotificationService.shared.requestPermission()
        setupNotifications()
    }

    private func setupNotifications() {
        var previousMode: ChargingMode = charging.mode

        charging.$mode
            .receive(on: RunLoop.main)
            .sink { [weak self] newMode in
                guard let self else { return }
                switch (previousMode, newMode) {
                case (.charging, .paused), (.sailing, .paused):
                    NotificationService.shared.send(.chargeLimitReached, settings: self.settings)
                case (_, .heatProtection):
                    NotificationService.shared.send(.heatProtection, settings: self.settings)
                case (.discharging, .paused), (.discharging, .idle):
                    NotificationService.shared.send(.dischargeComplete, settings: self.settings)
                default:
                    break
                }
                if newMode == .charging || newMode == .onBattery || newMode == .discharging {
                    NotificationService.shared.clearLastEvent()
                }
                previousMode = newMode
            }
            .store(in: &cancellables)

        battery.$batteryState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                let pct = state.effectivePercentage(useHardware: self.settings.useHardwareBatteryPercentage)
                if self.charging.mode == .topUp && pct >= 100 {
                    NotificationService.shared.send(.topUpComplete, settings: self.settings)
                }
            }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        #if DEBUG
        if Self.isRunningUIAudit {
            settings.cleanUpUIAuditDefaults()
            return
        }
        #endif
        // Synchronous reset with timeout to ensure charging is re-enabled before exit
        charging.resetToDefaultsSync()
        HelperClient.shared.disconnect()
        battery.stop()
        cancellables.removeAll()
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        // Remove sleep/wake observers to avoid stale callbacks
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.action = #selector(togglePopover)
            button.target = self
            updateStatusBarText()
        }
    }

    private func updateStatusBarText() {
        guard let button = statusItem?.button else { return }

        let state = battery.batteryState
        let pct = state.effectivePercentage(useHardware: settings.useHardwareBatteryPercentage)
        button.setAccessibilityLabel("Battery \(pct) percent. \(charging.mode.displayName).")
        button.toolTip = "Battery \(pct)% · \(charging.mode.displayName)"

        let iconName = settings.statusBarShowMode
            ? charging.mode.batteryIconName(percentage: pct, isCharging: state.isCharging)
            : ChargingMode.idle.batteryIconName(percentage: pct, isCharging: false)
        if iconName != lastIconName {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Battery \(pct)%")?.withSymbolConfiguration(config)
            lastIconName = iconName
        }

        let text = state.statusBarText(
            effectivePercentage: pct,
            showPercentage: settings.statusBarShowPercentage,
            showTemperature: settings.statusBarShowTemperature,
            showPower: settings.statusBarShowPower
        )
        button.title = text.isEmpty ? "" : " " + text
    }

    // MARK: - Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 392, height: 600)
        // Semitransient keeps the popover key while clicking its buttons;
        // transient often steals the first click just to activate the window.
        popover.behavior = .semitransient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PopoverView())
    }

    func popoverDidClose(_ notification: Notification) {
        battery.popoverDidClose()
    }

    @objc private func togglePopover() {
        guard statusItem.button != nil else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover(refreshBattery: true)
        }
    }

    private func showPopover(refreshBattery: Bool) {
        guard let button = statusItem.button else { return }
        if refreshBattery {
            battery.popoverDidOpen()
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    #if DEBUG
    private func configureUIAuditState() {
        battery.configureForUIAudit(BatteryState(
            percentage: 72,
            hardwarePercentage: 71,
            isCharging: true,
            isPluggedIn: true,
            currentCapacity: 4210,
            maxCapacity: 5860,
            designCapacity: 6249,
            cycleCount: 86,
            temperature: 31.4,
            voltage: 12.1,
            amperage: 1.08,
            systemPower: 18.6,
            adapterPower: 34.2,
            adapterVoltage: 20.3,
            adapterInfo: AdapterInfo(
                name: "96W USB-C Power Adapter",
                description: "USB-C power adapter",
                manufacturer: "Apple Inc.",
                model: "0x7002",
                watts: 96,
                voltage: 20.3,
                current: 1.7,
                serial: "C4H441203C3PM0WBF",
                firmware: "01090058",
                isWireless: false,
                usbPDProfiles: [],
                activeProfileIndex: nil
            ),
            batteryPower: 13.1,
            notChargingReason: 0,
            chargerInhibitReason: 0,
            timeToEmpty: nil,
            timeToFull: 64
        ))
        charging.mode = .charging
        charging.chargingAPI = .tahoe
        charging.isHelperInstalled = true
        charging.isHelperConnected = true
    }

    private func showUIAuditWindow() {
        let showsSettings = CommandLine.arguments.contains("--ui-audit-settings")
        let size = showsSettings ? NSSize(width: 800, height: 620) : NSSize(width: 392, height: 600)
        let colorScheme: ColorScheme = CommandLine.arguments.contains("--ui-audit-dark") ? .dark : .light
        let rootView = AnyView(
            (showsSettings ? AnyView(SettingsView()) : AnyView(PopoverView()))
                .preferredColorScheme(colorScheme)
        )
        let controller = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = showsSettings ? "just-right Settings — UI Audit" : "just-right Panel — UI Audit"
        window.contentViewController = controller
        window.setContentSize(size)
        window.center()
        window.makeKeyAndOrderFront(nil)
        uiAuditWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }
    #endif

    // MARK: - Event Monitor

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let self = self, self.popover.isShown {
                self.popover.performClose(nil)
            }
        }
    }

    // MARK: - Helper

    private func checkHelperStatus() {
        let status = HelperInstaller.status
        NSLog("[just-right] Helper status: \(HelperInstaller.statusDescription) (raw: \(String(describing: status)))")

        switch status {
        case .notRegistered:
            NSLog("[just-right] Attempting to register helper daemon...")
            if HelperInstaller.register() {
                charging.connectToHelper()
            }
        case .requiresApproval:
            // Don't call register() — it always fails. User must toggle in System Settings.
            NSLog("[just-right] Helper needs approval in System Settings > Login Items")
        case .enabled:
            NSLog("[just-right] Helper is enabled")
        case .notFound:
            NSLog("[just-right] Helper binary not found in app bundle")
        @unknown default:
            break
        }

        charging.isHelperInstalled = HelperInstaller.isRegistered
        if HelperInstaller.isRegistered {
            charging.connectToHelper()
        }
        NSLog("[just-right] Helper registered: \(charging.isHelperInstalled)")
    }

    // MARK: - Sleep/Wake

    private func setupSleepWakeNotifications() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(
            self,
            selector: #selector(willSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        ws.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func willSleep(_ notification: Notification) {
        charging.handleWillSleep()
        HelperClient.shared.suspendWatchdog()
    }

    @objc private func didWake(_ notification: Notification) {
        HelperClient.shared.sendHeartbeat()
        // Refresh battery state immediately — it may have changed during sleep
        // (e.g. charger unplugged, battery drained).
        battery.update()
        // Call handleDidWake directly for immediate response — the Combine publisher
        // from battery.update() delivers on the next RunLoop iteration via .receive(on:),
        // but we need to re-evaluate NOW (e.g. resume charging if below limit).
        // The subsequent Combine-triggered evaluateState is redundant but harmless (idempotent).
        charging.handleDidWake(battery.batteryState)
    }

}
