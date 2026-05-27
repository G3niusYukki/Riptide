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
}
