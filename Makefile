PROJECT := Screen-Remote.xcodeproj
SCHEME := Screen-Remote
CONFIGURATION ?= Debug
BUILD_ROOT := $(CURDIR)/.build
DERIVED_DATA := $(BUILD_ROOT)/DerivedData
APP := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/Screen Remote.app
EXECUTABLE := $(APP)/Contents/MacOS/Screen Remote
RELEASE_ROOT := $(BUILD_ROOT)/ReleasePackage
RELEASE_DERIVED_DATA := $(RELEASE_ROOT)/DerivedData
RELEASE_ARCHIVE := $(RELEASE_ROOT)/Screen-Remote.xcarchive
RELEASE_APP := $(RELEASE_ARCHIVE)/Products/Applications/Screen Remote.app
RELEASE_EXECUTABLE := $(RELEASE_APP)/Contents/MacOS/Screen Remote
RELEASE_STAGING := $(RELEASE_ROOT)/DiskImage
DMG_ASSETS := $(CURDIR)/assets/dmg
DMG_BACKGROUND := $(DMG_ASSETS)/.background/background.tiff
CREATE_DMG ?= $(shell command -v create-dmg 2>/dev/null)
DIST_DIR ?= $(CURDIR)/dist
RELEASE_ARCHS ?= arm64
RELEASE_CODE_SIGNING_ALLOWED ?= NO
RELEASE_SIGNING_IDENTITY ?=
RELEASE_LOG_FILE ?= $(RELEASE_ROOT)/release.log
RELEASE_LOG_TAIL_LINES ?= 80
NOTARY_PROFILE ?=
PID_FILE := $(BUILD_ROOT)/screen-remote.pid
LOG_FILE := $(BUILD_ROOT)/screen-remote.log
STAMP_FILE := $(BUILD_ROOT)/last-successful-build
WATCH_PATHS := Screen-Remote Screen-Remote.xcodeproj/project.pbxproj

.PHONY: help prepare-assets check-session-parameters build release run dev reload launch stop logs clean

help:
	@echo "make run      Build and launch the app outside Xcode"
	@echo "make dev      Watch source files, then rebuild and restart on changes"
	@echo "make release  Archive an unsigned Release build and create a DMG in dist/"
	@echo "make check-session-parameters  Verify every screen option update classification"
	@echo "make logs     Follow the application log"
	@echo "make stop     Stop the application launched by this Makefile"
	@echo "make clean    Remove local build artifacts"

prepare-assets:
	@"$(CURDIR)/scripts/prepare-scrcpy-server.sh"

check-session-parameters:
	@set -eu; \
		output="$$(mktemp "$${TMPDIR:-/tmp}/screen-remote-session-parameters.XXXXXX")"; \
		trap 'rm -f "$$output"' EXIT; \
		xcrun swiftc \
			"$(CURDIR)/Screen-Remote/Core/Models/ScrcpyDeviceOptions.swift" \
			"$(CURDIR)/Screen-Remote/Services/Scrcpy/Session/SessionParameterController.swift" \
			"$(CURDIR)/scripts/check-session-parameters.swift" \
			-o "$$output"; \
		"$$output"

build: prepare-assets
	@mkdir -p "$(BUILD_ROOT)"
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		CODE_SIGNING_ALLOWED=NO \
		ENABLE_APP_SANDBOX=NO \
		build
	@touch "$(STAMP_FILE)"

