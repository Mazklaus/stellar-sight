class_name Amphictyony
extends RefCounted
## La Grande Amphictyonie Galactique, dite l'Amphictyonie (étude « Conseil galactique », 2026-11-14).
## Règles : data/amphictyony.json. Lot 1 : fondation (3 fondateurs quand un empire a rencontré 70 % des
## autres, pas avant l'an 8), adhésion et départ, voix (population × stabilité, économie, technologies,
## flotte), file de propositions classée par le soutien, séance tous les 720 jours (vote de 180 jours,
## votes modifiables), présidence tournante, voix achetées, résolutions en familles de deux voies
## (catalogue ouvert, niveaux dans l'ordre, abrogation), Nomos (loi galactique), hors-la-loi, charte des
## atrocités, sanctions en 3 degrés, bannissement, marché commun réservé aux membres.
## Lot 2 (AmphInst) : troisième niveau des voies, Haute Voûte, Arbitre des étoiles, faveurs, observateurs,
## sessions extraordinaires et coalitions, aide d'urgence, grands travaux, ambassadeurs.
## Lot 3 (AmphPower) : pleins pouvoirs (Impérateur), victoire diplomatique (Chancelier des étoiles),
## ponts avec la politique et la religion, talents d'assemblée des peuples.
##
## state.amph (clés d'empire en texte, pour la sauvegarde) :
## - "founded" : jour de fondation (-1 avant) ; "offer" : {"since", "yes": [empires]} (offre de fonder) ;
## - "members" : [empires], "joined" : {empire: jour}, "banned" : {empire: jour de fin} ;
## - "voix" : {empire: voix de base sur 1000} (recalculées chaque mois) ;
## - "fam" : {famille: niveau signé} (+n = voie A au niveau n, -n = voie B) ;
## - "queue" : [{"id", "by", "kind" ("step", "sanction", "expel"), "fam", "from", "to", "target",
##   "sanc", "day", "paid", "sup": [empires]}] ;
## - "session" : {"prop", "start", "end", "pres", "votes": {empire: 1 ou -1}, "buy": {empire: tranches}}
##   ({} hors séance) ; "next" : jour de la prochaine séance ; "presided" : [empires] ;
## - "mods" : {empire: [[pct, jour de fin]]} (bonus ou malus de proposant) ;
## - "outlaw" : {empire: {"until", "why", "n"}} ; "atroc" : {empire: nombre} ; "casus" : {empire: fin}
##   (droit de guerre de tous les membres contre lui) ; "sanc" : {empire: {type: degré}} ;
## - "hist" : dernières séances [{"prop", "pass", "pour", "contre", "day", "pres", "votes"}] ; "next_id" ; "gfaith".
##
## Sans l'option de partie « amphictyony » (tests, bancs, vieilles sauvegardes), rien n'existe.

const KEYS := ["offer", "joined", "banned", "voix", "fam", "session", "mods", "outlaw", "atroc", "casus", "sanc"]
const LISTS := ["members", "queue", "presided", "hist"]
## Clés du lot 2 (voir AmphInst), relues telles quelles (nombres remis en entiers).
const KEYS2 := ["council", "arbiter", "favors", "special", "coal", "aid", "work", "den", "cd"]
const LISTS2 := ["observers", "trig", "done"]
## Clés du lot 3 (voir AmphPower).
const KEYS3 := ["imp", "chan", "dip", "share", "sov"]
const HIST_MAX := 12


static func data() -> Dictionary:
	return GameData.amphictyony()


static func enabled(state: GameState) -> bool:
	return state.amph_on


static func name_long() -> String:
	return String(data()["name"])


static func name_short() -> String:
	return String(data()["short"])


# --- Mise en place et sauvegarde -----------------------------------------------------------------

static func setup(state: GameState, mode: String) -> void:
	state.amph_on = mode == "active"
	state.amph = _blank()


static func _blank() -> Dictionary:
	var d := {"founded": -1, "next": -1, "next_id": 1, "gfaith": ""}
	for k in KEYS:
		d[k] = {}
	for k in LISTS:
		d[k] = []
	for k in KEYS2:
		d[k] = {}
	for k in LISTS2:
		d[k] = []
	for k in KEYS3:
		d[k] = {}
	return d


static func to_dict(state: GameState) -> Dictionary:
	var d: Dictionary = state.amph.duplicate(true)
	d["on"] = state.amph_on
	return d


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.amph_on = bool(d.get("on", false))
	state.amph = _blank()
	if d.is_empty():
		return
	for k in ["founded", "next", "next_id"]:
		state.amph[k] = int(d.get(k, state.amph[k]))
	state.amph["gfaith"] = String(d.get("gfaith", ""))
	for k in KEYS:
		state.amph[k] = (d.get(k, {}) as Dictionary).duplicate(true)
	for k in LISTS:
		state.amph[k] = (d.get(k, []) as Array).duplicate(true)
	for k in KEYS2:
		state.amph[k] = _intify((d.get(k, {}) as Dictionary).duplicate(true))
	for k in LISTS2:
		state.amph[k] = _intify((d.get(k, []) as Array).duplicate(true))
	for k in KEYS3:
		state.amph[k] = _intify((d.get(k, {}) as Dictionary).duplicate(true))
	var a: Dictionary = state.amph
	a["members"] = _ints(a["members"])
	a["presided"] = _ints(a["presided"])
	for k in ["joined", "banned", "voix", "fam", "atroc", "casus"]:
		for x in a[k]:
			a[k][x] = int(a[k][x])
	if not (a["offer"] as Dictionary).is_empty():
		a["offer"]["since"] = int(a["offer"].get("since", 0))
		a["offer"]["yes"] = _ints(a["offer"].get("yes", []))
	for p: Dictionary in a["queue"]:
		_fix_prop(p)
	var s: Dictionary = a["session"]
	if not s.is_empty():
		for k in ["start", "end", "pres"]:
			s[k] = int(s[k])
		_fix_prop(s["prop"])
		for x in s["votes"]:
			s["votes"][x] = int(s["votes"][x])
		for x in s["buy"]:
			s["buy"][x] = int(s["buy"][x])
		for k in ["calls", "bribe"]:
			if s.has(k):
				s[k] = _intify(s[k])
	for x in a["mods"]:
		var l: Array = []
		for m in a["mods"][x]:
			l.append([int(m[0]), int(m[1])])
		a["mods"][x] = l
	for x in a["outlaw"]:
		var o: Dictionary = a["outlaw"][x]
		o["until"] = int(o["until"])
		o["n"] = int(o.get("n", 1))
		o["why"] = String(o.get("why", ""))
	for x in a["sanc"]:
		for t in a["sanc"][x]:
			a["sanc"][x][t] = int(a["sanc"][x][t])
	for h: Dictionary in a["hist"]:
		_fix_prop(h["prop"])
		for k in ["pour", "contre", "day"]:
			h[k] = int(h[k])
		h["pass"] = bool(h["pass"])
		h["pres"] = int(h.get("pres", -1))
		var hv := {}
		for x in h.get("votes", {}):
			hv[str(x)] = int(h["votes"][x])
		h["votes"] = hv


