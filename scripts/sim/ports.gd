class_name Ports
extends RefCounted
## Spatioports et réseau de distribution (étude « Spatioports », 2026-11-16, 36 propositions validées ;
## data/ports.json). Le stock de l'empire reste unique : ce module dit seulement quelle part de la
## production matérielle de chaque colonie y arrive (sa « desserte »), selon sa distance au port relié
## le plus proche.
##
## - Ports : Comptoir (niveau 1), Spatioport (2), Grand port orbital (3), un par système, plus la
##   Balise de fret (niveau 0 : relais sans desserte, même sur un avant-poste). La capitale naît avec
##   un Spatioport.
## - Réseau (prop. 5) : la capitale est la racine ; un port est relié si sa zone (portée en sauts)
##   touche la zone d'un port déjà relié. Chemins par son territoire, l'espace libre ou celui de qui le
##   ravitaille (alliés, passage : voir Logistics.supplies) ; jamais à travers une tempête ionisée.
##   Nébuleuses (terrain qui ralentit le transit) : un saut de plus (prop. 30).
## - Desserte (prop. 1, 3, 4) : 100 % dans la portée d'un port relié, puis -15 % par saut, plancher
##   50 % ; une colonie dans la zone d'un port non relié est en enclave (plancher). États : Desservie,
##   Limite, Isolée, Enclave.
## - Mode complet (lot 2) : fret (besoin contre capacité), pirates, blocus et liaisons coupées par
##   l'ennemi, entrepôts (un port coupé vit sur sa réserve), pillage, flux Construction / Luxe /
##   Nourriture, ravitaillement (un Spatioport est un dépôt de flotte) ; lot 3 : ponts (privé,
##   commerce, fiscalité, espionnage, corruption, événements, talents).
##
## Le calcul se fait au début de chaque mois et dès qu'un port change (chantier achevé), puis il est
## SAUVEGARDÉ : la production lit state.ports["sv"], donc deux machines qui chargent la même partie
## voient la même desserte.
##
## state.ports = {"mode", "sv": {"planète": %}, "st": {"planète": état}, "nodes": {"système": N},
##   "fr": {"empire": [besoin, disponible, ratio]}, "hg": {"planète": 1} (enclave affamée),
##   "dis": {"système": fin}, "strike": {"système": fin}, "sat": {"empire": fin}, "bk": {"système": 1}}.
## N = {"o": empire, "l": niveau, "r": portée, "lk": 1 relié / 0, "res": jours de réserve, "bk": 1 bloqué}.
## États : 0 Desservie, 1 Limite, 2 Isolée, 3 Enclave.

const OK := 0
const LIMIT := 1
const ISOLATED := 2
const ENCLAVE := 3
const STATE_LABELS := ["Desservie", "Limite", "Isolée", "Enclave"]
const LAYERS := ["gouvernement", "credo", "archetype"]

static var _talent_cache := {}


static func data() -> Dictionary:
	return GameData.ports()


static func cfg(section: String) -> Dictionary:
	return data().get(section, {})


static func c_int(section: String, key: String) -> int:
	return int(cfg(section).get(key, 0))


static func mode_defs() -> Array:
	return data().get("modes", [])


static func default_mode() -> String:
	return String(data().get("default_mode", "complet"))


static func mode(state: GameState) -> String:
	return String(state.ports.get("mode", "desactivee"))


static func enabled(state: GameState) -> bool:
	return not state.ports.is_empty()


static func full(state: GameState) -> bool:
	return enabled(state) and mode(state) == "complet"


static func worth_saving(state: GameState) -> bool:
	return enabled(state)


static func _blank(mode_id: String) -> Dictionary:
	return {"mode": mode_id, "sv": {}, "st": {}, "nodes": {}, "fr": {}, "hg": {}, "dis": {}, "strike": {}, "sat": {}, "bk": {}}


