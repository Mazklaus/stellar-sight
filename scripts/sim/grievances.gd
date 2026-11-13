class_name Grievances
extends RefCounted
## Doléances et crise de régime (étude « Politique des peuples », lot 3 : propositions 12, 13 et 15).
## Doléances : le plus grand courant d'opposition formule une demande tirée de ce qui le nourrit
## (gagner une bataille, signer un traité, fonder une colonie…) ; satisfaite à temps, il gagne du
## terrain et ses systèmes de la stabilité ; ignorée, ils en perdent. Les espions d'un rival peuvent en
## financer une seconde, plus exigeante. Crise de régime : une stabilité d'empire trop basse pendant un
## an (ou un coup d'État réussi) met seul au pouvoir le courant opposé au courant en tête, révoque les
## lois et ouvre un interrègne sans lois. Données : data/politics.json "grievances", "crisis".
##
## Dans l'entrée d'empire de Politics : "grv" (doléance en cours, {} aucune), "grv2" (doléance
## financée), "grv_next" (jour de la prochaine), "gfx" (effets de stabilité en cours : [{c, v, end}]),
## "low" (mois de suite sous le seuil de crise), "inter" (fin de l'interrègne).


static func cfg() -> Dictionary:
	return Politics.data()["grievances"]


static func ccfg() -> Dictionary:
	return Politics.data()["crisis"]


## Le plus grand courant hors du pouvoir, s'il pèse assez (au moins min_pmille, sauf force).
static func opposition(state: GameState, empire_id: int, force := false) -> int:
	var op := Politics.empire_opinion(state, empire_id)
	var best := -1
	for i in Politics.N:
		if Politics.in_power(state, empire_id, i):
			continue
		if best < 0 or int(op[i]) > int(op[best]):
			best = i
	if best >= 0 and not force and int(op[best]) < int(cfg()["min_pmille"]):
		return -1
	return best


static func _make(state: GameState, c: int, funded: bool) -> Dictionary:
	var bc: Dictionary = cfg()["by_current"][Politics.current_id(c)]
	var need := int(bc["need"]) * (int(cfg()["funded_x"]) if funded else 1)
	return {"c": c, "acts": (bc["acts"] as Array).duplicate(), "need": need, "got": 0, "end": state.tick + int(cfg()["days"]), "f": funded}


## « la Forge demande d'achever 3 bâtiments (1/3) avant le 12/03/2403 ».
static func text(state: GameState, empire_id: int, g: Dictionary) -> String:
	var bc: Dictionary = cfg()["by_current"][Politics.current_id(int(g["c"]))]
	var what := String(bc["label"])
	if what.find("%d") >= 0:
		what = what % int(g["need"])
	var who := Politics.label(state, empire_id, int(g["c"]))
	return "%s demande de %s (%d/%d) avant le %s" % [who.substr(0, 1).to_upper() + who.substr(1), what,
			mini(int(g["got"]), int(g["need"])), int(g["need"]), GameCalendar.date_string(int(g["end"]))]


static func current(state: GameState, empire_id: int) -> Array:
	var out := []
	var en := Politics.emp(state, empire_id)
	for k in ["grv", "grv2"]:
		var g: Dictionary = en.get(k, {})
		if not g.is_empty():
			out.append(g)
	return out


## Un acte de l'empire fait avancer ses doléances (Politics.on_act, bâtiments).
static func on_act(state: GameState, empire_id: int, kind: String, n := 1) -> void:
	var en: Dictionary = state.politics["emp"].get(empire_id, {})
	if en.is_empty():
		return
	for k in ["grv", "grv2"]:
		var g: Dictionary = en.get(k, {})
		if not g.is_empty() and (g["acts"] as Array).has(kind):
			g["got"] = int(g["got"]) + maxi(1, n)


