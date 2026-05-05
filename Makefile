# macscreen — common project tasks
#
# Run `make` or `make help` to see what's available.
# All paths are computed from xcodebuild's own settings, so they stay correct
# even if Xcode moves DerivedData around.

PROJECT    := macscreen.xcodeproj
SCHEME     := macscreen
BUNDLE_ID  := com.pavelvasek.macscreen
CONFIG     := Debug

# Resolved lazily — `xcodebuild -showBuildSettings` is slow, only run when actually needed.
BUILD_DIR   = $(shell xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR / { print $$3 }')
APP_PATH    = $(BUILD_DIR)/$(SCHEME).app

.DEFAULT_GOAL := help
.PHONY: help project build build-release run rerun open stop clean clean-all test install uninstall reset-permission where tail-log

help:
	@echo "macscreen — available targets:"
	@echo "  make project           Regenerate $(PROJECT) from project.yml (xcodegen)"
	@echo "  make build             Build Debug configuration"
	@echo "  make build-release     Build Release configuration"
	@echo "  make run               Build and launch the app (replaces any running instance)"
	@echo "  make rerun             Stop + reset Accessibility + build + launch (fresh-grant cycle)"
	@echo "  make stop              Quit any running macscreen instance"
	@echo "  make open              Open the project in Xcode"
	@echo "  make clean             Remove build artifacts (DerivedData for this project)"
	@echo "  make clean-all         clean + delete the generated $(PROJECT)"
	@echo "  make test              Run unit tests (no test target defined yet)"
	@echo "  make install           Copy a Release build to /Applications"
	@echo "  make uninstall         Remove macscreen from /Applications"
	@echo "  make reset-permission  Forget the Accessibility grant for this app"
	@echo "  make where             Print resolved paths"
	@echo "  make tail-log          Stream unified log output from the running app"

# Regenerate xcodeproj whenever project.yml or any Swift source changes.
# This catches new files getting added without project.yml needing to be touched.
# Removing a file still requires `make project` (or `make clean-all`) explicitly.
$(PROJECT): project.yml $(wildcard macscreen/*.swift)
	xcodegen generate

project: $(PROJECT)

build: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -destination 'platform=macOS' -quiet build

build-release: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -destination 'platform=macOS' -quiet build

run: stop build
	open "$(APP_PATH)"
	@echo "Launched $(APP_PATH)"
	@echo "Look for the menu-bar icon near the clock."

# Use after an ad-hoc rebuild has invalidated the Accessibility grant.
# Order matters: stop before reset (so the running process can't race the TCC daemon).
rerun: stop reset-permission build
	open "$(APP_PATH)"
	@echo "Launched $(APP_PATH) — re-grant Accessibility when prompted."

stop:
	-@osascript -e 'tell application id "$(BUNDLE_ID)" to quit' 2>/dev/null || true
	-@pkill -x $(SCHEME) 2>/dev/null || true

open:
	@open $(PROJECT)

clean:
	-xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -quiet clean 2>/dev/null || true
	-rm -rf "$$HOME/Library/Developer/Xcode/DerivedData"/$(SCHEME)-*
	-rm -rf build

clean-all: clean
	-rm -rf $(PROJECT)

test:
	@echo "No tests yet. To add tests:"
	@echo "  1. Add a test target to project.yml (type: bundle.unit-test)"
	@echo "  2. Add Swift test files under macscreenTests/"
	@echo "  3. make project"
	@echo "  4. make test will then run: xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS'"

install: build-release
	@rm -rf /Applications/$(SCHEME).app
	@cp -R "$(BUILD_DIR)/$(SCHEME).app" /Applications/
	@echo "Installed to /Applications/$(SCHEME).app"

uninstall: stop
	-rm -rf /Applications/$(SCHEME).app
	@echo "Removed /Applications/$(SCHEME).app"

reset-permission:
	tccutil reset Accessibility $(BUNDLE_ID)
	@echo "Accessibility permission reset for $(BUNDLE_ID)."
	@echo "Next launch will require re-granting it in System Settings → Privacy & Security → Accessibility."

where:
	@echo "Project:    $(abspath $(PROJECT))"
	@echo "Build dir:  $(BUILD_DIR)"
	@echo "App bundle: $(APP_PATH)"

tail-log:
	@echo "Streaming logs from $(SCHEME) (Ctrl-C to stop)..."
	log stream --predicate 'process == "$(SCHEME)"' --info --debug
