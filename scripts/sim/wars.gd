class_name Wars
extends RefCounted
## Buts de guerre et traités de paix (étude du 2026-11-14), lot 1.
##
## - Motifs de guerre (casus belli) en catalogue ouvert : chaque motif ouvre des buts et fixe la
##   réprobation des tiers ; sans motif, c'est une agression (souvenir chez tous, stabilité -2).
## - Revendications sur des systèmes, payées en influence (gratuites pour le défenseur) ; un système
##   pris par la force laisse une revendication gratuite à l'ancien propriétaire (Reconquête).
## - But annoncé à la déclaration ; le défenseur choisit le sien dans les 90 jours ; buts appariés.
## - Score de guerre en pourcentage (-100 à +100) : batailles, systèmes pris, capitale, but tenu.
## - Reddition : le vaincu accepte le but du vainqueur (et lui cède ses revendications).
## - Trêve proportionnelle au score dépensé ; une trêve peut être rompue, à grand prix.
## - Noms de guerre.
## Tout est dans data/wars.json (catalogues ouverts de motifs, buts et noms).
##
## state.wars = {"claims": {"<empire>": {"<système>": tick}}, "lost": {"<empire>": {"<système>": tick}},
##               "list": {"<a-b>": guerre}, "pending": {} (motif choisi juste avant la déclaration),
##               "mods": [{"e", "kind", "until"}] (stabilité : trêve rompue, humiliation), "cd": {"<a-b>": tick}}
## guerre = {"a" (agresseur), "d" (défenseur), "t", "cb" (motif), "ga" (but de a), "gd" (but de d, "" à choisir),
##           "gdl" (échéance du choix), "name", "bat": [points a, points d], "took": {"<système>": [preneur, valeur]},
##           "hold": [mois a, mois d], "val": [valeur a, valeur d], "cap": [système capitale a, d],
##           "tgt": [[systèmes visés par a], [par d]], "ex": [lassitude a, d], "agg" (agression), "brk" (trêve rompue)}

const KINDS: Array[String] = ["wdemand", "wyield"]


static func data() -> Dictionary:
	return GameData.wars()


static func _cfg(k: String) -> Dictionary:
	return data().get(k, {})


static func _blank() -> Dictionary:
	return {"claims": {}, "lost": {}, "list": {}, "pending": {}, "mods": [], "cd": {}, "occ": {}, "treaties": [], "tid": 1, "occ_on": false,
			"ult": {}, "inc": {}, "crises": {}, "prep": {}, "retain": {}}


## mode : "actifs" ou "aucuns" ; occ : "occupation" (lot 2) ou "immediate" (conquête immédiate).
static func setup(state: GameState, mode: String, occ := "immediate") -> void:
	state.wars_on = mode == "actifs"
	state.wars = _blank()
	state.wars["occ_on"] = occ == "occupation"


static func to_dict(state: GameState) -> Dictionary:
	var d: Dictionary = state.wars.duplicate(true)
	d["on"] = state.wars_on
	d.erase("vic")
	return d


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.wars_on = bool(d.get("on", false))
	state.wars = _blank()
	for k in ["claims", "lost", "list", "cd", "occ"]:
		state.wars[k] = Vassals._ints(d.get(k, {}))
	state.wars["mods"] = Vassals._ints(d.get("mods", []))
	state.wars["treaties"] = Vassals._ints(d.get("treaties", []))
	state.wars["tid"] = int(d.get("tid", 1))
	state.wars["occ_on"] = bool(d.get("occ_on", false))
	for k in WarLaws.STORES:
		state.wars[k] = Vassals._ints(d.get(k, {}))


static func worth_saving(state: GameState) -> bool:
	return state.wars_on


static func _w(state: GameState) -> Dictionary:
	if not state.wars.has("list"):
		state.wars = _blank()
	return state.wars


static func _name(state: GameState, eid: int) -> String:
	var e := state.get_empire(eid)
	return e.display_name() if e != null else "?"


static func _short(state: GameState, eid: int) -> String:
	var e := state.get_empire(eid)
	return e.short_name() if e != null else "?"


# --- Catalogues ----------------------------------------------------------------------------------

static func casus_defs() -> Array:
	return data().get("casus", [])


static func casus_def(cid: String) -> Dictionary:
	for c in casus_defs():
		if String(c["id"]) == cid:
			return c
	return {}


static func goal_defs() -> Array:
	return data().get("goals", [])


static func goal_def(gid: String) -> Dictionary:
	for g in goal_defs():
		if String(g["id"]) == gid:
			return g
	return {}


static func casus_label(cid: String) -> String:
	return String(casus_def(cid).get("label", cid))


static func goal_label(gid: String) -> String:
	return String(goal_def(gid).get("label", "à choisir" if gid == "" else gid))


# --- Revendications (prop. 3) ----------------------------------------------------------------------

static func _map(state: GameState, k: String, eid: int) -> Dictionary:
	var w := _w(state)
	if not w[k].has(str(eid)):
		w[k][str(eid)] = {}
	return w[k][str(eid)]


## Revendications achetées par eid (systèmes), triées.
static func bought_claims(state: GameState, eid: int) -> Array[int]:
	var out: Array[int] = []
	for k in (_w(state)["claims"] as Dictionary).get(str(eid), {}):
		out.append(int(k))
	out.sort()
	return out


## Revendications de reconquête encore valides (systèmes pris par la force à eid).
static func lost_claims(state: GameState, eid: int) -> Array[int]:
	var out: Array[int] = []
	var days := int(_cfg("claims")["lost_days"])
	var m: Dictionary = (_w(state)["lost"] as Dictionary).get(str(eid), {})
	for k in m:
		if state.tick - int(m[k]) < days and state.system_owner(int(k)) != eid:
			out.append(int(k))
	out.sort()
	return out


static func has_claim(state: GameState, eid: int, sid: int) -> bool:
	if (_w(state)["claims"] as Dictionary).get(str(eid), {}).has(str(sid)):
		return true
	return lost_claims(state, eid).has(sid)


## Systèmes de b revendiqués par a (achetés ou de reconquête).
static func claims_on(state: GameState, a: int, b: int) -> Array[int]:
	var out: Array[int] = []
	for sid in EmpireReport.owned_systems(state, b):
		if state.system_owner(sid) == b and has_claim(state, a, sid):
			out.append(sid)
	out.sort()
	return out


