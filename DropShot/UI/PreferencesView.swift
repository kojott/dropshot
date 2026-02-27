import SwiftUI
import AppKit
import KeyboardShortcuts
import ServiceManagement

// MARK: - Preferences Tab

/// Identifies each tab in the preferences window.
enum PreferencesTab: String, CaseIterable, Identifiable {
    case server
    case uploads
    case shortcuts
    case general
    case advanced

    var id: String { rawValue }

    var label: String {
        switch self {
        case .server: return "Server"
        case .uploads: return "Uploads"
        case .shortcuts: return "Shortcuts"
        case .general: return "General"
        case .advanced: return "Advanced"
        }
    }

    var icon: String {
        switch self {
        case .server: return "server.rack"
        case .uploads: return "arrow.up.doc"
        case .shortcuts: return "keyboard"
        case .general: return "gearshape"
        case .advanced: return "wrench.and.screwdriver"
        }
    }
}

// MARK: - Preferences View

/// Sidebar-navigated preferences window for configuring DropShot.
/// Tabs are created lazily on first visit and kept alive to avoid
/// destroying NSViewRepresentable controls (KeyboardShortcuts.Recorder).
struct PreferencesView: View {
    @State private var selectedTab: PreferencesTab = .server
    @State private var visitedTabs: Set<PreferencesTab> = [.server]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
        .frame(width: 620, height: 480)
        .onChange(of: selectedTab) { newTab in
            visitedTabs.insert(newTab)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 2) {
            ForEach(PreferencesTab.allCases) { tab in
                SidebarRow(tab: tab, isSelected: selectedTab == tab)
                    .onTapGesture { selectedTab = tab }
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .frame(width: 150)
        .background(.background)
    }

    private var content: some View {
        ZStack {
            if visitedTabs.contains(.server) {
                ServerTab()
                    .opacity(selectedTab == .server ? 1 : 0)
                    .accessibilityHidden(selectedTab != .server)
            }
            if visitedTabs.contains(.uploads) {
                UploadsTab()
                    .opacity(selectedTab == .uploads ? 1 : 0)
                    .accessibilityHidden(selectedTab != .uploads)
            }
            if visitedTabs.contains(.shortcuts) {
                ShortcutsTab()
                    .opacity(selectedTab == .shortcuts ? 1 : 0)
                    .accessibilityHidden(selectedTab != .shortcuts)
            }
            if visitedTabs.contains(.general) {
                GeneralTab()
                    .opacity(selectedTab == .general ? 1 : 0)
                    .accessibilityHidden(selectedTab != .general)
            }
            if visitedTabs.contains(.advanced) {
                AdvancedTab()
                    .opacity(selectedTab == .advanced ? 1 : 0)
                    .accessibilityHidden(selectedTab != .advanced)
            }
        }
    }
}

// MARK: - Sidebar Row

private struct SidebarRow: View {
    let tab: PreferencesTab
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: tab.icon)
                .frame(width: 20)
                .foregroundStyle(isSelected ? .white : .secondary)
            Text(tab.label)
                .foregroundStyle(isSelected ? .white : .primary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Server Tab

/// Server connection settings: host, credentials, paths, and connection testing.
/// Keeps explicit Save button because server config changes should be intentional.
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
/// Auto-saves on every change.
private struct UploadsTab: View {
    @State private var filenamePattern: FilenamePattern = .original
    @State private var maxFileSizeMB: Int = 100
    @State private var duplicateHandling: DuplicateHandling = .appendSuffix
    @State private var isLoaded = false

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
        }
        .formStyle(.grouped)
        .onAppear(perform: loadSettings)
        .onChange(of: filenamePattern) { _ in autoSave() }
        .onChange(of: maxFileSizeMB) { _ in autoSave() }
        .onChange(of: duplicateHandling) { _ in autoSave() }
    }

    private func loadSettings() {
        let settings = AppSettings.shared
        filenamePattern = settings.filenamePattern
        maxFileSizeMB = settings.maxFileSizeMB
        duplicateHandling = settings.duplicateHandling
        isLoaded = true
    }

    private func autoSave() {
        guard isLoaded else { return }
        var settings = AppSettings.shared
        settings.filenamePattern = filenamePattern
        settings.maxFileSizeMB = maxFileSizeMB
        settings.duplicateHandling = duplicateHandling
        settings.save()
    }
}

// MARK: - Shortcuts Tab

