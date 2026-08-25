import SwiftUI

/// Main popover content shown when clicking the status bar icon
struct PopoverView: View {
    @ObservedObject var battery = BatteryService.shared
    @ObservedObject var charging = ChargingManager.shared
    @ObservedObject var settings = AppSettings.shared
    @Environment(\.openSettings) private var openSettingsAction

    private var displayPercentage: Int {
        battery.batteryState.effectivePercentage(useHardware: settings.useHardwareBatteryPercentage)
    }

    private var adapterVisible: Bool {
        Self.adapterVisible(isPluggedIn: battery.batteryState.isPluggedIn, mode: charging.mode)
    }

    /// Adapter details show when charger is connected — including during force discharge
    /// where isPluggedIn may be false (IOKit reports battery source) but charger is physically present.
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

    /// Pure function for testability
    static func canDischarge(isPluggedIn: Bool, percentage: Int, chargeLimit: Int, isHelperInstalled: Bool, chargingAPI: SMCChargingAPI) -> Bool {
        isPluggedIn && percentage > chargeLimit && isHelperInstalled && chargingAPI != .unknown
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)

            batteryBar
                .padding(.horizontal, 24)

            if let phase = charging.calibrationPhase {
                calibrationStatus(phase)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
            } else {
                primaryActions
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                limitPresets
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }

            if settings.showPowerFlow {
                PowerFlowView(battery: battery.batteryState, mode: charging.mode)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
            }

            if !charging.isHelperInstalled {
                helperWarning
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }

            if charging.systemChargeLimitConflict {
                systemLimitWarning
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }

            Divider()
                .padding(.top, 16)

            detailsGrid
                .padding(.horizontal, 24)
                .padding(.vertical, 16)

            Divider()

