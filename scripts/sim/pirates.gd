class_name Pirates
extends RefCounted
## Pirates (étude « Pirates et stabilité des colonies », 2026-11-12, propositions 9 à 12) : des
## repaires placés loin des départs (GameState.PIRATE_ID, hors de state.empires), gardés par une
## flotte qui grossit avec les années, lancent des raids vers le système le moins défendu à portée.
## Un raid vole des ressources, fait baisser la stabilité et ne conquiert jamais. On peut payer un
## tribut à un repaire connu, l'engager contre un rival, mettre une prime sur un empire, ou le
## démanteler en détruisant sa garde. Règles dans data/pirates.json. Entiers, sans aléatoire.
##
## state.lairs[sid] = {"born": jour de fondation, "next": prochain raid, "guard": flotte de garde
##   (-1 si détruite), "lost": jour où la garde est tombée, "raid": {"fleet", "target", "back",
##   "by", "victim"} (raid en cours, {} sinon), "contract": {"by", "victim"} (raid commandité en
##   attente), "tribute": {empire: jour de fin}, "hits": {empire: dernier raid subi}, "grown": navires ajoutés,
##   "calm": dernier jour où on l'a attaqué, "port": jour où il est devenu port franc (0 = repaire),
##   "deals": {"fleet"|"hero": prochain jour où le port en propose}}.
## state.pirate_meta = {"bounty": [{"by", "on", "until"}], "shame": [{"e", "label", "v", "until"}]}.

const LAYERS := ["archetype", "gouvernement", "credo", "registre"]

static var _talent_cache := {}


static func data() -> Dictionary:
	return GameData.pirates()


# --- Talents -----------------------------------------------------------------------------------

## Talents pirates du peuple, couches d'espèce additionnées (les booléens restent vrais).
static func talent(state: GameState, empire_id: int) -> Dictionary:
	var e := state.get_empire(empire_id)
	if e == null or e.is_npc():
		return {}
	var ck := "%s:%d" % [e.faction_id, GameData.factions_gen]
	if _talent_cache.has(ck):
		return _talent_cache[ck]
	var out := {}
	var sp: Dictionary = e.faction().get("species", {})
	var table: Dictionary = data().get("talents", {})
	for layer in LAYERS:
		var t: Dictionary = (table.get(layer, {}) as Dictionary).get(String(sp.get(layer, "")), {})
		for k in t:
			if k == "label" or k == "text":
				continue
			var v: Variant = t[k]
			out[k] = v if v is bool else int(out.get(k, 0)) + int(v)
	_talent_cache[ck] = out
	return out


## Talents à afficher : [[nom, texte], …].
static func talent_labels(state: GameState, empire_id: int) -> Array:
	var e := state.get_empire(empire_id)
	var out := []
	if e == null or e.is_npc():
		return out
	var sp: Dictionary = e.faction().get("species", {})
	var table: Dictionary = data().get("talents", {})
	for layer in LAYERS:
		var t: Dictionary = (table.get(layer, {}) as Dictionary).get(String(sp.get(layer, "")), {})
		if not t.is_empty():
			out.append([String(t["label"]), String(t["text"])])
	return out


# --- Densité et placement ----------------------------------------------------------------------

static func densities() -> Array:
	return data()["densities"]


static func density_def(id: String) -> Dictionary:
	for d: Dictionary in densities():
		if String(d["id"]) == id:
			return d
	return {}


static func default_density() -> String:
	return String(data().get("default", "normaux"))


static func density_label(id: String) -> String:
	return String(density_def(id).get("label", id))


