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
DMG_ASSETS := $(CURDIR)/dmg-assets
DMG_BACKGROUND := $(DMG_ASSETS)/.background/background.tiff
CREATE_DMG ?= $(shell command -v create-dmg 2>/dev/null)
DIST_DIR ?= $(CURDIR)/dist
RELEASE_ARCHS ?= arm64 x86_64
RELEASE_CODE_SIGNING_ALLOWED ?= YES
RELEASE_SIGNING_IDENTITY ?= Apple Development
NOTARY_PROFILE ?=
PID_FILE := $(BUILD_ROOT)/screen-remote.pid
LOG_FILE := $(BUILD_ROOT)/screen-remote.log
STAMP_FILE := $(BUILD_ROOT)/last-successful-build
WATCH_PATHS := Screen-Remote Screen-Remote.xcodeproj/project.pbxproj

RELEASE_SIGNING_SETTINGS := CODE_SIGNING_ALLOWED="$(RELEASE_CODE_SIGNING_ALLOWED)"
ifneq ($(strip $(RELEASE_SIGNING_IDENTITY)),)
RELEASE_SIGNING_SETTINGS += CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$(RELEASE_SIGNING_IDENTITY)"
endif

.PHONY: help prepare-assets build release run dev reload launch stop logs clean

help:
	@echo "make run      Build and launch the app outside Xcode"
	@echo "make dev      Watch source files, then rebuild and restart on changes"
	@echo "make release  Archive a universal Release build and create a DMG in dist/"
	@echo "make logs     Follow the application log"
	@echo "make stop     Stop the application launched by this Makefile"
	@echo "make clean    Remove local build artifacts"

prepare-assets:
	@"$(CURDIR)/scripts/prepare-scrcpy-server.sh"

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
	@test -f "$(DMG_ASSETS)/Fix Cannot Open" || { echo "Missing English repair tool."; exit 1; }
	@test -f "$(DMG_ASSETS)/打不开修复" || { echo "Missing Chinese repair tool."; exit 1; }
	@test -f "$(DMG_ASSETS)/Installation Instructions.rtf" || { echo "Missing English installation instructions."; exit 1; }
	@test -f "$(DMG_ASSETS)/安装说明.rtf" || { echo "Missing Chinese installation instructions."; exit 1; }
	rm -rf "$(RELEASE_DERIVED_DATA)" "$(RELEASE_ARCHIVE)" "$(RELEASE_STAGING)"
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration Release \
		-destination "generic/platform=macOS" \
		-derivedDataPath "$(RELEASE_DERIVED_DATA)" \
		-archivePath "$(RELEASE_ARCHIVE)" \
		ARCHS="$(RELEASE_ARCHS)" \
		ONLY_ACTIVE_ARCH=NO \
		$(RELEASE_SIGNING_SETTINGS) \
		archive
	@test -x "$(RELEASE_EXECUTABLE)" || { echo "Release archive does not contain an executable application."; exit 1; }
	@if [ "$(RELEASE_CODE_SIGNING_ALLOWED)" = "YES" ]; then \
		codesign --verify --deep --strict --verbose=2 "$(RELEASE_APP)"; \
		authority="$$(codesign -d --verbose=2 "$(RELEASE_APP)" 2>&1 | sed -n 's/^Authority=//p' | head -n 1)"; \
		echo "Signing authority: $$authority"; \
		case "$$authority" in \
			Developer\ ID\ Application:*) ;; \
			*) echo "Warning: public distribution requires Developer ID Application signing and notarization." ;; \
		esac; \
	else \
		echo "Warning: creating an unsigned release package."; \
	fi
	@set -eu; \
		actual_archs="$$(lipo -archs "$(RELEASE_EXECUTABLE)")"; \
		for arch in $(RELEASE_ARCHS); do \
			case " $$actual_archs " in *" $$arch "*) ;; *) echo "Release executable is missing the $$arch architecture."; exit 1;; esac; \
		done; \
		version="$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$(RELEASE_APP)/Contents/Info.plist")"; \
		build="$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$(RELEASE_APP)/Contents/Info.plist")"; \
		package="$(DIST_DIR)/Screen-Remote-$${version}-$${build}-macOS.dmg"; \
		mkdir -p "$(RELEASE_STAGING)/.background"; \
		/usr/bin/ditto "$(RELEASE_APP)" "$(RELEASE_STAGING)/Screen Remote.app"; \
		/usr/bin/ditto "$(DMG_BACKGROUND)" "$(RELEASE_STAGING)/.background/background.tiff"; \
		/usr/bin/ditto "$(DMG_ASSETS)/Fix Cannot Open" "$(RELEASE_STAGING)/Fix Cannot Open"; \
		/usr/bin/ditto "$(DMG_ASSETS)/打不开修复" "$(RELEASE_STAGING)/打不开修复"; \
		/usr/bin/ditto "$(DMG_ASSETS)/Installation Instructions.rtf" "$(RELEASE_STAGING)/Installation Instructions.rtf"; \
		/usr/bin/ditto "$(DMG_ASSETS)/安装说明.rtf" "$(RELEASE_STAGING)/安装说明.rtf"; \
		if [ "$(RELEASE_CODE_SIGNING_ALLOWED)" = "YES" ]; then \
			asset_signing_identity="$$(codesign -d --verbose=2 "$(RELEASE_APP)" 2>&1 | sed -n 's/^Authority=//p' | head -n 1)"; \
			test -n "$$asset_signing_identity" || { echo "Unable to determine the release asset signing identity."; exit 1; }; \
			codesign --force --sign "$$asset_signing_identity" "$(RELEASE_STAGING)/Fix Cannot Open"; \
			codesign --force --sign "$$asset_signing_identity" "$(RELEASE_STAGING)/打不开修复"; \
		fi; \
		rm -f "$$package"; \
		if [ -n "$(CREATE_DMG)" ]; then \
			"$(CREATE_DMG)" \
				--volname "Screen Remote $${version}" \
				--window-size 540 410 \
				--icon-size 52 \
				--background "$(RELEASE_STAGING)/.background/background.tiff" \
				--app-drop-link 407 100 \
				--icon "Screen Remote.app" 135 100 \
				--icon "打不开修复" 70 250 \
				--icon "安装说明.rtf" 200 250 \
				--icon "Fix Cannot Open" 340 250 \
				--icon "Installation Instructions.rtf" 470 250 \
				"$$package" "$(RELEASE_STAGING)"; \
		else \
			echo "Warning: create-dmg was not found; using the basic hdiutil layout."; \
			ln -s /Applications "$(RELEASE_STAGING)/Applications"; \
			hdiutil create -quiet -volname "Screen Remote $${version}" -srcfolder "$(RELEASE_STAGING)" -ov -format UDZO "$$package"; \
		fi; \
		if [ -n "$(NOTARY_PROFILE)" ]; then \
			xcrun notarytool submit "$$package" --keychain-profile "$(NOTARY_PROFILE)" --wait; \
			xcrun stapler staple "$$package"; \
			xcrun stapler validate "$$package"; \
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
