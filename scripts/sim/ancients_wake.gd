class_name AncientsWake
extends RefCounted
## Puissances anciennes : l'Éveil (lot 2 de l'étude du 2026-11-15, propositions 13 à 18 et 20).
##
## - Parvenue (13) : à partir de l'an 20, quand un bloc devient trop fort ou qu'on lui prend un monde ;
##   préavis d'un an (stage "notice"), puis "awake".
## - Éveillée (14) : flottes de plus, une colonie par an, sommations de Dominion (a["dom"] : empire →
##   jour), tribut mensuel, voix muette à l'Amphictyonie ; un refus vaut guerre ("dominion").
## - Endiguement (15) : carte à tous ; qui s'y joint lui fait la guerre avec +10 % de dégâts ; aide
##   d'urgence de l'Amphictyonie à ses membres.
## - Décadence (16) : vingt ans après l'éveil, elle monte avec ses mondes ; à 100, stage "decadent".
## - Gardiennes (17) : une crise arrivée depuis cinq ans éveille une ancienne bienveillante (stage
##   "guardian") qui chasse la crise, puis se rendort.
## - Guerre au ciel (18) : la rivale d'une parvenue s'éveille ; chacun choisit un camp ou la Ligue des
##   non-alignés (state.ancients["heaven"]).
## - Tombeaux (20) : Kheb s'éveille monde par monde (a["tombs"]), un sur cinq fou (flotte des Sans-Bannière).

const STAGE_NOTICE := "notice"
const STAGE_AWAKE := "awake"
const STAGE_DECADENT := "decadent"
const STAGE_GUARDIAN := "guardian"


static func cfg() -> Dictionary:
	return Ancients.data().get("wake", {})


static func wake_on(state: GameState) -> bool:
	return Ancients.enabled(state) and bool(state.ancients.get("wake", true))


static func roles(state: GameState, id: int) -> Array:
	return Ancients.kind_def(Ancients.kind_of(state, id)).get("roles", [])


## La parvenue du moment (préavis, éveillée ou décadente) ; -1 sinon.
static func parvenue(state: GameState) -> int:
	return int(state.ancients.get("parv", -1)) if Ancients.enabled(state) else -1


static func blocking_parvenue(state: GameState) -> int:
	var p := parvenue(state)
	if p >= 0 and Ancients.stage(state, p) == STAGE_AWAKE:
		return p
	var h := heaven(state)
	if not h.is_empty() and Ancients.stage(state, int(h["b"])) == STAGE_AWAKE:
		return int(h["b"])
	return -1


static func heaven(state: GameState) -> Dictionary:
	return state.ancients.get("heaven", {}) if Ancients.enabled(state) else {}


## Ancienne dont cet empire est le Dominion ; -1 sinon.
static func dominion_of(state: GameState, eid: int) -> int:
	if not Ancients.enabled(state):
		return -1
	for id in Ancients.ids(state):
		if (Ancients.get_a(state, id).get("dom", {}) as Dictionary).has(eid) and Ancients.stage(state, id) != STAGE_DECADENT:
			return id
	return -1


static func _push_all(state: GameState, id: int, card: String, added: Array[Dictionary], extra := {}) -> void:
	var a := Ancients.get_a(state, id)
	var subj := {"anc": id, "system": int(a["home"])}
	subj.merge(extra, true)
	for e in state.empires:
		if not e.eliminated:
			Events.push(state, e.id, card, subj, added)


# --- Chaque jour ------------------------------------------------------------------------------------

static func daily(state: GameState, id: int, a: Dictionary, added: Array[Dictionary]) -> void:
	if not wake_on(state):
		return
	var st := String(a.get("stage", Ancients.STAGE_SLEEP))
	if st == STAGE_GUARDIAN:
		_hunt(state, id)
	if (state.tick + id) % 30 != 0:
		return
	match st:
		Ancients.STAGE_SLEEP:
			if (state.tick / 30 + id) % 12 == 0:
				_check_parvenue(state, id, a, added)
			_check_guardian(state, id, a, added)
			_check_heaven(state, id, a, added)
		STAGE_NOTICE:
			if state.tick >= int(a.get("wake_at", 0)):
				awaken(state, id, added)
		STAGE_AWAKE:
			_dominion(state, id, a, added)
			_tribute(state, id, a)
			if state.tick >= int(a.get("expand", 0)):
				_expand(state, id, a, added)
			_tombs(state, id, a, added)
			_decay(state, id, a, added)
		STAGE_GUARDIAN:
			if not Crisis.active(state):
				_rest(state, id, a, added)
	_heaven_end(state, added)


static func marching(state: GameState, id: int) -> bool:
	var st := Ancients.stage(state, id)
	return st == STAGE_AWAKE or (not heaven(state).is_empty() and _in_heaven(state, id))


