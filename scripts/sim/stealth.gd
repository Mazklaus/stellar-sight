class_name Stealth
extends RefCounted
## Furtivité et détection (étude du 2026-11-16, 41 propositions validées ; data/stealth.json).
##
## Deux niveaux de 0 à 5 : le CAMOUFLAGE d'une flotte (ce qui la cache) et la DÉTECTION d'un empire
## (ce qui la perce). La PORTÉE reste la vision en sauts (Fleets.vision, claim_vision). Une flotte est
## vue par un empire si son système est dans sa vision (Fleets.visible_systems) ET si l'une de ses
## sources (colonie, flotte, balise, ou celles d'un allié) couvre ce système avec une détection au moins
## égale au camouflage. Camouflage 0 = vue comme avant ; détection de base 1 partout (0 dans une
## tempête de radiations).
##
## Camouflage d'une flotte = celui de son vaisseau le plus faible (module Voile de camouflage I-III :
## 2 à 4, un point au-dessus des yeux nus ; stat "cloak" des modèles), ou 3 pour un peuple voilé (le Voile du Chœur, prop. 28) ; s'y ajoutent le
## terrain, la posture Silence radio, le trait d'amiral Fantôme et les talents de peuple, plafond 5.
## Le voile tombe au premier tir (bataille, siège, débarquement) et se recharge en 30 jours ; il coûte
## de la vitesse. Une flotte cachée ne déclenche ni intrusion ni bataille, traverse blocus, mines et
## inhibiteurs ; en posture Embuscade, elle engage les ennemis présents et frappe plus fort le premier
## jour.
##
## Degrés de connaissance (mode Complète) : 3 détaillée (sur place, ou 2 points d'avance), 2 identifiée
## (à 1 saut d'une source), 1 contact (au-delà : une taille, pas d'empire). Le brouilleur plafonne à 2.
##
## Réglage « Furtivité » : Complète, Simple (niveaux sans degrés ni postures), Désactivée (state.stealth
## vide : tout est vu comme avant, seul Veil cache le Chœur). Sans l'option (tests, bancs) : désactivée.
##
## État : state.stealth = {"mode", "off": {"fid": jour de fin de recharge}, "pose": {"fid": posture},
##  "bc": {"sid": {"o": propriétaire, "d": jour de pose}}, "codes": {"a:b": jour de fin},
##  "amb": {"eid": dernier jour où il a subi une embuscade}, "dk": {"eid": nombre de leurres posés},
##  "st": {"eid": {"spectre": systèmes rivaux traversés caché, "found": flottes cachées repérées}},
##  "seen": {"fid:eid": 1} (flotte cachée déjà repérée par cet empire, pour les hauts faits et griefs)}.

const LAYERS := ["traits", "registre", "archetype", "gouvernement", "credo"]

static var _talent_cache := {}
## Caches valables pour un jour de simulation (vidés par invalidate(), appelée au début de
## FleetSystem.update_exploration et après chaque ordre qui change une posture).
static var _cache_key := ""
static var _cloak_cache := {}
static var _src_cache := {}
static var _dist_cache := {}
## Embuscades du jour (flottes cachées qui engagent), remplies par filter_battle.
static var _ambushers := {}


static func data() -> Dictionary:
	return GameData.stealth()


static func cfg(section: String) -> Dictionary:
	return data().get(section, {})


static func mode_defs() -> Array:
	return data().get("modes", [])


static func default_mode() -> String:
	return String(data().get("default_mode", "complete"))


static func mode(state: GameState) -> String:
	return String(state.stealth.get("mode", "desactivee"))


static func enabled(state: GameState) -> bool:
	return state != null and not state.stealth.is_empty()


static func full(state: GameState) -> bool:
	return enabled(state) and mode(state) == "complete"


static func mode_label(state: GameState) -> String:
	for m: Dictionary in mode_defs():
		if String(m["id"]) == mode(state):
			return String(m["label"])
	return "Désactivée"


static func max_level() -> int:
	return int(data().get("max_level", 5))


