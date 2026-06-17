import AppKit
import SwiftUI
import Riptide

@MainActor
public final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private weak var vm: AppViewModel?
    private var speedObservationTask: Task<Void, Never>?

    override public init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 400)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPlaceholderView()
        )

        super.init()
        configureStatusItem()
    }

    func setup(vm: AppViewModel) {
        self.vm = vm
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView(viewModel: vm)
        )
        startObservingSpeed()
    }

    private func startObservingSpeed() {
        speedObservationTask?.cancel()
        guard let vm else { return }
        speedObservationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let up = vm.currentSpeedUp
                let down = vm.currentSpeedDown
                let isRunning = vm.tunnelState == .running
                self.updateDisplay(uploadBytesPerSec: up, downloadBytesPerSec: down, isRunning: isRunning)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    deinit {
        speedObservationTask?.cancel()
    }

    private func updateDisplay(uploadBytesPerSec: Int64, downloadBytesPerSec: Int64, isRunning: Bool) {
        guard let button = statusItem.button else { return }

        // Render a single template SF Symbol and nothing else. A custom subview
        // (the old speed-text view) overflowed the status item's slot and drew
        // over neighbouring menu-bar items, so we never add subviews and force
        // image-only layout so the item width tracks the icon exactly.
        button.subviews.forEach { $0.removeFromSuperview() }
        button.title = ""
        button.imagePosition = .imageOnly

        let symbolName = isRunning ? "arrow.up.arrow.down" : "network"
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: isRunning ? "代理运行中" : "Riptide"
        )?.withSymbolConfiguration(config)
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = isRunning ? .systemGreen : .secondaryLabelColor
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleButtonClick)
        updateDisplay(uploadBytesPerSec: 0, downloadBytesPerSec: 0, isRunning: false)
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

/// Brief loading placeholder shown until the real view model is wired in.
private struct MenuBarPlaceholderView: View {
    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Riptide")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 360, height: 400)
    }
}