static func _in_heaven(state: GameState, id: int) -> bool:
	var h := heaven(state)
	return not h.is_empty() and (int(h["a"]) == id or int(h["b"]) == id)


static func heaven_pair(state: GameState, a: int, b: int) -> bool:
	var h := heaven(state)
	if h.is_empty():
		return false
	return (int(h["a"]) == a and int(h["b"]) == b) or (int(h["a"]) == b and int(h["b"]) == a)


## Hostilité hors guerre déclarée : un empire qui a pris le camp de sa rivale (Guerre au ciel).
static func hostile(state: GameState, anc: int, other: int) -> bool:
	var h := heaven(state)
	if h.is_empty() or not _in_heaven(state, anc):
		return false
	var rival := int(h["b"]) if int(h["a"]) == anc else int(h["a"])
	return int((h.get("sides", {}) as Dictionary).get(other, -1)) == rival


## Ennemis que ses flottes vont assiéger : guerres déclarées, rivale de la Guerre au ciel et ses partisans.
static func foes(state: GameState, id: int) -> Array[int]:
	var out: Array[int] = []
	for eid in Ancients.get_a(state, id).get("war", {}):
		out.append(int(eid))
	var h := heaven(state)
	if not h.is_empty() and _in_heaven(state, id):
		var rival := int(h["b"]) if int(h["a"]) == id else int(h["a"])
		out.append(rival)
		var sides: Dictionary = h.get("sides", {})
		for eid in sides:
			if int(sides[eid]) == rival and not out.has(int(eid)):
				out.append(int(eid))
	out.sort()
	return out


# --- Parvenue (prop. 13) ----------------------------------------------------------------------------

## Puissance d'un bloc : l'empire, ses alliés et les membres de son Koinon.
static func bloc_power(state: GameState, eid: int) -> int:
	var members: Array[int] = [eid]
	for b in Victory.bloc(state, eid):
		if not members.has(b):
			members.append(b)
	if state.koinon_on:
		var lid := Koinon.league_of(state, eid)
		if lid >= 0:
			for m in Koinon.members_of(state, lid):
				if not members.has(m):
					members.append(m)
	var p := 0
	for m in members:
		p += Ancients.empire_power(state, m)
	return p


static func average_power(state: GameState) -> int:
	var n := 0
	var p := 0
	for e in state.empires:
		if not e.eliminated:
			n += 1
			p += Ancients.empire_power(state, e.id)
	return p / maxi(1, n)


## Bloc trop fort : l'empire en tête de ce bloc ; -1 sinon.
static func too_strong(state: GameState) -> int:
	var avg := average_power(state)
	if avg <= 0:
		return -1
	var best := -1
	var best_p := 0
	for e in state.empires:
		if e.eliminated:
			continue
		var bp := bloc_power(state, e.id)
		if bp * 100 >= avg * int(cfg()["ratio_pct"]) and bp > best_p:
			best_p = bp
			best = e.id
	return best


static func _check_parvenue(state: GameState, id: int, a: Dictionary, added: Array[Dictionary]) -> void:
	if parvenue(state) >= 0 or state.tick < int(cfg()["parvenue_from"]) or not roles(state, id).has("parvenue"):
		return
	var who := too_strong(state)
	if who < 0 or Ancients._h(state, ["parvenue", id, state.tick / 360]) % 100 >= int(cfg()["roll_pct"]):
		return
	a["why"] = "On dit que la puissance de %s l'a tirée de son sommeil." % state.get_empire(who).display_name()
	notice(state, id, added)


## Préavis d'un an : fenêtre d'événement chez tous.
static func notice(state: GameState, id: int, added: Array[Dictionary]) -> void:
	var a := Ancients.get_a(state, id)
	if a.is_empty() or Ancients.stage(state, id) != Ancients.STAGE_SLEEP:
		return
	state.ancients["parv"] = id
	a["stage"] = STAGE_NOTICE
	a["wake_at"] = state.tick + int(cfg()["notice_days"])
	Announce.next(state, "ancient_stir", {})
	added.append(state.add_chronicle("%s remue dans son sommeil. Dans un an, elle sera debout." % Ancients.name_of(state, id)))
	_push_all(state, id, "anc_eveil_preavis", added)


## Un de ses mondes pris : la parvenue s'éveille aussitôt (préavis sauté).
static func on_lost_world(state: GameState, old: int, _new_owner: int, added: Array[Dictionary]) -> void:
	if not wake_on(state) or not GameState.is_ancient(old):
		return
	var a := Ancients.get_a(state, old)
	if Ancients.stage(state, old) == Ancients.STAGE_SLEEP and roles(state, old).has("parvenue") and parvenue(state) < 0:
		a["why"] = "On lui a pris un monde. Elle ne dormira plus."
		notice(state, old, added)
		awaken(state, old, added)
	elif Ancients.stage(state, old) == STAGE_NOTICE:
		awaken(state, old, added)


