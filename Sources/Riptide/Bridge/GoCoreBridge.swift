import Foundation
import GoCore

/// Swift wrapper for the GoCore Cgo API.
public actor GoCoreBridge {
    public static let shared = GoCoreBridge()
    
    private var eventHandler: (@Sendable (String, String) -> Void)?
    
    private init() {}
    
    public func start(configJSON: String, eventHandler: @escaping @Sendable (String, String) -> Void) throws {
        self.eventHandler = eventHandler
        
        let callback: @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void = { typePtr, dataPtr in
            guard let typePtr, let dataPtr else { return }
            let type = String(cString: typePtr)
            let data = String(cString: dataPtr)
            
            Task {
                await GoCoreBridge.shared.handleEvent(type: type, data: data)
            }
        }
        
        guard let configJSONPtr = configJSON.cString(using: .utf8) else {
            throw TunnelRuntimeError.startFailed("Invalid config encoding")
        }
        
        var configCopy = configJSONPtr
        let resultPtr = configCopy.withUnsafeMutableBufferPointer { buffer in
            GoCoreStart(buffer.baseAddress, callback)
        }
        
        if let resultPtr {
            let errorMsg = String(cString: resultPtr)
            free(resultPtr)
            throw TunnelRuntimeError.startFailed(errorMsg)
        }
    }
    
    public func stop() {
        GoCoreStop()
    }
    
    public func getTraffic() -> (up: Int64, down: Int64) {
        var up: Int64 = 0
        var down: Int64 = 0
        GoCoreGetTraffic(&up, &down)
        return (up, down)
    }
    
    public func switchProxy(group: String, name: String) throws {
        guard let groupPtr = group.cString(using: .utf8),
              let namePtr = name.cString(using: .utf8) else {
            throw TunnelRuntimeError.updateFailed("Invalid arguments encoding")
        }
        var groupCopy = groupPtr
        var nameCopy = namePtr
        let resultPtr = groupCopy.withUnsafeMutableBufferPointer { groupBuf in
            nameCopy.withUnsafeMutableBufferPointer { nameBuf in
                GoCoreSwitchProxy(groupBuf.baseAddress, nameBuf.baseAddress)
            }
        }
        if let resultPtr {
            let errorMsg = String(cString: resultPtr)
            free(resultPtr)
            throw TunnelRuntimeError.updateFailed(errorMsg)
        }
    }
    
    public func handleEvent(type: String, data: String) {
        eventHandler?(type, data)
    }
}
