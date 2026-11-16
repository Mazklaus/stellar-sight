class_name Private
extends RefCounted
## Économie privée à la Distant Worlds 2 (étude « Économie privée », 2026-11-16 ; data/private.json).
## Chaque empire a un secteur privé, avec sa propre caisse (capital), à part du Trésor : il vit de
## l'activité de la population, d'une part des routes commerciales, de ses stations minières sous
## licence, de ses stations touristiques, de ses filiales à l'étranger ; il paie la construction et
## l'entretien de ses cargos, paquebots et stations ; l'État prélève un impôt sur ses bénéfices (selon
## le cran de la fiscalité). Le joueur oriente (licences, commandes, subventions, chartes, lois), il ne
## pilote pas : le privé investit seul selon la confiance des investisseurs. Compagnies nommées (siège,
## prospérité, charte, dirigeant, lobbying, actions), filiales chez les partenaires, nationalisation,
## expropriation, confiscation ; cargos perdus aux pirates, zones militaires, réquisition, ravitaillement
## sous contrat. Syndicats du crime, espionnage industriel et ponts : PrivateBridges.
##
## Réglage « Économie privée » : Complète (défaut d'une nouvelle partie), Simple (caisse, impôt,
## licences, stations touristiques, cargos et paquebots abstraits) ou Désactivée (state.private vide).
## Sans l'option (tests, bancs) : désactivée, donc l'économie d'avant.
##
## État : state.private = {"mode", "e": {"empire": P}, "st": {"planète": S}, "co": {"id": C}, "cid",
##  "br": {"planète": B}, "zone": {"système": empire}, "crime": {"système": {"o", "t"}}, "slow": {"système": 1},
##  "exp": {"origine>hôte": fin du motif}, "cr": {"empire": fin de la comptabilité créative},
##  "mk": {"vainqueur>vaincu": fin du traité d'ouverture des marchés}, "hx": {clé: jour} (ponts : hauts faits, cour)}.
## P = {"cap", "conf", "cargos", "liners", "q": [file privée], "to": {ressource: n} (versé à l'État
##  au prochain bilan), "cost" (énergie payée par l'État), "rev": {poste: n}, "exp": {poste: n},
##  "profit", "tax", "sub", "sub_day", "loss", "req", "reqpay", "contract", "sup", "focus", "lic": [planètes],
##  "nat" (fin du malus de nationalisation), "pb": {"planète": bâtiment}, "orders": [commandes de vaisseaux],
##  "cr_day", "fx" (empreinte des effets), "tour", "block": [systèmes interdits aux mines spontanées]}.
## S = {"o": empire, "k": "mine"|"resort", "sid", "c": compagnie (-1), "t": jour}.
## C = {"id", "o", "n", "sec", "hq", "pr", "ch", "ch_day", "dir": {"name", "portrait", "trait"}, "nat",
##  "sh": {"empire": dixièmes}, "low", "born", "house", "lob"}.  B = {"c", "o", "t"}.
## Toutes les clés de dictionnaire sont des chaînes (la sauvegarde JSON les rend ainsi).

const LAYERS := ["gouvernement", "credo"]
const YEAR := 360

static var _talent_cache := {}


static func data() -> Dictionary:
	return GameData.private_eco()


static func mode_defs() -> Array:
	return data().get("modes", [])


static func default_mode() -> String:
	return String(data().get("default_mode", "complete"))


static func cfg(section: String) -> Dictionary:
	return data().get(section, {})


static func c_int(section: String, key: String) -> int:
	return int(cfg(section).get(key, 0))


static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "private"] + parts))


static func _month() -> int:
	return int(GameData.rules()["month_days"])


# --- Réglage, sauvegarde -----------------------------------------------------------------------

static func mode(state: GameState) -> String:
	return String(state.private.get("mode", "desactivee"))


static func enabled(state: GameState) -> bool:
	return not state.private.is_empty()


## Mode complet : compagnies, filiales, cargos vulnérables, réquisition, crime, ponts.
static func full(state: GameState) -> bool:
	return mode(state) == "complete"


static func worth_saving(state: GameState) -> bool:
	return not state.private.is_empty()


static func setup(state: GameState, mode_id: String) -> void:
	state.private = {}
	var ok := false
	for m: Dictionary in mode_defs():
		if String(m["id"]) == mode_id:
			ok = true
	if not ok or mode_id == "desactivee":
		return
	state.private = {"mode": mode_id, "e": {}, "st": {}, "co": {}, "cid": 1, "br": {}, "zone": {}, "crime": {},
			"slow": {}, "exp": {}, "cr": {}, "mk": {}, "hx": {}}
	for e in state.empires:
		if applies(state, e.id):
			_w(state, e.id)


static func to_dict(state: GameState) -> Dictionary:
	return Ancients._sorted(state.private)


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.private = {}
	if d.is_empty():
		return
	state.private = GameData._to_ints(d.duplicate(true))


# --- Talents -----------------------------------------------------------------------------------

static func talent(state: GameState, eid: int) -> Dictionary:
	var e := state.get_empire(eid)
	if e == null or e.is_npc():
		return {}
	var ck := "%s:%d" % [e.faction_id, GameData.factions_gen]
	if _talent_cache.has(ck):
		return _talent_cache[ck]
	var out := {}
	var table: Dictionary = data().get("talents", {})
	for layer in LAYERS:
		var t: Dictionary = (table.get(layer, {}) as Dictionary).get(Events.layer_value(state, eid, layer), {})
		for k in t:
			if k == "label" or k == "text":
				continue
			var v: Variant = t[k]
			out[k] = v if v is bool else int(out.get(k, 0)) + int(v)
	_talent_cache[ck] = out
	return out


static func talent_labels(state: GameState, eid: int) -> Array:
	var e := state.get_empire(eid)
	var out := []
	if e == null or e.is_npc():
		return out
	var table: Dictionary = data().get("talents", {})
	for layer in LAYERS:
		var t: Dictionary = (table.get(layer, {}) as Dictionary).get(Events.layer_value(state, eid, layer), {})
		if not t.is_empty():
			out.append([String(t["label"]), String(t["text"])])
	return out


# --- Lecture -----------------------------------------------------------------------------------

## L'empire a-t-il un secteur privé ? (pas de PNJ, pas de ruche : « rien n'est privé »)
static func applies(state: GameState, eid: int) -> bool:
	if state.private.is_empty():
		return false
	var e := state.get_empire(eid)
	if e == null or e.is_npc() or e.eliminated:
		return false
	return not bool(talent(state, eid).get("no_private", false))


static func entry(state: GameState, eid: int) -> Dictionary:
	if state.private.is_empty():
		return {}
	return (state.private["e"] as Dictionary).get(str(eid), {})


static func _w(state: GameState, eid: int) -> Dictionary:
	var all: Dictionary = state.private["e"]
	if not all.has(str(eid)):
		var st: Dictionary = cfg("start")
		var cols := 0
		for c in colonies_of(state, eid):
			if c.is_colony():
				cols += 1
		all[str(eid)] = {"cap": int(st["capital"]), "conf": int(st["confidence"]), "cargos": maxi(1, cols * int(st["cargos_per_colony"])),
				"liners": 0, "q": [], "to": {}, "cost": 0, "rev": {}, "exp": {}, "profit": 0, "tax": 0, "sub": 0, "sub_day": -100000,
				"loss": 0, "req": 0, "reqpay": 1, "contract": 0, "sup": 0, "focus": "", "lic": [], "nat": 0, "pb": {}, "orders": [],
				"cr_day": -100000, "fx": "", "tour": 0, "block": []}
	return all[str(eid)]


static func capital(state: GameState, eid: int) -> int:
	return int(entry(state, eid).get("cap", 0))


static func confidence(state: GameState, eid: int) -> int:
	return int(entry(state, eid).get("conf", 0))


static func colonies_of(state: GameState, eid: int) -> Array[Colony]:
	var out: Array[Colony] = []
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == eid and c.is_established():
			out.append(c)
	return out


static func stations_of(state: GameState, eid: int, kind := "") -> Array[int]:
	var out: Array[int] = []
	if state.private.is_empty():
		return out
	var st: Dictionary = state.private["st"]
	var keys := st.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	for k in keys:
		var s: Dictionary = st[k]
		if int(s["o"]) == eid and (kind == "" or String(s["k"]) == kind):
			out.append(int(k))
	return out


static func station(state: GameState, pid: int) -> Dictionary:
	if state.private.is_empty():
		return {}
	return (state.private["st"] as Dictionary).get(str(pid), {})


static func station_at(state: GameState, sid: int, kind: String) -> int:
	if state.private.is_empty():
		return -1
	for k in state.private["st"]:
		var s: Dictionary = state.private["st"][k]
		if int(s["sid"]) == sid and String(s["k"]) == kind:
			return int(k)
	return -1


static func queued(state: GameState, eid: int, kind: String, key := -1) -> bool:
	for it: Dictionary in entry(state, eid).get("q", []):
		if String(it["k"]) == kind and (key < 0 or int(it.get("pid", it.get("sid", -1))) == key):
			return true
	return false


static func in_zone(state: GameState, sid: int) -> bool:
	return not state.private.is_empty() and (state.private["zone"] as Dictionary).has(str(sid))


static func slowed(state: GameState, sid: int) -> bool:
	return not state.private.is_empty() and (state.private["slow"] as Dictionary).has(str(sid))


## Un jour de chantier sur quatre est perdu dans un système lointain mal desservi par le fret (prop. 8).
static func skip_day(state: GameState, sid: int) -> bool:
	@warning_ignore("integer_division")
	return slowed(state, sid) and posmod(state.tick, maxi(2, 100 / maxi(1, c_int("cargo", "slow_pct")))) == 0


