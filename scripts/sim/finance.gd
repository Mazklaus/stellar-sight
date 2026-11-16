class_name Finance
extends RefCounted
## Fiscalité et dette publique (étude « Fiscalité et dette publique », 2026-11-16 ; data/finance.json).
## L'énergie est le trésor de l'empire. Un niveau d'imposition à 5 crans (Normal = l'économie d'avant)
## module la production d'énergie, la stabilité et la croissance. Quand le stock passerait sous zéro,
## l'empire emprunte d'office à la Banque intérieure, sous un plafond de crédit (12 mois de production
## brute d'énergie, modulé par la stabilité, la cote, les technologies et les talents). Les emprunts
## volontaires se remboursent en 60 mensualités ; les prêteurs sont la Banque, une Grande Maison ou un
## autre empire. Les intérêts sont bas et fixés à la signature (pas de spirale). Au plafond, une crise
## de la dette monte en 4 paliers, avec des approches, jusqu'à la faillite (dettes effacées, 10 ans de
## malus). Cote de crédit de AAA à D, inflation douce, planche à billets, réserve plafonnée, solde des
## équipages, impôt de guerre, franchises fiscales. Ponts (révolte fiscale, doléances, Maisons, Krach,
## Koinon, espionnage, cour) : FinanceBridges.
##
## Réglage « Fiscalité » : Complète (défaut d'une nouvelle partie), Simple (impôt, emprunt automatique,
## crise et faillite) ou Désactivée (rien ne tourne, state.finance reste vide). Sans l'option (tests,
## bancs) : désactivée, donc l'économie d'avant.
##
## État : state.finance = {"mode", "lid": prochain identifiant d'emprunt, "e": {"empire": E},
##  "fr": {"système": empire} (franchises), "strike": {"système": jour de fin}, "rum": {"empire": fin de
##  la rumeur de faillite}, "mask": {"a>b": fin}, "def": {"débiteur>créancier": jour du défaut},
##  "hx": {"empire:maison": fin de l'exemption}, "hr": {"empire:maison": fin du refus},
##  "hrep": {"empire:maison": fin de la répudiation}, "clean": {"empire": jour depuis lequel il n'a pas de dette}}.
## E = {"tax", "tax_day", "pay", "wt" (impôt de guerre), "wt_m" (mois), "loans": [L], "prog", "stage",
##  "appr", "bk" (fin des malus de faillite), "bk0" (jour de la faillite), "hist" (cote D jusqu'à),
##  "infl", "mint_day", "gross" (production brute d'énergie au dernier bilan), "crush" (jour depuis
##  lequel l'impôt est Écrasant), "high" (depuis lequel il est Élevé ou plus), "rv_cd", "grv"...}.
## L = {"id", "l": "bank"|"house"|"empire", "w": maison ou empire prêteur (-1), "p": capital restant,
##  "r": intérêt en centièmes de % par mois, "m": mensualités restantes (0 = dette automatique)}.
## Toutes les clés sont des chaînes (la sauvegarde JSON les rend ainsi).

const LAYERS := ["credo", "gouvernement", "registre"]
const YEAR := 360

static var _talent_cache := {}


static func data() -> Dictionary:
	return GameData.finance()


static func mode_defs() -> Array:
	return data().get("modes", [])


static func default_mode() -> String:
	return String(data().get("default_mode", "complete"))


static func d_int(section: String, key: String) -> int:
	return int((data().get(section, {}) as Dictionary).get(key, 0))


static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "finance"] + parts))


# --- Réglage, sauvegarde -----------------------------------------------------------------------

static func mode(state: GameState) -> String:
	return String(state.finance.get("mode", "desactivee"))


static func enabled(state: GameState) -> bool:
	return not state.finance.is_empty()


## Mode complet : prêteurs, cote affichée, inflation, soldes, franchises, ponts.
static func full(state: GameState) -> bool:
	return mode(state) == "complete"


static func worth_saving(state: GameState) -> bool:
	return not state.finance.is_empty()


static func setup(state: GameState, mode_id: String) -> void:
	state.finance = {}
	var ok := false
	for m: Dictionary in mode_defs():
		if String(m["id"]) == mode_id:
			ok = true
	if not ok or mode_id == "desactivee":
		return
	state.finance = {"mode": mode_id, "lid": 1, "e": {}, "fr": {}, "strike": {}, "rum": {}, "mask": {}, "def": {},
			"hx": {}, "hr": {}, "hrep": {}, "clean": {}}
	for e in state.empires:
		if not e.is_npc():
			_w(state, e.id)


static func to_dict(state: GameState) -> Dictionary:
	return Ancients._sorted(state.finance)


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.finance = {}
	if d.is_empty():
		return
	state.finance = GameData._to_ints(d.duplicate(true))


# --- Talents -----------------------------------------------------------------------------------

static func talent(state: GameState, eid: int) -> Dictionary:
	var e := state.get_empire(eid)
	if e == null or e.is_npc():
		return {}
	var ck := "%s:%d" % [e.faction_id, GameData.factions_gen]
	if _talent_cache.has(ck):
		return _talent_cache[ck]
	var out := {}
	var table: Dictionary = data().get("talents", {})
	for layer in LAYERS:
		var t: Dictionary = (table.get(layer, {}) as Dictionary).get(Events.layer_value(state, eid, layer), {})
		for k in t:
			if k == "label" or k == "text":
				continue
			var v: Variant = t[k]
			out[k] = v if v is bool else int(out.get(k, 0)) + int(v)
	_talent_cache[ck] = out
	return out


static func talent_labels(state: GameState, eid: int) -> Array:
	var e := state.get_empire(eid)
	var out := []
	if e == null or e.is_npc():
		return out
	var table: Dictionary = data().get("talents", {})
	for layer in LAYERS:
		var t: Dictionary = (table.get(layer, {}) as Dictionary).get(Events.layer_value(state, eid, layer), {})
		if not t.is_empty():
			out.append([String(t["label"]), String(t["text"])])
	return out


# --- Lecture -----------------------------------------------------------------------------------

static func applies(state: GameState, eid: int) -> bool:
	var e := state.get_empire(eid)
	return enabled(state) and e != null and not e.is_npc() and not e.eliminated


static func entry(state: GameState, eid: int) -> Dictionary:
	if state.finance.is_empty():
		return {}
	return (state.finance["e"] as Dictionary).get(str(eid), {})


static func _w(state: GameState, eid: int) -> Dictionary:
	var all: Dictionary = state.finance["e"]
	if not all.has(str(eid)):
		all[str(eid)] = {"tax": String(data()["taxes"]["default"]), "tax_day": -100000, "pay": String(data()["pay"]["default"]),
				"wt": 0, "wt_m": 0, "loans": [], "prog": 0, "stage": 0, "appr": "maintenir", "bk": 0, "bk0": -100000,
				"hist": 0, "infl": 0, "mint_day": -100000, "gross": 0, "crush": -1, "high": -1, "rv_cd": 0}
	return all[str(eid)]


