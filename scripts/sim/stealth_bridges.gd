class_name StealthBridges
extends RefCounted
## Furtivité et détection, lot 3 : les ponts avec les autres piliers (data/stealth.json).
## - Héros (prop. 32) : traits d'amiral Fantôme (+1 camouflage), Œil-de-lynx (+1 détection), Chasseur
##   d'ombres (+25 % de dégâts dans une bataille où une flotte ennemie était cachée).
## - Espionnage (prop. 21, 29) : la sonde perce jusqu'à 3 ; le palier Amirauté perce le camouflage des
##   flottes du rival ; l'opération « Voler les codes de camouflage » donne +2 de détection contre lui.
## - Défenses (prop. 30) : mines, inhibiteur, blocus et stations ne retiennent que ce qu'ils voient
##   (Stealth.unseen_by / slips) ; assiéger ou débarquer fait tomber le voile.
## - Griefs (prop. 35) : une flotte camouflée repérée chez un empire en paix = souvenir « naval_spy ».
## - Hauts faits (prop. 34) : flottes voilées, systèmes rivaux traversés cachés, flottes cachées repérées.


static func _hero(state: GameState, f: Fleet) -> Dictionary:
	if f == null or f.id < 0 or state.heroes.is_empty():
		return {}
	return Heroes.at_post(state, "fleet", f.id, f.owner)


static func hero_cloak(state: GameState, f: Fleet) -> int:
	var h := _hero(state, f)
	return 0 if h.is_empty() else Heroes.trait_fx(h, "stealth_cloak")


static func hero_detect(state: GameState, f: Fleet) -> int:
	var h := _hero(state, f)
	return 0 if h.is_empty() else Heroes.trait_fx(h, "stealth_detect")


## Chasseur d'ombres : bonus contre une bataille où une flotte ennemie était voilée.
static func hunter_pct(state: GameState, b: Dictionary, f: Fleet) -> int:
	var h := _hero(state, f)
	if h.is_empty():
		return 0
	var pct := Heroes.trait_fx(h, "stealth_hunter_pct")
	if pct == 0:
		return 0
	for k in (b.get("veiled", {}) as Dictionary):
		var g: Fleet = state.fleets.get(int(k))
		if g != null and g.owner != f.owner:
			return pct
	return 0


## Codes de camouflage volés : +2 de détection de eid contre les flottes de against ; le palier
## Amirauté du réseau d'espionnage de eid chez against perce aussi (+5).
static func codes_bonus(state: GameState, eid: int, against: int) -> int:
	if against < 0 or against >= state.empires.size() or eid == against:
		return 0
	var n := 0
	var end := int((state.stealth.get("codes", {}) as Dictionary).get("%d:%d" % [eid, against], -1))
	if end > state.tick:
		n += int(Stealth.cfg("codes").get("detect", 2))
	if Espionage.tier(state, eid, against) >= 3:
		n += Stealth.max_level()
	return n


## Sonde (prop. 21) : les flottes du système sondé, cachées jusqu'à probe_detect, sont relevées dans la
## mémoire de l'empire (silhouettes), même hors de sa vision.
static func on_probe(state: GameState, player: int, sid: int) -> void:
	if not Stealth.enabled(state):
		return
	var e := state.get_empire(player)
	var lvl := int(Stealth.data().get("probe_detect", 3))
	for f in Fleets.fleets_at(state, sid):
		if f.owner == player or f.owner < 0 or f.owner >= state.empires.size():
			continue
		if Stealth.cloak(state, f) > lvl:
			continue
		e.sightings[f.id] = {"sys": sid, "day": state.tick, "owner": f.owner, "ships": f.ships.size(),
				"armed": 1 if Combat.is_armed(f) else 0}
		_found(state, player, f)


## Opération « Voler les codes de camouflage ».
static func spy_check(state: GameState, _a: int, _b: int, op_id: String) -> String:
	if op_id != "voler_codes":
		return ""
	if not Stealth.enabled(state):
		return "la furtivité n'est pas en jeu dans cette partie"
	return ""


