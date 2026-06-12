import SwiftUI
import AppKit

struct HotkeySettingsView: View {
    @ObservedObject var hotkeyManager: HotkeyManager
    @State private var recordingAction: HotkeyManager.HotkeyAction?
    @State private var recordingMonitor: Any?
    @State private var conflictWarning: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("快捷键设置")
                .font(.headline)
                .foregroundStyle(Theme.text)

            Text("⌃⌥P 可能在某些 IDE 中冲突；⌃⌥M 可能与 Spotlight 替代品冲突。")
                .font(.caption)
                .foregroundStyle(Theme.subtext)

            if let conflict = conflictWarning {
                Label(conflict, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
            }

            VStack(spacing: 8) {
                ForEach(HotkeyManager.HotkeyAction.allCases, id: \.self) { action in
                    HotkeyRow(
                        action: action,
                        shortcut: hotkeyManager.shortcuts.first(where: { $0.action == action }),
                        isRecording: recordingAction == action,
                        onRecord: { startRecording(for: action) },
                        onClear: { clearShortcut(for: action) }
                    )
                }
            }

            HStack {
                Spacer()
                Button("恢复默认") {
                    hotkeyManager.shortcuts = [
                        HotkeyManager.HotkeyShortcut(keyCode: 35, modifiers: [.option, .control], action: .toggleTunnel),
                        HotkeyManager.HotkeyShortcut(keyCode: 46, modifiers: [.option, .control], action: .toggleMode),
                    ]
                    hotkeyManager.save()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .onDisappear { stopRecording() }
    }

    private func startRecording(for action: HotkeyManager.HotkeyAction) {
        stopRecording()
        recordingAction = action
        conflictWarning = nil
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleRecordedKey(event, for: action)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor = recordingMonitor {
            NSEvent.removeMonitor(monitor)
            recordingMonitor = nil
        }
        recordingAction = nil
    }

    private func handleRecordedKey(_ event: NSEvent, for action: HotkeyManager.HotkeyAction) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Require at least one modifier
        guard !modifiers.isDisjoint(with: [.command, .control, .option]) else {
            conflictWarning = "请使用包含 ⌘/⌃/⌥ 的组合键"
            stopRecording()
            return
        }

        // Check for conflict with other Riptide shortcuts
        if hotkeyManager.shortcuts.contains(where: { $0.action != action && $0.keyCode == event.keyCode && $0.modifierFlags == modifiers.rawValue }) {
            conflictWarning = "该快捷键已被其他动作使用，将覆盖原有设置"
        }

        // Update or insert shortcut
        if let idx = hotkeyManager.shortcuts.firstIndex(where: { $0.action == action }) {
            hotkeyManager.shortcuts[idx].keyCode = event.keyCode
            hotkeyManager.shortcuts[idx].modifierFlags = modifiers.rawValue
        } else {
            hotkeyManager.shortcuts.append(HotkeyManager.HotkeyShortcut(
                keyCode: event.keyCode,
                modifiers: modifiers,
                action: action,
                isEnabled: true
            ))
        }
        hotkeyManager.save()
        stopRecording()
    }

    private func clearShortcut(for action: HotkeyManager.HotkeyAction) {
        hotkeyManager.shortcuts.removeAll { $0.action == action }
        hotkeyManager.save()
    }
}

private struct HotkeyRow: View {
    let action: HotkeyManager.HotkeyAction
    let shortcut: HotkeyManager.HotkeyShortcut?
    let isRecording: Bool
    let onRecord: () -> Void
    let onClear: () -> Void

    private var displayText: String {
        if isRecording { return "按下快捷键..." }
        guard let currentShortcut = shortcut else { return "未设置" }
        return HotkeyRow.format(keyCode: currentShortcut.keyCode, modifiers: currentShortcut.modifiers)
    }

    static func format(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        let keyName = keyCodeToString(keyCode)
        parts.append(keyName)
        return parts.joined()
    }

    private static func keyCodeToString(_ keyCode: UInt16) -> String {
        // Simplified key code map (extend as needed)
        let map: [UInt16: String] = [
            35: "P", 46: "M", 1: "S", 40: "K", 31: "O",
            38: "J", 2: "D", 8: "C", 14: "E", 3: "F",
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }

    var body: some View {
        HStack {
            Text(action.displayName)
                .foregroundStyle(Theme.text)
            Spacer()
            Text(displayText)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(isRecording ? Theme.warning : Theme.text)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isRecording ? Theme.warning.opacity(0.1) : Color.clear)
                .overlay(borderShape)

            Button(isRecording ? "取消" : (shortcut == nil ? "录制" : "重新录制")) {
                onRecord()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            if shortcut != nil && !isRecording {
                Button("清除", action: onClear)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(Theme.danger)
            }
        }
    }

    private var borderShape: some View {
        RoundedRectangle(cornerRadius: 4).strokeBorder(
            isRecording ? Theme.warning : Theme.subtext.opacity(0.3),
            style: isRecording ? StrokeStyle(lineWidth: 1.5, dash: [4]) : StrokeStyle(lineWidth: 1)
        )
    }
}
