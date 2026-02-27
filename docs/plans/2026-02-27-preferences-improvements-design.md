# Preferences Improvements Design

## Changes

### 1. Sidebar Navigation
- Replace `TabView` with custom sidebar using `List` + `HStack` layout
- Left sidebar ~150pt with icon + label rows, selection highlight
- 5 items: Server, Uploads, Shortcuts, General, Advanced
- Window size ~620x480

### 2. Auto-save
- Uploads, Shortcuts, General, Advanced: auto-save via `onChange`, no Save button
- Server tab: keep Save + Test Connection (intentional save for sensitive config)

### 3. Advanced Tab (new)
- Local cleanup: toggle, on by default, deletes temp files after upload
- Remote cleanup: toggle (off by default) + duration picker (1h, 6h, 12h, 1d, 7d, 30d, 90d)

### 4. Model Changes
- `AppSettings`: add `deleteLocalAfterUpload`, `autoDeleteRemoteFiles`, `remoteFileTTL`
- New `RemoteFileTTL` enum with presets
