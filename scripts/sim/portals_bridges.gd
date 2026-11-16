class_name PortalsBridges
extends RefCounted
## Ponts des portails de saut avec les autres piliers (lots 2 et 3) : commerce et pirates (prop. 15, 31),
## espionnage (prop. 25), événements (prop. 29), haut fait Maître des portes (prop. 38).
## La desserte des ports (prop. 30) et le ravitaillement (prop. 17) passent par Portals.civil_links et
## Portals.corridor ; le pacte des Portes (prop. 28) par Portals.on_guardian_pact.


# --- Commerce et pirates -------------------------------------------------------------------------

## Bonus (points de %) d'une route commerciale de l'empire a qui emprunte un corridor de relais.
static func trade_pct(state: GameState, a: int, p: Array) -> int:
	if not Portals.enabled(state) or state.galaxy.relays.is_empty():
		return 0
	for i in range(p.size() - 1):
		if Portals.corridor(state, a, int(p[i]), int(p[i + 1])):
			return int(Portals.cfg("relays").get("trade_pct", 10))
	return 0


## Un portail sans station de défense attire les pirates (prop. 31 ; défenses spatiales en jeu).
static func lures_pirates(state: GameState, sid: int) -> bool:
	if not Portals.enabled(state) or not Defenses.enabled(state):
		return false
	if not state.galaxy.portal_gates.has(sid):
		return false
	return Defenses.tier(state, sid) <= 0


# --- Espionnage (prop. 25) -----------------------------------------------------------------------

## Portail de la cible à désaccorder : celui de sa capitale, sinon le premier de ses portails.
static func spy_target(state: GameState, b: int) -> int:
	var cap := FactionTraits.capital_system(state, b)
	if cap >= 0 and state.galaxy.portal_gates.has(cap) and state.system_owner(cap) == b and not Portals.cut(state, cap):
		return cap
	var keys := state.galaxy.portal_gates.keys()
	keys.sort()
	for sid in keys:
		if state.system_owner(int(sid)) == b and not Portals.cut(state, int(sid)):
			return int(sid)
	return -1


static func spy_check(state: GameState, _a: int, b: int, _op_id: String) -> String:
	if not Portals.enabled(state):
		return "les portails de saut ne sont pas en jeu dans cette partie"
	if spy_target(state, b) < 0:
		return "il n'a aucun portail en service"
	return ""


static func spy_apply(state: GameState, _a: int, b: int, _o: Dictionary) -> String:
	var sid := spy_target(state, b)
	if sid < 0:
		return "le portail visé était déjà éteint. Les saboteurs sont rentrés bredouilles et vexés."
	Portals._sub(state, "cut")[str(sid)] = state.tick + int(Portals.cfg("gates").get("cut_days", 60))
	Portals.refresh(state)
	for e in state.empires:
		e.path_cache.clear()
	return "le portail de %s est désaccordé : deux mois de réglages avant qu'il ne relaie à nouveau." % state.galaxy.systems[sid].system_name


# --- Haut fait (prop. 38) ------------------------------------------------------------------------

## Portails de l'empire reliés à au moins un autre portail.
static func linked_gates(state: GameState, eid: int) -> int:
	if not Portals.enabled(state):
		return 0
	var n := 0
	for sid in state.galaxy.portal_gates:
		if state.system_owner(int(sid)) == eid and not (state.galaxy.portal_links.get(sid, {}) as Dictionary).is_empty():
			n += 1
	return n


# --- Événements (prop. 29) -----------------------------------------------------------------------

## Systèmes d'infrastructure de saut de l'empire (trous de ver connus, portails, relais), triés.
static func _sites(state: GameState, eid: int) -> Dictionary:
	var out := {"wh": [], "gate": [], "relay": []}
	var g := state.galaxy
	var keys := g.wormholes.keys()
	keys.sort()
	for sid in keys:
		var i := Portals.pair_index(state, int(sid))
		if state.system_owner(int(sid)) == eid or (i >= 0 and Portals.known_pair(state, eid, i) and state.empires[eid].explored.has(int(sid))):
			(out["wh"] as Array).append(int(sid))
	keys = g.portal_gates.keys()
	keys.sort()
	for sid in keys:
		if state.system_owner(int(sid)) == eid:
			(out["gate"] as Array).append(int(sid))
	keys = g.relays.keys()
	keys.sort()
	for sid in keys:
		if state.system_owner(int(sid)) == eid:
			(out["relay"] as Array).append(int(sid))
	return out