## Mise en place à la création de la partie : la capitale de chaque empire reçoit son Spatioport.
static func setup(state: GameState, mode_id: String) -> void:
	state.ports = {}
	var ids := []
	for m: Dictionary in mode_defs():
		ids.append(String(m["id"]))
	if mode_id == "" or mode_id == "desactivee" or not ids.has(mode_id):
		return
	state.ports = _blank(mode_id)
	var cb := String(data().get("capital_building", "spatioport"))
	for e in state.empires:
		if e.is_npc() or e.capital_planet < 0:
			continue
		var c: Colony = state.colonies.get(e.capital_planet)
		if c == null or c.owner != e.id or c.buildings.has(cb) or c.buildings.has("grand_port"):
			continue
		var at := c.buildings.find("comptoir")
		if at >= 0:
			c.buildings[at] = cb
		else:
			c.buildings.append(cb)
	refresh(state)


static func to_dict(state: GameState) -> Dictionary:
	return Ancients._sorted(state.ports)


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.ports = {}
	if d.is_empty():
		return
	state.ports = GameData._to_ints(d.duplicate(true))
	var blank := _blank(String(state.ports.get("mode", default_mode())))
	for k in blank:
		if not state.ports.has(k):
			state.ports[k] = blank[k]


# --- Talents (prop. 32) --------------------------------------------------------------------------

static func talent(state: GameState, eid: int) -> Dictionary:
	var e := state.get_empire(eid)
	if e == null or e.is_npc():
		return {}
	var ck := "%s:%d" % [e.faction_id, GameData.factions_gen]
	if _talent_cache.has(ck):
		return _talent_cache[ck]
	var out := {}
	var table: Dictionary = data().get("talents", {})
	for layer in LAYERS:
		var t: Dictionary = (table.get(layer, {}) as Dictionary).get(Events.layer_value(state, eid, layer), {})
		for k in t:
			if k == "label" or k == "text":
				continue
			var v: Variant = t[k]
			out[k] = v if v is bool else int(out.get(k, 0)) + int(v)
	_talent_cache[ck] = out
	return out


static func talent_labels(state: GameState, eid: int) -> Array:
	var e := state.get_empire(eid)
	var out := []
	if e == null or e.is_npc():
		return out
	var table: Dictionary = data().get("talents", {})
	for layer in LAYERS:
		var t: Dictionary = (table.get(layer, {}) as Dictionary).get(Events.layer_value(state, eid, layer), {})
		if not t.is_empty():
			out.append([String(t["label"]), String(t["text"])])
	return out


# --- Lecture -------------------------------------------------------------------------------------

## Niveau de port d'un bâtiment (-1 si ce n'est pas un port).
static func building_level(bid: String) -> int:
	return int((cfg("levels").get("buildings", {}) as Dictionary).get(bid, -1))


static func level_label(lvl: int) -> String:
	var l: Array = cfg("levels").get("labels", [])
	return String(l[lvl]) if lvl >= 0 and lvl < l.size() else ""


static func state_label(st: int) -> String:
	return STATE_LABELS[clampi(st, 0, 3)]


## Desserte d'une colonie en % (100 sans le pilier, ou avant le premier calcul).
static func service_pct(state: GameState, c: Colony) -> int:
	if state.ports.is_empty():
		return 100
	return int((state.ports["sv"] as Dictionary).get(str(c.planet_id), 100))


static func colony_state(state: GameState, pid: int) -> int:
	if state.ports.is_empty():
		return OK
	return int((state.ports["st"] as Dictionary).get(str(pid), OK))


## Pire état des colonies d'un empire dans un système (OK s'il n'y en a pas).
static func system_state(state: GameState, eid: int, sid: int) -> int:
	var worst := OK
	if state.ports.is_empty():
		return worst
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == eid and c.is_established():
			worst = maxi(worst, colony_state(state, pid))
	return worst


## Desserte d'un système pour un empire (meilleure de ses colonies ; 100 s'il n'en a pas).
static func system_pct(state: GameState, eid: int, sid: int) -> int:
	if state.ports.is_empty():
		return 100
	var best := -1
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == eid and c.is_established():
			best = maxi(best, service_pct(state, c))
	return 100 if best < 0 else best


