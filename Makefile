PROJECT := ScreenRemote.xcodeproj
SCHEME := ScreenRemote
CONFIGURATION ?= Debug
BUILD_ROOT := $(CURDIR)/.build
DERIVED_DATA := $(BUILD_ROOT)/DerivedData
APP := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/Screen Remote.app
EXECUTABLE := $(APP)/Contents/MacOS/Screen Remote
PID_FILE := $(BUILD_ROOT)/screen-remote.pid
LOG_FILE := $(BUILD_ROOT)/screen-remote.log
STAMP_FILE := $(BUILD_ROOT)/last-successful-build
WATCH_PATHS := ScreenRemote ScreenRemote.xcodeproj/project.pbxproj

.PHONY: help build run dev reload launch stop logs clean

help:
	@echo "make run    Build and launch the app outside Xcode"
	@echo "make dev    Watch source files, then rebuild and restart on changes"
	@echo "make logs   Follow the application log"
	@echo "make stop   Stop the application launched by this Makefile"
	@echo "make clean  Remove local build artifacts"

build:
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
	rm -rf "$(DERIVED_DATA)" "$(STAMP_FILE)" "$(LOG_FILE)"