# --- Réglage, sauvegarde -----------------------------------------------------------------------

static func setup(state: GameState, mode_id: String) -> void:
	state.stealth = {}
	invalidate()
	var ok := false
	for m: Dictionary in mode_defs():
		if String(m["id"]) == mode_id:
			ok = true
	if not ok or mode_id == "desactivee":
		return
	state.stealth = {"mode": mode_id, "off": {}, "pose": {}, "bc": {}, "codes": {}, "amb": {}, "dk": {}, "st": {}, "seen": {}}


static func worth_saving(state: GameState) -> bool:
	return enabled(state)


static func to_dict(state: GameState) -> Dictionary:
	return state.stealth.duplicate(true)


static func from_dict(state: GameState, d: Dictionary) -> void:
	invalidate()
	if d.is_empty():
		state.stealth = {}
		return
	state.stealth = d.duplicate(true)
	for k in ["off", "pose", "bc", "codes", "amb", "dk", "st", "seen"]:
		if not state.stealth.has(k):
			state.stealth[k] = {}


static func _sub(state: GameState, k: String) -> Dictionary:
	if not state.stealth.has(k):
		state.stealth[k] = {}
	return state.stealth[k]


static func invalidate() -> void:
	_cache_key = ""
	_cloak_cache.clear()
	_src_cache.clear()
	_dist_cache.clear()


static func _fresh(state: GameState) -> void:
	var k := "%d:%d" % [state.get_instance_id(), state.tick]
	if k != _cache_key:
		_cache_key = k
		_cloak_cache.clear()
		_src_cache.clear()
		_dist_cache.clear()


# --- Talents de peuple -------------------------------------------------------------------------

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
					out[k] = int(out.get(k, 0)) + int(d[k])
	_talent_cache[ck] = out
	return out


static func talent_labels(state: GameState, eid: int) -> Array:
	return talent(state, eid).get("labels", [])


# --- Postures ----------------------------------------------------------------------------------

static func posture(state: GameState, f: Fleet) -> String:
	if not enabled(state) or f == null:
		return ""
	var p := String(_sub(state, "pose").get(str(f.id), ""))
	if p != "" and bool(cfg("postures").get(p, {}).get("full", false)) and not full(state):
		return ""
	return p


static func posture_label(p: String) -> String:
	return String(cfg("postures").get(p, {}).get("label", "Aucune"))


## Postures proposées pour une flotte (selon le mode).
static func postures(state: GameState) -> Array[String]:
	var out: Array[String] = [""]
	for k in ["silence", "scan", "ambush"]:
		if not bool(cfg("postures").get(k, {}).get("full", false)) or full(state):
			out.append(k)
	return out


# --- Camouflage --------------------------------------------------------------------------------

static func ship_cloak(ship_id: String) -> int:
	return mini(int(data().get("module_max", 4)), int(GameData.ship(ship_id).get("cloak", 0)))


static func ship_detect(ship_id: String) -> int:
	return mini(int(data().get("module_max", 4)) - 1, int(GameData.ship(ship_id).get("detect", 0)))


static func _non_empire_kind(owner: int) -> String:
	if owner == GameState.PIRATE_ID:
		return "pirates"
	if owner == GameState.CRISIS_ID:
		return "crisis"
	if owner == GameState.FAUNA_ID:
		return "fauna"
	if owner >= GameState.ANCIENT_BASE and owner < GameState.ANCIENT_BASE + GameState.ANCIENT_MAX:
		return "ancients"
	return ""


## Camouflage de base : celui du vaisseau le plus faible (marque du voile), 3 pour un peuple voilé,
## celui des pirates pour eux, celui des créatures camouflées (champ "cloak" de l'unité).
static func base_cloak(state: GameState, f: Fleet) -> int:
	if f == null or f.ships.is_empty():
		return 0
	if f.owner == GameState.PIRATE_ID and full(state):
		return int(cfg("non_empires").get("pirate_cloak", 2))
	if f.owner >= 0 and f.owner < state.empires.size() and Veil.is_veiled(state, f.owner):
		return 3
	var lo := 99
	for s in f.ships:
		lo = mini(lo, ship_cloak(s))
	if lo > 0 and lo < 99 and f.owner >= 0:
		lo += Genetics.cloak_bonus(state, f.owner)  # Résonance du Voile (traits façonnés)
	return maxi(0, lo)