## Applique la desserte au rendement brut d'une colonie (appelé par Economy.colony_yields).
static func adjust_yields(state: GameState, c: Colony, gross: Dictionary) -> void:
	var pct := service_pct(state, c)
	if pct >= 100:
		return
	for r in cfg("service").get("resources", []):
		var k := String(r)
		if int(gross.get(k, 0)) > 0:
			@warning_ignore("integer_division")
			gross[k] = int(gross[k]) * pct / 100


static func _k(eid: int, sid: int) -> String:
	return "%d:%d" % [eid, sid]


static func _sid(key: Variant) -> int:
	return int(String(key).get_slice(":", 1))


static func node(state: GameState, eid: int, sid: int) -> Dictionary:
	if state.ports.is_empty():
		return {}
	return (state.ports["nodes"] as Dictionary).get(_k(eid, sid), {})


## Niveau du port d'un empire dans un système (-1 sans port).
static func port_level_at(state: GameState, eid: int, sid: int) -> int:
	var n := node(state, eid, sid)
	return -1 if n.is_empty() else int(n["l"])


static func nodes_of(state: GameState, eid: int) -> Array[int]:
	var out: Array[int] = []
	if state.ports.is_empty():
		return out
	var nodes: Dictionary = state.ports["nodes"]
	for k in nodes:
		if int(nodes[k]["o"]) == eid:
			out.append(int(String(k).get_slice(":", 1)))
	out.sort()
	return out


static func linked(state: GameState, eid: int, sid: int) -> bool:
	var n := node(state, eid, sid)
	return not n.is_empty() and int(n.get("lk", 0)) == 1


## Fret du réseau : [besoin, disponible, ratio %].
static func freight(state: GameState, eid: int) -> Array:
	if state.ports.is_empty():
		return [0, 0, 100]
	return (state.ports["fr"] as Dictionary).get(str(eid), [0, 0, 100])


static func warehouse_max(state: GameState, eid: int, lvl: int) -> int:
	if lvl <= 0:
		return 0
	var w: Dictionary = cfg("warehouse")
	var d := int(w["days_per_level"]) * lvl
	if lvl >= 3:
		d *= int(w["grand_mult"])
	return d * (100 + Research.fx_int(state, eid, "warehouse_pct") + int(talent(state, eid).get("warehouse_pct", 0))) / 100


static func port_range(state: GameState, eid: int, lvl: int) -> int:
	var rs: Array = cfg("levels").get("range", [1, 1, 2, 3])
	var r := int(rs[clampi(lvl, 0, rs.size() - 1)])
	if lvl >= 1:
		r += Research.fx_int(state, eid, "port_range") + int(talent(state, eid).get("range", 0))
	return maxi(0, r)


## Compte des colonies d'un empire par état et par flux (tableau d'approvisionnement, prop. 18).
static func supply_table(state: GameState, eid: int) -> Array:
	var counts := [0, 0, 0, 0]
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == eid and c.is_established() and c.is_colony():
			counts[colony_state(state, pid)] += 1
	return counts


## Causes de la desserte d'une colonie, pour l'infobulle : [[libellé, valeur]].
static func service_parts(state: GameState, pid: int) -> Array:
	var c: Colony = state.colonies.get(pid)
	if c == null or state.ports.is_empty():
		return []
	var info: Dictionary = (state.ports.get("why", {}) as Dictionary).get(str(pid), {})
	var out := []
	if info.has("j"):
		if int(info["j"]) <= 0:
			out.append(["Dans la portée d'un port relié", 100])
		else:
			out.append(["%d saut%s au-delà de la portée" % [int(info["j"]), "s" if int(info["j"]) > 1 else ""], -int(info["j"]) * c_int("service", "per_jump")])
	else:
		out.append(["Aucun port relié à portée", 0])
	if int(info.get("pi", 0)) > 0:
		out.append(["Pirates", -int(info["pi"])])
	if int(info.get("fr", 100)) < 100:
		out.append(["Fret insuffisant (%d %%)" % int(info["fr"]), 0])
	if colony_state(state, pid) == ENCLAVE:
		out.append(["Enclave coupée de la capitale", 0])
	out.append(["Plancher", c_int("service", "floor")])
	return out


# --- Calcul du réseau ----------------------------------------------------------------------------

