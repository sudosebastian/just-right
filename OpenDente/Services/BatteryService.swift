import Foundation
import Combine
import IOKit.ps
import os.log

private let log = Logger(subsystem: "com.opendente.app", category: "BatteryService")

/// Which SMC / IORegistry fields a poll needs. Background ticks stay lean; the
/// popover forces a full instrumentation read.
struct BatteryPollNeeds: Equatable {
    var temperature: Bool
    var systemPower: Bool
    var hardwarePercentage: Bool
    var adapterPower: Bool
    /// Voltage, amperage, battery power, capacity, cycles, adapter details, live VD0R/ID0R.
    var detail: Bool

    static let controlOnly = BatteryPollNeeds(
        temperature: false,
        systemPower: false,
        hardwarePercentage: false,
        adapterPower: false,
        detail: false
    )

    static let full = BatteryPollNeeds(
        temperature: true,
        systemPower: true,
        hardwarePercentage: true,
        adapterPower: true,
        detail: true
    )

    /// Derive read set from UI / control settings. Pure for tests.
    static func resolve(
        popoverOpen: Bool,
        heatProtectionEnabled: Bool,
        statusBarShowTemperature: Bool,
        statusBarShowPower: Bool,
        useHardwareBatteryPercentage: Bool,
        needsAdapterPower: Bool
    ) -> BatteryPollNeeds {
        if popoverOpen { return .full }
        return BatteryPollNeeds(
            temperature: heatProtectionEnabled || statusBarShowTemperature,
            systemPower: statusBarShowPower,
            hardwarePercentage: useHardwareBatteryPercentage,
            adapterPower: needsAdapterPower,
            detail: false
        )
    }
}

/// Monitors battery state using IOKit power source APIs + SMC for detailed data.
/// Reading does not require root.
@MainActor
final class BatteryService: ObservableObject {

    static let shared = BatteryService()

    @Published var batteryState: BatteryState = .unknown
    @Published private(set) var smcAvailable = false

    private var timer: Timer?
    private var runLoopSource: CFRunLoopSource?
    private let smc = SMCService.shared
    let settings: AppSettings
    /// Whether the popover is visible — drives full vs lean SMC reads.
    private(set) var isPopoverOpen = false
    /// Whether the first IORegistry diagnostic dump has been logged (avoid spamming every 2s)
    private var didLogIORegistryDiag = false
    /// Last logged NotChargingReason — only log when it changes
    private var lastLoggedNotChargingReason: UInt64?
    /// Whether full AdapterDetails have been logged (re-log when adapter first appears)
    private var didLogAdapterDetails = false
    /// Last logged ChargerInhibitReason — only log when it changes
    private var lastLoggedInhibitReason: UInt64?

    init(settings: AppSettings = .shared) {
        self.settings = settings
    }

    // MARK: - Lifecycle

    func start() {
        // Open SMC connection (for temperature, power, detailed data)
        do {
            try smc.open()
            smcAvailable = true
            log.notice("SMC connected successfully")
        } catch {
            log.error("SMC not available: \(error.localizedDescription, privacy: .public)")
            smcAvailable = false
        }

        // Initial read
        update()

        // Start polling
        scheduleTimer()

        // Register for power source change notifications
        registerPowerSourceNotification()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        smc.close()
    }

    /// Immediate full refresh when popover opens (don't wait for next tick)
    func popoverDidOpen() {
        isPopoverOpen = true
        update()
    }

    func popoverDidClose() {
        isPopoverOpen = false
    }

