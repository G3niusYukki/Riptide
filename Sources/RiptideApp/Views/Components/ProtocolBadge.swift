import SwiftUI
import Riptide

/// Renders a small colored capsule label for a proxy protocol.
struct ProtocolBadge: View {
    let kind: ProxyKind

    static func color(for kind: ProxyKind) -> Color {
        switch kind {
        case .shadowsocks: return Color(hex: "0fbcf9")  // cyan
        case .vmess: return Color(hex: "a55eea")        // purple
        case .vless: return Color(hex: "4834d4")        // blue
        case .trojan: return Color(hex: "f0932b")       // orange
        case .hysteria2: return Color(hex: "6ab04c")    // green
        case .tuic: return Color(hex: "f9ca24")         // yellow
        case .wireguard: return Color(hex: "eb4d4b")    // red
        case .http: return Color(hex: "95afc0")         // gray
        case .socks5: return Color(hex: "7ed6df")       // gray-blue
        case .snell: return Color(hex: "e056fd")        // pink
        case .anytls: return Color(hex: "22a6b3")       // teal
        case .ssh: return Color(hex: "636e72")          // dark gray
        case .relay: return Color(hex: "95afc0")        // gray (relay group)
        case .reality: return Color(hex: "4834d4")      // blue (VLESS combo)
        }
    }

    static func label(for kind: ProxyKind) -> String {
        switch kind {
        case .shadowsocks: return "SS"
        case .vmess: return "VMess"
        case .vless: return "VLESS"
        case .trojan: return "Trojan"
        case .hysteria2: return "Hy2"
        case .tuic: return "TUIC"
        case .wireguard: return "WG"
        case .http: return "HTTP"
        case .socks5: return "SOCKS5"
        case .snell: return "Snell"
        case .anytls: return "AnyTLS"
        case .ssh: return "SSH"
        case .relay: return "Relay"
        case .reality: return "VLESS+Reality"
        }
    }

    var body: some View {
        Text(ProtocolBadge.label(for: kind))
            .font(.caption2.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(ProtocolBadge.color(for: kind))
            .clipShape(Capsule())
            .accessibilityLabel("Protocol: \(ProtocolBadge.label(for: kind))")
    }
}

#Preview {
    HStack(spacing: 6) {
        ProtocolBadge(kind: .shadowsocks)
        ProtocolBadge(kind: .vmess)
        ProtocolBadge(kind: .trojan)
        ProtocolBadge(kind: .hysteria2)
    }
    .padding()
}