static func _fix_prop(p: Dictionary) -> void:
	for k in ["id", "by", "from", "to", "target", "day", "paid"]:
		p[k] = int(p.get(k, -1 if k == "target" else 0))
	p["kind"] = String(p.get("kind", "step"))
	p["fam"] = String(p.get("fam", ""))
	p["sanc"] = String(p.get("sanc", ""))
	p["sup"] = _ints(p.get("sup", []))
	if p.has("frozen"):
		p["frozen"] = int(p["frozen"])


## Nombres relus d'une sauvegarde (flottants JSON) remis en entiers, en profondeur.
static func _intify(v: Variant) -> Variant:
	if v is float:
		return int(v)
	if v is Dictionary:
		for k in (v as Dictionary).keys():
			v[k] = _intify(v[k])
	elif v is Array:
		for i in (v as Array).size():
			v[i] = _intify(v[i])
	return v


static func _ints(l: Array) -> Array:
	var out: Array = []
	for x in l:
		out.append(int(x))
	return out


# --- Lecture ---------------------------------------------------------------------------------------

static func founded(state: GameState) -> bool:
	return state.amph_on and int(state.amph.get("founded", -1)) >= 0


static func members(state: GameState) -> Array[int]:
	var out: Array[int] = []
	if not state.amph_on:
		return out
	for x in state.amph["members"]:
		out.append(int(x))
	return out


static func is_member(state: GameState, eid: int) -> bool:
	return state.amph_on and (state.amph["members"] as Array).has(eid)


## Empire qui peut siéger : vivant, pas une puissance neutre, et pas une ruche sans diplomatie.
static func eligible(state: GameState, eid: int) -> bool:
	var e := state.get_empire(eid)
	return e != null and not e.eliminated and not e.is_npc() and not Diplomacy.no_treaties(state, eid)


