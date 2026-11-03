//
//  MenuBarEngineTests.swift
//  HiddenBarTests
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import AppKit
import XCTest

// The engine sources are compiled straight into this bundle (no host app), so
// the tests never put items in the real menu bar, never need Accessibility, and
// never touch the private visibility API.

// MARK: - Fakes

private final class FakeItems: MenuBarItemProvider {
    private let bar = NSStatusBar()
    let toggleItem: NSStatusItem
    let separatorItem: NSStatusItem
    var alwaysHiddenItem: NSStatusItem?

    init() {
        toggleItem = bar.statusItem(withLength: NSStatusItem.variableLength)
        separatorItem = bar.statusItem(withLength: 1)
        alwaysHiddenItem = bar.statusItem(withLength: 20)
    }
}

private final class FakeInventory: MenuBarInventoryProviding {
    var isAuthorized = true
    var items: [MenuBarInventoryItem] = []
    var authorizationRequests = 0
    var snapshots = 0

    func requestAuthorization() {
        authorizationRequests += 1
    }

    func snapshot(completion: @escaping ([MenuBarInventoryItem]) -> Void) {
        snapshots += 1
        completion(items)
    }
}

private final class FakeAssertion: NativeVisibilityAssertion {
    let allowed: [String]
    private(set) var isInvalidated = false
    var onInvalidate: (() -> Void)?

    init(allowed: [String]) {
        self.allowed = allowed
    }

    func invalidate() {
        isInvalidated = true
        onInvalidate?()
    }
}

// Hands every activation to the test, which decides when and how it completes.
private final class FakeVisibility: NativeVisibilityProviding {
    struct Request {
        let systemItems: [Int]
        let bundles: [String]
        let completion: (Result<NativeVisibilityAssertion, Error>) -> Void
    }

    var isAvailable = true
    var requests: [Request] = []

    func activate(allowedSystemItems: [Int],
                  allowedBundleIdentifiers: [String],
                  completion: @escaping (Result<NativeVisibilityAssertion, Error>) -> Void) {
        requests.append(Request(systemItems: allowedSystemItems, bundles: allowedBundleIdentifiers, completion: completion))
    }

    @discardableResult
    func succeed(_ index: Int) -> FakeAssertion {
        let assertion = FakeAssertion(allowed: requests[index].bundles)
        requests[index].completion(.success(assertion))
        return assertion
    }

    func fail(_ index: Int) {
        requests[index].completion(.failure(NSError(domain: "test", code: 1)))
    }
}

private func item(_ bundle: String?, x: CGFloat, width: CGFloat = 24) -> MenuBarInventoryItem {
    return MenuBarInventoryItem(bundleIdentifier: bundle, frame: CGRect(x: x, y: 0, width: width, height: 24))
}

// LTR bar used throughout: always-hidden separator at 1000, the boundary at 1300
// (the regular separator for both the resolver and native engine).
private let alwaysHiddenSeparator = CGRect(x: 1000, y: 0, width: 20, height: 24)
private let separator = CGRect(x: 1300, y: 0, width: 20, height: 24)

// Explicit fixture: system hosts must remain allowed even with no AX items.
private let systemOwners = ["com.apple.MenuBarAgent", "com.apple.controlcenter", "com.apple.systemuiserver"]
private func allowedBundles(_ apps: [String]) -> [String] {
    return (systemOwners + apps).sorted()
}

// MARK: - Layout resolver

