class_name TranscendenceBridges
extends RefCounted
## La Transcendance et les autres piliers (lot 3 ; voir Transcendence, data/transcendence.json).
##
## Passages ratés : l'Avorté (prop. 27), crise appelée près de l'empire dont le Passage s'est brisé
## tard ou s'est mené dans le désordre ; le Raccourci (prop. 28), offert par une voix du Songe ou de
## l'ancienne, piège une fois sur deux (Coquilles, ou le Solde du Songe).
## Talents des peuples (prop. 32) : Relais du réseau de Teyl, Faim de l'Au-delà des Kh'thari (dégâts
## contre un empire en Passage). Credo Transcendance (prop. 33) : croissance -10 %.
## Ponts (prop. 35-38) : fêlures doublées pendant le Passage du Songe, merveilles qui comptent comme
## Relais, héros morts pendant le Passage. Le Fléau ne transcende pas (prop. 29, Transcendence.path_why).


# --- Relais en plus (prop. 32, 38) -------------------------------------------------------------

static func relay_wonders() -> Array:
	return Transcendence.cfg("relay_wonders").get("list", [])


static func extra_relays(state: GameState, eid: int) -> int:
	var n := 0
	var rw := relay_wonders()
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != eid:
			continue
		for b in c.buildings:
			if rw.has(String(b)):
				n += 1
	if Transcendence.t_int(state, eid, "network_relays") > 0 and Transcendence.path_of(state, eid) == "televersement":
		n += FactionTraits.network_nodes(state, eid)
	return n


# --- L'Avorté (prop. 27) -----------------------------------------------------------------------

## Chance d'avortement (%) d'un Passage brisé : pct au-delà de break_from, doublée par des carnets volés.
static func abort_chance(state: GameState, eid: int, pct: int, low_stab: bool) -> int:
	var a := Transcendence.cfg("avorte")
	var c := 0
	@warning_ignore("integer_division")
	if pct * 10 >= int(a.get("break_from", 750)):
		c = int(a.get("pct", 50))
	elif low_stab:
		c = int(a.get("low_stab_pct", 25))
	if c > 0 and Transcendence.stat(state, eid, "stolen_notes") > 0:
		c *= 2
	return mini(100, c)


static func on_break(state: GameState, eid: int, pct: int, added: Array[Dictionary]) -> void:
	var c := abort_chance(state, eid, pct, false)
	if c > 0 and Transcendence._h(state, ["avorte", eid, state.tick]) % 100 < c:
		abort(state, eid, added)


