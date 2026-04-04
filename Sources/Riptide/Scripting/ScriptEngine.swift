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

// Wrapper for JSContext to allow @unchecked Sendable
private final class JSContextWrapper: @unchecked Sendable {
    let context: JSContext
    init(_ context: JSContext) { self.context = context }
}

public actor ScriptEngine {
    private var contexts: [String: JSContextWrapper]

    public init() {
        self.contexts = [:]
    }

    @discardableResult
    public func loadScript(_ context: ScriptContext) throws -> String {
        let vm = JSVirtualMachine()
        guard let jsContext = JSContext(virtualMachine: vm) else {
            throw ScriptError.compilationFailed("failed to create JSContext")
        }

        jsContext.evaluateScript(context.source)
        if let exception = jsContext.exception {
            throw ScriptError.compilationFailed(exception.toString() ?? "unknown error")
        }

        let wrapper = JSContextWrapper(jsContext)
        contexts[context.name] = wrapper
        return context.name
    }

    public func executeRequestModify(scriptName: String, requestHeaders: [String: String]) throws -> [String: String] {
        guard let wrapper = contexts[scriptName] else {
            throw ScriptError.runtimeError("script not loaded: \(scriptName)")
        }

        let jsContext = wrapper.context
        let nsHeaders = NSDictionary(dictionary: requestHeaders)

        let jsRequest = NSMutableDictionary(dictionary: nsHeaders)
        jsContext.setObject(jsRequest, forKeyedSubscript: "request" as NSCopying & NSObjectProtocol)

        let result = jsContext.evaluateScript("handleRequestModify(request)")
        if let exception = jsContext.exception {
            throw ScriptError.runtimeError(exception.toString() ?? "unknown error")
        }

        guard let jsResult = result as? NSDictionary else {
            return requestHeaders
        }

        // Safe type conversion
        var output: [String: String] = [:]
        for (key, value) in jsResult {
            if let keyStr = key as? String, let valStr = value as? String {
                output[keyStr] = valStr
            }
        }
        return output.isEmpty ? requestHeaders : output
    }

    public func executeResponseModify(scriptName: String, responseBody: Data) throws -> Data {
        guard let wrapper = contexts[scriptName] else {
            throw ScriptError.runtimeError("script not loaded: \(scriptName)")
        }

        let jsContext = wrapper.context

        jsContext.setObject(responseBody, forKeyedSubscript: "response" as NSCopying & NSObjectProtocol)

        let result = jsContext.evaluateScript("handleResponseModify(response)")
        if let exception = jsContext.exception {
            throw ScriptError.runtimeError(exception.toString() ?? "unknown error")
        }

        if let jsResult = result as? Data {
            return jsResult
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