static func planned(state: GameState, eid: int) -> bool:
	return state.politics_on and Laws.is_enacted(state, eid, "economie_planifiee")


static func laissez_faire(state: GameState, eid: int) -> bool:
	return state.politics_on and Laws.is_enacted(state, eid, "laissez_faire")


## Dirigisme (prop. 29) : commandes d'État -25 %, subventions deux fois plus rassurantes.
static func dirigisme(state: GameState, eid: int) -> bool:
	return state.politics_on and Laws.is_enacted(state, eid, "dirigisme")


static func order_price(state: GameState, eid: int) -> int:
	@warning_ignore("integer_division")
	var p := item_cost("mine") * c_int("order", "energy_pct") / 100
	@warning_ignore("integer_division")
	return p * 75 / 100 if dirigisme(state, eid) else p


# --- Besoins : fret, passagers ------------------------------------------------------------------

static func cargo_need(state: GameState, eid: int) -> int:
	var n := 0
	for c in colonies_of(state, eid):
		if c.is_colony():
			n += 1
	n += Trade.sent_by(state, eid).size()
	@warning_ignore("integer_division")
	return maxi(1, n / 2 + stations_of(state, eid).size())


static func liner_need(state: GameState, eid: int) -> int:
	var n := 0
	for c in colonies_of(state, eid):
		if c.is_colony():
			n += 1
	@warning_ignore("integer_division")
	return maxi(1, n / maxi(1, c_int("liner", "per_colonies")) + stations_of(state, eid, "resort").size())


static func usable_cargos(state: GameState, eid: int) -> int:
	var en := entry(state, eid)
	return maxi(0, int(en.get("cargos", 0)) - int(en.get("req", 0)))


## Fret disponible en % du besoin (au plus 100).
static func freight_pct(state: GameState, eid: int) -> int:
	@warning_ignore("integer_division")
	return mini(100, usable_cargos(state, eid) * 100 / maxi(1, cargo_need(state, eid)))


static func liner_pct(state: GameState, eid: int) -> int:
	@warning_ignore("integer_division")
	return mini(100, int(entry(state, eid).get("liners", 0)) * 100 / maxi(1, liner_need(state, eid)))


## Migration : sauts de plus quand les paquebots suffisent (prop. 12).
static func migration_bonus(state: GameState, eid: int) -> int:
	if state.private.is_empty():
		return 0
	return int(entry(state, eid).get("mig", 0))  # calculé au bilan du mois


# --- Taux, effets ------------------------------------------------------------------------------

static func tax_rate(state: GameState, eid: int) -> int:
	var t := "normal"
	if Finance.applies(state, eid):
		t = Finance.tax(state, eid)
	var r := int((cfg("tax")["rates"] as Dictionary).get(t, 30))
	if laissez_faire(state, eid):
		r += int(cfg("tax").get("laissez_faire", 0))
	return clampi(r, 0, 90)


static func invest_pct(state: GameState, eid: int) -> int:
	var t := Finance.tax(state, eid) if Finance.applies(state, eid) else "normal"
	return int((cfg("tax")["invest_pct"] as Dictionary).get(t, 100))


static func sector_def(id: String) -> Dictionary:
	for s: Dictionary in cfg("companies").get("sectors", []):
		if String(s["id"]) == id:
			return s
	return {}


static func charter_def(id: String) -> Dictionary:
	for s: Dictionary in cfg("charters").get("list", []):
		if String(s["id"]) == id:
			return s
	return {}


static func trait_def(id: String) -> Dictionary:
	for s: Dictionary in cfg("directors").get("traits", []):
		if String(s["id"]) == id:
			return s
	return {}


## Effets au format des technologies (fusionnés dans Research.effects) : secteurs des compagnies
## prospères (doublés sous monopole), chartes, réquisition.
static func effects(state: GameState, eid: int) -> Dictionary:
	var out := {}
	if not applies(state, eid):
		return out
	var cc: Dictionary = cfg("companies")
	for c in companies_of(state, eid):
		var ch := String(c.get("ch", ""))
		if int(c["pr"]) >= int(cc["bonus_from"]):
			var fx: Dictionary = sector_def(String(c["sec"])).get("fx", {})
			Research._merge(out, fx.duplicate(true))
			if ch == "monopole":
				Research._merge(out, fx.duplicate(true))
		if ch != "":
			Research._merge(out, (charter_def(ch).get("fx", {}) as Dictionary).duplicate(true))
	if int(entry(state, eid).get("req", 0)) > 0:
		Research._merge(out, (cfg("requisition")["fx"] as Dictionary).duplicate(true))
	return out


static func _fx_sig(state: GameState, eid: int) -> String:
	var parts := PackedStringArray()
	var cc: Dictionary = cfg("companies")
	for c in companies_of(state, eid):
		parts.append("%s:%d:%s" % [String(c["sec"]), 1 if int(c["pr"]) >= int(cc["bonus_from"]) else 0, String(c.get("ch", ""))])
	parts.append("r%d" % (1 if int(entry(state, eid).get("req", 0)) > 0 else 0))
	return ",".join(parts)


static func empire_stability_parts(state: GameState, eid: int) -> Array:
	var out := []
	if not applies(state, eid):
		return out
	for c in companies_of(state, eid):
		if String(c.get("ch", "")) == "monopole":
			out.append(["Monopole : %s" % String(c["n"]), int(charter_def("monopole").get("stability", 0))])
	return out


static func system_stability_parts(state: GameState, sid: int) -> Array:
	var out := []
	if state.private.is_empty() or not full(state):
		return out
	if (state.private["co"] as Dictionary).is_empty():
		return out
	for c in all_companies(state):
		if int(c["hq"]) == sid and not (c.get("dir", {}) as Dictionary).is_empty():
			var v := int(trait_def(String(c["dir"].get("trait", ""))).get("stability", 0))
			if v != 0:
				out.append(["Dirigeant philanthrope (%s)" % String(c["n"]), v])
	return out


## Ce que le privé verse à l'État au bilan (impôt, loyers, livraisons des mines, lobbying…).
static func to_state(state: GameState, eid: int) -> Dictionary:
	return entry(state, eid).get("to", {})


## Ce que l'État paie au privé chaque mois (indemnités, contrats de ravitaillement).
static func state_cost(state: GameState, eid: int) -> int:
	return int(entry(state, eid).get("cost", 0))


# --- Mois --------------------------------------------------------------------------------------

