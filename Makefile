GODOT      := godot
PROJECT    := $(shell pwd)
LOG        := /tmp/flankers.log
HOST_LOG   := /tmp/flankers_host.log
CLIENT_LOG := /tmp/flankers_client.log

TEST_LOG      := /tmp/flankers_tests.log
COVERAGE_LOG  := /tmp/flankers_coverage.txt

GUT_VERSION  := v9.6.0
GUT_ZIP_URL  := https://github.com/bitwes/Gut/zipball/$(GUT_VERSION)
GUT_ZIP      := /tmp/gut_$(GUT_VERSION).zip
GUT_DEST     := $(PROJECT)/addons/gut
GUT_SENTINEL := $(GUT_DEST)/gut_cmdln.gd

VERSION ?= $(shell git describe --tags --always 2>/dev/null || date +%Y.%m.%d)

.PHONY: run stop restart logs host client hlogs clogs clean-symlink clean build test coverage install-gut release

.DEFAULT_GOAL := restart

build:
	@mkdir -p build
	$(GODOT) --headless --export-release "Linux" build/flanker-linux
	$(GODOT) --headless --export-release "Windows" build/flanker-windows.exe
	zip -j build/flanker-linux.zip build/flanker-linux build/flanker-linux.pck
	zip -j build/flanker-windows.zip build/flanker-windows.exe build/flanker-windows.pck

run:
	DISPLAY=:0 $(GODOT) --headless --import --path $(PROJECT) > /dev/null 2>&1
	DISPLAY=:0 $(GODOT) --path $(PROJECT) > $(LOG)

host:
	DISPLAY=:0 $(GODOT) --headless --import --path $(PROJECT) > /dev/null 2>&1
	DISPLAY=:0 $(GODOT) --path $(PROJECT) > $(HOST_LOG)

client:
	DISPLAY=:0 $(GODOT) --headless --import --path $(PROJECT) > /dev/null 2>&1
	DISPLAY=:0 $(GODOT) --path $(PROJECT) > $(CLIENT_LOG)

stop:
	@pkill -f "godot --path" || true
	sleep 1

restart: stop run

logs:
	cat $(LOG)

hlogs:
	cat $(HOST_LOG)

clogs:
	cat $(CLIENT_LOG)

clean-symlink:
	rm -f $(PROJECT)/godot

clean:
	find $(PROJECT)/scripts -name "*.uid" -delete

install-gut:
	@if [ -f "$(GUT_SENTINEL)" ]; then \
		echo "GUT already installed — skipping."; \
	else \
		echo "Downloading GUT $(GUT_VERSION)..."; \
		curl -sL "$(GUT_ZIP_URL)" -o "$(GUT_ZIP)"; \
		mkdir -p "$(GUT_DEST)"; \
		unzip -q "$(GUT_ZIP)" -d /tmp/gut_extract; \
		cp -r /tmp/gut_extract/*/addons/gut/. "$(GUT_DEST)/"; \
		rm -rf /tmp/gut_extract "$(GUT_ZIP)"; \
		echo "GUT $(GUT_VERSION) installed at $(GUT_DEST)."; \
	fi

test: install-gut
	DISPLAY=:0 $(GODOT) --headless --import --path $(PROJECT) > /dev/null 2>&1
	$(GODOT) --headless -s addons/gut/gut_cmdln.gd --path $(PROJECT) -gconfig=.gutconfig.json 2>&1 | tee $(TEST_LOG)

coverage: install-gut
	DISPLAY=:0 $(GODOT) --headless --import --path $(PROJECT) > /dev/null 2>&1
	$(GODOT) --headless -s addons/gut/gut_cmdln.gd --path $(PROJECT) -gconfig=.gutconfig.coverage.json 2>&1 | tee $(TEST_LOG)
	@echo ""
	@echo "Coverage report: $(COVERAGE_LOG)"
	@cat $(COVERAGE_LOG)

release: build
	@echo "Creating release $(VERSION)..."
	@if gh release view "$(VERSION)" >/dev/null 2>&1; then \
		echo "Error: Release $(VERSION) already exists."; \
		echo "Delete it first: gh release delete $(VERSION)"; \
		exit 1; \
	fi
	gh release create "$(VERSION)" \
		build/flanker-linux.zip \
		build/flanker-windows.zip \
		--title "Flanker $(VERSION)" \
		--notes "Automated release build"
	@echo "Release $(VERSION) created!"
