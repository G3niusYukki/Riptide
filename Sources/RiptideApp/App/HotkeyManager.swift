import Foundation
import AppKit

/// Manages global keyboard shortcuts using NSEvent global monitors.
@MainActor
public final class HotkeyManager: ObservableObject {
    @Published public var shortcuts: [HotkeyShortcut]

    public struct HotkeyShortcut: Identifiable, Codable, Equatable {
        public let id: UUID
        public var keyCode: UInt16
        public var modifierFlags: UInt
        public var action: HotkeyAction
        public var isEnabled: Bool

        public var modifiers: NSEvent.ModifierFlags {
            get { NSEvent.ModifierFlags(rawValue: modifierFlags) }
            set { modifierFlags = newValue.rawValue }
        }

        public init(id: UUID = UUID(), keyCode: UInt16, modifiers: NSEvent.ModifierFlags, action: HotkeyAction, isEnabled: Bool = true) {
            self.id = id
            self.keyCode = keyCode
            self.modifierFlags = modifiers.rawValue
            self.action = action
            self.isEnabled = isEnabled
        }
    }

    public enum HotkeyAction: String, Codable, CaseIterable {
        case toggleTunnel = "toggleTunnel"
        case toggleMode = "toggleMode"
        case showPanel = "showPanel"

        public var displayName: String {
            switch self {
            case .toggleTunnel: return "开关代理"
            case .toggleMode: return "切换模式"
            case .showPanel: return "显示面板"
            }
        }
    }

    private var monitor: Any?
    private var actionHandler: ((HotkeyAction) -> Void)?
    private let defaultsKey = "riptide.hotkeys"

    public init() {
        let stored = UserDefaults.standard.data(forKey: defaultsKey)
        if let data = stored, let decoded = try? JSONDecoder().decode([HotkeyShortcut].self, from: data) {
            self.shortcuts = decoded
        } else {
            // Default: Option+Control+P for toggle, Option+Control+M for mode
            self.shortcuts = [
                HotkeyShortcut(keyCode: 35, modifiers: [.option, .control], action: .toggleTunnel),  // P key
                HotkeyShortcut(keyCode: 46, modifiers: [.option, .control], action: .toggleMode),     // M key
            ]
        }
    }

    /// Registers all enabled hotkeys with the system.
    public func registerHotkeys(actionHandler: @escaping (HotkeyAction) -> Void) {
        unregisterHotkeys()
        self.actionHandler = actionHandler

        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                for shortcut in self.shortcuts where shortcut.isEnabled {
                    if event.keyCode == shortcut.keyCode && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == shortcut.modifiers {
                        self.actionHandler?(shortcut.action)
                        break
                    }
                }
            }
        }
    }

    /// Unregisters all hotkeys.
    public func unregisterHotkeys() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        actionHandler = nil
    }

    /// Saves current shortcuts to UserDefaults.
    public func save() {
        if let data = try? JSONEncoder().encode(shortcuts) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
