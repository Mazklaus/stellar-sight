class_name AmphictyonySystem
extends RefCounted
## L'Amphictyonie (voir Amphictyony), exécutée chaque jour après la diplomatie : ouverture et clôture
## des séances ; chaque mois : offre de fondation, voix, peines échues, foi galactique.


static func process(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if not state.amph_on:
		return added
	if state.tick % int(GameData.rules()["month_days"]) == 0:
		Amphictyony.monthly(state, added)
	Amphictyony.daily(state, added)
	return added