## Recalcule tout (chaque mois, ou dès qu'un port change).
static func refresh(state: GameState) -> void:
	if state.ports.is_empty():
		return
	var old_nodes: Dictionary = state.ports.get("nodes", {})
	state.ports["sv"] = {}
	state.ports["st"] = {}
	state.ports["why"] = {}
	state.ports["fr"] = {}
	var nodes := {}
	# Ports de chaque empire (le plus haut niveau du système), dans l'ordre des colonies.
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if GameState.is_npc(c.owner) or not c.is_established():
			continue
		var sid := state.galaxy.get_planet(pid).system_id
		if WarPeace.occupier(state, sid) >= 0:
			continue
		for b in c.buildings:
			var lvl := building_level(String(b))
			if lvl < 0:
				continue
			var key := _k(c.owner, sid)
			if nodes.has(key) and int(nodes[key]["l"]) >= lvl:
				continue
			var prev: Dictionary = old_nodes.get(key, {})
			var res := int(prev.get("res", -1))
			nodes[key] = {"o": c.owner, "l": lvl, "r": port_range(state, c.owner, lvl), "lk": 0,
					"res": res if res >= 0 else warehouse_max(state, c.owner, lvl), "bk": 0}
	state.ports["nodes"] = nodes
	for e in state.empires:
		if e.is_npc() or e.eliminated:
			continue
		_compute_empire(state, e.id)


static func _passable(state: GameState, eid: int, sid: int, owners_ok: Dictionary) -> bool:
	if Terrain.active(state) and Terrain.blocks_supply(state, sid):
		return false
	var o := state.system_owner(sid)
	if o >= 0 and o != eid:
		if not owners_ok.has(o):
			owners_ok[o] = not GameState.is_npc(o) and Logistics.supplies(state, o, eid)
		if not bool(owners_ok[o]):
			return false
	if full(state) and Logistics.blocks(state, eid, sid):
		return false  # liaison coupée par une flotte ennemie (prop. 20)
	return true


static func _step_cost(state: GameState, sid: int) -> int:
	if Terrain.active(state) and int(Terrain.fx_of(state, sid).get("transit_pct", 0)) > 0:
		return 2
	return 1


## Distances depuis un système, au plus maxd (chemins praticables pour eid ; départ toujours compté).
static func _dist_from(state: GameState, eid: int, from: int, maxd: int, owners_ok: Dictionary, pass_cache: Dictionary) -> Dictionary:
	var dist := {from: 0}
	var buckets: Array = []
	buckets.resize(maxd + 1)
	for i in maxd + 1:
		buckets[i] = []
	(buckets[0] as Array).append(from)
	for d in maxd + 1:
		for sid in buckets[d]:
			if int(dist[sid]) != d:
				continue
			for n in state.galaxy.systems[int(sid)].neighbors:
				if not pass_cache.has(n):
					pass_cache[n] = _passable(state, eid, n, owners_ok)
				if not bool(pass_cache[n]):
					continue
				var nd := d + _step_cost(state, n)
				if nd > maxd:
					continue
				if not dist.has(n) or int(dist[n]) > nd:
					dist[n] = nd
					(buckets[nd] as Array).append(n)
	return dist


