class_name Logistics
extends RefCounted
## Logistique et ravitaillement (étude du 2026-11-15, 30 propositions validées ; data/logistics.json).
##
## Option de partie « Logistique » : "aucune" (règles d'avant), "simple" ou "complete".
## - Zone de ravitaillement d'un empire : les systèmes tenus par lui ou par ceux qui le ravitaillent
##   (alliés, équipe, suzerain et sujets, même Koinon, coalition, libre-passage, frontière ouverte,
##   passage imposé), plus `range` sauts autour (technologies, talents), plus un saut autour des
##   dépôts de flotte. Un système occupé ou pris à l'ennemi n'est une source qu'après `bridge_days`
##   jours sans bataille (tête de pont). Routes commerciales actives, ports francs, flotte-ville de la
##   horde et loi de navigation de l'Amphictyonie l'étendent aussi.
## - Une flotte ARMÉE d'un empire (pas les vaisseaux civils, ni pirates ni créatures) est Ravitaillée
##   dans la zone, Étirée au-dehors, Coupée (mode complet) si tout chemin vers la zone passe par un
##   système tenu par une flotte ennemie sans flotte amie.
## - Réserves en jours : `autonomy_days` (+ technologies, talents, intendant, soute de ravitaillement).
##   Hors zone, -1 par jour (x2 Coupée, x2 en bataille ou en siège en mode complet, x2 en territoire
##   clos sans droit) ; en zone, +`refill_per_day`. À zéro : plus de réparation, dégâts -2 % par
##   semaine jusqu'à -30 %. Jamais de vaisseau ni de point de structure perdu sans combat.
## - Flotte à quai (immobile chez elle avec chantier ou dépôt) : -25 % d'entretien.
## Aucun surcoût d'entretien à distance, aucun plafond de flotte (consigne de l'utilisateur).
##
## state.logistics = {"mode", "res": {"<flotte>": réserves}, "ex": {"<flotte>": jours à sec},
##   "cut": {"<flotte>": jours coupée}, "hold": {"<système>": [tenant, depuis]}, "rq": {"<système>":
##   prochaine réquisition}, "sab": {"<empire>": fin du sabotage des dépôts}, "gr": {"<empire>:<système>":
##   jours hors zone des régiments}, "wn": {"<flotte>": 1} (lassitude déjà comptée ce mois)}.
## state.log_cache (dérivé, non sauvegardé) : zones et lignes du jour, recalculées à chaque tick.
## Tout est déterministe : parcours dans l'ordre des identifiants, aucun aléatoire.

const NONE := "aucune"
const SIMPLE := "simple"
const FULL := "complete"
const MODES: Array[String] = ["aucune", "simple", "complete"]
const OK := "ok"
const OUT := "out"
const CUT := "cut"
const DEPOT := "depot_flotte"

static var _talent_cache := {}


static func data() -> Dictionary:
	return GameData.logistics()


static func _cfg(k: String) -> Variant:
	return data().get(k, {})


static func mode_defs() -> Array:
	return data().get("modes", [])


static func _blank() -> Dictionary:
	return {"mode": NONE, "res": {}, "ex": {}, "cut": {}, "hold": {}, "rq": {}, "sab": {}, "gr": {}, "wn": {}}


static func setup(state: GameState, mode: String) -> void:
	state.logistics = _blank()
	state.logistics["mode"] = mode if MODES.has(mode) else NONE
	state.log_cache = {}


static func to_dict(state: GameState) -> Dictionary:
	return state.logistics.duplicate(true)


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.logistics = _blank()
	for k in d:
		state.logistics[k] = Vassals._ints(d[k])
	if not MODES.has(String(state.logistics.get("mode", ""))):
		state.logistics["mode"] = NONE
	state.log_cache = {}


static func worth_saving(state: GameState) -> bool:
	return active(state)


static func mode(state: GameState) -> String:
	return String(state.logistics.get("mode", NONE))


static func active(state: GameState) -> bool:
	return mode(state) != NONE


static func full(state: GameState) -> bool:
	return mode(state) == FULL


static func _l(state: GameState) -> Dictionary:
	var blank := _blank()
	for k in blank:
		if not state.logistics.has(k):
			state.logistics[k] = blank[k]
	return state.logistics


static func state_label(st: String) -> String:
	return String((_cfg("states") as Dictionary).get(st, {}).get("label", st))


static func state_text(st: String) -> String:
	return String((_cfg("states") as Dictionary).get(st, {}).get("text", ""))