static func awaken(state: GameState, id: int, added: Array[Dictionary]) -> void:
	var a := Ancients.get_a(state, id)
	a["stage"] = STAGE_AWAKE
	a["woke"] = state.tick
	a["decay"] = 0
	a["expand"] = state.tick + int(cfg()["expand_days"])
	if not a.has("dom"):
		a["dom"] = {}
	if not a.has("sub_cd"):
		a["sub_cd"] = {}
	var c := cfg()
	var kd := Ancients.kind_def(String(a["kind"]))
	if bool(kd.get("tombs", false)):
		# Kheb : les flottes sortent tombeau par tombeau (prop. 20).
		var tombs: Array = []
		for pid in state.sorted_colony_ids():
			var col: Colony = state.colonies[pid]
			if col.owner == id and state.galaxy.get_planet(pid).system_id != int(a["home"]):
				tombs.append(pid)
		a["tombs"] = tombs
		a["tomb_next"] = state.tick + int(c["tomb_days"])
	else:
		for i in int(c["awake_fleets"]):
			@warning_ignore("integer_division")
			Ancients.spawn_fleet(state, id, int(a["home"]), int(a["power"]) * int(c["awake_power_pct"]) / 100 / maxi(1, int(c["awake_fleets"])), false)
	for e in state.empires:
		e.path_cache.clear()
	var aid := ""
	if state.amph_on and Amphictyony.founded(state):
		aid = ", et l'Amphictyonie tient une session extraordinaire : aide d'urgence à chaque membre (%s)" % GameData.format_amounts(c["aid_res"])
		for m in Amphictyony.members(state):
			var me := state.get_empire(m)
			for r in c["aid_res"]:
				me.resources[r] = int(me.resources.get(r, 0)) + int(c["aid_res"][r])
		added.append(state.add_chronicle("Session extraordinaire de %s face à %s : l'assemblée vote l'aide d'urgence à l'unanimité, pour une fois." % [
				Amphictyony.name_short(), Crisis.obj_name(Ancients.name_of(state, id))]))
	a["aid"] = aid
	Announce.next(state, "ancient_wake", {})
	added.append(state.add_chronicle("%s s'éveille. Ses chantiers rouvrent ; ses hérauts partent avec des traités de soumission tout prêts." % Ancients.name_of(state, id)))
	_push_all(state, id, "anc_eveil", added)


# --- Éveillée : Dominion, tribut, expansion (prop. 14) ----------------------------------------------

static func _dominion(state: GameState, id: int, a: Dictionary, added: Array[Dictionary]) -> void:
	var c := cfg()
	var jumps := FactionTraits.jumps_from(state.galaxy, int(a["home"]))
	for e in state.empires:
		if e.eliminated or (a["dom"] as Dictionary).has(e.id) or Ancients.at_war_with(state, id, e.id):
			continue
		if dominion_of(state, e.id) >= 0 or _protected(state, id, e.id):
			continue
		var cap := FactionTraits.capital_system(state, e.id)
		if cap < 0 or int(jumps.get(cap, 999)) > int(c["dominion_jumps"]):
			continue
		if state.tick < int((a["sub_cd"] as Dictionary).get(e.id, 0)):
			continue
		(a["sub_cd"] as Dictionary)[e.id] = state.tick + int(c["dominion_cd"])
		Ancients.meet(state, id, e.id, added)
		Events.push(state, e.id, "anc_dominion", {"anc": id, "system": int(a["home"])}, added)


## Camp choisi dans la Guerre au ciel : protégé pendant side_days jours.
static func _protected(state: GameState, id: int, eid: int) -> bool:
	var h := heaven(state)
	return not h.is_empty() and int((h.get("sides", {}) as Dictionary).get(eid, -1)) == id and state.tick < int(h["since"]) + int(cfg()["side_days"])


static func _tribute(state: GameState, id: int, a: Dictionary) -> void:
	var pct := int(cfg()["tribute_pct"])
	for eid in (a["dom"] as Dictionary).keys():
		var e := state.get_empire(int(eid))
		if e == null or e.eliminated:
			(a["dom"] as Dictionary).erase(eid)
			continue
		for r in ["energy", "knowledge"]:
			@warning_ignore("integer_division")
			e.resources[r] = maxi(0, int(e.resources.get(r, 0)) - int(e.resources.get(r, 0)) * pct / 100)