## Le voile est-il levé (pas tombé au feu, pas en balayage actif) ?
static func veil_up(state: GameState, f: Fleet) -> bool:
	if not enabled(state) or base_cloak(state, f) <= 0:
		return false
	if posture(state, f) == "scan":
		return false
	return int(_sub(state, "off").get(str(f.id), -1)) <= state.tick


## Jours avant que le voile se relève (0 s'il est levé ou s'il n'y en a pas).
static func recharge_left(state: GameState, f: Fleet) -> int:
	if not enabled(state):
		return 0
	return maxi(0, int(_sub(state, "off").get(str(f.id), -1)) - state.tick)


static func _terrain_cloak(state: GameState, f: Fleet, sid: int) -> int:
	if not Terrain.active(state) or sid < 0:
		return 0
	var t: Dictionary = cfg("terrain")
	var n := 0
	for tid in Terrain.at(state, sid):
		var d: Dictionary = t.get(String(tid), {})
		if d.is_empty():
			continue
		if bool(d.get("rest", false)) and f.is_moving():
			continue
		n = maxi(n, int(d.get("cloak", 0)))
	return n


## Camouflage effectif d'une flotte (0 à 5).
static func cloak(state: GameState, f: Fleet) -> int:
	if not enabled(state) or f == null or f.id < 0:
		return 0
	_fresh(state)
	if _cloak_cache.has(f.id):
		return int(_cloak_cache[f.id])
	var c := 0
	var p := posture(state, f)
	if p != "scan":
		var up := veil_up(state, f)
		if up:
			c = base_cloak(state, f)
			c += int(talent(state, f.owner).get("cloak", 0))
			c += StealthBridges.hero_cloak(state, f)
		c += _terrain_cloak(state, f, Fleets.vision_center(state, f))
		if p == "silence":
			c += int(cfg("postures").get("silence", {}).get("cloak", 1))
	c = clampi(c, 0, max_level())
	_cloak_cache[f.id] = c
	return c


## Flotte cachée qui reste à l'écart des batailles et des sièges (voile levé, pas en Embuscade).
static func lurking(state: GameState, f: Fleet) -> bool:
	return veil_up(state, f) and posture(state, f) != "ambush"


## Le voile tombe (tir, siège, débarquement) : recharge de 30 jours.
static func drop(state: GameState, f: Fleet) -> void:
	if not enabled(state) or f == null or f.id < 0 or base_cloak(state, f) <= 0:
		return
	var off := _sub(state, "off")
	off[str(f.id)] = maxi(int(off.get(str(f.id), -1)), state.tick + int(cfg("cloak").get("recharge_days", 30)))
	_cloak_cache.erase(f.id)


## Signature de transit (pour les portails de saut et autres passages bruyants) : le passage
## illumine la flotte, son voile tombe comme au premier tir. Sans effet si la furtivité n'est pas en jeu.
static func on_transit(state: GameState, f: Fleet) -> void:
	drop(state, f)


## Vitesse en % (voile levé : malus selon la marque ; Silence radio : moitié).
static func speed_pct(state: GameState, f: Fleet) -> int:
	if not enabled(state) or f == null:
		return 100
	var pct := 100
	if veil_up(state, f) and not Veil.is_veiled(state, f.owner) and f.owner != GameState.PIRATE_ID:
		pct = int(cfg("cloak").get("speed_pct", {}).get(str(clampi(base_cloak(state, f), 2, 4)), 100))
	if posture(state, f) == "silence":
		@warning_ignore("integer_division")
		pct = pct * int(cfg("postures").get("silence", {}).get("speed_pct", 50)) / 100
	return pct