static func _name(state: GameState, eid: int) -> String:
	var e := state.get_empire(eid)
	return e.display_name() if e != null else "?"


static func _sys(state: GameState, sid: int) -> String:
	return state.galaxy.systems[sid].system_name


# --- Talents de peuple (prop. 25, 26) --------------------------------------------------------------

## Talent de logistique d'un empire par ses couches d'espèce ({} sinon). Les nombres s'additionnent,
## les drapeaux s'ajoutent ; un peuple créé dans l'éditeur en profite comme un peuple officiel.
static func talent(state: GameState, eid: int) -> Dictionary:
	var e := state.get_empire(eid)
	if e == null or e.is_npc():
		return {}
	var ck := "%s:%s:%s" % [e.faction_id, str(e.faction().get("species", {})), String(e.faction().get("registre", ""))]
	if _talent_cache.has(ck):
		return _talent_cache[ck]
	var out := {}
	var sp := FactionTraits.species(e.faction())
	var table: Dictionary = _cfg("talents")
	for layer in ["traits", "archetype", "gouvernement", "credo", "registre"]:
		var t: Dictionary = table.get(layer, {})
		var values: Array = sp.get("traits", []) if layer == "traits" else [String(sp.get(layer, ""))]
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
				else:
					out[k] = int(out.get(k, 0)) + int(d[k])
	_talent_cache[ck] = out
	return out


static func talent_labels(state: GameState, eid: int) -> Array:
	return talent(state, eid).get("labels", [])


# --- Qui ravitaille qui (prop. 2) ------------------------------------------------------------------

## Les systèmes tenus par o ravitaillent-ils les flottes de eid ?
static func supplies(state: GameState, o: int, eid: int) -> bool:
	if o < 0 or eid < 0:
		return false
	if o == eid:
		return true
	if GameState.is_npc(o) or GameState.is_npc(eid) or Combat.at_war(state, o, eid):
		return false
	if Borders.strong_link(state, o, eid):
		return true
	if Borders.has_treaty(state, o, eid) or Borders.forced(state, o, eid):
		return true
	return Borders.active(state) and Borders.policy(state, o, eid) == Borders.OPEN


## Portée de la zone autour des systèmes tenus (en sauts).
static func range_of(state: GameState, eid: int) -> int:
	return maxi(0, int(_cfg("range")) + Research.fx_int(state, eid, "supply_range") + int(talent(state, eid).get("range", 0)))


## Le tenant de ce système l'a-t-il depuis assez longtemps (tête de pont, prop. 8) ?
static func bridge_ok(state: GameState, sid: int, holder: int) -> bool:
	var h: Variant = (_l(state)["hold"] as Dictionary).get(str(sid))
	if h == null or int(h[0]) != holder:
		return true  # pas encore vu : système de départ ou fondé, tenu d'office
	return state.tick - int(h[1]) >= bridge_days(state, holder)


static func bridge_days(state: GameState, eid: int) -> int:
	var d := int(_cfg("bridge_days"))
	return maxi(1, d * maxi(10, 100 + Research.fx_int(state, eid, "bridge_days_pct")) / 100)


## Dépôt de flotte actif dans ce système pour ce tenant (bâtiment, pas saboté).
static func has_depot(state: GameState, sid: int, holder := -1) -> bool:
	if holder < 0:
		holder = WarPeace.holder(state, sid)
	if holder < 0 or int((_l(state)["sab"] as Dictionary).get(str(holder), 0)) > state.tick:
		return false
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == holder and c.is_established() and c.buildings.has(DEPOT):
			return true
	if Megastructures.depot_at(state, sid, holder):
		return true  # Siphon de géante achevé
	return Ports.depot_at(state, sid, holder)  # un Spatioport sert de dépôt (spatioports complets)


## Zone de ravitaillement de eid : {système: portée restante}. Recalculée une fois par jour.
static func zone(state: GameState, eid: int) -> Dictionary:
	var cache := state.log_cache
	if int(cache.get("t", -1)) != state.tick:
		cache.clear()
		cache["t"] = state.tick
		cache["z"] = {}
		cache["cut"] = {}
		cache["armed"] = null
	var zs: Dictionary = cache["z"]
	if zs.has(eid):
		return zs[eid]
	var z := _compute_zone(state, eid)
	zs[eid] = z
	return z