## Une colonie de plus par an : la plus belle planète libre à un saut de ses systèmes.
static func _expand(state: GameState, id: int, a: Dictionary, added: Array[Dictionary]) -> void:
	a["expand"] = state.tick + int(cfg()["expand_days"])
	var best := -1
	var best_s := -1
	var mine := Ancients.systems_of(state, id)
	for sid in mine:
		for nb in state.galaxy.systems[sid].neighbors:
			var n := int(nb)
			if state.system_owner(n) >= 0 and state.system_owner(n) != id:
				continue
			for pid in state.galaxy.systems[n].planet_ids:
				if state.colonies.has(pid):
					continue
				var s := state.galaxy.get_planet(pid).size * 1000 + Ancients._h(state, ["essor", id, pid]) % 1000
				if s > best_s:
					best_s = s
					best = pid
	if best < 0:
		return
	var col := Colony.new()
	col.planet_id = best
	col.owner = id
	col.kind = Colony.KIND_COLONY
	col.population = 4
	state.colonies[best] = col
	state.rebuild_ownership()
	var sid2 := state.galaxy.get_planet(best).system_id
	if not (a["systems"] as Array).has(sid2):
		(a["systems"] as Array).append(sid2)
	for e in state.empires:
		e.path_cache.clear()
	added.append(state.add_chronicle("%s s'étend : %s porte désormais ses couleurs." % [Ancients.name_of(state, id), state.galaxy.get_planet(best).display_name(state.galaxy)]))


# --- Décadence (prop. 16) ---------------------------------------------------------------------------

static func _decay(state: GameState, id: int, a: Dictionary, added: Array[Dictionary]) -> void:
	var c := cfg()
	if state.tick < int(a.get("woke", 0)) + int(c["decay_after"]):
		return
	var worlds := 0
	for pid in state.colonies:
		if (state.colonies[pid] as Colony).owner == id:
			worlds += 1
	a["decay"] = int(a.get("decay", 0)) + 1 + worlds / maxi(1, int(c["decay_worlds"]))
	if int(a["decay"]) >= 100:
		decline(state, id, added)


static func decline(state: GameState, id: int, added: Array[Dictionary]) -> void:
	var a := Ancients.get_a(state, id)
	a["stage"] = STAGE_DECADENT
	a["decay"] = 100
	var pct := int(cfg()["decay_ships_pct"])
	for f in Ancients.fleets_of(state, id):
		@warning_ignore("integer_division")
		var cut := f.ships.size() * pct / 100
		for i in cut:
			if f.ships.size() > 1:
				f.ships.pop_back()
	added.append(state.add_chronicle("%s décline. Ses flottes rouillent, ses Dominions relèvent la tête : on peut de nouveau la vaincre." % Ancients.name_of(state, id)))
	_push_all(state, id, "anc_decadence", added)


# --- Gardiennes de la galaxie (prop. 17) ------------------------------------------------------------

static func _check_guardian(state: GameState, id: int, a: Dictionary, added: Array[Dictionary]) -> void:
	if not Crisis.active(state) or not roles(state, id).has("gardienne") or not (a["war"] as Dictionary).is_empty():
		return
	var c := cfg()
	var cr := Crisis.cur(state)
	if state.tick < int(cr.get("arrived", state.tick)) + int(c["guardian_after"]):
		return
	var key := "%s:%d" % [Crisis.kind(state), int(cr.get("arrived", 0))]
	if String(state.ancients.get("guard_roll", "")) == key:
		return
	# Un seul tirage par crise, pour la première gardienne qui le tente.
	state.ancients["guard_roll"] = key
	if Ancients._h(state, ["gardienne", key]) % 100 >= int(c["guardian_pct"]):
		return
	a["stage"] = STAGE_GUARDIAN
	for i in int(c["guardian_fleets"]):
		@warning_ignore("integer_division")
		Ancients.spawn_fleet(state, id, int(a["home"]), int(a["power"]) / maxi(1, int(c["guardian_fleets"])), false)
	added.append(state.add_chronicle("%s se lève contre %s et rejoint le Front commun. On ne l'avait jamais vue si pressée." % [
			Ancients.name_of(state, id), Crisis.obj_name(Crisis.name_of(Crisis.kind(state)))]))
	_push_all(state, id, "anc_gardienne", added)


## Ses flottes (sauf la garde) vont droit aux flottes de la crise les plus proches.
static func _hunt(state: GameState, id: int) -> void:
	if state.tick % 5 != 0:
		return
	var targets := {}
	for g in Crisis.war_fleets(state):
		targets[g.system_id] = true
	for g in Crisis.stations(state):
		targets[g.system_id] = true
	if targets.is_empty():
		return
	var fl := Ancients.fleets_of(state, id)
	for i in fl.size():
		var f := fl[i]
		if i == 0 or f.is_moving() or state.battles.has(f.system_id) or targets.has(f.system_id):
			continue
		var jumps := FactionTraits.jumps_from(state.galaxy, f.system_id)
		var best := -1
		var best_j := 999
		var keys := targets.keys()
		keys.sort()
		for k in keys:
			var j := int(jumps.get(int(k), 999))
			if j < best_j:
				best_j = j
				best = int(k)
		if best >= 0:
			var route := Fleets.plan_route(state, f, best)
			if not route.is_empty():
				f.system_id = int(route["system"])
				f.path.assign(route["path"])
				f.progress = int(route["progress"])


