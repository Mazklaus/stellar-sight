class_name PsionicsTests2
extends RefCounted
## Tests des pouvoirs psioniques, lots 2 et 3 (le Songe, la guerre, les ponts). Appelés par psionics_tests.gd.

static var _check: Callable


static func run(check: Callable) -> void:
	_check = check
