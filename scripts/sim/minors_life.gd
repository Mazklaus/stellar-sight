class_name MinorsLife
extends RefCounted
## Vie des peuples mineurs (lot 2 de l'étude « Peuples mineurs ») :
## - Conscience (prop. 8) : points de 0 à 100 en quatre niveaux (Ignorants, Rumeurs, Soupçons, Savent) ;
##   flottes visibles, combats, poste ouvert la font monter ; « Se révéler » les fait passer à Savent.
##   Plus ils savent, plus leurs âges passent vite et plus le choc d'une conquête est court.
## - Programmes des spatiaux (prop. 15) : Fonds de développement, Migration choisie, Escadre étrangère.
## - Accords avec les pré-spatiaux révélés (prop. 16) : Guidance, Transfert de technologie, Accord commercial.
## - Sujet (prop. 19) : le suzerain d'un spatial en fait son sujet ; il garde sa vie propre et paie un tribut.
## - Disperser (prop. 20) : la capitale d'un spatial conquise peut être rasée pour un butin.
## - Hostiles (prop. 22) : un spatial hostile harcèle les colonies proches tant qu'on n'a pas 20 de
##   faveur ; un peuple sans ami depuis longtemps voit naître un repaire pirate à côté de lui.
## - Drames (prop. 23) : guerre nucléaire, astéroïde, déclin sous le siège.
## - Avènement (prop. 24) : un pré-spatial qui achève l'Aube spatiale devient un spatial.
## - Sécessions (prop. 25) : un système en sécession devient un peuple mineur de son espèce.
## - Pré-conscients et élévation (prop. 26).


static func data() -> Dictionary:
	return Minors.data()


static func _h(state: GameState, parts: Array) -> int:
	return Minors._h(state, parts)


# --- Conscience (prop. 8) ---------------------------------------------------------------------------

static func aware_level(state: GameState, id: int) -> int:
	var m := Minors.get_m(state, id)
	var v := int(m.get("aware", 0))
	var th: Array = data()["awareness"]["thresholds"]
	var lvl := 0
	for i in th.size():
		if v >= int(th[i]):
			lvl = i
	return lvl


static func aware_label(state: GameState, id: int) -> String:
	return String((data()["awareness"]["levels"] as Array)[aware_level(state, id)])


static func revealed(state: GameState, id: int) -> bool:
	return aware_level(state, id) >= (data()["awareness"]["levels"] as Array).size() - 1


static func add_aware(state: GameState, id: int, v: int) -> void:
	var m := Minors.get_m(state, id)
	if m.is_empty() or not Minors.is_pre(state, id):
		return
	m["aware"] = clampi(int(m.get("aware", 0)) + v, 0, 100)


static func _awareness(state: GameState, id: int, m: Dictionary) -> void:
	if not Minors.is_pre(state, id):
		return
	var ad: Dictionary = data()["awareness"]
	var sid := int(m["sid"])
	var gain := 0
	var seen := {}
	for f in Fleets.fleets_at(state, sid):
		if not f.is_moving() and not GameState.is_npc(f.owner) and not seen.has(f.owner):
			seen[f.owner] = true
			gain += int(ad["fleet"])
	for eid in m["post"]:
		if String(m["post"][eid]) == "ouvert":
			gain += int(ad["open_post"])
	if state.battles.has(sid):
		gain += int(ad["combat"])
	if gain == 0 and int(m["aware"]) > int(ad["decay_above"]) and not bool(m.get("revealed", false)):
		gain = -int(ad["decay"])
	add_aware(state, id, gain)


# --- Âges : accords et vitesse ----------------------------------------------------------------------

## Multiplicateur de vitesse des âges : transfert de technologie (×3, ×2 encore avec le talent Raison).
static func age_mult(state: GameState, id: int) -> int:
	var m := Minors.get_m(state, id)
	var x := 1
	for eid in m.get("acc", {}):
		if (m["acc"][eid] as Dictionary).has("tech"):
			x = maxi(x, int(data()["accords"]["tech"]["speed"]) * MinorsBridges.tech_x(state, int(eid)))
	return x


## L'Aube spatiale achevée : l'Avènement (prop. 24). Sous transfert de technologie, il naît protégé.
static func rise(state: GameState, id: int, added: Array[Dictionary]) -> void:
	var m := Minors.get_m(state, id)
	if m.is_empty() or not Minors.is_pre(state, id):
		return
	m["fam"] = Minors.FAM_SPACE
	m["age"] = 5
	m["age_days"] = 0
	# Le donneur : celui qui a le plus longtemps transféré sa technologie (accord encore en cours compris).
	var donor := -1
	var best := 0
	var months: Dictionary = (m.get("acc_tech", {}) as Dictionary).duplicate()
	for eid in m.get("acc", {}):
		if (m["acc"][eid] as Dictionary).has("tech"):
			months[eid] = int(months.get(eid, 0)) + 1
	var keys := months.keys()
	keys.sort()
	for eid in keys:
		if int(months[eid]) > best:
			best = int(months[eid])
			donor = int(eid)
	m["post"] = {}
	m["acc"] = {}
	var c: Colony = state.colonies.get(int(m["planet"]))
	if c != null:
		c.population = maxi(c.population, int(data()["space"]["pop"]))
	Minors.spawn_fleet(state, id)
	state.garrisons[int(m["sid"])] = Combat.garrison_max(state, int(m["sid"]))
	added.append(state.add_chronicle("Avènement ! %s lance son premier vaisseau. Il revient, ce qui est déjà mieux que la plupart des premiers vaisseaux." % Minors.name_of(state, id)))
	if donor >= 0 and state.get_empire(donor) != null and not state.get_empire(donor).eliminated:
		(m["contact"] as Dictionary)[donor] = int((m["contact"] as Dictionary).get(donor, state.tick))
		(m["fav"] as Dictionary)[donor] = int(data()["favor"]["max"])
		m["lock"] = donor
		Minors.set_suzerain(state, id, donor, added)
		added.append(state.add_chronicle("%s naît protégé de %s, qui lui a tout appris." % [Minors.name_of(state, id), state.get_empire(donor).display_name()]))
	m.erase("acc_tech")