    func update() {
        let needs = currentPollNeeds()
        let previous = batteryState
        let ioKitState = readIOKitPowerSource()
        let smcState = smcAvailable ? readSMCData(needs: needs, previous: previous) : SMCData()
        let ioRegState = readIORegistryBattery(includeAdapterDetails: needs.detail)

        // Hardware SoC: B0RM/B0FC gives the raw fuel gauge percentage.
        // BRSC is "Battery Remaining State of Charge" (ui16, high byte = %).
        let hwPercent: Int? = {
            if needs.hardwarePercentage || needs.detail {
                if let rem = smcState.remainingCapacity,
                   let full = smcState.fullChargeCapacity,
                   full > 0, rem >= 0 {
                    let ratio = Double(rem) / Double(full)
                    if ratio <= 1.1 {
                        return max(0, min(100, Int((ratio * 100.0).rounded())))
                    }
                }
                if let brsc = smcState.brscPercentage { return brsc }
                // Lean tick skipped capacity keys — keep prior value
                if !needs.hardwarePercentage && !needs.detail {
                    return previous.hardwarePercentage
                }
                return nil
            }
            return previous.hardwarePercentage
        }()

        // Always build AdapterInfo from IORegistry when available on a detail read.
        // SMC VD0R/ID0R override negotiated voltage/current with live readings.
        // Carry forward when lean so closing the popover doesn't blank rows.
        let adapterInfo: AdapterInfo? = {
            guard needs.detail else { return previous.adapterInfo }
            return ioRegState.adapterInfo.map { info in
                AdapterInfo(
                    name: info.name,
                    description: info.description,
                    manufacturer: info.manufacturer,
                    model: info.model,
                    watts: info.watts,
                    voltage: smcState.adapterVoltage ?? info.voltage,
                    current: smcState.adapterCurrent ?? info.current,
                    serial: info.serial,
                    firmware: info.firmware,
                    isWireless: info.isWireless,
                    usbPDProfiles: info.usbPDProfiles,
                    activeProfileIndex: info.activeProfileIndex
                )
            }
        }()

        let state = BatteryState(
            percentage: ioKitState.percentage,
            hardwarePercentage: hwPercent,
            isCharging: ioKitState.isCharging,
            isPluggedIn: ioKitState.isPluggedIn,
            currentCapacity: smcState.remainingCapacity
                ?? smcState.fullChargeCapacity.map { $0 * ioKitState.percentage / 100 }
                ?? previous.currentCapacity,
            maxCapacity: smcState.fullChargeCapacity ?? previous.maxCapacity,
            designCapacity: smcState.designCapacity ?? previous.designCapacity,
            cycleCount: smcState.cycleCount ?? ioKitState.cycleCount ?? previous.cycleCount,
            temperature: smcState.temperature ?? previous.temperature,
            voltage: smcState.voltage ?? previous.voltage,
            amperage: smcState.amperage ?? previous.amperage,
            systemPower: smcState.systemPower ?? previous.systemPower,
            adapterPower: smcState.adapterPower ?? previous.adapterPower,
            adapterInfo: adapterInfo,
            batteryPower: smcState.batteryPower ?? previous.batteryPower,
            notChargingReason: ioRegState.notChargingReason,
            chargerInhibitReason: ioRegState.chargerInhibitReason,
            timeToEmpty: ioKitState.timeToEmpty,
            timeToFull: ioKitState.timeToFull
        )

        // Skip identical snapshots — stops Combine/SwiftUI fan-out while idle at limit.
        guard state != previous else { return }
        batteryState = state
    }

    // MARK: - Poll needs

    /// Exposed for tests — same logic as production ticks.
    static func pollNeeds(
        popoverOpen: Bool,
        settings: AppSettings,
        needsAdapterPower: Bool
    ) -> BatteryPollNeeds {
        BatteryPollNeeds.resolve(
            popoverOpen: popoverOpen,
            heatProtectionEnabled: settings.heatProtectionEnabled,
            statusBarShowTemperature: settings.statusBarShowTemperature,
            statusBarShowPower: settings.statusBarShowPower,
            useHardwareBatteryPercentage: settings.useHardwareBatteryPercentage,
            needsAdapterPower: needsAdapterPower
        )
    }

    private func currentPollNeeds() -> BatteryPollNeeds {
        let charging = ChargingManager.shared
        let needsAdapterPower = charging.mode == .discharging
            || charging.calibrationPhase == .dischargingToLow
        return Self.pollNeeds(
            popoverOpen: isPopoverOpen,
            settings: settings,
            needsAdapterPower: needsAdapterPower
        )
    }

    // MARK: - IOKit Power Source (no root needed)

    private struct IOKitData {
        var percentage: Int = 0
        var isCharging: Bool = false
        var isPluggedIn: Bool = false
        var currentCapacity: Int?
        var maxCapacity: Int?
        var designCapacity: Int?
        var cycleCount: Int?
        var timeToEmpty: Int?
        var timeToFull: Int?
    }

