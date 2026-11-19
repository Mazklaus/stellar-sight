class_name InsQuietude
extends RefCounted
## Observateurs de Quiétude (props 77 à 82 ; voir Insolites, data/insolites.json "quietude").
## Ils gagnent en protégeant et en élevant en secret des espèces primitives.
##   - Postes voilés : implants cachés ("poste") au-dessus des peuples pré-spatiaux (pilier Peuples
##     mineurs), qui rapportent du Savoir ; peu de colonies à eux (lithoïdes lents, colonies chères).
##   - Élever en secret : une élévation discrète avance l'âge du jeune peuple, mais fait monter sa
##     conscience (MinorsLife.add_aware).
##   - Être découvert : un autre empire qui stationne une flotte, tient son propre poste, ou voit une
##     bataille où paraît une escadre de Quiétude peut repérer un poste ; un jeune peuple qui prend
##     conscience de tout le repère aussi. C'est un scandale : le poste tombe, tous les empires s'en
##     souviennent, et le compte des Envols repart de zéro.
##   - Protéger sans se montrer : leurs escadres sont voilées (talent de furtivité de la Non-ingérence).
##   - Victoire : l'Envol (faire atteindre l'espace à deux espèces primitives sans être découvert entre-temps).
##   - Les Protégés : un peuple élevé naît suzerain-verrouillé de Quiétude et lui fait des cadeaux.
##
## État (Insolites.emp) : "elevated" (Envols depuis la dernière découverte), "found" (découvertes),
## "prot": {mineur: jour}, "up": {mineur: jour de fin d'attente}.


static func _c(key: String, def := 0) -> int:
	return Insolites.c_int("quietude", key, def)


static func found(_state: GameState, _e: Empire, _sid: int, ed: Dictionary) -> void:
	ed["elevated"] = 0
	ed["found"] = 0
	ed["prot"] = {}
	ed["up"] = {}


