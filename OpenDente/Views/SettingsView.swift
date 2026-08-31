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
                    focusedDestination = item
                } label: {
                    HStack(spacing: JustRightTheme.Space.x3) {
                        Capsule()
                            .fill(destination == item ? JustRightTheme.accent : Color.clear)
                            .frame(width: 3, height: 16)
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
        ScrollView {
            VStack(alignment: .leading, spacing: JustRightTheme.Space.x6) {
                JRPageHeader(title: destination.title, detail: destination.detail)

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
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, JustRightTheme.Space.x8)
            .padding(.vertical, JustRightTheme.Space.x8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        VStack(alignment: .leading, spacing: JustRightTheme.Space.x6) {
            JRSettingsSection("Application") {
                JRSettingRow("Launch at login", detail: "Start just-right automatically after you sign in.") {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .labelsHidden()
                        .onChange(of: settings.launchAtLogin) { _, newValue in
                            setLaunchAtLogin(newValue)
                        }
                }
            }

            JRSettingsSection("Updates") {
                JRSettingRow("Installed version") {
                    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
                    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
                    Text("\(version) (\(build))")
                        .font(JustRightTheme.dataFont)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Button("Check for updates...") {
                    MacSparkleUpdater.shared.checkForUpdates()
                }
                .buttonStyle(JRSecondaryButtonStyle(compact: true))
                .disabled(!MacSparkleUpdater.shared.isAvailable)
            }

            JRSettingsSection("Privileged helper", detail: "The helper changes charging state with system access.") {
                JRSettingRow("Connection status") {
                    Text(helperStatusLabel)
                        .font(JustRightTheme.dataFont)
                        .foregroundStyle(charging.isHelperConnected ? JustRightTheme.accent : JustRightTheme.warning)
                }

                if !charging.isHelperConnected {
                    helperActions

                    Text(helperStatusHint)
                        .font(JustRightTheme.bodyFont)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var helperActions: some View {
        let status = HelperInstaller.status
        if status == .requiresApproval || (status == .enabled && !charging.isHelperConnected) {
            Button("Open System Settings") {
                HelperInstaller.openSystemSettings()
            }
            Text("Turn on the OpenDente / just-right row under Allow in the Background.")
                .font(.caption)
                .foregroundStyle(JustRightTheme.warning)
            Button("Retry connection") {
                charging.connectToHelper()
            }
            Button("Repair helper") {
                if HelperInstaller.repair() {
                    charging.connectToHelper()
                }
            }
        } else if status == .notFound, HelperInstaller.installedOutsideApplications {
            Button("Open Applications") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
            }
            Text("Copy just-right into Applications, open it from there, then install the helper.")
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

    private var helperStatusLabel: String {
        if charging.isHelperConnected {
            return "Connected"
        }
        if charging.isHelperInstalled {
            return "Blocked — enable Background access"
        }
        return HelperInstaller.statusDescription
    }

    private var helperStatusHint: String {
        if charging.isHelperInstalled {
            return "The helper is registered but not reachable. Enable the OpenDente / just-right row under Allow in the Background, quit any copy outside /Applications, then tap Retry connection."
        }
        return "The helper runs with system access so it can change the charging state."
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
        VStack(alignment: .leading, spacing: JustRightTheme.Space.x6) {
            JRSettingsSection("Notifications") {
                JRSettingRow("Allow notifications", detail: "Show native alerts for selected battery events.") {
                    Toggle("", isOn: $settings.showNotifications)
                        .labelsHidden()
                }
            }

            JRSettingsSection("Events") {
                notificationRow("Charge limit reached", binding: $settings.notifyChargeLimitReached)
                notificationRow("Full charge complete", binding: $settings.notifyTopUpComplete)
                notificationRow("Heat protection active", binding: $settings.notifyHeatProtection)
                notificationRow("Discharge complete", binding: $settings.notifyDischargeComplete)
            }
            .disabled(!settings.showNotifications)

            #if DEBUG
            JRSettingsSection("Test") {
                Button("Send test notification") {
                    sendTestNotification()
                }
                .buttonStyle(JRSecondaryButtonStyle(compact: true))
            }
            #endif
        }
    }

    private func notificationRow(_ title: String, binding: Binding<Bool>) -> some View {
        JRSettingRow(title) {
            Toggle("", isOn: binding)
                .labelsHidden()
        }
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
        VStack(alignment: .leading, spacing: JustRightTheme.Space.x6) {
            JRSettingsSection("Charge limit", detail: "Charging pauses when the battery reaches this level.") {
                HStack(spacing: JustRightTheme.Space.x4) {
                    Slider(
                        value: Binding(
                            get: { Double(settings.chargeLimit) },
                            set: { settings.chargeLimit = Int(($0 / 5).rounded() * 5) }
                        ),
                        in: 20...100
                    )
                    Text("\(settings.chargeLimit)%")
                        .font(JustRightTheme.dataFont)
                        .frame(width: 45, alignment: .trailing)
                }

                VStack(alignment: .leading, spacing: JustRightTheme.Space.x2) {
                    Text("Presets")
                        .font(JustRightTheme.labelFont)
                        .foregroundStyle(.secondary)
                    HStack(spacing: JustRightTheme.Space.x2) {
                        ForEach([60, 70, 80, 90, 100], id: \.self) { value in
                            LimitPresetButton(
                                value: value,
                                selection: Binding(
                                    get: { settings.chargeLimit },
                                    set: { settings.chargeLimit = $0 }
                                )
                            )
                        }
                    }
                }
            }

            JRSettingsSection("Sailing mode", detail: "Let the battery drift below the limit before charging resumes.") {
                settingToggle("Enable sailing mode", binding: $settings.sailingModeEnabled)

                if settings.sailingModeEnabled {
                    HStack(spacing: JustRightTheme.Space.x4) {
                        Text("Resume range")
                            .font(JustRightTheme.bodyFont)
                        Slider(
                            value: Binding(
                                get: { Double(settings.sailingRange) },
                                set: { settings.sailingRange = Int($0.rounded()) }
                            ),
                            in: 2...25
                        )
                        Text("\(settings.sailingRange)%")
                            .font(JustRightTheme.dataFont)
                            .frame(width: 40, alignment: .trailing)
                    }
                    Text("Charging resumes at \(settings.sailingLowerBound)%.")
                        .font(JustRightTheme.labelFont)
                        .foregroundStyle(.secondary)
                }
            }

            JRSettingsSection("Heat protection", detail: "Pause charging when the battery becomes too warm.") {
                settingToggle("Enable heat protection", binding: $settings.heatProtectionEnabled)

                if settings.heatProtectionEnabled {
                    HStack(spacing: JustRightTheme.Space.x4) {
                        Text("Maximum temperature")
                            .font(JustRightTheme.bodyFont)
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
                            .font(JustRightTheme.dataFont)
                            .frame(width: 50, alignment: .trailing)
                    }
                }
            }

            JRSettingsSection("System behavior") {
                settingToggle("Automatic discharge", detail: "Discharge to the limit while connected to power.", binding: $settings.automaticDischarge)
                settingToggle("Control MagSafe LED", detail: "Reflect just-right’s state on the connector.", binding: $settings.controlMagSafeLED)
                if settings.controlMagSafeLED {
                    settingToggle("Turn off LED when inactive", detail: "Keep the light off while holding or sailing.", binding: $settings.magSafeLEDOffWhenInactive)
                }
                settingToggle("Stop charging during sleep", detail: "Pause charging before the Mac sleeps.", binding: $settings.stopChargingWhenSleeping)
                settingToggle("Keep awake until the limit", detail: "Prevent sleep while moving toward the charge limit.", binding: $settings.disableSleepUntilChargeLimit)
                settingToggle("Use hardware battery percentage", detail: "Prefer the battery controller’s state of charge when available.", binding: $settings.useHardwareBatteryPercentage)
            }
        }
    }

    private func settingToggle(_ title: String, detail: String? = nil, binding: Binding<Bool>) -> some View {
        JRSettingRow(title, detail: detail) {
            Toggle("", isOn: binding)
                .labelsHidden()
        }
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
        VStack(alignment: .leading, spacing: JustRightTheme.Space.x6) {
            JRSettingsSection("Scheduled top up", detail: "Charge to 100% on selected days.") {
                JRSettingRow("Enable schedule") {
                    Toggle("", isOn: $settings.scheduledTopUpEnabled).labelsHidden()
                }

                JRSettingRow("Start time") {
                    DatePicker("", selection: scheduleTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .disabled(!settings.scheduledTopUpEnabled)
                }

                HStack(spacing: JustRightTheme.Space.x2) {
                    ForEach(1...7, id: \.self) { weekday in
                        weekdayButton(weekday)
                    }
                }
                .disabled(!settings.scheduledTopUpEnabled)

                if settings.scheduledTopUpWeekdays.isEmpty {
                    Text("Choose at least one day.")
                        .font(JustRightTheme.labelFont)
                        .foregroundStyle(JustRightTheme.warning)
                } else if settings.scheduledTopUpEnabled, let nextTopUp {
                    Text("Next full charge: \(nextTopUp.formatted(date: .abbreviated, time: .shortened))")
                        .font(JustRightTheme.labelFont)
                        .foregroundStyle(.secondary)
                }

                Text("The full charge starts within 15 minutes of this time. The Mac must be awake and connected to power.")
                    .font(JustRightTheme.bodyFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            JRSettingsSection("Battery calibration", detail: "Run a complete charge and discharge cycle to recalibrate the battery gauge.") {
                if let phase = charging.calibrationPhase {
                    VStack(alignment: .leading, spacing: JustRightTheme.Space.x2) {
                        HStack {
                            Text(phase.displayName)
                                .font(JustRightTheme.bodyFont.weight(.medium))
                            Spacer()
                            Text("Step \(phase.stepNumber) of 4")
                                .font(JustRightTheme.dataFont)
                                .foregroundStyle(.secondary)
                        }

                        ProgressView(value: Double(phase.stepNumber), total: 4)

                        Button("Cancel calibration", role: .destructive) {
                            charging.cancelCalibration()
                        }
                        .buttonStyle(JRSecondaryButtonStyle(compact: true))
                    }
                } else {
                    Button("Start calibration") {
                        charging.startCalibration()
                    }
                    .buttonStyle(JRSecondaryButtonStyle(compact: true))
                    .disabled(!charging.isHelperConnected)
                }

                Text("Calibration charges to 100%, waits for one hour, discharges to 15%, and charges to 100% again. It can take several hours and keeps the Mac awake.")
                    .font(JustRightTheme.bodyFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
        .buttonStyle(.plain)
        .font(JustRightTheme.labelFont)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .frame(maxWidth: .infinity, minHeight: 30)
        .background(RoundedRectangle(cornerRadius: JustRightTheme.Radius.small).fill(selected ? JustRightTheme.accent : JustRightTheme.subtleFill))
        .accessibilityLabel("\(calendar.weekdaySymbols[weekday - 1]), \(selected ? "selected" : "not selected")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Status Bar Tab

struct StatusBarTab: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var battery = BatteryService.shared
    @ObservedObject var charging = ChargingManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: JustRightTheme.Space.x6) {
            JRSettingsSection("Visible measurements") {
                measurementRow("Battery percentage", binding: $settings.statusBarShowPercentage)
                measurementRow("Temperature", binding: $settings.statusBarShowTemperature)
                measurementRow("Power use", binding: $settings.statusBarShowPower)
                measurementRow("Charging state icon", binding: $settings.statusBarShowMode)
            }

            JRSettingsSection("Preview", detail: "This is how the item appears in the menu bar.") {
                HStack(spacing: 6) {
                    Image(systemName: statusBarIcon)
                        .font(.system(size: 15))
                    if !statusBarPreview.isEmpty {
                        Text(statusBarPreview)
                            .font(JustRightTheme.dataFont)
                    }
                }
                .padding(.horizontal, JustRightTheme.Space.x3)
                .frame(minHeight: 36)
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
    }

    private func measurementRow(_ title: String, binding: Binding<Bool>) -> some View {
        JRSettingRow(title) { Toggle("", isOn: binding).labelsHidden() }
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
        VStack(alignment: .leading, spacing: JustRightTheme.Space.x6) {
            JRSettingsSection("Power flow") {
                JRSettingRow("Show power flow", detail: "Visualize how adapter and battery power reach the Mac.") {
                    Toggle("", isOn: $settings.showPowerFlow).labelsHidden()
                }
            }

            JRSettingsSection("Visible measurements", detail: "Use the arrow buttons to set the order shown in the panel.") {
                ForEach(Array(enabledItems.enumerated()), id: \.element.id) { index, item in
                    PopoverItemRow(
                        item: item,
                        isEnabled: true,
                        moveUp: index > 0 ? { moveItem(from: index, to: index - 1) } : nil,
                        moveDown: index < enabledItems.count - 1 ? { moveItem(from: index, to: index + 1) } : nil
                    ) {
                        disableItem(item)
                    }
                }
            }

            JRSettingsSection("Hidden measurements") {
                ForEach(disabledItems) { item in
                    PopoverItemRow(item: item, isEnabled: false) { enableItem(item) }
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

    private func moveItem(from source: Int, to destination: Int) {
        guard source != destination,
              enabledItems.indices.contains(source),
              enabledItems.indices.contains(destination) else { return }
        enabledItems.swapAt(source, destination)
        save()
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
    var moveUp: (() -> Void)? = nil
    var moveDown: (() -> Void)? = nil
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

            if isEnabled {
                Button(action: { moveUp?() }) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(JRIconButtonStyle())
                .disabled(moveUp == nil)
                .accessibilityLabel("Move \(item.displayName) up")

                Button(action: { moveDown?() }) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(JRIconButtonStyle())
                .disabled(moveDown == nil)
                .accessibilityLabel("Move \(item.displayName) down")
            }

            Button(action: onToggle) {
                Image(systemName: isEnabled ? "eye.slash" : "eye")
                    .font(.system(size: 12))
                    .foregroundStyle(isEnabled ? .secondary : JustRightTheme.accent)
            }
            .buttonStyle(JRIconButtonStyle())
            .accessibilityLabel("\(isEnabled ? "Hide" : "Show") \(item.displayName)")
        }
        .frame(minHeight: 32)
    }
}

// MARK: - Battery Info Tab

struct BatteryInfoTab: View {
    @ObservedObject var battery = BatteryService.shared
    @ObservedObject var charging = ChargingManager.shared

    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        let state = battery.batteryState

        VStack(alignment: .leading, spacing: JustRightTheme.Space.x6) {
            JRSettingsSection("Battery") {
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

            JRSettingsSection("Battery power") {
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

            JRSettingsSection("System power") {
                validatedRow("System power", raw: state.systemPower,
                             format: { String(format: "%.1f W", $0) },
                             warn: { $0 < 0 || $0 > 200 })
                validatedRow("Adapter power", raw: state.adapterPower,
                             format: { String(format: "%.1f W", $0) },
                             warn: { $0 < 0 || $0 > 200 })
            }

            if PopoverView.adapterVisible(
                isPluggedIn: state.isPluggedIn,
                isAdapterConnected: state.isAdapterConnected,
                mode: charging.mode
            ), let adapter = state.adapterInfo {
                JRSettingsSection("Adapter") {
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
                    JRSettingsSection("USB-PD profiles") {
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
                    JRSettingsSection("Charging state") {
                        infoRow("Not charging reason", value: String(format: "0x%016llX", reason))
                    }
                }
            }

            JRSettingsSection("Control") {
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

            JRSettingsSection("Diagnostics", detail: "Export system information, battery state, settings, and recent logs.") {
                Button("Export diagnostic report...") {
                    DiagnosticExporter.exportWithSavePanel()
                }
                .buttonStyle(JRSecondaryButtonStyle(compact: true))
            }
        }
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
        JRValueRow(label: label, value: value)
    }

    /// Show a value with warning if out of expected range, or "–" if unavailable
    private func validatedRow<T>(_ label: String, raw: T?, format: (T) -> String, warn: ((T) -> Bool)? = nil) -> some View {
        Group {
            if let val = raw {
                JRValueRow(label: label, value: format(val), tone: (warn?(val) ?? false) ? JustRightTheme.warning : .primary)
            } else {
                JRValueRow(label: label, value: "–", tone: .secondary)
            }
        }
    }

    /// Overload for pre-formatted string values
    private func validatedRow(_ label: String, value: String, warn: Bool) -> some View {
        JRValueRow(label: label, value: value, tone: warn ? JustRightTheme.warning : .primary)
    }
}