## Place les repaires d'une nouvelle partie : un pour `per` systèmes environ, à au moins
## min_jumps_from_start sauts de tout départ et min_jumps_between les uns des autres, dans des
## systèmes sans revendication. L'ordre de choix suit un hachage de la graine : même partie, mêmes repaires.
static func setup(state: GameState, density_id: String) -> void:
	state.pirate_density = density_id if not density_def(density_id).is_empty() else "aucun"
	var per := int(density_def(state.pirate_density).get("per", 0))
	if per <= 0:
		return
	@warning_ignore("integer_division")
	var want := maxi(1, (state.galaxy.systems.size() + per / 2) / per)
	var starts: Array = []
	for e in state.empires:
		var cap := FactionTraits.capital_system(state, e.id)
		if cap < 0 and e.home_planet >= 0:
			cap = state.galaxy.get_planet(e.home_planet).system_id
		if cap >= 0:
			starts.append(FactionTraits.jumps_from(state.galaxy, cap))
	var cands: Array = []
	for s in state.galaxy.systems:
		if state.system_owner(s.id) >= 0:
			continue
		var near := 999
		for d: Dictionary in starts:
			near = mini(near, int(d.get(s.id, 999)))
		if near < int(data()["min_jumps_from_start"]):
			continue
		cands.append([hash([state.seed_value, "repaire", s.id]), s.id])
	cands.sort()
	var picked: Array = []
	for c in cands:
		if picked.size() >= want:
			break
		var sid := int(c[1])
		var ok := true
		for p: Dictionary in picked.map(func(x: int) -> Dictionary: return FactionTraits.jumps_from(state.galaxy, x)):
			if int(p.get(sid, 999)) < int(data()["min_jumps_between"]):
				ok = false
				break
		if ok:
			picked.append(sid)
	picked.sort()
	for sid in picked:
		create_lair(state, sid)


static func create_lair(state: GameState, sid: int) -> void:
	var rd: Dictionary = data()["raid"]
	state.lairs[sid] = {"born": state.tick, "next": maxi(state.tick, int(rd["first_day"])) + posmod(sid * 37, 90),
			"guard": -1, "lost": -1, "raid": {}, "contract": {}, "tribute": {}, "hits": {}, "grown": 0,
			"calm": state.tick, "port": 0, "deals": {}}
	spawn_guard(state, sid)
	for o in state.empires:
		o.path_cache.clear()


## Garde du repaire : la flotte de base, plus ce qu'elle a gagné avec les années.
static func spawn_guard(state: GameState, sid: int) -> Fleet:
	var gd: Dictionary = data()["guard"]
	var ships: Array = (gd["ships"] as Array).duplicate()
	var grow: Array = gd["grow_ships"]
	var lair: Dictionary = state.lairs[sid]
	for i in int(lair.get("grown", 0)):
		ships.append(grow[i % grow.size()])
	ships = ships.slice(0, int(gd["max_ships"]))
	# Repaire dresseur (créatures, lot 3) : un nid à 3 sauts au plus, et les pirates ont dressé une bête.
	var beast := tamed_beast(state, sid)
	if beast != "":
		ships.append(beast)
	var f := state.spawn_ship(GameState.PIRATE_ID, String(ships[0]), sid)
	for i in range(1, ships.size()):
		f.add_ship(String(ships[i]), -1, 1)
	f.troops = 0
	f.fleet_name = lair_name(state, sid)
	lair["guard"] = f.id
	lair["lost"] = -1
	return f


## Bête dressée par un repaire proche d'un nid (à 3 sauts au plus), "" sinon : l'adulte de l'espèce du
## nid le plus proche.
static func tamed_beast(state: GameState, sid: int) -> String:
	if state.fauna.is_empty() or Fauna.nests(state).is_empty():
		return ""
	var j := FactionTraits.jumps_from(state.galaxy, sid)
	var best := ""
	var best_j := 4
	for nsid in Fauna.nest_ids(state):
		if int(j.get(nsid, 99)) < best_j:
			best_j = int(j.get(nsid, 99))
			best = WarBeasts.unit_for(String(Fauna.nests(state)[nsid]["sp"]), "adulte")
	return best


## Après le placement des nids (nouvelle partie) : les gardes des repaires proches d'un nid reçoivent leur bête.
static func tame_guards(state: GameState) -> void:
	for sid in lair_ids(state):
		var beast := tamed_beast(state, sid)
		var g := guard_fleet(state, sid)
		if beast != "" and g != null:
			g.add_ship(beast, -1, 1)


static func lair_name(state: GameState, sid: int) -> String:
	return "Repaire de %s" % state.galaxy.systems[sid].system_name


## « le repaire de X », dans une phrase.
static func lair_ref(state: GameState, sid: int) -> String:
	return "le repaire de %s" % state.galaxy.systems[sid].system_name


## Repaire actif (un port franc n'en est plus un).
static func is_lair(state: GameState, sid: int) -> bool:
	return state.lairs.has(sid) and int(state.lairs[sid].get("port", 0)) <= 0


static func is_port(state: GameState, sid: int) -> bool:
	return state.lairs.has(sid) and int(state.lairs[sid].get("port", 0)) > 0