## Suzerain verrouillé : né protégé du donneur, ou sujet.
static func suz_locked(state: GameState, id: int, m: Dictionary) -> bool:
	for key in ["lock", "subject"]:
		var who := int(m.get(key, -1))
		if who >= 0:
			var e := state.get_empire(who)
			if e != null and not e.eliminated and not Minors.at_war_with(state, id, who):
				if int(m["suz"]) != who:
					Minors.set_suzerain(state, id, who, [])
				return true
			m.erase(key)
	return false


static func on_suz_lost(state: GameState, id: int, was: int, _added: Array[Dictionary]) -> void:
	var m := Minors.get_m(state, id)
	if int(m.get("subject", -1)) == was:
		m.erase("subject")


# --- Programmes et accords (prop. 15-16) ------------------------------------------------------------

static func _prog(m: Dictionary, eid: int) -> Dictionary:
	if not m.has("prog"):
		m["prog"] = {}
	if not (m["prog"] as Dictionary).has(eid):
		m["prog"][eid] = {}
	return m["prog"][eid]


static func _acc(m: Dictionary, eid: int) -> Dictionary:
	if not m.has("acc"):
		m["acc"] = {}
	if not (m["acc"] as Dictionary).has(eid):
		m["acc"][eid] = {}
	return m["acc"][eid]


static func fonds_on(state: GameState, id: int, eid: int) -> bool:
	var m := Minors.get_m(state, id)
	return state.tick < int(((m.get("prog", {}) as Dictionary).get(eid, {}) as Dictionary).get("fonds", -1))


## Le Fonds de développement double le cadeau du suzerain ou le bonus de l'ami.
static func gift_mult(state: GameState, id: int, eid: int) -> int:
	return 2 if fonds_on(state, id, eid) else 1


static func friend_mult(state: GameState, id: int, eid: int) -> int:
	return 2 if fonds_on(state, id, eid) and Minors.suzerain(state, id) != eid else 1


static func check_prog(state: GameState, eid: int, id: int, key: String) -> String:
	var pd: Dictionary = (data()["programs"] as Dictionary).get(key, {})
	if pd.is_empty() or key.begins_with("_"):
		return "programme inconnu"
	if Minors.is_pre(state, id):
		return "seulement avec une cité-État spatiale"
	if not Minors.tier_at_least(state, id, eid, "ami" if String(pd.get("min", "friend")) == "friend" else String(pd["min"])):
		return "il faut leur amitié"
	var p := _prog(Minors.get_m(state, id), eid)
	if state.tick < int(p.get(key, -1)):
		return "déjà en cours" if key == "fonds" else "pas avant %d mois" % ((int(p[key]) - state.tick) / 30 + 1)
	var e := state.get_empire(eid)
	for r in pd.get("cost", {}):
		if int(e.resources.get(r, 0)) < int(pd["cost"][r]):
			return "il faut %d %s" % [int(pd["cost"][r]), GameData.resource_label(String(r)).to_lower()]
	if key == "migration" and _nearest_colony(state, eid, Minors.system_of(state, id)) == null:
		return "aucune colonie pour les accueillir"
	return ""


static func prog(state: GameState, eid: int, id: int, key: String, added: Array[Dictionary]) -> void:
	var m := Minors.get_m(state, id)
	var pd: Dictionary = data()["programs"][key]
	var e := state.get_empire(eid)
	for r in pd.get("cost", {}):
		e.resources[r] = int(e.resources.get(r, 0)) - int(pd["cost"][r])
	var p := _prog(m, eid)
	match key:
		"fonds":
			p["fonds"] = state.tick + int(pd["days"])
			Relics.touch(state)
		"migration":
			p["migration"] = state.tick + int(pd["cd_days"])
			var span: Array = pd["n"]
			var n := int(span[0]) + _h(state, ["migration", id, eid, state.tick]) % (int(span[1]) - int(span[0]) + 1)
			var src: Colony = state.colonies.get(int(m["planet"]))
			var dst := _nearest_colony(state, eid, int(m["sid"]))
			if src != null and dst != null:
				n = mini(n, maxi(0, src.population - 3))
				src.population -= n
				dst.population += n
				if Peoples.enabled(state) and n > 0:
					var sp := Minors.species_id(state, id)
					dst.species[sp] = int(dst.species.get(sp, 0)) + n
					dst.integ[sp] = int(Peoples.data().get("integration", {}).get("founded", 75))
				added.append(state.add_chronicle("%d habitants %s s'installent à %s, chez %s. Ils ont apporté leurs recettes." % [n, Crisis.de_name(Minors.short_of(state, id)),
						state.galaxy.get_planet(dst.planet_id).display_name(state.galaxy), e.display_name()], Espionage.private_to(state, [eid])))
		"escadre":
			p["escadre"] = state.tick + int(pd["cd_days"])
			var cap := FactionTraits.capital_system(state, eid)
			if cap >= 0:
				var ships: Array = data()["space"]["ships"]
				var f := state.spawn_ship(eid, String(ships[0]), cap)
				@warning_ignore("integer_division")
				var target := Minors.fleet_power_target(state) * int(pd["power_pct"]) / 100
				var guard := 0
				while Combat.fleet_power(f) < target and guard < 20:
					guard += 1
					f.add_ship(String(ships[guard % ships.size()]), -1, -1)
				f.fleet_name = "Escadre %s" % Crisis.de_name(Minors.short_of(state, id))
				added.append(state.add_chronicle("%s offre une escadre à %s." % [Minors.name_of(state, id), e.display_name()], Espionage.private_to(state, [eid])))


