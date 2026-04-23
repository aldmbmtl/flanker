GODOT   := godot
PROJECT := /home/aldmbmtl/devel/flanker
LOG     := /tmp/flankers.log

.PHONY: run stop restart logs clean-symlink

.DEFAULT_GOAL := restart

run:
	DISPLAY=:0 $(GODOT) --path $(PROJECT) > $(LOG) 2>&1 &
	sleep 8 && cat $(LOG)

stop:
	@pkill -f "godot --path" || true
	sleep 1

restart: stop run

logs:
	cat $(LOG)

clean-symlink:
	rm -f $(PROJECT)/godot
