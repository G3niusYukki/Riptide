import SwiftUI
import AppKit
import Riptide

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private weak var vm: AppViewModel?

    override init() {
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Use view (not button) so we fully control click handling.
        let barView = StatusBarView(frame: NSRect(x: 0, y: 0, width: 44, height: 22))
        barView.onLeftClick = { [weak self] in self?.openMainWindow() }
        barView.onRightClick = { [weak self] in self?.showMenu() }
        barView.onMouseEntered = { barView.setHighlighted(true) }
        barView.onMouseExited = { barView.setHighlighted(false) }
        statusItem?.view = barView
        self.barView = barView

        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
        self.statusMenu = menu

        updateButton(isRunning: false)
    }

    private var barView: StatusBarView?

    func setup(vm: AppViewModel) {
        self.vm = vm
    }

    private func showMenu() {
        guard let vm = vm else { return }
        buildMenu(vm: vm)
        guard let menu = statusMenu, let view = barView else { return }
        statusItem?.menu = menu
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: view)
        statusItem?.menu = nil
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        guard let vm = vm else { return }
        buildMenu(vm: vm)
        statusMenu?.delegate = nil
    }

    // MARK: - Menu Building

    private func buildMenu(vm: AppViewModel) {
        let menu = NSMenu()

        let isRunning = vm.tunnelState == .running
        let statusText = isRunning ? "已连接" : "未连接"
        let statusIcon = isRunning ? "🟢" : "⚪️"
        let s = NSMenuItem(title: "\(statusIcon) \(statusText)", action: nil, keyEquivalent: "")
        s.isEnabled = false
        menu.addItem(s)

        let up = formatSpeed(vm.currentSpeedUp)
        let down = formatSpeed(vm.currentSpeedDown)
        let speed = NSMenuItem(title: "↑ \(up)  ↓ \(down)", action: nil, keyEquivalent: "")
        speed.isEnabled = false
        menu.addItem(speed)

        menu.addItem(NSMenuItem.separator())

        let modeMenu = NSMenu()
        let currentMode = vm.proxyMode
        for mode in [ProxyMode.rule, .global, .direct] {
            let item = NSMenuItem(title: mode.rawValue.uppercased(), action: #selector(switchMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode
            item.state = (currentMode == mode) ? .on : .off
            modeMenu.addItem(item)
        }
        let modeItem = NSMenuItem(title: "模式", action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        menu.addItem(NSMenuItem.separator())

        let groups = vm.proxyGroups
        for group in groups {
            let groupMenu = NSMenu()
            for node in group.nodes {
                let item = NSMenuItem(title: node.name, action: #selector(selectNode(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = (groupID: group.id, nodeName: node.name)
                item.state = (node.name == group.selectedNodeName) ? .on : .off
                groupMenu.addItem(item)
            }
            let groupItem = NSMenuItem(title: group.name, action: nil, keyEquivalent: "")
            groupItem.submenu = groupMenu
            menu.addItem(groupItem)
        }

        menu.addItem(NSMenuItem.separator())

        let testItem = NSMenuItem(title: "延迟测试", action: #selector(testDelay), keyEquivalent: "")
        testItem.target = self
        menu.addItem(testItem)

        let toggleTitle = isRunning ? "停止" : "启动"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleTunnel), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        let openItem = NSMenuItem(title: "打开主窗口", action: #selector(openMainWindowAction), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        self.statusMenu = menu
    }

    @objc private func switchMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? ProxyMode else { return }
        Task { @MainActor in
            await vm?.switchMode(mode)
        }
    }

    @objc private func selectNode(_ sender: NSMenuItem) {
        guard let tuple = sender.representedObject as? (groupID: String, nodeName: String) else { return }
        Task { @MainActor in
            await vm?.selectProxy(groupID: tuple.groupID, nodeName: tuple.nodeName)
        }
    }

    @objc private func testDelay() {
        Task { @MainActor in
            await vm?.testDelay()
        }
    }

    @objc private func toggleTunnel() {
        Task { @MainActor in
            await vm?.toggleTunnel()
        }
    }

    @objc private func openMainWindowAction() {
        openMainWindow()
    }

    func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        let targetWindow: NSWindow?
        if let window = vm?.mainWindow {
            targetWindow = window
        } else if let window = AppCoordinator.shared.mainWindow {
            targetWindow = window
        } else {
            targetWindow = NSApp.windows.first
        }

        if let window = targetWindow {
            // Ensure window is on screen
            if let screen = NSScreen.main ?? NSScreen.screens.first {
                let screenFrame = screen.visibleFrame
                let windowFrame = window.frame
                let windowRight = windowFrame.origin.x + windowFrame.width
                let screenRight = screenFrame.origin.x + screenFrame.width
                if windowRight > screenRight + 100 || windowFrame.origin.x < screenFrame.origin.x - 100 {
                    let centerX = screenFrame.origin.x + (screenFrame.width - windowFrame.width) / 2
                    let centerY = screenFrame.origin.y + (screenFrame.height - windowFrame.height) / 2
                    window.setFrameOrigin(NSPoint(x: centerX, y: centerY))
                }
            }
            window.makeKeyAndOrderFront(nil)
        }
    }

    func updateButton(isRunning: Bool) {
        barView?.updateIcon(isRunning: isRunning)
    }

    private func formatSpeed(_ bytesPerSec: Int64) -> String {
        if bytesPerSec < 1024 { return "\(bytesPerSec) B/s" }
        if bytesPerSec < 1024 * 1024 { return String(format: "%.1f KB/s", Double(bytesPerSec) / 1024) }
        return String(format: "%.1f MB/s", Double(bytesPerSec) / 1024 / 1024)
    }
}

// MARK: - Status Bar View

final class StatusBarView: NSView {
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?

    private var trackingArea: NSTrackingArea?
    private var isHighlighted = false
    private let imageView: NSImageView

    override init(frame frameRect: NSRect) {
        imageView = NSImageView(frame: .zero)
        super.init(frame: frameRect)
        imageView.frame = bounds
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleProportionallyDown
        imageView.isEditable = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 18),
            imageView.heightAnchor.constraint(equalToConstant: 18),
        ])
        wantsLayer = true
        layer?.cornerRadius = 4
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseDown(with event: NSEvent) {
        let isRight = event.type == .rightMouseDown || event.modifierFlags.contains(.control)
        if !isRight {
            isHighlighted = true
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        let isRight = event.type == .rightMouseUp || event.modifierFlags.contains(.control)
        isHighlighted = false
        needsDisplay = true
        if !isRight {
            onLeftClick?()
        } else {
            onRightClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        // Don't highlight on right-click; handle in rightMouseUp
    }

    override func rightMouseUp(with event: NSEvent) {
        onRightClick?()
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
        needsDisplay = true
        onMouseExited?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.25).setFill()
            let path = NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4)
            path.fill()
        }
    }

    func setHighlighted(_ on: Bool) {
        isHighlighted = on
        needsDisplay = true
    }

    func updateIcon(isRunning: Bool) {
        let symbolName = isRunning ? "network.badge.shield.half.filled" : "network"
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Riptide")?
            .withSymbolConfiguration(config)
        imageView.contentTintColor = isRunning ? .systemGreen : .secondaryLabelColor
    }
}
