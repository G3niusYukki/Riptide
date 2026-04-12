import Foundation

/// TUIC protocol configuration model.
/// TUIC (Transparent UDP and ICMP over QUIC) is a modern proxy protocol
/// that provides secure, low-latency connections over QUIC.
public struct TUICConfig: Sendable, Codable {
    public let uuid: UUID
    public let password: String
    public let server: String
    public let port: Int
    public let congestionControl: CongestionControl
    public let udpRelayMode: UDPRelayMode
    public let zeroRTTHandshake: Bool
    public let sni: String?
    public let alpn: [String]?

    public enum CongestionControl: String, Sendable, Codable, CaseIterable {
        case bbr
        case cubic
        case newReno = "new_reno"
    }

    public enum UDPRelayMode: String, Sendable, Codable, CaseIterable {
        case native
        case quic
    }

    public init(
        uuid: UUID,
        password: String,
        server: String,
        port: Int,
        congestionControl: CongestionControl = .bbr,
        udpRelayMode: UDPRelayMode = .native,
        zeroRTTHandshake: Bool = true,
        sni: String? = nil,
        alpn: [String]? = nil
    ) {
        self.uuid = uuid
        self.password = password
        self.server = server
        self.port = port
        self.congestionControl = congestionControl
        self.udpRelayMode = udpRelayMode
        self.zeroRTTHandshake = zeroRTTHandshake
        self.sni = sni
        self.alpn = alpn
    }
}

/// Errors that can occur during TUIC operations.
public enum TUICError: Error, Sendable {
    case invalidConfiguration(String)
    case connectionFailed(String)
    case authenticationFailed
    case streamClosed
    case notConnected
    case timeout
    case unsupportedOnOlderOS
}
