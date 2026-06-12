import AppKit

/// AppKit NSView that displays up/down speed as "↑ 1.2M ↓ 3.4M" in the menu bar.
@MainActor
public final class MenuBarSpeedView: NSView {
    private let label: NSTextField

    override public init(frame frameRect: NSRect) {
        self.label = NSTextField(labelWithString: "")
        super.init(frame: frameRect)
        setupLabel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func setupLabel() {
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    public func update(uploadBytesPerSec: Int64, downloadBytesPerSec: Int64) {
        let up = Self.format(uploadBytesPerSec)
        let down = Self.format(downloadBytesPerSec)
        let attributed = NSMutableAttributedString()
        attributed.append(NSAttributedString(
            string: "↑ \(up) ",
            attributes: [.foregroundColor: NSColor.systemBlue, .font: label.font!]
        ))
        attributed.append(NSAttributedString(
            string: "↓ \(down)",
            attributes: [.foregroundColor: NSColor.systemGreen, .font: label.font!]
        ))
        label.attributedStringValue = attributed
        label.sizeToFit()
        invalidateIntrinsicContentSize()
    }

    override public var intrinsicContentSize: NSSize {
        let labelSize = label.intrinsicContentSize
        return NSSize(width: labelSize.width + 16, height: 22)
    }

    nonisolated public static func format(_ bytesPerSec: Int64) -> String {
        let abs = Double(bytesPerSec.magnitude)
        if abs < 1_000 { return "<1K" }
        if abs < 1_000_000 { return String(format: "%.1fK", abs / 1_000) }
        if abs < 1_000_000_000 { return String(format: "%.1fM", abs / 1_000_000) }
        return String(format: "%.1fG", abs / 1_000_000_000)
    }
}
