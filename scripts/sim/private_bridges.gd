class_name PrivateBridges
extends RefCounted
## Économie privée : ombres et ponts avec les autres piliers (étude « Économie privée », lot 3).
## Syndicats du crime (prop. 26), espionnage industriel (prop. 27), corruption : fuite fiscale et
## comptabilité créative (prop. 31), guerre : ouvrir les marchés (prop. 30), cour : maisons marchandes
## et dirigeants ruinés devenus héros (prop. 32). Les repaires vivent dans state.private["crime"] :
## {"système": {"o": empire hôte, "t": jour de naissance}}.
## Aucun aléatoire hors hachage déterministe, uniquement des entiers.

const MERCHANT_VOCS := ["marchands", "libres_marchands", "consortium", "cartel"]


static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "private_b"] + parts))


static func _c(key: String) -> int:
	return Private.c_int("crime", key)


static func _hx(state: GameState) -> Dictionary:
	if not state.private.has("hx"):
		state.private["hx"] = {}
	return state.private["hx"]


# --- Corruption (prop. 31) -------------------------------------------------------------------------

## Part de l'impôt privé détournée par la corruption : moitié de la corruption moyenne, en %.
static func tax_leak(state: GameState, eid: int, tax: int) -> int:
	if tax <= 0 or state.admin.is_empty() or not Admin.has_corruption(state, eid):
		return 0
	if bool(Private.talent(state, eid).get("no_leak", false)):
		return 0
	@warning_ignore("integer_division")
	return tax * mini(50, Admin.average_corruption(state, eid) / 2) / 100


## Sources de corruption d'un système : repaires des syndicats, comptabilité créative à la capitale.
static func corruption_parts(state: GameState, eid: int, sid: int) -> Array:
	var out := []
	if state.private.is_empty():
		return out
	var den: Dictionary = (state.private.get("crime", {}) as Dictionary).get(str(sid), {})
	if not den.is_empty() and not tolerated(state, eid):
		out.append(["Repaire d'un syndicat du crime", _c("corruption")])
	if int((state.private.get("cr", {}) as Dictionary).get(str(eid), 0)) > state.tick and FactionTraits.capital_system(state, eid) == sid:
		out.append(["Comptabilité créative", Private.c_int("creative", "corruption")])
	return out


static func check_creative(state: GameState, eid: int) -> String:
	var en := Private.entry(state, eid)
	if Private.planned(state, eid):
		return "l'économie planifiée n'a pas de comptables privés"
	if state.tick - int(en.get("cr_day", -100000)) < Private.c_int("creative", "cooldown_days"):
		return "une fois par an au plus"
	if int(en.get("tax", 0)) <= 0:
		return "le privé n'a payé aucun impôt le mois dernier"
	return ""


## Comptabilité créative : quelques mois d'impôt d'avance (pris dans la caisse privée), contre de la
## corruption à la capitale pendant un an.
static func creative(state: GameState, eid: int) -> void:
	var en := Private._w(state, eid)
	var n := int(en.get("tax", 0)) * Private.c_int("creative", "months")
	n = mini(n, maxi(0, int(en["cap"])))
	en["cap"] = int(en["cap"]) - n
	var e := state.get_empire(eid)
	e.resources["energy"] = int(e.resources.get("energy", 0)) + n
	en["cr_day"] = state.tick
	(state.private["cr"] as Dictionary)[str(eid)] = state.tick + Private.c_int("creative", "days")
	state.add_chronicle("%s : les comptables trouvent %d énergie d'impôt « en avance ». Personne ne pose de question, surtout pas les comptables." % [
			e.short_name(), n], Espionage.private_to(state, [eid]))


# --- Syndicats du crime (prop. 26) -----------------------------------------------------------------

static func tolerated(state: GameState, eid: int) -> bool:
	return bool(Private.talent(state, eid).get("crime_tolerant", false))


static func dens_of(state: GameState, eid: int) -> Array[int]:
	var out: Array[int] = []
	if state.private.is_empty():
		return out
	for k in state.private.get("crime", {}):
		if int(state.private["crime"][k]["o"]) == eid:
			out.append(int(k))
	out.sort()
	return out


static func has_den(state: GameState, sid: int) -> bool:
	return not state.private.is_empty() and (state.private.get("crime", {}) as Dictionary).has(str(sid))


## Ce qu'un repaire vole chaque mois à l'hôte.
static func den_theft(state: GameState, sid: int) -> int:
	@warning_ignore("integer_division")
	return _c("steal") + Admin.corruption(state, sid) / maxi(1, _c("steal_div"))


static func _near_port(state: GameState, sid: int) -> bool:
	for p in Pirates.port_ids(state):
		if int(FactionTraits.jumps_from(state.galaxy, p).get(sid, 99)) <= _c("from_free"):
			return true
	return false


