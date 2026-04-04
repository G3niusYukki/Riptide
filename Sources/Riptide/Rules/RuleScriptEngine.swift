import Foundation

/// A simple expression-based script engine for rule matching.
/// Supports basic operators: ==, !=, contains, startsWith, endsWith, matches (regex)
public struct RuleScriptEngine: Sendable {
    public let code: String

    public init(code: String) {
        self.code = code.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Evaluate the script against a rule target.
    /// Returns true if the script matches, false otherwise.
    public func evaluate(target: RuleTarget) -> Bool {
        let expression = code

        // Handle == operator
        if let range = expression.range(of: "==") {
            let left = String(expression[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let right = String(expression[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return evaluateEquality(left: left, right: right, target: target)
        }

        // Handle != operator
        if let range = expression.range(of: "!=") {
            let left = String(expression[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let right = String(expression[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return !evaluateEquality(left: left, right: right, target: target)
        }

        // Handle .contains("") method
        if expression.contains(".contains(") {
            return evaluateMethodCall(expression, target: target, method: "contains")
        }

        // Handle .startsWith("") method
        if expression.contains(".startsWith(") {
            return evaluateMethodCall(expression, target: target, method: "startsWith")
        }

        // Handle .endsWith("") method
        if expression.contains(".endsWith(") {
            return evaluateMethodCall(expression, target: target, method: "endsWith")
        }

        // Handle .matches("") method (regex)
        if expression.contains(".matches(") {
            return evaluateMethodCall(expression, target: target, method: "matches")
        }

        return false
    }

    private func evaluateEquality(left: String, right: String, target: RuleTarget) -> Bool {
        let value = getFieldValue(field: left, target: target)
        return value == right
    }

    private func evaluateMethodCall(_ expression: String, target: RuleTarget, method: String) -> Bool {
        // Parse object.method("argument")
        guard let dotIndex = expression.firstIndex(of: ".") else { return false }
        let object = String(expression[..<dotIndex]).trimmingCharacters(in: .whitespaces)

        // Extract argument from parentheses
        guard let openParen = expression.firstIndex(of: "("),
              let closeParen = expression.lastIndex(of: ")") else { return false }
        let argument = String(expression[expression.index(after: openParen)..<closeParen])
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

        let value = getFieldValue(field: object, target: target)

        switch method {
        case "contains":
            return value?.contains(argument) ?? false
        case "startsWith":
            return value?.hasPrefix(argument) ?? false
        case "endsWith":
            return value?.hasSuffix(argument) ?? false
        case "matches":
            guard let value = value else { return false }
            do {
                let regex = try NSRegularExpression(pattern: argument, options: [])
                let range = NSRange(location: 0, length: value.utf16.count)
                return regex.firstMatch(in: value, options: [], range: range) != nil
            } catch {
                return false
            }
        default:
            return false
        }
    }

    private func getFieldValue(field: String, target: RuleTarget) -> String? {
        switch field.lowercased() {
        case "domain":
            return target.domain
        case "ip", "ipaddress":
            return target.ipAddress
        case "sourceip", "srcip":
            return target.sourceIP
        case "sourceport", "srcport":
            return target.sourcePort.map(String.init)
        case "destinationport", "dstport", "port":
            return target.destinationPort.map(String.init)
        case "processname", "process":
            return target.processName
        default:
            return nil
        }
    }
}