## Repaires actifs, triés (sans les ports francs).
static func lair_ids(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for k in state.lairs:
		if int(state.lairs[k].get("port", 0)) <= 0:
			out.append(int(k))
	out.sort()
	return out


static func port_ids(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for k in state.lairs:
		if int(state.lairs[k].get("port", 0)) > 0:
			out.append(int(k))
	out.sort()
	return out


static func port_name(state: GameState, sid: int) -> String:
	return "Port franc de %s" % state.galaxy.systems[sid].system_name


static func known_ports(state: GameState, empire_id: int) -> Array[int]:
	var out: Array[int] = []
	var e := state.get_empire(empire_id)
	if e == null:
		return out
	for sid in port_ids(state):
		if e.explored.has(sid):
			out.append(sid)
	return out


static func guard_fleet(state: GameState, sid: int) -> Fleet:
	var fid := int((state.lairs.get(sid, {}) as Dictionary).get("guard", -1))
	return state.fleets.get(fid)


static func guard_power(state: GameState, sid: int) -> int:
	var f := guard_fleet(state, sid)
	return Combat.fleet_power(f) if f != null else 0


## L'empire connaît-il ce repaire ? (il a exploré le système)
static func knows(state: GameState, empire_id: int, sid: int) -> bool:
	if not is_lair(state, sid):
		return false
	var e := state.get_empire(empire_id)
	return e != null and e.explored.has(sid)


static func known_lairs(state: GameState, empire_id: int) -> Array[int]:
	var out: Array[int] = []
	for sid in lair_ids(state):
		if knows(state, empire_id, sid):
			out.append(sid)
	return out


# --- Port franc --------------------------------------------------------------------------------

## Le repaire se range-t-il ? Personne ne l'a attaqué depuis untouched_years ans, pas de raid ni de
## contrat en cours, sa garde est là.
static func ready_for_port(state: GameState, sid: int) -> bool:
	var l: Dictionary = state.lairs[sid]
	var years := int(data()["port"]["untouched_years"])
	return years > 0 and guard_fleet(state, sid) != null and (l["raid"] as Dictionary).is_empty() \
			and (l["contract"] as Dictionary).is_empty() and state.tick - int(l.get("calm", l["born"])) >= years * GameCalendar.DAYS_PER_YEAR


static func make_port(state: GameState, sid: int, added: Array[Dictionary]) -> void:
	var l: Dictionary = state.lairs[sid]
	var g := guard_fleet(state, sid)
	if g != null:
		state.fleets.erase(g.id)
	l["guard"] = -1
	l["port"] = state.tick
	l["tribute"] = {}
	l["deals"] = {}
	for o in state.empires:
		o.path_cache.clear()
	var who: Array[int] = []
	for o in state.empires:
		if not o.eliminated and o.explored.has(sid):
			who.append(o.id)
	if not who.is_empty():
		added.append(state.add_chronicle("Quinze ans sans qu'on vienne les déloger : les pirates de %s se rangent. Le repaire devient un port franc, où l'on loue des mercenaires et où traînent des aventuriers (écran Ordre intérieur)." % [
				state.galaxy.systems[sid].system_name], Espionage.public_to(state, who)))


const PORT_DEALS := ["fleet", "hero"]


static func port_cost(kind: String) -> Dictionary:
	return (data()["port"][kind]["cost"] as Dictionary).duplicate()


## Prochain jour où le port propose ce marché (0 = maintenant).
static func port_next(state: GameState, sid: int, kind: String) -> int:
	return int((state.lairs.get(sid, {}).get("deals", {}) as Dictionary).get(kind, 0))


static func check_port(state: GameState, empire_id: int, sid: int, kind: String) -> String:
	var e := state.get_empire(empire_id)
	if e == null or e.eliminated or e.is_npc():
		return "empire inconnu"
	if not is_port(state, sid):
		return "ce n'est pas un port franc"
	if not e.explored.has(sid):
		return "vous ne connaissez pas ce port"
	if not PORT_DEALS.has(kind):
		return "marché inconnu"
	if port_next(state, sid, kind) > state.tick:
		return "plus rien à louer avant le %s" % GameCalendar.date_string(port_next(state, sid, kind))
	if kind == "hero" and Heroes.ids_of(state, empire_id).size() >= Heroes.cap(state, empire_id):
		return "vous avez déjà autant de héros que vous pouvez en entretenir"
	if not Economy.can_afford(e, port_cost(kind)):
		return "pas assez de ressources (%s)" % GameData.format_amounts(port_cost(kind))
	return ""


## Louer une flotte de mercenaires (elle apparaît au port, à vous pour de bon) ou recruter un héros.
static func port_deal(state: GameState, empire_id: int, sid: int, kind: String) -> void:
	var e := state.get_empire(empire_id)
	var pd: Dictionary = data()["port"][kind]
	Economy.pay(e, port_cost(kind))
	state.lairs[sid]["deals"][kind] = state.tick + int(pd["every_days"])
	var text := ""
	if kind == "fleet":
		var ships: Array = pd["ships"]
		var f := state.spawn_ship(empire_id, String(ships[0]), sid)
		for i in range(1, ships.size()):
			f.add_ship(String(ships[i]), -1, 1)
		f.fleet_name = "Mercenaires de %s" % state.galaxy.systems[sid].system_name
		text = "%s loue une flotte de mercenaires au %s : %d vaisseaux, payés d'avance, sans questions." % [
				e.display_name(), port_name(state, sid), ships.size()]
	else:
		var cls: String = Heroes.CLASSES[posmod(sid * 7 + state.tick, Heroes.CLASSES.size())]
		var id := Heroes.recruit(state, empire_id, Heroes.make_candidate(state, empire_id, cls, ["port", sid, state.tick]))
		text = "%s recrute %s dans une taverne du %s. Son passé est flou ; ses talents, eux, sont nets." % [
				e.display_name(), state.heroes[id]["name"], port_name(state, sid)]
	_reputation(state, empire_id)
	state.add_chronicle(text, Espionage.private_to(state, [empire_id]))


# --- Raids -------------------------------------------------------------------------------------

## Vaisseaux d'un raid : la base, plus un navire tous les extra_every_days de partie.
static func raid_ships(state: GameState) -> Array:
	var rd: Dictionary = data()["raid"]
	var ships: Array = (rd["ships"] as Array).duplicate()
	var every := int(rd["extra_every_days"])
	if every > 0:
		@warning_ignore("integer_division")
		for _i in state.tick / every:
			ships.append(String(rd["extra_ship"]))
	return ships.slice(0, int(rd["max_ships"]))


static func tribute_until(state: GameState, sid: int, empire_id: int) -> int:
	return int(((state.lairs.get(sid, {}) as Dictionary).get("tribute", {}) as Dictionary).get(empire_id, -1))


static func pays_tribute(state: GameState, sid: int, empire_id: int) -> bool:
	return tribute_until(state, sid, empire_id) > state.tick


## Primes en cours sur un empire (chacune pèse autant).
static func bounty_weight(state: GameState, empire_id: int) -> int:
	var n := 0
	for b: Dictionary in state.pirate_meta.get("bounty", []):
		if int(b["on"]) == empire_id and int(b["until"]) > state.tick:
			n += 1
	return n


## Les pirates voient-ils les mondes de cet empire ? (un peuple voilé leur échappe s'il n'a pas été
## repéré depuis moins d'un an)
static func sees(state: GameState, empire_id: int) -> bool:
	if not bool(talent(state, empire_id).get("veiled", false)) or not Veil.is_veiled(state, empire_id):
		return true
	var e := state.get_empire(empire_id)
	return e.spotted_tick >= 0 and state.tick - e.spotted_tick < GameCalendar.DAYS_PER_YEAR


## Cible d'un raid depuis le repaire `sid` : le système revendiqué le moins défendu à portée (puissance
## armée du propriétaire sur place, puis distance, puis identifiant). Jamais une capitale, ni un
## empire qui paie tribut à ce repaire ; un système défendu (flotte armée, batterie) seulement à défaut
## d'autre. Les primes orientent vers l'empire le plus mis à prix. victim >= 0 : raid commandité contre
## cet empire. -1 s'il n'y a rien à piller.
static func pick_target(state: GameState, sid: int, victim := -1, range_jumps := -1) -> int:
	var rd: Dictionary = data()["raid"]
	if range_jumps < 0:
		range_jumps = int(rd["range_jumps"])
	var jumps := FactionTraits.jumps_from(state.galaxy, sid)
	var cands: Array = []
	var caps := {}
	for s in state.galaxy.systems:
		var j := int(jumps.get(s.id, 999))
		if j > range_jumps:
			continue
		var owner := state.system_owner(s.id)
		if owner < 0 or GameState.is_npc(owner) or (victim >= 0 and owner != victim):
			continue
		if not caps.has(owner):
			caps[owner] = FactionTraits.capital_system(state, owner)
		if s.id == int(caps[owner]) or Stability.colony_systems_in(state, owner, s.id) == 0:
			continue
		if victim < 0 and pays_tribute(state, sid, owner):
			continue
		if not sees(state, owner):
			continue
		var power := 0
		for f in Fleets.fleets_at(state, s.id, owner):
			if not f.is_moving() and Combat.is_armed(f):
				power += Combat.fleet_power(f)
		var defended := power > 0 or not Combat.battery(state, s.id).is_empty()
		cands.append({"sid": s.id, "owner": owner, "defended": defended, "key": [power, j, s.id]})
	if cands.is_empty():
		return -1
	if victim < 0:
		var top := 0
		for c in cands:
			top = maxi(top, bounty_weight(state, int(c["owner"])))
		if top > 0:
			cands = cands.filter(func(c: Dictionary) -> bool: return bounty_weight(state, int(c["owner"])) == top)
	var open := cands.filter(func(c: Dictionary) -> bool: return not c["defended"])
	if not open.is_empty():
		cands = open
	var best: Dictionary = cands[0]
	for c in cands:
		if (c["key"] as Array) < (best["key"] as Array):
			best = c
	return int(best["sid"])


## Lance un raid du repaire vers target. Renvoie la flotte (null si la route est impossible).
static func launch_raid(state: GameState, sid: int, target: int, added: Array[Dictionary], by := -1, victim := -1) -> Fleet:
	var ships := raid_ships(state)
	var f := state.spawn_ship(GameState.PIRATE_ID, String(ships[0]), sid)
	for i in range(1, ships.size()):
		f.add_ship(String(ships[i]), -1, 1)
	f.troops = 0
	f.fleet_name = "Pillards de %s" % state.galaxy.systems[sid].system_name
	var plan := Fleets.plan_route(state, f, target)
	if plan.is_empty():
		state.fleets.erase(f.id)
		return null
	f.path.assign(plan["path"])
	f.progress = int(plan["progress"])
	state.lairs[sid]["raid"] = {"fleet": f.id, "target": target, "back": false, "by": by, "victim": victim}
	var owner := state.system_owner(target)
	if owner >= 0 and knows(state, owner, sid) and not state.get_empire(owner).is_ai():
		added.append(state.add_chronicle("Une flotte de pillards quitte %s, cap sur %s. Les guetteurs l'ont vue partir : il reste quelques jours pour l'accueillir." % [
				lair_ref(state, sid), state.galaxy.systems[target].system_name], Espionage.private_to(state, [owner], target)))
	return f


## Le raid arrive : vol de ressources, coup à la stabilité. Rien n'est conquis.
static func plunder(state: GameState, sid: int, target: int, added: Array[Dictionary]) -> void:
	var owner := state.system_owner(target)
	if owner < 0 or GameState.is_npc(owner):
		return
	var rd: Dictionary = data()["raid"]
	var e := state.get_empire(owner)
	var lair: Dictionary = state.lairs[sid]
	var raid: Dictionary = lair["raid"]
	var taken := {}
	for r in ["energy", "materials"]:
		@warning_ignore("integer_division")
		var amt := mini(int(rd["steal_max"]), maxi(0, int(e.resources.get(r, 0))) * int(rd["steal_pct"]) / 100)
		if amt > 0:
			e.resources[r] = int(e.resources.get(r, 0)) - amt
			taken[r] = amt
	if Stability.applies(state, owner):
		var en := Stability._entry_w(state, target)
		en["v"] = clampi(int(en.get("v", 50)) + int(rd["stability"]), 0, 100)
		en["hit"] = state.tick
	(lair["hits"] as Dictionary)[owner] = state.tick
	# Le commanditaire d'un syndicat touche sa part du butin.
	var by := int(raid.get("by", -1))
	var share := int(talent(state, by).get("loot_share", 0)) if by >= 0 else 0
	if share > 0 and not taken.is_empty():
		var be := state.get_empire(by)
		for r in taken:
			@warning_ignore("integer_division")
			be.resources[r] = int(be.resources.get(r, 0)) + int(taken[r]) * share / 100
	var sname := state.galaxy.systems[target].system_name
	var what := GameData.format_amounts(taken) if not taken.is_empty() else "rien, les caisses étaient vides"
	if not e.is_ai():
		added.append(state.add_chronicle("Raid pirate sur %s : les pillards emportent %s, et la confiance des habitants avec. Ils ne restent pas pour les remerciements." % [
				sname, what], Espionage.private_to(state, [owner], target)))
	if by >= 0 and not state.get_empire(by).is_ai():
		added.append(state.add_chronicle("Le contrat est rempli : les pirates de %s ont pillé %s (%s). Personne ne saura qui a payé." % [
				lair_ref(state, sid), sname, what], Espionage.private_to(state, [by])))


# --- Actions sur un repaire connu --------------------------------------------------------------

static func _pct_cost(cost: Dictionary, pct: int) -> Dictionary:
	if pct <= 0 or pct == 100:
		return cost.duplicate()
	var out := {}
	for k in cost:
		@warning_ignore("integer_division")
		out[k] = maxi(1, int(cost[k]) * pct / 100)
	return out


static func tribute_cost(state: GameState, empire_id: int) -> Dictionary:
	var td: Dictionary = data()["tribute"]
	var gross := int((Economy.empire_income(state, empire_id)["gross"] as Dictionary).get("energy", 0))
	return _pct_cost({"energy": int(td["base"]) + int(td["per_energy"]) * maxi(0, gross)}, int(talent(state, empire_id).get("pirate_pct", 0)))


static func hire_cost(state: GameState, empire_id: int) -> Dictionary:
	return _pct_cost(data()["hire"]["cost"], int(talent(state, empire_id).get("pirate_pct", 0)))


static func bounty_cost(state: GameState, empire_id: int) -> Dictionary:
	return _pct_cost(data()["bounty"]["cost"], int(talent(state, empire_id).get("bounty_pct", 0)))


static func _check_lair(state: GameState, empire_id: int, sid: int) -> String:
	var e := state.get_empire(empire_id)
	if e == null or e.is_npc():
		return "empire inconnu : %d" % empire_id
	if not is_lair(state, sid):
		return "il n'y a pas de repaire pirate ici"
	if not knows(state, empire_id, sid):
		return "vous ne connaissez pas ce repaire"
	return ""


static func check_tribute(state: GameState, empire_id: int, sid: int) -> String:
	var why := _check_lair(state, empire_id, sid)
	if why != "":
		return why
	if pays_tribute(state, sid, empire_id):
		return "vous payez déjà tribut à ce repaire"
	if not Economy.can_afford(state.get_empire(empire_id), tribute_cost(state, empire_id)):
		return "pas assez d'énergie (%s)" % GameData.format_amounts(tribute_cost(state, empire_id))
	return ""


static func tribute(state: GameState, empire_id: int, sid: int) -> void:
	var e := state.get_empire(empire_id)
	Economy.pay(e, tribute_cost(state, empire_id))
	(state.lairs[sid]["tribute"] as Dictionary)[empire_id] = state.tick + int(data()["tribute"]["days"])
	var tal := talent(state, empire_id)
	if int(tal.get("tribute_scandal", 0)) != 0:
		_shame(state, empire_id, "Scandale du tribut", int(tal["tribute_scandal"]), int(tal.get("scandal_days", 180)))
	if int(tal.get("tribute_shame", 0)) != 0:
		_shame(state, empire_id, "Tribut payé aux forbans", int(tal["tribute_shame"]), int(tal.get("shame_days", 360)))


static func check_hire(state: GameState, empire_id: int, sid: int, victim: int) -> String:
	var why := _check_lair(state, empire_id, sid)
	if why != "":
		return why
	var v := state.get_empire(victim)
	if v == null or v.is_npc() or victim == empire_id or v.eliminated:
		return "cible inconnue"
	if not (state.get_empire(empire_id).contacts as Array).has(victim):
		return "vous n'avez pas rencontré cet empire"
	var lair: Dictionary = state.lairs[sid]
	if not (lair["contract"] as Dictionary).is_empty() or int((lair["raid"] as Dictionary).get("by", -1)) >= 0:
		return "ce repaire a déjà un contrat en cours"
	if guard_fleet(state, sid) == null:
		return "le repaire n'a plus de flotte"
	if pick_target(state, sid, victim, int(data()["hire"]["range_jumps"])) < 0:
		return "aucun système de cet empire à portée du repaire"
	if not Economy.can_afford(state.get_empire(empire_id), hire_cost(state, empire_id)):
		return "pas assez de ressources (%s)" % GameData.format_amounts(hire_cost(state, empire_id))
	return ""


static func hire(state: GameState, empire_id: int, sid: int, victim: int) -> void:
	Economy.pay(state.get_empire(empire_id), hire_cost(state, empire_id))
	state.lairs[sid]["contract"] = {"by": empire_id, "victim": victim}
	_reputation(state, empire_id)


static func check_bounty(state: GameState, empire_id: int, victim: int) -> String:
	var e := state.get_empire(empire_id)
	if e == null or e.is_npc():
		return "empire inconnu : %d" % empire_id
	if state.lairs.is_empty():
		return "il n'y a pas de pirates dans cette galaxie"
	var v := state.get_empire(victim)
	if v == null or v.is_npc() or victim == empire_id or v.eliminated:
		return "cible inconnue"
	if not (e.contacts as Array).has(victim):
		return "vous n'avez pas rencontré cet empire"
	for b: Dictionary in state.pirate_meta.get("bounty", []):
		if int(b["by"]) == empire_id and int(b["on"]) == victim and int(b["until"]) > state.tick:
			return "votre prime sur cet empire court toujours"
	if not Economy.can_afford(e, bounty_cost(state, empire_id)):
		return "pas assez de ressources (%s)" % GameData.format_amounts(bounty_cost(state, empire_id))
	return ""


static func bounty(state: GameState, empire_id: int, victim: int) -> void:
	Economy.pay(state.get_empire(empire_id), bounty_cost(state, empire_id))
	if not state.pirate_meta.has("bounty"):
		state.pirate_meta["bounty"] = []
	(state.pirate_meta["bounty"] as Array).append({"by": empire_id, "on": victim, "until": state.tick + int(data()["bounty"]["days"])})


## Démantèlement : la garde est tombée et une flotte armée de l'empire tient le système.
static func dismantle(state: GameState, sid: int, empire_id: int, added: Array[Dictionary]) -> void:
	var e := state.get_empire(empire_id)
	var loot: Dictionary = data()["dismantle"]["loot"]
	for r in loot:
		e.resources[r] = int(e.resources.get(r, 0)) + int(loot[r])
	var tal := talent(state, empire_id)
	var extra := ""
	if int(tal.get("crusade_fervor", 0)) > 0 and FactionTraits.has_fervor(e.faction()):
		e.fervor += int(tal["crusade_fervor"])
		extra = " Les prêcheurs parlent de croisade."
	if int(tal.get("devour", 0)) > 0:
		var bg := FactionTraits.biomass_gain(state, empire_id)
		if not bg.is_empty():
			var gain := int(bg["materials"]) * int(tal["devour"])
			e.resources["materials"] = int(e.resources.get("materials", 0)) + gain
			e.biomass += gain
			extra = " Rien ne reste de la station, pas même les rivets."
	if bool(tal.get("rally", false)):
		var f := _rally_fleet(state, sid, empire_id)
		if f != null:
			for t in data()["guard"]["ships"]:
				f.add_ship(String(t), -1, 1)
			Stability.on_loot(state, empire_id)
			extra += " Les équipages rallient les clans : %d vaisseaux de plus dans %s." % [(data()["guard"]["ships"] as Array).size(), f.fleet_name]
	if not state.heroes.is_empty():
		var freed := Heroes.free_from_pirates(state, empire_id)
		if not freed.is_empty():
			extra += " Dans les cales, on retrouve %s, vivant%s." % [", ".join(freed), "s" if freed.size() > 1 else ""]
	_reputation(state, empire_id)
	Heroes.act(state, empire_id, "lair")
	Quests.on_lair(state, sid, empire_id)
	var raid: Dictionary = state.lairs[sid]["raid"]
	state.lairs.erase(sid)
	# Les routes des vaisseaux sans armes ne contournent plus ce repaire.
	for o in state.empires:
		o.path_cache.clear()
	if not raid.is_empty() and state.fleets.has(int(raid["fleet"])):
		(state.fleets[int(raid["fleet"])] as Fleet).fleet_name = "Pillards sans repaire"
	added.append(state.add_chronicle("%s démantèle %s : la station saute, le butin change de mains (%s).%s" % [
			e.display_name(), lair_ref(state, sid), GameData.format_amounts(loot), extra], Espionage.public_to(state, [empire_id])))


## Flotte armée de l'empire, à l'arrêt au repaire (le plus petit identifiant), null sinon.
static func _rally_fleet(state: GameState, sid: int, empire_id: int) -> Fleet:
	for f in Fleets.fleets_at(state, sid, empire_id):
		if Combat.is_armed(f):
			return f
	return null


static func _reputation(state: GameState, empire_id: int) -> void:
	var n := int(talent(state, empire_id).get("reputation", 0))
	if n > 0 and Reputation.has(state.get_empire(empire_id).faction()):
		Reputation.add(state, empire_id, n)


static func _shame(state: GameState, empire_id: int, label: String, v: int, days: int) -> void:
	if not state.pirate_meta.has("shame"):
		state.pirate_meta["shame"] = []
	(state.pirate_meta["shame"] as Array).append({"e": empire_id, "label": label, "v": v, "until": state.tick + days})


## Sources de stabilité venues des pirates (scandale, honte du tribut), pour Stability.context.
static func stability_parts(state: GameState, empire_id: int) -> Array:
	var out := []
	var seen := {}
	for s: Dictionary in state.pirate_meta.get("shame", []):
		var label := String(s["label"])
		if int(s["e"]) == empire_id and int(s["until"]) > state.tick and not seen.has(label):
			seen[label] = true
			out.append([label, int(s["v"])])
	return out


## Bonus de dégâts contre les pirates (credo de l'honneur), en points de %.
static func hunt_pct(state: GameState, f: Fleet, fighters: Array) -> int:
	var h := int(talent(state, f.owner).get("hunt_pct", 0))
	if h == 0:
		return 0
	for g in fighters:
		if (g as Fleet).owner == GameState.PIRATE_ID:
			return h
	return 0


## Le ménage du mois : primes et hontes échues.
static func prune_meta(state: GameState) -> void:
	for key in ["bounty", "shame"]:
		if state.pirate_meta.has(key):
			state.pirate_meta[key] = (state.pirate_meta[key] as Array).filter(func(x: Dictionary) -> bool: return int(x["until"]) > state.tick)


# --- Sauvegarde --------------------------------------------------------------------------------

static func _pairs(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort()
	return keys.map(func(k: Variant) -> Array: return [int(k), int(d[k])])


static func _unpairs(a: Array) -> Dictionary:
	var out := {}
	for p in a:
		out[int(p[0])] = int(p[1])
	return out


static func _ints(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[String(k)] = int(d[k])
	return out


static func to_list(state: GameState) -> Array:
	var out := []
	var ids := state.lairs.keys()
	ids.sort()
	for sid in ids:
		var l: Dictionary = state.lairs[sid]
		out.append({"sid": int(sid), "born": int(l["born"]), "next": int(l["next"]), "guard": int(l["guard"]), "lost": int(l["lost"]),
				"raid": _ints(l["raid"]), "contract": _ints(l["contract"]), "tribute": _pairs(l["tribute"]), "hits": _pairs(l["hits"]),
				"grown": int(l.get("grown", 0)), "calm": int(l.get("calm", l["born"])), "port": int(l.get("port", 0)),
				"deals": _ints(l.get("deals", {}))})
	return out


static func from_list(list: Array) -> Dictionary:
	var out := {}
	for d: Dictionary in list:
		var raid := {}
		var r: Dictionary = d.get("raid", {})
		for k in r:
			raid[String(k)] = bool(r[k]) if String(k) == "back" else int(r[k])
		var con := {}
		var c: Dictionary = d.get("contract", {})
		for k in c:
			con[String(k)] = int(c[k])
		out[int(d["sid"])] = {"born": int(d.get("born", 0)), "next": int(d.get("next", 0)), "guard": int(d.get("guard", -1)),
				"lost": int(d.get("lost", -1)), "raid": raid, "contract": con, "tribute": _unpairs(d.get("tribute", [])),
				"hits": _unpairs(d.get("hits", [])), "grown": int(d.get("grown", 0)),
				"calm": int(d.get("calm", d.get("born", 0))), "port": int(d.get("port", 0)), "deals": {}}
		var deals: Dictionary = d.get("deals", {})
		for k in deals:
			out[int(d["sid"])]["deals"][String(k)] = int(deals[k])
	return out


static func meta_to_dict(state: GameState) -> Dictionary:
	var out := {}
	for key in ["bounty", "shame"]:
		if state.pirate_meta.has(key):
			out[key] = (state.pirate_meta[key] as Array).duplicate(true)
	return out


static func meta_from_dict(d: Dictionary) -> Dictionary:
	var out := {}
	if d.has("bounty"):
		out["bounty"] = (d["bounty"] as Array).map(func(b: Dictionary) -> Dictionary:
			return {"by": int(b["by"]), "on": int(b["on"]), "until": int(b["until"])})
	if d.has("shame"):
		out["shame"] = (d["shame"] as Array).map(func(s: Dictionary) -> Dictionary:
			return {"e": int(s["e"]), "label": String(s["label"]), "v": int(s["v"]), "until": int(s["until"])})
	return out
