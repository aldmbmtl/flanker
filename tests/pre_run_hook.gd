## GUT pre-run hook: instruments res://scripts/ for line coverage.
##
## Excludes:
##   - res://addons/*   (GUT, coverage addon itself)
##   - res://tests/*    (test files — must NOT be instrumented or Godot crashes)
##   - res://contrib/*
##
## The Coverage singleton is available as Coverage.instance during the run.

extends GutHookScript

const Coverage = preload("res://addons/coverage/coverage.gd")

const EXCLUDE_PATHS := [
	"res://addons/*",
	"res://tests/*",
	"res://contrib/*",
]

func run() -> void:
	Coverage.new(gut.get_tree(), EXCLUDE_PATHS)
	Coverage.instance.instrument_scripts("res://scripts/")
	gut.logger.log("Coverage: instrumented res://scripts/")