static func _nearest_colony(state: GameState, eid: int, from: int) -> Colony:
	var jumps := FactionTraits.jumps_from(state.galaxy, from)
	var best: Colony = null
	var best_j := 999
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != eid or not c.is_colony() or not c.is_established():
			continue
		var j := int(jumps.get(state.galaxy.get_planet(pid).system_id, 999))
		if j < best_j:
			best_j = j
			best = c
	return best


static func check_accord(state: GameState, eid: int, id: int, key: String) -> String:
	var ad: Dictionary = (data()["accords"] as Dictionary).get(key, {})
	if ad.is_empty() or key.begins_with("_"):
		return "accord inconnu"
	if not Minors.is_pre(state, id):
		return "seulement avec un pré-spatial"
	var acc: Dictionary = ((Minors.get_m(state, id).get("acc", {}) as Dictionary).get(eid, {}))
	if acc.has(key):
		return ""  # on peut toujours y mettre fin
	if not revealed(state, id) and not MinorsBridges.infiltrated(state, id, eid):
		return "ils doivent d'abord savoir que vous existez (se révéler)"
	if not Minors.can_talk(state, id, eid) or Minors.at_war_with(state, id, eid):
		return "vous ne pouvez pas leur parler"
	if key == "tech" and MinorsBridges.accord_banned(state, key):
		return "interdit par la loi de l'Amphictyonie"
	if int(state.get_empire(eid).resources.get("influence", 0)) < int(ad["influence"]):
		return "il faut %d influence par mois" % int(ad["influence"])
	return ""


## Signe l'accord, ou y met fin s'il existe.
static func accord(state: GameState, eid: int, id: int, key: String, added: Array[Dictionary]) -> void:
	var m := Minors.get_m(state, id)
	var acc := _acc(m, eid)
	if acc.has(key):
		acc.erase(key)
		return
	acc[key] = state.tick
	added.append(state.add_chronicle("%s signe avec %s : %s." % [state.get_empire(eid).display_name(), Minors.name_of(state, id),
			String(data()["accords"][key]["label"]).to_lower()], Espionage.private_to(state, [eid])))


static func has_accord(state: GameState, id: int, eid: int, key: String) -> bool:
	return (((Minors.get_m(state, id).get("acc", {}) as Dictionary).get(eid, {})) as Dictionary).has(key)


static func _accords(state: GameState, id: int, m: Dictionary, added: Array[Dictionary]) -> void:
	if not m.has("acc"):
		return
	var ad: Dictionary = data()["accords"]
	for eid in (m["acc"] as Dictionary).keys():
		var acc: Dictionary = m["acc"][eid]
		var e := state.get_empire(int(eid))
		if e == null or e.eliminated or Minors.at_war_with(state, id, int(eid)):
			(m["acc"] as Dictionary).erase(eid)
			continue
		for key in acc.keys():
			if not ad.has(key):
				continue  # le comptoir (lot 3) se paie à part
			var cost := int(ad[key]["influence"])
			if int(e.resources.get("influence", 0)) < cost:
				acc.erase(key)
				added.append(state.add_chronicle("%s ne paie plus l'accord avec %s (%s)." % [e.display_name(), Minors.name_of(state, id), String(ad[key]["label"]).to_lower()],
						Espionage.private_to(state, [int(eid)])))
				continue
			e.resources["influence"] = int(e.resources.get("influence", 0)) - cost
			match String(key):
				"guide":
					if state.tick - int(acc[key]) >= int(ad["guide"]["years"]) * 360:
						if not m.has("credo"):
							m["credo"] = String(e.faction().get("species", {}).get("credo", ""))
							added.append(state.add_chronicle("%s a adopté le credo de %s. Leurs prêtres jurent que c'était leur idée." % [Minors.name_of(state, id), e.display_name()],
									Espionage.private_to(state, [int(eid)])))
						Minors.add_fav(state, id, int(eid), int(ad["guide"]["fav"]))
				"tech":
					if not m.has("acc_tech"):
						m["acc_tech"] = {}
					m["acc_tech"][int(eid)] = int(m["acc_tech"].get(int(eid), 0)) + 1
				"trade":
					var v := int(ad["trade"]["energy_per_age"]) * (1 + int(m["age"])) * MinorsBridges.trade_x(state, int(eid))
					e.resources["energy"] = int(e.resources.get("energy", 0)) + v


# --- Sujet (prop. 19) -------------------------------------------------------------------------------

static func check_subject(state: GameState, eid: int, id: int) -> String:
	var m := Minors.get_m(state, id)
	if Minors.is_pre(state, id):
		return "seulement une cité-État spatiale"
	if int(m.get("subject", -1)) == eid:
		return ""  # rompre le lien
	if Minors.suzerain(state, id) != eid:
		return "réservé au suzerain"
	if Minors.fav(state, id, eid) < 80:
		return "il faut 80 de faveur"
	return ""


static func subject(state: GameState, eid: int, id: int, added: Array[Dictionary]) -> void:
	var m := Minors.get_m(state, id)
	if int(m.get("subject", -1)) == eid:
		m.erase("subject")
		added.append(state.add_chronicle("%s rend sa pleine liberté à %s." % [state.get_empire(eid).display_name(), Minors.name_of(state, id)], Espionage.private_to(state, [eid])))
		return
	m["subject"] = eid
	added.append(state.add_chronicle("%s devient le sujet de %s. Il garde ses lois, ses fêtes et son drapeau ; il change de suzerain pour toujours." % [
			Minors.name_of(state, id), state.get_empire(eid).display_name()]))


