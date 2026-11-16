class_name Defenses
extends RefCounted
## Défenses spatiales (étude du 2026-11-16, 40 propositions validées ; data/defenses.json).
##
## Trois couches par système : l'orbite (station de défense, ses modules, les plates-formes, les mines),
## le sol-orbite (batteries, hangars et bouclier planétaires) et le sol (garnison, Citadelle,
## fortifications : l'existant). Les éléments armés forment une FLOTTE FIXE du défenseur, construite à
## la volée chaque jour de bataille (identifiant FIXED_BASE - système, jamais rangée dans state.fleets) :
## elle se bat dans les batailles du système comme une flotte immobile (tactique Rempart), puis ses
## dégâts sont recopiés dans state.defenses. Tant que la station tient, ni siège, ni bombardement, ni
## débarquement (Combat.besiegers, Combat.check_invade). Vaincue, elle est réduite au silence et se
## répare seule (60 jours) ; les plates-formes détruites sont perdues.
##
## Station : le bâtiment de palier le plus haut du système (Bastion orbital = I, Forteresse orbitale =
## II, Rempart stellaire = III, bâtiments « station »), un seul par système. Modules (« defense » :
## "module") et plates-formes ("platform") se bâtissent sur la colonie de la station, sans emplacement
## de planète ; les modules sont limités par le palier, les plates-formes par la capacité du système.
##
## Réglage « Défenses spatiales » : Complètes, Simples (station, modules, boucliers) ou Désactivées
## (state.defenses vide : le Bastion et la Citadelle n'agissent qu'au siège, comme avant). Sans
## l'option (tests, bancs) : désactivées.
##
## État : state.defenses = {"mode", "hp": {"sid": {clé: PV}} (absent = intact), "gen": {"sid": {clé: marque}},
##  "o": {"sid": propriétaire relevé}, "sil": {"sid": 1} (station réduite au silence), "sh": {"sid": points
##  de bouclier} (absent = plein), "mines": {"sid": {"o", "d"}}, "cut": {"sid": {"shield"|"inhib": jour de fin}}
##  (sabotage), "demil": {"sid": {"o", "t"}} (traité), "hx": {clé: jour}}.
## Clés d'élément : "st" (cœur), "m:<bâtiment>:<n>", "pf:<bâtiment>:<n>", "pl:<planète>:<bâtiment>", "se:<planète>:<n>".

const FIXED_BASE := -100000
const STATION_BUILDINGS := ["bastion", "forteresse_orbitale", "rempart_stellaire"]
const LAYERS := ["traits", "registre", "archetype", "gouvernement", "credo"]

static var _unit_cache := {}
static var _talent_cache := {}


static func data() -> Dictionary:
	return GameData.defenses()


static func cfg(section: String) -> Dictionary:
	return data().get(section, {})


static func mode_defs() -> Array:
	return data().get("modes", [])


static func default_mode() -> String:
	return String(data().get("default_mode", "complete"))


static func mode(state: GameState) -> String:
	return String(state.defenses.get("mode", "desactivee"))


static func enabled(state: GameState) -> bool:
	return state != null and not state.defenses.is_empty()


static func full(state: GameState) -> bool:
	return mode(state) == "complete"


static func mode_label(state: GameState) -> String:
	for m: Dictionary in mode_defs():
		if String(m["id"]) == mode(state):
			return String(m["label"])
	return "Désactivées"


# --- Réglage, sauvegarde -----------------------------------------------------------------------

static func setup(state: GameState, mode_id: String) -> void:
	state.defenses = {}
	var ok := false
	for m: Dictionary in mode_defs():
		if String(m["id"]) == mode_id:
			ok = true
	if not ok or mode_id == "desactivee":
		return
	state.defenses = {"mode": mode_id, "hp": {}, "gen": {}, "o": {}, "sil": {}, "sh": {}, "mines": {}, "cut": {}, "demil": {}, "hx": {}, "cs": {}}


static func worth_saving(state: GameState) -> bool:
	return not state.defenses.is_empty()


static func to_dict(state: GameState) -> Dictionary:
	return Ancients._sorted(state.defenses)


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.defenses = {}
	if d.is_empty():
		return
	state.defenses = GameData._to_ints(d.duplicate(true))
	for k in ["hp", "gen", "o", "sil", "sh", "mines", "cut", "demil", "hx", "cs"]:
		if not state.defenses.has(k):
			state.defenses[k] = {}


static func _sub(state: GameState, k: String) -> Dictionary:
	if not state.defenses.has(k):
		state.defenses[k] = {}
	return state.defenses[k]


# --- Bâtiments ---------------------------------------------------------------------------------

## Rôle de défense d'un bâtiment : "station", "module", "platform", "planetary", "shield" ou "".
static func role(bid: String) -> String:
	var b := GameData.building(bid)
	if b.has("station"):
		return "station"
	var d: Variant = b.get("defense", "")
	return String(d) if d is String else ""


static func station_tier_of(bid: String) -> int:
	return int(GameData.building(bid).get("station", 0))


static func module_def(bid: String) -> Dictionary:
	return cfg("buildings").get("modules", {}).get(bid, {})


static func platform_def(bid: String) -> Dictionary:
	return cfg("buildings").get("platforms", {}).get(bid, {})


static func planetary_def(bid: String) -> Dictionary:
	return cfg("buildings").get("planetary", {}).get(bid, {})


static func shield_def(bid: String) -> Dictionary:
	return cfg("buildings").get("shields", {}).get(bid, {})


static func tier_def(tier: int) -> Dictionary:
	return cfg("stations").get(str(tier), {})


## Un bâtiment de défense est-il permis par le mode de la partie ? (Le Bastion l'est toujours.)
static func building_allowed(state: GameState, bid: String) -> bool:
	var r := role(bid)
	if r == "" or bid == "bastion":
		return true
	if not enabled(state):
		return false
	if r == "platform" or r == "planetary":
		return full(state)
	if r == "module":
		return String(module_def(bid).get("mode", "")) != "complete" or full(state)
	return true