static func spy_apply(state: GameState, a: int, b: int, o: Dictionary) -> String:
	if String(o.get("id", "")) != "voler_codes":
		return ""
	var codes := Stealth._sub(state, "codes")
	codes["%d:%d" % [a, b]] = state.tick + int(Stealth.cfg("codes").get("days", 360))
	Stealth.invalidate()
	return "les codes de camouflage de %s sont à nous pour un an : leurs voiles s'effilochent sur nos écrans." % state.get_empire(b).display_name()


## Embuscade réussie (pour l'interface et la chronique).
static func on_ambush(state: GameState, f: Fleet, b: Dictionary) -> void:
	var sid := int(b.get("system", f.system_id))
	var names := PackedStringArray()
	var ids: Array[int] = [f.owner]
	for s: Dictionary in b.get("sides", []):
		var o := int(s["empire"])
		if o != f.owner and o >= 0 and o < state.empires.size():
			ids.append(o)
			names.append(state.get_empire(o).display_name())
	state.add_chronicle("Embuscade à %s : %s jaillit du néant sur %s. Les premiers tirs partent avant les alarmes." % [
			state.galaxy.systems[sid].system_name, f.fleet_name, ", ".join(names) if not names.is_empty() else "l'ennemi"],
			Espionage.private_to(state, ids, sid))


# --- Hauts faits et griefs ---------------------------------------------------------------------

static func _stats(state: GameState, eid: int) -> Dictionary:
	var st := Stealth._sub(state, "st")
	if not st.has(str(eid)):
		st[str(eid)] = {"spectre": 0, "found": 0, "path": {}}
	return st[str(eid)]


## Une flotte voilée est repérée par viewer (première fois) : haut fait et grief éventuel.
static func _found(state: GameState, viewer: int, f: Fleet) -> void:
	var seen := Stealth._sub(state, "seen")
	var k := "%d:%d" % [f.id, viewer]
	if seen.has(k):
		return
	seen[k] = state.tick
	var st := _stats(state, viewer)
	st["found"] = int(st.get("found", 0)) + 1
	var host := state.system_owner(f.system_id)
	if host == viewer and not Combat.at_war(state, viewer, f.owner):
		Diplomacy.remember(state, viewer, f.owner, "naval_spy")
		state.add_chronicle("%s repère une flotte camouflée de %s à %s, en pleine paix. On convoque l'ambassadeur ; il jure n'avoir rien vu, ce qui est exactement le problème." % [
				state.get_empire(viewer).display_name(), state.get_empire(f.owner).display_name(), state.galaxy.systems[f.system_id].system_name],
				Espionage.private_to(state, [viewer, f.owner]))


static func spectre(state: GameState, eid: int) -> int:
	if not Stealth.enabled(state):
		return 0
	return int(_stats(state, eid).get("spectre", 0))


static func found(state: GameState, eid: int) -> int:
	if not Stealth.enabled(state):
		return 0
	return int(_stats(state, eid).get("found", 0))


static func veiled_fleets(state: GameState, eid: int) -> int:
	if not Stealth.enabled(state):
		return 0
	var n := 0
	for f in Fleets.empire_fleets(state, eid):
		if Stealth.base_cloak(state, f) > 0 and not Veil.is_veiled(state, eid):
			n += 1
	return n


## Chaque jour : flottes voilées repérées (griefs, hauts faits) et systèmes rivaux traversés cachés.
static func daily(state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state.seen_cache.size() < state.empires.size():
		return out
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.owner < 0 or f.owner >= state.empires.size() or not Stealth.veil_up(state, f):
			continue
		var sid := Fleets.vision_center(state, f)
		var spotted := false
		for e in state.empires:
			if e.eliminated or e.id == f.owner or Diplomacy.allied(state, e.id, f.owner):
				continue
			if not (state.seen_cache[e.id] as Dictionary).has(sid):
				continue
			if Stealth.detects(state, e.id, f):
				spotted = true
				_found(state, e.id, f)
		# Spectre : un système rival (revendiqué par un autre empire) traversé sans être vu.
		var host := state.system_owner(sid)
		if not spotted and host >= 0 and host != f.owner and host < state.empires.size():
			var st := _stats(state, f.owner)
			var path: Dictionary = st.get("path", {})
			if not path.has(str(sid)):
				path[str(sid)] = 1
				st["path"] = path
				st["spectre"] = path.size()
	return out