static func subjects_of(state: GameState, eid: int) -> Array[int]:
	var out: Array[int] = []
	for id in Minors.ids(state):
		if int(Minors.get_m(state, id).get("subject", -1)) == eid:
			out.append(id)
	return out


# --- Hostiles (prop. 22) ----------------------------------------------------------------------------

## Un spatial hostile est en guerre avec les empires sous le palier de contact.
static func hostile_to(state: GameState, id: int, eid: int) -> bool:
	var m := Minors.get_m(state, id)
	if String(m.get("att", "")) != "hostile" or String(m.get("fam", "")) != Minors.FAM_SPACE:
		return false
	var e := state.get_empire(eid)
	if e == null or e.eliminated:
		return false
	return Minors.fav(state, id, eid) < int(data()["favor"]["contact"]) and int(m.get("suz", -1)) != eid


static func _raids(state: GameState, id: int, m: Dictionary, added: Array[Dictionary]) -> void:
	var hd: Dictionary = data()["hostile"]
	var raid: Dictionary = m.get("raid", {})
	if not raid.is_empty():
		if state.tick >= int(raid["until"]):
			m.erase("raid")
			_go_home(state, id)
		return
	if String(m["att"]) != "hostile" or Minors.is_pre(state, id) or not (m["levy"] as Dictionary).is_empty():
		return
	var fl := Minors.fleets_of(state, id)
	if fl.is_empty() or _h(state, ["raid", id, state.tick]) % maxi(1, int(hd["raid_chance"])) != 0:
		return
	var target := int(m.get("incite", -1))
	m.erase("incite")
	var sid := _raid_target(state, id, int(hd["raid_jumps"]), target)
	if sid < 0:
		return
	for f in fl:
		var route := Fleets.plan_route(state, f, sid)
		if not route.is_empty():
			f.system_id = int(route["system"])
			f.path.assign(route["path"])
			f.progress = int(route["progress"])
	m["raid"] = {"until": state.tick + int(hd["raid_days"]), "sid": sid}
	var victim := state.system_owner(sid)
	added.append(state.add_chronicle("%s lance un raid sur %s." % [Minors.name_of(state, id), state.galaxy.systems[sid].system_name],
			Espionage.private_to(state, [victim], sid)))


## Colonie la plus proche d'un empire hostile (ou de l'empire visé par une incitation, lot 3).
static func _raid_target(state: GameState, id: int, reach: int, only := -1) -> int:
	var jumps := FactionTraits.jumps_from(state.galaxy, Minors.system_of(state, id))
	var best := -1
	var best_j := reach + 1
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if GameState.is_npc(c.owner) or (only >= 0 and c.owner != only):
			continue
		if only < 0 and not hostile_to(state, id, c.owner):
			continue
		var sid := state.galaxy.get_planet(pid).system_id
		var j := int(jumps.get(sid, 999))
		if j < best_j:
			best_j = j
			best = sid
	return best


static func _go_home(state: GameState, id: int) -> void:
	var sid := Minors.system_of(state, id)
	for f in Minors.fleets_of(state, id):
		if f.system_id == sid and not f.is_moving():
			continue
		var route := Fleets.plan_route(state, f, sid)
		if not route.is_empty():
			f.system_id = int(route["system"])
			f.path.assign(route["path"])
			f.progress = int(route["progress"])


## Sans ami depuis longtemps, un repaire pirate peut naître à côté.
static func _lonely(state: GameState, id: int, m: Dictionary, added: Array[Dictionary]) -> void:
	var friend := false
	for eid in m["fav"]:
		if int(m["fav"][eid]) >= int(data()["favor"]["friend"]):
			friend = true
			break
	if friend:
		m["lonely"] = state.tick
		return
	if not m.has("lonely"):
		m["lonely"] = state.tick
	@warning_ignore("integer_division")
	if (state.tick / 30 + id) % 12 != 0 or state.tick - int(m["lonely"]) < int(data()["hostile"]["lair_years"]) * 360:
		return
	if _h(state, ["repaire", id, state.tick]) % 100 >= 25:
		return
	var ns: Array = state.galaxy.systems[int(m["sid"])].neighbors.duplicate()
	ns.sort()
	for n in ns:
		var sid := int(n)
		if state.system_owner(sid) < 0 and not state.lairs.has(sid) and Minors._free(state, sid):
			Pirates.create_lair(state, sid)
			m["lonely"] = state.tick
			added.append(state.add_chronicle("Personne ne s'occupe %s : un repaire pirate s'installe à côté, à %s." % [Crisis.de_name(Minors.name_of(state, id)),
					state.galaxy.systems[sid].system_name]))
			return


# --- Drames (prop. 23) ------------------------------------------------------------------------------

