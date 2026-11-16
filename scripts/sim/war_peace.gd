class_name WarPeace
extends RefCounted
## Buts de guerre, lot 2 (voir Wars pour le lot 1) : occupation avant annexion (prop. 8), lassitude par
## camp (9), statu quo (11), reddition sur occupation totale (12), traité à la carte étendu (13), registre
## des traités (15), camps et chef de guerre (16), revanchisme (17), victoires (30).
##
## Données dans state.wars (sauvegardées avec le lot 1) :
##   "occ_on" : option Occupation ; "occ" : {"<système>": {"o": occupant, "own": propriétaire, "t"}} ;
##   "treaties" : [{id, name, a, b, w (vainqueur, -1 statu quo), t, kind, war, cl: {clause: échéance (-1
##   sans échéance, -2 violée)}, dmz: [systèmes]}] ; "tid" ; "vic" (règlement en cours, transitoire).
## Dans chaque guerre (Wars) : "ex" (lassitude %), "pw" (puissance au début), "e100" (jour des 100 %),
## "lead" (clé de la guerre du chef, pour un allié entré à ses côtés), "chief", "idle".

const CLAUSES: Array[String] = ["dmz", "fleet", "pass", "heroes", "convert", "regime", "transfer", "koinon", "people"]


static func _cfg(k: String) -> Dictionary:
	return Wars.data().get(k, {})


static func _w(state: GameState) -> Dictionary:
	var w := Wars._w(state)
	if not w.has("occ"):
		w["occ"] = {}
	if not w.has("treaties"):
		w["treaties"] = []
	return w


# --- Occupation (prop. 8) -------------------------------------------------------------------------

static func occ_on(state: GameState) -> bool:
	return state.wars_on and bool(state.wars.get("occ_on", false))


static func occupier(state: GameState, sid: int) -> int:
	if not state.wars_on:
		return -1
	var o: Variant = (state.wars.get("occ", {}) as Dictionary).get(str(sid))
	return -1 if o == null else int(o["o"])


## Qui tient le système : l'occupant s'il y en a un, sinon le propriétaire.
static func holder(state: GameState, sid: int) -> int:
	var o := occupier(state, sid)
	return o if o >= 0 else state.system_owner(sid)


## Systèmes occupés par eid (triés).
static func occupied_by(state: GameState, eid: int) -> Array[int]:
	var out: Array[int] = []
	var m: Dictionary = state.wars.get("occ", {})
	for k in m:
		if int(m[k]["o"]) == eid:
			out.append(int(k))
	out.sort()
	return out


## Systèmes de eid occupés par d'autres (triés).
static func occupied_of(state: GameState, eid: int) -> Array[int]:
	var out: Array[int] = []
	var m: Dictionary = state.wars.get("occ", {})
	for k in m:
		if state.system_owner(int(k)) == eid:
			out.append(int(k))
	out.sort()
	return out


## Invasion réussie (appelé par l'ordre "invade") : vrai si l'occupation s'en charge (sinon, conquête).
static func invade(state: GameState, sid: int, by: int) -> bool:
	if not state.wars_on:
		return false
	var occ := occupier(state, sid)
	var owner := state.system_owner(sid)
	if occ >= 0:
		if by == owner or not Combat.at_war(state, by, owner):
			release(state, sid, "%s libère %s : l'occupant plie bagage, les drapeaux reviennent aux fenêtres." % [_name(state, by), _sys(state, sid)])
		else:
			_occupy(state, sid, by)
		return true
	if not occ_on(state) or not Combat.at_war(state, by, owner):
		return false
	_occupy(state, sid, by)
	return true


static func _occupy(state: GameState, sid: int, by: int) -> void:
	var owner := state.system_owner(sid)
	var w := _w(state)
	w["occ"][str(sid)] = {"o": by, "own": owner, "t": state.tick}
	state.garrisons.erase(sid)
	state.sieges.erase(sid)
	Wars.on_occupy(state, sid, by, owner)
	Diplomacy.note_conquest(state, by, owner)
	state.add_chronicle("%s occupe %s, système de %s. La propriété attendra le traité ; les impôts, eux, changent de main dès ce soir." % [
			_name(state, by), _sys(state, sid), _name(state, owner)], Espionage.public_to(state, [by, owner]))