final class MenuBarLayoutResolverTests: XCTestCase {
    func testLTRSectionsFollowSeparators() {
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [item("com.always", x: 900), item("com.hidden", x: 1100), item("com.visible", x: 1400)],
            separatorFrame: separator, alwaysHiddenSeparatorFrame: alwaysHiddenSeparator,
            isLTR: true, excludingBundle: nil)
        XCTAssertEqual(layout.sections, ["com.always": .alwaysHidden, "com.hidden": .hidden, "com.visible": .visible])
    }

    func testRTLSectionsAreMirrored() {
        // RTL: arrow on the left, separator just right of it, hidden further right.
        let rtlSeparator = CGRect(x: 300, y: 0, width: 20, height: 24)
        let rtlAlwaysHidden = CGRect(x: 600, y: 0, width: 20, height: 24)
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [item("com.visible", x: 200), item("com.hidden", x: 450), item("com.always", x: 700)],
            separatorFrame: rtlSeparator, alwaysHiddenSeparatorFrame: rtlAlwaysHidden,
            isLTR: false, excludingBundle: nil)
        XCTAssertEqual(layout.sections, ["com.always": .alwaysHidden, "com.hidden": .hidden, "com.visible": .visible])
    }

    func testWithoutAlwaysHiddenSeparatorEverythingLeftIsHidden() {
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [item("com.far", x: 100), item("com.near", x: 1200)],
            separatorFrame: separator, alwaysHiddenSeparatorFrame: nil,
            isLTR: true, excludingBundle: nil)
        XCTAssertEqual(layout.sections, ["com.far": .hidden, "com.near": .hidden])
    }

    func testMostVisibleItemWinsForABundle() {
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [item("com.split", x: 1100), item("com.split", x: 1400),
                        item("com.pair", x: 900), item("com.pair", x: 1100)],
            separatorFrame: separator, alwaysHiddenSeparatorFrame: alwaysHiddenSeparator,
            isLTR: true, excludingBundle: nil)
        XCTAssertEqual(layout.sections["com.split"], .visible)
        XCTAssertEqual(layout.sections["com.pair"], .hidden)
    }

    func testSkipsOwnSystemAndUnidentifiedItems() {
        let layout = MenuBarLayoutResolver.resolve(
            inventory: [item("com.dwarvesv.minimalbar", x: 1100), item("com.apple.MenuBarAgent", x: 1100),
                        item(nil, x: 1100), item("com.app", x: 1100)],
            separatorFrame: separator, alwaysHiddenSeparatorFrame: nil,
            isLTR: true, excludingBundle: "com.dwarvesv.minimalbar")
        XCTAssertEqual(layout.sections, ["com.app": .hidden])
    }

    func testBundlesAreFilteredAndSorted() {
        let layout = MenuBarLayout(sections: ["b": .visible, "a": .visible, "c": .hidden, "d": .alwaysHidden])
        XCTAssertEqual(layout.bundles(in: [.visible]), ["a", "b"])
        XCTAssertEqual(layout.bundles(in: [.visible, .hidden]), ["a", "b", "c"])
    }
}

// MARK: - Native engine

final class NativeVisibilityEngineTests: XCTestCase {
    private var items: FakeItems!
    private var inventory: FakeInventory!
    private var visibility: FakeVisibility!

    override func setUp() {
        super.setUp()
        items = FakeItems()
        inventory = FakeInventory()
        inventory.items = [item("com.always", x: 900), item("com.hidden", x: 1100), item("com.visible", x: 1400)]
        visibility = FakeVisibility()
    }