static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	if not Portals.full(state):
		return
	var per := int(Portals.cfg("events").get("monthly_permille", 25))
	if per <= 0:
		return
	var rng := Portals._rng(state, 71 + state.tick * 13)
	for e in state.empires:
		if e.eliminated or e.is_npc():
			continue
		var roll := rng.randi_range(0, 999)
		if roll >= per:
			continue
		var s := _sites(state, e.id)
		var kinds: Array[String] = []
		if not (s["wh"] as Array).is_empty():
			kinds.append("sortie")
			kinds.append("revelation")
		if not (s["gate"] as Array).is_empty():
			kinds.append("resonance")
			kinds.append("contrebande")
		if kinds.is_empty():
			continue
		var k := kinds[rng.randi_range(0, kinds.size() - 1)]
		_event(state, e, k, s, rng, added)


static func _event(state: GameState, e: Empire, k: String, s: Dictionary, rng: RandomNumberGenerator, added: Array[Dictionary]) -> void:
	var g := state.galaxy
	var me := Espionage.private_to(state, [e.id])
	match k:
		"sortie":
			var sid: int = (s["wh"] as Array)[rng.randi_range(0, (s["wh"] as Array).size() - 1)]
			var nm := Portals.wormhole_name(state, sid)
			if Fauna.active(state):
				var sps := Fauna.species_ids()
				if not sps.is_empty():
					var sp := sps[rng.randi_range(0, sps.size() - 1)]
					Fauna.spawn_herd(state, sp, sid, -1, state.tick + 180)
					added.append(state.add_chronicle("Quelque chose sort du %s, à %s : des %s, égarées et nerveuses, qui n'ont visiblement rien demandé." % [nm, g.systems[sid].system_name, String(Fauna.species(sp).get("label", "créatures"))], me))
					return
			e.resources["knowledge"] = int(e.resources.get("knowledge", 0)) + 40
			added.append(state.add_chronicle("Une épave sans âge dérive hors du %s, à %s. Les savants de %s en tirent 40 Savoir et beaucoup de questions." % [nm, g.systems[sid].system_name, e.short_name()], me))
		"revelation":
			var sid: int = (s["wh"] as Array)[rng.randi_range(0, (s["wh"] as Array).size() - 1)]
			var far := int(g.wormholes.get(sid, -1))
			if far < 0:
				return
			var j := FactionTraits.jumps_from(g, far)
			var n := 0
			for t in j:
				if int(j[t]) <= 2 and not e.explored.has(int(t)):
					e.explored[int(t)] = true
					n += 1
			e.path_cache.clear()
			added.append(state.add_chronicle("Le %s s'illumine un instant : %s y voit toute une région autour de %s (%d systèmes cartographiés)." % [Portals.wormhole_name(state, sid), e.short_name(), g.systems[far].system_name, n], me))
		"resonance":
			var sid: int = (s["gate"] as Array)[rng.randi_range(0, (s["gate"] as Array).size() - 1)]
			Portals._sub(state, "cut")[str(sid)] = state.tick + int(Portals.cfg("events").get("resonance_days", 30))
			for o in state.empires:
				o.path_cache.clear()
			added.append(state.add_chronicle("Résonance au portail de %s : l'anneau chante une note que personne n'aime. Il est coupé pour un mois." % g.systems[sid].system_name, me))
		"contrebande":
			var sid: int = (s["gate"] as Array)[rng.randi_range(0, (s["gate"] as Array).size() - 1)]
			e.resources["energy"] = int(e.resources.get("energy", 0)) + 40
			var risk: Dictionary = state.trade.get("risk", {})
			if state.pirate_density != "aucun":
				risk[sid] = int(risk.get(sid, 0)) + 20
				state.trade["risk"] = risk
			added.append(state.add_chronicle("Des contrebandiers passent par le portail de %s. Les douaniers de %s touchent 40 énergie pour regarder ailleurs ; les pirates, eux, regardent par ici." % [g.systems[sid].system_name, e.short_name()], me))
