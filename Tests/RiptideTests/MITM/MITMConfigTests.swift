import Testing
@testable import Riptide

@Suite("MITMConfig")
struct MITMConfigTests {
    @Test("wildcard matches all hosts")
    func wildcardMatchesAll() async {
        let config = MITMConfig(enabled: true, hosts: ["*"])
        #expect(config.shouldIntercept("example.com") == true)
        #expect(config.shouldIntercept("api.example.com") == true)
        #expect(config.shouldIntercept("anything") == true)
    }

    @Test("exact host match")
    func exactHostMatch() async {
        let config = MITMConfig(enabled: true, hosts: ["example.com"])
        #expect(config.shouldIntercept("example.com") == true)
        #expect(config.shouldIntercept("other.com") == false)
    }

    @Test("wildcard subdomain matches with dot boundary")
    func wildcardSubdomainMatchesWithDotBoundary() async {
        let config = MITMConfig(enabled: true, hosts: ["*.example.com"])
        #expect(config.shouldIntercept("api.example.com") == true)
        #expect(config.shouldIntercept("cdn.example.com") == true)
        // Must NOT match hosts without a dot boundary
        #expect(config.shouldIntercept("badexample.com") == false)
        #expect(config.shouldIntercept("notexample.com") == false)
    }

    @Test("wildcard matches base domain")
    func wildcardMatchesBaseDomain() async {
        let config = MITMConfig(enabled: true, hosts: ["*.example.com"])
        // *.example.com should also match example.com itself
        #expect(config.shouldIntercept("example.com") == true)
    }

    @Test("exclusion overrides host match")
    func exclusionOverridesHostMatch() async {
        let config = MITMConfig(
            enabled: true,
            hosts: ["*.example.com"],
            excludeHosts: ["api.example.com"]
        )
        #expect(config.shouldIntercept("cdn.example.com") == true)
        #expect(config.shouldIntercept("api.example.com") == false)
    }

    @Test("exclusion works with wildcard all")
    func exclusionWorksWithWildcardAll() async {
        let config = MITMConfig(
            enabled: true,
            hosts: ["*"],
            excludeHosts: ["safe.example.com", "another.com"]
        )
        #expect(config.shouldIntercept("any.com") == true)
        #expect(config.shouldIntercept("safe.example.com") == false)
        #expect(config.shouldIntercept("another.com") == false)
    }

    @Test("disabled config never intercepts")
    func disabledConfigNeverIntercepts() async {
        let config = MITMConfig(enabled: false, hosts: ["*"])
        #expect(config.shouldIntercept("example.com") == false)
    }

    @Test("empty hosts matches all when enabled")
    func emptyHostsMatchesAllWhenEnabled() async {
        let config = MITMConfig(enabled: true, hosts: [])
        #expect(config.shouldIntercept("example.com") == true)
        #expect(config.shouldIntercept("anything") == true)
    }
}
