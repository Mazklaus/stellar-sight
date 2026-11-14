class_name Koinon
extends RefCounted
## Le Koinon (pilier fédérations et vassaux, lot 2) : ligue de 2 à 6 empires au-dessus des alliances.
##
## - Fondation par deux alliés de longue date ; adhésion et exclusion votées ; membres associés
##   (protégés, sans voix, impôt réduit de moitié).
## - Formes (catalogue ouvert : marchande, savante, martiale, hégémonie, communion), bonus par rang ;
##   trois rangs gagnés par l'expérience, qui vient surtout de la cohésion (-100 à 100).
## - Stratège élu pour 5 ans par le synode, jamais deux mandats de suite (règle achéenne) ; en
##   Hégémonie, le plus puissant, à vie, et des voix pesées à la population.
## - Synode : admissions, exclusions (deux tiers), guerres offensives (seuls ceux qui votent pour y
##   entrent), lois, forme. La défense est automatique.
## - Lois : centralisation, politique commerciale, impôt fédéral (trésor commun, dons du Stratège).
## - Sortie : trêve avec chaque membre et mauvais souvenir ; en Hégémonie, l'accord du Stratège, ou
##   la guerre de sécession.
## Tout est dans data/koinon.json.
##
## state.koinon = {"leagues": {"<id>": ligue}, "next": prochain identifiant}
## ligue = {"id", "name", "form", "founded", "members": [], "assoc": [], "joined": {"<eid>": tick},
##          "strat", "strat_until", "strat_prev", "coh", "xp", "laws": {famille: cran}, "treasury",
##          "votes": [{"id", "kind", "x", "s", "by", "until", "yes": [], "no": [], "ballots": {}}], "vid",
##          "consigne": 0}

const VOTE_KINDS: Array[String] = ["admit", "exclude", "war", "law", "form", "elect"]


static func data() -> Dictionary:
	return GameData.koinon()


static func _blank() -> Dictionary:
	return {"leagues": {}, "next": 1}


static func setup(state: GameState, mode: String) -> void:
	state.koinon_on = mode == "actif"
	state.koinon = _blank()


static func to_dict(state: GameState) -> Dictionary:
	var d: Dictionary = state.koinon.duplicate(true)
	d["on"] = state.koinon_on
	return d


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.koinon_on = bool(d.get("on", false))
	state.koinon = _blank()
	state.koinon["leagues"] = Vassals._ints(d.get("leagues", {}))
	state.koinon["next"] = int(d.get("next", 1))


static func _name(state: GameState, eid: int) -> String:
	var e := state.get_empire(eid)
	return e.display_name() if e != null else "?"


static func _leagues(state: GameState) -> Dictionary:
	if not state.koinon.has("leagues"):
		state.koinon = _blank()
	return state.koinon["leagues"]


static func league(state: GameState, lid: int) -> Dictionary:
	return _leagues(state).get(str(lid), {})


