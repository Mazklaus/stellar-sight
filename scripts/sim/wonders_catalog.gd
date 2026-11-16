class_name WondersCatalog
extends RefCounted
## Catalogue des merveilles (lot 2) : effets codés (« special » et drapeaux « fx » lus par les autres
## systèmes), ruines à restaurer (Stellaris), Monde-anneau qui change les planètes de son système,
## Portes stellaires (sauts d'une porte à l'autre), trait Architecte des gouverneurs.
##
## Les drapeaux « fx » (wonder_sight, refuge, pirate_peace, tamer, hero_start_lvl, grievance_half,
## crisis_last, ancient_friend, all_seeing, amph_voix_pct, known_tech_pct, tribunal) passent par
## Research.fx_int, gardé en cache : les autres systèmes les lisent sans parcourir les colonies.

const MONTH := 30
const OFFSET := 23
## Longueur d'un saut de porte à porte (unités) : moins d'un jour pour toute flotte.
const GATE_LEN := 1


static func setup(state: GameState) -> void:
	if not Wonders.enabled(state):
		return
	_place_ruins(state)


## Ruines (prop. 15) : quelques merveilles galactiques des premières ères gisent sur des mondes
## inhabités, loin des capitales ; qui tient la planète peut les restaurer pour 60 % du prix.
static func _place_ruins(state: GameState) -> void:
	var n := 0
	for row in Wonders.rules().get("ruins_by_size", []):
		if state.galaxy.systems.size() >= int(row[0]):
			n = int(row[1])
	if n <= 0:
		return
	var cands: Array[String] = []
	for wid in Wonders.all_ids():
		var d := Wonders.def(wid)
		if Wonders.family(wid) == "galactique" and int(d.get("era", 1)) <= 3 and Wonders.in_pool(state, wid) and not bool(d.get("culture", false)) and wid != "bourse_galactique":
			cands.append(wid)
	var homes: Array[int] = []
	for e in state.empires:
		if e.capital_planet >= 0:
			homes.append(state.galaxy.get_planet(e.capital_planet).system_id)
	var far := {}
	for h in homes:
		var j := FactionTraits.jumps_from(state.galaxy, h)
		for sid in j:
			far[sid] = mini(int(far.get(sid, 999)), int(j[sid]))
	var planets: Array[int] = []
	for p in state.galaxy.planets:
		if state.colonies.has(p.id) or int(far.get(p.system_id, 999)) < 3:
			continue
		planets.append(p.id)
	var ruins := {}
	var used := {}
	for i in n:
		if cands.is_empty() or planets.is_empty():
			break
		var wid: String = cands.pop_at(absi(hash([state.seed_value, "ruine", i])) % cands.size())
		var pid := planets[absi(hash([state.seed_value, "ruine_site", i])) % planets.size()]
		var sid := state.galaxy.get_planet(pid).system_id
		if used.has(sid):
			continue
		used[sid] = true
		ruins[wid] = pid
	state.wonders["ruins"] = ruins


## Planète où gît la ruine de cette merveille, -1 sinon.
static func ruin_of(state: GameState, wid: String) -> int:
	return int(state.wonders.get("ruins", {}).get(wid, -1))


## Ruines sur cette planète (identifiants).
static func ruins_at(state: GameState, pid: int) -> Array[String]:
	var out: Array[String] = []
	var r: Dictionary = state.wonders.get("ruins", {})
	var keys := r.keys()
	keys.sort()
	for wid in keys:
		if int(r[wid]) == pid:
			out.append(String(wid))
	return out


static func restore_cost(state: GameState, eid: int, wid: String) -> Dictionary:
	return Research.scaled_amounts(Wonders.total_cost(state, eid, wid), Wonders.r_int("restore_pct") - 100)