static func tax_defs() -> Array:
	return data()["taxes"]["levels"]


static func tax_def(id: String) -> Dictionary:
	for d: Dictionary in tax_defs():
		if String(d["id"]) == id:
			return d
	return {}


static func tax_index(id: String) -> int:
	var defs := tax_defs()
	for i in defs.size():
		if String(defs[i]["id"]) == id:
			return i
	return 2


static func tax(state: GameState, eid: int) -> String:
	if bool(talent(state, eid).get("no_tax", false)):
		return String(data()["taxes"]["default"])
	return String(entry(state, eid).get("tax", data()["taxes"]["default"]))


static func pay_defs() -> Array:
	return data()["pay"]["levels"]


static func pay_def(id: String) -> Dictionary:
	for d: Dictionary in pay_defs():
		if String(d["id"]) == id:
			return d
	return {}


static func pay(state: GameState, eid: int) -> String:
	if not full(state):
		return String(data()["pay"]["default"])
	return String(entry(state, eid).get("pay", data()["pay"]["default"]))


static func war_tax_on(state: GameState, eid: int) -> bool:
	return full(state) and int(entry(state, eid).get("wt", 0)) == 1


static func loans(state: GameState, eid: int) -> Array:
	return entry(state, eid).get("loans", [])


static func loan(state: GameState, eid: int, lid: int) -> Dictionary:
	for l: Dictionary in loans(state, eid):
		if int(l["id"]) == lid:
			return l
	return {}


## Dette totale (capital restant de tous les emprunts).
static func debt(state: GameState, eid: int) -> int:
	var n := 0
	for l: Dictionary in loans(state, eid):
		n += int(l["p"])
	return n


static func auto_loan(state: GameState, eid: int) -> Dictionary:
	for l: Dictionary in loans(state, eid):
		if int(l["m"]) == 0:
			return l
	return {}


static func gross_energy(state: GameState, eid: int) -> int:
	return int(entry(state, eid).get("gross", 0))


static func inflation(state: GameState, eid: int) -> int:
	return int(entry(state, eid).get("infl", 0)) if full(state) else 0


static func bankrupt_until(state: GameState, eid: int) -> int:
	return int(entry(state, eid).get("bk", 0))


static func in_bankruptcy(state: GameState, eid: int) -> bool:
	return bankrupt_until(state, eid) > state.tick


static func crisis_progress(state: GameState, eid: int) -> int:
	return int(entry(state, eid).get("prog", 0))


static func crisis_stage(state: GameState, eid: int) -> int:
	return int(entry(state, eid).get("stage", 0))


static func stage_def(n: int) -> Dictionary:
	var st: Array = data()["crisis"]["stages"]
	return st[clampi(n - 1, 0, st.size() - 1)] if n > 0 else {}


static func approach_defs() -> Array:
	return data()["crisis"]["approaches"]


static func approach_def(id: String) -> Dictionary:
	for d: Dictionary in approach_defs():
		if String(d["id"]) == id:
			return d
	return {}


static func approach(state: GameState, eid: int) -> String:
	return String(entry(state, eid).get("appr", "maintenir"))


## Pourcentage tiré des technologies, reliques, lois… (clés debt_*), hors effets propres (pas de récursion).
static func _fx(state: GameState, eid: int, key: String) -> int:
	if state.get_empire(eid) == null:
		return 0
	return Research.fx_int(state, eid, key)


# --- Plafond, cote, taux -----------------------------------------------------------------------

## Stabilité moyenne des systèmes de l'empire (50 sans système ni stabilité).
static func _avg_stability(state: GameState, eid: int) -> int:
	if not Stability.applies(state, eid):
		return 50
	var s := Stability.systems_of(state, eid)
	if s.is_empty():
		return 50
	var t := 0
	for sid in s:
		t += Stability.value(state, sid)
	@warning_ignore("integer_division")
	return t / s.size()


## Plafond avant la cote (la cote dépend du rapport dette / plafond de base).
static func base_cap(state: GameState, eid: int) -> int:
	var cc: Dictionary = data()["credit"]
	var v := maxi(int(cc["min"]), gross_energy(state, eid) * int(cc["months"]))
	var pct := 100 + _fx(state, eid, "debt_cap_pct") + int(talent(state, eid).get("cap_pct", 0))
	var avg := _avg_stability(state, eid)
	if avg >= int(cc["stab_hi"]):
		pct += int(cc["stab_hi_pct"])
	elif avg < int(cc["stab_lo"]):
		pct += int(cc["stab_lo_pct"])
	pct += FinanceBridges.cap_pct(state, eid)
	@warning_ignore("integer_division")
	return maxi(int(cc["min"]) / 2, v * maxi(10, pct) / 100)


static func cap(state: GameState, eid: int) -> int:
	@warning_ignore("integer_division")
	return maxi(1, base_cap(state, eid) * int(grade_def(grade(state, eid)).get("cap_pct", 100)) / 100)


static func grade_defs() -> Array:
	return data()["rating"]["grades"]


static func grade_def(id: String) -> Dictionary:
	for d: Dictionary in grade_defs():
		if String(d["id"]) == id:
			return d
	return grade_defs()[3]


static func ratio_pct(state: GameState, eid: int) -> int:
	@warning_ignore("integer_division")
	return debt(state, eid) * 100 / maxi(1, base_cap(state, eid))


## Cote de crédit réelle : D après une faillite ou une répudiation récente, sinon selon la dette.
static func grade(state: GameState, eid: int) -> String:
	var defs := grade_defs()
	if int(entry(state, eid).get("hist", 0)) > state.tick:
		return String(defs[defs.size() - 1]["id"])
	var r := ratio_pct(state, eid)
	var i := defs.size() - 1
	for k in defs.size():
		if r <= int(defs[k]["max_ratio"]):
			i = k
			break
	if int((state.finance.get("rum", {}) as Dictionary).get(str(eid), 0)) > state.tick:
		i = mini(defs.size() - 1, i + 1)  # rumeur de faillite
	return String(defs[i]["id"])


## Cote telle que l'empire viewer la voit (« Maquiller les comptes » : il la croit bonne).
static func grade_seen(state: GameState, eid: int, viewer: int) -> String:
	if viewer != eid and int((state.finance.get("mask", {}) as Dictionary).get("%d>%d" % [eid, viewer], 0)) > state.tick:
		return "A"
	return grade(state, eid)


static func grade_index(id: String) -> int:
	var defs := grade_defs()
	for i in defs.size():
		if String(defs[i]["id"]) == id:
			return i
	return 3


