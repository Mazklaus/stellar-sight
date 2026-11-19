class_name InsExode
extends RefCounted
## Flotte-Exode des Derniers (props 11 à 16 ; voir Insolites, data/insolites.json "exode").
## Quatre Nefs-cités portent tout le peuple : au mouillage (à l'arrêt), chacune travaille les planètes
## libres de son système sans les revendiquer ; en route, elle ne produit rien. Les Traqueurs frappent
## l'Exode qui reste deux ans au même mouillage. L'Espoir remplace la stabilité : à zéro, une nef fait
## sécession. Les nefs recueillent les réfugiés des batailles et des révoltes proches. Sur la Terre
## promise (victoire déjà codée pour la Horde), l'Exode peut se poser : c'est l'Arrivée.
##
## État (Insolites.emp) : "pop", "sp", "hope", "anc": {"s": système du mouillage (-1 en route), "t": jour},
## "nefs": nefs comptées la veille, "grow", "best": plus courte distance connue à la Terre promise,
## "hunters": [{"f": flotte, "until": jour}], "arrived": 0/1, "final": jour de la dernière bataille (0 = aucune).

const SHIP := "nef_cite"


static func _c(key: String, def := 0) -> int:
	return Insolites.c_int("exode", key, def)


static func found(state: GameState, e: Empire, sid: int, ed: Dictionary) -> void:
	ed["pop"] = _c("start_pop", 24)
	ed["sp"] = {e.faction_id: int(ed["pop"])}
	ed["hope"] = _c("hope_start", 60)
	ed["anc"] = {"s": sid, "t": state.tick}
	ed["nefs"] = maxi(1, int(e.faction()["nomad"].get("count", 4)))
	ed["grow"] = 0
	ed["best"] = -1
	ed["hunters"] = []
	ed["arrived"] = 0
	ed["final"] = 0


static func nef_count(state: GameState, eid: int) -> int:
	var n := 0
	for f in Fleets.empire_fleets(state, eid):
		n += f.count(SHIP)
	return n


static func nef_fleets(state: GameState, eid: int) -> Array[Fleet]:
	var out: Array[Fleet] = []
	for f in Fleets.empire_fleets(state, eid):
		if f.count(SHIP) > 0:
			out.append(f)
	return out


static func arrived(state: GameState, eid: int) -> bool:
	return int(Insolites.emp(state, eid).get("arrived", 0)) > 0


static func pop_cap(state: GameState, eid: int) -> int:
	return nef_count(state, eid) * Insolites.tuned(state, eid, "exode", "nef_cap", _c("nef_cap", 12))


## Rendement d'une planète travaillée depuis le mouillage (celui d'un avant-poste de son type).
static func planet_work(state: GameState, eid: int, pid: int) -> Dictionary:
	var p := state.galaxy.get_planet(pid)
	var c: Colony = state.colonies.get(pid)
	if (c != null and c.owner != eid) or Insolites.is_eaten(state, pid):
		return {}
	return GameData.planet_type(p.type).get("outpost_yields", {})


## Revenu des nefs au mouillage : un fonds par nef, plus le travail des planètes libres du système
## (compté une fois par nef, deux nefs au plus par système).
static func income(state: GameState, eid: int) -> Dictionary:
	var out := {}
	if arrived(state, eid):
		return out
	var per_sys := {}
	for f in nef_fleets(state, eid):
		if f.is_moving():
			continue
		per_sys[f.system_id] = int(per_sys.get(f.system_id, 0)) + f.count(SHIP)
	var sids := per_sys.keys()
	sids.sort()
	var base: Dictionary = Insolites.cfg("exode").get("anchor_base", {})
	var pct := _c("anchor_work_pct", 100)
	for sid in sids:
		var n := int(per_sys[sid])
		Insolites.add_to(out, base, n)
		var work := {}
		for pid in state.galaxy.systems[int(sid)].planet_ids:
			Insolites.add_to(work, planet_work(state, eid, pid))
		for r in work:
			@warning_ignore("integer_division")
			out[r] = int(out.get(r, 0)) + int(work[r]) * mini(n, 2) * pct / 100
	return out


