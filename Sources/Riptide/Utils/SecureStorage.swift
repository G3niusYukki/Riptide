import Foundation
import Security

// MARK: - Secure Storage

/// Secure credential storage using Keychain
public enum SecureStorage {
    
    // MARK: - WebDAV Credentials
    
    /// Save WebDAV credentials to Keychain
    public static func saveWebDAVCredentials(_ credentials: WebDAVCredentials) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "webdav_credentials",
            kSecAttrService as String: "com.riptide.webdav",
            kSecValueData as String: try credentials.toData(),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    /// Load WebDAV credentials from Keychain
    public static func loadWebDAVCredentials() throws -> WebDAVCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "webdav_credentials",
            kSecAttrService as String: "com.riptide.webdav",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw KeychainError.loadFailed(status)
        }
        
        guard let data = result as? Data else {
            return nil
        }
        
        return try WebDAVCredentials(from: data)
    }
    
    /// Delete WebDAV credentials from Keychain
    public static func deleteWebDAVCredentials() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "webdav_credentials",
            kSecAttrService as String: "com.riptide.webdav"
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
    
    // MARK: - Generic Password Storage
    
    /// Save a generic password to Keychain
    public static func savePassword(_ password: String, service: String, account: String) throws {
        guard let passwordData = password.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: passwordData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    /// Load a generic password from Keychain
    public static func loadPassword(service: String, account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw KeychainError.loadFailed(status)
        }
        
        guard let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        
        return password
    }
    
    /// Delete a generic password from Keychain
    public static func deletePassword(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

// MARK: - Keychain Errors

public enum KeychainError: Error, LocalizedError, Sendable {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case invalidData
    
    public var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save to Keychain: \(status)"
        case .loadFailed(let status):
            return "Failed to load from Keychain: \(status)"
        case .deleteFailed(let status):
            return "Failed to delete from Keychain: \(status)"
        case .invalidData:
            return "Invalid data format"
        }
    }
}

// MARK: - WebDAV Credentials

public struct WebDAVCredentials: Sendable, Equatable {
    public let username: String
    public let password: String
    
    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
    
    var base64Encoded: String {
        let credentials = "\(username):\(password)"
        return Data(credentials.utf8).base64EncodedString()
    }
    
    func toData() throws -> Data {
        let dict: [String: String] = [
            "username": username,
            "password": password
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else {
            throw KeychainError.invalidData
        }
        return data
    }
    
    init(from data: Data) throws {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let username = dict["username"],
              let password = dict["password"] else {
            throw KeychainError.invalidData
        }
        self.username = username
        self.password = password
    }
}
