import Foundation
import Testing

@testable import Riptide

@Suite("Proxy URI serializer")
struct ProxyURISerializerTests {
    @Test("ss round-trip")
    func ssRoundTrip() {
        let node = ProxyNode(
            name: "MySS",
            kind: .shadowsocks,
            server: "ss.example.com",
            port: 8388,
            cipher: "aes-256-gcm",
            password: "secret-password"
        )
        let uri = ProxyURISerializer.makeURI(from: node)
        #expect(uri != nil)
        let parsed = ProxyURIParser.parse(uri!)
        #expect(parsed?.kind == .shadowsocks)
        #expect(parsed?.server == "ss.example.com")
        #expect(parsed?.port == 8388)
        #expect(parsed?.cipher == "aes-256-gcm")
        #expect(parsed?.password == "secret-password")
    }

    @Test("vless round-trip")
    func vlessRoundTrip() {
        let node = ProxyNode(
            name: "MyVLESS",
            kind: .vless,
            server: "vless.example.com",
            port: 443,
            uuid: "b2a3e7c1-1234-5678-90ab-cdef12345678",
            sni: "cdn.example.com"
        )
        let uri = ProxyURISerializer.makeURI(from: node)
        #expect(uri != nil)
        let parsed = ProxyURIParser.parse(uri!)
        #expect(parsed?.kind == .vless)
        #expect(parsed?.server == "vless.example.com")
        #expect(parsed?.port == 443)
        // Note: existing ProxyURIParser does not surface uuid in ParsedProxy;
        // we assert on what it does surface (server, port, kind).
    }

    @Test("trojan round-trip")
    func trojanRoundTrip() {
        let node = ProxyNode(
            name: "MyTrojan",
            kind: .trojan,
            server: "trojan.example.com",
            port: 443,
            password: "trojan-secret"
        )
        let uri = ProxyURISerializer.makeURI(from: node)
        #expect(uri != nil)
        let parsed = ProxyURIParser.parse(uri!)
        #expect(parsed?.kind == .trojan)
        #expect(parsed?.server == "trojan.example.com")
        #expect(parsed?.port == 443)
        #expect(parsed?.password == "trojan-secret")
    }

    @Test("vmess round-trip")
    func vmessRoundTrip() {
        let node = ProxyNode(
            name: "MyVMess",
            kind: .vmess,
            server: "vmess.example.com",
            port: 443,
            cipher: "auto",
            uuid: "11111111-2222-3333-4444-555555555555"
        )
        let uri = ProxyURISerializer.makeURI(from: node)
        #expect(uri != nil)
        let parsed = ProxyURIParser.parse(uri!)
        #expect(parsed?.kind == .vmess)
        #expect(parsed?.server == "vmess.example.com")
        #expect(parsed?.port == 443)
    }

    @Test("hysteria2 round-trip")
    func hysteria2RoundTrip() {
        let node = ProxyNode(
            name: "MyHy2",
            kind: .hysteria2,
            server: "hy2.example.com",
            port: 443,
            password: "hy2-secret",
            sni: "cdn.example.com"
        )
        let uri = ProxyURISerializer.makeURI(from: node)
        #expect(uri != nil)
        let parsed = ProxyURIParser.parse(uri!)
        #expect(parsed?.kind == .hysteria2)
        #expect(parsed?.server == "hy2.example.com")
        #expect(parsed?.port == 443)
        #expect(parsed?.password == "hy2-secret")
    }

    @Test("tuic round-trip")
    func tuicRoundTrip() {
        let node = ProxyNode(
            name: "MyTUIC",
            kind: .tuic,
            server: "tuic.example.com",
            port: 443,
            password: "tuic-secret",
            uuid: "uuid-aaaa-bbbb-cccc"
        )
        let uri = ProxyURISerializer.makeURI(from: node)
        #expect(uri != nil)
        let parsed = ProxyURIParser.parse(uri!)
        #expect(parsed?.kind == .tuic)
        #expect(parsed?.server == "tuic.example.com")
        #expect(parsed?.port == 443)
    }
}