static func release(state: GameState, sid: int, line := "") -> void:
	var w := _w(state)
	if not w["occ"].has(str(sid)):
		return
	var o := int(w["occ"][str(sid)]["o"])
	w["occ"].erase(str(sid))
	if line != "":
		state.add_chronicle(line, Espionage.public_to(state, [o, state.system_owner(sid)]))


## Libérer un système occupé : le propriétaire, ou un ennemi de l'occupant. "" si possible.
static func check_liberate(state: GameState, eid: int, f: Fleet, occ: int) -> String:
	if occ == eid:
		return "vous occupez déjà ce système"
	if not Combat.at_war(state, eid, occ):
		return "vous n'êtes pas en guerre avec %s, qui l'occupe" % state.get_empire(occ).short_name()
	for other in Fleets.fleets_at(state, f.system_id, occ):
		if Combat.is_armed(other):
			return "une flotte de l'occupant tient encore l'orbite"
	if f.troops <= 0:
		return "aucune troupe à bord (les croiseurs en emportent le plus)"
	return ""


## Revenu de l'occupant : sa part de ce que produisent les systèmes qu'il occupe.
static func occupation_income(state: GameState, eid: int) -> Dictionary:
	var out := {}
	var pct := int(_cfg("occupation").get("income_pct", 50))
	if pct <= 0 or pct >= 100:
		return out
	for sid in occupied_by(state, eid):
		var owner := state.system_owner(sid)
		var held_pct := GroundOccupation.income_pct(state, sid)  # combat au sol : occupation tenue ou non
		for pid in state.galaxy.systems[sid].planet_ids:
			var c: Colony = state.colonies.get(pid)
			if c == null or c.owner != owner:
				continue
			var g: Dictionary = Economy.colony_yields(state, c)["gross"]
			for r in g:
				if int(g[r]) > 0 and r != "knowledge":
					@warning_ignore("integer_division")
					out[r] = int(out.get(r, 0)) + int(g[r]) * pct / (100 - pct) * held_pct / 100
	var bonus := int(WarLaws.talent(state, eid).get("occ_income_pct", 0))
	if bonus != 0:
		for r in out:
			@warning_ignore("integer_division")
			out[r] = int(out[r]) * (100 + bonus) / 100
	return out


## Part laissée au propriétaire d'un système occupé (100 sinon).
static func owner_pct(state: GameState, sid: int) -> int:
	if occupier(state, sid) < 0:
		return 100
	return 100 - int(_cfg("occupation").get("income_pct", 50))


## Plus d'occupation sans guerre (paix signée, empire disparu, propriétaire changé).
static func _prune_occ(state: GameState) -> void:
	var m: Dictionary = _w(state)["occ"]
	var keys := m.keys()
	keys.sort()
	for k in keys:
		var o := int(m[k]["o"])
		var owner := state.system_owner(int(k))
		if owner < 0 or owner == o or not Combat.at_war(state, o, owner):
			m.erase(k)


# --- Lassitude (prop. 9) ---------------------------------------------------------------------------

## Multiplicateur de lassitude de eid dans rec (en %).
static func _ex_mult(rec: Dictionary, eid: int) -> int:
	var c := _cfg("exhaustion")
	var gid := Wars.goal_of(rec, eid)
	if int(rec["a"]) == eid and (gid == "conquete" or gid == "soumission"):
		@warning_ignore("integer_division")
		return int(c.get("attacker_pct", 125)) * int(rec.get("exm", [100, 100])[0]) / 100
	var m := int(rec.get("exm", [100, 100])[Wars.side(rec, eid)])
	if int(rec["d"]) == eid:
		@warning_ignore("integer_division")
		return int(c.get("defender_pct", 75)) * m / 100
	return m


static func add_ex(rec: Dictionary, eid: int, n: int) -> void:
	if n <= 0:
		return
	if not rec.has("ex"):
		rec["ex"] = [0, 0]
	var i := Wars.side(rec, eid)
	# Centièmes de point gardés à part : 1 % par mois x 75 % ne doit pas s'arrondir à 1.
	if not rec.has("exr"):
		rec["exr"] = [0, 0]
	var tot := n * _ex_mult(rec, eid) + int(rec["exr"][i])
	@warning_ignore("integer_division")
	rec["ex"][i] = mini(100, int(rec["ex"][i]) + tot / 100)
	rec["exr"][i] = tot % 100


