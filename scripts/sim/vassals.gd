class_name Vassals
extends RefCounted
## Fin des guerres à conditions et sujets (pilier fédérations et vassaux, lot 1).
##
## - Conditions de paix payées en score de guerre (céder des systèmes, tribut, réparations, rompre
##   les alliances, libérer les sujets, devenir vassal) ; l'IA vaincue accepte si le prix ne dépasse
##   pas le score du vainqueur.
## - Reddition : un vaincu (score de 100 contre lui, ou capitale perdue) devient vassal au lieu de mourir.
## - Un seul lien de sujet, réglé par clauses (diplomatie, guerres suivies, expansion, intégration,
##   tribut par famille de ressources) ; préréglages Vassal, Tributaire, Protectorat ; la Cour
##   impériale de l'Amphictyonie est un préréglage verrouillé (voir sync_court).
## - Loyauté en dixièmes de point (-1000 à 1000) : effet immédiat et mensuel des clauses, opinion,
##   credo, puissance relative, patronage divisé ; allégeance secrète à un rival du suzerain.
## - Protectorat, intégration après 10 ans, libération, indépendance exigée (refus = guerre),
##   soutien de tiers.
## Tout est dans data/vassals.json (catalogues ouverts : clauses, options et préréglages).
##
## state.vassals = {"subs": {"<sujet>": lien}, "trib": [tributs de paix], "cap": {"perdant-vainqueur": tick},
##                  "cd": {"<empire>": tick (prochaine demande de protection)}}
## lien = {"lord", "since", "preset", "cl": {dip, war, exp, integ, trib: {famille: %}}, "loy",
##         "next" (prochaine renégociation), "fealty" (-1 ou rival), "integ" (-1 ou début), "imo" (mois payés),
##         "sup": [soutiens à l'indépendance]}

const KINDS: Array[String] = ["terms", "surrender", "protect", "freedom"]
const TERM_KEYS: Array[String] = ["cede", "trib", "repar", "break", "free", "vassal"]


static func data() -> Dictionary:
	return GameData.vassals()


static func _blank() -> Dictionary:
	return {"subs": {}, "trib": [], "cap": {}, "cd": {}}


static func setup(state: GameState, mode: String) -> void:
	state.vassals_on = mode == "actifs"
	state.vassals = _blank()


static func to_dict(state: GameState) -> Dictionary:
	var d: Dictionary = state.vassals.duplicate(true)
	d["on"] = state.vassals_on
	return d


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.vassals_on = bool(d.get("on", false))
	state.vassals = _blank()
	for k in ["subs", "cap", "cd"]:
		state.vassals[k] = _ints(d.get(k, {}))
	state.vassals["trib"] = _ints(d.get("trib", []))


## Relecture JSON : les nombres reviennent en flottants ; on rend leurs entiers.
static func _ints(v: Variant) -> Variant:
	if v is float:
		return int(v)
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _ints(v[k])
		return out
	if v is Array:
		var out := []
		for x in v:
			out.append(_ints(x))
		return out
	return v


## Faut-il sauvegarder le bloc ? (option active, ou des liens de la Cour impériale.)
static func worth_saving(state: GameState) -> bool:
	return state.vassals_on or not (state.vassals.get("subs", {}) as Dictionary).is_empty() \
			or not (state.vassals.get("trib", []) as Array).is_empty()


static func _cfg(k: String) -> Dictionary:
	return data().get(k, {})


static func _name(state: GameState, eid: int) -> String:
	var e := state.get_empire(eid)
	return e.display_name() if e != null else "?"


# --- Catalogues ----------------------------------------------------------------------------------

static func clause_defs() -> Array:
	return data().get("clauses", [])


static func clause_def(cid: String) -> Dictionary:
	for c in clause_defs():
		if String(c["id"]) == cid:
			return c
	return {}


static func opt_def(cid: String, oid: String) -> Dictionary:
	for o in clause_def(cid).get("opts", []):
		if String(o["id"]) == oid:
			return o
	return {}


static func preset_defs() -> Array:
	return data().get("presets", [])


static func preset(pid: String) -> Dictionary:
	for p in preset_defs():
		if String(p["id"]) == pid:
			return p
	return {}


static func preset_label(pid: String) -> String:
	return String(preset(pid).get("label", "Sur mesure"))


## Préréglages qu'un joueur peut choisir (la Cour impériale est réservée à l'Amphictyonie).
static func free_presets() -> Array[String]:
	var out: Array[String] = []
	for p in preset_defs():
		if not bool(p.get("locked", false)):
			out.append(String(p["id"]))
	return out


static func families() -> Array:
	return data().get("tribute_families", [])


static func steps() -> Array:
	return data().get("tribute_steps", [0, 10, 20, 30])


## Clauses d'un préréglage (copie modifiable).
static func preset_clauses(pid: String) -> Dictionary:
	return (preset(pid).get("cl", {}) as Dictionary).duplicate(true)


## Clauses complétées et validées : chaque clause du catalogue a une option connue, tribut aux paliers.
static func normalize(cl: Dictionary) -> Dictionary:
	var out := {}
	for c in clause_defs():
		var cid := String(c["id"])
		var oid := String(cl.get(cid, ""))
		if opt_def(cid, oid).is_empty():
			oid = String(c["opts"][0]["id"])
		out[cid] = oid
	var trib := {}
	var src: Dictionary = cl.get("trib", {})
	for f in families():
		var v := int(src.get(f, 0))
		if v > 0 and steps().has(v):
			trib[String(f)] = v
	out["trib"] = trib
	return out


## Clauses valides ? "" si oui.
static func check_clauses(cl: Dictionary) -> String:
	for c in clause_defs():
		var cid := String(c["id"])
		if not cl.has(cid) or opt_def(cid, String(cl[cid])).is_empty():
			return "clause « %s » inconnue ou absente" % String(c.get("label", cid))
	var trib: Dictionary = cl.get("trib", {})
	for f in trib:
		if not families().has(f):
			return "tribut inconnu : %s" % f
		if not steps().has(int(trib[f])):
			return "palier de tribut invalide : %d %%" % int(trib[f])
	return ""


static func _tribute_steps(cl: Dictionary) -> int:
	var n := 0
	var st := steps()
	for f in cl.get("trib", {}):
		n += maxi(0, st.find(int(cl["trib"][f])))
	return n


## Effet immédiat des clauses sur la loyauté (dixièmes).
static func clauses_now(cl: Dictionary) -> int:
	var n := 0
	for c in clause_defs():
		n += int(opt_def(String(c["id"]), String(cl.get(String(c["id"]), ""))).get("now", 0))
	return n + _tribute_steps(cl) * int(data().get("tribute_step_now", 0))


## Effet mensuel des clauses sur la loyauté (dixièmes).
static func clauses_m10(cl: Dictionary) -> int:
	var n := 0
	for c in clause_defs():
		n += int(opt_def(String(c["id"]), String(cl.get(String(c["id"]), ""))).get("m10", 0))
	return n + _tribute_steps(cl) * int(data().get("tribute_step_m10", 0))