static func _compute_zone(state: GameState, eid: int) -> Dictionary:
	var g := state.galaxy
	var rng := range_of(state, eid)
	var depot_r := int((_cfg("depot") as Dictionary).get("range", 1))
	var best := {}
	var maxr := 0
	var holders_ok := {}
	for s in g.systems:
		var sid := s.id
		var h := WarPeace.holder(state, sid)
		if h < 0:
			continue
		if not holders_ok.has(h):
			holders_ok[h] = supplies(state, h, eid)
		if not bool(holders_ok[h]) or not bridge_ok(state, sid, h):
			continue
		var r := rng
		if has_depot(state, sid, h):
			r += depot_r
		if int(best.get(sid, -1)) < r:
			best[sid] = r
			maxr = maxi(maxr, r)
	# Flotte-ville de la horde : un dépôt mobile (talent).
	if bool(talent(state, eid).get("mobile_depot", false)):
		var cf := FactionTraits.city_fleet(state, eid)
		if cf != null and int(best.get(cf.system_id, -1)) < rng:
			best[cf.system_id] = rng
			maxr = maxi(maxr, rng)
	# Diffusion par portée décroissante.
	var buckets: Array = []
	buckets.resize(maxr + 1)
	for i in maxr + 1:
		buckets[i] = []
	for sid in best:
		(buckets[int(best[sid])] as Array).append(sid)
	# Terrain (voir Terrain) : une tempête ou une nébuleuse ionisée arrête les convois.
	var walled := {}
	if Terrain.active(state):
		for s in g.systems:
			if Terrain.blocks_supply(state, s.id):
				walled[s.id] = true
	# Portails (prop. 17) : un saut le long d'un corridor de relais coûte supply_jumps de moins.
	var corr := Portals.enabled(state) and not g.relays.is_empty()
	var cj := int(Portals.cfg("relays").get("supply_jumps", 1)) if corr else 0
	for r in range(maxr, 0, -1):
		var bucket: Array = buckets[r]
		var bi := 0
		while bi < bucket.size():
			var sid: int = int(bucket[bi])
			bi += 1
			if int(best[sid]) != r:
				continue
			for n in g.systems[sid].neighbors:
				if walled.has(n):
					continue
				var nr := r - 1
				if corr and Portals.corridor(state, eid, sid, int(n)):
					nr = mini(r, r - 1 + cj)
				if int(best.get(n, -1)) < nr:
					best[n] = nr
					(buckets[nr] as Array).append(n)
	# Couloirs sans portée : routes commerciales libres (prop. 14), espace neutre sous la
	# Convention de ravitaillement de l'Amphictyonie (prop. 22).
	for r: Dictionary in Trade.routes_of(state, eid):
		if bool(r.get("blocked", false)):
			continue
		for sid in r.get("path", []):
			if not best.has(int(sid)):
				best[int(sid)] = 0
	if state.amph_on and Amphictyony.is_member(state, eid) and Amphictyony._level_flag(state, "supply_neutral"):
		for s in g.systems:
			if not best.has(s.id) and state.system_owner(s.id) < 0:
				best[s.id] = 0
	return best


static func in_zone(state: GameState, eid: int, sid: int) -> bool:
	return zone(state, eid).has(sid)


# --- État d'une flotte (prop. 1, 5, 6) -------------------------------------------------------------

## La logistique s'applique-t-elle à cette flotte (armée, d'un empire) ?
static func applies(state: GameState, f: Fleet) -> bool:
	return active(state) and f != null and not GameState.is_npc(f.owner) and f.owner >= 0 and Combat.is_armed(f)


static func status(state: GameState, f: Fleet) -> String:
	if not applies(state, f):
		return OK
	if in_zone(state, f.owner, f.system_id):
		return OK
	if full(state) and _is_cut(state, f):
		return CUT
	return OUT


## Systèmes où une flotte armée ennemie tient la place (pour couper les lignes) : {système: [empires]}.
static func _armed_at(state: GameState) -> Dictionary:
	zone(state, -1)  # remet le cache du jour à neuf si besoin
	if state.log_cache.get("armed") != null:
		return state.log_cache["armed"]
	var m := {}
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.owner < 0 or GameState.is_npc(f.owner) or not Combat.is_armed(f):
			continue
		var l: Array = m.get(f.system_id, [])
		if not l.has(f.owner):
			l.append(f.owner)
		m[f.system_id] = l
	state.log_cache["armed"] = m
	return m


