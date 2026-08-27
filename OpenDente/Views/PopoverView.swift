import SwiftUI

/// The daily control surface. Battery state leads, intervention follows, and
/// technical detail stays available without competing for attention.
struct PopoverView: View {
    @ObservedObject var battery = BatteryService.shared
    @ObservedObject var charging = ChargingManager.shared
    @ObservedObject var settings = AppSettings.shared
    @Environment(\.openSettings) private var openSettingsAction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var displayPercentage: Int {
        battery.batteryState.effectivePercentage(useHardware: settings.useHardwareBatteryPercentage)
    }

    private var adapterVisible: Bool {
        Self.adapterVisible(isPluggedIn: battery.batteryState.isPluggedIn, mode: charging.mode)
    }

    static func adapterVisible(isPluggedIn: Bool, mode: ChargingMode) -> Bool {
        isPluggedIn || mode == .discharging
    }

    private var canDischarge: Bool {
        Self.canDischarge(
            isPluggedIn: battery.batteryState.isPluggedIn,
            percentage: displayPercentage,
            chargeLimit: settings.chargeLimit,
            isHelperInstalled: charging.isHelperInstalled,
            chargingAPI: charging.chargingAPI
        )
    }

    static func canDischarge(
        isPluggedIn: Bool,
        percentage: Int,
        chargeLimit: Int,
        isHelperInstalled: Bool,
        chargingAPI: SMCChargingAPI
    ) -> Bool {
        // chargingAPI is advisory — helper may know the keys when the app cannot read them.
        _ = chargingAPI
        return isPluggedIn && percentage > chargeLimit && isHelperInstalled
    }

    var body: some View {
        VStack(spacing: 0) {
            hero
                .padding(.horizontal, JustRightTheme.Space.x6)
                .padding(.top, JustRightTheme.Space.x4)
                .padding(.bottom, JustRightTheme.Space.x6)

            JRDivider()

            ScrollView {
                VStack(alignment: .leading, spacing: JustRightTheme.Space.x6) {
                    // Show blockers first — otherwise Charge/Discharge look broken
                    // with no explanation above the fold.
                    notices

                    if let phase = charging.calibrationPhase {
                        calibrationStatus(phase)
                    } else {
                        controls
                    }

                    if settings.showPowerFlow {
                        VStack(alignment: .leading, spacing: JustRightTheme.Space.x3) {
                            sectionLabel("Power flow")
                            PowerFlowView(battery: battery.batteryState, mode: charging.mode)
                        }
                    }

                    details
                }
                .padding(.horizontal, JustRightTheme.Space.x6)
                .padding(.vertical, JustRightTheme.Space.x6)
            }

            JRDivider()
            footer
                .padding(.horizontal, JustRightTheme.Space.x6)
                .padding(.vertical, JustRightTheme.Space.x3)
        }
        .frame(width: 392, height: 600)
        .justRightCanvas()
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: JustRightTheme.Space.x4) {
            HStack(spacing: JustRightTheme.Space.x2) {
                JustRightMark(size: 22)
                Text("just-right")
                    .font(JustRightTheme.labelFont)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: openSettings) {
                    Image(systemName: "slider.horizontal.3")
                        .accessibilityLabel("Open settings")
                }
                .buttonStyle(JRIconButtonStyle())
                .help("Open settings")
            }

