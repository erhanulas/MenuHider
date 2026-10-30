//
//  MenuBarEngineFactory.swift
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

import Foundation

// The single place that picks a hiding mechanism for the running OS.
enum MenuBarEngineFactory {
    static var usesSystemOverflow: Bool {
        // Preserve activity-based system controls by default on macOS 27.
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
    }

    static func make(items: MenuBarItemProvider) -> MenuBarEngine {
        if usesSystemOverflow {
            return SystemOverflowEngine(items: items)
        }
        // macOS 27 ejects an inflated separator from the menu bar (#360). The
        // direct build hides natively there instead. The App Store build cannot:
        // the sandbox blocks the Accessibility reads that locate the sections.
        #if HIDDENBAR_NATIVE_VISIBILITY
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 {
            return NativeVisibilityEngine(items: items)
        }
        #endif
        items.separatorItem.isVisible = true
        return LegacyLengthEngine(items: items)
    }
}
