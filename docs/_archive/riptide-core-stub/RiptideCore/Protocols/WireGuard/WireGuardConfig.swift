import Foundation

// MARK: - WireGuard Configuration

/// WireGuard tunnel configuration — maps to `ProxyNode` WireGuard fields.
public struct WireGuardConfig: Sendable, Equatable {
    /// Local private key (base64-encoded Curve25519).
    public let privateKey: String

    /// Local IP address with CIDR prefix (e.g., "172.16.0.2/32").
    public let localAddress: String

    /// DNS servers pushed by the WireGuard peer (optional).
    public let dnsServers: [String]

    /// Maximum transmission unit (default 1420).
    public let mtu: Int

    /// List of peers (typically one).
    public let peers: [WireGuardPeer]

    public struct WireGuardPeer: Sendable, Equatable {
        /// Peer's public key (base64-encoded Curve25519).
        public let publicKey: String

        /// Pre-shared key for post-quantum resistance (optional, base64-encoded).
        public let preSharedKey: String?

        /// Endpoint host:port (e.g., "demo.wireguard.com:51820").
        public let endpoint: String

        /// Allowed IP ranges (CIDR notation).
        public let allowedIPs: [String]

        /// Persistent keepalive interval in seconds (0 = disabled).
        public let persistentKeepalive: Int

        /// Reserved bytes for obfuscation (optional, 3 bytes base64-encoded).
        public let reserved: Data?

        public init(
            publicKey: String,
            preSharedKey: String? = nil,
            endpoint: String,
            allowedIPs: [String] = ["0.0.0.0/0"],
            persistentKeepalive: Int = 25,
            reserved: Data? = nil
        ) {
            self.publicKey = publicKey
            self.preSharedKey = preSharedKey
            self.endpoint = endpoint
            self.allowedIPs = allowedIPs
            self.persistentKeepalive = persistentKeepalive
            self.reserved = reserved
        }
    }

    public init(
        privateKey: String,
        localAddress: String,
        dnsServers: [String] = [],
        mtu: Int = 1420,
        peers: [WireGuardPeer]
    ) {
        self.privateKey = privateKey
        self.localAddress = localAddress
        self.dnsServers = dnsServers
        self.mtu = mtu
        self.peers = peers
    }
}

// MARK: - WireGuard Protocol Constants

enum WireGuardConstants {
    /// WireGuard default port.
    static let defaultPort: UInt16 = 51820

    /// Recommended MTU for WireGuard over UDP.
    static let defaultMTU: Int = 1420

    /// Maximum UDP datagram size (IPv4).
    static let maxDatagramSize: Int = 65535

    /// Maximum message size considering overhead.
    static let maxMessageSize: Int = maxDatagramSize - 32

    /// Rekey-after interval: 120 seconds after initiation.
    static let rekeyAfterSeconds: TimeInterval = 120

    /// Reject-after interval: 180 seconds of no response → tear down.
    static let rejectAfterSeconds: TimeInterval = 180

    /// Keepalive interval (default for persistent keepalive).
    static let keepaliveIntervalSeconds: Int = 25

    /// Handshake initiation retry interval.
    static let handshakeRetrySeconds: TimeInterval = 5

    /// Maximum handshake retries before giving up.
    static let maxHandshakeRetries: Int = 5

    // MARK: - Noise Protocol Constants

    /// Noise protocol name: Noise_IK_25519_ChaChaPoly_BLAKE2s
    static let noiseProtocol = "Noise_IK_25519_ChaChaPoly_BLAKE2s"

    /// Construction identifier for WireGuard's Noise IK pattern.
    static let construction = "WireGuard v1 zx2c4 Jason@zx2c4.com"

    /// Label for initial chain key derivation.
    static func label(_ purpose: String) -> Data {
        let prefix = Data(construction.utf8)
        let suffix = Data(purpose.utf8)
        return prefix + suffix
    }

    // MARK: - Message Types

    enum MessageType: UInt8 {
        case invalid = 0
        case initiateHandshake = 1
        case respondHandshake = 2
        case cookieReply = 3
        case transportData = 4
    }
}