## "" si l'empire peut restaurer cette ruine (il tient la planète, colonie fondée).
static func check_restore(state: GameState, eid: int, wid: String) -> String:
	var pid := ruin_of(state, wid)
	if pid < 0:
		return "aucune ruine de cette merveille"
	var c: Colony = state.colonies.get(pid)
	if c == null or c.owner != eid or not c.is_established():
		return "il faut tenir %s" % state.galaxy.get_planet(pid).display_name(state.galaxy)
	if not Wonders.build_of(state, eid, wid).is_empty():
		return "restauration déjà en cours"
	if Research.current_era(state, eid) < int(Wonders.def(wid).get("era", 1)):
		return "il faut atteindre l'ère %d" % int(Wonders.def(wid).get("era", 1))
	var adv := Research.scaled_amounts(restore_cost(state, eid, wid), Wonders.r_int("advance_pct") - 100)
	if not Economy.can_afford(state.get_empire(eid), adv):
		return "ressources insuffisantes pour l'avance (il faut %s)" % GameData.format_amounts(adv)
	return ""


## Restaurer une ruine : un chantier à part (hors limite), 60 % du prix et de la durée.
static func restore(state: GameState, eid: int, wid: String, added: Array[Dictionary]) -> void:
	var pid := ruin_of(state, wid)
	var tot := restore_cost(state, eid, wid)
	var adv := Research.scaled_amounts(tot, Wonders.r_int("advance_pct") - 100)
	Economy.pay(state.get_empire(eid), adv)
	var b: Dictionary = Wonders._m(state, "build")
	if not b.has(wid):
		b[wid] = {}
	@warning_ignore("integer_division")
	b[wid][str(eid)] = {"p": pid, "pts": 0, "need": Wonders.need_pts(wid) * Wonders.r_int("restore_pct") / 100, "paid": adv, "total": tot,
			"ok": 1, "since": state.tick, "st": 0, "ruin": 1}
	var p := state.galaxy.get_planet(pid)
	added.append(state.add_chronicle("%s entreprend de relever %s sur %s. Les archéologues pleurent, les maçons sifflent." % [
			state.get_empire(eid).short_name(), Wonders.label(wid), p.display_name(state.galaxy)], Espionage.private_to(state, [eid], p.system_id)))


# --- Lecture des drapeaux -----------------------------------------------------------------------

static func sees_all(state: GameState, eid: int) -> bool:
	return eid >= 0 and not GameState.is_npc(eid) and Research.fx_int(state, eid, "wonder_sight") > 0


static func fx(state: GameState, eid: int, key: String) -> int:
	if eid < 0 or GameState.is_npc(eid) or state.wonders.is_empty():
		return 0
	return Research.fx_int(state, eid, key)


## Voix amphictyoniques en plus (Sénat des étoiles, Tribunal des étoiles), en pour cent.
static func voix_pct(state: GameState, eid: int) -> int:
	return fx(state, eid, "amph_voix_pct")


## Collège universel : une technologie déjà connue d'un empire rencontré coûte moins.
static func tech_cost_pct(state: GameState, eid: int, tid: String) -> int:
	var v := fx(state, eid, "known_tech_pct")
	if v == 0:
		return 0
	var e := state.get_empire(eid)
	for o in e.contacts:
		var oe := state.get_empire(o)
		if oe and oe.techs.has(tid):
			return v
	return 0


## Si la vue de toute la galaxie est acquise (Œil du Démiurge), remplit seen.
static func see_all(state: GameState, eid: int, seen: Dictionary) -> void:
	if fx(state, eid, "all_seeing") > 0:
		for s in state.galaxy.systems:
			seen[s.id] = true


## Grand Caravansérail : chaque route commerciale étrangère qui traverse le système paie un péage.
static func tolls(state: GameState, routes: Array, income: Dictionary) -> void:
	if state.wonders.is_empty():
		return
	var booths := {}
	for row in Wonders.held(state):
		if String(Wonders.def(String(row[0])).get("special", "")) == "toll":
			booths[state.galaxy.get_planet(int(row[1])).system_id] = int(row[2])
	if booths.is_empty():
		return
	for r: Dictionary in routes:
		if String(r["kind"]) != "ext" or bool(r.get("blocked", false)):
			continue
		for sid in r["path"]:
			var o := int(booths.get(int(sid), -1))
			if o >= 0 and o != int(r["from"]) and o != int(r["to"]):
				var inc: Dictionary = income.get(o, {})
				inc["influence"] = int(inc.get("influence", 0)) + Wonders.r_int("toll_influence")
				income[o] = inc