static func _rest(state: GameState, id: int, a: Dictionary, added: Array[Dictionary]) -> void:
	a["stage"] = Ancients.STAGE_SLEEP
	Ancients._go_home(state, id)
	for e in state.empires:
		if Ancients.in_contact(state, id, e.id):
			Ancients.add_op(state, id, e.id, 50)
	added.append(state.add_chronicle("La crise vaincue, %s retourne au repos. Elle laisse un mot : « Ne recommencez pas. »" % Ancients.name_of(state, id)))


# --- Guerre au ciel (prop. 18) ----------------------------------------------------------------------

static func _check_heaven(state: GameState, id: int, a: Dictionary, added: Array[Dictionary]) -> void:
	var p := parvenue(state)
	if p < 0 or not heaven(state).is_empty() or Ancients.stage(state, p) != STAGE_AWAKE:
		return
	var rival := Ancients.id_of_kind(state, String(Ancients.kind_def(Ancients.kind_of(state, p)).get("rival", "")))
	if rival != id:
		return
	var c := cfg()
	var since := int(Ancients.get_a(state, p).get("woke", state.tick))
	if state.tick - since < int(c["heaven_every"]) or (state.tick - since) % int(c["heaven_every"]) >= 30:
		return
	if Ancients._h(state, ["ciel", id, (state.tick - since) / int(c["heaven_every"])]) % 100 >= int(c["heaven_pct"]):
		return
	start_heaven(state, p, id, added)


static func start_heaven(state: GameState, parv: int, rival: int, added: Array[Dictionary]) -> void:
	var b := Ancients.get_a(state, rival)
	b["stage"] = STAGE_AWAKE
	b["woke"] = state.tick
	b["expand"] = state.tick + int(cfg()["expand_days"])
	if not b.has("dom"):
		b["dom"] = {}
	if not b.has("sub_cd"):
		b["sub_cd"] = {}
	for i in int(cfg()["awake_fleets"]):
		@warning_ignore("integer_division")
		Ancients.spawn_fleet(state, rival, int(b["home"]), int(b["power"]) / maxi(1, int(cfg()["awake_fleets"])), false)
	state.ancients["heaven"] = {"a": parv, "b": rival, "since": state.tick, "sides": {}, "league": -1}
	for e in state.empires:
		e.path_cache.clear()
	Announce.next(state, "sky_war", {})
	added.append(state.add_chronicle("Guerre au ciel : %s s'éveille pour affronter %s. Les deux plus vieilles puissances de la galaxie se battent, et la galaxie est entre les deux." % [
			Ancients.name_of(state, rival), Crisis.obj_name(Ancients.name_of(state, parv))]))
	_push_all(state, rival, "anc_guerre_ciel", added)


## Choix d'un camp (v = 1 : l'ancienne de la carte, 2 : sa rivale, 0 : neutre).
static func choose_side(state: GameState, eid: int, v: int, added: Array[Dictionary]) -> void:
	var h := heaven(state)
	if h.is_empty():
		return
	var pick := int(h["b"]) if v == 1 else (int(h["a"]) if v == 2 else 0)
	(h["sides"] as Dictionary)[eid] = pick
	var e := state.get_empire(eid)
	if pick > 0:
		Ancients.meet(state, pick, eid, added)
		Ancients.add_op(state, pick, eid, 100)
		added.append(state.add_chronicle("%s prend le parti %s dans la Guerre au ciel." % [e.display_name(), Crisis.de_name(Ancients.name_of(state, pick))]))
	else:
		_league(state, added)
	for o in state.empires:
		o.path_cache.clear()


## Ligue des non-alignés : le plus grand Koinon s'il est neutre, sinon autour du neutre le plus fort.
static func _league(state: GameState, added: Array[Dictionary]) -> void:
	var h := heaven(state)
	if int(h.get("league", -1)) >= 0 or int(h.get("league_e", -1)) >= 0:
		return
	var neutrals: Array[int] = []
	for k in h["sides"]:
		if int(h["sides"][k]) == 0:
			neutrals.append(int(k))
	if state.koinon_on:
		var best := -1
		var best_n := 0
		for lid in Koinon.league_ids(state):
			var ms := Koinon.members_of(state, lid)
			if ms.size() > best_n:
				best_n = ms.size()
				best = lid
		if best >= 0:
			var all_neutral := true
			for m in Koinon.members_of(state, best):
				if int((h["sides"] as Dictionary).get(m, -1)) > 0:
					all_neutral = false
			if all_neutral:
				h["league"] = best
				added.append(state.add_chronicle("%s se proclame Ligue des non-alignés : ni l'une, ni l'autre, et que les anciennes se débrouillent." % String(Koinon.league(state, best)["name"])))
				return
	var strongest := -1
	for n in neutrals:
		if strongest < 0 or Ancients.empire_power(state, n) > Ancients.empire_power(state, strongest):
			strongest = n
	if strongest >= 0:
		h["league_e"] = strongest
		added.append(state.add_chronicle("Une Ligue des non-alignés se forme autour de %s. Neutres, mais pas sans dents." % state.get_empire(strongest).display_name()))