static func daily(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if state.private.is_empty():
		return added
	if state.tick % _month() != 0:
		return added
	_conquests(state, added)
	var slow := {}
	for e in state.empires:
		if e.is_npc():
			continue
		if not applies(state, e.id):
			if (state.private["e"] as Dictionary).has(str(e.id)):
				_forget(state, e.id)
			continue
		_monthly(state, e, slow, added)
	state.private["slow"] = slow
	if full(state):
		_branches(state, added)
		PrivateBridges.monthly(state, added)
	_prune(state)
	return added


static func _monthly(state: GameState, e: Empire, slow: Dictionary, added: Array[Dictionary]) -> void:
	var en := _w(state, e.id)
	var a: Dictionary = cfg("activity")
	var rev := {}
	var exp := {}
	var to := {}
	var plan := planned(state, e.id)
	# Activité de la population (prop. 2).
	var act := 0
	for c in colonies_of(state, e.id):
		if c.is_colony() and c.population >= int(a["min_pop"]):
			@warning_ignore("integer_division")
			act += c.population / maxi(1, int(a["per_pop"]))
	@warning_ignore("integer_division")
	act = act * (50 + int(en["conf"])) / 100
	if plan:
		@warning_ignore("integer_division")
		_add(to, "energy", act * int(data().get("planned_pct", 70)) / 100)
	else:
		rev["Activité de la population"] = act
	# Part privée des routes commerciales.
	var routes := int(Trade.income(state, e.id).get("energy", 0))
	if routes > 0:
		@warning_ignore("integer_division")
		rev["Commerce (part privée)"] = routes * int(a["route_pct"]) / 100
	# Stations minières et touristiques (props 14, 16).
	var fp := freight_pct(state, e.id)
	var mines := 0
	var mc: Dictionary = cfg("mine")
	for pid in stations_of(state, e.id, "mine"):
		var s := station(state, pid)
		if in_zone(state, int(s["sid"])) or (Trade.risk_at(state, int(s["sid"])) >= int(mc["raid_risk"]) and full(state)):
			continue
		var y := mine_yield(state, pid)
		for r in y["state"]:
			@warning_ignore("integer_division")
			_add(to, String(r), int(y["state"][r]) * fp / 100)
		@warning_ignore("integer_division")
		mines += int(y["private"]) * fp / 100
	if mines > 0:
		rev["Stations minières"] = mines
	var tour := 0
	for pid in stations_of(state, e.id, "resort"):
		if not in_zone(state, int(station(state, pid)["sid"])):
			tour += resort_income(state, pid)
	en["tour"] = tour
	if tour > 0:
		rev["Tourisme"] = tour
	# Filiales à l'étranger, contrats de l'État.
	var brv := branch_income(state, e.id)
	if brv > 0:
		rev["Filiales à l'étranger"] = brv
	var cost := 0
	if int(en.get("contract", 0)) > 0 and int(en.get("sup", 0)) > 0:
		var cv := int(en["sup"]) * c_int("contract", "energy")
		rev["Contrats de ravitaillement"] = cv
		cost += cv
	if int(en.get("req", 0)) > 0 and int(en.get("reqpay", 1)) > 0:
		var rv := int(en["req"]) * c_int("requisition", "pay")
		rev["Indemnités de réquisition"] = rv
		cost += rv
	en["sup"] = 0
	en["cost"] = cost
	# Dépenses : entretien des cargos, paquebots, stations (renchéri par l'inflation).
	@warning_ignore("integer_division")
	var up_c := (int(en["cargos"]) + 2) / 3 * c_int("cargo", "upkeep_per3")
	@warning_ignore("integer_division")
	var up_l := (int(en["liners"]) + 2) / 3 * c_int("liner", "upkeep_per3")
	var up_s := stations_of(state, e.id, "mine").size() * int(mc["upkeep"]) + stations_of(state, e.id, "resort").size() * c_int("resort", "upkeep")
	var infl := Finance.inflation(state, e.id) if Finance.applies(state, e.id) else 0
	if up_c > 0:
		exp["Entretien des cargos"] = _inflated(up_c, infl)
	if up_l > 0:
		exp["Entretien des paquebots"] = _inflated(up_l, infl)
	if up_s > 0:
		exp["Entretien des stations"] = _inflated(up_s, infl)
	# Cargos perdus (prop. 9).
	en["loss"] = 0
	if full(state):
		en["loss"] = _losses(state, e, en, added)
	var total_rev := 0
	for k in rev:
		total_rev += int(rev[k])
	var total_exp := 0
	for k in exp:
		total_exp += int(exp[k])
	var profit := total_rev - total_exp
	var tax := 0
	if profit > 0:
		@warning_ignore("integer_division")
		tax = profit * tax_rate(state, e.id) / 100
		var leak := PrivateBridges.tax_leak(state, e.id, tax)
		tax -= leak
		if leak > 0:
			exp["Impôt détourné (corruption, pour mémoire)"] = leak
	_add(to, "energy", tax)
	var after := profit - (tax if profit > 0 else 0)
	# Compagnies nationalisées : leur part du bénéfice va au Trésor (prop. 23).
	if after > 0 and full(state):
		var nat := 0
		for c in companies_of(state, e.id):
			if bool(c.get("nat", false)):
				nat += 1
		if nat > 0:
			@warning_ignore("integer_division")
			var share := after * nat * c_int("nationalize", "share_pct") / 100
			_add(to, "energy", share)
			after -= share
	en["cap"] = int(en["cap"]) + after
	en["rev"] = rev
	en["exp"] = exp
	en["profit"] = profit
	en["tax"] = tax
	# Confiance (prop. 5).
	var target := confidence_target(state, e.id)
	var cur := int(en["conf"])
	var dr := c_int("confidence", "drift")
	en["conf"] = clampi(cur + clampi(target - cur, -dr, dr), 0, 100)
	en["sub"] = maxi(0, int(en.get("sub", 0)) - 1)
	# File privée, investissements (prop. 4).
	_finish_queue(state, e, en, to, added)
	if not plan:
		_invest(state, e, en, to)
	en["mig"] = c_int("liner", "jumps") if liner_pct(state, e.id) >= 100 else 0
	# Chantiers lointains mal desservis (prop. 8).
	if usable_cargos(state, e.id) < cargo_need(state, e.id):
		_mark_slow(state, e.id, slow)
	# Compagnies (lot 2).
	if full(state) and not plan:
		_companies(state, e, en, to, added)
	en["to"] = to
	var sig := _fx_sig(state, e.id)
	if sig != String(en.get("fx", "")):
		en["fx"] = sig
		state.relic_rev += 1


static func _inflated(n: int, infl: int) -> int:
	@warning_ignore("integer_division")
	return n * (10000 + infl) / 10000


static func _add(d: Dictionary, k: String, n: int) -> void:
	if n != 0:
		d[k] = int(d.get(k, 0)) + n


## Cible de la confiance des investisseurs, avec ses raisons : [[libellé, valeur]].
static func confidence_parts(state: GameState, eid: int) -> Array:
	var cc: Dictionary = cfg("confidence")
	var out := [["Base", int(cc["base"])]]
	var e := state.get_empire(eid)
	var avg := Finance._avg_stability(state, eid)
	if avg >= int(cc["stab_hi"]):
		out.append(["Stabilité élevée", int(cc["stab_hi_v"])])
	elif avg < int(cc["stab_lo"]):
		out.append(["Stabilité basse", int(cc["stab_lo_v"])])
	if e.wars.is_empty():
		out.append(["Paix", int(cc["peace"])])
	else:
		out.append(["Guerre", int(cc["war"])])
		if _war_on_soil(state, eid):
			out.append(["Guerre sur notre sol", int(cc["war_soil"])])
	if Finance.applies(state, eid) and Finance.full(state):
		var gi := Finance.grade_index(Finance.grade(state, eid))
		if gi <= 1:
			out.append(["Excellente cote de crédit", int(cc["grade_hi"])])
		elif gi >= 6:
			out.append(["Cote de crédit désastreuse", int(cc["grade_lo"])])
	if Finance.applies(state, eid) and Finance.in_bankruptcy(state, eid):
		out.append(["Faillite de l'État", int(cc["bankrupt"])])
	var ch := 0
	for c in companies_of(state, eid):
		if String(c.get("ch", "")) != "":
			ch += int(cc["per_charter"])
	if ch > 0:
		out.append(["Chartes accordées", mini(ch, int(cc["charter_max"]))])
	if laissez_faire(state, eid):
		out.append(["Laissez-faire", int(cc["laissez_faire"])])
	var en := entry(state, eid)
	if int(en.get("nat", 0)) > state.tick:
		out.append(["Nationalisation récente", int(cc["nationalized"])])
	if not state.admin.is_empty() and Admin.has_corruption(state, eid):
		@warning_ignore("integer_division")
		var cv := -Admin.average_corruption(state, eid) / maxi(1, int(cc["corruption_div"]))
		if cv != 0:
			out.append(["Corruption", cv])
	var ls := int(en.get("loss", 0))
	if ls > 0:
		out.append(["Cargos perdus le mois dernier", maxi(int(cc["cargo_loss_max"]), ls * int(cc["cargo_loss"]))])
	if not state.crisis.is_empty() and CrisisKinds.infected(state, eid):
		out.append(["Le Krach", int(cc["krach"])])
	var sub := int(en.get("sub", 0))
	if sub > 0:
		out.append(["Subventions", sub])
	if int(en.get("req", 0)) > 0 and int(en.get("reqpay", 1)) <= 0:
		out.append(["Réquisition sans indemnité", int(cc["requisition"])])
	out.append_array(PrivateBridges.confidence_parts(state, eid))
	return out


static func confidence_target(state: GameState, eid: int) -> int:
	var n := 0
	for p in confidence_parts(state, eid):
		n += int(p[1])
	return clampi(n, 0, 100)


static func _war_on_soil(state: GameState, eid: int) -> bool:
	for sid in Stability.systems_of(state, eid):
		if Combat.is_besieged(state, sid) or WarPeace.occupier(state, sid) >= 0:
			return true
	return false


# --- Stations ----------------------------------------------------------------------------------

## Planètes où une station minière est possible : un gisement, dans un système où l'empire a pied,
## sans station, pas la colonie d'un autre empire.
static func mine_sites(state: GameState, eid: int) -> Array[int]:
	var out: Array[int] = []
	var seen := {}
	for c in colonies_of(state, eid):
		var sid := state.galaxy.get_planet(c.planet_id).system_id
		if seen.has(sid):
			continue
		seen[sid] = true
		for pid in state.galaxy.systems[sid].planet_ids:
			if not has_deposit(state, pid) or not station(state, pid).is_empty():
				continue
			var oc: Colony = state.colonies.get(pid)
			if oc != null and oc.owner != eid:
				continue
			out.append(pid)
	out.sort()
	return out


static func has_deposit(state: GameState, pid: int) -> bool:
	if not state.galaxy.get_planet(pid).deposits.is_empty():
		return true
	return not state.goods.is_empty() and Goods.deposit_of(state, pid) != ""


## Rendement d'une station minière : {"state": {ressource: n}, "private": énergie}.
static func mine_yield(state: GameState, pid: int) -> Dictionary:
	var mc: Dictionary = cfg("mine")
	var to := {}
	var priv := 0
	var dep_defs := {}
	for d: Dictionary in GameData.rules()["deposits"]:
		dep_defs[String(d["id"])] = d
	for did in state.galaxy.get_planet(pid).deposits:
		var y: Dictionary = (dep_defs.get(did, {}) as Dictionary).get("yields", {})
		for r in y:
			to[r] = int(to.get(r, 0)) + int(y[r])
			priv += int(y[r]) * (int(mc["crystals_value"]) if r == "crystals" else int(mc["revenue_per_unit"]))
	if not state.goods.is_empty() and Goods.deposit_of(state, pid) != "":
		to["energy"] = int(to.get("energy", 0)) + int(mc["goods_state"])
		priv += int(mc["goods_private"])
	return {"state": to, "private": priv}


## Systèmes où une station touristique est possible : beaux, tenus, sans station.
static func resort_sites(state: GameState, eid: int) -> Array[int]:
	var out: Array[int] = []
	var seen := {}
	for c in colonies_of(state, eid):
		var sid := state.galaxy.get_planet(c.planet_id).system_id
		if seen.has(sid):
			continue
		seen[sid] = true
		if station_at(state, sid, "resort") >= 0 or in_zone(state, sid):
			continue
		if Culture.beauty(state, sid) >= c_int("resort", "min_beauty"):
			out.append(sid)
	out.sort()
	return out


## Revenu touristique d'une station (prop. 16).
static func resort_income(state: GameState, pid: int) -> int:
	var s := station(state, pid)
	if s.is_empty():
		return 0
	var rc: Dictionary = cfg("resort")
	var sid := int(s["sid"])
	var eid := int(s["o"])
	var jumps := FactionTraits.jumps_from(state.galaxy, sid)
	var pop := 0
	var partners := Trade.partners(state, eid)
	var foreign := {}
	for k in jumps:
		var j := int(jumps[k])
		if j > maxi(int(rc["jumps"]), int(rc["foreign_jumps"])):
			continue
		for p2 in state.galaxy.systems[int(k)].planet_ids:
			var c: Colony = state.colonies.get(p2)
			if c == null or not c.is_colony() or not c.is_established() or GameState.is_npc(c.owner):
				continue
			if j <= int(rc["jumps"]):
				pop += c.population
			if c.owner != eid and partners.has(c.owner) and j <= int(rc["foreign_jumps"]):
				foreign[c.owner] = true
	@warning_ignore("integer_division")
	var base := mini(int(rc["max"]), pop / maxi(1, int(rc["pop_div"])))
	var bp := Culture.beauty(state, sid) * int(rc["beauty_pct"])
	if bp > int(rc["soft_cap"]):
		@warning_ignore("integer_division")
		bp = int(rc["soft_cap"]) + (bp - int(rc["soft_cap"])) / 2
	bp += Research.fx_int(state, eid, "tourism_pct")
	@warning_ignore("integer_division")
	var v := base * (100 + bp) / 100 + foreign.size() * int(rc["foreign"])
	@warning_ignore("integer_division")
	return v * (50 + liner_pct(state, eid) / 2) / 100


# --- File privée et investissement (prop. 4) ---------------------------------------------------

static func item_cost(kind: String) -> int:
	match kind:
		"cargo":
			return c_int("cargo", "cost")
		"liner":
			return c_int("liner", "cost")
		"mine":
			return c_int("mine", "cost")
		"resort":
			return c_int("resort", "cost")
	return 0


static func item_days(kind: String) -> int:
	match kind:
		"cargo":
			return c_int("cargo", "days")
		"liner":
			return c_int("liner", "days")
		"mine":
			return c_int("mine", "days")
		"resort":
			return c_int("resort", "days")
	return 30


static func _queue(state: GameState, eid: int, en: Dictionary, to: Dictionary, kind: String, key: int, paid_by_state := false) -> void:
	var cost := item_cost(kind)
	if not paid_by_state:
		en["cap"] = int(en["cap"]) - cost
	@warning_ignore("integer_division")
	_add(to, "energy", cost * int(data().get("rent_pct", 10)) / 100)  # chantiers loués (prop. 17)
	var it := {"k": kind, "done": state.tick + item_days(kind)}
	if kind == "mine":
		it["pid"] = key
	elif kind == "resort":
		it["sid"] = key
	(en["q"] as Array).append(it)


static func _finish_queue(state: GameState, e: Empire, en: Dictionary, _to: Dictionary, added: Array[Dictionary]) -> void:
	var keep := []
	for it: Dictionary in en["q"]:
		if int(it["done"]) > state.tick:
			keep.append(it)
			continue
		match String(it["k"]):
			"cargo":
				en["cargos"] = int(en["cargos"]) + 1
			"liner":
				en["liners"] = int(en["liners"]) + 1
			"mine":
				var pid := int(it["pid"])
				var sid := state.galaxy.get_planet(pid).system_id
				if station(state, pid).is_empty() and Economy.has_foothold(state, e.id, sid):
					(state.private["st"] as Dictionary)[str(pid)] = {"o": e.id, "k": "mine", "sid": sid, "c": -1, "t": state.tick}
					if not e.is_ai():
						added.append(state.add_chronicle("Le privé ouvre une station minière sur %s : des foreuses, des dortoirs et un bar, dans cet ordre." % state.galaxy.get_planet(pid).display_name(state.galaxy), Espionage.private_to(state, [e.id], sid)))
			"resort":
				var rs := int(it["sid"])
				if station_at(state, rs, "resort") < 0 and Economy.has_foothold(state, e.id, rs):
					var host := -1
					for pid2 in state.galaxy.systems[rs].planet_ids:
						if station(state, pid2).is_empty():
							host = pid2
							break
					if host >= 0:
						(state.private["st"] as Dictionary)[str(host)] = {"o": e.id, "k": "resort", "sid": rs, "c": -1, "t": state.tick}
						if not e.is_ai():
							added.append(state.add_chronicle("Une station touristique ouvre à %s : vue imprenable, cocktails hors de prix." % state.galaxy.systems[rs].system_name, Espionage.private_to(state, [e.id], rs)))
	en["q"] = keep
	# Vaisseaux commandés au privé (prop. 17).
	var ok := []
	for o: Dictionary in en.get("orders", []):
		if int(o["done"]) > state.tick:
			ok.append(o)
			continue
		var c: Colony = state.colonies.get(int(o["pid"]))
		if c != null and c.owner == e.id:
			var f := state.spawn_ship(e.id, String(o["ship"]), state.galaxy.get_planet(c.planet_id).system_id)
			Research.count_stat(state, e.id, "built")
			if not e.is_ai():
				added.append(state.add_chronicle("Les chantiers privés livrent un vaisseau à %s : %s, en avance et sur facture." % [state.galaxy.get_planet(c.planet_id).display_name(state.galaxy), f.fleet_name], Espionage.private_to(state, [e.id])))
	en["orders"] = ok


## Ce que le privé investit ce mois-ci : besoins de fret et de passagers, licences, stations
## touristiques, mines spontanées, bâtiments civils, selon la confiance et l'impôt.
static func _invest(state: GameState, e: Empire, en: Dictionary, to: Dictionary) -> void:
	var cc: Dictionary = cfg("confidence")
	var conf := int(en["conf"])
	if conf < int(cc["min_invest"]):
		return
	if _h(state, ["inv", e.id, state.tick]) % 100 >= invest_pct(state, e.id):
		return
	var tries := 2 if conf >= int(cc["double"]) else 1
	var focus := String(en.get("focus", "")) if bool(talent(state, e.id).get("guild", false)) else ""
	for i in tries:
		var opts := _options(state, e.id, en, conf)
		if opts.is_empty():
			return
		var pick: Array = opts[0]
		if focus != "":
			for o: Array in opts:
				if String(o[2]) == focus:
					pick = o
					break
		var kind := String(pick[0])
		if kind == "building":
			_start_building(state, e.id, en, to, int(pick[1]), String(pick[3]))
		else:
			_queue(state, e.id, en, to, kind, int(pick[1]))


## Options d'investissement possibles, dans l'ordre de préférence : [kind, clé, famille, extra].
static func _options(state: GameState, eid: int, en: Dictionary, conf: int) -> Array:
	var out := []
	var cap := int(en["cap"])
	var qc := 0
	var ql := 0
	for it: Dictionary in en["q"]:
		if String(it["k"]) == "cargo":
			qc += 1
		elif String(it["k"]) == "liner":
			ql += 1
	# Fret d'abord tant qu'il manque plus de la moitié du besoin, sinon après les mines sous licence.
	var need_c := int(en["cargos"]) + qc < cargo_need(state, eid) and cap >= item_cost("cargo")
	var urgent := need_c and (int(en["cargos"]) + qc) * 2 < cargo_need(state, eid)
	if urgent:
		out.append(["cargo", -1, "cargos", ""])
	# Licences d'abord, puis mines spontanées (prop. 15).
	if cap >= item_cost("mine"):
		for pid in en.get("lic", []):
			if station(state, int(pid)).is_empty() and not queued(state, eid, "mine", int(pid)) \
					and Economy.has_foothold(state, eid, state.galaxy.get_planet(int(pid)).system_id):
				out.append(["mine", int(pid), "mines", ""])
				break
	if need_c and not urgent:
		out.append(["cargo", -1, "cargos", ""])
	if cap >= item_cost("resort"):
		for sid in resort_sites(state, eid):
			if not queued(state, eid, "resort", sid):
				out.append(["resort", sid, "tourisme", ""])
				break
	if int(en["liners"]) + ql < liner_need(state, eid) and cap >= item_cost("liner"):
		out.append(["liner", -1, "cargos", ""])
	if conf >= c_int("confidence", "spontaneous") and cap >= item_cost("mine"):
		var best := -1
		var bv := 0
		for pid in mine_sites(state, eid):
			var sid := state.galaxy.get_planet(pid).system_id
			if queued(state, eid, "mine", pid) or in_zone(state, sid) or (en.get("block", []) as Array).has(sid):
				continue
			var v := int(mine_yield(state, pid)["private"])
			if v > bv:
				bv = v
				best = pid
		if best >= 0:
			out.append(["mine", best, "mines", ""])
	var b := _building_site(state, eid, cap)
	if not b.is_empty():
		out.append(["building", int(b[0]), "batiments", String(b[1])])
	return out


static func building_price(state: GameState, eid: int, bid: String) -> int:
	var n := 0
	var cost := Economy.building_cost(state, eid, bid)
	for r in cost:
		n += int(cost[r])
	@warning_ignore("integer_division")
	return n * c_int("buildings", "cost_mult") / 100


## Une colonie dont le chantier est libre, et un bâtiment civil que le privé peut y payer.
static func _building_site(state: GameState, eid: int, cap: int) -> Array:
	for bid in cfg("buildings").get("ids", []):
		var price := building_price(state, eid, String(bid))
		if cap < price:
			continue
		for c in colonies_of(state, eid):
			if c.construction != "":
				continue
			if String(bid) == "comptoir" and Trade.partners(state, eid).is_empty():
				continue
			if _can_place(state, eid, c, String(bid)):
				return [c.planet_id, String(bid)]
	return []


## Le bâtiment se pose-t-il (hors coût, payé par le privé) ?
static func _can_place(state: GameState, eid: int, c: Colony, bid: String) -> bool:
	if not Economy.building_unlocked(state, eid, bid):
		return false
	var b := GameData.building(bid)
	if not c.is_colony() and not bool(b.get("outpost_ok", false)):
		return false
	if bool(b.get("unique", false)) and c.buildings.has(bid):
		return false
	if bool(b.get("per_system", false)):
		var sid := state.galaxy.get_planet(c.planet_id).system_id
		for pid in state.galaxy.systems[sid].planet_ids:
			var o: Colony = state.colonies.get(pid)
			if o != null and (o.buildings.has(bid) or o.construction == bid):
				return false
	if Economy.takes_slot(bid) and Economy.building_slots_used(c) >= Economy.building_slots(state, c):
		return false
	return true


static func _start_building(state: GameState, eid: int, en: Dictionary, to: Dictionary, pid: int, bid: String) -> void:
	var c: Colony = state.colonies[pid]
	var price := building_price(state, eid, bid)
	en["cap"] = int(en["cap"]) - price
	@warning_ignore("integer_division")
	_add(to, "energy", price * int(data().get("rent_pct", 10)) / 100)
	c.construction = bid
	c.construction_days = maxi(1, Research.scaled(int(GameData.building(bid)["days"]), Research.fx_int(state, eid, "building_days_pct")))
	(en["pb"] as Dictionary)[str(pid)] = bid


static func private_building(state: GameState, pid: int) -> String:
	var c: Colony = state.colonies.get(pid)
	if c == null:
		return ""
	var en := entry(state, c.owner)
	var b := String((en.get("pb", {}) as Dictionary).get(str(pid), ""))
	return b if b != "" and c.construction == b else ""


static func _mark_slow(state: GameState, eid: int, slow: Dictionary) -> void:
	var hubs: Array[int] = []
	var cap := FactionTraits.capital_system(state, eid)
	if cap >= 0:
		hubs.append(cap)
	for pid in Trade.comptoirs(state, eid):
		hubs.append(state.galaxy.get_planet(pid).system_id)
	if hubs.is_empty():
		return
	var near := {}
	for h in hubs:
		var jumps := FactionTraits.jumps_from(state.galaxy, h)
		for k in jumps:
			if int(jumps[k]) <= c_int("cargo", "far_jumps"):
				near[int(k)] = true
	for c in colonies_of(state, eid):
		var sid := state.galaxy.get_planet(c.planet_id).system_id
		if not near.has(sid):
			slow[str(sid)] = 1


# --- Cargos perdus (prop. 9) -------------------------------------------------------------------

static func _losses(state: GameState, e: Empire, en: Dictionary, added: Array[Dictionary]) -> int:
	var lc: Dictionary = cfg("losses")
	var lost := 0
	var hostile := Trade._hostile_presence(state)
	var loss_pct := 0
	for c in companies_of(state, e.id):
		if String(c["sec"]) == "fret":
			loss_pct += int(trait_def(String((c.get("dir", {}) as Dictionary).get("trait", ""))).get("loss_pct", 0))
	for r: Dictionary in Trade.sent_by(state, e.id):
		var worst := 0
		var foe := false
		for sid in r.get("path", []):
			if in_zone(state, int(sid)):
				continue
			worst = maxi(worst, Trade.risk_at(state, int(sid)))
			for o in hostile.get(int(sid), []):
				if int(o) != e.id and (GameState.is_npc(int(o)) or Combat.at_war(state, e.id, int(o))):
					foe = true
		@warning_ignore("integer_division")
		var chance := worst / maxi(1, int(lc["risk_div"]))
		@warning_ignore("integer_division")
		chance = chance * maxi(0, 100 + loss_pct) / 100
		if foe:
			chance += int(lc["hostile_pct"])
		if chance > 0 and _h(state, ["loss", e.id, state.tick, int(r.get("to", -1))]) % 100 < chance:
			lost += 1
	lost = mini(lost, int(en["cargos"]))
	if lost > 0:
		en["cargos"] = int(en["cargos"]) - lost
		Deeds.note(state, e.id, "cargos_lost", lost)
		if not e.is_ai() and lost >= 2:
			added.append(state.add_chronicle("%d cargos de %s ne sont jamais arrivés : pirates, ennemis ou mauvais sort. Les assureurs relisent leurs contrats." % [lost, e.short_name()], Espionage.private_to(state, [e.id])))
	return lost


# --- Conquêtes : les stations changent de mains (prop. 30) --------------------------------------

static func _conquests(state: GameState, added: Array[Dictionary]) -> void:
	var st: Dictionary = state.private["st"]
	var keys := st.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	for k in keys:
		var s: Dictionary = st[k]
		var sid := int(s["sid"])
		if Economy.has_foothold(state, int(s["o"]), sid):
			continue
		var now := state.system_owner(sid)
		if now >= 0 and applies(state, now) and Economy.has_foothold(state, now, sid):
			var old := int(s["o"])
			s["o"] = now
			s["c"] = -1
			if bool(talent(state, now).get("loot_station", false)):
				var ne := state.get_empire(now)
				ne.resources["energy"] = int(ne.resources.get("energy", 0)) + c_int("conquest", "loot")
			added.append(state.add_chronicle("La station privée de %s passe aux mains de %s, qui garde le personnel et change l'enseigne." % [
					state.galaxy.systems[sid].system_name, state.get_empire(now).short_name()], Espionage.private_to(state, [old, now], sid)))
		else:
			st.erase(k)


# --- Compagnies (props 18-25) ------------------------------------------------------------------

static func all_companies(state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state.private.is_empty():
		return out
	var co: Dictionary = state.private["co"]
	var keys := co.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	for k in keys:
		out.append(co[k])
	return out


static func companies_of(state: GameState, eid: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in all_companies(state):
		if int(c["o"]) == eid:
			out.append(c)
	return out


static func company(state: GameState, cid: int) -> Dictionary:
	if state.private.is_empty():
		return {}
	return (state.private["co"] as Dictionary).get(str(cid), {})


static func company_max(state: GameState, eid: int) -> int:
	var n := c_int("companies", "base_max") + Research.fx_int(state, eid, "company_max")
	if laissez_faire(state, eid):
		n += 1
	return n


static func charter_max(state: GameState, eid: int) -> int:
	return c_int("charters", "base") + Research.fx_int(state, eid, "charters") + int(talent(state, eid).get("charters", 0))


static func charters_used(state: GameState, eid: int) -> int:
	var n := 0
	for c in companies_of(state, eid):
		if String(c.get("ch", "")) != "":
			n += 1
	return n


## Actifs d'une compagnie de ce secteur dans l'empire (stations, cargos, filiales…).
static func sector_assets(state: GameState, eid: int, sec: String) -> int:
	var en := entry(state, eid)
	match sec:
		"fret":
			@warning_ignore("integer_division")
			return int(en.get("cargos", 0)) / 2
		"mines":
			return stations_of(state, eid, "mine").size()
		"tourisme":
			return stations_of(state, eid, "resort").size() * 2 + int(en.get("liners", 0)) / 2
		"chantiers":
			return (en.get("orders", []) as Array).size() * 2 + (en.get("pb", {}) as Dictionary).size()
		"banque":
			@warning_ignore("integer_division")
			return int(en.get("cap", 0)) / 200
		"armement":
			return 0 if state.get_empire(eid).wars.is_empty() else 4
		"biotech":
			@warning_ignore("integer_division")
			return Laws.empire_pop(state, eid) / 20
		"medias":
			@warning_ignore("integer_division")
			return colonies_of(state, eid).size() / 3
	return 0


static func _pick_sector(state: GameState, eid: int) -> String:
	var have := {}
	for c in companies_of(state, eid):
		have[String(c["sec"])] = true
	var best := ""
	var bv := -1
	for s: Dictionary in cfg("companies")["sectors"]:
		var id := String(s["id"])
		if have.has(id):
			continue
		var v := sector_assets(state, eid, id) * 10 + _h(state, ["sec", eid, id, state.tick]) % 7
		if v > bv:
			bv = v
			best = id
	return best


static func _hq_for(state: GameState, eid: int) -> int:
	var best := -1
	var bv := -1
	for c in colonies_of(state, eid):
		if not c.is_colony():
			continue
		var sid := state.galaxy.get_planet(c.planet_id).system_id
		var v := c.population
		if Finance.applies(state, eid) and Finance.has_franchise(state, sid):
			v += 50  # une franchise fiscale attire les sièges (prop. 28)
		if v > bv:
			bv = v
			best = sid
	return best


static func make_director(state: GameState, eid: int, salt: Array) -> Dictionary:
	if bool(talent(state, eid).get("no_directors", false)):
		return {}
	var cand := Heroes.make_candidate(state, eid, "intendant", salt)
	var traits: Array = cfg("directors")["traits"]
	return {"name": String(cand["name"]), "portrait": String(cand.get("portrait", "")),
			"trait": String(traits[_h(state, salt + ["trait"]) % traits.size()]["id"])}


static func found_company(state: GameState, eid: int, sec: String, added: Array[Dictionary]) -> Dictionary:
	var hq := _hq_for(state, eid)
	if hq < 0 or sec == "":
		return {}
	var cid := int(state.private["cid"])
	state.private["cid"] = cid + 1
	var names: Array = sector_def(sec).get("names", ["Compagnie de %s"])
	var c := {"id": cid, "o": eid, "sec": sec, "hq": hq, "pr": 50, "ch": "", "ch_day": -100000, "nat": false, "sh": {},
			"low": 0, "born": state.tick, "house": -1, "lob": -1,
			"n": String(names[_h(state, ["name", cid]) % names.size()]) % state.galaxy.systems[hq].system_name,
			"dir": make_director(state, eid, ["dir", cid, 0])}
	(state.private["co"] as Dictionary)[str(cid)] = c
	PrivateBridges.on_founded(state, eid, c)
	Deeds.note(state, eid, "company_founded")
	Rulers.note(state, eid, "companies")
	var e := state.get_empire(eid)
	added.append(state.add_chronicle("%s naît à %s : %s, secteur %s. Les actionnaires sablent ce qu'ils ont." % [
			String(c["n"]), state.galaxy.systems[hq].system_name, e.short_name(), String(sector_def(sec)["label"]).to_lower()], Espionage.private_to(state, [eid], hq)))
	return c


static func _companies(state: GameState, e: Empire, en: Dictionary, to: Dictionary, added: Array[Dictionary]) -> void:
	var cc: Dictionary = cfg("companies")
	var mine := companies_of(state, e.id)
	# Naissance (prop. 18).
	if mine.size() < company_max(state, e.id) and int(en["cap"]) >= int(cc["found_at"]):
		var c := found_company(state, e.id, _pick_sector(state, e.id), added)
		if not c.is_empty():
			en["cap"] = int(en["cap"]) - int(cc["found_cost"])
			mine.append(c)
	# Prospérité, faillite, lobbying, déménagement (props 19, 24).
	for c in mine:
		var hq := int(c["hq"])
		if not Economy.has_foothold(state, e.id, hq):
			var nh := _hq_for(state, e.id)
			if nh < 0:
				_ruin(state, c, added, "son siège est tombé")
				continue
			c["hq"] = nh
		if bool(c.get("nat", false)):
			continue
		var target := company_target(state, c)
		var dr := int(cc["drift"])
		var pr := clampi(int(c["pr"]) + clampi(target - int(c["pr"]), -dr, dr), 0, 100)
		var floor_v := int(trait_def(String((c.get("dir", {}) as Dictionary).get("trait", ""))).get("floor", 0))
		c["pr"] = maxi(pr, floor_v)
		if int(c["pr"]) < int(cc["ruin_below"]):
			c["low"] = int(c.get("low", 0)) + 1
			if int(c["low"]) >= int(cc["ruin_months"]):
				_ruin(state, c, added, "elle ne vend plus rien")
				continue
		else:
			c["low"] = 0
		_lobby(state, e, c, to, added)
	# Dividendes annuels (prop. 25).
	if state.tick % YEAR == 0:
		_dividends(state, e, en)


## Prospérité visée par une compagnie, avec ses raisons.
static func company_parts(state: GameState, c: Dictionary) -> Array:
	var cc: Dictionary = cfg("companies")
	var eid := int(c["o"])
	var out := [["Base", 50]]
	var a := mini(int(cc["assets_max"]), sector_assets(state, eid, String(c["sec"])) * 5)
	if a != 0:
		out.append(["Actifs du secteur", a])
	@warning_ignore("integer_division")
	var cf := (confidence(state, eid) - 50) / 2
	if cf != 0:
		out.append(["Confiance des investisseurs", cf])
	if String(c.get("ch", "")) != "":
		out.append(["Charte", int(cc["charter_pr"])])
	var tp := int(trait_def(String((c.get("dir", {}) as Dictionary).get("trait", ""))).get("pr", 0))
	if tp != 0:
		out.append(["Dirigeant", tp])
	if Finance.applies(state, eid) and Finance.has_franchise(state, int(c["hq"])):
		out.append(["Siège en franchise fiscale", int(cc["franchise_pr"])])
	var law := lobby_law(state, c)
	if law != "" and state.politics_on and Laws.is_enacted(state, eid, law):
		out.append(["Sa loi est en vigueur", c_int("lobby", "pr")])
	if not state.crisis.is_empty() and CrisisKinds.infected(state, eid):
		out.append(["Le Krach", int(cc["krach"])])
	out.append_array(PrivateBridges.company_parts(state, c))
	return out


static func company_target(state: GameState, c: Dictionary) -> int:
	var n := 0
	for p in company_parts(state, c):
		n += int(p[1])
	return clampi(n, 0, 100)


static func _ruin(state: GameState, c: Dictionary, added: Array[Dictionary], why: String) -> void:
	var eid := int(c["o"])
	(state.private["co"] as Dictionary).erase(str(int(c["id"])))
	var br: Dictionary = state.private["br"]
	for k in br.keys():
		if int(br[k]["c"]) == int(c["id"]):
			br.erase(k)
	PrivateBridges.on_ruin(state, eid, c)
	state.relic_rev += 1
	added.append(state.add_chronicle("Faillite : %s ferme ses portes, %s. Les huissiers emportent jusqu'aux plantes vertes." % [String(c["n"]), why], Espionage.private_to(state, [eid])))


## Loi que réclame une compagnie (prop. 24) ; à défaut de rayonnement, le libre-échange.
static func lobby_law(state: GameState, c: Dictionary) -> String:
	var law := String(sector_def(String(c["sec"])).get("law", ""))
	if law == "":
		return ""
	var d := Laws.law_def(law)
	if bool(d.get("culture", false)) and not Culture.enabled(state):
		return "libre_echange"
	return law


static func _lobby(state: GameState, e: Empire, c: Dictionary, to: Dictionary, added: Array[Dictionary]) -> void:
	if not state.politics_on or not Laws.applies(state, e.id):
		return
	var law := lobby_law(state, c)
	if law == "":
		return
	if Laws.is_enacted(state, e.id, law):
		var x := maxi(1, int(trait_def(String((c.get("dir", {}) as Dictionary).get("trait", ""))).get("lobby_x", 1)))
		_add(to, "influence", c_int("lobby", "influence") * x)
		c["lob"] = -1
		return
	var against := false
	for x in Laws.law_def(law).get("excludes", []):
		if Laws.is_enacted(state, e.id, String(x)):
			against = true
	if law == "laissez_faire" and Laws.is_enacted(state, e.id, "economie_planifiee"):
		against = true
	if not against:
		c["lob"] = -1
		return
	if int(c.get("lob", -1)) < 0:
		c["lob"] = state.tick
		return
	if state.tick - int(c["lob"]) < c_int("lobby", "relocate_days"):
		return
	# Déménagement chez le meilleur partenaire commercial.
	var best := -1
	var bv := 0
	for o in Trade.partners(state, e.id):
		if applies(state, o) and companies_of(state, o).size() < company_max(state, o):
			var v := Trade.value_between(state, e.id, o)
			if v > bv or best < 0:
				bv = v
				best = o
	if best < 0:
		return
	var nh := _hq_for(state, best)
	if nh < 0:
		return
	c["o"] = best
	c["hq"] = nh
	c["ch"] = ""
	c["lob"] = -1
	state.relic_rev += 1
	added.append(state.add_chronicle("%s en a assez des lois de %s : elle déménage son siège chez %s, avec ses avocats et ses plantes vertes." % [
			String(c["n"]), e.short_name(), state.get_empire(best).short_name()], Espionage.public_to(state, [e.id, best])))


# --- Actions du joueur -------------------------------------------------------------------------

## Ordre « private » : {"act": action, "a": entier, "b": entier, "s": texte}.
static func check(state: GameState, eid: int, act: String, a: int, b: int, s: String) -> String:
	if not applies(state, eid):
		return "pas de secteur privé dans votre empire"
	var e := state.get_empire(eid)
	var en := entry(state, eid)
	match act:
		"subsidize":
			if planned(state, eid):
				return "l'économie planifiée n'a pas de secteur privé à subventionner"
			if state.tick - int(en.get("sub_day", -100000)) < _month():
				return "une subvention par mois au plus"
			if int(e.resources.get("energy", 0)) < c_int("subsidy", "energy"):
				return "il faut %d énergie" % c_int("subsidy", "energy")
			return ""
		"licence":
			if not mine_sites(state, eid).has(a):
				return "pas de gisement libre ici, ou hors de vos systèmes"
			if (en.get("lic", []) as Array).has(a):
				return "licence déjà accordée"
			if not Economy.can_afford(e, cfg("mine")["licence"]):
				return "il faut %s" % GameData.format_amounts(cfg("mine")["licence"])
			return ""
		"order":
			if not mine_sites(state, eid).has(a) or queued(state, eid, "mine", a):
				return "pas de gisement libre ici"
			var price := order_price(state, eid)
			if int(e.resources.get("energy", 0)) < price:
				return "il faut %d énergie" % price
			return ""
		"block":
			if not Stability.systems_of(state, eid).has(a):
				return "ce système ne vous appartient pas"
			return ""
		"zone":
			if not full(state):
				return "seulement en économie privée complète"
			if not Stability.systems_of(state, eid).has(a):
				return "ce système ne vous appartient pas"
			return ""
		"requisition":
			if not full(state):
				return "seulement en économie privée complète"
			if a > 0 and e.wars.is_empty():
				return "on ne réquisitionne qu'en guerre"
			return ""
		"contract":
			if not full(state):
				return "seulement en économie privée complète"
			return ""
		"focus":
			if not bool(talent(state, eid).get("guild", false)):
				return "seule une guilde marchande dirige son privé"
			for f: Dictionary in data().get("focus", []):
				if String(f["id"]) == s:
					return ""
			return "priorité inconnue"
		"ship":
			return check_ship_order(state, eid, a, s)
	if not full(state):
		return "seulement en économie privée complète"
	var c := company(state, a)
	match act:
		"charter":
			if c.is_empty() or int(c["o"]) != eid:
				return "compagnie inconnue"
			if bool(c.get("nat", false)):
				return "une compagnie nationalisée n'a pas de charte"
			if s != "" and charter_def(s).is_empty():
				return "charte inconnue"
			if s == String(c.get("ch", "")):
				return "déjà la sienne"
			if state.tick - int(c.get("ch_day", -100000)) < c_int("charters", "cooldown_days"):
				return "une charte se change une fois par an"
			if s != "" and String(c.get("ch", "")) == "" and charters_used(state, eid) >= charter_max(state, eid):
				return "plus de charte libre (%d)" % charter_max(state, eid)
			if s == "monopole":
				for o in companies_of(state, eid):
					if int(o["id"]) != a and String(o["sec"]) == String(c["sec"]):
						return "une autre compagnie du même secteur empêche le monopole"
			return ""
		"nationalize":
			if c.is_empty() or int(c["o"]) != eid:
				return "compagnie inconnue"
			if bool(c.get("nat", false)):
				return "déjà nationalisée"
			if laissez_faire(state, eid):
				return "le Laissez-faire interdit les nationalisations"
			if int(e.resources.get("influence", 0)) < c_int("nationalize", "influence"):
				return "il faut %d influence" % c_int("nationalize", "influence")
			return ""
		"recruit":
			if c.is_empty() or int(c["o"]) != eid:
				return "compagnie inconnue"
			if (c.get("dir", {}) as Dictionary).is_empty():
				return "elle n'a pas de dirigeant"
			if Heroes.ids_of(state, eid).size() >= Heroes.cap(state, eid):
				return "plus de place pour un héros"
			return ""
		"branch":
			return check_branch(state, eid, a, b)
		"expropriate":
			var br: Dictionary = (state.private["br"] as Dictionary).get(str(a), {})
			if br.is_empty():
				return "pas de filiale ici"
			var cc: Colony = state.colonies.get(a)
			if cc == null or cc.owner != eid:
				return "cette colonie n'est pas à vous"
			if int((state.private.get("mk", {}) as Dictionary).get("%d>%d" % [int(br["o"]), eid], 0)) > state.tick:
				return "le traité d'ouverture des marchés vous l'interdit"
			return ""
		"confiscate":
			if not Combat.at_war(state, eid, a):
				return "on ne confisque que les comptes d'un ennemi"
			if branches_in(state, eid, a).is_empty():
				return "il n'a aucune filiale chez vous"
			return ""
		"shares":
			if c.is_empty():
				return "compagnie inconnue"
			if int(c["o"]) != eid and Trade.tier(state, eid, int(c["o"])) < 1:
				return "il faut des comptoirs ouverts avec son pays"
			var sold := 0
			for k in c.get("sh", {}):
				sold += int(c["sh"][k])
			if sold >= c_int("shares", "max_tenths"):
				return "plus aucune part à vendre"
			if int(e.resources.get("energy", 0)) < share_price(c):
				return "il faut %d énergie" % share_price(c)
			return ""
		"creative":
			return PrivateBridges.check_creative(state, eid)
		"raid":
			return PrivateBridges.check_raid(state, eid, a)
	return "action inconnue : %s" % act


static func apply(state: GameState, eid: int, act: String, a: int, b: int, s: String) -> void:
	var e := state.get_empire(eid)
	var en := _w(state, eid)
	match act:
		"subsidize":
			var n := c_int("subsidy", "energy")
			e.resources["energy"] = int(e.resources.get("energy", 0)) - n
			en["cap"] = int(en["cap"]) + n
			en["sub_day"] = state.tick
			var gain := c_int("confidence", "subsidy") * (2 if dirigisme(state, eid) else 1)
			en["sub"] = mini(c_int("confidence", "subsidy_max"), int(en.get("sub", 0)) + gain)
		"licence":
			Economy.pay(e, cfg("mine")["licence"])
			(en["lic"] as Array).append(a)
		"order":
			var price := order_price(state, eid)
			e.resources["energy"] = int(e.resources.get("energy", 0)) - price
			if not (en["lic"] as Array).has(a):
				(en["lic"] as Array).append(a)
			_queue(state, eid, en, en["to"], "mine", a, true)
		"block":
			var bl: Array = en["block"]
			if bl.has(a):
				bl.erase(a)
			else:
				bl.append(a)
		"zone":
			var z: Dictionary = state.private["zone"]
			if z.has(str(a)):
				z.erase(str(a))
			else:
				z[str(a)] = eid
		"requisition":
			if a > 0:
				@warning_ignore("integer_division")
				en["req"] = maxi(1, int(en["cargos"]) * c_int("requisition", "pct") / 100)
				en["reqpay"] = 1 if b > 0 else 0
			else:
				en["req"] = 0
			state.relic_rev += 1
		"contract":
			en["contract"] = 1 if a > 0 else 0
		"focus":
			en["focus"] = s
		"ship":
			order_ship(state, eid, a, s)
		"charter":
			var c := company(state, a)
			c["ch"] = s
			c["ch_day"] = state.tick
			state.relic_rev += 1
		"nationalize":
			var c2 := company(state, a)
			e.resources["influence"] = int(e.resources.get("influence", 0)) - c_int("nationalize", "influence")
			c2["nat"] = true
			c2["ch"] = ""
			en["nat"] = state.tick + c_int("confidence", "nationalized_days")
			Rulers.note(state, eid, "nationalized")
			state.relic_rev += 1
			state.add_chronicle("%s nationalise %s : les actionnaires apprennent la nouvelle par la radio d'État." % [e.short_name(), String(c2["n"])], Espionage.private_to(state, [eid]))
		"recruit":
			var c3 := company(state, a)
			var d: Dictionary = c3["dir"]
			var cand := Heroes.make_candidate(state, eid, "intendant", ["dir", int(c3["id"]), state.tick])
			cand["name"] = String(d["name"])
			if String(d.get("portrait", "")) != "":
				cand["portrait"] = String(d["portrait"])
			Heroes.recruit(state, eid, cand)
			c3["dir"] = make_director(state, eid, ["dir", int(c3["id"]), state.tick, "new"])
		"branch":
			open_branch(state, eid, a, b)
		"expropriate":
			expropriate(state, eid, a)
		"confiscate":
			confiscate(state, eid, a)
		"shares":
			buy_shares(state, eid, a)
		"creative":
			PrivateBridges.creative(state, eid)
		"raid":
			PrivateBridges.raid(state, eid, a)


# --- Vaisseaux commandés au privé (prop. 17) ---------------------------------------------------

static func ship_order_cost(state: GameState, eid: int, ship: String) -> Dictionary:
	return Research.scaled_amounts(Fleets.ship_cost(state, eid, ship), c_int("ship_order", "cost_pct"))


static func check_ship_order(state: GameState, eid: int, pid: int, ship: String) -> String:
	if planned(state, eid):
		return "l'économie planifiée n'a pas de chantiers privés"
	var c: Colony = state.colonies.get(pid)
	if c == null or c.owner != eid or not c.is_established() or not c.is_colony():
		return "il faut une colonie fondée à vous"
	var sd := GameData.ship(ship)
	if sd.is_empty() or not Designs.can_build_id(state, eid, ship) or not Fleets.ship_unlocked(state, eid, ship):
		return "classe de vaisseau indisponible"
	if int(sd.get("pop_cost", 0)) > 0 or bool((sd.get("requires", {}) as Dictionary).get("unique_per_empire", false)):
		return "le privé ne construit ni vaisseaux colons ni méga-vaisseaux"
	var need := String((sd.get("requires", {}) as Dictionary).get("building", ""))
	if need != "" and not c.buildings.has(need):
		return "il faut un bâtiment sur cette colonie : %s" % String(GameData.building(need).get("label", need))
	for o: Dictionary in entry(state, eid).get("orders", []):
		if int(o["pid"]) == pid:
			return "une commande privée à la fois par colonie"
	var cost := ship_order_cost(state, eid, ship)
	if not Economy.can_afford(state.get_empire(eid), cost):
		return "il faut %s" % GameData.format_amounts(cost)
	return ""


static func order_ship(state: GameState, eid: int, pid: int, ship: String) -> void:
	var en := _w(state, eid)
	var cost := ship_order_cost(state, eid, ship)
	Economy.pay(state.get_empire(eid), cost)
	var total := 0
	for r in cost:
		total += int(cost[r])
	@warning_ignore("integer_division")
	en["cap"] = int(en["cap"]) + total / 6  # la marge du chantier privé
	var days := maxi(1, Research.scaled(Fleets.ship_days(state, eid, ship), c_int("ship_order", "days_pct")))
	(en["orders"] as Array).append({"pid": pid, "ship": ship, "done": state.tick + days})


# --- Filiales (prop. 22), expropriation, confiscation (prop. 23) --------------------------------

static func branch_cost(state: GameState, cid: int, pid: int) -> int:
	var c := company(state, cid)
	var bc: Dictionary = cfg("branches")
	var j := int(FactionTraits.jumps_from(state.galaxy, int(c.get("hq", 0))).get(state.galaxy.get_planet(pid).system_id, 30))
	@warning_ignore("integer_division")
	return int(bc["energy"]) * (100 + maxi(0, j - int(bc["free_jumps"])) * int(bc["per_jump"])) / 100


static func check_branch(state: GameState, eid: int, cid: int, pid: int) -> String:
	var c := company(state, cid)
	if c.is_empty() or int(c["o"]) != eid:
		return "compagnie inconnue"
	if bool(c.get("nat", false)):
		return "une compagnie nationalisée n'ouvre pas de filiale"
	var col: Colony = state.colonies.get(pid)
	if col == null or not col.is_colony() or not col.is_established() or col.owner == eid or GameState.is_npc(col.owner):
		return "il faut une colonie d'un autre empire"
	if not applies(state, col.owner):
		return "ce peuple n'a pas d'économie privée"
	if Trade.tier(state, eid, col.owner) < c_int("branches", "tier"):
		return "il faut un accord commercial avec son pays"
	if (state.private["br"] as Dictionary).has(str(pid)):
		return "une filiale y est déjà"
	if capital(state, eid) < branch_cost(state, cid, pid):
		return "la caisse privée n'a pas %d énergie" % branch_cost(state, cid, pid)
	if int(state.get_empire(eid).resources.get("influence", 0)) < c_int("branches", "influence"):
		return "il faut %d influence" % c_int("branches", "influence")
	return ""


static func open_branch(state: GameState, eid: int, cid: int, pid: int) -> void:
	var en := _w(state, eid)
	en["cap"] = int(en["cap"]) - branch_cost(state, cid, pid)
	var e := state.get_empire(eid)
	e.resources["influence"] = int(e.resources.get("influence", 0)) - c_int("branches", "influence")
	var host := (state.colonies[pid] as Colony).owner
	(state.private["br"] as Dictionary)[str(pid)] = {"c": cid, "o": eid, "t": state.tick}
	Diplomacy.remember(state, host, eid, "branch_opened")
	var empires := {}
	for k in state.private["br"]:
		var b: Dictionary = state.private["br"][k]
		if int(b["o"]) == eid:
			var cc: Colony = state.colonies.get(int(k))
			if cc != null:
				empires[cc.owner] = true
	Deeds.note(state, eid, "branch_opened")
	(state.private["e"][str(eid)] as Dictionary)["brx"] = maxi(int(en.get("brx", 0)), empires.size())


static func branch_value(state: GameState, pid: int) -> int:
	var c: Colony = state.colonies.get(pid)
	if c == null:
		return 0
	var bc: Dictionary = cfg("branches")
	@warning_ignore("integer_division")
	return mini(int(bc["max"]), c.population / maxi(1, int(bc["pop_div"])))


static func branch_income(state: GameState, eid: int) -> int:
	var n := 0
	if state.private.is_empty():
		return 0
	for k in state.private["br"]:
		var b: Dictionary = state.private["br"][k]
		if int(b["o"]) == eid:
			n += branch_value(state, int(k))
	return n


## Filiales que l'empire origin a chez host : [planète].
static func branches_in(state: GameState, host: int, origin: int) -> Array[int]:
	var out: Array[int] = []
	if state.private.is_empty():
		return out
	for k in state.private["br"]:
		var b: Dictionary = state.private["br"][k]
		var c: Colony = state.colonies.get(int(k))
		if c != null and c.owner == host and (origin < 0 or int(b["o"]) == origin):
			out.append(int(k))
	out.sort()
	return out


static func expropriate(state: GameState, eid: int, pid: int) -> void:
	var br: Dictionary = state.private["br"][str(pid)]
	var origin := int(br["o"])
	var gain := branch_value(state, pid) * c_int("branches", "expropriate_months")
	var e := state.get_empire(eid)
	e.resources["energy"] = int(e.resources.get("energy", 0)) + gain
	(state.private["br"] as Dictionary).erase(str(pid))
	(state.private["exp"] as Dictionary)["%d>%d" % [origin, eid]] = state.tick + c_int("branches", "casus_days")
	Diplomacy.remember(state, origin, eid, "branch_expropriated")
	state.add_chronicle("%s exproprie une filiale de %s : les scellés tombent sur les bureaux, %d énergie dans les caisses de l'État." % [
			e.short_name(), state.get_empire(origin).short_name(), gain], Espionage.public_to(state, [eid, origin]))


static func confiscate(state: GameState, eid: int, enemy: int) -> void:
	var gain := 0
	for pid in branches_in(state, eid, enemy):
		gain += branch_value(state, pid) * c_int("branches", "confiscate_months")
		(state.private["br"] as Dictionary).erase(str(pid))
	var e := state.get_empire(eid)
	e.resources["energy"] = int(e.resources.get("energy", 0)) + gain
	var en := _w(state, eid)
	en["sub"] = int(en.get("sub", 0)) + c_int("confidence", "confiscation")
	Diplomacy.remember(state, enemy, eid, "accounts_confiscated")
	(state.private["exp"] as Dictionary)["%d>%d" % [enemy, eid]] = state.tick + c_int("branches", "casus_days")
	state.add_chronicle("%s confisque les comptes de %s : %d énergie saisie, et quelques coffres-forts de collection." % [
			e.short_name(), state.get_empire(enemy).short_name(), gain], Espionage.public_to(state, [eid, enemy]))


## Revenus des filiales : l'hôte en touche aussi un peu (en énergie, au bilan).
static func _branches(state: GameState, _added: Array[Dictionary]) -> void:
	var br: Dictionary = state.private["br"]
	for k in br.keys():
		var b: Dictionary = br[k]
		var c: Colony = state.colonies.get(int(k))
		if c == null or company(state, int(b["c"])).is_empty() or GameState.is_npc(c.owner) or not applies(state, c.owner):
			br.erase(k)
			continue
		if c.owner == int(b["o"]):
			br.erase(k)  # conquise par le pays d'origine : elle n'est plus à l'étranger
			continue
		_add(_w(state, c.owner)["to"], "energy", c_int("branches", "host"))


static func expropriation_casus(state: GameState, a: int, b: int) -> bool:
	return not state.private.is_empty() and int((state.private["exp"] as Dictionary).get("%d>%d" % [a, b], 0)) > state.tick


# --- Actions (prop. 25) ------------------------------------------------------------------------

static func share_price(c: Dictionary) -> int:
	return c_int("shares", "base") + c_int("shares", "per_pr") * int(c.get("pr", 0))


static func buy_shares(state: GameState, eid: int, cid: int) -> void:
	var c := company(state, cid)
	var e := state.get_empire(eid)
	var price := share_price(c)
	e.resources["energy"] = int(e.resources.get("energy", 0)) - price
	var oen := _w(state, int(c["o"]))
	oen["cap"] = int(oen["cap"]) + price
	var sh: Dictionary = c["sh"]
	sh[str(eid)] = int(sh.get(str(eid), 0)) + 1


static func _dividends(state: GameState, e: Empire, en: Dictionary) -> void:
	for c in companies_of(state, e.id):
		for k in c.get("sh", {}):
			@warning_ignore("integer_division")
			var d := int(c["sh"][k]) * int(c["pr"]) * c_int("shares", "div_pct") / 100
			d = mini(d, maxi(0, int(en["cap"])))
			if d <= 0:
				continue
			var h := state.get_empire(int(k))
			if h == null or h.eliminated:
				continue
			en["cap"] = int(en["cap"]) - d
			h.resources["energy"] = int(h.resources.get("energy", 0)) + d


static func shares_of(state: GameState, eid: int) -> Array:
	var out := []
	for c in all_companies(state):
		var n := int((c.get("sh", {}) as Dictionary).get(str(eid), 0))
		if n > 0:
			out.append([c, n])
	return out


# --- Prêteurs (prop. 24) -----------------------------------------------------------------------

static func lender_companies(state: GameState, eid: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not full(state):
		return out
	for c in companies_of(state, eid):
		if not bool(c.get("nat", false)) and int(c["pr"]) >= c_int("companies", "lender_from"):
			out.append(c)
	return out


static func lend_check(state: GameState, eid: int, cid: int, amount: int) -> String:
	var c := company(state, cid)
	if c.is_empty() or int(c["o"]) != eid or not lender_companies(state, eid).has(c):
		return "cette compagnie ne prête pas"
	if amount > c_int("companies", "lender_max"):
		return "elle ne prête pas plus de %d énergie" % c_int("companies", "lender_max")
	if capital(state, eid) < amount:
		return "la caisse privée n'a pas %d énergie" % amount
	return ""


static func lend_take(state: GameState, eid: int, amount: int) -> void:
	var en := _w(state, eid)
	en["cap"] = int(en["cap"]) - amount


static func lend_repaid(state: GameState, eid: int, amount: int) -> void:
	if applies(state, eid):
		var en := _w(state, eid)
		en["cap"] = int(en["cap"]) + amount


# --- Divers ------------------------------------------------------------------------------------

## Ravitaillement sous contrat (prop. 13) : la flotte hors zone (non coupée) est-elle servie ?
static func supplies(state: GameState, f: Fleet) -> bool:
	if state.private.is_empty() or not full(state) or not applies(state, f.owner):
		return false
	var en := entry(state, f.owner)
	if int(en.get("contract", 0)) <= 0 or usable_cargos(state, f.owner) < c_int("contract", "min_cargos"):
		return false
	if state.tick % _month() == 0:
		en["sup"] = int(en.get("sup", 0)) + 1
	return true


static func _forget(state: GameState, eid: int) -> void:
	(state.private["e"] as Dictionary).erase(str(eid))
	var st: Dictionary = state.private["st"]
	for k in st.keys():
		if int(st[k]["o"]) == eid:
			st.erase(k)
	var co: Dictionary = state.private["co"]
	for k in co.keys():
		if int(co[k]["o"]) == eid:
			co.erase(k)
	var z: Dictionary = state.private["zone"]
	for k in z.keys():
		if int(z[k]) == eid:
			z.erase(k)


static func _prune(state: GameState) -> void:
	for key in ["exp", "cr", "mk"]:
		var d: Dictionary = state.private.get(key, {})
		for k in d.keys():
			if int(d[k]) <= state.tick:
				d.erase(k)
	# Zones militaires d'un système perdu.
	var z: Dictionary = state.private["zone"]
	for k in z.keys():
		if state.system_owner(int(k)) != int(z[k]):
			z.erase(k)


static func sector_label(id: String) -> String:
	return String(sector_def(id).get("label", id))


static func charter_label(id: String) -> String:
	return String(charter_def(id).get("label", "aucune")) if id != "" else "aucune"