static func _compute_empire(state: GameState, eid: int) -> void:
	var sv: Dictionary = state.ports["sv"]
	var st: Dictionary = state.ports["st"]
	var why: Dictionary = state.ports["why"]
	var nodes: Dictionary = state.ports["nodes"]
	var mine: Array[int] = nodes_of(state, eid)
	var is_full := full(state)
	var sc: Dictionary = cfg("service")
	var floor_pct := int(sc["floor"])
	var per_jump := maxi(1, int(sc["per_jump"]))
	@warning_ignore("integer_division")
	var extra := (100 - floor_pct + per_jump - 1) / per_jump
	var owners_ok := {}
	var pass_cache := {}
	# Ports actifs : un port bloqué (mode complet) ou désorganisé ne compte que tant que dure sa réserve.
	var active := {}
	for sid in mine:
		var n: Dictionary = nodes[_k(eid, sid)]
		n["bk"] = 0
		var down := false
		if is_full:
			if Combat.blocks(state, eid, sid):
				n["bk"] = 1
				down = true
			if int((state.ports["dis"] as Dictionary).get(str(sid), 0)) > state.tick or int((state.ports["strike"] as Dictionary).get(str(sid), 0)) > state.tick:
				down = true
		if not down or (is_full and int(n["res"]) > 0):
			active[sid] = true
	# Zones : distances depuis chaque port actif.
	var dists := {}
	for sid in active:
		var n: Dictionary = nodes[_k(eid, sid)]
		dists[sid] = _dist_from(state, eid, sid, int(n["r"]) + (extra if int(n["l"]) >= 1 else 0), owners_ok, pass_cache)
	# Réseau (prop. 5) : depuis la capitale, un port se relie si sa zone touche la zone reliée.
	var root := FactionTraits.capital_system(state, eid)
	if not active.has(root):
		root = -1
		var best_l := -1
		for sid in active:
			if int(nodes[_k(eid, sid)]["l"]) > best_l:
				best_l = int(nodes[_k(eid, sid)]["l"])
				root = sid
	var covered := {}
	var linked_set := {}
	if root >= 0:
		_link(state, eid, root, nodes, dists, covered, linked_set)
		var changed := true
		while changed:
			changed = false
			for sid in mine:
				if linked_set.has(sid) or not active.has(sid):
					continue
				var d: Dictionary = dists[sid]
				var r := int(nodes[_k(eid, sid)]["r"])
				var touches := false
				for s in d:
					if int(d[s]) > r:
						continue
					if covered.has(s):
						touches = true
						break
					for nb in state.galaxy.systems[int(s)].neighbors:
						if covered.has(nb):
							touches = true
							break
					if touches:
						break
				if touches:
					_link(state, eid, sid, nodes, dists, covered, linked_set)
					changed = true
	# Ports coupés qui vivent sur leur réserve (mode complet) : restent reliés tant qu'elle dure.
	for sid in mine:
		var n: Dictionary = nodes[_k(eid, sid)]
		if active.has(sid) and not linked_set.has(sid) and is_full and int(n["res"]) > 0 and int(n["l"]) >= 1:
			linked_set[sid] = true
			n["cut"] = 1
		else:
			n.erase("cut")
		n["lk"] = 1 if linked_set.has(sid) and active.has(sid) else 0
	# Meilleure portée restante par système (ports reliés de niveau 1 et plus) ; zones des non reliés.
	var best := {}
	var enclave := {}
	for sid in active:
		var n: Dictionary = nodes[_k(eid, sid)]
		if int(n["l"]) < 1:
			continue
		var d: Dictionary = dists[sid]
		var r := int(n["r"])
		for s in d:
			if linked_set.has(sid):
				var left := r - int(d[s])
				if not best.has(s) or int(best[s]) < left:
					best[s] = left
			elif int(d[s]) <= r:
				enclave[s] = true
	# Desserte des colonies.
	var tal := talent(state, eid)
	var need := 0
	var colonies: Array[Colony] = []
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != eid or not c.is_established():
			continue
		colonies.append(c)
		var sid := state.galaxy.get_planet(pid).system_id
		var pct := floor_pct
		var cs := ISOLATED
		var info := {}
		if enclave.has(sid) and (not best.has(sid) or int(best[sid]) < 0):
			cs = ENCLAVE
		elif best.has(sid):
			var left := int(best[sid])
			var j := maxi(0, -left)
			info["j"] = j
			pct = maxi(floor_pct, 100 - j * per_jump)
			if c.is_colony() and not nodes.has(_k(eid, sid)):
				need += 1 + mini(5, j)
		if is_full and pct > floor_pct:
			var risk := Trade.risk_at(state, sid)
			if risk > 0:
				var pc: Dictionary = cfg("pirates")
				@warning_ignore("integer_division")
				var loss := int(pc["min_loss"]) + (int(pc["max_loss"]) - int(pc["min_loss"])) * mini(risk, int(pc["risk_max"])) / maxi(1, int(pc["risk_max"]))
				info["pi"] = loss
				pct = maxi(floor_pct, pct - loss)
		sv[str(pid)] = pct
		why[str(pid)] = info
		if cs != ENCLAVE:
			cs = OK if pct >= int(sc["ok_at"]) else (LIMIT if pct >= int(sc["limit_at"]) else ISOLATED)
		st[str(pid)] = cs
	# Fret (prop. 13, mode complet) : la part au-dessus du plancher baisse sous le besoin.
	var avail := 0
	for sid in linked_set:
		avail += int(nodes[_k(eid, sid)]["l"]) * c_int("freight", "per_level")
	if is_full:
		if Private.applies(state, eid):
			avail += Private.usable_cargos(state, eid) * c_int("freight", "per_cargo")
		avail = avail * maxi(0, 100 + Research.fx_int(state, eid, "freight_pct") + int(tal.get("freight_pct", 0))) / 100
		if int((state.ports["sat"] as Dictionary).get(str(eid), 0)) > state.tick:
			avail = avail * int(cfg("events").get("saturated_freight_pct", 75)) / 100
	var ratio := 100
	if is_full and need > 0:
		ratio = mini(100, avail * 100 / need)
	state.ports["fr"][str(eid)] = [need, avail, ratio]
	if ratio < 100:
		for c in colonies:
			var sid := state.galaxy.get_planet(c.planet_id).system_id
			if nodes.has(_k(eid, sid)) and linked_set.has(sid):
				continue
			var key := str(c.planet_id)
			var pct := int(sv[key])
			if pct > floor_pct:
				@warning_ignore("integer_division")
				pct = floor_pct + (pct - floor_pct) * ratio / 100
				sv[key] = pct
				(why[key] as Dictionary)["fr"] = ratio
				if int(st[key]) != ENCLAVE:
					st[key] = OK if pct >= int(sc["ok_at"]) else (LIMIT if pct >= int(sc["limit_at"]) else ISOLATED)


