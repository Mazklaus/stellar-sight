class_name Politics
extends RefCounted
## Politique intérieure (étude « Politique des peuples », 2026-11-12, lot 1 : le socle).
## Six courants sur une roue (data/politics.json "currents", dans l'ordre de la roue) : chaque système
## d'un empire a une opinion en pour mille (somme 1000) que les actes de l'empire déplacent et qui
## revient lentement vers le penchant naturel du peuple (credo et gouvernement). Tous les 1080 jours,
## chaque système élit des représentants par tirage pondéré (hachage de la graine : identique sur
## toutes les machines) ; les courants battus donnent leurs voix au voisin le plus proche sur la roue,
## jamais à l'opposé. Les règles du vote (courants au pouvoir, représentants, choix direct) dépendent
## de la couche gouvernement ("regimes"). Un système dont la majorité des représentants est au pouvoir
## gagne de la stabilité, sinon il en perd (voir Stability.parts).
##
## state.politics = {"emp": {empire: entrée d'empire}, "sys": {système: entrée de système}}.
## Entrée d'empire : {"ruling": [courants au pouvoir, le premier en tête], "votes": [représentants
##   élus par courant], "final": [voix après redistribution], "next": jour de la prochaine élection,
##   "last": jour de la dernière, "n": élections tenues, "pick": courant soutenu (-1 aucun),
##   "top": courant arrivé en tête du vote populaire, "fervor": ferveur payée au Conclave ; lot 2 :
##   "laws", "xp", "act", "cm", voir Laws}.
## Entrée de système : {"o": propriétaire, "op": [6 entiers, somme 1000], "reps": [représentants
##   par courant à la dernière élection], "rep": courant majoritaire (-1 sans représentants),
##   "pop": population au dernier bilan}.
## Les lectures (interface) ne créent jamais d'entrée : seuls la simulation et les ordres écrivent.

const N := 6
const TOTAL := 1000


static func data() -> Dictionary:
	return GameData.politics()


# --- Courants ----------------------------------------------------------------------------------

static func current_def(i: int) -> Dictionary:
	var cs: Array = data()["currents"]
	return cs[i] if i >= 0 and i < cs.size() else {}


static func current_id(i: int) -> String:
	return String(current_def(i).get("id", ""))


static func index_of(id: String) -> int:
	var cs: Array = data()["currents"]
	for i in cs.size():
		if String(cs[i]["id"]) == id:
			return i
	return -1


static func color(i: int) -> Color:
	return Color(String(current_def(i).get("color", "#a9b4c2")))


## Nom d'un courant pour un empire (son registre peut le renommer) : « la Forge », « l'Ecclésiarchat ».
static func label(state: GameState, empire_id: int, i: int) -> String:
	var e := state.get_empire(empire_id) if state != null else null
	if e != null and not e.is_npc():
		var reg := String(e.faction().get("registre", ""))
		var names: Dictionary = (data().get("names_by_register", {}) as Dictionary).get(reg, {})
		if names.has(current_id(i)):
			return String(names[current_id(i)])
	return String(current_def(i).get("label", "?"))


## Nom court, sans article (« Forge », « Ecclésiarchat »).
static func short(state: GameState, empire_id: int, i: int) -> String:
	var l := label(state, empire_id, i)
	for art in ["les ", "la ", "le ", "l'"]:
		if l.begins_with(art) and l.length() > art.length():
			var rest := l.substr(art.length())
			return rest.substr(0, 1).to_upper() + rest.substr(1)
	return l


## Distance sur la roue (0 à 3) ; 3 = courant opposé.
static func wheel_dist(a: int, b: int) -> int:
	var d := absi(a - b) % N
	return mini(d, N - d)


static func opposite(i: int) -> int:
	return (i + int(data().get("opposite_offset", 3))) % N


# --- Régimes -----------------------------------------------------------------------------------

static func government_of(state: GameState, empire_id: int) -> String:
	var e := state.get_empire(empire_id)
	if e == null or e.is_npc():
		return ""
	return String((e.faction().get("species", {}) as Dictionary).get("gouvernement", ""))


static func regime_id(state: GameState, empire_id: int) -> String:
	var g := government_of(state, empire_id)
	return g if (data()["regimes"] as Dictionary).has(g) else String(data()["default_regime"])


static func regime(state: GameState, empire_id: int) -> Dictionary:
	return data()["regimes"][regime_id(state, empire_id)]


