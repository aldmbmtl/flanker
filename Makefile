GODOT      := godot
PROJECT    := $(shell pwd)
LOG        := /tmp/flankers.log
HOST_LOG   := /tmp/flankers_host.log
CLIENT_LOG := /tmp/flankers_client.log

.PHONY: run stop restart logs host client hlogs clogs clean-symlink

.DEFAULT_GOAL := restart

run:
	DISPLAY=:0 $(GODOT) --headless --import --path $(PROJECT) > /dev/null 2>&1
	DISPLAY=:0 $(GODOT) --path $(PROJECT) > $(LOG) 2>&1 &
	sleep 8 && cat $(LOG)

host:
	DISPLAY=:0 $(GODOT) --headless --import --path $(PROJECT) > /dev/null 2>&1
	DISPLAY=:0 $(GODOT) --path $(PROJECT) > $(HOST_LOG) 2>&1 &
	sleep 8 && cat $(HOST_LOG)

client:
	DISPLAY=:0 $(GODOT) --path $(PROJECT) > $(CLIENT_LOG) 2>&1 &
	sleep 8 && cat $(CLIENT_LOG)

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