## Sauts entre sid et le plus proche système de eid (999 si aucun).
static func jumps_to(state: GameState, eid: int, sid: int) -> int:
	var d := FactionTraits.jumps_from(state.galaxy, sid)
	var best := 999
	for s in EmpireReport.owned_systems(state, eid):
		if d.has(s):
			best = mini(best, int(d[s]))
	return best


## Coût en influence d'une revendication de a sur sid (-1 si impossible).
static func claim_cost(state: GameState, a: int, sid: int) -> int:
	var c := _cfg("claims")
	var owner := state.system_owner(sid)
	if owner < 0 or owner == a or GameState.is_npc(owner):
		return -1
	var j := jumps_to(state, a, sid)
	if j > int(c["max_jumps"]):
		return -1
	var rec := war(state, a, owner)
	if not rec.is_empty() and int(rec["d"]) == a:
		return 0
	var n := int(c["base"]) + int(c["per_jump"]) * maxi(0, j - 1)
	if Vassals.system_pop(state, sid, owner) > 0:
		n += int(c["colonized"])
	if not rec.is_empty() and int(rec["a"]) == a:
		n *= int(c["offensive_mult"])
	if Diplomacy.opinion(state, a, owner) <= int(c["rival_opinion"]):
		@warning_ignore("integer_division")
		n -= n * int(c["rival_pct"]) / 100
	# Couronne vacillante du propriétaire (voir RulersBridges) : revendiquer coûte moins cher.
	if not state.rulers.is_empty():
		@warning_ignore("integer_division")
		n = n * (100 + RulersBridges.wobbly_claim_pct(state, owner)) / 100
	@warning_ignore("integer_division")
	return n * WarLaws.claim_pct(state, a) / 100


static func check_claim(state: GameState, a: int, sid: int) -> String:
	if not state.wars_on:
		return "les buts de guerre ne sont pas actifs dans cette partie"
	if sid < 0 or sid >= state.galaxy.systems.size():
		return "système inconnu"
	var owner := state.system_owner(sid)
	if owner < 0 or GameState.is_npc(owner):
		return "ce système n'appartient à aucun empire"
	if owner == a:
		return "ce système est déjà à vous"
	var e := state.get_empire(a)
	if not e.contacts.has(owner):
		return "vous n'avez jamais rencontré son propriétaire"
	if Diplomacy.team_of(state, a, owner) > 0 or Diplomacy.allied(state, a, owner):
		return "on ne revendique pas les systèmes d'un allié"
	if Vassals.lord_of(state, owner) == a or Vassals.lord_of(state, a) == owner:
		return "pas entre suzerain et sujet"
	if (_w(state)["claims"] as Dictionary).get(str(a), {}).has(str(sid)):
		return "vous le revendiquez déjà"
	var cost := claim_cost(state, a, sid)
	if cost < 0:
		return "trop loin de vos systèmes (%d sauts au plus)" % int(_cfg("claims")["max_jumps"])
	if int(e.resources.get("influence", 0)) < cost:
		return "il faut %d influence" % cost
	return ""


static func claim(state: GameState, a: int, sid: int) -> void:
	var cost := claim_cost(state, a, sid)
	var e := state.get_empire(a)
	e.resources["influence"] = int(e.resources.get("influence", 0)) - maxi(0, cost)
	_map(state, "claims", a)[str(sid)] = state.tick
	var owner := state.system_owner(sid)
	state.add_chronicle("%s revendique %s, système de %s. Les cartographes redessinent la frontière ; les amiraux, eux, la regardent." % [
			_name(state, a), state.galaxy.systems[sid].system_name, _name(state, owner)], Espionage.public_to(state, [a, owner]))


## Systèmes de b que a pourrait revendiquer, triés par coût puis identifiant : [[système, coût]].
static func claim_candidates(state: GameState, a: int, b: int, limit := 8) -> Array:
	var out: Array = []
	for sid in EmpireReport.owned_systems(state, b):
		if state.system_owner(sid) != b or (_w(state)["claims"] as Dictionary).get(str(a), {}).has(str(sid)):
			continue
		var c := claim_cost(state, a, sid)
		if c >= 0:
			out.append([sid, c])
	out.sort_custom(func(x: Array, y: Array) -> bool: return int(x[1]) < int(y[1]) or (int(x[1]) == int(y[1]) and int(x[0]) < int(y[0])))
	return out.slice(0, limit)


# --- Motifs et buts (prop. 1, 2, 4, 5, 6) ------------------------------------------------------------

static func _req_ok(state: GameState, req: String, a: int, b: int) -> bool:
	match req:
		"always":
			return true
		"claims":
			return not claims_on(state, a, b).is_empty()
		"lost":
			for sid in lost_claims(state, a):
				if state.system_owner(sid) == b:
					return true
			return false
		"liberation":
			return not _liberable(state, a, b).is_empty()
		"reprisal":
			if Espionage.has_grief(state, a, b):
				return true
			for m in state.memories:
				if int(m["who"]) == a and int(m["about"]) == b and (String(m["kind"]) == "broke_treaty" or String(m["kind"]) == "truce_broken" or String(m["kind"]) == "treaty_violated") \
						and Diplomacy.memory_value(state, m) != 0:
					return true
			return false
		"rival":
			return Diplomacy.opinion(state, a, b) <= int(_cfg("claims")["rival_opinion"])
		"holy":
			return FaithWars.casus(state, a, b) != ""
		"amph":
			return Amphictyony.casus(state, a, b)
		"subject":
			return Vassals.lord_of(state, a) == b
		"protection":
			return Minors.protection_casus(state, a, b)
		"power":
			return state.vassals_on and not Vassals.is_subject(state, b) and not Vassals.is_subject(state, a) \
					and Vassals.power_pct(state, a, b) >= 150
		"total":
			return Diplomacy.no_treaties(state, a)
		"ultimatum":
			return WarLaws.has_ult_casus(state, a, b)
		"incident":
			return WarLaws.has_incident(state, a, b)
		"border":
			return Borders.has_cb(state, a, b)
		"kanly":
			return WarLaws.kanly_ok(state, a, b)
		"succession":
			return not state.rulers.is_empty() and RulersBridges.succession_casus(state, a, b)
		"debt":
			return not state.finance.is_empty() and FinanceBridges.debt_casus(state, a, b)
		"expropriated":
			return not state.private.is_empty() and Private.full(state) and Private.expropriation_casus(state, a, b)
		"silence":
			return not state.contact.is_empty() and ContactRace.silence_casus(state, a, b)
		"ascension":
			return Transcendence.full(state) and Transcendence.leaving(state, b) and not Transcendence.leaving(state, a)
	return false


