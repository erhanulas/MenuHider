import AppKit

enum StatusMenuPlacement {
    // NSMenu with in:nil uses screen coordinates. Avoid the remote status
    // button's backing-window origin when determining the menu's vertical edge.
    static func anchor(mouse: NSPoint, screen: NSRect, visibleFrame: NSRect,
                       menuWidth: CGFloat, buttonWidth: CGFloat,
                       menuBarHeight: CGFloat, safeAreaTop: CGFloat) -> NSPoint {
        let barBottom = min(visibleFrame.maxY, screen.maxY - max(menuBarHeight, safeAreaTop))
        let rightmost = max(screen.minX, screen.maxX - menuWidth)
        let x = min(max(screen.minX, mouse.x - buttonWidth / 2), rightmost)
        return NSPoint(x: x, y: barBottom - 2)
    }
}
