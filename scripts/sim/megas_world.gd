class_name MegasWorld
extends RefCounted
## Les mégastructures et la galaxie (lot 2 ; voir Megastructures, data/megastructures.json).
##
## Ruines d'anciennes mégastructures posées à la création (prop. 28, réglage « ruines ») et leur
## restauration (prop. 29) ; la Forteresse dormante, trouvaille jamais bâtie (prop. 30) ; sièges qui
## ruinent l'étape la plus haute (prop. 32) ; usure des Essaims (prop. 10) ; événements de chantier
## (prop. 13) ; Catapulte quantique (prop. 25) ; superarmes, Brise-monde et Anneau d'extinction (prop. 27).


static func _cfg_kind(k: String, key: String) -> Dictionary:
	var v: Variant = Megastructures.kind_def(k).get(key, {})
	return v if v is Dictionary else {}


# --- Ruines (prop. 28, 30) -----------------------------------------------------------------------

## Types qui peuvent laisser une ruine dans ce système (étoile ou planète libre), avec leur poids.
static func _ruin_fits(state: GameState, k: String, sid: int) -> int:
	var d := Megastructures.kind_def(k)
	if not (bool(d.get("ruin", false)) or bool(d.get("ruin_only", false))) or not Megastructures.kind_allowed(state, k):
		return -2
	var site: Dictionary = d.get("site", {})
	var s := state.galaxy.systems[sid]
	var b := String(site.get("body", "star"))
	if b == "star":
		var allowed: Array = site.get("stars", [])
		if not allowed.is_empty() and not allowed.has(s.star_type):
			return -2
		if (site.get("not_stars", []) as Array).has(s.star_type) or String(site.get("on_kind", "")) != "":
			return -2
		return -1
	if b == "planet":
		var types: Array = site.get("planet_types", [])
		for pid in s.planet_ids:
			if (types.is_empty() or types.has(state.galaxy.get_planet(pid).type)) and not state.colonies.has(pid):
				return pid
	return -2


static func place_ruins(state: GameState) -> void:
	var per := 0
	for r: Dictionary in Megastructures.ruin_defs():
		if String(r["id"]) == String(state.megas.get("ruins_opt", "")):
			per = int(r.get("per_systems", 0))
	if per <= 0 or state.galaxy == null:
		return
	@warning_ignore("integer_division")
	var want := maxi(1, state.galaxy.systems.size() / per)
	# Loin des capitales (3 sauts au moins), dans un système sans maître.
	var near := {}
	for e in state.empires:
		var c := FactionTraits.capital_system(state, e.id)
		if c < 0:
			continue
		var j := FactionTraits.jumps_from(state.galaxy, c)
		for sid in j:
			if int(j[sid]) < 3:
				near[int(sid)] = true
	var cands: Array[int] = []
	for s in state.galaxy.systems:
		if not near.has(s.id) and state.system_owner(s.id) < 0:
			cands.append(s.id)
	var kinds := Megastructures.kind_ids()
	kinds.sort()
	var i := 0
	var placed := 0
	while placed < want and not cands.is_empty() and i < 400:
		var ci := Megastructures._h(state, ["ruin_sys", i]) % cands.size()
		var sid := cands[ci]
		cands.remove_at(ci)
		# Tirage pondéré : la Forteresse dormante est rare (poids 1 contre 3).
		var pool: Array = []
		for k in kinds:
			var where := _ruin_fits(state, k, sid)
			if where == -2:
				continue
			var w := 1 if bool(Megastructures.kind_def(k).get("ruin_only", false)) else 3
			for _n in w:
				pool.append([k, where])
		i += 1
		if pool.is_empty():
			continue
		var pick: Array = pool[Megastructures._h(state, ["ruin_kind", sid]) % pool.size()]
		var k := String(pick[0])
		var n := Megastructures.stage_count(k)
		var st := n - 1 if bool(Megastructures.kind_def(k).get("ruin_only", false)) else 1 + Megastructures._h(state, ["ruin_st", sid]) % maxi(1, n - 1)
		var id := int(state.megas.get("next", 1))
		state.megas["next"] = id + 1
		Megastructures.entries(state)[str(id)] = {"id": id, "k": k, "o": -1, "s": sid, "p": int(pick[1]), "st": st, "w": 0, "ruin": 1}
		Megastructures.changed(state)
		placed += 1