## L'Avorté : la moitié de l'espèce fondatrice est perdue, la voie aussi, et la crise s'ouvre.
static func abort(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == eid and c.is_colony() and c.population > 1:
			@warning_ignore("integer_division")
			c.population = maxi(1, c.population - c.population / 2)
			Peoples.normalize(c)
	for k in ["path", "gauge", "oeuvre", "passage", "ark"]:
		Transcendence.sub(state, k).erase(str(eid))
	Transcendence.sub(state, "renounced")[str(eid)] = state.tick
	Transcendence._stat(state, eid, "aborted", 1)
	state.relic_rev += 1
	added.append(state.add_chronicle("Le Passage de %s avorte. La moitié du peuple est passée, l'autre non ; ce qui est resté coincé entre les deux revient, et il a faim." % e.display_name(),
			Espionage.public_to(state, [eid])))
	var k := String(Transcendence.cfg("avorte").get("crisis", "avorte"))
	if Crisis.enabled(state) and Crisis.cur(state).is_empty() and not (state.crisis.get("done", []) as Array).has(k) and not Crisis.kind_def(k).is_empty():
		state.crisis["summoner"] = eid
		Crisis.begin(state, k, added)


# --- Le Raccourci (prop. 28) -------------------------------------------------------------------

static func _offer_shortcut(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var r := Transcendence.cfg("raccourci")
	if Transcendence.sub(state, "offered").has(str(eid)) or Transcendence.gauge(state, eid) < int(r.get("from", 500)):
		return
	if Transcendence.in_passage(state, eid) or Transcendence.stage(state, eid) > 0 or Transcendence.stage_running(state, eid):
		return
	@warning_ignore("integer_division")
	if posmod(state.tick / Transcendence.month_days(), 12) != posmod(eid + 9, 12):
		return
	if Transcendence._h(state, ["offre", eid, state.tick]) % 100 >= int(r.get("offer_pct", 30)):
		return
	Transcendence.sub(state, "offered")[str(eid)] = state.tick
	if not Events.card("orree_raccourci").is_empty():
		Events.push(state, eid, "orree_raccourci", {}, added)


static func check_shortcut(state: GameState, eid: int) -> String:
	if Transcendence.path_of(state, eid) == "" or Transcendence.in_passage(state, eid):
		return "la porte de côté ne s'ouvre plus"
	return ""


static func take_shortcut(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	if check_shortcut(state, eid) != "":
		return
	Transcendence.sub(state, "shortcut")[str(eid)] = state.tick
	Transcendence.sub(state, "gauge")[str(eid)] = Transcendence.gauge_max()
	Transcendence.begin_passage(state, eid, added, Transcendence.c_int("raccourci", "days", 720))


static func event_act(state: GameState, eid: int, act: String, added: Array[Dictionary]) -> void:
	if act == "shortcut" and Transcendence.applies(state, eid):
		take_shortcut(state, eid, added)


## Fin d'un Passage pris par le Raccourci : piège une fois sur deux. true si piégé (rien ne part).
static func trap(state: GameState, eid: int, added: Array[Dictionary]) -> bool:
	if not Transcendence.sub(state, "shortcut").has(str(eid)):
		return false
	Transcendence.sub(state, "shortcut").erase(str(eid))
	if Transcendence._h(state, ["piege", eid]) % 100 >= Transcendence.c_int("raccourci", "trap_pct", 50):
		return false
	var e := state.get_empire(eid)
	for k in ["path", "gauge", "oeuvre", "passage", "ark"]:
		Transcendence.sub(state, k).erase(str(eid))
	for j in Transcendence.joined_to(state, eid):
		Transcendence.sub(state, "joined").erase(str(j))
	Transcendence.sub(state, "renounced")[str(eid)] = state.tick
	Transcendence._stat(state, eid, "trapped", 1)
	state.relic_rev += 1
	var k := "solde"
	if Psionics.full(state) and Crisis.enabled(state) and Crisis.cur(state).is_empty() and not (state.crisis.get("done", []) as Array).has(k) and not Crisis.kind_def(k).is_empty():
		added.append(state.add_chronicle("Le Raccourci de %s était une dette. La voix douce présente la note : le peuple ne part pas, il nourrit le Songe." % e.display_name(),
				Espionage.public_to(state, [eid])))
		state.crisis["summoner"] = eid
		Crisis.begin(state, k, added)
		return true
	Transcendence.sub(state, "curse")[str(eid)] = {"until": state.tick + Transcendence.c_int("renounce", "days", 1800), "v": Transcendence.c_int("renounce", "stab", -20), "label": "Coquilles", "fx": "coquilles"}
	added.append(state.add_chronicle("Le Raccourci de %s était un piège. Au bout du chemin, le peuple se réveille dans des corps de métal, sans rien dedans : des Coquilles qui travaillent, obéissent, et ne rêvent plus." % e.display_name(),
			Espionage.public_to(state, [eid])))
	return true


# --- Effets, combat, psionique ------------------------------------------------------------------

static func effects(state: GameState, eid: int) -> Dictionary:
	var out := {}
	if Transcendence.credo(state, eid) == String(Transcendence.cfg("credo").get("id", "transcendance")):
		out["growth_pct"] = Transcendence.c_int("credo", "growth_pct", -10)
	var cu: Dictionary = Transcendence.sub(state, "curse").get(str(eid), {})
	if String(cu.get("fx", "")) == "coquilles" and int(cu.get("until", 0)) > state.tick:
		out["production_pct"] = {"knowledge": -50}
		out["growth_pct"] = int(out.get("growth_pct", 0)) - 100
	return out


## Faim de l'Au-delà (Kh'thari) : dégâts en plus contre les flottes d'un empire en Passage.
static func damage_pct(state: GameState, f: Fleet, sid: int) -> int:
	var p := Transcendence.t_int(state, f.owner, "anti_damage_pct")
	if p <= 0:
		return 0
	for g in Fleets.fleets_at(state, sid, -1):
		if g.owner != f.owner and not g.ships.is_empty() and Transcendence.leaving(state, g.owner):
			return p
	return 0


## Fêlures doublées pendant le Passage du Songe (prop. 35) : points de % en plus.
static func felure_pct(state: GameState, eid: int) -> int:
	if Transcendence.enabled(state) and Transcendence.path_of(state, eid) == "songe" and Transcendence.in_passage(state, eid):
		return 100
	return 0


## Un héros qui meurt pendant le Passage part avec les siens (prop. 38) : la phrase du chroniqueur.
static func hero_epitaph(state: GameState, owner: int) -> String:
	if state.transcendence.is_empty() or not Transcendence.leaving(state, owner):
		return ""
	return " Pendant le Passage, on dit qu'il n'est pas mort : il est parti un peu en avance."


# --- Commandes, bilan --------------------------------------------------------------------------

static func check(_state: GameState, _eid: int, _act: String, _d: Dictionary) -> String:
	return "action inconnue"


static func apply(_state: GameState, _eid: int, _act: String, _d: Dictionary, _added: Array[Dictionary]) -> void:
	pass


static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	for e in state.empires:
		if not Transcendence.applies(state, e.id) or Transcendence.path_of(state, e.id) == "":
			continue
		_offer_shortcut(state, e.id, added)
		# Passage mené sous 30 de stabilité moyenne : un jet par an.
		if Transcendence.in_passage(state, e.id) and Stability.applies(state, e.id) \
				and Stability.empire_value(state, e.id) < Transcendence.c_int("avorte", "stab", 30):
			@warning_ignore("integer_division")
			if posmod(state.tick / Transcendence.month_days(), 12) == posmod(e.id + 2, 12):
				var c := abort_chance(state, e.id, 0, true)
				if Transcendence._h(state, ["desordre", e.id, state.tick]) % 100 < c:
					abort(state, e.id, added)
