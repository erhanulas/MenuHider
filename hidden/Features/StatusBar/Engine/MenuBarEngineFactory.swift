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
        usesSystemOverflow(on: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }

    static func usesSystemOverflow(on majorVersion: Int) -> Bool {
        #if HIDDENBAR_NATIVE_VISIBILITY
        // A spacer can fit on a wide display without overflowing any apps.
        // Direct builds use native hiding so no empty reservation remains.
        return false
        #else
        // The sandboxed build cannot read other apps' Accessibility sections.
        return majorVersion >= 27
        #endif
    }

    static func make(items: MenuBarItemProvider,
                     osMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) -> MenuBarEngine {
        if usesSystemOverflow(on: osMajorVersion) {
            return SystemOverflowEngine(items: items)
        }
        // macOS 27 ejects an inflated separator from the menu bar (#360). The
        // direct build hides natively there instead. The App Store build cannot:
        // the sandbox blocks the Accessibility reads that locate the sections.
        #if HIDDENBAR_NATIVE_VISIBILITY
        if osMajorVersion >= 27 {
            return NativeVisibilityEngine(items: items)
        }
        #endif
        items.separatorItem.isVisible = true
        return LegacyLengthEngine(items: items)
    }
}