## Intérêt mensuel (centièmes de %) proposé à l'empire par ce prêteur, à la signature.
static func rate_for(state: GameState, eid: int, lender := "bank", who := -1) -> int:
	var rc: Dictionary = data()["rate"]
	var tal := talent(state, eid)
	var g := grade(state, eid) if not bool(tal.get("ignore_rating", false)) else "BBB"
	var pct := int(grade_def(g).get("rate_pct", 100))
	var cr: Dictionary = data()["creditors"]
	match lender:
		"house":
			pct = pct * (int(cr["house_pct"]) + int(tal.get("house_rate_pct", 0))) / 100
			var h := Court.house(state, eid, who) if not state.court.is_empty() else {}
			if not h.is_empty() and (cr["merchant_vocations"] as Array).has(String(h.get("voc", ""))):
				pct = pct * int(cr["merchant_pct"]) / int(cr["house_pct"])
		"company":
			pct = pct * Private.c_int("companies", "lender_pct") / 100  # compagnie nationale prêteuse
		"empire":
			pct = pct * (int(cr["lord_pct"]) if state.vassals_on and Vassals.lord_of(state, eid) == who else int(cr["empire_pct"])) / 100
	var adj := _fx(state, eid, "debt_rate_pct") + int(tal.get("rate_pct", 0)) + FinanceBridges.rate_pct(state, eid)
	if in_bankruptcy(state, eid):
		adj += d_int("bankruptcy", "rate_pct")
	@warning_ignore("integer_division")
	return maxi(int(rc["min"]), int(rc["base"]) * pct / 100 * maxi(10, 100 + adj) / 100)


static func interest_of(state: GameState, eid: int, l: Dictionary) -> int:
	if bool(talent(state, eid).get("no_interest", false)):
		return 0
	var p := int(l["p"])
	if p <= 0:
		return 0
	@warning_ignore("integer_division")
	return (p * int(l["r"]) + 9999) / 10000


static func principal_part(l: Dictionary) -> int:
	var m := int(l["m"])
	if m <= 0:
		return 0
	@warning_ignore("integer_division")
	return (int(l["p"]) + m - 1) / m


## Mensualité d'un emprunt (capital et intérêts ; intérêts seuls pour la dette automatique).
static func installment(state: GameState, eid: int, l: Dictionary) -> int:
	return interest_of(state, eid, l) + principal_part(l)


# --- Effets lus par les autres systèmes -------------------------------------------------------

## Entretien mensuel : inflation sur l'entretien en énergie, puis mensualités des emprunts.
static func adjust_upkeep(state: GameState, eid: int, upkeep: Dictionary) -> void:
	if not applies(state, eid):
		return
	var infl := inflation(state, eid)
	if infl > 0 and int(upkeep.get("energy", 0)) > 0:
		@warning_ignore("integer_division")
		upkeep["energy"] = int(upkeep["energy"]) * (10000 + infl) / 10000
	var n := 0
	for l: Dictionary in loans(state, eid):
		n += installment(state, eid, l)
	if n > 0:
		upkeep["energy"] = int(upkeep.get("energy", 0)) + n


## Énergie touchée chaque mois sur les prêts consentis à d'autres empires.
static func lender_income(state: GameState, eid: int) -> int:
	if state.finance.is_empty():
		return 0
	var n := 0
	var bonus := int(talent(state, eid).get("lend_pct", 0))
	for k in (state.finance["e"] as Dictionary).keys():
		var b := int(k)
		if b == eid:
			continue
		for l: Dictionary in loans(state, b):
			if String(l["l"]) == "empire" and int(l["w"]) == eid:
				var i := interest_of(state, b, l)
				@warning_ignore("integer_division")
				n += principal_part(l) + i + i * bonus / 100
	return n


## Effets au format des technologies (fusionnés dans Research.effects) : crans d'impôt, solde, impôt de
## guerre, palier et approche de la crise, faillite. Pas de stabilité ici (lignes à part).
static func effects(state: GameState, eid: int) -> Dictionary:
	var out := {}
	if not applies(state, eid):
		return out
	var td := tax_def(tax(state, eid))
	if int(td.get("energy_pct", 0)) != 0:
		Research._merge(out, {"production_pct": {"energy": int(td["energy_pct"])}})
	if int(td.get("growth_pct", 0)) != 0:
		out["growth_pct"] = int(out.get("growth_pct", 0)) + int(td["growth_pct"])
	if full(state):
		Research._merge(out, (pay_def(pay(state, eid)).get("fx", {}) as Dictionary).duplicate(true))
		if war_tax_on(state, eid):
			Research._merge(out, (data()["war_tax"]["fx"] as Dictionary).duplicate(true))
	var st := crisis_stage(state, eid)
	if st > 0:
		Research._merge(out, (stage_def(st).get("fx", {}) as Dictionary).duplicate(true))
		Research._merge(out, (approach_def(approach(state, eid)).get("fx", {}) as Dictionary).duplicate(true))
	var loot := int(talent(state, eid).get("loot_energy_pct", 0))
	if loot != 0 and not state.get_empire(eid).wars.is_empty():
		Research._merge(out, {"production_pct": {"energy": loot}})
	if in_bankruptcy(state, eid):
		var bc: Dictionary = data()["bankruptcy"]
		Research._merge(out, {"building_cost_pct": int(bc["cost_pct"]), "ship_cost_pct": int(bc["cost_pct"]),
				"production_pct": {"influence": int(bc["influence_pct"])}, "damage_pct": int(bc["damage_pct"])})
	return out


## Sources de stabilité d'empire : impôt, crise, faillite, approche, solde rognée en guerre, impôt de guerre.
static func empire_stability_parts(state: GameState, eid: int) -> Array:
	var out := []
	if not applies(state, eid):
		return out
	var td := tax_def(tax(state, eid))
	if int(td.get("stability", 0)) != 0:
		out.append(["Impôt %s" % String(td["label"]).to_lower(), int(td["stability"])])
	var st := crisis_stage(state, eid)
	if st > 0:
		out.append(["Crise de la dette : %s" % String(stage_def(st)["label"]).to_lower(), int(stage_def(st).get("stability", 0))])
		var ad := approach_def(approach(state, eid))
		if int(ad.get("stability", 0)) != 0:
			out.append([String(ad["label"]), int(ad["stability"])])
	var en := entry(state, eid)
	if in_bankruptcy(state, eid) and state.tick - int(en.get("bk0", -100000)) < d_int("bankruptcy", "stability_days"):
		out.append(["Faillite récente", d_int("bankruptcy", "stability")])
	if full(state):
		var e := state.get_empire(eid)
		if e != null and not e.wars.is_empty():
			var pd := pay_def(pay(state, eid))
			if int(pd.get("war_stability", 0)) != 0:
				out.append(["Équipages mal payés", int(pd["war_stability"])])
		if war_tax_on(state, eid):
			out.append(["Impôt de guerre", int(data()["war_tax"]["stability"])])
	out.append_array(FinanceBridges.empire_stability_parts(state, eid))
	return out