## Bilan mensuel : doléances tenues ou ignorées, nouvelle doléance, effets échus, crise de régime.
static func monthly(state: GameState, empire_id: int, en: Dictionary, added: Array[Dictionary]) -> void:
	var e := state.get_empire(empire_id)
	var c := cfg()
	for k in ["grv", "grv2"]:
		var g: Dictionary = en.get(k, {})
		if g.is_empty():
			continue
		var ci := int(g["c"])
		if int(g["got"]) >= int(g["need"]):
			for sid in Stability.systems_of(state, empire_id):
				Politics.push(state, sid, ci, int(c["push"]))
			_fx(en, ci, int(c["stability"]), state.tick + int(c["fx_days"]))
			en.erase(k)
			if not e.is_ai():
				added.append(state.add_chronicle("%s : %s est écoutée. Ses partisans applaudissent, et le font savoir pendant un an (+%d stabilité là où l'on penche pour lui)." % [
						e.short_name(), Politics.label(state, empire_id, ci), int(c["stability"])], Espionage.private_to(state, [empire_id])))
		elif state.tick >= int(g["end"]):
			_fx(en, ci, int(c["stability_fail"]), state.tick + int(c["fx_days"]))
			en.erase(k)
			if not e.is_ai():
				added.append(state.add_chronicle("%s : la doléance de %s est restée lettre morte. Ses partisans grognent (%d stabilité là où l'on penche pour lui, un an)." % [
						e.short_name(), Politics.label(state, empire_id, ci), int(c["stability_fail"])], Espionage.private_to(state, [empire_id])))
		if not en.has(k) and k == "grv":
			en["grv_next"] = state.tick + int(c["cooldown"])
	var fx: Array = en.get("gfx", [])
	var keep := []
	for f in fx:
		if int(f["end"]) > state.tick:
			keep.append(f)
	if keep.size() != fx.size():
		en["gfx"] = keep
	if not en.has("grv") and state.tick >= int(en.get("grv_next", 360)):
		var o := opposition(state, empire_id)
		if o >= 0:
			en["grv"] = _make(state, o, false)
			if not e.is_ai():
				added.append(state.add_chronicle("%s : doléance. %s." % [e.short_name(), text(state, empire_id, en["grv"])], Espionage.private_to(state, [empire_id])))
	_crisis_check(state, empire_id, en, added)


static func _fx(en: Dictionary, c: int, v: int, end: int) -> void:
	var fx: Array = en.get("gfx", [])
	fx.append({"c": c, "v": v, "end": end})
	en["gfx"] = fx


## Doléance financée par des espions (opération « Financer l'opposition ») ; renvoie la phrase.
static func fund(state: GameState, empire_id: int) -> String:
	var en := Politics._emp_w(state, empire_id)
	if en.has("grv2"):
		return "l'opposition avait déjà ses mécènes. Notre argent a fini en banquets."
	var o := opposition(state, empire_id, true)
	if o < 0:
		return "il n'y avait pas d'opposition à financer. Une rareté."
	en["grv2"] = _make(state, o, true)
	return "%s reçoit nos fonds et durcit le ton : %s." % [Politics.label(state, empire_id, o), text(state, empire_id, en["grv2"])]


## Lignes de stabilité des doléances pour un système (voir Stability.parts).
static func stability_parts(state: GameState, sid: int, owner: int) -> Array:
	var out := []
	var fx: Array = Politics.emp(state, owner).get("gfx", [])
	if fx.is_empty():
		return out
	var op := Politics.opinion(state, sid)
	if op.is_empty():
		return out
	var top := Politics._argmax(op)
	for f in fx:
		if int(f["c"]) == top and int(f["end"]) > state.tick:
			out.append(["Doléance de %s %s" % [Politics.short(state, owner, top), "écoutée" if int(f["v"]) > 0 else "ignorée"], int(f["v"])])
	return out


# --- Crise de régime ---------------------------------------------------------------------------

static func interregnum(state: GameState, empire_id: int) -> bool:
	return int(Politics.emp(state, empire_id).get("inter", -1)) > state.tick


static func _crisis_check(state: GameState, empire_id: int, en: Dictionary, added: Array[Dictionary]) -> void:
	var cc := ccfg()
	if not Stability.applies(state, empire_id) or state.stability.is_empty():
		return
	if Stability.empire_value(state, empire_id) < int(cc["below"]):
		en["low"] = int(en.get("low", 0)) + 1
	else:
		en.erase("low")
	if int(en.get("low", 0)) >= int(cc["months"]):
		added.append_array(crisis(state, empire_id, "stabilité d'empire sous %d depuis un an" % int(cc["below"])))


## Crise : le courant opposé au courant en tête gouverne seul, lois révoquées, interrègne.
static func crisis(state: GameState, empire_id: int, why: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var lead := Politics.lead(state, empire_id)
	if lead < 0:
		return out
	var en := Laws._w(state, empire_id)
	var nw := Politics.opposite(lead)
	en["ruling"] = [nw]
	var xp: Array = en["xp"]
	xp[nw] = maxi(1, int(xp[nw]))
	var n := (en["laws"] as Array).size()
	en["laws"] = []
	en["inter"] = state.tick + int(ccfg()["interregnum_days"])
	en.erase("low")
	state.relic_rev += 1
	var e := state.get_empire(empire_id)
	out.append(state.add_chronicle("Crise de régime chez %s (%s) : %s tombe, %s prend seul le pouvoir. %s Six mois d'interrègne, sans lois." % [
			e.short_name(), why, Politics.label(state, empire_id, lead), Politics.label(state, empire_id, nw),
			("%d loi%s révoquée%s." % [n, "s" if n > 1 else "", "s" if n > 1 else ""]) if n > 0 else ""]))
	return out