static func _dramas(state: GameState, id: int, m: Dictionary, added: Array[Dictionary]) -> bool:
	var dd: Dictionary = data()["drama"]
	@warning_ignore("integer_division")
	var month_n := (state.tick / 30 + id)
	if Minors.is_pre(state, id) and int(m["age"]) >= 4 and month_n % (int(dd["nuke_years"]) * 12) == 0 and state.tick > 0:
		if _h(state, ["atome", id, state.tick]) % 100 < int(dd["nuke_pct"]):
			if _h(state, ["extinction", id, state.tick]) % 100 < int(dd["extinct_pct"]) * 10:
				_extinct(state, id, added)
				return true
			m["age"] = 0
			m["age_days"] = 0
			var c: Colony = state.colonies.get(int(m["planet"]))
			if c != null:
				c.population = maxi(1, int(Minors.age_def(0)["pop"]))
			state.garrisons[int(m["sid"])] = Combat.garrison_max(state, int(m["sid"]))
			added.append(state.add_chronicle("Guerre nucléaire chez %s. Les survivants redécouvrent le feu, avec une méfiance compréhensible." % Minors.name_of(state, id)))
	# Astéroïde.
	var ast: Dictionary = m.get("asteroid", {})
	if not ast.is_empty():
		if state.tick >= int(ast["until"]):
			m.erase("asteroid")
			if not bool(ast.get("saved", false)):
				m["age"] = maxi(0, int(m["age"]) - 2)
				m["age_days"] = 0
				var c2: Colony = state.colonies.get(int(m["planet"]))
				if c2 != null:
					c2.population = maxi(1, c2.population / 2)
				state.garrisons[int(m["sid"])] = Combat.garrison_max(state, int(m["sid"]))
				added.append(state.add_chronicle("Un astéroïde frappe le monde %s. Leurs mythes parleront longtemps du ciel qui tombe." % Crisis.de_name(Minors.name_of(state, id))))
	elif Minors.is_pre(state, id) and month_n % 12 == 0 and _h(state, ["asteroide", id, state.tick]) % 100 < int(dd["asteroid_per_year"]):
		m["asteroid"] = {"until": state.tick + 45, "saved": false}
		for eid in Minors._contact_ids(m):
			if Minors.has_post(state, id, eid):
				Events.push(state, eid, "min_asteroid", {"min": id, "system": int(m["sid"])}, added)
	return false


static func _extinct(state: GameState, id: int, added: Array[Dictionary]) -> void:
	var m := Minors.get_m(state, id)
	var sid := int(m["sid"])
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == id:
			state.colonies.erase(pid)
	state.rebuild_ownership()
	state.garrisons.erase(sid)
	added.append(state.add_chronicle("%s s'est éteint dans le feu atomique. Leur monde n'est plus qu'un tombeau radioactif que les archéologues visiteront un jour." % Minors.name_of(state, id)))
	Minors._remove(state, id)
	for o in state.empires:
		o.path_cache.clear()


## Un spatial assiégé decline_days jours entre en déclin : tout empire peut l'intégrer à moitié prix.
static func declining(state: GameState, id: int) -> bool:
	return bool(Minors.get_m(state, id).get("decline", false))


static func decline_pct(state: GameState, id: int, _eid: int) -> int:
	return int(data()["drama"]["decline_pct"]) if declining(state, id) else 100


# --- Chaque jour, chaque mois -----------------------------------------------------------------------

static func daily(state: GameState, id: int, m: Dictionary, added: Array[Dictionary]) -> void:
	if Minors.is_pre(state, id) or bool(m.get("decline", false)):
		return
	var sid := int(m["sid"])
	if state.sieges.has(sid) or state.sieges.has(str(sid)):
		m["siege_days"] = int(m.get("siege_days", 0)) + 1
		if int(m["siege_days"]) >= int(data()["drama"]["decline_days"]):
			m["decline"] = true
			added.append(state.add_chronicle("%s, assiégé, entre en déclin : il se donnera au premier qui le recueille." % Minors.name_of(state, id)))
	else:
		m["siege_days"] = 0


static func month(state: GameState, id: int, m: Dictionary, added: Array[Dictionary]) -> void:
	_awareness(state, id, m)
	_accords(state, id, m, added)
	_raids(state, id, m, added)
	_lonely(state, id, m, added)
	if int(m.get("subject", -1)) >= 0:
		var lord := state.get_empire(int(m["subject"]))
		if lord != null:
			lord.resources["energy"] = int(lord.resources.get("energy", 0)) + 3  # tribut du sujet
	_dramas(state, id, m, added)


static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	_elevations(state, added)


# --- Sécessions (prop. 25) --------------------------------------------------------------------------

## Le système en sécession devient un peuple mineur spatial de son espèce, neutre et courtisable.
## false si ce n'est pas possible (pas de mineurs dans la partie, plus d'identifiant libre).
static func secession(state: GameState, sid: int, from: int, added: Array[Dictionary]) -> bool:
	if not Minors.enabled(state) or Minors._new_id(state) < 0:
		return false
	var main := -1
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == from and c.is_colony() and (main < 0 or c.population > state.colonies[main].population):
			main = pid
	if main < 0:
		return false
	var e := state.get_empire(from)
	var sd: Dictionary = data()["secession"]
	var sname := state.galaxy.systems[sid].system_name
	var sp := e.faction_id
	var counts := Peoples.counts(state, state.colonies[main])
	var best_n := -1
	for fid in counts:
		if int(counts[fid]) > best_n:
			best_n = int(counts[fid])
			sp = String(fid)
	var extra := {"fam": Minors.FAM_SPACE, "att": "neutre", "name": String(sd["name"]) % sname, "short": String(sd["short"]) % sname, "species": sp,
			"orientation": "economique", "gift": {"label": "Loyauté retrouvée", "text": "Stabilité +3 dans tout l'empire.", "fx": {"stability": 3}}}
	var others: Array = []
	for pid in state.galaxy.systems[sid].planet_ids:
		var c2: Colony = state.colonies.get(pid)
		if c2 != null and c2.owner == from and pid != main:
			others.append(pid)
	var id := Minors.create(state, "libres", sid, main, extra)
	if id < 0:
		return false
	var m := Minors.get_m(state, id)
	m["att"] = "neutre"
	for pid in others:
		var c3: Colony = state.colonies[pid]
		Peoples.on_owner_change(state, c3, from, id)
		c3.owner = id
	state.rebuild_ownership()
	(m["contact"] as Dictionary)[from] = state.tick
	(m["fav"] as Dictionary)[from] = 0
	(m["grudge"] as Dictionary)[from] = state.tick + int(data()["favor"]["grudge_days"])
	for o in state.empires:
		o.path_cache.clear()
	added.append(state.add_chronicle("Sécession ! %s rompt avec %s et devient un peuple libre : %s. Il accepte les visites, pas les ordres." % [sname, e.display_name(), Minors.name_of(state, id)],
			Espionage.public_to(state, [from])))
	return true


