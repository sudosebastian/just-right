import XCTest
@testable import JustRight

@MainActor
final class PollingIntervalTests: XCTestCase {

    func testPollingInterval_isFixed2s() {
        XCTAssertEqual(BatteryService.pollingInterval, 2)
    }

    func testPollNeeds_popoverOpen_isFull() {
        let needs = BatteryPollNeeds.resolve(
            popoverOpen: true,
            heatProtectionEnabled: false,
            statusBarShowTemperature: false,
            statusBarShowPower: false,
            useHardwareBatteryPercentage: false,
            needsAdapterPower: false,
            needsAdapterVoltage: false
        )
        XCTAssertEqual(needs, .full)
    }

    func testPollNeeds_idleBackground_isControlOnly() {
        let needs = BatteryPollNeeds.resolve(
            popoverOpen: false,
            heatProtectionEnabled: false,
            statusBarShowTemperature: false,
            statusBarShowPower: false,
            useHardwareBatteryPercentage: false,
            needsAdapterPower: false,
            needsAdapterVoltage: false
        )
        XCTAssertEqual(needs, .controlOnly)
        XCTAssertFalse(needs.temperature)
        XCTAssertFalse(needs.systemPower)
        XCTAssertFalse(needs.hardwarePercentage)
        XCTAssertFalse(needs.adapterPower)
        XCTAssertFalse(needs.adapterVoltage)
        XCTAssertFalse(needs.detail)
    }

    func testPollNeeds_statusBarPower_readsSystemPowerOnly() {
        let needs = BatteryPollNeeds.resolve(
            popoverOpen: false,
            heatProtectionEnabled: false,
            statusBarShowTemperature: false,
            statusBarShowPower: true,
            useHardwareBatteryPercentage: false,
            needsAdapterPower: false,
            needsAdapterVoltage: false
        )
        XCTAssertTrue(needs.systemPower)
        XCTAssertFalse(needs.detail)
        XCTAssertFalse(needs.temperature)
    }

    func testPollNeeds_heatProtection_readsTemperature() {
        let needs = BatteryPollNeeds.resolve(
            popoverOpen: false,
            heatProtectionEnabled: true,
            statusBarShowTemperature: false,
            statusBarShowPower: false,
            useHardwareBatteryPercentage: false,
            needsAdapterPower: false,
            needsAdapterVoltage: false
        )
        XCTAssertTrue(needs.temperature)
        XCTAssertFalse(needs.detail)
    }

    func testPollNeeds_discharge_readsAdapterPowerAndVoltage() {
        let needs = BatteryPollNeeds.resolve(
            popoverOpen: false,
            heatProtectionEnabled: false,
            statusBarShowTemperature: false,
            statusBarShowPower: false,
            useHardwareBatteryPercentage: false,
            needsAdapterPower: true,
            needsAdapterVoltage: false
        )
        XCTAssertTrue(needs.adapterPower)
        XCTAssertTrue(needs.adapterVoltage, "PDTR reads also pull VD0R for CHIE presence")
        XCTAssertFalse(needs.detail)
    }

    func testPollNeeds_chieGate_readsAdapterVoltageOnly() {
        let needs = BatteryPollNeeds.resolve(
            popoverOpen: false,
            heatProtectionEnabled: false,
            statusBarShowTemperature: false,
            statusBarShowPower: false,
            useHardwareBatteryPercentage: false,
            needsAdapterPower: false,
            needsAdapterVoltage: true
        )
        XCTAssertFalse(needs.adapterPower)
        XCTAssertTrue(needs.adapterVoltage)
        XCTAssertFalse(needs.detail)
    }

    func testPollNeeds_hardwarePercentage_withoutDetail() {
        let needs = BatteryPollNeeds.resolve(
            popoverOpen: false,
            heatProtectionEnabled: false,
            statusBarShowTemperature: false,
            statusBarShowPower: false,
            useHardwareBatteryPercentage: true,
            needsAdapterPower: false,
            needsAdapterVoltage: false
        )
        XCTAssertTrue(needs.hardwarePercentage)
        XCTAssertFalse(needs.detail)
    }

    /// ChargingManager.start() wires this so inhibit retries still run when
    /// BatteryService skips republishing an identical snapshot.
    func testUnchangedPollHook_isInvokedByContract() {
        let defaults = UserDefaults(suiteName: "com.opendente.tests.pollhook")!
        defaults.removePersistentDomain(forName: "com.opendente.tests.pollhook")
        let settings = AppSettings(defaults: defaults)
        let battery = BatteryService(settings: settings)

        var received: BatteryState?
        battery.onUnchangedPoll = { received = $0 }

        let state = BatteryState.unknown
        battery.onUnchangedPoll?(state)
        XCTAssertEqual(received, state)
    }
}
