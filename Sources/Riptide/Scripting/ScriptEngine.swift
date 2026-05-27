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
    case profileScript = "profile-script"
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

    // MARK: - Profile Script

    /// Execute a profile transformation script.
    /// The script should define a `transform(config)` function that receives
    /// the config as a JSON object and returns a modified config object.
    /// - Parameters:
    ///   - scriptName: Name of the loaded script
    ///   - configJSON: JSON string representation of the config
    /// - Returns: JSON string of the transformed config
    public func executeProfileScript(scriptName: String, configJSON: String) throws -> String {
        guard let wrapper = contexts[scriptName] else {
            throw ScriptError.runtimeError("script not loaded: \(scriptName)")
        }

        let jsContext = wrapper.context

        // Parse the config JSON and set it as a global variable.
        let jsonLiteralData = try JSONEncoder().encode(configJSON)
        guard let jsonLiteral = String(data: jsonLiteralData, encoding: .utf8) else {
            throw ScriptError.runtimeError("failed to encode config JSON literal")
        }
        let parseScript = "var config = JSON.parse(\(jsonLiteral));"
        jsContext.evaluateScript(parseScript)
        if let exception = jsContext.exception {
            throw ScriptError.runtimeError("failed to parse config JSON: \(exception.toString() ?? "unknown error")")
        }

        // Execute the transform function
        let result = jsContext.evaluateScript("JSON.stringify(transform(config))")
        if let exception = jsContext.exception {
            throw ScriptError.runtimeError("transform failed: \(exception.toString() ?? "unknown error")")
        }

        guard let jsonResult = result?.toString() else {
            throw ScriptError.runtimeError("transform did not return a valid JSON string")
        }

        return jsonResult
    }
}