## Membres de la Ligue des non-alignés (+10 % de dégâts face aux deux anciennes).
static func in_league(state: GameState, eid: int) -> bool:
	var h := heaven(state)
	if h.is_empty() or int((h.get("sides", {}) as Dictionary).get(eid, -1)) != 0:
		return false
	if int(h.get("league", -1)) >= 0:
		return Koinon.members_of(state, int(h["league"])).has(eid)
	return int(h.get("league_e", -1)) >= 0


## Fin de la Guerre au ciel : une des deux n'a plus de monde ou décline ; le butin va au camp vainqueur.
static func _heaven_end(state: GameState, added: Array[Dictionary]) -> void:
	var h := heaven(state)
	if h.is_empty():
		return
	var loser := -1
	for x in [int(h["a"]), int(h["b"])]:
		if Ancients.systems_of(state, x).is_empty() or Ancients.stage(state, x) == STAGE_DECADENT:
			loser = x
	if loser < 0:
		return
	var winner := int(h["b"]) if loser == int(h["a"]) else int(h["a"])
	var loot: Dictionary = cfg()["heaven_loot"]
	var names := PackedStringArray()
	for k in h["sides"]:
		if int(h["sides"][k]) == winner:
			var e := state.get_empire(int(k))
			if e != null and not e.eliminated:
				for r in loot:
					e.resources[r] = int(e.resources.get(r, 0)) + int(loot[r])
				names.append(e.short_name())
	state.ancients.erase("heaven")
	for e in state.empires:
		e.path_cache.clear()
	added.append(state.add_chronicle("La Guerre au ciel est finie : %s l'emporte sur %s.%s" % [Ancients.name_of(state, winner), Crisis.obj_name(Ancients.name_of(state, loser)),
			(" Ses partisans se partagent le butin : %s." % ", ".join(names)) if not names.is_empty() else ""]))


# --- Tombeaux de Kheb (prop. 20) --------------------------------------------------------------------

static func _tombs(state: GameState, id: int, a: Dictionary, added: Array[Dictionary]) -> void:
	if not a.has("tombs") or state.tick < int(a.get("tomb_next", 0)):
		return
	var c := cfg()
	a["tomb_next"] = state.tick + int(c["tomb_days"])
	var tombs: Array = a["tombs"]
	while not tombs.is_empty():
		var pid := int(tombs.pop_front())
		var col: Colony = state.colonies.get(pid)
		if col == null or col.owner != id:
			continue  # tombeau rasé avant qu'il ouvre les yeux
		var sid := state.galaxy.get_planet(pid).system_id
		var n := int(a.get("tomb_n", 0))
		a["tomb_n"] = n + 1
		@warning_ignore("integer_division")
		var pw := int(a["power"]) * int(c["tomb_power_pct"]) / 100
		var mad := Ancients._h(state, ["fou", id, pid]) % maxi(1, int(c["tomb_mad"])) == 0
		if mad:
			var kd := Ancients.kind_def(String(a["kind"]))
			var line := String(kd.get("units", {}).get("line", ""))
			var f := state.spawn_ship(GameState.NPC_ID, line, sid)
			var guard := 0
			while Combat.fleet_power(f) < pw and guard < 50:
				guard += 1
				f.add_ship(line, -1, -1)
			f.troops = 0
			f.fleet_name = "Tombeau fou"
			a["tomb_text"] = "Celui-là s'est réveillé fou : il attaque tout ce qui bouge, Kheb compris."
		else:
			var g := Ancients.spawn_fleet(state, id, sid, pw, false)
			g.fleet_name = "Tombeau %s" % GameState.ROMAN[mini(n + 1, GameState.ROMAN.size() - 1)]
			a["tomb_text"] = "Une flotte de plus se lève pour la Dynastie."
		added.append(state.add_chronicle("Sur %s, un tombeau %s ouvre les yeux. %s" % [state.galaxy.systems[sid].system_name, Crisis.de_name(Ancients.name_of(state, id)), String(a["tomb_text"])]))
		for e in state.empires:
			if Ancients.in_contact(state, id, e.id):
				Events.push(state, e.id, "anc_tombeau", {"anc": id, "system": sid}, added)
		return


