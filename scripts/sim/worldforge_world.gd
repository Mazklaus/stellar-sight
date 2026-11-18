class_name WorldForgeWorld
extends RefCounted
## La Forge des mondes, côté mondes : mondes-reliquaires des Façonneurs (prop. 27), monde-abri (prop. 28),
## mondes vivants (prop. 29), carcasses de titans (prop. 30), moteurs planétaires et marche des mondes
## (prop. 23, 25), rosettes de Klemperer (prop. 24), bélier planétaire (prop. 26), commandes (prop. 13).
##
## Sous-états de state.forge : "relics" {"pid": {"n": rang du nom, "open": 0/1, "woke": 0/1, "living":
## {"o", "hate": jours} ou absent, "dead": 0/1}}, "moving" {"pid": {"to", "w", "o", "from"}}, "rosettes"
## {"sid": {"o", "unpaid"}}, "carcass" {"sid": {"o", "until"}}.

static func _r(key: String, def := 0) -> int:
	return WorldForge.r_int(key, def)


# --- Mondes-reliquaires (prop. 27-29) ----------------------------------------------------------

## Pose les mondes-reliquaires à la création (réglage Aucun / Peu / Beaucoup) : un corps nouveau de
## type "reliquaire" dans des systèmes sans peuple au départ, choisis par hachage.
static func place_relics(state: GameState) -> void:
	var per := 0
	for o: Dictionary in WorldForge.ancient_defs():
		if String(o["id"]) == String(state.forge.get("anc", "")):
			per = int(o.get("per", 0))
	if per <= 0:
		return
	var n := state.galaxy.systems.size() / per
	if n <= 0:
		return
	var homes := {}
	for e in state.empires:
		if e.home_planet >= 0 and state.galaxy.get_planet(e.home_planet) != null:
			homes[state.galaxy.get_planet(e.home_planet).system_id] = true
	var cands: Array = []
	for s in state.galaxy.systems:
		if homes.has(s.id) or s.planet_ids.size() >= 8:
			continue
		cands.append([WorldForge._h(state, ["relic", s.id]), s.id])
	cands.sort()
	var names: Array = (WorldForge.cfg("relics").get("names", []) as Array)
	for i in mini(n, cands.size()):
		var sid := int(cands[i][1])
		var pid := WorldForge.add_body(state, sid, "reliquaire", 3)
		WorldForge.sub(state, "relics")[str(pid)] = {"n": i % maxi(1, names.size()), "open": 0, "woke": 0}


static func relic(state: GameState, pid: int) -> Dictionary:
	var v: Variant = WorldForge.sub(state, "relics").get(str(pid), {})
	return v if v is Dictionary else {}


## Monde-reliquaire encore scellé.
static func is_relic(state: GameState, pid: int) -> bool:
	if state.forge.is_empty():
		return false
	var r := relic(state, pid)
	return not r.is_empty() and int(r.get("open", 0)) == 0


static func is_living(state: GameState, pid: int) -> bool:
	if state.forge.is_empty():
		return false
	var r := relic(state, pid)
	return r.has("living") and int(r.get("dead", 0)) == 0


static func relic_name(state: GameState, pid: int) -> String:
	if state.forge.is_empty():
		return ""
	var r := relic(state, pid)
	if r.is_empty():
		return ""
	var key := "living_names" if r.has("living") else "names"
	var names: Array = (WorldForge.cfg("relics").get(key, []) as Array)
	if names.is_empty():
		return ""
	var s := String(names[int(r.get("n", 0)) % names.size()])
	return s.substr(0, 1).to_upper() + s.substr(1)


