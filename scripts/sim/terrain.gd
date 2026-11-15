class_name Terrain
extends RefCounted
## Terrain galactique et environnements de bataille (étude du 2026-11-15, 32 propositions validées ;
## data/terrain.json).
##
## Option de partie « Terrain » : "aucun" (l'espace d'avant, aucune règle ne dépend du lieu),
## "clairseme", "normal" ou "dense" ; option « Tempêtes » : "actives" ou "aucunes".
## - Chaque système a au plus un terrain de zone (nébuleuse, nébuleuse ionisée, champ d'astéroïdes,
##   nuage de plasma, champ de radiations, cimetière d'épaves), en plus de son étoile (étoile à
##   neutrons, trou noir et géante bleue ont un effet), et peut être pris dans une tempête mobile.
## - Un terrain combine des leviers fermés (voir data/terrain.json, "fx") ; deux effets sur le même
##   levier ne s'additionnent pas, le plus fort compte.
## - Les nébuleuses forment des nappes nommées de 3 à 8 systèmes ; rien de gênant au départ ni à 1 saut.
## - Le terrain est lu par les règles (transit, vision, batailles, réparations, rendements,
##   ravitaillement, commerce, discrétion) et par le décor des batailles (Terrain.at, bloc "visual").
##
## state.terrain = {"d": densité, "s": tempêtes, "sys": {"<système>": terrain de zone},
##   "rg": [[nom, [systèmes]]...] (nébuleuses), "held": {"<système>": [tenant, depuis]},
##   "st": [{"id", "k": genre, "c": centre, "nx": prochain centre, "left": jours de vie, "step": jours
##   avant le saut}], "nst": prochain identifiant de tempête}.
## Dérivé (non sauvegardé) : StarSystem.terrain, transit_pct, veiled, blind, recalculés par refresh().
## Tout est déterministe : flux aléatoires dérivés de la graine, parcours dans l'ordre des identifiants.

const NONE := "aucun"
const STORMS_ON := "actives"
const STORMS_OFF := "aucunes"
const MODES: Array[String] = ["aucun", "clairseme", "normal", "dense"]
const STORM_MODES: Array[String] = ["actives", "aucunes"]

static var _talent_cache := {}


static func data() -> Dictionary:
	return GameData.terrain()


static func def(id: String) -> Dictionary:
	return (data().get("terrains", {}) as Dictionary).get(id, {})


static func label(id: String) -> String:
	return String(def(id).get("label", id))


static func mode_defs() -> Array:
	return data().get("densities", [])


static func storm_mode_defs() -> Array:
	return data().get("storm_modes", [])


static func default_density() -> String:
	return String(data().get("default_density", "normal"))


static func default_storms() -> String:
	return String(data().get("default_storms", STORMS_ON))


static func _blank() -> Dictionary:
	return {"d": NONE, "s": STORMS_OFF, "sys": {}, "rg": [], "held": {}, "st": [], "nst": 1}


static func active(state: GameState) -> bool:
	return String(state.terrain.get("d", NONE)) != NONE


static func storms_on(state: GameState) -> bool:
	return active(state) and String(state.terrain.get("s", STORMS_OFF)) == STORMS_ON


static func density(state: GameState) -> String:
	return String(state.terrain.get("d", NONE))


# --- Création, sauvegarde ------------------------------------------------------------------------

static func setup(state: GameState, mode: String, storms := STORMS_ON) -> void:
	state.terrain = _blank()
	state.terrain["d"] = mode if MODES.has(mode) else NONE
	state.terrain["s"] = storms if STORM_MODES.has(storms) else STORMS_OFF
	if active(state):
		_generate(state)
		for sid in _sorted_sys(state):
			var o := state.system_owner(sid)
			if o >= 0:
				state.terrain["held"][str(sid)] = [o, 0]
	refresh(state)


static func worth_saving(state: GameState) -> bool:
	return active(state)


static func to_dict(state: GameState) -> Dictionary:
	return state.terrain.duplicate(true)


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.terrain = _blank()
	for k in d:
		state.terrain[k] = Vassals._ints(d[k])
	if not MODES.has(density(state)):
		state.terrain["d"] = NONE
	refresh(state)


