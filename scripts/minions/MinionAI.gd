## MinionAI — standard rifle minion. Thin subclass of MinionBase.
## All shared logic (movement, targeting, combat, puppet sync) lives in MinionBase.
## This class exists so callers can reference MinionAI.set_model_characters() by name.

class_name MinionAI
extends MinionBase