## Règles propres aux défenses, appelées par Economy.check_special : une station par système, les
## modules et plates-formes sur la colonie de la station, dans la limite des emplacements et des places.
static func check_build(state: GameState, empire_id: int, c: Colony, bid: String) -> String:
	var r := role(bid)
	if r == "":
		return ""
	if not building_allowed(state, bid):
		return "les défenses spatiales %s ne sont pas en jeu dans cette partie" % ("complètes" if enabled(state) else "")
	var sid := state.galaxy.get_planet(c.planet_id).system_id
	if demilitarized(state, sid, empire_id):
		return "système démilitarisé par traité : aucune défense ne peut y être bâtie"
	if r == "station":
		if not enabled(state):
			return ""
		var st := station(state, sid)
		if not st.is_empty() and int(st["pid"]) != c.planet_id:
			return "ce système a déjà sa station de défense (%s)" % String(tier_def(int(st["t"])).get("label", ""))
		for pid in state.galaxy.systems[sid].planet_ids:
			var o: Colony = state.colonies.get(pid)
			if o != null and o.planet_id != c.planet_id and o.owner == empire_id and STATION_BUILDINGS.has(o.construction):
				return "une station est déjà en chantier dans ce système"
		return ""
	if r == "module" or r == "platform":
		var st := station(state, sid)
		if st.is_empty() or int(st["pid"]) != c.planet_id:
			return "se bâtit sur la colonie qui porte la station de défense du système"
		var need := int(module_def(bid).get("tier", platform_def(bid).get("tier", 1)))
		if int(st["t"]) < need:
			return "il faut une station de palier %s" % ["", "I", "II", "III"][need]
		if r == "module":
			if bid == "module_mouilleur" and bool(talent(state, empire_id).get("no_mines", false)):
				return "votre peuple refuse de semer des mines : ce n'est pas une façon de se battre"
			if modules_count(state, c) >= int(tier_def(int(st["t"])).get("slots", 0)):
				return "plus d'emplacement de module libre (%d/%d)" % [modules_count(state, c), int(tier_def(int(st["t"])).get("slots", 0))]
			var fx := String(module_def(bid).get("fx", ""))
			if fx == "armor" or fx == "shield":
				if c.buildings.count(bid) + (1 if c.construction == bid else 0) >= int(cfg("core").get("stack_max", 3)):
					return "trois modules de ce type au plus"
		else:
			var places := int(platform_def(bid).get("places", 1))
			var used := capacity_used(state, sid)
			var cap := capacity(state, sid)
			if used + places > cap:
				return "plus de place pour une plate-forme (%d/%d)" % [used, cap]
	return ""


## Système démilitarisé par traité (clause de paix, prop. 31) : l'empire empire_id n'y bâtit plus de défense.
static func demilitarized(state: GameState, sid: int, empire_id: int) -> bool:
	if not enabled(state):
		return false
	var d: Dictionary = _sub(state, "demil").get(str(sid), {})
	return not d.is_empty() and int(d.get("o", -1)) == empire_id and int(d.get("t", 0)) > state.tick


## Modules (bâtis et en chantier) sur la colonie de la station.
static func modules_count(_state: GameState, c: Colony) -> int:
	var n := 0
	for b in c.buildings:
		if role(b) == "module":
			n += 1
	if c.construction != "" and role(c.construction) == "module":
		n += 1
	return n


## Prend-il un emplacement de planète ? Pas les modules ni les plates-formes (ils sont en orbite).
static func takes_slot(bid: String) -> bool:
	var r := role(bid)
	return r != "module" and r != "platform"


# --- Station et éléments -----------------------------------------------------------------------

## Station de défense d'un système : {"t": palier, "pid": planète, "o": propriétaire} ou {} (aucune,
## système libre ou occupé). Sans le réglage, aucune station au sens des défenses spatiales.
static func station(state: GameState, sid: int) -> Dictionary:
	if not enabled(state) or sid < 0:
		return {}
	var owner := state.system_owner(sid)
	if owner < 0 or WarPeace.occupier(state, sid) >= 0:
		return {}
	var best := {}
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c == null or c.owner != owner or not c.is_established():
			continue
		for b in c.buildings:
			var t := station_tier_of(b)
			if t > int(best.get("t", 0)):
				best = {"t": t, "pid": pid, "o": owner}
	if best.is_empty() and GameState.is_minor(owner):
		best = DefensesBridges.minor_station(state, sid, owner)  # peuples mineurs : selon leur âge
	return best


static func tier(state: GameState, sid: int) -> int:
	return int(station(state, sid).get("t", 0))


static func silenced(state: GameState, sid: int) -> bool:
	return enabled(state) and _sub(state, "sil").has(str(sid))


## La station tient-elle l'orbite (armée, pas réduite au silence) ? Elle interdit alors siège,
## bombardement et débarquement.
static func holds(state: GameState, sid: int) -> bool:
	return tier(state, sid) > 0 and not silenced(state, sid)


static func _station_colony(state: GameState, st: Dictionary) -> Colony:
	return state.colonies.get(int(st["pid"])) if not st.is_empty() else null


## Nombre de modules d'un type sur la station (pour le cœur, la réparation, le commandement...).
static func module_count(state: GameState, sid: int, fx: String) -> int:
	var st := station(state, sid)
	var c := _station_colony(state, st)
	if c == null:
		return 0
	var n := 0
	for b in c.buildings:
		if String(module_def(b).get("fx", "")) == fx:
			n += 1
	return n


## Grands senseurs : +vision par module sur la colonie de la station.
static func vision_bonus(c: Colony) -> int:
	return c.buildings.count("module_senseurs") * int(module_def("module_senseurs").get("vision", 1))


static func has_module(state: GameState, sid: int, bid: String) -> bool:
	var c := _station_colony(state, station(state, sid))
	return c != null and c.buildings.has(bid)


## Places de plates-formes : base du palier, population du système, technologies, commandement, talent.
static func capacity(state: GameState, sid: int) -> int:
	var st := station(state, sid)
	if st.is_empty():
		return 0
	var owner := int(st["o"])
	var n := int(tier_def(int(st["t"])).get("capacity", 0))
	var pop := 0
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == owner and c.is_colony():
			pop += c.population
	@warning_ignore("integer_division")
	n += pop / maxi(1, int(cfg("capacity").get("pop_per", 6)))
	n += Research.fx_int(state, owner, "defense_capacity")
	n += module_count(state, sid, "capacity") * int(module_def("module_commandement").get("capacity", 4))
	n += int(talent(state, owner).get("capacity", 0))
	n += DefensesBridges.capacity_bonus(state, sid, owner)
	return n