static func seats(state: GameState, empire_id: int) -> int:
	return int(regime(state, empire_id).get("seats", 0))


static func mode(state: GameState, empire_id: int) -> String:
	return String(regime(state, empire_id).get("mode", "none"))


## L'empire a-t-il une vie politique ? (option de partie, pas de PNJ, pas d'esprit de ruche.)
static func enabled(state: GameState) -> bool:
	return state.politics_on


static func applies(state: GameState, empire_id: int) -> bool:
	if not state.politics_on:
		return false
	var e := state.get_empire(empire_id)
	return e != null and not e.is_npc() and not e.eliminated and seats(state, empire_id) > 0


# --- Penchant et opinion -----------------------------------------------------------------------

## Penchant naturel du peuple, en pour mille (somme 1000).
static func nature(state: GameState, empire_id: int) -> Array:
	var e := state.get_empire(empire_id)
	var ld: Dictionary = data()["lean"]
	var sp: Dictionary = e.faction().get("species", {}) if e != null and not e.is_npc() else {}
	var p := index_of(String((ld["credo"] as Dictionary).get(String(sp.get("credo", "")), "")))
	var s := index_of(String((ld["gouvernement"] as Dictionary).get(String(sp.get("gouvernement", "")), "")))
	if p < 0:
		p = s if s >= 0 else 0
	if s < 0 or s == p:
		s = (p + 1) % N
	var main := int(ld["principal"])
	var sec := int(ld["secondary"])
	@warning_ignore("integer_division")
	var rest := (TOTAL - main - sec) / (N - 2)
	var out := []
	for i in N:
		out.append(main if i == p else (sec if i == s else rest))
	_normalize(out, p)
	return out


## Courant principal du peuple (le plus fort de son penchant).
static func principal(state: GameState, empire_id: int) -> int:
	return _argmax(nature(state, empire_id))


static func sys_entry(state: GameState, sid: int) -> Dictionary:
	return state.politics["sys"].get(sid, {})


static func emp(state: GameState, empire_id: int) -> Dictionary:
	return state.politics["emp"].get(empire_id, {})


## Opinion d'un système (copie), le penchant du propriétaire s'il n'a pas encore d'entrée.
static func opinion(state: GameState, sid: int) -> Array:
	var en := sys_entry(state, sid)
	var owner := state.system_owner(sid)
	if not en.is_empty() and int(en.get("o", -1)) == owner:
		return (en["op"] as Array).duplicate()
	if owner < 0 or GameState.is_npc(owner):
		return []
	return nature(state, owner)


## Opinion de l'empire : moyenne de ses systèmes pondérée par la population (au moins 1 chacun).
static func empire_opinion(state: GameState, empire_id: int) -> Array:
	var tot := [0, 0, 0, 0, 0, 0]
	var w := 0
	for sid in Stability.systems_of(state, empire_id):
		var p := maxi(1, Stability.system_pop(state, sid, empire_id))
		var op := opinion(state, sid)
		if op.is_empty():
			continue
		for i in N:
			tot[i] += int(op[i]) * p
		w += p
	if w == 0:
		return nature(state, empire_id)
	for i in N:
		@warning_ignore("integer_division")
		tot[i] = tot[i] / w
	_normalize(tot, _argmax(tot))
	return tot


static func ruling(state: GameState, empire_id: int) -> Array:
	return (emp(state, empire_id).get("ruling", []) as Array).duplicate()


## Courant en tête du gouvernement (-1 sans vie politique).
static func lead(state: GameState, empire_id: int) -> int:
	var r := ruling(state, empire_id)
	return int(r[0]) if not r.is_empty() else -1


static func in_power(state: GameState, empire_id: int, i: int) -> bool:
	return ruling(state, empire_id).has(i)


static func next_election(state: GameState, empire_id: int) -> int:
	return int(emp(state, empire_id).get("next", -1))


# --- Écriture (simulation) ---------------------------------------------------------------------

static func _sys_w(state: GameState, sid: int, owner: int) -> Dictionary:
	var en: Dictionary = state.politics["sys"].get(sid, {})
	if en.is_empty() or int(en.get("o", -1)) != owner:
		en = {"o": owner, "op": nature(state, owner), "reps": [], "rep": -1, "pop": Stability.system_pop(state, sid, owner)}
		state.politics["sys"][sid] = en
	return en


