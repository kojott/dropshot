import XCTest
@testable import DropShot

final class ServerConfigurationTests: XCTestCase {

    // MARK: - Default Configuration

    func testDefaultConfiguration() {
        let config = ServerConfiguration()
        XCTAssertEqual(config.name, "My Server")
        XCTAssertEqual(config.host, "")
        XCTAssertEqual(config.port, 22)
        XCTAssertEqual(config.username, "")
        XCTAssertEqual(config.authMethod, .sshKey)
        XCTAssertEqual(config.remotePath, "/srv/uploads/")
        XCTAssertNil(config.baseURL)
        // Default config has empty host/username so it should be invalid
        XCTAssertFalse(config.isValid)
    }

    // MARK: - Valid Configuration

    func testValidConfigurationWithPassword() {
        let config = ServerConfiguration(
            host: "example.com",
            port: 22,
            username: "deploy",
            authMethod: .password,
            sshKeyPath: nil,
            remotePath: "/srv/uploads/",
            baseURL: "https://example.com/uploads/"
        )
        XCTAssertTrue(config.isValid)
        XCTAssertNoThrow(try config.validate())
    }

    func testValidConfigurationWithSSHKey() throws {
        // Create a temporary SSH key file to pass validation
        let tempDir = FileManager.default.temporaryDirectory
        let keyPath = tempDir.appendingPathComponent("test_ed25519_\(UUID().uuidString)")
        try Data("fake-key-data".utf8).write(to: keyPath)
        defer { try? FileManager.default.removeItem(at: keyPath) }

        let config = ServerConfiguration(
            host: "example.com",
            port: 22,
            username: "deploy",
            authMethod: .sshKey,
            sshKeyPath: keyPath.path,
            remotePath: "/srv/uploads/"
        )
        XCTAssertTrue(config.isValid)
        XCTAssertNoThrow(try config.validate())
    }

    // MARK: - Invalid: Empty Host

    func testEmptyHostInvalid() {
        let config = ServerConfiguration(
            host: "",
            port: 22,
            username: "user",
            authMethod: .password,
            remotePath: "/uploads/"
        )
        XCTAssertFalse(config.isValid)
        XCTAssertThrowsError(try config.validate()) { error in
            XCTAssertTrue(error is ServerConfigurationError)
            if let configError = error as? ServerConfigurationError {
                if case .emptyHost = configError {
                    // Expected
                } else {
                    XCTFail("Expected emptyHost error, got \(configError)")
                }
            }
        }
    }

    func testWhitespaceOnlyHostInvalid() {
        let config = ServerConfiguration(
            host: "   ",
            port: 22,
            username: "user",
            authMethod: .password,
            remotePath: "/uploads/"
        )
        XCTAssertFalse(config.isValid)
    }

    // MARK: - Invalid: Port

    func testPortZeroInvalid() {
        let config = ServerConfiguration(
            host: "example.com",
            port: 0,
            username: "user",
            authMethod: .password,
            remotePath: "/uploads/"
        )
        XCTAssertFalse(config.isValid)
        XCTAssertThrowsError(try config.validate()) { error in
            if let configError = error as? ServerConfigurationError,
               case .invalidPort = configError {
                // Expected
            } else {
                XCTFail("Expected invalidPort error")
            }
        }
    }

    func testNegativePortInvalid() {
        let config = ServerConfiguration(
            host: "example.com",
            port: -1,
            username: "user",
            authMethod: .password,
            remotePath: "/uploads/"
        )
        XCTAssertFalse(config.isValid)
    }

    func testPort65536Invalid() {
        let config = ServerConfiguration(
            host: "example.com",
            port: 65536,
            username: "user",
            authMethod: .password,
            remotePath: "/uploads/"
        )
        XCTAssertFalse(config.isValid)
    }

    func testPort65535Valid() {
        let config = ServerConfiguration(
            host: "example.com",
            port: 65535,
            username: "user",
            authMethod: .password,
            remotePath: "/uploads/"
        )
        // Port is valid; other fields may also need to be valid
        XCTAssertNoThrow(try config.validate())
    }

    func testPort1Valid() {
        let config = ServerConfiguration(
            host: "example.com",
            port: 1,
            username: "user",
            authMethod: .password,
            remotePath: "/uploads/"
        )
        XCTAssertNoThrow(try config.validate())
    }

    // MARK: - Invalid: Username

    func testEmptyUsernameInvalid() {
        let config = ServerConfiguration(
            host: "example.com",
            port: 22,
            username: "",
            authMethod: .password,
            remotePath: "/uploads/"
        )
        XCTAssertFalse(config.isValid)
        XCTAssertThrowsError(try config.validate()) { error in
            if let configError = error as? ServerConfigurationError,
               case .emptyUsername = configError {
                // Expected
            } else {
                XCTFail("Expected emptyUsername error")
            }
        }
    }

    // MARK: - Invalid: Remote Path

    func testEmptyRemotePathInvalid() {
        let config = ServerConfiguration(
            host: "example.com",
            port: 22,
            username: "user",
            authMethod: .password,
            remotePath: ""
        )
        XCTAssertFalse(config.isValid)
        XCTAssertThrowsError(try config.validate()) { error in
            if let configError = error as? ServerConfigurationError,
               case .emptyRemotePath = configError {
                // Expected
            } else {
                XCTFail("Expected emptyRemotePath error")
            }
        }
    }

    func testNonAbsoluteRemotePathInvalid() {
        let config = ServerConfiguration(
            host: "example.com",
            port: 22,
            username: "user",
            authMethod: .password,
            remotePath: "relative/path/"
        )
        XCTAssertFalse(config.isValid)
        XCTAssertThrowsError(try config.validate()) { error in
            if let configError = error as? ServerConfigurationError,
               case .remotePathNotAbsolute = configError {
                // Expected
            } else {
                XCTFail("Expected remotePathNotAbsolute error")
            }
        }
    }