    private func makeEngine() -> NativeVisibilityEngine {
        let items = self.items!
        return NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility,
                                      ownBundleIdentifier: "com.dwarvesv.minimalbar",
                                      itemFrame: {
                                          if $0 === items.separatorItem { return separator }
                                          if $0 === items.toggleItem { return CGRect(x: 1500, y: 0, width: 20, height: 24) }
                                          return alwaysHiddenSeparator
                                      },
                                      isLTR: { true })
    }

    func testCollapseKeepsOnlyVisibleAppsAndSystemItems() {
        let engine = makeEngine()
        var results: [CollapseResult] = []
        engine.collapse { results.append($0) }

        XCTAssertEqual(engine.state, .calibrating)
        XCTAssertEqual(visibility.requests.first?.bundles, allowedBundles(["com.dwarvesv.minimalbar", "com.visible"]))
        XCTAssertEqual(visibility.requests.first?.systemItems, NativeVisibilityEngine.systemItemsToKeep)
        XCTAssertTrue(items.separatorItem.isVisible, "the visible line is the hiding boundary")

        visibility.succeed(0)
        XCTAssertEqual(engine.state, .collapsed)
        XCTAssertEqual(results, [.collapsed])

        XCTAssertTrue(items.separatorItem.isVisible, "retain the registered slot and its saved order")
        XCTAssertEqual(items.separatorItem.length, 0)
        XCTAssertNil(items.separatorItem.button?.image, "no line remains inside the status-item padding")
        XCTAssertEqual(items.separatorItem.button?.isEnabled, false)
        engine.expand()
        XCTAssertTrue(items.separatorItem.isVisible)
        XCTAssertEqual(items.separatorItem.length, 20)
        XCTAssertEqual(items.separatorItem.button?.isEnabled, true)
    }

    func testAppsBetweenDividerAndArrowStayVisibleAndMovesAcrossDividerAreReRead() {
        let engine = makeEngine()
        // The visible app at x=1400 sits left of the arrow (1500), but right
        // of the divider (1300). Arrow-based classification would hide it.
        engine.collapse { _ in }
        XCTAssertTrue(visibility.requests[0].bundles.contains("com.visible"))
        XCTAssertFalse(visibility.requests[0].bundles.contains("com.hidden"))
        visibility.succeed(0)
        engine.expand()

        inventory.items = [item("com.hidden", x: 1350), item("com.visible", x: 1200)]
        engine.collapse { _ in }
        XCTAssertTrue(visibility.requests[1].bundles.contains("com.hidden"))
        XCTAssertFalse(visibility.requests[1].bundles.contains("com.visible"))
    }

    func testMissingDividerDoesNotFallBackToArrowOrHideApps() {
        let items = self.items!
        let engine = NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility,
                                          itemFrame: { $0 === items.separatorItem ? nil : separator })
        var result: CollapseResult?
        engine.collapse { result = $0 }
        XCTAssertEqual(result, .unavailable)
        XCTAssertTrue(visibility.requests.isEmpty)
        XCTAssertTrue(items.separatorItem.isVisible)
    }

    func testRTLUsesDividerRatherThanArrow() {
        let items = self.items!
        inventory.items = [item("com.visible", x: 1200), item("com.hidden", x: 1400)]
        let engine = NativeVisibilityEngine(items: items, inventory: inventory, visibility: visibility,
                                          itemFrame: { $0 === items.separatorItem ? separator : alwaysHiddenSeparator },
                                          isLTR: { false })
        engine.collapse { _ in }
        XCTAssertTrue(visibility.requests[0].bundles.contains("com.visible"))
        XCTAssertFalse(visibility.requests[0].bundles.contains("com.hidden"))
    }

    func testSystemHostsRemainAllowedWithoutInventoryAndItemsAbove63AreKept() {
        inventory.items = []
        let engine = makeEngine()
        engine.collapse { _ in }

        let request = visibility.requests[0]
        XCTAssertEqual(request.bundles, allowedBundles(["com.dwarvesv.minimalbar"]))
        XCTAssertTrue(Set(64...255).isSubset(of: Set(request.systemItems)))
        XCTAssertFalse(request.bundles.contains("com.hidden"))
        XCTAssertFalse(request.bundles.contains("com.always"))
    }

    func testAlwaysHiddenSeparatorFollowsTheSectionSetting() {
        let engine = makeEngine()
        engine.updateAlwaysHiddenSection(enabled: false, separatorHidden: false)
        XCTAssertEqual(items.alwaysHiddenItem?.length, 0)

        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: false)
        XCTAssertEqual(items.alwaysHiddenItem?.length, 20)

        engine.collapse { _ in }
        visibility.succeed(visibility.requests.count - 1)
        XCTAssertEqual(items.alwaysHiddenItem?.length, 0)

        engine.expand()
        XCTAssertEqual(items.alwaysHiddenItem?.length, 20)
    }

    func testUnavailableAPIFailsOpen() {
        visibility.isAvailable = false
        let engine = makeEngine()
        var result: CollapseResult?
        engine.collapse { result = $0 }

        XCTAssertEqual(result, .unavailable)
        XCTAssertEqual(engine.state, .unavailable)
        XCTAssertTrue(visibility.requests.isEmpty)
    }

    func testMissingAccessibilityAsksAndRetriesLater() {
        inventory.isAuthorized = false
        let engine = makeEngine()
        var results: [CollapseResult] = []
        engine.collapse { results.append($0) }

        XCTAssertEqual(results, [.unavailable])
        XCTAssertEqual(inventory.authorizationRequests, 1)
        XCTAssertTrue(visibility.requests.isEmpty, "never guess which icons to hide")

        inventory.isAuthorized = true
        engine.collapse { results.append($0) }
        XCTAssertEqual(visibility.requests.count, 1, "works once the permission is granted")
    }

    func testActivationFailureReportsUnavailable() {
        let engine = makeEngine()
        var result: CollapseResult?
        engine.collapse { result = $0 }
        visibility.fail(0)

        XCTAssertEqual(result, .unavailable)
        XCTAssertEqual(engine.state, .expanded)
        XCTAssertEqual(items.alwaysHiddenItem?.length, 0, "the always-hidden separator only shows when enabled")
    }

    func testExpandDropsTheRestriction() {
        let engine = makeEngine()
        engine.collapse { _ in }
        let collapsed = visibility.succeed(0)

        engine.expand()
        XCTAssertTrue(collapsed.isInvalidated)
        XCTAssertEqual(engine.state, .expanded)
        XCTAssertEqual(visibility.requests.count, 1)
    }

    func testExpandKeepsAlwaysHiddenSectionHiddenAndSwapsWithoutFlashing() {
        let engine = makeEngine()
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: true)
        // Expanded with separators hidden: everything but always-hidden is shown.
        XCTAssertEqual(visibility.requests.last?.bundles, allowedBundles(["com.dwarvesv.minimalbar", "com.hidden", "com.visible"]))
        visibility.succeed(visibility.requests.count - 1)

        engine.collapse { _ in }
        let collapseIndex = visibility.requests.count - 1
        XCTAssertEqual(visibility.requests[collapseIndex].bundles, allowedBundles(["com.dwarvesv.minimalbar", "com.visible"]))
        let collapsed = visibility.succeed(collapseIndex)

        var newIsActiveWhenOldDropped = false
        collapsed.onInvalidate = { newIsActiveWhenOldDropped = true }
        engine.expand()
        let expandIndex = visibility.requests.count - 1
        XCTAssertEqual(visibility.requests[expandIndex].bundles, allowedBundles(["com.dwarvesv.minimalbar", "com.hidden", "com.visible"]))
        XCTAssertFalse(collapsed.isInvalidated, "the old restriction stays until the new one is active")
        visibility.succeed(expandIndex)
        XCTAssertTrue(newIsActiveWhenOldDropped)
    }

    func testSectionsAreNotReadWhileSomethingIsHidden() {
        let engine = makeEngine()
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: true)
        visibility.succeed(visibility.requests.count - 1)
        let snapshotsBefore = inventory.snapshots

        // Hidden items would report stale positions now; the cached layout is used.
        inventory.items = [item("com.visible", x: 100)]
        engine.collapse { _ in }
        XCTAssertEqual(inventory.snapshots, snapshotsBefore)
        XCTAssertEqual(visibility.requests.last?.bundles, allowedBundles(["com.dwarvesv.minimalbar", "com.visible"]))
    }

    func testExpandDuringActivationDropsTheLateResult() {
        let engine = makeEngine()
        var results: [CollapseResult] = []
        engine.collapse { results.append($0) }

        engine.expand()
        let late = visibility.succeed(0)

        XCTAssertTrue(late.isInvalidated, "a restriction nobody wants any more is released")
        XCTAssertEqual(engine.state, .expanded)
        XCTAssertEqual(results, [])
    }

    func testDisplayChangeKeepsTheBarCollapsed() {
        let engine = makeEngine()
        engine.collapse { _ in }
        let collapsed = visibility.succeed(0)

        engine.invalidateLayout()
        XCTAssertEqual(engine.state, .collapsed)
        XCTAssertFalse(collapsed.isInvalidated)
    }
}