static func _emp_w(state: GameState, empire_id: int) -> Dictionary:
	var en: Dictionary = state.politics["emp"].get(empire_id, {})
	if en.is_empty():
		var nat := nature(state, empire_id)
		@warning_ignore("integer_division")
		var first := int(data()["election_days"]) * (1 + state.tick / int(data()["election_days"]))
		en = {"ruling": _top(nat, seats(state, empire_id)), "votes": [], "final": [], "last": -1, "n": 0, "pick": -1, "top": -1,
				"next": first}
		state.politics["emp"][empire_id] = en
	return en


## Pousse un courant de pts pour mille dans un système : les autres reculent en proportion.
static func push(state: GameState, sid: int, i: int, pts: int) -> void:
	var owner := state.system_owner(sid)
	if pts <= 0 or i < 0 or not applies(state, owner):
		return
	var op: Array = _sys_w(state, sid, owner)["op"]
	pts = mini(pts, TOTAL)
	for k in N:
		@warning_ignore("integer_division")
		op[k] = int(op[k]) * (TOTAL - pts) / TOTAL
	op[i] = int(op[i]) + pts
	_normalize(op, i)


## Un acte de l'empire (compteurs d'actes des héros et de Research.count_stat) : poussée partout.
static func on_act(state: GameState, empire_id: int, kind: String, n := 1) -> void:
	if not state.politics_on:
		return
	var a: Dictionary = (data()["acts"] as Dictionary).get(kind, {})
	if a.is_empty() or not applies(state, empire_id):
		return
	var i := index_of(String(a["current"]))
	var pts := int(a["all"]) * maxi(1, n)
	for sid in Stability.systems_of(state, empire_id):
		push(state, sid, i, pts)


static func push_local(state: GameState, sid: int, current: String, key: String) -> void:
	if not state.politics_on:
		return
	push(state, sid, index_of(current), int((data()["local"] as Dictionary).get(key, 0)))


## Bâtiment achevé : la Forge (l'Autel pour une cathédrale) gagne du terrain dans le système.
static func on_building(state: GameState, sid: int, building_id: String) -> void:
	if building_id == "cathedrale":
		push_local(state, sid, "autel", "cathedrale")
	else:
		push_local(state, sid, "forge", "built")


## Vaisseau de guerre lancé : le Glaive gagne du terrain dans le système du chantier.
static func on_ship(state: GameState, sid: int, armed: bool) -> void:
	if armed:
		push_local(state, sid, "glaive", "warship")


static func on_colony(state: GameState, sid: int) -> void:
	push_local(state, sid, "seve", "colony")


static func on_battle(state: GameState, b: Dictionary, winner: int) -> void:
	var sid := int(b.get("system", -1))
	if winner >= 0 and sid >= 0 and state.system_owner(sid) == winner:
		push_local(state, sid, "glaive", "battle")


# --- Bilan mensuel -----------------------------------------------------------------------------

## Chaque mois : opinion qui revient vers le penchant, croissance (Sève), attaques (Glaive), paix
## (Concorde), consensus des consciences, élections arrivées à échéance.
static func monthly(state: GameState, empire_id: int, added: Array[Dictionary]) -> void:
	var e := state.get_empire(empire_id)
	var en := _emp_w(state, empire_id)
	var nat := nature(state, empire_id)
	var drift := int(data()["drift_pct"])
	var loc: Dictionary = data()["local"]
	var at_peace := e.wars.is_empty() and state.tick >= 360
	var gl := index_of("glaive")
	var sv := index_of("seve")
	var cc := index_of("concorde")
	for sid in Stability.systems_of(state, empire_id):
		var se := _sys_w(state, sid, empire_id)
		var op: Array = se["op"]
		for i in N:
			@warning_ignore("integer_division")
			op[i] = int(op[i]) + (int(nat[i]) - int(op[i])) * drift / 100
		_normalize(op, _argmax(op))
		var pop := Stability.system_pop(state, sid, empire_id)
		if pop > int(se.get("pop", 0)):
			push(state, sid, sv, int(loc["growth"]))
		se["pop"] = pop
		var st := Stability.entry(state, sid)
		if st.has("hit") and state.tick - int(st["hit"]) < int(GameData.rules()["month_days"]):
			push(state, sid, gl, int(loc["attacked"]))
		if at_peace:
			push(state, sid, cc, int(data()["peace_monthly"]))
	if mode(state, empire_id) == "continuous":
		_consensus(state, empire_id, en)
		return
	if int(en["next"]) - state.tick == 90 and not e.is_ai():
		added.append(state.add_chronicle("%s : %s dans trois mois. %s (Sénat, touche P)." % [e.short_name(), "le Conclave se réunit" if mode(state, empire_id) == "appoint" else "élections",
				"Choisissez le courant à nommer" if mode(state, empire_id) == "appoint" else "Le soutien officiel, c'est maintenant"], Espionage.private_to(state, [empire_id])))
	if state.tick >= int(en["next"]):
		added.append_array(run_election(state, empire_id))