static func _crime(state: GameState, added: Array[Dictionary]) -> void:
	var crime: Dictionary = state.private["crime"]
	var month := state.tick / 30
	# Repaires existants : vol, essaimage, fermeture, perte du système.
	var keys := crime.keys()
	keys.sort_custom(func(x: Variant, y: Variant) -> bool: return int(x) < int(y))
	for k in keys:
		var sid := int(k)
		var den: Dictionary = crime[k]
		var host := state.system_owner(sid)
		if host < 0 or not Private.applies(state, host):
			crime.erase(k)
			continue
		den["o"] = host
		var e := state.get_empire(host)
		if tolerated(state, host):
			e.resources["energy"] = int(e.resources.get("energy", 0)) + _c("tolerated")
		else:
			var steal := mini(den_theft(state, sid), maxi(0, int(e.resources.get("energy", 0))))
			e.resources["energy"] = int(e.resources.get("energy", 0)) - steal
		var close := _c("close_pct") if Admin.corruption(state, sid) <= 0 else 0
		if not state.admin.is_empty() and Admin.effort(state, host) == "enquete":
			close = _c("close_inquiry")
		if close > 0 and _h(state, ["close", sid, month]) % 100 < close:
			crime.erase(k)
			if not e.is_ai():
				added.append(state.add_chronicle("Le syndicat de %s plie bagage : plus personne à soudoyer. Les tripots deviennent des salons de thé." % state.galaxy.systems[sid].system_name, Espionage.private_to(state, [host], sid)))
			continue
		# Essaimage, une fois l'an (au jour anniversaire, au mois près).
		if (state.tick - int(den["t"])) % 360 < 30 and state.tick > int(den["t"]) and _h(state, ["spread", sid, month]) % 100 < _c("spread_pct"):
			for nb in state.galaxy.systems[sid].neighbors:
				if state.system_owner(nb) == host and not crime.has(str(nb)) and Admin.corruption(state, nb) >= _c("spread_cor"):
					crime[str(nb)] = {"o": host, "t": state.tick}
					break
	# Naissance : le système le plus corrompu, ou proche d'un port franc ; au plus un par an et par empire.
	for e in state.empires:
		if not Private.applies(state, e.id):
			continue
		var en := Private._w(state, e.id)
		if state.tick - int(en.get("crime_day", -100000)) < 360:
			continue
		if _h(state, ["birth", e.id, month]) % 100 >= _c("birth_pct"):
			continue
		var best := -1
		var bv := -1
		for sid in Stability.systems_of(state, e.id):
			if crime.has(str(sid)) or sid == FactionTraits.capital_system(state, e.id):
				continue
			var cor := Admin.corruption(state, sid)
			var ok := (not state.admin.is_empty() and Admin.has_corruption(state, e.id) and cor >= _c("birth_cor")) or _near_port(state, sid)
			if ok and cor > bv:
				bv = cor
				best = sid
		if best < 0:
			continue
		crime[str(best)] = {"o": e.id, "t": state.tick}
		en["crime_day"] = state.tick
		if not e.is_ai():
			added.append(state.add_chronicle("Un syndicat du crime s'installe à %s : tripots, contrebande et « assurances ». Les commerçants paient, en souriant jaune." % state.galaxy.systems[best].system_name, Espionage.private_to(state, [e.id], best)))


static func check_raid(state: GameState, eid: int, sid: int) -> String:
	if not has_den(state, sid) or state.system_owner(sid) != eid:
		return "aucun repaire dans ce système à vous"
	if int(state.get_empire(eid).resources.get("influence", 0)) < _c("raid_influence"):
		return "il faut %d influence" % _c("raid_influence")
	return ""


## Descente de police : coûte de l'influence, réussit raid_pct % du temps.
static func raid(state: GameState, eid: int, sid: int) -> void:
	var e := state.get_empire(eid)
	e.resources["influence"] = int(e.resources.get("influence", 0)) - _c("raid_influence")
	var ok := _h(state, ["raid", sid, state.tick]) % 100 < _c("raid_pct")
	var name := state.galaxy.systems[sid].system_name
	if ok:
		(state.private["crime"] as Dictionary).erase(str(sid))
		state.add_chronicle("Descente de police à %s : le syndicat est démantelé. On retrouve le parrain dans un placard à balais, l'air vexé." % name, Espionage.private_to(state, [eid], sid))
	else:
		state.add_chronicle("Descente de police à %s : les lieux sont vides, le café encore chaud. Quelqu'un a prévenu." % name, Espionage.private_to(state, [eid], sid))


