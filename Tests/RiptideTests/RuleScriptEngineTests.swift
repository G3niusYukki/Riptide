import Foundation
import Testing

@testable import Riptide

@Suite("Rule Script Engine")
struct RuleScriptEngineTests {

    @Test("ScriptEngine evaluates domain equality")
    func domainEquality() {
        let engine = RuleScriptEngine(code: "domain == \"example.com\"")
        let target = RuleTarget(domain: "example.com", ipAddress: nil)
        #expect(engine.evaluate(target: target) == true)
    }

    @Test("ScriptEngine evaluates domain inequality")
    func domainInequality() {
        let engine = RuleScriptEngine(code: "domain == \"example.com\"")
        let target = RuleTarget(domain: "other.com", ipAddress: nil)
        #expect(engine.evaluate(target: target) == false)
    }

    @Test("ScriptEngine evaluates not equal")
    func notEqual() {
        let engine = RuleScriptEngine(code: "domain != \"blocked.com\"")
        let target = RuleTarget(domain: "allowed.com", ipAddress: nil)
        #expect(engine.evaluate(target: target) == true)
    }

    @Test("ScriptEngine evaluates domain contains")
    func domainContains() {
        let engine = RuleScriptEngine(code: "domain.contains(\"google\")")
        let target = RuleTarget(domain: "www.google.com", ipAddress: nil)
        #expect(engine.evaluate(target: target) == true)
    }

    @Test("ScriptEngine evaluates domain startsWith")
    func domainStartsWith() {
        let engine = RuleScriptEngine(code: "domain.startsWith(\"api.\")")
        let target = RuleTarget(domain: "api.example.com", ipAddress: nil)
        #expect(engine.evaluate(target: target) == true)
    }

    @Test("ScriptEngine evaluates domain endsWith")
    func domainEndsWith() {
        let engine = RuleScriptEngine(code: "domain.endsWith(\".cn\")")
        let target = RuleTarget(domain: "example.cn", ipAddress: nil)
        #expect(engine.evaluate(target: target) == true)
    }

    @Test("ScriptEngine evaluates IP address equality")
    func ipAddressEquality() {
        let engine = RuleScriptEngine(code: "ip == \"192.168.1.1\"")
        let target = RuleTarget(domain: nil, ipAddress: "192.168.1.1")
        #expect(engine.evaluate(target: target) == true)
    }

    @Test("ScriptEngine evaluates source IP startsWith")
    func sourceIPStartsWith() {
        let engine = RuleScriptEngine(code: "sourceIP.startsWith(\"10.0.\")")
        let target = RuleTarget(domain: nil, ipAddress: "1.2.3.4", sourceIP: "10.0.5.1")
        #expect(engine.evaluate(target: target) == true)
    }

    @Test("ScriptEngine evaluates destination port equality")
    func destinationPort() {
        let engine = RuleScriptEngine(code: "destinationPort == \"443\"")
        let target = RuleTarget(domain: nil, ipAddress: nil, destinationPort: 443)
        #expect(engine.evaluate(target: target) == true)
    }

    @Test("ScriptEngine evaluates process name equality")
    func processName() {
        let engine = RuleScriptEngine(code: "processName == \"curl\"")
        let target = RuleTarget(domain: "example.com", ipAddress: nil, processName: "curl")
        #expect(engine.evaluate(target: target) == true)
    }

    @Test("ScriptEngine evaluates regex matches")
    func regexMatches() {
        let engine = RuleScriptEngine(code: "domain.matches(\".*\\\\.google\\\\..*\")")
        let target = RuleTarget(domain: "mail.google.com", ipAddress: nil)
        #expect(engine.evaluate(target: target) == true)
    }

    @Test("ScriptEngine returns false for unknown field")
    func unknownField() {
        let engine = RuleScriptEngine(code: "unknownField == \"test\"")
        let target = RuleTarget(domain: "example.com", ipAddress: nil)
        #expect(engine.evaluate(target: target) == false)
    }

    @Test("ScriptEngine returns false for invalid expression")
    func invalidExpression() {
        let engine = RuleScriptEngine(code: "invalid expression here")
        let target = RuleTarget(domain: "example.com", ipAddress: nil)
        #expect(engine.evaluate(target: target) == false)
    }

    @Test("RuleEngine resolves script rule - matching")
    func ruleEngineScriptMatching() {
        let rules: [ProxyRule] = [
            .script(code: "domain.contains(\"ads\")", policy: .reject),
            .final(policy: .direct)
        ]
        let engine = RuleEngine(rules: rules)
        let target = RuleTarget(domain: "ads.example.com", ipAddress: nil)
        let policy = engine.resolve(target: target)
        #expect(policy == .reject)
    }

    @Test("RuleEngine resolves script rule - not matching")
    func ruleEngineScriptNotMatching() {
        let rules: [ProxyRule] = [
            .script(code: "domain.contains(\"ads\")", policy: .reject),
            .final(policy: .direct)
        ]
        let engine = RuleEngine(rules: rules)
        let target = RuleTarget(domain: "example.com", ipAddress: nil)
        let policy = engine.resolve(target: target)
        #expect(policy == .direct)
    }
}
