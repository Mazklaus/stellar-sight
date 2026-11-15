class_name MinorsBridges
extends RefCounted
## Ponts des peuples mineurs avec le reste du jeu (lot 3 de l'étude « Peuples mineurs ») :
## - Amphictyonie (prop. 27) : famille « Peuples mineurs » du Nomos : Non-ingérence (poste ouvert,
##   transfert de technologie et conquête de pré-spatiaux interdits) ou Exploitation (observation +50 %,
##   puis Égalité des échanges : transfert de technologie et commerce doublés). Conquérir le protégé d'un
##   membre est une infraction. Les mineurs n'ont pas de voix ; le Sénat de Tisseterre en prête à son suzerain.
## - Religion (prop. 28) : foi native ; prêcher ; la même foi donne de la faveur ; guerre sainte ; zèle
##   des Cendres ; les Pouffiks et le premier visiteur.
## - Espionnage (prop. 29) : Ingérence (voler de la faveur au suzerain), Pousser au raid, Infiltrer.
## - Commerce et frontières (prop. 30) : comptoir chez un spatial (faveur et énergie) ; leurs systèmes
##   sont des enclaves (Economy.check_colonize), Close s'ils sont hostiles (Borders.policy).
## - Anciennes et crises (prop. 31) : le Conservatoire aime les protecteurs et punit les conquérants des
##   pré-spatiaux ; au Front commun, les protégés envoient une escadre ; le Roi-Corsaire recrute les hostiles ;
##   Préscience de Quellis.
## - Héros, talents, victoires (prop. 32) : héros offert par un ami ; talents par couche d'espèce
##   (data/minors.json « talents ») ; systèmes des protégés comptés à moitié pour la domination.


static func data() -> Dictionary:
	return Minors.data()


static func bd() -> Dictionary:
	return data()["bridges"]


# --- Talents par couche d'espèce (prop. 32) ---------------------------------------------------------

## Talents de l'empire : ceux de son gouvernement et de son credo (valables pour les peuples créés).
static func talent(state: GameState, eid: int) -> Dictionary:
	var out := {}
	var e := state.get_empire(eid)
	if e == null or GameState.is_npc(eid):
		return out
	var sp: Dictionary = e.faction().get("species", {})
	var table: Dictionary = data().get("talents", {})
	for layer in ["gouvernement", "credo"]:
		var t: Dictionary = (table.get(layer, {}) as Dictionary).get(String(sp.get(layer, "")), {})
		for k in t:
			if k != "label" and k != "text":
				out[k] = t[k]
	return out


static func talent_lines(state: GameState, eid: int) -> Array:
	var out: Array = []
	var e := state.get_empire(eid)
	if e == null:
		return out
	var sp: Dictionary = e.faction().get("species", {})
	var table: Dictionary = data().get("talents", {})
	for layer in ["gouvernement", "credo"]:
		var t: Dictionary = (table.get(layer, {}) as Dictionary).get(String(sp.get(layer, "")), {})
		if not t.is_empty():
			out.append("Talent : %s. %s" % [String(t["label"]), String(t["text"])])
	return out


static func levy_pct(state: GameState, eid: int) -> int:
	return int(talent(state, eid).get("levy_pct", 100))


static func integ_pct(state: GameState, id: int, eid: int) -> int:
	var t := talent(state, eid)
	if t.has("integ_ruche_pct") and String(GameData.faction(Minors.species_id(state, id)).get("species", {}).get("gouvernement", "")) == "ruche":
		return int(t["integ_ruche_pct"])
	return 100


## Transfert de technologie : Raison (×2), Égalité des échanges (×2).
static func tech_x(state: GameState, eid: int) -> int:
	var x := int(talent(state, eid).get("tech_x", 1))
	if _equal(state):
		x *= 2
	return maxi(1, x)


## Accords commerciaux : Profit (×2), Égalité des échanges (×2).
static func trade_x(state: GameState, eid: int) -> int:
	var x := int(talent(state, eid).get("trade_x", 1))
	if _equal(state):
		x *= 2
	return maxi(1, x)


# --- Amphictyonie (prop. 27) ------------------------------------------------------------------------

static func _amph(state: GameState) -> bool:
	return state.amph_on and Amphictyony.founded(state)