## Sources de stabilité d'un système : franchise fiscale.
static func system_stability_parts(state: GameState, sid: int) -> Array:
	var out := []
	if state.finance.is_empty() or not full(state):
		return out
	if has_franchise(state, sid):
		out.append(["Franchise fiscale", d_int("franchises", "stability")])
	return out


## Production d'une colonie : franchise (énergie), grève fiscale, Maison exemptée ou furieuse.
static func adjust_yields(state: GameState, colony: Colony, sid: int, gross: Dictionary) -> void:
	if not full(state):
		return
	var pct := 100
	if has_franchise(state, sid):
		pct += d_int("franchises", "energy_pct")
	else:
		pct -= leak_pct(state, colony.owner, sid)
	pct += FinanceBridges.house_energy_pct(state, colony.owner, sid)
	if pct != 100 and int(gross.get("energy", 0)) > 0:
		@warning_ignore("integer_division")
		gross["energy"] = int(gross["energy"]) * maxi(0, pct) / 100
	if int((state.finance["strike"] as Dictionary).get(str(sid), 0)) > state.tick:
		var sp := d_int("revolt", "strike_pct")
		for r in gross:
			if int(gross[r]) > 0:
				@warning_ignore("integer_division")
				gross[r] = int(gross[r]) * sp / 100


## Fuite fiscale : la corruption retient sa part de l'impôt supplémentaire (crans Élevé et Écrasant),
## en points de % de la production d'énergie de la colonie.
static func leak_pct(state: GameState, eid: int, sid: int) -> int:
	var tp := int(tax_def(tax(state, eid)).get("energy_pct", 0))
	if tp <= 0:
		return 0
	@warning_ignore("integer_division")
	return tp * FinanceBridges.leak_pct(state, eid, sid) / 100


static func on_strike(state: GameState, sid: int) -> bool:
	return not state.finance.is_empty() and int((state.finance.get("strike", {}) as Dictionary).get(str(sid), 0)) > state.tick


# --- Réserve ------------------------------------------------------------------------------------

static func reserve(state: GameState, eid: int) -> int:
	var rc: Dictionary = data()["reserve"]
	@warning_ignore("integer_division")
	return maxi(int(rc["min"]), gross_energy(state, eid) * int(rc["months"])) * maxi(10, 100 + _fx(state, eid, "reserve_pct")) / 100


# --- Bilan mensuel (EconomySystem, avant le plancher à zéro) -----------------------------------

## Après l'ajout du bilan du mois : réserve plafonnée, emprunt automatique ou remboursement, crise.
static func settle(state: GameState, e: Empire, inc_all: Dictionary, added: Array[Dictionary]) -> void:
	if not applies(state, e.id):
		return
	var en := _w(state, e.id)
	en["gross"] = int(inc_all["gross"].get("energy", 0))
	var net := int(inc_all["net"].get("energy", 0))
	var energy := int(e.resources.get("energy", 0))
	# Réserve plafonnée : l'excédent du mois au-delà de la réserve ne rentre qu'en partie.
	if full(state) and net > 0:
		var res := reserve(state, e.id)
		if energy > res:
			var over := mini(net, energy - res)
			var keep := int(talent(state, e.id).get("reserve_keep", d_int("reserve", "keep_pct")))
			@warning_ignore("integer_division")
			energy -= over * (100 - keep) / 100
	# Trésor à sec : emprunt d'office, dans la limite du plafond.
	var dry := false
	if energy < 0:
		var room := maxi(0, cap(state, e.id) - debt(state, e.id))
		var take := mini(-energy, room)
		if take > 0:
			_draw_auto(state, e.id, take)
			energy += take
			if not e.is_ai() and debt(state, e.id) == take:
				added.append(state.add_chronicle("%s emprunte pour la première fois : la Banque intérieure avance %d énergie, à %s par mois." % [
						e.short_name(), take, rate_label(int(auto_loan(state, e.id).get("r", 0)))], Espionage.private_to(state, [e.id])))
		dry = energy < 0
	elif energy > 0:
		var al := auto_loan(state, e.id)
		if not al.is_empty() and net > 0:
			@warning_ignore("integer_division")
			var r := mini(int(al["p"]), mini(energy, net * d_int("auto", "repay_pct") / 100 + 1))
			al["p"] = int(al["p"]) - r
			energy -= r
			if int(al["p"]) <= 0:
				(en["loans"] as Array).erase(al)
	e.resources["energy"] = energy
	_crisis(state, e, en, net, dry, added)
	# Sans dette : depuis quand (haut fait « Budget à l'équilibre »).
	var clean: Dictionary = state.finance["clean"]
	if debt(state, e.id) == 0:
		if not clean.has(str(e.id)):
			clean[str(e.id)] = state.tick
	else:
		clean.erase(str(e.id))


static func _draw_auto(state: GameState, eid: int, take: int) -> void:
	var en := _w(state, eid)
	var al := auto_loan(state, eid)
	var r := rate_for(state, eid, "bank")
	if al.is_empty():
		al = {"id": _next_id(state), "l": "bank", "w": -1, "p": 0, "r": r, "m": 0}
		(en["loans"] as Array).append(al)
	var p := int(al["p"])
	@warning_ignore("integer_division")
	al["r"] = (p * int(al["r"]) + take * r) / maxi(1, p + take)
	al["p"] = p + take
	_inflate(state, eid, take)


static func _next_id(state: GameState) -> int:
	var n := int(state.finance.get("lid", 1))
	state.finance["lid"] = n + 1
	return n


static func _inflate(state: GameState, eid: int, borrowed: int) -> void:
	if not full(state) or borrowed <= 0:
		return
	var en := _w(state, eid)
	var ic: Dictionary = data()["inflation"]
	@warning_ignore("integer_division")
	en["infl"] = mini(int(ic["max"]), int(en.get("infl", 0)) + borrowed * int(ic["per_100"]) / 100)


static func add_inflation(state: GameState, eid: int, n: int) -> void:
	if not full(state) or not applies(state, eid):
		return
	var en := _w(state, eid)
	en["infl"] = clampi(int(en.get("infl", 0)) + n, 0, d_int("inflation", "max"))


