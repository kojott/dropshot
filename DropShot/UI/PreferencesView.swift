import SwiftUI
import AppKit
import KeyboardShortcuts
import ServiceManagement

// MARK: - Preferences Tab

/// Identifies each tab in the preferences window.
private enum PreferencesTab: Hashable {
    case server
    case uploads
    case shortcuts
    case general
}

// MARK: - Preferences View

/// Four-tab preferences window for configuring DropShot.
/// Designed for a 500x400pt window hosted via NSHostingController.
struct PreferencesView: View {
    @State private var selectedTab: PreferencesTab = .server

    var body: some View {
        TabView(selection: $selectedTab) {
            ServerTab()
                .tabItem {
                    Label("Server", systemImage: "server.rack")
                }
                .tag(PreferencesTab.server)

            UploadsTab()
                .tabItem {
                    Label("Uploads", systemImage: "arrow.up.doc")
                }
                .tag(PreferencesTab.uploads)

            ShortcutsTab()
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
                .tag(PreferencesTab.shortcuts)

            GeneralTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(PreferencesTab.general)
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - Server Tab

/// Server connection settings: host, credentials, paths, and connection testing.
private struct ServerTab: View {
    @State private var host: String = ""
    @State private var port: Int = 22
    @State private var username: String = ""
    @State private var authMethod: AuthMethod = .sshKey
    @State private var sshKeyPath: String = ""
    @State private var remotePath: String = "/srv/uploads/"
    @State private var baseURL: String = ""
    @State private var showAdvanced: Bool = false
    @State private var showFileImporter: Bool = false

    @State private var testResult: TestConnectionResult?
    @State private var isTesting: Bool = false
    @State private var isSaving: Bool = false

    var body: some View {
        Form {
            Section {
                TextField("Host:", text: $host, prompt: Text("files.example.com"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Server hostname")

                TextField("Username:", text: $username, prompt: Text("deploy"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("SSH username")

                Picker("Authentication:", selection: $authMethod) {
                    ForEach(AuthMethod.allCases, id: \.self) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .accessibilityLabel("Authentication method")

                if authMethod == .sshKey {
                    HStack {
                        TextField("SSH Key:", text: $sshKeyPath, prompt: Text("~/.ssh/id_ed25519"))
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("SSH key file path")

                        Button("Browse...") {
                            showFileImporter = true
                        }
                        .accessibilityLabel("Browse for SSH key file")
                    }
                    .fileImporter(
                        isPresented: $showFileImporter,
                        allowedContentTypes: [.data],
                        allowsMultipleSelection: false
                    ) { result in
                        if case .success(let urls) = result, let url = urls.first {
                            sshKeyPath = url.path
                        }
                    }
                }

                if authMethod == .password {
                    Text("Password is stored securely in the macOS Keychain.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                TextField("Remote Path:", text: $remotePath, prompt: Text("/srv/uploads/"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Remote upload directory path")
            }

            // Advanced section: base URL and port
            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                TextField("Base URL:", text: $baseURL, prompt: Text("https://files.example.com/uploads/"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Public base URL for uploaded files")

                HStack {
                    Text("Port:")
                    TextField("", value: $port, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .accessibilityLabel("SSH port number")
                }
            }

            Section {
                HStack {
                    connectionTestResult
                    Spacer()
                    testConnectionButton
                    saveButton
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadCurrentConfig)
    }

    // MARK: - Connection Test

    @ViewBuilder
    private var connectionTestResult: some View {
        if let result = testResult {
            HStack(spacing: 4) {
                Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(result.isSuccess ? .green : .red)
                    .font(.caption)
                Text(result.message)
                    .font(.caption)
                    .foregroundColor(result.isSuccess ? .green : .red)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Connection test: \(result.message)")
        }
    }

    private var testConnectionButton: some View {
        Button(action: testConnection) {
            if isTesting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text("Test Connection")
            }
        }
        .disabled(isTesting || host.isEmpty || username.isEmpty)
        .accessibilityLabel("Test connection to server")
    }

    private var saveButton: some View {
        Button("Save") {
            saveConfiguration()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(isSaving)
        .accessibilityLabel("Save server configuration")
    }

    // MARK: - Actions

    private func loadCurrentConfig() {
        // Load the first stored server config from UserDefaults, or use defaults.
        if let data = UserDefaults.standard.data(forKey: "com.dropshot.serverConfig"),
           let config = try? JSONDecoder().decode(ServerConfiguration.self, from: data) {
            host = config.host
            port = config.port
            username = config.username
            authMethod = config.authMethod
            sshKeyPath = config.sshKeyPath ?? ""
            remotePath = config.remotePath
            baseURL = config.baseURL ?? ""
        } else if let detectedKey = ServerConfiguration.detectDefaultSSHKeyPath() {
            sshKeyPath = detectedKey
        }
    }

    private func saveConfiguration() {
        isSaving = true
        let config = ServerConfiguration(
            host: host,
            port: port,
            username: username,
            authMethod: authMethod,
            sshKeyPath: sshKeyPath.isEmpty ? nil : sshKeyPath,
            remotePath: remotePath,
            baseURL: baseURL.isEmpty ? nil : baseURL
        )

        do {
            let data = try JSONEncoder().encode(config)
            UserDefaults.standard.set(data, forKey: "com.dropshot.serverConfig")
            testResult = TestConnectionResult(isSuccess: true, message: "Saved.")
        } catch {
            testResult = TestConnectionResult(isSuccess: false, message: "Failed to save: \(error.localizedDescription)")
        }
        isSaving = false
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        let config = ServerConfiguration(
            host: host,
            port: port,
            username: username,
            authMethod: authMethod,
            sshKeyPath: sshKeyPath.isEmpty ? nil : sshKeyPath,
            remotePath: remotePath,
            baseURL: baseURL.isEmpty ? nil : baseURL
        )

        // Validate configuration locally before attempting a network test.
        do {
            try config.validate()
        } catch {
            testResult = TestConnectionResult(isSuccess: false, message: error.localizedDescription)
            isTesting = false
            return
        }

        Task {
            do {
                let transport = SystemSFTPTransport()
                let serverInfo = try await transport.testConnection(config: config)
                await MainActor.run {
                    testResult = TestConnectionResult(isSuccess: true, message: serverInfo)
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = TestConnectionResult(isSuccess: false, message: error.localizedDescription)
                    isTesting = false
                }
            }
        }
    }
}

/// Result of a connection test attempt, shown inline in the Server tab.
private struct TestConnectionResult {
    let isSuccess: Bool
    let message: String
}

// MARK: - Uploads Tab

/// File handling settings: filename patterns, size limits, duplicate handling.
private struct UploadsTab: View {
    @State private var filenamePattern: FilenamePattern = .original
    @State private var maxFileSizeMB: Int = 100
    @State private var duplicateHandling: DuplicateHandling = .appendSuffix

    var body: some View {
        Form {
            Section("Filename") {
                Picker("Filename pattern:", selection: $filenamePattern) {
                    ForEach(FilenamePattern.allCases, id: \.self) { pattern in
                        VStack(alignment: .leading) {
                            Text(pattern.displayName)
                            Text(pattern.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .tag(pattern)
                    }
                }
                .accessibilityLabel("Filename pattern")

                Text("Example: \(filenamePattern.description)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("File Size") {
                Stepper(
                    "Maximum file size: \(maxFileSizeMB == 0 ? "Unlimited" : "\(maxFileSizeMB) MB")",
                    value: $maxFileSizeMB,
                    in: 0...1000,
                    step: 10
                )
                .accessibilityLabel("Maximum file size")
                .accessibilityValue(maxFileSizeMB == 0 ? "Unlimited" : "\(maxFileSizeMB) megabytes")

                if maxFileSizeMB == 0 {
                    Text("No file size limit will be enforced.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Duplicates") {
                Picker("When a file already exists:", selection: $duplicateHandling) {
                    ForEach(DuplicateHandling.allCases, id: \.self) { handling in
                        Text(handling.displayName).tag(handling)
                    }
                }
                .accessibilityLabel("Duplicate file handling")
            }

            Section {
                Text("After uploading, the public URL or server path is automatically copied to your clipboard.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Save") {
                        saveUploadSettings()
                    }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel("Save upload settings")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadSettings)
    }

    private func loadSettings() {
        let settings = AppSettings.shared
        filenamePattern = settings.filenamePattern
        maxFileSizeMB = settings.maxFileSizeMB
        duplicateHandling = settings.duplicateHandling
    }

    private func saveUploadSettings() {
        var settings = AppSettings.shared
        settings.filenamePattern = filenamePattern
        settings.maxFileSizeMB = maxFileSizeMB
        settings.duplicateHandling = duplicateHandling
        settings.save()
    }
}

// MARK: - Shortcuts Tab

/// Global keyboard shortcut configuration using the KeyboardShortcuts package.
private struct ShortcutsTab: View {
    @State private var screenshotShortcutEnabled: Bool = true
    @State private var clipboardUploadShortcutEnabled: Bool = false

    var body: some View {
        Form {
            Section("Screenshot") {
                ShortcutRecorderView(
                    name: .captureScreenshot,
                    label: "Capture & upload screenshot",
                    isEnabled: $screenshotShortcutEnabled
                )
                Text("Takes a screenshot of the selected area and uploads it immediately.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Clipboard") {
                ShortcutRecorderView(
                    name: .uploadClipboard,
                    label: "Upload clipboard contents",
                    isEnabled: $clipboardUploadShortcutEnabled
                )
                Text("Uploads the current clipboard image or file to the server.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Save") {
                        saveShortcutSettings()
                    }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel("Save shortcut settings")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadSettings)
    }

    private func loadSettings() {
        let settings = AppSettings.shared
        screenshotShortcutEnabled = settings.screenshotShortcutEnabled
        clipboardUploadShortcutEnabled = settings.clipboardUploadShortcutEnabled
    }

    private func saveShortcutSettings() {
        var settings = AppSettings.shared
        settings.screenshotShortcutEnabled = screenshotShortcutEnabled
        settings.clipboardUploadShortcutEnabled = clipboardUploadShortcutEnabled
        settings.save()
    }
}

// MARK: - General Tab

/// Application-wide preferences: launch at login, notifications, diagnostics.
private struct GeneralTab: View {
    @State private var launchAtLogin: Bool = false
    @State private var showNotifications: Bool = true
    @State private var playSound: Bool = false
    @State private var showResetConfirmation: Bool = false
    @State private var showExportSuccess: Bool = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch DropShot at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        updateLaunchAtLogin(newValue)
                    }
                    .accessibilityLabel("Launch at login")
            }

            Section("Notifications") {
                Toggle("Show upload notifications", isOn: $showNotifications)
                    .accessibilityLabel("Show notifications")
                Toggle("Play sound on upload completion", isOn: $playSound)
                    .accessibilityLabel("Play sound")
            }

            Section("Diagnostics") {
                Button("Export Diagnostic Log...") {
                    exportDiagnosticLog()
                }
                .accessibilityLabel("Export diagnostic log")
                .accessibilityHint("Saves a diagnostic log file to your chosen location")

                if showExportSuccess {
                    Text("Log exported successfully.")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            Section {
                HStack {
                    Button("Reset to Defaults", role: .destructive) {
                        showResetConfirmation = true
                    }
                    .accessibilityLabel("Reset all settings to defaults")
                    .accessibilityHint("This will erase all your custom settings")

                    Spacer()

                    Button("Save") {
                        saveGeneralSettings()
                    }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel("Save general settings")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadSettings)
        .alert("Reset to Defaults?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                resetToDefaults()
            }
        } message: {
            Text("This will reset all settings to their default values. Server configuration will not be affected.")
        }
    }

    private func loadSettings() {
        let settings = AppSettings.shared
        launchAtLogin = settings.launchAtLogin
        showNotifications = settings.showNotifications
        playSound = settings.playSound
    }

    private func saveGeneralSettings() {
        var settings = AppSettings.shared
        settings.launchAtLogin = launchAtLogin
        settings.showNotifications = showNotifications
        settings.playSound = playSound
        settings.save()
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("[GeneralTab] Failed to update launch at login: \(error.localizedDescription)")
                // Revert the toggle if the operation fails.
                launchAtLogin = !enabled
            }
        }
    }

    private func exportDiagnosticLog() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "DropShot-diagnostic.log"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        // Capture MainActor-isolated values before the nonisolated NSSavePanel callback
        let logContent = buildDiagnosticLog()

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try logContent.write(to: url, atomically: true, encoding: .utf8)
                showExportSuccess = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    showExportSuccess = false
                }
            } catch {
                print("[GeneralTab] Failed to export diagnostic log: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func buildDiagnosticLog() -> String {
        let settings = AppSettings.shared
        let networkConnected = NetworkMonitor.shared.isConnected
        let networkType = NetworkMonitor.shared.connectionType
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"

        var log = """
        DropShot Diagnostic Log
        Generated: \(dateFormatter.string(from: Date()))
        ----------------------------------------
        macOS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)
        App Settings:
          Filename Pattern: \(settings.filenamePattern.displayName)
          Max File Size: \(settings.maxFileSizeMB == 0 ? "Unlimited" : "\(settings.maxFileSizeMB) MB")
          Duplicate Handling: \(settings.duplicateHandling.displayName)
          Launch at Login: \(settings.launchAtLogin)
          Notifications: \(settings.showNotifications)
          Sound: \(settings.playSound)
          Screenshot Shortcut Enabled: \(settings.screenshotShortcutEnabled)
          Clipboard Shortcut Enabled: \(settings.clipboardUploadShortcutEnabled)
          Setup Completed: \(settings.hasCompletedSetup)
        Network:
          Connected: \(networkConnected)
          Connection Type: \(networkType)
        ----------------------------------------
        """
        log += "\nEnd of diagnostic log.\n"
        return log
    }

    private func resetToDefaults() {
        AppSettings.resetToDefaults()
        loadSettings()
    }
}