release: prepare-assets
	@mkdir -p "$(RELEASE_ROOT)" "$(DIST_DIR)"
	@test -f "$(DMG_BACKGROUND)" || { echo "Missing DMG background: $(DMG_BACKGROUND)"; exit 1; }
	@test -f "$(DMG_ASSETS)/Tools" || { echo "Missing helper tool: $(DMG_ASSETS)/Tools"; exit 1; }
	@test -f "$(DMG_ASSETS)/README.rtf" || { echo "Missing installation guide: $(DMG_ASSETS)/README.rtf"; exit 1; }
	@set -eu; \
		release_log="$(RELEASE_LOG_FILE)"; \
		: > "$$release_log"; \
		run_logged() { \
			step="$$1"; shift; \
			echo "==> $$step"; \
			if "$$@" >>"$$release_log" 2>&1; then \
				return 0; \
			else \
				command_exit_code="$$?"; \
				echo "Release failed during: $$step" >&2; \
				echo "Full release log: $$release_log" >&2; \
				tail -n "$(RELEASE_LOG_TAIL_LINES)" "$$release_log" >&2 || true; \
				exit "$$command_exit_code"; \
			fi; \
		}; \
		echo "Release log: $$release_log"; \
		rm -rf "$(RELEASE_DERIVED_DATA)" "$(RELEASE_ARCHIVE)" "$(RELEASE_STAGING)"; \
		signing_identity="$(RELEASE_SIGNING_IDENTITY)"; \
		if [ "$(RELEASE_CODE_SIGNING_ALLOWED)" = "YES" ]; then \
			if [ -n "$$signing_identity" ]; then \
				echo "Using requested signing identity: $$signing_identity"; \
				run_logged "Archive" xcodebuild \
					-project "$(PROJECT)" \
					-scheme "$(SCHEME)" \
					-configuration Release \
					-destination "generic/platform=macOS" \
					-derivedDataPath "$(RELEASE_DERIVED_DATA)" \
					-archivePath "$(RELEASE_ARCHIVE)" \
					ARCHS="$(RELEASE_ARCHS)" \
					ONLY_ACTIVE_ARCH=NO \
					CODE_SIGNING_ALLOWED=YES \
					CODE_SIGN_STYLE=Manual \
					"CODE_SIGN_IDENTITY=$$signing_identity" \
					archive; \
			else \
				echo "Using Xcode automatic signing for the configured development team"; \
				run_logged "Archive" xcodebuild \
					-project "$(PROJECT)" \
					-scheme "$(SCHEME)" \
					-configuration Release \
					-destination "generic/platform=macOS" \
					-derivedDataPath "$(RELEASE_DERIVED_DATA)" \
					-archivePath "$(RELEASE_ARCHIVE)" \
					ARCHS="$(RELEASE_ARCHS)" \
					ONLY_ACTIVE_ARCH=NO \
					CODE_SIGNING_ALLOWED=YES \
					archive; \
			fi; \
		else \
			echo "Warning: creating an unsigned release package."; \
			run_logged "Archive" xcodebuild \
				-project "$(PROJECT)" \
				-scheme "$(SCHEME)" \
				-configuration Release \
				-destination "generic/platform=macOS" \
				-derivedDataPath "$(RELEASE_DERIVED_DATA)" \
				-archivePath "$(RELEASE_ARCHIVE)" \
				ARCHS="$(RELEASE_ARCHS)" \
				ONLY_ACTIVE_ARCH=NO \
				CODE_SIGNING_ALLOWED=NO \
				archive; \
		fi; \
		test -x "$(RELEASE_EXECUTABLE)" || { echo "Release archive does not contain an executable application." >&2; exit 1; }; \
		if [ "$(RELEASE_CODE_SIGNING_ALLOWED)" = "YES" ]; then \
			run_logged "Verify application signature" codesign --verify --deep --strict --verbose=2 "$(RELEASE_APP)"; \
			authority="$$(codesign -d --verbose=2 "$(RELEASE_APP)" 2>&1 | sed -n 's/^Authority=//p' | head -n 1)"; \
			test -n "$$authority" || { echo "Unable to determine the application signing authority." >&2; exit 1; }; \
			signing_identity="$$authority"; \
			echo "Signing authority: $$authority"; \
			case "$$authority" in \
				Developer\ ID\ Application:*) ;; \
				*) echo "Warning: public distribution requires Developer ID Application signing and notarization." ;; \
			esac; \
		fi; \
		actual_archs="$$(lipo -archs "$(RELEASE_EXECUTABLE)")"; \
		for arch in $(RELEASE_ARCHS); do \
			case " $$actual_archs " in *" $$arch "*) ;; *) echo "Release executable is missing the $$arch architecture." >&2; exit 1;; esac; \
		done; \
		version="$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$(RELEASE_APP)/Contents/Info.plist")"; \
		build="$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$(RELEASE_APP)/Contents/Info.plist")"; \
		package="$(DIST_DIR)/Screen-Remote-$${version}-$${build}.dmg"; \
		mkdir -p "$(RELEASE_STAGING)/.background"; \
		/usr/bin/ditto "$(RELEASE_APP)" "$(RELEASE_STAGING)/Screen Remote.app"; \
		/usr/bin/ditto "$(DMG_BACKGROUND)" "$(RELEASE_STAGING)/.background/background.tiff"; \
		if [ "$(RELEASE_CODE_SIGNING_ALLOWED)" = "YES" ]; then \
			signed_assets="$(RELEASE_ROOT)/SignedAssets"; \
			signed_tools="$$signed_assets/Tools"; \
			signed_tools_identity="$$signed_assets/Tools.identity"; \
			signed_tools_source_hash="$$signed_assets/Tools.source.sha256"; \
			tools_source_hash="$$(shasum -a 256 "$(DMG_ASSETS)/Tools" | awk '{print $$1}')"; \
			if [ -f "$$signed_tools" ] && [ -f "$$signed_tools_identity" ] && [ -f "$$signed_tools_source_hash" ] && [ "$$(cat "$$signed_tools_identity")" = "$$signing_identity" ] && [ "$$(cat "$$signed_tools_source_hash")" = "$$tools_source_hash" ] && codesign --verify --strict "$$signed_tools" >>"$$release_log" 2>&1; then \
				echo "Using cached signed Tools asset"; \
			else \
				echo "Signing Tools asset for the selected identity"; \
				mkdir -p "$$signed_assets"; \
				/usr/bin/ditto "$(DMG_ASSETS)/Tools" "$$signed_tools"; \
				run_logged "Sign Tools asset" codesign --force --sign "$$signing_identity" --timestamp=none "$$signed_tools"; \
				printf '%s\n' "$$signing_identity" > "$$signed_tools_identity"; \
				printf '%s\n' "$$tools_source_hash" > "$$signed_tools_source_hash"; \
			fi; \
			/usr/bin/ditto "$$signed_tools" "$(RELEASE_STAGING)/Tools"; \
		else \
			/usr/bin/ditto "$(DMG_ASSETS)/Tools" "$(RELEASE_STAGING)/Tools"; \
		fi; \
		/usr/bin/ditto "$(DMG_ASSETS)/README.rtf" "$(RELEASE_STAGING)/README.rtf"; \
		rm -f "$$package"; \
		if [ -n "$(CREATE_DMG)" ]; then \
			run_logged "Create DMG" "$(CREATE_DMG)" \
				--volname "Screen Remote $${version}" \
				--window-size 540 410 \
				--icon-size 80 \
				--background "$(RELEASE_STAGING)/.background/background.tiff" \
				--app-drop-link 407 100 \
				--icon "Screen Remote.app" 135 100 \
				--icon "README.rtf" 135 250 \
				--icon "Tools" 407 250 \
				"$$package" "$(RELEASE_STAGING)"; \
		else \
			echo "Warning: create-dmg was not found; using the basic hdiutil layout."; \
			ln -s /Applications "$(RELEASE_STAGING)/Applications"; \
			run_logged "Create basic DMG" hdiutil create -quiet -volname "Screen Remote $${version}" -srcfolder "$(RELEASE_STAGING)" -ov -format UDZO "$$package"; \
		fi; \
		if [ -n "$(NOTARY_PROFILE)" ]; then \
			run_logged "Submit for notarization" xcrun notarytool submit "$$package" --keychain-profile "$(NOTARY_PROFILE)" --wait; \
			run_logged "Staple notarization" xcrun stapler staple "$$package"; \
			run_logged "Validate notarization" xcrun stapler validate "$$package"; \
		fi; \
		checksum="$$(shasum -a 256 "$$package" | awk '{print $$1}')"; \
		echo "Release package: $$package"; \
		echo "Architectures: $$actual_archs"; \
		echo "SHA-256: $$checksum"