static func _crisis(state: GameState, e: Empire, en: Dictionary, net: int, dry: bool, added: Array[Dictionary]) -> void:
	var cc: Dictionary = data()["crisis"]
	var at_cap := debt(state, e.id) >= cap(state, e.id) and net < 0
	var prog := int(en.get("prog", 0))
	if at_cap or dry:
		var up := int(cc["per_month"]) + (int(cc["dry_extra"]) if dry else 0) - int(approach_def(approach(state, e.id)).get("slow", 0))
		@warning_ignore("integer_division")
		up = up * maxi(0, 100 + _fx(state, e.id, "debt_crisis_pct")) / 100
		prog += maxi(1, up)
	else:
		prog -= int(cc["recede"])
	prog = clampi(prog, 0, 100)
	en["prog"] = prog
	if prog >= 100:
		bankrupt(state, e.id, added)
		return
	@warning_ignore("integer_division")
	var st := mini(4, prog / int(cc["stage_size"]))
	if st != int(en.get("stage", 0)):
		var up_stage := st > int(en.get("stage", 0))
		en["stage"] = st
		if st == 0:
			en["appr"] = "maintenir"
		state.relic_rev += 1
		if not e.is_ai():
			if up_stage:
				added.append(state.add_chronicle("Crise de la dette chez %s : %s. %s" % [e.short_name(), String(stage_def(st)["label"]).to_lower(), String(stage_def(st)["text"])], Espionage.private_to(state, [e.id])))
			elif st == 0:
				added.append(state.add_chronicle("La crise de la dette s'éloigne : %s respire, et ses créanciers raccrochent." % e.short_name(), Espionage.private_to(state, [e.id])))


