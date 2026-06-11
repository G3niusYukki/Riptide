import SwiftUI

/// Renders a flag emoji for a node name, falling back to a globe if no region is detected.
struct CountryFlagView: View {
    let nodeName: String
    let size: CGFloat

    init(nodeName: String, size: CGFloat = 14) {
        self.nodeName = nodeName
        self.size = size
    }

    var body: some View {
        Text(RegionMapping.flagEmoji(for: RegionMapping.isoCode(for: nodeName) ?? ""))
            .font(.system(size: size))
            .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        RegionMapping.isoCode(for: nodeName).map { "Region: \($0)" } ?? "Region: unknown"
    }
}

#Preview {
    HStack(spacing: 12) {
        CountryFlagView(nodeName: "香港01")
        CountryFlagView(nodeName: "JP-Tokyo")
        CountryFlagView(nodeName: "未知节点")
    }
    .padding()
}