static func _sorted_sys(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for k in state.terrain.get("sys", {}):
		out.append(int(k))
	out.sort()
	return out


## Recalcule ce que chaque système doit au terrain (transit, voile, aveuglement), après la création,
## un chargement, un cimetière qui apparaît ou une tempête qui bouge.
static func refresh(state: GameState) -> void:
	var g := state.galaxy
	if g == null:
		return
	var on := active(state)
	for s in g.systems:
		s.terrain = String(state.terrain["sys"].get(str(s.id), "")) if on else ""
		s.transit_pct = 0
		s.veiled = false
		s.blind = false
	if not on:
		return
	for s in g.systems:
		var fx := fx_of(state, s.id)
		s.transit_pct = int(fx.get("transit_pct", 0))
		s.veiled = bool(fx.get("veil", false))
		s.blind = bool(fx.get("blind", false))


# --- Génération (prop. 5, 6) ---------------------------------------------------------------------

static func _generate(state: GameState) -> void:
	var g := state.galaxy
	var cfg := data()
	var share := 0
	for m: Dictionary in mode_defs():
		if String(m["id"]) == density(state):
			share = int(m.get("share", 0))
	var n := g.systems.size()
	var target := roundi(float(n) * share / 100.0)
	if target <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([state.seed_value, "terrain"])
	# Distances aux départs (2 sauts au plus).
	var starts: Array[int] = []
	for e in state.empires:
		if e.home_planet >= 0:
			var hp := g.get_planet(e.home_planet)
			if hp != null and not starts.has(hp.system_id):
				starts.append(hp.system_id)
	var place: Dictionary = cfg.get("placement", {})
	var safe := int(place.get("safe_radius", 1))
	var max_ring := int(place.get("max_ring", 1))
	var near := {}  # système -> [[départ, distance]...]
	for si in starts.size():
		var dist := {starts[si]: 0}
		var frontier: Array[int] = [starts[si]]
		for r in 2:
			var nxt: Array[int] = []
			for s in frontier:
				for nb in g.systems[s].neighbors:
					if not dist.has(nb):
						dist[nb] = r + 1
						nxt.append(nb)
			frontier = nxt
		for s in dist:
			if not near.has(s):
				near[s] = []
			near[s].append([si, int(dist[s])])
	var ring := PackedInt32Array()
	ring.resize(starts.size())
	var sys: Dictionary = state.terrain["sys"]
	var ok := func(s: int) -> bool:
		if sys.has(str(s)):
			return false
		for pair: Array in near.get(s, []):
			if int(pair[1]) <= safe:
				return false
			if int(pair[1]) == 2 and ring[int(pair[0])] >= max_ring:
				return false
		return true
	var take := func(s: int, id: String) -> void:
		sys[str(s)] = id
		for pair: Array in near.get(s, []):
			if int(pair[1]) == 2:
				ring[int(pair[0])] += 1
	var neb: Dictionary = cfg.get("nebula", {})
	var neb_target := roundi(float(target) * int(neb.get("share", 60)) / 100.0)
	var sizes: Array = neb.get("size", [3, 8])
	var prefixes: Array = neb.get("prefixes", ["Nébuleuse de"])
	var placed := 0
	var tries := 0
	while placed < neb_target and tries < 300:
		tries += 1
		var seed_sys := rng.randi_range(0, n - 1)
		if not ok.call(seed_sys):
			continue
		var want := rng.randi_range(int(sizes[0]), int(sizes[1]))
		var region: Array[int] = [seed_sys]
		take.call(seed_sys, "nebuleuse")
		var frontier: Array[int] = [seed_sys]
		while region.size() < want and not frontier.is_empty():
			var cur: int = frontier.pop_front()
			var nbs: Array = g.systems[cur].neighbors.duplicate()
			nbs.sort()
			for i in range(nbs.size() - 1, 0, -1):
				var j := rng.randi_range(0, i)
				var t: Variant = nbs[i]
				nbs[i] = nbs[j]
				nbs[j] = t
			for nb in nbs:
				if region.size() >= want:
					break
				if ok.call(int(nb)):
					take.call(int(nb), "nebuleuse")
					region.append(int(nb))
					frontier.append(int(nb))
		placed += region.size()
		if region.size() >= 3 and rng.randi_range(1, 100) <= int(neb.get("ionized_chance", 35)):
			sys[str(seed_sys)] = "nebuleuse_ionisee"
		region.sort()
		var pre := String(prefixes[rng.randi_range(0, prefixes.size() - 1)])
		state.terrain["rg"].append([_region_name(pre, g.systems[seed_sys].system_name), region])
	# Terrains isolés.
	var singles: Dictionary = cfg.get("singles", {})
	var kinds: Array[String] = []
	for k in singles:
		if not String(k).begins_with("_"):
			kinds.append(String(k))
	kinds.sort()
	tries = 0
	while placed < target and tries < 2000:
		tries += 1
		var s := rng.randi_range(0, n - 1)
		if not ok.call(s):
			continue
		var belt := false
		for pid in g.systems[s].planet_ids:
			if g.get_planet(pid).type == "asteroids":
				belt = true
		var total := 0
		for k in kinds:
			total += int(singles[k]) * (3 if belt and k == "asteroides" else 1)
		var roll := rng.randi_range(1, total)
		for k in kinds:
			roll -= int(singles[k]) * (3 if belt and k == "asteroides" else 1)
			if roll <= 0:
				take.call(s, k)
				break
		placed += 1
	_add_deposits(state)


static func _region_name(prefix: String, sys_name: String) -> String:
	var first := sys_name.substr(0, 1).to_lower()
	if prefix.ends_with(" de") and "aeiouyéèêh".contains(first):
		return prefix.substr(0, prefix.length() - 2) + "d'" + sys_name
	return prefix + " " + sys_name


## Gisements plus fréquents dans certains terrains (nébuleuses : cristaux ; astéroïdes : filons).
static func _add_deposits(state: GameState) -> void:
	var defs := {}
	for d: Dictionary in GameData.rules()["deposits"]:
		defs[String(d["id"])] = d
	for sid in _sorted_sys(state):
		var bonus: Dictionary = def(String(state.terrain["sys"][str(sid)])).get("fx", {}).get("deposits", {})
		if bonus.is_empty():
			continue
		for pid in state.galaxy.systems[sid].planet_ids:
			var p := state.galaxy.get_planet(pid)
			var prng := RandomNumberGenerator.new()
			prng.seed = hash([state.seed_value, "terrain_dep", pid])
			var ids := bonus.keys()
			ids.sort()
			for dep in ids:
				var dd: Dictionary = defs.get(String(dep), {})
				if dd.is_empty() or p.deposits.has(String(dep)):
					continue
				if dd.get("habitable_only", false) and not p.is_habitable_type():
					continue
				if prng.randi_range(1, 100) <= int(bonus[dep]):
					p.deposits.append(String(dep))


# --- Lecture ---------------------------------------------------------------------------------------

## Terrains actifs d'un système, triés : effet d'étoile, terrain de zone, tempêtes. Vide sans terrain.
## C'est ce que lisent le décor des batailles (scene["terrain"]) et l'interface.
static func at(state: GameState, sid: int) -> Array[String]:
	var out: Array[String] = []
	if not active(state) or sid < 0 or sid >= state.galaxy.systems.size():
		return out
	var star := state.galaxy.systems[sid].star_type
	if def(star).get("family", "") == "star":
		out.append(star)
	var z := String(state.terrain["sys"].get(str(sid), ""))
	if z != "":
		out.append(z)
	for st: Dictionary in state.terrain.get("st", []):
		var k := String(st["k"])
		if not out.has(k) and storm_covers(state, st, sid):
			out.append(k)
	out.sort()
	return out


## Terrain de zone d'un système ("" sinon).
static func zone(state: GameState, sid: int) -> String:
	if not active(state):
		return ""
	return String(state.terrain["sys"].get(str(sid), ""))


## Nom de la nébuleuse qui contient le système ("" sinon).
static func region_name(state: GameState, sid: int) -> String:
	for r: Array in state.terrain.get("rg", []):
		if (r[1] as Array).has(sid):
			return String(r[0])
	return ""


## Effets réunis des terrains d'un système : le plus fort compte sur chaque levier.
static func fx_of(state: GameState, sid: int, ids: Variant = null) -> Dictionary:
	var list: Array = at(state, sid) if ids == null else ids
	return merge_fx(list)


static func merge_fx(list: Array) -> Dictionary:
	var out := {}
	for id in list:
		var fx: Dictionary = def(String(id)).get("fx", {})
		for k in fx:
			var v: Variant = fx[k]
			match String(k):
				"transit_pct":
					out[k] = maxi(int(out.get(k, 0)), int(v))
				"shield_pct", "taken_pct":
					out[k] = mini(int(out.get(k, 100)), int(v))
				"phase_pct":
					var cur: Array = out.get(k, [100, 100, 100])
					var nv: Array = []
					for i in 3:
						nv.append(mini(int(cur[i]), int((v as Array)[i])))
					out[k] = nv
				"weapon_pct":
					var w: Dictionary = (out.get(k, {}) as Dictionary).duplicate()
					for wk in v:
						w[wk] = mini(int(w.get(wk, 100)), int(v[wk]))
					out[k] = w
				"yields", "deposits":
					var y: Dictionary = (out.get(k, {}) as Dictionary).duplicate()
					for r in v:
						y[r] = maxi(int(y.get(r, 0)), int(v[r]))
					out[k] = y
				_:
					if v is bool:
						out[k] = bool(out.get(k, false)) or bool(v)
	return out


static func has_fx(state: GameState, sid: int, key: String) -> bool:
	return active(state) and bool(fx_of(state, sid).get(key, false))


## Une ligne par terrain : « Nébuleuse : transit 50 % plus long… · discrétion… ».
static func lines(state: GameState, sid: int) -> Array[String]:
	var out: Array[String] = []
	for id in at(state, sid):
		var d := def(id)
		out.append("%s : %s · %s" % [String(d.get("label", id)), String(d.get("bad", "")), String(d.get("good", ""))])
	return out


## Résumé court pour un en-tête (« Étoile à neutrons, Nébuleuse »).
static func short(state: GameState, sid: int) -> String:
	var parts := PackedStringArray()
	for id in at(state, sid):
		parts.append(label(id))
	return ", ".join(parts)


# --- Talents, technologies, héros (prop. 25, 27, 28) ----------------------------------------------

## Talent de terrain d'un empire par ses couches d'espèce ({} sinon), comme Logistics.talent.
static func talent(state: GameState, eid: int) -> Dictionary:
	var e := state.get_empire(eid)
	if e == null or e.is_npc():
		return {}
	var ck := "%s:%s:%s" % [e.faction_id, str(e.faction().get("species", {})), String(e.faction().get("registre", ""))]
	if _talent_cache.has(ck):
		return _talent_cache[ck]
	var out := {}
	var sp := FactionTraits.species(e.faction())
	var table: Dictionary = data().get("talents", {})
	for layer in ["traits", "archetype", "gouvernement", "credo", "registre"]:
		var t: Dictionary = table.get(layer, {})
		var values: Array = sp.get("traits", []) if layer == "traits" else [String(sp.get(layer, "")) if layer != "registre" else String(e.faction().get("registre", ""))]
		for v in values:
			if not t.has(String(v)):
				continue
			var d: Dictionary = t[String(v)]
			out["labels"] = (out.get("labels", []) as Array) + [[String(d["label"]), String(d["text"])]]
			for k in d:
				if k == "label" or k == "text":
					continue
				if d[k] is bool:
					out[k] = bool(out.get(k, false)) or bool(d[k])
				elif d[k] is Array:
					out[k] = (out.get(k, []) as Array) + (d[k] as Array)
				elif d[k] is Dictionary:
					var m: Dictionary = (out.get(k, {}) as Dictionary).duplicate(true)
					for kk in d[k]:
						m[kk] = d[k][kk]
					out[k] = m
				else:
					out[k] = int(out.get(k, 0)) + int(d[k])
	_talent_cache[ck] = out
	return out


static func talent_labels(state: GameState, eid: int) -> Array:
	return talent(state, eid).get("labels", [])


static func immune(state: GameState, eid: int, id: String) -> bool:
	return (talent(state, eid).get("immune", []) as Array).has(id)


## Réduction des malus de transit (%, de 0 à 100) pour une flotte : technologies, talents, amiral.
static func transit_cut(state: GameState, f: Fleet) -> int:
	if f.owner < 0 or GameState.is_npc(f.owner):
		return 0
	var cut := -int(talent(state, f.owner).get("transit_pct", 0)) - Research.fx_int(state, f.owner, "terrain_transit_pct")
	if not state.heroes.is_empty():
		var h := Heroes.at_post(state, "fleet", f.id, f.owner)
		if not h.is_empty() and Heroes.trait_fx(h, "terrain_transit") > 0:
			cut = 100
	return clampi(cut, 0, 100)


## L'empire voit-il dans les nébuleuses à 1 saut (technologie, talent) ?
static func pierces(state: GameState, eid: int) -> bool:
	if not active(state) or eid < 0 or GameState.is_npc(eid):
		return false
	return bool(talent(state, eid).get("pierce", false)) or Research.fx_int(state, eid, "terrain_pierce") > 0


# --- Déplacements (prop. 4, 9-11) ------------------------------------------------------------------

## Vitesse d'une flotte sur la route qu'elle parcourt : la longueur de route tient déjà compte du
## terrain (Fleets.lane_length) ; une flotte qui en réduit le malus va plus vite d'autant.
static func fleet_speed(state: GameState, f: Fleet, sp: int) -> int:
	if not active(state) or not f.is_moving():
		return sp
	var g := state.galaxy
	var pct := maxi(g.systems[f.system_id].transit_pct, g.systems[f.path[0]].transit_pct)
	if pct <= 0:
		return sp
	var cut := transit_cut(state, f)
	if cut <= 0:
		return sp
	@warning_ignore("integer_division")
	var eff := pct * (100 - cut) / 100
	@warning_ignore("integer_division")
	return maxi(1, sp * (100 + pct) / (100 + eff))


## Bataille qu'on ne peut pas quitter (trou noir, tempête gravitationnelle) : la flotte y est engagée.
static func pinned(state: GameState, f: Fleet) -> bool:
	if not active(state) or f.progress > 0:
		return false
	var b: Dictionary = state.battles.get(f.system_id, {})
	if b.is_empty():
		return false
	var engaged := false
	for e: Array in b.get("fleets", []):
		if int(e[0]) == f.id:
			engaged = true
	if not engaged or not has_fx(state, f.system_id, "pin"):
		return false
	for id in at(state, f.system_id):
		if bool(def(id).get("fx", {}).get("pin", false)) and not immune(state, f.owner, id):
			return true
	return false


# --- Batailles (prop. 13-17) -----------------------------------------------------------------------

## Effets de combat du terrain pour un camp : les malus des terrains dont son peuple est immunisé
## tombent ; le camp qui tient le système depuis assez longtemps n'en subit qu'une part (prop. 15).
## {"shield_pct", "taken_pct", "phase_pct", "weapon_pct", "no_repair"}.
static func battle_fx(state: GameState, sid: int, eid: int) -> Dictionary:
	if not active(state):
		return {}
	var list: Array = []
	for id in at(state, sid):
		if not immune(state, eid, id):
			list.append(id)
	var fx := merge_fx(list)
	var out := {}
	for k in ["shield_pct", "taken_pct", "phase_pct", "weapon_pct"]:
		if fx.has(k):
			out[k] = fx[k]
	if out.is_empty():
		return out
	var fam: Dictionary = data().get("familiarity", {})
	var held: Array = state.terrain["held"].get(str(sid), [])
	if not held.is_empty() and int(held[0]) == eid and state.tick - int(held[1]) >= int(fam.get("days", 720)):
		var keep := int(fam.get("pct", 50))
		if out.has("shield_pct"):
			out["shield_pct"] = _soften(int(out["shield_pct"]), keep)
		if out.has("phase_pct"):
			var p: Array = []
			for v in out["phase_pct"]:
				p.append(_soften(int(v), keep))
			out["phase_pct"] = p
		if out.has("weapon_pct"):
			var w := {}
			for k in out["weapon_pct"]:
				w[k] = _soften(int(out["weapon_pct"][k]), keep)
			out["weapon_pct"] = w
		out["familiar"] = true
	return out


## Un malus (valeur < 100) dont on ne garde que keep % : 0 avec keep 50 -> 50.
static func _soften(v: int, keep: int) -> int:
	if v >= 100:
		return v
	@warning_ignore("integer_division")
	return 100 - (100 - v) * keep / 100


## Boucliers effectifs (%) d'un vaisseau ciblé : boucliers durcis (prop. 25) = moitié au lieu de rien.
static func shield_pct(fx: Dictionary, ship_id: String) -> int:
	var v := int(fx.get("shield_pct", 100))
	if v < 100 and bool(GameData.ship(ship_id).get("hardened_shields", false)):
		v = maxi(v, int(data().get("counters", {}).get("shield_floor", 50)))
	return v


## Multiplicateur (%) des dégâts d'une arme à une phase, pour le camp qui tire.
static func shot_pct(fx: Dictionary, weapon: String, phase: int) -> int:
	if fx.is_empty():
		return 100
	var w := int((fx.get("weapon_pct", {}) as Dictionary).get(weapon, 100))
	var p := int((fx.get("phase_pct", [100, 100, 100]) as Array)[phase])
	@warning_ignore("integer_division")
	return w * p / 100


## Réparations coupées (radiations) pour cette flotte ?
## Handicap (%) d'un attaquant contre le défenseur dans un système (prop. 30, IA Vétéran et plus) :
## compare ce que chaque camp inflige (phases, armes) à ce qu'il encaisse (boucliers, dégâts subis).
## Un terrain qui frappe les deux camps pareil ne compte pas ; seuls l'immunité et la familiarité
## du défenseur, ou un talent de terrain, creusent l'écart.
static func ai_handicap(state: GameState, sid: int, attacker: int, defender: int) -> int:
	if not active(state):
		return 0
	var a := battle_fx(state, sid, attacker)
	var d := battle_fx(state, sid, defender)
	if a.is_empty() and d.is_empty():
		return 0
	var mine := _ai_strength(a) * _ai_vulnerability(d)
	var theirs := _ai_strength(d) * _ai_vulnerability(a)
	if theirs <= 0 or mine >= theirs:
		return 0
	@warning_ignore("integer_division")
	return 100 - mine * 100 / theirs


const AI_WEAPONS := ["kinetic", "beam", "missile", "torpedo", "fighters"]


static func _ai_strength(fx: Dictionary) -> int:
	var p := 0
	for v in fx.get("phase_pct", [100, 100, 100]):
		p += int(v)
	var w: Dictionary = fx.get("weapon_pct", {})
	var wsum := 0
	for k in AI_WEAPONS:
		wsum += int(w.get(k, 100))
	@warning_ignore("integer_division")
	return (p / 3) * (wsum / AI_WEAPONS.size()) / 100


static func _ai_vulnerability(fx: Dictionary) -> int:
	@warning_ignore("integer_division")
	return int(fx.get("taken_pct", 100)) * (100 + (100 - int(fx.get("shield_pct", 100))) / 2) / 100


static func no_repair(state: GameState, f: Fleet) -> bool:
	if not active(state) or f.is_moving():
		return false
	for id in at(state, f.system_id):
		if bool(def(id).get("fx", {}).get("no_repair", false)) and not immune(state, f.owner, id):
			return true
	return false


## Rendement en plus de chaque revendication d'un système (prop. 9-12, 28).
static func adjust_yields(state: GameState, sid: int, owner: int, gross: Dictionary) -> void:
	if not active(state):
		return
	var fx := fx_of(state, sid)
	var y: Dictionary = fx.get("yields", {})
	for r in y:
		gross[r] = int(gross.get(r, 0)) + int(y[r])
	var z := zone(state, sid)
	if z != "" and owner >= 0:
		var extra: Dictionary = (talent(state, owner).get("yields_in", {}) as Dictionary).get(z, {})
		for r in extra:
			gross[r] = int(gross.get(r, 0)) + int(extra[r])


# --- Chaque jour : tenants, cimetières, tempêtes ---------------------------------------------------

static func daily(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if not active(state):
		return added
	if state.tick % 30 == 0:
		_update_held(state)
	if storms_on(state):
		_storms_daily(state, added)
	return added


static func _update_held(state: GameState) -> void:
	var held: Dictionary = state.terrain["held"]
	for s in state.galaxy.systems:
		if at(state, s.id).is_empty():
			continue
		var o := state.system_owner(s.id)
		var k := str(s.id)
		if o < 0:
			held.erase(k)
		elif not held.has(k) or int(held[k][0]) != o:
			held[k] = [o, state.tick]


## Fin de bataille : un système sans terrain de zone qui a vu trop de vaisseaux mourir devient un
## cimetière d'épaves (prop. 12).
static func on_battle_end(state: GameState, sid: int, added: Array[Dictionary]) -> void:
	if not active(state) or zone(state, sid) != "":
		return
	var need := int(data().get("graveyard", {}).get("wrecks", 30))
	if int(state.battle_wrecks.get(sid, 0)) < need:
		return
	state.terrain["sys"][str(sid)] = "cimetiere"
	refresh(state)
	added.append(state.add_chronicle("À %s, les épaves sont si nombreuses qu'on y navigue entre les carcasses : le système devient un cimetière d'épaves. Les ferrailleurs se frottent les mains, les pilotes beaucoup moins." % [
			state.galaxy.systems[sid].system_name]))


# --- Tempêtes (prop. 18-21) ------------------------------------------------------------------------

static func storm_cfg() -> Dictionary:
	return data().get("storms", {})


## Systèmes couverts par une tempête : son centre et les voisins à `radius` sauts.
static func storm_systems(state: GameState, st: Dictionary) -> Array[int]:
	var out: Array[int] = [int(st["c"])]
	var radius := int(storm_cfg().get("radius", 1))
	var frontier: Array[int] = [int(st["c"])]
	for _r in radius:
		var nxt: Array[int] = []
		for s in frontier:
			for nb in state.galaxy.systems[s].neighbors:
				if not out.has(nb):
					out.append(nb)
					nxt.append(nb)
		frontier = nxt
	out.sort()
	return out


static func storm_covers(state: GameState, st: Dictionary, sid: int) -> bool:
	var c := int(st["c"])
	if c == sid:
		return true
	if int(storm_cfg().get("radius", 1)) <= 1:
		return state.galaxy.systems[c].neighbors.has(sid)
	return storm_systems(state, st).has(sid)


static func storms(state: GameState) -> Array:
	return state.terrain.get("st", [])


static func _storm_rng(state: GameState, tag: Variant) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([state.seed_value, "storm", state.tick, tag])
	return rng


static func _storms_daily(state: GameState, added: Array[Dictionary]) -> void:
	var cfg := storm_cfg()
	var changed := false
	var keep: Array = []
	for st: Dictionary in storms(state):
		st["left"] = int(st["left"]) - 1
		if int(st["left"]) <= 0:
			changed = true
			added.append(state.add_chronicle("La %s s'éteint près de %s. Les navigateurs ressortent leurs cartes, un peu froissées." % [
					label(String(st["k"])).to_lower(), state.galaxy.systems[int(st["c"])].system_name]))
			continue
		st["step"] = int(st["step"]) - 1
		if int(st["step"]) <= 0:
			st["c"] = int(st["nx"])
			st["nx"] = _next_center(state, st)
			st["step"] = int(cfg.get("step_days", 60))
			changed = true
		keep.append(st)
	state.terrain["st"] = keep
	if state.tick % 30 == 0:
		_storm_research(state, added)
		if state.tick >= int(cfg.get("start_day", 3600)):
			var cap := clampi(state.galaxy.systems.size() / maxi(1, int(cfg.get("per_systems", 70))), 1, int(cfg.get("max", 3)))
			if keep.size() < cap:
				var rng := _storm_rng(state, "spawn")
				if rng.randi_range(1, 1000) <= int(cfg.get("spawn_chance", 250)):
					_spawn_storm(state, rng, added)
					changed = true
	if changed:
		refresh(state)


static func _spawn_storm(state: GameState, rng: RandomNumberGenerator, added: Array[Dictionary]) -> void:
	var cfg := storm_cfg()
	var cands: Array[int] = []
	for sid in _sorted_sys(state):
		var z := String(state.terrain["sys"][str(sid)])
		if z == "nebuleuse" or z == "nebuleuse_ionisee":
			cands.append(sid)
	if cands.is_empty():
		for s in state.galaxy.systems:
			cands.append(s.id)
	var c := cands[rng.randi_range(0, cands.size() - 1)]
	var kinds: Array = cfg.get("kinds", [])
	var life: Array = cfg.get("life_days", [360, 1080])
	var st := {"id": int(state.terrain.get("nst", 1)), "k": String(kinds[rng.randi_range(0, kinds.size() - 1)]), "c": c,
			"nx": c, "left": rng.randi_range(int(life[0]), int(life[1])), "step": int(cfg.get("step_days", 60)), "prev": -1}
	state.terrain["nst"] = int(st["id"]) + 1
	st["nx"] = _next_center(state, st)
	state.terrain["st"].append(st)
	added.append(state.add_chronicle("Une %s se lève %s. Elle dérive vers %s : prudence, ou bonne occasion pour les savants." % [
			label(String(st["k"])).to_lower(), where_text(state, c), state.galaxy.systems[int(st["nx"])].system_name]))


## « dans le Voile de Kessaran », « dans la Brume d'Orvel », sinon « près de Kessaran ».
static func where_text(state: GameState, sid: int) -> String:
	var r := region_name(state, sid)
	if r == "":
		return "près de " + state.galaxy.systems[sid].system_name
	return ("dans le " if r.begins_with("Voile") or r.begins_with("Linceul") else "dans la ") + r


## Prochain centre : un voisin tiré, en évitant de revenir sur ses pas.
static func _next_center(state: GameState, st: Dictionary) -> int:
	var c := int(st["c"])
	var nbs: Array = state.galaxy.systems[c].neighbors.duplicate()
	nbs.sort()
	var prev := int(st.get("prev", -1))
	if nbs.size() > 1 and nbs.has(prev):
		nbs.erase(prev)
	st["prev"] = c
	if nbs.is_empty():
		return c
	return int(nbs[_storm_rng(state, ["next", int(st["id"])]).randi_range(0, nbs.size() - 1)])


## Chasseurs de tempêtes : une flotte à l'arrêt dans une tempête rapporte du Savoir à son empire et
## parfois un eurêka (une avance sur la recherche en cours) ; les mondes d'un peuple à « signes du ciel »
## gagnent de la ferveur.
static func _storm_research(state: GameState, added: Array[Dictionary]) -> void:
	var cfg := storm_cfg()
	var per := int(cfg.get("research", 2)) * 30
	var studied := {}
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.is_moving() or f.owner < 0 or GameState.is_npc(f.owner) or studied.has(f.owner):
			continue
		for st: Dictionary in storms(state):
			if storm_covers(state, st, f.system_id):
				studied[f.owner] = String(st["k"])
				break
	var owners := studied.keys()
	owners.sort()
	for eid in owners:
		var e := state.get_empire(int(eid))
		if e == null or e.eliminated:
			continue
		e.resources["knowledge"] = int(e.resources.get("knowledge", 0)) + per
		var rng := _storm_rng(state, ["eureka", int(eid)])
		if not e.research_queue.is_empty() and rng.randi_range(1, 100) <= int(cfg.get("eureka_chance", 10)):
			var tid := e.research_queue[0]
			@warning_ignore("integer_division")
			Research.add_progress(state, int(eid), tid, Research.cost(state, int(eid), tid) / 4)
			added.append(state.add_chronicle("%s : les relevés pris au cœur de la %s font avancer « %s » d'un bond." % [
					e.short_name(), label(String(studied[eid])).to_lower(), String(Research.tech(tid).get("label", tid))], [int(eid)]))
	# Signes du ciel (credo) : une tempête qui couvre au moins un de ses systèmes.
	for e in state.empires:
		var fv := int(talent(state, e.id).get("storm_fervor", 0))
		if fv <= 0 or e.eliminated or not e.faction().has("fervor"):
			continue
		var hit := false
		for st: Dictionary in storms(state):
			for sid in storm_systems(state, st):
				if state.system_owner(sid) == e.id:
					hit = true
		if hit:
			e.fervor = mini(int(e.faction()["fervor"]["max"]), e.fervor + fv)


# --- Ponts (prop. 22-24) ---------------------------------------------------------------------------

## Le ravitaillement ne traverse pas ce système (tempête, nébuleuse ionisée).
static func blocks_supply(state: GameState, sid: int) -> bool:
	return active(state) and has_fx(state, sid, "supply_block")


## Une route commerciale qui passe par ce système est suspendue (tempête).
static func blocks_trade(state: GameState, sid: int) -> bool:
	return active(state) and not storms(state).is_empty() and has_fx(state, sid, "trade_block")


## Discrétion (nébuleuse) : intrusions repérées seulement par une présence dans le système, et
## opérations d'espionnage plus sûres.
static func stealthy(state: GameState, sid: int) -> bool:
	return active(state) and has_fx(state, sid, "stealth")


## Bonus de discrétion (en points de %) d'une opération d'espionnage dans ce système.
static func spy_bonus(state: GameState, eid: int, sid: int) -> int:
	if not stealthy(state, sid):
		return 0
	return 20 if bool(talent(state, eid).get("stealth_x2", false)) else 10


## Discrétion d'un réseau d'espionnage de a chez b : quand au moins un quart des systèmes de b sont
## dans une nébuleuse, la découverte baisse (spy_bonus).
static func empire_spy_bonus(state: GameState, a: int, b: int) -> int:
	if not active(state):
		return 0
	var total := 0
	var hidden := 0
	var any := -1
	for s in state.galaxy.systems:
		if state.system_owner(s.id) == b:
			total += 1
			if stealthy(state, s.id):
				hidden += 1
				any = s.id
	if total == 0 or hidden * 4 < total:
		return 0
	return spy_bonus(state, a, any)


## Le propriétaire du système a-t-il une présence (flotte ou colonie) dedans ? Sert à repérer les
## intruses dans une nébuleuse.
static func present(state: GameState, eid: int, sid: int) -> bool:
	if state.system_owner(sid) == eid:
		for pid in state.galaxy.systems[sid].planet_ids:
			var c: Colony = state.colonies.get(pid)
			if c != null and c.owner == eid:
				return true
	for f in Fleets.fleets_at(state, sid, eid):
		if not f.is_moving():
			return true
	return false