// MARK: - Legacy engine

final class LegacyLengthEngineTests: XCTestCase {
    func testCollapseAndExpandFlipSeparatorLength() {
        let items = FakeItems()
        let engine = LegacyLengthEngine(items: items)
        XCTAssertEqual(engine.state, .expanded)

        var result: CollapseResult?
        engine.collapse { result = $0 }
        XCTAssertEqual(result, .collapsed)
        XCTAssertEqual(engine.state, .collapsed)
        XCTAssertEqual(items.alwaysHiddenItem?.length, 20, "collapse leaves the always-hidden item alone")

        engine.expand()
        XCTAssertEqual(engine.state, .expanded)
        XCTAssertEqual(items.separatorItem.length, 20)
    }
}

// No status items are added to the system bar: FakeItems uses a private bar.
private final class OverflowScheduler {
    var actions: [() -> Void] = []
    func schedule(_ delay: TimeInterval, _ action: @escaping () -> Void) {
        actions.append(action)
    }
    func drain() {
        var remaining = 1000
        while !actions.isEmpty && remaining > 0 {
            remaining -= 1
            actions.removeFirst()()
        }
        XCTAssertTrue(actions.isEmpty, "overflow transition must terminate")
    }
}

final class SystemOverflowEngineTests: XCTestCase {
    func testPreferredReservationIsBoundedAndRetargetsWithoutExpanding() {
        XCTAssertEqual(SystemOverflowEngine.reservationLength(screenWidths: [1920], preferredLength: 320), 320)
        XCTAssertEqual(SystemOverflowEngine.reservationLength(screenWidths: [1280], preferredLength: 900), 576)
        XCTAssertEqual(SystemOverflowEngine.reservationLength(screenWidths: [1920], preferredLength: 1), 40)
        let items = FakeItems()
        let scheduler = OverflowScheduler()
        var preferred: CGFloat = 320
        let engine = SystemOverflowEngine(items: items, screenWidths: { [1920] }, preferredLength: { preferred }, schedule: scheduler.schedule)
        var completions = 0
        engine.collapse { _ in completions += 1 }
        preferred = 240
        engine.invalidateLayout()
        XCTAssertEqual(items.separatorItem.length, 240)
        scheduler.drain()
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(engine.state, .collapsed)
    }

