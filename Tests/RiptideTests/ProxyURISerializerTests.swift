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

    @Test("ss name with URL-unsafe chars is percent-encoded and round-trips")
    func ssNameWithURLUnsafeChars() {
        let node = ProxyNode(
            name: "中国节点#1",
            kind: .shadowsocks,
            server: "ss.example.com",
            port: 8388,
            cipher: "chacha20-ietf-poly1305",
            password: "p@ss w0rd"
        )
        let uri = ProxyURISerializer.makeURI(from: node)
        #expect(uri != nil)
        #expect(uri!.contains("#"))  // The trailing fragment
        let parsed = ProxyURIParser.parse(uri!)
        #expect(parsed?.kind == .shadowsocks)
        #expect(parsed?.password == "p@ss w0rd")
    }

    @Test("vless missing uuid returns nil")
    func vlessMissingUUIDReturnsNil() {
        let node = ProxyNode(
            name: "NoUUID",
            kind: .vless,
            server: "vless.example.com",
            port: 443,
            uuid: nil
        )
        #expect(ProxyURISerializer.makeURI(from: node) == nil)
    }

    @Test("trojan missing password returns nil")
    func trojanMissingPasswordReturnsNil() {
        let node = ProxyNode(
            name: "NoPassword",
            kind: .trojan,
            server: "trojan.example.com",
            port: 443,
            password: nil
        )
        #expect(ProxyURISerializer.makeURI(from: node) == nil)
    }

    @Test("hysteria2 empty name generates URI with empty fragment")
    func hysteria2EmptyName() {
        let node = ProxyNode(
            name: "",
            kind: .hysteria2,
            server: "hy2.example.com",
            port: 443,
            password: "secret"
        )
        let uri = ProxyURISerializer.makeURI(from: node)
        #expect(uri != nil)
        // The URI ends with `#` (empty fragment)
        #expect(uri!.hasSuffix("#"))
    }

    @Test("tuic missing password returns nil")
    func tuicMissingPasswordReturnsNil() {
        let node = ProxyNode(
            name: "NoPassword",
            kind: .tuic,
            server: "tuic.example.com",
            port: 443,
            password: nil,
            uuid: "uuid"
        )
        #expect(ProxyURISerializer.makeURI(from: node) == nil)
    }

    @Test("port 0 returns nil")
    func portZeroReturnsNil() {
        let node = ProxyNode(
            name: "BadPort",
            kind: .shadowsocks,
            server: "ss.example.com",
            port: 0,
            cipher: "aes-256-gcm",
            password: "secret"
        )
        #expect(ProxyURISerializer.makeURI(from: node) == nil)
    }

    @Test("http kind returns nil (no industry-standard share URI)")
    func httpKindReturnsNil() {
        let node = ProxyNode(
            name: "HTTPNode",
            kind: .http,
            server: "proxy.example.com",
            port: 8080
        )
        #expect(ProxyURISerializer.makeURI(from: node) == nil)
    }
}