## Portée de vision d'une flotte en sauts (Silence radio : son système ; Balayage actif : +1).
static func vision_of(state: GameState, f: Fleet) -> int:
	var v := Fleets.vision(f)
	if not full(state):
		return v
	match posture(state, f):
		"silence":
			return 0
		"scan":
			return v + int(cfg("postures").get("scan", {}).get("range", 1))
	return v


## Vision des balises d'écoute de eid, ajoutée aux sources de vision {système: portée} (Fleets).
static func beacon_vision(state: GameState, eid: int, src: Dictionary) -> void:
	if not full(state):
		return
	var r := int(cfg("beacon").get("range", 1))
	for k in _sub(state, "bc"):
		if int(state.stealth["bc"][k].get("o", -1)) == eid:
			src[int(k)] = maxi(int(src.get(int(k), -1)), r)


# --- Détection ---------------------------------------------------------------------------------

## Détection d'une flotte (sur toute sa portée).
static func fleet_detect(state: GameState, f: Fleet) -> int:
	var best := 0
	for s in f.ships:
		best = maxi(best, ship_detect(s))
	var d := int(data().get("base_detection", 1)) + best + _empire_detect(state, f.owner) + StealthBridges.hero_detect(state, f)
	if posture(state, f) == "scan":
		d += int(cfg("postures").get("scan", {}).get("detect", 1))
	return d


## Détection ajoutée à toutes les sources d'un empire (technologies, talents).
static func _empire_detect(state: GameState, eid: int) -> int:
	if eid < 0 or eid >= state.empires.size():
		return 0
	return Research.fx_int(state, eid, "detect") + int(talent(state, eid).get("detect", 0)) + Genetics.detect_bonus(state, eid)


## Sources de détection d'un empire : [[système, portée, détection, à l'arrêt (1/0)]...].
static func sources(state: GameState, eid: int) -> Array:
	_fresh(state)
	if _src_cache.has(eid):
		return _src_cache[eid]
	var out: Array = []
	var base := int(data().get("base_detection", 1)) + _empire_detect(state, eid)
	var claim := int(GameData.rules().get("claim_vision", 1)) + Research.fx_int(state, eid, "claim_vision")
	var per_sys := {}
	var bcfg: Dictionary = cfg("sources").get("buildings", {})
	var mcfg: Dictionary = cfg("sources").get("station_modules", {})
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != eid:
			continue
		var sid := state.galaxy.get_planet(pid).system_id
		var det := base
		var rng := claim
		for b in bcfg:
			if c.buildings.has(String(b)):
				det += int(bcfg[b].get("detect", 0))
		if Defenses.enabled(state):
			for m in mcfg:
				var n := c.buildings.count(String(m))
				if n > 0:
					det += int(mcfg[m].get("detect", 0))
					rng += int(mcfg[m].get("range", 0))
		var old: Array = per_sys.get(sid, [])
		if old.is_empty() or int(old[2]) < det or int(old[1]) < rng:
			per_sys[sid] = [sid, maxi(rng, int(old[1]) if not old.is_empty() else 0), maxi(det, int(old[2]) if not old.is_empty() else 0), 1]
	var keys := per_sys.keys()
	keys.sort()
	for k in keys:
		out.append(per_sys[k])
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.owner != eid:
			continue
		out.append([Fleets.vision_center(state, f), vision_of(state, f), fleet_detect(state, f), 0 if f.is_moving() else 1])
	if full(state):
		var bc: Dictionary = cfg("beacon")
		for k in _sub(state, "bc"):
			var b: Dictionary = state.stealth["bc"][k]
			if int(b.get("o", -1)) == eid:
				out.append([int(k), int(bc.get("range", 1)), int(bc.get("detect", 1)) + _empire_detect(state, eid), 0])
	_src_cache[eid] = out
	return out