## Chantier « ouvrir » achevé : défenses (une fois), trésor, monde-abri ou effondré, parfois vivant.
static func opened(state: GameState, j: Dictionary, added: Array[Dictionary]) -> void:
	var pid := int(j["p"])
	var eid := int(j.get("b", j["o"]))
	var sid := int(j["s"])
	var r := relic(state, pid)
	var e := state.get_empire(eid)
	if r.is_empty() or e == null:
		return
	var nm := relic_name(state, pid)
	if int(r.get("woke", 0)) == 0 and WorldForge._h(state, ["wake", pid]) % 100 < _r("relic_wake_pct", 34):
		r["woke"] = 1
		var lost := ""
		for f in Megastructures.architects_at(state, eid, sid):
			state.fleets.erase(f.id)
			lost = " Le Vaisseau-architecte est perdu corps et biens."
			break
		for x in state.empires:
			x.path_cache.clear()
		added.append(state.add_chronicle("%s s'éveille : ses défenses dormantes balaient l'orbite.%s Les sceaux, eux, ont cédé d'un cran ; la prochaine fois sera la bonne." % [nm, lost],
				WorldForge._who(state, eid, sid)))
		return
	r["open"] = 1
	var p := state.galaxy.get_planet(pid)
	var collapsed := WorldForge._h(state, ["collapse", pid]) % 100 < _r("relic_collapsed_pct", 20)
	if collapsed:
		WorldForge.reshape(state, pid, "barren", p.size)
	else:
		WorldForge.reshape(state, pid, "abri", mini(9, p.size + int(WorldForge.op_def("ouvrir").get("grow", 1))))
		WorldForge.mark_world(state, pid, "abri", eid)
	var tre := WorldForge.r_dict("relic_treasure")
	for res in tre:
		e.resources[res] = int(e.resources.get(res, 0)) + int(tre[res])
	WorldForge.add_mass(state, eid, _r("relic_mass", 80))
	var living := not collapsed and WorldForge._h(state, ["living", pid]) % 100 < _r("relic_living_pct", 10)
	var txt := "%s s'ouvre. Trésor des Façonneurs : %s et %d Masse. " % [nm, GameData.format_amounts(tre), _r("relic_mass", 80)]
	if collapsed:
		txt += "Mais l'intérieur s'effondre sur lui-même : il n'en reste qu'un monde stérile."
	elif living:
		var ln: Array = (WorldForge.cfg("relics").get("living_names", []) as Array)
		r["living"] = {"o": -1, "hate": 0}
		r["n"] = WorldForge._h(state, ["lname", pid]) % maxi(1, ln.size())
		txt += "Au cœur du monde, quelque chose bat. Il est vivant, et il s'appelle désormais %s. Il choisira ses hôtes." % relic_name(state, pid)
	else:
		txt += "Ses salles profondes deviennent un monde-abri : aucune crise n'y entre."
	WorldForge._stat(state, eid, "opened", 1)
	Announce.next(state, "forge_made", {"actor": eid, "system": sid})
	added.append(state.add_chronicle(txt, WorldForge._who(state, eid, sid)))
	WorldForge.touch(state)


## Prop. 28 : la colonie d'un monde-abri est à l'abri des crises (lu par Crisis).
static func shelter(state: GameState, pid: int) -> bool:
	if state.forge.is_empty():
		return false
	var p := state.galaxy.get_planet(pid)
	return p != null and p.type == "abri"


## Un monde vivant aime son hôte s'il n'a jamais défait de monde, le hait sinon (prop. 29).
static func loves(state: GameState, pid: int, eid: int) -> bool:
	return WorldForge.stat(state, eid, "dism") == 0 and WorldForge.stat(state, eid, "rams") == 0 and is_living(state, pid)


# --- Carcasses de titans (prop. 30) ------------------------------------------------------------

## Un gardien abattu laisse une carcasse en orbite : matériaux et cristaux pour le maître du système,
## habitat-monde à moitié prix tant qu'elle est là.
static func on_titan_slain(state: GameState, gid: String, eid: int, sid: int, added: Array[Dictionary]) -> void:
	if state.forge.is_empty() or sid < 0:
		return
	WorldForge.sub(state, "carcass")[str(sid)] = {"o": eid, "until": state.tick + _r("carcass_days", 3600), "g": gid}
	added.append(state.add_chronicle("La carcasse du titan dérive autour de %s : une montagne d'os et de métal, que les ferrailleurs dépècent déjà. On pourrait y ancrer un habitat-monde." % state.galaxy.systems[sid].system_name,
			WorldForge._who(state, eid, sid)))


# --- Ordres -----------------------------------------------------------------------------------