## Places occupées (plates-formes bâties et en chantier sur la colonie de la station).
static func capacity_used(state: GameState, sid: int) -> int:
	var c := _station_colony(state, station(state, sid))
	if c == null:
		return 0
	var n := 0
	for b in c.buildings:
		n += int(platform_def(b).get("places", 0))
	if c.construction != "":
		n += int(platform_def(c.construction).get("places", 0))
	return n


## Éléments de défense d'un système, dans un ordre fixe : cœur, modules armés, plates-formes,
## batteries et hangars planétaires, sentinelles. [{"k", "u", "kind", "b", "pid"}].
static func elements(state: GameState, sid: int) -> Array:
	var out: Array = []
	if not enabled(state):
		return out
	var owner := state.system_owner(sid)
	if owner < 0 or WarPeace.occupier(state, sid) >= 0:
		return out
	var st := station(state, sid)
	var sc := _station_colony(state, st)
	if sc != null and not silenced(state, sid):
		out.append({"k": "st", "u": core_unit_id(state, sid, st), "kind": "core", "b": String(tier_def(int(st["t"])).get("building", "")), "pid": sc.planet_id})
		var seen := {}
		var slots := int(tier_def(int(st["t"])).get("slots", 0))
		var count := 0
		for b in sc.buildings:
			if role(b) != "module":
				continue
			count += 1
			if count > slots:
				break
			var u := String(module_def(b).get("unit", ""))
			if u == "":
				continue
			var n := int(seen.get(b, 0))
			seen[b] = n + 1
			out.append({"k": "m:%s:%d" % [b, n], "u": u, "kind": "module", "b": b, "pid": sc.planet_id})
	if full(state):
		if sc != null:
			var seen_pf := {}
			for b in sc.buildings:
				var u := String(platform_def(b).get("unit", ""))
				if u == "":
					continue
				var n := int(seen_pf.get(b, 0))
				seen_pf[b] = n + 1
				out.append({"k": "pf:%s:%d" % [b, n], "u": u, "kind": "platform", "b": b, "pid": sc.planet_id})
		var sen: Dictionary = cfg("sentinels")
		for pid in state.galaxy.systems[sid].planet_ids:
			var c: Colony = state.colonies.get(pid)
			if c == null or c.owner != owner or not c.is_established():
				continue
			for b in c.buildings:
				var u := String(planetary_def(b).get("unit", ""))
				if u != "":
					out.append({"k": "pl:%d:%s" % [pid, b], "u": u, "kind": "planetary", "b": b, "pid": pid})
			if c.is_colony() and c.population >= int(sen.get("min_pop", 6)):
				var many := 2 if c.population >= int(sen.get("double_pop", 12)) else 1
				for i in many:
					out.append({"k": "se:%d:%d" % [pid, i], "u": "def_sentinelle", "kind": "sentinel", "b": "", "pid": pid})
	return out


## Un système a-t-il quelque chose qui se bat ? (Vite : sans liste d'éléments.)
static func has_any(state: GameState, sid: int) -> bool:
	if not enabled(state):
		return false
	var owner := state.system_owner(sid)
	if owner < 0:
		return false
	if GameState.is_minor(owner) and not DefensesBridges.minor_station(state, sid, owner).is_empty():
		return true
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c == null or c.owner != owner or not c.is_established():
			continue
		if full(state) and c.is_colony() and c.population >= int(cfg("sentinels").get("min_pop", 6)):
			return true
		for b in c.buildings:
			var r := role(b)
			if r == "station" or (r == "platform" or r == "planetary") and full(state):
				return true
	return false


static func hp_of(state: GameState, sid: int, key: String, unit_id: String) -> int:
	var d: Dictionary = _sub(state, "hp").get(str(sid), {})
	return int(d.get(key, Fleet.max_hp_of(unit_id)))


# --- Unités ------------------------------------------------------------------------------------

## Identifiant du cœur de station : def_st_<palier>_<blindage>_<bouclier>_<% PV>.
static func core_unit_id(state: GameState, sid: int, st: Dictionary) -> String:
	var core: Dictionary = cfg("core")
	var mx := int(core.get("stack_max", 3))
	var na := mini(mx, module_count(state, sid, "armor"))
	var ns := mini(mx, module_count(state, sid, "shield"))
	var owner := int(st["o"])
	var armor := na * int(core.get("armor_per", 10)) + DefensesBridges.core_armor(state, sid, owner)
	var shield := ns * int(core.get("shield_per", 20)) + int(talent(state, owner).get("core_shield", 0))
	var hp_pct := 100 + na * int(core.get("hp_pct_per", 20)) + int(talent(state, owner).get("core_hp_pct", 0))
	return "def_st_%d_%d_%d_%d" % [int(st["t"]), armor, shield, hp_pct]


## Fiche de combat d'une unité de défense (lue par GameData.ship).
static func unit(id: String) -> Dictionary:
	if _unit_cache.has(id):
		return _unit_cache[id]
	var out := {}
	if id.begins_with("def_st_"):
		var parts := id.split("_")
		if parts.size() >= 6:
			var t := int(parts[2])
			var base: Dictionary = cfg("core").get(str(t), {})
			if not base.is_empty():
				out = base.duplicate(true)
				out["hp"] = int(base["hp"]) * int(parts[5]) / 100
				out["armor"] = int(base.get("armor", 0)) + int(parts[3])
				out["shield"] = int(base.get("shield", 0)) + int(parts[4])
				out["label"] = String(tier_def(t).get("label", "Station"))
				out["plural"] = out["label"]
				out["line"] = "screen"
				out["role"] = "Défense"
				out["military"] = true
				out["speed"] = 0
				out["fixed"] = true
				out["station"] = t
	else:
		var u: Dictionary = cfg("units").get(id, {})
		if not u.is_empty():
			out = u.duplicate(true)
			out["role"] = "Défense"
			out["military"] = true
			out["speed"] = 0
			out["fixed"] = true
	_unit_cache[id] = out
	return out