static func _living(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for e in state.empires:
		if not e.eliminated and not e.is_npc():
			out.append(e.id)
	return out


## Part (en %) des autres empires vivants que eid a rencontrés.
static func met_pct(state: GameState, eid: int) -> int:
	var e := state.get_empire(eid)
	if e == null:
		return 0
	var n := 0
	var met := 0
	for o in _living(state):
		if o == eid:
			continue
		n += 1
		if e.contacts.has(o):
			met += 1
	@warning_ignore("integer_division")
	return 100 if n == 0 else met * 100 / n


static func banned_until(state: GameState, eid: int) -> int:
	return int((state.amph["banned"] as Dictionary).get(str(eid), 0))


static func family_defs() -> Array:
	return data()["families"]


static func family_def(fid: String) -> Dictionary:
	for f: Dictionary in family_defs():
		if String(f["id"]) == fid:
			return f
	return {}


## La famille a-t-elle un sens dans cette partie (religions, créatures ou pirates en jeu) ?
static func family_available(state: GameState, fid: String) -> bool:
	var f := family_def(fid)
	if f.is_empty():
		return false
	match String(f.get("requires", "")):
		"faiths":
			return state.faith_on
		"perils":
			return Fauna.active(state) or state.pirate_density != "aucun"
		"vassals":
			return state.vassals_on
	return true


static func fam_value(state: GameState, fid: String) -> int:
	return int((state.amph["fam"] as Dictionary).get(fid, 0))


static func max_level(fid: String, way: String) -> int:
	return (family_def(fid).get(way, {}).get("levels", []) as Array).size()


static func way_of(v: int) -> String:
	return "a" if v > 0 else "b"


## Nom du niveau v (signé) d'une famille ("" pour 0).
static func level_name(fid: String, v: int) -> String:
	if v == 0:
		return ""
	var lv: Array = family_def(fid).get(way_of(v), {}).get("levels", [])
	var i := absi(v) - 1
	return String(lv[i]["name"]) if i < lv.size() else ""


## Première lettre en capitale (sans toucher au reste, contrairement à String.capitalize).
static func cap(t: String) -> String:
	return t.substr(0, 1).to_upper() + t.substr(1)


static func _roman(n: int) -> String:
	return ["", "I", "II", "III", "IV", "V"][clampi(n, 0, 5)]


## Résolutions en vigueur : [{"fam", "v", "name", "way"}] dans l'ordre du catalogue.
static func active(state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not founded(state):
		return out
	for f: Dictionary in family_defs():
		var v := fam_value(state, String(f["id"]))
		if v != 0:
			out.append({"fam": String(f["id"]), "v": v, "name": level_name(String(f["id"]), v), "way": String(f[way_of(v)]["label"])})
	return out


## Niveaux en vigueur d'une famille (du premier au niveau atteint).
static func _levels_in_force(state: GameState, fid: String) -> Array:
	var v := fam_value(state, fid)
	if v == 0:
		return []
	var lv: Array = family_def(fid).get(way_of(v), {}).get("levels", [])
	return lv.slice(0, mini(absi(v), lv.size()))


## Interdits du Nomos en vigueur (la charte des atrocités tient dès la fondation).
static func bans(state: GameState) -> Array[String]:
	var out: Array[String] = []
	if not founded(state):
		return out
	out.append("exterminate")
	for f: Dictionary in family_defs():
		var fid := String(f["id"])
		var v := fam_value(state, fid)
		if v == 0 or not family_available(state, fid):
			continue
		for b in f[way_of(v)].get("bans", []):
			if not out.has(String(b)):
				out.append(String(b))
		for l: Dictionary in _levels_in_force(state, fid):
			for b in l.get("bans", []):
				if not out.has(String(b)):
					out.append(String(b))
	return out


static func banned(state: GameState, kind: String) -> bool:
	return bans(state).has(kind)


## Somme d'un champ numérique des niveaux en vigueur (op_cost_pct, discovery, bounty, faith_voix_pct).
static func level_sum(state: GameState, key: String) -> int:
	var n := 0
	if not founded(state):
		return n
	for f: Dictionary in family_defs():
		var fid := String(f["id"])
		if not family_available(state, fid):
			continue
		for l: Dictionary in _levels_in_force(state, fid):
			n += int(l.get(key, 0))
	return n


static func _level_flag(state: GameState, key: String) -> bool:
	if not founded(state):
		return false
	for f: Dictionary in family_defs():
		for l: Dictionary in _levels_in_force(state, String(f["id"])):
			if bool(l.get(key, false)):
				return true
	return false


static func outlaw(state: GameState, eid: int) -> bool:
	return state.amph_on and int((state.amph["outlaw"] as Dictionary).get(str(eid), {}).get("until", 0)) > state.tick


static func outlaws(state: GameState) -> Array[int]:
	var out: Array[int] = []
	if not state.amph_on:
		return out
	for e in state.empires:
		if outlaw(state, e.id) and not e.eliminated:
			out.append(e.id)
	return out


## Passible de sanctions : hors-la-loi, ou dénoncé par un conseiller de la Haute Voûte.
static func sanctionable(state: GameState, eid: int) -> bool:
	return outlaw(state, eid) or AmphInst.denounced(state, eid)


static func sanctionables(state: GameState) -> Array[int]:
	var out: Array[int] = []
	if not state.amph_on:
		return out
	for e in state.empires:
		if not e.eliminated and not e.is_npc() and sanctionable(state, e.id):
			out.append(e.id)
	return out


static func sanction_degree(state: GameState, target: int, sanc: String) -> int:
	return int((state.amph["sanc"] as Dictionary).get(str(target), {}).get(sanc, 0))


static func sanction_defs() -> Array:
	return data()["sanctions"]


static func sanction_def(sid: String) -> Dictionary:
	for s: Dictionary in sanction_defs():
		if String(s["id"]) == sid:
			return s
	return {}


# --- Voix ------------------------------------------------------------------------------------------

## Voix de base (sur 1000) d'un membre, recalculées chaque mois.
static func base_voix(state: GameState, eid: int) -> int:
	return int((state.amph["voix"] as Dictionary).get(str(eid), 0))


## Bonus en points de % : proposant récompensé ou désavoué, fidèles de la foi galactique.
static func voix_pct(state: GameState, eid: int) -> int:
	var pct := 0
	for m in (state.amph["mods"] as Dictionary).get(str(eid), []):
		if int(m[1]) > state.tick:
			pct += int(m[0])
	if galactic_follower(state, eid):
		pct += level_sum(state, "faith_voix_pct")
	return pct + AmphInst.voix_pct(state, eid) + AmphPower.voix_pct(state, eid) + Vassals.voix_pct(state, eid)


## Voix effectives d'un membre (0 pour un non-membre).
@warning_ignore("integer_division")
static func weight(state: GameState, eid: int) -> int:
	if not is_member(state, eid):
		return 0
	return maxi(1, base_voix(state, eid) * maxi(0, 100 + voix_pct(state, eid)) / 100)


static func total_weight(state: GameState) -> int:
	var t := 0
	for m in members(state):
		t += weight(state, m)
	return t


## Parts brutes d'un empire : population × stabilité, économie, technologies, flotte.
static func components(state: GameState, eid: int) -> Dictionary:
	var e := state.get_empire(eid)
	if e == null:
		return {"pop": 0, "eco": 0, "tech": 0, "fleet": 0}
	var pop := 0
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		if c.owner == eid and c.is_established():
			pop += c.population
	@warning_ignore("integer_division")
	pop = pop * maxi(10, Stability.empire_value(state, eid)) / 100
	var g: Dictionary = Economy.empire_income(state, eid)["gross"]
	var eco := maxi(0, int(g.get("energy", 0))) + maxi(0, int(g.get("materials", 0))) + maxi(0, int(g.get("knowledge", 0)))
	var fleet := 0
	for f in Fleets.empire_fleets(state, eid):
		fleet += Combat.fleet_power(f)
	fleet *= AmphPower.fleet_x(state, eid)
	return {"pop": pop, "eco": eco, "tech": e.techs.size(), "fleet": fleet}


static func recompute_voix(state: GameState) -> void:
	var ms := members(state)
	var comps := {}
	var sums := {"pop": 0, "eco": 0, "tech": 0, "fleet": 0}
	for m in ms:
		var c := components(state, m)
		comps[m] = c
		for k in sums:
			sums[k] = int(sums[k]) + int(c[k])
	var vd: Dictionary = data()["voix"]
	var total := int(vd["total"])
	var w: Dictionary = vd["weights"]
	# Une part que personne n'a (aucune flotte, par exemple) redistribue son poids aux autres.
	var wsum := 0
	for k in w:
		if int(sums[k]) > 0:
			wsum += int(w[k])
	var out := {}
	for m in ms:
		var v := 0
		for k in w:
			if int(sums[k]) > 0:
				@warning_ignore("integer_division")
				v += int(w[k]) * int(comps[m][k]) * total / (wsum * int(sums[k]))
		out[str(m)] = maxi(1, v)
	state.amph["voix"] = out


# --- Fondation, adhésion, départ ---------------------------------------------------------------

static func offer_open(state: GameState) -> bool:
	return state.amph_on and not founded(state) and not (state.amph["offer"] as Dictionary).is_empty()


static func check_found(state: GameState, eid: int) -> String:
	if not state.amph_on:
		return "pas d'Amphictyonie dans cette partie"
	if founded(state):
		return "l'Amphictyonie est déjà fondée"
	if not offer_open(state):
		return "aucune offre de fondation en cours"
	if not eligible(state, eid):
		return "votre peuple ne siège pas dans les assemblées"
	if (state.amph["offer"]["yes"] as Array).has(eid):
		return "vous avez déjà signé"
	return ""


static func found_sign(state: GameState, eid: int) -> void:
	var yes: Array = state.amph["offer"]["yes"]
	yes.append(eid)
	var e := state.get_empire(eid)
	state.add_chronicle("%s signe l'acte de fondation de %s (%d signature%s sur %d)." % [e.display_name(), name_long(), yes.size(), "s" if yes.size() > 1 else "", int(data()["found"]["founders"])],
			Espionage.public_to(state, [eid]))
	if yes.size() >= int(data()["found"]["founders"]):
		_found(state)


static func _found(state: GameState) -> void:
	var a: Dictionary = state.amph
	var yes: Array = a["offer"]["yes"]
	a["founded"] = state.tick
	a["offer"] = {}
	a["members"] = []
	for x in yes:
		_add_member(state, int(x))
	a["next"] = state.tick + int(data()["first_session_days"])
	recompute_voix(state)
	state.relic_rev += 1
	var names := PackedStringArray()
	for x in yes:
		names.append(state.get_empire(int(x)).display_name())
	state.add_chronicle("Fondation de %s ! %s en signent la charte : une loi commune, une tribune, et pour commencer l'interdiction des atrocités. Les autres empires peuvent adhérer ; la première séance s'ouvrira dans un an." % [name_long(), ", ".join(names)])


static func _add_member(state: GameState, eid: int) -> void:
	var ms: Array = state.amph["members"]
	if not ms.has(eid):
		ms.append(eid)
		ms.sort()
	state.amph["joined"][str(eid)] = state.tick


static func join_cost(_state: GameState, _eid: int) -> Dictionary:
	return (data()["join_cost"] as Dictionary).duplicate()


static func check_join(state: GameState, eid: int) -> String:
	if not founded(state):
		return "l'Amphictyonie n'est pas encore fondée"
	if not eligible(state, eid):
		return "votre peuple ne siège pas dans les assemblées"
	if is_member(state, eid):
		return "vous siégez déjà"
	if banned_until(state, eid) > state.tick:
		return "retour interdit jusqu'au %s" % GameCalendar.date_string(banned_until(state, eid))
	var e := state.get_empire(eid)
	var met := false
	for m in members(state):
		if e.contacts.has(m):
			met = true
			break
	if not met:
		return "vous n'avez rencontré aucun amphictyon"
	if not Economy.can_afford(e, join_cost(state, eid)):
		return "il faut %s" % GameData.format_amounts(join_cost(state, eid))
	return ""


static func join(state: GameState, eid: int) -> void:
	Economy.pay(state.get_empire(eid), join_cost(state, eid))
	_add_member(state, eid)
	recompute_voix(state)
	state.relic_rev += 1
	state.add_chronicle("%s adhère à %s et prend place sur les gradins." % [state.get_empire(eid).display_name(), name_short()], Espionage.public_to(state, members(state)))


static func leave_cost(state: GameState, eid: int) -> Dictionary:
	var ld: Dictionary = data()["leave"]
	return {"influence": int(ld["influence"]) + int(ld["per_system"]) * Stability.systems_of(state, eid).size()}


static func check_leave(state: GameState, eid: int) -> String:
	if not is_member(state, eid):
		return "vous ne siégez pas"
	var e := state.get_empire(eid)
	if not Economy.can_afford(e, leave_cost(state, eid)):
		return "partir coûte %s" % GameData.format_amounts(leave_cost(state, eid))
	return ""


static func leave(state: GameState, eid: int) -> void:
	Economy.pay(state.get_empire(eid), leave_cost(state, eid))
	_remove_member(state, eid, int(data()["leave"]["ban_days"]))
	state.add_chronicle("%s claque la porte de %s. Retour interdit pendant 10 ans." % [state.get_empire(eid).display_name(), name_short()], Espionage.public_to(state, [eid]))


static func _remove_member(state: GameState, eid: int, ban_days: int) -> void:
	var a: Dictionary = state.amph
	(a["members"] as Array).erase(eid)
	a["banned"][str(eid)] = state.tick + ban_days
	(a["voix"] as Dictionary).erase(str(eid))
	var kept: Array = []
	for p: Dictionary in a["queue"]:
		if int(p["by"]) != eid:
			(p["sup"] as Array).erase(eid)
			kept.append(p)
	a["queue"] = kept
	var s: Dictionary = a["session"]
	if not s.is_empty():
		(s["votes"] as Dictionary).erase(str(eid))
	AmphInst.on_remove(state, eid)
	AmphPower.on_remove(state, eid)
	state.relic_rev += 1


# --- Propositions ----------------------------------------------------------------------------------

## Pas suivant d'une famille dans une direction (+1 voie A, -1 voie B) : niveau visé, ou 0 si impossible.
## Un pas vers la voie opposée à celle en vigueur abroge son dernier niveau.
static func step_to(state: GameState, fid: String, dir: int) -> Array:
	var v := fam_value(state, fid)
	var to := v + signi(dir)
	if v != 0 and signi(dir) != signi(v):
		return [true, to]
	if absi(to) > max_level(fid, way_of(to)):
		return [false, v]
	return [true, to]


static func is_repeal(from: int, to: int) -> bool:
	return absi(to) < absi(from)


static func step_cost(from: int, to: int) -> Dictionary:
	if is_repeal(from, to):
		return {"influence": int(data()["repeal_cost"])}
	var cl: Array = data()["cost_by_level"]
	return {"influence": int(cl[clampi(absi(to) - 1, 0, cl.size() - 1)])}


## eid : le proposant (talents de peuple : Tribune, Anathème), -1 pour le prix de base.
static func prop_cost(state: GameState, kind: String, fid: String, dir: int, eid := -1) -> Dictionary:
	var base := {}
	match kind:
		"sanction":
			base = {"influence": int(data()["sanction_cost"])}
		"expel":
			base = {"influence": int(data()["expel_cost"])}
		_:
			if AmphInst.INST_KINDS.has(kind):
				base = AmphInst.prop_cost(kind)
			else:
				var st := step_to(state, fid, dir)
				base = step_cost(fam_value(state, fid), int(st[1]))
	return AmphPower.cost_for(state, eid, kind, fid, base)


static func proposals_count(state: GameState, eid: int) -> int:
	var n := 0
	for p: Dictionary in state.amph["queue"]:
		if int(p["by"]) == eid:
			n += 1
	var s: Dictionary = state.amph["session"]
	if not s.is_empty() and int(s["prop"]["by"]) == eid:
		n += 1
	return n


static func proposal_of(state: GameState, eid: int) -> Dictionary:
	for p: Dictionary in state.amph["queue"]:
		if int(p["by"]) == eid:
			return p
	var s: Dictionary = state.amph["session"]
	if not s.is_empty() and int(s["prop"]["by"]) == eid:
		return s["prop"]
	return {}


static func check_propose(state: GameState, eid: int, kind: String, fid: String, dir: int, target: int, sanc: String) -> String:
	if not founded(state):
		return "l'Amphictyonie n'est pas fondée"
	if not is_member(state, eid):
		return "seuls les amphictyons proposent"
	if proposals_count(state, eid) >= AmphPower.max_props(state, eid):
		return "vous avez déjà une proposition en cours" if AmphPower.max_props(state, eid) <= 1 else "vous avez déjà %d propositions en cours" % AmphPower.max_props(state, eid)
	match kind:
		"step":
			if family_def(fid).is_empty() or not family_available(state, fid):
				return "famille inconnue"
			if dir != 1 and dir != -1:
				return "direction inconnue"
			var st := step_to(state, fid, dir)
			if not bool(st[0]):
				return "déjà au plus haut niveau"
			var pending: Array = (state.amph["queue"] as Array).duplicate()
			if in_session(state):
				pending.append(session(state)["prop"])
			for p: Dictionary in pending:
				if String(p["kind"]) == "step" and String(p["fam"]) == fid and int(p["to"]) == int(st[1]):
					return "la même proposition attend déjà"
		"sanction":
			if sanction_def(sanc).is_empty():
				return "sanction inconnue"
			if not sanctionable(state, target):
				return "seul un hors-la-loi ou un empire dénoncé peut être sanctionné"
			if target == eid:
				return "on ne se sanctionne pas soi-même"
			if AmphPower.immune(state, target):
				return "les sanctions glissent sur la ruche (Hors du concert)"
			if sanction_degree(state, target, sanc) >= (sanction_def(sanc)["degrees"] as Array).size():
				return "déjà au degré le plus dur"
		"expel":
			if not is_member(state, target) or not outlaw(state, target):
				return "seul un amphictyon hors-la-loi peut être banni"
			if target == eid:
				return "partez plutôt"
		_:
			var why := AmphInst.check_prop(state, eid, kind, fid, dir, target)
			if why != "":
				return why
	if not Economy.can_afford(state.get_empire(eid), prop_cost(state, kind, fid, dir, eid)):
		return "il faut %s" % GameData.format_amounts(prop_cost(state, kind, fid, dir, eid))
	return ""


static func propose(state: GameState, eid: int, kind: String, fid: String, dir: int, target: int, sanc: String) -> void:
	var cost := prop_cost(state, kind, fid, dir, eid)
	Economy.pay(state.get_empire(eid), cost)
	var from := fam_value(state, fid) if kind == "step" else 0
	var to := int(step_to(state, fid, dir)[1]) if kind == "step" else 0
	var p := {"id": int(state.amph["next_id"]), "by": eid, "kind": kind, "fam": fid if kind == "step" else "", "from": from, "to": to,
			"target": target if kind != "step" else -1, "sanc": sanc if kind == "sanction" else "", "day": state.tick,
			"paid": int(cost.get("influence", 0)), "sup": [eid]}
	if AmphInst.INST_KINDS.has(kind):
		p.merge(AmphInst.make_fields(state, kind, fid, dir, target), true)
	state.amph["next_id"] = int(state.amph["next_id"]) + 1
	(state.amph["queue"] as Array).append(p)
	state.add_chronicle("%s dépose une proposition devant %s : %s." % [state.get_empire(eid).display_name(), name_short(), prop_label(state, p)], Espionage.public_to(state, members(state)))


## Libellé d'une proposition (« Routes franches I », « abroger Murs de douane », « Sanctions économiques
## (2e degré) contre … », « bannir … »).
static func prop_label(state: GameState, p: Dictionary) -> String:
	match String(p["kind"]):
		"step":
			var from := int(p["from"])
			var to := int(p["to"])
			if is_repeal(from, to):
				return "abroger %s (%s)" % [level_name(String(p["fam"]), from), String(family_def(String(p["fam"]))["label"])]
			var way := String(family_def(String(p["fam"]))[way_of(to)]["label"])
			var ln := level_name(String(p["fam"]), to)
			if ln == way:
				return "%s %s" % [ln, _roman(absi(to))]
			return "%s (%s %s)" % [ln, way, _roman(absi(to))]
		"sanction":
			var t := state.get_empire(int(p["target"]))
			var deg := sanction_degree(state, int(p["target"]), String(p["sanc"])) + 1
			return "%s (%d%s degré) contre %s" % [String(sanction_def(String(p["sanc"])).get("label", "")), deg, "er" if deg == 1 else "e", t.display_name() if t != null else "?"]
		"expel":
			var t2 := state.get_empire(int(p["target"]))
			return "bannir %s de %s" % [t2.display_name() if t2 != null else "?", name_short()]
	return AmphInst.prop_label(state, p)


## Texte des effets d'une proposition (infobulle).
static func prop_text(state: GameState, p: Dictionary) -> String:
	match String(p["kind"]):
		"step":
			var f := family_def(String(p["fam"]))
			var to := int(p["to"])
			if is_repeal(int(p["from"]), to):
				return "Retire le dernier niveau en vigueur de la famille %s." % String(f["label"])
			return String(f[way_of(to)].get("text", ""))
		"sanction":
			return String(sanction_def(String(p["sanc"])).get("text", ""))
		"expel":
			return "L'empire hors-la-loi perd son siège et ne pourra pas revenir avant 10 ans."
	return AmphInst.prop_text(state, p)


static func check_support(state: GameState, eid: int, pid: int) -> String:
	if not is_member(state, eid):
		return "seuls les amphictyons soutiennent"
	for p: Dictionary in state.amph["queue"]:
		if int(p["id"]) == pid:
			if int(p["by"]) == eid:
				return "c'est votre proposition"
			return ""
	return "proposition inconnue"


## Soutenir une proposition de la file (ou retirer son soutien).
static func support(state: GameState, eid: int, pid: int) -> void:
	for p: Dictionary in state.amph["queue"]:
		if int(p["id"]) == pid:
			var sup: Array = p["sup"]
			if sup.has(eid):
				sup.erase(eid)
			else:
				sup.append(eid)
				sup.sort()
			return


static func support_weight(state: GameState, p: Dictionary) -> int:
	var n := 0
	for x in p["sup"]:
		n += weight(state, int(x))
	return n


## File triée par soutien (puis la plus ancienne d'abord).
static func sorted_queue(state: GameState) -> Array:
	var q: Array = (state.amph["queue"] as Array).duplicate()
	var w := {}
	for p: Dictionary in q:
		w[int(p["id"])] = support_weight(state, p)
	q.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if int(w[int(x["id"])]) != int(w[int(y["id"])]):
			return int(w[int(x["id"])]) > int(w[int(y["id"])])
		return int(x["id"]) < int(y["id"]))
	return q


static func check_withdraw(state: GameState, eid: int) -> String:
	for p: Dictionary in state.amph["queue"]:
		if int(p["by"]) == eid:
			return ""
	return "aucune proposition à retirer de la file"


static func withdraw(state: GameState, eid: int) -> void:
	var kept: Array = []
	for p: Dictionary in state.amph["queue"]:
		if int(p["by"]) != eid:
			kept.append(p)
	state.amph["queue"] = kept


## La proposition a-t-elle encore un sens aujourd'hui ?
static func still_valid(state: GameState, p: Dictionary) -> bool:
	if not is_member(state, int(p["by"])):
		return false
	match String(p["kind"]):
		"step":
			return family_available(state, String(p["fam"])) and fam_value(state, String(p["fam"])) == int(p["from"])
		"sanction":
			return sanctionable(state, int(p["target"])) and sanction_degree(state, int(p["target"]), String(p["sanc"])) < (sanction_def(String(p["sanc"]))["degrees"] as Array).size()
		"expel":
			return is_member(state, int(p["target"])) and outlaw(state, int(p["target"]))
	return AmphInst.still_valid(state, p)


# --- Séances ---------------------------------------------------------------------------------------

static func in_session(state: GameState) -> bool:
	return founded(state) and not (state.amph["session"] as Dictionary).is_empty()


static func session(state: GameState) -> Dictionary:
	return state.amph["session"]


static func vote_of(state: GameState, eid: int) -> int:
	if not in_session(state):
		return 0
	return int((session(state)["votes"] as Dictionary).get(str(eid), 0))


static func check_vote(state: GameState, eid: int, v: int) -> String:
	if not in_session(state):
		return "aucune séance en cours"
	if not is_member(state, eid):
		return "seuls les amphictyons votent"
	if v < -1 or v > 1:
		return "vote inconnu"
	return ""


static func vote(state: GameState, eid: int, v: int) -> void:
	var votes: Dictionary = session(state)["votes"]
	if v == 0:
		votes.erase(str(eid))
	else:
		votes[str(eid)] = v


static func bought(state: GameState, eid: int) -> int:
	if not in_session(state):
		return 0
	return int((session(state)["buy"] as Dictionary).get(str(eid), 0))


static func buy_cost(state: GameState, eid: int) -> Dictionary:
	var bd: Dictionary = data()["buy"]
	return AmphPower.buy_cost(state, eid, {"influence": int(bd["base"]) + int(bd["step"]) * bought(state, eid)})


@warning_ignore("integer_division")
static func buy_voix(state: GameState) -> int:
	return maxi(1, total_weight(state) * int(data()["buy"]["voix_pct"]) / 100)


static func check_buy(state: GameState, eid: int) -> String:
	var why := check_vote(state, eid, 1)
	if why != "":
		return why
	if vote_of(state, eid) == 0:
		return "votez d'abord pour ou contre"
	if bought(state, eid) >= int(data()["buy"]["max"]):
		return "plus de voix à vendre pour ce vote"
	if not Economy.can_afford(state.get_empire(eid), buy_cost(state, eid)):
		return "il faut %s" % GameData.format_amounts(buy_cost(state, eid))
	return ""


static func buy(state: GameState, eid: int) -> void:
	var cost := buy_cost(state, eid)
	Economy.pay(state.get_empire(eid), cost)
	var b: Dictionary = session(state)["buy"]
	b[str(eid)] = int(b.get(str(eid), 0)) + 1
	AmphPower.on_buy(state, eid)


## Dépouillement : {"pour", "contre", "abst"} en voix (voix achetées comprises).
static func tally(state: GameState) -> Dictionary:
	var out := {"pour": 0, "contre": 0, "abst": 0}
	if not in_session(state):
		return out
	var s := session(state)
	var bv := buy_voix(state)
	for m in members(state):
		# Vote lié : un sujet vote comme son suzerain.
		var v := Vassals.bound_vote(state, m, s["votes"])
		var w := weight(state, m) + bv * int((s["buy"] as Dictionary).get(str(m), 0))
		if v > 0:
			out["pour"] = int(out["pour"]) + w
		elif v < 0:
			out["contre"] = int(out["contre"]) + w
		else:
			out["abst"] = int(out["abst"]) + weight(state, m)
	# Landsraad : les lignées unies qui votent pareil.
	AmphPower.tally_bonus(state, s["votes"], out)
	# Faveurs appelées : une part des voix du débiteur rejoint le camp du créancier.
	var calls: Dictionary = s.get("calls", {})
	for d in calls:
		var side := int((s["votes"] as Dictionary).get(str(int(calls[d])), 0))
		if side != 0:
			@warning_ignore("integer_division")
			var cw := weight(state, int(d)) * int(data()["institutions"]["favors"]["call_pct"]) / 100
			out["pour" if side > 0 else "contre"] = int(out["pour" if side > 0 else "contre"]) + cw
	# Délégués achetés par des espions : une part des voix de la cible change de camp.
	var bribe: Dictionary = s.get("bribe", {})
	for t in bribe:
		var spy_side := int((s["votes"] as Dictionary).get(str(int(bribe[t])), 0))
		if spy_side == 0 or not is_member(state, int(t)):
			continue
		@warning_ignore("integer_division")
		var bw := weight(state, int(t)) * int(Espionage.op_def("acheter_delegue").get("voix_pct", 25)) / 100
		var t_side := int((s["votes"] as Dictionary).get(str(int(t)), 0))
		var from_key := "pour" if t_side > 0 else ("contre" if t_side < 0 else "abst")
		out[from_key] = maxi(0, int(out[from_key]) - bw)
		out["pour" if spy_side > 0 else "contre"] = int(out["pour" if spy_side > 0 else "contre"]) + bw
	return out


static func president(state: GameState) -> int:
	return int(session(state).get("pres", -1)) if in_session(state) else -1


static func _choose_president(state: GameState) -> int:
	var ms := members(state)
	var done: Array = state.amph["presided"]
	var left: Array[int] = []
	for m in ms:
		if not done.has(m):
			left.append(m)
	if left.is_empty():
		done.clear()
		left = ms
	var best := -1
	for m in left:
		if best < 0 or weight(state, m) > weight(state, best):
			best = m
	if best >= 0:
		done.append(best)
	return best


## force_pid : procédure d'urgence d'un conseiller (cette proposition, tout de suite).
static func _open_session(state: GameState, added: Array[Dictionary], force_pid := -1) -> void:
	var a: Dictionary = state.amph
	var kept: Array = []
	for p: Dictionary in a["queue"]:
		if still_valid(state, p):
			kept.append(p)
	a["queue"] = kept
	# Les propositions gelées par l'Arbitre attendent leur tour.
	var ready: Array = []
	for p: Dictionary in sorted_queue(state):
		if int(p.get("frozen", 0)) <= state.tick or int(p["id"]) == force_pid:
			ready.append(p)
	if ready.is_empty():
		a["next"] = state.tick + 30
		return
	var pres := _choose_president(state)
	var pick: Dictionary = {}
	var free := false
	if force_pid >= 0:
		for p: Dictionary in ready:
			if int(p["id"]) == force_pid:
				pick = p
	if pick.is_empty():
		for p: Dictionary in ready:
			if int(p["by"]) == pres:
				pick = p
		free = not pick.is_empty()
	if pick.is_empty():
		pick = ready[0]
	(a["queue"] as Array).erase(pick)
	if free and int(pick["paid"]) > 0:
		var pe := state.get_empire(pres)
		pe.resources["influence"] = int(pe.resources.get("influence", 0)) + int(pick["paid"])
	a["session"] = {"prop": pick, "start": state.tick, "end": state.tick + int(data()["vote_days"]), "pres": pres,
			"votes": {str(int(pick["by"])): 1}, "buy": {}}
	a["next"] = state.tick + int(data()["session_days"])
	var lines: Array = data()["presidency_lines"]
	var line := String(lines[posmod(hash([state.seed_value, "pres", state.tick]), lines.size())]) % state.get_empire(pres).display_name()
	added.append(state.add_chronicle("Séance de %s : %s Au vote pendant 6 mois : %s, proposé par %s%s." % [name_short(), line, prop_label(state, pick),
			state.get_empire(int(pick["by"])).display_name(), " (le président la met en tête de file, sans frais)" if free else ""], Espionage.public_to(state, members(state))))


## veto_by : conseiller de la Haute Voûte qui oppose son veto (la proposition tombe).
static func _close_session(state: GameState, added: Array[Dictionary], veto_by := -1) -> void:
	var a: Dictionary = state.amph
	var s: Dictionary = a["session"]
	var p: Dictionary = s["prop"]
	var t := tally(state)
	var pour := int(t["pour"])
	var contre := int(t["contre"])
	var pres := int(s["pres"])
	Koinon.on_amph_close(state, s["votes"])
	var passed := pour > contre or (pour == contre and pour > 0 and int((s["votes"] as Dictionary).get(str(pres), 0)) > 0)
	var valid := still_valid(state, p)
	passed = passed and valid and veto_by < 0
	var by := int(p["by"])
	# Faveurs : qui a voté pour une proposition adoptée, son auteur lui en doit une.
	if passed:
		for k in s["votes"]:
			if int(k) != by and int(s["votes"][k]) > 0:
				AmphInst.add_favor(state, int(k), by, 1)
	# Souvenirs : voter pour plaît au proposant, voter contre le froisse.
	for k in s["votes"]:
		var who := int(k)
		if who == by or AmphPower.veiled(state, who):
			continue
		Diplomacy.remember(state, by, who, "amph_backed" if int(s["votes"][k]) > 0 else "amph_opposed")
	# Voix achetées du camp perdant : remboursées à moitié.
	var bd: Dictionary = data()["buy"]
	for k in s["buy"]:
		var who2 := int(k)
		var side := int((s["votes"] as Dictionary).get(k, 0))
		if (side > 0) == passed or side == 0:
			continue
		var n := int(s["buy"][k])
		var spent := 0
		for i in n:
			spent += int(bd["base"]) + int(bd["step"]) * i
		var e2 := state.get_empire(who2)
		if e2 != null:
			@warning_ignore("integer_division")
			e2.resources["influence"] = int(e2.resources.get("influence", 0)) + spent / 2
	if valid and is_member(state, by):
		var pm: Dictionary = data()["proposer_mod"]
		var mods: Array = (a["mods"] as Dictionary).get(str(by), [])
		mods.append([int(pm["pct"]) if passed else -int(pm["pct"]), state.tick + int(pm["days"])])
		a["mods"][str(by)] = mods
	a["session"] = {}
	var hist: Array = a["hist"]
	hist.append({"prop": p, "pass": passed, "pour": pour, "contre": contre, "day": state.tick, "pres": pres, "votes": (s["votes"] as Dictionary).duplicate()})
	while hist.size() > HIST_MAX:
		hist.pop_front()
	var label := prop_label(state, p)
	AmphPower.on_close(state, p, s["votes"], passed)
	if passed:
		_apply(state, p, added)
	var verdict := "adopte" if passed else ("rejette" if valid else "classe sans suite")
	if veto_by >= 0:
		verdict = "rejette, sur le veto de %s," % state.get_empire(veto_by).display_name()
	added.append(state.add_chronicle("%s %s : %s (%d voix pour, %d contre)." % [cap(name_short()), verdict, label, pour, contre],
			Espionage.public_to(state, members(state))))


static func _apply(state: GameState, p: Dictionary, added: Array[Dictionary]) -> void:
	var a: Dictionary = state.amph
	match String(p["kind"]):
		"step":
			a["fam"][String(p["fam"])] = int(p["to"])
			if int(p["to"]) == 0:
				(a["fam"] as Dictionary).erase(String(p["fam"]))
		"sanction":
			var key := str(int(p["target"]))
			var m: Dictionary = (a["sanc"] as Dictionary).get(key, {})
			m[String(p["sanc"])] = int(m.get(String(p["sanc"]), 0)) + 1
			a["sanc"][key] = m
		"expel":
			var t := int(p["target"])
			_remove_member(state, t, int(data()["expel_ban_days"]))
			added.append(state.add_chronicle("%s est banni de %s : son siège reste vide, et le restera dix ans." % [state.get_empire(t).display_name(), name_short()]))
		_:
			AmphInst.apply_prop(state, p, added)
	state.relic_rev += 1


# --- Nomos : infractions, hors-la-loi, atrocités, droit de guerre ----------------------------------

static func breach_label(kind: String) -> String:
	return String(data()["breaches"].get(kind, kind))


## Un membre enfreint le Nomos (si l'interdit est en vigueur) : hors-la-loi, souvenir chez tous.
static func breach(state: GameState, eid: int, kind: String) -> void:
	if not founded(state) or not is_member(state, eid) or not banned(state, kind) or AmphPower.exempt_kind(state, eid, kind):
		return
	_make_outlaw(state, eid, kind)


static func _make_outlaw(state: GameState, eid: int, kind: String) -> void:
	var a: Dictionary = state.amph
	var key := str(eid)
	var o: Dictionary = (a["outlaw"] as Dictionary).get(key, {"n": 0})
	var was := outlaw(state, eid)
	o["until"] = state.tick + int(data()["outlaw_days"])
	o["why"] = kind
	o["n"] = int(o.get("n", 0)) + 1
	a["outlaw"][key] = o
	for m in members(state):
		if m != eid:
			Diplomacy.remember(state, m, eid, "amph_outlaw")
	var e := state.get_empire(eid)
	state.add_chronicle("%s déclare %s hors-la-loi : %s. %s" % [cap(name_short()), e.display_name(), breach_label(kind),
			"Sa peine est prolongée." if was else "Les amphictyons peuvent désormais voter des sanctions contre lui."], Espionage.public_to(state, members(state) + [eid]))


## Extermination d'une population : atrocité tant que la charte tient (pour tous les empires).
## Sanctions automatiques ; à la seconde, tous les membres gagnent un droit de guerre sans parjure.
static func on_atrocity(state: GameState, eid: int) -> void:
	if not founded(state) or GameState.is_npc(eid):
		return
	var a: Dictionary = state.amph
	var key := str(eid)
	var n := int((a["atroc"] as Dictionary).get(key, 0)) + 1
	a["atroc"][key] = n
	_make_outlaw(state, eid, "exterminate")
	var m: Dictionary = (a["sanc"] as Dictionary).get(key, {})
	for sid in data()["atrocity"]["auto_sanctions"]:
		m[String(sid)] = maxi(int(m.get(String(sid), 0)), 1)
	a["sanc"][key] = m
	state.relic_rev += 1
	AmphInst.add_trig(state, "atrocity", eid, -1)
	if n >= 2:
		state.add_chronicle("Seconde atrocité de %s : selon la charte, chaque amphictyon peut lui déclarer la guerre sans se parjurer." % state.get_empire(eid).display_name(),
				Espionage.public_to(state, members(state) + [eid]))


## a (membre) peut-il attaquer b sans parjure (charte des atrocités, défense mutuelle) ?
static func casus(state: GameState, a: int, b: int) -> bool:
	if not founded(state) or not is_member(state, a) or a == b:
		return false
	if int((state.amph["atroc"] as Dictionary).get(str(b), 0)) >= 2 and outlaw(state, b):
		return true
	return int((state.amph["casus"] as Dictionary).get(str(b), 0)) > state.tick


## Une guerre vient d'être déclarée (a contre b) : Conventions de guerre et Défense mutuelle.
## broke : un traité a été rompu ; grief : a avait un dossier d'espions contre b.
static func on_war(state: GameState, a: int, b: int, broke: bool, grief: bool) -> void:
	if not founded(state) or grief or casus(state, a, b) or GameState.is_npc(a) or GameState.is_npc(b):
		return
	if is_member(state, a) and is_member(state, b):
		if broke and banned(state, "treaty_war"):
			breach(state, a, "treaty_war")
		elif banned(state, "aggression"):
			breach(state, a, "aggression")
	if is_member(state, b) and _level_flag(state, "defense"):
		state.amph["casus"][str(a)] = state.tick + int(data()["casus_days"])
		state.add_chronicle("Défense mutuelle : %s attaque %s sans motif. Chaque amphictyon peut lui déclarer la guerre sans se parjurer pendant 5 ans." % [
				state.get_empire(a).display_name(), state.get_empire(b).display_name()], Espionage.public_to(state, members(state) + [a]))


## Un espion de a démasqué chez b.
static func on_spy_caught(state: GameState, a: int, b: int, op_id: String) -> void:
	if not founded(state) or not is_member(state, b):
		return
	if op_id == "vol_techno" and banned(state, "tech_theft"):
		breach(state, a, "tech_theft")
	elif banned(state, "spy"):
		breach(state, a, "spy")


## Un nid détruit, un repaire démantelé : infraction (Sanctuaires) ou prime (Primes et patrouilles).
static func on_hunt(state: GameState, eid: int, nest: bool) -> void:
	if not founded(state) or not is_member(state, eid):
		return
	if nest and banned(state, "nest"):
		breach(state, eid, "nest")
		return
	var lvl := level_sum(state, "bounty")
	if lvl <= 0:
		return
	var reward: Dictionary = data()["bounty"].get(str(mini(lvl, 3)), {})
	var e := state.get_empire(eid)
	for r in reward:
		e.resources[r] = int(e.resources.get(r, 0)) + int(reward[r])


# --- Effets ----------------------------------------------------------------------------------------

## Fidèle de la foi galactique : membre dont la foi d'État est la foi galactique.
static func galactic_follower(state: GameState, eid: int) -> bool:
	var gf := String(state.amph.get("gfaith", ""))
	if gf == "" or not state.faith_on or not is_member(state, eid):
		return false
	return String((state.faiths.get("state", {}) as Dictionary).get(str(eid), "")) == gf


## Effets pour Research.effects (même empreinte relic_rev) : résolutions pour les membres, sanctions
## pour les visés.
static func effects(state: GameState, eid: int) -> Dictionary:
	var out := {}
	if not founded(state):
		return out
	if is_member(state, eid):
		var gf := galactic_follower(state, eid)
		for f: Dictionary in family_defs():
			var fid := String(f["id"])
			if not family_available(state, fid) or AmphPower.sovereign(state, eid, fid):
				continue
			for l: Dictionary in _levels_in_force(state, fid):
				Research._merge(out, l.get("fx", {}))
				if gf:
					Research._merge(out, l.get("faith_fx", {}))
	AmphInst.effects(state, eid, out)
	var sc: Dictionary = (state.amph["sanc"] as Dictionary).get(str(eid), {})
	if not sc.is_empty() and sanctionable(state, eid) and not AmphPower.immune(state, eid):
		for sid in sc:
			var degs: Array = sanction_def(String(sid)).get("degrees", [])
			var d := clampi(int(sc[sid]), 0, degs.size())
			if d > 0:
				Research._merge(out, degs[d - 1])
	return out


## Coût des opérations d'espionnage d'un membre, en points de % (Concurrence des ombres).
static func op_cost_pct(state: GameState, eid: int) -> int:
	return level_sum(state, "op_cost_pct") if is_member(state, eid) else 0


## Chances de découverte en plus pour un espion de a chez b (Bureau des chiffres, entre membres).
static func discovery_bonus(state: GameState, a: int, b: int) -> int:
	return level_sum(state, "discovery") if is_member(state, a) and is_member(state, b) else 0


## Accès au marché commun de la Bourse galactique : réservé aux membres dès la fondation, et fermé
## aux visés par des sanctions économiques du 3e degré.
static func in_common_market(state: GameState, eid: int) -> bool:
	if not founded(state):
		return true
	if not is_member(state, eid):
		return false
	return not (sanctionable(state, eid) and sanction_degree(state, eid, "eco") >= 3)


# --- Mois et jours ---------------------------------------------------------------------------------

## Chaque mois : offre de fondation, voix, peines échues, foi galactique.
static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	var a: Dictionary = state.amph
	if not founded(state):
		_check_offer(state, added)
		return
	# Membres disparus ou devenus inéligibles.
	for m in members(state):
		if not eligible(state, m):
			(a["members"] as Array).erase(m)
			(a["voix"] as Dictionary).erase(str(m))
			state.relic_rev += 1
	recompute_voix(state)
	# Peines échues : les sanctions tombent avec le statut de hors-la-loi.
	for key in (a["outlaw"] as Dictionary).keys():
		if int(a["outlaw"][key]["until"]) <= state.tick:
			(a["outlaw"] as Dictionary).erase(key)
			if (a["sanc"] as Dictionary).has(key) and not AmphInst.denounced(state, int(key)):
				(a["sanc"] as Dictionary).erase(key)
				state.relic_rev += 1
			var e := state.get_empire(int(key))
			if e != null and not e.eliminated:
				added.append(state.add_chronicle("%s purge sa peine : il n'est plus hors-la-loi, et les sanctions tombent." % e.display_name(), Espionage.public_to(state, members(state) + [int(key)])))
	# Sanctions d'un empire qui n'est plus ni hors-la-loi ni dénoncé : elles tombent aussi.
	for key in (a["sanc"] as Dictionary).keys():
		if not sanctionable(state, int(key)):
			(a["sanc"] as Dictionary).erase(key)
			state.relic_rev += 1
	for key in (a["mods"] as Dictionary).keys():
		var kept: Array = []
		for m in a["mods"][key]:
			if int(m[1]) > state.tick:
				kept.append(m)
		if kept.is_empty():
			(a["mods"] as Dictionary).erase(key)
		else:
			a["mods"][key] = kept
	_galactic_faith(state, added)
	AmphInst.monthly(state, added)
	AmphPower.monthly(state, added)


static func _check_offer(state: GameState, added: Array[Dictionary]) -> void:
	var fd: Dictionary = data()["found"]
	var a: Dictionary = state.amph
	if not (a["offer"] as Dictionary).is_empty():
		if state.tick - int(a["offer"]["since"]) > int(fd["offer_days"]):
			a["offer"] = {}
			added.append(state.add_chronicle("L'acte de fondation de %s n'a pas réuni ses trois signatures : il retourne aux archives, en attendant des temps meilleurs." % name_long()))
		return
	if state.tick < int(fd["min_day"]):
		return
	var n := 0
	var convener := -1
	for e in state.empires:
		if eligible(state, e.id):
			n += 1
			if convener < 0 and met_pct(state, e.id) >= int(fd["met_pct"]):
				convener = e.id
	if convener < 0 or n < int(fd["founders"]):
		return
	a["offer"] = {"since": state.tick, "yes": []}
	added.append(state.add_chronicle("%s, qui a rencontré presque toute la galaxie, fait circuler un projet : %s. Il faut trois signatures pour la fonder." % [state.get_empire(convener).display_name(), name_long()]))


static func _galactic_faith(state: GameState, added: Array[Dictionary]) -> void:
	var a: Dictionary = state.amph
	var gf := ""
	if state.faith_on and fam_value(state, "foi") < 0:
		var cnt := {}
		for pid in state.colonies:
			var c: Colony = state.colonies[pid]
			if not is_member(state, c.owner):
				continue
			for fid in c.faith:
				cnt[String(fid)] = int(cnt.get(String(fid), 0)) + int(c.faith[fid])
		var keys := cnt.keys()
		keys.sort()
		for k in keys:
			if gf == "" or int(cnt[k]) > int(cnt[gf]):
				gf = String(k)
	if gf != String(a.get("gfaith", "")):
		a["gfaith"] = gf
		state.relic_rev += 1
		if gf != "" and (state.faiths.get("list", {}) as Dictionary).has(gf):
			added.append(state.add_chronicle("%s proclame %s foi galactique : ses fidèles d'État parleront plus fort sous la voûte." % [cap(name_short()), String(state.faiths["list"][gf]["name"])], Espionage.public_to(state, members(state))))


## Chaque jour : ouverture et clôture des séances.
static func daily(state: GameState, added: Array[Dictionary]) -> void:
	if not founded(state):
		return
	AmphInst.daily(state, added)
	AmphPower.daily(state, added)
	if in_session(state):
		if state.tick >= int(session(state)["end"]):
			_close_session(state, added)
	elif state.tick >= int(state.amph["next"]):
		_open_session(state, added)


## Jours avant la prochaine séance (ou avant la clôture du vote en cours).
static func days_left(state: GameState) -> int:
	if not founded(state):
		return -1
	if in_session(state):
		return maxi(0, int(session(state)["end"]) - state.tick)
	return maxi(0, int(state.amph["next"]) - state.tick)
