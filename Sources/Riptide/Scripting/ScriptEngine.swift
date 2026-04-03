import Foundation
import JavaScriptCore

public enum ScriptError: Error, Sendable {
    case runtimeError(String)
    case compilationFailed(String)
}

public struct ScriptContext: Sendable {
    public let name: String
    public let source: String
    public let type: ScriptType
}

public enum ScriptType: String, Sendable {
    case requestModify = "request-modify"
    case responseModify = "response-modify"
    case ruleProvider = "rule-provider"
}

public actor ScriptEngine {
    private var contexts: [String: JSValue]

    public init() {
        self.contexts = [:]
    }

    @discardableResult
    public func loadScript(_ context: ScriptContext) throws -> String {
        let vm = JSVirtualMachine()
        let jsContext = JSContext(virtualMachine: vm)

        jsContext?.evaluateScript(context.source)
        if let exception = jsContext?.exception {
            throw ScriptError.compilationFailed(exception.toString() ?? "unknown error")
        }

        let value = JSValue(object: jsContext?.globalObject, in: jsContext)
        contexts[context.name] = value
        return context.name
    }

    public func executeRequestModify(scriptName: String, requestHeaders: [String: String]) throws -> [String: String] {
        guard contexts[scriptName] != nil else {
            throw ScriptError.runtimeError("script not loaded: \(scriptName)")
        }
        return requestHeaders
    }

    public func executeResponseModify(scriptName: String, responseBody: Data) throws -> Data {
        guard contexts[scriptName] != nil else {
            throw ScriptError.runtimeError("script not loaded: \(scriptName)")
        }
        return responseBody
    }

    public func unloadScript(_ name: String) {
        contexts.removeValue(forKey: name)
    }

    public func listScripts() -> [String] {
        Array(contexts.keys)
    }
}