# --- Guerres et prises ------------------------------------------------------------------------------

static func on_war(state: GameState, id: int, eid: int, _why: String, _added: Array[Dictionary]) -> void:
	# Un Dominion qui entre en guerre contre son maître cesse de l'être.
	var a := Ancients.get_a(state, id)
	(a.get("dom", {}) as Dictionary).erase(eid)
	Relics.touch(state)


static func on_take(_state: GameState, _id: int, _sid: int, _owner: int, _added: Array[Dictionary]) -> void:
	pass


# --- Effets, cartes, commandes ----------------------------------------------------------------------

## Endiguement (+10 % de dégâts contre une parvenue éveillée) et Ligue des non-alignés.
static func effects(state: GameState, eid: int) -> Dictionary:
	var out := {}
	if not wake_on(state):
		return out
	var fx: Dictionary = cfg().get("contain_fx", {})
	for id in Ancients.ids(state):
		if Ancients.stage(state, id) == STAGE_AWAKE and Ancients.at_war_with(state, id, eid):
			Research._merge(out, fx)
			break
	if in_league(state, eid):
		Research._merge(out, fx)
	return out


static func card_fx(state: GameState, eid: int, item: Dictionary, fx: Dictionary, added: Array[Dictionary]) -> void:
	var id := int(item.get("anc", -1))
	var a := Ancients.get_a(state, id)
	if a.is_empty():
		return
	match String(fx.get("act", "")):
		"contain":
			if not Ancients.at_war_with(state, id, eid) and dominion_of(state, eid) != id:
				Ancients.meet(state, id, eid, added)
				Ancients.declare_war(state, id, eid, "endiguement", added)
				Relics.touch(state)
		"dominion":
			if Ancients.stage(state, id) == STAGE_AWAKE:
				(a["dom"] as Dictionary)[eid] = state.tick
				Ancients.add_op(state, id, eid, 100)
				added.append(state.add_chronicle("%s devient un Dominion %s. Le tribut part chaque mois, avec une lettre de remerciement qu'on ne lit pas." % [
						state.get_empire(eid).display_name(), Crisis.de_name(Ancients.name_of(state, id))]))
		"refuse_dom":
			if Ancients.stage(state, id) == STAGE_AWAKE:
				if AncientsBridges.shield(state, id, eid):
					added.append(state.add_chronicle("%s refuse la soumission, sa relique-clé en main. %s grince, mais ne frappe pas." % [state.get_empire(eid).display_name(), Ancients.name_of(state, id)]))
					(a["sub_cd"] as Dictionary)[eid] = state.tick + 99999
				else:
					Ancients.declare_war(state, id, eid, "dominion", added)
		"side":
			choose_side(state, eid, int(fx.get("v", 0)), added)


static func fx_line(state: GameState, item: Dictionary, fx: Dictionary) -> String:
	var id := int(item.get("anc", -1))
	match String(fx.get("act", "")):
		"contain":
			return "guerre contre %s, +10 %% de dégâts tant qu'elle dure" % Ancients.name_of(state, id)
		"dominion":
			return "tribut de %d %% de l'énergie et du Savoir chaque mois, voix muette à l'Amphictyonie" % int(cfg()["tribute_pct"])
		"refuse_dom":
			return "guerre : ses flottes viennent prendre vos systèmes"
		"side":
			var v := int(fx.get("v", 0))
			if v == 0:
				return "Ligue des non-alignés (+10 % de dégâts si elle se forme autour de vous ou de votre Koinon)"
			return "protégé dix ans par elle, ennemi de l'autre, part du butin"
	return ""


static func fill(state: GameState, _eid: int, item: Dictionary, s: String) -> String:
	var id := int(item.get("anc", -1))
	var a := Ancients.get_a(state, id)
	var out := s.replace("{anc_why}", String(a.get("why", "")))
	out = out.replace("{anc_aid}", String(a.get("aid", "")))
	out = out.replace("{anc_tomb}", String(a.get("tomb_text", "")))
	if out.contains("{anc_rival}"):
		var h := heaven(state)
		var rv := -1
		if not h.is_empty():
			rv = int(h["a"]) if int(h["b"]) == id else int(h["b"])
		out = out.replace("{anc_rival}", Ancients.name_of(state, rv) if rv >= 0 else "sa rivale")
	return out


