import Foundation
import Testing

@testable import Riptide

@Suite("SingBox config generator")
struct SingBoxConfigGeneratorTests {
    @Test("generates WireGuard outbound for GoCore")
    func generatesWireGuardOutboundForGoCore() throws {
        let node = ProxyNode(
            name: "warp",
            kind: .wireguard,
            server: "162.159.193.10",
            port: 2408,
            password: "private-key-base64",
            wireguardPublicKey: "public-key-base64",
            wireguardPreSharedKey: "psk-base64",
            wireguardReserved: [1, 2, 3],
            wireguardMTU: 1280,
            wireguardIP: "172.16.0.2/32"
        )
        let config = RiptideConfig(
            mode: .rule,
            proxies: [node],
            rules: [.final(policy: .proxyNode(name: "warp"))]
        )

        let json = try SingBoxConfigGenerator.generate(
            config: config,
            options: SingBoxConfigGenerator.GenerationOptions(mode: .systemProxy)
        )
        let data = try #require(json.data(using: .utf8))
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        let inbounds = try #require(root["inbounds"] as? [[String: Any]])
        #expect(inbounds.first?["type"] as? String == "mixed")
        #expect(inbounds.first?["listen_port"] as? Int == 6152)

        let outbounds = try #require(root["outbounds"] as? [[String: Any]])
        let wireguard = try #require(outbounds.first { $0["tag"] as? String == "warp" })
        #expect(wireguard["type"] as? String == "wireguard")
        #expect(wireguard["server"] as? String == "162.159.193.10")
        #expect(wireguard["server_port"] as? Int == 2408)
        #expect(wireguard["private_key"] as? String == "private-key-base64")
        #expect(wireguard["peer_public_key"] as? String == "public-key-base64")
        #expect(wireguard["pre_shared_key"] as? String == "psk-base64")
        #expect(wireguard["local_address"] as? [String] == ["172.16.0.2/32"])
        #expect(wireguard["reserved"] as? [Int] == [1, 2, 3])
        #expect(wireguard["mtu"] as? Int == 1280)

        let route = try #require(root["route"] as? [String: Any])
        #expect(route["final"] as? String == "warp")
    }

    // MARK: - vmess / vless / hysteria2 / tuic (sing-box v1.9.0 schema)

    private static let sampleUUID = "bf000d23-0752-40b4-affe-68f7707a9661"

    private func generateRoot(
        _ nodes: [ProxyNode],
        finalNode: String,
        supportsUTLS: Bool = false
    ) throws -> [String: Any] {
        let config = RiptideConfig(
            mode: .rule,
            proxies: nodes,
            rules: [.final(policy: .proxyNode(name: finalNode))]
        )
        let json = try SingBoxConfigGenerator.generate(
            config: config,
            options: SingBoxConfigGenerator.GenerationOptions(mode: .systemProxy, supportsUTLS: supportsUTLS)
        )
        let data = try #require(json.data(using: .utf8))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func outbound(_ root: [String: Any], tag: String) throws -> [String: Any] {
        let outbounds = try #require(root["outbounds"] as? [[String: Any]])
        return try #require(outbounds.first { $0["tag"] as? String == tag })
    }

    @Test("vmess ws+tls outbound uses snake_case keys and routes ws to transport")
    func vmessWsTls() throws {
        let node = ProxyNode(
            name: "vm", kind: .vmess, server: "ex.com", port: 443,
            uuid: Self.sampleUUID, alterId: 0, security: "auto",
            sni: "ex.com", alpn: ["h2"], tls: true,
            network: "ws", wsPath: "/p", wsHost: "ex.com"
        )
        let ob = try outbound(try generateRoot([node], finalNode: "vm"), tag: "vm")
        #expect(ob["type"] as? String == "vmess")
        #expect(ob["server_port"] as? Int == 443)
        #expect(ob["uuid"] as? String == Self.sampleUUID)
        #expect(ob["security"] as? String == "auto")
        #expect(ob["alter_id"] as? Int == 0)
        // ws must NOT leak into the L4 "network" key.
        #expect(ob["network"] == nil)

        let tls = try #require(ob["tls"] as? [String: Any])
        #expect(tls["enabled"] as? Bool == true)
        #expect(tls["server_name"] as? String == "ex.com")

        let transport = try #require(ob["transport"] as? [String: Any])
        #expect(transport["type"] as? String == "ws")
        #expect(transport["path"] as? String == "/p")
        #expect((transport["headers"] as? [String: Any])?["Host"] as? String == "ex.com")
    }

    @Test("vmess without tls omits the tls and transport objects")
    func vmessPlaintext() throws {
        let node = ProxyNode(name: "vm", kind: .vmess, server: "ex.com", port: 80, uuid: Self.sampleUUID)
        let ob = try outbound(try generateRoot([node], finalNode: "vm"), tag: "vm")
        #expect(ob["tls"] == nil)
        #expect(ob["transport"] == nil)
    }