    func testReservationFitsNarrowestDisplayAndRejectsUnknownGeometry() {
        XCTAssertEqual(SystemOverflowEngine.reservationLength(screenWidths: [1920, 1280]), 576)
        XCTAssertNil(SystemOverflowEngine.reservationLength(screenWidths: []))
        XCTAssertNil(SystemOverflowEngine.reservationLength(screenWidths: [.nan, .infinity, 0]))
        XCTAssertNil(SystemOverflowEngine.reservationLength(screenWidths: [100]))
    }

    func testInvisibleSpacerReservesSpaceWithoutRemovingTheArrow() {
        let items = FakeItems()
        let scheduler = OverflowScheduler()
        let engine = SystemOverflowEngine(items: items, screenWidths: { [1920] }, schedule: scheduler.schedule)
        XCTAssertTrue(items.separatorItem.isVisible, "expanded mode shows the arrangement boundary")
        XCTAssertTrue(items.separatorItem.button?.image === SystemOverflowEngine.boundaryImage)
        var results: [CollapseResult] = []
        engine.collapse { results.append($0) }
        XCTAssertEqual(engine.state, .calibrating)
        XCTAssertEqual(items.separatorItem.length, 896, "one target width, without intermediate layout steps")
        XCTAssertTrue(items.separatorItem.isVisible, "the invisible spacer must still reserve space")
        XCTAssertTrue(items.separatorItem.button?.image === SystemOverflowEngine.invisibleSpacerImage)
        XCTAssertTrue(items.toggleItem.isVisible, "the separate arrow must stay available")
        XCTAssertTrue(results.isEmpty)
        scheduler.drain()
        XCTAssertEqual(engine.state, .collapsed)
        XCTAssertEqual(results, [.collapsed])
        XCTAssertEqual(items.separatorItem.length, 896)
        engine.expand()
        XCTAssertEqual(items.separatorItem.length, SystemOverflowEngine.expandedLength)
        XCTAssertTrue(items.separatorItem.isVisible)
        XCTAssertTrue(items.separatorItem.button?.image === SystemOverflowEngine.boundaryImage)
        XCTAssertEqual(engine.state, .expanded)
    }

    func testExpandCancelsPendingTransitionAndCompletion() {
        let items = FakeItems()
        let scheduler = OverflowScheduler()
        let engine = SystemOverflowEngine(items: items, screenWidths: { [1920] }, schedule: scheduler.schedule)
        var completed = false
        engine.collapse { _ in completed = true }
        engine.expand()
        scheduler.drain()
        XCTAssertFalse(completed)
        XCTAssertEqual(engine.state, .expanded)
        XCTAssertEqual(items.separatorItem.length, SystemOverflowEngine.expandedLength)
    }

    func testDisplayChangeCancelsOldTargetAndCompletesNewReservationOnce() {
        let items = FakeItems()
        let scheduler = OverflowScheduler()
        var widths: [CGFloat] = [1920]
        let engine = SystemOverflowEngine(items: items, screenWidths: { widths }, schedule: scheduler.schedule)
        var completions = 0
        engine.collapse { _ in completions += 1 }
        widths = [1280]
        engine.invalidateLayout()
        XCTAssertEqual(items.separatorItem.length, 576, "retarget without reopening the bar first")
        scheduler.drain()
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(items.separatorItem.length, 576)
    }