static func is_fixed(f: Fleet) -> bool:
	return f != null and f.id <= FIXED_BASE


static func is_fixed_ship(ship_id: String) -> bool:
	return ship_id.begins_with("def_")


static func fixed_id(sid: int) -> int:
	return FIXED_BASE - sid


# --- Flotte fixe -------------------------------------------------------------------------------

## Flotte fixe du système (null s'il n'y a rien d'armé). Les clés des éléments sont gardées en méta.
static func fixed_fleet(state: GameState, sid: int) -> Fleet:
	var els := elements(state, sid)
	if els.is_empty():
		return null
	var f := Fleet.new()
	f.id = fixed_id(sid)
	f.owner = state.system_owner(sid)
	f.system_id = sid
	f.tactic = "rempart"
	f.fleet_name = "Défenses de %s" % state.galaxy.systems[sid].system_name
	var keys: Array = []
	var gens: Dictionary = _sub(state, "gen").get(str(sid), {})
	if int(_sub(state, "o").get(str(sid), f.owner)) != f.owner:
		gens = {}
	for el: Dictionary in els:
		var hp := hp_of(state, sid, String(el["k"]), String(el["u"]))
		if hp <= 0:
			continue
		f.ships.append(String(el["u"]))
		f.hp.append(hp)
		f.gen.append(int(gens.get(String(el["k"]), -1)))
		keys.append(el)
	if f.ships.is_empty() or not Combat.is_armed(f):
		return null
	f.set_meta("def_keys", keys)
	f.set_meta("def_ships", f.ships.duplicate())
	return f


## Ajoute aux flottes à l'arrêt de chaque système la flotte fixe du défenseur, quand une flotte
## hostile y stationne.
static func add_fixed(state: GameState, by_sys: Dictionary) -> void:
	if not enabled(state):
		return
	var sids := by_sys.keys()
	sids.sort()
	for k in sids:
		var sid := int(k)
		if not has_any(state, sid):
			continue
		var owner := state.system_owner(sid)
		var foe := false
		for g: Fleet in by_sys[k]:
			if g.owner != owner and (Combat.at_war(state, owner, g.owner) or g.owner == GameState.PIRATE_ID \
					or g.owner == GameState.FAUNA_ID and Fauna.hostile(state, g, owner) or g.owner == GameState.CRISIS_ID):
				foe = true
				break
		if not foe:
			continue
		var f := fixed_fleet(state, sid)
		if f != null:
			by_sys[k].append(f)


## Après les tirs du jour : PV recopiés, éléments détruits (station réduite au silence, plates-formes
## perdues), baies de réparation. Appelée par CombatSystem._battle_day.
static func after_battle_day(state: GameState, sid: int, fighters: Array, added: Array[Dictionary]) -> void:
	if not enabled(state):
		return
	for f: Fleet in fighters:
		if is_fixed(f):
			_write_back(state, sid, f, added)
	var rep := module_count(state, sid, "repair")
	if rep > 0 and holds(state, sid):
		var owner := state.system_owner(sid)
		var pct := rep * int(module_def("module_reparation").get("repair_pct", 3))
		for g: Fleet in fighters:
			if is_fixed(g) or not state.fleets.has(g.id) or not (g.owner == owner or Diplomacy.allied(state, owner, g.owner)):
				continue
			for i in g.ships.size():
				var mx := Fleet.max_hp_of(g.ships[i])
				@warning_ignore("integer_division")
				g.hp[i] = mini(mx, g.hp[i] + maxi(1, mx * pct / 100))


static func _write_back(state: GameState, sid: int, f: Fleet, added: Array[Dictionary]) -> void:
	var keys: Array = f.get_meta("def_keys", [])
	var orig: Array = f.get_meta("def_ships", [])
	var hpd := _sub(state, "hp")
	var sk := str(sid)
	if not hpd.has(sk):
		hpd[sk] = {}
	var d: Dictionary = hpd[sk]
	_sub(state, "o")[sk] = state.system_owner(sid)
	var j := 0
	var lost_platforms: Array = []
	var silenced_now := false
	for i in orig.size():
		var el: Dictionary = keys[i]
		var k := String(el["k"])
		if j < f.ships.size() and f.ships[j] == String(orig[i]):
			var mx := Fleet.max_hp_of(f.ships[j])
			if f.hp[j] >= mx:
				d.erase(k)
			else:
				d[k] = f.hp[j]
			j += 1
			continue
		match String(el["kind"]):
			"platform":
				lost_platforms.append(el)
			"core":
				d[k] = 0
				silenced_now = true
			_:
				d[k] = 0
	if silenced_now:
		_sub(state, "sil")[sk] = 1
		var owner := state.system_owner(sid)
		added.append(state.add_chronicle("La station de %s se tait : ses batteries sont éteintes, ses ponts en feu. Elle reprendra du service si on lui en laisse le temps." % state.galaxy.systems[sid].system_name,
				Espionage.private_to(state, [owner] + (Espionage.battle_sides(state.battles[sid]) if state.battles.has(sid) else []), sid)))
	for el: Dictionary in lost_platforms:
		var c: Colony = state.colonies.get(int(el["pid"]))
		if c == null:
			continue
		var at := c.buildings.rfind(String(el["b"]))
		if at >= 0:
			c.buildings.remove_at(at)
		_reindex_platforms(state, sid, String(el["b"]), String(el["k"]))
	if d.is_empty():
		hpd.erase(sk)


## Une plate-forme détruite : les PV des suivantes du même type glissent d'un rang.
static func _reindex_platforms(state: GameState, sid: int, bid: String, lost_key: String) -> void:
	var d: Dictionary = _sub(state, "hp").get(str(sid), {})
	var lost_n := int(lost_key.get_slice(":", 2))
	var n := lost_n
	while true:
		var nxt := "pf:%s:%d" % [bid, n + 1]
		var cur := "pf:%s:%d" % [bid, n]
		if d.has(nxt):
			d[cur] = d[nxt]
			d.erase(nxt)
		else:
			d.erase(cur)
			if not _any_key_above(d, bid, n + 1):
				break
		n += 1
	var g: Dictionary = _sub(state, "gen").get(str(sid), {})
	n = lost_n
	while g.has("pf:%s:%d" % [bid, n + 1]) or g.has("pf:%s:%d" % [bid, n]):
		var nxt := "pf:%s:%d" % [bid, n + 1]
		var cur := "pf:%s:%d" % [bid, n]
		if g.has(nxt):
			g[cur] = g[nxt]
			g.erase(nxt)
		else:
			g.erase(cur)
		n += 1