static func check(state: GameState, eid: int, act: String, d: Dictionary) -> String:
	match act:
		"move":
			return check_move(state, eid, int(d.get("p", -1)), int(d.get("t", -1)))
		"rosette":
			return check_rosette(state, eid, int(d.get("s", -1)))
		"ram":
			return check_ram(state, eid, int(d.get("p", -1)), int(d.get("t", -1)))
		"order":
			return check_order(state, eid, int(d.get("seller", -1)), int(d.get("s", -1)), String(d.get("a", "")))
	return "ordre inconnu"


static func apply(state: GameState, eid: int, act: String, d: Dictionary, added: Array[Dictionary]) -> void:
	match act:
		"move":
			move(state, eid, int(d["p"]), int(d["t"]), added)
		"rosette":
			rosette(state, eid, int(d["s"]), added)
		"ram":
			ram(state, eid, int(d["p"]), int(d["t"]), added)
		"order":
			order(state, eid, int(d["seller"]), int(d["s"]), String(d["a"]), added)


# --- Moteurs planétaires : la marche (prop. 23, 25) --------------------------------------------

static func _engine_world(state: GameState, eid: int, pid: int) -> String:
	var p := state.galaxy.get_planet(pid)
	if p == null or WorldForge.is_gone(state, pid):
		return "monde inconnu"
	if int(WorldForge.world(state, pid).get("eng", 0)) <= 0:
		return "ce monde n'a pas de moteurs planétaires"
	if WorldForge.holder(state, pid) != eid:
		return "ce monde n'est pas à vous"
	if WorldForge.sub(state, "moving").has(str(pid)):
		return "ce monde est déjà en marche"
	if not WorldForge.job_on(state, pid).is_empty():
		return "un chantier est en cours sur ce monde"
	return ""


## Systèmes où ce monde peut aller : voisins par une route, à vous ou sans maître, avec une orbite libre.
static func move_targets(state: GameState, eid: int, pid: int) -> Array[int]:
	var out: Array[int] = []
	var p := state.galaxy.get_planet(pid)
	if p == null:
		return out
	for n in state.galaxy.systems[p.system_id].neighbors:
		var o := state.system_owner(n)
		if (o == eid or o < 0) and state.galaxy.systems[n].planet_ids.size() < 9:
			out.append(n)
	out.sort()
	return out


static func check_move(state: GameState, eid: int, pid: int, to: int) -> String:
	var why := _engine_world(state, eid, pid)
	if why != "":
		return why
	if not move_targets(state, eid, pid).has(to):
		return "seulement vers un système voisin, à vous ou sans maître, avec une orbite libre"
	return ""


static func move(state: GameState, eid: int, pid: int, to: int, added: Array[Dictionary]) -> void:
	var p := state.galaxy.get_planet(pid)
	var days := _r("move_days", 720)
	WorldForge.sub(state, "moving")[str(pid)] = {"to": to, "w": days, "o": eid, "from": p.system_id}
	# Une rosette perd ce monde.
	_dissolve_if_small(state, p.system_id, added)
	Announce.next(state, "forge_moving", {"actor": eid, "system": p.system_id})
	added.append(state.add_chronicle("%s se met en marche vers %s : %d jours de voyage, au pas d'un continent. Ses habitants regardent les étoiles changer de place." % [
			WorldForge.world_name(state, pid), state.galaxy.systems[to].system_name, days], WorldForge._who(state, eid, p.system_id, true)))


