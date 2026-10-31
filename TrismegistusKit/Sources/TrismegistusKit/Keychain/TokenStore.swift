import Foundation
#if canImport(Security)
import Security
#endif

/// Where the device token lives. Never UserDefaults, logs or files.
public protocol TokenStore: Sendable {
    func token() throws -> String?
    func setToken(_ token: String) throws
    func deleteToken() throws
}

/// For tests and previews.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    public init(token: String? = nil) { value = token }

    public func token() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    public func setToken(_ token: String) throws {
        lock.lock()
        defer { lock.unlock() }
        value = token
    }

    public func deleteToken() throws {
        lock.lock()
        defer { lock.unlock() }
        value = nil
    }
}

#if canImport(Security)
public struct KeychainError: Error, Equatable {
    public let status: OSStatus
}

/// A generic password, local to this Mac (never synced), readable while the Mac is unlocked.
public struct KeychainTokenStore: TokenStore {
    public static let defaultService = "dev.x-muramasa.trismegistus"

    let service: String
    let account: String
    let dataProtection: Bool

    /// The default is the login keychain, which works for an ad-hoc signed app (the app is not signed with a team; see
    /// SPEC "Signing"). dataProtection uses the data protection keychain instead (where kSecAttrAccessible applies);
    /// that needs a team-signed app with a keychain entitlement and a provisioning profile.
    public init(service: String = defaultService, account: String = "device-token", dataProtection: Bool = false) {
        self.service = service
        self.account = account
        self.dataProtection = dataProtection
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: dataProtection,
        ]
    }

    public func token() throws -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else { throw KeychainError(status: status) }
        return String(decoding: data, as: UTF8.self)
    }

    public func setToken(_ token: String) throws {
        try deleteToken()
        var q = query
        q[kSecValueData as String] = Data(token.utf8)
        if dataProtection { q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly }
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func deleteToken() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
#endif
