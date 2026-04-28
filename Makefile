GODOT      := godot
PROJECT    := $(shell pwd)
LOG        := /tmp/flankers.log
HOST_LOG   := /tmp/flankers_host.log
CLIENT_LOG := /tmp/flankers_client.log

TEST_LOG      := /tmp/flankers_tests.log
COVERAGE_LOG  := /tmp/flankers_coverage.txt

.PHONY: run stop restart logs host client hlogs clogs clean-symlink clean build test coverage

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

test:
	DISPLAY=:0 $(GODOT) --headless --import --path $(PROJECT) > /dev/null 2>&1
	$(GODOT) --headless -s addons/gut/gut_cmdln.gd --path $(PROJECT) -gconfig=.gutconfig.json 2>&1 | tee $(TEST_LOG)

coverage:
	DISPLAY=:0 $(GODOT) --headless --import --path $(PROJECT) > /dev/null 2>&1
	$(GODOT) --headless -s addons/gut/gut_cmdln.gd --path $(PROJECT) -gconfig=.gutconfig.coverage.json 2>&1 | tee $(TEST_LOG)
	@echo ""
	@echo "Coverage report: $(COVERAGE_LOG)"
	@cat $(COVERAGE_LOG)
