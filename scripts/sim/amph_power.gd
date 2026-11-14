class_name AmphPower
extends RefCounted
## Amphictyonie, lot 3 (étude « Conseil galactique », 2026-11-14) : pouvoir, victoire et ponts.
## Règles : data/amphictyony.json (« power », « chancellor », « politics », « religion », « talents »).
## - Pleins pouvoirs (21) : mandat à vie de l'Arbitre, puis l'Impérateur ; soumis et rebelles, autorité.
## - Victoire diplomatique (22) : élection du Chancelier des étoiles (67 % de toutes les voix), refus du
##   verdict et Dernière Guerre.
## - Politique (25) : siéger pousse la Concorde, une résolution adoptée pousse le courant de sa voie
##   chez ceux qui l'ont votée, conflits entre résolutions et lois, loi Souveraineté.
## - Religion (27) : zèle de la foi galactique, guerre sainte qui réunit l'assemblée, Conclave.
## - Talents de peuple (28), par couches d'espèce (marchent pour les peuples personnalisés).
##
## Clés de state.amph ajoutées au lot 3 :
## - "imp" : {"eid", "since", "auth", "until" (fin du choix), "settled", "sub": [soumis], "reb": [rebelles]} ;
## - "chan" : {"start", "end", "cands": [a, b], "votes": {empire: candidat}} (élection en cours) ;
## - "dip" : {"eid", "loser", "until", "voters", "war", "cap0", "war_end", "won"} (verdict du Chancelier) ;
## - "share" : {empire: dernier score à l'élection, en %} ; "sov" : {empire: {famille: fin}} (souveraineté).


static func data() -> Dictionary:
	return Amphictyony.data()


static func pdata() -> Dictionary:
	return data()["power"]


static func cdata() -> Dictionary:
	return data()["chancellor"]


static func poldata() -> Dictionary:
	return data()["politics"]


static func _a(state: GameState) -> Dictionary:
	return state.amph


static func _name(state: GameState, eid: int) -> String:
	var e := state.get_empire(eid)
	return e.display_name() if e != null else "?"


static func _audience(state: GameState, extra: Array = []) -> Array:
	return Amphictyony.members(state) + AmphInst.observers(state) + extra


# --- Talents de peuple -------------------------------------------------------------------------------

static func talent_defs() -> Array:
	return data()["talents"]


## Le talent si l'empire y a droit par ses couches d'espèce, sinon {}.
static func talent(state: GameState, eid: int, id: String) -> Dictionary:
	var e := state.get_empire(eid)
	if e == null:
		return {}
	for t: Dictionary in talent_defs():
		if String(t["id"]) == id:
			return t if FactionTraits.species_matches(e.faction(), t.get("requires", {})) else {}
	return {}


static func has_talent(state: GameState, eid: int, id: String) -> bool:
	return not talent(state, eid, id).is_empty()


