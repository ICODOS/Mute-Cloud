// KeychainManager.swift
// Mute

import Foundation
import Security

/// Manages secure storage of sensitive data in the macOS Keychain
final class KeychainManager {
    static let shared = KeychainManager()

    private let service = "com.mute.app"

    private init() {}

    // MARK: - Groq API Key

    private let groqAPIKeyAccount = "groq-api-key"

    /// Retrieves the Groq API key from the Keychain
    /// - Returns: The API key if found, nil otherwise
    func getGroqAPIKey() -> String? {
        return getString(account: groqAPIKeyAccount)
    }

    /// Saves the Groq API key to the Keychain
    /// - Parameter key: The API key to save
    /// - Returns: True if successful, false otherwise
    @discardableResult
    func setGroqAPIKey(_ key: String) -> Bool {
        return setString(key, account: groqAPIKeyAccount)
    }

    /// Deletes the Groq API key from the Keychain
    /// - Returns: True if successful or key didn't exist, false otherwise
    @discardableResult
    func deleteGroqAPIKey() -> Bool {
        return delete(account: groqAPIKeyAccount)
    }

    /// Checks if a Groq API key is stored
    var hasGroqAPIKey: Bool {
        return getGroqAPIKey() != nil
    }

    // MARK: - Generic Keychain Operations

    private func getString(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            if status != errSecItemNotFound {
                Logger.shared.log("Keychain read error for \(account): \(status)", level: .warning)
            }
            return nil
        }

        return string
    }

    private func setString(_ string: String, account: String) -> Bool {
        guard let data = string.data(using: .utf8) else {
            Logger.shared.log("Failed to encode string for keychain", level: .error)
            return false
        }

        // First, try to delete any existing item
        delete(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status != errSecSuccess {
            Logger.shared.log("Keychain write error for \(account): \(status)", level: .error)
            return false
        }

        Logger.shared.log("Successfully saved to keychain: \(account)")
        return true
    }

    @discardableResult
    private func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            Logger.shared.log("Keychain delete error for \(account): \(status)", level: .warning)
            return false
        }

        return true
    }
}

// MARK: - Masked Key Display

extension KeychainManager {
    /// Returns a masked version of the API key for display (e.g., "gsk_***...***M1V")
    func getMaskedGroqAPIKey() -> String? {
        guard let key = getGroqAPIKey(), key.count > 10 else {
            return nil
        }

        let prefix = String(key.prefix(4))
        let suffix = String(key.suffix(3))
        return "\(prefix)***...\(suffix)"
    }
}
