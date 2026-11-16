class_name FinanceBridges
extends RefCounted
## Ponts du pilier Fiscalité et dette publique (étude 2026-11-16, propositions 5 à 7 et 26 à 31) :
## révolte fiscale (grève), doléances « Baisser les impôts » et « Rembourser la dette », courants
## politiques poussés par les crans, Grandes Maisons (exemption, créancières, répudiation, Maison
## usurière), banquier en fuite, Grand Krach (taux, plafond, inflation) et Banque des Étoiles, Bourse
## galactique, Koinon (renflouement), Grand Intendant et héros Fiscaliste au conseil, Banque centrale,
## espionnage (rumeur, comptes maquillés, créance rachetée), motif de guerre « Recouvrement »,
## haut fait « Budget à l'équilibre », surnoms de souverain.
## État : state.finance (voir Finance) ; dans l'entrée d'empire : "gt"/"gd" (fin de la doléance impôt /
## dette), "gt_cd"/"gd_cd", "gfx" {"t": {"v", "end"}, "d": {...}}, "kr" (Krach déjà compté), "kb" (dernier
## renflouement du Koinon).

const YEAR := 360


static func _cfg(section: String) -> Dictionary:
	return Finance.data().get(section, {})


static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "finance_ponts"] + parts))


static func _month(state: GameState) -> int:
	@warning_ignore("integer_division")
	return state.tick / int(GameData.rules()["month_days"])


# --- Plafond, taux, inflation ---------------------------------------------------------------------

static func has_bank(state: GameState, eid: int) -> bool:
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == eid and c.buildings.has("banque_centrale"):
			return true
	return false


## La Banque des Étoiles a ouvert ses guichets (le Grand Krach est passé).
static func star_bank_open(state: GameState) -> bool:
	return not state.crisis.is_empty() and (state.crisis.get("done", []) as Array).has("krach") \
			and String((state.crisis.get("cur", {}) as Dictionary).get("kind", "")) != "krach"


## Points de % sur le plafond de crédit : Krach, Banque des Étoiles, Banque centrale.
static func cap_pct(state: GameState, eid: int) -> int:
	var bc := _cfg("bridges")
	var n := 0
	if not state.crisis.is_empty() and CrisisKinds.infected(state, eid):
		n += int(bc["krach_cap_pct"])
	if star_bank_open(state):
		n += int(bc["banque_cap_pct"])
	if Finance.full(state) and has_bank(state, eid):
		n += 25
	return n


## Lignes du plafond (écran Trésor).
static func cap_lines(state: GameState, eid: int) -> Array:
	var bc := _cfg("bridges")
	var out := []
	if not state.crisis.is_empty() and CrisisKinds.infected(state, eid):
		out.append(["Grand Krach", int(bc["krach_cap_pct"])])
	if star_bank_open(state):
		out.append(["Banque des Étoiles", int(bc["banque_cap_pct"])])
	if Finance.full(state) and has_bank(state, eid):
		out.append(["Banque centrale", 25])
	return out


## Points de % sur les intérêts : Krach, Bourse galactique, Grand Intendant, Fiscalistes au conseil, Banque centrale.
static func rate_pct(state: GameState, eid: int) -> int:
	var n := 0
	for l in rate_lines(state, eid):
		n += int(l[1])
	return n


static func rate_lines(state: GameState, eid: int) -> Array:
	var bc := _cfg("bridges")
	var out := []
	if not state.crisis.is_empty() and CrisisKinds.infected(state, eid):
		out.append(["Grand Krach", int(bc["krach_rate_pct"])])
	var host := Goods.bourse_host(state)
	if host == eid:
		out.append(["Hôte de la Bourse galactique", int(bc["bourse_rate_pct"])])
	elif host >= 0 and Goods.common_market(state) and (not state.amph_on or Amphictyony.in_common_market(state, eid)):
		@warning_ignore("integer_division")
		out.append(["Marché commun de la Bourse", int(bc["bourse_rate_pct"]) / 2])
	if not state.court.is_empty() and Court.applies(state, eid):
		var apt := Court.office_apt(state, eid, "intendant")
		if apt > 0:
			out.append([Court.office_label(state, eid, "intendant"), apt * int(bc["intendant_rate"])])
	if not state.heroes.is_empty():
		var fisc := 0
		for h in Heroes.council(state, eid):
			if (h.get("traits", []) as Array).has("fiscaliste"):
				fisc += 1
		if fisc > 0:
			out.append(["Argentier au conseil (Fiscaliste)", -10 * fisc])
	if Finance.full(state) and has_bank(state, eid):
		out.append(["Banque centrale", -10])
	return out