static func _equal(state: GameState) -> bool:
	return _amph(state) and Amphictyony.level_sum(state, "minor_equal") > 0


static func post_banned(state: GameState, mode: String) -> bool:
	return mode == "ouvert" and _amph(state) and Amphictyony.banned(state, "minor_open_post")


static func accord_banned(state: GameState, key: String) -> bool:
	return key == "tech" and _amph(state) and Amphictyony.banned(state, "minor_tech")


static func post_pct(state: GameState) -> int:
	return Amphictyony.level_sum(state, "minor_post_pct") if _amph(state) else 0


static func war_banned(_state: GameState, _eid: int, _id: int) -> String:
	return ""  # la guerre est permise ; la conquête, elle, peut être une infraction


## Voix prêtées par le Sénat de Tisseterre à son suzerain (en %).
static func voix_pct(state: GameState, eid: int) -> int:
	if not Minors.enabled(state):
		return 0
	var n := 0
	for id in Minors.proteges_of(state, eid):
		if Minors.gift_def(state, id).has("voix"):
			@warning_ignore("integer_division")
			n += int(bd()["voix"]) / 10 * MinorsLife.gift_mult(state, id, eid)
	return n


# --- Religion (prop. 28) ----------------------------------------------------------------------------

static func minor_faith(state: GameState, id: int) -> String:
	var c: Colony = state.colonies.get(int(Minors.get_m(state, id).get("planet", -1)))
	return Faiths.majority(c) if c != null else ""


static func check_preach(state: GameState, eid: int, id: int) -> String:
	if not state.faith_on:
		return "pas de religions dans cette partie"
	var f := Faiths.state_faith(state, eid)
	if f == "":
		return "il vous faut une foi d'État"
	if not Minors.can_talk(state, id, eid):
		return "vous ne pouvez pas leur parler"
	if minor_faith(state, id) == f:
		return "ils partagent déjà votre foi"
	if int(state.get_empire(eid).resources.get("influence", 0)) < 30:
		return "il faut 30 influence"
	return ""


