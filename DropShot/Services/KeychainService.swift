import Foundation
import Security

// MARK: - Keychain Errors

enum KeychainError: LocalizedError {
    case encodingFailed
    case unexpectedData
    case itemNotFound
    case duplicateItem
    case authFailed
    case unhandledError(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode the password data."
        case .unexpectedData:
            return "Unexpected data format returned from the Keychain."
        case .itemNotFound:
            return "No matching Keychain item was found."
        case .duplicateItem:
            return "A Keychain item with this identifier already exists."
        case .authFailed:
            return "Authentication failed. The user may have denied Keychain access."
        case .unhandledError(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
            return "Keychain error (\(status)): \(message)"
        }
    }

    /// Maps an OSStatus from the Security framework to a typed KeychainError.
    static func fromStatus(_ status: OSStatus) -> KeychainError {
        switch status {
        case errSecItemNotFound:
            return .itemNotFound
        case errSecDuplicateItem:
            return .duplicateItem
        case errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed:
            return .authFailed
        default:
            return .unhandledError(status: status)
        }
    }
}

// MARK: - Keychain Service

actor KeychainService {
    static let shared = KeychainService()

    private let serviceIdentifier = "com.dropshot.ssh"

    private init() {}

    // MARK: - Public API

    /// Stores a password in the macOS Keychain for the given server configuration.
    /// If a password already exists for this config, it is updated in place.
    func storePassword(_ password: String, for config: ServerConfiguration) throws {
        guard let passwordData = password.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        let account = accountIdentifier(for: config)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: account
        ]

        // Check if an item already exists so we can update rather than insert.
        let existingStatus = SecItemCopyMatching(query as CFDictionary, nil)

        if existingStatus == errSecSuccess {
            // Update the existing item.
            let attributes: [String: Any] = [
                kSecValueData as String: passwordData,
                kSecAttrComment as String: "DropShot SSH password for \(config.name)",
                kSecAttrModificationDate as String: Date()
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.fromStatus(updateStatus)
            }
        } else if existingStatus == errSecItemNotFound {
            // Insert a new item.
            var addQuery = query
            addQuery[kSecValueData as String] = passwordData
            addQuery[kSecAttrComment as String] = "DropShot SSH password for \(config.name)"
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.fromStatus(addStatus)
            }
        } else {
            throw KeychainError.fromStatus(existingStatus)
        }
    }

    /// Retrieves the stored password for the given server configuration.
    /// Returns `nil` if no password is stored (rather than throwing).
    func retrievePassword(for config: ServerConfiguration) throws -> String? {
        let account = accountIdentifier(for: config)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.unexpectedData
            }
            guard let password = String(data: data, encoding: .utf8) else {
                throw KeychainError.unexpectedData
            }
            return password

        case errSecItemNotFound:
            return nil

        default:
            throw KeychainError.fromStatus(status)
        }
    }

    /// Deletes the stored password for the given server configuration.
    /// Does not throw if the item does not exist.
    func deletePassword(for config: ServerConfiguration) throws {
        let account = accountIdentifier(for: config)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.fromStatus(status)
        }
    }

    /// Checks whether stored credentials exist for the given server configuration.
    func hasCredentials(for config: ServerConfiguration) -> Bool {
        let account = accountIdentifier(for: config)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Private Helpers

    /// Builds a stable, unique account identifier from the server configuration's
    /// host, username, and port. This ensures credentials are scoped correctly
    /// even when multiple servers share the same host or username.
    private func accountIdentifier(for config: ServerConfiguration) -> String {
        return "\(config.username)@\(config.host):\(config.port)"
    }
}
