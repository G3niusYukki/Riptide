import SwiftUI
import AppKit

@MainActor
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem?

    override init() {
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "network", accessibilityDescription: "Riptide")
        }
    }

    func update(image: String, tooltip: String) {
        statusItem?.button?.image = NSImage(systemSymbolName: image, accessibilityDescription: tooltip)
    }

    func update(tooltip: String) {
        statusItem?.button?.toolTip = tooltip
    }
}