## Décrue d'inflation en plus (Banque centrale : deux fois plus vite).
static func decay_bonus(state: GameState, eid: int) -> int:
	return Finance.d_int("inflation", "decay") if Finance.full(state) and has_bank(state, eid) else 0


## Part (en %) de l'impôt supplémentaire perdue par la corruption locale (« Fuite fiscale »).
static func leak_pct(state: GameState, eid: int, sid: int) -> int:
	if state.admin.is_empty() or not Admin.has_corruption(state, eid):
		return 0
	var c := Admin.corruption(state, sid)
	if c <= 0:
		return 0
	var cut := 0
	if not state.court.is_empty() and Court.applies(state, eid):
		cut = mini(50, Court.office_apt(state, eid, "intendant") * 10)
	@warning_ignore("integer_division")
	return c * (100 - cut) / 100


# --- Stabilité d'empire : suites des doléances ------------------------------------------------------

static func empire_stability_parts(state: GameState, eid: int) -> Array:
	var out := []
	var gfx: Dictionary = Finance.entry(state, eid).get("gfx", {})
	for k in ["t", "d"]:
		var g: Dictionary = gfx.get(k, {})
		if not g.is_empty() and int(g.get("end", 0)) > state.tick:
			var what := "Baisser les impôts" if k == "t" else "Rembourser la dette"
			out.append(["Doléance « %s » %s" % [what, "entendue" if int(g["v"]) > 0 else "ignorée"], int(g["v"])])
	return out


# --- Grandes Maisons ----------------------------------------------------------------------------

static func _hk(eid: int, hid: int) -> String:
	return "%d:%d" % [eid, hid]


## Énergie des fiefs d'une Maison (points de %) : exemption accordée, Maison furieuse qui ne paie plus.
static func house_energy_pct(state: GameState, owner: int, sid: int) -> int:
	if state.court.is_empty():
		return 0
	var h := Court.fief_house(state, sid, owner)
	if h.is_empty():
		return 0
	var cc := _cfg("court")
	var n := 0
	if int((state.finance["hx"] as Dictionary).get(_hk(owner, int(h["id"])), 0)) > state.tick:
		n += int(cc["exempt_pct"])
	if Court.tier_id(h) == "furieuse":
		n += int(cc["furious_pct"])
	return n


## Faveur d'une Maison : créancière, exemption accordée ou refusée, dette répudiée.
static func favor_parts(state: GameState, eid: int, h: Dictionary) -> Array:
	var out := []
	if not Finance.full(state):
		return out
	var hid := int(h["id"])
	var cc := _cfg("court")
	var n := 0
	for l: Dictionary in Finance.loans(state, eid):
		if String(l["l"]) == "house" and int(l["w"]) == hid:
			n += 1
	if n > 0:
		out.append(["Créancière de la couronne", n * int(_cfg("creditors")["house_favor"])])
	var k := _hk(eid, hid)
	if int((state.finance["hx"] as Dictionary).get(k, 0)) > state.tick:
		out.append(["Exemption fiscale accordée", int(cc["exempt_favor"])])
	if int((state.finance["hr"] as Dictionary).get(k, 0)) > state.tick:
		out.append(["Exemption fiscale refusée", int(cc["refuse_favor"])])
	if int((state.finance["hrep"] as Dictionary).get(k, 0)) > state.tick:
		out.append(["Dette répudiée", int(cc["repudiate_favor"])])
	return out


## Une Maison créancière lésée : faillite (humeur -30) ou répudiation (faveur -100 pendant la cote D).
static func house_wronged(state: GameState, eid: int, hid: int, repudiated: bool) -> void:
	if state.court.is_empty() or hid < 0:
		return
	if repudiated:
		(state.finance["hrep"] as Dictionary)[_hk(eid, hid)] = state.tick + Finance.d_int("rating", "history_days")
		Court.refresh(state, eid)
	else:
		Court.adjust(state, eid, hid, -30)


# --- Haut fait, guerre --------------------------------------------------------------------------

## Années sans dette (haut fait « Budget à l'équilibre »), 0 sous le nombre de systèmes requis.
static func balanced_years(state: GameState, eid: int) -> int:
	if state.finance.is_empty() or Stability.systems_of(state, eid).size() < int(_cfg("deed")["min_systems"]):
		return 0
	var since: Variant = (state.finance.get("clean", {}) as Dictionary).get(str(eid))
	if since == null:
		return 0
	@warning_ignore("integer_division")
	return (state.tick - int(since)) / YEAR


