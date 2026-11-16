class_name PortsBridges
extends RefCounted
## Ponts des spatioports avec les autres piliers (lot 3 de l'étude « Spatioports ») : contrebande aux
## docks (administration), événements de port, opération d'espionnage « Désorganiser les docks ».
## Les autres ponts sont lus directement dans Ports (privé, commerce, fiscalité, frontières, terrain,
## talents). Tout est déterministe : tirages par hachage de la graine, du jour et du port.


static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "ports"] + parts))


## Mois (mode complet) : contrebande puis événements, avant le recalcul du réseau.
static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	var nodes: Dictionary = state.ports["nodes"]
	var keys := nodes.keys()
	keys.sort()
	for key in keys:
		var n: Dictionary = nodes[key]
		var eid := int(n["o"])
		var sid := Ports._sid(key)
		var e := state.get_empire(eid)
		if e == null or e.eliminated or int(n["l"]) < 1 or int(n.get("lk", 0)) != 1:
			continue
		# Contrebande aux docks (prop. 31) : la corruption ronge la réserve.
		if not state.admin.is_empty():
			var cc: Dictionary = Ports.cfg("corruption")
			if Admin.corruption(state, sid) >= int(cc.get("at", 40)):
				n["res"] = maxi(0, int(n["res"]) - int(cc.get("days", 10)))
		_event(state, e, sid, n, added)


static func _event(state: GameState, e: Empire, sid: int, n: Dictionary, added: Array[Dictionary]) -> void:
	var ev: Dictionary = Ports.cfg("events")
	var list: Array = ev.get("list", [])
	if list.is_empty():
		return
	if _h(state, [state.tick, sid, e.id]) % 1000 >= int(ev.get("chance_permil", 0)):
		return
	var d: Dictionary = list[_h(state, [state.tick, sid, e.id, "k"]) % list.size()]
	var place := state.galaxy.systems[sid].system_name
	match String(d["id"]):
		"greve":
			state.ports["strike"][str(sid)] = state.tick + int(d.get("days", 30))
		"incendie":
			n["res"] = 0
		"afflux":
			e.resources["energy"] = int(e.resources.get("energy", 0)) + int(d.get("energy_per_level", 20)) * int(n["l"])
		"sature":
			state.ports["sat"][str(e.id)] = state.tick + int(d.get("days", 60))
	added.append(state.add_chronicle(String(d["text"]) % [e.short_name(), place], Espionage.private_to(state, [e.id], sid)))


# --- Espionnage (prop. 29) -----------------------------------------------------------------------

## Port visé : le plus haut niveau relié de la cible, hors capitale si possible.
static func spy_target(state: GameState, b: int) -> int:
	var best := -1
	var best_l := 0
	var cap := FactionTraits.capital_system(state, b)
	for sid in Ports.nodes_of(state, b):
		var n := Ports.node(state, b, sid)
		var lvl := int(n["l"]) * 2 - (1 if sid == cap else 0)
		if int(n["l"]) >= 1 and int(n.get("lk", 0)) == 1 and lvl > best_l:
			best_l = lvl
			best = sid
	return best


static func spy_check(state: GameState, _a: int, b: int, _op_id: String) -> String:
	if not Ports.full(state):
		return "les spatioports complets ne sont pas en jeu"
	if spy_target(state, b) < 0:
		return "il n'a aucun port relié"
	return ""


static func spy_apply(state: GameState, _a: int, b: int, _o: Dictionary) -> String:
	var sid := spy_target(state, b)
	if sid < 0:
		return "ses ports ont fermé entre-temps : rien à désorganiser."
	state.ports["dis"][str(sid)] = state.tick + Ports.c_int("espionage", "days")
	Ports.refresh(state)
	return "les docks de %s sont sens dessus dessous : manifestes échangés, grues en grève, cargos perdus dans les files." % state.galaxy.systems[sid].system_name