            HStack(alignment: .lastTextBaseline, spacing: JustRightTheme.Space.x4) {
                VStack(alignment: .leading, spacing: JustRightTheme.Space.x1) {
                    Text("\(displayPercentage)%")
                        .font(JustRightTheme.displayFont)
                        .contentTransition(.numericText())
                    HStack(spacing: JustRightTheme.Space.x2) {
                        Image(systemName: statusIcon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(statusText)
                            .font(JustRightTheme.bodyFont)
                    }
                    .foregroundStyle(statusTone)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: JustRightTheme.Space.x1) {
                    Text("Charge limit")
                        .font(JustRightTheme.labelFont)
                        .foregroundStyle(.secondary)
                    Text("\(settings.chargeLimit)%")
                        .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                }
            }

            batteryTrack
        }
    }

    private var batteryTrack: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let percentage = CGFloat(displayPercentage.clamped(to: 0...100)) / 100
            let limit = CGFloat(settings.chargeLimit) / 100
            let sailingLower = CGFloat(settings.sailingLowerBound) / 100

            ZStack(alignment: .leading) {
                Capsule().fill(JustRightTheme.subtleFill)
                Capsule()
                    .fill(batteryColor)
                    .frame(width: max(0, width * percentage))

                if settings.sailingModeEnabled {
                    Circle()
                        .fill(JustRightTheme.line)
                        .frame(width: 6, height: 6)
                        .offset(x: width * sailingLower - 3)
                        .accessibilityHidden(true)
                }

                Circle()
                    .fill(JustRightTheme.canvas)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.primary.opacity(0.72), lineWidth: 2))
                    .offset(x: width * limit - 6)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery \(displayPercentage) percent. Charge limit \(settings.chargeLimit) percent.")
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: JustRightTheme.Space.x4) {
            sectionLabel("Charge control")
            primaryActions

            VStack(alignment: .leading, spacing: JustRightTheme.Space.x2) {
                HStack {
                    Text("Set the limit")
                        .font(JustRightTheme.labelFont)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(settings.chargeLimit)%")
                        .font(JustRightTheme.dataFont)
                }
                HStack(spacing: JustRightTheme.Space.x2) {
                    ForEach([60, 70, 80, 90, 100], id: \.self) { value in
                        LimitPresetButton(value: value, selection: chargeLimitBinding)
                    }
                }
            }
        }
    }

    /// Explicit binding — `$settings.chargeLimit` on a non-`@Published`
    /// computed property is unreliable in some SwiftUI/popover hosts.
    private var chargeLimitBinding: Binding<Int> {
        Binding(
            get: { settings.chargeLimit },
            set: { settings.chargeLimit = $0 }
        )
    }

    private var canChargeToFull: Bool {
        battery.batteryState.isPluggedIn && charging.isHelperInstalled
    }

    private var chargeToFullDisabledReason: String? {
        if !charging.isHelperInstalled {
            return HelperInstaller.controlBlockedDetail
        }
        if !battery.batteryState.isPluggedIn {
            return "Plug in a charger to charge to 100%."
        }
        return nil
    }

    private var dischargeDisabledReason: String? {
        if !charging.isHelperInstalled {
            return HelperInstaller.controlBlockedDetail
        }
        if !battery.batteryState.isPluggedIn {
            return "Plug in a charger to discharge to the limit."
        }
        if displayPercentage <= settings.chargeLimit {
            return "Battery is already at or below the \(settings.chargeLimit)% limit."
        }
        return nil
    }

    private var primaryActions: some View {
        HStack(spacing: JustRightTheme.Space.x2) {
            if charging.mode == .topUp {
                Button("Cancel top up", role: .destructive) {
                    charging.cancelTopUp()
                }
                .buttonStyle(JRSecondaryButtonStyle())
            } else if charging.mode == .discharging {
                Button("Stop discharging", role: .destructive) {
                    charging.stopDischarge()
                }
                .buttonStyle(JRSecondaryButtonStyle())
            } else {
                Button {
                    charging.startTopUp()
                } label: {
                    Label("Charge to 100%", systemImage: "arrow.up.to.line")
                }
                .buttonStyle(JRPrimaryButtonStyle())
                .disabled(!canChargeToFull)
                .help(chargeToFullDisabledReason ?? "Temporarily charge to 100%")

                Button {
                    charging.startDischarge()
                } label: {
                    Label("Discharge to limit", systemImage: "arrow.down.to.line")
                }
                .buttonStyle(JRSecondaryButtonStyle())
                .disabled(!canDischarge)
                .help(dischargeDisabledReason ?? "Drain the battery down to the charge limit")
            }
            Spacer()
        }
    }

    private func calibrationStatus(_ phase: CalibrationPhase) -> some View {
        VStack(alignment: .leading, spacing: JustRightTheme.Space.x3) {
            HStack {
                VStack(alignment: .leading, spacing: JustRightTheme.Space.x1) {
                    sectionLabel("Battery calibration")
                    Text(phase.displayName)
                        .font(JustRightTheme.bodyFont)
                }
                Spacer()
                Text("\(phase.stepNumber) of 4")
                    .font(JustRightTheme.dataFont)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(phase.stepNumber), total: 4)
            Button("Cancel calibration", role: .destructive) {
                charging.cancelCalibration()
            }
            .buttonStyle(JRSecondaryButtonStyle(compact: true))
        }
    }

    @ViewBuilder
    private var notices: some View {
        if !charging.isHelperInstalled {
            JRNotice(
                title: HelperInstaller.controlBlockedTitle,
                detail: HelperInstaller.controlBlockedDetail,
                tone: .warning,
                actionTitle: helperNoticeActionTitle,
                action: helperNoticeAction
            )
        }

        if charging.systemChargeLimitConflict {
            JRNotice(
                title: "macOS is limiting the charge",
                detail: "Turn off Charge Limit in Battery settings so just-right can charge the battery.",
                tone: .warning,
                actionTitle: "Open Battery settings",
                action: openBatterySettings
            )
        }
    }

    private var details: some View {
        let state = battery.batteryState
        let rows = settings.popoverDetailItems.compactMap { detailValue(for: $0, state: state) }

        return VStack(alignment: .leading, spacing: JustRightTheme.Space.x3) {
            sectionLabel("Battery details")
            VStack(spacing: JustRightTheme.Space.x2) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    JRMetricRow(label: row.label, value: row.value)
                }
            }

            if !battery.smcAvailable {
                JRNotice(
                    title: "Detailed measurements are unavailable",
                    detail: "just-right cannot read the System Management Controller on this Mac.",
                    tone: .warning
                )
            }
        }
    }

    private func detailValue(for item: PopoverDetailItem, state: BatteryState) -> (label: String, value: String)? {
        switch item {
        case .temperature:
            guard let temp = state.temperature else { return nil }
            return ("Temperature", TemperatureDisplay.format(temp))
        case .batteryHealth:
            guard let health = state.healthPercentage else { return nil }
            return ("Battery health", String(format: "%.1f%%", health))
        case .cycleCount:
            guard let cycles = state.cycleCount else { return nil }
            return ("Cycle count", "\(cycles)")
        case .timeRemaining:
            return charging.mode.timeRemainingDisplay(
                chargeLimit: settings.chargeLimit,
                percentage: displayPercentage,
                timeToFull: state.timeToFull,
                timeToEmpty: state.timeToEmpty
            )
        case .systemPower:
            guard let power = state.systemPower, power > 0 else { return nil }
            return ("System power", String(format: "%.1f W", power))
        case .adapterPower:
            guard adapterVisible, let power = state.adapterPower, power > 0 else { return nil }
            if let maximum = state.adapterInfo?.watts, maximum > 0 {
                return ("Adapter power", String(format: "%.1f W of %d W", power, maximum))
            }
            return ("Adapter power", String(format: "%.1f W", power))
        case .adapterName:
            guard adapterVisible, let info = state.adapterInfo else { return nil }
            return ("Adapter", info.name)
        case .adapterManufacturer:
            guard adapterVisible, let manufacturer = state.adapterInfo?.manufacturer else { return nil }
            return ("Manufacturer", manufacturer)
        case .adapterModel:
            guard adapterVisible, let model = state.adapterInfo?.model else { return nil }
            return ("Model", model)
        case .adapterSerial:
            guard adapterVisible, let serial = state.adapterInfo?.serial else { return nil }
            return ("Serial number", serial)
        case .adapterVoltage:
            guard adapterVisible, let info = state.adapterInfo else { return nil }
            return ("Adapter voltage", String(format: "%.2f V", info.voltage))
        case .adapterCurrent:
            guard adapterVisible, let info = state.adapterInfo else { return nil }
            return ("Adapter current", String(format: "%.3f A", info.current))
        case .voltage:
            guard let voltage = state.voltage else { return nil }
            return ("Battery voltage", String(format: "%.2f V", voltage))
        case .amperage:
            guard let amperage = state.amperage else { return nil }
            return ("Battery current", String(format: "%.3f A", amperage))
        case .currentCapacity:
            guard let current = state.currentCapacity, let maximum = state.maxCapacity else { return nil }
            return ("Capacity", "\(current) / \(maximum) mAh")
        case .designCapacity:
            guard let design = state.designCapacity else { return nil }
            return ("Design capacity", "\(design) mAh")
        case .batteryPower:
            guard let power = state.batteryPower else { return nil }
            return ("Battery power", String(format: "%.1f W", power))
        case .notChargingReason:
            guard let reason = state.notChargingReason, reason != 0 else { return nil }
            return ("Not charging reason", String(format: "0x%016llX", reason))
        }
    }

    private var footer: some View {
        HStack {
            Text("Charging stops at \(settings.chargeLimit)%")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit just-right") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(JustRightTheme.labelFont)
            .foregroundStyle(.secondary)
    }

    private var statusText: String {
        if charging.systemChargeLimitConflict { return "macOS charge limit is active" }
        switch charging.mode {
        case .charging: return "Charging to \(settings.chargeLimit)%"
        case .paused: return "Holding at \(settings.chargeLimit)%"
        case .sailing: return "Waiting until \(settings.sailingLowerBound)%"
        case .discharging: return "Discharging to \(settings.chargeLimit)%"
        case .topUp: return "Charging to 100%"
        case .calibrating: return "Calibration in progress"
        case .heatProtection: return "Paused to reduce heat"
        case .onBattery: return "Running on battery"
        case .idle: return "Reading battery state"
        }
    }

    private var statusIcon: String {
        charging.systemChargeLimitConflict ? "exclamationmark.triangle.fill" : charging.mode.statusBarIcon
    }

    private var statusTone: Color {
        if charging.systemChargeLimitConflict || charging.mode == .heatProtection {
            return JustRightTheme.warning
        }
        return .secondary
    }

    private var batteryColor: Color {
        switch charging.mode {
        case .heatProtection: JustRightTheme.critical
        case .discharging: JustRightTheme.warning
        default: displayPercentage <= 20 ? JustRightTheme.critical : JustRightTheme.accent
        }
    }

    private var needsHelperApproval: Bool {
        HelperInstaller.status == .requiresApproval
    }

    private var helperNoticeActionTitle: String {
        switch HelperInstaller.status {
        case .requiresApproval: return "Open System Settings"
        case .notFound where HelperInstaller.installedOutsideApplications: return "Open Applications"
        default: return "Open settings"
        }
    }

    private var helperNoticeAction: () -> Void {
        switch HelperInstaller.status {
        case .requiresApproval:
            return HelperInstaller.openSystemSettings
        case .notFound where HelperInstaller.installedOutsideApplications:
            return openApplicationsFolder
        default:
            return openSettings
        }
    }

    private func openSettings() {
        openSettingsAction()
        NSApp.activate()
    }

    private func openApplicationsFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
        NSApp.activate()
    }

    private func openBatterySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
