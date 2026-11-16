class_name Portals
extends RefCounted
## Portails de saut et raccourcis spatiaux (étude du 2026-11-16, 38 propositions validées ;
## data/portals.json). Trois infrastructures sous la Porte stellaire (merveille, voir WondersCatalog) :
## - trous de ver naturels (paires générées avec la galaxie) : on les emprunte avec la technologie
##   Stabilisation des trous de ver ; 1 jour de transit ; certains dérivent (Complets) ; une Ancre sur une
##   extrémité les ferme à qui n'a pas le droit de passage, et y lève le péage ;
## - relais hyperspatiaux (bâtiment, un par système) : une route dont les deux bouts ont un relais compte
##   trois fois moins pour qui y a accès (corridor) ;
## - portails de saut (bâtiment, un par système) : saut d'un portail à un autre en 1 jour, dans la limite
##   de la portée en sauts (la plus petite des deux), recharge selon la taille de la flotte de guerre,
##   coût en cristaux de saut, choc de transit à l'arrivée (Complets), péage du propriétaire.
## Un raccourci est un lieu à tenir : il faut pouvoir passer aux deux bouts ; un ennemi en guerre ne passe
## jamais ; système occupé, sous blocus, saboté ou pris dans une tempête gravitationnelle = coupé.
##
## Réglage « Portails » : Complets, Simples (sans recharge, choc, instabilité, péage, ruines) ou
## Désactivés (state.portals vide : comme avant). Sans l'option (tests, bancs) : désactivés.
##
## État : state.portals = {"mode", "wh": [[a, b, instable, prochaine dérive, annoncée, nom]],
##  "wk": {"<empire>": {"<paire>": 1}} (destinations connues), "cd": {"<système>": jour de fin de recharge},
##  "tr": {"<flotte>": jour du transit}, "cut": {"<système>": jour de fin} (sabotage, résonance),
##  "ruins": {"<système>": 0 en ruine | 1 réveillé (libre)}, "rs": portails anciens restaurés,
##  "off": {"<empire>": 1} (relais éteints faute de cristaux), "law": 1 (loi Portes ouvertes)}.
## Dérivé (non sauvegardé, refresh) : Galaxy.wormholes, portal_gates, portal_links, relays.
## Déterministe : flux aléatoires dérivés de la graine, parcours dans l'ordre des identifiants.

const MONTH := 30
const OFFSET := 17
const TECH_WORM := "stabilisation_ver"
const LAYERS := ["traits", "registre", "archetype", "gouvernement", "credo"]
const GATE_BUILDINGS := ["portail_saut", "grand_portail", "portail_ancien"]

static var _talent_cache := {}


static func data() -> Dictionary:
	return GameData.portals()


static func cfg(section: String) -> Dictionary:
	return data().get(section, {})


static func mode_defs() -> Array:
	return data().get("modes", [])


static func default_mode() -> String:
	return String(data().get("default_mode", "complets"))


static func mode(state: GameState) -> String:
	return String(state.portals.get("mode", "desactives"))


static func enabled(state: GameState) -> bool:
	return state != null and not state.portals.is_empty()


static func full(state: GameState) -> bool:
	return enabled(state) and mode(state) == "complets"


static func mode_label(state: GameState) -> String:
	for m: Dictionary in mode_defs():
		if String(m["id"]) == mode(state):
			return String(m["label"])
	return "Désactivés"


static func _sub(state: GameState, k: String) -> Dictionary:
	if not state.portals.has(k):
		state.portals[k] = {}
	return state.portals[k]


# --- Réglage, sauvegarde -----------------------------------------------------------------------

static func setup(state: GameState, mode_id: String) -> void:
	state.portals = {}
	var ok := false
	for m: Dictionary in mode_defs():
		if String(m["id"]) == mode_id:
			ok = true
	if not ok or mode_id == "desactives":
		refresh(state)
		return
	state.portals = {"mode": mode_id, "wh": [], "wk": {}, "cd": {}, "tr": {}, "cut": {}, "ruins": {}, "rs": 0, "off": {}}
	_place_wormholes(state)
	if full(state):
		_place_ruins(state)
	refresh(state)


static func worth_saving(state: GameState) -> bool:
	return not state.portals.is_empty()


static func to_dict(state: GameState) -> Dictionary:
	return Ancients._sorted(state.portals)


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.portals = {}
	if not d.is_empty():
		state.portals = GameData._to_ints(d.duplicate(true))
		for k in ["wk", "cd", "tr", "cut", "ruins", "off"]:
			if not state.portals.has(k):
				state.portals[k] = {}
		if not state.portals.has("wh"):
			state.portals["wh"] = []
		if not state.portals.has("rs"):
			state.portals["rs"] = 0


