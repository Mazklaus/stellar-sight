class_name StabilitySystem
extends RefCounted
## Stabilité des systèmes (voir Stability), exécutée à chaque tick :
## - chaque jour : les systèmes assiégés ou en bataille notent l'attaque ;
## - chaque mois : la stabilité glisse vers sa cible, la révolte s'installe, les rebelles se lèvent,
##   et au bout d'un an de révolte le système fait sécession (Sans-Bannière). Les colonies d'un esprit
##   de ruche trop loin de la capitale redeviennent sauvages de la même façon.
## Aucun aléatoire, systèmes parcourus dans l'ordre de leur identifiant.


static func process(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	_mark_attacks(state)
	if state.tick % int(GameData.rules()["month_days"]) != 0:
		return added
	var month := int(GameData.rules()["month_days"])
	for e in state.empires:
		if e.eliminated:
			continue
		if Stability.applies(state, e.id):
			var cx := Stability.context(state, e.id)
			for sid in Stability.systems_of(state, e.id):
				_monthly_system(state, e, sid, month, cx, added)
			Stability.refresh_empire(state, e.id)
		elif bool(Stability.talent(state, e.id).get("wild", false)):
			_monthly_wild(state, e, month, added)
	_prune(state)
	return added


static func _mark_attacks(state: GameState) -> void:
	for k in state.sieges:
		_hit(state, int(k))
	for k in state.battles:
		_hit(state, int(k))


static func _hit(state: GameState, sid: int) -> void:
	var owner := state.system_owner(sid)
	if owner < 0 or GameState.is_npc(owner):
		return
	if not state.stability.has(sid):
		state.stability[sid] = {"v": int(Stability.data()["base"])}
	state.stability[sid]["hit"] = state.tick


static func _monthly_system(state: GameState, e: Empire, sid: int, month: int, cx: Dictionary, added: Array[Dictionary]) -> void:
	if not state.stability.has(sid):
		state.stability[sid] = {"v": int(Stability.data()["base"])}
	var en: Dictionary = state.stability[sid]
	var v := int(en.get("v", Stability.data()["base"]))
	var goal := Stability.target(state, sid, cx)
	var drift := int(Stability.data()["drift_per_month"])
	if v < goal:
		v = mini(goal, v + drift)
	elif v > goal:
		v = maxi(goal, v - drift)
	var was := Stability.tier_for(int(en.get("v", v)))
	en["v"] = v
	var now := Stability.tier_for(v)
	if String(en.get("decree", "")) != "" and int(en.get("decree_end", 0)) <= state.tick:
		en.erase("decree")
		en.erase("decree_end")
	var sname := state.galaxy.systems[sid].system_name
	if String(now["id"]) != String(was["id"]) and not e.is_ai():
		var up := int(now["min"]) > int(was["min"])
		added.append(state.add_chronicle("%s : %s passe %s « %s ». %s" % [e.short_name(), sname, "à" if up else "en", String(now["label"]),
				"Les tavernes chantent l'hymne, pour une fois." if up else "Les murs se couvrent d'affiches qu'on n'a pas commandées."], Espionage.private_to(state, [e.id], sid)))
	if String(now["id"]) != "revolte":
		en.erase("revolt")
		return
	var sec: Dictionary = Stability.data()["secession"]
	var before := int(en.get("revolt", 0))
	var days := before + month
	en["revolt"] = days
	for w in sec["warn_days"]:
		if before < int(w) and days >= int(w):
			@warning_ignore("integer_division")
			added.append(state.add_chronicle("Révolte à %s (%s) depuis %d mois : on y parle de sécession à voix haute. Encore %d mois et il sera trop tard." % [
					sname, e.short_name(), days / month, (int(sec["revolt_days"]) - days) / month], Espionage.private_to(state, [e.id], sid)))
	if days % int(sec["rebels_every"]) == 0:
		_spawn_rebels(state, sid, e, added)
	if days >= int(sec["revolt_days"]) and sid != int(cx["capital"]):
		secede(state, sid, e.id, added)


## Esprit de ruche : une colonie à plus de far_jumps sauts de tout monde-ruche redevient sauvage en un an.
static func _monthly_wild(state: GameState, e: Empire, month: int, added: Array[Dictionary]) -> void:
	var wd: Dictionary = Stability.data()["wild"]
	var cap := FactionTraits.capital_system(state, e.id)
	if cap < 0:
		return
	# Mondes-ruches : la capitale et les colonies d'au moins hive_pop population.
	var hives: Array[int] = [cap]
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == e.id and c.is_colony() and c.is_established() and c.population >= int(wd.get("hive_pop", 10)):
			var hs := state.galaxy.get_planet(pid).system_id
			if not hives.has(hs):
				hives.append(hs)
	var nests: Array = []
	for h in hives:
		nests.append(FactionTraits.jumps_from(state.galaxy, h))
	for sid in Stability.systems_of(state, e.id):
		if Stability.colony_systems_in(state, e.id, sid) == 0:
			continue
		var near := 99
		for d: Dictionary in nests:
			near = mini(near, int(d.get(sid, 99)))
		if near <= int(wd["far_jumps"]):
			if state.stability.has(sid):
				state.stability[sid].erase("wild")
			continue
		if not state.stability.has(sid):
			state.stability[sid] = {"v": int(Stability.data()["base"])}
		var en: Dictionary = state.stability[sid]
		var before := int(en.get("wild", 0))
		var days := before + month
		en["wild"] = days
		var sname := state.galaxy.systems[sid].system_name
		if before < int(wd["warn_days"]) and days >= int(wd["warn_days"]):
			added.append(state.add_chronicle("%s : la colonie de %s, trop loin du nid, n'obéit plus qu'à moitié. Elle a commencé à chanter seule." % [
					e.short_name(), sname], Espionage.private_to(state, [e.id], sid)))
		if days >= int(wd["days"]):
			secede(state, sid, e.id, added, true)


## Sécession : les revendications de l'empire dans le système passent aux Sans-Bannière.
static func secede(state: GameState, sid: int, empire_id: int, added: Array[Dictionary], wild := false) -> void:
	var e := state.get_empire(empire_id)
	var sname := state.galaxy.systems[sid].system_name
	# Sécession par affinité (peuples mêlés) : la majorité d'une autre espèce rejoint son empire voisin.
	var kin := -1 if wild else Movements.affinity_target(state, sid, empire_id)
	if kin >= 0:
		var ek := state.get_empire(kin)
		Stability._transfer(state, sid, empire_id, kin)
		state.stability.erase(sid)
		added.append(state.add_chronicle("Sécession ! %s rompt avec %s et rejoint %s, l'empire de son peuple. On change de drapeau, de langue officielle et, pour certains, de cousins." % [
				sname, e.display_name(), ek.display_name()], Espionage.public_to(state, [empire_id, kin])))
		Movements.on_secession(state, sid, empire_id, kin, added)
		return
	Stability._transfer(state, sid, empire_id, GameState.NPC_ID)
	state.stability.erase(sid)
	if not wild:
		Movements.on_secession(state, sid, empire_id, GameState.NPC_ID, added)
	if wild:
		added.append(state.add_chronicle("La colonie de %s rompt avec %s et redevient sauvage : un essaim sans maître, qui ne reconnaît plus personne." % [
				sname, e.display_name()], Espionage.public_to(state, [empire_id])))
	else:
		added.append(state.add_chronicle("Sécession ! %s rompt avec %s et rejoint les Sans-Bannière. On brûle les portraits officiels, on garde les cadres." % [
				sname, e.display_name()], Espionage.public_to(state, [empire_id])))
	_spawn_rebels(state, sid, e, added, true)


static func _spawn_rebels(state: GameState, sid: int, e: Empire, added: Array[Dictionary], quiet := false) -> void:
	var sec: Dictionary = Stability.data()["secession"]
	var ships: Array = sec["rebel_ships"].duplicate()
	var every := int(sec["rebel_extra_every_years"]) * 360
	if every > 0:
		@warning_ignore("integer_division")
		for _i in state.tick / every:
			ships.append(ships[0])
	var fl := state.spawn_ship(GameState.NPC_ID, String(ships[0]), sid)
	for i in range(1, ships.size()):
		fl.add_ship(String(ships[i]), -1, 1)
	fl.troops = Combat.max_troops(fl, state)
	fl.fleet_name = "Rebelles de %s" % state.galaxy.systems[sid].system_name
	if not quiet:
		added.append(state.add_chronicle("Des rebelles s'emparent de vaisseaux à %s (%s). Ils ont des revendications, et des canons pour les appuyer." % [
				state.galaxy.systems[sid].system_name, e.short_name()], Espionage.private_to(state, [e.id], sid)))


## Entrées de systèmes qui n'ont plus de propriétaire avec une stabilité.
static func _prune(state: GameState) -> void:
	var drop := []
	for k in state.stability:
		var owner := state.system_owner(int(k))
		if owner < 0 or GameState.is_npc(owner):
			drop.append(k)
	for k in drop:
		state.stability.erase(k)
