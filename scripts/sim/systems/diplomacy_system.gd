class_name DiplomacySystem
extends RefCounted
## Diplomatie, exécutée à chaque tick après les combats :
## - chaque jour : les propositions sans réponse expirent ;
## - chaque mois : la confiance monte entre empires liés par un traité et retombe sinon ; les alliés
##   partagent leurs cartes ; les souvenirs effacés sont oubliés ; loyauté de l'héritier des dynasties
##   féodales (et trahison) ; ferveur perdue par les théocraties en paix avec des hérétiques ;
##   réseaux d'espionnage, sondes et dividendes du credo Profit (Espionage.monthly) ;
## - chaque jour aussi : les opérations d'espionnage qui arrivent à leur terme (Espionage.daily).
## Tout dans l'ordre des identifiants : la même partie sur toutes les machines.


static func process(state: GameState) -> Array[Dictionary]:
	var start := state.chronicle.size()
	var last: Variant = state.chronicle.back() if start > 0 else null
	_expire(state)
	Espionage.daily(state)
	if state.tick % int(GameData.rules()["month_days"]) == 0:
		_monthly(state)
	# Nouvelles entrées de chronique (la chronique est bornée : on remonte jusqu'à la dernière connue).
	var fresh: Array[Dictionary] = []
	for i in range(state.chronicle.size() - 1, -1, -1):
		if last != null and is_same(state.chronicle[i], last):
			break
		fresh.push_front(state.chronicle[i])
	return fresh


static func _expire(state: GameState) -> void:
	if state.proposals.is_empty():
		return
	var limit := Diplomacy.days("proposal_days", 30)
	var kept: Array[Dictionary] = []
	for p in state.proposals:
		var from := state.get_empire(int(p["from"]))
		var to := state.get_empire(int(p["to"]))
		if state.tick - int(p["tick"]) >= limit or from.eliminated or to.eliminated:
			continue
		kept.append(p)
	state.proposals = kept


static func _monthly(state: GameState) -> void:
	var cfg: Dictionary = Diplomacy.data()["opinion"]
	var keys := state.relations.keys()
	keys.sort()
	for k in keys:
		var r: Dictionary = state.relations[k]
		if String(r["pact"]) != Diplomacy.COLD:
			r["trust"] = mini(int(cfg["trust_max"]), int(r["trust"]) + int(cfg["trust_per_month"]))
		else:
			r["trust"] = maxi(0, int(r["trust"]) - int(cfg["trust_decay_per_month"]))
		if String(r["pact"]) == Diplomacy.ALLIANCE:
			var ids := String(k).split("-")
			var a := int(ids[0])
			var b := int(ids[1])
			if not state.get_empire(a).eliminated and not state.get_empire(b).eliminated:
				Diplomacy.share_maps(state, a, b)
	Diplomacy.prune_memories(state)
	Espionage.monthly(state)
	Vassals.monthly(state)
	Reputation.monthly(state)
	Echoes.monthly(state)
	for e in state.empires:
		if e.eliminated:
			continue
		Diplomacy.heir_month(state, e.id)
		Diplomacy.crusade_month(state, e.id)
		Diplomacy.contract_month(state, e.id)