    private func readIOKitPowerSource() -> IOKitData {
        var data = IOKitData()

        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any],
              let first = sources.first,
              let desc = IOPSGetPowerSourceDescription(snapshot, first as CFTypeRef)?.takeUnretainedValue() as? [String: Any]
        else {
            return data
        }

        data.percentage = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
        data.isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
        data.maxCapacity = desc[kIOPSMaxCapacityKey] as? Int
        data.designCapacity = desc[kIOPSDesignCapacityKey] as? Int

        if let powerSource = desc[kIOPSPowerSourceStateKey] as? String {
            data.isPluggedIn = (powerSource == kIOPSACPowerValue)
        }

        if let timeToEmpty = desc[kIOPSTimeToEmptyKey] as? Int, timeToEmpty >= 0 {
            data.timeToEmpty = timeToEmpty
        }
        if let timeToFull = desc[kIOPSTimeToFullChargeKey] as? Int, timeToFull >= 0 {
            data.timeToFull = timeToFull
        }

        // IOKit sometimes reports cycle count
        data.cycleCount = desc["CycleCount"] as? Int

        return data
    }

    // MARK: - SMC Data (detailed, no root for reads)

    private struct SMCData {
        var temperature: Double?
        var voltage: Double?
        var amperage: Double?
        var systemPower: Double?
        var adapterPower: Double?
        var adapterVoltage: Double?  // VD0R (live adapter voltage)
        var adapterCurrent: Double?  // ID0R (live adapter current)
        var batteryPower: Double?
        var cycleCount: Int?
        var brscPercentage: Int?        // BRSC: Battery Remaining State of Charge
        var remainingCapacity: Int?
        var fullChargeCapacity: Int?
        var designCapacity: Int?
    }

    private func readSMCData(needs: BatteryPollNeeds, previous _: BatteryState) -> SMCData {
        var data = SMCData()

        if needs.temperature || needs.detail {
            // Temperature: prefer TB0T (flt on Apple Silicon) over B0AT (ui16 deci-Kelvin)
            if let val = smc.readKeyOptional("TB0T") {
                if val.dataType.hasPrefix("flt"), let f = val.floatValue {
                    data.temperature = Self.rounded(Double(f), places: 1)
                } else if let sp = val.sp78Value {
                    data.temperature = Self.rounded(sp, places: 1)
                }
            }
            if data.temperature == nil, let val = smc.readKeyOptional("B0AT") {
                if val.dataType == "ui16", let raw = val.uint16Value {
                    let celsius = (Double(raw) - 2732.0) / 10.0
                    if celsius > -20 && celsius < 100 {
                        data.temperature = Self.rounded(celsius, places: 1)
                    }
                }
            }
        }

        if needs.systemPower || needs.detail {
            if let val = smc.readKeyOptional("PSTR") {
                if let f = val.floatValue, val.dataType.hasPrefix("flt") {
                    data.systemPower = Self.rounded(Double(f), places: 1)
                } else if let sp = val.sp78Value {
                    data.systemPower = Self.rounded(sp, places: 1)
                }
            }
        }

        if needs.adapterPower || needs.detail {
            if let val = smc.readKeyOptional("PDTR") {
                if let f = val.floatValue, val.dataType.hasPrefix("flt") {
                    data.adapterPower = Self.rounded(Double(f), places: 1)
                } else if let sp = val.sp96Value {
                    data.adapterPower = Self.rounded(sp, places: 1)
                }
            }
        }

        guard needs.detail || needs.hardwarePercentage else { return data }

        if needs.detail {
            // Voltage: B0AV in mV
            if let raw = smc.readUInt16("B0AV") {
                data.voltage = Self.rounded(Double(raw) / 1000.0, places: 2)
            }

            // Current: B0AC in mA (signed)
            if let raw = smc.readInt16("B0AC") {
                data.amperage = Self.rounded(Double(raw) / 1000.0, places: 3)
            }

            // Adapter voltage: VD0R
            if let val = smc.readKeyOptional("VD0R") {
                if val.dataType.hasPrefix("flt"), let f = val.floatValue {
                    data.adapterVoltage = Self.rounded(Double(f), places: 2)
                } else if let raw = val.uint16Value {
                    data.adapterVoltage = Self.rounded(Double(raw) / 1000.0, places: 2)
                }
            }

            // Adapter current: ID0R
            if let val = smc.readKeyOptional("ID0R") {
                if val.dataType.hasPrefix("flt"), let f = val.floatValue {
                    data.adapterCurrent = Self.rounded(Double(f), places: 3)
                } else if let raw = val.uint16Value {
                    data.adapterCurrent = Self.rounded(Double(raw) / 1000.0, places: 3)
                }
            }

            // Battery power: prefer B0AP over V*A
            if let val = smc.readKeyOptional("B0AP") {
                if let f = val.floatValue, val.dataType.hasPrefix("flt") {
                    data.batteryPower = Self.rounded(Double(f), places: 1)
                } else if let raw = val.int32Value {
                    data.batteryPower = Self.rounded(Double(raw) / 1000.0, places: 1)
                }
            }
            if data.batteryPower == nil, let v = data.voltage, let a = data.amperage {
                data.batteryPower = Self.rounded(v * a, places: 1)
            }

            if let raw = smc.readUInt16("B0CT") {
                data.cycleCount = Int(raw)
            }

            if let raw = smc.readUInt16("B0DC") {
                data.designCapacity = Int(raw)
            }
        }

        if needs.hardwarePercentage || needs.detail {
            if let raw = smc.readUInt16("B0FC") {
                data.fullChargeCapacity = Int(raw)
            }

            // BRSC fallback for hardware %
            if let raw = smc.readUInt16("BRSC") {
                let pct = Int(raw >> 8)
                if pct >= 0 && pct <= 100 {
                    data.brscPercentage = pct
                }
            }

            // B0RM uses big-endian byte order per Asahi Linux docs, but try both.
            if let val = smc.readKeyOptional("B0RM"), let fc = data.fullChargeCapacity, fc > 0 {
                let be = val.uint16BigEndian.map(Int.init) ?? -1
                let le = val.uint16Value.map(Int.init) ?? -1
                let beRatio = Double(be) / Double(fc)
                let leRatio = Double(le) / Double(fc)
                if be >= 0 && beRatio <= 1.1 {
                    data.remainingCapacity = be
                } else if le >= 0 && leRatio <= 1.1 {
                    data.remainingCapacity = le
                }
            }
        }

        return data
    }

    private static func rounded(_ value: Double, places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (value * factor).rounded() / factor
    }

    // MARK: - IORegistry (adapter details, not-charging reason)

    private func readIORegistryBattery(includeAdapterDetails: Bool) -> (adapterInfo: AdapterInfo?, notChargingReason: UInt64?, chargerInhibitReason: UInt64?) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return (nil, nil, nil) }
        defer { IOObjectRelease(service) }

        // Read only the keys we need — NOT CreateCFProperties which copies the entire 16KB+ dict
        let adapterDict: [String: Any]? = includeAdapterDetails
            ? IORegistryEntryCreateCFProperty(service, "AdapterDetails" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any]
            : nil
        let chargerDict = IORegistryEntryCreateCFProperty(service, "ChargerData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any]

        // Parse AdapterDetails
        var adapterInfo: AdapterInfo?
        if let adapter = adapterDict {
            let name = adapter["Name"] as? String
                ?? adapter["Description"] as? String
                ?? "Unknown Adapter"
            let description = adapter["Description"] as? String
            let manufacturer = adapter["Manufacturer"] as? String
            let model = adapter["Model"] as? String
            let watts = adapter["Watts"] as? Int ?? 0

            // AdapterVoltage in mV, Current in mA
            let voltage: Double = {
                if let v = adapter["AdapterVoltage"] as? Int {
                    return Self.rounded(Double(v) / 1000.0, places: 2)
                }
                return 0
            }()
            let current: Double = {
                if let a = adapter["Current"] as? Int {
                    return Self.rounded(Double(a) / 1000.0, places: 3)
                }
                return 0
            }()

            let serial = adapter["SerialString"] as? String
            let firmware = adapter["FwVersion"] as? String
            let isWireless = adapter["IsWireless"] as? Bool ?? false

            // USB-PD profiles (keys: MaxVoltage/MaxCurrent in mV/mA)
            var profiles: [USBPDProfile] = []
            if let menu = adapter["UsbHvcMenu"] as? [[String: Any]] {
                for entry in menu {
                    if let v = entry["MaxVoltage"] as? Int, let a = entry["MaxCurrent"] as? Int {
                        profiles.append(USBPDProfile(
                            voltage: Self.rounded(Double(v) / 1000.0, places: 2),
                            current: Self.rounded(Double(a) / 1000.0, places: 3)
                        ))
                    }
                }
            }
            let activeIndex = adapter["UsbHvcHvcIndex"] as? Int

            adapterInfo = AdapterInfo(
                name: name,
                description: description,
                manufacturer: manufacturer,
                model: model,
                watts: watts,
                voltage: voltage,
                current: current,
                serial: serial,
                firmware: firmware,
                isWireless: isWireless,
                usbPDProfiles: profiles,
                activeProfileIndex: activeIndex
            )
        }

        // NotChargingReason and ChargerInhibitReason from ChargerData
        var notChargingReason: UInt64?
        var chargerInhibitReason: UInt64?
        if let chargerData = chargerDict {
            if let raw = chargerData["NotChargingReason"] {
                if let val = raw as? UInt64 {
                    notChargingReason = val
                } else if let val = raw as? Int {
                    notChargingReason = UInt64(bitPattern: Int64(val))
                }
                if notChargingReason != lastLoggedNotChargingReason {
                    let hex = String(notChargingReason ?? 0, radix: 16, uppercase: true)
                    log.notice("NotChargingReason: \(notChargingReason ?? 0, privacy: .public) (0x\(hex, privacy: .public))")
                    lastLoggedNotChargingReason = notChargingReason
                }
            }

            // ChargerInhibitReason — may reveal WHO is inhibiting (us vs system)
            if let raw = chargerData["ChargerInhibitReason"] {
                var val: UInt64 = 0
                if let v = raw as? UInt64 { val = v }
                else if let v = raw as? Int { val = UInt64(bitPattern: Int64(v)) }
                chargerInhibitReason = val
                if val != lastLoggedInhibitReason {
                    let hex = String(val, radix: 16, uppercase: true)
                    log.notice("ChargerInhibitReason: \(val, privacy: .public) (0x\(hex, privacy: .public))")
                    lastLoggedInhibitReason = val
                }
            }

            // Log IORegistry dict keys once, and re-log if adapter appears
            let hasFullAdapter = (adapterDict?.count ?? 0) > 1
            if includeAdapterDetails && (!didLogIORegistryDiag || (!didLogAdapterDetails && hasFullAdapter)) {
                let chargerKeys = chargerData.keys.sorted().joined(separator: ", ")
                log.info("ChargerData keys: [\(chargerKeys, privacy: .public)]")
                if let adapter = adapterDict {
                    let adapterKeys = adapter.keys.sorted().joined(separator: ", ")
                    log.info("AdapterDetails keys: [\(adapterKeys, privacy: .public)]")
                    if hasFullAdapter { didLogAdapterDetails = true }
                }
                didLogIORegistryDiag = true
            }
        }

        return (adapterInfo, notChargingReason, chargerInhibitReason)
    }

    // MARK: - Polling

    /// Fixed 2s polling interval. Lean background ticks skip unused SMC keys;
    /// popover opens force a full instrumentation read.
    static let pollingInterval: TimeInterval = 2

    private func scheduleTimer() {
        timer?.invalidate()
        // Timer fires on the main run loop — call update() directly (no Task hop).
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollingInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.update()
            }
        }
    }

    // MARK: - Power Source Notifications

    private func registerPowerSourceNotification() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let ctx = context else { return }
            let service = Unmanaged<BatteryService>.fromOpaque(ctx).takeUnretainedValue()
            // Callback fires on main RunLoop — use assumeIsolated for Swift 6 safety
            MainActor.assumeIsolated {
                service.update()
            }
        }, context)?.takeRetainedValue() {
            self.runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }
}