## Description courte des clauses : « Vote lié, Toutes, Dîme, Interdite ; tribut 10 % matériaux ».
static func clauses_text(cl: Dictionary) -> String:
	var parts := PackedStringArray()
	for c in clause_defs():
		parts.append("%s : %s" % [String(c["label"]), String(opt_def(String(c["id"]), String(cl.get(String(c["id"]), ""))).get("label", "?"))])
	var trib: Dictionary = cl.get("trib", {})
	var tp := PackedStringArray()
	for f in families():
		if int(trib.get(f, 0)) > 0:
			tp.append("%d %% %s" % [int(trib[f]), GameData.resource_label(String(f)).to_lower()])
	parts.append("Tribut : %s" % (", ".join(tp) if not tp.is_empty() else "aucun"))
	return " ; ".join(parts)


# --- Liens ---------------------------------------------------------------------------------------

static func _subs(state: GameState) -> Dictionary:
	if not state.vassals.has("subs"):
		state.vassals = _blank()
	return state.vassals["subs"]


static func link(state: GameState, sub: int) -> Dictionary:
	return _subs(state).get(str(sub), {})


static func lord_of(state: GameState, sub: int) -> int:
	return int(link(state, sub).get("lord", -1))


static func is_subject(state: GameState, eid: int) -> bool:
	return lord_of(state, eid) >= 0


static func subjects_of(state: GameState, lord: int) -> Array[int]:
	var out: Array[int] = []
	for k in _subs(state):
		if int(_subs(state)[k]["lord"]) == lord:
			out.append(int(k))
	out.sort()
	return out


