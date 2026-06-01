import SwiftUI

public struct MenuBarPopoverView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            Text("Riptide")
                .font(.headline)
            Text("Menu Bar Popover")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Content coming in Task 7.8")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 360, height: 400)
    }
}