## Motif « Recouvrement » : b a fait défaut envers a (faillite ou répudiation) depuis moins de 5 ans.
static func debt_casus(state: GameState, a: int, b: int) -> bool:
	if not Finance.full(state):
		return false
	var d: Variant = (state.finance.get("def", {}) as Dictionary).get("%d>%d" % [b, a])
	return d != null and state.tick - int(d) < 5 * YEAR


# --- Mois ---------------------------------------------------------------------------------------

static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	for e in state.empires:
		if e.eliminated or e.is_npc() or not Finance.applies(state, e.id):
			continue
		var en := Finance._w(state, e.id)
		_krach(state, e, en)
		_revolt(state, e, en, added)
		_grievances(state, e, en, added)
		_frugal(state, e)
		if Finance.full(state):
			_push_currents(state, e)
			_houses(state, e, en, added)
			_banker(state, e, en, added)
			_koinon(state, e, en, added)


static func _krach(state: GameState, e: Empire, en: Dictionary) -> void:
	if state.crisis.is_empty():
		return
	if CrisisKinds.infected(state, e.id):
		if int(en.get("kr", 0)) == 0:
			en["kr"] = 1
			Finance.add_inflation(state, e.id, Finance.d_int("inflation", "krach"))
	elif en.has("kr"):
		en.erase("kr")


## Système le moins stable de l'empire (-1 sans système).
static func _least_stable(state: GameState, eid: int) -> int:
	var best := -1
	var bv := 1000
	for sid in Stability.systems_of(state, eid):
		var v := Stability.value(state, sid) if Stability.applies(state, eid) else 50
		if v < bv:
			bv = v
			best = sid
	return best


static func _revolt(state: GameState, e: Empire, en: Dictionary, added: Array[Dictionary]) -> void:
	if bool(Finance.talent(state, e.id).get("no_revolt", false)):
		return
	var month := _month(state)
	if posmod(month + e.id, 12) != 3 or int(en.get("rv_cd", 0)) > state.tick:
		return
	var rc := _cfg("revolt")
	var ti := Finance.tax_index(Finance.tax(state, e.id))
	var sid := _least_stable(state, e.id)
	if sid < 0:
		return
	var crushed := ti >= 4 and int(en.get("crush", -1)) >= 0 and state.tick - int(en["crush"]) >= int(rc["crush_days"])
	var restless := ti >= 3 and Stability.applies(state, e.id) and Stability.value(state, sid) < int(rc["low_stability"])
	if not (crushed or restless):
		return
	if _h(state, ["revolte", e.id, month]) % 100 >= int(rc["chance_pct"]):
		return
	(state.finance["strike"] as Dictionary)[str(sid)] = state.tick + int(rc["strike_days"])
	en["rv_cd"] = state.tick + int(rc["cooldown_days"])
	added.append(state.add_chronicle("Révolte fiscale à %s : les registres brûlent, les docks font grève. La production tombe de moitié." % state.galaxy.systems[sid].system_name,
			Espionage.private_to(state, [e.id], sid)))
	Events.push(state, e.id, "finance_revolte", {"system": sid}, added)


static func _grievances(state: GameState, e: Empire, en: Dictionary, added: Array[Dictionary]) -> void:
	if not state.politics_on or not Politics.applies(state, e.id) or bool(Finance.talent(state, e.id).get("no_revolt", false)):
		return
	var pc := _cfg("politics")
	var ti := Finance.tax_index(Finance.tax(state, e.id))
	var high := int(en.get("high", -1))
	var ratio := Finance.debt(state, e.id) * 100 / maxi(1, Finance.cap(state, e.id))
	# « Baisser les impôts »
	_grievance(state, e, en, "t", ti <= 2, ti >= 3 and high >= 0 and state.tick - high >= int(pc["tax_days"]),
			"Baisser les impôts", "revenir au cran Normal ou moins", added)
	# « Rembourser la dette »
	_grievance(state, e, en, "d", ratio < int(pc["debt_ok_pct"]), ratio > int(pc["debt_pct"]),
			"Rembourser la dette", "ramener la dette sous %d %% du plafond" % int(pc["debt_ok_pct"]), added)


