class_name InsVergemonde
extends RefCounted
## Hallier de Vergemonde, le 9e peuple, végétal (props 100 à 105 ; voir Insolites, data/insolites.json
## "vergemonde"). Des gardiens paisibles qui transforment lentement les mondes en jardins.
##   - Trois âges : les Pousses (immobiles, Savoir), les Marcheurs (travail, soldats, colons), les
##     Enracinés (influence et stabilité, ne bougent plus). La répartition glisse chaque mois de drift
##     points vers la Saison choisie (Pousses, Marcheurs ou Enracinés), changeable tous les season_cd_days.
##   - Terraformation lente : une colonie devient un monde-jardin au bout de garden_days ; ensuite, tous
##     les spread_days, une autre planète du système (libre ou à eux) le devient aussi.
##   - Planter un Cœur : sur un de leurs mondes-jardins, éveiller un monde vivant (pilier Mondes vivants),
##     bienveillant d'emblée ; l'humeur des mondes vivants monte deux fois plus vite pour eux (talent).
##   - Gardiens paisibles : forts en défense, faibles en attaque (brique) ; le Feu-qui-renouvelle (un
##     incendie emporte des habitants, puis la forêt repousse plus dense un an plus tard).
##   - Victoire : le Grand Jardin (gardens mondes-jardins et living mondes vivants Liés, tenus 5 ans). La
##     Biosphère unique de Myrr leur est ouverte aussi (végétal de survie).
##
## État (Insolites.emp) : "ages": {"p", "m", "e"}, "season", "season_t", "since": {pid: jour d'arrivée},
## "spread": {sid: jour de la dernière extension}, "fire": {pid: jour de la repousse}, "hearts".


const SEASONS := {"pousses": {"p": 60, "m": 25, "e": 15}, "marcheurs": {"p": 20, "m": 60, "e": 20}, "enracines": {"p": 20, "m": 25, "e": 55}}
const SEASON_LABEL := {"pousses": "Saison des Pousses", "marcheurs": "Saison des Marcheurs", "enracines": "Saison des Enracinés"}


static func _c(key: String, def := 0) -> int:
	return Insolites.c_int("vergemonde", key, def)


static func found(_state: GameState, _e: Empire, _sid: int, ed: Dictionary) -> void:
	ed["ages"] = {"p": 40, "m": 40, "e": 20}
	ed["season"] = "marcheurs"
	ed["season_t"] = 0
	ed["since"] = {}
	ed["spread"] = {}
	ed["fire"] = {}
	ed["hearts"] = 0


static func is_verge(state: GameState, eid: int) -> bool:
	return not state.insolites.is_empty() and Insolites.kind(state, eid) == "vergemonde"


# --- Trois âges (prop. 101) --------------------------------------------------------------------------

static func ages(state: GameState, eid: int) -> Dictionary:
	return Insolites.emp(state, eid).get("ages", {"p": 34, "m": 33, "e": 33})


static func check_season(state: GameState, eid: int, s: String) -> String:
	if not is_verge(state, eid):
		return "seul le Hallier change de saison"
	if not SEASONS.has(s):
		return "saison inconnue"
	var ed := Insolites.emp(state, eid)
	if String(ed.get("season", "")) == s:
		return "c'est déjà la saison en cours"
	if int(ed.get("season_t", 0)) > state.tick:
		return "la saison ne tourne pas si vite (%d jours)" % (int(ed["season_t"]) - state.tick)
	return ""


static func set_season(state: GameState, eid: int, s: String, added: Array[Dictionary]) -> void:
	var ed := Insolites.emp(state, eid)
	ed["season"] = s
	ed["season_t"] = state.tick + Insolites.tuned(state, eid, "vergemonde", "season_cd_days", _c("season_cd_days", 360))
	added.append(state.add_chronicle("Le Hallier de Vergemonde entre dans la %s. Personne ne l'a décidé ; tout le monde l'a senti." % String(SEASON_LABEL[s]).to_lower(),
			Espionage.private_to(state, [eid])))


static func _drift(ed: Dictionary) -> void:
	var aim: Dictionary = SEASONS.get(String(ed.get("season", "marcheurs")), SEASONS["marcheurs"])
	var a: Dictionary = ed["ages"]
	var step := Insolites.c_int("vergemonde", "drift", 2)
	for k in ["p", "m", "e"]:
		var v := int(a[k])
		var t := int(aim[k])
		a[k] = v + clampi(t - v, -step, step)
	var tot := int(a["p"]) + int(a["m"]) + int(a["e"])
	a["e"] = int(a["e"]) + 100 - tot  # le reste aux Enracinés : la somme reste à 100