# --- Pré-conscients et élévation (prop. 26) ---------------------------------------------------------

static func setup_pres(state: GameState) -> void:
	var pd: Dictionary = data()["presapients"]
	@warning_ignore("integer_division")
	var want := maxi(1, state.galaxy.systems.size() / maxi(1, int(pd["per_systems"])))
	var kinds: Array = (pd["kinds"] as Dictionary).keys()
	kinds.sort()
	var starts: Array = []
	for e in state.empires:
		var cap := FactionTraits.capital_system(state, e.id)
		if cap >= 0:
			starts.append(FactionTraits.jumps_from(state.galaxy, cap))
	var cands: Array = []
	for s in state.galaxy.systems:
		if not Minors._free(state, s.id) or Minors._near_start(starts, s.id) < 2:
			continue
		for pid in s.planet_ids:
			var p := state.galaxy.get_planet(pid)
			if state.colonies.has(pid) or (GameData.planet_type(p.type).get("pop_yields", {}) as Dictionary).is_empty():
				continue
			cands.append([_h(state, ["preconscient", pid]), pid])
	cands.sort()
	var pres := {}
	var used := {}
	for cand in cands:
		if pres.size() >= want:
			break
		var pid := int(cand[1])
		var sid := state.galaxy.get_planet(pid).system_id
		if used.has(sid):
			continue
		used[sid] = true
		pres[pid] = String(kinds[pres.size() % kinds.size()])
	state.minors["pres"] = pres
	state.minors["elev"] = {}


static func pres_kind(state: GameState, pid: int) -> String:
	if state.minors.is_empty():
		return ""
	return String((state.minors.get("pres", {}) as Dictionary).get(pid, ""))


static func pres_def(kind: String) -> Dictionary:
	return (data()["presapients"]["kinds"] as Dictionary).get(kind, {})


## Mondes de l'empire qui abritent des pré-conscients.
static func pres_of(state: GameState, eid: int) -> Array[int]:
	var out: Array[int] = []
	if state.minors.is_empty():
		return out
	for pid in state.minors.get("pres", {}):
		var c: Colony = state.colonies.get(int(pid))
		if c != null and c.owner == eid and c.is_colony():
			out.append(int(pid))
	out.sort()
	return out


static func check_elevate(state: GameState, eid: int, pid: int) -> String:
	var pd: Dictionary = data()["presapients"]
	if pres_kind(state, pid) == "":
		return "pas d'espèce pré-consciente ici"
	var c: Colony = state.colonies.get(pid)
	if c == null or c.owner != eid or not c.is_colony() or not c.is_established():
		return "il faut une colonie établie sur ce monde"
	if (state.minors.get("elev", {}) as Dictionary).has(pid):
		return "élévation déjà en cours"
	var e := state.get_empire(eid)
	if not e.techs.has(String(pd["tech"])):
		return "il faut %s" % String(Research.tech(String(pd["tech"])).get("label", pd["tech"]))
	for r in pd["cost"]:
		if int(e.resources.get(r, 0)) < int(pd["cost"][r]):
			return "il faut %d %s" % [int(pd["cost"][r]), GameData.resource_label(String(r)).to_lower()]
	return ""


static func elevate(state: GameState, eid: int, pid: int, added: Array[Dictionary]) -> void:
	var pd: Dictionary = data()["presapients"]
	var e := state.get_empire(eid)
	for r in pd["cost"]:
		e.resources[r] = int(e.resources.get(r, 0)) - int(pd["cost"][r])
	if not state.minors.has("elev"):
		state.minors["elev"] = {}
	state.minors["elev"][pid] = {"e": eid, "until": state.tick + int(pd["days"])}
	added.append(state.add_chronicle("%s commence l'élévation des %s. On leur apprend à compter au-delà de sept." % [e.display_name(),
			String(pres_def(pres_kind(state, pid)).get("short", "pré-conscients"))], Espionage.private_to(state, [eid])))


static func _elevations(state: GameState, added: Array[Dictionary]) -> void:
	var ev: Dictionary = state.minors.get("elev", {})
	if ev.is_empty():
		return
	var pd: Dictionary = data()["presapients"]
	var keys := ev.keys()
	keys.sort()
	for k in keys:
		var el: Dictionary = ev[k]
		var pid := int(k)
		var c: Colony = state.colonies.get(pid)
		if c == null or c.owner != int(el["e"]):
			ev.erase(k)
			continue
		if state.tick < int(el["until"]):
			continue
		ev.erase(k)
		var kind := pres_kind(state, pid)
		(state.minors["pres"] as Dictionary).erase(pid)
		var n := int(pd["pop"])
		c.population += n
		if Peoples.enabled(state):
			c.species[kind] = int(c.species.get(kind, 0)) + n
			c.integ[kind] = 100
		var sid := state.galaxy.get_planet(pid).system_id
		Events.apply_fx(state, c.owner, {"id": -1, "card": "", "system": sid, "planet": pid, "rival": -1, "hero": -1},
				[{"k": "stab", "v": 10, "days": int(pd["stab_days"]), "scope": "system"}], added)
		added.append(state.add_chronicle("Élévation achevée : les %s rejoignent %s comme citoyens. Leur gratitude est bruyante et touchante." % [
				String(pres_def(kind).get("name", kind)), state.get_empire(c.owner).display_name()], Espionage.private_to(state, [c.owner])))