static func exhaustion(state: GameState, eid: int, other: int) -> int:
	var rec := Wars.war(state, eid, other)
	if rec.is_empty():
		return 0
	return int(rec.get("ex", [0, 0])[Wars.side(rec, eid)])


## Lassitude la plus forte de eid dans ses guerres.
static func max_exhaustion(state: GameState, eid: int) -> int:
	var n := 0
	var e := state.get_empire(eid)
	if e == null:
		return 0
	for w in e.wars:
		n = maxi(n, exhaustion(state, eid, int(w)))
	return n


## Pertes en bataille : lassitude du perdant.
static func on_losses(state: GameState, rec: Dictionary, loser: int, pts: int) -> void:
	var i := Wars.side(rec, loser)
	var pw: Array = rec.get("pw", [0, 0])
	var base := maxi(50, int(pw[i]))
	@warning_ignore("integer_division")
	add_ex(rec, loser, pts * int(_cfg("exhaustion").get("loss_pct", 60)) / base)


## Stabilité : la lassitude remplace la durée de la guerre.
static func stability_value(state: GameState, eid: int) -> int:
	var ex := max_exhaustion(state, eid)
	@warning_ignore("integer_division")
	return ex * int(_cfg("exhaustion").get("stability_max", -6)) / 100


# --- Statu quo (prop. 11) --------------------------------------------------------------------------

## Peut-on imposer le statu quo à other ? "" si oui.
static func check_impose(state: GameState, eid: int, other: int) -> String:
	if not state.wars_on:
		return "les buts de guerre ne sont pas actifs dans cette partie"
	var rec := Wars.war(state, eid, other)
	if rec.is_empty():
		return "vous n'êtes pas en guerre"
	if rec.has("lead") and not Wars.war_by_key(state, String(rec["lead"])).is_empty():
		return "votre chef de guerre négocie pour vous"
	if Diplomacy.no_treaties(state, eid) or Diplomacy.no_treaties(state, other):
		return "l'Essaim ne signe rien : il digère"
	var i := 1 - Wars.side(rec, eid)
	var t := int(rec.get("e100", [-1, -1])[i])
	var need := int(_cfg("status_quo").get("impose_days", 360))
	if t < 0:
		return "il faut que sa lassitude atteigne 100 %% (elle est à %d %%)" % int(rec.get("ex", [0, 0])[i])
	if state.tick - t < need:
		return "sa lassitude est à 100 %% depuis %d jours (il en faut %d)" % [state.tick - t, need]
	return ""


static func impose(state: GameState, eid: int, other: int) -> void:
	var name := String(Wars.war(state, eid, other).get("name", "la guerre"))
	Diplomacy.sign_treaty(state, eid, other, Diplomacy.PEACE)
	state.add_chronicle("Fin de la %s : %s impose le statu quo à %s, à bout de forces." % [name, _name(state, eid), _name(state, other)],
			Espionage.public_to(state, [eid, other]))


## Juste avant une paix (Diplomacy.sign_treaty) : statu quo, sauf règlement en cours (victoire, conditions).
static func before_peace(state: GameState, a: int, b: int) -> void:
	if not state.wars_on:
		return
	var w := _w(state)
	var rec := Wars.war(state, a, b)
	if rec.is_empty():
		return
	if not bool(w.get("vic", false)):
		var kept := _status_quo(state, a, b, rec)
		register(state, a, b, -1, "statu quo", {}, String(rec.get("name", "")), kept)
	else:
		_release_pair(state, a, b)
	_end_linked(state, Diplomacy.key(a, b))