static func _link(state: GameState, eid: int, sid: int, nodes: Dictionary, dists: Dictionary, covered: Dictionary, linked_set: Dictionary) -> void:
	linked_set[sid] = true
	var d: Dictionary = dists[sid]
	var r := int(nodes[_k(eid, sid)]["r"])
	for s in d:
		if int(d[s]) <= r:
			covered[s] = true


## À appeler quand un port change (chantier achevé, port détruit).
static func touch(state: GameState, bid := "") -> void:
	if state.ports.is_empty():
		return
	if bid != "" and building_level(bid) < 0:
		return
	refresh(state)


# --- Jour et mois --------------------------------------------------------------------------------

static func daily(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if state.ports.is_empty():
		return added
	if state.tick % int(GameData.rules()["month_days"]) != 0:
		return added
	_monthly(state, added)
	return added


static func _monthly(state: GameState, added: Array[Dictionary]) -> void:
	var is_full := full(state)
	var md := int(GameData.rules()["month_days"])
	if is_full:
		_reserves(state, md, added)
		PortsBridges.monthly(state, added)
	refresh(state)
	if is_full:
		_blockades(state, added)
		_hunger(state)
	for k in ["dis", "strike", "sat"]:
		var d: Dictionary = state.ports[k]
		for key in d.keys():
			if int(d[key]) <= state.tick:
				d.erase(key)


## Entrepôts (prop. 17) : un port coupé ou bloqué entame sa réserve, un port relié la recharge.
static func _reserves(state: GameState, md: int, added: Array[Dictionary]) -> void:
	var nodes: Dictionary = state.ports["nodes"]
	var keys := nodes.keys()
	keys.sort()
	for key in keys:
		var n: Dictionary = nodes[key]
		var eid := int(n["o"])
		var mx := warehouse_max(state, eid, int(n["l"]))
		var cut := int(n.get("bk", 0)) == 1 or int(n.get("cut", 0)) == 1
		if cut:
			var before := int(n["res"])
			n["res"] = maxi(0, before - md)
			if before > 0 and int(n["res"]) == 0:
				added.append(state.add_chronicle("%s : les entrepôts de %s sont vides. Le port coupé ne nourrit plus personne." % [
						state.get_empire(eid).short_name(), state.galaxy.systems[_sid(key)].system_name], Espionage.private_to(state, [eid], _sid(key))))
		else:
			n["res"] = mini(mx, int(n["res"]) + c_int("warehouse", "refill") * md)


## Blocus (prop. 19, 22, 24) : annonce, puis pillage chaque mois par l'empire qui bloque.
static func _blockades(state: GameState, added: Array[Dictionary]) -> void:
	var nodes: Dictionary = state.ports["nodes"]
	var bk: Dictionary = state.ports["bk"]
	var keys := nodes.keys()
	keys.sort()
	var now := {}
	for key in keys:
		var n: Dictionary = nodes[key]
		if int(n.get("bk", 0)) != 1 or int(n["l"]) < 1:
			continue
		var sid := _sid(key)
		var eid := int(n["o"])
		now[key] = 1
		var by := _blockader(state, eid, sid)
		var victim := state.get_empire(eid)
		if not bk.has(key):
			added.append(state.add_chronicle("Blocus : %s ferme le %s de %s. Les cargos font demi-tour, les entrepôts comptent les jours." % [
					state.get_empire(by).short_name() if by >= 0 else "L'ennemi", level_label(int(n["l"])).to_lower(), state.galaxy.systems[sid].system_name],
					Espionage.private_to(state, [eid, by] if by >= 0 else [eid], sid)))
		if by >= 0:
			var loot := int(n["l"]) * c_int("blockade", "loot_per_level")
			var eb := state.get_empire(by)
			for r in ["energy", "materials"]:
				var take := mini(loot, maxi(0, int(victim.resources.get(r, 0))))
				victim.resources[r] = int(victim.resources.get(r, 0)) - take
				eb.resources[r] = int(eb.resources.get(r, 0)) + take
	state.ports["bk"] = now


static func _blockader(state: GameState, eid: int, sid: int) -> int:
	for f in Fleets.fleets_at(state, sid):
		if f.owner >= 0 and not GameState.is_npc(f.owner) and Combat.at_war(state, f.owner, eid) and Combat.is_armed(f):
			return f.owner
	return -1


## Nourriture des enclaves (prop. 16) : une enclave qui mange plus qu'elle ne produit cesse de grandir.
static func _hunger(state: GameState) -> void:
	var hg := {}
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if not c.is_colony() or colony_state(state, pid) != ENCLAVE:
			continue
		if bool(talent(state, c.owner).get("enclave_fed", false)):
			continue
		var y := Economy.colony_yields(state, c)
		var diet := FactionTraits.diet(state.get_empire(c.owner).faction())
		if int(y["gross"].get(diet, 0)) < int(y["upkeep"].get(diet, 0)):
			hg[str(pid)] = 1
	state.ports["hg"] = hg


static func hungry(state: GameState, c: Colony) -> bool:
	return not state.ports.is_empty() and (state.ports["hg"] as Dictionary).has(str(c.planet_id))


# --- Flux et ponts lus ailleurs ------------------------------------------------------------------

## Un jour de chantier perdu dans une colonie mal desservie (prop. 14, mode complet).
static func skip_build(state: GameState, c: Colony) -> bool:
	if not full(state):
		return false
	var cs := colony_state(state, c.planet_id)
	if cs == OK:
		return false
	var bs: Dictionary = cfg("flows").get("build_skip", {})
	var every := int(bs.get("limit", 4)) if cs == LIMIT else int(bs.get("isolated", 2))
	return every > 0 and posmod(state.tick, every) == 0


## Jours de chantier spatial gagnés aujourd'hui dans ce système (prop. 12).
static func ship_bonus(state: GameState, eid: int, sid: int) -> int:
	var lvl := port_level_at(state, eid, sid)
	if lvl < 2:
		return 0
	var every: Array = cfg("shipyard").get("bonus_every", [])
	var k := int(every[lvl]) if lvl < every.size() else 0
	return 1 if k > 0 and posmod(state.tick, k) == 0 else 0


## Luxes mal distribués (prop. 15) : une ligne de stabilité dans un système mal desservi.
static func system_stability_parts(state: GameState, sid: int) -> Array:
	if not full(state):
		return []
	var eid := state.system_owner(sid)
	if eid < 0 or GameState.is_npc(eid):
		return []
	var cs := system_state(state, eid, sid)
	if cs == OK:
		return []
	var parts := Goods.stability_parts(state, eid)
	if parts.is_empty():
		return []
	var lux := int(parts[0][1])
	if lux <= 0:
		return []
	var lp: Dictionary = cfg("flows").get("luxury_pct", {})
	var keep := int(lp.get("limit", 50)) if cs == LIMIT else int(lp.get("isolated", 0))
	@warning_ignore("integer_division")
	var loss := lux * (100 - keep) / 100
	return [["Luxes mal distribués (%s)" % state_label(cs).to_lower(), -loss]] if loss > 0 else []


## Un port de ce système sert-il de dépôt de flotte (prop. 23) ?
static func depot_at(state: GameState, sid: int, holder: int) -> bool:
	return full(state) and port_level_at(state, holder, sid) >= 2


## Bonus des routes commerciales (prop. 26) : % par niveau du meilleur port relié au-delà du premier.
static func route_pct(state: GameState, eid: int) -> int:
	if not full(state):
		return 0
	var best := 0
	for sid in nodes_of(state, eid):
		if linked(state, eid, sid):
			best = maxi(best, int(node(state, eid, sid)["l"]))
	return maxi(0, best - 1) * c_int("trade", "route_pct")


## Revenus de l'État (prop. 25, 27) : droits de port, entretien des balises repris par le privé.
static func income(state: GameState, eid: int) -> Dictionary:
	if not full(state):
		return {}
	var levels := 0
	var beacons := 0
	for sid in nodes_of(state, eid):
		var n := node(state, eid, sid)
		if int(n["l"]) == 0:
			beacons += 1
		elif int(n.get("lk", 0)) == 1:
			levels += int(n["l"])
	var tax_pct := 100
	if Finance.applies(state, eid):
		tax_pct = int((cfg("dues").get("tax_pct", {}) as Dictionary).get(Finance.tax(state, eid), 100))
	@warning_ignore("integer_division")
	var en := levels * c_int("dues", "per_level") * tax_pct / 100
	if beacons > 0 and Private.applies(state, eid):
		en += beacons * c_int("private", "beacon_upkeep")
	return {"energy": en} if en > 0 else {}


## Droits de quai versés au privé chaque mois (prop. 25).
static func dock_fees(state: GameState, eid: int) -> int:
	if not full(state):
		return 0
	var levels := 0
	for sid in nodes_of(state, eid):
		var n := node(state, eid, sid)
		if int(n["l"]) >= 1 and int(n.get("lk", 0)) == 1:
			levels += int(n["l"])
	return levels * c_int("private", "dock_fees")


static func beacon_count(state: GameState, eid: int) -> int:
	var n := 0
	for sid in nodes_of(state, eid):
		if int(node(state, eid, sid)["l"]) == 0:
			n += 1
	return n


# --- IA (prop. 33) -------------------------------------------------------------------------------

## Port souhaité par l'IA pour cette colonie ("" sinon).
static func ai_wish(state: GameState, eid: int, c: Colony) -> String:
	if state.ports.is_empty() or not c.is_established():
		return ""
	var e := state.get_empire(eid)
	var sid := state.galaxy.get_planet(c.planet_id).system_id
	var lvl := port_level_at(state, eid, sid)
	if c.buildings.has("comptoir") and c.is_colony() and c.population >= 3 and Economy.building_unlocked(state, eid, "spatioport"):
		return "spatioport"
	if c.buildings.has("spatioport") and c.population >= 5 and Economy.building_unlocked(state, eid, "grand_port") and int(e.resources.get("materials", 0)) >= 500:
		return "grand_port"
	if lvl >= 0:
		return ""
	var cs := colony_state(state, c.planet_id)
	if cs >= ISOLATED and c.is_colony() and c.population >= 3:
		return "comptoir"
	if cs >= ISOLATED and not c.is_colony():
		return "balise_fret"
	return ""