## Conscience distribuée : les deux courants dominants des nœuds reliés gouvernent, chaque mois.
static func _consensus(state: GameState, empire_id: int, en: Dictionary) -> void:
	var net := FactionTraits.network_systems(state, empire_id)
	var tot := [0, 0, 0, 0, 0, 0]
	for sid in Stability.systems_of(state, empire_id):
		var se := _sys_w(state, sid, empire_id)
		if not net.has(sid):
			se["rep"] = -1
			se["reps"] = []
			continue
		var op: Array = se["op"]
		var p := maxi(1, Stability.system_pop(state, sid, empire_id))
		for i in N:
			tot[i] += int(op[i]) * p
		se["rep"] = _argmax(op)
	var r := _top(tot, seats(state, empire_id))
	if r != en.get("ruling", []):
		state.relic_rev += 1  # loi de pouvoir (voir Laws)
	en["ruling"] = r
	en["votes"] = tot.duplicate()
	en["top"] = _argmax(tot)


# --- Élections ---------------------------------------------------------------------------------

## Représentants d'un système selon le régime.
static func reps_count(state: GameState, empire_id: int, sid: int) -> int:
	var rule := String(regime(state, empire_id).get("reps", "pop"))
	var pop := Stability.system_pop(state, sid, empire_id)
	match rule:
		"level":
			@warning_ignore("integer_division")
			return 1 + Stability.colony_systems_in(state, empire_id, sid) + pop / 6
		"production":
			var prod := 0
			for pid in state.galaxy.systems[sid].planet_ids:
				var c: Colony = state.colonies.get(pid)
				if c != null and c.owner == empire_id and c.is_established():
					var y := Economy.colony_yields(state, c)
					prod += int(y.get("energy", 0)) + int(y.get("materials", 0))
			@warning_ignore("integer_division")
			return 1 + maxi(0, prod) / 8
	return pop