static func confidence_parts(state: GameState, eid: int) -> Array:
	var out := []
	var n := dens_of(state, eid).size()
	if n > 0 and not tolerated(state, eid):
		out.append(["Syndicats du crime", -2 * mini(n, 5)])
	if int(_hx(state).get("rum:%d" % eid, 0)) > state.tick:
		out.append(["Rumeur de fraude", Private.c_int("espionage", "rumor_pr") * 2 / 3])
	return out


# --- Compagnies : cour, espionnage (props 27, 32) ----------------------------------------------

static func company_parts(state: GameState, c: Dictionary) -> Array:
	var out := []
	var sp: Dictionary = c.get("sp", {})
	if not sp.is_empty() and int(sp.get("until", 0)) > state.tick and int(sp.get("v", 0)) != 0:
		out.append([String(sp.get("why", "Espionnage industriel")), int(sp["v"])])
	var hid := int(c.get("house", -1))
	if hid >= 0 and not state.court.is_empty():
		var h := Court.house(state, int(c["o"]), hid)
		if not h.is_empty():
			out.append(["Aux mains de %s" % String(h.get("name", "?")), 5 if Court.serves(h) else -5])
	return out


static func _mark(state: GameState, c: Dictionary, v: int, why: String) -> void:
	var sp: Dictionary = c.get("sp", {})
	var cur := int(sp.get("v", 0)) if int(sp.get("until", 0)) > state.tick else 0
	c["sp"] = {"v": clampi(cur + v, -50, 30), "until": state.tick + 720, "why": why}
	c["pr"] = clampi(int(c["pr"]) + v, 0, 100)


## Une Maison marchande prend la compagnie qui naît (si elle n'en tient pas déjà une).
static func on_founded(state: GameState, eid: int, c: Dictionary) -> void:
	if state.court.is_empty() or not Court.applies(state, eid):
		return
	var taken := {}
	for o in Private.companies_of(state, eid):
		taken[int(o.get("house", -1))] = true
	for h: Dictionary in Court.houses(state, eid):
		if MERCHANT_VOCS.has(String(h.get("voc", ""))) and not taken.has(int(h["id"])):
			c["house"] = int(h["id"])
			return


static func favor_parts(state: GameState, eid: int, h: Dictionary) -> Array:
	var out := []
	if not Private.full(state):
		return out
	for c in Private.companies_of(state, eid):
		if int(c.get("house", -1)) != int(h["id"]):
			continue
		if bool(c.get("nat", false)):
			out.append(["Sa compagnie nationalisée (%s)" % String(c["n"]), -20])
		elif int(c["pr"]) >= 60:
			out.append(["Sa compagnie prospère (%s)" % String(c["n"]), 10])
		elif int(c["pr"]) < 30:
			out.append(["Sa compagnie périclite (%s)" % String(c["n"]), -5])
	return out


## Faillite : le dirigeant ruiné rejoint le conseil, s'il y a de la place (prop. 32).
static func on_ruin(state: GameState, eid: int, c: Dictionary) -> void:
	var d: Dictionary = c.get("dir", {})
	if d.is_empty() or Heroes.ids_of(state, eid).size() >= Heroes.cap(state, eid):
		return
	var cand := Heroes.make_candidate(state, eid, "intendant", ["ruin", int(c["id"]), state.tick])
	cand["name"] = String(d["name"])
	if String(d.get("portrait", "")) != "":
		cand["portrait"] = String(d["portrait"])
	Heroes.recruit(state, eid, cand)
	var e := state.get_empire(eid)
	if not e.is_ai():
		state.add_chronicle("%s, ruiné, offre ses talents au conseil de %s : « J'ai beaucoup appris. Surtout ce qu'il ne faut pas faire. »" % [
				String(d["name"]), e.short_name()], Espionage.private_to(state, [eid]))


# --- Guerre : ouvrir les marchés (prop. 30) ---------------------------------------------------------

static func open_markets(state: GameState, winner: int, loser: int) -> Array[String]:
	var out: Array[String] = []
	if state.private.is_empty() or not Private.applies(state, winner) or not Private.applies(state, loser):
		return out
	if not Diplomacy.has_trade(state, winner, loser) and not Combat.at_war(state, winner, loser):
		Diplomacy.sign_treaty(state, winner, loser, Diplomacy.TRADE)
		out.append("accord commercial")
	(state.private["mk"] as Dictionary)["%d>%d" % [winner, loser]] = state.tick + 3600
	var best: Dictionary = {}
	for c in Private.companies_of(state, winner):
		if not bool(c.get("nat", false)) and (best.is_empty() or int(c["pr"]) > int(best["pr"])):
			best = c
	if best.is_empty():
		return out
	var cols := []
	for c in Private.colonies_of(state, loser):
		if c.is_colony() and not (state.private["br"] as Dictionary).has(str(c.planet_id)):
			cols.append(c)
	cols.sort_custom(func(x: Colony, y: Colony) -> bool: return x.population > y.population or (x.population == y.population and x.planet_id < y.planet_id))
	var n := 0
	for c: Colony in cols:
		if n >= 2:
			break
		(state.private["br"] as Dictionary)[str(c.planet_id)] = {"c": int(best["id"]), "o": winner, "t": state.tick}
		n += 1
	if n > 0:
		out.append("%d filiale%s de %s" % [n, "s" if n > 1 else "", String(best["n"])])
	return out


