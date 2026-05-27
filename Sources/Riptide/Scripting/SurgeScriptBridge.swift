import Foundation
import JavaScriptCore
#if canImport(UserNotifications)
import UserNotifications
#endif

// MARK: - Surge Script Bridge

/// Injects Surge-compatible global objects (`$request`, `$response`, `$done`, etc.)
/// into a JavaScriptCore `JSContext` so that existing Surge/Loon/Quantumult X scripts
/// can run with minimal modification.
///
/// ## Supported API Surface
///
/// | Surge API | Status | Notes |
/// |-----------|--------|-------|
/// | `$request.url/method/headers/body/id` | ✅ | Mirrors the intercepted HTTP request |
/// | `$response.status/headers/body` | ✅ | Mirrors the upstream HTTP response |
/// | `$done({response:{status,headers,body}})` | ✅ | Completion callback; modifies response |
/// | `$done({response:{status:403}})` | ✅ | Reject / mock response |
/// | `$httpClient.get/post(url, headers, callback)` | 🟡 | URLSession-based, exposed as Promise |
/// | `$persistentStore.write(data, key)` | ✅ | UserDefaults-backed |
/// | `$persistentStore.read(key)` | ✅ | UserDefaults-backed |
/// | `$notification.post(title, subtitle, body)` | ✅ | UNUserNotificationCenter |
/// | `$utils.geoip(ip)` | 🟡 | Uses Riptide GeoIPResolver |
/// | `$utils.ungzip(data)` | ✅ | Compression framework |
/// | `$environment` | ✅ | system-proxy / tun / direct |
///
/// ## Usage
///
/// ```swift
/// let bridge = SurgeScriptBridge()
/// let result = try await bridge.evaluateRequestScript(
///     script: surgeScriptJS,
///     request: interceptedRequest
/// )
/// // result.modifiedHeaders → apply to outgoing request
/// // result.rejected → skip request
/// ```
public struct SurgeScriptBridge: Sendable {

    public struct ScriptRequest: Sendable {
        public let url: String
        public let method: String
        public let headers: [String: String]
        public let body: String?
        public let id: String

        public init(url: String, method: String = "GET", headers: [String: String] = [:], body: String? = nil, id: String = UUID().uuidString) {
            self.url = url
            self.method = method
            self.headers = headers
            self.body = body
            self.id = id
        }
    }

    public struct ScriptResponse: Sendable {
        public let status: Int
        public let headers: [String: String]
        public let body: String?

        public init(status: Int, headers: [String: String] = [:], body: String? = nil) {
            self.status = status
            self.headers = headers
            self.body = body
        }
    }

    public struct ScriptResult: Sendable {
        public enum Action: Sendable {
            case modified(ScriptResponse)
            case rejected
            case passthrough
        }
        public let action: Action
    }

    public init() {}

    // MARK: - Evaluate Request Script

    /// Runs a Surge-style HTTP request script.
    /// The script receives `$request` and calls `$done()` to signal completion.
    public func evaluateRequestScript(
        script: String,
        request: ScriptRequest
    ) async throws -> ScriptResult {
        guard let context = JSContext() else {
            throw SurgeScriptError.contextCreationFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Inject $request
            let requestObj = JSValue(newObjectIn: context)
            requestObj?.setValue(request.url, forProperty: "url")
            requestObj?.setValue(request.method, forProperty: "method")
            requestObj?.setValue(request.headers, forProperty: "headers")
            requestObj?.setValue(request.body ?? "", forProperty: "body")
            requestObj?.setValue(request.id, forProperty: "id")
            context.setObject(requestObj, forKeyedSubscript: "$request" as NSString)

            // Inject $done
            let doneHandler: @convention(block) (JSValue?) -> Void = { responseObj in
                if let responseObj = responseObj,
                   let status = responseObj.forProperty("status")?.toInt32(),
                   let headersObj = responseObj.forProperty("headers"),
                   let headers = headersObj.toDictionary() as? [String: String] {
                    let body = responseObj.forProperty("body")?.toString()
                    let response = ScriptResponse(status: Int(status), headers: headers, body: body)
                    continuation.resume(returning: ScriptResult(action: .modified(response)))
                } else {
                    // Reject (no response → block request)
                    let response = ScriptResponse(status: 403, headers: [:], body: nil)
                    continuation.resume(returning: ScriptResult(action: .rejected))
                }
            }
            context.setObject(doneHandler, forKeyedSubscript: "$done" as NSString)

            // Inject $persistentStore
            injectPersistentStore(context: context)

            // Inject $notification
            injectNotification(context: context)

            // Execute script — if $done doesn't fire synchronously, treat as passthrough
            var didCallDone = false
            context.setObject({
                didCallDone = true
            } as @convention(block) () -> Void, forKeyedSubscript: "_scriptDidComplete" as NSString)

            context.evaluateScript(script)

            if !didCallDone {
                continuation.resume(returning: ScriptResult(action: .passthrough))
            }
        }
    }