## Lieux saints (prop. 20) : une colonie qui tient une merveille (hors mégastructures) prêche deux
## fois plus fort pour la foi d'État de son maître.
static func holy_x(state: GameState, c: Colony, fid: String) -> int:
	if state.wonders.is_empty() or GameState.is_npc(c.owner) or not state.faith_on:
		return 1
	for b in c.buildings:
		if Wonders.is_wonder(b) and Wonders.family(b) != "mega" and Faiths.state_faith(state, c.owner) == fid:
			return 2
	return 1


# --- Chaque jour ---------------------------------------------------------------------------------

static func daily(state: GameState, added: Array[Dictionary]) -> void:
	if posmod(state.tick, MONTH) != OFFSET:
		return
	var held := Wonders.held(state)
	if held.is_empty():
		return
	var gates_sig := PackedStringArray()
	for row in held:
		var wid := String(row[0])
		var pid := int(row[1])
		var eid := int(row[2])
		if eid < 0 or GameState.is_npc(eid):
			continue
		if Wonders.family(wid) == "credo" and state.faith_on:
			var sf := Faiths.state_faith(state, eid)
			if sf != "":
				FaithWars.add_zeal(state, sf, 1)  # les merveilles de credo nourrissent le zèle
		match String(Wonders.def(wid).get("special", "")):
			"calm":
				_calm(state, pid, added)
			"eureka", "free_tech":
				_era_gift(state, wid, pid, eid, added)
			"bulwark":
				if Crisis.active(state) and not state.wonders.get("bulwark", {}).has("%s#%d" % [wid, pid]):
					_bulwark(state, wid, pid, eid, added)
		if wid == "porte_stellaire" and not Wonders.is_staging(state, wid, pid):
			gates_sig.append("%d:%d" % [state.galaxy.get_planet(pid).system_id, eid])
	_pirate_tribute(state)
	var sig := ",".join(gates_sig)
	if sig != String(state.wonders.get("gsig", "")) or not state.galaxy.gates.is_empty():
		state.wonders["gsig"] = sig
		refresh_gates(state)  # aussi chaque mois : alliances et droits de passage changent


## Brise-tempêtes : plus aucune tempête à 5 sauts ou moins.
static func _calm(state: GameState, pid: int, added: Array[Dictionary]) -> void:
	if Terrain.storms(state).is_empty():
		return
	var j := FactionTraits.jumps_from(state.galaxy, state.galaxy.get_planet(pid).system_id)
	for st: Dictionary in Terrain.storms(state):
		if int(j.get(int(st["c"]), 999)) <= 5 and int(st["left"]) > 1:
			st["left"] = 1
			added.append(state.add_chronicle("Les antennes du Brise-tempêtes chantent : la %s se défait avant d'atteindre ses eaux." % Terrain.label(String(st["k"])).to_lower()))


## Observatoire de l'Horizon et Calculateur de Raison : à chaque ère franchie, un cadeau de savoir.
static func _era_gift(state: GameState, wid: String, pid: int, eid: int, added: Array[Dictionary]) -> void:
	var key := "%s#%d" % [wid, pid]
	var eras: Dictionary = Wonders._m(state, "era")
	var now := Research.current_era(state, eid)
	if not eras.has(key):
		eras[key] = now
		return
	if int(eras[key]) >= now and int(eras.get(key + "@", eid)) == eid:
		return
	eras[key] = now
	eras[key + "@"] = eid
	_gift(state, wid, eid, added)