## Distances (en sauts) depuis sid, jusqu'à maxr.
static func _dist(state: GameState, sid: int, maxr: int) -> Dictionary:
	_fresh(state)
	var key := sid * 16 + mini(maxr, 15)
	if _dist_cache.has(key):
		return _dist_cache[key]
	var out := {sid: 0}
	var frontier: Array[int] = [sid]
	for r in maxr:
		var nxt: Array[int] = []
		for s in frontier:
			for n in state.galaxy.systems[s].neighbors:
				if not out.has(n):
					out[n] = r + 1
					nxt.append(n)
		frontier = nxt
	_dist_cache[key] = out
	return out


## Détection d'un empire (et de ses alliés) sur un système, pour un camouflage donné :
## {"det": meilleure détection, "dist": distance de la source la plus proche qui perce cam (-1 si aucune)}.
static func detection_at(state: GameState, viewer: int, sid: int, cam := 0, against := -1) -> Dictionary:
	var out := {"det": 0, "dist": -1}
	if viewer < 0 or viewer >= state.empires.size():
		return out
	if state.galaxy.systems[sid].blind:
		return out  # tempête de radiations : détection 0
	var who: Array[int] = [viewer]
	who.append_array(Fleets.allies_of(state, viewer))
	var dists := _dist(state, sid, 8)
	# Prop. 28 : contre un peuple voilé (le Chœur), une présence à l'arrêt sur place voit +2, et les
	# Détecteurs d'abysse donnent leur bonus (detect_veil) partout : le Voile d'avant, à l'identique.
	var veil_target := against >= 0 and against < state.empires.size() and Veil.is_veiled(state, against)
	var stat := int(cfg("stationary_bonus").get("detect", 2)) if veil_target else 0
	for eid in who:
		var extra := StealthBridges.codes_bonus(state, eid, against) if against >= 0 else 0
		if veil_target:
			extra += Research.fx_int(state, eid, "detect_veil")
		extra += PsionicsBridges.detect_bonus(state, eid, against)  # Lecture des esprits réussie
		var tal := int(talent(state, eid).get("stationary", 0))
		for src in sources(state, eid):
			var d := int(dists.get(int(src[0]), 99))
			if d > int(src[1]):
				continue
			var det := int(src[2]) + extra
			if d == 0 and int(src[3]) == 1:
				det += stat + tal
			if det > int(out["det"]):
				out["det"] = det
			if det >= cam and (int(out["dist"]) < 0 or d < int(out["dist"])):
				out["dist"] = d
	return out


## L'empire viewer (ou un allié) perce-t-il le camouflage de f ? (la portée est vérifiée à part :
## Fleets.fleet_visible). Une puissance qui n'est pas un empire voit sur place selon son niveau.
static func detects(state: GameState, viewer: int, f: Fleet) -> bool:
	if not enabled(state) or f == null or viewer == f.owner:
		return true
	var cam := cloak(state, f)
	if cam <= 0:
		return true
	if posture(state, f) == "scan":
		return true
	if viewer < 0:
		return true  # spectateur
	var kind := _non_empire_kind(viewer)
	if kind != "" or viewer >= state.empires.size():
		var lvl := int(cfg("non_empires").get("detect", {}).get(kind, 1))
		for g in Fleets.fleets_at(state, f.system_id, viewer):
			if g != null:
				return lvl >= cam
		return false
	if Diplomacy.allied(state, viewer, f.owner):
		return true
	var sid := Fleets.vision_center(state, f)
	return int(detection_at(state, viewer, sid, cam, f.owner)["dist"]) >= 0


## Degré de connaissance d'une flotte vue (0 si invisible) : 1 contact, 2 identifiée, 3 détaillée.
static func degree(state: GameState, viewer: int, f: Fleet, seen: Variant = null) -> int:
	if f == null:
		return 0
	if viewer < 0 or f.owner == viewer:
		return 3
	var sid := Fleets.vision_center(state, f)
	var vis: Dictionary = seen if seen != null else Fleets.visible_systems(state, viewer)
	if not vis.has(sid):
		return 0
	if not enabled(state):
		return 0 if Veil.hides(state, f.owner, viewer, sid) else 3
	if not detects(state, viewer, f):
		return 0
	if not full(state) or viewer >= state.empires.size() or Diplomacy.allied(state, viewer, f.owner):
		return 3
	if posture(state, f) == "scan":
		return 3
	var cam := cloak(state, f)
	var dc: Dictionary = cfg("degrees")
	var at := detection_at(state, viewer, sid, cam, f.owner)
	var adv := int(at["det"]) - cam
	var d := int(at["dist"])
	var out := 1
	if d == 0 or adv >= int(dc.get("detail_adv", 2)):
		out = 3
	elif d >= 0 and d <= int(dc.get("identify_dist", 1)):
		out = 2
	if out == 3 and jammed(f) and adv < int(dc.get("jam_adv", 3)) and d != 0:
		out = 2
	return out


