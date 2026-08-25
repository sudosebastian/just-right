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
            needsAdapterPower: false
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
            needsAdapterPower: false
        )
        XCTAssertEqual(needs, .controlOnly)
        XCTAssertFalse(needs.temperature)
        XCTAssertFalse(needs.systemPower)
        XCTAssertFalse(needs.hardwarePercentage)
        XCTAssertFalse(needs.adapterPower)
        XCTAssertFalse(needs.detail)
    }

    func testPollNeeds_statusBarPower_readsSystemPowerOnly() {
        let needs = BatteryPollNeeds.resolve(
            popoverOpen: false,
            heatProtectionEnabled: false,
            statusBarShowTemperature: false,
            statusBarShowPower: true,
            useHardwareBatteryPercentage: false,
            needsAdapterPower: false
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
            needsAdapterPower: false
        )
        XCTAssertTrue(needs.temperature)
        XCTAssertFalse(needs.detail)
    }

    func testPollNeeds_discharge_readsAdapterPower() {
        let needs = BatteryPollNeeds.resolve(
            popoverOpen: false,
            heatProtectionEnabled: false,
            statusBarShowTemperature: false,
            statusBarShowPower: false,
            useHardwareBatteryPercentage: false,
            needsAdapterPower: true
        )
        XCTAssertTrue(needs.adapterPower)
        XCTAssertFalse(needs.detail)
    }

    func testPollNeeds_hardwarePercentage_withoutDetail() {
        let needs = BatteryPollNeeds.resolve(
            popoverOpen: false,
            heatProtectionEnabled: false,
            statusBarShowTemperature: false,
            statusBarShowPower: false,
            useHardwareBatteryPercentage: true,
            needsAdapterPower: false
        )
        XCTAssertTrue(needs.hardwarePercentage)
        XCTAssertFalse(needs.detail)
    }
}