## Production en points de % selon les âges : Pousses le Savoir, Marcheurs matériaux et énergie,
## Enracinés l'influence (autour d'un tiers chacun, rien de plus ni de moins).
static func production_bonus(state: GameState, eid: int, resource: String) -> int:
	var a := ages(state, eid)
	@warning_ignore("integer_division")
	match resource:
		"knowledge":
			return (int(a["p"]) - 33) / 2
		"materials", "energy":
			return (int(a["m"]) - 33) / 2
		"influence":
			return (int(a["e"]) - 33) / 2
	return 0


static func stability_parts(state: GameState, owner: int, out: Array) -> void:
	if not is_verge(state, owner):
		return
	@warning_ignore("integer_division")
	var s := (int(ages(state, owner)["e"]) - 20) / 5
	if s != 0:
		out.append(["Enracinés", s])


# --- Terraformation lente (prop. 102) ----------------------------------------------------------------

static func gardenable(state: GameState, pid: int) -> bool:
	var t := state.galaxy.get_planet(pid).type
	return (Insolites.cfg("vergemonde").get("garden_from", []) as Array).has(t)


static func _garden(state: GameState, eid: int, pid: int, added: Array[Dictionary], first: bool) -> void:
	var p := state.galaxy.get_planet(pid)
	var before := p.type_label()
	state.override_planet(pid, {"type": "gaia"})
	Ecology.on_terraform(state, pid)
	for e in state.empires:
		e.hab_cache.clear()
	added.append(state.add_chronicle(("%s n'est plus un monde %s : le Hallier en a fait un jardin. Les arbres ont pris trois générations ; ils en prendront trente de plus." if first
			else "La forêt du Hallier a traversé le vide jusqu'à %s, qui n'est plus un monde %s : il fleurit.") % [p.display_name(state.galaxy), before.to_lower()],
			Espionage.public_to(state, [eid])))


static func _grow(state: GameState, eid: int, ed: Dictionary, added: Array[Dictionary]) -> void:
	var since: Dictionary = ed["since"]
	var spread: Dictionary = ed["spread"]
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != eid or not c.is_colony() or not c.is_established():
			continue
		if not since.has(str(pid)):
			since[str(pid)] = state.tick
		var p := state.galaxy.get_planet(int(pid))
		if p.type != "gaia":
			if gardenable(state, int(pid)) and state.tick - int(since[str(pid)]) >= Insolites.tuned(state, eid, "vergemonde", "garden_days", _c("garden_days", 2880)):
				_garden(state, eid, int(pid), added, true)
				spread[str(p.system_id)] = state.tick
			continue
		var last := int(spread.get(str(p.system_id), since[str(pid)]))
		if state.tick - last < _c("spread_days", 1440):
			continue
		for q in state.galaxy.systems[p.system_id].planet_ids:
			var qc: Colony = state.colonies.get(q)
			if (qc == null or qc.owner == eid) and state.galaxy.get_planet(int(q)).type != "gaia" and gardenable(state, int(q)) and not Insolites.is_eaten(state, int(q)):
				_garden(state, eid, int(q), added, false)
				break
		spread[str(p.system_id)] = state.tick
	for k in since.keys():
		var c2: Colony = state.colonies.get(int(k))
		if c2 == null or c2.owner != eid:
			since.erase(k)


static func gardens(state: GameState, eid: int) -> int:
	var n := 0
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == eid and state.galaxy.get_planet(int(pid)).type == "gaia":
			n += 1
	return n


# --- Planter un Cœur (prop. 103) ---------------------------------------------------------------------

static func check_heart(state: GameState, eid: int, pid: int) -> String:
	if not is_verge(state, eid):
		return "seul le Hallier plante des Cœurs"
	if not LivingWorlds.enabled(state):
		return "les mondes vivants ne sont pas en jeu dans cette partie"
	var c: Colony = state.colonies.get(pid)
	if c == null or c.owner != eid:
		return "il faut une de vos colonies"
	if state.galaxy.get_planet(pid).type != "gaia":
		return "un Cœur ne prend que dans un monde-jardin"
	if LivingWorlds.is_living(state, pid):
		return "ce monde vit déjà"
	var cost: Dictionary = Insolites.cfg("vergemonde").get("heart_cost", {})
	if not Economy.can_afford(state.get_empire(eid), cost):
		return "ressources insuffisantes (il faut %s)" % GameData.format_amounts(cost)
	return ""