static func _grievance(state: GameState, e: Empire, en: Dictionary, k: String, ok: bool, opens: bool, what: String, goal: String, added: Array[Dictionary]) -> void:
	var gfx: Dictionary = en.get("gfx", {})
	var end := int(en.get("g" + k, 0))
	if end > 0:
		if ok or end <= state.tick:
			en.erase("g" + k)
			en["g%s_cd" % k] = state.tick + YEAR
			gfx[k] = {"v": 5 if ok else -5, "end": state.tick + YEAR}
			en["gfx"] = gfx
			if not e.is_ai():
				var msg := "La doléance « %s » est entendue : %s respire (+5 stabilité pendant un an)." if ok else "La doléance « %s » est restée lettre morte : %s gronde (-5 stabilité pendant un an)."
				added.append(state.add_chronicle(msg % [what, e.short_name()], Espionage.private_to(state, [e.id])))
		return
	if opens and int(en.get("g%s_cd" % k, 0)) <= state.tick:
		en["g" + k] = state.tick + 2 * YEAR
		if not e.is_ai():
			added.append(state.add_chronicle("Doléance « %s » à %s : %s en deux ans, ou la colère montera." % [what, e.short_name(), goal], Espionage.private_to(state, [e.id])))


## Doléance fiscale en cours : jour de fin (0 si aucune) ; k = "t" (impôts) ou "d" (dette).
static func grievance_end(state: GameState, eid: int, k: String) -> int:
	return int(Finance.entry(state, eid).get("g" + k, 0))


static func _push_currents(state: GameState, e: Empire) -> void:
	if not state.politics_on or not Politics.applies(state, e.id):
		return
	var pc := _cfg("politics")
	var ti := Finance.tax_index(Finance.tax(state, e.id))
	var pts := int(pc["push"])
	var pushes := []
	if ti >= 3:
		pushes.append([Politics.index_of(String(pc["high_tax"])), pts * (ti - 2)])
	elif ti <= 1:
		pushes.append([Politics.index_of(String(pc["low_tax"])), pts * (2 - ti)])
	if Finance.pay(state, e.id) == "pleine":
		pushes.append([Politics.index_of(String(pc["full_pay"])), pts])
	if pushes.is_empty():
		return
	for sid in Stability.systems_of(state, e.id):
		for p in pushes:
			Politics.push(state, sid, int(p[0]), int(p[1]))


static func _frugal(state: GameState, e: Empire) -> void:
	if state.rulers.is_empty() or posmod(_month(state), 12) != 0:
		return
	if Finance.debt(state, e.id) == 0 and int(e.resources.get("energy", 0)) * 2 >= Finance.reserve(state, e.id):
		Rulers.note(state, e.id, "frugal")


## Exemption réclamée par une Maison qui tient des fiefs ; Maison usurière quand la dette pèse.
static func _houses(state: GameState, e: Empire, en: Dictionary, added: Array[Dictionary]) -> void:
	if state.court.is_empty() or not Court.applies(state, e.id):
		return
	var month := _month(state)
	if posmod(month + e.id, 12) != 7:
		return
	var cc := _cfg("court")
	var cands := []
	var lenders := []
	for h: Dictionary in Court.houses(state, e.id):
		var hid := int(h["id"])
		var k := _hk(e.id, hid)
		if not Court.fiefs_of(state, e.id, hid).is_empty() and not (state.finance["hx"] as Dictionary).has(k) and not (state.finance["hr"] as Dictionary).has(k):
			cands.append(hid)
		if Court.serves(h) and not (state.finance["hrep"] as Dictionary).has(k):
			lenders.append(hid)
	if not cands.is_empty() and _h(state, ["exemption", e.id, month]) % 100 < int(cc["exempt_chance_pct"]):
		Court.push_card(state, e.id, "finance_exemption", {"h": int(cands[_h(state, ["qui", e.id, month]) % cands.size()])}, added)
		return
	var al := Finance.auto_loan(state, e.id)
	if not lenders.is_empty() and not al.is_empty() and int(al["p"]) >= 200 and Finance.crisis_stage(state, e.id) >= 1 \
			and _h(state, ["usuriers", e.id, month]) % 100 < 50:
		Court.push_card(state, e.id, "finance_usuriers", {"h": int(lenders[_h(state, ["usurier", e.id, month]) % lenders.size()])}, added)