static func _gift(state: GameState, wid: String, eid: int, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	var era := Research.current_era(state, eid)
	var best := ""
	var best_cost := 1 << 40
	for tid in Research.visible_ids(e.faction()):
		if e.techs.has(tid) or not Research.is_available(state, eid, tid):
			continue
		var special := String(Wonders.def(wid).get("special", ""))
		if special == "eureka" and (e.eurekas.has(tid) or int(Research.tech(tid).get("era", 1)) != era):
			continue
		var c := Research.cost(state, eid, tid)
		if c < best_cost or (c == best_cost and tid < best):
			best = tid
			best_cost = c
	if best == "":
		return
	var label := String(Research.tech(best).get("label", best))
	if String(Wonders.def(wid).get("special", "")) == "free_tech":
		Research.grant(state, eid, [best])
		added.append(state.add_chronicle("%s : le Calculateur de Raison livre %s, tout cuit." % [e.short_name(), label], Espionage.private_to(state, [eid])))
	else:
		e.eurekas[best] = true
		@warning_ignore("integer_division")
		Research.add_progress(state, eid, best, maxi(1, best_cost * int(Research.data().get("eureka_pct", 40)) / 100))
		added.append(state.add_chronicle("%s : l'Observatoire de l'Horizon offre un eurêka pour %s." % [e.short_name(), label], Espionage.private_to(state, [eid])))


## Rade franche et Tripot des lunes : les repaires versent un tribut à qui les abrite.
static func _pirate_tribute(state: GameState) -> void:
	if state.lairs.is_empty():
		return
	var n := Pirates.lair_ids(state).size()
	for e in state.empires:
		if not e.eliminated and fx(state, e.id, "pirate_peace") > 0:
			e.resources["energy"] = int(e.resources.get("energy", 0)) + n * Wonders.r_int("pirate_tribute")


## Rempart de l'Aube : une flotte de défense se lève (une fois par rempart et par crise).
static func _bulwark(state: GameState, wid: String, pid: int, eid: int, added: Array[Dictionary]) -> void:
	var key := "%s#%d" % [wid, pid]
	Wonders._m(state, "bulwark")[key] = state.tick
	var best := ""
	var best_v := -1
	for sid in Designs.buildable_ids(state, eid):
		var v := int(Fleets.ship_cost(state, eid, sid).get("materials", 0))
		if Combat.is_armed_ship(sid) and v > best_v:
			best = sid
			best_v = v
	if best == "":
		return
	var sys := state.galaxy.get_planet(pid).system_id
	var f := state.spawn_ship(eid, best, sys)
	for i in Wonders.r_int("bulwark_fleet") - 1:
		f.add_ship(best, -1, Research.mark_gen(state, eid))
	f.fleet_name = "Gardes du Rempart"
	added.append(state.add_chronicle("%s : les portes du Rempart de l'Aube s'ouvrent, une flotte de garde en sort." % state.get_empire(eid).short_name(),
			Espionage.private_to(state, [eid], sys)))


# --- Étapes et achèvement ------------------------------------------------------------------------

static func on_stage(state: GameState, wid: String, eid: int, pid: int, stage: int, added: Array[Dictionary]) -> void:
	var sts := Wonders.stages(wid)
	if stage >= 1 and stage <= sts.size() and int((sts[stage - 1] as Dictionary).get("ring", 0)) > 0:
		_ring_segment(state, pid, eid, added)


static func on_complete(state: GameState, wid: String, eid: int, pid: int, added: Array[Dictionary]) -> void:
	if state.wonders.get("ruins", {}).has(wid):
		(state.wonders["ruins"] as Dictionary).erase(wid)
	var sts := Wonders.stages(wid)
	if not sts.is_empty() and int((sts[-1] as Dictionary).get("ring", 0)) > 0:
		_ring_segment(state, pid, eid, added)
	match String(Wonders.def(wid).get("special", "")):
		"reveal":
			_reveal(state, eid, state.galaxy.get_planet(pid).system_id, 6)
		"eureka", "free_tech":
			Wonders._m(state, "era")["%s#%d" % [wid, pid]] = Research.current_era(state, eid)
			Wonders._m(state, "era")["%s#%d@" % [wid, pid]] = eid
			_gift(state, wid, eid, added)
		"bulwark":
			if Crisis.active(state):
				_bulwark(state, wid, pid, eid, added)
		"ancient_friend":
			if Ancients.enabled(state):
				for id in Ancients.ids(state):
					var a := Ancients.get_a(state, id)
					if not a.is_empty() and (a.get("contact", {}) as Dictionary).has(eid) and not Ancients.no_opinion(state, id):
						(a["op"] as Dictionary)[eid] = maxi(Ancients.opinion(state, id, eid), 60)
	if wid == "porte_stellaire":
		refresh_gates(state)
	_architect(state, eid, pid, added)


## Gouverneur du système : il gagne le trait Architecte (prop. 24).
static func _architect(state: GameState, eid: int, pid: int, added: Array[Dictionary]) -> void:
	if state.heroes.is_empty():
		return
	var h := Heroes.at_post(state, "system", state.galaxy.get_planet(pid).system_id, eid)
	if not h.is_empty():
		CrisisAllies._give(state, h, "architecte", added)
		Heroes.gain_xp(state, h, 100)  # le héros posté à l'achèvement y gagne en renommée


## Cartothèque des vents : révèle les systèmes à `radius` sauts.
static func _reveal(state: GameState, eid: int, sid: int, radius: int) -> void:
	var e := state.get_empire(eid)
	var j := FactionTraits.jumps_from(state.galaxy, sid)
	for s in j:
		if int(j[s]) <= radius:
			e.explored[int(s)] = true


## Monde-anneau : une planète du système devient un segment d'anneau.
static func _ring_segment(state: GameState, pid: int, eid: int, added: Array[Dictionary]) -> void:
	var sid := state.galaxy.get_planet(pid).system_id
	for p in state.galaxy.planets:
		if p.system_id != sid or p.type == "anneau":
			continue
		var c: Colony = state.colonies.get(p.id)
		if c != null and c.owner != eid:
			continue
		state.override_planet(p.id, {"type": "anneau"})
		state.get_empire(eid).hab_cache.clear()
		added.append(state.add_chronicle("%s : un segment d'anneau se referme autour de %s. Il y a de la place pour tout le monde, et de la vue." % [
				state.get_empire(eid).short_name(), state.galaxy.systems[sid].system_name], Espionage.private_to(state, [eid], sid)))
		return


# --- Portes stellaires ---------------------------------------------------------------------------

## Reconstruit le réseau des portes (galaxy.gates : système -> propriétaire) et vide les caches de
## chemins. Appelé à l'ouverture d'une porte, au chargement et quand une porte change de mains.
static func refresh_gates(state: GameState) -> void:
	var g := {}
	for row in Wonders.held(state):
		if String(row[0]) == "porte_stellaire" and not Wonders.is_staging(state, "porte_stellaire", int(row[1])):
			g[state.galaxy.get_planet(int(row[1])).system_id] = int(row[2])
	state.galaxy.gates = g
	for e in state.empires:
		e.path_cache.clear()
		e.border_cache.clear()
		e.path_cache_explored = -1


## L'empire peut-il emprunter la porte de ce système ? La sienne, celle d'un allié ou d'un empire
## qui lui accorde le droit de passage.
static func gate_open(state: GameState, eid: int, sid: int) -> bool:
	var o := int(state.galaxy.gates.get(sid, -1))
	if o < 0:
		return false
	if o == eid:
		return true
	if Diplomacy.allied(state, eid, o):
		return true
	return Borders.active(state) and Borders.grants(state, o, eid)


# --- Tribunal des étoiles -----------------------------------------------------------------------

static func check_tribunal(state: GameState, eid: int) -> String:
	if fx(state, eid, "tribunal") <= 0:
		return "il faut tenir le Tribunal des étoiles"
	if not Amphictyony.founded(state):
		return "l'Amphictyonie n'existe pas encore"
	if Amphictyony.in_session(state):
		return "une séance est en cours"
	var last := int(state.wonders.get("trib", {}).get(str(eid), -999999))
	if state.tick - last < Wonders.r_int("tribunal_cooldown"):
		return "une fois par décennie (prochaine fois le %s)" % GameCalendar.date_string(last + Wonders.r_int("tribunal_cooldown"))
	return ""


static func tribunal(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	Wonders._m(state, "trib")[str(eid)] = state.tick
	state.amph["next"] = int(state.amph["next"]) + Wonders.r_int("tribunal_delay")
	added.append(state.add_chronicle("%s saisit le Tribunal des étoiles : la prochaine séance de l'Amphictyonie est repoussée d'un an. Les juristes adorent." % state.get_empire(eid).display_name(),
			Espionage.public_to(state, [eid])))
