# Contributing to DropShot

Thank you for your interest in contributing to DropShot. Whether you are reporting a bug, suggesting a feature, improving documentation, or writing code, your help is appreciated.

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). By participating, you agree to uphold a welcoming and respectful environment for everyone.

## How to Contribute

### Reporting Bugs

1. Search [existing issues](https://github.com/nickarino/DropShot/issues) to make sure the bug has not already been reported.
2. Open a new issue using the **Bug Report** template.
3. Include your macOS version, DropShot version, and clear steps to reproduce the problem.
4. If relevant, attach console logs from Console.app filtered by "DropShot".

### Suggesting Features

Open an issue using the **Feature Request** template. Describe the use case, not just the solution -- understanding *why* helps us design the right approach.

### Submitting Pull Requests

1. Fork the repository and create a feature branch from `main`.
2. Make your changes (see the development workflow below).
3. Write or update tests to cover your changes.
4. Submit a pull request targeting `main`.

## Development Setup

### Prerequisites

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later
- Docker (for integration tests only)

### Clone and build

```bash
git clone https://github.com/YOUR_USERNAME/DropShot.git
cd DropShot
swift build
```

### Run tests

```bash
# Unit tests
swift test

# Integration tests (requires Docker)
docker compose -f docker-compose.test.yml up -d
swift test --filter IntegrationTests
docker compose -f docker-compose.test.yml down -v
```

### Run the app

```bash
swift run DropShot
```

## Swift Style Guide

DropShot follows standard Swift conventions. Key points:

- **Naming**: Use `camelCase` for variables, functions, and parameters. Use `PascalCase` for types and protocols. Acronyms are uppercase only when they begin a type name (`SFTPTransport`, not `SftpTransport`).
- **Access control**: Mark types and members with the most restrictive access level that works. Prefer `private` over `internal` when something is only used within its declaring scope.
- **MARK comments**: Use `// MARK: -` to organize sections within a file (Properties, Initialization, Public Methods, Private Helpers, etc.).
- **Documentation**: Add doc comments (`///`) to all public types, methods, and properties.
- **SwiftLint**: The project includes SwiftLint rules. Run `swiftlint` before submitting a PR to catch style issues. CI runs SwiftLint as well, though violations are non-blocking to avoid friction.
- **Line length**: Aim for 120 characters or fewer. The linter warns at 150.
- **Force unwrapping**: Avoid `!` except in tests and truly impossible-nil situations. Prefer `guard let`, `if let`, or `??`.
- **Trailing closures**: Use trailing closure syntax for the last closure parameter only.

## Pull Request Process

### Branch naming

Use a descriptive prefix:

- `feature/` -- new functionality (e.g. `feature/clipboard-upload`)
- `fix/` -- bug fixes (e.g. `fix/unicode-filename-encoding`)
- `docs/` -- documentation changes
- `refactor/` -- code restructuring without behavior changes
- `test/` -- new or updated tests

### Commit messages

Write clear, imperative-mood commit messages:

```
Add upload progress animation to menu bar icon

The menu bar icon now shows an animated progress indicator during
active uploads. The animation respects the Reduce Motion accessibility
setting by falling back to a static badge.
```

- First line: 50 characters or fewer, imperative mood ("Add", "Fix", "Remove", not "Added", "Fixed", "Removed").
- Blank line, then an optional body wrapping at 72 characters.

### Review checklist

Before requesting review, verify:

- [ ] The code compiles without warnings (`swift build`)
- [ ] All existing tests pass (`swift test`)
- [ ] New tests cover the changes
- [ ] Documentation is updated if behavior changed
- [ ] SwiftLint reports no new violations
- [ ] The PR description explains *what* changed and *why*

### Review process

- At least one maintainer approval is required before merging.
- CI must pass (build, tests).
- PRs are squash-merged to keep the history clean.

## Testing Requirements

- **Unit tests are required** for all new logic -- models, services, utilities.
- **Integration tests are required** for changes to SFTP transport, connection handling, or file transfer logic. These run against the Docker-based SFTP server.
- **UI tests** are encouraged but not required for v1.0.
- Tests must not depend on network access or external services (except the Docker SFTP container for integration tests).

## Architecture Overview

The project is organized into four main layers:

```
DropShot/
  App/          Entry point, Info.plist, app lifecycle
  Models/       Data structures: ServerConfiguration, AppSettings, UploadRecord
  Core/         Business logic: PathBuilder, SFTPTransport protocol
  Services/     Service layer: upload orchestration, Keychain, network monitor
  UI/           SwiftUI views and components
  Resources/    Assets, localization files
```

- **Models** are plain Swift structs and enums with `Codable` conformance.
- **Core** defines protocols and stateless utilities.
- **Services** implement the protocols and manage side effects (network, filesystem, Keychain).
- **UI** contains SwiftUI views that observe service state via `@Observable` or `@ObservedObject`.

## Localization

DropShot ships with English (`en`) and Czech (`cs`) translations.

### Adding a new language

1. Create a new `.lproj` directory under `DropShot/Resources/` (e.g. `de.lproj/` for German).
2. Copy `Localizable.strings` from `en.lproj` (once it exists) into the new directory.
3. Translate all string values, keeping the keys unchanged.
4. Test by changing your macOS language in System Settings or by passing `-AppleLanguages "(de)"` as a launch argument.
5. Submit a PR with the new translations.

### String guidelines

- Use `NSLocalizedString("key", comment: "Context for translators")` or SwiftUI's `LocalizedStringKey`.
- Keep keys descriptive: `"upload.progress.percent"` not `"str47"`.
- Include a meaningful comment for every localized string to help translators.

## Questions?

If anything is unclear, open a [Discussion](https://github.com/nickarino/DropShot/discussions) or ask in a PR comment. We are happy to help.