static func _march_day(state: GameState, added: Array[Dictionary]) -> void:
	var mv := WorldForge.sub(state, "moving")
	var keys := mv.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	for k in keys:
		var m: Dictionary = mv[k]
		var pid := int(k)
		var o := int(m["o"])
		var p := state.galaxy.get_planet(pid)
		if p == null or state.get_empire(o) == null:
			mv.erase(k)
			continue
		# Attaquable en route : une flotte ennemie en guerre au départ ou à l'arrivée arrête la marche et
		# entame la structure.
		if WorldForgeBridges.enemy_present(state, o, p.system_id) or WorldForgeBridges.enemy_present(state, o, int(m["to"])):
			var wd := WorldForge.world(state, pid)
			if not wd.is_empty() and state.tick % 30 == 0:
				wd["integ"] = maxi(1, int(wd.get("integ", 100)) - 5)
			continue
		m["w"] = int(m["w"]) - 1
		if int(m["w"]) > 0:
			continue
		mv.erase(k)
		var to := int(m["to"])
		if state.galaxy.systems[to].planet_ids.size() >= 9:
			added.append(state.add_chronicle("%s arrive aux portes de %s, mais il n'y a plus une orbite libre : il s'arrête où il est." % [
					WorldForge.world_name(state, pid), state.galaxy.systems[to].system_name], [o]))
			continue
		WorldForge.move_body(state, pid, to)
		WorldForge._stat(state, o, "moved", 1)
		added.append(state.add_chronicle("%s a rejoint %s. Les cartographes déchirent leurs cartes ; les astrologues, leurs horoscopes." % [
				WorldForge.world_name(state, pid), state.galaxy.systems[to].system_name], WorldForge._who(state, o, to, true)))


# --- Rosettes de Klemperer (prop. 24) ---------------------------------------------------------

## Mondes peuplés de l'empire dans le système (hors mondes en marche).
static func rosette_worlds(state: GameState, eid: int, sid: int) -> Array[int]:
	var out: Array[int] = []
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == eid and c.is_colony() and c.population > 0 and not WorldForge.sub(state, "moving").has(str(pid)):
			out.append(pid)
	return out


static func check_rosette(state: GameState, eid: int, sid: int) -> String:
	if not WorldForge.unlocked(state, eid, "rosette"):
		return "technologie requise : %s" % Research.missing_text(state, eid, ["moteurs_planetaires"])
	if sid < 0 or sid >= state.galaxy.systems.size():
		return "système inconnu"
	if WorldForge.sub(state, "rosettes").has(str(sid)):
		return "une rosette tourne déjà ici"
	if not WorldForge._holds(state, eid, sid):
		return "il faut tenir le système"
	var n := rosette_worlds(state, eid, sid).size()
	if n < _r("rosette_min", 3) or n > _r("rosette_max", 5):
		return "il faut de %d à %d de vos mondes peuplés dans le système (%d)" % [_r("rosette_min", 3), _r("rosette_max", 5), n]
	var cost: Dictionary = (WorldForge.cfg("instant").get("rosette", {}) as Dictionary).get("cost", {})
	if not Economy.can_afford(state.get_empire(eid), cost):
		return "il faut %s" % GameData.format_amounts(cost)
	return ""


static func rosette(state: GameState, eid: int, sid: int, added: Array[Dictionary]) -> void:
	Economy.pay(state.get_empire(eid), (WorldForge.cfg("instant").get("rosette", {}) as Dictionary).get("cost", {}))
	WorldForge.sub(state, "rosettes")[str(sid)] = {"o": eid, "unpaid": 0}
	WorldForge._stat(state, eid, "rosettes", 1)
	WorldForge.touch(state)
	added.append(state.add_chronicle("Autour de %s, %d mondes se rangent en rosette et tournent ensemble, à égale distance, comme les rayons d'une roue. Les poètes sont ravis ; les ingénieurs, nerveux." % [
			state.galaxy.systems[sid].system_name, rosette_worlds(state, eid, sid).size()], WorldForge._who(state, eid, sid, true)))


static func rosette_of(state: GameState, pid: int) -> Dictionary:
	var p := state.galaxy.get_planet(pid)
	if p == null:
		return {}
	var v: Variant = WorldForge.sub(state, "rosettes").get(str(p.system_id), {})
	return v if v is Dictionary else {}


static func _dissolve_if_small(state: GameState, sid: int, added: Array[Dictionary]) -> void:
	var ro: Variant = WorldForge.sub(state, "rosettes").get(str(sid), null)
	if not (ro is Dictionary):
		return
	var o := int((ro as Dictionary)["o"])
	var n := rosette_worlds(state, o, sid).size()
	if n >= _r("rosette_min", 3) and state.system_owner(sid) == o:
		return
	WorldForge.sub(state, "rosettes").erase(str(sid))
	WorldForge.touch(state)
	added.append(state.add_chronicle("La rosette de %s se défait : les mondes reprennent chacun leur orbite." % state.galaxy.systems[sid].system_name,
			WorldForge._who(state, o, sid)))