# --- Chaque jour ----------------------------------------------------------------------------------

static func daily(state: GameState, eid: int, ed: Dictionary, month: bool, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	# Nefs perdues : la population de la nef s'en va avec elle, l'Espoir avec.
	var n := nef_count(state, eid)
	var before := int(ed.get("nefs", n))
	if n < before and before > 0:
		var lost := before - n
		@warning_ignore("integer_division")
		var gone := int(ed["pop"]) * lost / before
		ed["pop"] = maxi(0, int(ed["pop"]) - gone)
		_hope(ed, _c("hope_nef_lost", -15) * lost)
		added.append(state.add_chronicle("%s pleure %s : %d population disparaît avec elle. L'Espoir vacille." % [
				e.display_name(), "une Nef-cité" if lost == 1 else "%d Nefs-cités" % lost, gone], Espionage.public_to(state, [eid])))
	ed["nefs"] = n
	_hunters_day(state, eid, ed)
	if not arrived(state, eid):
		_anchor_day(state, eid, ed, added)
	elif int(ed.get("final", 0)) > 0 and state.tick >= int(ed["final"]):
		ed["final"] = 0
		var cap := e.capital_planet
		if cap >= 0:
			_hunt(state, eid, ed, state.galaxy.get_planet(cap).system_id, _c("final_hunt_extra", 4), added, true)
	if month:
		_month(state, eid, ed, added)


static func _hope(ed: Dictionary, delta: int) -> void:
	ed["hope"] = clampi(int(ed.get("hope", 0)) + delta, 0, Insolites.c_int("exode", "hope_max", 100))


## Mouillage et Traqueurs (prop. 12) : deux ans au même endroit, et ils frappent.
static func _anchor_day(state: GameState, eid: int, ed: Dictionary, added: Array[Dictionary]) -> void:
	var cf := FactionTraits.city_fleet(state, eid)
	var anc: Dictionary = ed.get("anc", {"s": -1, "t": state.tick})
	if cf == null:
		return
	if cf.is_moving():
		anc = {"s": -1, "t": state.tick}
	elif int(anc["s"]) != cf.system_id:
		anc = {"s": cf.system_id, "t": state.tick}
	ed["anc"] = anc
	if int(anc["s"]) < 0:
		return
	var stay := state.tick - int(anc["t"])
	if stay == _c("stalk_warn_days", 630):
		added.append(state.add_chronicle("Les guetteurs de %s ont vu des signatures sur les routes de %s. Les Traqueurs approchent : il est temps de lever l'ancre." % [
				state.get_empire(eid).display_name(), state.galaxy.systems[int(anc["s"])].system_name], Espionage.private_to(state, [eid])))
	if stay >= Insolites.tuned(state, eid, "exode", "stalk_days", _c("stalk_days", 720)):
		@warning_ignore("integer_division")
		var extra := state.tick / (360 * maxi(1, _c("hunter_extra_per_years", 2)))
		_hunt(state, eid, ed, int(anc["s"]), extra, added, false)
		anc["t"] = state.tick
		_hope(ed, _c("hope_hunted", -5))


## Les Traqueurs arrivent dans ce système : une flotte hostile à tous, qui repart après quelques semaines.
static func _hunt(state: GameState, eid: int, ed: Dictionary, sid: int, extra: int, added: Array[Dictionary], final: bool) -> void:
	var ships: Array = Insolites.cfg("exode").get("hunter_ships", ["corvette"])
	var f := state.spawn_ship(GameState.NPC_ID, String(ships[0]), sid)
	for i in range(1, ships.size() + extra):
		f.add_ship(String(ships[i % ships.size()]), -1, 1)
	f.troops = 0
	f.fleet_name = "Les Traqueurs" if not final else "Les Traqueurs, dernière meute"
	var hl: Array = ed.get("hunters", [])
	hl.append({"f": f.id, "until": state.tick + _c("hunter_stay_days", 60)})
	ed["hunters"] = hl
	Research.count_stat(state, eid, "hunted")
	var e := state.get_empire(eid)
	var txt := "Les Traqueurs surgissent à %s et tombent sur %s. Personne ne leur a jamais parlé ; ils n'ont jamais rien demandé." % [
			state.galaxy.systems[sid].system_name, e.display_name()]
	if final:
		txt = "Les Traqueurs livrent leur dernière bataille à %s : %s s'est posé, et ils ne le supportent pas." % [state.galaxy.systems[sid].system_name, e.display_name()]
	added.append(state.add_chronicle(txt, Espionage.public_to(state, [eid])))


static func _hunters_day(state: GameState, eid: int, ed: Dictionary) -> void:
	var hl: Array = ed.get("hunters", [])
	if hl.is_empty():
		return
	var keep := []
	for h: Dictionary in hl:
		var fid := int(h["f"])
		if not state.fleets.has(fid):
			continue
		if state.tick >= int(h["until"]) and not state.battles.has((state.fleets[fid] as Fleet).system_id):
			state.fleets.erase(fid)  # la meute repart sur la trace, loin derrière
			continue
		keep.append(h)
	ed["hunters"] = keep


# --- Chaque mois ----------------------------------------------------------------------------------

static func _month(state: GameState, eid: int, ed: Dictionary, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	_hope(ed, _c("hope_month", -1))
	# Signes de la Terre promise (prop. 13) : chaque mois où les Chants la disent plus proche.
	var cf := FactionTraits.city_fleet(state, eid)
	if cf != null and Victory.has_tech(state, eid, "terre_promise") and not arrived(state, eid):
		var pid := Victory.promised_planet(state, eid)
		if pid >= 0:
			var dist := int(FactionTraits.jumps_from(state.galaxy, cf.system_id).get(state.galaxy.get_planet(pid).system_id, 999))
			if int(ed.get("best", -1)) < 0 or dist < int(ed["best"]):
				if int(ed.get("best", -1)) >= 0:
					_hope(ed, Insolites.tuned(state, eid, "exode", "hope_sign", _c("hope_sign", 6)))
					Insolites.learn(state, eid, "learn_sign", 1)  # Mémoire des nefs
					added.append(state.add_chronicle("Un signe ! Les Chants de la route disent la Terre promise à %d sauts de %s. On chante plus fort dans les coursives." % [
							dist, e.display_name()], Espionage.private_to(state, [eid])))
				ed["best"] = dist
	if not arrived(state, eid):
		_refugees(state, eid, ed, added)
		_growth(state, eid, ed)
		if int(ed["hope"]) <= 0 and nef_count(state, eid) > 1:
			_secession(state, eid, ed, added)


## Croissance naturelle, moitié moins rapide (prop. 15), plafonnée par la place à bord.
static func _growth(state: GameState, eid: int, ed: Dictionary) -> void:
	var cap := pop_cap(state, eid)
	if int(ed["pop"]) >= cap:
		return
	@warning_ignore("integer_division")
	ed["grow"] = int(ed.get("grow", 0)) + int(ed["pop"]) * _c("growth_per_pop", 50) * int(state.get_empire(eid).faction().get("growth_pct", 100)) / 100
	var th := maxi(1, _c("growth_threshold", 900))
	while int(ed["grow"]) >= th and int(ed["pop"]) < cap:
		ed["grow"] = int(ed["grow"]) - th
		ed["pop"] = int(ed["pop"]) + 1
		Insolites.add_species(ed, state.get_empire(eid).faction_id, 1)


## Réfugiés (prop. 15) : une population par colonie en bataille ou en révolte à portée des nefs.
static func _refugees(state: GameState, eid: int, ed: Dictionary, added: Array[Dictionary]) -> void:
	var near := {}
	var reach := _c("refugee_jumps", 3)
	for f in nef_fleets(state, eid):
		var d: Dictionary = FactionTraits.jumps_from(state.galaxy, f.system_id)
		for sid in d:
			if int(d[sid]) <= reach:
				near[int(sid)] = true
	var taken := 0
	var cap := pop_cap(state, eid)
	var from := {}
	for pid in state.sorted_colony_ids():
		if taken >= _c("refugee_max_month", 3) or int(ed["pop"]) >= cap:
			break
		var c: Colony = state.colonies[pid]
		if c.owner == eid or c.owner < 0 or c.owner >= state.empires.size() or not c.is_colony() or not c.is_established():
			continue
		if c.population < _c("refugee_min_pop", 3):
			continue
		var sid := state.galaxy.get_planet(pid).system_id
		if not near.has(sid):
			continue
		var fleeing := state.battles.has(sid) or (Stability.applies(state, c.owner) and Stability.tier_id(state, sid) == "revolte")
		if not fleeing:
			continue
		c.population -= 1
		ed["pop"] = int(ed["pop"]) + 1
		Insolites.add_species(ed, state.get_empire(c.owner).faction_id, 1)
		_hope(ed, _c("hope_refugee", 2))
		Research.count_stat(state, eid, "refugees")
		from[c.owner] = int(from.get(c.owner, 0)) + 1
		taken += 1
	if taken > 0:
		var names := PackedStringArray()
		var ks := from.keys()
		ks.sort()
		for k in ks:
			names.append(state.get_empire(int(k)).short_name())
		added.append(state.add_chronicle("%s recueille %d réfugié%s (%s). Les nefs se serrent un peu plus." % [
				state.get_empire(eid).display_name(), taken, "s" if taken > 1 else "", ", ".join(names)], Espionage.private_to(state, [eid])))


## L'Espoir tombe à zéro (prop. 14) : la nef la plus récente fait sécession et devient un peuple mineur
## si un monde libre l'accueille dans son système, sinon elle s'en va seule dans le noir.
static func _secession(state: GameState, eid: int, ed: Dictionary, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	var fleets := nef_fleets(state, eid)
	var f: Fleet = fleets[fleets.size() - 1]
	var n := nef_count(state, eid)
	@warning_ignore("integer_division")
	var gone := int(ed["pop"]) / maxi(1, n)
	f.remove_ship(SHIP)
	var sid := f.system_id
	if f.ships.is_empty():
		state.fleets.erase(f.id)
	ed["pop"] = maxi(0, int(ed["pop"]) - gone)
	ed["nefs"] = n - 1
	ed["hope"] = _c("hope_after_secession", 35)
	var where := "s'éloigne seule dans le noir"
	if Minors.enabled(state):
		var pid := _free_world(state, sid)
		if pid >= 0:
			var kinds: Array[String] = []
			for k in Minors.kind_ids():
				if String(Minors.kind_def(k).get("family", "")) == "space":
					kinds.append(k)
			if not kinds.is_empty():
				var mid := Minors.create(state, kinds[0], sid, pid, {"fam": "space", "name": "Nef dissidente des %s" % e.short_name(), "short": "Dissidents", "species": e.faction_id})
				if mid >= 0:
					var c: Colony = state.colonies.get(pid)
					if c != null:
						c.population = maxi(c.population, gone)
					where = "se pose sur %s et y fonde une cité libre" % state.galaxy.get_planet(pid).display_name(state.galaxy)
	added.append(state.add_chronicle("Le désespoir l'emporte : une Nef-cité de %s rompt avec le conseil et %s, emportant %d population." % [
			e.display_name(), where, gone], Espionage.public_to(state, [eid])))


static func _free_world(state: GameState, sid: int) -> int:
	if state.system_owner(sid) >= 0:
		return -1
	var best := -1
	for pid in state.galaxy.systems[sid].planet_ids:
		var p := state.galaxy.get_planet(pid)
		if state.colonies.has(pid) or Insolites.is_eaten(state, pid):
			continue
		if not GameData.planet_type(p.type).get("pop_yields", {}).is_empty() and (best < 0 or p.size > state.galaxy.get_planet(best).size):
			best = pid
	return best


# --- L'Arrivée (prop. 13) --------------------------------------------------------------------------

static func check_settle(state: GameState, eid: int) -> String:
	if Insolites.kind(state, eid) != "exode":
		return "seul l'Exode peut se poser"
	if arrived(state, eid):
		return "l'Exode s'est déjà posé"
	if not Victory.has_tech(state, eid, "terre_promise"):
		return "il faut les Chants de la route pour reconnaître la Terre promise"
	var pid := Victory.promised_planet(state, eid)
	if pid < 0:
		return "aucune Terre promise dans cette galaxie"
	var cf := FactionTraits.city_fleet(state, eid)
	var p := state.galaxy.get_planet(pid)
	if cf == null or cf.is_moving() or cf.system_id != p.system_id:
		return "les nefs doivent mouiller au-dessus de la Terre promise"
	var c: Colony = state.colonies.get(pid)
	if c != null and c.owner != eid:
		return "quelqu'un vit déjà sur la Terre promise : il faudra la reprendre"
	if state.system_owner(p.system_id) >= 0 and state.system_owner(p.system_id) != eid:
		return "le système de la Terre promise est revendiqué par un autre empire"
	return ""


static func settle(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	var ed := Insolites.emp(state, eid)
	var pid := Victory.promised_planet(state, eid)
	var p := state.galaxy.get_planet(pid)
	var cap := maxi(1, Economy.max_pop(state, p, eid))
	var c := Colony.new()
	c.planet_id = pid
	c.owner = eid
	c.kind = Colony.KIND_COLONY
	c.population = clampi(int(ed["pop"]), 1, cap)
	for b in GameData.rules()["homeworld"]["buildings"]:
		c.buildings.append(String(b))
	# Les espèces recueillies en route descendent avec leurs hôtes (populations mixtes).
	var sp: Dictionary = ed.get("sp", {})
	var ks := sp.keys()
	ks.sort()
	var room := c.population - 1
	for k in ks:
		if String(k) == e.faction_id or room <= 0:
			continue
		var n := mini(int(sp[k]), room)
		c.species[String(k)] = n
		room -= n
	state.colonies[pid] = c
	ed["pop"] = maxi(0, int(ed["pop"]) - c.population)
	ed["arrived"] = 1
	ed["final"] = state.tick + _c("final_hunt_days", 30)
	e.capital_planet = pid
	state.rebuild_ownership()
	state.garrisons[p.system_id] = Combat.garrison_max(state, p.system_id)
	added.append(state.add_chronicle("L'Arrivée. Après onze générations de route, %s se pose sur %s. On ouvre les sas ; l'air sent la pluie. Quelque part derrière, les Traqueurs accélèrent." % [
			e.display_name(), p.display_name(state.galaxy)], Espionage.public_to(state, [eid])))


static func status_lines(state: GameState, eid: int, ed: Dictionary) -> Array[String]:
	var out: Array[String] = []
	out.append("Population à bord : %d / %d (%d nef%s)" % [int(ed["pop"]), pop_cap(state, eid), nef_count(state, eid), "s" if nef_count(state, eid) > 1 else ""])
	out.append("Espoir : %d / %d" % [int(ed.get("hope", 0)), _c("hope_max", 100)])
	if arrived(state, eid):
		out.append("L'Exode s'est posé : c'est l'Arrivée.")
	else:
		var anc: Dictionary = ed.get("anc", {})
		if int(anc.get("s", -1)) >= 0:
			var left := Insolites.tuned(state, eid, "exode", "stalk_days", _c("stalk_days", 720)) - (state.tick - int(anc["t"]))
			out.append("Mouillage à %s : les Traqueurs frappent dans %d jours" % [state.galaxy.systems[int(anc["s"])].system_name, maxi(0, left)])
		else:
			out.append("En route : les nefs ne produisent rien")
	return out