    // MARK: - Trailing Slash Normalization

    func testTrailingSlashNormalizationWithSlash() {
        let config = ServerConfiguration(remotePath: "/srv/uploads/")
        XCTAssertEqual(config.remotePathWithTrailingSlash, "/srv/uploads/")
    }

    func testTrailingSlashNormalizationWithoutSlash() {
        let config = ServerConfiguration(remotePath: "/srv/uploads")
        XCTAssertEqual(config.remotePathWithTrailingSlash, "/srv/uploads/")
    }

    // MARK: - Base URL

    func testBaseURLOptional() {
        let config = ServerConfiguration(
            host: "example.com",
            port: 22,
            username: "user",
            authMethod: .password,
            remotePath: "/uploads/"
        )
        XCTAssertNil(config.baseURL)
        XCTAssertTrue(config.isValid)
    }

    func testBaseURLValidation() {
        let config = ServerConfiguration(
            host: "example.com",
            port: 22,
            username: "user",
            authMethod: .password,
            remotePath: "/uploads/",
            baseURL: "not-a-valid-url"
        )
        XCTAssertFalse(config.isValid)
        XCTAssertThrowsError(try config.validate()) { error in
            if let configError = error as? ServerConfigurationError,
               case .invalidBaseURL = configError {
                // Expected
            } else {
                XCTFail("Expected invalidBaseURL error, got \(error)")
            }
        }
    }

    func testBaseURLMustHaveHTTPScheme() {
        let config = ServerConfiguration(
            host: "example.com",
            port: 22,
            username: "user",
            authMethod: .password,
            remotePath: "/uploads/",
            baseURL: "ftp://example.com/uploads/"
        )
        XCTAssertFalse(config.isValid)
    }

    func testBaseURLEmptyStringIsValid() {
        // Empty base URL should be treated as "not set" and pass validation
        let config = ServerConfiguration(
            host: "example.com",
            port: 22,
            username: "user",
            authMethod: .password,
            remotePath: "/uploads/",
            baseURL: ""
        )
        XCTAssertTrue(config.isValid)
    }

    // MARK: - Codable Round Trip

    func testCodableRoundTrip() throws {
        let original = ServerConfiguration(
            id: UUID(),
            name: "Test Server",
            host: "example.com",
            port: 2222,
            username: "deploy",
            authMethod: .password,
            sshKeyPath: nil,
            remotePath: "/var/www/uploads/",
            baseURL: "https://cdn.example.com/uploads/"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ServerConfiguration.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.host, original.host)
        XCTAssertEqual(decoded.port, original.port)
        XCTAssertEqual(decoded.username, original.username)
        XCTAssertEqual(decoded.authMethod, original.authMethod)
        XCTAssertEqual(decoded.sshKeyPath, original.sshKeyPath)
        XCTAssertEqual(decoded.remotePath, original.remotePath)
        XCTAssertEqual(decoded.baseURL, original.baseURL)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - Auth Method Codable

    func testAuthMethodCodable() throws {
        for method in AuthMethod.allCases {
            let encoder = JSONEncoder()
            let data = try encoder.encode(method)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(AuthMethod.self, from: data)

            XCTAssertEqual(decoded, method)
        }
    }

    func testAuthMethodRawValues() {
        XCTAssertEqual(AuthMethod.sshKey.rawValue, "sshKey")
        XCTAssertEqual(AuthMethod.password.rawValue, "password")
    }

    func testAuthMethodDisplayNames() {
        XCTAssertEqual(AuthMethod.sshKey.displayName, "SSH Key")
        XCTAssertEqual(AuthMethod.password.displayName, "Password")
    }

    // MARK: - SSH Key Validation

    func testSSHKeyAuthWithMissingPath() {
        let config = ServerConfiguration(
            host: "example.com",
            port: 22,
            username: "user",
            authMethod: .sshKey,
            sshKeyPath: nil,
            remotePath: "/uploads/"
        )
        XCTAssertFalse(config.isValid)
        XCTAssertThrowsError(try config.validate()) { error in
            if let configError = error as? ServerConfigurationError,
               case .sshKeyPathNotSet = configError {
                // Expected
            } else {
                XCTFail("Expected sshKeyPathNotSet error, got \(error)")
            }
        }
    }

    func testSSHKeyAuthWithNonExistentKeyFile() {
        let config = ServerConfiguration(
            host: "example.com",
            port: 22,
            username: "user",
            authMethod: .sshKey,
            sshKeyPath: "/nonexistent/path/id_rsa",
            remotePath: "/uploads/"
        )
        XCTAssertFalse(config.isValid)
        XCTAssertThrowsError(try config.validate()) { error in
            if let configError = error as? ServerConfigurationError,
               case .sshKeyNotFound = configError {
                // Expected
            } else {
                XCTFail("Expected sshKeyNotFound error, got \(error)")
            }
        }
    }

    // MARK: - Identifiable / Equatable

    func testIdentifiable() {
        let id = UUID()
        let config = ServerConfiguration(id: id)
        XCTAssertEqual(config.id, id)
    }

    func testEquatable() {
        let id = UUID()
        let config1 = ServerConfiguration(id: id, host: "a.com", port: 22, username: "u", authMethod: .password, remotePath: "/p/")
        let config2 = ServerConfiguration(id: id, host: "a.com", port: 22, username: "u", authMethod: .password, remotePath: "/p/")
        XCTAssertEqual(config1, config2)
    }
}
