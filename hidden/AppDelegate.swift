//
//  AppDelegate.swift
//  vanillaClone
//
//  Created by Thanh Nguyen on 1/24/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import AppKit
import HotKey
import Sparkle
import ServiceManagement

@NSApplicationMain

class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    
    var statusBarController = StatusBarController()

    // Sparkle owns downloading, EdDSA verification, installation and relaunch.
    // Keep the controller alive for the application's entire lifetime.
    lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    
    var hotKey: HotKey? {
        didSet {
            guard let hotKey = hotKey else { return }
            
            hotKey.keyDownHandler = { [weak self] in
                self?.statusBarController.expandCollapseIfNeeded()
            }
        }
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        updaterController.startUpdater()
        setupAutoStartApp()
        registerDefaultValues()
        setupHotKey()
        openPreferencesIfNeeded()
        detectLTRLang()
    }
    
    func feedURLString(for updater: SPUUpdater) -> String? {
        // A long-running menu-bar app can retain GitHub's previous latest-release
        // redirect. Give each check its own URL while retaining signed contents.
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              var components = URLComponents(string: feed) else { return nil }
        var query = components.queryItems ?? []
        query.append(URLQueryItem(name: "check", value: UUID().uuidString))
        components.queryItems = query
        return components.url?.absoluteString
    }

    func openPreferencesIfNeeded() {
        if Preferences.isShowPreference {
            Util.showPrefWindow()
        }
    }
    
    func setupAutoStartApp() {
        removeLegacyLauncherLoginItem()
        Util.setUpAutoStart(isAutoStart: Preferences.isAutoStart)
    }

    private func removeLegacyLauncherLoginItem() {
        // Builds before the SMAppService migration registered a helper app in BTM;
        // macOS never garbage-collects that record (TN3111), so deauthorize it once.
        let migratedKey = "smAppServiceMigrated"
        guard !UserDefaults.standard.bool(forKey: migratedKey) else { return }
        SMLoginItemSetEnabled("com.dwarvesv.LauncherApplication" as CFString, false)
        UserDefaults.standard.set(true, forKey: migratedKey)
    }
    
    func registerDefaultValues() {
         UserDefaults.standard.register(defaults: [
            UserDefaults.Key.isAutoStart: false,
            UserDefaults.Key.isShowPreference: true,
            UserDefaults.Key.isAutoHide: true,
            UserDefaults.Key.numberOfSecondForAutoHide: 10.0,
            UserDefaults.Key.areSeparatorsHidden: false,
            UserDefaults.Key.alwaysHiddenSectionEnabled: false
         ])
    }
    
    func setupHotKey() {
        guard let globalKey = Preferences.globalKey else {return}
        hotKey = HotKey(keyCombo: KeyCombo(carbonKeyCode: globalKey.keyCode, carbonModifiers: globalKey.carbonFlags))
    }
    
    func detectLTRLang() {
        // Languages like Arabic uses right to left (RTL) writing direction,
        // so some behavier of the app needs to be changed in these cases
        
        Constant.isUsingLTRLanguage = (NSApplication.shared.userInterfaceLayoutDirection == .leftToRight)
    }
   
}