## Ce système barre-t-il la route aux convois de eid (ennemi armé, aucune flotte amie) ?
static func blocks(state: GameState, eid: int, sid: int) -> bool:
	var owners: Array = _armed_at(state).get(sid, [])
	var enemy := false
	for o in owners:
		if int(o) == eid or Borders.strong_link(state, int(o), eid):
			return false
		if Combat.at_war(state, int(o), eid):
			enemy = true
	return enemy


static func _is_cut(state: GameState, f: Fleet) -> bool:
	if bool(talent(state, f.owner).get("never_cut", false)):
		return false
	var cache: Dictionary = state.log_cache["cut"]
	if cache.has(f.id):
		return bool(cache[f.id])
	var z := zone(state, f.owner)
	# Intendant (prop. 12) : un seul système ennemi ne suffit pas à couper la flotte.
	var pass_one := Heroes.trait_fx(Heroes.at_post(state, "fleet", f.id, f.owner), "supply_pass") > 0
	var seen := {[f.system_id, 0]: true}
	var frontier: Array = [[f.system_id, 0]]
	var cut := true
	while not frontier.is_empty() and cut:
		var nxt: Array = []
		for node in frontier:
			for n in state.galaxy.systems[int(node[0])].neighbors:
				var used := int(node[1])
				if blocks(state, f.owner, n):
					if not pass_one or used >= 1:
						continue
					used += 1
				if z.has(n):
					cut = false
					break
				var key := [n, used]
				if not seen.has(key):
					seen[key] = true
					nxt.append(key)
			if not cut:
				break
		frontier = nxt
	cache[f.id] = cut
	return cut


## Réserves maximales d'une flotte, en jours.
static func autonomy(state: GameState, f: Fleet) -> int:
	var pct := 100 + Research.fx_int(state, f.owner, "autonomy_pct") + int(talent(state, f.owner).get("autonomy_pct", 0))
	pct += Heroes.trait_fx(Heroes.at_post(state, "fleet", f.id, f.owner), "autonomy_pct")
	if Combat._fleet_has_flag(f, "supply_hold"):
		pct += int((_cfg("supply_hold") as Dictionary).get("autonomy_pct", 100))
	if Combat._fleet_has_flag(f, "cold_blood"):
		pct += 100  # Sang-froid (coque de peuple reptilienne) : autonomie doublée
	return maxi(10, int(_cfg("autonomy_days")) * maxi(10, pct) / 100)


static func reserves(state: GameState, f: Fleet) -> int:
	return int((_l(state)["res"] as Dictionary).get(str(f.id), autonomy(state, f)))


static func dry_days(state: GameState, f: Fleet) -> int:
	return int((_l(state)["ex"] as Dictionary).get(str(f.id), 0))


static func exhausted(state: GameState, f: Fleet) -> bool:
	return applies(state, f) and reserves(state, f) <= 0 and status(state, f) != OK


## Malus de dégâts (en points de %) d'une flotte à sec (prop. 4).
static func damage_pct(state: GameState, f: Fleet) -> int:
	if not applies(state, f):
		return 0
	var ex := dry_days(state, f)
	if ex <= 0:
		return 0
	var c: Dictionary = _cfg("exhausted")
	@warning_ignore("integer_division")
	return -mini(int(c.get("damage_pct_max", 30)), int(c.get("damage_pct_per_week", 2)) * ((ex + 6) / 7))


## Réparation du jour (en %) en tenant compte de la logistique ; base = taux d'avant.
static func repair_pct(state: GameState, f: Fleet, base: int) -> int:
	if not active(state):
		return base
	var pct := base
	if not f.is_moving() and has_depot(state, f.system_id) and supplies(state, WarPeace.holder(state, f.system_id), f.owner):
		pct = maxi(pct, int((_cfg("depot") as Dictionary).get("repair_pct", 8)))
	if exhausted(state, f) and not Combat._fleet_has_flag(f, "fleet_repair") and not bool(Combat.trait_value(state, f.owner, "repair_anywhere", false)):
		pct = int((_cfg("supply_hold") as Dictionary).get("repair_pct", 1)) if Combat._fleet_has_flag(f, "supply_hold") else 0
	return pct


## Flotte à quai : immobile, chez un ravitailleur, avec chantier ami ou dépôt (prop. 17).
static func docked(state: GameState, f: Fleet) -> bool:
	if not active(state) or f.is_moving() or GameState.is_npc(f.owner) or not Combat.is_armed(f):
		return false
	if not Combat.battle_at(state, f.system_id).is_empty():
		return false
	if Fleets.has_own_yard(state, f.owner, f.system_id):
		return true
	return has_depot(state, f.system_id) and supplies(state, WarPeace.holder(state, f.system_id), f.owner)