## Faillite : dettes effacées, malus pendant 10 ans, cote D, mercenaires renvoyés, prêteurs furieux.
static func bankrupt(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	var en := _w(state, eid)
	var bc: Dictionary = data()["bankruptcy"]
	var lenders := {}
	for l: Dictionary in loans(state, eid):
		if String(l["l"]) == "empire" and int(l["w"]) >= 0:
			lenders[int(l["w"])] = true
		elif String(l["l"]) == "house":
			FinanceBridges.house_wronged(state, eid, int(l["w"]), false)
	for lid in lenders:
		Diplomacy.remember(state, int(lid), eid, "debt_default")
		(state.finance["def"] as Dictionary)["%d>%d" % [eid, int(lid)]] = state.tick
	en["loans"] = []
	en["prog"] = 0
	en["stage"] = 0
	en["appr"] = "maintenir"
	en["bk"] = state.tick + int(bc["days"])
	en["bk0"] = state.tick
	en["hist"] = state.tick + d_int("rating", "history_days")
	if int(e.resources.get("energy", 0)) < 0:
		e.resources["energy"] = 0
	state.relic_rev += 1
	# Les mercenaires ne travaillent pas à crédit.
	for o in state.empires:
		var c := Diplomacy.contract_of(state, o.id)
		if not c.is_empty() and int(c["client"]) == eid:
			Diplomacy.end_contract(state, o.id, "unpaid")
	Deeds.note(state, eid, "bankrupt")
	Rulers.note(state, eid, "bankrupt")
	if bool(talent(state, eid).get("bankrupt_election", false)) and state.politics_on and Politics.applies(state, eid):
		Politics._emp_w(state, eid)["next"] = state.tick + 1
	added.append(state.add_chronicle("FAILLITE : %s ne paie plus personne. Les dettes sont effacées, la parole de l'empire aussi : dix ans de malus, et les banquiers changent de trottoir." % e.display_name(), Espionage.public_to(state, [eid])))


# --- Mois (Simulation, après l'économie) ---------------------------------------------------------

static func daily(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if state.finance.is_empty():
		return added
	if state.tick % int(GameData.rules()["month_days"]) != 0:
		return added
	for e in state.empires:
		if e.is_npc():
			continue
		if e.eliminated:
			if (state.finance["e"] as Dictionary).has(str(e.id)):
				_forget(state, e.id)
			continue
		var en := _w(state, e.id)
		_amortize(state, e, en, added)
		# Butin de la horde (effets en cache) : un tick de révision quand la guerre commence ou finit.
		if int(talent(state, e.id).get("loot_energy_pct", 0)) != 0:
			var war := 0 if e.wars.is_empty() else 1
			if int(en.get("war", 0)) != war:
				en["war"] = war
				state.relic_rev += 1
		# Inflation : décrue, impôt de guerre trop long.
		if full(state):
			var ic: Dictionary = data()["inflation"]
			if war_tax_on(state, e.id):
				en["wt_m"] = int(en.get("wt_m", 0)) + 1
				if int(en["wt_m"]) > int(ic["war_tax_months"]):
					en["infl"] = int(en.get("infl", 0)) + int(ic["war_tax"])
				if e.wars.is_empty():
					en["wt"] = 0
					en["wt_m"] = 0
					state.relic_rev += 1
			en["infl"] = clampi(int(en.get("infl", 0)) - int(ic["decay"]) - _fx(state, e.id, "inflation_decay") - FinanceBridges.decay_bonus(state, e.id), 0, int(ic["max"]))
		# Fin des malus de faillite (les effets sont en cache) : un tick de révision.
		if int(en.get("bk", 0)) > 0 and int(en["bk"]) <= state.tick:
			en["bk"] = 0
			state.relic_rev += 1
		# Depuis quand l'impôt est-il lourd (révolte, doléance) ?
		var ti := tax_index(tax(state, e.id))
		en["crush"] = (int(en["crush"]) if int(en.get("crush", -1)) >= 0 else state.tick) if ti >= 4 else -1
		en["high"] = (int(en["high"]) if int(en.get("high", -1)) >= 0 else state.tick) if ti >= 3 else -1
	_prune(state)
	FinanceBridges.monthly(state, added)
	return added


## Mensualités du mois (déjà payées par le bilan) : le capital baisse, l'emprunt s'éteint.
static func _amortize(state: GameState, e: Empire, en: Dictionary, added: Array[Dictionary]) -> void:
	var keep := []
	for l: Dictionary in (en["loans"] as Array):
		var gone := false
		if String(l["l"]) == "empire":
			var le := state.get_empire(int(l["w"]))
			if le == null or le.eliminated:
				gone = true  # le créancier a disparu : la dette avec lui
		elif String(l["l"]) == "koinon":
			var lg := Koinon.league(state, int(l["w"])) if not state.koinon.is_empty() else {}
			if lg.is_empty():
				gone = true  # le Koinon dissous n'a plus de trésorier
			elif int(l["m"]) > 0:
				lg["treasury"] = int(lg.get("treasury", 0)) + principal_part(l)
		elif String(l["l"]) == "company":
			if Private.company(state, int(l["w"])).is_empty():
				gone = true  # la compagnie a fait faillite : la créance part avec elle
			elif int(l["m"]) > 0:
				Private.lend_repaid(state, e.id, installment(state, e.id, l))
		if int(l["m"]) > 0 and not gone:
			l["p"] = int(l["p"]) - principal_part(l)
			l["m"] = int(l["m"]) - 1
			if int(l["p"]) <= 0 or int(l["m"]) <= 0:
				gone = true
				if String(l["l"]) == "empire":
					Diplomacy.remember(state, int(l["w"]), e.id, "loan_repaid")
				if not e.is_ai():
					added.append(state.add_chronicle("%s solde un emprunt : la dernière mensualité part, avec un soupir de soulagement." % e.short_name(), Espionage.private_to(state, [e.id])))
		if not gone and int(l["p"]) > 0:
			keep.append(l)
	en["loans"] = keep


static func _forget(state: GameState, eid: int) -> void:
	(state.finance["e"] as Dictionary).erase(str(eid))
	var fr: Dictionary = state.finance["fr"]
	for k in fr.keys():
		if int(fr[k]) == eid:
			fr.erase(k)


static func _prune(state: GameState) -> void:
	for key in ["strike", "rum", "mask", "hx", "hr", "hrep"]:
		var d: Dictionary = state.finance.get(key, {})
		for k in d.keys():
			if int(d[k]) <= state.tick:
				d.erase(k)
	# Franchises : le système doit rester à l'empire.
	var fr: Dictionary = state.finance["fr"]
	for k in fr.keys():
		if state.system_owner(int(k)) != int(fr[k]):
			fr.erase(k)


# --- Ordres ------------------------------------------------------------------------------------

static func check_tax(state: GameState, eid: int, id: String) -> String:
	if not applies(state, eid):
		return "la fiscalité n'est pas en jeu"
	if tax_def(id).is_empty():
		return "cran inconnu"
	if bool(talent(state, eid).get("no_tax", false)):
		return "votre peuple ne lève pas d'impôt : il prend"
	if id == tax(state, eid):
		return "c'est déjà le cran en vigueur"
	var en := entry(state, eid)
	var cd := d_int("taxes", "cooldown_days")
	if state.tick - int(en.get("tax_day", -100000)) < cd:
		return "un changement par an au plus (prochain le %s)" % GameCalendar.date_string(int(en["tax_day"]) + cd)
	var e := state.get_empire(eid)
	if not Economy.can_afford(e, data()["taxes"]["change_cost"]):
		return "il faut %d influence" % int(data()["taxes"]["change_cost"].get("influence", 0))
	return ""


static func set_tax(state: GameState, eid: int, id: String) -> void:
	var en := _w(state, eid)
	Economy.pay(state.get_empire(eid), data()["taxes"]["change_cost"])
	en["tax"] = id
	en["tax_day"] = state.tick
	state.relic_rev += 1


static func check_pay(state: GameState, eid: int, id: String) -> String:
	if not applies(state, eid) or not full(state):
		return "la solde ne se règle qu'en fiscalité complète"
	if pay_def(id).is_empty():
		return "cran inconnu"
	if id == pay(state, eid):
		return "c'est déjà la solde en vigueur"
	return ""


static func set_pay(state: GameState, eid: int, id: String) -> void:
	_w(state, eid)["pay"] = id
	state.relic_rev += 1


static func check_war_tax(state: GameState, eid: int, on: bool) -> String:
	if not applies(state, eid) or not full(state):
		return "l'impôt de guerre ne se lève qu'en fiscalité complète"
	if on == war_tax_on(state, eid):
		return "déjà fait"
	if on and state.get_empire(eid).wars.is_empty():
		return "seulement en guerre"
	return ""


static func set_war_tax(state: GameState, eid: int, on: bool) -> void:
	var en := _w(state, eid)
	en["wt"] = 1 if on else 0
	if not on:
		en["wt_m"] = 0
	state.relic_rev += 1


static func check_approach(state: GameState, eid: int, id: String) -> String:
	if not applies(state, eid):
		return "la fiscalité n'est pas en jeu"
	if crisis_stage(state, eid) <= 0:
		return "pas de crise de la dette en cours"
	if approach_def(id).is_empty():
		return "approche inconnue"
	if id == approach(state, eid):
		return "c'est déjà l'approche choisie"
	return ""


static func set_approach(state: GameState, eid: int, id: String) -> void:
	_w(state, eid)["appr"] = id
	state.relic_rev += 1


## Prêteurs possibles pour un empire : [[clé, libellé]] (clé "bank", "house:ID", "empire:ID").
static func lenders(state: GameState, eid: int) -> Array:
	var out := [["bank", "Banque intérieure"]]
	if not full(state):
		return out
	if not state.court.is_empty() and Court.applies(state, eid):
		for h: Dictionary in Court.houses(state, eid):
			out.append(["house:%d" % int(h["id"]), String(h.get("name", "?"))])
	for c in Private.lender_companies(state, eid):
		out.append(["company:%d" % int(c["id"]), String(c["n"])])
	for o in state.empires:
		if o.id != eid and not o.eliminated and not o.is_npc() and state.get_empire(eid).contacts.has(o.id):
			out.append(["empire:%d" % o.id, o.short_name()])
	return out


static func _split(key: String) -> Array:
	var parts := key.split(":")
	return [String(parts[0]), int(parts[1]) if parts.size() > 1 else -1]


static func house_lent(state: GameState, eid: int, hid: int) -> int:
	var n := 0
	for l: Dictionary in loans(state, eid):
		if String(l["l"]) == "house" and int(l["w"]) == hid:
			n += int(l["p"])
	return n


static func check_borrow(state: GameState, eid: int, key: String, amount: int) -> String:
	if not applies(state, eid):
		return "la fiscalité n'est pas en jeu"
	if not full(state):
		return "les emprunts volontaires ne se lèvent qu'en fiscalité complète"
	var lc: Dictionary = data()["loan"]
	if amount < int(lc["min"]) or amount > int(lc["max"]) or amount % int(lc["step"]) != 0:
		return "de %d à %d énergie, par tranches de %d" % [int(lc["min"]), int(lc["max"]), int(lc["step"])]
	if debt(state, eid) + amount > cap(state, eid):
		return "au-delà du plafond de crédit (%d)" % cap(state, eid)
	if in_bankruptcy(state, eid) and key == "bank":
		return "la Banque intérieure ne prête plus à un empire en faillite"
	var tal := talent(state, eid)
	if int(tal.get("loan_influence", 0)) > 0:
		@warning_ignore("integer_division")
		var inf := int(tal["loan_influence"]) * amount / 100
		if int(state.get_empire(eid).resources.get("influence", 0)) < inf:
			return "il faut une offrande de %d influence" % inf
	var kw := _split(key)
	match String(kw[0]):
		"bank":
			return ""
		"house":
			if state.court.is_empty() or not Court.applies(state, eid):
				return "pas de Grandes Maisons"
			var h := Court.house(state, eid, int(kw[1]))
			if h.is_empty():
				return "Maison inconnue"
			if not Court.serves(h):
				return "cette Maison vous boude : elle ne prête pas"
			if (state.finance["hrep"] as Dictionary).has("%d:%d" % [eid, int(kw[1])]):
				return "vous l'avez déjà volée une fois"
			var mx := int(data()["creditors"]["house_max"]) * maxi(1, int(tal.get("house_max_x", 1)))
			if house_lent(state, eid, int(kw[1])) + amount > mx:
				return "elle ne prête pas plus de %d énergie en tout" % mx
			return ""
		"empire":
			return lend_refusal(state, int(kw[1]), eid, amount)
		"company":
			return Private.lend_check(state, eid, int(kw[1]), amount)
	return "prêteur inconnu"


## Pourquoi l'empire a refuserait de prêter à b ("" s'il accepte). Un joueur humain ne se sollicite pas :
## c'est lui qui prête (Prêter).
static func lend_refusal(state: GameState, a: int, b: int, amount: int) -> String:
	var ea := state.get_empire(a)
	if ea == null or ea.eliminated or ea.is_npc() or a == b:
		return "prêteur inconnu"
	if not ea.is_ai():
		return "%s est un joueur : demandez-lui de vous prêter" % ea.short_name()
	if Combat.at_war(state, a, b):
		return "on ne prête pas à l'ennemi"
	var cr: Dictionary = data()["creditors"]
	if int(ea.resources.get("energy", 0)) - amount < int(cr["ai_reserve"]):
		return "%s n'a pas assez d'énergie à prêter" % ea.short_name()
	if Diplomacy.opinion(state, a, b) < int(cr["ai_opinion"]):
		return "%s ne vous fait pas confiance" % ea.short_name()
	if grade_index(grade_seen(state, b, a)) > grade_index(String(cr["ai_min_grade"])):
		return "votre cote (%s) l'effraie" % grade_seen(state, b, a)
	if (state.finance["def"] as Dictionary).has("%d>%d" % [b, a]):
		return "vous lui devez déjà une faillite"
	return ""


static func borrow(state: GameState, eid: int, key: String, amount: int) -> void:
	var kw := _split(key)
	var kind := String(kw[0])
	var who := int(kw[1])
	var e := state.get_empire(eid)
	var tal := talent(state, eid)
	if int(tal.get("loan_influence", 0)) > 0:
		@warning_ignore("integer_division")
		e.resources["influence"] = int(e.resources.get("influence", 0)) - int(tal["loan_influence"]) * amount / 100
	if kind == "empire":
		var le := state.get_empire(who)
		le.resources["energy"] = int(le.resources.get("energy", 0)) - amount
		Diplomacy.remember(state, eid, who, "loan_granted")
	elif kind == "company":
		Private.lend_take(state, eid, amount)
	var l := {"id": _next_id(state), "l": kind, "w": who, "p": amount, "r": rate_for(state, eid, kind, who), "m": d_int("loan", "months")}
	(_w(state, eid)["loans"] as Array).append(l)
	e.resources["energy"] = int(e.resources.get("energy", 0)) + amount
	_inflate(state, eid, amount)
	Rulers.note(state, eid, "borrowed")
	if kind == "house" and not state.court.is_empty():
		Court.refresh(state, eid)


## Prêter à un autre empire (traité de prêt) : une IA accepte si elle en a besoin ; un joueur accepte d'office.
static func check_lend(state: GameState, a: int, b: int, amount: int) -> String:
	if not applies(state, a) or not full(state):
		return "les prêts entre empires ne se font qu'en fiscalité complète"
	var eb := state.get_empire(b)
	if eb == null or eb.eliminated or eb.is_npc() or a == b or not applies(state, b):
		return "emprunteur inconnu"
	if not state.get_empire(a).contacts.has(b):
		return "vous ne le connaissez pas"
	if Combat.at_war(state, a, b):
		return "on ne prête pas à l'ennemi"
	var lc: Dictionary = data()["loan"]
	if amount < int(lc["min"]) or amount > int(lc["max"]) or amount % int(lc["step"]) != 0:
		return "de %d à %d énergie, par tranches de %d" % [int(lc["min"]), int(lc["max"]), int(lc["step"])]
	if int(state.get_empire(a).resources.get("energy", 0)) < amount:
		return "vous n'avez pas %d énergie" % amount
	if debt(state, b) + amount > cap(state, b):
		return "il est déjà à son plafond de crédit"
	if eb.is_ai() and not ai_wants_loan(state, b, amount):
		return "%s n'a pas besoin de votre argent" % eb.short_name()
	return ""


static func lend(state: GameState, a: int, b: int, amount: int) -> void:
	var ea := state.get_empire(a)
	var eb := state.get_empire(b)
	ea.resources["energy"] = int(ea.resources.get("energy", 0)) - amount
	eb.resources["energy"] = int(eb.resources.get("energy", 0)) + amount
	var l := {"id": _next_id(state), "l": "empire", "w": a, "p": amount, "r": rate_for(state, b, "empire", a), "m": d_int("loan", "months")}
	(_w(state, b)["loans"] as Array).append(l)
	_inflate(state, b, amount)
	Diplomacy.remember(state, b, a, "loan_granted")
	state.add_chronicle("%s prête %d énergie à %s, remboursables en %d mois." % [ea.short_name(), amount, eb.short_name(), int(l["m"])], Espionage.public_to(state, [a, b]))


## Une IA veut-elle cet emprunt ? (trésor bas, guerre, ou crise ; jamais au-delà de la moitié du plafond.)
static func ai_wants_loan(state: GameState, eid: int, amount: int) -> bool:
	var e := state.get_empire(eid)
	if debt(state, eid) + amount > cap(state, eid) / 2:
		return false
	return int(e.resources.get("energy", 0)) < 200 or not e.wars.is_empty() or crisis_stage(state, eid) > 0


static func check_repay(state: GameState, eid: int, lid: int, amount: int) -> String:
	if not applies(state, eid):
		return "la fiscalité n'est pas en jeu"
	var l := loan(state, eid, lid)
	if l.is_empty():
		return "emprunt inconnu"
	if amount <= 0:
		return "montant nul"
	if int(state.get_empire(eid).resources.get("energy", 0)) < mini(amount, int(l["p"])):
		return "pas assez d'énergie"
	return ""


static func repay(state: GameState, eid: int, lid: int, amount: int) -> void:
	var l := loan(state, eid, lid)
	var e := state.get_empire(eid)
	var n := mini(amount, int(l["p"]))
	e.resources["energy"] = int(e.resources.get("energy", 0)) - n
	l["p"] = int(l["p"]) - n
	if String(l["l"]) == "empire":
		var le := state.get_empire(int(l["w"]))
		if le != null and not le.eliminated:
			le.resources["energy"] = int(le.resources.get("energy", 0)) + n
	elif String(l["l"]) == "koinon" and not state.koinon.is_empty():
		var lg := Koinon.league(state, int(l["w"]))
		if not lg.is_empty():
			lg["treasury"] = int(lg.get("treasury", 0)) + n
	if int(l["p"]) <= 0:
		(_w(state, eid)["loans"] as Array).erase(l)
		if String(l["l"]) == "empire":
			Diplomacy.remember(state, int(l["w"]), eid, "loan_repaid")
		if String(l["l"]) == "house" and not state.court.is_empty():
			Court.refresh(state, eid)


static func check_repudiate(state: GameState, eid: int, lid: int) -> String:
	if not applies(state, eid) or not full(state):
		return "on ne répudie qu'en fiscalité complète"
	var l := loan(state, eid, lid)
	if l.is_empty():
		return "emprunt inconnu"
	if String(l["l"]) == "bank":
		return "on ne répudie pas sa propre banque : c'est la faillite"
	if String(l["l"]) == "koinon":
		return "on ne répudie pas le trésor fédéral : quittez plutôt le Koinon"
	if bool(talent(state, eid).get("no_repudiate", false)):
		return "votre peuple paie toujours ses dettes"
	return ""


## Répudier une dette envers une Maison ou un empire : pas de malus de faillite, mais cote D,
## motif de guerre pour le créancier, prêteurs fâchés.
static func repudiate(state: GameState, eid: int, lid: int, added: Array[Dictionary] = []) -> void:
	var l := loan(state, eid, lid)
	var en := _w(state, eid)
	(en["loans"] as Array).erase(l)
	en["hist"] = state.tick + d_int("rating", "history_days")
	var e := state.get_empire(eid)
	var who := int(l["w"])
	if String(l["l"]) == "empire":
		(state.finance["def"] as Dictionary)["%d>%d" % [eid, who]] = state.tick
		Diplomacy.remember(state, who, eid, "debt_repudiated")
		for o in state.empires:
			if o.id != eid and o.id != who and not o.eliminated and not o.is_npc() and _lends_to_anyone(state, o.id):
				Diplomacy.remember(state, o.id, eid, "debt_repudiated")
		added.append(state.add_chronicle("%s répudie sa dette envers %s : %d énergie qui ne reviendront jamais. Les banquiers de la galaxie prennent note." % [
				e.short_name(), state.get_empire(who).short_name(), int(l["p"])], Espionage.public_to(state, [eid, who])))
	elif String(l["l"]) == "house":
		FinanceBridges.house_wronged(state, eid, who, true)
		added.append(state.add_chronicle("%s refuse de rembourser une Grande Maison : %d énergie gardées, une famille perdue." % [e.short_name(), int(l["p"])], Espionage.private_to(state, [eid])))
	Deeds.note(state, eid, "repudiated")


static func _lends_to_anyone(state: GameState, eid: int) -> bool:
	for k in (state.finance["e"] as Dictionary).keys():
		for l: Dictionary in loans(state, int(k)):
			if String(l["l"]) == "empire" and int(l["w"]) == eid:
				return true
	return false


static func mint_amount(state: GameState, eid: int) -> int:
	return maxi(100, gross_energy(state, eid) * d_int("mint", "months"))


static func check_mint(state: GameState, eid: int) -> String:
	if not applies(state, eid) or not full(state):
		return "la planche à billets ne tourne qu'en fiscalité complète"
	var cd := d_int("mint", "cooldown_days")
	var last := int(entry(state, eid).get("mint_day", -100000))
	if state.tick - last < cd:
		return "une fois par an au plus (prochaine le %s)" % GameCalendar.date_string(last + cd)
	return ""


static func mint(state: GameState, eid: int) -> void:
	var e := state.get_empire(eid)
	var en := _w(state, eid)
	e.resources["energy"] = int(e.resources.get("energy", 0)) + mint_amount(state, eid)
	en["mint_day"] = state.tick
	var inf := d_int("inflation", "mint")
	if bool(talent(state, eid).get("mint_half", false)):
		@warning_ignore("integer_division")
		inf = inf / 2
	add_inflation(state, eid, inf)


# --- Franchises ---------------------------------------------------------------------------------

static func has_franchise(state: GameState, sid: int) -> bool:
	return not state.finance.is_empty() and (state.finance.get("fr", {}) as Dictionary).has(str(sid))


static func franchises_of(state: GameState, eid: int) -> Array[int]:
	var out: Array[int] = []
	if state.finance.is_empty():
		return out
	var fr: Dictionary = state.finance["fr"]
	for k in fr:
		if int(fr[k]) == eid:
			out.append(int(k))
	out.sort()
	return out


static func franchise_max(state: GameState, eid: int) -> int:
	var fc: Dictionary = data()["franchises"]
	@warning_ignore("integer_division")
	return int(fc["base"]) + Stability.systems_of(state, eid).size() / maxi(1, int(fc["per_systems"]))


static func check_franchise(state: GameState, eid: int, sid: int) -> String:
	if not applies(state, eid) or not full(state):
		return "les franchises n'existent qu'en fiscalité complète"
	if state.system_owner(sid) != eid:
		return "ce système n'est pas à vous"
	if not has_franchise(state, sid) and franchises_of(state, eid).size() >= franchise_max(state, eid):
		return "au plus %d franchises" % franchise_max(state, eid)
	if not Economy.can_afford(state.get_empire(eid), data()["franchises"]["cost"]):
		return "il faut %d influence" % int(data()["franchises"]["cost"].get("influence", 0))
	return ""


static func toggle_franchise(state: GameState, eid: int, sid: int) -> void:
	var fr: Dictionary = state.finance["fr"]
	Economy.pay(state.get_empire(eid), data()["franchises"]["cost"])
	if fr.has(str(sid)):
		fr.erase(str(sid))
	else:
		fr[str(sid)] = eid


# --- Libellés ------------------------------------------------------------------------------------

static func rate_label(bp: int) -> String:
	@warning_ignore("integer_division")
	return "%d,%02d %%" % [bp / 100, bp % 100]


static func inflation_label(v: int) -> String:
	@warning_ignore("integer_division")
	return "%d,%01d %%" % [v / 100, (v % 100) / 10]


static func lender_label(state: GameState, eid: int, l: Dictionary) -> String:
	match String(l["l"]):
		"house":
			var h := Court.house(state, eid, int(l["w"])) if not state.court.is_empty() else {}
			return String(h.get("name", "Une Grande Maison"))
		"empire":
			var o := state.get_empire(int(l["w"]))
			return o.short_name() if o != null else "?"
		"koinon":
			var lg := Koinon.league(state, int(l["w"])) if not state.koinon.is_empty() else {}
			return String(lg.get("name", "Le Koinon"))
		"company":
			return String(Private.company(state, int(l["w"])).get("n", "Une compagnie disparue"))
	return "Dette courante (Banque)" if int(l["m"]) == 0 else "Banque intérieure"
