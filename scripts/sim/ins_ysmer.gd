class_name InsYsmer
extends RefCounted
## Rêveurs d'Ysmer (props 54 à 58 ; voir Insolites, data/insolites.json "ysmer").
## Un seul monde physique, le sanctuaire du Dormeur (pas de vaisseau colon, pas de nouvelle colonie),
## et presque pas de flotte. Leur territoire, ce sont les Rêveries : des implants cachés dans le sommeil
## des populations organiques (jamais chez les synthétiques, la Noosphère ou le Signal), qui gagnent
## parfois une colonie à huit sauts au plus du Dormeur ou à trois sauts d'une rêverie. Seuls des Éveillés (pilier
## psionique) les voient, et les chassent en plongeant dans le Songe. Depuis une rêverie, les Ysmer
## soufflent une inspiration (Savoir pour l'hôte) ou un cauchemar (stabilité -10 six mois), ou rêvent
## une flotte de songe qui dure 90 jours. Chaque rêverie rapporte de l'influence. Victoire : le Rêve
## commun ; la Transcendance (credo) reste ouverte.
##
## État (Insolites.emp) : "dream": {"fid": fin}, "dream_cd": jour, "pop" (rêveries) ; état commun
## state.insolites["night"] = {"sid": fin du cauchemar}.


static func _c(key: String, def := 0) -> int:
	return Insolites.c_int("ysmer", key, def)


static func found(_state: GameState, _e: Empire, _sid: int, ed: Dictionary) -> void:
	ed["dream"] = {}
	ed["dream_cd"] = 0


## Première rêverie (Insolites.after_setup) : la colonie organique la plus proche du Dormeur.
static func seed_reverie(state: GameState, eid: int) -> void:
	var e := state.get_empire(eid)
	if e.home_planet < 0:
		return
	var d: Dictionary = FactionTraits.jumps_from(state.galaxy, state.galaxy.get_planet(e.home_planet).system_id)
	var best := -1
	var best_d := 999
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == eid or not c.is_colony() or not organic(state, c.owner):
			continue
		var j := int(d.get(state.galaxy.get_planet(int(pid)).system_id, 999))
		if j < best_d:
			best_d = j
			best = int(pid)
	if best >= 0:
		Insolites.add_implant(state, best, "reverie", eid)
	Insolites.emp(state, eid)["pop"] = 1 if best >= 0 else 0


static func reveries(state: GameState, eid: int) -> Array[int]:
	return Insolites.implants_of(state, eid, "reverie")


## Population organique : ni synthétique, ni Noosphère, ni pure donnée.
static func organic(state: GameState, eid: int) -> bool:
	var e := state.get_empire(eid)
	if e == null or e.is_npc():
		return false
	var sp: Dictionary = e.faction().get("species", {})
	return not ["synthetique", "information"].has(String(sp.get("archetype", ""))) and String(sp.get("gouvernement", "")) != "conscience"


static func detects(state: GameState, eid: int) -> bool:
	return not state.psionics.is_empty() and Psionics.awake(state, eid)


static func income(state: GameState, eid: int) -> Dictionary:
	return {"influence": reveries(state, eid).size() * _c("reverie_influence", 1)}


static func daily(state: GameState, eid: int, ed: Dictionary, month: bool, added: Array[Dictionary]) -> void:
	var dr: Dictionary = ed.get("dream", {})
	for k in dr.keys():
		if int(dr[k]) > state.tick and state.fleets.has(int(k)):
			continue
		dr.erase(k)
		if state.fleets.has(int(k)):
			var f: Fleet = state.fleets[int(k)]
			state.fleets.erase(int(k))
			added.append(state.add_chronicle("La flotte de songe des Ysmer se dissipe au réveil de ceux qui la rêvaient.", Espionage.private_to(state, [eid], f.system_id)))
	if not month:
		return
	_spread(state, eid)
	ed["pop"] = reveries(state, eid).size()


