import SwiftUI
import ServiceManagement
import UserNotifications
import os.log

/// Settings window with tabbed interface
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gear") }

            ChargingTab()
                .tabItem { Label("Charging", systemImage: "bolt.fill") }

            AutomationTab()
                .tabItem { Label("Automation", systemImage: "calendar.badge.clock") }

            NotificationsTab()
                .tabItem { Label("Notifications", systemImage: "bell") }

            StatusBarTab()
                .tabItem { Label("Status Bar", systemImage: "menubar.rectangle") }

            PopoverItemsTab()
                .tabItem { Label("Popover", systemImage: "list.bullet") }

            BatteryInfoTab()
                .tabItem { Label("Battery", systemImage: "battery.100percent") }
        }
        .tint(JustRightTheme.accent)
        .frame(width: 560)
        .frame(minHeight: 520)
    }
}

// MARK: - General Tab

struct GeneralTab: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var charging = ChargingManager.shared

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            }

            Section {
                LabeledContent("Version") {
                    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
                    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
                    Text("\(version) (\(build))")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Button("Check for Updates…") {
                    MacSparkleUpdater.shared.checkForUpdates()
                }
                .disabled(!MacSparkleUpdater.shared.isAvailable)
            }

            Section("Privileged Helper") {
                LabeledContent("Status") {
                    Text(HelperInstaller.statusDescription)
                        .foregroundStyle(charging.isHelperInstalled ? .green : .orange)
                }

                if !charging.isHelperInstalled {
                    helperActions

                    Text("The helper daemon is required for charging control. It runs as root to write SMC keys.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var helperActions: some View {
        let status = HelperInstaller.status
        if status == .requiresApproval {
            Button("Open System Settings") {
                HelperInstaller.openSystemSettings()
            }
            Text("Toggle just-right ON in Login Items to approve the helper.")
                .font(.caption)
                .foregroundStyle(.orange)
        } else {
            Button("Install Helper") {
                if HelperInstaller.register() {
                    charging.connectToHelper()
                }
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Logger(subsystem: "com.opendente.app", category: "Settings").error("Failed to set launch at login: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Notifications Tab

struct NotificationsTab: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Toggle("Enable Notifications", isOn: $settings.showNotifications)
            }

            Section("Events") {
                Toggle("Charge Limit Reached", isOn: $settings.notifyChargeLimitReached)
                Toggle("Top Up Complete (100%)", isOn: $settings.notifyTopUpComplete)
                Toggle("Heat Protection Active", isOn: $settings.notifyHeatProtection)
                Toggle("Discharge Complete", isOn: $settings.notifyDischargeComplete)
            }
            .disabled(!settings.showNotifications)

            #if DEBUG
            Section("Test") {
                Button("Send Test Notification") {
                    sendTestNotification()
                }
            }
            #endif
        }
        .formStyle(.grouped)
    }

    #if DEBUG
    private func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "just-right test"
        content.body = "Notifications are working!"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "com.opendente.test.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
    #endif
}

// MARK: - Charging Tab

struct ChargingTab: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var charging = ChargingManager.shared

    var body: some View {
        Form {
            Section("Charge limit") {
                HStack {
                    Text("Limit")
                    Slider(
                        value: Binding(
                            get: { Double(settings.chargeLimit) },
                            set: { settings.chargeLimit = Int(($0 / 5).rounded() * 5) }
                        ),
                        in: 20...100
                    )
                    Text("\(settings.chargeLimit)%")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 45, alignment: .trailing)
                }

                HStack(spacing: 8) {
                    Text("Presets")
                        .foregroundStyle(.secondary)
                    Spacer()
                    ForEach([60, 70, 80, 90, 100], id: \.self) { value in
                        LimitPresetButton(value: value, selection: $settings.chargeLimit)
                    }
                }
            }

            Section("Sailing mode") {
                Toggle("Enable sailing mode", isOn: $settings.sailingModeEnabled)

                if settings.sailingModeEnabled {
                    HStack {
                        Text("Range")
                        Slider(
                            value: Binding(
                                get: { Double(settings.sailingRange) },
                                set: { settings.sailingRange = Int($0.rounded()) }
                            ),
                            in: 2...25
                        )
                        Text("\(settings.sailingRange)%")
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 35, alignment: .trailing)
                    }
                    Text("Won't recharge until battery drops to \(settings.sailingLowerBound)%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Heat protection") {
                Toggle("Enable heat protection", isOn: $settings.heatProtectionEnabled)

                if settings.heatProtectionEnabled {
                    HStack {
                        Text("Maximum temperature")
                        Slider(
                            value: Binding(
                                get: { TemperatureDisplay.toDisplay(settings.heatProtectionTemp) },
                                set: {
                                    let step = TemperatureDisplay.sliderStep
                                    let snapped = ($0 / step).rounded() * step
                                    settings.heatProtectionTemp = TemperatureDisplay.toCelsius(snapped)
                                }
                            ),
                            in: TemperatureDisplay.sliderRange
                        )
                        Text(TemperatureDisplay.format(settings.heatProtectionTemp, fractionDigits: 0))
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 50, alignment: .trailing)
                    }
                }
            }

            Section("Other") {
                Toggle("Automatic discharge", isOn: $settings.automaticDischarge)
                Toggle("Control MagSafe LED", isOn: $settings.controlMagSafeLED)
                if settings.controlMagSafeLED {
                    Toggle("Turn off LED when not charging", isOn: $settings.magSafeLEDOffWhenInactive)
                        .padding(.leading, 16)
                    Text("Off when limit reached/sailing, orange when charging. Otherwise green/orange.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 16)
                } else {
                    Text("Orange when charging, green when limit reached. Requires MagSafe.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Stop charging when sleeping", isOn: $settings.stopChargingWhenSleeping)
                Text("Inhibits charging before sleep so the battery stays at its current level.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Keep awake until charge limit", isOn: $settings.disableSleepUntilChargeLimit)
                Text("Keeps Mac awake while charging or discharging toward the limit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Use hardware battery percentage", isOn: $settings.useHardwareBatteryPercentage)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Automation Tab

struct AutomationTab: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var charging = ChargingManager.shared

    private let calendar = Calendar.current

    private var scheduleTime: Binding<Date> {
        Binding(
            get: {
                var components = calendar.dateComponents([.year, .month, .day], from: Date())
                components.hour = settings.scheduledTopUpHour
                components.minute = settings.scheduledTopUpMinute
                return calendar.date(from: components) ?? Date()
            },
            set: { date in
                settings.scheduledTopUpHour = calendar.component(.hour, from: date)
                settings.scheduledTopUpMinute = calendar.component(.minute, from: date)
            }
        )
    }

    private var nextTopUp: Date? {
        ChargeSchedule.nextOccurrence(
            weekdays: settings.scheduledTopUpWeekdays,
            hour: settings.scheduledTopUpHour,
            minute: settings.scheduledTopUpMinute
        )
    }

    var body: some View {
        Form {
            Section("Scheduled top up") {
                Toggle("Charge to 100% on a schedule", isOn: $settings.scheduledTopUpEnabled)

                DatePicker("Start time", selection: scheduleTime, displayedComponents: .hourAndMinute)
                    .disabled(!settings.scheduledTopUpEnabled)

                HStack(spacing: 8) {
                    ForEach(1...7, id: \.self) { weekday in
                        weekdayButton(weekday)
                    }
                }
                .disabled(!settings.scheduledTopUpEnabled)

                if settings.scheduledTopUpWeekdays.isEmpty {
                    Text("Choose at least one day.")
                        .font(.caption)
                        .foregroundStyle(JustRightTheme.warning)
                } else if settings.scheduledTopUpEnabled, let nextTopUp {
                    Text("Next top up: \(nextTopUp.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("just-right starts within 15 minutes of the set time. The Mac must be awake and connected to power.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Battery calibration") {
                if let phase = charging.calibrationPhase {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(phase.displayName)
                                .fontWeight(.medium)
                            Spacer()
                            Text("Step \(phase.stepNumber) of 4")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        ProgressView(value: Double(phase.stepNumber), total: 4)

                        Button("Cancel calibration", role: .destructive) {
                            charging.cancelCalibration()
                        }
                    }
                } else {
                    Button("Start calibration") {
                        charging.startCalibration()
                    }
                    .disabled(!charging.isHelperInstalled || charging.chargingAPI == .unknown)
                }

                Text("Calibration charges to 100%, holds for one hour, discharges to 15%, then recharges to 100%. It can take several hours and keeps the Mac awake while running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func weekdayButton(_ weekday: Int) -> some View {
        let selected = settings.scheduledTopUpWeekdays.contains(weekday)
        let symbol = calendar.veryShortWeekdaySymbols[weekday - 1]

        return Button(symbol) {
            var days = settings.scheduledTopUpWeekdays
            if selected {
                days.remove(weekday)
            } else {
                days.insert(weekday)
            }
            settings.scheduledTopUpWeekdays = days
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(selected ? JustRightTheme.accent : .secondary)
        .accessibilityLabel("\(calendar.weekdaySymbols[weekday - 1]), \(selected ? "selected" : "not selected")")
    }
}

// MARK: - Status Bar Tab

struct StatusBarTab: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var battery = BatteryService.shared
    @ObservedObject var charging = ChargingManager.shared

    var body: some View {
        Form {
            Section("Show in Status Bar") {
                Toggle("Battery Percentage", isOn: $settings.statusBarShowPercentage)
                Toggle("Temperature", isOn: $settings.statusBarShowTemperature)
                Toggle("Power Usage", isOn: $settings.statusBarShowPower)
                Toggle("Charging Mode Icon", isOn: $settings.statusBarShowMode)
            }

            Section {
                Text("Preview:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Image(systemName: statusBarIcon)
                        .font(.system(size: 15))
                    if !statusBarPreview.isEmpty {
                        Text(statusBarPreview)
                            .font(.system(size: 13, design: .monospaced))
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }
        }
        .formStyle(.grouped)
    }

    private var statusBarIcon: String {
        let state = battery.batteryState
        let pct = state.effectivePercentage(useHardware: settings.useHardwareBatteryPercentage)
        return settings.statusBarShowMode
            ? charging.mode.batteryIconName(percentage: pct, isCharging: state.isCharging)
            : ChargingMode.idle.batteryIconName(percentage: pct, isCharging: false)
    }

    private var statusBarPreview: String {
        let state = battery.batteryState
        let pct = state.effectivePercentage(useHardware: settings.useHardwareBatteryPercentage)
        return state.statusBarText(
            effectivePercentage: pct,
            showPercentage: settings.statusBarShowPercentage,
            showTemperature: settings.statusBarShowTemperature,
            showPower: settings.statusBarShowPower
        )
    }
}

// MARK: - Popover Items Tab

struct PopoverItemsTab: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var enabledItems: [PopoverDetailItem] = []
    @State private var disabledItems: [PopoverDetailItem] = []

    var body: some View {
        VStack(spacing: 0) {
            Text("Drag to reorder. Toggle to show/hide.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)

            List {
                Section {
                    Toggle("Show Power Flow", isOn: $settings.showPowerFlow)
                }

                Section("Visible") {
                    ForEach(enabledItems) { item in
                        PopoverItemRow(item: item, isEnabled: true) {
                            disableItem(item)
                        }
                    }
                    .onMove { from, to in
                        enabledItems.move(fromOffsets: from, toOffset: to)
                        save()
                    }
                }

                Section("Hidden") {
                    ForEach(disabledItems) { item in
                        PopoverItemRow(item: item, isEnabled: false) {
                            enableItem(item)
                        }
                    }
                }
            }
        }
        .onAppear { load() }
    }

    private func load() {
        enabledItems = settings.popoverDetailItems
        let enabledSet = Set(enabledItems.map(\.rawValue))
        disabledItems = PopoverDetailItem.allCases.filter { !enabledSet.contains($0.rawValue) }
    }

    private func save() {
        settings.popoverDetailItems = enabledItems
    }

    private func disableItem(_ item: PopoverDetailItem) {
        enabledItems.removeAll { $0 == item }
        disabledItems.append(item)
        save()
    }

    private func enableItem(_ item: PopoverDetailItem) {
        disabledItems.removeAll { $0 == item }
        enabledItems.append(item)
        save()
    }
}

struct PopoverItemRow: View {
    let item: PopoverDetailItem
    let isEnabled: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 12))
                .foregroundStyle(isEnabled ? .primary : .secondary)
                .frame(width: 18)

            Text(item.displayName)
                .foregroundStyle(isEnabled ? .primary : .secondary)

            Spacer()

            Button(action: onToggle) {
                Image(systemName: isEnabled ? "eye.fill" : "eye.slash")
                    .font(.system(size: 12))
                    .foregroundStyle(isEnabled ? .blue : .secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Battery Info Tab

struct BatteryInfoTab: View {
    @ObservedObject var battery = BatteryService.shared
    @ObservedObject var charging = ChargingManager.shared

    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        let state = battery.batteryState

        Form {
            Section("Battery") {
                infoRow("macOS Percentage", value: "\(state.percentage)%")
                validatedRow("Hardware SoC", raw: state.hardwarePercentage, format: { "\($0)%" })
                if let current = state.currentCapacity, let max = state.maxCapacity {
                    validatedRow("Capacity", value: "\(current) / \(max) mAh",
                                 warn: max < 500 || max > 20000 || current < 0 || current > max * 11 / 10)
                }
                validatedRow("Design Capacity", raw: state.designCapacity, format: { "\($0) mAh" },
                             warn: { $0 < 500 || $0 > 20000 })
                if let health = state.healthPercentage {
                    validatedRow("Health", value: String(format: "%.1f%%", health),
                                 warn: health < 0 || health > 120)
                }
                validatedRow("Cycle Count", raw: state.cycleCount, format: { "\($0)" },
                             warn: { $0 < 0 || $0 >= 10000 })
                validatedRow("Temperature", raw: state.temperature,
                             format: { TemperatureDisplay.format($0) },
                             warn: { $0 < -20 || $0 > 100 })
            }

            Section("Battery Power") {
                infoRow("Source", value: state.powerSource)
                validatedRow("Battery Voltage", raw: state.voltage,
                             format: { String(format: "%.2f V", $0) },
                             warn: { $0 < 1 || $0 > 30 })
                validatedRow("Battery Current", raw: state.amperage,
                             format: { String(format: "%.3f A", $0) },
                             warn: { abs($0) > 10 })
                validatedRow("Battery Power", raw: state.batteryPower,
                             format: { String(format: "%.1f W", $0) },
                             warn: { abs($0) > 200 })
            }

            Section("System Power") {
                validatedRow("System Power", raw: state.systemPower,
                             format: { String(format: "%.1f W", $0) },
                             warn: { $0 < 0 || $0 > 200 })
                validatedRow("Adapter Power", raw: state.adapterPower,
                             format: { String(format: "%.1f W", $0) },
                             warn: { $0 < 0 || $0 > 200 })
            }

            if PopoverView.adapterVisible(isPluggedIn: state.isPluggedIn, mode: charging.mode), let adapter = state.adapterInfo {
                Section("Adapter") {
                    infoRow("Name", value: adapter.name)
                    if let desc = adapter.description {
                        infoRow("Description", value: desc)
                    }
                    if let mfr = adapter.manufacturer {
                        infoRow("Manufacturer", value: mfr)
                    }
                    if let model = adapter.model {
                        infoRow("Model", value: model)
                    }
                    infoRow("Wattage", value: "\(adapter.watts) W")
                    validatedRow("Voltage", raw: adapter.voltage,
                                 format: { String(format: "%.2f V", $0) },
                                 warn: { $0 < 1 || $0 > 30 })
                    validatedRow("Current", raw: adapter.current,
                                 format: { String(format: "%.3f A", $0) },
                                 warn: { abs($0) > 10 })
                    if !adapter.usbPDProfiles.isEmpty {
                        infoRow("Protocol", value: "USB-PD")
                    }
                    if let serial = adapter.serial {
                        infoRow("Serial", value: serial)
                    }
                    if let firmware = adapter.firmware {
                        infoRow("Firmware", value: firmware)
                    }
                    if adapter.isWireless {
                        infoRow("Wireless", value: "Yes")
                    }
                }

                if !adapter.usbPDProfiles.isEmpty {
                    Section("USB-PD Profiles") {
                        ForEach(Array(adapter.usbPDProfiles.enumerated()), id: \.offset) { index, profile in
                            HStack {
                                Text(String(format: "%.0fV \u{00D7} %.2fA (%dW)",
                                            profile.voltage, profile.current, profile.watts))
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                                if index == adapter.activeProfileIndex {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }

                if let reason = state.notChargingReason, reason != 0 {
                    Section {
                        infoRow("Not Charging Reason", value: String(format: "0x%016llX", reason))
                    }
                }
            }

            Section("Control") {
                infoRow("Mode", value: charging.mode.displayName)
                infoRow("Charging API", value: chargingAPIName)
                if settings.controlMagSafeLED {
                    infoRow("MagSafe LED", value: ledColorName)
                }
                infoRow("SMC Available", value: battery.smcAvailable ? "Yes" : "No")
                if let version = charging.helperVersion {
                    infoRow("Helper Version", value: version)
                }
            }

            Section {
                Button("Export Diagnostic Report...") {
                    DiagnosticExporter.exportWithSavePanel()
                }
                Text("Exports system info, current state, settings, and recent logs as a text file for troubleshooting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var chargingAPIName: String {
        switch charging.chargingAPI {
        case .legacy: return "Legacy (CH0B/CH0C)"
        case .tahoe:  return "Tahoe (CHTE/CHIE)"
        case .unknown: return "Not detected"
        }
    }

    private var ledColorName: String {
        switch charging.lastLEDColor {
        case HelperConstants.ledAuto:   return "Auto"
        case HelperConstants.ledOff:    return "Off"
        case HelperConstants.ledGreen:  return "Green"
        case HelperConstants.ledOrange: return "Orange"
        default: return charging.lastLEDColor.map { String(format: "0x%02X", $0) } ?? "–"
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        LabeledContent(label) {
            Text(value)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    /// Show a value with warning if out of expected range, or "–" if unavailable
    private func validatedRow<T>(_ label: String, raw: T?, format: (T) -> String, warn: ((T) -> Bool)? = nil) -> some View {
        LabeledContent(label) {
            if let val = raw {
                let isWarning = warn?(val) ?? false
                Text(format(val))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(isWarning ? .orange : .primary)
                    .textSelection(.enabled)
            } else {
                Text("–")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Overload for pre-formatted string values
    private func validatedRow(_ label: String, value: String, warn: Bool) -> some View {
        LabeledContent(label) {
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(warn ? .orange : .primary)
                .textSelection(.enabled)
        }
    }
}