static func degree_label(n: int) -> String:
	return String(cfg("degrees").get("labels", {}).get(str(n), "Invisible"))


static func jammed(f: Fleet) -> bool:
	for s in f.ships:
		if int(GameData.ship(s).get("jam", 0)) > 0:
			return true
	return false


static func has_decoys(f: Fleet) -> bool:
	for s in f.ships:
		if int(GameData.ship(s).get("decoy", 0)) > 0:
			return true
	return false


## Une flotte qui tente un blocus, des mines ou un inhibiteur : passe-t-elle sans être vue de owner ?
static func unseen_by(state: GameState, owner: int, f: Fleet) -> bool:
	if not enabled(state) or f == null or cloak(state, f) <= 0:
		return false
	return not detects(state, owner, f)


## Blocus : la flotte se glisse entre les ennemis armés présents sans qu'aucun la voie.
static func slips(state: GameState, f: Fleet, sid: int) -> bool:
	if not enabled(state) or f == null or cloak(state, f) <= 0:
		return false
	for g in Fleets.fleets_at(state, sid):
		if g.owner != f.owner and Combat.is_armed(g) and Combat.hostile_fleets(state, g, f) and detects(state, g.owner, f):
			return false
	if state.system_owner(sid) >= 0 and Combat.at_war(state, state.system_owner(sid), f.owner) and Defenses.holds(state, sid) \
			and detects(state, state.system_owner(sid), f):
		return false
	return true


# --- Batailles ---------------------------------------------------------------------------------

## Retire des listes de combat les flottes cachées que personne d'hostile ne voit ; note celles qui
## engagent (Embuscade). by_sys : {système: [flottes]} (CombatSystem).
static func filter_battle(state: GameState, by_sys: Dictionary) -> void:
	_ambushers.clear()
	if not enabled(state):
		return
	for sid in by_sys.keys():
		var list: Array = by_sys[sid]
		var keep: Array = []
		var changed := false
		for f: Fleet in list:
			if f.id < 0 or not veil_up(state, f):
				keep.append(f)
				continue
			var spotted := false
			for g: Fleet in list:
				if g != f and Combat.hostile_fleets(state, g, f) and detects(state, g.owner, f):
					spotted = true
					break
			if spotted:
				keep.append(f)
			elif posture(state, f) == "ambush":
				keep.append(f)
				_ambushers[f.id] = true
			else:
				changed = true
		if changed:
			by_sys[sid] = keep


## Un jour de bataille : les flottes voilées qui combattent perdent leur voile ; note l'embuscade.
static func on_battle_day(state: GameState, b: Dictionary, fighters: Array) -> void:
	if not enabled(state):
		return
	for f: Fleet in fighters:
		if f.id < 0:
			continue
		if veil_up(state, f):
			if not b.has("veiled"):
				b["veiled"] = {}
			b["veiled"][str(f.id)] = int(b["day"])
			if _ambushers.has(f.id):
				if not b.has("ambush"):
					b["ambush"] = {}
				b["ambush"][str(f.owner)] = 1
				for g: Fleet in fighters:
					if g.owner != f.owner and g.owner >= 0 and g.owner < state.empires.size() and Combat.hostile_fleets(state, g, f):
						_sub(state, "amb")[str(g.owner)] = state.tick
				StealthBridges.on_ambush(state, f, b)
			drop(state, f)