static func all_subjects(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for k in _subs(state):
		out.append(int(k))
	out.sort()
	return out


static func clause(state: GameState, sub: int, cid: String) -> String:
	return String(link(state, sub).get("cl", {}).get(cid, ""))


static func preset_of(state: GameState, sub: int) -> String:
	return String(link(state, sub).get("preset", ""))


static func locked(state: GameState, sub: int) -> bool:
	return bool(preset(preset_of(state, sub)).get("locked", false))


static func is_court(state: GameState, sub: int) -> bool:
	return preset_of(state, sub) == "cour"


static func is_protectorate(state: GameState, sub: int) -> bool:
	return bool(preset(preset_of(state, sub)).get("protect", false)) and is_subject(state, sub)


static func loyalty(state: GameState, sub: int) -> int:
	return int(link(state, sub).get("loy", 0))


static func loyalty_points(state: GameState, sub: int) -> int:
	@warning_ignore("integer_division")
	return loyalty(state, sub) / 10


static func disloyal(state: GameState, sub: int) -> bool:
	return is_subject(state, sub) and loyalty(state, sub) < int(_cfg("loyalty").get("disloyal_below", 0))


static func bond_days(state: GameState, sub: int) -> int:
	return state.tick - int(link(state, sub).get("since", state.tick))


## Lie sub à lord (sans vérification). Les sujets de sub sont libérés : pas de chaîne de vassaux.
static func bind(state: GameState, lord: int, sub: int, pid: String, cl: Dictionary, loy0: int, quiet := false) -> void:
	for s in subjects_of(state, sub):
		unbind(state, s, "son suzerain %s devient lui-même sujet" % _name(state, sub))
	var c := normalize(cl)
	var lc := _cfg("loyalty")
	var loy := clampi(loy0 + clauses_now(c), int(lc.get("min", -1000)), int(lc.get("max", 1000)))
	_subs(state)[str(sub)] = {"lord": lord, "since": state.tick, "preset": pid, "cl": c, "loy": loy,
			"next": state.tick + int(_cfg("renegotiate").get("first_days", 360)), "fealty": -1, "integ": -1, "imo": 0, "sup": []}
	if Combat.at_war(state, lord, sub):
		Diplomacy.end_war(state, lord, sub)
	var r := Diplomacy._rel_w(state, lord, sub)
	if String(r["pact"]) == Diplomacy.COLD:
		r["pact"] = Diplomacy.PEACE
		r["since"] = state.tick
	# Un sujet quitte les alliances qui le lieraient aux ennemis de son suzerain.
	for ally in Diplomacy.allies(state, sub):
		if Combat.at_war(state, lord, ally) and Diplomacy.team_of(state, sub, ally) <= 0:
			Diplomacy._rel_w(state, sub, ally)["pact"] = Diplomacy.COLD
	state.relic_rev += 1
	if not quiet:
		state.add_chronicle("%s devient %s de %s (%s). On change les armoiries ; la chancellerie, elle, garde ses dossiers." % [
				_name(state, sub), "le protégé" if bool(preset(pid).get("protect", false)) else "le sujet", _name(state, lord), preset_label(pid)],
				Espionage.public_to(state, [lord, sub]))


## Délie un sujet (why : raison pour la chronique, "" = silencieux).
static func unbind(state: GameState, sub: int, why := "") -> void:
	var l := link(state, sub)
	if l.is_empty():
		return
	var lord := int(l["lord"])
	_subs(state).erase(str(sub))
	state.relic_rev += 1
	if why != "":
		state.add_chronicle("%s n'est plus sujet de %s : %s." % [_name(state, sub), _name(state, lord), why], Espionage.public_to(state, [lord, sub]))


# --- Puissance -----------------------------------------------------------------------------------

static func power(state: GameState, eid: int) -> int:
	var e := state.get_empire(eid)
	if e == null or e.eliminated:
		return 0
	return AiDiplomacy.own_power(state, e)


## Puissance de a en % de celle de b.
static func power_pct(state: GameState, a: int, b: int) -> int:
	@warning_ignore("integer_division")
	return 100 * power(state, a) / maxi(1, power(state, b))


# --- Conditions de paix (prop. 1) ------------------------------------------------------------------

static func war_days(state: GameState, a: int, b: int) -> int:
	return Diplomacy.pact_days(state, a, b) if Combat.at_war(state, a, b) else 0


static func system_pop(state: GameState, sid: int, owner: int) -> int:
	var n := 0
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == owner and c.is_colony():
			n += c.population
	return n


## Systèmes que le vaincu peut céder : les siens, hors capitale.
static func cedable(state: GameState, loser: int) -> Array[int]:
	var out: Array[int] = []
	var e := state.get_empire(loser)
	var home := state.galaxy.get_planet(e.capital_planet).system_id if e != null and e.capital_planet >= 0 else -1
	for sid in EmpireReport.owned_systems(state, loser):
		if sid != home and state.system_owner(sid) == loser:
			out.append(sid)
	out.sort()
	return out


static func cede_price(state: GameState, loser: int, sid: int) -> int:
	var t := _cfg("terms")
	return int(t["cede_base"]) + int(t["cede_per_pop"]) * system_pop(state, sid, loser)


static func vassal_price(state: GameState, loser: int) -> int:
	var t := _cfg("terms")
	return int(t["vassal_base"]) + int(t["vassal_per_system"]) * EmpireReport.owned_systems(state, loser).size()


## Prix d'un ensemble de conditions, en points de score de guerre.
static func price(state: GameState, loser: int, terms: Dictionary) -> int:
	var t := _cfg("terms")
	var n := 0
	for sid in terms.get("cede", []):
		n += cede_price(state, loser, int(sid))
	if bool(terms.get("trib", false)):
		n += int(t["tribute_price"])
	if bool(terms.get("repar", false)):
		n += int(t["repar_price"])
	if bool(terms.get("break", false)):
		n += int(t["break_price"])
	if bool(terms.get("free", false)):
		n += int(t["break_price"]) * maxi(1, subjects_of(state, loser).size())
	if String(terms.get("vassal", "")) != "":
		n += vassal_price(state, loser)
	return n


## Libellés des conditions, pour la chronique et l'écran des propositions.
static func terms_text(state: GameState, loser: int, terms: Dictionary) -> String:
	var parts := PackedStringArray()
	for sid in terms.get("cede", []):
		parts.append("céder %s" % state.galaxy.systems[int(sid)].system_name)
	if bool(terms.get("trib", false)):
		parts.append("tribut de %d %% pendant %d ans" % [int(_cfg("terms")["tribute_pct"]), int(_cfg("terms")["tribute_days"]) / GameCalendar.DAYS_PER_YEAR])
	if bool(terms.get("repar", false)):
		parts.append("réparations (%d %% des réserves)" % int(_cfg("terms")["repar_pct"]))
	if bool(terms.get("break", false)):
		parts.append("rompre ses alliances")
	if bool(terms.get("free", false)):
		parts.append("libérer ses sujets")
	if String(terms.get("vassal", "")) != "":
		parts.append("devenir %s" % preset_label(String(terms["vassal"])).to_lower())
	return ", ".join(parts) if not parts.is_empty() else "rien"


## Conditions bien formées et applicables ? "" si oui.
static func check_terms_set(state: GameState, winner: int, loser: int, terms: Dictionary) -> String:
	var any := false
	for k in terms:
		if not TERM_KEYS.has(String(k)):
			return "condition inconnue : %s" % k
	var cede: Array = terms.get("cede", [])
	if cede.size() > int(_cfg("terms")["cede_max"]):
		return "au plus %d systèmes cédés" % int(_cfg("terms")["cede_max"])
	var ok := cedable(state, loser)
	var seen := {}
	for sid in cede:
		if not ok.has(int(sid)) or seen.has(int(sid)):
			return "système non cessible (le vaincu doit le tenir, et pas sa capitale)"
		seen[int(sid)] = true
		any = true
	for k in ["trib", "repar", "break", "free"]:
		if bool(terms.get(k, false)):
			any = true
	if bool(terms.get("free", false)) and subjects_of(state, loser).is_empty():
		return "le vaincu n'a aucun sujet à libérer"
	if bool(terms.get("break", false)) and Diplomacy.allies(state, loser).is_empty():
		return "le vaincu n'a aucune alliance à rompre"
	var vp := String(terms.get("vassal", ""))
	if vp != "":
		if not free_presets().has(vp):
			return "préréglage inconnu : %s" % vp
		if is_subject(state, loser):
			return "%s est déjà le sujet d'un autre" % _name(state, loser)
		if is_subject(state, winner):
			return "un sujet ne prend pas de sujets"
		any = true
	if not any:
		return "aucune condition"
	return ""


## Le vainqueur peut-il proposer ces conditions ? "" si oui.
static func check_offer_terms(state: GameState, winner: int, loser: int, terms: Dictionary) -> String:
	var why := _check_pair(state, winner, loser)
	if why != "":
		return why
	if not state.vassals_on:
		return "les conditions de paix ne sont pas actives dans cette partie"
	if not Combat.at_war(state, winner, loser):
		return "vous n'êtes pas en guerre"
	if war_days(state, winner, loser) < int(_cfg("terms")["min_war_days"]):
		return "trop tôt : la guerre dure depuis %d jours (il en faut %d)" % [war_days(state, winner, loser), int(_cfg("terms")["min_war_days"])]
	why = check_terms_set(state, winner, loser, terms)
	if why != "":
		return why
	return _check_pending(state, winner, loser, "terms")


static func _check_pair(state: GameState, a: int, b: int) -> String:
	var ea := state.get_empire(a)
	var eb := state.get_empire(b)
	if ea == null or eb == null or a == b or GameState.is_npc(a) or GameState.is_npc(b):
		return "empire inconnu"
	if ea.eliminated or eb.eliminated:
		return "cet empire a disparu"
	if not ea.contacts.has(b):
		return "vous n'avez jamais rencontré cet empire"
	if Diplomacy.no_treaties(state, a) or Diplomacy.no_treaties(state, b):
		return "l'Essaim ne signe rien : il digère"
	return ""


static func _check_pending(state: GameState, from: int, to: int, kind: String) -> String:
	if not Diplomacy.pending(state, from, to, kind).is_empty():
		return "proposition déjà envoyée"
	var left := Diplomacy.cooldown_left(state, from, to, kind)
	if left > 0:
		return "trop tôt pour reproposer (%d jours)" % left
	return ""


## Applique des conditions acceptées : paix, puis chaque condition.
static func apply_terms(state: GameState, winner: int, loser: int, terms: Dictionary) -> void:
	Diplomacy.sign_treaty(state, winner, loser, Diplomacy.PEACE)
	var t := _cfg("terms")
	var text := terms_text(state, loser, terms)
	for sid in terms.get("cede", []):
		if state.system_owner(int(sid)) == loser:
			Combat.capture_system(state, int(sid), winner)
	if bool(terms.get("trib", false)):
		(state.vassals["trib"] as Array).append({"from": loser, "to": winner, "until": state.tick + int(t["tribute_days"]), "pct": int(t["tribute_pct"])})
	if bool(terms.get("repar", false)):
		var el := state.get_empire(loser)
		var ew := state.get_empire(winner)
		for r in ["materials", "energy", "influence"]:
			@warning_ignore("integer_division")
			var n := maxi(0, int(el.resources.get(r, 0))) * int(t["repar_pct"]) / 100
			el.resources[r] = int(el.resources.get(r, 0)) - n
			ew.resources[r] = int(ew.resources.get(r, 0)) + n
	if bool(terms.get("break", false)):
		for ally in Diplomacy.allies(state, loser):
			if Diplomacy.team_of(state, loser, ally) <= 0:
				var r := Diplomacy._rel_w(state, loser, ally)
				r["pact"] = Diplomacy.COLD
				r["since"] = state.tick
	if bool(terms.get("free", false)):
		for s in subjects_of(state, loser):
			unbind(state, s, "le traité de paix l'affranchit")
			Diplomacy.remember(state, s, winner, "vassal_freed")
	var vp := String(terms.get("vassal", ""))
	if vp != "":
		bind(state, winner, loser, vp, preset_clauses(vp), int(_cfg("loyalty")["start_terms"]), true)
	Diplomacy.remember(state, loser, winner, "harsh_terms")
	state.add_chronicle("Paix à conditions : %s impose à %s %s. On signe, et l'on compte ce qu'il reste." % [
			_name(state, winner), _name(state, loser), text], Espionage.public_to(state, [winner, loser]))


# --- Reddition (prop. 2) et protection (prop. 5) ---------------------------------------------------------

static func capital_lost(state: GameState, loser: int, winner: int) -> bool:
	return (state.vassals.get("cap", {}) as Dictionary).has("%d-%d" % [loser, winner])


## Capitale prise : le vaincu pourra se rendre.
static func on_capital_lost(state: GameState, loser: int, winner: int) -> void:
	if not state.vassals.has("cap"):
		state.vassals["cap"] = {}
	state.vassals["cap"]["%d-%d" % [loser, winner]] = state.tick


static func check_surrender(state: GameState, loser: int, winner: int) -> String:
	var why := _check_pair(state, loser, winner)
	if why != "":
		return why
	if not state.vassals_on:
		return "la reddition n'est pas active dans cette partie"
	if not Combat.at_war(state, loser, winner):
		return "vous n'êtes pas en guerre"
	var sc := _cfg("surrender")
	if Diplomacy.war_score(state, winner, loser) < int(sc["score"]) and not (bool(sc["capital"]) and capital_lost(state, loser, winner)):
		return "on ne se rend qu'à %d points de score contre soi, ou capitale perdue" % int(sc["score"])
	if is_subject(state, loser):
		return "vous êtes déjà le sujet d'un autre"
	if is_subject(state, winner):
		return "un sujet ne prend pas de sujets"
	return _check_pending(state, loser, winner, "surrender")


static func apply_surrender(state: GameState, loser: int, winner: int) -> void:
	Diplomacy.sign_treaty(state, winner, loser, Diplomacy.PEACE)
	bind(state, winner, loser, "vassal", preset_clauses("vassal"), int(_cfg("surrender")["loyalty"]), true)
	state.add_chronicle("%s se rend à %s et devient son vassal : plutôt plier le genou que disparaître. Les poètes hésitent entre la honte et la sagesse." % [
			_name(state, loser), _name(state, winner)], Espionage.public_to(state, [winner, loser]))


static func check_protect(state: GameState, weak: int, strong: int) -> String:
	var why := _check_pair(state, weak, strong)
	if why != "":
		return why
	if not state.vassals_on:
		return "les sujets ne sont pas actifs dans cette partie"
	if Combat.at_war(state, weak, strong):
		return "on ne demande pas protection à un ennemi"
	if is_subject(state, weak):
		return "vous êtes déjà le sujet d'un autre"
	if is_subject(state, strong):
		return "un sujet ne protège personne"
	if not subjects_of(state, weak).is_empty():
		return "libérez d'abord vos propres sujets"
	var pc := _cfg("protect")
	if power_pct(state, weak, strong) >= int(pc["power_pct"]):
		return "un protégé doit être bien plus faible (moins de %d %% de la puissance du protecteur)" % int(pc["power_pct"])
	if int(state.vassals.get("cd", {}).get(str(weak), 0)) > state.tick:
		return "trop tôt pour redemander protection"
	return _check_pending(state, weak, strong, "protect")


static func apply_protect(state: GameState, weak: int, strong: int) -> void:
	bind(state, strong, weak, "protectorat", preset_clauses("protectorat"), int(_cfg("protect")["loyalty"]), true)
	Diplomacy.remember(state, weak, strong, "protected_us")
	state.add_chronicle("%s se place sous la protection de %s. Le protégé rattrapera son retard ; le protecteur, lui, a déjà ses raisons." % [
			_name(state, weak), _name(state, strong)], Espionage.public_to(state, [weak, strong]))


# --- Renégociation (prop. 3) -----------------------------------------------------------------------

## Coût en influence d'un changement de clauses (0 si l'on ne fait qu'assouplir).
static func renegotiate_cost(state: GameState, sub: int, cl: Dictionary) -> int:
	var old: Dictionary = link(state, sub).get("cl", {})
	var delta := clauses_now(normalize(cl)) - clauses_now(old)
	if loosens(old, normalize(cl)):
		return 0
	var rc := _cfg("renegotiate")
	@warning_ignore("integer_division")
	return int(rc["base_cost"]) + int(rc["cost_per_point"]) * maxi(0, -delta) / 10


## Les nouvelles clauses ne font qu'assouplir (aucune clause plus dure, tribut pas plus lourd) ?
static func loosens(old: Dictionary, new: Dictionary) -> bool:
	for c in clause_defs():
		var cid := String(c["id"])
		if int(opt_def(cid, String(new.get(cid, ""))).get("m10", 0)) < int(opt_def(cid, String(old.get(cid, ""))).get("m10", 0)):
			return false
	for f in families():
		if int(new.get("trib", {}).get(f, 0)) > int(old.get("trib", {}).get(f, 0)):
			return false
	return true


static func check_set_terms(state: GameState, lord: int, sub: int, cl: Dictionary) -> String:
	if lord_of(state, sub) != lord or lord < 0:
		return "ce n'est pas votre sujet"
	if locked(state, sub):
		return "clauses imposées par l'Amphictyonie : non négociables"
	var why := check_clauses(cl)
	if why != "":
		return why
	var old: Dictionary = link(state, sub)["cl"]
	var n := normalize(cl)
	if n == old:
		return "rien ne change"
	if loosens(old, n):
		return ""
	if int(link(state, sub)["next"]) > state.tick:
		return "renégociation possible dans %d jours (on peut toujours assouplir)" % (int(link(state, sub)["next"]) - state.tick)
	if loyalty(state, sub) < int(_cfg("renegotiate")["refuse_below"]):
		return "%s refuse de discuter : sa loyauté est trop basse (assouplissez d'abord)" % _name(state, sub)
	var cost := renegotiate_cost(state, sub, n)
	if int(state.get_empire(lord).resources.get("influence", 0)) < cost:
		return "il faut %d influence" % cost
	return ""


static func set_terms(state: GameState, lord: int, sub: int, cl: Dictionary) -> void:
	var l := link(state, sub)
	var old: Dictionary = l["cl"]
	var n := normalize(cl)
	var soft := loosens(old, n)
	if not soft:
		state.get_empire(lord).resources["influence"] = int(state.get_empire(lord).resources.get("influence", 0)) - renegotiate_cost(state, sub, n)
		l["next"] = state.tick + int(_cfg("renegotiate")["every_days"])
	var lc := _cfg("loyalty")
	l["loy"] = clampi(int(l["loy"]) + clauses_now(n) - clauses_now(old), int(lc["min"]), int(lc["max"]))
	l["cl"] = n
	l["preset"] = _matching_preset(n)
	state.add_chronicle("%s %s les clauses de %s : %s." % [_name(state, lord), "assouplit" if soft else "renégocie", _name(state, sub), clauses_text(n)],
			Espionage.private_to(state, [lord, sub]))


static func _matching_preset(cl: Dictionary) -> String:
	for p in preset_defs():
		if bool(p.get("locked", false)):
			continue
		if normalize(p["cl"]) == cl:
			return String(p["id"])
	return "libre"


# --- Intégration (prop. 7) -------------------------------------------------------------------------

static func check_integrate(state: GameState, lord: int, sub: int) -> String:
	if lord_of(state, sub) != lord or lord < 0:
		return "ce n'est pas votre sujet"
	if clause(state, sub, "integ") != "permise":
		return "les clauses interdisent l'intégration"
	if int(link(state, sub)["integ"]) >= 0:
		return "intégration déjà en cours"
	var ic := _cfg("integration")
	if bond_days(state, sub) < int(ic["after_days"]):
		return "il faut %d ans de lien (encore %d jours)" % [int(ic["after_days"]) / GameCalendar.DAYS_PER_YEAR, int(ic["after_days"]) - bond_days(state, sub)]
	if loyalty(state, sub) < int(ic["min_loyalty"]):
		return "un sujet déloyal ne se laisse pas intégrer"
	if not Economy.can_afford(state.get_empire(lord), ic["cost"]):
		return "il faut %s par mois" % GameData.format_amounts(ic["cost"])
	return ""


static func integrate(state: GameState, lord: int, sub: int) -> void:
	var l := link(state, sub)
	l["integ"] = state.tick
	l["imo"] = 0
	state.add_chronicle("%s entreprend d'intégrer %s : un an de juristes, de cartographes et de discours sur l'unité retrouvée." % [
			_name(state, lord), _name(state, sub)], Espionage.public_to(state, [lord, sub]))


## Fin de l'intégration : colonies et flottes passent au suzerain, le sujet disparaît.
static func _absorb(state: GameState, lord: int, sub: int) -> void:
	var es := state.get_empire(sub)
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == sub:
			Peoples.on_owner_change(state, c, sub, lord)
			c.owner = lord
	for f in Fleets.empire_fleets(state, sub):
		f.owner = lord
	for sid in es.explored:
		state.get_empire(lord).explored[sid] = true
	state.rebuild_ownership()
	_subs(state).erase(str(sub))
	CombatSystem.eliminate(state, es)
	state.relic_rev += 1
	state.add_chronicle("%s est intégré à %s. Un drapeau de moins dans la galaxie, une province de plus dans les manuels." % [
			es.display_name(), _name(state, lord)], Espionage.public_to(state, [lord, sub]))


# --- Indépendance (prop. 8) ------------------------------------------------------------------------

static func check_release(state: GameState, lord: int, sub: int) -> String:
	if lord_of(state, sub) != lord or lord < 0:
		return "ce n'est pas votre sujet"
	if locked(state, sub):
		return "la Cour impériale ne libère personne : c'est l'Amphictyonie qui décide"
	return ""


static func release(state: GameState, lord: int, sub: int) -> void:
	unbind(state, sub)
	var r := Diplomacy._rel_w(state, lord, sub)
	r["pact"] = Diplomacy.PEACE
	r["since"] = state.tick
	r["truce"] = state.tick + int(_cfg("release")["truce_days"])
	Diplomacy.remember(state, sub, lord, "vassal_freed")
	state.add_chronicle("%s rend sa liberté à %s. Dix ans de trêve, et quelques regrets des deux côtés." % [_name(state, lord), _name(state, sub)],
			Espionage.public_to(state, [lord, sub]))


static func check_freedom(state: GameState, sub: int) -> String:
	var lord := lord_of(state, sub)
	if lord < 0:
		return "vous n'êtes le sujet de personne"
	if locked(state, sub):
		return "pour quitter la Cour impériale, il faut se soulever (Amphictyonie)"
	return _check_pending(state, sub, lord, "freedom")


## Puissance du camp de l'indépendance : le sujet et ses soutiens.
static func freedom_power(state: GameState, sub: int) -> int:
	var n := power(state, sub)
	for s in link(state, sub).get("sup", []):
		n += power(state, int(s))
	return n


## Le suzerain cède : le sujet est libre (trêve comme une libération).
static func grant_freedom(state: GameState, sub: int) -> void:
	var lord := lord_of(state, sub)
	unbind(state, sub)
	var r := Diplomacy._rel_w(state, lord, sub)
	r["pact"] = Diplomacy.PEACE
	r["since"] = state.tick
	r["truce"] = state.tick + int(_cfg("release")["truce_days"])
	state.add_chronicle("%s cède : %s retrouve son indépendance sans tirer un coup de feu." % [_name(state, lord), _name(state, sub)],
			Espionage.public_to(state, [lord, sub]))


## Le suzerain refuse : le lien est rompu, c'est la guerre d'indépendance ; les soutiens suivent.
static func freedom_war(state: GameState, sub: int) -> void:
	var lord := lord_of(state, sub)
	var sup: Array = link(state, sub).get("sup", []).duplicate()
	unbind(state, sub)
	Diplomacy._rel_w(state, lord, sub)["truce"] = 0
	Diplomacy.remember(state, lord, sub, "vassal_rebelled")
	state.add_chronicle("%s refuse l'indépendance à %s : c'est la guerre de libération." % [_name(state, lord), _name(state, sub)],
			Espionage.public_to(state, [lord, sub]))
	Combat.start_war(state, sub, lord)
	for s in sup:
		var x := int(s)
		var ex := state.get_empire(x)
		if ex == null or ex.eliminated or Combat.at_war(state, x, lord) or not ex.contacts.has(lord) or Diplomacy.allied(state, x, lord):
			continue
		Combat.start_war(state, x, lord, false, true)
		state.add_chronicle("%s tient parole et entre en guerre aux côtés de %s." % [ex.display_name(), _name(state, sub)], Espionage.public_to(state, [x, lord, sub]))


static func check_support(state: GameState, who: int, sub: int) -> String:
	var lord := lord_of(state, sub)
	if lord < 0:
		return "cet empire n'est le sujet de personne"
	if who == sub or who == lord:
		return "il faut être un tiers"
	var e := state.get_empire(who)
	if e == null or e.eliminated or not e.contacts.has(sub):
		return "vous n'avez jamais rencontré cet empire"
	if is_subject(state, who):
		return "un sujet ne soutient pas d'autres sujets"
	if locked(state, sub):
		return "la Cour impériale se combat à l'Amphictyonie"
	if (link(state, sub)["sup"] as Array).has(who):
		return "vous soutenez déjà son indépendance"
	var cost: Dictionary = _cfg("independence")["support_cost"]
	if not Economy.can_afford(e, cost):
		return "il faut %s" % GameData.format_amounts(cost)
	return ""


static func support(state: GameState, who: int, sub: int) -> void:
	Economy.pay(state.get_empire(who), _cfg("independence")["support_cost"])
	(link(state, sub)["sup"] as Array).append(who)
	var lord := lord_of(state, sub)
	Diplomacy.remember(state, lord, who, "rebel_supported")
	state.add_chronicle("%s soutient l'indépendance de %s : fonds, armes et promesses. %s fait semblant de ne rien voir." % [
			_name(state, who), _name(state, sub), _name(state, lord)], Espionage.private_to(state, [who, sub, lord]))


# --- Allégeance secrète (prop. 4) ------------------------------------------------------------------

static func check_fealty(state: GameState, sub: int, rival: int) -> String:
	var lord := lord_of(state, sub)
	if lord < 0:
		return "vous n'êtes le sujet de personne"
	if rival == -1:
		return "" if int(link(state, sub)["fealty"]) >= 0 else "aucune allégeance secrète"
	if rival == lord or rival == sub:
		return "il faut un rival de votre suzerain"
	var e := state.get_empire(rival)
	if e == null or e.eliminated or not state.get_empire(sub).contacts.has(rival):
		return "vous n'avez jamais rencontré cet empire"
	if is_subject(state, rival):
		return "un sujet ne protège personne"
	if int(link(state, sub)["fealty"]) == rival:
		return "c'est déjà votre allégeance secrète"
	return ""


static func set_fealty(state: GameState, sub: int, rival: int) -> void:
	link(state, sub)["fealty"] = rival


# --- Guerres (clauses « guerres suivies » et « diplomatie ») ---------------------------------------

## Ce qui s'ajoute à Diplomacy.check_war pour les sujets et suzerains.
static func check_war(state: GameState, a: int, b: int) -> String:
	if lord_of(state, b) == a:
		return "c'est votre sujet : libérez-le d'abord"
	if lord_of(state, a) == b:
		return "c'est votre suzerain : exigez d'abord l'indépendance"
	if is_subject(state, a):
		match clause(state, a, "dip"):
			"aucune":
				return "vos clauses vous interdisent de déclarer la guerre"
			"liee":
				if not Combat.at_war(state, lord_of(state, a), b):
					return "vos clauses ne permettent la guerre qu'aux ennemis de votre suzerain"
	return ""


## Ce qui s'ajoute à Diplomacy.check_terms : un sujet sans diplomatie ne signe qu'avec son suzerain.
static func check_treaty(state: GameState, a: int, b: int, treaty: String) -> String:
	for pair in [[a, b], [b, a]]:
		var s := int(pair[0])
		var o := int(pair[1])
		if is_subject(state, s) and clause(state, s, "dip") == "aucune" and lord_of(state, s) != o:
			return "les clauses de %s lui interdisent tout traité" % _name(state, s)
	if treaty == Diplomacy.ALLIANCE:
		for pair in [[a, b], [b, a]]:
			var s := int(pair[0])
			var o := int(pair[1])
			if is_subject(state, s) and Combat.at_war(state, lord_of(state, s), o):
				return "%s ne s'allie pas avec l'ennemi de son suzerain" % _name(state, s)
	return ""


static func _join(state: GameState, who: int, foe: int, friend: int, text: String) -> bool:
	var e := state.get_empire(who)
	if e == null or e.eliminated or who == foe or Combat.at_war(state, who, foe) or not e.contacts.has(foe):
		return false
	if Diplomacy.in_truce(state, who, foe) or Diplomacy.allied(state, who, foe) or lord_of(state, foe) == who or lord_of(state, who) == foe:
		return false
	Combat.start_war(state, who, foe, false, true)
	state.add_chronicle(text % [e.display_name(), _name(state, foe), _name(state, friend)], Espionage.public_to(state, [who, foe, friend]))
	return true


## Appelé par Diplomacy.on_war_declared : a déclare à b (joined : a suit un allié).
static func on_war_declared(state: GameState, a: int, b: int, joined: bool) -> void:
	if _subs(state).is_empty():
		return
	# Un lien entre ennemis ne survit pas.
	for pair in [[a, b], [b, a]]:
		if lord_of(state, int(pair[1])) == int(pair[0]):
			unbind(state, int(pair[1]), "suzerain et sujet sont en guerre")
	# Allégeance secrète : le sujet d'un camp, juré à l'autre, rompt et change de camp.
	for pair in [[a, b], [b, a]]:
		var lord := int(pair[0])
		var rival := int(pair[1])
		for s in subjects_of(state, lord):
			if int(link(state, s)["fealty"]) != rival:
				continue
			unbind(state, s, "il révèle son allégeance secrète à %s" % _name(state, rival))
			Diplomacy.remember(state, lord, s, "vassal_rebelled")
			Diplomacy._rel_w(state, lord, s)["truce"] = 0
			if not Combat.at_war(state, s, lord):
				Combat.start_war(state, s, lord, false, true)
	if joined:
		return
	# Le suzerain défend son sujet.
	var lb := lord_of(state, b)
	if lb >= 0 and lb != a:
		_join(state, lb, a, b, "%s vole au secours de son sujet et entre en guerre contre %s (pour %s).")
	# Les sujets défendent leur suzerain (« Défense » et « Toutes ») ; la Cour impériale passe par l'Amphictyonie.
	for s in subjects_of(state, b):
		if is_court(state, s) or s == a:
			continue
		if ["def", "toutes"].has(clause(state, s, "war")):
			_join(state, s, a, b, "%s, sujet fidèle, entre en guerre contre %s aux côtés de %s.")
	# Les sujets suivent les guerres déclarées par leur suzerain (« Toutes », s'ils sont loyaux).
	for s in subjects_of(state, a):
		if is_court(state, s) or s == b or clause(state, s, "war") != "toutes" or disloyal(state, s):
			continue
		_join(state, s, b, a, "%s suit son suzerain et entre en guerre contre %s aux côtés de %s.")


## Paix signée entre a et b : les sujets de chacun en guerre contre l'autre signent aussi.
static func on_peace(state: GameState, a: int, b: int) -> void:
	if _subs(state).is_empty():
		return
	for pair in [[a, b], [b, a]]:
		for s in subjects_of(state, int(pair[0])):
			if Combat.at_war(state, s, int(pair[1])):
				Diplomacy.sign_treaty(state, s, int(pair[1]), Diplomacy.PEACE)
	(state.vassals.get("cap", {}) as Dictionary).erase("%d-%d" % [a, b])
	(state.vassals.get("cap", {}) as Dictionary).erase("%d-%d" % [b, a])


# --- Expansion, protectorat ------------------------------------------------------------------------

## Ce qui s'ajoute à Economy.check_colonize.
static func check_found(state: GameState, eid: int) -> String:
	if is_subject(state, eid) and clause(state, eid, "exp") == "interdite":
		return "vos clauses vous interdisent toute nouvelle fondation"
	return ""


## Fondation payée : la dîme part chez le suzerain (la moitié du coût en influence, en plus).
static func on_found(state: GameState, eid: int, cost: Dictionary) -> void:
	if not is_subject(state, eid) or clause(state, eid, "exp") != "dime":
		return
	@warning_ignore("integer_division")
	var n := int(cost.get("influence", 0)) * int(data().get("dime_pct", 50)) / 100
	var e := state.get_empire(eid)
	n = mini(n, maxi(0, int(e.resources.get("influence", 0))))
	if n <= 0:
		return
	e.resources["influence"] = int(e.resources["influence"]) - n
	var le := state.get_empire(lord_of(state, eid))
	le.resources["influence"] = int(le.resources.get("influence", 0)) + n


## Bonus de Savoir du protégé tant qu'il connaît moins de technologies que son protecteur.
static func knowledge_pct(state: GameState, eid: int) -> int:
	if not is_protectorate(state, eid):
		return 0
	var lord := state.get_empire(lord_of(state, eid))
	if lord == null or state.get_empire(eid).techs.size() >= lord.techs.size():
		return 0
	return int(_cfg("protectorate").get("knowledge_pct", 0))


## Accord de recherche interdit aux protectorats.
static func check_pact(state: GameState, a: int, b: int) -> String:
	for x in [a, b]:
		if is_protectorate(state, int(x)):
			return "un protectorat ne signe pas d'accord de recherche"
	return ""


# --- Loyauté (prop. 4) -----------------------------------------------------------------------------

## Tendance mensuelle de la loyauté d'un sujet : [{label, value}] en dixièmes.
static func loyalty_parts(state: GameState, sub: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var l := link(state, sub)
	if l.is_empty():
		return out
	var lc := _cfg("loyalty")
	var lord := int(l["lord"])
	_part(out, "Clauses", clauses_m10(l["cl"]))
	_part(out, "Habitude du lien", int(lc.get("habit", 0)))
	@warning_ignore("integer_division")
	_part(out, "Opinion du suzerain", Diplomacy.opinion(state, sub, lord) / maxi(1, int(lc["opinion_div"])))
	var cs := String(Diplomacy._species(state, sub).get("credo", ""))
	if cs != "" and cs == String(Diplomacy._species(state, lord).get("credo", "")):
		_part(out, "Même credo", int(lc["same_credo"]))
	var pp := power_pct(state, sub, lord)
	if pp <= 50:
		_part(out, "Suzerain puissant", int(lc["power_strong"]))
	elif pp >= 100:
		_part(out, "Suzerain plus faible que nous", int(lc["power_weak"]))
	var others := subjects_of(state, lord).size() - 1
	if others > 0:
		_part(out, "Patronage divisé (%d autre%s sujet%s)" % [others, "s" if others > 1 else "", "s" if others > 1 else ""], int(lc["patronage"]) * mini(others, 3))
	if is_protectorate(state, sub):
		_part(out, "Protection", int(lc["protectorate"]))
	var le := state.get_empire(lord)
	for w in le.wars:
		if Diplomacy.war_score(state, lord, int(w)) <= -50:
			_part(out, "Le suzerain perd une guerre", int(lc["at_war_lost"]))
			break
	return out


static func _part(out: Array[Dictionary], label: String, value: int) -> void:
	if value != 0:
		out.append({"label": label, "value": value})


static func loyalty_trend(state: GameState, sub: int) -> int:
	var n := 0
	for p in loyalty_parts(state, sub):
		n += int(p["value"])
	return n


# --- Mensuel ---------------------------------------------------------------------------------------

## Appelé chaque mois par DiplomacySystem : liens morts, Cour, loyauté, tributs, intégrations.
static func monthly(state: GameState) -> void:
	sync_court(state)
	var lc := _cfg("loyalty")
	for s in all_subjects(state):
		var l := link(state, s)
		var lord := int(l["lord"])
		var es := state.get_empire(s)
		var el := state.get_empire(lord)
		if es == null or es.eliminated:
			_subs(state).erase(str(s))
			continue
		if el == null or el.eliminated:
			unbind(state, s, "son suzerain a disparu")
			continue
		l["loy"] = clampi(int(l["loy"]) + loyalty_trend(state, s), int(lc["min"]), int(lc["max"]))
		_pay_tribute(state, s, lord, l["cl"].get("trib", {}))
		if is_protectorate(state, s):
			var inc: Dictionary = _cfg("protectorate").get("lord_income", {})
			for r in inc:
				var n := mini(int(inc[r]), maxi(0, int(es.resources.get(r, 0))))
				es.resources[r] = int(es.resources.get(r, 0)) - n
				el.resources[r] = int(el.resources.get(r, 0)) + n
		if int(l["integ"]) >= 0:
			var ic := _cfg("integration")
			if loyalty(state, s) < int(ic["min_loyalty"]) or clause(state, s, "integ") != "permise":
				l["integ"] = -1
				state.add_chronicle("L'intégration de %s s'arrête : le sujet ne s'y prête plus." % es.display_name(), Espionage.public_to(state, [lord, s]))
			elif Economy.can_afford(el, ic["cost"]):
				Economy.pay(el, ic["cost"])
				l["imo"] = int(l["imo"]) + 1
				if int(l["imo"]) >= int(ic["months"]):
					_absorb(state, lord, s)
	# Tributs des paix à conditions.
	var kept: Array = []
	for t in state.vassals.get("trib", []):
		var ef := state.get_empire(int(t["from"]))
		var et := state.get_empire(int(t["to"]))
		if state.tick >= int(t["until"]) or ef == null or ef.eliminated or et == null or et.eliminated:
			continue
		var tr := {}
		for f in ["materials", "energy"]:
			tr[f] = int(t["pct"])
		_pay_tribute(state, int(t["from"]), int(t["to"]), tr)
		kept.append(t)
	state.vassals["trib"] = kept


## Verse au suzerain pct % du revenu net positif de chaque famille (dans la limite des réserves).
static func _pay_tribute(state: GameState, from: int, to: int, trib: Dictionary) -> void:
	if trib.is_empty():
		return
	var ef := state.get_empire(from)
	var et := state.get_empire(to)
	var net: Dictionary = Economy.empire_income(state, from)["net"]
	for f in families():
		var pct := int(trib.get(f, 0))
		if pct <= 0:
			continue
		@warning_ignore("integer_division")
		var n := maxi(0, int(net.get(f, 0))) * pct / 100
		n = mini(n, maxi(0, int(ef.resources.get(f, 0))))
		if n <= 0:
			continue
		ef.resources[f] = int(ef.resources.get(f, 0)) - n
		et.resources[f] = int(et.resources.get(f, 0)) + n


## Tribut mensuel estimé que verse un sujet (pour l'interface).
static func tribute_estimate(state: GameState, sub: int) -> Dictionary:
	var out := {}
	var trib: Dictionary = link(state, sub).get("cl", {}).get("trib", {})
	if trib.is_empty():
		return out
	var net: Dictionary = Economy.empire_income(state, sub)["net"]
	for f in trib:
		@warning_ignore("integer_division")
		var n := maxi(0, int(net.get(f, 0))) * int(trib[f]) / 100
		if n > 0:
			out[f] = n
	return out


# --- Cour impériale (prop. 9) ----------------------------------------------------------------------

## La Cour impériale de l'Amphictyonie est un préréglage verrouillé : ses soumis sont des sujets de
## l'Impérateur. La liste des soumis reste tenue par AmphPower ; on la reflète ici.
static func sync_court(state: GameState) -> void:
	var imp := AmphPower.imperator(state) if state.amph_on else -1
	for s in all_subjects(state):
		if not is_court(state, s):
			continue
		if imp < 0 or lord_of(state, s) != imp or not AmphPower.submitted(state, s):
			_subs(state).erase(str(s))
			state.relic_rev += 1
	if imp < 0:
		return
	for x in state.amph["imp"]["sub"]:
		var s := int(x)
		var e := state.get_empire(s)
		if e == null or e.eliminated or is_subject(state, s) or s == imp:
			continue
		bind(state, imp, s, "cour", preset_clauses("cour"), int(_cfg("loyalty")["start_court"]), true)


# --- Propositions ----------------------------------------------------------------------------------

static func is_kind(kind: String) -> bool:
	return KINDS.has(kind)


static func kind_label(p: Dictionary) -> String:
	match String(p["treaty"]):
		"terms":
			return "Paix à conditions"
		"surrender":
			return "Reddition (devenir vassal)"
		"protect":
			return "Demande de protection"
		"freedom":
			return "Exige son indépendance"
	return String(p["treaty"])


## Texte détaillé d'une proposition (conditions demandées).
static func kind_text(state: GameState, p: Dictionary) -> String:
	match String(p["treaty"]):
		"terms":
			return "Conditions : %s (prix %d, score %d)." % [terms_text(state, int(p["to"]), p.get("terms", {})),
					price(state, int(p["to"]), p.get("terms", {})), Diplomacy.war_score(state, int(p["from"]), int(p["to"]))]
		"surrender":
			return "Il deviendrait votre vassal (clauses du préréglage Vassal)."
		"protect":
			return "Il deviendrait votre protégé : vous le défendrez, il vous versera 1 influence par mois."
		"freedom":
			return "Refuser, c'est la guerre d'indépendance (soutiens : %d)." % (link(state, int(p["from"])).get("sup", []) as Array).size()
	return ""


## Validation d'une proposition (act → kind) ; "" si possible.
static func check_propose(state: GameState, kind: String, from: int, to: int, terms: Dictionary) -> String:
	match kind:
		"terms":
			return check_offer_terms(state, from, to, terms)
		"surrender":
			return check_surrender(state, from, to)
		"protect":
			return check_protect(state, from, to)
		"freedom":
			if lord_of(state, from) != to:
				return "ce n'est pas votre suzerain"
			return check_freedom(state, from)
	return "proposition inconnue"


## Réponse de l'IA destinataire : true si elle accepte.
static func ai_accepts(state: GameState, kind: String, from: int, to: int, terms: Dictionary) -> bool:
	var ai := _cfg("ai")
	match kind:
		"terms":
			return price(state, to, terms) <= Diplomacy.war_score(state, from, to)
		"surrender":
			var et := state.get_empire(to)
			return not bool(AiLevels.personality(et).get("temperament", {}).get("never_peace", false))
		"protect":
			return Diplomacy.opinion(state, to, from) >= int(ai["protect_opinion"])
		"freedom":
			return freedom_power(state, from) >= power(state, to)
	return false


static func propose(state: GameState, kind: String, from: int, to: int, terms: Dictionary) -> void:
	var et := state.get_empire(to)
	if et.is_ai():
		_resolve(state, kind, from, to, terms, ai_accepts(state, kind, from, to, terms))
		return
	state.proposals.append({"id": state.next_proposal_id, "from": from, "to": to, "treaty": kind, "tick": state.tick, "terms": terms.duplicate(true)})
	state.next_proposal_id += 1
	Diplomacy._set_cooldown(state, from, to, kind, Diplomacy.days("proposal_days", 30))
	state.add_chronicle("%s adresse à %s : %s." % [_name(state, from), _name(state, to), kind_label({"treaty": kind}).to_lower()],
			Espionage.private_to(state, [from, to]))


static func check_accept(state: GameState, p: Dictionary) -> String:
	var kind := String(p["treaty"])
	var from := int(p["from"])
	var to := int(p["to"])
	match kind:
		"terms":
			if not Combat.at_war(state, from, to):
				return "la guerre est finie"
			return check_terms_set(state, from, to, p.get("terms", {}))
		"surrender":
			if not Combat.at_war(state, from, to) or is_subject(state, from) or is_subject(state, to):
				return "la reddition n'a plus d'objet"
		"protect":
			if is_subject(state, from) or is_subject(state, to) or Combat.at_war(state, from, to):
				return "la demande n'a plus d'objet"
		"freedom":
			if lord_of(state, from) != to:
				return "la demande n'a plus d'objet"
	return ""


## Réponse humaine (proposition retirée de la file par Diplomacy.answer).
static func answer(state: GameState, p: Dictionary, accept: bool) -> void:
	_resolve(state, String(p["treaty"]), int(p["from"]), int(p["to"]), p.get("terms", {}), accept)


static func _resolve(state: GameState, kind: String, from: int, to: int, terms: Dictionary, accept: bool) -> void:
	match kind:
		"terms":
			if accept:
				apply_terms(state, from, to, terms)
				return
		"surrender":
			if accept:
				apply_surrender(state, from, to)
				return
		"protect":
			if accept:
				apply_protect(state, from, to)
				return
			if not state.vassals.has("cd"):
				state.vassals["cd"] = {}
			state.vassals["cd"][str(from)] = state.tick + int(_cfg("protect")["cooldown_days"])
		"freedom":
			if accept:
				grant_freedom(state, from)
			else:
				freedom_war(state, from)
			return
	Diplomacy._set_cooldown(state, from, to, kind, int(_cfg("terms")["cooldown_days"]))
	state.add_chronicle("%s repousse la proposition de %s (%s)." % [_name(state, to), _name(state, from), kind_label({"treaty": kind}).to_lower()],
			Espionage.private_to(state, [from, to]))


# --- Ordre unique ----------------------------------------------------------------------------------

static func check_act(state: GameState, player: int, act: String, x: int, s: String, terms: Dictionary) -> String:
	var e := state.get_empire(player)
	if e == null or e.eliminated:
		return "empire inconnu"
	match act:
		"terms":
			return check_propose(state, "terms", player, x, terms)
		"surrender":
			return check_propose(state, "surrender", player, x, terms)
		"protect":
			return check_propose(state, "protect", player, x, terms)
		"freedom":
			return check_propose(state, "freedom", player, lord_of(state, player), terms)
		"set_terms":
			var cl := terms if s == "" else preset_clauses(s)
			if s != "" and not free_presets().has(s):
				return "préréglage inconnu : %s" % s
			return check_set_terms(state, player, x, cl)
		"release":
			return check_release(state, player, x)
		"integrate":
			return check_integrate(state, player, x)
		"support":
			return check_support(state, player, x)
		"fealty":
			return check_fealty(state, player, x)
	return "action inconnue : %s" % act


static func act(state: GameState, player: int, act_id: String, x: int, s: String, terms: Dictionary) -> void:
	match act_id:
		"terms", "surrender", "protect":
			propose(state, act_id, player, x, terms)
		"freedom":
			propose(state, "freedom", player, lord_of(state, player), terms)
		"set_terms":
			set_terms(state, player, x, terms if s == "" else preset_clauses(s))
		"release":
			release(state, player, x)
		"integrate":
			integrate(state, player, x)
		"support":
			support(state, player, x)
		"fealty":
			set_fealty(state, player, x)