## Le but est-il possible pour a contre b ?
static func goal_ok(state: GameState, gid: String, a: int, b: int) -> bool:
	var g := goal_def(gid)
	if g.is_empty():
		return false
	match String(g.get("req", "")):
		"wonder":
			if WondersBridges.prize_system(state, b) < 0:
				return false
		"mega":
			if not Megastructures.full(state) or MegasBridges.prize_system(state, b) < 0:
				return false
		"archaeo":
			if not Archaeology.full(state) or Archaeology.antiqs_of(state, b).is_empty():
				return false
		"vassals":
			if not state.vassals_on or bool(Vassals.talent(state, a).get("no_subjects", false)) or bool(Vassals.talent(state, b).get("no_subjects", false)):
				return false
		"private":
			if state.private.is_empty() or not Private.full(state) or not Private.applies(state, a) or not Private.applies(state, b):
				return false
		"ascension":
			if not Transcendence.full(state) or not Transcendence.leaving(state, b):
				return false
		"silence":
			if state.contact.is_empty() or not Contact.transmitting(state, b):
				return false
	return true


## Motifs disponibles pour a contre b, dans l'ordre du catalogue. La guerre totale n'en laisse pas d'autre.
static func casus_list(state: GameState, a: int, b: int) -> Array[String]:
	var out: Array[String] = []
	if _req_ok(state, "total", a, b):
		out.append("totale")
		return out
	for c in casus_defs():
		var cid := String(c["id"])
		if cid == "totale":
			continue
		if _req_ok(state, String(c["req"]), a, b):
			out.append(cid)
	return out


## Couples [motif, but] possibles pour a contre b.
static func choices(state: GameState, a: int, b: int) -> Array:
	var out: Array = []
	for cid in casus_list(state, a, b):
		for gid in casus_def(cid).get("goals", []):
			if goal_ok(state, String(gid), a, b) and not bool(goal_def(String(gid)).get("defense_only", false)):
				if String(gid) == "conquete" and claims_on(state, a, b).is_empty() and cid != "guerre_sainte":
					continue
				out.append([cid, String(gid)])
	return out


static func check_choice(state: GameState, a: int, b: int, cid: String, gid: String) -> String:
	if not state.wars_on or cid == "":
		return ""
	for c in choices(state, a, b):
		if String(c[0]) == cid and String(c[1]) == gid:
			return ""
	if casus_def(cid).is_empty():
		return "motif inconnu : %s" % cid
	if not casus_list(state, a, b).has(cid):
		return "vous n'avez pas ce motif contre lui"
	return "ce motif n'ouvre pas ce but"


## Choix automatique (IA, ou ordre sans motif) : selon le niveau, le meilleur motif ou un au hasard.
static func auto_choice(state: GameState, a: int, b: int) -> Array:
	var ch := choices(state, a, b)
	if ch.is_empty():
		return ["agression", "humiliation"]
	var e := state.get_empire(a)
	if e != null and e.is_ai() and int(AiLevels.level(e.ai_level).get("military", {}).get("skill", 1)) <= 0:
		return ch[(a * 7 + b * 13 + state.tick / 30) % ch.size()]
	var rank := ["totale", "independance", "quitter", "ascension", "faire_taire", "conquete", "soumission", "liberer", "ouvrir_marches", "rancon", "merveille", "mega", "restitution", "demanteler", "humiliation", "kanly"]
	var best: Array = ch[0]
	for c in ch:
		var better := rank.find(String(c[1])) < rank.find(String(best[1]))
		var same := String(c[1]) == String(best[1])
		# À but égal, un motif qui n'est pas une agression.
		if better or (same and bool(casus_def(String(best[0])).get("aggression", false)) and not bool(casus_def(String(c[0])).get("aggression", false))):
			best = c
	# Sans motif avouable, une maison féodale préfère le kanly à l'agression.
	if e != null and e.is_ai() and bool(casus_def(String(best[0])).get("aggression", false)):
		for c in ch:
			if String(c[0]) == "kanly":
				return c
	return best