## Bonus de dégâts (%) : embuscade le premier jour ; Chasseur d'ombres contre une flotte qui était cachée.
static func damage_pct(state: GameState, b: Dictionary, f: Fleet, day: int) -> int:
	if not enabled(state):
		return 0
	var pct := 0
	if day == 1 and (b.get("ambush", {}) as Dictionary).has(str(f.owner)):
		pct += int(cfg("ambush").get("damage_pct", 25))
	if not (b.get("veiled", {}) as Dictionary).is_empty():
		pct += StealthBridges.hunter_pct(state, b, f)
	return pct


## Boucliers (%) d'une cible : à moitié le jour où son voile tombe.
static func shield_pct(b: Dictionary, tg: Fleet) -> int:
	var v: Dictionary = b.get("veiled", {})
	if v.has(str(tg.id)) and int(v[str(tg.id)]) == int(b.get("day", 0)):
		return int(GameData.stealth().get("cloak", {}).get("shield_pct", 50))
	return 100


# --- Ordres ------------------------------------------------------------------------------------

static func check(state: GameState, player: int, act: String, a := -1, _b := -1, s := "") -> String:
	if not enabled(state):
		return "la furtivité n'est pas en jeu"
	var f: Fleet = state.fleets.get(a)
	if f == null or f.owner != player:
		return "cette flotte ne vous appartient pas"
	match act:
		"pose":
			if not postures(state).has(s):
				return "posture inconnue"
			return ""
		"beacon":
			return check_beacon(state, player, f)
	return "ordre inconnu"


static func apply(state: GameState, player: int, act: String, a := -1, b := -1, s := "") -> void:
	if check(state, player, act, a, b, s) != "":
		return
	var f: Fleet = state.fleets[a]
	match act:
		"pose":
			if s == "":
				_sub(state, "pose").erase(str(f.id))
			else:
				_sub(state, "pose")[str(f.id)] = s
		"beacon":
			_place_beacon(state, player, f)
	invalidate()


# --- Balises d'écoute (prop. 20) ---------------------------------------------------------------

static func beacons_of(state: GameState, eid: int) -> Array[int]:
	var out: Array[int] = []
	for k in _sub(state, "bc"):
		if int(state.stealth["bc"][k].get("o", -1)) == eid:
			out.append(int(k))
	out.sort()
	return out


static func check_beacon(state: GameState, player: int, f: Fleet) -> String:
	if not full(state):
		return "les balises d'écoute demandent la furtivité complète"
	var bc: Dictionary = cfg("beacon")
	var e := state.get_empire(player)
	if not e.techs.has(String(bc.get("tech", "detecteurs_2"))):
		return "il faut la technologie %s" % String(Research.tech(String(bc.get("tech", "detecteurs_2"))).get("label", bc.get("tech", "")))
	if f.is_moving():
		return "la flotte doit être à l'arrêt"
	if Combat.is_armed(f):
		return "seule une flotte sans armes (éclaireur) pose une balise"
	if _sub(state, "bc").has(str(f.system_id)):
		return "une balise écoute déjà ce système"
	if state.system_owner(f.system_id) == player:
		return "inutile chez vous : vos colonies écoutent déjà"
	if beacons_of(state, player).size() >= int(bc.get("max", 6)):
		return "au plus %d balises" % int(bc.get("max", 6))
	if not Economy.can_afford(e, bc.get("cost", {})):
		return "pas assez de ressources (%s)" % GameData.format_amounts(bc.get("cost", {}))
	return ""


static func _place_beacon(state: GameState, player: int, f: Fleet) -> void:
	Economy.pay(state.get_empire(player), cfg("beacon").get("cost", {}))
	_sub(state, "bc")[str(f.system_id)] = {"o": player, "d": state.tick}
	state.add_chronicle("%s pose une balise d'écoute à %s. Un caillou de plus dans le vide, qui écoute." % [
			f.fleet_name, state.galaxy.systems[f.system_id].system_name], Espionage.private_to(state, [player]))


