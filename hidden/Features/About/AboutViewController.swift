//
//  AboutViewController.swift
//  Hidden Bar
//
//  Created by phucld on 12/19/19.
//  Copyright © 2019 Dwarves Foundation. All rights reserved.
//

import Cocoa
import Sparkle

class AboutViewController: NSViewController {

    @IBOutlet weak var lblVersion: NSTextField!
    private var updateObservation: NSKeyValueObservation?
    
    static func initWithStoryboard() -> AboutViewController {
        let vc = NSStoryboard(name:"Main", bundle: nil).instantiateController(withIdentifier: "aboutVC") as! AboutViewController
        return vc
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupUpdateButton()
    }
    
    private func setupUpdateButton() {
        guard let app = NSApp.delegate as? AppDelegate else { return }
        let controller = app.updaterController
        let button = NSButton(title: "Check for Updates…".localized,
                              target: controller,
                              action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)))
        button.bezelStyle = .rounded
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: lblVersion.leadingAnchor),
            button.topAnchor.constraint(equalTo: lblVersion.bottomAnchor, constant: 18)
        ])
        updateObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak button] updater, _ in
            button?.isEnabled = updater.canCheckForUpdates
        }
    }

    private func setupUI() {
        guard let version = Bundle.main.releaseVersionNumber,
                let buildNumber = Bundle.main.buildVersionNumber else { return }
        lblVersion.stringValue += " \(version) (\(buildNumber))"
    }
    
}
