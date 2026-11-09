class_name GameCalendar
extends RefCounted
## Calendrier du jeu : un tick de simulation = un jour de jeu.

const START_YEAR := 2400
const DAYS_PER_MONTH := 30
const DAYS_PER_YEAR := 360


static func date_string(tick: int) -> String:
	@warning_ignore("integer_division")
	var year := START_YEAR + tick / DAYS_PER_YEAR
	@warning_ignore("integer_division")
	var month := (tick % DAYS_PER_YEAR) / DAYS_PER_MONTH + 1
	var day_of_month := tick % DAYS_PER_MONTH + 1
	return "%02d/%02d/%d" % [day_of_month, month, year]
