class_name VictorySystem
extends RefCounted
## Les victoires (voir Victory) : chaque mois, l'avancée de chaque empire est recalculée, les comptes
## à rebours avancent (ou repartent de zéro), les alertes partent à 50 et 75 %, et le premier empire
## qui remplit une condition est proclamé vainqueur. La date limite se vérifie chaque jour.
## Une fois un vainqueur proclamé, plus rien ne bouge ici : la partie peut continuer pour le plaisir.


static func process(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if not state.winner.is_empty():
		return added
	var every := maxi(1, int(Victory.data().get("check_days", 30)))
	if state.tick % every == 0:
		_drop_broken_unions(state, added)
		_monthly(state, every, added)
	if state.winner.is_empty():
		var dl := Victory.deadline(state)
		if dl > 0 and state.tick >= dl:
			var rank := Victory.ranking(state)
			if not rank.is_empty():
				_proclaim(state, int(rank[0]["id"]), Victory.SCORE, added)
	return added


static func _monthly(state: GameState, every: int, added: Array[Dictionary]) -> void:
	var warn: Array = Victory.data().get("warn_at", [50, 75])
	for e in state.empires:
		if e.eliminated:
			continue
		for id in Victory.ids_for(state, e.id):
			if id == Victory.SCORE:
				continue
			var rec: Dictionary = e.victory.get(id, {"pct": 0, "held": 0, "warn": 0})
			var p := Victory.progress(state, e.id, id)
			var hold := int(p["hold"])
			if hold > 0:
				if p["cond"]:
					rec["held"] = int(rec.get("held", 0)) + every
				elif not p["keep"]:
					rec["held"] = 0
				e.victory[id] = rec
				p = Victory.progress(state, e.id, id)  # avec le compte à rebours à jour
			rec["pct"] = int(p["pct"])
			# Alertes : chaque seuil franchi une fois (on retombe sous le seuil : il pourra resonner).
			var level := 0
			for i in warn.size():
				if int(rec["pct"]) >= int(warn[i]):
					level = i + 1
			if level > int(rec.get("warn", 0)):
				added.append(state.add_chronicle(_warning(e, id, int(warn[level - 1]))))
			rec["warn"] = level
			e.victory[id] = rec
			if bool(p["won"]) or (hold > 0 and int(rec.get("held", 0)) >= hold and Victory.has_tech(state, e.id, id)):
				_proclaim(state, e.id, id, added)
				return


static func _warning(e: Empire, id: String, at: int) -> String:
	if at >= Victory.met_at():
		return "Alerte galactique : %s a rempli la condition de %s. Le compte à rebours a commencé ; il est encore temps de l'arrêter." % [e.display_name(), Victory.label(id)]
	return "Les chroniqueurs s'inquiètent : %s est à mi-chemin de %s." % [e.display_name(), Victory.label(id)]


## Une union de lignées ne survit pas à la fin de l'alliance.
static func _drop_broken_unions(state: GameState, added: Array[Dictionary]) -> void:
	var keys := state.relations.keys()
	keys.sort()
	for k in keys:
		var r: Dictionary = state.relations[k]
		if int(r.get("union", 0)) <= 0:
			continue
		var pair := String(k).split("-")
		var a := int(pair[0])
		var b := int(pair[1])
		if Diplomacy.allied(state, a, b):
			continue
		r.erase("union")
		added.append(state.add_chronicle("L'union des lignées de %s et de %s est rompue avec leur alliance. Les cadeaux de noces sont réclamés." % [
				state.get_empire(a).short_name(), state.get_empire(b).short_name()]))


static func _proclaim(state: GameState, empire_id: int, id: String, added: Array[Dictionary]) -> void:
	var e := state.get_empire(empire_id)
	state.winner = {"empire": empire_id, "victory": id, "tick": state.tick, "allies": []}
	# Conquête et domination se gagnent en alliance (Endless Space 2) : les alliés partagent la victoire.
	if id == "conquete" or id == "domination":
		var b := Victory.bloc(state, empire_id)
		b.erase(empire_id)
		state.winner["allies"] = Array(b)
	if e.victory.has(id):
		e.victory[id]["pct"] = 100
	added.append(state.add_chronicle("VICTOIRE. " + Victory.chronicle_text(id, e, state.winner["allies"], state)))