static func _any_key_above(d: Dictionary, bid: String, n: int) -> bool:
	for k in d:
		var s := String(k)
		if s.begins_with("pf:%s:" % bid) and int(s.get_slice(":", 2)) > n:
			return true
	return false


## Le défenseur reste-t-il présent à la fin d'une bataille grâce à ses défenses ? (Propriétaire, sinon -1.)
static func standing_owner(state: GameState, sid: int) -> int:
	if not has_any(state, sid):
		return -1
	var f := fixed_fleet(state, sid)
	return f.owner if f != null else -1


# --- Effets au combat --------------------------------------------------------------------------

## Couverture de station (prop. 9), posture de garde (prop. 23), talents : bonus de dégâts en points de %.
static func damage_pct(state: GameState, f: Fleet, sid: int) -> int:
	if not enabled(state):
		return 0
	var pct := 0
	var owner := state.system_owner(sid)
	if is_fixed(f):
		pct += int(talent(state, f.owner).get("damage_pct", 0))
		pct += DefensesBridges.fixed_damage_pct(state, sid, f.owner)
	elif owner >= 0 and (f.owner == owner or Diplomacy.allied(state, owner, f.owner)) and holds(state, sid):
		pct += cover_pct(state, sid)
	if not is_fixed(f) and f.standing_order == Fleet.ORDER_GUARD and f.patrol.size() >= 1 and int(f.patrol[0]) == sid:
		pct += int(cfg("guard").get("damage_pct", 10))
	return pct


static func cover_pct(state: GameState, sid: int) -> int:
	var t := tier(state, sid)
	if t <= 0:
		return 0
	var arr: Array = cfg("cover").get("pct", [0, 10, 10, 15])
	return int(arr[mini(t, arr.size() - 1)]) + int(talent(state, state.system_owner(sid)).get("cover_pct", 0))


## Dégâts d'un tir après défenses : couverture du camp visé (moins de dégâts subis), armes de siège
## contre les défenses fixes (prop. 26 : la stat de siège double les dégâts contre elles).
static func shot(state: GameState, sid: int, shooter: Fleet, si: int, target: Fleet, ti: int, dmg: int) -> int:
	if not enabled(state) or dmg <= 0:
		return dmg
	if is_fixed_ship(target.ships[ti]):
		if int(GameData.ship(shooter.ships[si]).get("siege", 0)) > 0:
			@warning_ignore("integer_division")
			dmg = dmg * int(data().get("siege_vs_defense_pct", 200)) / 100
	elif not is_fixed(target):
		var owner := state.system_owner(sid)
		if owner >= 0 and (target.owner == owner or Diplomacy.allied(state, owner, target.owner)) and holds(state, sid):
			@warning_ignore("integer_division")
			dmg = maxi(1, dmg * (100 - cover_pct(state, sid)) / 100)
	return dmg


# --- Siège, bombardement, débarquement ---------------------------------------------------------

## Bouclier planétaire du système : {"level", "max", "pts"} ou {}.
static func shield(state: GameState, sid: int) -> Dictionary:
	if not enabled(state):
		return {}
	var owner := state.system_owner(sid)
	if owner < 0 or WarPeace.occupier(state, sid) >= 0:
		return {}
	var best := {}
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c == null or c.owner != owner or not c.is_established():
			continue
		for b in c.buildings:
			var sd := shield_def(b)
			if not sd.is_empty() and int(sd["level"]) > int(best.get("level", 0)):
				best = {"level": int(sd["level"]), "max": int(sd["points"])}
	if best.is_empty():
		return best
	@warning_ignore("integer_division")
	best["max"] = int(best["max"]) * (100 + int(talent(state, owner).get("shield_pct", 0))) / 100
	best["pts"] = mini(int(best["max"]), int(_sub(state, "sh").get(str(sid), best["max"])))
	if DefensesBridges.cut(state, sid, "shield"):
		best["pts"] = 0
	return best


static func shield_up(state: GameState, sid: int) -> bool:
	var s := shield(state, sid)
	return not s.is_empty() and int(s["pts"]) > 0


## Le siège use d'abord le bouclier : renvoie la puissance de siège qui passe.
static func absorb_siege(state: GameState, sid: int, power: int) -> int:
	var s := shield(state, sid)
	if s.is_empty() or int(s["pts"]) <= 0 or power <= 0:
		return power
	var left := maxi(0, int(s["pts"]) - power)
	power -= int(s["pts"]) - left
	_sub(state, "sh")[str(sid)] = left
	return power


## Bombardement en % (Bouclier I : 50 ; Dôme debout : 0).
static func bombard_pct(state: GameState, sid: int) -> int:
	var s := shield(state, sid)
	if s.is_empty():
		return 100
	if int(s["level"]) >= 2 and int(s["pts"]) > 0:
		return 0
	return int(cfg("shields").get("bomb_pct_1", 50))


static func blocks_landing(state: GameState, sid: int) -> bool:
	var s := shield(state, sid)
	return not s.is_empty() and int(s["level"]) >= 2 and int(s["pts"]) > 0


## Raison qui interdit un débarquement ("" si rien).
static func landing_block(state: GameState, sid: int) -> String:
	if holds(state, sid):
		return "la station de défense tient encore l'orbite : réduisez-la au silence d'abord"
	if blocks_landing(state, sid):
		return "le dôme planétaire couvre le monde : usez-le par le siège d'abord"
	return ""


## Credo Survie (talent Bunkers) : le siège n'use pas la garnison sous un plancher.
static func garrison_floor(state: GameState, sid: int) -> void:
	var owner := state.system_owner(sid)
	var pct := int(talent(state, owner).get("garrison_floor_pct", 0))
	if pct <= 0 or tier(state, sid) <= 0:
		return
	@warning_ignore("integer_division")
	var floor_v := Combat.garrison_max(state, sid) * pct / 100
	if Combat.garrison(state, sid) < floor_v:
		state.garrisons[sid] = floor_v