## Chacun garde ce qu'il occupe (ou a pris) et revendique ; le reste revient. Renvoie un système gardé (-1).
static func _status_quo(state: GameState, a: int, b: int, rec: Dictionary) -> int:
	var kept := -1
	var m: Dictionary = _w(state)["occ"]
	var keys := m.keys()
	keys.sort()
	for k in keys:
		var sid := int(k)
		var o := int(m[k]["o"])
		var owner := state.system_owner(sid)
		if not ((o == a and owner == b) or (o == b and owner == a)):
			continue
		m.erase(k)
		if Wars.has_claim(state, o, sid) and sid != FactionTraits.capital_system(state, owner):
			Combat.capture_system(state, sid, o)
			kept = sid
	# Conquête immédiate : les systèmes pris sans revendication reviennent.
	var took: Dictionary = rec.get("took", {})
	var tk := took.keys()
	tk.sort()
	for k in tk:
		var sid := int(k)
		var t: Array = took[k]
		var taker := int(t[0])
		var old := int(rec["d"]) if taker == int(rec["a"]) else int(rec["a"])
		if state.system_owner(sid) != taker or occupier(state, sid) >= 0:
			continue
		if t.size() > 2 and int(t[2]) == 1:
			kept = sid
			continue
		if sid == FactionTraits.capital_system(state, taker):
			continue
		var ec := state.get_empire(old)
		if ec == null or ec.eliminated:
			continue
		Combat.capture_system(state, sid, old)
	return kept


static func _release_pair(state: GameState, a: int, b: int) -> void:
	var m: Dictionary = _w(state)["occ"]
	var keys := m.keys()
	for k in keys:
		var o := int(m[k]["o"])
		var owner := state.system_owner(int(k))
		if (o == a and owner == b) or (o == b and owner == a):
			m.erase(k)


# --- Camps et chef de guerre (prop. 16) -------------------------------------------------------------

## Une guerre où un allié entre aux côtés d'un ami : on la rattache à celle du chef.
static func link_joined(state: GameState, rec: Dictionary) -> void:
	var ally := int(rec["a"])
	var foe := int(rec["d"])
	var w := Wars._w(state)
	var best := ""
	var best_t := -1
	var keys: Array = (w["list"] as Dictionary).keys()
	keys.sort()
	for k in keys:
		var r: Dictionary = w["list"][k]
		if r.has("lead") or r == rec:
			continue
		var friend := -1
		if int(r["a"]) == foe:
			friend = int(r["d"])
		elif int(r["d"]) == foe:
			friend = int(r["a"])
		if friend < 0 or friend == ally:
			continue
		if int(r["t"]) > best_t:
			best_t = int(r["t"])
			best = String(k)
			rec["chief"] = friend
	if best != "":
		rec["lead"] = best