            bottomBar
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
        }
        .tint(JustRightTheme.accent)
        .frame(width: 360)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(displayPercentage)%")
                    .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())

                Label(
                    charging.systemChargeLimitConflict ? "System limit active" : charging.mode.displayName,
                    systemImage: charging.systemChargeLimitConflict
                        ? "exclamationmark.triangle.fill"
                        : charging.mode.statusBarIcon
                )
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(charging.systemChargeLimitConflict ? JustRightTheme.warning : .secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("Charge limit")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("\(settings.chargeLimit)%")
                    .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
            }

            Button(action: { openSettings() }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open settings")
        }
    }

    // MARK: - Battery Bar

    private var batteryBar: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let percentage = CGFloat(displayPercentage) / 100.0
            let limitPosition = CGFloat(settings.chargeLimit) / 100.0
            let sailingLower = CGFloat(settings.sailingLowerBound) / 100.0

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(JustRightTheme.subtleFill)

                Capsule()
                    .fill(batteryColor)
                    .frame(width: width * percentage)

                if settings.sailingModeEnabled {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 1)
                        .offset(x: width * sailingLower)
                }

                Rectangle()
                    .fill(Color.primary.opacity(0.6))
                    .frame(width: 2)
                    .offset(x: width * limitPosition - 1)

            }
        }
        .frame(height: 10)
    }

    @ViewBuilder
    private var modeIcon: some View {
        switch charging.mode {
        case .charging, .topUp:
            Image(systemName: "bolt.fill")
        case .discharging:
            Image(systemName: "bolt.fill")
                .rotationEffect(.degrees(180))
        case .sailing:
            Image(systemName: "wind")
        case .heatProtection:
            Image(systemName: "thermometer.sun.fill")
        default:
            EmptyView()
        }
    }

    private var batteryColor: Color {
        switch charging.mode {
        case .charging, .topUp:
            return JustRightTheme.accent
        case .discharging:
            return JustRightTheme.warning
        case .heatProtection:
            return JustRightTheme.critical
        case .sailing:
            return JustRightTheme.accent.opacity(0.72)
        default:
            if displayPercentage <= 20 {
                return JustRightTheme.critical
            }
            return JustRightTheme.accent
        }
    }

    // MARK: - Primary Controls

    private var primaryActions: some View {
        HStack(spacing: 8) {
            if charging.mode == .topUp {
                Button("Cancel top up", role: .destructive) {
                    charging.cancelTopUp()
                }
                .buttonStyle(.bordered)
            } else if charging.mode == .discharging {
                Button("Stop discharge", role: .destructive) {
                    charging.stopDischarge()
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    charging.startTopUp()
                } label: {
                    Label("Top up", systemImage: "arrow.up.to.line")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!battery.batteryState.isPluggedIn || !charging.isHelperInstalled || charging.chargingAPI == .unknown)

                Button {
                    charging.startDischarge()
                } label: {
                    Label("Discharge", systemImage: "arrow.down.to.line")
                }
                .buttonStyle(.bordered)
                .disabled(!canDischarge)
            }

            Spacer()
        }
        .controlSize(.small)
    }

    private var limitPresets: some View {
        HStack(spacing: 8) {
            Text("Limit")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            ForEach([60, 70, 80, 90, 100], id: \.self) { value in
                LimitPresetButton(value: value, selection: $settings.chargeLimit)
            }
        }
    }

    private func calibrationStatus(_ phase: CalibrationPhase) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(phase.displayName)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(phase.stepNumber)/4")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(phase.stepNumber), total: 4)

            Button("Cancel calibration", role: .destructive) {
                charging.cancelCalibration()
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
        }
    }

    // MARK: - Details Grid

    private var detailsGrid: some View {
        let state = battery.batteryState
        let items = settings.popoverDetailItems

        return VStack(spacing: 6) {
            ForEach(items) { item in
                if let row = detailValue(for: item, state: state) {
                    detailRow(row.label, value: row.value)
                }
            }

            if !battery.smcAvailable {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10))
                    Text("SMC not available — detailed data unavailable")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.orange)
                .padding(.top, 4)
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
            return ("Battery Health", String(format: "%.1f%%", health))
        case .cycleCount:
            guard let cycles = state.cycleCount else { return nil }
            return ("Cycle Count", "\(cycles)")
        case .timeRemaining:
            return charging.mode.timeRemainingDisplay(
                chargeLimit: settings.chargeLimit,
                percentage: displayPercentage,
                timeToFull: state.timeToFull,
                timeToEmpty: state.timeToEmpty
            )
        case .systemPower:
            guard let power = state.systemPower, power > 0 else { return nil }
            return ("System Power", String(format: "%.1f W", power))
        case .adapterPower:
            guard adapterVisible, let power = state.adapterPower, power > 0 else { return nil }
            if let max = state.adapterInfo?.watts, max > 0 {
                return ("Adapter Power", String(format: "%.1f W of %d W", power, max))
            }
            return ("Adapter Power", String(format: "%.1f W", power))
        case .adapterName:
            guard adapterVisible, let info = state.adapterInfo else { return nil }
            return ("Adapter", info.name)
        case .adapterManufacturer:
            guard adapterVisible, let mfr = state.adapterInfo?.manufacturer else { return nil }
            return ("Manufacturer", mfr)
        case .adapterModel:
            guard adapterVisible, let model = state.adapterInfo?.model else { return nil }
            return ("Model", model)
        case .adapterSerial:
            guard adapterVisible, let serial = state.adapterInfo?.serial else { return nil }
            return ("Serial", serial)
        case .adapterVoltage:
            guard adapterVisible, let info = state.adapterInfo else { return nil }
            return ("Adapter Voltage", String(format: "%.2f V", info.voltage))
        case .adapterCurrent:
            guard adapterVisible, let info = state.adapterInfo else { return nil }
            return ("Adapter Current", String(format: "%.3f A", info.current))
        case .voltage:
            guard let voltage = state.voltage else { return nil }
            return ("Battery Voltage", String(format: "%.2f V", voltage))
        case .amperage:
            guard let amperage = state.amperage else { return nil }
            return ("Battery Current", String(format: "%.3f A", amperage))
        case .currentCapacity:
            guard let current = state.currentCapacity, let max = state.maxCapacity else { return nil }
            return ("Capacity", "\(current) / \(max) mAh")
        case .designCapacity:
            guard let design = state.designCapacity else { return nil }
            return ("Design Capacity", "\(design) mAh")
        case .batteryPower:
            guard let power = state.batteryPower else { return nil }
            return ("Battery Power", String(format: "%.1f W", power))
        case .notChargingReason:
            guard let reason = state.notChargingReason, reason != 0 else { return nil }
            return ("Not Charging", String(format: "0x%016llX", reason))
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Text("just-right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helper Warning

    private var needsHelperApproval: Bool {
        HelperInstaller.status == .requiresApproval
    }

    private var helperWarning: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
            Text(needsHelperApproval
                 ? "Helper needs approval in System Settings"
                 : "Helper not installed — charging control unavailable")
                .font(.system(size: 10))
            Spacer()
            if needsHelperApproval {
                Button("Approve") {
                    HelperInstaller.openSystemSettings()
                }
                .font(.system(size: 10))
                .buttonStyle(.bordered)
                .controlSize(.mini)
            } else {
                Button("Install") {
                    openSettings()
                }
                .font(.system(size: 10))
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .foregroundStyle(.orange)
    }

    // MARK: - System Limit Warning

    private var systemLimitWarning: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
            Text("macOS Charge Limit is preventing charging")
                .font(.system(size: 10))
                .lineLimit(2)
            Spacer()
            Button("Open") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!)
            }
            .font(.system(size: 10))
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .foregroundStyle(.orange)
    }

    // MARK: - Actions

    private func openSettings() {
        openSettingsAction()
        NSApp.activate()
    }
}