# --- Mouvements : mines et inhibiteur ----------------------------------------------------------

## Une flotte entre dans un système : 0 rien, 1 les mines la ralentissent (fin du trajet du jour),
## 2 l'inhibiteur la retient (trajet annulé).
static func on_enter(state: GameState, f: Fleet, sid: int) -> int:
	if not enabled(state) or not full(state):
		return 0
	var out := 0
	var md: Dictionary = _sub(state, "mines").get(str(sid), {})
	if not md.is_empty() and int(md.get("d", 0)) > 0 and _foe_of(state, int(md["o"]), f):
		if _mine_hits(state, f, sid, int(md["o"]), int(md["d"])):
			out = 1
	if inhibits(state, sid) and _foe_of(state, state.system_owner(sid), f):
		out = 2
	return out


static func _foe_of(state: GameState, owner: int, f: Fleet) -> bool:
	if owner < 0 or f.owner == owner:
		return false
	if f.owner == GameState.PIRATE_ID or f.owner == GameState.CRISIS_ID:
		return true
	if f.owner == GameState.FAUNA_ID:
		return Fauna.hostile(state, f, owner)
	return Combat.at_war(state, owner, f.owner)


static func inhibits(state: GameState, sid: int) -> bool:
	return full(state) and holds(state, sid) and tier(state, sid) >= 2 and has_module(state, sid, "module_inhibiteur") \
			and not DefensesBridges.cut(state, sid, "inhib")


static func _mine_hits(state: GameState, f: Fleet, sid: int, owner: int, density: int) -> bool:
	var mc: Dictionary = cfg("mines")
	@warning_ignore("integer_division")
	var chance := density / maxi(1, int(mc.get("hit_div", 2)))
	chance = chance * (100 + int(talent(state, owner).get("mine_hit_pct", 0))) / 100
	var hits := 0
	for i in f.ships.size():
		if state.rng.randi_range(0, 99) >= chance:
			continue
		var mx := Fleet.max_hp_of(f.ships[i])
		@warning_ignore("integer_division")
		var dmg := mx * int(mc.get("dmg_pct", {}).get(Combat.ship_size(f.ships[i]), 20)) / 100
		f.hp[i] = maxi(1, f.hp[i] - dmg)  # une mine estropie, elle ne détruit pas
		hits += 1
	if hits > 0:
		state.add_chronicle("Champ de mines à %s : %d vaisseau%s de %s touché%s. Les démineurs auront du travail." % [
				state.galaxy.systems[sid].system_name, hits, "x" if hits > 1 else "", state.get_empire(f.owner).short_name() if state.get_empire(f.owner) else "l'intrus", "s" if hits > 1 else ""],
				Espionage.private_to(state, [owner, f.owner], sid))
	return hits > 0


static func mines(state: GameState, sid: int) -> Dictionary:
	return _sub(state, "mines").get(str(sid), {}) if enabled(state) else {}


# --- Jour par jour -----------------------------------------------------------------------------