## La balise est-elle repérée par le maître du système ?
static func _beacon_found(state: GameState, sid: int, owner: int) -> bool:
	var host := state.system_owner(sid)
	if host < 0 or host == owner or host >= state.empires.size():
		return false
	if Diplomacy.allied(state, host, owner):
		return false
	var cam := int(cfg("beacon").get("cloak", 2))
	return int(detection_at(state, host, sid, cam, owner)["dist"]) >= 0


# --- Chaque jour -------------------------------------------------------------------------------

static func daily(state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not enabled(state):
		return out
	# Ménage : flottes disparues.
	for k in ["off", "pose"]:
		var d := _sub(state, k)
		for fid in d.keys():
			if not state.fleets.has(int(fid)):
				d.erase(fid)
	# Balises : détruites quand le maître des lieux les repère.
	var bc := _sub(state, "bc")
	var ks := bc.keys()
	ks.sort()
	for k in ks:
		var owner := int(bc[k].get("o", -1))
		var e := state.get_empire(owner)
		if e == null or e.eliminated:
			bc.erase(k)
			continue
		if _beacon_found(state, int(k), owner):
			bc.erase(k)
			var host := state.get_empire(state.system_owner(int(k)))
			out.append(state.add_chronicle("%s déniche une balise d'écoute de %s à %s, et la réduit en ferraille." % [
					host.display_name(), e.display_name(), state.galaxy.systems[int(k)].system_name],
					Espionage.private_to(state, [owner, host.id])))
	if state.tick % 7 == 0:
		_decoys(state)
	out.append_array(StealthBridges.daily(state))
	return out


## Leurres (prop. 26) : une flotte qui en porte laisse une fausse silhouette (contact) dans la mémoire
## des empires qui la voient en contact.
static func _decoys(state: GameState) -> void:
	if not full(state):
		return
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if not has_decoys(f) or f.owner < 0 or f.owner >= state.empires.size():
			continue
		var sid := Fleets.vision_center(state, f)
		for e in state.empires:
			if e.eliminated or e.id == f.owner or e.id >= state.seen_cache.size():
				continue
			if degree(state, e.id, f, state.seen_cache[e.id]) != 1:
				continue
			# La fausse flotte apparaît dans un système voisin que l'empire ne voit pas.
			var spot := -1
			var ns: Array = state.galaxy.systems[sid].neighbors.duplicate()
			ns.sort()
			for n in ns:
				if not (state.seen_cache[e.id] as Dictionary).has(int(n)):
					spot = int(n)
					break
			if spot < 0:
				continue
			var fake: int = -(1000000 + int(fid) * 16 + (e.id % 16))
			e.sightings[fake] = {"sys": spot, "day": state.tick, "owner": -1, "ships": f.ships.size() * 2 + 1, "armed": 1}
			var dk := _sub(state, "dk")
			dk[str(f.owner)] = int(dk.get(str(f.owner), 0)) + 1


## Alerte privée « contact inconnu » (prop. 27) : un contact entre dans les frontières de l'empire.
static func contact_alert(state: GameState, viewer: int, f: Fleet) -> String:
	var sid := Fleets.vision_center(state, f)
	if state.system_owner(sid) != viewer:
		return ""
	return "Contact inconnu près de %s : une ombre sur les écrans, sans pavillon." % state.galaxy.systems[sid].system_name


# --- Interface ---------------------------------------------------------------------------------

## Lignes de la fiche de flotte (camouflage, détection, posture).
static func fleet_lines(state: GameState, f: Fleet) -> PackedStringArray:
	var out := PackedStringArray()
	if not enabled(state):
		return out
	var c := cloak(state, f)
	var base := base_cloak(state, f)
	var t := "camouflage %d" % c
	if base > 0 and not veil_up(state, f):
		t += " (voile tombé, %d j)" % recharge_left(state, f) if recharge_left(state, f) > 0 else " (voile baissé)"
	t += "  ·  détection %d" % fleet_detect(state, f)
	var p := posture(state, f)
	if p != "":
		t += "  ·  " + posture_label(p)
	out.append(t)
	return out
