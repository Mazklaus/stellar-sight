class_name PsionicsTests3
extends RefCounted
## Tests des pouvoirs psioniques, lot 3 (les ponts). Appelés par psionics_tests2.gd.

static var _check: Callable


static func run(check: Callable) -> void:
	_check = check