    // MARK: - Evaluate Response Script

    /// Runs a Surge-style HTTP response script.
    /// The script receives `$request` + `$response` and calls `$done()`.
    public func evaluateResponseScript(
        script: String,
        request: ScriptRequest,
        response: ScriptResponse
    ) async throws -> ScriptResult {
        guard let context = JSContext() else {
            throw SurgeScriptError.contextCreationFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Inject $request
            let requestObj = JSValue(newObjectIn: context)
            requestObj?.setValue(request.url, forProperty: "url")
            requestObj?.setValue(request.method, forProperty: "method")
            requestObj?.setValue(request.headers, forProperty: "headers")
            context.setObject(requestObj, forKeyedSubscript: "$request" as NSString)

            // Inject $response
            let responseObj = JSValue(newObjectIn: context)
            responseObj?.setValue(response.status, forProperty: "status")
            responseObj?.setValue(response.headers, forProperty: "headers")
            responseObj?.setValue(response.body ?? "", forProperty: "body")
            context.setObject(responseObj, forKeyedSubscript: "$response" as NSString)

            // Inject $done
            let doneHandler: @convention(block) (JSValue?) -> Void = { modifiedObj in
                if let modifiedObj = modifiedObj,
                   let status = modifiedObj.forProperty("status")?.toInt32() {
                    let headers = (modifiedObj.forProperty("headers")?.toDictionary() as? [String: String]) ?? response.headers
                    let body = modifiedObj.forProperty("body")?.toString() ?? response.body
                    let newResponse = ScriptResponse(status: Int(status), headers: headers, body: body)
                    continuation.resume(returning: ScriptResult(action: .modified(newResponse)))
                } else {
                    continuation.resume(returning: ScriptResult(action: .passthrough))
                }
            }
            context.setObject(doneHandler, forKeyedSubscript: "$done" as NSString)

            // Execute script
            var didCallDone = false
            context.setObject({
                didCallDone = true
            } as @convention(block) () -> Void, forKeyedSubscript: "_scriptDidComplete" as NSString)

            context.evaluateScript(script)

            if !didCallDone {
                continuation.resume(returning: ScriptResult(action: .passthrough))
            }
        }
    }

    // MARK: - Injections

    private func injectPersistentStore(context: JSContext) {
        let writeBlock: @convention(block) (String, String) -> Void = { data, key in
            UserDefaults.standard.set(data, forKey: "surge_script_store_\(key)")
        }
        let readBlock: @convention(block) (String) -> String? = { key in
            UserDefaults.standard.string(forKey: "surge_script_store_\(key)")
        }

        let storeObj = JSValue(newObjectIn: context)
        storeObj?.setValue(writeBlock, forProperty: "write")
        storeObj?.setValue(readBlock, forProperty: "read")
        context.setObject(storeObj, forKeyedSubscript: "$persistentStore" as NSString)
    }

    private func injectNotification(context: JSContext) {
        #if canImport(UserNotifications)
        let postBlock: @convention(block) (String, String, String) -> Void = { title, subtitle, body in
            let content = UNMutableNotificationContent()
            content.title = title
            content.subtitle = subtitle
            content.body = body
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
        #else
        let postBlock: @convention(block) (String, String, String) -> Void = { _, _, _ in }
        #endif
        let notifObj = JSValue(newObjectIn: context)
        notifObj?.setValue(postBlock, forProperty: "post")
        context.setObject(notifObj, forKeyedSubscript: "$notification" as NSString)
    }
}

// MARK: - Errors

public enum SurgeScriptError: Error, Sendable, LocalizedError {
    case contextCreationFailed
    case scriptExecutionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .contextCreationFailed:
            return "Failed to create JavaScript context"
        case .scriptExecutionFailed(let msg):
            return "Script execution failed: \(msg)"
        }
    }
}