## Réparations, boucliers, mines, garde, propriétaires. Appelée chaque jour par la simulation.
static func daily(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if not enabled(state):
		return added
	_repairs(state, added)
	_shields(state)
	if full(state):
		_mines_daily(state)
		_guards(state)
	DefensesBridges.daily(state, added)
	return added


static func _quiet(state: GameState, sid: int) -> bool:
	return not state.battles.has(sid) and not state.sieges.has(sid)


static func _repairs(state: GameState, added: Array[Dictionary]) -> void:
	var hpd := _sub(state, "hp")
	var sil := _sub(state, "sil")
	var days := maxi(1, int(cfg("repair").get("days", 60)))
	var keys := hpd.keys()
	for k in sil.keys():
		if not hpd.has(k):
			keys.append(k)
	keys.sort()
	for k in keys:
		var sid := int(k)
		var owner := state.system_owner(sid)
		if owner < 0 or not has_any(state, sid):
			hpd.erase(k)
			sil.erase(k)
			continue
		if int(_sub(state, "o").get(k, owner)) != owner:
			_sub(state, "gen").erase(k)
			_sub(state, "o")[k] = owner
		if not _quiet(state, sid):
			continue
		var x := int(talent(state, owner).get("repair_x", 1)) + DefensesBridges.repair_bonus(state, sid, owner)
		var d: Dictionary = hpd.get(k, {})
		var st := station(state, sid)
		var units := {}
		if not st.is_empty():
			units["st"] = core_unit_id(state, sid, st)
		for el: Dictionary in _all_elements(state, sid):
			units[String(el["k"])] = String(el["u"])
		for ek in d.keys():
			var u := String(units.get(ek, ""))
			if u == "":
				d.erase(ek)
				continue
			var mx := Fleet.max_hp_of(u)
			@warning_ignore("integer_division")
			var v := int(d[ek]) + maxi(1, mx * x / days)
			if v >= mx:
				d.erase(ek)
			else:
				d[ek] = v
		if d.is_empty():
			hpd.erase(k)
		if sil.has(k) and not d.has("st"):
			sil.erase(k)
			added.append(state.add_chronicle("La station de %s reprend du service : on rallume les batteries une à une." % state.galaxy.systems[sid].system_name,
					Espionage.private_to(state, [owner], sid)))


## Tous les éléments, station comprise même réduite au silence (pour les réparations).
static func _all_elements(state: GameState, sid: int) -> Array:
	var sil := _sub(state, "sil")
	var k := str(sid)
	if not sil.has(k):
		return elements(state, sid)
	sil.erase(k)
	var out := elements(state, sid)
	sil[k] = 1
	return out


static func _shields(state: GameState) -> void:
	var sh := _sub(state, "sh")
	var regen := int(cfg("shields").get("regen", 5))
	var keys := sh.keys()
	keys.sort()
	for k in keys:
		var sid := int(k)
		var s := shield(state, sid)
		if s.is_empty():
			sh.erase(k)
			continue
		if state.sieges.has(sid):
			continue
		var v := int(sh[k]) + regen
		if v >= int(s["max"]):
			sh.erase(k)
		else:
			sh[k] = v


static func _mines_daily(state: GameState) -> void:
	var mc: Dictionary = cfg("mines")
	var mx := int(mc.get("max", 100))
	var md := _sub(state, "mines")
	var month := state.tick % int(GameData.rules()["month_days"]) == 0
	# Mouilleurs de station : chaque mois.
	if month:
		for sid in range(state.galaxy.systems.size()):
			if not has_module(state, sid, "module_mouilleur") or tier(state, sid) < 2:
				continue
			var owner := state.system_owner(sid)
			var add := module_count(state, sid, "mines") * int(module_def("module_mouilleur").get("mines_per_month", 10))
			_lay(state, sid, owner, add, mx)
	# Vaisseaux mouilleurs et démineurs à l'arrêt ; armes à rayons qui balaient.
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.is_moving():
			continue
		var sid := f.system_id
		var lay := 0
		var sweep := 0
		var beams := 0
		for s in f.ships:
			var sd := GameData.ship(s)
			if sd.get("minelayer", false):
				lay += 1
			if sd.get("sweeper", false):
				sweep += 1
			beams += int(Combat.weapons(s).get("beam", 0))
		var cur: Dictionary = md.get(str(sid), {})
		if lay > 0 and not bool(talent(state, f.owner).get("no_mines", false)):
			var owner := state.system_owner(sid)
			if owner == f.owner or (owner >= 0 and Combat.at_war(state, owner, f.owner)) or owner < 0:
				if cur.is_empty() or int(cur["o"]) == f.owner:
					_lay(state, sid, f.owner, lay * int(mc.get("lay_per_ship", 2)), mx)
		if not cur.is_empty() and _foe_of(state, int(cur["o"]), f):
			var gone := sweep * int(mc.get("sweep_per_ship", 4))
			if beams > 0:
				gone += maxi(1, beams * int(mc.get("beam_sweep", 1)) / 100)
			if gone > 0:
				cur["d"] = maxi(0, int(cur["d"]) - gone)
				if int(cur["d"]) <= 0:
					md.erase(str(sid))
	# Usure annuelle.
	if state.tick % 360 == 0:
		for k in md.keys():
			var cur: Dictionary = md[k]
			var pct := int(mc.get("decay_pct", 5))
			if DefensesBridges.in_nebula(state, int(k)):
				pct *= int(mc.get("nebula_x", 3))
			@warning_ignore("integer_division")
			cur["d"] = int(cur["d"]) - maxi(1, int(cur["d"]) * pct / 100)
			if int(cur["d"]) <= 0:
				md.erase(k)


static func _lay(state: GameState, sid: int, owner: int, add: int, mx: int) -> void:
	if add <= 0 or owner < 0 or DefensesBridges.mines_banned(state, owner):
		return
	var md := _sub(state, "mines")
	var cur: Dictionary = md.get(str(sid), {})
	if not cur.is_empty() and int(cur["o"]) != owner:
		return  # un champ à la fois : celui d'un autre empire doit d'abord être balayé
	md[str(sid)] = {"o": owner, "d": mini(mx, int(cur.get("d", 0)) + add)}


## Posture de garde : une flotte gardienne à l'arrêt hors de son système y retourne.
static func _guards(state: GameState) -> void:
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.standing_order != Fleet.ORDER_GUARD or f.is_moving() or f.patrol.is_empty():
			continue
		var home := int(f.patrol[0])
		if f.system_id == home:
			continue
		var plan := Fleets.plan_route(state, f, home)
		if (plan.get("path", []) as Array).is_empty():
			continue
		f.system_id = int(plan["system"])
		f.path.assign(plan["path"])
		f.progress = int(plan["progress"])


# --- Ordres ------------------------------------------------------------------------------------

## Ordres : "guard" (flotte a garde le système où elle est), "unguard" (flotte a), "modernize"
## (système a : défenses remises aux marques du jour contre 25 % de leur coût).
static func check(state: GameState, player: int, act: String, a: int, _b: int, _s: String) -> String:
	if not enabled(state):
		return "les défenses spatiales ne sont pas en jeu dans cette partie"
	match act:
		"guard", "unguard":
			if not full(state):
				return "la posture de garde demande les défenses spatiales complètes"
			var f: Fleet = state.fleets.get(a)
			if f == null or f.owner != player:
				return "cette flotte ne vous appartient pas"
			if act == "guard":
				if f.is_moving():
					return "la flotte doit être à l'arrêt dans le système à garder"
				if f.standing_order == Fleet.ORDER_GUARD and not f.patrol.is_empty() and int(f.patrol[0]) == f.system_id:
					return "la flotte garde déjà ce système"
			elif f.standing_order != Fleet.ORDER_GUARD:
				return "cette flotte ne garde aucun système"
			return ""
		"modernize":
			if a < 0 or a >= state.galaxy.systems.size() or state.system_owner(a) != player:
				return "ce système ne vous appartient pas"
			var cost := modernize_cost(state, a)
			if cost.is_empty():
				return "les défenses de ce système sont déjà à jour"
			if not Economy.can_afford(state.get_empire(player), cost):
				return "ressources insuffisantes (il faut %s)" % GameData.format_amounts(cost)
			return ""
	return "ordre inconnu : %s" % act


static func apply(state: GameState, player: int, act: String, a: int, b: int, s: String) -> void:
	if check(state, player, act, a, b, s) != "":
		return
	match act:
		"guard":
			var f: Fleet = state.fleets[a]
			f.standing_order = Fleet.ORDER_GUARD
			f.patrol.assign([f.system_id])
		"unguard":
			var f: Fleet = state.fleets[a]
			f.standing_order = ""
			f.patrol.clear()
		"modernize":
			var cost := modernize_cost(state, a)
			var e := state.get_empire(player)
			for r in cost:
				e.resources[r] = int(e.resources.get(r, 0)) - int(cost[r])
			var g := {}
			var now := Research.mark_gen(state, player)
			for el: Dictionary in _all_elements(state, a):
				g[String(el["k"])] = now
			_sub(state, "gen")[str(a)] = g
			_sub(state, "o")[str(a)] = player


## Éléments en retard sur les marques de l'empire, et coût de leur remise à niveau.
static func outdated(state: GameState, sid: int) -> Array:
	var out: Array = []
	var owner := state.system_owner(sid)
	var gens: Dictionary = _sub(state, "gen").get(str(sid), {})
	for el: Dictionary in _all_elements(state, sid):
		var g := int(gens.get(String(el["k"]), -1))
		if g >= 0 and Research.gen_outdated(state, owner, g):
			out.append(el)
	return out


static func modernize_cost(state: GameState, sid: int) -> Dictionary:
	var cost := {}
	var owner := state.system_owner(sid)
	for el: Dictionary in outdated(state, sid):
		var bid := String(el["b"])
		if bid == "":
			continue
		var bc := Economy.building_cost(state, owner, bid)
		for r in bc:
			@warning_ignore("integer_division")
			cost[r] = int(cost.get(r, 0)) + maxi(1, int(bc[r]) * int(data().get("modernize_pct", 25)) / 100)
	return cost


## Un bâtiment de défense vient d'être achevé : il garde les marques du jour (prop. 14).
static func on_built(state: GameState, c: Colony, bid: String) -> void:
	if not enabled(state) or role(bid) == "" or role(bid) == "shield":
		return
	var sid := state.galaxy.get_planet(c.planet_id).system_id
	var now := Research.mark_gen(state, c.owner)
	var g: Dictionary = _sub(state, "gen").get(str(sid), {})
	if int(_sub(state, "o").get(str(sid), c.owner)) != c.owner:
		g = {}
	for el: Dictionary in _all_elements(state, sid):
		var k := String(el["k"])
		if not g.has(k):
			g[k] = now
	if role(bid) == "station":
		g["st"] = now
	_sub(state, "gen")[str(sid)] = g
	_sub(state, "o")[str(sid)] = c.owner
	# Un palier de plus remet le cœur à neuf.
	if role(bid) == "station":
		var hp: Dictionary = _sub(state, "hp").get(str(sid), {})
		hp.erase("st")
		_sub(state, "sil").erase(str(sid))


# --- Talents -----------------------------------------------------------------------------------

static func talent(state: GameState, eid: int) -> Dictionary:
	var e := state.get_empire(eid) if eid >= 0 else null
	if e == null or e.is_npc():
		return {}
	var ck := "%s:%s" % [e.faction_id, str(e.faction().get("species", {}))]
	if _talent_cache.has(ck):
		return _talent_cache[ck]
	var out := {}
	var sp := FactionTraits.species(e.faction())
	var table: Dictionary = cfg("talents")
	for layer in LAYERS:
		var t: Dictionary = table.get(layer, {})
		if t.is_empty():
			continue
		var values: Array = sp.get("traits", []) if layer == "traits" else [String(sp.get(layer, ""))]
		for v in values:
			if not t.has(String(v)):
				continue
			var d: Dictionary = t[String(v)]
			out["labels"] = (out.get("labels", []) as Array) + [[String(d["label"]), String(d["text"])]]
			for k in d:
				if k != "label" and k != "text":
					out[k] = d[k]
	_talent_cache[ck] = out
	return out


## Coût des bâtiments de défense (talent Bâtisseurs de forteresses), en points de %.
static func cost_pct(state: GameState, eid: int, bid: String) -> int:
	if role(bid) != "station" and role(bid) != "module":
		return 0
	return int(talent(state, eid).get("cost_pct", 0))


# --- Interface ---------------------------------------------------------------------------------

## Lignes de la fiche de système (prop. 25 : l'ordre d'assaut et où en est l'assaillant).
static func system_lines(state: GameState, sid: int) -> Array[String]:
	var out: Array[String] = []
	if not enabled(state):
		return out
	var st := station(state, sid)
	if not st.is_empty():
		var t := int(st["t"])
		var line := "%s" % String(tier_def(t).get("label", "Station"))
		if silenced(state, sid):
			var hp := hp_of(state, sid, "st", core_unit_id(state, sid, st))
			@warning_ignore("integer_division")
			line += " : réduite au silence (%d %%)" % (hp * 100 / maxi(1, Fleet.max_hp_of(core_unit_id(state, sid, st))))
		else:
			var hp := hp_of(state, sid, "st", core_unit_id(state, sid, st))
			@warning_ignore("integer_division")
			line += " : tient l'orbite (%d %%)" % (hp * 100 / maxi(1, Fleet.max_hp_of(core_unit_id(state, sid, st))))
		var c := _station_colony(state, st)
		line += ", modules %d/%d" % [modules_count(state, c), int(tier_def(t).get("slots", 0))]
		if full(state):
			line += ", plates-formes %d/%d" % [capacity_used(state, sid), capacity(state, sid)]
		out.append(line)
		if inhibits(state, sid):
			out.append("Inhibiteur de saut actif")
	var s := shield(state, sid)
	if not s.is_empty():
		out.append("%s : %d / %d" % ["Dôme planétaire" if int(s["level"]) >= 2 else "Bouclier planétaire", int(s["pts"]), int(s["max"])])
	var m := mines(state, sid)
	if not m.is_empty():
		out.append("Champ de mines (%s) : densité %d" % [state.get_empire(int(m["o"])).short_name() if state.get_empire(int(m["o"])) else "?", int(m["d"])])
	if not out.is_empty() or Combat.is_besieged(state, sid):
		out.append("Assaut : %s" % assault_stage(state, sid))
	return out


## Où en est l'assaut (prop. 25) : flottes, station, bouclier, fortifications, garnison, débarquement.
static func assault_stage(state: GameState, sid: int) -> String:
	var owner := state.system_owner(sid)
	for f in Fleets.fleets_at(state, sid, owner):
		if Combat.is_armed(f):
			return "1. les flottes du défenseur tiennent"
	if holds(state, sid):
		return "2. la station tient l'orbite"
	if shield_up(state, sid):
		return "3. le bouclier planétaire tient"
	if Ground.full(state) and GroundSiege.fort(state, sid) > 0:
		return "4. les fortifications tiennent"
	if Combat.garrison(state, sid) > 0:
		return "4. la garnison tient"
	return "5. le monde est ouvert au débarquement"


## Puissance des défenses fixes d'un système (pour l'IA).
static func power(state: GameState, sid: int) -> int:
	var f := fixed_fleet(state, sid)
	return Combat.fleet_power(f) if f != null else 0
