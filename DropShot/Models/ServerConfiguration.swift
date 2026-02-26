import Foundation

// MARK: - Authentication Method

enum AuthMethod: String, Codable, CaseIterable {
    case sshKey = "sshKey"
    case password = "password"

    var displayName: String {
        switch self {
        case .sshKey: return "SSH Key"
        case .password: return "Password"
        }
    }
}

// MARK: - Validation Errors

enum ServerConfigurationError: LocalizedError {
    case emptyHost
    case invalidPort
    case emptyUsername
    case emptyRemotePath
    case remotePathNotAbsolute
    case sshKeyPathNotSet
    case sshKeyNotFound(String)
    case invalidBaseURL

    var errorDescription: String? {
        switch self {
        case .emptyHost:
            return "Server host is required."
        case .invalidPort:
            return "Port must be between 1 and 65535."
        case .emptyUsername:
            return "Username is required."
        case .emptyRemotePath:
            return "Remote path is required."
        case .remotePathNotAbsolute:
            return "Remote path must be an absolute path (starting with /)."
        case .sshKeyPathNotSet:
            return "SSH key path is required when using SSH key authentication."
        case .sshKeyNotFound(let path):
            return "SSH key not found at: \(path)"
        case .invalidBaseURL:
            return "Base URL must be a valid URL (e.g. https://example.com/uploads)."
        }
    }
}

// MARK: - Server Configuration

struct ServerConfiguration: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var authMethod: AuthMethod
    var sshKeyPath: String?
    var remotePath: String
    var baseURL: String?

    init(
        id: UUID = UUID(),
        name: String = "My Server",
        host: String = "",
        port: Int = 22,
        username: String = "",
        authMethod: AuthMethod = .sshKey,
        sshKeyPath: String? = ServerConfiguration.detectDefaultSSHKeyPath(),
        remotePath: String = "/srv/uploads/",
        baseURL: String? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.sshKeyPath = sshKeyPath
        self.remotePath = remotePath
        self.baseURL = baseURL
    }

    // MARK: - Computed Properties

    var isValid: Bool {
        do {
            try validate()
            return true
        } catch {
            return false
        }
    }

    /// Remote path guaranteed to end with a trailing slash.
    var remotePathWithTrailingSlash: String {
        remotePath.hasSuffix("/") ? remotePath : remotePath + "/"
    }

    // MARK: - Validation

    /// Validates the configuration and throws a descriptive error on failure.
    func validate() throws {
        guard !host.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ServerConfigurationError.emptyHost
        }

        guard (1...65535).contains(port) else {
            throw ServerConfigurationError.invalidPort
        }

        guard !username.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ServerConfigurationError.emptyUsername
        }

        guard !remotePath.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ServerConfigurationError.emptyRemotePath
        }

        guard remotePath.hasPrefix("/") else {
            throw ServerConfigurationError.remotePathNotAbsolute
        }

        if authMethod == .sshKey {
            guard let keyPath = sshKeyPath, !keyPath.isEmpty else {
                throw ServerConfigurationError.sshKeyPathNotSet
            }
            let expandedPath = (keyPath as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: expandedPath) else {
                throw ServerConfigurationError.sshKeyNotFound(expandedPath)
            }
        }

        if let baseURL = baseURL, !baseURL.isEmpty {
            guard URL(string: baseURL) != nil,
                  baseURL.hasPrefix("http://") || baseURL.hasPrefix("https://") else {
                throw ServerConfigurationError.invalidBaseURL
            }
        }
    }

    // MARK: - SSH Key Detection

    /// Looks for common SSH key files in ~/.ssh/ and returns the first one found.
    static func detectDefaultSSHKeyPath() -> String? {
        let sshDir = (NSHomeDirectory() as NSString).appendingPathComponent(".ssh")
        let candidates = ["id_ed25519", "id_rsa", "id_ecdsa"]

        for candidate in candidates {
            let path = (sshDir as NSString).appendingPathComponent(candidate)
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }
}