static func league_ids(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for k in _leagues(state):
		out.append(int(k))
	out.sort()
	return out


## Ligue dont eid est membre ou associé (-1 sinon).
static func league_of(state: GameState, eid: int) -> int:
	for k in _leagues(state):
		var l: Dictionary = _leagues(state)[k]
		if (l["members"] as Array).has(eid) or (l["assoc"] as Array).has(eid):
			return int(k)
	return -1


static func is_member(state: GameState, eid: int) -> bool:
	var l := league(state, league_of(state, eid))
	return not l.is_empty() and (l["members"] as Array).has(eid)


static func is_assoc(state: GameState, eid: int) -> bool:
	var l := league(state, league_of(state, eid))
	return not l.is_empty() and (l["assoc"] as Array).has(eid)


static func same_league(state: GameState, a: int, b: int) -> bool:
	var la := league_of(state, a)
	return la >= 0 and la == league_of(state, b)


static func members_of(state: GameState, lid: int) -> Array[int]:
	var out: Array[int] = []
	for m in league(state, lid).get("members", []):
		out.append(int(m))
	out.sort()
	return out


static func all_of(state: GameState, lid: int) -> Array[int]:
	var out := members_of(state, lid)
	for m in league(state, lid).get("assoc", []):
		out.append(int(m))
	out.sort()
	return out


## Jours d'appartenance (pour le délai de grâce des victoires).
static func member_days(state: GameState, eid: int) -> int:
	var l := league(state, league_of(state, eid))
	if l.is_empty():
		return 0
	return state.tick - int(l["joined"].get(str(eid), state.tick))


# --- Catalogues ----------------------------------------------------------------------------------

static func form_defs() -> Array:
	return data().get("forms", [])


static func form(fid: String) -> Dictionary:
	for f in form_defs():
		if String(f["id"]) == fid:
			return f
	return {}


static func form_label(fid: String) -> String:
	return String(form(fid).get("label", fid))


static func law_defs() -> Array:
	return data().get("laws", [])


static func law_def(fam: String) -> Dictionary:
	for l in law_defs():
		if String(l["id"]) == fam:
			return l
	return {}


static func law_step(state: GameState, lid: int, fam: String) -> int:
	return int(league(state, lid).get("laws", {}).get(fam, 0))


static func law_step_def(state: GameState, lid: int, fam: String) -> Dictionary:
	var steps: Array = law_def(fam).get("steps", [])
	var i := clampi(law_step(state, lid, fam), 0, maxi(0, steps.size() - 1))
	return steps[i] if not steps.is_empty() else {}


static func hegemony(state: GameState, lid: int) -> bool:
	return bool(form(String(league(state, lid).get("form", ""))).get("hegemony", false))


static func rank(state: GameState, lid: int) -> int:
	var xp := int(league(state, lid).get("xp", 0))
	var r := 0
	var rs: Array = data().get("ranks", [0])
	for i in rs.size():
		if xp >= int(rs[i]):
			r = i + 1
	return r


## Bonus de la forme au rang actuel (dictionnaire de valeurs).
static func form_fx(state: GameState, lid: int) -> Dictionary:
	var l := league(state, lid)
	if l.is_empty():
		return {}
	var rs: Array = form(String(l["form"])).get("ranks", [])
	var r := rank(state, lid)
	if r <= 0 or rs.is_empty():
		return {}
	return rs[mini(r, rs.size()) - 1]


## Valeur d'un bonus de forme pour un membre (les associés n'en profitent pas).
static func fx_int(state: GameState, eid: int, key: String) -> int:
	if not is_member(state, eid):
		return 0
	return int(form_fx(state, league_of(state, eid)).get(key, 0))


static func knowledge_pct(state: GameState, eid: int) -> int:
	var n := fx_int(state, eid, "knowledge_pct")
	var up := int(talent(state, eid).get("savante_rank", 0))
	if n > 0 and up > 0:
		var lid := league_of(state, eid)
		var rs: Array = form(String(league(state, lid)["form"])).get("ranks", [])
		var r := mini(rank(state, lid) + up, rs.size())
		n = int(rs[r - 1].get("knowledge_pct", n))
	return n


static func weapon_pct(state: GameState, eid: int) -> int:
	return fx_int(state, eid, "weapon_pct")


## Bonus des routes entre deux membres de la même ligue.
static func route_pct(state: GameState, a: int, b: int) -> int:
	if not same_league(state, a, b) or not is_member(state, a) or not is_member(state, b):
		return 0
	return fx_int(state, a, "route_pct")


## Palier commercial minimal entre deux empires de la même ligue (loi commerciale).
static func trade_floor(state: GameState, a: int, b: int) -> int:
	if not same_league(state, a, b):
		return 0
	return int(law_step_def(state, league_of(state, a), "trade").get("tier", 0))


## Opinion entre membres : forme (Communion) et centralisation.
static func opinion_bonus(state: GameState, a: int, b: int) -> int:
	if not same_league(state, a, b):
		return 0
	var lid := league_of(state, a)
	return int(form_fx(state, lid).get("opinion", 0)) + int(law_step_def(state, lid, "central").get("opinion", 0))


static func influence_pct(state: GameState, eid: int) -> int:
	if not is_member(state, eid):
		return 0
	return int(law_step_def(state, league_of(state, eid), "central").get("influence_pct", 0))


# --- Conditions ----------------------------------------------------------------------------------

## Credo ou foi d'État, pour la Communion.
static func _faith_key(state: GameState, eid: int) -> String:
	if state.faith_on:
		return "f:" + String(Faiths.state_faith(state, eid))
	return "c:" + String(Diplomacy._species(state, eid).get("credo", ""))


## Même foi, ou la loi de Tolérance des deux côtés (religion, prop. 27).
static func _faith_ok(state: GameState, a: int, b: int) -> bool:
	if _faith_key(state, a) == _faith_key(state, b):
		return true
	return state.politics_on and Laws.is_enacted(state, a, "tolerance") and Laws.is_enacted(state, b, "tolerance")


static func _ok_empire(state: GameState, eid: int) -> String:
	var e := state.get_empire(eid)
	if e == null or e.eliminated or GameState.is_npc(eid):
		return "empire inconnu"
	if Diplomacy.no_treaties(state, eid):
		return "l'Essaim ne signe rien : il digère"
	if Vassals.is_subject(state, eid):
		return "%s est un sujet : son suzerain parle pour lui" % e.short_name()
	if bool(talent(state, eid).get("no_koinon", false)):
		return "%s n'a ni maîtres ni pairs" % e.short_name()
	return ""


static func check_found(state: GameState, a: int, b: int, fid: String) -> String:
	if not state.koinon_on:
		return "le Koinon n'est pas actif dans cette partie"
	for x in [a, b]:
		var why := _ok_empire(state, int(x))
		if why != "":
			return why
		if league_of(state, int(x)) >= 0:
			return "%s appartient déjà à un Koinon" % state.get_empire(int(x)).short_name()
	if a == b or not state.get_empire(a).contacts.has(b):
		return "il faut un allié"
	if form(fid).is_empty():
		return "forme inconnue : %s" % fid
	if not Diplomacy.allied(state, a, b):
		return "il faut une alliance"
	var need := int(data()["found"]["alliance_days"])
	if Diplomacy.team_of(state, a, b) <= 0 and Diplomacy.pact_days(state, a, b) < need and not bool(talent(state, a).get("quick_found", false)):
		return "il faut %d ans d'alliance (encore %d jours)" % [need / GameCalendar.DAYS_PER_YEAR, need - Diplomacy.pact_days(state, a, b)]
	if bool(form(fid).get("faith", false)) and not _faith_ok(state, a, b):
		return "une Communion exige une même foi (ou la Tolérance des deux côtés)"
	if state.get_empire(b).is_ai() and Diplomacy.opinion(state, b, a) < 0:
		return "%s ne veut pas lier son sort au vôtre (opinion négative)" % state.get_empire(b).short_name()
	var cost: Dictionary = data()["found"]["cost"]
	for x in [a, b]:
		if not Economy.can_afford(state.get_empire(int(x)), cost):
			return "%s n'a pas %s" % [state.get_empire(int(x)).short_name(), GameData.format_amounts(cost)]
	return ""


## Talent de peuple pour le Koinon (couches d'espèce, table commune avec les sujets : voir Vassals.talent).
static func talent(state: GameState, eid: int) -> Dictionary:
	return Vassals.talent(state, eid)


static func found(state: GameState, a: int, b: int, fid: String) -> int:
	var cost: Dictionary = data()["found"]["cost"]
	Economy.pay(state.get_empire(a), cost)
	Economy.pay(state.get_empire(b), cost)
	var lid := int(state.koinon.get("next", 1))
	state.koinon["next"] = lid + 1
	var l := {"id": lid, "name": "%s de %s" % [form_label(fid), state.get_empire(a).short_name()], "form": fid, "founded": state.tick,
			"members": [a, b], "assoc": [], "joined": {str(a): state.tick, str(b): state.tick},
			"strat": a, "strat_until": state.tick + int(data()["term_days"]), "strat_prev": -1,
			"coh": int(data()["cohesion"]["start"]), "xp": 0, "laws": {}, "treasury": 0, "votes": [], "vid": 1, "consigne": 0}
	for law in law_defs():
		l["laws"][String(law["id"])] = 0
	_leagues(state)[str(lid)] = l
	if hegemony(state, lid):
		l["strat"] = _strongest(state, lid)
	Politics.on_act(state, a, "koinon")
	Politics.on_act(state, b, "koinon")
	state.relic_rev += 1
	state.add_chronicle("%s et %s fondent un Koinon : %s. Un synode, un Stratège, et des serments plus longs que les traités." % [
			_name(state, a), _name(state, b), String(l["name"])], Espionage.public_to(state, [a, b]))
	return lid


static func _strongest(state: GameState, lid: int) -> int:
	var best := -1
	var bp := -1
	for m in members_of(state, lid):
		var p := Vassals.power(state, m)
		if p > bp:
			best = m
			bp = p
	return best


# --- Votes du synode ---------------------------------------------------------------------------

## Poids d'une voix (population en Hégémonie, 1 sinon).
static func weight(state: GameState, lid: int, eid: int) -> int:
	if not hegemony(state, lid):
		return 1
	return maxi(1, int(EmpireReport.totals(state, eid)["population"]))


static func vote(state: GameState, lid: int, vid: int) -> Dictionary:
	for v in league(state, lid).get("votes", []):
		if int(v["id"]) == vid:
			return v
	return {}


static func pending_kind(state: GameState, lid: int, kind: String, x: int, s := "") -> bool:
	for v in league(state, lid).get("votes", []):
		if String(v["kind"]) == kind and int(v["x"]) == x and String(v["s"]) == s:
			return true
	return false


## Ce qu'une proposition du synode demanderait ; "" si elle peut être déposée.
static func check_propose(state: GameState, by: int, kind: String, x: int, s: String) -> String:
	if not state.koinon_on:
		return "le Koinon n'est pas actif dans cette partie"
	var lid := league_of(state, by)
	if kind == "admit":
		lid = league_of(state, x)
		if lid < 0:
			return "cet empire n'est dans aucun Koinon"
		var why := _ok_empire(state, by)
		if why != "":
			return why
		if league_of(state, by) >= 0:
			return "vous appartenez déjà à un Koinon"
		if s != "member" and s != "assoc":
			return "adhésion inconnue"
		if s == "member" and members_of(state, lid).size() >= int(data()["found"]["max_members"]):
			return "le Koinon a déjà %d membres" % int(data()["found"]["max_members"])
		var any := false
		for m in members_of(state, lid):
			if state.get_empire(by).contacts.has(m):
				any = true
			if Combat.at_war(state, by, m):
				return "vous êtes en guerre avec un membre"
		if not any:
			return "vous ne connaissez aucun membre"
		var l := league(state, lid)
		if s == "member" and bool(form(String(l["form"])).get("faith", false)) and not _faith_ok(state, by, int(l["members"][0])):
			return "une Communion exige une même foi (ou la Tolérance des deux côtés)"
		if s == "member" and not Economy.can_afford(state.get_empire(by), data()["join_cost"]):
			return "il faut %s" % GameData.format_amounts(data()["join_cost"])
		if pending_kind(state, lid, "admit", by, s):
			return "demande déjà déposée"
		return _check_cd(state, lid, _cd_key("admit", by, x, s))
	if lid < 0 or not is_member(state, by):
		return "seuls les membres du Koinon proposent"
	if pending_kind(state, lid, kind, x, s):
		return "déjà au vote"
	var cdw := _check_cd(state, lid, _cd_key(kind, by, x, s))
	if cdw != "":
		return cdw
	match kind:
		"exclude":
			if not all_of(state, lid).has(x) or x == by:
				return "il faut un autre membre ou associé"
		"war":
			var t := state.get_empire(x)
			if t == null or t.eliminated or same_league(state, by, x):
				return "cible invalide"
			if not state.get_empire(by).contacts.has(x):
				return "vous n'avez jamais rencontré cet empire"
		"law":
			var ld := law_def(s)
			if ld.is_empty():
				return "loi inconnue"
			var steps: Array = ld["steps"]
			if x < 0 or x >= steps.size() or x == law_step(state, lid, s):
				return "cran invalide"
			if absi(x - law_step(state, lid, s)) != 1:
				return "un cran à la fois"
			var need := int(steps[x].get("rank", 1))
			if s == "central" and state.politics_on and Laws.is_enacted(state, by, "hegemonie"):
				need -= 1
			if x > law_step(state, lid, s) and rank(state, lid) < need:
				return "il faut le rang %d" % need
		"form":
			if form(s).is_empty() or s == String(league(state, lid)["form"]):
				return "forme invalide"
			if bool(form(s).get("faith", false)):
				for m in members_of(state, lid):
					if not _faith_ok(state, by, m):
						return "une Communion exige une même foi (ou la Tolérance des deux côtés)"
		_:
			return "proposition inconnue"
	return ""


## Clé du délai après un rejet : une demande d'entrée par empire, sinon le genre, la cible et le détail.
static func _cd_key(kind: String, by: int, x: int, s: String) -> String:
	return "admit:%d" % by if kind == "admit" else "%s:%d:%s" % [kind, x, s]


static func _check_cd(state: GameState, lid: int, key: String) -> String:
	var left := int(league(state, lid).get("cd", {}).get(key, 0)) - state.tick
	if left > 0:
		return "le synode l'a rejeté : attendez encore %d jours" % left
	return ""


## Dépose une proposition : les membres IA votent tout de suite ; tranchée quand tous ont voté ou au terme.
static func propose(state: GameState, by: int, kind: String, x: int, s: String) -> void:
	var lid := league_of(state, x) if kind == "admit" else league_of(state, by)
	var l := league(state, lid)
	# Adhésion : x désigne un membre pour trouver la ligue ; le vote porte sur le candidat.
	if kind == "admit":
		x = by
	var v := {"id": int(l["vid"]), "kind": kind, "x": x, "s": s, "by": by, "until": state.tick + int(data()["vote_days"]), "yes": [], "no": [], "ballots": {}}
	l["vid"] = int(l["vid"]) + 1
	(l["votes"] as Array).append(v)
	if kind != "admit":
		(v["yes"] as Array).append(by)
	state.add_chronicle("Synode de %s : %s." % [String(l["name"]), vote_text(state, lid, v)], Espionage.private_to(state, all_of(state, lid) + ([by] if kind == "admit" else [])))
	_ai_votes(state, lid, v)
	_try_close(state, lid, v)


static func vote_text(state: GameState, lid: int, v: Dictionary) -> String:
	match String(v["kind"]):
		"admit":
			return "%s demande à entrer%s" % [_name(state, int(v["x"])), " comme associé" if String(v["s"]) == "assoc" else ""]
		"exclude":
			return "exclure %s" % _name(state, int(v["x"]))
		"war":
			return "guerre contre %s" % _name(state, int(v["x"]))
		"law":
			return "%s : %s" % [String(law_def(String(v["s"])).get("label", "")), String(law_def(String(v["s"]))["steps"][int(v["x"])]["label"])]
		"form":
			return "devenir %s" % form_label(String(v["s"])).to_lower()
		"elect":
			return "élection du Stratège"
	return String(v["kind"])


## Peut-on voter ? "" si oui.
static func check_vote(state: GameState, eid: int, vid: int, s: String) -> String:
	var lid := league_of(state, eid)
	if lid < 0 or not is_member(state, eid):
		return "seuls les membres votent"
	var v := vote(state, lid, vid)
	if v.is_empty():
		return "vote inconnu ou clos"
	if String(v["kind"]) == "elect":
		if not candidates(state, lid).has(int(s)):
			return "candidat invalide"
		return ""
	if s != "yes" and s != "no":
		return "voix invalide"
	if String(v["kind"]) == "exclude" and int(v["x"]) == eid:
		return "on ne vote pas sa propre exclusion"
	return ""


static func cast(state: GameState, eid: int, vid: int, s: String) -> void:
	var lid := league_of(state, eid)
	var v := vote(state, lid, vid)
	(v["yes"] as Array).erase(eid)
	(v["no"] as Array).erase(eid)
	if String(v["kind"]) == "elect":
		v["ballots"][str(eid)] = int(s)
	else:
		(v["yes" if s == "yes" else "no"] as Array).append(eid)
	_try_close(state, lid, v)


static func _voters(state: GameState, lid: int, v: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for m in members_of(state, lid):
		if String(v["kind"]) == "exclude" and m == int(v["x"]):
			continue
		out.append(m)
	return out


static func _voted(v: Dictionary, m: int) -> bool:
	return (v["yes"] as Array).has(m) or (v["no"] as Array).has(m) or (v["ballots"] as Dictionary).has(str(m))


static func _try_close(state: GameState, lid: int, v: Dictionary, force := false) -> void:
	if league(state, lid).is_empty():
		return
	var all_in := true
	for m in _voters(state, lid, v):
		if not _voted(v, m):
			all_in = false
	if all_in or force or state.tick >= int(v["until"]):
		_close(state, lid, v)


static func _close(state: GameState, lid: int, v: Dictionary) -> void:
	var l := league(state, lid)
	(l["votes"] as Array).erase(v)
	if String(v["kind"]) == "elect":
		_elect(state, lid, v)
		return
	var total := 0
	var yes := 0
	for m in _voters(state, lid, v):
		var w := weight(state, lid, m)
		total += w
		if (v["yes"] as Array).has(m):
			yes += w
	var passed := yes * 100 >= total * int(data()["exclude_pct"]) if String(v["kind"]) == "exclude" else yes * 2 > total
	var audience := all_of(state, lid)
	if String(v["kind"]) == "admit":
		audience.append(int(v["x"]))
	if not passed:
		_coh(state, lid, int(data()["cohesion"]["failed_vote"]))
		if not l.has("cd"):
			l["cd"] = {}
		l["cd"][_cd_key(String(v["kind"]), int(v["by"]), int(v["x"]), String(v["s"]))] = state.tick + int(data().get("refused_days", 360))
		state.add_chronicle("Synode de %s : rejeté (%s)." % [String(l["name"]), vote_text(state, lid, v)], Espionage.private_to(state, audience))
		return
	state.add_chronicle("Synode de %s : adopté (%s)." % [String(l["name"]), vote_text(state, lid, v)], Espionage.private_to(state, audience))
	var x := int(v["x"])
	match String(v["kind"]):
		"admit":
			if league_of(state, x) >= 0 or _ok_empire(state, x) != "":
				return
			if String(v["s"]) == "member":
				Economy.pay(state.get_empire(x), data()["join_cost"])
				(l["members"] as Array).append(x)
			else:
				(l["assoc"] as Array).append(x)
			l["joined"][str(x)] = state.tick
			_coh(state, lid, int(data()["cohesion"]["join"]))
			Politics.on_act(state, x, "koinon")
			for m in all_of(state, lid):
				if m != x and Combat.at_war(state, m, x):
					Diplomacy.sign_treaty(state, m, x, Diplomacy.PEACE)
			state.relic_rev += 1
		"exclude":
			_remove(state, lid, x, "exclu par le synode")
		"war":
			for m in v["yes"]:
				var mi := int(m)
				if Combat.check_declare_war(state, mi, x) == "":
					Combat.start_war(state, mi, x)
		"law":
			l["laws"][String(v["s"])] = x
			if x > 0:
				_coh(state, lid, int(data()["cohesion"]["law_step"]))
		"form":
			l["form"] = String(v["s"])
			l["xp"] = 0
			l["name"] = "%s de %s" % [form_label(String(v["s"])), state.get_empire(int(l["members"][0])).short_name()]
			if hegemony(state, lid):
				l["strat"] = _strongest(state, lid)
			state.relic_rev += 1


# --- Stratège ---------------------------------------------------------------------------------------

## Candidats : tous les membres, sauf le Stratège sortant (règle achéenne).
static func candidates(state: GameState, lid: int) -> Array[int]:
	var l := league(state, lid)
	var out: Array[int] = []
	for m in members_of(state, lid):
		if m == int(l.get("strat", -1)) and not bool(talent(state, m).get("reelect", false)):
			continue
		out.append(m)
	return out


static func strategos(state: GameState, lid: int) -> int:
	return int(league(state, lid).get("strat", -1))


static func _open_election(state: GameState, lid: int) -> void:
	var l := league(state, lid)
	if pending_kind(state, lid, "elect", -1, ""):
		return
	var v := {"id": int(l["vid"]), "kind": "elect", "x": -1, "s": "", "by": -1, "until": state.tick + int(data()["vote_days"]), "yes": [], "no": [], "ballots": {}}
	l["vid"] = int(l["vid"]) + 1
	(l["votes"] as Array).append(v)
	_ai_votes(state, lid, v)
	_try_close(state, lid, v)


static func _elect(state: GameState, lid: int, v: Dictionary) -> void:
	var l := league(state, lid)
	var cands := candidates(state, lid)
	if cands.is_empty():
		cands = members_of(state, lid)
	var score := {}
	for m in v["ballots"]:
		var c := int(v["ballots"][m])
		if cands.has(c):
			score[c] = int(score.get(c, 0)) + 1
	var best := -1
	var bs := -1
	for c in cands:
		var s := int(score.get(c, 0)) * 100000 + Vassals.power(state, c)
		if s > bs:
			best = c
			bs = s
	l["strat_prev"] = int(l["strat"])
	l["strat"] = best
	l["strat_until"] = state.tick + int(data()["term_days"])
	state.add_chronicle("Le synode de %s élit %s Stratège pour cinq ans." % [String(l["name"]), _name(state, best)], Espionage.private_to(state, all_of(state, lid)))


# --- Sortie, exclusion, dissolution ---------------------------------------------------------------

static func check_leave(state: GameState, eid: int) -> String:
	if league_of(state, eid) < 0:
		return "vous n'êtes dans aucun Koinon"
	return ""


## Départ : libre (trêve avec chaque membre, mauvais souvenir), ou en Hégémonie l'accord du Stratège.
static func leave(state: GameState, eid: int) -> void:
	var lid := league_of(state, eid)
	var strat := strategos(state, lid)
	if hegemony(state, lid) and is_member(state, eid) and strat != eid and strat >= 0:
		var es := state.get_empire(strat)
		if es.is_ai():
			if Vassals.power(state, eid) * 2 >= Vassals.power(state, strat) or int(league(state, lid)["coh"]) < 0:
				_leave_now(state, lid, eid)
			else:
				_secede(state, lid, eid)
			return
		state.proposals.append({"id": state.next_proposal_id, "from": eid, "to": strat, "treaty": "secede", "tick": state.tick, "terms": {}})
		state.next_proposal_id += 1
		state.add_chronicle("%s demande au Stratège %s la permission de quitter %s." % [_name(state, eid), _name(state, strat), String(league(state, lid)["name"])],
				Espionage.private_to(state, [eid, strat]))
		return
	_leave_now(state, lid, eid)


static func _leave_now(state: GameState, lid: int, eid: int) -> void:
	var l := league(state, lid)
	var others := all_of(state, lid)
	others.erase(eid)
	_remove(state, lid, eid, "il quitte le Koinon")
	for m in others:
		Diplomacy.remember(state, m, eid, "left_koinon")
		var r := Diplomacy._rel_w(state, m, eid)
		if Combat.at_war(state, m, eid):
			continue
		if String(r["pact"]) == Diplomacy.COLD:
			r["pact"] = Diplomacy.PEACE
			r["since"] = state.tick
		r["truce"] = maxi(int(r.get("truce", 0)), state.tick + int(data()["leave"]["truce_days"]))
	if not l.is_empty():
		_coh(state, lid, int(data()["cohesion"]["leave"]))


## Le Stratège refuse : guerre de sécession (sans parjure).
static func _secede(state: GameState, lid: int, eid: int) -> void:
	var strat := strategos(state, lid)
	_remove(state, lid, eid, "le Stratège lui refuse la sortie : sécession")
	var r := Diplomacy._rel_w(state, eid, strat)
	r["pact"] = Diplomacy.COLD
	r["truce"] = 0
	if not Combat.at_war(state, eid, strat):
		Combat.start_war(state, eid, strat)


static func answer_secede(state: GameState, p: Dictionary, accept: bool) -> void:
	var eid := int(p["from"])
	var lid := league_of(state, eid)
	if lid < 0:
		return
	if accept:
		_leave_now(state, lid, eid)
	else:
		_secede(state, lid, eid)


static func check_accept_secede(state: GameState, p: Dictionary) -> String:
	var lid := league_of(state, int(p["from"]))
	if lid < 0 or strategos(state, lid) != int(p["to"]):
		return "la demande n'a plus d'objet"
	return ""


static func _remove(state: GameState, lid: int, eid: int, why: String) -> void:
	var l := league(state, lid)
	if l.is_empty():
		return
	(l["members"] as Array).erase(eid)
	(l["assoc"] as Array).erase(eid)
	(l["joined"] as Dictionary).erase(str(eid))
	state.relic_rev += 1
	if why != "":
		state.add_chronicle("%s n'est plus dans %s : %s." % [_name(state, eid), String(l["name"]), why], Espionage.public_to(state, all_of(state, lid) + [eid]))
	if (l["members"] as Array).size() < 2:
		_dissolve(state, lid)
		return
	if int(l["strat"]) == eid:
		if hegemony(state, lid):
			l["strat"] = _strongest(state, lid)
		else:
			l["strat"] = members_of(state, lid)[0]
			_open_election(state, lid)


static func _dissolve(state: GameState, lid: int) -> void:
	var l := league(state, lid)
	var who := all_of(state, lid)
	for fid in federal_fleets(state, lid):
		state.fleets.erase(fid)
	_leagues(state).erase(str(lid))
	state.relic_rev += 1
	state.add_chronicle("%s est dissous : il ne reste plus assez de membres pour tenir un synode." % String(l["name"]), Espionage.public_to(state, who))


# --- Cohésion, expérience, mensuel -------------------------------------------------------------------

static func _coh(state: GameState, lid: int, d: int) -> void:
	var l := league(state, lid)
	if l.is_empty():
		return
	var c: Dictionary = data()["cohesion"]
	l["coh"] = clampi(int(l["coh"]) + d, int(c["min"]), int(c["max"]))


static func cohesion(state: GameState, lid: int) -> int:
	return int(league(state, lid).get("coh", 0))


## Tendance mensuelle de la cohésion : [{label, value}].
static func cohesion_parts(state: GameState, lid: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var l := league(state, lid)
	if l.is_empty():
		return out
	var c: Dictionary = data()["cohesion"]
	var ms := members_of(state, lid)
	_part(out, "Vie commune", int(c["habit"]))
	_part(out, "Membres (%d)" % ms.size(), int(c["per_member"]) * maxi(0, ms.size() - 2))
	var credos := {}
	var govs := {}
	for m in ms:
		var sp := Diplomacy._species(state, m)
		credos[String(sp.get("credo", ""))] = true
		govs[String(sp.get("gouvernement", ""))] = true
	var strat := int(l.get("strat", -1))
	var faith_free := bool(form(String(l["form"])).get("faith", false)) and bool(talent(state, strat).get("communion_free", false))
	_part(out, "Credos différents", 0 if faith_free else int(c["per_credo"]) * maxi(0, credos.size() - 1))
	_part(out, "Gouvernements différents", int(c["per_gov"]) * maxi(0, govs.size() - 1))
	var heg_law := state.politics_on and strat >= 0 and Laws.is_enacted(state, strat, "hegemonie")
	_part(out, "Centralisation", 0 if heg_law else int(c["per_central"]) * law_step(state, lid, "central"))
	# Délégués au Koinon (héros) : selon leur niveau.
	var dl := 0
	for m in ms:
		var h := Heroes.at_post(state, "koinon", 0, m)
		if not h.is_empty():
			@warning_ignore("integer_division")
			dl += maxi(1, Heroes.half_levels(h, "koinon") / 2)
	_part(out, "Délégués au Koinon", dl)
	var common := false
	for m in ms:
		for w in state.get_empire(m).wars:
			for o in ms:
				if o != m and state.get_empire(o).wars.has(w):
					common = true
	if common:
		_part(out, "Guerre commune", int(c["common_war"]))
	return out


static func _part(out: Array[Dictionary], label: String, value: int) -> void:
	if value != 0:
		out.append({"label": label, "value": value})


static func cohesion_trend(state: GameState, lid: int) -> int:
	var n := 0
	for p in cohesion_parts(state, lid):
		n += int(p["value"])
	return n


## Appelé chaque mois par DiplomacySystem.
static func monthly(state: GameState) -> void:
	for lid in league_ids(state):
		var l := league(state, lid)
		if l.is_empty():
			continue
		for m in all_of(state, lid):
			var e := state.get_empire(m)
			if e == null or e.eliminated or Vassals.is_subject(state, m):
				_remove(state, lid, m, "" if e == null or e.eliminated else "il est devenu sujet")
		l = league(state, lid)
		if l.is_empty():
			continue
		# Stratège : l'hégémon à vie, ou l'élection tous les cinq ans.
		if hegemony(state, lid):
			if not members_of(state, lid).has(int(l["strat"])):
				l["strat"] = _strongest(state, lid)
		elif state.tick >= int(l["strat_until"]):
			_open_election(state, lid)
		_coh(state, lid, cohesion_trend(state, lid))
		var xc: Dictionary = data()["xp"]
		if int(l["coh"]) >= 0:
			@warning_ignore("integer_division")
			l["xp"] = int(l["xp"]) + int(xc["base"]) + int(l["coh"]) / maxi(1, int(xc["coh_div"]))
		else:
			l["xp"] = maxi(0, int(l["xp"]) - int(xc["loss"]))
		# Impôt fédéral.
		var pct := int(law_step_def(state, lid, "tax").get("pct", 0))
		if pct > 0:
			for m in all_of(state, lid):
				var p := pct
				if is_assoc(state, m):
					@warning_ignore("integer_division")
					p = pct * int(data()["assoc_tax_pct"]) / 100
				var em := state.get_empire(m)
				@warning_ignore("integer_division")
				var n := maxi(0, int(Economy.empire_income(state, m)["net"].get("energy", 0))) * p / 100
				n = mini(n, maxi(0, int(em.resources.get("energy", 0))))
				em.resources["energy"] = int(em.resources.get("energy", 0)) - n
				l["treasury"] = int(l["treasury"]) + n
		# Bonus d'influence de la forme.
		var fx := form_fx(state, lid)
		for m in members_of(state, lid):
			var inf := int(fx.get("influence", 0)) + (int(fx.get("strat_influence", 0)) if m == int(l["strat"]) else 0)
			if inf > 0:
				var em := state.get_empire(m)
				em.resources["influence"] = int(em.resources.get("influence", 0)) + inf
		if bool(law_step_def(state, lid, "central").get("maps", false)):
			var ms := members_of(state, lid)
			for i in ms.size():
				for j in range(i + 1, ms.size()):
					Diplomacy.share_maps(state, ms[i], ms[j])
		for v in (l["votes"] as Array).duplicate():
			_try_close(state, lid, v)
		if not league(state, lid).is_empty():
			_federal_month(state, lid)
			_joint_month(state, lid)


# --- Guerres -----------------------------------------------------------------------------------------

## Ce qui s'ajoute à Diplomacy.check_war.
static func check_war(state: GameState, a: int, b: int) -> String:
	if same_league(state, a, b):
		return "membres du même Koinon"
	return ""


## Défense automatique (appelé par Diplomacy.on_war_declared, a déclare à b).
static func on_war_declared(state: GameState, a: int, b: int, joined: bool) -> void:
	if _leagues(state).is_empty():
		return
	if same_league(state, a, b):
		_remove(state, league_of(state, a), a, "il a attaqué un autre membre")
	if joined:
		return
	var lid := league_of(state, b)
	if lid < 0:
		return
	for m in all_of(state, lid):
		if m == b or m == a:
			continue
		var e := state.get_empire(m)
		if e.eliminated or Combat.at_war(state, m, a) or not e.contacts.has(a) or Diplomacy.in_truce(state, m, a) or Diplomacy.allied(state, m, a):
			continue
		if Vassals.lord_of(state, a) == m or Vassals.lord_of(state, m) == a:
			continue
		Combat.start_war(state, m, a, false, true)
		state.add_chronicle("%s honore le Koinon et entre en guerre contre %s pour défendre %s." % [e.display_name(), _name(state, a), _name(state, b)],
				Espionage.public_to(state, [m, a, b]))


## Paix signée : une guerre commune gagnée soude la ligue.
static func on_peace(state: GameState, a: int, b: int, score_a: int) -> void:
	if _leagues(state).is_empty():
		return
	var la := league_of(state, a)
	if la >= 0 and score_a > 0 and members_of(state, la).size() >= 2:
		var other := 0
		for m in members_of(state, la):
			if m != a and Combat.at_war(state, m, b):
				other += 1
		if other > 0:
			_coh(state, la, int(data()["cohesion"]["war_won"]))


# --- Trésor ----------------------------------------------------------------------------------------

static func check_grant(state: GameState, eid: int, to: int, n: int) -> String:
	var lid := league_of(state, eid)
	if lid < 0 or strategos(state, lid) != eid:
		return "seul le Stratège dispose du trésor"
	if not all_of(state, lid).has(to):
		return "il faut un membre ou un associé"
	if n <= 0 or n > int(data()["grant_max"]):
		return "de 1 à %d énergie à la fois" % int(data()["grant_max"])
	if int(league(state, lid)["treasury"]) < n:
		return "le trésor n'a que %d énergie" % int(league(state, lid)["treasury"])
	return ""


static func grant(state: GameState, eid: int, to: int, n: int) -> void:
	var l := league(state, league_of(state, eid))
	l["treasury"] = int(l["treasury"]) - n
	var e := state.get_empire(to)
	e.resources["energy"] = int(e.resources.get("energy", 0)) + n
	state.add_chronicle("Le Stratège de %s verse %d énergie du trésor commun à %s." % [String(l["name"]), n, _name(state, to)], Espionage.private_to(state, all_of(state, league_of(state, eid))))


# --- Amphictyonie : consigne de vote ------------------------------------------------------------------

static func check_consigne(state: GameState, eid: int, v: int) -> String:
	var lid := league_of(state, eid)
	if lid < 0 or strategos(state, lid) != eid:
		return "seul le Stratège donne une consigne"
	if not Amphictyony.in_session(state):
		return "aucune séance de l'Amphictyonie en cours"
	if v < -1 or v > 1:
		return "consigne invalide"
	return ""


static func set_consigne(state: GameState, eid: int, v: int) -> void:
	league(state, league_of(state, eid))["consigne"] = v


static func consigne(state: GameState, eid: int) -> int:
	var lid := league_of(state, eid)
	return int(league(state, lid).get("consigne", 0)) if lid >= 0 else 0


## Séance close : les membres qui ont suivi la consigne soudent la ligue, les autres l'abîment.
static func on_amph_close(state: GameState, votes: Dictionary) -> void:
	for lid in league_ids(state):
		var l := league(state, lid)
		var c := int(l.get("consigne", 0))
		if c == 0:
			continue
		for m in members_of(state, lid):
			var v := int(votes.get(str(m), 0))
			if v == c:
				_coh(state, lid, int(data()["cohesion"]["consigne_kept"]))
			elif v == -c:
				_coh(state, lid, int(data()["cohesion"]["consigne_broken"]))
		l["consigne"] = 0


# --- IA dans le synode --------------------------------------------------------------------------------

static func _ai_votes(state: GameState, lid: int, v: Dictionary) -> void:
	for m in _voters(state, lid, v):
		var e := state.get_empire(m)
		if not e.is_ai() or _voted(v, m):
			continue
		if String(v["kind"]) == "elect":
			v["ballots"][str(m)] = AiKoinon.elect_choice(state, m, candidates(state, lid))
		else:
			var side: Array = v["yes"] if AiKoinon.vote_yes(state, m, lid, v) else v["no"]
			side.append(m)


# --- Propositions humaines (sécession) ----------------------------------------------------------------

static func is_kind(kind: String) -> bool:
	return kind == "secede" or kind == "kfound"


static func kind_label(p: Dictionary) -> String:
	if String(p["treaty"]) == "kfound":
		return "Fonder un Koinon (%s)" % form_label(String(p.get("terms", {}).get("form", "")))
	return "Demande à quitter l'Hégémonie"


static func check_accept(state: GameState, p: Dictionary) -> String:
	if String(p["treaty"]) == "kfound":
		return check_found(state, int(p["from"]), int(p["to"]), String(p.get("terms", {}).get("form", "")))
	return check_accept_secede(state, p)


static func answer(state: GameState, p: Dictionary, accept: bool) -> void:
	if String(p["treaty"]) == "kfound":
		if accept:
			found(state, int(p["from"]), int(p["to"]), String(p["terms"]["form"]))
		else:
			Diplomacy._set_cooldown(state, int(p["from"]), int(p["to"]), "kfound", int(data().get("refused_days", 360)))
		return
	answer_secede(state, p, accept)


## Fonder avec un allié : une IA décide sur-le-champ (check_found), un joueur reçoit la proposition.
static func offer_found(state: GameState, a: int, b: int, fid: String) -> void:
	if state.get_empire(b).is_ai():
		found(state, a, b, fid)
		return
	state.proposals.append({"id": state.next_proposal_id, "from": a, "to": b, "treaty": "kfound", "tick": state.tick, "terms": {"form": fid}})
	state.next_proposal_id += 1


# --- Ordre unique --------------------------------------------------------------------------------------

static func check_act(state: GameState, player: int, act: String, x: int, s: String, n: int) -> String:
	var e := state.get_empire(player)
	if e == null or e.eliminated:
		return "empire inconnu"
	match act:
		"found":
			return check_found(state, player, x, s)
		"join":
			return check_propose(state, player, "admit", x, s)
		"propose":
			var parts := s.split(":")
			return check_propose(state, player, parts[0], x, parts[1] if parts.size() > 1 else "")
		"vote":
			return check_vote(state, player, x, s)
		"leave":
			return check_leave(state, player)
		"grant":
			return check_grant(state, player, x, n)
		"consigne":
			return check_consigne(state, player, x)
		"joint":
			return check_joint(state, player)
	return "action inconnue : %s" % act


static func act(state: GameState, player: int, act_id: String, x: int, s: String, n: int) -> void:
	match act_id:
		"found":
			offer_found(state, player, x, s)
		"join":
			propose(state, player, "admit", x, s)
		"propose":
			var parts := s.split(":")
			propose(state, player, parts[0], x, parts[1] if parts.size() > 1 else "")
		"vote":
			cast(state, player, x, s)
		"leave":
			leave(state, player)
		"grant":
			grant(state, player, x, n)
		"consigne":
			set_consigne(state, player, x)
		"joint":
			joint(state, player)


# --- Lot 3 : flotte fédérale (prop. 22) -------------------------------------------------------------

## Flottes fédérales encore vivantes d'une ligue (le Stratège les commande).
static func federal_fleets(state: GameState, lid: int) -> Array[int]:
	var out: Array[int] = []
	for fid in league(state, lid).get("fleet", []):
		if state.fleets.has(int(fid)):
			out.append(int(fid))
	return out


static func is_federal(state: GameState, fleet_id: int) -> bool:
	if not state.koinon_on:
		return false
	for lid in league_ids(state):
		if (league(state, lid).get("fleet", []) as Array).has(fleet_id):
			return true
	return false


static func federal_ships(state: GameState, lid: int) -> int:
	var n := 0
	for fid in federal_fleets(state, lid):
		n += (state.fleets[fid] as Fleet).ships.size()
	return n


## Modèle de la flotte fédérale : le premier de la liste qu'un membre sait construire ("" sinon).
static func federal_model(state: GameState, lid: int) -> String:
	for sid in data().get("federal", {}).get("ships", []):
		for m in members_of(state, lid):
			if Fleets.ship_unlocked(state, m, String(sid)):
				return String(sid)
	return ""


static func _federal_month(state: GameState, lid: int) -> void:
	var l := league(state, lid)
	var pct := int(law_step_def(state, lid, "fleet").get("fleet_pct", 0))
	var strat := int(l["strat"])
	# Le Stratège commande : les flottes fédérales le suivent.
	var alive := federal_fleets(state, lid)
	for fid in alive:
		(state.fleets[fid] as Fleet).owner = strat
	l["fleet"] = alive
	if pct <= 0:
		return
	for m in members_of(state, lid):
		var em := state.get_empire(m)
		@warning_ignore("integer_division")
		var n := maxi(0, int(Economy.empire_income(state, m)["net"].get("materials", 0))) * pct / 100
		n = mini(n, maxi(0, int(em.resources.get("materials", 0))))
		em.resources["materials"] = int(em.resources.get("materials", 0)) - n
		l["ffund"] = int(l.get("ffund", 0)) + n
	var model := federal_model(state, lid)
	var es := state.get_empire(strat)
	if model == "" or es == null or es.capital_planet < 0:
		return
	if federal_ships(state, lid) >= int(data().get("federal", {}).get("max_per_rank", 4)) * rank(state, lid):
		return
	var cost := int(Fleets.ship_cost(state, strat, model).get("materials", 0))
	if cost <= 0 or int(l.get("ffund", 0)) < cost:
		return
	l["ffund"] = int(l["ffund"]) - cost
	var sid: int = state.galaxy.get_planet(es.capital_planet).system_id
	var f: Fleet = null
	for fid in federal_fleets(state, lid):
		var ff: Fleet = state.fleets[fid]
		if ff.system_id == sid and not ff.is_moving():
			f = ff
			break
	if f == null:
		f = state.spawn_ship(strat, model, sid)
		f.fleet_name = "Flotte fédérale de %s" % String(l["name"])
		(l["fleet"] as Array).append(f.id)
	else:
		f.add_ship(model, -1, Research.mark_gen(state, strat))
	state.add_chronicle("L'arsenal de %s livre un vaisseau à la flotte fédérale : %s." % [String(l["name"]), String(GameData.ship(model).get("label", model))], Espionage.private_to(state, all_of(state, lid)))


# --- Lot 3 : opérations communes (prop. 23) ---------------------------------------------------------

static func joint_def(state: GameState, lid: int) -> Dictionary:
	return data().get("joint", {}).get("forms", {}).get(String(league(state, lid).get("form", "")), {})


static func check_joint(state: GameState, eid: int) -> String:
	var lid := league_of(state, eid)
	if lid < 0 or strategos(state, lid) != eid:
		return "seul le Stratège lance une opération commune"
	var jc: Dictionary = data().get("joint", {})
	var l := league(state, lid)
	if joint_def(state, lid).is_empty():
		return "cette forme n'a pas d'opération commune"
	if rank(state, lid) < int(jc.get("rank", 2)):
		return "il faut le rang %d" % int(jc.get("rank", 2))
	if not (l.get("joint", {}) as Dictionary).is_empty():
		return "une opération est déjà en cours"
	var last := int(l.get("joint_last", -100000))
	if state.tick - last < int(jc.get("every_days", 3600)):
		return "une par décennie (encore %d jours)" % (int(jc.get("every_days", 3600)) - (state.tick - last))
	if not state.get_empire(eid).wars.is_empty():
		return "il faut être en paix"
	if int(l["treasury"]) < int(jc.get("cost", 150)):
		return "le trésor n'a que %d énergie (il en faut %d)" % [int(l["treasury"]), int(jc.get("cost", 150))]
	return ""


static func joint_chance(state: GameState, lid: int) -> int:
	var jc: Dictionary = data().get("joint", {})
	@warning_ignore("integer_division")
	return clampi(int(jc.get("base", 50)) + cohesion(state, lid) / 2, int(jc.get("min", 15)), int(jc.get("max", 90)))


static func joint(state: GameState, eid: int) -> void:
	var lid := league_of(state, eid)
	var l := league(state, lid)
	var jc: Dictionary = data().get("joint", {})
	l["treasury"] = int(l["treasury"]) - int(jc.get("cost", 150))
	l["joint"] = {"until": state.tick + int(jc.get("days", 180)), "form": String(l["form"])}
	l["joint_last"] = state.tick
	state.add_chronicle("%s lance une opération commune : %s." % [String(l["name"]), String(joint_def(state, lid).get("label", ""))], Espionage.private_to(state, all_of(state, lid)))


static func _joint_month(state: GameState, lid: int) -> void:
	var l := league(state, lid)
	var j: Dictionary = l.get("joint", {})
	if j.is_empty() or state.tick < int(j["until"]):
		return
	l["joint"] = {}
	var jc: Dictionary = data().get("joint", {})
	var jd: Dictionary = data().get("joint", {}).get("forms", {}).get(String(j["form"]), {})
	var roll := posmod(hash([state.seed_value, "koi_joint", lid, int(j["until"])]), 100)
	if roll >= joint_chance(state, lid):
		_coh(state, lid, int(jc.get("fail_coh", -10)))
		state.add_chronicle("L'opération commune de %s échoue (%s) : chacun accuse l'autre." % [String(l["name"]), String(jd.get("label", ""))], Espionage.private_to(state, all_of(state, lid)))
		return
	_coh(state, lid, int(jc.get("coh", 15)))
	l["xp"] = int(l["xp"]) + int(jc.get("xp", 40))
	var rw: Dictionary = jd.get("reward", {})
	for m in members_of(state, lid):
		var em := state.get_empire(m)
		for k in rw:
			match String(k):
				"xp":
					l["xp"] = int(l["xp"]) + int(rw[k])
				"strat_influence":
					if m == int(l["strat"]):
						em.resources["influence"] = int(em.resources.get("influence", 0)) + int(rw[k])
				_:
					em.resources[String(k)] = int(em.resources.get(String(k), 0)) + int(rw[k])
	state.add_chronicle("L'opération commune de %s réussit (%s) : la ligue en sort soudée." % [String(l["name"]), String(jd.get("label", ""))], Espionage.private_to(state, all_of(state, lid)))


# --- Lot 3 : espionnage (prop. 29) ------------------------------------------------------------------

static func spy_check(state: GameState, a: int, b: int) -> String:
	var lid := league_of(state, b)
	if lid < 0:
		return "la cible n'est dans aucun Koinon"
	if same_league(state, a, b):
		return "pas dans son propre Koinon"
	return ""


static func spy_apply(state: GameState, _a: int, b: int, o: Dictionary) -> String:
	var lid := league_of(state, b)
	if lid < 0:
		return "le Koinon s'était déjà dissous."
	_coh(state, lid, int(o.get("cohesion", -15)))
	return "des rumeurs circulent entre les délégués de %s : la cohésion s'effrite." % String(league(state, lid)["name"])