run: build
	@$(MAKE) --no-print-directory stop
	@$(MAKE) --no-print-directory launch

launch:
	@if [ ! -x "$(EXECUTABLE)" ]; then \
		echo "No executable application was found. Run make build first."; \
		exit 1; \
	fi
	@mkdir -p "$(BUILD_ROOT)"
	@nohup "$(EXECUTABLE)" > "$(LOG_FILE)" 2>&1 & echo $$! > "$(PID_FILE)"
	@sleep 0.5
	@if ! kill -0 "$$(cat "$(PID_FILE)")" 2>/dev/null; then \
		echo "The application failed to launch. Recent log output:"; \
		tail -n 40 "$(LOG_FILE)"; \
		exit 1; \
	fi
	@echo "Screen Remote launched outside Xcode (PID $$(cat "$(PID_FILE)"))"

stop:
	@if [ -f "$(PID_FILE)" ]; then \
		pid="$$(cat "$(PID_FILE)")"; \
		if kill -0 "$$pid" 2>/dev/null; then \
			kill "$$pid" 2>/dev/null || true; \
			for _ in 1 2 3 4 5; do \
				kill -0 "$$pid" 2>/dev/null || break; \
				sleep 0.2; \
			done; \
		fi; \
		rm -f "$(PID_FILE)"; \
	fi

reload: build
	@$(MAKE) --no-print-directory stop
	@$(MAKE) --no-print-directory launch

dev: run
	@echo "Watching Swift source files. Saving a file will rebuild and restart the app. Press Ctrl-C to exit."
	@trap '$(MAKE) --no-print-directory stop' EXIT; \
	trap 'exit 130' INT TERM; \
	while true; do \
		if find $(WATCH_PATHS) -type f \( -name '*.swift' -o -name 'project.pbxproj' \) \
			-newer "$(STAMP_FILE)" -print -quit | grep -q .; then \
			echo "Changes detected. Reloading..."; \
			$(MAKE) --no-print-directory reload || true; \
		fi; \
		sleep 1; \
	done

logs:
	@touch "$(LOG_FILE)"
	tail -f "$(LOG_FILE)"

clean: stop
	rm -rf "$(DERIVED_DATA)" "$(RELEASE_ROOT)" "$(STAMP_FILE)" "$(LOG_FILE)"
