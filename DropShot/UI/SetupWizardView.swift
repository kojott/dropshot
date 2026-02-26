import SwiftUI
import ServiceManagement

// MARK: - Setup Step

/// Tracks the current step in the first-run setup wizard.
private enum SetupStep: Int, CaseIterable {
    case welcome = 0
    case serverConfiguration = 1
    case ready = 2

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .serverConfiguration: return "Server"
        case .ready: return "Ready"
        }
    }
}

// MARK: - Setup Wizard View

/// Three-step first-run setup wizard presented in a fixed-size window (480x400pt).
/// Guides users through initial server configuration after installation.
struct SetupWizardView: View {
    @State private var currentStep: SetupStep = .welcome

    // Server configuration fields
    @State private var host: String = ""
    @State private var port: Int = 22
    @State private var username: String = ""
    @State private var authMethod: AuthMethod = .sshKey
    @State private var sshKeyPath: String = ServerConfiguration.detectDefaultSSHKeyPath() ?? ""
    @State private var remotePath: String = "/srv/uploads/"
    @State private var baseURL: String = ""

    // Connection test
    @State private var connectionTestPassed: Bool = false
    @State private var connectionTestMessage: String = ""
    @State private var isTesting: Bool = false

    // Ready step options
    @State private var launchAtLogin: Bool = false
    @State private var enableScreenshotShortcut: Bool = true

    // File importer
    @State private var showFileImporter: Bool = false

    /// Called when the wizard finishes or is skipped. The hosting controller should dismiss the window.
    var onComplete: () -> Void = {}

    /// Detects reduced motion preference for cross-step transitions.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            stepIndicator
                .padding(.top, 20)
                .padding(.bottom, 16)

            Divider()

