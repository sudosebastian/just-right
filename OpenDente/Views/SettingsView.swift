import SwiftUI
import ServiceManagement
import UserNotifications
import os.log

/// Settings use stable, task-based navigation. Feature pages keep their own
/// complexity, while the shell provides one hierarchy and one visual rhythm.
struct SettingsView: View {
    @State private var destination: SettingsDestination = .general
    @FocusState private var focusedDestination: SettingsDestination?

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
                .frame(width: 184)
            Rectangle()
                .fill(JustRightTheme.line.opacity(0.7))
                .frame(width: 1)
            settingsContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 800, height: 620)
        .justRightCanvas()
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: JustRightTheme.Space.x3) {
                JustRightMark(size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("just-right")
                        .font(.system(size: 13, weight: .semibold))
                    Text(versionText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, JustRightTheme.Space.x4)
            .padding(.top, JustRightTheme.Space.x6)
            .padding(.bottom, JustRightTheme.Space.x6)

            sidebarGroup("Essentials", destinations: [.general, .charging, .automation])
            sidebarGroup("Experience", destinations: [.notifications, .menuBar, .panel])
            sidebarGroup("System", destinations: [.battery])

            Spacer()
        }
        .background(JustRightTheme.surface)
    }

    private func sidebarGroup(_ title: String, destinations: [SettingsDestination]) -> some View {
        VStack(alignment: .leading, spacing: JustRightTheme.Space.x1) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, JustRightTheme.Space.x4)
                .padding(.top, JustRightTheme.Space.x3)
                .accessibilityAddTraits(.isHeader)

            ForEach(destinations) { item in
                Button {
                    destination = item
                } label: {
                    HStack(spacing: JustRightTheme.Space.x3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 16)
                        Text(item.title)
                            .font(.system(size: 12, weight: destination == item ? .semibold : .regular))
                        Spacer()
                    }
                    .foregroundStyle(destination == item ? Color.primary : Color.secondary)
                    .padding(.horizontal, JustRightTheme.Space.x3)
                    .frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: JustRightTheme.Radius.small)
                            .fill(destination == item ? JustRightTheme.subtleFill : Color.clear)
                    )
                    .overlay {
                        if focusedDestination == item {
                            RoundedRectangle(cornerRadius: JustRightTheme.Radius.small)
                                .stroke(JustRightTheme.accent, lineWidth: 2)
                                .padding(1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable()
                .focused($focusedDestination, equals: item)
                .accessibilityHint("Press Space to open this settings page")
                .accessibilityAddTraits(destination == item ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, JustRightTheme.Space.x1)
    }

    @ViewBuilder
    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: JustRightTheme.Space.x4) {
            JRPageHeader(title: destination.title, detail: destination.detail)
                .padding(.horizontal, JustRightTheme.Space.x8)
                .padding(.top, JustRightTheme.Space.x8)

            switch destination {
            case .general: GeneralTab()
            case .charging: ChargingTab()
            case .automation: AutomationTab()
            case .notifications: NotificationsTab()
            case .menuBar: StatusBarTab()
            case .panel: PopoverItemsTab()
            case .battery: BatteryInfoTab()
            }
        }
        .background(JustRightTheme.canvas)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "v\(version) · \(build)"
    }
}

private enum SettingsDestination: String, Identifiable, CaseIterable {
    case general, charging, automation, notifications, menuBar, panel, battery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .charging: "Charge"
        case .automation: "Automation"
        case .notifications: "Notifications"
        case .menuBar: "Menu bar"
        case .panel: "Panel"
        case .battery: "Battery data"
        }
    }

    var detail: String {
        switch self {
        case .general: "Start just-right, manage its helper, and keep the app current."
        case .charging: "Set the limit and choose how just-right protects the battery."
        case .automation: "Schedule a full charge or run a battery calibration."
        case .notifications: "Choose which battery events can interrupt you."
        case .menuBar: "Choose the measurements visible beside the menu-bar icon."
        case .panel: "Choose and order the measurements in the daily control panel."
        case .battery: "Inspect measured values and export a report for troubleshooting."
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .charging: "battery.75percent"
        case .automation: "calendar.badge.clock"
        case .notifications: "bell"
        case .menuBar: "menubar.rectangle"
        case .panel: "rectangle.topthird.inset.filled"
        case .battery: "waveform.path.ecg"
        }
    }
}

