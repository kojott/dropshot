.PHONY: build test clean run lint format dmg docker-test

# DropShot - macOS Menu Bar SFTP Upload App
# Build and development targets

SWIFT_BUILD_FLAGS = -c release
DOCKER_COMPOSE_TEST = docker compose -f docker-compose.test.yml

# Build release binary
build:
	swift build $(SWIFT_BUILD_FLAGS)

# Run all tests
test:
	swift test

# Clean build artifacts
clean:
	swift package clean

# Build and run the app
run:
	swift run

# Run SwiftLint if installed
lint:
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint; \
	else \
		echo "SwiftLint is not installed. Install with: brew install swiftlint"; \
		exit 1; \
	fi

# Run swift-format if installed
format:
	@if command -v swift-format >/dev/null 2>&1; then \
		swift-format --recursive --in-place DropShot/ DropShotTests/; \
	else \
		echo "swift-format is not installed. Install with: brew install swift-format"; \
		exit 1; \
	fi

# Create DMG for distribution
dmg:
	@echo "=== DMG Creation ==="
	@echo "To create a distributable DMG:"
	@echo ""
	@echo "  1. Build the release binary:"
	@echo "     swift build -c release"
	@echo ""
	@echo "  2. Create the app bundle structure:"
	@echo "     mkdir -p DropShot.app/Contents/MacOS"
	@echo "     mkdir -p DropShot.app/Contents/Resources"
	@echo "     cp .build/release/DropShot DropShot.app/Contents/MacOS/"
	@echo "     cp DropShot/App/Info.plist DropShot.app/Contents/"
	@echo ""
	@echo "  3. Create the DMG:"
	@echo "     hdiutil create -volname DropShot -srcfolder DropShot.app -ov -format UDZO DropShot.dmg"
	@echo ""
	@echo "  4. (Optional) Sign and notarize:"
	@echo "     codesign --deep --force --sign \"Developer ID Application: ...\" DropShot.app"
	@echo "     xcrun notarytool submit DropShot.dmg --apple-id ... --team-id ... --password ..."

# Run integration tests with Docker test environment
docker-test:
	$(DOCKER_COMPOSE_TEST) up -d
	@echo "Waiting for services to be healthy..."
	@sleep 3
	swift test || ($(DOCKER_COMPOSE_TEST) down -v && exit 1)
	$(DOCKER_COMPOSE_TEST) down -v