static func talents_of(state: GameState, eid: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var e := state.get_empire(eid)
	if e == null:
		return out
	for t: Dictionary in talent_defs():
		if FactionTraits.species_matches(e.faction(), t.get("requires", {})):
			out.append(t)
	return out


## Coût d'une proposition après les talents (Tribune : -25 % ; Anathème : Foi à moitié prix).
@warning_ignore("integer_division")
static func cost_for(state: GameState, eid: int, kind: String, fid: String, cost: Dictionary) -> Dictionary:
	if eid < 0 or cost.is_empty():
		return cost
	var pct := 100
	var tr := talent(state, eid, "tribune")
	if not tr.is_empty():
		pct += int(tr["cost_pct"])
	var an := talent(state, eid, "anatheme")
	if not an.is_empty() and kind == "step" and fid == "foi":
		pct = pct * int(an["foi_cost_pct"]) / 100
	if pct == 100:
		return cost
	var out := {}
	for r in cost:
		out[r] = maxi(1, int(cost[r]) * pct / 100)
	return out


## Propositions qu'un membre peut avoir en même temps (Tribune : 2).
static func max_props(state: GameState, eid: int) -> int:
	var tr := talent(state, eid, "tribune")
	return int(tr["props"]) if not tr.is_empty() else 1


## Siège voilé : ni nom sur les propositions (pour les autres), ni souvenirs de vote.
static func veiled(state: GameState, eid: int) -> bool:
	return has_talent(state, eid, "siege_voile")


## Hors du concert : les sanctions glissent sur la ruche.
static func immune(state: GameState, eid: int) -> bool:
	return has_talent(state, eid, "hors_concert")


## Paliers de la Moisson qui déclenchent une crise (Hors du concert : 25, 50 et 75 %).
static func moisson_steps(state: GameState, eid: int) -> Array:
	var hc := talent(state, eid, "hors_concert")
	return hc["moisson"] if not hc.is_empty() else [int(AmphInst.idata()["crisis"]["moisson_pct"])]


## Consensus calculé : dans les derniers jours d'un vote, le vrai décompte.
static func sees_tally(state: GameState, eid: int) -> bool:
	var t := talent(state, eid, "consensus")
	return not t.is_empty() and Amphictyony.in_session(state) and int(Amphictyony.session(state)["end"]) - state.tick <= int(t["days"])


## Droit du plus fort : multiplicateur de la flotte dans les voix.
static func fleet_x(state: GameState, eid: int) -> int:
	var t := talent(state, eid, "plus_fort")
	return int(t["fleet_x"]) if not t.is_empty() else 1


## Lobby : voix achetées en énergie.
static func buy_cost(state: GameState, eid: int, cost: Dictionary) -> Dictionary:
	var t := talent(state, eid, "lobby")
	if t.is_empty():
		return cost
	return {"energy": int(cost.get("influence", 0)) * int(t["energy_x"])}


## Lobby : commission sur chaque tranche achetée par un autre.
static func on_buy(state: GameState, buyer: int) -> void:
	for m in Amphictyony.members(state):
		var t := talent(state, m, "lobby")
		if m != buyer and not t.is_empty():
			var e := state.get_empire(m)
			e.resources["energy"] = int(e.resources.get("energy", 0)) + int(t["commission"])


## Landsraad : les lignées unies qui votent pareil ajoutent une part de leurs voix (au dépouillement).
@warning_ignore("integer_division")
static func tally_bonus(state: GameState, votes: Dictionary, out: Dictionary) -> void:
	for m in Amphictyony.members(state):
		var t := talent(state, m, "landsraad")
		var v := int(votes.get(str(m), 0))
		if t.is_empty() or v == 0:
			continue
		for o in Amphictyony.members(state):
			if o != m and int(votes.get(str(o), 0)) == v and Victory.united(state, m, o):
				var side := "pour" if v > 0 else "contre"
				out[side] = int(out[side]) + Amphictyony.weight(state, o) * int(t["union_pct"]) / 100


# --- Anathème (Chœur) ---------------------------------------------------------------------------------

static func check_anathema(state: GameState, eid: int, target: int) -> String:
	var t := talent(state, eid, "anatheme")
	if t.is_empty():
		return "seule une foi conquérante jette l'anathème"
	if not Amphictyony.is_member(state, eid):
		return "il faut siéger"
	if not state.faith_on or not Faiths.has_state_faith(state, eid):
		return "il faut une foi d'État"
	var tg := state.get_empire(target)
	if tg == null or tg.eliminated or tg.is_npc() or target == eid or not state.get_empire(eid).contacts.has(target):
		return "cible inconnue"
	if Faiths.state_faith(state, target) == Faiths.state_faith(state, eid):
		return "il partage votre foi"
	if AmphInst.special_on(state) or AmphInst.coal_on(state):
		return "une session extraordinaire ou une coalition occupe déjà l'assemblée"
	var left := AmphInst._cd_left(state, "anath", eid)
	if left > 0:
		return "encore %d jours avant un nouvel anathème" % left
	if not Economy.can_afford(state.get_empire(eid), t["cost"]):
		return "il faut %s" % GameData.format_amounts(t["cost"])
	return ""


static func anathema(state: GameState, eid: int, target: int) -> void:
	var t := talent(state, eid, "anatheme")
	Economy.pay(state.get_empire(eid), t["cost"])
	AmphInst._set_cd(state, "anath", eid, int(t["cd"]))
	AmphInst.add_trig(state, "anathema", target, eid)
	var trigs: Array = _a(state)["trig"]
	AmphInst.open_special(state, trigs[trigs.size() - 1], eid)


# --- Droit du plus fort (Ferrocornes) -----------------------------------------------------------------

## Dernière résolution adoptée depuis moins d'un an que eid a votée contre (et qui tient encore).
static func duel_target(state: GameState, eid: int) -> Dictionary:
	var t := talent(state, eid, "plus_fort")
	if t.is_empty():
		return {}
	var hist: Array = _a(state)["hist"]
	for i in range(hist.size() - 1, -1, -1):
		var h: Dictionary = hist[i]
		if state.tick - int(h["day"]) > int(t["days"]):
			break
		var p: Dictionary = h["prop"]
		if bool(h["pass"]) and String(p["kind"]) == "step" and int((h.get("votes", {}) as Dictionary).get(str(eid), 0)) < 0 \
				and Amphictyony.fam_value(state, String(p["fam"])) == int(p["to"]) and int(p["by"]) != eid:
			return h
	return {}


static func _fleet(state: GameState, eid: int) -> int:
	var n := 0
	for f in Fleets.empire_fleets(state, eid):
		n += Combat.fleet_power(f)
	return n


static func check_duel(state: GameState, eid: int) -> String:
	var t := talent(state, eid, "plus_fort")
	if t.is_empty():
		return "seule une horde règle ses différends par un duel"
	if not Amphictyony.is_member(state, eid):
		return "il faut siéger"
	if duel_target(state, eid).is_empty():
		return "aucune résolution récente votée contre vous"
	var left := AmphInst._cd_left(state, "duel", eid)
	if left > 0:
		return "encore %d jours avant un nouveau duel" % left
	if not Economy.can_afford(state.get_empire(eid), t["cost"]):
		return "il faut %s" % GameData.format_amounts(t["cost"])
	return ""


static func duel(state: GameState, eid: int) -> void:
	var t := talent(state, eid, "plus_fort")
	var h := duel_target(state, eid)
	Economy.pay(state.get_empire(eid), t["cost"])
	AmphInst._set_cd(state, "duel", eid, int(t["cd"]))
	var p: Dictionary = h["prop"]
	var foe := int(p["by"])
	var label := Amphictyony.prop_label(state, p)
	if _fleet(state, eid) > _fleet(state, foe):
		var fid := String(p["fam"])
		_a(state)["fam"][fid] = int(p["from"])
		if int(p["from"]) == 0:
			(_a(state)["fam"] as Dictionary).erase(fid)
		state.relic_rev += 1
		state.add_chronicle("Duel de champions sous la voûte : %s terrasse le champion de %s. « %s » est abrogée, et personne n'ose ramasser le gant." % [
				_name(state, eid), _name(state, foe), Amphictyony.cap(label)], Espionage.public_to(state, _audience(state)))
	else:
		state.add_chronicle("Duel de champions sous la voûte : le champion de %s mord la poussière devant celui de %s. « %s » tient." % [
				_name(state, eid), _name(state, foe), Amphictyony.cap(label)], Espionage.public_to(state, _audience(state)))


# --- Pleins pouvoirs : l'Impérateur ------------------------------------------------------------------

static func life(state: GameState) -> bool:
	return AmphInst.arbiter(state) >= 0 and int((_a(state)["arbiter"] as Dictionary).get("life", 0)) > 0


static func imp_on(state: GameState) -> bool:
	return Amphictyony.founded(state) and not (_a(state)["imp"] as Dictionary).is_empty()


static func imperator(state: GameState) -> int:
	return int(_a(state)["imp"]["eid"]) if imp_on(state) else -1


static func authority(state: GameState) -> int:
	return int(_a(state)["imp"].get("auth", 0)) if imp_on(state) else 0


static func choosing(state: GameState) -> bool:
	return imp_on(state) and int(_a(state)["imp"].get("settled", 0)) == 0


static func submitted(state: GameState, eid: int) -> bool:
	return imp_on(state) and (_a(state)["imp"]["sub"] as Array).has(eid)


static func is_rebel(state: GameState, eid: int) -> bool:
	return imp_on(state) and (_a(state)["imp"]["reb"] as Array).has(eid)


static func prop_cost(kind: String) -> Dictionary:
	match kind:
		"term_lift":
			return {"influence": int(pdata()["lift_cost"])}
		"full_powers":
			return {"influence": int(pdata()["full_cost"])}
	return {}


static func check_prop(state: GameState, eid: int, kind: String) -> String:
	match kind:
		"term_lift":
			if AmphInst.arbiter(state) < 0:
				return "il n'y a pas d'Arbitre des étoiles"
			if life(state):
				return "son mandat est déjà à vie"
		"full_powers":
			if AmphInst.arbiter(state) != eid:
				return "seul l'Arbitre des étoiles réclame les pleins pouvoirs"
			if not life(state):
				return "il faut d'abord un mandat à vie"
			if imp_on(state):
				return "il y a déjà un Impérateur"
	return ""


static func prop_label(state: GameState, p: Dictionary) -> String:
	match String(p["kind"]):
		"term_lift":
			return "mandat à vie pour l'Arbitre des étoiles (%s)" % _name(state, int(p["target"]))
		"full_powers":
			return "pleins pouvoirs à l'Arbitre (%s) : il devient l'Impérateur" % _name(state, int(p["target"]))
	return "?"


static func prop_text(p: Dictionary) -> String:
	match String(p["kind"]):
		"term_lift":
			return "Le mandat de l'Arbitre n'a plus de terme. Une motion de défiance reste possible, tant qu'il n'a pas les pleins pouvoirs."
		"full_powers":
			return "L'Arbitre devient l'Impérateur (+50 % de voix). Chaque membre a 90 jours pour se soumettre (tribut, guerres de la Cour) ou se soulever (il quitte l'assemblée et entre en guerre contre lui). À autorité nulle, la Cour s'effondre."
	return ""


static func still_valid(state: GameState, p: Dictionary) -> bool:
	match String(p["kind"]):
		"term_lift":
			return AmphInst.arbiter(state) >= 0 and AmphInst.arbiter(state) == int(p["target"]) and not life(state)
		"full_powers":
			return AmphInst.arbiter(state) == int(p["target"]) and life(state) and not imp_on(state)
	return false


static func apply_prop(state: GameState, p: Dictionary, added: Array[Dictionary]) -> void:
	var a: Dictionary = _a(state)
	match String(p["kind"]):
		"term_lift":
			a["arbiter"]["life"] = 1
			added.append(state.add_chronicle("Le mandat de l'Arbitre des étoiles (%s) n'a plus de terme. On rallonge la toge." % _name(state, int(p["target"])),
					Espionage.public_to(state, _audience(state))))
		"full_powers":
			var pd := pdata()
			a["imp"] = {"eid": int(p["target"]), "since": state.tick, "auth": int(pd["auth0"]), "until": state.tick + int(pd["choice_days"]), "settled": 0, "sub": [], "reb": []}
			added.append(state.add_chronicle("%s reçoit les pleins pouvoirs : l'Arbitre des étoiles devient l'Impérateur. Chaque amphictyon a 90 jours pour ployer le genou ou prendre les armes." % _name(state, int(p["target"])),
					Espionage.public_to(state, _audience(state))))


static func check_submit(state: GameState, eid: int) -> String:
	if not choosing(state):
		return "aucune Cour impériale n'attend votre réponse"
	if not Amphictyony.is_member(state, eid) or eid == imperator(state):
		return "seuls les autres amphictyons choisissent"
	if submitted(state, eid):
		return "déjà soumis"
	return ""


static func submit(state: GameState, eid: int) -> void:
	(_a(state)["imp"]["sub"] as Array).append(eid)
	Diplomacy.remember(state, imperator(state), eid, "amph_submitted")
	state.add_chronicle("%s ploie le genou devant l'Impérateur (%s)." % [_name(state, eid), _name(state, imperator(state))], Espionage.public_to(state, _audience(state)))


static func check_rebel(state: GameState, eid: int) -> String:
	if not imp_on(state):
		return "il n'y a pas d'Impérateur"
	if not Amphictyony.is_member(state, eid) or eid == imperator(state):
		return "seuls les autres amphictyons se soulèvent"
	return ""


## eid se soulève : il quitte l'assemblée (banni 10 ans) et entre en guerre contre la Cour.
static func rise(state: GameState, eid: int) -> void:
	var imp := imperator(state)
	var im: Dictionary = _a(state)["imp"]
	(im["sub"] as Array).erase(eid)
	if not (im["reb"] as Array).has(eid):
		(im["reb"] as Array).append(eid)
	Amphictyony._remove_member(state, eid, int(pdata()["rebel_ban"]))
	Diplomacy.remember(state, imp, eid, "amph_rebel")
	state.add_chronicle("%s se soulève contre l'Impérateur (%s) : il déchire sa carte de membre et sonne la charge." % [_name(state, eid), _name(state, imp)],
			Espionage.public_to(state, _audience(state, [eid])))
	var e := state.get_empire(eid)
	for foe in [imp] + Array(im["sub"]):
		var f := int(foe)
		if f == eid or Combat.at_war(state, eid, f) or not e.contacts.has(f) or Diplomacy.check_war(state, eid, f) != "":
			continue
		Combat.start_war(state, eid, f)


## Une guerre déclarée contre l'Impérateur : ses soumis entrent en guerre à ses côtés.
static func on_war_declared(state: GameState, a: int, b: int, joined: bool) -> void:
	if joined or not imp_on(state) or b != imperator(state):
		return
	var names := PackedStringArray()
	for s in _a(state)["imp"]["sub"]:
		var sid := int(s)
		var se := state.get_empire(sid)
		if sid == a or se == null or se.eliminated or Combat.at_war(state, sid, a) or not se.contacts.has(a) or Diplomacy.check_war(state, sid, a) != "":
			continue
		Combat.start_war(state, sid, a, false, true)
		names.append(se.short_name())
	if not names.is_empty():
		state.add_chronicle("La Cour impériale appelle ses vassaux : %s entrent en guerre contre %s." % [", ".join(names), _name(state, a)], Espionage.public_to(state, _audience(state, [a])))


static func _collapse(state: GameState, why: String, added: Array[Dictionary]) -> void:
	var imp := imperator(state)
	_a(state)["imp"] = {}
	_a(state)["arbiter"] = {}
	state.relic_rev += 1
	var c := state.add_chronicle("La Cour impériale s'effondre (%s) : %s n'est plus Impérateur, et l'Amphictyonie n'a plus d'Arbitre. On décroche les portraits." % [why, _name(state, imp)],
			Espionage.public_to(state, _audience(state, [imp])))
	added.append(c)


## Un départ de l'assemblée : l'Impérateur parti, la Cour tombe ; un soumis parti n'est plus soumis.
static func on_remove(state: GameState, eid: int) -> void:
	if not imp_on(state):
		return
	if eid == imperator(state):
		var added: Array[Dictionary] = []
		_collapse(state, "l'Impérateur a quitté l'assemblée", added)
		return
	(_a(state)["imp"]["sub"] as Array).erase(eid)


static func _imp_monthly(state: GameState, added: Array[Dictionary]) -> void:
	if not imp_on(state):
		return
	var pd := pdata()
	var im: Dictionary = _a(state)["imp"]
	var imp := int(im["eid"])
	var ie := state.get_empire(imp)
	if ie == null or ie.eliminated or not Amphictyony.is_member(state, imp):
		_collapse(state, "l'Impérateur n'est plus", added)
		return
	if int(im.get("settled", 0)) == 0 and state.tick >= int(im["until"]):
		im["settled"] = 1
		for m in Amphictyony.members(state):
			if m != imp and not (im["sub"] as Array).has(m):
				(im["sub"] as Array).append(m)
		added.append(state.add_chronicle("Le délai de la Cour impériale expire : qui n'a rien dit s'est soumis. %d vassal%s, %d rebelle%s." % [
				(im["sub"] as Array).size(), "s" if (im["sub"] as Array).size() > 1 else "", (im["reb"] as Array).size(), "s" if (im["reb"] as Array).size() > 1 else ""],
				Espionage.public_to(state, _audience(state))))
	var sub: Array = []
	for s in im["sub"]:
		if Amphictyony.is_member(state, int(s)):
			sub.append(int(s))
	im["sub"] = sub
	var auth := int(im["auth"])
	var reb: Array = []
	for r in im["reb"]:
		var re := state.get_empire(int(r))
		if re == null or re.eliminated:
			auth += int(pd["auth_kill"])
			continue
		reb.append(int(r))
		if Combat.at_war(state, imp, int(r)):
			auth += int(pd["auth_reb"])
	im["reb"] = reb
	if int(im.get("settled", 0)) > 0:
		auth += mini(int(pd["auth_sub_max"]), sub.size() * int(pd["auth_sub"]))
	# Tribut des soumis.
	for s in sub:
		var se := state.get_empire(int(s))
		if se != null and Economy.can_afford(se, pd["tribute"]):
			Economy.pay(se, pd["tribute"])
			for r in pd["tribute"]:
				ie.resources[r] = int(ie.resources.get(r, 0)) + int(pd["tribute"][r])
	im["auth"] = clampi(auth, 0, int(pd["auth_max"]))
	if int(im["auth"]) <= 0:
		_collapse(state, "son autorité est tombée à zéro", added)


static func spy_check(state: GameState, a: int, b: int, op_id: String) -> String:
	if not imp_on(state):
		return "il n'y a pas d'Impérateur"
	if a == imperator(state):
		return "on ne sape pas sa propre Cour"
	if authority(state) >= int(pdata()["spy_below"]):
		return "son autorité est trop solide (%d)" % authority(state)
	match op_id:
		"saper_autorite":
			if b != imperator(state):
				return "la cible n'est pas l'Impérateur"
		"allumer_rebellion":
			if not submitted(state, b):
				return "la cible ne s'est pas soumise"
	return ""


static func spy_apply(state: GameState, _a2: int, b: int, o: Dictionary) -> String:
	match String(o["id"]):
		"saper_autorite":
			if not imp_on(state):
				return "la Cour était déjà tombée."
			var im: Dictionary = _a(state)["imp"]
			im["auth"] = maxi(0, int(im["auth"]) - int(o.get("auth", 15)))
			if int(im["auth"]) <= 0:
				var added: Array[Dictionary] = []
				_collapse(state, "les pamphlets ont eu raison d'elle", added)
				return "les pamphlets font le tour de la galaxie : la Cour impériale s'effondre."
			return "les pamphlets font le tour de la galaxie : l'autorité de l'Impérateur tombe à %d." % int(im["auth"])
		"allumer_rebellion":
			if not submitted(state, b):
				return "il n'était plus soumis."
			rise(state, b)
			return "nos agents ont soufflé sur les braises : il se soulève contre l'Impérateur."
	return ""


# --- Victoire diplomatique : le Chancelier des étoiles ------------------------------------------------

static func dip_enabled(state: GameState) -> bool:
	return Amphictyony.founded(state) and Victory.enabled(state, "diplomatique")


static func chan_on(state: GameState) -> bool:
	return Amphictyony.founded(state) and not (_a(state)["chan"] as Dictionary).is_empty()


static func chan(state: GameState) -> Dictionary:
	return _a(state)["chan"]


static func dip(state: GameState) -> Dictionary:
	return _a(state)["dip"]


## Jour de la prochaine élection (à partir de l'an 30, tous les 10 ans).
@warning_ignore("integer_division")
static func next_election(state: GameState) -> int:
	var cd := cdata()
	var from := int(cd["from_day"])
	if state.tick <= from:
		return from
	var every := int(cd["every"])
	return from + ((state.tick - from + every - 1) / every) * every


## Part (en %) des empires vivants éligibles qui siègent.
@warning_ignore("integer_division")
static func coverage(state: GameState) -> int:
	var n := 0
	for e in state.empires:
		if Amphictyony.eligible(state, e.id):
			n += 1
	return 0 if n == 0 else Amphictyony.members(state).size() * 100 / n


## Pourquoi l'assemblée ne peut pas élire de Chancelier ("" si elle le peut).
static func check_ready(state: GameState) -> String:
	var cd := cdata()
	if Amphictyony.members(state).size() < int(cd["min_members"]):
		return "il faut au moins %d amphictyons" % int(cd["min_members"])
	if coverage(state) < int(cd["cover_pct"]):
		return "l'assemblée ne réunit que %d %% des empires (il en faut %d %%)" % [coverage(state), int(cd["cover_pct"])]
	return ""


static func _open_chan(state: GameState, added: Array[Dictionary]) -> void:
	var why := check_ready(state)
	if why != "":
		added.append(state.add_chronicle("Pas d'élection du Chancelier des étoiles cette décennie : %s." % why, Espionage.public_to(state, _audience(state))))
		return
	var ms := Amphictyony.members(state)
	ms.sort_custom(func(x: int, y: int) -> bool:
		var wx := Amphictyony.weight(state, x)
		var wy := Amphictyony.weight(state, y)
		return wx > wy or (wx == wy and x < y))
	var cands := [ms[0], ms[1]]
	_a(state)["chan"] = {"start": state.tick, "end": state.tick + int(cdata()["vote_days"]), "cands": cands, "votes": {str(ms[0]): ms[0], str(ms[1]): ms[1]}}
	added.append(state.add_chronicle("Élection du Chancelier des étoiles : %s contre %s. Il faudra %d %% de toutes les voix de l'assemblée ; vote de 6 mois." % [
			_name(state, ms[0]), _name(state, ms[1]), int(cdata()["win_pct"])], Espionage.public_to(state, _audience(state))))


static func check_cvote(state: GameState, eid: int, x: int) -> String:
	if not chan_on(state):
		return "aucune élection en cours"
	if not Amphictyony.is_member(state, eid):
		return "seuls les amphictyons votent"
	var cands: Array = chan(state)["cands"]
	if x >= 0 and not cands.has(x):
		return "ce n'est pas un candidat"
	if cands.has(eid) and x != eid:
		return "un candidat vote pour lui-même"
	return ""


static func cvote(state: GameState, eid: int, x: int) -> void:
	var votes: Dictionary = chan(state)["votes"]
	if x < 0:
		votes.erase(str(eid))
	else:
		votes[str(eid)] = x


static func cvote_of(state: GameState, eid: int) -> int:
	if not chan_on(state):
		return -1
	return int((chan(state)["votes"] as Dictionary).get(str(eid), -1))


## Dépouillement : {candidat: voix} et "total" (toutes les voix de l'assemblée).
static func ctally(state: GameState) -> Dictionary:
	var out := {"total": Amphictyony.total_weight(state)}
	if not chan_on(state):
		return out
	for c in chan(state)["cands"]:
		out[int(c)] = 0
	for k in chan(state)["votes"]:
		var c2 := int(chan(state)["votes"][k])
		if out.has(c2) and Amphictyony.is_member(state, int(k)):
			out[c2] = int(out[c2]) + Amphictyony.weight(state, int(k))
	return out


@warning_ignore("integer_division")
static func _close_chan(state: GameState, added: Array[Dictionary]) -> void:
	var c := chan(state)
	var t := ctally(state)
	var total := maxi(1, int(t["total"]))
	var cands: Array = c["cands"]
	var w := int(cands[0])
	var l := int(cands[1])
	if int(t.get(l, 0)) > int(t.get(w, 0)):
		w = int(cands[1])
		l = int(cands[0])
	var share := int(t.get(w, 0)) * 100 / total
	_a(state)["share"][str(w)] = share
	_a(state)["share"][str(l)] = int(t.get(l, 0)) * 100 / total
	var voters: Array = []
	for k in c["votes"]:
		if int(c["votes"][k]) == w and int(k) != w and Amphictyony.is_member(state, int(k)):
			voters.append(int(k))
	voters.sort()
	_a(state)["chan"] = {}
	var we := state.get_empire(w)
	var le := state.get_empire(l)
	if share < int(cdata()["win_pct"]) or we == null or we.eliminated or check_ready(state) != "":
		added.append(state.add_chronicle("Élection du Chancelier des étoiles : %s arrive en tête avec %d %% des voix, loin des %d %% requis. Pas de Chancelier cette fois." % [
				_name(state, w), share, int(cdata()["win_pct"])], Espionage.public_to(state, _audience(state))))
		return
	if le == null or le.eliminated:
		_a(state)["dip"] = {"eid": w, "loser": l, "until": state.tick, "voters": voters, "war": 0, "won": 1}
		return
	_a(state)["dip"] = {"eid": w, "loser": l, "until": state.tick + int(cdata()["refuse_days"]), "voters": voters, "war": 0, "won": 0}
	added.append(state.add_chronicle("%s est élu Chancelier des étoiles avec %d %% des voix. %s a 60 jours pour s'incliner, ou refuser le verdict : ce serait la Dernière Guerre." % [
			_name(state, w), share, _name(state, l)], Espionage.public_to(state, _audience(state))))


static func pending_verdict(state: GameState) -> bool:
	var d := dip(state)
	return Amphictyony.founded(state) and not d.is_empty() and int(d["war"]) == 0 and int(d["won"]) == 0


static func check_refuse(state: GameState, eid: int) -> String:
	if not pending_verdict(state):
		return "aucun verdict à refuser"
	if int(dip(state)["loser"]) != eid:
		return "seul le candidat battu peut refuser le verdict"
	return ""


static func refuse(state: GameState, eid: int) -> void:
	var d := dip(state)
	var w := int(d["eid"])
	d["war"] = 1
	d["cap0"] = FactionTraits.capital_system(state, eid)
	d["war_end"] = state.tick + int(cdata()["war_days"])
	var e := state.get_empire(eid)
	var marchers: Array = [w] + Array(d["voters"])
	for v in marchers:
		var vid := int(v)
		Diplomacy.remember(state, vid, eid, "amph_refused")
		var ve := state.get_empire(vid)
		if vid == eid or ve == null or ve.eliminated or Combat.at_war(state, vid, eid) or not ve.contacts.has(eid) or Diplomacy.check_war(state, vid, eid) != "":
			continue
		Combat.start_war(state, vid, eid)
	state.add_chronicle("%s refuse le verdict : la Dernière Guerre commence. Le Chancelier élu (%s) et ceux qui l'ont élu marchent sur %s." % [
			e.display_name(), _name(state, w), e.short_name()], Espionage.public_to(state, _audience(state, [eid])))


static func check_accept(state: GameState, eid: int) -> String:
	return check_refuse(state, eid).replace("refuser", "accepter")


static func accept(state: GameState, eid: int) -> void:
	var d := dip(state)
	d["won"] = 1
	state.add_chronicle("%s s'incline devant le verdict de l'Amphictyonie." % _name(state, eid), Espionage.public_to(state, _audience(state)))


static func _dip_monthly(state: GameState, added: Array[Dictionary]) -> void:
	var d := dip(state)
	if d.is_empty() or int(d["won"]) > 0:
		return
	var we := state.get_empire(int(d["eid"]))
	if we == null or we.eliminated:
		_a(state)["dip"] = {}
		return
	var loser := int(d["loser"])
	var le := state.get_empire(loser)
	if int(d["war"]) == 0:
		if state.tick >= int(d["until"]) or le == null or le.eliminated:
			d["won"] = 1
		return
	var cap := int(d.get("cap0", -1))
	if le == null or le.eliminated or (cap >= 0 and state.system_owner(cap) != loser):
		d["won"] = 1
		added.append(state.add_chronicle("La Dernière Guerre est finie : %s a perdu sa capitale. Le Chancelier des étoiles (%s) prend place sous la voûte." % [
				_name(state, loser), _name(state, int(d["eid"]))], Espionage.public_to(state, _audience(state, [loser]))))
	elif state.tick >= int(d["war_end"]):
		_a(state)["dip"] = {}
		added.append(state.add_chronicle("La Dernière Guerre s'enlise : %s tient toujours sa capitale, et le titre de Chancelier retourne aux archives." % _name(state, loser),
				Espionage.public_to(state, _audience(state, [loser]))))


## Avancée vers la victoire diplomatique (Victory.progress).
static func victory(state: GameState, e: Empire, out: Dictionary) -> void:
	var cd := cdata()
	if not Amphictyony.founded(state):
		out["lines"].append("L'Amphictyonie n'est pas encore fondée")
		return
	var d := dip(state)
	var mine := not d.is_empty() and int(d["eid"]) == e.id
	out["won"] = mine and int(d["won"]) > 0
	var share := int((_a(state)["share"] as Dictionary).get(str(e.id), 0))
	if chan_on(state):
		out["lines"].append("Élection du Chancelier en cours, clôture le %s" % GameCalendar.date_string(int(chan(state)["end"])))
	else:
		out["lines"].append("Prochaine élection du Chancelier : le %s" % GameCalendar.date_string(next_election(state)))
	out["lines"].append("Dernier score : %d %% des voix (il en faut %d %%)" % [share, int(cd["win_pct"])])
	out["lines"].append("Assemblée : %d membres, %d %% des empires (il en faut %d et %d %%)" % [Amphictyony.members(state).size(), coverage(state), int(cd["min_members"]), int(cd["cover_pct"])])
	if mine and int(d["war"]) > 0:
		out["lines"].append("Dernière Guerre contre %s : prendre sa capitale avant le %s" % [_name(state, int(d["loser"])), GameCalendar.date_string(int(d["war_end"]))])
		share = int(cd["win_pct"])
	elif mine:
		out["lines"].append("Élu ; %s peut encore refuser le verdict jusqu'au %s" % [_name(state, int(d["loser"])), GameCalendar.date_string(int(d["until"]))])
		share = int(cd["win_pct"])
	Victory._instant(out, share, int(cd["win_pct"]))


# --- Politique : courants, conflits de lois, Souveraineté --------------------------------------------

## Une résolution adoptée pousse, chez ceux qui l'ont votée, le courant de sa voie.
static func _push_way(state: GameState, p: Dictionary, votes: Dictionary) -> void:
	if not state.politics_on or String(p["kind"]) != "step" or Amphictyony.is_repeal(int(p["from"]), int(p["to"])):
		return
	var cur := String((poldata()["way_current"] as Dictionary).get("%s:%s" % [String(p["fam"]), Amphictyony.way_of(int(p["to"]))], ""))
	var i := Politics.index_of(cur)
	if i < 0:
		return
	for k in votes:
		if int(votes[k]) <= 0 or not Politics.applies(state, int(k)):
			continue
		for sid in Stability.systems_of(state, int(k)):
			Politics.push(state, sid, i, int(poldata()["push"]))


static func sovereign(state: GameState, eid: int, fid: String) -> bool:
	return int(((_a(state)["sov"] as Dictionary).get(str(eid), {}) as Dictionary).get(fid, 0)) > state.tick


## Un interdit du Nomos qui ne lie pas eid (souveraineté invoquée sur sa famille).
static func exempt_kind(state: GameState, eid: int, kind: String) -> bool:
	for fid in (_a(state)["sov"] as Dictionary).get(str(eid), {}):
		if not sovereign(state, eid, String(fid)):
			continue
		var f := Amphictyony.family_def(String(fid))
		for way in ["a", "b"]:
			if (f.get(way, {}).get("bans", []) as Array).has(kind):
				return true
			for l: Dictionary in f.get(way, {}).get("levels", []):
				if (l.get("bans", []) as Array).has(kind):
					return true
	return false


## Conflits en cours entre les résolutions et les lois de eid : [{"law", "fam", "way"}].
static func conflicts(state: GameState, eid: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not state.politics_on or not Amphictyony.is_member(state, eid):
		return out
	for c: Dictionary in poldata()["law_conflicts"]:
		var fid := String(c["fam"])
		var v := Amphictyony.fam_value(state, fid)
		if v == 0 or Amphictyony.way_of(v) != String(c["way"]) or not Amphictyony.family_available(state, fid):
			continue
		if Laws.is_enacted(state, eid, String(c["law"])) and not sovereign(state, eid, fid):
			out.append(c)
	return out


## Lignes de stabilité d'empire (voir Stability.parts).
static func stability_parts(state: GameState, eid: int) -> Array:
	var out := []
	if not Amphictyony.founded(state):
		return out
	for c in conflicts(state, eid):
		out.append(["Nomos contre la loi %s" % String(Laws.law_def(String(c["law"])).get("label", c["law"])), int(poldata()["conflict_stability"])])
	return out


static func check_sovereign(state: GameState, eid: int, fid: String) -> String:
	if not Amphictyony.founded(state) or not Amphictyony.is_member(state, eid):
		return "il faut siéger"
	if not state.politics_on or not Laws.is_enacted(state, eid, "souverainete"):
		return "il faut la loi Souveraineté"
	if Amphictyony.family_def(fid).is_empty() or Amphictyony.fam_value(state, fid) == 0:
		return "aucune résolution de cette famille en vigueur"
	if sovereign(state, eid, fid):
		return "déjà invoquée"
	var left := AmphInst._cd_left(state, "sov", eid)
	if left > 0:
		return "encore %d jours avant de l'invoquer de nouveau" % left
	return ""


static func invoke_sovereign(state: GameState, eid: int, fid: String) -> void:
	var sd: Dictionary = poldata()["sovereign"]
	var m: Dictionary = (_a(state)["sov"] as Dictionary).get(str(eid), {})
	m[fid] = state.tick + int(sd["days"])
	_a(state)["sov"][str(eid)] = m
	AmphInst._set_cd(state, "sov", eid, int(sd["cd"]))
	state.relic_rev += 1
	for o in Amphictyony.members(state):
		if o != eid:
			Diplomacy.remember(state, o, eid, "amph_sovereign")
	state.add_chronicle("%s invoque sa souveraineté : pendant un an, les résolutions « %s » ne le lient plus. Murmures sous la voûte." % [
			_name(state, eid), String(Amphictyony.family_def(fid)["label"])], Espionage.public_to(state, _audience(state)))


# --- Religion ----------------------------------------------------------------------------------------

## Une guerre sainte : l'assemblée se réunit d'elle-même si rien ne siège.
static func on_holy_war(state: GameState, a: int, b: int) -> void:
	if not Amphictyony.founded(state) or AmphInst.special_on(state) or AmphInst.coal_on(state):
		return
	var trigs: Array = _a(state)["trig"]
	for i in range(trigs.size() - 1, -1, -1):
		var t: Dictionary = trigs[i]
		if String(t["kind"]) == "holy_war" and int(t["a"]) == a and int(t["b"]) == b and not bool(t["used"]):
			AmphInst.open_special(state, t, -1)
			return


## Conclave : deux théocraties de même foi d'État.
static func conclave(state: GameState, a: int, b: int) -> bool:
	if not state.faith_on or a == b:
		return false
	var ea := state.get_empire(a)
	var eb := state.get_empire(b)
	if ea == null or eb == null:
		return false
	if String(FactionTraits.species(ea.faction()).get("gouvernement", "")) != "theocratie" or String(FactionTraits.species(eb.faction()).get("gouvernement", "")) != "theocratie":
		return false
	return Faiths.has_state_faith(state, a) and Faiths.state_faith(state, a) == Faiths.state_faith(state, b)


## Fin d'une séance ordinaire : courants poussés, Conclave.
static func on_close(state: GameState, p: Dictionary, votes: Dictionary, passed: bool) -> void:
	if passed:
		_push_way(state, p, votes)
	var ks := votes.keys()
	ks.sort()
	for x in ks:
		for y in ks:
			if int(x) < int(y) and int(votes[x]) != 0 and int(votes[x]) == int(votes[y]) and conclave(state, int(x), int(y)):
				Diplomacy.remember(state, int(x), int(y), "amph_conclave")
				Diplomacy.remember(state, int(y), int(x), "amph_conclave")


# --- Effets, mois et jours ---------------------------------------------------------------------------

static func voix_pct(state: GameState, eid: int) -> int:
	return int(pdata()["voix_pct"]) if imperator(state) == eid else 0


static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	_imp_monthly(state, added)
	_dip_monthly(state, added)
	if state.politics_on:
		for m in Amphictyony.members(state):
			Politics.on_act(state, m, "amph_member")
	var gf := String(_a(state).get("gfaith", ""))
	if gf != "" and state.faith_on:
		FaithWars.add_zeal(state, gf, int(data()["religion"]["zeal_month"]))
	var sov: Dictionary = _a(state)["sov"]
	for k in sov.keys():
		var m: Dictionary = sov[k]
		for f in m.keys():
			if int(m[f]) <= state.tick:
				m.erase(f)
				state.relic_rev += 1
		if m.is_empty():
			sov.erase(k)


static func daily(state: GameState, added: Array[Dictionary]) -> void:
	if chan_on(state):
		if state.tick >= int(chan(state)["end"]):
			_close_chan(state, added)
	elif dip_enabled(state) and state.tick >= int(cdata()["from_day"]) and posmod(state.tick - int(cdata()["from_day"]), int(cdata()["every"])) == 0 \
			and (dip(state).is_empty()):
		_open_chan(state, added)


# --- Ordres (« amph_act ») ---------------------------------------------------------------------------

static func check_act(state: GameState, eid: int, act: String, x: int, _y: int, s: String) -> String:
	match act:
		"submit":
			return check_submit(state, eid)
		"rebel":
			return check_rebel(state, eid)
		"cvote":
			return check_cvote(state, eid, x)
		"refuse":
			return check_refuse(state, eid)
		"accept":
			return check_accept(state, eid)
		"sovereign":
			return check_sovereign(state, eid, s)
		"anathema":
			return check_anathema(state, eid, x)
		"duel":
			return check_duel(state, eid)
	return "ordre inconnu"


static func act(state: GameState, eid: int, act_id: String, x: int, _y: int, s: String) -> void:
	match act_id:
		"submit":
			submit(state, eid)
		"rebel":
			rise(state, eid)
		"cvote":
			cvote(state, eid, x)
		"refuse":
			refuse(state, eid)
		"accept":
			accept(state, eid)
		"sovereign":
			invoke_sovereign(state, eid, s)
		"anathema":
			anathema(state, eid, x)
		"duel":
			duel(state, eid)