// MARK: - General Tab

struct GeneralTab: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var charging = ChargingManager.shared

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
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

                Button("Check for updates...") {
                    MacSparkleUpdater.shared.checkForUpdates()
                }
                .disabled(!MacSparkleUpdater.shared.isAvailable)
            }

            Section("Privileged helper") {
                LabeledContent("Status") {
                    Text(HelperInstaller.statusDescription)
                        .foregroundStyle(charging.isHelperInstalled ? JustRightTheme.accent : JustRightTheme.warning)
                }

                if !charging.isHelperInstalled {
                    helperActions

                    Text("The helper runs with system access so it can change the charging state.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.columns)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, JustRightTheme.Space.x8)
        .padding(.bottom, JustRightTheme.Space.x6)
    }

    @ViewBuilder
    private var helperActions: some View {
        let status = HelperInstaller.status
        if status == .requiresApproval {
            Button("Open System Settings") {
                HelperInstaller.openSystemSettings()
            }
            Text("Turn on just-right under Allow in the Background.")
                .font(.caption)
                .foregroundStyle(JustRightTheme.warning)
        } else {
            Button("Install helper") {
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
                Toggle("Allow notifications", isOn: $settings.showNotifications)
            }

            Section("Events") {
                Toggle("Charge limit reached", isOn: $settings.notifyChargeLimitReached)
                Toggle("Full charge complete", isOn: $settings.notifyTopUpComplete)
                Toggle("Heat protection active", isOn: $settings.notifyHeatProtection)
                Toggle("Discharge complete", isOn: $settings.notifyDischargeComplete)
            }
            .disabled(!settings.showNotifications)

            #if DEBUG
            Section("Test") {
                Button("Send test notification") {
                    sendTestNotification()
                }
            }
            #endif
        }
        .formStyle(.columns)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, JustRightTheme.Space.x8)
        .padding(.bottom, JustRightTheme.Space.x6)
    }

    #if DEBUG
    private func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "just-right test"
        content.body = "Notifications are working."
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
                    Text("Charging resumes when the battery reaches \(settings.sailingLowerBound)%.")
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

            Section("System behavior") {
                Toggle("Automatic discharge", isOn: $settings.automaticDischarge)
                Toggle("Control MagSafe LED", isOn: $settings.controlMagSafeLED)
                if settings.controlMagSafeLED {
                    Toggle("Turn off LED when not charging", isOn: $settings.magSafeLEDOffWhenInactive)
                        .padding(.leading, 16)
                    Text("The light turns off while holding or sailing, and orange while charging.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 16)
                } else {
                    Text("The light is orange while charging and green at the limit. This setting needs MagSafe.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Stop charging when sleeping", isOn: $settings.stopChargingWhenSleeping)
                Text("Pause charging before the Mac sleeps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Keep awake until charge limit", isOn: $settings.disableSleepUntilChargeLimit)
                Text("Keep the Mac awake while it moves toward the charge limit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Use hardware battery percentage", isOn: $settings.useHardwareBatteryPercentage)
            }
        }
        .formStyle(.columns)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, JustRightTheme.Space.x8)
        .padding(.bottom, JustRightTheme.Space.x6)
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
                    Text("Next full charge: \(nextTopUp.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("The full charge starts within 15 minutes of this time. The Mac must be awake and connected to power.")
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

                Text("Calibration charges to 100%, waits for one hour, discharges to 15%, and charges to 100% again. It can take several hours and keeps the Mac awake.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.columns)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, JustRightTheme.Space.x8)
        .padding(.bottom, JustRightTheme.Space.x6)
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
            Section("Visible measurements") {
                Toggle("Battery percentage", isOn: $settings.statusBarShowPercentage)
                Toggle("Temperature", isOn: $settings.statusBarShowTemperature)
                Toggle("Power use", isOn: $settings.statusBarShowPower)
                Toggle("Charging state icon", isOn: $settings.statusBarShowMode)
            }

            Section {
                Text("Preview")
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
                    RoundedRectangle(cornerRadius: JustRightTheme.Radius.small)
                        .fill(JustRightTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: JustRightTheme.Radius.small)
                        .stroke(JustRightTheme.line, lineWidth: 1)
                )
            }
        }
        .formStyle(.columns)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, JustRightTheme.Space.x8)
        .padding(.bottom, JustRightTheme.Space.x6)
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
            Text("Drag visible measurements to reorder them. Use the eye button to show or hide a measurement.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, JustRightTheme.Space.x8)
                .padding(.bottom, JustRightTheme.Space.x3)

            List {
                Section {
                    Toggle("Show power flow", isOn: $settings.showPowerFlow)
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
            .scrollContentBackground(.hidden)
            .padding(.horizontal, JustRightTheme.Space.x6)
            .padding(.bottom, JustRightTheme.Space.x6)
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
        HStack(spacing: JustRightTheme.Space.x3) {
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
                    .foregroundStyle(isEnabled ? JustRightTheme.accent : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(isEnabled ? "Hide" : "Show") \(item.displayName)")
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
                infoRow("macOS percentage", value: "\(state.percentage)%")
                validatedRow("Hardware SoC", raw: state.hardwarePercentage, format: { "\($0)%" })
                if let current = state.currentCapacity, let max = state.maxCapacity {
                    validatedRow("Capacity", value: "\(current) / \(max) mAh",
                                 warn: max < 500 || max > 20000 || current < 0 || current > max * 11 / 10)
                }
                validatedRow("Design capacity", raw: state.designCapacity, format: { "\($0) mAh" },
                             warn: { $0 < 500 || $0 > 20000 })
                if let health = state.healthPercentage {
                    validatedRow("Health", value: String(format: "%.1f%%", health),
                                 warn: health < 0 || health > 120)
                }
                validatedRow("Cycle count", raw: state.cycleCount, format: { "\($0)" },
                             warn: { $0 < 0 || $0 >= 10000 })
                validatedRow("Temperature", raw: state.temperature,
                             format: { TemperatureDisplay.format($0) },
                             warn: { $0 < -20 || $0 > 100 })
            }

            Section("Battery power") {
                infoRow("Source", value: state.powerSource)
                validatedRow("Battery voltage", raw: state.voltage,
                             format: { String(format: "%.2f V", $0) },
                             warn: { $0 < 1 || $0 > 30 })
                validatedRow("Battery current", raw: state.amperage,
                             format: { String(format: "%.3f A", $0) },
                             warn: { abs($0) > 10 })
                validatedRow("Battery power", raw: state.batteryPower,
                             format: { String(format: "%.1f W", $0) },
                             warn: { abs($0) > 200 })
            }

            Section("System power") {
                validatedRow("System power", raw: state.systemPower,
                             format: { String(format: "%.1f W", $0) },
                             warn: { $0 < 0 || $0 > 200 })
                validatedRow("Adapter power", raw: state.adapterPower,
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
                    Section("USB-PD profiles") {
                        ForEach(Array(adapter.usbPDProfiles.enumerated()), id: \.offset) { index, profile in
                            HStack {
                                Text(String(format: "%.0fV \u{00D7} %.2fA (%dW)",
                                            profile.voltage, profile.current, profile.watts))
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                                if index == adapter.activeProfileIndex {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(JustRightTheme.accent)
                                }
                            }
                        }
                    }
                }

                if let reason = state.notChargingReason, reason != 0 {
                    Section {
                        infoRow("Not charging reason", value: String(format: "0x%016llX", reason))
                    }
                }
            }

            Section("Control") {
                infoRow("Mode", value: charging.mode.displayName)
                infoRow("Charging API", value: chargingAPIName)
                if settings.controlMagSafeLED {
                    infoRow("MagSafe LED", value: ledColorName)
                }
                infoRow("SMC available", value: battery.smcAvailable ? "Yes" : "No")
                if let version = charging.helperVersion {
                    infoRow("Helper version", value: version)
                }
            }

            Section {
                Button("Export diagnostic report...") {
                    DiagnosticExporter.exportWithSavePanel()
                }
                Text("Save system information, battery state, settings, and recent logs as a text file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.columns)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, JustRightTheme.Space.x8)
        .padding(.bottom, JustRightTheme.Space.x6)
        .frame(maxHeight: .infinity)
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