## Buts que le défenseur peut choisir.
static func defense_goals(state: GameState, rec: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var ga := goal_def(String(rec["ga"]))
	if String(ga.get("pair", "")) != "":
		out.append(String(ga["pair"]))
		return out
	if bool(ga.get("total", false)):
		out.append("totale")
		return out
	for gid in data().get("defense_goals", []):
		if goal_ok(state, String(gid), int(rec["d"]), int(rec["a"])):
			out.append(String(gid))
	return out


# --- Guerres en cours -----------------------------------------------------------------------------

static func war_by_key(state: GameState, k: String) -> Dictionary:
	return (_w(state)["list"] as Dictionary).get(k, {})


static func war(state: GameState, a: int, b: int) -> Dictionary:
	return (_w(state)["list"] as Dictionary).get(Diplomacy.key(a, b), {})


static func side(rec: Dictionary, eid: int) -> int:
	return 0 if int(rec["a"]) == eid else 1


static func goal_of(rec: Dictionary, eid: int) -> String:
	return String(rec["ga"]) if int(rec["a"]) == eid else String(rec["gd"])


static func _value(state: GameState, sid: int, owner: int) -> int:
	return 1 + Vassals.system_pop(state, sid, owner)


static func _total_value(state: GameState, eid: int) -> int:
	var n := 0
	for sid in EmpireReport.owned_systems(state, eid):
		if state.system_owner(sid) == eid:
			n += _value(state, sid, eid)
	return n


## Le motif et le but choisis pour la prochaine déclaration de a contre b.
## Motif et but de la prochaine déclaration de a contre b. force : déjà vérifiés ailleurs (la guerre
## d'indépendance rompt le lien avant de commencer, le motif ne se vérifierait plus).
static func set_pending(state: GameState, a: int, b: int, cid: String, gid: String, force := false) -> void:
	_w(state)["pending"] = {"a": a, "b": b, "cb": cid, "g": gid, "f": force}


## Une guerre commence (appelé par Diplomacy.on_war_declared).
static func on_war_declared(state: GameState, a: int, b: int, by_nature: bool, joined: bool) -> void:
	if not state.wars_on or GameState.is_npc(a) or GameState.is_npc(b):
		return
	var w := _w(state)
	var p: Dictionary = w.get("pending", {})
	w["pending"] = {}
	var cid := ""
	var gid := ""
	if not p.is_empty() and int(p["a"]) == a and int(p["b"]) == b:
		cid = String(p["cb"])
		gid = String(p["g"])
	if by_nature or Diplomacy.no_treaties(state, a):
		cid = "totale"
		gid = "totale"
	elif joined:
		cid = "allie"
		gid = "humiliation"
	elif cid == "" or (not bool(p.get("f", false)) and check_choice(state, a, b, cid, gid) != ""):
		var ch := auto_choice(state, a, b)
		cid = String(ch[0])
		gid = String(ch[1])
	var broke := Diplomacy.in_truce_raw(state, a, b)
	var rec := {"a": a, "d": b, "t": state.tick, "cb": cid, "ga": gid, "gd": "", "gdl": state.tick + int(data()["defender_days"]),
			"bat": [0, 0], "took": {}, "hold": [0, 0], "val": [_total_value(state, a), _total_value(state, b)],
			"cap": [FactionTraits.capital_system(state, a), FactionTraits.capital_system(state, b)],
			"tgt": [claims_on(state, a, b), claims_on(state, b, a)], "ex": [0, 0],
			"pw": [Vassals.power(state, a), Vassals.power(state, b)], "e100": [-1, -1],
			"agg": bool(casus_def(cid).get("aggression", false)), "brk": broke}
	if rec["agg"]:
		rec["ex"][0] = int(data()["aggressor_exhaustion"])
	if broke:
		rec["ex"][0] = int(rec["ex"][0]) + int(_cfg("truce")["break_exhaustion"])
	rec["name"] = _make_name(state, rec)
	var defs := defense_goals(state, rec)
	if defs.size() == 1 or state.get_empire(b).is_ai():
		rec["gd"] = _ai_defense_goal(state, rec, defs)
	w["list"][Diplomacy.key(a, b)] = rec
	WarLaws.on_declared(state, rec, joined)
	if joined:
		WarPeace.link_joined(state, rec)
		return
	# Réprobation des tiers selon le motif ; agression et trêve rompue.
	var mem := String(casus_def(cid).get("memory", ""))
	var ea := state.get_empire(a)
	for e in state.empires:
		if e.id == a or e.id == b or e.eliminated or e.is_npc() or not e.contacts.has(a):
			continue
		if mem != "":
			Diplomacy.remember(state, e.id, a, mem)
		if broke:
			Diplomacy.remember(state, e.id, a, "truce_breaker")
	if broke:
		Diplomacy.remember(state, b, a, "truce_broken")
		(w["mods"] as Array).append({"e": a, "kind": "truce", "until": state.tick + int(_cfg("truce")["break_days"])})
	var why := String(casus_def(cid).get("label", cid))
	state.add_chronicle("%s commence : %s déclare la guerre à %s (motif : %s ; but : %s).%s" % [String(rec["name"]), ea.display_name(), _name(state, b),
			why.to_lower(), goal_label(gid).to_lower(), " La trêve est rompue : la galaxie retient son souffle, puis son mépris." if broke else ""],
			Espionage.public_to(state, [a, b]))


static func _ai_defense_goal(state: GameState, rec: Dictionary, defs: Array[String]) -> String:
	if defs.is_empty():
		return "humiliation"
	var d := int(rec["d"])
	var a := int(rec["a"])
	if defs.has("conquete") and Vassals.power_pct(state, d, a) >= 120:
		return "conquete"
	if defs.has("rancon"):
		return "rancon"
	return defs[0]


static func check_defense_goal(state: GameState, eid: int, other: int, gid: String) -> String:
	var rec := war(state, eid, other)
	if rec.is_empty():
		return "vous n'êtes pas en guerre"
	if int(rec["d"]) != eid:
		return "seul le défenseur choisit son but"
	if String(rec["gd"]) != "":
		return "votre but est déjà fixé"
	if not defense_goals(state, rec).has(gid):
		return "but impossible : %s" % goal_label(gid)
	return ""


static func set_defense_goal(state: GameState, eid: int, other: int, gid: String) -> void:
	var rec := war(state, eid, other)
	rec["gd"] = gid
	rec["tgt"][1] = claims_on(state, eid, other)
	state.add_chronicle("%s fixe son but dans la %s : %s." % [_name(state, eid), String(rec["name"]), goal_label(gid).to_lower()],
			Espionage.public_to(state, [eid, other]))


static func _make_name(state: GameState, rec: Dictionary) -> String:
	var names: Dictionary = data().get("names", {})
	var pool: Array = names.get(String(rec["ga"]), names.get("any", ["Guerre de {a} contre {d}"]))
	if pool.is_empty():
		pool = names.get("any", ["Guerre de {a} contre {d}"])
	var i := (int(rec["a"]) * 31 + int(rec["d"]) * 17 + state.tick) % pool.size()
	return String(pool[i]).replace("{a}", _short(state, int(rec["a"]))).replace("{d}", _short(state, int(rec["d"])))


## Fin d'une guerre (appelé par Diplomacy.end_war).
static func on_war_ended(state: GameState, a: int, b: int) -> void:
	if not state.wars_on:
		return
	(_w(state)["list"] as Dictionary).erase(Diplomacy.key(a, b))


## Système pris ou occupé pendant la guerre : il compte au score de taker tant qu'il le tient.
static func _took(state: GameState, sid: int, taker: int, old: int) -> void:
	var rec := war(state, taker, old)
	if rec.is_empty():
		return
	var t: Dictionary = rec["took"]
	if t.has(str(sid)) and int(t[str(sid)][0]) == old:
		t.erase(str(sid))  # repris : il redevient sien
	else:
		t[str(sid)] = [taker, _value(state, sid, old), 1 if has_claim(state, taker, sid) else 0]


## Système occupé (lot 2) : la revendication reste, la propriété changera au traité.
static func on_occupy(state: GameState, sid: int, taker: int, old: int) -> void:
	WarLaws.on_invaded(state, sid, taker, old)
	_took(state, sid, taker, old)


# --- Score (prop. 7) ---------------------------------------------------------------------------------

## Points de bataille (puissance détruite) gagnés par winner contre loser.
static func on_battle(state: GameState, winner: int, loser: int, pts: int) -> void:
	var rec := war(state, winner, loser)
	if rec.is_empty() or pts <= 0:
		return
	var i := side(rec, winner)
	rec["bat"][i] = int(rec["bat"][i]) + pts
	WarPeace.on_losses(state, rec, loser, pts)


## Système pris par la force (appelé par Combat.capture_system avant le changement de propriétaire).
static func on_capture(state: GameState, sid: int, taker: int, old: int) -> void:
	if not state.wars_on or GameState.is_npc(taker) or GameState.is_npc(old) or taker == old:
		return
	WarPeace.release(state, sid)
	if Combat.at_war(state, taker, old):
		WarLaws.on_invaded(state, sid, taker, old)
		_map(state, "lost", old)[str(sid)] = state.tick
		_took(state, sid, taker, old)
	(_map(state, "claims", taker) as Dictionary).erase(str(sid))
	(_map(state, "lost", taker) as Dictionary).erase(str(sid))


## Score de a contre b, de -100 à +100, détaillé : {"total", "parts": [[libellé, valeur]]}.
static func score_parts(state: GameState, a: int, b: int) -> Dictionary:
	var rec := war(state, a, b)
	var parts: Array = []
	if rec.is_empty():
		return {"total": 0, "parts": parts}
	var sc := _cfg("score")
	var ia := side(rec, a)
	var ib := 1 - ia
	var pa := int(rec["bat"][ia])
	var pb := int(rec["bat"][ib])
	@warning_ignore("integer_division")
	var bat := int(sc["battle_cap"]) * (pa - pb) / maxi(1, pa + pb + int(sc["battle_base"]))
	if bat != 0:
		parts.append(["Batailles", bat])
	var took := [0, 0]
	for k in rec["took"]:
		var t: Array = rec["took"][k]
		var taker := int(t[0])
		if WarPeace.holder(state, int(k)) == taker:
			took[0 if taker == a else 1] += int(t[1])
	var occ_cap := int(sc["occ_cap"])
	@warning_ignore("integer_division")
	var oa := mini(occ_cap, 100 * int(took[0]) / maxi(1, int(rec["val"][ib])))
	@warning_ignore("integer_division")
	var ob := mini(occ_cap, 100 * int(took[1]) / maxi(1, int(rec["val"][ia])))
	if oa != 0:
		parts.append(["Systèmes pris", oa])
	if ob != 0:
		parts.append(["Systèmes perdus", -ob])
	var cap_b := int(rec["cap"][ib])
	var cap_a := int(rec["cap"][ia])
	if cap_b >= 0 and WarPeace.holder(state, cap_b) == a:
		parts.append(["Sa capitale est à vous", int(sc["capital"])])
	if cap_a >= 0 and WarPeace.holder(state, cap_a) == b:
		parts.append(["Votre capitale est à lui", -int(sc["capital"])])
	var hca := mini(int(sc.get("hero_cap", 20)), WarLaws.captives(state, a, b) * int(sc.get("hero_each", 8)))
	var hcb := mini(int(sc.get("hero_cap", 20)), WarLaws.captives(state, b, a) * int(sc.get("hero_each", 8)))
	if hca != 0:
		parts.append(["Ses héros captifs", hca])
	if hcb != 0:
		parts.append(["Vos héros captifs", -hcb])
	var ha := mini(int(sc["hold_cap"]), int(rec["hold"][ia]) * int(sc["hold_per_month"]))
	var hb := mini(int(sc["hold_cap"]), int(rec["hold"][ib]) * int(sc["hold_per_month"]))
	if ha != 0:
		parts.append(["But tenu (%d mois)" % int(rec["hold"][ia]), ha])
	if hb != 0:
		parts.append(["Il tient son but (%d mois)" % int(rec["hold"][ib]), -hb])
	var total := 0
	for p in parts:
		total += int(p[1])
	return {"total": clampi(total, -100, 100), "parts": parts}


static func score(state: GameState, a: int, b: int) -> int:
	return int(score_parts(state, a, b)["total"])


## L'objectif du but de eid est-il tenu ?
static func objective_held(state: GameState, rec: Dictionary, eid: int) -> bool:
	var i := side(rec, eid)
	var other := int(rec["d"]) if i == 0 else int(rec["a"])
	var gid := goal_of(rec, eid)
	if gid == "":
		return false
	var obj := String(goal_def(gid).get("objective", "capital"))
	match obj:
		"claims":
			var tgt: Array = rec["tgt"][i]
			if tgt.is_empty():
				obj = "capital"
			else:
				for sid in tgt:
					if WarPeace.holder(state, int(sid)) != eid:
						return false
				return true
		"battles":
			var sp := score_parts(state, eid, other)
			for p in sp["parts"]:
				if String(p[0]) == "Batailles":
					return int(p[1]) >= int(_cfg("score")["battles_objective"])
			return false
		"keep":
			for k in rec["took"]:
				if int(rec["took"][k][0]) == other and WarPeace.holder(state, int(k)) == other:
					return false
			return state.tick - int(rec["t"]) >= 30
	var cap := int(rec["cap"][1 - i])
	return cap >= 0 and WarPeace.holder(state, cap) == eid


## Chaque mois : objectifs tenus, but du défenseur échu, fins de malus.
static func monthly(state: GameState) -> void:
	if not state.wars_on:
		return
	var w := _w(state)
	var keys: Array = (w["list"] as Dictionary).keys()
	keys.sort()
	for k in keys:
		var rec: Dictionary = w["list"][k]
		var a := int(rec["a"])
		var d := int(rec["d"])
		if not Combat.at_war(state, a, d):
			w["list"].erase(k)
			continue
		if String(rec["gd"]) == "" and state.tick >= int(rec["gdl"]):
			rec["gd"] = _ai_defense_goal(state, rec, defense_goals(state, rec))
		for e in [a, d]:
			var i := side(rec, e)
			rec["hold"][i] = int(rec["hold"][i]) + 1 if objective_held(state, rec, e) else 0
	var kept: Array = []
	for m in w["mods"]:
		if int(m["until"]) > state.tick:
			kept.append(m)
	w["mods"] = kept
	WarPeace.monthly(state)
	WarLaws.monthly(state)


# --- Reddition (prop. 12) ----------------------------------------------------------------------------

## Marge d'acceptation de loser s'il se rend au but de winner : >= 0, il accepte. Détaillée.
static func accept_parts(state: GameState, winner: int, loser: int) -> Dictionary:
	var rec := war(state, winner, loser)
	var parts: Array = []
	if rec.is_empty():
		return {"total": -1000, "parts": parts}
	var g := goal_def(goal_of(rec, winner))
	parts.append(["Score de guerre", score(state, winner, loser)])
	var sc := _cfg("surrender")
	@warning_ignore("integer_division")
	var fleet := clampi((Vassals.power_pct(state, winner, loser) - 100) / int(sc["fleet_div"]), 0, int(sc["fleet_max"]))
	if fleet > 0:
		parts.append(["Rapport de forces", fleet])
	var ex := int(rec.get("ex", [0, 0])[side(rec, loser)])
	@warning_ignore("integer_division")
	var exv := ex / maxi(1, int(_cfg("exhaustion").get("accept_div", 2)))
	if exv > 0:
		parts.append(["Sa lassitude (%d %%)" % ex, exv])
	parts.append(["But : %s" % String(g.get("label", "?")), int(g.get("accept", 0))])
	var t := 0
	for p in parts:
		t += int(p[1])
	return {"total": t, "parts": parts}


static func acceptance(state: GameState, winner: int, loser: int) -> int:
	return int(accept_parts(state, winner, loser)["total"])


static func _check_end(state: GameState, winner: int, loser: int) -> String:
	if not state.wars_on:
		return "les buts de guerre ne sont pas actifs dans cette partie"
	var rec := war(state, winner, loser)
	if rec.is_empty():
		return "vous n'êtes pas en guerre"
	if rec.has("lead") and not war_by_key(state, String(rec["lead"])).is_empty():
		return "les chefs de guerre négocient pour leur camp (paix séparée possible)"
	var gid := goal_of(rec, winner)
	if gid == "":
		return "le but de %s n'est pas encore fixé" % _short(state, winner)
	if bool(goal_def(gid).get("total", false)):
		return "guerre totale : pas de reddition"
	if Diplomacy.no_treaties(state, winner) or Diplomacy.no_treaties(state, loser):
		return "l'Essaim ne signe rien : il digère"
	if state.tick - int(rec["t"]) < int(_cfg("surrender")["min_days"]):
		return "trop tôt : la guerre dure depuis %d jours (il en faut %d)" % [state.tick - int(rec["t"]), int(_cfg("surrender")["min_days"])]
	if gid == "soumission" and (Vassals.is_subject(state, loser) or Vassals.is_subject(state, winner)):
		return "la soumission n'a plus d'objet"
	return ""


## winner exige la reddition de loser (proposition « wdemand »).
static func check_demand(state: GameState, winner: int, loser: int) -> String:
	var why := _check_end(state, winner, loser)
	if why != "":
		return why
	return _check_pending(state, winner, loser, "wdemand")


## loser se rend à winner (proposition « wyield »).
static func check_yield(state: GameState, loser: int, winner: int) -> String:
	var why := _check_end(state, winner, loser)
	if why != "":
		return why
	return _check_pending(state, loser, winner, "wyield")


static func _check_pending(state: GameState, from: int, to: int, kind: String) -> String:
	if not Diplomacy.pending(state, from, to, kind).is_empty():
		return "proposition déjà envoyée"
	var left := Diplomacy.cooldown_left(state, from, to, kind)
	if left > 0:
		return "trop tôt pour reproposer (%d jours)" % left
	return ""


## Applique la victoire de winner : son but et ses revendications ; trêve selon le score.
static func apply_victory(state: GameState, winner: int, loser: int) -> void:
	var rec := war(state, winner, loser).duplicate(true)
	var gid := goal_of(rec, winner)
	var sc := score(state, winner, loser)
	var name := String(rec.get("name", "la guerre"))
	# Camps (lot 2) : le butin des alliés selon leur contribution, avant que leurs guerres ne finissent.
	var shares := WarPeace.contributions(state, war(state, winner, loser), winner) if not rec.is_empty() else {winner: 1}
	var tot_share := 0
	for k in shares:
		tot_share += maxi(0, int(shares[k]))
	if tot_share <= 0:
		shares = {winner: 1}
	var spoils := WarPeace.allied_spoils(state, winner, loser)
	var w := _w(state)
	w["vic"] = true
	Diplomacy.sign_treaty(state, winner, loser, Diplomacy.PEACE)
	w["vic"] = false
	var ceded: Array[String] = []
	var first_ceded := -1
	# Toujours : les revendications du vainqueur (sauf la capitale du vaincu).
	var home := FactionTraits.capital_system(state, loser)
	var limited := bool(goal_def(gid).get("limited", false))
	var to_cede: Array[int] = []
	if not limited:
		to_cede = claims_on(state, winner, loser)
	for sid in to_cede:
		if sid != home:
			Combat.capture_system(state, sid, winner)
			ceded.append(state.galaxy.systems[sid].system_name)
			if first_ceded < 0:
				first_ceded = sid
	ceded.append_array(spoils)
	var el := state.get_empire(loser)
	match gid:
		"soumission":
			if not Vassals.is_subject(state, loser) and not Vassals.is_subject(state, winner):
				Vassals.bind(state, winner, loser, "vassal", Vassals.preset_clauses("vassal"), int(Vassals.data()["loyalty"].get("start_terms", 0)), true)
		"humiliation":
			var h := _cfg("humiliation")
			_share(state, shares, "influence", int(h["influence"]))
			@warning_ignore("integer_division")
			el.resources["influence"] = int(el.resources.get("influence", 0)) - maxi(0, int(el.resources.get("influence", 0))) / 2
			(_w(state)["mods"] as Array).append({"e": loser, "kind": "humil", "until": state.tick + int(h["days"])})
			Diplomacy.remember(state, loser, winner, "humiliated")
		"rancon":
			var rc := _cfg("ransom")
			for r in ["materials", "energy", "influence"]:
				@warning_ignore("integer_division")
				var n := maxi(0, int(el.resources.get(r, 0))) * int(rc["repar_pct"]) * (100 + int(WarLaws.talent(state, winner).get("ransom_pct", 0))) / 10000
				el.resources[r] = int(el.resources.get(r, 0)) - n
				_share(state, shares, r, n)
			if not state.vassals.has("trib"):
				state.vassals["trib"] = []
			(state.vassals["trib"] as Array).append({"from": loser, "to": winner, "until": state.tick + int(rc["tribute_days"]), "pct": int(rc["tribute_pct"])})
		"liberer":
			for sid in _liberable(state, winner, loser):
				var to := _liberable_owner(state, winner, sid)
				if to >= 0 and state.system_owner(sid) == loser and sid != home:
					Combat.capture_system(state, sid, to)
					ceded.append(state.galaxy.systems[sid].system_name)
			for s in Vassals.subjects_of(state, loser):
				Vassals.unbind(state, s, "la paix l'affranchit")
		"ouvrir_marches":
			ceded.append_array(PrivateBridges.open_markets(state, winner, loser))
		"faire_taire":
			if not state.contact.is_empty():
				ceded.append(ContactRace.silence(state, winner, loser))
		"ascension":
			var host := Transcendence.host_of(state, loser)
			if host >= 0:
				Transcendence.sub(state, "joined").erase(str(loser))
				ceded.append("son départ avec %s" % state.get_empire(host).short_name())
			elif Transcendence.in_passage(state, loser):
				Transcendence.break_passage(state, loser, "la paix imposée par %s l'oblige à rebâtir" % state.get_empire(winner).short_name(), 1, [])
				ceded.append("son Passage")
		"merveille":
			var won := WondersBridges.take_prize(state, winner, loser)
			if won != "":
				ceded.append(won)
		"mega":
			var took := MegasBridges.take_prize(state, winner, loser)
			if took != "":
				ceded.append(took)
		"restitution":
			var back := ArchaeoBridges.take_prize(state, winner, loser)
			if back != "":
				ceded.append(back)
		"demanteler":
			for ally in Diplomacy.allies(state, loser):
				if Diplomacy.team_of(state, loser, ally) <= 0:
					var r := Diplomacy._rel_w(state, loser, ally)
					r["pact"] = Diplomacy.COLD
					r["since"] = state.tick
			if Koinon.league_of(state, loser) >= 0:
				Koinon._leave_now(state, Koinon.league_of(state, loser), loser)
		"independance":
			if Vassals.lord_of(state, winner) == loser:
				Vassals.unbind(state, winner, "il a gagné sa guerre d'indépendance")
		"affirmer":
			if not Vassals.is_subject(state, loser) and not Vassals.is_subject(state, winner):
				Vassals.bind(state, winner, loser, "vassal", Vassals.preset_clauses("vassal"), int(_cfg("affirm")["loyalty"]), true)
				Diplomacy._set_cooldown(state, loser, winner, "freedom", int(_cfg("affirm")["freedom_cd_days"]))
		"kanly":
			var n := mini(maxi(0, int(el.resources.get("influence", 0))), int(_cfg("kanly").get("influence", 60)))
			el.resources["influence"] = int(el.resources.get("influence", 0)) - n
			_share(state, shares, "influence", n)
			Diplomacy.remember(state, loser, winner, "kanly_lost")
		"quitter", "retenir":
			WarLaws.apply_secession(state, winner, loser, gid)
		"heritier":
			RulersBridges.impose_heir(state, winner, loser)
	WarLaws.release_one_way(state, loser, winner)
	var spent := maxi(sc, int(_cfg("truce")["victory_min_pct"]))
	set_truce(state, winner, loser, spent)
	if not limited:
		Diplomacy.remember(state, loser, winner, "harsh_terms")
	if not ceded.is_empty():
		WarPeace.on_ceded(state, loser, spent)
	WarPeace.register(state, winner, loser, winner, "reddition : " + goal_label(gid).to_lower(), {}, name, first_ceded)
	var extra := (" Systèmes cédés : %s." % ", ".join(ceded)) if not ceded.is_empty() else ""
	state.add_chronicle("Fin de la %s : %s se rend à %s, qui obtient son but (%s).%s Les vainqueurs écrivent l'histoire ; les vaincus, des mémoires." % [
			name, _name(state, loser), _name(state, winner), goal_label(gid).to_lower(), extra], Espionage.public_to(state, [winner, loser]))


## Répartit n unités de r entre les membres du camp vainqueur selon leur contribution.
static func _share(state: GameState, shares: Dictionary, r: String, n: int) -> void:
	var tot := 0
	var ids := shares.keys()
	ids.sort()
	for k in ids:
		tot += maxi(0, int(shares[k]))
	var given := 0
	for i in ids.size():
		var eid := int(ids[i])
		var part := n - given
		if tot > 0 and i < ids.size() - 1:
			@warning_ignore("integer_division")
			part = n * maxi(0, int(shares[eid])) / tot
		elif tot <= 0:
			part = n if i == 0 else 0
		given += part
		var e := state.get_empire(eid)
		if e != null:
			e.resources[r] = int(e.resources.get(r, 0)) + part


## Trêve selon le score dépensé (prop. 14).
static func set_truce(state: GameState, a: int, b: int, spent_pct: int) -> void:
	if not state.wars_on:
		return
	var t := _cfg("truce")
	var days := mini(int(t["max_days"]), Diplomacy.days("truce_days", 360) + maxi(0, spent_pct) * int(t["per_pct"]))
	Diplomacy._rel_w(state, a, b)["truce"] = state.tick + days


# --- Libération ------------------------------------------------------------------------------------

## Ceux que a peut venger : alliés, sujets, équipiers, membres de son Koinon.
static func _friends(state: GameState, a: int) -> Array[int]:
	var out: Array[int] = []
	for e in state.empires:
		if e.id == a or e.eliminated or e.is_npc():
			continue
		if Diplomacy.allied(state, a, e.id) or Diplomacy.team_of(state, a, e.id) > 0 or Vassals.lord_of(state, e.id) == a \
				or (Koinon.league_of(state, a) >= 0 and Koinon.league_of(state, a) == Koinon.league_of(state, e.id)):
			out.append(e.id)
	return out


## Systèmes de b pris par la force à des amis de a.
static func _liberable(state: GameState, a: int, b: int) -> Array[int]:
	var out: Array[int] = []
	for f in _friends(state, a):
		for sid in lost_claims(state, f):
			if state.system_owner(sid) == b and not out.has(sid):
				out.append(sid)
	out.sort()
	return out


static func _liberable_owner(state: GameState, a: int, sid: int) -> int:
	for f in _friends(state, a):
		if lost_claims(state, f).has(sid):
			return f
	return -1


# --- Stabilité (agression, trêve rompue, humiliation) -------------------------------------------------

static func stability_parts(state: GameState, eid: int) -> Array:
	var out: Array = []
	if not state.wars_on:
		return out
	var w := _w(state)
	var agg := false
	for k in w["list"]:
		var rec: Dictionary = w["list"][k]
		if int(rec["a"]) == eid and bool(rec.get("agg", false)):
			agg = true
	if agg:
		out.append(["Guerre d'agression", int(_cfg("aggression")["stability"])])
	else:
		for k in w["list"]:
			var rec: Dictionary = w["list"][k]
			if int(rec["a"]) == eid and bool(casus_def(String(rec["cb"])).get("just", false)) and not rec.has("lead"):
				out.append(["Guerre juste", int(_cfg("just").get("stability", 1))])
				break
	var truce := false
	var humil := false
	for m in w["mods"]:
		if int(m["e"]) == eid and int(m["until"]) > state.tick:
			truce = truce or String(m["kind"]) == "truce"
			humil = humil or String(m["kind"]) == "humil"
	if truce:
		out.append(["Trêve rompue", int(_cfg("truce")["break_stability"])])
	if humil:
		out.append(["Humilié à la guerre", int(_cfg("humiliation")["stability"])])
	return out


# --- Propositions ------------------------------------------------------------------------------------

static func is_kind(kind: String) -> bool:
	return KINDS.has(kind) or WarLaws.KINDS.has(kind)


static func kind_label(p: Dictionary) -> String:
	if WarLaws.KINDS.has(String(p["treaty"])):
		return WarLaws.kind_label(p)
	match String(p["treaty"]):
		"wdemand":
			return "Exige votre reddition"
		"wyield":
			return "Se rend"
	return String(p["treaty"])


static func kind_text(state: GameState, p: Dictionary) -> String:
	if WarLaws.KINDS.has(String(p["treaty"])):
		return WarLaws.kind_text(state, p)
	var from := int(p["from"])
	var to := int(p["to"])
	match String(p["treaty"]):
		"wdemand":
			var rec := war(state, from, to)
			return "Vous vous rendriez à son but (%s) et lui céderiez ses revendications." % goal_label(goal_of(rec, from)).to_lower() if not rec.is_empty() else ""
		"wyield":
			var rec := war(state, from, to)
			return "Il se rendrait à votre but (%s) et vous céderait vos revendications." % goal_label(goal_of(rec, to)).to_lower() if not rec.is_empty() else ""
	return ""


static func check_accept(state: GameState, p: Dictionary) -> String:
	if WarLaws.KINDS.has(String(p["treaty"])):
		return WarLaws.check_accept(state, p)
	var from := int(p["from"])
	var to := int(p["to"])
	match String(p["treaty"]):
		"wdemand":
			return _check_end(state, from, to)
		"wyield":
			return _check_end(state, to, from)
	return ""


static func answer(state: GameState, p: Dictionary, accept: bool) -> void:
	if WarLaws.KINDS.has(String(p["treaty"])):
		WarLaws.answer(state, p, accept)
		return
	_resolve(state, String(p["treaty"]), int(p["from"]), int(p["to"]), accept)


static func ai_accepts(state: GameState, kind: String, from: int, to: int) -> bool:
	match kind:
		"wdemand":
			var e := state.get_empire(to)
			if bool(AiLevels.personality(e).get("temperament", {}).get("never_peace", false)):
				return false
			return acceptance(state, from, to) >= int(_cfg("ai")["demand_at"])
		"wyield":
			return true
	return false


static func propose(state: GameState, kind: String, from: int, to: int) -> void:
	var et := state.get_empire(to)
	if et.is_ai():
		_resolve(state, kind, from, to, ai_accepts(state, kind, from, to))
		return
	state.proposals.append({"id": state.next_proposal_id, "from": from, "to": to, "treaty": kind, "tick": state.tick, "terms": {}})
	state.next_proposal_id += 1
	Diplomacy._set_cooldown(state, from, to, kind, Diplomacy.days("proposal_days", 30))
	state.add_chronicle("%s adresse à %s : %s." % [_name(state, from), _name(state, to), kind_label({"treaty": kind}).to_lower()],
			Espionage.private_to(state, [from, to]))


static func _resolve(state: GameState, kind: String, from: int, to: int, accept: bool) -> void:
	if accept:
		match kind:
			"wdemand":
				apply_victory(state, from, to)
			"wyield":
				apply_victory(state, to, from)
		return
	Diplomacy._set_cooldown(state, from, to, kind, int(_cfg("surrender")["cooldown_days"]))
	state.add_chronicle("%s repousse la proposition de %s (%s)." % [_name(state, to), _name(state, from), kind_label({"treaty": kind}).to_lower()],
			Espionage.private_to(state, [from, to]))


# --- Ordre unique ------------------------------------------------------------------------------------

## act : "claim" (x = système), "goal" (x = ennemi, s = but du défenseur), "demand" (x = ennemi),
## "yield" (x = ennemi).
static func check_act(state: GameState, player: int, act: String, x: int, s: String) -> String:
	var e := state.get_empire(player)
	if e == null or e.eliminated:
		return "empire inconnu"
	if not state.wars_on:
		return "les buts de guerre ne sont pas actifs dans cette partie"
	match act:
		"claim":
			return check_claim(state, player, x)
		"goal":
			return check_defense_goal(state, player, x, s)
		"demand":
			return check_demand(state, player, x)
		"yield":
			return check_yield(state, player, x)
		"status":
			return WarPeace.check_impose(state, player, x)
		"separate":
			return WarPeace.check_separate(state, player, x)
	return WarLaws.check_act(state, player, act, x, s)


static func act(state: GameState, player: int, act_id: String, x: int, s: String) -> void:
	match act_id:
		"claim":
			claim(state, player, x)
		"goal":
			set_defense_goal(state, player, x, s)
		"demand":
			propose(state, "wdemand", player, x)
		"yield":
			propose(state, "wyield", player, x)
		"status":
			WarPeace.impose(state, player, x)
		"separate":
			WarPeace.separate(state, player, x)
		_:
			WarLaws.act(state, player, act_id, x, s)