## Tient l'élection de l'empire : représentants par système, courants au pouvoir, redistribution
## des voix des battus. Renvoie les entrées de chronique.
static func run_election(state: GameState, empire_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var e := state.get_empire(empire_id)
	var en := _emp_w(state, empire_id)
	var reg := regime(state, empire_id)
	var pick := int(en.get("pick", -1))
	var bonus := int(data()["support_bonus"])
	# Action électorale et héros du Conseil (voir Laws), en vote libre seulement.
	var extra: Array = Laws.vote_weights(state, empire_id) if String(reg["mode"]) == "vote" else [0, 0, 0, 0, 0, 0]
	var votes := [0, 0, 0, 0, 0, 0]
	var sys_reps := {}
	for sid in Stability.systems_of(state, empire_id):
		var se := _sys_w(state, sid, empire_id)
		var n := reps_count(state, empire_id, sid)
		var reps := [0, 0, 0, 0, 0, 0]
		var w: Array = (se["op"] as Array).duplicate()
		if pick >= 0 and String(reg["mode"]) == "vote":
			w[pick] = int(w[pick]) + bonus
		for i in N:
			w[i] = int(w[i]) + int(extra[i])
		var total := 0
		for x in w:
			total += int(x)
		for k in n:
			var r := posmod(hash([state.seed_value, "vote", state.tick, empire_id, sid, k]), maxi(1, total))
			var acc := 0
			for i in N:
				acc += int(w[i])
				if r < acc:
					reps[i] += 1
					break
		for i in N:
			votes[i] += reps[i]
		se["reps"] = reps
		sys_reps[sid] = reps
	var top := _argmax(votes)
	var winners: Array
	var paid := 0
	if String(reg["mode"]) == "appoint":
		var chosen := pick if pick >= 0 else top
		winners = [chosen]
		if chosen != top and int(reg.get("fervor_cost", 0)) > 0 and FactionTraits.has_fervor(e.faction()):
			paid = mini(e.fervor, int(reg["fervor_cost"]))
			e.fervor -= paid
	else:
		# Un courant sans aucun élu ne siège pas (s'il en reste, le gouvernement est plus étroit).
		winners = []
		for wi in _top(votes, int(reg["seats"])):
			if int(votes[int(wi)]) > 0 or winners.is_empty():
				winners.append(int(wi))
	var final := [0, 0, 0, 0, 0, 0]
	for wi in winners:
		final[int(wi)] = int(votes[int(wi)])
	for i in N:
		if winners.has(i) or int(votes[i]) == 0:
			continue
		var best := 99
		var near: Array = []
		for wi in winners:
			var d := wheel_dist(i, int(wi))
			if d >= 3:
				continue
			if d < best:
				best = d
				near = [int(wi)]
			elif d == best:
				near.append(int(wi))
		if near.size() == 1:
			final[near[0]] += int(votes[i])
		elif near.size() == 2:
			@warning_ignore("integer_division")
			var half := int(votes[i]) / 2
			final[near[0]] += half
			final[near[1]] += half
	# Au pouvoir, du plus de voix au moins (à égalité, l'ordre de la roue).
	var ruled := []
	for wi in winners:
		ruled.append([-int(final[int(wi)]), int(wi)])
	ruled.sort()
	var r: Array = []
	for x in ruled:
		r.append(int(x[1]))
	en["ruling"] = r
	en["votes"] = votes
	en["final"] = final
	en["top"] = top
	en["fervor"] = paid
	en["last"] = state.tick
	en["n"] = int(en.get("n", 0)) + 1
	en["next"] = state.tick + int(data()["election_days"])
	en["pick"] = -1
	var fallen := Laws.after_election(state, empire_id)
	for sid in sys_reps:
		var se: Dictionary = state.politics["sys"][sid]
		se["rep"] = _majority(sys_reps[sid], r)
	var names := PackedStringArray()
	for wi in r:
		names.append(label(state, empire_id, int(wi)))
	var line := "%s : %s se réunit. Au pouvoir : %s." % [e.short_name(), String(reg["assembly"]), ", ".join(names)]
	if String(reg["mode"]) == "appoint" and int(r[0]) != top:
		line += " Le peuple avait voté pour %s ; on lui a expliqué qu'il s'était trompé." % label(state, empire_id, top)
	elif names.size() > 1:
		line += " Les coalitions se forment au bar, les discours à la tribune."
	else:
		line += " Les banderoles sont prêtes, les hymnes aussi."
	if paid > 0:
		line += " (-%d ferveur)" % paid
	if fallen != "":
		line += " Lois abrogées avec leurs courants : %s." % fallen
	out.append(state.add_chronicle(line, Espionage.private_to(state, [empire_id], FactionTraits.capital_system(state, empire_id))))
	state.politics["elected"] = {"empire": empire_id, "tick": state.tick}
	return out


## Courant majoritaire des représentants d'un système (à égalité, celui au pouvoir, puis la roue).
static func _majority(reps: Array, ruling_: Array) -> int:
	var best := -1
	var bv := 0
	for i in N:
		var v := int(reps[i])
		if v <= 0:
			continue
		if v > bv or (v == bv and ruling_.has(i) and not ruling_.has(best)):
			best = i
			bv = v
	return best


# --- Représentation et stabilité ---------------------------------------------------------------

## Source de stabilité de la représentation : [libellé, valeur] ou [] (voir Stability.parts).
static func stability_part(state: GameState, sid: int, owner: int) -> Array:
	if not applies(state, owner):
		return []
	var en := sys_entry(state, sid)
	if en.is_empty() or int(en.get("o", -1)) != owner or int(en.get("rep", -1)) < 0:
		return []
	var rp: Dictionary = data()["representation"]
	var rep := int(en["rep"])
	if in_power(state, owner, rep):
		return ["Représenté au pouvoir (%s)" % short(state, owner, rep), int(rp["in_power"])]
	var v := int(rp["out"])
	if regime_id(state, owner) == "horde":
		var city := FactionTraits.city_fleet(state, owner)
		if city != null and city.system_id == sid and not city.is_moving():
			return ["Le clan %s grogne, mais la flotte-ville est là" % short(state, owner, rep), 0]
		v = int(rp.get("horde_out", v))
	return ["Non représenté (%s dans l'opposition)" % short(state, owner, rep), v]


# --- Soutien officiel (ordre) ------------------------------------------------------------------

static func check_support(state: GameState, empire_id: int, i: int) -> String:
	if not applies(state, empire_id):
		return "votre peuple n'a pas de vie politique"
	if i < -1 or i >= N:
		return "courant inconnu"
	if mode(state, empire_id) == "continuous":
		return "le consensus des nœuds ne se commande pas"
	return ""


static func support(state: GameState, empire_id: int, i: int) -> void:
	_emp_w(state, empire_id)["pick"] = i


static func pick(state: GameState, empire_id: int) -> int:
	return int(emp(state, empire_id).get("pick", -1))


# --- Mise en place, sauvegarde -----------------------------------------------------------------

## Réglages de Nouvelle partie (data "modes") ; "active" par défaut à l'écran, "aucune" sans option.
static func modes() -> Array:
	return data()["modes"]


static func mode_def(id: String) -> Dictionary:
	for m: Dictionary in modes():
		if String(m["id"]) == id:
			return m
	return {}


static func default_mode() -> String:
	return String(data().get("default_mode", "active"))


## Option de partie "politics" : "active" ou "aucune" (défaut, pour les tests et les bancs).
static func setup(state: GameState, option: String) -> void:
	state.politics = {"emp": {}, "sys": {}}
	state.politics_on = option == "active"
	if not state.politics_on:
		return
	for e in state.empires:
		if applies(state, e.id):
			_emp_w(state, e.id)
	Laws.setup(state)


static func to_dict(state: GameState) -> Dictionary:
	var emps := []
	for k in _sorted_keys(state.politics["emp"]):
		emps.append([k, state.politics["emp"][k]])
	var syss := []
	for k in _sorted_keys(state.politics["sys"]):
		syss.append([k, state.politics["sys"][k]])
	return {"on": state.politics_on, "emp": emps, "sys": syss}


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.politics = {"emp": {}, "sys": {}}
	state.politics_on = bool(d.get("on", false))
	for pair in d.get("emp", []):
		var en: Dictionary = (pair[1] as Dictionary).duplicate(true)
		for k in ["next", "last", "n", "pick", "top", "fervor"]:
			if en.has(k):
				en[k] = int(en[k])
		for k in ["ruling", "votes", "final"]:
			en[k] = _ints(en.get(k, []))
		for k in ["xp", "cm"]:
			if en.has(k):
				en[k] = _ints(en[k])
		if en.has("laws"):
			var ls := []
			for x in en["laws"]:
				ls.append(String(x))
			en["laws"] = ls
		state.politics["emp"][int(pair[0])] = en
	for pair in d.get("sys", []):
		var en: Dictionary = (pair[1] as Dictionary).duplicate(true)
		for k in ["o", "rep", "pop"]:
			en[k] = int(en.get(k, -1 if k != "pop" else 0))
		en["op"] = _ints(en.get("op", []))
		en["reps"] = _ints(en.get("reps", []))
		state.politics["sys"][int(pair[0])] = en


## Entrées de systèmes qui ont changé de mains ou n'ont plus de propriétaire.
static func prune(state: GameState) -> void:
	var drop := []
	for k in state.politics["sys"]:
		var o := state.system_owner(int(k))
		if o < 0 or GameState.is_npc(o) or int(state.politics["sys"][k].get("o", -1)) != o:
			drop.append(k)
	for k in drop:
		state.politics["sys"].erase(k)


# --- Outils ------------------------------------------------------------------------------------

static func _ints(a: Array) -> Array:
	var out := []
	for x in a:
		out.append(int(x))
	return out


static func _sorted_keys(d: Dictionary) -> Array:
	var ks := []
	for k in d:
		ks.append(int(k))
	ks.sort()
	return ks


static func _argmax(a: Array) -> int:
	var best := 0
	for i in a.size():
		if int(a[i]) > int(a[best]):
			best = i
	return best


## Les n plus grands (à égalité, l'ordre de la roue), du plus grand au plus petit.
static func _top(a: Array, n: int) -> Array:
	var l := []
	for i in a.size():
		l.append([-int(a[i]), i])
	l.sort()
	var out := []
	for k in mini(n, l.size()):
		out.append(int(l[k][1]))
	return out


## Ramène la somme à 1000 (l'écart va au courant donné), sans valeur négative.
static func _normalize(op: Array, into: int) -> void:
	var s := 0
	for i in op.size():
		op[i] = maxi(0, int(op[i]))
		s += int(op[i])
	op[into] = maxi(0, int(op[into]) + TOTAL - s)