# --- Effets -----------------------------------------------------------------------------------------

static func effects(_state: GameState, _eid: int) -> Dictionary:
	return {}


# --- Commandes (Minors.check_act / act) -------------------------------------------------------------

## "?" : l'acte n'est pas de ce lot.
static func check_act(state: GameState, eid: int, act: String, x: int, s: String, _n: int) -> String:
	match act:
		"reveal":
			if not Minors.is_pre(state, x):
				return "seulement avec un pré-spatial"
			if not Minors.has_post(state, x, eid):
				return "il faut un poste d'observation"
			if revealed(state, x):
				return "ils savent déjà"
			if MinorsBridges.post_banned(state, "ouvert"):
				return "interdit par la loi de l'Amphictyonie"
			return ""
		"prog":
			return check_prog(state, eid, x, s)
		"accord":
			return check_accord(state, eid, x, s)
		"subject":
			return check_subject(state, eid, x)
	return "?"


static func act(state: GameState, eid: int, act_id: String, x: int, s: String, _n: int, added: Array[Dictionary]) -> bool:
	match act_id:
		"reveal":
			var m := Minors.get_m(state, x)
			m["aware"] = 100
			m["revealed"] = true
			added.append(state.add_chronicle("%s se révèle %s. Les prophètes locaux sont ravis ; les sceptiques, beaucoup moins." % [state.get_empire(eid).display_name(),
					Crisis.obj_name(Minors.name_of(state, x)).trim_prefix("")], Espionage.private_to(state, [eid])))
		"prog":
			prog(state, eid, x, s, added)
		"accord":
			accord(state, eid, x, s, added)
		"subject":
			subject(state, eid, x, added)
		_:
			return false
	return true


## Élévation : acte hors d'un peuple (x = -1, n = planète), passe par Minors.check_act avant le peuple.
static func check_global(state: GameState, eid: int, act: String, n: int) -> String:
	if act == "elevate":
		return check_elevate(state, eid, n)
	return "?"


# --- Cartes : astéroïde, dispersion -----------------------------------------------------------------

static func card_fx(state: GameState, eid: int, item: Dictionary, fx: Dictionary, added: Array[Dictionary]) -> void:
	var id := int(item.get("min", -1))
	var m := Minors.get_m(state, id)
	var e := state.get_empire(eid)
	match String(fx.get("act", "")):
		"asteroid_save":
			var cost := int(data()["drama"]["asteroid_save_energy"])
			var ast: Dictionary = m.get("asteroid", {})
			if ast.is_empty() or int(e.resources.get("energy", 0)) < cost:
				return
			e.resources["energy"] = int(e.resources.get("energy", 0)) - cost
			ast["saved"] = true
			add_aware(state, id, 20)
			Minors.add_fav(state, id, eid, 5)
			MinorsBridges.on_protect(state, id, eid, added)
			added.append(state.add_chronicle("%s pulvérise l'astéroïde qui menaçait %s. Là-bas, on parle de signes dans le ciel." % [e.display_name(), Minors.name_of(state, id)],
					Espionage.private_to(state, [eid])))


static func fx_line(state: GameState, item: Dictionary, fx: Dictionary) -> String:
	match String(fx.get("act", "")):
		"asteroid_save":
			return "énergie -%d, le peuple est sauvé (et la conscience monte)" % int(data()["drama"]["asteroid_save_energy"])
		"asteroid_let":
			return "ils reculeront peut-être de deux âges"
		"disperse":
			return "butin selon leur orientation ; le peuple disparaît, son trait aussi"
	return ""


static func ai_value(_state: GameState, _eid: int, _item: Dictionary, _fx: Dictionary, _temper: int) -> int:
	return 0


# --- IA ---------------------------------------------------------------------------------------------

static func ai_think(ctx: Dictionary, met: Array[int], temper: int) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	# Élévation des pré-conscients.
	for pid in pres_of(state, e.id):
		if AiPlayer._issue(ctx, SimCommands.min_act(e.id, "elevate", -1, "", pid)):
			AiPlayer._intent(ctx, "Élève une espèce pré-consciente")
			return
	for id in met:
		if Minors.suzerain(state, id) != e.id:
			continue
		if not Minors.is_pre(state, id):
			if int(e.resources.get("energy", 0)) > 600 and AiPlayer._issue(ctx, SimCommands.min_act(e.id, "prog", id, "fonds")):
				AiPlayer._intent(ctx, "Finance %s" % Minors.name_of(state, id))
			if temper >= 0 and AiPlayer._issue(ctx, SimCommands.min_act(e.id, "prog", id, "escadre")):
				AiPlayer._intent(ctx, "Reçoit une escadre %s" % Crisis.de_name(Minors.short_of(state, id)))
		elif revealed(state, id) and not has_accord(state, id, e.id, "trade"):
			AiPlayer._issue(ctx, SimCommands.min_act(e.id, "accord", id, "trade"))


# --- Interface --------------------------------------------------------------------------------------