    @Test("vless reality+vision outbound emits reality/utls and no transport")
    func vlessRealityVision() throws {
        let node = ProxyNode(
            name: "vl", kind: .vless, server: "ex.com", port: 443,
            uuid: Self.sampleUUID, flow: "xtls-rprx-vision",
            network: "tcp",
            realityServerName: "www.microsoft.com",
            realityShortId: "0123456789abcdef",
            realityPublicKey: "jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0",
            realityFingerprint: "chrome"
        )
        let ob = try outbound(try generateRoot([node], finalNode: "vl", supportsUTLS: true), tag: "vl")
        #expect(ob["type"] as? String == "vless")
        #expect(ob["flow"] as? String == "xtls-rprx-vision")
        // Vision is incompatible with a v2ray transport.
        #expect(ob["transport"] == nil)

        let tls = try #require(ob["tls"] as? [String: Any])
        #expect(tls["server_name"] as? String == "www.microsoft.com")
        // REALITY must not weaken verification.
        #expect(tls["insecure"] == nil)

        let utls = try #require(tls["utls"] as? [String: Any])
        #expect(utls["enabled"] as? Bool == true)
        #expect(utls["fingerprint"] as? String == "chrome")

        let reality = try #require(tls["reality"] as? [String: Any])
        #expect(reality["enabled"] as? Bool == true)
        #expect(reality["public_key"] as? String == "jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0")
        // short_id is a single STRING on the outbound side, not an array.
        #expect(reality["short_id"] as? String == "0123456789abcdef")
    }

    @Test("hysteria2 outbound carries mandatory tls with default h3 alpn")
    func hysteria2() throws {
        let node = ProxyNode(
            name: "hy", kind: .hysteria2, server: "ex.com", port: 443,
            password: "pw", sni: "ex.com", alpn: nil, skipCertVerify: true
        )
        let ob = try outbound(try generateRoot([node], finalNode: "hy"), tag: "hy")
        #expect(ob["type"] as? String == "hysteria2")
        #expect(ob["password"] as? String == "pw")
        #expect(ob["transport"] == nil)

        let tls = try #require(ob["tls"] as? [String: Any])
        #expect(tls["enabled"] as? Bool == true)
        #expect(tls["server_name"] as? String == "ex.com")
        #expect(tls["insecure"] as? Bool == true)
        #expect(tls["alpn"] as? [String] == ["h3"])
    }

    @Test("tuic outbound emits congestion_control and mandatory tls")
    func tuic() throws {
        let node = ProxyNode(
            name: "tu", kind: .tuic, server: "ex.com", port: 443,
            password: "pw", uuid: Self.sampleUUID, alpn: ["h3"],
            congestionControl: "bbr"
        )
        let ob = try outbound(try generateRoot([node], finalNode: "tu"), tag: "tu")
        #expect(ob["type"] as? String == "tuic")
        #expect(ob["uuid"] as? String == Self.sampleUUID)
        #expect(ob["password"] as? String == "pw")
        #expect(ob["congestion_control"] as? String == "bbr")
        #expect(ob["transport"] == nil)

        let tls = try #require(ob["tls"] as? [String: Any])
        #expect(tls["enabled"] as? Bool == true)
        #expect(tls["alpn"] as? [String] == ["h3"])
    }

    @Test("reality short_id absent defaults to empty string, not array")
    func realityShortIdDefault() throws {
        let node = ProxyNode(
            name: "vl", kind: .vless, server: "ex.com", port: 443,
            uuid: Self.sampleUUID,
            realityServerName: "www.apple.com",
            realityPublicKey: "jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0"
        )
        let ob = try outbound(try generateRoot([node], finalNode: "vl", supportsUTLS: true), tag: "vl")
        let reality = try #require((ob["tls"] as? [String: Any])?["reality"] as? [String: Any])
        #expect(reality["short_id"] as? String == "")
    }

    @Test("without utls support, reality degrades to plain TLS (no utls/reality keys)")
    func realityDegradesWithoutUTLS() throws {
        let node = ProxyNode(
            name: "vl", kind: .vless, server: "ex.com", port: 443,
            uuid: Self.sampleUUID, flow: "xtls-rprx-vision", network: "tcp",
            realityServerName: "www.microsoft.com",
            realityShortId: "0123456789abcdef",
            realityPublicKey: "jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0",
            realityFingerprint: "chrome"
        )
        // Default supportsUTLS == false (matches the shipped libgocore.a).
        let ob = try outbound(try generateRoot([node], finalNode: "vl"), tag: "vl")
        let tls = try #require(ob["tls"] as? [String: Any])
        #expect(tls["enabled"] as? Bool == true)
        #expect(tls["server_name"] as? String == "www.microsoft.com")
        // No uTLS/REALITY — would otherwise make the whole config fail to load.
        #expect(tls["utls"] == nil)
        #expect(tls["reality"] == nil)
    }
}