## Guerres des alliés rattachées à la guerre lead_key (triées).
static func linked(state: GameState, lead_key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var w := Wars._w(state)
	var keys: Array = (w["list"] as Dictionary).keys()
	keys.sort()
	for k in keys:
		var r: Dictionary = w["list"][k]
		if String(r.get("lead", "")) == lead_key:
			out.append(r)
	return out


## La guerre du chef finit : celles de ses alliés aussi (statu quo).
static func _end_linked(state: GameState, lead_key: String) -> void:
	for r in linked(state, lead_key):
		var a := int(r["a"])
		var d := int(r["d"])
		if Combat.at_war(state, a, d):
			r.erase("lead")
			Diplomacy.sign_treaty(state, a, d, Diplomacy.PEACE)


## Contribution de chaque membre du camp de eid dans la guerre rec (points de bataille + valeur prise).
static func contributions(state: GameState, rec: Dictionary, eid: int) -> Dictionary:
	var out := {}
	out[eid] = _contrib(state, rec, eid)
	for r in linked(state, Diplomacy.key(int(rec["a"]), int(rec["d"]))):
		if int(r.get("chief", -1)) == eid:
			var ally := int(r["a"])
			out[ally] = int(out.get(ally, 0)) + _contrib(state, r, ally)
	return out


static func _contrib(state: GameState, rec: Dictionary, eid: int) -> int:
	var i := Wars.side(rec, eid)
	var n := int(rec["bat"][i])
	for k in rec.get("took", {}):
		var t: Array = rec["took"][k]
		if int(t[0]) == eid and holder(state, int(k)) == eid:
			n += int(t[1]) * 10
	return n


## Part (en %) de eid dans les contributions de son camp.
static func share_pct(state: GameState, rec: Dictionary, eid: int) -> int:
	var c := contributions(state, rec, eid)
	var tot := 0
	for k in c:
		tot += int(c[k])
	if tot <= 0:
		return 100
	@warning_ignore("integer_division")
	return 100 * int(c[eid]) / tot


## Butin des alliés du vainqueur : les revendications qu'ils tiennent sur le vaincu leur reviennent.
static func allied_spoils(state: GameState, winner: int, loser: int) -> Array[String]:
	var out: Array[String] = []
	var home := FactionTraits.capital_system(state, loser)
	for r in linked(state, Diplomacy.key(winner, loser)):
		if int(r.get("chief", -1)) != winner or int(r["d"]) != loser:
			continue
		var ally := int(r["a"])
		for sid in Wars.claims_on(state, ally, loser):
			if sid != home and holder(state, sid) == ally:
				release(state, sid)
				Combat.capture_system(state, sid, ally)
				out.append("%s (à %s)" % [_sys(state, sid), state.get_empire(ally).short_name()])
	return out


## Paix séparée d'un allié entré en guerre aux côtés de son chef. "" si possible.
static func check_separate(state: GameState, eid: int, other: int) -> String:
	if not state.wars_on:
		return "les buts de guerre ne sont pas actifs dans cette partie"
	var rec := Wars.war(state, eid, other)
	if rec.is_empty():
		return "vous n'êtes pas en guerre"
	if not rec.has("lead") or Wars.war_by_key(state, String(rec["lead"])).is_empty() or int(rec["a"]) != eid:
		return "seul un allié entré aux côtés de son chef signe une paix séparée"
	if Diplomacy.no_treaties(state, other):
		return "l'Essaim ne signe rien : il digère"
	var cost := int(_cfg("sides").get("separate_influence", 50))
	if int(state.get_empire(eid).resources.get("influence", 0)) < cost:
		return "il faut %d influence" % cost
	return ""


static func separate(state: GameState, eid: int, other: int) -> void:
	var rec := Wars.war(state, eid, other)
	var chief := int(rec.get("chief", -1))
	var e := state.get_empire(eid)
	e.resources["influence"] = int(e.resources.get("influence", 0)) - int(_cfg("sides").get("separate_influence", 50))
	rec.erase("lead")
	Diplomacy.sign_treaty(state, eid, other, Diplomacy.PEACE)
	if chief >= 0:
		Diplomacy.remember(state, chief, eid, "separate_peace")
	state.add_chronicle("%s signe une paix séparée avec %s et laisse %s finir la guerre seul. On appelle cela de la prudence, ou autre chose." % [
			_name(state, eid), _name(state, other), _name(state, chief) if chief >= 0 else "ses alliés"], Espionage.public_to(state, [eid, other]))


# --- Traités (prop. 13 et 15) -----------------------------------------------------------------------

static func clause_def(k: String) -> Dictionary:
	return (_cfg("treaty").get("clauses", {}) as Dictionary).get(k, {})


static func is_clause(k: String) -> bool:
	return CLAUSES.has(k)


## La clause est-elle justifiée par le but annoncé du vainqueur ? (sans guerre suivie : oui)
static func justified(state: GameState, winner: int, loser: int, k: String) -> bool:
	if not state.wars_on:
		return true
	var rec := Wars.war(state, winner, loser)
	if rec.is_empty():
		return true
	var gid := Wars.goal_of(rec, winner)
	return (clause_def(k).get("goals", []) as Array).has(gid) or (clause_def(k).get("casus", []) as Array).has(String(rec["cb"]))


## Prix d'une clause du lot 2 (sans le doublement).
static func clause_price(k: String) -> int:
	return int(clause_def(k).get("price", 0))


static func _clause_on(terms: Dictionary, k: String) -> bool:
	var v: Variant = terms.get(k, false)
	if v is bool:
		return v
	if v is Array:
		return not (v as Array).is_empty()
	if v is String:
		return v != ""
	return v != null and int(v) != 0


## Clauses de terms qui ne sont pas justifiées par le but.
static func unjust(state: GameState, winner: int, loser: int, terms: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for k in terms:
		if _clause_on(terms, String(k)) and not justified(state, winner, loser, String(k)):
			out.append(String(k))
	out.sort()
	return out


static func check_clause(state: GameState, winner: int, loser: int, k: String) -> String:
	if not state.wars_on:
		return "condition inconnue : %s" % k
	match k:
		"heroes":
			if _relics_of(state, loser).is_empty():
				return "il ne tient aucune relique (vos héros prisonniers rentrent de toute façon à la paix)"
		"convert":
			if not state.faith_on or not Faiths.has_state_faith(state, winner) or Faiths.state_faith(state, winner) == Faiths.state_faith(state, loser):
				return "rien à convertir (il faut une foi d'État différente de la sienne)"
		"regime":
			if not state.politics_on or Politics.lead(state, winner) < 0 or Politics.lead(state, loser) < 0 or Politics.lead(state, winner) == Politics.lead(state, loser):
				return "pas de changement de régime possible (vie politique, courant différent)"
		"transfer":
			if Vassals.subjects_of(state, loser).is_empty():
				return "il n'a aucun sujet"
			if Vassals.is_subject(state, winner):
				return "un sujet ne prend pas de sujets"
		"koinon":
			if Koinon.league_of(state, loser) < 0:
				return "il n'est dans aucun Koinon"
		"people":
			var fid := state.get_empire(winner).faction_id
			var ok := Peoples.allowed_statuses(state, loser, fid)
			if ok.is_empty() or Peoples.status(state, loser, fid) == ok[0]:
				return "votre peuple n'a pas de statut à gagner chez lui"
	return ""


static func _relics_of(state: GameState, eid: int) -> Array[String]:
	var out: Array[String] = []
	for id in state.relics:
		if int(state.relics[id].get("owner", -1)) == eid:
			out.append(String(id))
	out.sort()
	return out


## Applique les clauses du lot 2 ; renvoie les échéances {clause: jour} pour le registre.
static func apply_clauses(state: GameState, winner: int, loser: int, terms: Dictionary) -> Dictionary:
	var cl := {}
	for k in CLAUSES:
		if not _clause_on(terms, k):
			continue
		var days := int(clause_def(k).get("days", 0))
		cl[k] = state.tick + days if days > 0 else -1
		match k:
			"pass":
				Diplomacy.share_maps(state, winner, loser)
			"heroes":
				WarLaws.release_one_way(state, loser, winner)
				var rl := _relics_of(state, loser)
				if not rl.is_empty():
					state.relics[rl[0]]["owner"] = winner
					state.relics[rl[0]]["hero"] = -1
					state.relic_rev += 1
			"convert":
				state.faiths["state"][str(loser)] = Faiths.state_faith(state, winner)
			"regime":
				var en := Politics.emp(state, loser)
				var r: Array = (en.get("ruling", []) as Array).duplicate()
				var lw := Politics.lead(state, winner)
				r.erase(lw)
				r.push_front(lw)
				en["ruling"] = r
				state.relic_rev += 1
			"transfer":
				var best := -1
				for s in Vassals.subjects_of(state, loser):
					if best < 0 or Vassals.power(state, s) > Vassals.power(state, best):
						best = s
				if best >= 0:
					var pid := Vassals.preset_of(state, best)
					var c: Dictionary = (Vassals.link(state, best).get("cl", {}) as Dictionary).duplicate(true)
					var loy := Vassals.loyalty(state, best)
					Vassals.unbind(state, best)
					Vassals.bind(state, winner, best, pid, c, loy, true)
			"koinon":
				if Koinon.league_of(state, loser) >= 0:
					Koinon._leave_now(state, Koinon.league_of(state, loser), loser)
			"people":
				var fid := state.get_empire(winner).faction_id
				var ok := Peoples.allowed_statuses(state, loser, fid)
				if not ok.is_empty():
					Peoples.set_status(state, loser, fid, ok[0])
	return cl


## Inscrit une paix au registre. place : système qui donne son nom (-1 : la capitale du vaincu).
static func register(state: GameState, a: int, b: int, winner: int, kind: String, cl: Dictionary, war_name: String, place := -1) -> Dictionary:
	if not state.wars_on:
		return {}
	var w := _w(state)
	var loser := b if winner == a else a
	var sid := place if place >= 0 else FactionTraits.capital_system(state, loser if winner >= 0 else b)
	var names: Array = _cfg("treaty").get("names", ["Traité de {s}"])
	var tid := int(w.get("tid", 1))
	var nm := String(names[posmod(tid * 7 + a + b, names.size())]).replace("{s}", _sys(state, sid) if sid >= 0 else "?")
	var t := {"id": tid, "name": nm, "a": a, "b": b, "w": winner, "t": state.tick, "kind": kind, "war": war_name, "cl": cl.duplicate(), "dmz": []}
	if cl.has("dmz") and winner >= 0:
		t["dmz"] = dmz_systems(state, winner, loser)
	w["tid"] = tid + 1
	(w["treaties"] as Array).append(t)
	while (w["treaties"] as Array).size() > 60:
		(w["treaties"] as Array).pop_front()
	DeedsBridges.on_peace(state, a, b, winner)
	return t


## Traités où figure eid, du plus récent au plus ancien.
static func treaties_of(state: GameState, eid: int) -> Array:
	var out: Array = []
	for t in state.wars.get("treaties", []):
		if int(t["a"]) == eid or int(t["b"]) == eid:
			out.push_front(t)
	return out


## Systèmes du vaincu à dmz_jumps sauts ou moins de ceux du vainqueur.
static func dmz_systems(state: GameState, winner: int, loser: int) -> Array[int]:
	var out: Array[int] = []
	var n := int(_cfg("treaty").get("dmz_jumps", 2))
	for sid in EmpireReport.owned_systems(state, loser):
		if state.system_owner(sid) == loser and Wars.jumps_to(state, winner, sid) <= n:
			out.append(sid)
	out.sort()
	return out


## Clause en vigueur entre le vainqueur w et le vaincu l ?
static func clause_active(state: GameState, w: int, l: int, k: String) -> Dictionary:
	for t in state.wars.get("treaties", []):
		if int(t["w"]) == w and (int(t["a"]) == l or int(t["b"]) == l) and int(t["w"]) != l:
			var u := int(t["cl"].get(k, -3))
			if u == -1 or u > state.tick:
				return t
	return {}


## Limite de flotte : les chantiers de eid ne lancent plus de vaisseaux de guerre.
static func fleet_capped(state: GameState, eid: int) -> bool:
	if not state.wars_on:
		return false
	for t in state.wars.get("treaties", []):
		var w := int(t["w"])
		if w < 0 or w == eid or (int(t["a"]) != eid and int(t["b"]) != eid):
			continue
		var u := int(t["cl"].get("fleet", -3))
		if u > state.tick and Vassals.power_pct(state, eid, w) > int(_cfg("treaty").get("fleet_pct", 50)):
			return true
	return false


## Violations (chaque mois) : flotte de guerre en zone démilitarisée.
static func _violations(state: GameState) -> void:
	for t in state.wars.get("treaties", []):
		var w := int(t["w"])
		if w < 0:
			continue
		var l := int(t["b"]) if int(t["a"]) == w else int(t["a"])
		var u := int(t["cl"].get("dmz", -3))
		if u <= state.tick:
			continue
		var bad := -1
		for sid in t["dmz"]:
			for f in Fleets.fleets_at(state, int(sid), l):
				if Combat.is_armed(f) and not f.is_moving():
					bad = int(sid)
					break
			if bad >= 0:
				break
		if bad >= 0:
			t["cl"]["dmz"] = -2
			violate(state, l, w, "%s envoie sa flotte de guerre à %s, en pleine zone démilitarisée (%s)." % [_name(state, l), _sys(state, bad), String(t["name"])])
			WarLaws.on_violated(state, t, l)


## l viole un traité signé avec w : motif Représailles pour w, parjure aux yeux des tiers.
static func violate(state: GameState, l: int, w: int, line: String) -> void:
	Diplomacy.remember(state, w, l, "treaty_violated")
	for e in state.empires:
		if e.id != l and e.id != w and not e.eliminated and not e.is_npc() and e.contacts.has(l):
			Diplomacy.remember(state, e.id, l, "oathbreaker")
	state.add_chronicle(line + " Les juristes ouvrent le registre ; les amiraux, leurs cartes.", Espionage.public_to(state, [l, w]))


# --- Revanchisme (prop. 17) -------------------------------------------------------------------------

## Le vaincu cède des systèmes pour score_pct de score : bonus de revanche.
static func on_ceded(state: GameState, loser: int, score_pct: int) -> void:
	if not state.wars_on or score_pct <= 0:
		return
	var c := _cfg("revanche")
	@warning_ignore("integer_division")
	var pct := mini(int(c.get("max_pct", 20)), score_pct / maxi(1, int(c.get("div", 4))))
	if pct <= 0:
		return
	(Wars._w(state)["mods"] as Array).append({"e": loser, "kind": "revanche", "pct": pct, "t": state.tick,
			"until": state.tick + int(c.get("years", 10)) * GameCalendar.DAYS_PER_YEAR})


## Bonus de revanche de eid en % (production de matériaux et d'énergie, garnisons).
static func revanche_pct(state: GameState, eid: int) -> int:
	if not state.wars_on:
		return 0
	var n := 0
	var span := int(_cfg("revanche").get("years", 10)) * GameCalendar.DAYS_PER_YEAR
	for m in state.wars.get("mods", []):
		if String(m["kind"]) == "revanche" and int(m["e"]) == eid and int(m["until"]) > state.tick:
			@warning_ignore("integer_division")
			n = maxi(n, int(m["pct"]) * (span - (state.tick - int(m["t"]))) / maxi(1, span))
	return n


# --- Chaque mois -----------------------------------------------------------------------------------

static func monthly(state: GameState) -> void:
	var w := _w(state)
	_prune_occ(state)
	var c := _cfg("exhaustion")
	var keys: Array = (w["list"] as Dictionary).keys()
	keys.sort()
	for k in keys:
		var rec: Dictionary = w["list"].get(k, {})
		if rec.is_empty():
			continue
		if not rec.has("e100"):
			rec["e100"] = [-1, -1]
		for eid in [int(rec["a"]), int(rec["d"])]:
			var i := Wars.side(rec, eid)
			var other := int(rec["d"]) if i == 0 else int(rec["a"])
			# Valeur occupée ou prise par l'autre, en % de la sienne.
			var lost := 0
			for tk in rec.get("took", {}):
				var t: Array = rec["took"][tk]
				if int(t[0]) == other and holder(state, int(tk)) == other:
					lost += int(t[1])
			@warning_ignore("integer_division")
			var occ_pct := 100 * lost / maxi(1, int(rec["val"][i]))
			@warning_ignore("integer_division")
			add_ex(rec, eid, int(c.get("per_month", 1)) + occ_pct / maxi(1, int(c.get("occ_div", 10))))
			if int(rec["ex"][i]) >= 100 and int(rec["e100"][i]) < 0:
				rec["e100"][i] = state.tick
		# Allié inactif.
		if rec.has("lead") and not bool(rec.get("idle", false)) and state.tick - int(rec["t"]) >= int(_cfg("sides").get("idle_days", 720)):
			if _contrib(state, rec, int(rec["a"])) <= 0 and int(rec.get("chief", -1)) >= 0:
				rec["idle"] = true
				Diplomacy.remember(state, int(rec["chief"]), int(rec["a"]), "idle_ally")
	# Fins automatiques : statu quo des deux camps épuisés, occupation totale.
	var auto := int(_cfg("status_quo").get("auto_days", 360))
	for k in keys:
		var rec: Dictionary = w["list"].get(k, {})
		if rec.is_empty() or rec.has("lead"):
			continue
		var a := int(rec["a"])
		var d := int(rec["d"])
		if Diplomacy.no_treaties(state, a) or Diplomacy.no_treaties(state, d):
			continue
		var e1: Array = rec.get("e100", [-1, -1])
		if int(e1[0]) >= 0 and int(e1[1]) >= 0 and state.tick - maxi(int(e1[0]), int(e1[1])) >= auto:
			var name := String(rec.get("name", "la guerre"))
			Diplomacy.sign_treaty(state, a, d, Diplomacy.PEACE)
			state.add_chronicle("Fin de la %s : épuisés, %s et %s reviennent au statu quo sans même le négocier." % [name, _name(state, a), _name(state, d)],
					Espionage.public_to(state, [a, d]))
			continue
		for pair in [[a, d], [d, a]]:
			if _all_occupied(state, int(pair[1])) and Wars._check_end(state, int(pair[0]), int(pair[1])) == "":
				Wars.apply_victory(state, int(pair[0]), int(pair[1]))
				break
	_violations(state)


## Tous les systèmes de eid sont-ils occupés ?
static func _all_occupied(state: GameState, eid: int) -> bool:
	if not occ_on(state):
		return false
	var own := EmpireReport.owned_systems(state, eid)
	if own.is_empty():
		return false
	for sid in own:
		if occupier(state, sid) < 0:
			return false
	return true


static func _name(state: GameState, eid: int) -> String:
	var e := state.get_empire(eid)
	return e.display_name() if e != null else "?"


static func _sys(state: GameState, sid: int) -> String:
	return state.galaxy.systems[sid].system_name if sid >= 0 and sid < state.galaxy.systems.size() else "?"