    func testUnchangedDisplayDoesNotRestartOrReopenTransition() {
        let items = FakeItems()
        let scheduler = OverflowScheduler()
        let engine = SystemOverflowEngine(items: items, screenWidths: { [1920] }, schedule: scheduler.schedule)
        var completions = 0
        engine.collapse { _ in completions += 1 }
        engine.invalidateLayout()
        XCTAssertEqual(scheduler.actions.count, 1)
        scheduler.drain()
        engine.invalidateLayout()
        XCTAssertTrue(scheduler.actions.isEmpty)
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(engine.state, .collapsed)
        XCTAssertEqual(items.separatorItem.length, 896)
    }

    func testMissingGeometryLeavesDividerExpandedAndReportsUnavailable() {
        let items = FakeItems()
        let engine = SystemOverflowEngine(items: items, screenWidths: { [] })
        var result: CollapseResult?
        engine.collapse { result = $0 }
        XCTAssertEqual(result, .unavailable)
        XCTAssertEqual(engine.state, .unavailable)
        XCTAssertEqual(items.separatorItem.length, SystemOverflowEngine.expandedLength)
    }

    func testAlwaysHiddenIsExplicitlyUnsupported() {
        let items = FakeItems()
        let engine = SystemOverflowEngine(items: items, screenWidths: { [1920] })
        XCTAssertFalse(engine.supportsAlwaysHiddenSection)
        engine.updateAlwaysHiddenSection(enabled: true, separatorHidden: true)
        XCTAssertEqual(items.alwaysHiddenItem?.length, 0)
    }
}

final class StatusMenuPlacementTests: XCTestCase {
    func testMenuOpensBelowBarEvenWhenVisibleFrameIncludesIt() {
        let frame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let point = StatusMenuPlacement.anchor(mouse: NSPoint(x: 400, y: 1068), screen: frame,
                                              visibleFrame: frame, menuWidth: 300, buttonWidth: 24,
                                              menuBarHeight: 24, safeAreaTop: 0)
        XCTAssertEqual(point, NSPoint(x: 388, y: 1054))
    }

    func testNotchedDisplayAndRightEdgeKeepMenuWithinScreen() {
        let point = StatusMenuPlacement.anchor(mouse: NSPoint(x: 1500, y: 965),
                                              screen: NSRect(x: 0, y: 0, width: 1512, height: 982),
                                              visibleFrame: NSRect(x: 0, y: 0, width: 1512, height: 944),
                                              menuWidth: 300, buttonWidth: 24, menuBarHeight: 24, safeAreaTop: 38)
        XCTAssertEqual(point, NSPoint(x: 1212, y: 942))
    }

    func testSecondaryDisplayUsesItsOwnNegativeOrigin() {
        let point = StatusMenuPlacement.anchor(mouse: NSPoint(x: -1900, y: 868),
                                              screen: NSRect(x: -1920, y: -200, width: 1920, height: 1080),
                                              visibleFrame: NSRect(x: -1920, y: -200, width: 1920, height: 1056),
                                              menuWidth: 300, buttonWidth: 24, menuBarHeight: 24, safeAreaTop: 0)
        XCTAssertEqual(point, NSPoint(x: -1912, y: 854))
    }
}

// MARK: - Engine selection

final class MenuBarEngineFactoryTests: XCTestCase {
    func testDirectBuildUsesNativeHidingOnMacOS27WithoutReservingSpace() {
        let items = FakeItems()
        let engine = MenuBarEngineFactory.make(items: items, osMajorVersion: 27)
        #if HIDDENBAR_NATIVE_VISIBILITY
        XCTAssertFalse(MenuBarEngineFactory.usesSystemOverflow(on: 27))
        XCTAssertTrue(engine is NativeVisibilityEngine)
        XCTAssertTrue(items.separatorItem.isVisible)
        XCTAssertEqual(items.separatorItem.length, 20, "only a fixed divider, no wide blank spacer")
        #else
        XCTAssertTrue(MenuBarEngineFactory.usesSystemOverflow(on: 27))
        XCTAssertTrue(engine is SystemOverflowEngine)
        #endif
    }

    func testOlderMacOSKeepsLegacyHiding() {
        let items = FakeItems()
        XCTAssertTrue(MenuBarEngineFactory.make(items: items, osMajorVersion: 26) is LegacyLengthEngine)
        XCTAssertFalse(MenuBarEngineFactory.usesSystemOverflow(on: 26))
    }
}
