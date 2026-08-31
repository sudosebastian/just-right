import Foundation
import SwiftUI

/// All user-configurable settings, backed by UserDefaults.
/// Production uses `.standard` via `AppSettings.shared`.
/// Tests pass an isolated suite to avoid polluting real settings.
@MainActor
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    private(set) var defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    #if DEBUG
    private static let uiAuditSuiteName = "com.opendente.ui-audit"

    func configureForUIAudit() {
        guard let isolatedDefaults = UserDefaults(suiteName: Self.uiAuditSuiteName) else { return }
        isolatedDefaults.removePersistentDomain(forName: Self.uiAuditSuiteName)
        defaults = isolatedDefaults

        isolatedDefaults.set(80, forKey: "chargeLimit")
        isolatedDefaults.set(true, forKey: "sailingModeEnabled")
        isolatedDefaults.set(10, forKey: "sailingRange")
        isolatedDefaults.set(true, forKey: "heatProtectionEnabled")
        isolatedDefaults.set(35.0, forKey: "heatProtectionTemp")
        isolatedDefaults.set(true, forKey: "scheduledTopUpEnabled")
        isolatedDefaults.set(7, forKey: "scheduledTopUpHour")
        isolatedDefaults.set(0, forKey: "scheduledTopUpMinute")
        isolatedDefaults.set(Array(2...6), forKey: "scheduledTopUpWeekdays")
        isolatedDefaults.set(true, forKey: "statusBarShowPercentage")
        isolatedDefaults.set(true, forKey: "statusBarShowPower")
        isolatedDefaults.set(true, forKey: "statusBarShowMode")
        isolatedDefaults.set(true, forKey: "showPowerFlow")
        isolatedDefaults.set(true, forKey: "controlMagSafeLED")
        isolatedDefaults.set(true, forKey: "showNotifications")
    }

    func cleanUpUIAuditDefaults() {
        UserDefaults(suiteName: Self.uiAuditSuiteName)?
            .removePersistentDomain(forName: Self.uiAuditSuiteName)
        defaults = .standard
    }
    #endif

    // MARK: - Charging

    var chargingEnabled: Bool {
        get { defaults.object(forKey: "chargingEnabled") as? Bool ?? true }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "chargingEnabled") }
    }

    /// Charge limit percentage (20-100), clamped on set
    var chargeLimit: Int {
        get {
            let v = defaults.integer(forKey: "chargeLimit")
            return v == 0 ? 80 : min(100, max(20, v))
        }
        set {
            objectWillChange.send()
            defaults.set(min(100, max(20, newValue)), forKey: "chargeLimit")
        }
    }

    // MARK: - Sailing Mode

    var sailingModeEnabled: Bool {
        get { defaults.object(forKey: "sailingModeEnabled") as? Bool ?? true }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "sailingModeEnabled") }
    }

    /// Sailing range percentage (2-25), clamped on set
    var sailingRange: Int {
        get {
            let v = defaults.integer(forKey: "sailingRange")
            return v == 0 ? 10 : min(25, max(2, v))
        }
        set {
            objectWillChange.send()
            defaults.set(min(25, max(2, newValue)), forKey: "sailingRange")
        }
    }

    // MARK: - Heat Protection

    var heatProtectionEnabled: Bool {
        get { defaults.object(forKey: "heatProtectionEnabled") as? Bool ?? true }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "heatProtectionEnabled") }
    }

    /// Heat protection temperature threshold in Celsius (30-45), clamped on get/set
    var heatProtectionTemp: Double {
        get {
            let v = defaults.double(forKey: "heatProtectionTemp")
            return (v == 0 ? 35.0 : v).clamped(to: 30...45)
        }
        set {
            objectWillChange.send()
            defaults.set(newValue.clamped(to: 30...45), forKey: "heatProtectionTemp")
        }
    }

    // MARK: - Discharge

    var automaticDischarge: Bool {
        get { defaults.bool(forKey: "automaticDischarge") }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "automaticDischarge") }
    }

    // MARK: - Scheduled Top Up

    var scheduledTopUpEnabled: Bool {
        get { defaults.bool(forKey: "scheduledTopUpEnabled") }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "scheduledTopUpEnabled") }
    }

    var scheduledTopUpHour: Int {
        get {
            guard defaults.object(forKey: "scheduledTopUpHour") != nil else { return 7 }
            return min(23, max(0, defaults.integer(forKey: "scheduledTopUpHour")))
        }
        set {
            objectWillChange.send()
            defaults.set(min(23, max(0, newValue)), forKey: "scheduledTopUpHour")
        }
    }

    var scheduledTopUpMinute: Int {
        get {
            guard defaults.object(forKey: "scheduledTopUpMinute") != nil else { return 0 }
            return min(59, max(0, defaults.integer(forKey: "scheduledTopUpMinute")))
        }
        set {
            objectWillChange.send()
            defaults.set(min(59, max(0, newValue)), forKey: "scheduledTopUpMinute")
        }
    }

    /// Calendar weekday values (1 = Sunday, 7 = Saturday). Defaults to weekdays.
    var scheduledTopUpWeekdays: Set<Int> {
        get {
            guard let values = defaults.array(forKey: "scheduledTopUpWeekdays") as? [Int] else {
                return Set(2...6)
            }
            return Set(values.filter { (1...7).contains($0) })
        }
        set {
            objectWillChange.send()
            defaults.set(newValue.filter { (1...7).contains($0) }.sorted(), forKey: "scheduledTopUpWeekdays")
        }
    }

    var lastScheduledTopUpDay: String? {
        get { defaults.string(forKey: "lastScheduledTopUpDay") }
        set { defaults.set(newValue, forKey: "lastScheduledTopUpDay") }
    }

    // MARK: - Calibration

    var savedCalibrationPhase: CalibrationPhase? {
        get {
            guard let raw = defaults.string(forKey: "calibrationPhase") else { return nil }
            return CalibrationPhase(rawValue: raw)
        }
        set {
            if let newValue {
                defaults.set(newValue.rawValue, forKey: "calibrationPhase")
            } else {
                defaults.removeObject(forKey: "calibrationPhase")
            }
        }
    }

    var savedCalibrationPhaseStartedAt: Date? {
        get { defaults.object(forKey: "calibrationPhaseStartedAt") as? Date }
        set {
            if let newValue {
                defaults.set(newValue, forKey: "calibrationPhaseStartedAt")
            } else {
                defaults.removeObject(forKey: "calibrationPhaseStartedAt")
            }
        }
    }

    // MARK: - Sleep

    var stopChargingWhenSleeping: Bool {
        get { defaults.bool(forKey: "stopChargingWhenSleeping") }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "stopChargingWhenSleeping") }
    }

    var disableSleepUntilChargeLimit: Bool {
        get { defaults.bool(forKey: "disableSleepUntilChargeLimit") }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "disableSleepUntilChargeLimit") }
    }

    // MARK: - Status Bar Display

    var statusBarShowPercentage: Bool {
        get { defaults.object(forKey: "statusBarShowPercentage") as? Bool ?? true }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "statusBarShowPercentage") }
    }

    var statusBarShowTemperature: Bool {
        get { defaults.bool(forKey: "statusBarShowTemperature") }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "statusBarShowTemperature") }
    }

    var statusBarShowPower: Bool {
        get { defaults.bool(forKey: "statusBarShowPower") }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "statusBarShowPower") }
    }

    var statusBarShowMode: Bool {
        get { defaults.object(forKey: "statusBarShowMode") as? Bool ?? true }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "statusBarShowMode") }
    }

    // MARK: - Power Flow

    var showPowerFlow: Bool {
        get { defaults.object(forKey: "showPowerFlow") as? Bool ?? true }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "showPowerFlow") }
    }

    // MARK: - MagSafe LED

    var controlMagSafeLED: Bool {
        get { defaults.object(forKey: "controlMagSafeLED") as? Bool ?? true }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "controlMagSafeLED") }
    }

    var magSafeLEDOffWhenInactive: Bool {
        get { defaults.bool(forKey: "magSafeLEDOffWhenInactive") }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "magSafeLEDOffWhenInactive") }
    }

    // MARK: - General

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: "launchAtLogin") }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "launchAtLogin") }
    }

    var useHardwareBatteryPercentage: Bool {
        get { defaults.bool(forKey: "useHardwareBatteryPercentage") }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "useHardwareBatteryPercentage") }
    }

    var showNotifications: Bool {
        get { defaults.object(forKey: "showNotifications") as? Bool ?? true }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "showNotifications") }
    }

    var notifyChargeLimitReached: Bool {
        get { defaults.object(forKey: "notifyChargeLimitReached") as? Bool ?? true }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "notifyChargeLimitReached") }
    }

    var notifyTopUpComplete: Bool {
        get { defaults.object(forKey: "notifyTopUpComplete") as? Bool ?? true }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "notifyTopUpComplete") }
    }

    var notifyHeatProtection: Bool {
        get { defaults.object(forKey: "notifyHeatProtection") as? Bool ?? true }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "notifyHeatProtection") }
    }

    var notifyDischargeComplete: Bool {
        get { defaults.object(forKey: "notifyDischargeComplete") as? Bool ?? true }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "notifyDischargeComplete") }
    }

    // MARK: - Popover Detail Items

    /// Ordered list of enabled detail items in the popover
    var popoverDetailItems: [PopoverDetailItem] {
        get {
            guard let data = defaults.data(forKey: "popoverDetailItems"),
                  let items = try? JSONDecoder().decode([PopoverDetailItem].self, from: data)
            else {
                return PopoverDetailItem.defaultItems
            }
            return items
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                objectWillChange.send()
                defaults.set(data, forKey: "popoverDetailItems")
            }
        }
    }

    // MARK: - Computed

    /// Lower bound of sailing range
    var sailingLowerBound: Int {
        max(0, chargeLimit - sailingRange)
    }
}
