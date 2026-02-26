import SwiftUI
import AppKit

// MARK: - Menu Content View

/// Main SwiftUI view rendered inside the menu bar dropdown.
/// Hosted in an NSMenuItem via NSHostingView by the AppDelegate.
struct MenuContentView: View {
    @ObservedObject var networkMonitor: NetworkMonitor
    @ObservedObject var uploadManager: UploadManager

    @State private var recentUploads: [UploadRecord] = []
    @State private var isLoadingHistory = false

    /// The active server configuration, if any.
    var serverConfig: ServerConfiguration?

    /// Callback invoked when the user clicks Preferences.
    var onOpenPreferences: () -> Void = {}

    /// Callback invoked when the user clicks Quit.
    var onQuit: () -> Void = {}

    private let maxRecentUploads = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            serverStatusSection
            Divider().padding(.horizontal, 12)
            uploadProgressSection
            recentUploadsSection
            Divider().padding(.horizontal, 12)
            footerSection
        }
        .frame(width: 320)
        .task {
            await loadRecentUploads()
        }
        .onChange(of: uploadManager.isUploading) { _ in
            Task { await loadRecentUploads() }
        }
    }

    // MARK: - Server Status

    private var serverStatusSection: some View {
        HStack(spacing: 8) {
            connectionIndicator
            VStack(alignment: .leading, spacing: 1) {
                if let config = serverConfig, config.isValid {
                    Text(config.host)
                        .font(.system(.body, design: .default))
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text("\(config.username)@\(config.host):\(config.port)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text("No Server Configured")
                        .font(.system(.body, design: .default))
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    Text("Open Preferences to set up a server.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Image(systemName: "server.rack")
                .font(.title3)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(serverStatusAccessibilityLabel)
    }

    @ViewBuilder
    private var connectionIndicator: some View {
        Circle()
            .fill(connectionColor)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }

    private var connectionColor: Color {
        guard let config = serverConfig, config.isValid else {
            return .gray
        }
        return networkMonitor.isConnected ? .green : .red
    }

    private var serverStatusAccessibilityLabel: String {
        guard let config = serverConfig, config.isValid else {
            return "Server status: not configured"
        }
        let connectionStatus = networkMonitor.isConnected ? "connected" : "disconnected"
        return "Server \(config.host), \(connectionStatus)"
    }

    // MARK: - Upload Progress

    @ViewBuilder
    private var uploadProgressSection: some View {
        if uploadManager.isUploading, let current = uploadManager.currentUpload {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Upload in progress")

                    VStack(alignment: .leading, spacing: 2) {
                        Text(current.filename)
                            .font(.system(.body, design: .default))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text(progressText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(progressPercentageText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                ProgressView(value: uploadManager.overallProgress)
                    .progressViewStyle(.linear)
                    .accessibilityLabel("Upload progress \(Int(uploadManager.overallProgress * 100)) percent")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().padding(.horizontal, 12)
        }
    }

    private var progressText: String {
        let queueCount = uploadManager.uploadQueue.count
        if queueCount > 0 {
            return "Uploading (\(queueCount) more queued)"
        }
        return "Uploading..."
    }

    private var progressPercentageText: String {
        let percent = Int(uploadManager.overallProgress * 100)
        return "\(percent)%"
    }

    // MARK: - Recent Uploads

    @ViewBuilder
    private var recentUploadsSection: some View {
        if recentUploads.isEmpty && !uploadManager.isUploading {
            emptyStateView
        } else if !recentUploads.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(recentUploads) { record in
                    UploadRecordRow(record: record)
                    if record.id != recentUploads.last?.id {
                        Divider()
                            .padding(.horizontal, 12)
                            .opacity(0.5)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.up.doc")
                .font(.title2)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            Text("No recent uploads.")
                .font(.body)
                .foregroundColor(.secondary)
            Text("Drop a file on this icon\nto upload it.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No recent uploads. Drop a file on the menu bar icon to upload it.")
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onOpenPreferences) {
                HStack {
                    Image(systemName: "gear")
                        .frame(width: 16)
                    Text("Preferences...")
                    Spacer()
                    Text("\u{2318},")
                        .font(.system(.caption, design: .default))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(MenuItemButtonStyle())
            .keyboardShortcut(",", modifiers: .command)
            .accessibilityLabel("Preferences")
            .accessibilityHint("Opens the preferences window")

            Button(action: onQuit) {
                HStack {
                    Image(systemName: "power")
                        .frame(width: 16)
                    Text("Quit DropShot")
                    Spacer()
                    Text("\u{2318}Q")
                        .font(.system(.caption, design: .default))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(MenuItemButtonStyle())
            .keyboardShortcut("q", modifiers: .command)
            .accessibilityLabel("Quit DropShot")
        }
        .padding(.vertical, 4)
    }

    // MARK: - Data Loading

    private func loadRecentUploads() async {
        isLoadingHistory = true
        let records = await HistoryService.shared.recentRecords(limit: maxRecentUploads)
        recentUploads = records
        isLoadingHistory = false
    }
}

// MARK: - Upload Record Row

/// A single row in the recent uploads list, showing filename, truncated path, and a copy button.
private struct UploadRecordRow: View {
    let record: UploadRecord

    @State private var showCopiedFeedback = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            statusIcon
                .frame(width: 16)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.filename)
                    .font(.system(.body, design: .default))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 4) {
                    Text(truncatedPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if record.status == .completed {
                        Text("  \(record.formattedTimestamp)")
                            .font(.caption2)
                            .foregroundColor(.tertiary)
                    }
                }
            }

            Spacer()

            if record.status == .completed {
                Button(action: copyToClipboard) {
                    Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(showCopiedFeedback ? .green : .secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy path for \(record.filename)")
                .accessibilityHint("Copies the upload path to the clipboard")
                .help("Copy to clipboard")
            } else if record.status == .failed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
                    .help(record.errorMessage ?? "Upload failed")
                    .accessibilityLabel("Upload failed")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.filename), \(record.status.displayName)")
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch record.status {
        case .completed:
            Image(systemName: "doc.text")
                .foregroundColor(.secondary)
        case .failed:
            Image(systemName: "doc.text")
                .foregroundColor(.red)
        case .uploading:
            ProgressView()
                .controlSize(.mini)
        case .cancelled:
            Image(systemName: "doc.text")
                .foregroundColor(.secondary)
                .opacity(0.5)
        }
    }

    private var truncatedPath: String {
        let path = record.copyableText
        if path.count > 30 {
            let prefix = path.prefix(25)
            return "\(prefix)..."
        }
        return path
    }

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(record.copyableText, forType: .string)

        withAnimation(.easeInOut(duration: 0.2)) {
            showCopiedFeedback = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showCopiedFeedback = false
            }
        }
    }
}

// MARK: - Menu Item Button Style

/// A button style that mimics the hover behavior of native NSMenu items.
private struct MenuItemButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .onHover { hovering in
                isHovered = hovering
            }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return Color.accentColor.opacity(0.8)
        } else if isHovered {
            return Color.accentColor.opacity(0.3)
        }
        return Color.clear
    }
}