static func _spread(state: GameState, eid: int) -> void:
	var e := state.get_empire(eid)
	var sources: Array[int] = []
	var home := e.capital_planet if e.capital_planet >= 0 else e.home_planet
	if home >= 0:
		sources.append(state.galaxy.get_planet(home).system_id)
	for pid in reveries(state, eid):
		var sid := state.galaxy.get_planet(pid).system_id
		if not sources.has(sid):
			sources.append(sid)
	for i in sources.size():
		var src := sources[i]
		var reach := _c("dormeur_jumps", 8) if i == 0 and home >= 0 else _c("spread_jumps", 3)
		var h := hash([state.seed_value, state.tick, eid, src, "reve"])
		if posmod(h, 1000) >= Insolites.tuned(state, eid, "ysmer", "spread_pmille", _c("spread_pmille", 50)):
			continue
		var d: Dictionary = FactionTraits.jumps_from(state.galaxy, src)
		var cands: Array[int] = []
		for pid in state.sorted_colony_ids():
			var c: Colony = state.colonies[pid]
			if c.owner == eid or not c.is_colony() or not c.is_established() or not organic(state, c.owner):
				continue
			if not Insolites.implant(state, int(pid), "reverie").is_empty():
				continue
			if int(d.get(state.galaxy.get_planet(int(pid)).system_id, 999)) <= reach:
				cands.append(int(pid))
		if not cands.is_empty():
			Insolites.add_implant(state, cands[posmod(h / 1000, cands.size())], "reverie", eid)


# --- Souffler un rêve (prop. 56) ---------------------------------------------------------------------

static func check_breath(state: GameState, eid: int, act: String, pid: int) -> String:
	if Insolites.kind(state, eid) != "ysmer":
		return "seuls les Rêveurs d'Ysmer soufflent des rêves"
	var im := Insolites.implant(state, pid, "reverie")
	if im.is_empty() or int(im["o"]) != eid:
		return "il faut une rêverie dans ce monde"
	var cost: Dictionary = Insolites.cfg("ysmer").get("inspire_cost" if act == "inspire" else "nightmare_cost", {})
	if not Economy.can_afford(state.get_empire(eid), cost):
		return "ressources insuffisantes (il faut %s)" % GameData.format_amounts(cost)
	if act == "nightmare" and int((state.insolites.get("night", {}) as Dictionary).get(str(state.galaxy.get_planet(pid).system_id), 0)) > state.tick:
		return "ce système fait déjà des cauchemars"
	return ""


static func breath(state: GameState, eid: int, act: String, pid: int, added: Array[Dictionary]) -> void:
	var c: Colony = state.colonies[pid]
	var host := state.get_empire(c.owner)
	var name := state.galaxy.get_planet(pid).display_name(state.galaxy)
	if act == "inspire":
		Economy.pay(state.get_empire(eid), Insolites.cfg("ysmer").get("inspire_cost", {}))
		host.resources["knowledge"] = int(host.resources.get("knowledge", 0)) + _c("inspire_knowledge", 30)
		Insolites.learn(state, eid, "learn_inspire", 1)  # Rêves savants
		Diplomacy.remember(state, c.owner, eid, "ins_dream_gift")
		added.append(state.add_chronicle("À %s, un chercheur se réveille avec la solution d'un problème qu'il ne s'était jamais posé. Il remercie le café." % name, Espionage.private_to(state, [eid, c.owner])))
	else:
		Economy.pay(state.get_empire(eid), Insolites.cfg("ysmer").get("nightmare_cost", {}))
		var sid := state.galaxy.get_planet(pid).system_id
		Insolites.sub(state, "night")[str(sid)] = state.tick + _c("nightmare_days", 180)
		added.append(state.add_chronicle("Cauchemars à %s : toute la colonie rêve la même nuit d'un couloir sans fin et d'une porte qui respire." % name, Espionage.private_to(state, [eid, c.owner], sid)))