## Le banquier s'enfuit avec une part du trésor (empire endetté et mal noté).
static func _banker(state: GameState, e: Empire, en: Dictionary, added: Array[Dictionary]) -> void:
	var month := _month(state)
	if posmod(month + e.id, 12) != 9 or Finance.debt(state, e.id) <= 0:
		return
	if Finance.grade_index(Finance.grade(state, e.id)) < 4 or _h(state, ["banquier", e.id, month]) % 100 >= 15:
		return
	@warning_ignore("integer_division")
	var n := mini(300, int(e.resources.get("energy", 0)) / 5)
	if n < 20:
		return
	e.resources["energy"] = int(e.resources.get("energy", 0)) - n
	Events.push(state, e.id, "finance_banquier", {"n": n}, added)


## Le Koinon renfloue un membre en crise de la dette (prêt fédéral sans intérêts).
static func _koinon(state: GameState, e: Empire, en: Dictionary, added: Array[Dictionary]) -> void:
	if state.koinon.is_empty() or not Koinon.is_member(state, e.id):
		return
	var bc := _cfg("bridges")
	if Finance.crisis_stage(state, e.id) < int(bc["koinon_stage"]) or state.tick - int(en.get("kb", -100000)) < int(bc["koinon_days"]):
		return
	var lid := Koinon.league_of(state, e.id)
	var l := Koinon.league(state, lid)
	var n := mini(int(bc["koinon_max"]), int(l.get("treasury", 0)))
	if n < 100:
		return
	l["treasury"] = int(l["treasury"]) - n
	Koinon._coh(state, lid, int(bc["koinon_coh"]))
	en["kb"] = state.tick
	(en["loans"] as Array).append({"id": Finance._next_id(state), "l": "koinon", "w": lid, "p": n, "r": 0, "m": Finance.d_int("loan", "months")})
	e.resources["energy"] = int(e.resources.get("energy", 0)) + n
	added.append(state.add_chronicle("%s renfloue %s : %d énergie sans intérêts, remboursables en cinq ans. La solidarité fédérale a un prix : la cohésion." % [
			String(l.get("name", "Le Koinon")), e.short_name(), n], Espionage.public_to(state, [e.id])))


# --- Cartes -------------------------------------------------------------------------------------

static func _note_house(state: GameState, eid: int, item: Dictionary) -> int:
	if state.court.is_empty():
		return -1
	return int(Court.note_of(state, eid, item).get("h", -1))


static func apply_fx(state: GameState, eid: int, item: Dictionary, fx: Dictionary, added: Array[Dictionary]) -> void:
	var sid := int(item.get("system", -1))
	var en := Finance._w(state, eid)
	match String(fx.get("act", "")):
		"lower_tax":
			var i := Finance.tax_index(Finance.tax(state, eid))
			if i > 0:
				en["tax"] = String(Finance.tax_defs()[i - 1]["id"])
				en["tax_day"] = state.tick
				state.relic_rev += 1
			(state.finance["strike"] as Dictionary).erase(str(sid))
		"end_strike":
			(state.finance["strike"] as Dictionary).erase(str(sid))
		"exempt":
			var hid := _note_house(state, eid, item)
			if hid >= 0:
				(state.finance["hx"] as Dictionary)[_hk(eid, hid)] = state.tick + int(_cfg("court")["exempt_days"])
				Court.refresh(state, eid)
		"refuse":
			var hid := _note_house(state, eid, item)
			if hid >= 0:
				(state.finance["hr"] as Dictionary)[_hk(eid, hid)] = state.tick + int(_cfg("court")["refuse_days"])
				Court.refresh(state, eid)
		"recover":
			var e := state.get_empire(eid)
			e.resources["energy"] = int(e.resources.get("energy", 0)) + int(item.get("n", 0))
		"rumor_self":
			(state.finance["rum"] as Dictionary)[str(eid)] = state.tick + int(_cfg("espionage")["rumor_days"])
		"house_buy":
			var hid := _note_house(state, eid, item)
			var al := Finance.auto_loan(state, eid)
			if hid >= 0 and not al.is_empty():
				@warning_ignore("integer_division")
				var r := Finance.rate_for(state, eid, "house", hid) * 3 / 2
				(en["loans"] as Array).erase(al)
				(en["loans"] as Array).append({"id": Finance._next_id(state), "l": "house", "w": hid, "p": int(al["p"]), "r": r, "m": Finance.d_int("loan", "months")})
				en["prog"] = maxi(0, int(en.get("prog", 0)) - 25)
				Court.refresh(state, eid)