# --- Espionnage industriel (prop. 27) ---------------------------------------------------------------

static func _best(state: GameState, eid: int) -> Dictionary:
	var best: Dictionary = {}
	for c in Private.companies_of(state, eid):
		if not bool(c.get("nat", false)) and (best.is_empty() or int(c["pr"]) > int(best["pr"])):
			best = c
	return best


static func _weakest(state: GameState, eid: int, sec := "") -> Dictionary:
	var out: Dictionary = {}
	for c in Private.companies_of(state, eid):
		if bool(c.get("nat", false)):
			continue
		if sec != "" and String(c["sec"]) == sec:
			return c
		if out.is_empty() or int(c["pr"]) < int(out["pr"]):
			out = c
	return out


static func spy_check(state: GameState, a: int, b: int, op_id: String) -> String:
	if state.private.is_empty() or not Private.full(state) or not Private.applies(state, b):
		return "l'économie privée complète n'est pas en jeu"
	if _best(state, b).is_empty():
		return "il n'a aucune compagnie privée"
	if (op_id == "voler_procede" or op_id == "debaucher_dirigeant") and (not Private.applies(state, a) or _weakest(state, a).is_empty()):
		return "il vous faut une compagnie pour en profiter"
	if op_id == "debaucher_dirigeant" and (_best(state, b).get("dir", {}) as Dictionary).is_empty():
		return "sa meilleure compagnie n'a pas de dirigeant"
	return ""


static func spy_apply(state: GameState, a: int, b: int, o: Dictionary) -> String:
	var sc: Dictionary = Private.cfg("espionage")
	var theirs := _best(state, b)
	if theirs.is_empty():
		return "ses compagnies ont fermé entre-temps : rien à prendre."
	state.relic_rev += 1
	match String(o["id"]):
		"voler_procede":
			var ours := _weakest(state, a, String(theirs["sec"]))
			if ours.is_empty():
				return "nos ingénieurs ont les plans, mais plus d'usine pour s'en servir."
			_mark(state, ours, int(sc["steal_pr"]), "Procédé volé")
			_mark(state, theirs, -int(sc["steal_loss"]), "Procédé volé par un concurrent")
			return "les plans de %s sont chez %s : nos ingénieurs jurent les avoir inventés." % [String(theirs["n"]), String(ours["n"])]
		"saboter_compagnie":
			_mark(state, theirs, int(sc["sabotage_pr"]), "Sabotage")
			return "un entrepôt de %s a brûlé, puis l'audit est tombé. Mauvaise semaine." % String(theirs["n"])
		"debaucher_dirigeant":
			var ours2 := _weakest(state, a)
			if ours2.is_empty():
				return "le dirigeant est prêt à partir, mais nous n'avons plus de fauteuil à lui offrir."
			var d: Dictionary = theirs["dir"]
			ours2["dir"] = d.duplicate()
			theirs["dir"] = Private.make_director(state, b, ["poach", int(theirs["id"]), state.tick])
			_mark(state, ours2, int(sc["poach_pr"]), "Dirigeant débauché à la concurrence")
			return "%s quitte %s pour diriger %s. Le pont d'or était solide." % [String(d.get("name", "?")), String(theirs["n"]), String(ours2["n"])]
		"rumeur_actions":
			for c in Private.companies_of(state, b):
				if not bool(c.get("nat", false)):
					_mark(state, c, int(sc["rumor_pr"]), "Rumeur de fraude")
			_hx(state)["rum:%d" % b] = state.tick + 360
			return "une rumeur de fraude fait plonger toutes ses compagnies. Les petits porteurs vendent, les gros rachètent."
	return ""


# --- Mois ----------------------------------------------------------------------------------------

static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	_crime(state, added)
	var hx := _hx(state)
	for k in hx.keys():
		if int(hx[k]) <= state.tick:
			hx.erase(k)
	# Les compagnies dont la Maison a disparu redeviennent indépendantes.
	for c in Private.all_companies(state):
		var hid := int(c.get("house", -1))
		if hid >= 0 and (state.court.is_empty() or Court.house(state, int(c["o"]), hid).is_empty()):
			c["house"] = -1
