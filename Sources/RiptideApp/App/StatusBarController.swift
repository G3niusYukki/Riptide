import SwiftUI
import AppKit
import Riptide

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var statusMenu: NSMenu?
    private weak var vm: AppViewModel?

    func setup(vm: AppViewModel) {
        self.vm = vm
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.action = #selector(toggleMenu)
        statusItem?.button?.target = self
        updateButton(isRunning: false)
    }

    @objc private func toggleMenu() {
        guard let vm = vm else { return }
        if let menu = statusMenu {
            statusItem?.menu = menu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else {
            buildMenu(vm: vm)
            statusItem?.menu = statusMenu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        }
    }

    private func buildMenu(vm: AppViewModel) {
        let menu = NSMenu()

        // Status section
        let statusText = vm.tunnelState == .running ? "已连接" : "未连接"
        let statusIcon = vm.tunnelState == .running ? "🟢" : "⚪️"
        let statusItem = NSMenuItem(title: "\(statusIcon) \(statusText)", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        let speedItem = NSMenuItem(title: "↑ \(formatSpeed(vm.currentSpeedUp))  ↓ \(formatSpeed(vm.currentSpeedDown))", action: nil, keyEquivalent: "")
        speedItem.isEnabled = false
        menu.addItem(speedItem)

        menu.addItem(NSMenuItem.separator())

        // Mode section
        let modeMenu = NSMenu()
        for mode in [ProxyMode.rule, .global, .direct] {
            let item = NSMenuItem(title: mode.rawValue.uppercased(), action: #selector(switchMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode
            item.state = (vm.proxyMode == mode) ? .on : .off
            modeMenu.addItem(item)
        }
        let modeItem = NSMenuItem(title: "模式", action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        menu.addItem(NSMenuItem.separator())

        // Proxy groups
        for group in vm.proxyGroups {
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

        // Test delay
        let testItem = NSMenuItem(title: "延迟测试", action: #selector(testDelay), keyEquivalent: "")
        testItem.target = self
        menu.addItem(testItem)

        // Toggle tunnel
        let toggleTitle = vm.tunnelState == .running ? "停止" : "启动"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleTunnel), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        // Open main window
        let openItem = NSMenuItem(title: "打开主窗口", action: #selector(openMainWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        self.statusMenu = menu
    }

    @objc private func switchMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? ProxyMode else { return }
        Task { await vm?.switchMode(mode) }
    }

    @objc private func selectNode(_ sender: NSMenuItem) {
        guard let tuple = sender.representedObject as? (groupID: String, nodeName: String) else { return }
        Task { await vm?.selectProxy(groupID: tuple.groupID, nodeName: tuple.nodeName) }
    }

    @objc private func testDelay() {
        Task { await vm?.testDelay() }
    }

    @objc private func toggleTunnel() {
        Task { await vm?.toggleTunnel() }
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func updateButton(isRunning: Bool) {
        let symbolName = isRunning ? "network.badge.shield.half.filled" : "network"
        statusItem?.button?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Riptide")
        statusItem?.button?.contentTintColor = isRunning ? .systemGreen : .secondaryLabelColor
    }

    private func formatSpeed(_ bytesPerSec: Int64) -> String {
        if bytesPerSec < 1024 { return "\(bytesPerSec) B/s" }
        if bytesPerSec < 1024 * 1024 { return String(format: "%.1f KB/s", Double(bytesPerSec) / 1024) }
        return String(format: "%.1f MB/s", Double(bytesPerSec) / 1024 / 1024)
    }
}