static func fx_lines(state: GameState, eid: int, item: Dictionary, fx: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var cc := _cfg("court")
	match String(fx.get("act", "")):
		"lower_tax":
			out.append("Impôt baissé d'un cran, fin de la grève")
		"end_strike":
			out.append("Fin de la grève")
		"exempt":
			out.append("Faveur +%d ; énergie de ses fiefs %d %% pendant dix ans" % [int(cc["exempt_favor"]), int(cc["exempt_pct"])])
		"refuse":
			out.append("Faveur %d pendant trois ans" % int(cc["refuse_favor"]))
		"recover":
			out.append("Récupère %d énergie" % int(item.get("n", 0)))
		"rumor_self":
			out.append("Cote de crédit -1 cran pendant deux ans (les marchés doutent)")
		"house_buy":
			var al := Finance.auto_loan(state, eid)
			out.append("La dette courante (%d) devient un emprunt sur 5 ans à %s par mois ; crise de la dette -25" % [
					int(al.get("p", 0)), Finance.rate_label(Finance.rate_for(state, eid, "house", _note_house(state, eid, item)) * 3 / 2)])
	return out


static func fx_problem(state: GameState, eid: int, item: Dictionary, fx: Dictionary) -> String:
	if not Finance.applies(state, eid):
		return "pas de fiscalité"
	match String(fx.get("act", "")):
		"lower_tax":
			if bool(Finance.talent(state, eid).get("no_tax", false)):
				return "votre peuple ne lève pas d'impôt"
		"exempt", "refuse", "house_buy":
			if _note_house(state, eid, item) < 0 or Court.house(state, eid, _note_house(state, eid, item)).is_empty():
				return "cette Maison n'est plus là"
			if String(fx["act"]) == "house_buy" and Finance.auto_loan(state, eid).is_empty():
				return "plus de dette courante à racheter"
	return ""


static func ai_value(state: GameState, eid: int, _item: Dictionary, fx: Dictionary) -> int:
	match String(fx.get("act", "")):
		"lower_tax":
			return 5 if Finance.crisis_stage(state, eid) == 0 else -15
		"end_strike":
			return 15
		"exempt":
			return -5
		"recover":
			return 15
		"rumor_self":
			return -5
		"house_buy":
			return 25 if Finance.crisis_stage(state, eid) >= 2 else -10
	return 0


# --- Espionnage ---------------------------------------------------------------------------------

## Plus gros emprunt de b envers sa Banque intérieure ({} sinon).
static func bank_loan(state: GameState, b: int) -> Dictionary:
	var best := {}
	for l: Dictionary in Finance.loans(state, b):
		if String(l["l"]) == "bank" and int(l["p"]) >= 100 and (best.is_empty() or int(l["p"]) > int(best["p"])):
			best = l
	return best


static func spy_check(state: GameState, a: int, b: int, op_id: String) -> String:
	if not Finance.full(state) or not Finance.applies(state, b):
		return "la fiscalité complète n'est pas en jeu"
	if op_id == "racheter_creance":
		var l := bank_loan(state, b)
		if l.is_empty():
			return "il ne doit rien à sa Banque intérieure"
		@warning_ignore("integer_division")
		var price := int(l["p"]) * int(_cfg("espionage")["buy_pct"]) / 100
		if int(state.get_empire(a).resources.get("energy", 0)) < price:
			return "il faut %d énergie pour racheter sa créance" % price
	return ""


static func spy_apply(state: GameState, a: int, b: int, o: Dictionary) -> String:
	var sc := _cfg("espionage")
	match String(o["id"]):
		"rumeur_faillite":
			(state.finance["rum"] as Dictionary)[str(b)] = state.tick + int(sc["rumor_days"])
			state.relic_rev += 1
			return "les gazettes annoncent sa ruine : sa cote tombe à %s pendant deux ans." % Finance.grade(state, b)
		"maquiller_comptes":
			(state.finance["mask"] as Dictionary)["%d>%d" % [a, b]] = state.tick + int(sc["mask_days"])
			return "ses comptables lisent nos chiffres comme nous l'entendons : il nous croit noté A."
		"racheter_creance":
			var l := bank_loan(state, b)
			if l.is_empty():
				return "il a remboursé entre-temps : rien à racheter."
			@warning_ignore("integer_division")
			var price := int(l["p"]) * int(sc["buy_pct"]) / 100
			var ea := state.get_empire(a)
			ea.resources["energy"] = int(ea.resources.get("energy", 0)) - price
			l["l"] = "empire"
			l["w"] = a
			if int(l["m"]) <= 0:
				l["m"] = Finance.d_int("loan", "months")
			return "nous avons racheté %d énergie de sa dette pour %d : c'est à nous qu'il paiera désormais ses mensualités." % [int(l["p"]), price]
	return ""
