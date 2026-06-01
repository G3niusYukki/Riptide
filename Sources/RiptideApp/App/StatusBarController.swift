import AppKit
import SwiftUI
import Riptide

@MainActor
public final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private weak var vm: AppViewModel?

    public override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 400)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView()
        )

        super.init()
        configureStatusItem()
    }

    func setup(vm: AppViewModel) {
        self.vm = vm
    }

    func updateButton(isRunning: Bool) {
        guard let button = statusItem.button else { return }
        let symbolName = isRunning ? "network.badge.shield.half.filled" : "network"
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Riptide")?
            .withSymbolConfiguration(config)
        button.image?.isTemplate = true
        button.contentTintColor = isRunning ? .systemGreen : .secondaryLabelColor
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleButtonClick)
        updateButton(isRunning: false)
    }

    @objc private func handleButtonClick() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
