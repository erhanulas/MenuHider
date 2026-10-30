import AppKit

// Experimental macOS 27 path. Reserves space using our own status item only;
// A separate invisible spacer reserves space; the standard arrow stays visible.
// macOS decides which items enter its native overflow. No visibility assertion
// is created, so system controls retain their normal activity-based policy.
// A requested collapse is not proof that every intended icon is in overflow.
final class SystemOverflowEngine: MenuBarEngine {
    private weak var items: MenuBarItemProvider?
    private let screenWidths: () -> [CGFloat]
    private let preferredLength: () -> CGFloat?
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private var generation = 0
    private var pendingCompletion: ((CollapseResult) -> Void)?
    private(set) var state: MenuBarEngineState = .expanded

    static let expandedLength: CGFloat = 1
    static let widthPreferenceKey = "overflowReservationWidth"
    // Give the native spacer a valid image without drawing a visible divider.
    static let invisibleSpacerImage = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in true }

    static let boundaryImage = NSImage(named: NSImage.Name("ic_line"))

    init(items: MenuBarItemProvider,
         screenWidths: @escaping () -> [CGFloat] = { NSScreen.screens.map { $0.frame.width } },
         preferredLength: @escaping () -> CGFloat? = {
             (UserDefaults.standard.object(forKey: widthPreferenceKey) as? NSNumber).map { CGFloat($0.doubleValue) }
         },
         schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, action in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
         }) {
        self.items = items
        self.screenWidths = screenWidths
        self.preferredLength = preferredLength
        self.schedule = schedule
        showBoundary(items.separatorItem)
    }

    // Stay below half of the narrowest display, with room for status-item
    // chrome. The old huge spacer can be dropped from macOS 27's layout.
    static func reservationLength(screenWidths: [CGFloat], preferredLength: CGFloat? = nil) -> CGFloat? {
        guard let narrowest = screenWidths.filter({ $0.isFinite && $0 > 0 }).min(),
              narrowest / 2 - 64 > expandedLength else { return nil }
        let maximum = min(narrowest / 2 - 64, 10_000)
        guard let preferred = preferredLength, preferred.isFinite, preferred > 0 else { return maximum }
        return min(maximum, max(40, preferred))
    }

    func collapse(completion: @escaping (CollapseResult) -> Void) {
        if state == .collapsed { return completion(.collapsed) }
        if state == .calibrating { return }
        guard let target = Self.reservationLength(screenWidths: screenWidths(), preferredLength: preferredLength()),
              items != nil else {
            state = .unavailable
            return completion(.unavailable)
        }
        reserve(target, completion: completion)
    }

    private func reserve(_ target: CGFloat, completion: @escaping (CollapseResult) -> Void) {
        guard let separator = items?.separatorItem else {
            generation += 1
            pendingCompletion = nil
            state = .unavailable
            return completion(.unavailable)
        }
        generation += 1
        let current = generation
        state = .calibrating
        pendingCompletion = completion
        // One invisible spacer changes in one step. The standard arrow is a
        // separate fixed-width item, so it cannot overflow with the spacer.
        separator.button?.image = Self.invisibleSpacerImage
        separator.button?.toolTip = nil
        if separator.length != target { separator.length = target }
        separator.isVisible = true
        schedule(0.15) { [weak self] in
            guard let self = self, self.generation == current, self.state == .calibrating else { return }
            self.state = .collapsed
            self.recordLayoutDiagnostic()
            NSLog("SystemOverflow: reservation=\(target); native overflow decides item visibility; no assessment assertion")
            self.finish(.collapsed)
        }
    }

    private func finish(_ result: CollapseResult) {
        let completion = pendingCompletion
        pendingCompletion = nil
        completion?(result)
    }

    private func recordLayoutDiagnostic() {
        #if DEBUG
        guard let items = items else { return }
        var values: [String: Any] = ["reservation": items.separatorItem.length]
        if let frame = items.separatorItem.button?.window?.frame {
            values["spacerFrame"] = NSStringFromRect(frame)
        }
        if let frame = items.toggleItem.button?.window?.frame {
            values["arrowFrame"] = NSStringFromRect(frame)
        }
        UserDefaults.standard.set(values, forKey: "overflowLayoutDiagnostic")
        #endif
    }

    func expand() {
        generation += 1
        pendingCompletion = nil
        if let separator = items?.separatorItem {
            showBoundary(separator)
        }
        state = .expanded
    }

    private func showBoundary(_ separator: NSStatusItem) {
        if separator.length != Self.expandedLength { separator.length = Self.expandedLength }
        separator.button?.image = Self.boundaryImage
        separator.button?.toolTip = NSLocalizedString("Move icons to hide to the left of this line using ⌘.", comment: "Visible hiding boundary tooltip")
        separator.isVisible = true
    }

    var supportsAlwaysHiddenSection: Bool { false }

    func updateAlwaysHiddenSection(enabled: Bool, separatorHidden: Bool) {
        // Native overflow remains accessible. It cannot implement a private,
        // always-hidden section, and must never silently use assessment instead.
        items?.alwaysHiddenItem?.length = 0
    }

    var isArrangementValid: Bool {
        // Keep the boundary in its native slot in both states. Expanded mode
        // displays the line so the user can arrange it with Command-drag.
        items?.toggleItem.isVisible == true
    }

    var isAlwaysHiddenSeparatorPlaced: Bool { false }

    func invalidateLayout() {
        guard state == .collapsed || state == .calibrating else { return }
        let completion = pendingCompletion
        guard let target = Self.reservationLength(screenWidths: screenWidths(), preferredLength: preferredLength()) else {
            expand()
            state = .unavailable
            completion?(.unavailable)
            return
        }
        // A geometry notification must not briefly reveal all icons or restart
        // a transition when the effective reservation has not changed.
        guard items?.separatorItem.length != target else { return }
        reserve(target, completion: completion ?? { _ in })
    }
}