static func preach(state: GameState, eid: int, id: int, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	e.resources["influence"] = int(e.resources.get("influence", 0)) - 30
	var c: Colony = state.colonies.get(int(Minors.get_m(state, id)["planet"]))
	var f := Faiths.state_faith(state, eid)
	if c == null:
		return
	@warning_ignore("integer_division")
	c.faith[f] = mini(c.population, int(c.faith.get(f, 0)) + maxi(1, (c.population + 3) / 4))
	added.append(state.add_chronicle("Des missionnaires %s prêchent chez %s." % [Crisis.de_name(e.short_name()), Minors.name_of(state, id)], Espionage.private_to(state, [eid])))


# --- Commerce : comptoir chez un spatial (prop. 30) -------------------------------------------------

static func check_route(state: GameState, eid: int, id: int) -> String:
	if Minors.is_pre(state, id):
		return "seulement avec une cité-État spatiale"
	if MinorsLife.has_accord(state, id, eid, "route"):
		return ""
	if not Minors.tier_at_least(state, id, eid, "contact"):
		return "il faut 20 de faveur"
	if int(state.get_empire(eid).resources.get("influence", 0)) < 1:
		return "il faut 1 influence par mois"
	return ""


static func route(state: GameState, eid: int, id: int, added: Array[Dictionary]) -> void:
	var m := Minors.get_m(state, id)
	var acc := MinorsLife._acc(m, eid)
	if acc.has("route"):
		acc.erase("route")
		return
	acc["route"] = state.tick
	added.append(state.add_chronicle("%s ouvre un comptoir chez %s." % [state.get_empire(eid).display_name(), Minors.name_of(state, id)], Espionage.private_to(state, [eid])))


# --- Espionnage (prop. 29) --------------------------------------------------------------------------

static func infiltrated(state: GameState, id: int, eid: int) -> bool:
	return ((Minors.get_m(state, id).get("infil", {}) as Dictionary)).has(eid)


static func _pay(state: GameState, eid: int, cost: Dictionary) -> void:
	var e := state.get_empire(eid)
	for r in cost:
		e.resources[r] = int(e.resources.get(r, 0)) - int(cost[r])


static func _cost_why(state: GameState, eid: int, cost: Dictionary) -> String:
	var e := state.get_empire(eid)
	for r in cost:
		if int(e.resources.get(r, 0)) < int(cost[r]):
			return "il faut %d %s" % [int(cost[r]), GameData.resource_label(String(r)).to_lower()]
	return ""


static func _cd(state: GameState, id: int, eid: int, key: String) -> int:
	var ops: Dictionary = Minors.get_m(state, id).get("ops", {})
	return int((ops.get(eid, {}) as Dictionary).get(key, -1))


static func _set_cd(state: GameState, id: int, eid: int, key: String, days: int) -> void:
	var m := Minors.get_m(state, id)
	if not m.has("ops"):
		m["ops"] = {}
	if not (m["ops"] as Dictionary).has(eid):
		m["ops"][eid] = {}
	m["ops"][eid][key] = state.tick + days


static func check_op(state: GameState, eid: int, id: int, op: String, n: int) -> String:
	var od: Dictionary = bd().get(op, {})
	if not Minors.in_contact(state, id, eid):
		return "vous ne les connaissez pas"
	match op:
		"meddle":
			var s := Minors.suzerain(state, id)
			if s < 0 or s == eid:
				return "il faut un suzerain à qui voler la faveur"
		"incite":
			if Minors.is_pre(state, id) or String(Minors.get_m(state, id).get("att", "")) != "hostile" or Minors.fleets_of(state, id).is_empty():
				return "seulement un spatial hostile qui a une flotte"
			var t := state.get_empire(n)
			if t == null or t.eliminated or GameState.is_npc(n) or n == eid:
				return "choisissez un rival"
			if MinorsLife._raid_target(state, id, int(data()["hostile"]["raid_jumps"]) + 2, n) < 0:
				return "aucune colonie de ce rival à leur portée"
		"infiltrate":
			if not Minors.is_pre(state, id):
				return "seulement chez un pré-spatial"
			if infiltrated(state, id, eid):
				return "déjà infiltré"
		_:
			return "opération inconnue"
	if state.tick < _cd(state, id, eid, op):
		return "pas avant %d mois" % ((_cd(state, id, eid, op) - state.tick) / 30 + 1)
	var c: Dictionary = od.get("cost", {})
	var cost := c.duplicate()
	@warning_ignore("integer_division")
	for r in cost:
		cost[r] = int(cost[r]) * maxi(10, 100 + Research.fx_int(state, eid, "spy_cost_pct")) / 100
	return _cost_why(state, eid, cost)


static func op(state: GameState, eid: int, id: int, op_id: String, n: int, added: Array[Dictionary]) -> void:
	var od: Dictionary = bd()[op_id]
	var cost: Dictionary = (od.get("cost", {}) as Dictionary).duplicate()
	@warning_ignore("integer_division")
	for r in cost:
		cost[r] = int(cost[r]) * maxi(10, 100 + Research.fx_int(state, eid, "spy_cost_pct")) / 100
	_pay(state, eid, cost)
	var m := Minors.get_m(state, id)
	var e := state.get_empire(eid)
	match op_id:
		"meddle":
			_set_cd(state, id, eid, op_id, int(od["cd_days"]))
			var s := Minors.suzerain(state, id)
			var v := mini(int(od["fav"]), Minors.fav(state, id, s))
			(m["fav"] as Dictionary)[s] = Minors.fav(state, id, s) - v
			(m["fav"] as Dictionary)[eid] = clampi(Minors.fav(state, id, eid) + v, 0, int(data()["favor"]["max"]))
			var caught := Minors._h(state, ["ingerence", id, eid, state.tick]) % 100 < int(od["discovery_pct"]) + Research.fx_int(state, eid, "spy_discovery_pct")
			if caught:
				Diplomacy.remember(state, s, eid, "ingerence_mineur")
				added.append(state.add_chronicle("Ingérence démasquée : %s intriguait chez %s contre %s." % [e.display_name(), Minors.name_of(state, id), state.get_empire(s).display_name()],
						Espionage.private_to(state, [eid, s])))
			else:
				added.append(state.add_chronicle("Vos agents détournent la faveur %s : %d points de moins pour %s." % [Crisis.de_name(Minors.name_of(state, id)), v,
						state.get_empire(s).display_name()], Espionage.private_to(state, [eid])))
		"incite":
			_set_cd(state, id, eid, op_id, int(od["cd_days"]))
			m["incite"] = n
			m.erase("raid")
			var sid := MinorsLife._raid_target(state, id, int(data()["hostile"]["raid_jumps"]) + 2, n)
			if sid >= 0:
				for f in Minors.fleets_of(state, id):
					var r := Fleets.plan_route(state, f, sid)
					if not r.is_empty():
						f.system_id = int(r["system"])
						f.path.assign(r["path"])
						f.progress = int(r["progress"])
				m["raid"] = {"until": state.tick + int(data()["hostile"]["raid_days"]), "sid": sid}
				m.erase("incite")
				added.append(state.add_chronicle("%s lance un raid sur %s. Des rumeurs parlent d'or étranger." % [Minors.name_of(state, id), state.galaxy.systems[sid].system_name],
						Espionage.private_to(state, [eid, n], sid)))
		"infiltrate":
			if not m.has("infil"):
				m["infil"] = {}
			m["infil"][eid] = state.tick
			added.append(state.add_chronicle("Vos agents vivent désormais parmi %s, déguisés en marchands de tapis." % Minors.name_of(state, id), Espionage.private_to(state, [eid])))


# --- Héros, menace (prop. 32) -----------------------------------------------------------------------

static func check_hero(state: GameState, eid: int, id: int) -> String:
	if not Minors.tier_at_least(state, id, eid, "ami"):
		return "il faut leur amitié"
	if ((Minors.get_m(state, id).get("given", {}) as Dictionary)).has("h%d" % eid):
		return "ils vous ont déjà offert un héros"
	return _cost_why(state, eid, bd()["hero_cost"])


static func hero(state: GameState, eid: int, id: int, added: Array[Dictionary]) -> void:
	_pay(state, eid, bd()["hero_cost"])
	var m := Minors.get_m(state, id)
	(m["given"] as Dictionary)["h%d" % eid] = 1
	var cls := {"militaire": "stratege", "economique": "intendant", "savant": "intendant", "foi": "orateur", "diplomatique": "orateur", "expansion": "intendant"}
	var o := String(m.get("orientation", Minors.kind_def(String(m["kind"])).get("orientation", "economique")))
	var cand := Heroes.make_candidate(state, eid, String(cls.get(o, "orateur")), ["mineur", id, eid], Minors.species_id(state, id))
	var hid := Heroes.recruit(state, eid, cand)
	var h: Dictionary = state.heroes.get(hid, {})
	if not h.is_empty():
		h["lvl"] = 2
	added.append(state.add_chronicle("%s offre à %s un des siens : %s." % [Minors.name_of(state, id), state.get_empire(eid).display_name(), String(h.get("name", "un héros"))],
			Espionage.private_to(state, [eid])))


static func check_threat(state: GameState, eid: int, id: int) -> String:
	if int(talent(state, eid).get("threat", 0)) <= 0:
		return "réservé aux hordes"
	var td: Dictionary = bd()["threat"]
	if state.tick < _cd(state, id, eid, "threat"):
		return "pas avant %d mois" % ((_cd(state, id, eid, "threat") - state.tick) / 30 + 1)
	var theirs := maxi(Minors.power(state, id), Combat.garrison(state, Minors.system_of(state, id)) * 10)
	if Ancients.empire_power(state, eid) < theirs * int(td["ratio"]):
		return "votre flotte doit être %d fois plus forte que la leur" % int(td["ratio"])
	return ""


static func threat(state: GameState, eid: int, id: int, added: Array[Dictionary]) -> void:
	var td: Dictionary = bd()["threat"]
	_set_cd(state, id, eid, "threat", int(td["cd_days"]))
	var m := Minors.get_m(state, id)
	(m["fav"] as Dictionary)[eid] = clampi(Minors.fav(state, id, eid) + int(td["fav"]), 0, int(data()["favor"]["max"]))
	added.append(state.add_chronicle("%s fait défiler sa flotte au-dessus %s. Ils trouvent soudain beaucoup de qualités à la Horde." % [
			state.get_empire(eid).display_name(), Crisis.de_name(Minors.name_of(state, id))], Espionage.private_to(state, [eid])))


# --- Victoires (prop. 32) ---------------------------------------------------------------------------

## Systèmes des protégés comptés à moitié pour la domination.
static func domination_bonus(state: GameState, eid: int) -> int:
	if not Minors.enabled(state):
		return 0
	@warning_ignore("integer_division")
	return Minors.proteges_of(state, eid).size() / maxi(1, int(bd()["domination_div"]))


# --- Anciennes et crises (prop. 31) -----------------------------------------------------------------

static func _ylm(state: GameState) -> int:
	return Ancients.id_of_kind(state, "conservatoire") if Ancients.enabled(state) else -1


## Le Conservatoire aime ceux qui protègent les pré-spatiaux (astéroïde détruit, nouveau protégé).
static func on_protect(state: GameState, id: int, eid: int, _added: Array[Dictionary]) -> void:
	var y := _ylm(state)
	if y >= 0 and Minors.is_pre(state, id):
		Ancients.add_op(state, y, eid, int(bd()["ylm_protect"]))


## Préscience de Quellis : les suzerains qui sentent venir la crise.
static func presage_seers(state: GameState) -> Array[int]:
	var out: Array[int] = []
	if not Minors.enabled(state):
		return out
	for id in Minors.ids(state):
		var s := Minors.suzerain(state, id)
		if s >= 0 and Minors.gift_def(state, id).has("presage") and not out.has(s):
			out.append(s)
	return out


static func presage_days(state: GameState, seers: Array[int]) -> int:
	for s in presage_seers(state):
		if seers.has(s):
			return int(bd()["presage_days"])
	return 0


static func omen(state: GameState, eid: int) -> String:
	if presage_seers(state).has(eid):
		return "Les devins de Quellis, protégés de {empire}, se réveillent en hurlant : quelque chose approche, du côté de {origin}."
	return ""


## Au Front commun contre la crise, chaque protégé spatial envoie une escadre à son suzerain (une fois
## par crise) ; le Roi-Corsaire recrute les spatiaux hostiles.
static func _crisis(state: GameState, id: int, m: Dictionary, added: Array[Dictionary]) -> void:
	if not Crisis.enabled(state) or not Crisis.active(state):
		return
	var since := int(Crisis.cur(state).get("since", 0))
	if int(m.get("front", -1)) == since:
		return
	var s := int(m["suz"])
	if Crisis.kind(state) == "corsaire" and String(m.get("att", "")) == "hostile" and not Minors.is_pre(state, id) and s < 0:
		m["front"] = since
		for f in Minors.fleets_of(state, id):
			f.owner = GameState.CRISIS_ID
		m["fleets"] = []
		added.append(state.add_chronicle("Le Roi-Corsaire recrute la flotte %s. Ils n'aimaient personne ; maintenant, ils sont payés pour." % Crisis.de_name(Minors.name_of(state, id))))
		return
	if s < 0 or Minors.is_pre(state, id) or not Crisis.in_front(state, s):
		return
	m["front"] = since
	var cap := FactionTraits.capital_system(state, s)
	if cap < 0:
		return
	var ships: Array = data()["space"]["ships"]
	var f2 := state.spawn_ship(s, String(ships[0]), cap)
	@warning_ignore("integer_division")
	var target := Minors.fleet_power_target(state) / 2
	var guard := 0
	while Combat.fleet_power(f2) < target and guard < 20:
		guard += 1
		f2.add_ship(String(ships[guard % ships.size()]), -1, -1)
	f2.fleet_name = "Renforts %s" % Crisis.de_name(Minors.short_of(state, id))
	added.append(state.add_chronicle("%s envoie des renforts à %s contre la crise." % [Minors.name_of(state, id), state.get_empire(s).display_name()], Espionage.private_to(state, [s])))


# --- Points d'entrée de Minors ----------------------------------------------------------------------

static func month(state: GameState, id: int, m: Dictionary, added: Array[Dictionary]) -> void:
	# Même foi : faveur chaque mois (prop. 28) ; comptoir : faveur et énergie (prop. 30).
	var mf := minor_faith(state, id) if state.faith_on else ""
	for eid in Minors._contact_ids(m):
		var e := state.get_empire(eid)
		if e == null or e.eliminated:
			continue
		if mf != "" and mf != Faiths.NATIVE and Faiths.state_faith(state, eid) == mf:
			Minors.add_fav(state, id, eid, int(bd()["same_faith"]) * int(talent(state, eid).get("faith_x", 1)))
		if MinorsLife.has_accord(state, id, eid, "route"):
			if int(e.resources.get("influence", 0)) < 1:
				(m["acc"][eid] as Dictionary).erase("route")
				continue
			e.resources["influence"] = int(e.resources.get("influence", 0)) - 1
			Minors.add_fav(state, id, eid, int(bd()["trade_route"]))
			e.resources["energy"] = int(e.resources.get("energy", 0)) + int(bd()["trade_energy"]) * trade_x(state, eid)
	_crisis(state, id, m, added)


## Cadeaux de suzerain du lot 3 : zèle des Cendres (chaque année).
static func suz_gift(state: GameState, id: int, m: Dictionary, s: int, _added: Array[Dictionary]) -> void:
	var gd := Minors.gift_def(state, id)
	if gd.has("zeal") and state.faith_on:
		@warning_ignore("integer_division")
		if (state.tick / 30 + id) % 12 == 0:
			var f := Faiths.state_faith(state, s)
			if f != "":
				FaithWars.add_zeal(state, f, int(gd["zeal"]) * MinorsLife.gift_mult(state, id, s))
	if int(m.get("suz", -1)) == s and Minors.is_pre(state, id) and int(m.get("ylm_noted", -1)) != s:
		m["ylm_noted"] = s
		on_protect(state, id, s, [])


static func on_gift(_state: GameState, _id: int, _eid: int) -> void:
	pass


## Guerre déclarée : une guerre sainte si leur foi n'est pas la vôtre.
static func on_war(state: GameState, eid: int, id: int, added: Array[Dictionary]) -> void:
	if not state.faith_on:
		return
	var f := Faiths.state_faith(state, eid)
	var mf := minor_faith(state, id)
	if f != "" and mf != f:
		FaithWars.add_zeal(state, f, 5)
		added.append(state.add_chronicle("%s présente sa guerre contre %s comme une guerre sainte. Les prêcheurs approuvent ; les intéressés, moins." % [
				state.get_empire(eid).display_name(), Minors.name_of(state, id)]))


## Conquête : infraction à la Non-ingérence (pré-spatial), protégé d'un membre, colère du Conservatoire.
static func on_conquest(state: GameState, id: int, eid: int, _added: Array[Dictionary]) -> void:
	var pre := Minors.is_pre(state, id)
	if _amph(state):
		if pre:
			Amphictyony.breach(state, eid, "minor_conquest")
		var s := Minors.suzerain(state, id)
		if s >= 0 and s != eid and Amphictyony.is_member(state, s) and Amphictyony.is_member(state, eid) and not Amphictyony.outlaw(state, eid):
			Amphictyony._make_outlaw(state, eid, "minor_protege")
	var y := _ylm(state)
	if y >= 0 and pre:
		Ancients.add_op(state, y, eid, int(bd()["ylm_conquest"]))


static func check_act(state: GameState, eid: int, act: String, x: int, s: String, n: int) -> String:
	match act:
		"preach":
			return check_preach(state, eid, x)
		"route":
			return check_route(state, eid, x)
		"meddle", "incite", "infiltrate":
			return check_op(state, eid, x, act, n)
		"hero":
			return check_hero(state, eid, x)
		"threat":
			return check_threat(state, eid, x)
	return "action inconnue"


static func act(state: GameState, eid: int, act_id: String, x: int, _s: String, n: int, added: Array[Dictionary]) -> void:
	match act_id:
		"preach":
			preach(state, eid, x, added)
		"route":
			route(state, eid, x, added)
		"meddle", "incite", "infiltrate":
			op(state, eid, x, act_id, n, added)
		"hero":
			hero(state, eid, x, added)
		"threat":
			threat(state, eid, x, added)


# --- IA ---------------------------------------------------------------------------------------------

static func ai_think(ctx: Dictionary, met: Array[int]) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	for id in met:
		if Minors.tier_at_least(state, id, e.id, "ami") and AiPlayer._issue(ctx, SimCommands.min_act(e.id, "hero", id)):
			AiPlayer._intent(ctx, "Accueille un héros %s" % Crisis.de_name(Minors.short_of(state, id)))
			return
		if Minors.tier_at_least(state, id, e.id, "contact") and not MinorsLife.has_accord(state, id, e.id, "route") and int(e.resources.get("influence", 0)) > 80:
			if AiPlayer._issue(ctx, SimCommands.min_act(e.id, "route", id)):
				return
		if AiPlayer._issue(ctx, SimCommands.min_act(e.id, "threat", id)):
			return


# --- Interface --------------------------------------------------------------------------------------

static func ui_lines(state: GameState, player: int, id: int) -> Array:
	var out: Array = []
	if state.faith_on:
		var mf := minor_faith(state, id)
		out.append("Foi : %s." % ("native" if mf == Faiths.NATIVE or mf == "" else String(Faiths.faith(state, mf).get("name", mf))))
	if infiltrated(state, id, player):
		out.append("Vos agents vivent parmi eux.")
	if MinorsLife.has_accord(state, id, player, "route"):
		out.append("Comptoir ouvert : +%d de faveur et +%d énergie par mois." % [int(bd()["trade_route"]), int(bd()["trade_energy"]) * trade_x(state, player)])
	return out


static func ui_buttons(state: GameState, player: int, id: int, emit: Callable) -> Array:
	var out: Array = []
	if state.faith_on:
		out.append(VassalUi._btn("Prêcher (30 influence)", check_act(state, player, "preach", id, "", -1), "Des missionnaires convertissent une partie du peuple à votre foi d'État ; la même foi donne de la faveur chaque mois.",
				func() -> void: emit.call(SimCommands.min_act(player, "preach", id))))
	if not Minors.is_pre(state, id):
		var on := MinorsLife.has_accord(state, id, player, "route")
		out.append(VassalUi._btn("%sComptoir (1 influence/mois)" % ("✓ " if on else ""), check_act(state, player, "route", id, "", -1),
				"Une route marchande vers leur cité : faveur et énergie chaque mois." + (" Cliquer le ferme." if on else ""),
				func() -> void: emit.call(SimCommands.min_act(player, "route", id))))
	out.append(VassalUi._btn("Ingérence (40 influence)", check_act(state, player, "meddle", id, "", -1), "Vos agents volent 15 de faveur au suzerain. Une chance sur quatre d'être démasqué.",
			func() -> void: emit.call(SimCommands.min_act(player, "meddle", id))))
	if Minors.is_pre(state, id) and not infiltrated(state, id, player):
		out.append(VassalUi._btn("Infiltrer (30 influence, 50 savoir)", check_act(state, player, "infiltrate", id, "", -1), "Des agents déguisés : vous pouvez leur parler et signer des accords sans vous révéler.",
				func() -> void: emit.call(SimCommands.min_act(player, "infiltrate", id))))
	if String(Minors.get_m(state, id).get("att", "")) == "hostile" and not Minors.is_pre(state, id):
		var target := -1
		for e in state.empires:
			if e.id != player and not e.eliminated and check_act(state, player, "incite", id, "", e.id) == "":
				target = e.id
				break
		var t := target
		out.append(VassalUi._btn("Pousser au raid%s (60 influence)" % ((" contre %s" % state.get_empire(t).short_name()) if t >= 0 else ""),
				check_act(state, player, "incite", id, "", t) if t >= 0 else "aucun rival à leur portée", "Un peu d'or, et leur flotte va harceler un rival.",
				func() -> void: emit.call(SimCommands.min_act(player, "incite", id, "", t))))
	out.append(VassalUi._btn("Demander un héros (50 influence)", check_act(state, player, "hero", id, "", -1), "Un ami peut vous offrir un des siens.",
			func() -> void: emit.call(SimCommands.min_act(player, "hero", id))))
	if int(talent(state, player).get("threat", 0)) > 0:
		out.append(VassalUi._btn("Menacer", check_act(state, player, "threat", id, "", -1), "Horde : +15 de faveur par la peur, si votre flotte est trois fois plus forte.",
				func() -> void: emit.call(SimCommands.min_act(player, "threat", id))))
	return out