            // Step content
            Group {
                switch currentStep {
                case .welcome:
                    welcomeStep
                case .serverConfiguration:
                    serverConfigurationStep
                case .ready:
                    readyStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(stepTransition)

            Divider()

            // Navigation buttons
            navigationButtons
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .frame(width: 480, height: 400)
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 24) {
            ForEach(SetupStep.allCases, id: \.rawValue) { step in
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(stepCircleColor(for: step))
                            .frame(width: 24, height: 24)

                        if step.rawValue < currentStep.rawValue {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        } else {
                            Text("\(step.rawValue + 1)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(step == currentStep ? .white : .secondary)
                        }
                    }
                    .accessibilityHidden(true)

                    Text(step.title)
                        .font(.caption)
                        .foregroundColor(step == currentStep ? .primary : .secondary)
                        .fontWeight(step == currentStep ? .semibold : .regular)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(step.title), step \(step.rawValue + 1) of \(SetupStep.allCases.count)")
                .accessibilityAddTraits(step == currentStep ? .isSelected : [])

                if step != SetupStep.allCases.last {
                    Rectangle()
                        .fill(step.rawValue < currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(height: 1)
                        .frame(maxWidth: 40)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func stepCircleColor(for step: SetupStep) -> Color {
        if step.rawValue < currentStep.rawValue {
            return .accentColor
        } else if step == currentStep {
            return .accentColor
        }
        return Color.secondary.opacity(0.3)
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "arrow.up.to.line.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("Welcome to DropShot")
                .font(.title)
                .fontWeight(.semibold)

            Text("Upload files to your server with a simple drag and drop.\nScreenshots, clipboard content, and files are uploaded via SFTP\nand the URL is copied to your clipboard instantly.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 24)

            HStack(spacing: 6) {
                Image(systemName: "key.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("You'll need SSH access to a server to get started.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)

            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Step 2: Server Configuration

    private var serverConfigurationStep: some View {
        Form {
            Section {
                TextField("Host:", text: $host, prompt: Text("files.example.com"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Server hostname")
                    .onChange(of: host) { _ in resetTestState() }

                TextField("Username:", text: $username, prompt: Text("deploy"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("SSH username")
                    .onChange(of: username) { _ in resetTestState() }

                Picker("Authentication:", selection: $authMethod) {
                    ForEach(AuthMethod.allCases, id: \.self) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .onChange(of: authMethod) { _ in resetTestState() }
                .accessibilityLabel("Authentication method")

                if authMethod == .sshKey {
                    HStack {
                        TextField("SSH Key:", text: $sshKeyPath, prompt: Text("~/.ssh/id_ed25519"))
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("SSH key file path")
                            .onChange(of: sshKeyPath) { _ in resetTestState() }

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
                            resetTestState()
                        }
                    }
                }

                TextField("Remote Path:", text: $remotePath, prompt: Text("/srv/uploads/"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Remote upload directory path")
                    .onChange(of: remotePath) { _ in resetTestState() }
            }

            Section {
                HStack {
                    testConnectionResult
                    Spacer()
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
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var testConnectionResult: some View {
        if !connectionTestMessage.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: connectionTestPassed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(connectionTestPassed ? .green : .red)
                    .font(.caption)
                Text(connectionTestMessage)
                    .font(.caption)
                    .foregroundColor(connectionTestPassed ? .green : .red)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Connection test: \(connectionTestMessage)")
        }
    }

    // MARK: - Step 3: Ready

    private var readyStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)
                .accessibilityHidden(true)

            Text("You're All Set!")
                .font(.title)
                .fontWeight(.semibold)

            Text("DropShot is configured and ready to use.\nDrag files onto the menu bar icon to upload them.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Launch DropShot at login", isOn: $launchAtLogin)
                    .accessibilityLabel("Launch at login")

                Toggle("Enable screenshot shortcut (\u{21E7}\u{2318}U)", isOn: $enableScreenshotShortcut)
                    .accessibilityLabel("Enable screenshot keyboard shortcut")
            }
            .padding(.horizontal, 60)
            .padding(.top, 8)

            Spacer()
        }
    }

    // MARK: - Navigation

    private var navigationButtons: some View {
        HStack {
            switch currentStep {
            case .welcome:
                Button("Skip") {
                    markSetupComplete()
                    onComplete()
                }
                .accessibilityLabel("Skip setup wizard")
                Spacer()
                Button("Get Started") {
                    goToStep(.serverConfiguration)
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("Begin server setup")

            case .serverConfiguration:
                Button("Back") {
                    goToStep(.welcome)
                }
                .accessibilityLabel("Go back to welcome")
                Spacer()
                Button("Next") {
                    goToStep(.ready)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!connectionTestPassed)
                .accessibilityLabel("Continue to final step")
                .accessibilityHint(connectionTestPassed ? "" : "Test the connection first before proceeding")

            case .ready:
                Spacer()
                Button("Finish") {
                    saveAndFinish()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("Finish setup and start using DropShot")
            }
        }
    }

    private var stepTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    // MARK: - Actions

    private func goToStep(_ step: SetupStep) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
            currentStep = step
        }
    }

    private func resetTestState() {
        connectionTestPassed = false
        connectionTestMessage = ""
    }

    private func testConnection() {
        isTesting = true
        connectionTestMessage = ""

        let config = ServerConfiguration(
            host: host,
            port: port,
            username: username,
            authMethod: authMethod,
            sshKeyPath: sshKeyPath.isEmpty ? nil : sshKeyPath,
            remotePath: remotePath,
            baseURL: baseURL.isEmpty ? nil : baseURL
        )

        // Validate the configuration structure first.
        do {
            try config.validate()
        } catch {
            connectionTestMessage = error.localizedDescription
            connectionTestPassed = false
            isTesting = false
            return
        }

        Task {
            do {
                let transport = SystemSFTPTransport()
                let serverInfo = try await transport.testConnection(config: config)
                await MainActor.run {
                    connectionTestPassed = true
                    connectionTestMessage = serverInfo
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    connectionTestPassed = false
                    connectionTestMessage = error.localizedDescription
                    isTesting = false
                }
            }
        }
    }

    private func saveAndFinish() {
        // Save server configuration
        let config = ServerConfiguration(
            host: host,
            port: port,
            username: username,
            authMethod: authMethod,
            sshKeyPath: sshKeyPath.isEmpty ? nil : sshKeyPath,
            remotePath: remotePath,
            baseURL: baseURL.isEmpty ? nil : baseURL
        )

        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "com.dropshot.serverConfig")
        }

        // Save app settings
        var settings = AppSettings.shared
        settings.launchAtLogin = launchAtLogin
        settings.screenshotShortcutEnabled = enableScreenshotShortcut
        settings.hasCompletedSetup = true
        settings.save()

        // Register or unregister launch at login
        if #available(macOS 13.0, *) {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("[SetupWizard] Failed to update launch at login: \(error.localizedDescription)")
            }
        }

        markSetupComplete()
        onComplete()
    }

    private func markSetupComplete() {
        var settings = AppSettings.shared
        settings.hasCompletedSetup = true
        settings.save()
    }
}