/// Global keyboard shortcut configuration using the KeyboardShortcuts package.
/// Auto-saves on every change.
private struct ShortcutsTab: View {
    @State private var screenshotShortcutEnabled: Bool = true
    @State private var clipboardUploadShortcutEnabled: Bool = false
    @State private var isLoaded = false

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
        }
        .formStyle(.grouped)
        .onAppear(perform: loadSettings)
        .onChange(of: screenshotShortcutEnabled) { _ in autoSave() }
        .onChange(of: clipboardUploadShortcutEnabled) { _ in autoSave() }
    }

    private func loadSettings() {
        let settings = AppSettings.shared
        screenshotShortcutEnabled = settings.screenshotShortcutEnabled
        clipboardUploadShortcutEnabled = settings.clipboardUploadShortcutEnabled
        isLoaded = true
    }

    private func autoSave() {
        guard isLoaded else { return }
        var settings = AppSettings.shared
        settings.screenshotShortcutEnabled = screenshotShortcutEnabled
        settings.clipboardUploadShortcutEnabled = clipboardUploadShortcutEnabled
        settings.save()
    }
}

// MARK: - General Tab

/// Application-wide preferences: launch at login, notifications, diagnostics.
/// Auto-saves on every change (except reset which has confirmation).
private struct GeneralTab: View {
    @State private var launchAtLogin: Bool = false
    @State private var showNotifications: Bool = true
    @State private var playSound: Bool = false
    @State private var showResetConfirmation: Bool = false
    @State private var showExportSuccess: Bool = false
    @State private var isLoaded = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch DropShot at login", isOn: $launchAtLogin)
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
                Button("Reset to Defaults", role: .destructive) {
                    showResetConfirmation = true
                }
                .accessibilityLabel("Reset all settings to defaults")
                .accessibilityHint("This will erase all your custom settings")
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadSettings)
        .onChange(of: launchAtLogin) { newValue in
            updateLaunchAtLogin(newValue)
            autoSave()
        }
        .onChange(of: showNotifications) { _ in autoSave() }
        .onChange(of: playSound) { _ in autoSave() }
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
        isLoaded = true
    }

    private func autoSave() {
        guard isLoaded else { return }
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

    private func buildDiagnosticLog() -> String {
        let settings = AppSettings.shared
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
          Delete Local After Upload: \(settings.deleteLocalAfterUpload)
          Auto-Delete Remote Files: \(settings.autoDeleteRemoteFiles)
          Remote File TTL: \(settings.remoteFileTTL.displayName)
          Setup Completed: \(settings.hasCompletedSetup)
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

// MARK: - Advanced Tab

/// File cleanup settings: local temp file removal and remote file auto-deletion.
/// Auto-saves on every change.
private struct AdvancedTab: View {
    @State private var deleteLocalAfterUpload: Bool = true
    @State private var autoDeleteRemoteFiles: Bool = false
    @State private var remoteFileTTL: RemoteFileTTL = .sevenDays
    @State private var isLoaded = false

    var body: some View {
        Form {
            Section("Local Files") {
                Toggle("Delete local files after upload", isOn: $deleteLocalAfterUpload)
                    .accessibilityLabel("Delete local files after upload")
                Text("Temporary files are removed immediately after a successful upload.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Remote File Cleanup") {
                Toggle("Auto-delete uploaded files from server", isOn: $autoDeleteRemoteFiles)
                    .accessibilityLabel("Auto-delete remote files")

                if autoDeleteRemoteFiles {
                    Picker("Delete after:", selection: $remoteFileTTL) {
                        ForEach(RemoteFileTTL.allCases, id: \.self) { ttl in
                            Text(ttl.displayName).tag(ttl)
                        }
                    }
                    .accessibilityLabel("Remote file lifetime")

                    Label {
                        Text("Files will be permanently deleted from the server after \(remoteFileTTL.displayName.lowercased()). This cannot be undone.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadSettings)
        .onChange(of: deleteLocalAfterUpload) { _ in autoSave() }
        .onChange(of: autoDeleteRemoteFiles) { _ in autoSave() }
        .onChange(of: remoteFileTTL) { _ in autoSave() }
    }

    private func loadSettings() {
        let settings = AppSettings.shared
        deleteLocalAfterUpload = settings.deleteLocalAfterUpload
        autoDeleteRemoteFiles = settings.autoDeleteRemoteFiles
        remoteFileTTL = settings.remoteFileTTL
        isLoaded = true
    }

    private func autoSave() {
        guard isLoaded else { return }
        var settings = AppSettings.shared
        settings.deleteLocalAfterUpload = deleteLocalAfterUpload
        settings.autoDeleteRemoteFiles = autoDeleteRemoteFiles
        settings.remoteFileTTL = remoteFileTTL
        settings.save()
    }
}
