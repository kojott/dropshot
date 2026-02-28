# Changelog

All notable changes to DropShot will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.7] - 

## [1.1.6] - 

## [1.1.4] - 

## [1.1.3] - 

## [1.1.2] - 

## [1.1.1] - 

## [1.1.0] - 

## [1.0.5] - 

## [1.0.4] - 

## [1.0.3] - 

## [1.0.2] - 

## [1.0.1] - 

### Added

- macOS menu bar app with drag-and-drop file upload via SFTP
- Screenshot capture with configurable global keyboard shortcut (Command+Shift+U)
- Absolute server path copied to clipboard after upload
- Optional public URL mode with configurable base URL
- Full Unicode filename support (Czech diacritics, CJK characters, emoji, combining marks)
- RFC 3986 percent-encoding for filenames in URL mode
- SSH key authentication with auto-detection of `id_ed25519`, `id_rsa`, and `id_ecdsa` keys
- ssh-agent support including 1Password SSH agent integration
- Password authentication as an alternative to SSH keys
- macOS Keychain integration for secure credential storage
- Upload queue with real-time progress indicators and per-file cancellation
- Host key verification using trust-on-first-use (TOFU) model with mismatch warnings
- Network connectivity monitoring with automatic pause/resume of uploads
- Multi-file upload support with per-line clipboard output
- Configurable filename patterns: original, date-time prefixed, UUID, and content hash
- Duplicate filename handling: append numeric suffix or overwrite existing
- Configurable maximum file size limit
- Server configuration with validation (host, port, username, remote path)
- Connection testing from the preferences UI
- Launch at Login option
- macOS notification support on upload completion
- Accessibility: VoiceOver support, keyboard navigation, Reduce Motion compliance
- English and Czech localization
- Unit test suite
- Integration test suite using Docker-based SFTP server (atmoz/sftp)
- GitHub Actions CI workflow (build, test, lint)
- GitHub Actions release workflow (universal binary, signing, notarization, DMG, GitHub Release)
- Homebrew cask formula
- Server setup guide for new users

[Unreleased]: https://github.com/kojott/dropshot/compare/v1.1.7...HEAD
[1.1.7]: https://github.com/kojott/dropshot/compare/v1.1.6...v1.1.7
[1.1.6]: https://github.com/kojott/dropshot/compare/v1.1.5...v1.1.6
[1.1.4]: https://github.com/kojott/dropshot/compare/v1.1.3...v1.1.4
[1.1.3]: https://github.com/kojott/dropshot/compare/v1.1.2...v1.1.3
[1.1.2]: https://github.com/kojott/dropshot/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/kojott/dropshot/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/kojott/dropshot/compare/v1.0.5...v1.1.0
[1.0.5]: https://github.com/kojott/dropshot/compare/v1.0.4...v1.0.5
[1.0.4]: https://github.com/kojott/dropshot/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/kojott/dropshot/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/kojott/dropshot/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/kojott/dropshot/compare/v1.0.0...v1.0.1