static func docked_upkeep_pct() -> int:
	return int(_cfg("docked_upkeep_pct"))


# --- Chaque jour (prop. 3-7, 18-19, 21, 23, 24) -----------------------------------------------------

static func daily(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if not active(state):
		return added
	var l := _l(state)
	_update_holds(state)
	state.log_cache.clear()  # zones du jour recalculées avec les têtes de pont à jour
	var res: Dictionary = l["res"]
	var ex: Dictionary = l["ex"]
	var cut: Dictionary = l["cut"]
	var wn: Dictionary = l["wn"]
	var month := state.tick % int(GameData.rules()["month_days"]) == 0
	if month:
		wn.clear()
	var alive := {}
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if not applies(state, f):
			continue
		var k := str(fid)
		alive[k] = true
		var aut := autonomy(state, f)
		var cur := int(res.get(k, aut))
		var st := status(state, f)
		if st == OK:
			cur = mini(aut, cur + int(_cfg("refill_per_day")))
			ex.erase(k)
			cut.erase(k)
		elif _free_port(state, f) or (st != CUT and Private.supplies(state, f)):
			cur = aut
			ex.erase(k)
			cut.erase(k)
		else:
			var use := 1
			if st == CUT:
				use *= int(_cfg("cut_mult"))
				if not cut.has(k):
					added.append(state.add_chronicle("La %s est coupée de ses arrières à %s : plus aucun convoi ne passe, les rations fondent deux fois plus vite." % [
							f.fleet_name, _sys(state, f.system_id)], [f.owner]))
				cut[k] = int(cut.get(k, 0)) + 1
				_weariness(state, f, int(cut[k]))
			else:
				cut.erase(k)
			if full(state) and (not Combat.battle_at(state, f.system_id).is_empty() or _besieging(state, f)):
				use *= int(_cfg("battle_mult"))
			if _closed_trespass(state, f):
				use *= int(_cfg("closed_mult"))
			var before := cur
			cur = maxi(0, cur - use)
			if cur <= 0:
				if before > 0:
					added.append(state.add_chronicle("La %s a vidé ses soutes à %s : plus de pièces de rechange, plus de munitions de réserve. Il faut rentrer, ou tenir avec ce qu'on a." % [
							f.fleet_name, _sys(state, f.system_id)], [f.owner]))
				ex[k] = int(ex.get(k, 0)) + 1
		if cur >= aut:
			res.erase(k)
		else:
			res[k] = cur
	for d: Dictionary in [res, ex, cut, wn]:
		for k in d.keys():
			if not alive.has(k):
				d.erase(k)
	if full(state) and Ground.full(state):
		_ground_supply(state)
	return added


## Tenants des systèmes : le jour où chacun a changé de mains, remis à zéro par une bataille tant que
## la tête de pont n'est pas tenue (prop. 8).
static func _update_holds(state: GameState) -> void:
	var hold: Dictionary = _l(state)["hold"]
	for s in state.galaxy.systems:
		var sid := s.id
		var k := str(sid)
		var h := WarPeace.holder(state, sid)
		if h < 0:
			hold.erase(k)
			continue
		var cur: Variant = hold.get(k)
		if cur == null:
			hold[k] = [h, -100000]  # tenu depuis toujours (départ, fondation)
		elif int(cur[0]) != h:
			hold[k] = [h, state.tick]  # pris ou occupé : tête de pont à tenir
		elif state.tick - int(cur[1]) < bridge_days(state, h) and not Combat.battle_at(state, sid).is_empty():
			hold[k] = [h, state.tick]


static func _besieging(state: GameState, f: Fleet) -> bool:
	if f.is_moving():
		return false
	var sg: Variant = state.sieges.get(f.system_id)
	return sg != null and int((sg as Dictionary).get("by", -1)) == f.owner


## Frontière close (prop. 21) : flotte sans droit dans un territoire qui lui est fermé.
static func _closed_trespass(state: GameState, f: Fleet) -> bool:
	if not Borders.active(state):
		return false
	var o := state.system_owner(f.system_id)
	if o < 0 or o == f.owner or Combat.at_war(state, o, f.owner):
		return false
	return Borders.policy(state, o, f.owner) == Borders.CLOSED and not Borders.fleet_right(state, f, o)


## Port franc (prop. 24) : ravitaille contre de l'énergie, gratuitement pour les amis des ports francs.
static func _free_port(state: GameState, f: Fleet) -> bool:
	if f.is_moving() or not Pirates.is_port(state, f.system_id):
		return false
	if bool(talent(state, f.owner).get("free_ports", false)):
		return true
	var e := state.get_empire(f.owner)
	var cost: Dictionary = _cfg("free_port_cost")
	for r in cost:
		if int(e.resources.get(r, 0)) < int(cost[r]):
			return false
	for r in cost:
		e.resources[r] = int(e.resources.get(r, 0)) - int(cost[r])
	return true


## Lassitude (prop. 23) : une flotte coupée depuis longtemps pèse sur le moral à l'arrière.
static func _weariness(state: GameState, f: Fleet, days: int) -> void:
	if not state.wars_on or days < int((_cfg("weariness") as Dictionary).get("after_days", 60)):
		return
	var wn: Dictionary = _l(state)["wn"]
	if wn.has(str(f.id)):
		return
	var e := state.get_empire(f.owner)
	var other := state.system_owner(f.system_id)
	if other < 0 or not e.wars.has(other):
		if e.wars.is_empty():
			return
		var ws := e.wars.duplicate()
		ws.sort()
		other = ws[0]
	var rec := Wars.war(state, f.owner, other)
	if rec.is_empty():
		return
	wn[str(f.id)] = 1
	WarPeace.add_ex(rec, f.owner, int((_cfg("weariness") as Dictionary).get("points", 1)))


# --- Régiments et encerclement (prop. 18, 19) -------------------------------------------------------

## Régiments au sol hors de la zone de leur empire : jours passés, puis moral qui fond.
static func _ground_supply(state: GameState) -> void:
	var gr: Dictionary = _l(state)["gr"]
	var seen := {}
	var gc: Dictionary = _cfg("ground")
	for rid in Ground._sorted_ids(state):
		var r: Dictionary = state.ground["r"][str(rid)]
		if int(r["f"]) >= 0:
			continue
		var o := int(r["o"])
		var sid := int(r["s"])
		if in_zone(state, o, sid):
			continue
		var k := "%d:%d" % [o, sid]
		if not seen.has(k):
			seen[k] = true
			gr[k] = int(gr.get(k, 0)) + 1
		if int(gr[k]) <= int(_cfg("autonomy_days")):
			continue
		var loss := int(gc.get("morale_loss", 2))
		if _ground_cut(state, o, sid):
			loss *= int(gc.get("cut_morale_mult", 2))
		r["mo"] = maxi(1, int(r["mo"]) - loss)
	for k in gr.keys():
		if not seen.has(k):
			gr.erase(k)


## Les régiments de eid à sid sont-ils sans ravitaillement (réserves épuisées) ?
static func ground_unsupplied(state: GameState, eid: int, sid: int) -> bool:
	if not (full(state) and Ground.full(state)):
		return false
	return int((_l(state)["gr"] as Dictionary).get("%d:%d" % [eid, sid], 0)) > int(_cfg("autonomy_days"))


static func _ground_cut(state: GameState, eid: int, sid: int) -> bool:
	if bool(talent(state, eid).get("never_cut", false)):
		return false
	var z := zone(state, eid)
	var seen := {sid: true}
	var frontier: Array[int] = [sid]
	while not frontier.is_empty():
		var nxt: Array[int] = []
		for s in frontier:
			for n in state.galaxy.systems[s].neighbors:
				if seen.has(n) or blocks(state, eid, n):
					continue
				if z.has(n):
					return false
				seen[n] = true
				nxt.append(n)
		frontier = nxt
	return true


## Planète assiégée encerclée (mode complet) : tous les systèmes voisins sont tenus par l'ennemi
## (système ennemi en guerre, ou flotte ennemie armée sans flotte amie).
static func encircled(state: GameState, sid: int) -> bool:
	if not full(state):
		return false
	var d := WarPeace.holder(state, sid)
	if d < 0 or GameState.is_npc(d):
		return false
	var ns: Array = state.galaxy.systems[sid].neighbors
	if ns.is_empty():
		return false
	for n in ns:
		var h := WarPeace.holder(state, int(n))
		if h >= 0 and Combat.at_war(state, h, d):
			continue
		if blocks(state, d, int(n)):
			continue
		return false
	return true


static func encircled_loss(key: String) -> int:
	return int((_cfg("encircled") as Dictionary).get(key, 1))


# --- Fusion et scission --------------------------------------------------------------------------

static func on_split(state: GameState, f: Fleet, nf: Fleet) -> void:
	if not active(state):
		return
	var l := _l(state)
	for d: Dictionary in [l["res"], l["ex"], l["cut"]]:
		if d.has(str(f.id)):
			d[str(nf.id)] = d[str(f.id)]


## La flotte qui absorbe garde les plus basses réserves des deux (pas de plein par fusion).
static func on_merge(state: GameState, from_id: int, into_id: int) -> void:
	if not active(state):
		return
	var l := _l(state)
	var a := str(from_id)
	var b := str(into_id)
	var res: Dictionary = l["res"]
	if res.has(a):
		res[b] = mini(int(res[a]), int(res.get(b, 1 << 30)))
	var ex: Dictionary = l["ex"]
	if ex.has(a):
		ex[b] = maxi(int(ex[a]), int(ex.get(b, 0)))
	for d: Dictionary in [res, ex, l["cut"]]:
		d.erase(a)


# --- Réquisition (prop. 13) ----------------------------------------------------------------------

static func check_requisition(state: GameState, eid: int, fid: int) -> String:
	if not full(state):
		return "la réquisition demande la logistique complète"
	var f: Fleet = state.fleets.get(fid)
	if f == null or f.owner != eid:
		return "flotte inconnue"
	if not applies(state, f):
		return "seules les flottes armées ont des réserves"
	if not _besieging(state, f):
		return "il faut assiéger un système ennemi peuplé"
	var owner := state.system_owner(f.system_id)
	if owner < 0 or Vassals.system_pop(state, f.system_id, owner) <= 0:
		return "personne à réquisitionner ici"
	if int((_l(state)["rq"] as Dictionary).get(str(f.system_id), 0)) > state.tick:
		return "ce système a déjà été pressé jusqu'au dernier grain"
	if reserves(state, f) >= autonomy(state, f):
		return "les soutes sont déjà pleines"
	return ""


static func requisition(state: GameState, eid: int, fid: int) -> void:
	var f: Fleet = state.fleets[fid]
	var sid := f.system_id
	var owner := state.system_owner(sid)
	var c: Dictionary = _cfg("requisition")
	var l := _l(state)
	(l["res"] as Dictionary).erase(str(fid))
	(l["ex"] as Dictionary).erase(str(fid))
	l["rq"][str(sid)] = state.tick + int(c.get("cooldown_days", 180))
	var free := bool(talent(state, eid).get("requisition_free", false))
	if Ground.full(state):
		GroundSiege.add_dev(state, sid, int(c.get("devastation", 10)))
	if Stability.applies(state, owner):
		var en := Stability._entry_w(state, sid)
		en["v"] = clampi(int(en.get("v", 50)) + int(c.get("stability", -10)), 0, 100)
	if not free:
		Diplomacy.remember(state, owner, eid, "requisitioned")
		WarLaws.war_crime(state, eid, owner, "requisition")
	state.add_chronicle("La %s réquisitionne %s : greniers vidés, ateliers saisis, et des reçus que personne ne pourra jamais encaisser." % [
			f.fleet_name, _sys(state, sid)], Espionage.private_to(state, [eid, owner], sid))


# --- Espionnage (prop. 20) -----------------------------------------------------------------------

static func spy_check(state: GameState, _a: int, b: int, op_id: String) -> String:
	if op_id != "saboter_depots":
		return ""
	if not active(state):
		return "la logistique n'est pas en jeu dans cette partie"
	for f in Fleets.empire_fleets(state, b):
		if applies(state, f) and status(state, f) != OK:
			return ""
	for s in state.galaxy.systems:
		if has_depot(state, s.id) and WarPeace.holder(state, s.id) == b:
			return ""
	return "il n'a ni flotte loin de ses bases ni dépôt de flotte"


static func spy_apply(state: GameState, _a: int, b: int, _o: Dictionary) -> String:
	var sc: Dictionary = _cfg("sabotage")
	var l := _l(state)
	var n := 0
	for f in Fleets.empire_fleets(state, b):
		if applies(state, f) and status(state, f) != OK:
			l["res"][str(f.id)] = reserves(state, f) * (100 - int(sc.get("reserve_pct", 50))) / 100
			n += 1
	l["sab"][str(b)] = state.tick + int(sc.get("depot_days", 60))
	return "des cales percées, des stocks avariés : %d flotte%s loin de chez elle perd la moitié de ses réserves, et ses dépôts de flotte restent fermés deux mois." % [n, "s" if n > 1 else ""]


# --- Itinéraires et IA (prop. 27, 28) --------------------------------------------------------------

## Avertissement d'itinéraire : destination hors zone, ou réserves trop courtes ("" sinon).
static func route_warning(state: GameState, f: Fleet, path: Array, days := -1) -> String:
	if not applies(state, f) or path.is_empty():
		return ""
	var dest := int(path[-1])
	if in_zone(state, f.owner, dest):
		return ""
	var r := reserves(state, f)
	if days >= 0 and days > r:
		return "hors ravitaillement : le trajet dure %d jours, les réserves n'en tiennent que %d" % [days, r]
	return "hors ravitaillement (réserves : %d jours)" % r


## Système de la zone le plus proche (le sien d'abord à distance égale), -1 si aucun.
static func nearest_supply(state: GameState, f: Fleet) -> int:
	var z := zone(state, f.owner)
	if z.has(f.system_id):
		return f.system_id
	var seen := {f.system_id: true}
	var frontier: Array[int] = [f.system_id]
	while not frontier.is_empty():
		var nxt: Array[int] = []
		var found := -1
		for s in frontier:
			for n in state.galaxy.systems[s].neighbors:
				if seen.has(n):
					continue
				seen[n] = true
				if z.has(n) and (found < 0 or state.system_owner(n) == f.owner and state.system_owner(found) != f.owner or n < found and (state.system_owner(n) == f.owner) == (state.system_owner(found) == f.owner)):
					found = n
				nxt.append(n)
		if found >= 0:
			return found
		frontier = nxt
	return -1


## L'IA doit-elle rentrer refaire le plein ? (Normale et plus, réserves sous le seuil, hors bataille.)
static func should_resupply(state: GameState, f: Fleet, skill: int) -> bool:
	if skill < 1 or not applies(state, f) or f.is_moving():
		return false
	if not Combat.battle_at(state, f.system_id).is_empty() or status(state, f) == OK:
		return false
	return reserves(state, f) * 100 < autonomy(state, f) * int(_cfg("low_reserve_pct"))


## Point de coupure (Vétéran et plus, mode complet) : le premier système sur le chemin de la flotte
## ennemie e vers sa zone, s'il n'est pas déjà dans sa zone (-1 sinon).
static func cut_point(state: GameState, e: Fleet) -> int:
	if not full(state) or not applies(state, e) or status(state, e) == OK:
		return -1
	var z := zone(state, e.owner)
	var prev := {e.system_id: -1}
	var frontier: Array[int] = [e.system_id]
	var goal := -1
	while not frontier.is_empty() and goal < 0:
		var nxt: Array[int] = []
		for s in frontier:
			for n in state.galaxy.systems[s].neighbors:
				if prev.has(n):
					continue
				prev[n] = s
				if z.has(n):
					goal = n
					break
				nxt.append(n)
			if goal >= 0:
				break
		frontier = nxt
	if goal < 0:
		return -1
	# Remonte jusqu'au premier pas depuis la flotte ennemie.
	var step := goal
	while int(prev[step]) != e.system_id and int(prev[step]) >= 0:
		step = int(prev[step])
	return step if not z.has(step) else -1


# --- Textes d'interface ----------------------------------------------------------------------------

## Ligne de la fiche de flotte : état, réserves, malus.
static func status_line(state: GameState, f: Fleet) -> String:
	if not applies(state, f):
		return ""
	var st := status(state, f)
	var aut := autonomy(state, f)
	var r := reserves(state, f)
	var s := "%s  ·  réserves %d/%d j" % [state_label(st), r, aut]
	if docked(state, f):
		s += "  ·  à quai (entretien %d %%)" % docked_upkeep_pct()
	var dp := damage_pct(state, f)
	if dp != 0:
		s += "  ·  à sec depuis %d j, dégâts %d %%" % [dry_days(state, f), dp]
	return s


static func status_tooltip(state: GameState, f: Fleet) -> String:
	var st := status(state, f)
	var lines := PackedStringArray([state_text(st)])
	lines.append("Zone : vos systèmes et ceux qui vous ravitaillent, plus %d saut%s autour." % [range_of(state, f.owner), "s" if range_of(state, f.owner) > 1 else ""])
	lines.append("Réserves vides : plus de réparation, dégâts -2 %% par semaine (au plus -%d %%). Aucun vaisseau n'est perdu." % int((_cfg("exhausted") as Dictionary).get("damage_pct_max", 30)))
	return "\n".join(lines)
