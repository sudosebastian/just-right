import XCTest
@testable import JustRight

final class ChargeScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int) -> Date {
        date(2026, 8, 24, hour, minute)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        ))!
    }

    func testScheduleStartsInsideTriggerWindow() {
        let now = date(7, 5) // Monday
        XCTAssertTrue(ChargeSchedule.shouldStart(
            enabled: true,
            weekdays: [2],
            hour: 7,
            minute: 0,
            now: now,
            lastTriggeredDay: nil,
            calendar: calendar
        ))
    }

    func testScheduleDoesNotStartAfterWindow() {
        XCTAssertFalse(ChargeSchedule.shouldStart(
            enabled: true,
            weekdays: [2],
            hour: 7,
            minute: 0,
            now: date(7, 15),
            lastTriggeredDay: nil,
            calendar: calendar
        ))
    }

    func testScheduleRunsOnlyOncePerDay() {
        let now = date(7, 5)
        XCTAssertFalse(ChargeSchedule.shouldStart(
            enabled: true,
            weekdays: [2],
            hour: 7,
            minute: 0,
            now: now,
            lastTriggeredDay: ChargeSchedule.dayKey(for: now, calendar: calendar),
            calendar: calendar
        ))
    }

    func testNextOccurrenceSkipsDisabledDays() {
        let mondayMorning = date(2026, 8, 24, 8, 0)
        let next = ChargeSchedule.nextOccurrence(
            weekdays: [4], // Wednesday
            hour: 7,
            minute: 30,
            after: mondayMorning,
            calendar: calendar
        )

        XCTAssertEqual(calendar.component(.weekday, from: next!), 4)
        XCTAssertEqual(calendar.component(.hour, from: next!), 7)
        XCTAssertEqual(calendar.component(.minute, from: next!), 30)
    }
}

@MainActor
final class CalibrationTests: XCTestCase {
    private let suiteName = "com.opendente.tests.calibration"
    private var manager: ChargingManager!
    private var mock: MockChargingControl!
    private var settings: AppSettings!
    private var now: Date!

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        settings = AppSettings(defaults: defaults)
        settings.heatProtectionEnabled = false
        settings.controlMagSafeLED = false
        mock = MockChargingControl()
        manager = ChargingManager(settings: settings, helper: mock, battery: .shared)
        manager.chargingAPI = .legacy
        manager.isHelperInstalled = true
        manager.isHelperConnected = true
        now = Date(timeIntervalSince1970: 1_800_000_000)
        manager.nowProvider = { [unowned self] in self.now }
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        manager = nil
        mock = nil
        settings = nil
        super.tearDown()
    }

    func testCalibrationRunsAllFourStages() {
        manager.startCalibration()
        XCTAssertEqual(manager.calibrationPhase, .chargingToFull)
        XCTAssertEqual(manager.mode, .calibrating)

        manager.evaluateState(makeBatteryState(percentage: 100, isCharging: false))
        XCTAssertEqual(manager.calibrationPhase, .holdingAtFull)

        now = now.addingTimeInterval(ChargingManager.calibrationHoldDuration)
        manager.evaluateState(makeBatteryState(percentage: 100, isCharging: false))
        XCTAssertEqual(manager.calibrationPhase, .dischargingToLow)
        XCTAssertTrue(mock.calls.contains(.forceDischarge(enable: true)))

        manager.evaluateState(makeBatteryState(percentage: 15, isCharging: false))
        XCTAssertEqual(manager.calibrationPhase, .rechargingToFull)
        XCTAssertTrue(mock.calls.contains(.forceDischarge(enable: false)))

        manager.evaluateState(makeBatteryState(percentage: 100, isCharging: false))
        XCTAssertNil(manager.calibrationPhase)
        XCTAssertNil(settings.savedCalibrationPhase)
        XCTAssertEqual(manager.mode, .idle)
    }

    func testCalibrationStatePersists() {
        manager.startCalibration()
        manager.evaluateState(makeBatteryState(percentage: 100))

        XCTAssertEqual(settings.savedCalibrationPhase, .holdingAtFull)
        XCTAssertEqual(settings.savedCalibrationPhaseStartedAt, now)
    }

    func testUnplugCancelsCalibrationAndStopsDischarge() {
        manager.startCalibration()
        manager.evaluateState(makeBatteryState(percentage: 100))
        now = now.addingTimeInterval(ChargingManager.calibrationHoldDuration)
        manager.evaluateState(makeBatteryState(percentage: 100))
        mock.reset()

        manager.evaluateState(makeBatteryState(percentage: 80, isPluggedIn: false))

        XCTAssertNil(manager.calibrationPhase)
        XCTAssertEqual(manager.mode, .onBattery)
        XCTAssertEqual(mock.calls, [.forceDischarge(enable: false)])
    }

    func testCalibrationDischargeDoesNotTreatVirtualUnplugAsCableRemoval() {
        manager.startCalibration()
        manager.evaluateState(makeBatteryState(percentage: 100))
        now = now.addingTimeInterval(ChargingManager.calibrationHoldDuration)
        manager.evaluateState(makeBatteryState(percentage: 100))
        mock.reset()

        manager.evaluateState(makeBatteryState(
            percentage: 80,
            isPluggedIn: false,
            adapterPower: 67
        ))

        XCTAssertEqual(manager.calibrationPhase, .dischargingToLow)
        XCTAssertEqual(manager.mode, .calibrating)
        XCTAssertTrue(mock.calls.isEmpty)
    }

    func testHeatProtectionPausesAndResumesCalibrationDischarge() {
        settings.heatProtectionEnabled = true
        settings.heatProtectionTemp = 35
        manager.startCalibration()
        manager.evaluateState(makeBatteryState(percentage: 100))
        now = now.addingTimeInterval(ChargingManager.calibrationHoldDuration)
        manager.evaluateState(makeBatteryState(percentage: 100))
        mock.reset()

        manager.evaluateState(makeBatteryState(percentage: 80, temperature: 36))

        XCTAssertEqual(manager.mode, .heatProtection)
        XCTAssertTrue(mock.calls.contains(.forceDischarge(enable: false)))
        XCTAssertTrue(mock.calls.contains(.inhibitCharging))
        XCTAssertEqual(manager.calibrationPhase, .dischargingToLow)

        manager.heatProtectionTimer = Date(timeIntervalSinceNow: -301)
        mock.reset()
        manager.evaluateState(makeBatteryState(percentage: 80, temperature: 30))

        XCTAssertEqual(manager.mode, .calibrating)
        XCTAssertEqual(mock.calls, [.forceDischarge(enable: true)])
    }
}