static func heart(state: GameState, eid: int, pid: int, added: Array[Dictionary]) -> void:
	Economy.pay(state.get_empire(eid), Insolites.cfg("vergemonde").get("heart_cost", {}))
	LivingWorlds.add_world(state, pid, "graine", eid)
	LivingWorlds.set_mood(state, pid, eid, _c("heart_mood", 50))
	var ed := Insolites.emp(state, eid)
	ed["hearts"] = int(ed.get("hearts", 0)) + 1
	added.append(state.add_chronicle("Le Hallier plante un Cœur au fond de %s. Une nuit, la planète respire ; au matin, elle a un nom, %s, et elle aime ceux qui l'ont plantée." % [
			state.galaxy.get_planet(pid).display_name(state.galaxy), LivingWorlds.name_of(state, pid)], Espionage.public_to(state, [eid])))


static func living_bound(state: GameState, eid: int) -> int:
	if state.living.is_empty():
		return 0
	var n := 0
	for pid in LivingWorlds.ids(state):
		if LivingWorlds.tier_id(state, pid, eid) == "lie":
			n += 1
	return n


# --- Le Feu-qui-renouvelle (prop. 104) ---------------------------------------------------------------

static func _fire(state: GameState, eid: int, ed: Dictionary, added: Array[Dictionary]) -> void:
	var fire: Dictionary = ed["fire"]
	for k in fire.keys():
		if int(fire[k]) > state.tick:
			continue
		fire.erase(k)
		var c: Colony = state.colonies.get(int(k))
		if c == null or c.owner != eid:
			continue
		var p := state.galaxy.get_planet(int(k))
		c.population = mini(Economy.max_pop(state, p, eid), c.population + _c("fire_regrow", 3))
		Ecology.heal(state, int(k))
		added.append(state.add_chronicle("Sur %s, la forêt brûlée l'an dernier repousse, plus dense qu'avant. Les Pousses nées dans les cendres sont les plus fortes." % p.display_name(state.galaxy),
				Espionage.private_to(state, [eid])))
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != eid or not c.is_colony() or c.population < _c("fire_min_pop", 5) or fire.has(str(pid)):
			continue
		if posmod(hash([state.seed_value, state.tick, pid, "feu"]), 1000) >= _c("fire_pmille", 15):
			continue
		var lost := mini(_c("fire_pop", 2), c.population - 1)
		c.population -= lost
		Peoples.normalize(c)
		Faiths.normalize(c)
		fire[str(pid)] = state.tick + _c("fire_regrow_days", 360)
		added.append(state.add_chronicle("Le Feu-qui-renouvelle passe sur %s. Les Enracinés brûlent sans un cri ; on dit qu'ils savaient. Dans un an, la forêt sera plus belle." % state.galaxy.get_planet(int(pid)).display_name(state.galaxy),
				Espionage.private_to(state, [eid])))
		break  # un incendie par mois au plus


static func daily(state: GameState, eid: int, ed: Dictionary, month: bool, added: Array[Dictionary]) -> void:
	if not month:
		return
	_drift(ed)
	_grow(state, eid, ed, added)
	_fire(state, eid, ed, added)
	Insolites.learn(state, eid, "learn_garden", gardens(state, eid))  # Mémoire des anneaux


# --- Victoire : le Grand Jardin (prop. 105) ----------------------------------------------------------

static func victory(state: GameState, e: Empire, out: Dictionary) -> void:
	var v: Dictionary = Insolites.cfg("victories").get("grand_jardin", {})
	var want_g := int(v.get("gardens", 8))
	var want_l := int(v.get("living", 3))
	var g := gardens(state, e.id)
	var l := living_bound(state, e.id)
	out["lines"].append("Mondes-jardins : %d / %d ; mondes vivants Liés : %d / %d" % [g, want_g, l, want_l])
	out["cond"] = g >= want_g and l >= want_l
	Victory._timed(out, mini(g, want_g) + mini(l, want_l), want_g + want_l)


static func status_lines(state: GameState, eid: int, ed: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var a := ages(state, eid)
	out.append("%s : Pousses %d %%, Marcheurs %d %%, Enracinés %d %%" % [String(SEASON_LABEL.get(String(ed.get("season", "")), "Saison")), int(a["p"]), int(a["m"]), int(a["e"])])
	out.append("Mondes-jardins : %d ; Cœurs plantés : %d ; mondes vivants Liés : %d" % [gardens(state, eid), int(ed.get("hearts", 0)), living_bound(state, eid)])
	return out