static func watchers(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for eid in Insolites.nomad_ids(state):
		if Insolites.kind(state, eid) == "quietude":
			out.append(eid)
	return out


static func posts(state: GameState, eid: int) -> Array[int]:
	return Insolites.implants_of(state, eid, "poste")


static func post_on(state: GameState, mid: int) -> Dictionary:
	var m := Minors.get_m(state, mid)
	return {} if m.is_empty() else Insolites.implant(state, int(m["planet"]), "poste")


# --- Postes voilés (prop. 77) ------------------------------------------------------------------------

static func check_post(state: GameState, eid: int, mid: int) -> String:
	if Insolites.kind(state, eid) != "quietude":
		return "seuls les Observateurs posent des postes voilés"
	if not Minors.enabled(state) or Minors.get_m(state, mid).is_empty() or not Minors.is_pre(state, mid):
		return "il faut un peuple pré-spatial"
	var e := state.get_empire(eid)
	var sid := Minors.system_of(state, mid)
	if not e.explored.has(sid):
		return "système inexploré"
	if not post_on(state, mid).is_empty():
		return "un poste voilé veille déjà sur eux"
	var cap := FactionTraits.capital_system(state, eid)
	if cap >= 0 and int(FactionTraits.jumps_from(state.galaxy, cap).get(sid, 999)) > _c("post_jumps", 12):
		return "trop loin de Quiétude (%d sauts au plus)" % _c("post_jumps", 12)
	var cost: Dictionary = Insolites.cfg("quietude").get("post_cost", {})
	if not Economy.can_afford(e, cost):
		return "ressources insuffisantes (il faut %s)" % GameData.format_amounts(cost)
	return ""


static func post(state: GameState, eid: int, mid: int, added: Array[Dictionary]) -> void:
	Economy.pay(state.get_empire(eid), Insolites.cfg("quietude").get("post_cost", {}))
	Insolites.add_implant(state, int(Minors.get_m(state, mid)["planet"]), "poste", eid)
	added.append(state.add_chronicle("Les Observateurs posent un poste voilé au-dessus %s. Personne en bas ne lève les yeux ; c'est exactement le but." % Crisis.de_name(Minors.name_of(state, mid)),
			Espionage.private_to(state, [eid])))


# --- Élever en secret (prop. 78) ---------------------------------------------------------------------

static func check_uplift(state: GameState, eid: int, mid: int) -> String:
	if Insolites.kind(state, eid) != "quietude":
		return "seuls les Observateurs élèvent en secret"
	var im := post_on(state, mid)
	if im.is_empty() or int(im["o"]) != eid:
		return "il faut un poste voilé au-dessus d'eux"
	var up: Dictionary = Insolites.emp(state, eid).get("up", {})
	if int(up.get(str(mid), 0)) > state.tick:
		return "laissez-les digérer la dernière idée (%d jours)" % (int(up[str(mid)]) - state.tick)
	var cost: Dictionary = Insolites.cfg("quietude").get("uplift_cost", {})
	if not Economy.can_afford(state.get_empire(eid), cost):
		return "ressources insuffisantes (il faut %s)" % GameData.format_amounts(cost)
	return ""


static func uplift(state: GameState, eid: int, mid: int, added: Array[Dictionary]) -> void:
	Economy.pay(state.get_empire(eid), Insolites.cfg("quietude").get("uplift_cost", {}))
	var m := Minors.get_m(state, mid)
	m["age_days"] = int(m["age_days"]) + Insolites.tuned(state, eid, "quietude", "uplift_days", _c("uplift_days", 540))
	MinorsLife.add_aware(state, mid, _c("uplift_aware", 10))
	(Insolites.emp(state, eid)["up"] as Dictionary)[str(mid)] = state.tick + _c("uplift_cd_days", 180)
	added.append(state.add_chronicle("Chez %s, un inventeur fait un rêve très précis. Au réveil, il dessine une roue meilleure. Au-dessus, quelqu'un prend une note, et s'inquiète un peu." % Minors.name_of(state, mid),
			Espionage.private_to(state, [eid])))


# --- Être découvert (prop. 79) -----------------------------------------------------------------------

static func _detect(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	for pid in posts(state, eid):
		var c: Colony = state.colonies.get(pid)
		var mid := c.owner if c != null else -1
		if mid < 0 or not GameState.is_minor(mid) or Minors.get_m(state, mid).is_empty() or not Minors.is_pre(state, mid):
			Insolites.remove_implant(state, pid, "poste")
			continue
		var sid := state.galaxy.get_planet(pid).system_id
		var finder := -2
		if MinorsLife.revealed(state, mid):
			finder = -1  # le jeune peuple a levé les yeux
		var h := hash([state.seed_value, state.tick, pid, "voile"])
		var mine_here := false
		for f in Fleets.fleets_at(state, sid):
			if f.owner == eid:
				mine_here = true
		if finder == -2 and mine_here and state.battles.has(sid) and posmod(h, 1000) < _c("detect_battle_pmille", 300):
			finder = _foe_in_battle(state, eid, sid)
		if finder == -2:
			var m := Minors.get_m(state, mid)
			var seen := {}
			for f in Fleets.fleets_at(state, sid):
				if f.owner != eid and not GameState.is_npc(f.owner) and not f.is_moving():
					seen[f.owner] = _c("detect_fleet_pmille", 40)
			for o in m.get("post", {}):
				if int(o) != eid:
					seen[int(o)] = int(seen.get(int(o), 0)) + Insolites.tuned(state, eid, "quietude", "detect_pmille", _c("detect_pmille", 25))
			var ks := seen.keys()
			ks.sort()
			for o in ks:
				if posmod(hash([h, o]), 1000) < int(seen[o]):
					finder = int(o)
					break
		if finder != -2:
			scandal(state, eid, pid, finder, added)


static func _foe_in_battle(state: GameState, eid: int, sid: int) -> int:
	for f in Fleets.fleets_at(state, sid):
		if f.owner != eid and not GameState.is_npc(f.owner):
			return f.owner
	return -1


## Le poste est découvert : scandale, le poste tombe, le compte des Envols repart de zéro.
static func scandal(state: GameState, eid: int, pid: int, finder: int, added: Array[Dictionary]) -> void:
	var ed := Insolites.emp(state, eid)
	var mid := (state.colonies[pid] as Colony).owner
	Insolites.remove_implant(state, pid, "poste")
	ed["found"] = int(ed.get("found", 0)) + 1
	ed["elevated"] = 0
	var e := state.get_empire(eid)
	e.resources["influence"] = maxi(0, int(e.resources.get("influence", 0)) + _c("scandal_influence", -50))
	if finder >= 0 and not state.get_empire(finder).contacts.has(eid):
		state.get_empire(finder).contacts.append(eid)
		e.contacts.append(finder)
	for o in state.empires:
		if o.id != eid and not o.eliminated and not o.is_npc() and o.contacts.has(eid):
			Diplomacy.remember(state, o.id, eid, "ins_watchers_found")
	var who := state.get_empire(finder).display_name() if finder >= 0 else Minors.name_of(state, mid)
	added.append(state.add_chronicle("Scandale ! %s découvre un poste voilé des Observateurs de Quiétude au-dessus %s. Des décennies de notes sur leurs repas, leurs chansons, leurs guerres. Toute la galaxie se demande qui d'autre est regardé." % [
			who, Crisis.de_name(Minors.name_of(state, mid))]))


# --- Protégés (props 80 et 82) -----------------------------------------------------------------------

## L'Avènement d'un pré-spatial (MinorsLife.rise) : s'il était veillé, il devient un Protégé.
static func on_rise(state: GameState, mid: int, added: Array[Dictionary]) -> void:
	if state.insolites.is_empty():
		return
	var m := Minors.get_m(state, mid)
	var im := Insolites.implant(state, int(m["planet"]), "poste")
	if im.is_empty():
		return
	var q := int(im["o"])
	Insolites.remove_implant(state, int(m["planet"]), "poste")
	var ed := Insolites.emp(state, q)
	if ed.is_empty():
		return
	ed["elevated"] = int(ed.get("elevated", 0)) + 1
	(ed["prot"] as Dictionary)[str(mid)] = state.tick
	(m["contact"] as Dictionary)[q] = state.tick
	(m["fav"] as Dictionary)[q] = int(Minors.data()["favor"]["max"])
	m["lock"] = q
	Minors.set_suzerain(state, mid, q, added)
	added.append(state.add_chronicle("%s atteint l'espace. Le premier message que reçoit son vaisseau est un mot très court, sans signature : « Bravo. »" % Minors.name_of(state, mid),
			Espionage.private_to(state, [q])))


static func proteges(state: GameState, eid: int) -> Array[int]:
	var out: Array[int] = []
	for k in (Insolites.emp(state, eid).get("prot", {}) as Dictionary):
		if not Minors.get_m(state, int(k)).is_empty():
			out.append(int(k))
	out.sort()
	return out


static func daily(state: GameState, eid: int, ed: Dictionary, month: bool, added: Array[Dictionary]) -> void:
	if not month:
		return
	var e := state.get_empire(eid)
	var ps := posts(state, eid)
	e.resources["knowledge"] = int(e.resources.get("knowledge", 0)) + ps.size() * _c("post_knowledge", 3)
	var gift: Dictionary = Insolites.cfg("quietude").get("protege_gift", {})
	for mid in proteges(state, eid):
		Insolites.add_to(e.resources, gift)
	_detect(state, eid, added)
	ed["pop"] = 0


# --- Victoire : l'Envol (prop. 81) ---------------------------------------------------------------

static func victory(state: GameState, e: Empire, out: Dictionary) -> void:
	var want := int(Insolites.cfg("victories").get("envol", {}).get("count", 2))
	var n := int(Insolites.emp(state, e.id).get("elevated", 0))
	out["lines"].append("Espèces élevées en secret depuis la dernière découverte : %d / %d" % [n, want])
	out["cond"] = n >= want
	Victory._timed(out, mini(n, want), want)


static func status_lines(state: GameState, eid: int, ed: Dictionary) -> Array[String]:
	var out: Array[String] = []
	out.append("Postes voilés : %d ; Protégés : %d" % [posts(state, eid).size(), proteges(state, eid).size()])
	out.append("Envols sans être vu : %d ; découvertes : %d" % [int(ed.get("elevated", 0)), int(ed.get("found", 0))])
	return out