static func _rosettes_month(state: GameState, added: Array[Dictionary]) -> void:
	var ros := WorldForge.sub(state, "rosettes")
	var keys := ros.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	for k in keys:
		var sid := int(k)
		_dissolve_if_small(state, sid, added)
		if not ros.has(k):
			continue
		var ro: Dictionary = ros[k]
		var e := state.get_empire(int(ro["o"]))
		if e == null or int(e.resources.get("energy", 0)) <= 0:
			ro["unpaid"] = int(ro.get("unpaid", 0)) + 1
		else:
			ro["unpaid"] = 0
		if int(ro["unpaid"]) >= _r("rosette_unpaid_months", 6):
			_collide(state, sid, int(ro["o"]), added)


## Six mois impayés : deux mondes de la rosette se percutent.
static func _collide(state: GameState, sid: int, o: int, added: Array[Dictionary]) -> void:
	var ws := rosette_worlds(state, o, sid)
	WorldForge.sub(state, "rosettes").erase(str(sid))
	if ws.size() < 2:
		return
	var i := WorldForge._h(state, ["collide", sid, state.tick]) % ws.size()
	var a := ws[i]
	var b := ws[(i + 1) % ws.size()]
	var na := WorldForge.world_name(state, a)
	var nb := WorldForge.world_name(state, b)
	_smash(state, a, added)
	_smash(state, b, added)
	added.append(state.add_chronicle("Catastrophe à %s : faute d'énergie, la rosette s'est déréglée et %s a percuté %s. Il n'en reste que des cailloux et des survivants hagards." % [
			state.galaxy.systems[sid].system_name, na, nb]))


## Un monde devient une ceinture de cailloux ; ses habitants fuient.
static func _smash(state: GameState, pid: int, added: Array[Dictionary]) -> void:
	var p := state.galaxy.get_planet(pid)
	var c: Colony = state.colonies.get(pid)
	if c != null:
		var n := c.population if c.is_colony() else 0
		var owner := c.owner
		state.colonies.erase(pid)
		state.rebuild_ownership()
		if n > 0 and not GameState.is_npc(owner):
			Movements.flee_from(state, p.system_id, Peoples.founder_of(state, owner), maxi(1, n / 2), owner, added)
	WorldForge.sub(state, "worlds").erase(str(pid))
	WorldForge.sub(state, "moving").erase(str(pid))
	WorldForge.reshape(state, pid, "asteroids", 1)
	state.override_planet(pid, {"deposits": []})
	WorldForge.sub(state, "debris")[str(pid)] = 1


# --- Bélier planétaire (prop. 26) --------------------------------------------------------------

static func check_ram(state: GameState, eid: int, pid: int, target: int) -> String:
	if not WorldForge.unlocked(state, eid, "belier"):
		return "technologie requise : %s" % Research.missing_text(state, eid, ["moteurs_planetaires"])
	var why := _engine_world(state, eid, pid)
	if why != "":
		return why
	var c: Colony = state.colonies.get(pid)
	if c != null and c.is_colony() and c.population > 0:
		return "seulement un monde vide"
	var t := state.galaxy.get_planet(target)
	var p := state.galaxy.get_planet(pid)
	if t == null or WorldForge.is_gone(state, target):
		return "cible inconnue"
	if not state.galaxy.systems[p.system_id].neighbors.has(t.system_id):
		return "la cible doit être dans un système voisin"
	var tc: Colony = state.colonies.get(target)
	if tc == null or tc.owner == eid or GameState.is_npc(tc.owner):
		return "la cible doit être une planète ennemie"
	if not Combat.at_war(state, eid, tc.owner):
		return "seulement en guerre"
	var te := state.get_empire(tc.owner)
	if te != null and (te.capital_planet == target or te.home_planet == target):
		return "jamais une capitale"
	return ""