## Valeur pour l'IA : plier si la parvenue l'écrase, rejoindre l'Endiguement si elle est assez forte,
## le camp le plus fort dans la Guerre au ciel.
static func ai_value(state: GameState, eid: int, item: Dictionary, fx: Dictionary, temper: int) -> int:
	var id := int(item.get("anc", -1))
	var mine := bloc_power(state, eid)
	var theirs := maxi(1, Ancients.total_power(state, id))
	match String(fx.get("act", "")):
		"dominion":
			return 500 if mine * 100 < theirs * int(Ancients.data()["ai"]["demand_accept_ratio"]) else -300 - temper * 100
		"contain":
			return 300 + temper * 100 if mine * 100 >= theirs * 80 else -400
		"side":
			var h := heaven(state)
			if h.is_empty():
				return 0
			var v := int(fx.get("v", 0))
			var pa := Ancients.total_power(state, int(h["b"]))
			var pb := Ancients.total_power(state, int(h["a"]))
			if v == 0:
				return 100
			var mine_side := pa if v == 1 else pb
			var other := pb if v == 1 else pa
			return 250 + temper * 50 if mine_side > other * 3 / 2 else -100
	return 0


static func check_act(state: GameState, eid: int, act: String, x: int, s: String, n: int) -> String:
	match act:
		"free":
			if not (Ancients.get_a(state, x).get("dom", {}) as Dictionary).has(eid):
				return "vous n'êtes pas son Dominion"
			if Ancients.stage(state, x) != STAGE_DECADENT:
				return "elle est encore trop forte : attendez sa décadence"
			return ""
	return AncientsBridges.check_act(state, eid, act, x, s, n)


static func act(state: GameState, eid: int, act_id: String, x: int, s: String, n: int, added: Array[Dictionary]) -> void:
	match act_id:
		"free":
			(Ancients.get_a(state, x)["dom"] as Dictionary).erase(eid)
			added.append(state.add_chronicle("%s rompt avec %s décadente. Le tribut s'arrête ; la lettre de remerciement aussi." % [
					state.get_empire(eid).display_name(), Crisis.obj_name(Ancients.name_of(state, x))]))
		_:
			AncientsBridges.act(state, eid, act_id, x, s, n, added)


## Décisions de l'IA liées à l'Éveil : un Dominion se libère dès la décadence.
static func ai_think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	for id in Ancients.ids(state):
		if (Ancients.get_a(state, id).get("dom", {}) as Dictionary).has(e.id):
			AiPlayer._issue(ctx, SimCommands.anc_act(e.id, "free", id))


## Lignes de l'Éveil pour la fiche de l'écran Diplomatie (AncientsUi).
static func ui_lines(state: GameState, player: int, id: int) -> PackedStringArray:
	var out := PackedStringArray()
	var a := Ancients.get_a(state, id)
	match Ancients.stage(state, id):
		STAGE_NOTICE:
			out.append("Elle s'éveille dans %d mois. %s" % [maxi(0, int(a.get("wake_at", 0)) - state.tick) / 30, String(a.get("why", ""))])
		STAGE_AWAKE:
			out.append("Éveillée depuis %d ans. Dominions : %d. Décadence : %d / 100%s." % [(state.tick - int(a.get("woke", 0))) / 360, (a.get("dom", {}) as Dictionary).size(), int(a.get("decay", 0)),
					" (commence vingt ans après l'éveil)" if state.tick < int(a.get("woke", 0)) + int(cfg()["decay_after"]) else ""])
		STAGE_GUARDIAN:
			out.append("Gardienne : elle chasse la crise et se rendormira quand celle-ci sera vaincue.")
	if (a.get("dom", {}) as Dictionary).has(player):
		out.append("Vous êtes son Dominion : tribut de %d %% de votre énergie et de votre Savoir chaque mois, voix muette à l'Amphictyonie." % int(cfg()["tribute_pct"]))
	var h := heaven(state)
	if not h.is_empty() and _in_heaven(state, id):
		var side := int((h.get("sides", {}) as Dictionary).get(player, -1))
		out.append("Guerre au ciel en cours. Votre camp : %s." % ("neutre" + (" (Ligue des non-alignés)" if in_league(state, player) else "") if side == 0 else (Ancients.name_of(state, side) if side > 0 else "pas encore choisi")))
	if not (a.get("tombs", []) as Array).is_empty():
		out.append("Tombeaux encore fermés : %d (raser un tombeau avant son réveil l'empêche de s'ouvrir)." % (a["tombs"] as Array).size())
	return out


## Boutons de l'Éveil pour la fiche de l'écran Diplomatie (AncientsUi).
static func ui_buttons(state: GameState, player: int, id: int, emit: Callable) -> Array[Control]:
	var out: Array[Control] = []
	if (Ancients.get_a(state, id).get("dom", {}) as Dictionary).has(player):
		out.append(VassalUi._btn("Se libérer du Dominion", check_act(state, player, "free", id, "", -1), "Possible quand elle est décadente.",
				func() -> void: emit.call(SimCommands.anc_act(player, "free", id))))
	return out
