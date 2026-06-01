import XCTest
import RiptideApp

/// UI tests for the Touch Bar provider (Task 7.5).
///
/// Touch Bar hardware only ships on 2016-2021 MacBook Pros, and the XCUI
/// touch-bar query API (`XCUIApplication.touchBar`) only returns meaningful
/// results on real Touch Bar hardware. The tests in this file therefore
/// verify the *provider API surface* — the bar's identifiers and item
/// construction — which is the part that's exercisable on any Mac running
/// Xcode's UI test runner. Runtime scrubber behavior depends on the system
/// instantiating the bar, which only happens on Touch Bar hardware.
final class TouchBarTests: RiptideUITestCase {

    func testMakeTouchBarReturnsBarWithExpectedItemIdentifiers() {
        let bar = TouchBarProvider.shared.makeTouchBar()
        XCTAssertTrue(
            bar.defaultItemIdentifiers.contains(TouchBarProvider.modeButtonIdentifier),
            "Mode button should be one of the bar's default items"
        )
        XCTAssertTrue(
            bar.defaultItemIdentifiers.contains(TouchBarProvider.groupScrubberIdentifier),
            "Group scrubber should be one of the bar's default items"
        )
        XCTAssertTrue(
            bar.defaultItemIdentifiers.contains(TouchBarProvider.testDelayButtonIdentifier),
            "Test-delay button should be one of the bar's default items"
        )
    }

    func testMakeTouchBarUsesExpectedCustomizationIdentifier() {
        let bar = TouchBarProvider.shared.makeTouchBar()
        XCTAssertEqual(
            bar.customizationIdentifier,
            TouchBarProvider.touchBarIdentifier,
            "Bar should carry the Riptide customization identifier"
        )
    }

    func testMakeTouchBarAllowsCustomizationForAllItems() {
        let bar = TouchBarProvider.shared.makeTouchBar()
        XCTAssertTrue(
            bar.customizationAllowedItemIdentifiers.contains(TouchBarProvider.modeButtonIdentifier)
        )
        XCTAssertTrue(
            bar.customizationAllowedItemIdentifiers.contains(TouchBarProvider.groupScrubberIdentifier)
        )
        XCTAssertTrue(
            bar.customizationAllowedItemIdentifiers.contains(TouchBarProvider.testDelayButtonIdentifier)
        )
    }

    func testTouchBarDelegateProducesItemsForAllIdentifiers() {
        let bar = TouchBarProvider.shared.makeTouchBar()
        let delegate = bar.delegate
        XCTAssertNotNil(delegate, "Bar should have a delegate set")
        for identifier in bar.defaultItemIdentifiers {
            let item = delegate?.touchBar?(bar, makeItemForIdentifier: identifier)
            XCTAssertNotNil(
                item,
                "Delegate should produce a touch bar item for identifier \(identifier.rawValue)"
            )
        }
    }
}