static func ui_lines(state: GameState, player: int, id: int) -> Array:
	var out: Array = []
	var m := Minors.get_m(state, id)
	if Minors.is_pre(state, id):
		out.append("Conscience : %s (%d / 100). Plus ils savent, plus leurs âges passent vite." % [aware_label(state, id), int(m.get("aware", 0))])
		if not (m.get("asteroid", {}) as Dictionary).is_empty():
			out.append("Un astéroïde fonce vers leur monde.")
	elif String(m.get("att", "")) == "hostile":
		out.append("Hostiles : ils attaquent quiconque n'a pas 20 de faveur." if hostile_to(state, id, player) else "Hostiles, mais pas envers vous.")
	if int(m.get("subject", -1)) >= 0 and state.get_empire(int(m["subject"])) != null:
		out.append("Sujet de %s." % state.get_empire(int(m["subject"])).display_name())
	if declining(state, id):
		out.append("En déclin : n'importe qui peut l'intégrer à moitié prix.")
	if fonds_on(state, id, player):
		out.append("Fonds de développement en cours : cadeau et bonus doublés.")
	return out


static func ui_buttons(state: GameState, player: int, id: int, emit: Callable) -> Array:
	var out: Array = []
	if Minors.is_pre(state, id):
		if not revealed(state, id):
			out.append(VassalUi._btn("Se révéler", check_act(state, player, "reveal", id, "", -1), "Ils sauront que vous existez : la conscience passe à « Savent » et les accords s'ouvrent.",
					func() -> void: emit.call(SimCommands.min_act(player, "reveal", id))))
		for k in data()["accords"]:
			if String(k).begins_with("_"):
				continue
			var key := String(k)
			var ad: Dictionary = data()["accords"][key]
			var on := has_accord(state, id, player, key)
			out.append(VassalUi._btn("%s%s (%d influence/mois)" % ["✓ " if on else "", String(ad["label"]), int(ad["influence"])], check_act(state, player, "accord", id, key, -1),
					String(ad["text"]) + (" Cliquer y met fin." if on else ""), func() -> void: emit.call(SimCommands.min_act(player, "accord", id, key))))
	else:
		for k in data()["programs"]:
			if String(k).begins_with("_"):
				continue
			var key2 := String(k)
			var pd: Dictionary = data()["programs"][key2]
			out.append(VassalUi._btn(String(pd["label"]), check_act(state, player, "prog", id, key2, -1), String(pd["text"]),
					func() -> void: emit.call(SimCommands.min_act(player, "prog", id, key2))))
		if Minors.suzerain(state, id) == player:
			var is_sub := int(Minors.get_m(state, id).get("subject", -1)) == player
			out.append(VassalUi._btn("Rendre sa liberté" if is_sub else "En faire un sujet", check_act(state, player, "subject", id, "", -1),
					"Un sujet garde sa vie propre et son cadeau, vous reste lié pour toujours et paie un petit tribut.",
					func() -> void: emit.call(SimCommands.min_act(player, "subject", id))))
	return out


## Pré-conscients sur les mondes du joueur : une ligne et un bouton d'élévation chacun.
static func ui_pres(state: GameState, player: int, emit: Callable) -> Control:
	var pids := pres_of(state, player)
	if pids.is_empty():
		return null
	var box := VBoxContainer.new()
	box.add_child(HSeparator.new())
	box.add_child(UiTheme.section("Espèces pré-conscientes"))
	for pid in pids:
		var kind := pres_kind(state, pid)
		var pd := pres_def(kind)
		var row := HBoxContainer.new()
		var el: Dictionary = (state.minors.get("elev", {}) as Dictionary).get(pid, {})
		var txt := "%s sur %s : %s" % [String(pd.get("name", kind)), state.galaxy.get_planet(pid).display_name(state.galaxy), String(pd.get("lore", ""))]
		if not el.is_empty():
			txt += " Élévation : encore %d mois." % (maxi(0, int(el["until"]) - state.tick) / 30)
		row.add_child(AncientsUi._dim(txt, 13))
		if el.is_empty():
			var p := pid
			row.add_child(VassalUi._btn("Élever (300 savoir, 5 ans)", check_elevate(state, player, pid), "Ils deviennent une espèce de votre mosaïque, reconnaissante (stabilité +10).",
					func() -> void: emit.call(SimCommands.min_act(player, "elevate", -1, "", p))))
		box.add_child(row)
	return box


## Raser la capitale conquise d'un spatial (prop. 20) : butin selon l'orientation, le peuple disparaît.
static func disperse(state: GameState, eid: int, sid: int, added: Array[Dictionary]) -> void:
	var fm: Dictionary = (state.minors.get("former", {}) as Dictionary).get(sid, {})
	if fm.is_empty() or int(fm.get("conq", -1)) != eid or state.system_owner(sid) != eid:
		return
	var e := state.get_empire(eid)
	var loot: Dictionary = Minors.orientation_def(String(fm.get("orient", "economique"))).get("loot", {})
	for r in loot:
		e.resources[r] = int(e.resources.get(r, 0)) + int(loot[r])
	var c: Colony = null
	for pid in state.galaxy.systems[sid].planet_ids:
		var x: Colony = state.colonies.get(pid)
		if x != null and x.owner == eid and x.is_colony():
			c = x
			break
	if c != null:
		var keep := 1
		var sp := "mineur_" + String(fm["kind"])
		c.population = keep
		c.species.erase(sp)
		c.integ.erase(sp)
	var kind := String(fm["kind"])
	for key in ["absorbed", "active"]:
		var arr: Array = (state.minors[key] as Dictionary).get(eid, [])
		arr.erase(kind)
	(state.minors["former"] as Dictionary).erase(sid)
	Relics.touch(state)
	added.append(state.add_chronicle("%s rase la capitale %s et disperse son peuple. Le butin est considérable ; la galaxie, elle, détourne les yeux." % [
			e.display_name(), Crisis.de_name(String(fm.get("name", kind)))]))
