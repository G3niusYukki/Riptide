import AppKit

/// Provides an `NSTouchBar` showing the first proxy group's nodes, a mode
/// toggle button, and a test-delay button.
///
/// Touch Bar hardware only exists on 2016-2021 MacBook Pros. On other Macs
/// the system silently does not show the bar — the provider compiles and
/// runs everywhere, it just has no visible effect on machines without a
/// Touch Bar.
///
/// The provider is wired to `AppViewModel` via a weak reference (dependency
/// injection point). When the view model is nil — e.g. after the app is
/// torn down — the touch bar items no-op rather than crash.
@MainActor
public final class TouchBarProvider: NSObject {

    public static let shared = TouchBarProvider()

    public weak var appViewModel: AppViewModel?

    public static let touchBarIdentifier: NSTouchBar.CustomizationIdentifier = "com.riptide.app.touchbar"
    public static let modeButtonIdentifier = NSTouchBarItem.Identifier("com.riptide.app.touchbar.mode")
    public static let groupScrubberIdentifier = NSTouchBarItem.Identifier("com.riptide.app.touchbar.group-scrubber")
    public static let testDelayButtonIdentifier = NSTouchBarItem.Identifier("com.riptide.app.touchbar.test-delay")

    private static let nodeItemIdentifier = NSUserInterfaceItemIdentifier("com.riptide.app.touchbar.node-item")
    private static let maxScrubberItems = 8

    private weak var cachedScrubber: NSScrubber?
    private weak var cachedModeButton: NSButton?

    public func makeTouchBar() -> NSTouchBar {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.customizationIdentifier = Self.touchBarIdentifier
        bar.defaultItemIdentifiers = [
            Self.modeButtonIdentifier,
            Self.groupScrubberIdentifier,
            Self.testDelayButtonIdentifier,
        ]
        bar.customizationAllowedItemIdentifiers = [
            Self.modeButtonIdentifier,
            Self.groupScrubberIdentifier,
            Self.testDelayButtonIdentifier,
        ]
        return bar
    }

    // MARK: - Helpers

    private var currentGroup: ProxyGroupDisplay? {
        appViewModel?.proxyGroups.first
    }

    private var modeButtonTitle: String {
        guard let vm = appViewModel else { return "模式" }
        switch vm.connectionMode {
        case .systemProxy: return "系统代理"
        case .tun: return "TUN"
        }
    }

    // MARK: - Actions

    @objc private func handleModeButton() {
        guard let vm = appViewModel else { return }
        Task { @MainActor in
            if vm.tunnelState == .running {
                await vm.stop()
            } else {
                vm.connectionMode = (vm.connectionMode == .systemProxy) ? .tun : .systemProxy
            }
            cachedModeButton?.title = modeButtonTitle
        }
    }

    @objc private func handleTestDelay() {
        guard let vm = appViewModel else { return }
        Task { @MainActor in
            await vm.testDelay()
            cachedScrubber?.reloadData()
        }
    }
}

// MARK: - NSTouchBarDelegate

extension TouchBarProvider: NSTouchBarDelegate {
    public func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        switch identifier {
        case Self.modeButtonIdentifier:
            return makeModeButtonItem(identifier: identifier)
        case Self.groupScrubberIdentifier:
            return makeScrubberItem(identifier: identifier)
        case Self.testDelayButtonIdentifier:
            return makeTestDelayButtonItem(identifier: identifier)
        default:
            return nil
        }
    }

    private func makeModeButtonItem(identifier: NSTouchBarItem.Identifier) -> NSCustomTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.customizationLabel = "代理模式"
        let button = NSButton(
            title: modeButtonTitle,
            target: self,
            action: #selector(handleModeButton)
        )
        button.bezelColor = .systemBlue
        item.view = button
        cachedModeButton = button
        return item
    }

    private func makeScrubberItem(identifier: NSTouchBarItem.Identifier) -> NSCustomTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.customizationLabel = "代理组节点"
        let scrubber = NSScrubber()
        scrubber.scrubberLayout = NSScrubberFlowLayout()
        scrubber.dataSource = self
        scrubber.delegate = self
        scrubber.mode = .free
        scrubber.selectionBackgroundStyle = NSScrubberSelectionStyle.roundedBackground
        scrubber.register(
            NSScrubberTextItemView.self,
            forItemIdentifier: Self.nodeItemIdentifier
        )
        item.view = scrubber
        cachedScrubber = scrubber
        return item
    }

    private func makeTestDelayButtonItem(identifier: NSTouchBarItem.Identifier) -> NSCustomTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.customizationLabel = "测试延迟"
        let button = NSButton(
            title: "测试延迟",
            target: self,
            action: #selector(handleTestDelay)
        )
        item.view = button
        return item
    }
}

// MARK: - NSScrubberDataSource, NSScrubberDelegate

extension TouchBarProvider: NSScrubberDataSource, NSScrubberDelegate {
    public func numberOfItems(for scrubber: NSScrubber) -> Int {
        guard let group = currentGroup else { return 0 }
        return min(Self.maxScrubberItems, group.nodes.count)
    }

    public func scrubber(_ scrubber: NSScrubber, viewForItemAt index: Int) -> NSScrubberItemView {
        let view = scrubber.makeItem(withIdentifier: Self.nodeItemIdentifier, owner: nil) as? NSScrubberTextItemView
            ?? NSScrubberTextItemView()
        if let group = currentGroup, index < group.nodes.count {
            let node = group.nodes[index]
            view.textField.stringValue = node.name
            if let selected = group.selectedNodeName, node.name == selected {
                view.textField.textColor = .systemBlue
            } else {
                view.textField.textColor = .labelColor
            }
        }
        return view
    }

    public func scrubber(_ scrubber: NSScrubber, didSelectItemAt index: Int) {
        guard let vm = appViewModel,
              let group = currentGroup,
              index < group.nodes.count else { return }
        let nodeName = group.nodes[index].name
        let groupID = group.id
        Task { @MainActor in
            await vm.selectProxy(groupID: groupID, nodeName: nodeName)
            cachedScrubber?.reloadData()
        }
    }
}