static func _rng(state: GameState, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([state.galaxy.seed_value, 7919, salt])
	return rng


static func _starts(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for e in state.empires:
		var c := FactionTraits.capital_system(state, e.id)
		if c >= 0 and not out.has(c):
			out.append(c)
	return out


## Paires de trous de ver (prop. 6) : extrémités loin l'une de l'autre, trous noirs et étoiles à neutrons
## d'abord, jamais sur un système de départ ni deux fois le même système.
static func _place_wormholes(state: GameState) -> void:
	var w := cfg("wormholes")
	var n := maxi(int(w.get("min_pairs", 1)), state.galaxy.systems.size() / maxi(1, int(w.get("per_systems", 12))))
	var rng := _rng(state, 1)
	var used := {}
	for s in _starts(state):
		used[s] = true
	var pairs: Array = []
	for i in n:
		var pr := _pick_pair(state, rng, used)
		if pr.is_empty():
			break
		used[pr[0]] = true
		used[pr[1]] = true
		var unstable := 1 if full(state) and rng.randi_range(1, 100) <= int(w.get("unstable_pct", 25)) else 0
		pairs.append([pr[0], pr[1], unstable, _next_shift(state, rng) if unstable else 0, 0, i % maxi(1, (w.get("names", ["Faille"]) as Array).size())])
	state.portals["wh"] = pairs


static func _pick_pair(state: GameState, rng: RandomNumberGenerator, used: Dictionary) -> Array:
	var g := state.galaxy
	var min_j := int(cfg("wormholes").get("min_jumps", 6))
	var cands: Array[int] = []
	var weights: Array[int] = []
	for s in g.systems:
		if used.has(s.id):
			continue
		cands.append(s.id)
		weights.append(6 if s.star_type == "black_hole" else (4 if s.star_type == "neutron" else 1))
	if cands.size() < 2:
		return []
	for _t in 40:
		var a := _weighted(rng, cands, weights)
		var dist := FactionTraits.jumps_from(g, a)
		var far: Array[int] = []
		var fw: Array[int] = []
		for i in cands.size():
			var b := cands[i]
			if b != a and int(dist.get(b, -1)) >= min_j:
				far.append(b)
				fw.append(weights[i])
		if not far.is_empty():
			return [a, _weighted(rng, far, fw)]
	return []


static func _weighted(rng: RandomNumberGenerator, ids: Array[int], w: Array[int]) -> int:
	var total := 0
	for x in w:
		total += x
	var roll := rng.randi_range(1, total)
	for i in ids.size():
		roll -= w[i]
		if roll <= 0:
			return ids[i]
	return ids[ids.size() - 1]


static func _next_shift(state: GameState, rng: RandomNumberGenerator) -> int:
	var w := cfg("wormholes")
	return state.tick + rng.randi_range(int(w.get("shift_years_min", 8)), int(w.get("shift_years_max", 15))) * GameCalendar.DAYS_PER_YEAR


## Portails anciens en ruine (prop. 27) : systèmes vides, loin des départs.
static func _place_ruins(state: GameState) -> void:
	var n := 0
	for row in cfg("ruins").get("count_by_size", []):
		if state.galaxy.systems.size() >= int(row[0]):
			n = int(row[1])
	var rng := _rng(state, 2)
	var min_j := int(cfg("ruins").get("min_jumps_from_start", 4))
	var near := {}
	for s in _starts(state):
		var dist := FactionTraits.jumps_from(state.galaxy, s)
		for k in dist:
			if int(dist[k]) < min_j:
				near[int(k)] = true
	var cands: Array[int] = []
	for s in state.galaxy.systems:
		if near.has(s.id) or wormhole_at(state, s.id) >= 0 or state.system_owner(s.id) >= 0:
			continue
		cands.append(s.id)
	var ruins := _sub(state, "ruins")
	for i in n:
		if cands.is_empty():
			break
		var k := rng.randi_range(0, cands.size() - 1)
		ruins[str(cands[k])] = 0
		cands.remove_at(k)


# --- Réseau dérivé -----------------------------------------------------------------------------

## Reconstruit les données dérivées (trous de ver, portails, liens à portée, relais) et vide les caches
## de chemins. Appelé à la création, au chargement, à chaque chantier de portail fini, chaque mois.
static func refresh(state: GameState) -> void:
	var g := state.galaxy
	g.wormholes = {}
	g.portal_gates = {}
	g.portal_links = {}
	g.relays = {}
	if enabled(state):
		for pr in state.portals.get("wh", []):
			g.wormholes[int(pr[0])] = int(pr[1])
			g.wormholes[int(pr[1])] = int(pr[0])
		var ranges: Dictionary = cfg("gates").get("range", {})
		for pid in state.sorted_colony_ids():
			var c: Colony = state.colonies[pid]
			if not c.is_established():
				continue
			var sid := g.get_planet(pid).system_id
			for b in c.buildings:
				if GATE_BUILDINGS.has(b):
					g.portal_gates[sid] = maxi(int(g.portal_gates.get(sid, 0)), int(ranges.get(b, 6)))
				elif b == "relais_hyper":
					g.relays[sid] = true
		var ruins: Dictionary = state.portals.get("ruins", {})
		for k in ruins:
			if int(ruins[k]) == 1:
				g.portal_gates[int(k)] = maxi(int(g.portal_gates.get(int(k), 0)), int(ranges.get("portail_ancien", 8)))
		_links(state)
	for e in state.empires:
		e.path_cache.clear()
		e.border_cache.clear()
		e.path_cache_explored = -1


## Liens entre portails : distance en sauts par les routes, tant qu'elle reste sous la plus grande portée
## possible (la portée effective, talents compris, se vérifie à l'usage).
static func _links(state: GameState) -> void:
	var g := state.galaxy
	if g.portal_gates.size() < 2:
		return
	var max_r := 0
	for sid in g.portal_gates:
		max_r = maxi(max_r, int(g.portal_gates[sid]))
	max_r += _max_range_bonus()
	var keys := g.portal_gates.keys()
	keys.sort()
	for a in keys:
		var dist := FactionTraits.jumps_from(g, int(a))
		var out := {}
		for b in keys:
			if b != a and dist.has(b) and int(dist[b]) <= max_r:
				out[int(b)] = int(dist[b])
		g.portal_links[int(a)] = out


static func _max_range_bonus() -> int:
	var m := 0
	for layer in LAYERS:
		var t: Dictionary = cfg("talents").get(layer, {})
		for k in t:
			if t[k] is Dictionary:
				m = maxi(m, int((t[k] as Dictionary).get("range_bonus", 0)))
	return m


static func wormhole_at(state: GameState, sid: int) -> int:
	return int(state.galaxy.wormholes.get(sid, -1))


static func pair_index(state: GameState, sid: int) -> int:
	var wh: Array = state.portals.get("wh", [])
	for i in wh.size():
		if int(wh[i][0]) == sid or int(wh[i][1]) == sid:
			return i
	return -1


static func wormhole_name(state: GameState, sid: int) -> String:
	var i := pair_index(state, sid)
	if i < 0:
		return ""
	var names: Array = cfg("wormholes").get("names", ["Faille"])
	return "Trou de ver %s" % String(names[int(state.portals["wh"][i][5]) % names.size()])


static func has_gate(state: GameState, sid: int) -> bool:
	return state.galaxy.portal_gates.has(sid)


static func has_relay(state: GameState, sid: int) -> bool:
	return state.galaxy.relays.has(sid)


## Un saut de raccourci (trou de ver ou portail) entre deux systèmes qui ne sont pas voisins ?
static func is_shortcut(g: Galaxy, a: int, b: int) -> bool:
	if not g.wormholes.is_empty() and int(g.wormholes.get(a, -1)) == b:
		return true
	return not g.portal_gates.is_empty() and g.portal_gates.has(a) and g.portal_gates.has(b) and a != b \
			and not g.systems[a].neighbors.has(b)


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
	var table := cfg("talents")
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


## Coût des bâtiments de portail (talent Tisseurs de portes), en points de %.
static func cost_pct(state: GameState, eid: int, bid: String) -> int:
	if String(GameData.building(bid).get("portals", "")) == "":
		return 0
	return int(talent(state, eid).get("cost_pct", 0))


# --- Accès -------------------------------------------------------------------------------------

## L'empire eid peut-il passer par une infrastructure tenue par o ? La sienne, celle d'un système libre,
## d'un allié, d'un membre de son Koinon, de son suzerain ou vassal, d'un empire qui lui accorde le
## droit de passage, ou de tout membre en paix avec la loi galactique Portes ouvertes. Jamais en guerre.
static func may_use(state: GameState, o: int, eid: int) -> bool:
	if o < 0 or o == eid:
		return true
	if eid < 0 or GameState.is_npc(eid) or GameState.is_npc(o):
		return false
	if Combat.at_war(state, o, eid):
		return false
	if Borders.strong_link(state, o, eid):
		return true
	if int(state.portals.get("law", 0)) == 1 and state.amph_on and Amphictyony.is_member(state, o) and Amphictyony.is_member(state, eid):
		return true
	return Borders.active(state) and Borders.grants(state, o, eid)


## Système coupé : sabotage, résonance, tempête gravitationnelle, blocus ennemi du tenant, occupation.
static func cut(state: GameState, sid: int) -> bool:
	if int(_sub(state, "cut").get(str(sid), 0)) > state.tick:
		return true
	for t in Terrain.at(state, sid):
		if t == "tempete_gravitationnelle":
			return true
	return false


static func _gate_cut(state: GameState, sid: int) -> bool:
	if cut(state, sid):
		return true
	var o := state.system_owner(sid)
	if o >= 0 and (Combat.blocks(state, o, sid) or Combat.is_besieged(state, sid)):
		return true
	return state.wars_on and WarPeace.occupier(state, sid) >= 0


static func knows_worm(state: GameState, eid: int) -> bool:
	return Research.knows(state, eid, TECH_WORM)


## Trou de ver praticable depuis a pour eid (prop. 8, 9, 12, 33) : technologie (les créatures et les
## flottes de crise passent sans), destination connue, ancre éventuelle ouverte, inhibiteur ennemi.
static func wormhole_ok(state: GameState, eid: int, a: int, check_known := true) -> bool:
	var b := wormhole_at(state, a)
	if b < 0 or not enabled(state):
		return false
	if eid < 0 or GameState.is_npc(eid):
		return eid == GameState.FAUNA_ID or eid == GameState.CRISIS_ID
	if not knows_worm(state, eid):
		return false
	if check_known and not known_pair(state, eid, pair_index(state, a)):
		return false
	for sid in [a, b]:
		if anchored(state, sid) and not may_use(state, state.system_owner(sid), eid):
			return false
	return not _inhibited(state, eid, b)


static func known_pair(state: GameState, eid: int, idx: int) -> bool:
	return idx >= 0 and ((state.portals.get("wk", {}) as Dictionary).get(str(eid), {}) as Dictionary).has(str(idx))


static func anchored(state: GameState, sid: int) -> bool:
	return _has_building(state, sid, "ancre_ver")


static func _has_building(state: GameState, sid: int, bid: String) -> bool:
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.is_established() and c.buildings.has(bid):
			return true
	return false


static func _inhibited(state: GameState, eid: int, sid: int) -> bool:
	if not Defenses.enabled(state) or not Defenses.inhibits(state, sid):
		return false
	var o := state.system_owner(sid)
	return o >= 0 and o != eid and Combat.at_war(state, o, eid)


## Corridor de relais praticable par eid entre deux systèmes voisins (prop. 14, 16, 32).
static func relay_ok(state: GameState, eid: int, a: int, b: int) -> bool:
	var g := state.galaxy
	if g.relays.is_empty() or not g.relays.has(a) or not g.relays.has(b):
		return false
	for sid in [a, b]:
		var o := state.system_owner(sid)
		if o >= 0 and (state.portals.get("off", {}) as Dictionary).has(str(o)):
			return false
		if not may_use(state, o, eid) or cut(state, sid):
			return false
	return true


## Portée effective du portail d'un système (talent du tenant).
static func gate_range(state: GameState, sid: int) -> int:
	var r := int(state.galaxy.portal_gates.get(sid, 0))
	if r <= 0:
		return 0
	return r + int(talent(state, state.system_owner(sid)).get("range_bonus", 0))


## Saut de portail praticable de a vers b pour eid (prop. 19, 23, 25, 26) ; smuggle : éclaireurs et
## civils d'un peuple contrebandier, qui passent sans droit de passage (jamais en guerre).
static func gate_ok(state: GameState, eid: int, a: int, b: int, smuggle := false) -> bool:
	var g := state.galaxy
	var links: Dictionary = g.portal_links.get(a, {})
	if not links.has(b):
		return false
	if int(links[b]) > mini(gate_range(state, a), gate_range(state, b)):
		return false
	if eid < 0 or GameState.is_npc(eid):
		return false  # créatures et crises ne passent jamais les portails (prop. 33)
	for sid in [a, b]:
		var o := state.system_owner(sid)
		if not may_use(state, o, eid):
			if not (smuggle and o >= 0 and not Combat.at_war(state, o, eid)):
				return false
		if _gate_cut(state, sid):
			return false
	return not _inhibited(state, eid, b)


static func smuggler(state: GameState, eid: int) -> bool:
	return bool(talent(state, eid).get("smuggle", false))


## Arêtes de raccourci depuis un système pour le Dijkstra des flottes : [voisin, longueur, ...].
static func edges(state: GameState, eid: int, sid: int, explored: Dictionary, smuggle := false) -> Array[int]:
	var out: Array[int] = []
	var g := state.galaxy
	var w := int(g.wormholes.get(sid, -1))
	if w >= 0 and wormhole_ok(state, eid, sid):
		out.append(w)
		out.append(1)
	if g.portal_gates.has(sid) and explored.has(sid):
		var links: Dictionary = g.portal_links.get(sid, {})
		var keys := links.keys()
		keys.sort()
		for b in keys:
			if explored.has(int(b)) and gate_ok(state, eid, sid, int(b), smuggle):
				out.append(int(b))
				out.append(1)
	return out


## Multiplicateur de vitesse d'une flotte sur la route a -> b (corridor de relais).
static func lane_mult(state: GameState, eid: int, a: int, b: int) -> int:
	if state.galaxy.relays.is_empty() or not relay_ok(state, eid, a, b):
		return 1
	return maxi(1, int(cfg("relays").get("divisor", 3)))


# --- Sauts ---------------------------------------------------------------------------------------

## Points de coque d'une flotte de guerre (recharge du portail).
static func fleet_points(f: Fleet) -> int:
	var sp: Dictionary = cfg("gates").get("size_points", {})
	var n := 0
	for s in f.ships:
		if Combat.is_armed_ship(s):
			n += int(sp.get(String(GameData.ship(s).get("size", "small")), 1))
	return n


static func _armed_count(f: Fleet) -> int:
	var n := 0
	for s in f.ships:
		if Combat.is_armed_ship(s):
			n += 1
	return n


static func jump_cost(state: GameState, f: Fleet) -> int:
	if bool(talent(state, f.owner).get("free_jump", false)):
		return 0
	var n := _armed_count(f)
	if n <= 0:
		return 0
	var per := maxi(1, int(cfg("gates").get("ships_per_crystal", 5)))
	@warning_ignore("integer_division")
	return (n + per - 1) / per


static func _has_mega(f: Fleet) -> bool:
	var megas: Array = data().get("mega_ships", [])
	for s in f.ships:
		var sd := GameData.ship(s)
		if megas.has(s) or megas.has(String(sd.get("hull", ""))):
			return true
	return false


## Avant un saut de raccourci : 0 on passe, 1 on attend (recharge), 2 trajet annulé (et la raison).
static func hop_check(state: GameState, f: Fleet, a: int, b: int) -> Array:
	var g := state.galaxy
	if int(g.wormholes.get(a, -1)) == b:
		if not wormhole_ok(state, f.owner, a, false):
			return [2, "le trou de ver est fermé"]
		if _has_mega(f) and not (anchored(state, a) or anchored(state, b)):
			return [2, "un méga-vaisseau ne passe qu'un trou de ver ancré"]
		return [0, ""]
	if g.portal_gates.has(a) and g.portal_gates.has(b):
		if not gate_ok(state, f.owner, a, b, smuggler(state, f.owner) and not Combat.is_armed(f)):
			return [2, "le portail est fermé"]
		if full(state) and Combat.is_armed(f) and int(_sub(state, "cd").get(str(a), 0)) > state.tick:
			return [1, "le portail se recharge"]
		var cost := jump_cost(state, f)
		var e := state.get_empire(f.owner)
		if cost > 0 and e != null and int(e.resources.get("crystals", 0)) < cost:
			return [2, "pas assez de cristaux de saut (%d)" % cost]
		return [0, ""]
	return [2, "le raccourci n'existe plus"]


## Après un saut de raccourci : cristaux, recharge, péage, marque du choc de transit.
static func on_hop(state: GameState, f: Fleet, a: int, b: int) -> void:
	var g := state.galaxy
	var e := state.get_empire(f.owner)
	var armed := Combat.is_armed(f)
	if armed:
		_sub(state, "tr")[str(f.id)] = state.tick
	if int(g.wormholes.get(a, -1)) == b:
		for sid in [a, b]:
			if anchored(state, sid):
				_toll(state, f, sid, 1)
		return
	if e != null:
		var cost := jump_cost(state, f)
		if cost > 0:
			e.resources["crystals"] = int(e.resources.get("crystals", 0)) - cost
	if full(state) and armed:
		var per := maxi(1, int(cfg("gates").get("points_per_day", 4)))
		@warning_ignore("integer_division")
		var days := (fleet_points(f) + per - 1) / per
		days = maxi(0, days * (100 + int(talent(state, f.owner).get("recharge_pct", 0))) / 100)
		if days > 0:
			_sub(state, "cd")[str(a)] = state.tick + days
	_toll(state, f, a, int(cfg("gates").get("toll_mult", 2)))
	Research.count_stat(state, f.owner, "gate_jumps")


static func _toll(state: GameState, f: Fleet, sid: int, mult: int) -> void:
	if not full(state) or not Combat.is_armed(f):
		return
	var o := state.system_owner(sid)
	if o < 0 or o == f.owner or GameState.is_npc(o) or Borders.strong_link(state, o, f.owner):
		return
	var amount := Borders.toll_of(state, o) * mult
	if amount <= 0:
		return
	var ev := state.get_empire(f.owner)
	var eo := state.get_empire(o)
	if ev == null or eo == null:
		return
	var paid := mini(amount, int(ev.resources.get("energy", 0)))
	ev.resources["energy"] = int(ev.resources.get("energy", 0)) - paid
	eo.resources["energy"] = int(eo.resources.get("energy", 0)) + paid


## Choc de transit (prop. 22) : premier jour d'une bataille livrée juste après un saut.
static func shock_pct(state: GameState, f: Fleet) -> int:
	if not full(state):
		return 0
	var t := int((state.portals.get("tr", {}) as Dictionary).get(str(f.id), -1000000))
	if state.tick - t > int(cfg("gates").get("shock_days", 2)):
		return 0
	if not state.heroes.is_empty():
		var h := Heroes.at_post(state, "fleet", f.id, f.owner)
		if not h.is_empty() and Heroes.trait_fx(h, "jump_shock") > 0:
			return 0
	return -int(cfg("gates").get("shock_pct", 25))


# --- Bâtiments -----------------------------------------------------------------------------------

static func building_allowed(state: GameState, bid: String) -> bool:
	var k := String(GameData.building(bid).get("portals", ""))
	if k == "":
		return true
	if not enabled(state):
		return false
	if k == "ruin" or k == "anchor":
		return full(state)
	return true


## Règles propres aux portails (Economy.check_special) : un portail par système, ancre sur un trou de
## ver, restauration sur une ruine.
static func check_build(state: GameState, empire_id: int, c: Colony, bid: String) -> String:
	var k := String(GameData.building(bid).get("portals", ""))
	if k == "":
		return ""
	if not building_allowed(state, bid):
		return "les portails %s ne sont pas en jeu dans cette partie" % ("complets" if enabled(state) else "")
	var sid := state.galaxy.get_planet(c.planet_id).system_id
	match k:
		"anchor":
			if wormhole_at(state, sid) < 0:
				return "seulement sur une extrémité de trou de ver"
		"ruin":
			if int((state.portals.get("ruins", {}) as Dictionary).get(str(sid), -1)) != 0:
				return "seulement sur un portail ancien en ruine"
		"gate":
			if bid != "grand_portail" and (has_gate(state, sid) or _gate_building_here(state, sid, c.planet_id)):
				return "ce système a déjà son portail"
	if k == "gate" or k == "ruin":
		if k == "ruin" and _gate_building_here(state, sid, -1):
			return "ce système a déjà son portail"
	return ""


static func _gate_building_here(state: GameState, sid: int, except_pid: int) -> bool:
	for pid in state.galaxy.systems[sid].planet_ids:
		var o: Colony = state.colonies.get(pid)
		if o == null or o.planet_id == except_pid:
			continue
		for b in GATE_BUILDINGS:
			if o.buildings.has(b) or o.construction == b:
				return true
	return false


static func on_built(state: GameState, c: Colony, bid: String, added: Array[Dictionary]) -> void:
	var k := String(GameData.building(bid).get("portals", ""))
	if k == "" or not enabled(state):
		return
	var sid := state.galaxy.get_planet(c.planet_id).system_id
	if k == "ruin":
		var ruins := _sub(state, "ruins")
		ruins.erase(str(sid))
		state.portals["rs"] = int(state.portals.get("rs", 0)) + 1
		if int(state.portals["rs"]) == 1:
			_wake_ruin(state, c.owner, added)
	refresh(state)


## Le premier portail ancien restauré en réveille un autre, libre (prop. 27).
static func _wake_ruin(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var ruins := _sub(state, "ruins")
	var keys := ruins.keys()
	keys.sort_custom(func(x, y): return int(x) < int(y))
	for k in keys:
		if int(ruins[k]) == 0:
			ruins[k] = 1
			var e := state.get_empire(eid)
			added.append(state.add_chronicle("%s rallume un portail ancien. Quelque part ailleurs, un autre s'éveille en réponse, à %s : la vieille toile se souvient d'elle-même." % [
					e.display_name() if e else "Quelqu'un", state.galaxy.systems[int(k)].system_name], Espionage.public_to(state, [eid])))
			return


## Le pacte des Portes (gardien) laisse un portail ancien éveillé dans son système (prop. 28).
static func on_guardian_pact(state: GameState, sid: int) -> void:
	if not enabled(state):
		return
	_sub(state, "ruins")[str(sid)] = 1
	refresh(state)


## L'occupant rase le portail du système (prop. 25).
static func check_raze(state: GameState, eid: int, sid: int) -> String:
	if not enabled(state):
		return "les portails ne sont pas en jeu dans cette partie"
	if sid < 0 or sid >= state.galaxy.systems.size():
		return "système inconnu"
	if not state.wars_on or WarPeace.occupier(state, sid) != eid:
		return "il faut occuper ce système"
	if _gate_colony(state, sid) == null:
		return "aucun portail à raser ici"
	return ""


static func _gate_colony(state: GameState, sid: int) -> Colony:
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c == null:
			continue
		for b in GATE_BUILDINGS:
			if c.buildings.has(b):
				return c
	return null


static func raze(state: GameState, eid: int, sid: int) -> Dictionary:
	var c := _gate_colony(state, sid)
	if c == null:
		return {}
	for b in GATE_BUILDINGS:
		c.buildings.erase(b)
	refresh(state)
	var e := state.get_empire(eid)
	return state.add_chronicle("%s rase le portail de %s. On dit que la boucle d'énergie a mis trois jours à s'éteindre, et qu'elle a crié." % [
			e.display_name(), state.galaxy.systems[sid].system_name], Espionage.public_to(state, [eid, c.owner]))


# --- Chaque jour ---------------------------------------------------------------------------------

static func daily(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if not enabled(state):
		return added
	_discover(state, added)
	if full(state):
		_drift(state, added)
	if posmod(state.tick, MONTH) == OFFSET:
		_monthly(state, added)
	return added


## Avec la technologie, un empire qui a exploré une extrémité connaît l'autre (prop. 7) : on envoie
## une sonde, et le système d'arrivée s'ajoute aux cartes.
static func _discover(state: GameState, added: Array[Dictionary]) -> void:
	var wh: Array = state.portals.get("wh", [])
	if wh.is_empty():
		return
	var wk := _sub(state, "wk")
	for e in state.empires:
		if e.eliminated or e.is_npc() or not knows_worm(state, e.id):
			continue
		for i in wh.size():
			var a := int(wh[i][0])
			var b := int(wh[i][1])
			if not (e.explored.has(a) or e.explored.has(b)):
				continue
			if not wk.has(str(e.id)):
				wk[str(e.id)] = {}
			var mine: Dictionary = wk[str(e.id)]
			if mine.has(str(i)):
				continue
			mine[str(i)] = 1
			var fresh := b if e.explored.has(a) else a
			e.explored[fresh] = true
			e.path_cache.clear()
			e.path_cache_explored = -1
			added.append(state.add_chronicle("%s : une sonde traverse le %s et ressort à %s. Le retour du signal a pris un jour ; le voyage aussi." % [
					e.short_name(), wormhole_name(state, a), state.galaxy.systems[fresh].system_name], Espionage.private_to(state, [e.id])))


## Trous de ver instables (prop. 10) : annonce un an avant, puis dérive vers une autre paire.
static func _drift(state: GameState, added: Array[Dictionary]) -> void:
	var wh: Array = state.portals.get("wh", [])
	var warn := int(cfg("wormholes").get("warn_days", 360))
	for i in wh.size():
		var pr: Array = wh[i]
		if int(pr[2]) != 1:
			continue
		if int(pr[4]) == 0 and state.tick >= int(pr[3]) - warn:
			pr[4] = 1
			added.append(state.add_chronicle("Le %s se met à trembler. Les astronomes donnent un an avant qu'il ne se referme, puis se rouvre ailleurs." % wormhole_name(state, int(pr[0])), _knowers(state, i)))
		if state.tick < int(pr[3]):
			continue
		var used := {}
		for s in _starts(state):
			used[s] = true
		for j in wh.size():
			if j != i:
				used[int(wh[j][0])] = true
				used[int(wh[j][1])] = true
		var rng := _rng(state, 1000 + state.tick + i)
		var np := _pick_pair(state, rng, used)
		var old := wormhole_name(state, int(pr[0]))
		var who := _knowers(state, i)
		if not np.is_empty():
			pr[0] = np[0]
			pr[1] = np[1]
		pr[3] = _next_shift(state, rng)
		pr[4] = 0
		for k in _sub(state, "wk"):
			((state.portals["wk"] as Dictionary)[k] as Dictionary).erase(str(i))
		added.append(state.add_chronicle("Le %s s'est refermé. Ses deux bouches se sont rouvertes ailleurs : les cartes sont à refaire." % old, who))
		refresh(state)


static func _knowers(state: GameState, idx: int) -> Array:
	var who: Array = []
	for e in state.empires:
		if known_pair(state, e.id, idx):
			who.append(e.id)
	return Espionage.private_to(state, who) if not who.is_empty() else []


static func _monthly(state: GameState, added: Array[Dictionary]) -> void:
	# Entretien des relais : 0,5 cristal par relais et par mois ; sans cristaux, les relais s'éteignent.
	var count := {}
	for sid in state.galaxy.relays:
		var o := state.system_owner(int(sid))
		if o >= 0:
			count[o] = int(count.get(o, 0)) + 1
	var off := {}
	var per2 := int(cfg("relays").get("upkeep_per_two", 1))
	var keys := count.keys()
	keys.sort()
	for o in keys:
		var e := state.get_empire(int(o))
		if e == null:
			continue
		@warning_ignore("integer_division")
		var cost := (int(count[o]) * per2 + 1) / 2
		if int(e.resources.get("crystals", 0)) >= cost:
			e.resources["crystals"] = int(e.resources.get("crystals", 0)) - cost
		else:
			off[str(o)] = 1
			if not (state.portals.get("off", {}) as Dictionary).has(str(o)):
				added.append(state.add_chronicle("%s : faute de cristaux de saut, les relais hyperspatiaux s'éteignent un à un." % e.short_name(), Espionage.private_to(state, [e.id])))
	state.portals["off"] = off
	# Ménage : marques de transit et recharges passées.
	var tr := _sub(state, "tr")
	for k in tr.keys():
		if state.tick - int(tr[k]) > 30:
			tr.erase(k)
	var cd := _sub(state, "cd")
	for k in cd.keys():
		if int(cd[k]) <= state.tick:
			cd.erase(k)
	var ct := _sub(state, "cut")
	for k in ct.keys():
		if int(ct[k]) <= state.tick:
			ct.erase(k)
	PortalsBridges.monthly(state, added)
	refresh(state)


# --- Interface ------------------------------------------------------------------------------------

## Lignes de la fiche Passages d'un système (prop. 37), vues par viewer.
static func passage_lines(state: GameState, viewer: int, sid: int) -> Array[String]:
	var out: Array[String] = []
	if not enabled(state):
		return out
	var w := wormhole_at(state, sid)
	if w >= 0:
		var idx := pair_index(state, sid)
		var dest := state.galaxy.systems[w].system_name if known_pair(state, viewer, idx) else "destination inconnue"
		var line := "%s, vers %s" % [wormhole_name(state, sid), dest]
		if not knows_worm(state, viewer):
			line += " (il faut la Stabilisation des trous de ver)"
		if anchored(state, sid) or anchored(state, w):
			line += " ; ancré"
		if full(state) and int(state.portals["wh"][idx][2]) == 1 and int(state.portals["wh"][idx][4]) == 1:
			line += " ; instable, va se refermer"
		out.append(line)
	if has_relay(state, sid):
		var on := not (state.portals.get("off", {}) as Dictionary).has(str(state.system_owner(sid)))
		out.append("Relais hyperspatial%s : les routes vers un autre relais comptent trois fois moins" % ("" if on else " (éteint faute de cristaux)"))
	if has_gate(state, sid):
		var o := state.system_owner(sid)
		var line2 := "Portail de saut : portée %d sauts" % gate_range(state, sid)
		if o < 0:
			line2 = "Portail ancien éveillé (libre) : portée %d sauts" % gate_range(state, sid)
		var links: Dictionary = state.galaxy.portal_links.get(sid, {})
		var n := 0
		for b in links:
			if int(links[b]) <= mini(gate_range(state, sid), gate_range(state, int(b))):
				n += 1
		line2 += ", relié à %d portail%s" % [n, "s" if n > 1 else ""]
		var cdv := int(_sub(state, "cd").get(str(sid), 0))
		if cdv > state.tick:
			line2 += " ; recharge : %d j" % (cdv - state.tick)
		if _gate_cut(state, sid):
			line2 += " ; COUPÉ"
		elif not may_use(state, o, viewer):
			line2 += " ; fermé pour vous"
		elif full(state) and o >= 0 and o != viewer and Borders.toll_of(state, o) > 0:
			line2 += " ; péage %d énergie" % (Borders.toll_of(state, o) * int(cfg("gates").get("toll_mult", 2)))
		out.append(line2)
	if int((state.portals.get("ruins", {}) as Dictionary).get(str(sid), -1)) == 0:
		out.append("Portail ancien en ruine : se restaure pour la moitié du prix (Portail ancien)")
	return out