static func ram_targets(state: GameState, eid: int, pid: int) -> Array[int]:
	var out: Array[int] = []
	var p := state.galaxy.get_planet(pid)
	if p == null:
		return out
	for n in state.galaxy.systems[p.system_id].neighbors:
		for tp in state.galaxy.systems[n].planet_ids:
			if check_ram(state, eid, pid, tp) == "":
				out.append(tp)
	return out


static func ram(state: GameState, eid: int, pid: int, target: int, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	var tc: Colony = state.colonies.get(target)
	var victim := tc.owner if tc != null else -1
	var na := WorldForge.world_name(state, pid)
	var nb := WorldForge.world_name(state, target)
	var tsid := state.galaxy.get_planet(target).system_id
	_smash(state, pid, added)
	_smash(state, target, added)
	WorldForge._stat(state, eid, "rams", 1)
	for x in state.empires:
		if x.id != eid and not x.is_npc() and not x.eliminated:
			Diplomacy.remember(state, x.id, eid, "world_rammed")
	Announce.next(state, "forge_unmade", {"actor": eid, "target": victim, "system": tsid})
	added.append(state.add_chronicle("Bélier planétaire : %s lance %s sur %s. Les deux mondes ne sont plus que des cailloux. La galaxie s'en souviendra longtemps, et pas en bien." % [
			e.short_name(), na, nb]))


# --- Commandes de mondes (prop. 13) ------------------------------------------------------------

## Empires qui fabriquent des planètes sur mesure et accepteraient une commande de eid.
static func sellers(state: GameState, eid: int) -> Array[int]:
	var out: Array[int] = []
	for x in state.empires:
		if x.id == eid or x.is_npc() or x.eliminated:
			continue
		if _seller_reason(state, eid, x.id) == "":
			out.append(x.id)
	return out


static func order_price(state: GameState, seller: int) -> Dictionary:
	return Research.scaled_amounts(WorldForge.r_dict("order_price"), WorldForge.t_int(state, seller, "order_pct"))


static func _seller_reason(state: GameState, eid: int, seller: int) -> String:
	var se := state.get_empire(seller)
	if se == null or se.is_npc() or se.eliminated or seller == eid:
		return "vendeur inconnu"
	if not WorldForge.unlocked(state, seller, "sur_mesure"):
		return "il ne sait pas fabriquer de planètes"
	if Combat.at_war(state, eid, seller):
		return "on ne commande pas une planète à un ennemi"
	if Diplomacy.opinion(state, seller, eid) < _r("order_min_opinion", -10):
		return "il vous en veut trop pour travailler pour vous"
	if WorldForge.busy(state, seller) >= WorldForge.slots(state, seller):
		return "ses chantiers sont tous occupés"
	return ""


static func check_order(state: GameState, eid: int, seller: int, sid: int, arg: String) -> String:
	var why := _seller_reason(state, eid, seller)
	if why != "":
		return why
	if sid < 0 or sid >= state.galaxy.systems.size():
		return "système inconnu"
	if not WorldForge._holds(state, eid, sid):
		return "il faut tenir le système"
	if not WorldForge.job_in_system(state, sid).is_empty():
		return "un chantier planétaire est déjà en cours dans ce système"
	if state.galaxy.systems[sid].planet_ids.size() >= 9:
		return "plus aucune orbite libre dans ce système"
	if not (WorldForge.op_def("sur_mesure").get("choices", []) as Array).has(arg):
		return "choisissez le type de monde"
	if WorldForge.custom_count(state, eid) >= _r("custom_limit", 3):
		return "limite atteinte : %d planètes sur mesure par empire" % _r("custom_limit", 3)
	var price := order_price(state, seller)
	if not Economy.can_afford(state.get_empire(eid), price):
		return "il faut %s" % GameData.format_amounts(price)
	if WorldForge.mass(state, eid) < WorldForge.op_mass("sur_mesure"):
		return "il faut fournir %d Masse planétaire" % WorldForge.op_mass("sur_mesure")
	return ""


static func order(state: GameState, eid: int, seller: int, sid: int, arg: String, added: Array[Dictionary]) -> void:
	var price := order_price(state, seller)
	Economy.pay(state.get_empire(eid), price)
	var se := state.get_empire(seller)
	for r in price:
		se.resources[r] = int(se.resources.get(r, 0)) + int(price[r])
	WorldForge.add_mass(state, eid, -WorldForge.op_mass("sur_mesure"))
	WorldForge.start(state, seller, "sur_mesure", sid, -1, arg, null, added, eid)


# --- Jour, mois, rendements --------------------------------------------------------------------

static func daily(state: GameState, added: Array[Dictionary]) -> void:
	if state.forge.is_empty():
		return
	_march_day(state, added)


static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	if state.forge.is_empty():
		return
	_rosettes_month(state, added)
	var ca := WorldForge.sub(state, "carcass")
	for k in ca.keys():
		if int((ca[k] as Dictionary).get("until", 0)) <= state.tick:
			ca.erase(k)
	_living_month(state, added)


## Monde vivant : il choisit son hôte. Haï trente jours par mois, il part au bout de living_leave_days.
static func _living_month(state: GameState, added: Array[Dictionary]) -> void:
	var rel := WorldForge.sub(state, "relics")
	var keys := rel.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	for k in keys:
		var pid := int(k)
		if not is_living(state, pid):
			continue
		var lv: Dictionary = (rel[k] as Dictionary)["living"]
		var c: Colony = state.colonies.get(pid)
		if c == null or not c.is_colony() or GameState.is_npc(c.owner):
			lv["hate"] = 0
			continue
		if loves(state, pid, c.owner):
			lv["hate"] = 0
			continue
		lv["hate"] = int(lv.get("hate", 0)) + 30
		if int(lv["hate"]) < _r("living_leave_days", 1800):
			continue
		var nm := relic_name(state, pid)
		var owner := c.owner
		var sid := state.galaxy.get_planet(pid).system_id
		(rel[k] as Dictionary)["dead"] = 1
		Movements.flee_from(state, sid, Peoples.founder_of(state, owner), c.population, owner, added)
		WorldForge.remove_body(state, pid)
		added.append(state.add_chronicle("%s en a assez de %s, briseurs de mondes : il s'arrache à son orbite et s'en va dans le noir. Ses habitants ont juste eu le temps de faire leurs valises." % [
				nm, state.get_empire(owner).short_name()]))


static func income(state: GameState, eid: int) -> Dictionary:
	var gross := {}
	var upkeep := {}
	var ros := WorldForge.sub(state, "rosettes")
	for k in ros:
		if int((ros[k] as Dictionary)["o"]) != eid:
			continue
		var n := rosette_worlds(state, eid, int(k)).size()
		gross["food"] = int(gross.get("food", 0)) + n * _r("rosette_food", 2)
		var up := WorldForge.r_dict("rosette_upkeep")
		for r in up:
			upkeep[r] = int(upkeep.get(r, 0)) + n * int(up[r])
	var ca := WorldForge.sub(state, "carcass")
	var y := WorldForge.r_dict("carcass_yields")
	for k in ca:
		if state.system_owner(int(k)) == eid:
			for r in y:
				gross[r] = int(gross.get(r, 0)) + int(y[r])
	return {"gross": gross, "upkeep": upkeep}


## Bonus de population : rosette (+1), monde vivant (+2 s'il vous aime, -2 sinon).
static func pop_bonus(state: GameState, pid: int, eid: int) -> int:
	var n := 0
	var ro := rosette_of(state, pid)
	if not ro.is_empty() and int(ro["o"]) == eid:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == eid:
			n += _r("rosette_hab_pop", 1)
	if is_living(state, pid):
		n += _r("living_pop", 2) if loves(state, pid, eid) else -_r("living_pop", 2)
	return n


## Prop. 37 (Murmurants) : l'intérieur de leurs mondes creux cache leurs flottes au renseignement.
static func hides_fleets(state: GameState, eid: int, sid: int) -> bool:
	if state.forge.is_empty() or not WorldForge.t_bool(state, eid, "hollow_hide"):
		return false
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == eid and state.galaxy.get_planet(pid).type == "creux":
			return true
	return false
