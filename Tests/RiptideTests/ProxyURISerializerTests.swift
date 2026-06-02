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
}