static func check_dream_fleet(state: GameState, eid: int) -> String:
	if Insolites.kind(state, eid) != "ysmer":
		return "seuls les Rêveurs d'Ysmer rêvent des flottes"
	var ed := Insolites.emp(state, eid)
	if not (ed.get("dream", {}) as Dictionary).is_empty():
		return "une flotte de songe est déjà rêvée"
	if int(ed.get("dream_cd", 0)) > state.tick:
		return "les dormeurs se reposent (%d jours)" % (int(ed["dream_cd"]) - state.tick)
	var e := state.get_empire(eid)
	if e.capital_planet < 0 and e.home_planet < 0:
		return "le Dormeur a disparu"
	if not Economy.can_afford(e, Insolites.cfg("ysmer").get("dream_fleet_cost", {})):
		return "ressources insuffisantes (il faut %s)" % GameData.format_amounts(Insolites.cfg("ysmer").get("dream_fleet_cost", {}))
	return ""


static func dream_fleet(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	Economy.pay(e, Insolites.cfg("ysmer").get("dream_fleet_cost", {}))
	var home := e.capital_planet if e.capital_planet >= 0 else e.home_planet
	var sid := state.galaxy.get_planet(home).system_id
	var ships: Array = Insolites.cfg("ysmer").get("dream_fleet_ships", ["corvette"])
	var f := state.spawn_ship(eid, String(ships[0]), sid)
	for i in range(1, ships.size()):
		f.add_ship(String(ships[i]), -1, Research.mark_gen(state, eid))
	f.fleet_name = "Flotte de songe"
	var ed := Insolites.emp(state, eid)
	(ed["dream"] as Dictionary)[str(f.id)] = state.tick + Insolites.tuned(state, eid, "ysmer", "dream_fleet_days", _c("dream_fleet_days", 90))
	ed["dream_cd"] = state.tick + _c("dream_fleet_days", 90) + _c("dream_fleet_cooldown_days", 360)
	added.append(state.add_chronicle("Au-dessus du Dormeur, des vaisseaux se condensent comme la buée sur une vitre. Ils dureront le temps d'un rêve.", Espionage.private_to(state, [eid], sid)))


static func nightmare(state: GameState, sid: int) -> bool:
	return int((state.insolites.get("night", {}) as Dictionary).get(str(sid), 0)) > state.tick


# --- Victoire : le Rêve commun (prop. 58) ------------------------------------------------------------

static func dream_share(state: GameState, eid: int) -> Array[int]:
	var tot := 0
	var mine := 0
	var rv := reveries(state, eid)
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if not c.is_colony() or c.owner == eid or not organic(state, c.owner):
			continue
		tot += c.population
		if rv.has(int(pid)):
			mine += c.population
	return [tot, mine]


static func victory(state: GameState, e: Empire, out: Dictionary) -> void:
	var want := int(Insolites.cfg("victories").get("reve_commun", {}).get("pct", _c("dream_pct", 50)))
	var ds := dream_share(state, e.id)
	@warning_ignore("integer_division")
	var pct := ds[1] * 100 / ds[0] if ds[0] > 0 else 0
	out["lines"].append("Population organique qui rêve avec Ysmer : %d %% / %d %%" % [pct, want])
	out["cond"] = ds[0] > 0 and pct >= want
	Victory._timed(out, mini(pct, want), want)


static func status_lines(state: GameState, eid: int, ed: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var ds := dream_share(state, eid)
	@warning_ignore("integer_division")
	out.append("Rêveries : %d (%d %% de la population organique)" % [reveries(state, eid).size(), ds[1] * 100 / ds[0] if ds[0] > 0 else 0])
	if not (ed.get("dream", {}) as Dictionary).is_empty():
		out.append("Flotte de songe rêvée")
	elif int(ed.get("dream_cd", 0)) > state.tick:
		out.append("Prochaine flotte de songe dans %d jours" % (int(ed["dream_cd"]) - state.tick))
	return out