static func ruins(state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in Megastructures.all_sorted(state):
		if Megastructures.is_ruin(m):
			out.append(m)
	return out


# --- Restauration (prop. 29) ---------------------------------------------------------------------

## Relever une ruine coûte restore_pct % des étapes qu'elle garde (talent des Brisecomètes).
static func restore_cost(state: GameState, eid: int, m: Dictionary) -> Dictionary:
	var k := String(m["k"])
	var total := {}
	for n in int(m["st"]):
		var c: Dictionary = Megastructures.stage_def(k, n).get("cost", {})
		for r in c:
			total[r] = int(total.get(r, 0)) + int(c[r])
	var pct := Megastructures.r_int("restore_pct", 40)
	@warning_ignore("integer_division")
	pct = pct * (100 + Megastructures.t_int(state, eid, "restore_pct") + ArchaeoBridges.plans_pct(state, eid, int(m.get("s", -1)))) / 100
	@warning_ignore("integer_division")
	pct = pct * (100 + KardashevWorld.repair_pct(state, eid)) / 100  # Âge sombre
	return Research.scaled_amounts(total, pct - 100)


@warning_ignore("integer_division")
static func restore_days(state: GameState, eid: int) -> int:
	return maxi(30, Megastructures.r_int("restore_days", 360) * (100 + Megastructures.t_int(state, eid, "restore_days_pct")) / 100)


static func check_restore(state: GameState, eid: int, id: int) -> String:
	var m := Megastructures.get_m(state, id)
	if m.is_empty() or not Megastructures.is_ruin(m):
		return "ce n'est pas une ruine"
	if bool(m.get("rs", 0)):
		return "déjà en restauration"
	var k := String(m["k"])
	if not Megastructures.kind_allowed(state, k):
		return "pas en jeu dans cette partie"
	if bool(Megastructures.kind_def(k).get("ruin_only", false)) and not Megastructures.unlocked(state, eid, k):
		return "technologie requise : %s" % Research.missing_text(state, eid, Megastructures.kind_def(k).get("tech", []))
	var sid := int(m["s"])
	if not Megastructures._holds(state, eid, sid):
		return "il faut tenir le système (une colonie ou un avant-poste établi, sans occupant)"
	if Megastructures._free_architect(state, eid, sid) == null:
		return "il faut un Vaisseau-architecte libre sur place"
	if Megastructures.busy(state, eid) >= Megastructures.slots(state, eid):
		return "trop d'étapes en chantier (%d à la fois)" % Megastructures.slots(state, eid)
	var lim: Dictionary = Megastructures.kind_def(k).get("limit", {})
	if lim.has("empire") and Megastructures.count_kind(state, eid, k) >= int(lim["empire"]):
		return "limite atteinte : %d par empire" % int(lim["empire"])
	var cost := restore_cost(state, eid, m)
	if not Economy.can_afford(state.get_empire(eid), cost):
		return "il faut %s" % GameData.format_amounts(cost)
	return ""


static func restore(state: GameState, eid: int, id: int, added: Array[Dictionary]) -> void:
	var m := Megastructures.get_m(state, id)
	var e := state.get_empire(eid)
	Economy.pay(e, restore_cost(state, eid, m))
	m["o"] = eid
	m["rs"] = 1
	m["w"] = restore_days(state, eid)
	added.append(state.add_chronicle("%s entreprend de relever %s. Les archéologues réclament un an ; les ingénieurs, « un peu plus »." % [
			e.short_name(), Megastructures.name_of(state, m)], Megastructures._who(state, eid, int(m["s"]))))


static func restored(state: GameState, m: Dictionary, added: Array[Dictionary]) -> void:
	m.erase("ruin")
	m["found"] = 1  # une trouvaille relevée ne compte pas dans le plafond (Megastructures.cap)
	m.erase("rs")
	m.erase("dmg")
	m.erase("sg")
	var eid := int(m["o"])
	Megastructures._stat(state, eid, "restored", 1)
	Megastructures.touch(state)
	var e := state.get_empire(eid)
	added.append(state.add_chronicle("%s a relevé %s. Ses bâtisseurs d'origine, s'ils regardent, sont sûrement un peu vexés." % [
			e.short_name() if e != null else "?", Megastructures.name_of(state, m)], Megastructures._who(state, eid, int(m["s"]))))


# --- Catapulte quantique (prop. 25) ----------------------------------------------------------------

static func check_launch(state: GameState, eid: int, id: int, fid: int, t: int) -> String:
	var m := Megastructures.get_m(state, id)
	if m.is_empty() or int(m["o"]) != eid or String(m["k"]) != "catapulte_quantique":
		return "ce n'est pas votre Catapulte quantique"
	var rng := int(Megastructures.special(m, "range", 0))
	if rng <= 0:
		return "la catapulte n'a pas encore de lentilles"
	if not Megastructures.kind_allowed(state, String(m["k"])):
		return "pas en jeu dans cette partie"
	if int(m.get("cd", 0)) > state.tick:
		return "en recharge (%d jours)" % (int(m["cd"]) - state.tick)
	var f: Fleet = state.fleets.get(fid)
	if f == null or f.owner != eid:
		return "choisissez une de vos flottes"
	if f.system_id != int(m["s"]) or f.is_moving():
		return "la flotte doit attendre à l'arrêt dans le système de la catapulte"
	if t < 0 or t >= state.galaxy.systems.size() or t == int(m["s"]):
		return "choisissez une destination"
	if not Fleets.is_explored(state, eid, t):
		return "destination inexplorée"
	var j := FactionTraits.jumps_from(state.galaxy, int(m["s"]))
	if int(j.get(t, 999)) > rng:
		return "trop loin (%d sauts au plus)" % rng
	var cost: Dictionary = Megastructures.kind_def("catapulte_quantique").get("launch_cost", {})
	if not Economy.can_afford(state.get_empire(eid), cost):
		return "il faut %s" % GameData.format_amounts(cost)
	return ""


static func launch(state: GameState, eid: int, id: int, fid: int, t: int, added: Array[Dictionary]) -> void:
	var m := Megastructures.get_m(state, id)
	var f: Fleet = state.fleets[fid]
	Economy.pay(state.get_empire(eid), Megastructures.kind_def("catapulte_quantique").get("launch_cost", {}))
	var dest := t
	var miss := _h_pct(state, ["cata", id, fid, state.tick]) < int(Megastructures.special(m, "miss", 0))
	if miss:
		var nbs: Array = state.galaxy.systems[t].neighbors.duplicate()
		nbs.sort()
		if not nbs.is_empty():
			dest = int(nbs[Megastructures._h(state, ["cata_to", id, fid, state.tick]) % nbs.size()])
	_teleport(state, f, dest)
	m["cd"] = state.tick + int(Megastructures.special(m, "cooldown", 120))
	Megastructures._stat(state, eid, "launches", 1)
	var nm := state.galaxy.systems[dest].system_name
	if miss:
		added.append(state.add_chronicle("La Catapulte quantique de %s projette %s… un peu à côté : la flotte reprend ses esprits à %s." % [
				state.get_empire(eid).short_name(), f.fleet_name, nm], [eid]))
	else:
		added.append(state.add_chronicle("La Catapulte quantique de %s projette %s jusqu'à %s. L'équipage aimerait qu'on le prévienne, la prochaine fois." % [
				state.get_empire(eid).short_name(), f.fleet_name, nm], Espionage.private_to(state, [eid], dest)))


static func _h_pct(state: GameState, parts: Array) -> int:
	return Megastructures._h(state, parts) % 100


static func _teleport(state: GameState, f: Fleet, dest: int) -> void:
	f.system_id = dest
	f.path.clear()
	f.progress = 0
	f.standing_order = ""
	f.patrol.clear()
	Ground.sync_fleet(state, f)
	for o in state.empires:
		o.path_cache.clear()


# --- Superarmes (prop. 27) -------------------------------------------------------------------------

## Le Brise-monde : détruire une planète à portée (pas une capitale ; pas un ami en paix).
static func check_fire(state: GameState, eid: int, id: int, pid: int) -> String:
	var m := Megastructures.get_m(state, id)
	if m.is_empty() or int(m["o"]) != eid or String(m["k"]) != "brise_monde":
		return "ce n'est pas votre Brise-monde"
	if not Megastructures.kind_allowed(state, "brise_monde"):
		return "les superarmes ne sont pas en jeu"
	if not bool(Megastructures.special(m, "fire", false)):
		return "le Brise-monde n'est pas armé"
	if int(m.get("cd", 0)) > state.tick:
		return "en recharge (%d jours)" % (int(m["cd"]) - state.tick)
	var fd := _cfg_kind("brise_monde", "fire")
	if pid < 0 or state.galaxy.get_planet(pid) == null:
		return "choisissez une planète"
	var p := state.galaxy.get_planet(pid)
	if p.type == "asteroids" or p.type == "anneau":
		return "il n'y a plus rien à briser là"
	if int(m["p"]) == pid:
		return "le Brise-monde ne se vise pas lui-même"
	var j := FactionTraits.jumps_from(state.galaxy, int(m["s"]))
	if int(j.get(p.system_id, 999)) > int(fd.get("range", 8)):
		return "hors de portée (%d sauts au plus)" % int(fd.get("range", 8))
	var c: Colony = state.colonies.get(pid)
	if c != null:
		var o := state.get_empire(c.owner)
		if o != null and o.capital_planet == pid:
			return "une capitale résiste : son bouclier planétaire absorbe le tir"
		if c.owner == eid:
			return "c'est une de vos colonies"
		if not GameState.is_npc(c.owner) and not Combat.at_war(state, eid, c.owner):
			return "vous n'êtes pas en guerre avec ce monde"
	var cost: Dictionary = fd.get("cost", {})
	if not Economy.can_afford(state.get_empire(eid), cost):
		return "il faut %s" % GameData.format_amounts(cost)
	return ""


static func fire(state: GameState, eid: int, id: int, pid: int, added: Array[Dictionary]) -> void:
	var m := Megastructures.get_m(state, id)
	var fd := _cfg_kind("brise_monde", "fire")
	var e := state.get_empire(eid)
	Economy.pay(e, fd.get("cost", {}))
	var p := state.galaxy.get_planet(pid)
	var nm := p.display_name(state.galaxy)
	var c: Colony = state.colonies.get(pid)
	var victim := c.owner if c != null else -1
	WorldForge.on_world_broken(state, eid, pid, added)  # monde creux, débris, Masse (Forge des mondes)
	if c != null and state.colonies.has(pid):
		state.colonies.erase(pid)
		state.rebuild_ownership()
	# Ce qui était bâti sur la planète disparaît avec elle.
	for o in Megastructures.in_system(state, p.system_id):
		if int(o["p"]) == pid:
			Megastructures.entries(state).erase(str(int(o["id"])))
			Megastructures.changed(state)
	state.override_planet(pid, {"type": "asteroids"})
	for x in state.empires:
		x.hab_cache.clear()
	m["cd"] = state.tick + int(fd.get("cooldown", 1800))
	Megastructures._stat(state, eid, "fired", 1)
	Megastructures.touch(state)
	for x in state.empires:
		if x.id != eid and not x.is_npc() and not x.eliminated:
			Diplomacy.remember(state, x.id, eid, "world_breaker")
	var who := (" (%s y vivait)" % state.get_empire(victim).short_name()) if victim >= 0 and state.get_empire(victim) != null else ""
	added.append(state.add_chronicle("Le Brise-monde de %s a tiré : %s n'est plus qu'une ceinture de cailloux%s. Toute la galaxie a vu l'éclair, et personne ne l'oubliera." % [
			e.short_name(), nm, who]))


## L'Anneau d'extinction : seulement pendant une crise ; ses flottes à portée sont anéanties (un seul
## vaisseau à bout de souffle survit par flotte, pour que la crise tienne ses comptes), mais la moitié des
## habitants des colonies de la zone meurt aussi.
static func check_purge(state: GameState, eid: int, id: int) -> String:
	var m := Megastructures.get_m(state, id)
	if m.is_empty() or int(m["o"]) != eid or String(m["k"]) != "anneau_extinction":
		return "ce n'est pas votre Anneau d'extinction"
	if not Megastructures.kind_allowed(state, "anneau_extinction"):
		return "les superarmes ne sont pas en jeu"
	if not bool(Megastructures.special(m, "purge", false)):
		return "l'anneau n'est pas armé"
	if not Crisis.active(state):
		return "seulement pendant une crise"
	if int(m.get("cd", 0)) > state.tick:
		return "en recharge (%d jours)" % (int(m["cd"]) - state.tick)
	var cost: Dictionary = _cfg_kind("anneau_extinction", "purge").get("cost", {})
	if not Economy.can_afford(state.get_empire(eid), cost):
		return "il faut %s" % GameData.format_amounts(cost)
	return ""


@warning_ignore("integer_division")
static func purge(state: GameState, eid: int, id: int, added: Array[Dictionary]) -> void:
	var m := Megastructures.get_m(state, id)
	var pd := _cfg_kind("anneau_extinction", "purge")
	var e := state.get_empire(eid)
	Economy.pay(e, pd.get("cost", {}))
	var j := FactionTraits.jumps_from(state.galaxy, int(m["s"]))
	var radius := int(pd.get("radius", 6))
	var hit := 0
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if not Crisis.is_crisis_fleet(f) or int(j.get(f.system_id, 999)) > radius or f.ships.is_empty():
			continue
		hit += f.ships.size()
		var keep := f.ships[0]
		var keep_gen := f.gen[0] if not f.gen.is_empty() else -1
		f.ships.clear()
		f.hp.clear()
		f.gen.clear()
		f.add_ship(keep, 1, keep_gen)
	var dead := 0
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if not c.is_colony() or int(j.get(state.galaxy.get_planet(pid).system_id, 999)) > radius:
			continue
		var lost := c.population * int(pd.get("pop_pct", 50)) / 100
		c.population = maxi(1, c.population - lost)
		dead += lost
	m["cd"] = state.tick + int(pd.get("cooldown", 3600))
	Megastructures._stat(state, eid, "purged", 1)
	added.append(state.add_chronicle("L'Anneau d'extinction de %s s'allume. %d vaisseaux de la crise se taisent à jamais… et %d populations des mondes voisins avec eux. Personne n'applaudit." % [
			e.short_name(), hit, dead]))


# --- Chaque jour : point faible du Brise-monde ------------------------------------------------------

static func _hostile_here(state: GameState, eid: int, sid: int) -> bool:
	var foe := false
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.system_id != sid or f.is_moving() or not Combat.is_armed(f):
			continue
		if f.owner == eid:
			return false  # nos vaisseaux défendent la structure
		if f.owner != GameState.FAUNA_ID and Combat.at_war(state, f.owner, eid):
			foe = true
	return foe


static func daily(state: GameState, added: Array[Dictionary]) -> void:
	var weak := int(_cfg_kind("brise_monde", "fire").get("weak_days", Megastructures.r_int("contested_days", 30)))
	for m in Megastructures.all_sorted(state):
		if String(m["k"]) != "brise_monde" or Megastructures.is_ruin(m) or int(m["st"]) < 1:
			continue
		if _hostile_here(state, int(m["o"]), int(m["s"])):
			m["wk"] = int(m.get("wk", 0)) + 1
		elif int(m.get("wk", 0)) > 0:
			m["wk"] = 0
		if int(m.get("wk", 0)) >= weak:
			ArchaeoWorld.queue_history(state, int(m["s"]), "m", "epave")  # ses débris deviendront un site
			Megastructures.entries(state).erase(str(int(m["id"])))
			Megastructures.changed(state)
			Megastructures.touch(state)
			added.append(state.add_chronicle("Des saboteurs ennemis trouvent le point faible du Brise-monde de %s : il saute, et emporte avec lui une bonne partie de la croûte de %s." % [
					state.get_empire(int(m["o"])).short_name(), Megastructures.site_name(state, m)]))


# --- Chaque mois : sièges, usure des Essaims, événements de chantier ---------------------------------

static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	for m in Megastructures.all_sorted(state):
		if Megastructures.is_ruin(m) or int(m["o"]) < 0:
			continue
		_siege(state, m, added)
		if String(m["k"]) == "essaim_dyson":
			_wear(state, m, added)
		if Megastructures.full(state) and Megastructures.running(m) and not bool(m.get("rp", 0)):
			_event(state, m, added)


## Siège (prop. 32) : une flotte ennemie qui tient le système siege_months mois ruine l'étape la plus haute.
static func _siege(state: GameState, m: Dictionary, added: Array[Dictionary]) -> void:
	if int(m["st"]) < 1 or bool(m.get("dmg", 0)):
		m.erase("sg")
		return
	var eid := int(m["o"])
	if not _hostile_here(state, eid, int(m["s"])):
		m.erase("sg")
		return
	m["sg"] = int(m.get("sg", 0)) + 1
	if int(m["sg"]) < Megastructures.r_int("siege_months", 3):
		return
	m.erase("sg")
	m["dmg"] = 1
	m["w"] = 0
	m.erase("rp")
	Megastructures.touch(state)
	added.append(state.add_chronicle("Le siège a raison de %s : l'étape « %s » est ruinée. Il faudra la réparer." % [
			Megastructures.name_of(state, m), String(Megastructures.stage_def(String(m["k"]), int(m["st"]) - 1).get("label", ""))],
			Espionage.private_to(state, [eid], int(m["s"]))))


## Usure des voiles d'un Essaim (prop. 10) : entretien en matériaux (nourriture pour les Khthari), sinon
## le rendement baisse par paliers ; payé, il remonte.
static func _wear(state: GameState, m: Dictionary, added: Array[Dictionary]) -> void:
	var n := Megastructures.eff_stage(m)
	if n < 1:
		return
	var wd := _cfg_kind("essaim_dyson", "wear")
	var eid := int(m["o"])
	var res := "food" if bool(Megastructures.talent(state, eid).get("wear_food", false)) else "materials"
	var cost := {res: int(wd.get("materials_per_stage", 2)) * n}
	var e := state.get_empire(eid)
	var before := int(m.get("wear", 0))
	if e != null and Economy.can_afford(e, cost):
		Economy.pay(e, cost)
		m["wear"] = maxi(0, before - int(wd.get("step", 10)))
	else:
		m["wear"] = mini(int(wd.get("max", 50)), before + int(wd.get("step", 10)))
		if int(m["wear"]) > before and before == 0 and e != null:
			added.append(state.add_chronicle("%s : faute d'entretien, les voiles de %s s'usent ; le rendement baisse." % [e.short_name(), Megastructures.name_of(state, m)], [eid]))
	if int(m.get("wear", 0)) == 0:
		m.erase("wear")


## Événement de chantier (prop. 13), event_pct % de chances par mois et par étape en cours.
static func _event(state: GameState, m: Dictionary, added: Array[Dictionary]) -> void:
	@warning_ignore("integer_division")
	var month := state.tick / int(GameData.rules()["month_days"])
	if _h_pct(state, ["ev", int(m["id"]), month]) >= Megastructures.r_int("event_pct", 8):
		return
	var evs: Array = Megastructures.data().get("events", [])
	if evs.is_empty():
		return
	var ev: Dictionary = evs[Megastructures._h(state, ["evk", int(m["id"]), month]) % evs.size()]
	var eid := int(m["o"])
	var e := state.get_empire(eid)
	if e == null:
		return
	var n := 0
	match String(ev.get("id", "")):
		"accident":
			n = int(ev.get("days", 30))
			m["w"] = int(m["w"]) + n
		"heros":
			n = mini(int(ev.get("days", 20)), int(m["w"]) - 1)
			if n <= 0:
				return
			m["w"] = int(m["w"]) - n
		"decouverte":
			n = int(ev.get("knowledge", 40))
			e.resources["knowledge"] = int(e.resources.get("knowledge", 0)) + n
		"greve":
			n = int(ev.get("energy", 30))
			if Economy.can_afford(e, {"energy": n}):
				Economy.pay(e, {"energy": n})
			else:
				m["w"] = int(m["w"]) + 30
		_:
			return
	added.append(state.add_chronicle(String(ev.get("text", "%s %s %d")) % [e.short_name(), Megastructures.name_of(state, m), n], [eid]))
