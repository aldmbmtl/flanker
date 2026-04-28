## GUT post-run hook: finalizes coverage and prints the report.
##
## Prints a per-file summary showing coverage% for every instrumented script,
## with full line-by-line detail for any file below 100%.
##
## Report is also written to /tmp/flankers_coverage.txt.

extends GutHookScript

const Coverage = preload("res://addons/coverage/coverage.gd")

func run() -> void:
	if !Coverage.instance:
		gut.logger.log("Coverage: no instance found — was pre_run_hook.gd configured?")
		return
	gut.logger.log("Coverage: finalizing...")
	Coverage.finalize(Coverage.Verbosity.PARTIAL_FILES)
