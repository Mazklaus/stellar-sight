class_name Goods
extends RefCounted
## Ressources de luxe et stratégiques, licences, monopoles, marché intérieur et contrats d'échange
## (lot 2A du commerce, data/goods.json). État dans state.goods :
##   mode : densité des gisements ("aucuns" = rien de tout cela, ni coûts en stratégiques) ;
##   market : marché intérieur actif ;
##   dep : {planet_id: bien} (luxe ou stratégique), posé à la création ;
##   lic : [{seller, buyer, good, since}] licences en cours ;
##   closed : {empire: [luxes]} luxes dont l'empire ne vend pas de licence ;
##   mono : {luxe: empire} monopoles du mois ;
##   own : {empire: {bien: gisements exploités}} (calculé chaque mois) ;
##   inc : {empire: {"energy": n}} revenu du mois (licences, monopoles, exemplaires en plus) ;
##   mkt : {empire: {ressource: facteur ‰}} ; orders : {empire: {ressource: n par mois}} ;
##   deals : contrats en cours ; offers : propositions en attente ; next : prochain identifiant.


static func data() -> Dictionary:
	return GameData.goods()


# --- Mise en place -----------------------------------------------------------------------------

static func mode_def(id: String) -> Dictionary:
	for m: Dictionary in data()["modes"]:
		if String(m["id"]) == id:
			return m
	return {}


static func mode_ids() -> Array[String]:
	var out: Array[String] = []
	for m: Dictionary in data()["modes"]:
		out.append(String(m["id"]))
	return out


## Gisements posés avec un flux aléatoire à part : la galaxie et la simulation ne changent pas.
static func setup(state: GameState, mode: String, market: bool) -> void:
	if mode_def(mode).is_empty():
		mode = "aucuns"
	state.goods = {"mode": mode, "market": market, "dep": {}, "lic": [], "closed": {}, "mono": {}, "own": {},
			"inc": {}, "mkt": {}, "orders": {}, "deals": [], "offers": [], "next": 1}
	var md := mode_def(mode)
	if int(md.get("luxury_chance", 0)) <= 0 and int(md.get("strategic_chance", 0)) <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([state.seed_value, "goods"])
	var homes := {}
	for e in state.empires:
		if e.capital_planet >= 0:
			homes[e.capital_planet] = true
	var lux_w := []
	for l: Dictionary in data()["luxuries"]:
		lux_w.append([String(l["id"]), int(tier_def(int(l["tier"])).get("weight", 1))])
	var str_w := []
	for s: Dictionary in data()["strategic"]:
		str_w.append([String(s["id"]), 5 - int(s["era"])])
	for sys in state.galaxy.systems:
		for pid in sys.planet_ids:
			if homes.has(pid):
				continue
			var roll := rng.randi_range(1, 100)
			if roll <= int(md["luxury_chance"]):
				state.goods["dep"][pid] = _weighted(rng, lux_w)
			elif roll <= int(md["luxury_chance"]) + int(md["strategic_chance"]):
				state.goods["dep"][pid] = _weighted(rng, str_w)


static func _weighted(rng: RandomNumberGenerator, items: Array) -> String:
	var total := 0
	for it in items:
		total += int(it[1])
	var r := rng.randi_range(1, total)
	for it in items:
		r -= int(it[1])
		if r <= 0:
			return String(it[0])
	return String(items[0][0])


## Luxes et stratégiques en jeu ?
static func active(state: GameState) -> bool:
	return String(state.goods.get("mode", "aucuns")) != "aucuns"


static func market_on(state: GameState) -> bool:
	return bool(state.goods.get("market", false))


# --- Définitions -------------------------------------------------------------------------------

static func tier_def(n: int) -> Dictionary:
	for t: Dictionary in data()["tiers"]:
		if int(t["id"]) == n:
			return t
	return {}


static func luxury(id: String) -> Dictionary:
	for l: Dictionary in data()["luxuries"]:
		if String(l["id"]) == id:
			return l
	return {}


static func strategic(id: String) -> Dictionary:
	for s: Dictionary in data()["strategic"]:
		if String(s["id"]) == id:
			return s
	return {}


static func is_luxury(id: String) -> bool:
	return not luxury(id).is_empty()


static func luxury_ids() -> Array[String]:
	var out: Array[String] = []
	for l: Dictionary in data()["luxuries"]:
		out.append(String(l["id"]))
	return out


static func label(id: String) -> String:
	var d := luxury(id)
	if d.is_empty():
		d = strategic(id)
	return String(d.get("label", id))


## Bien d'une planète ("" si aucun).
static func deposit_of(state: GameState, pid: int) -> String:
	return String(state.goods.get("dep", {}).get(pid, ""))


## Ligne lisible du gisement d'une planète, pour les fiches ("" si aucun).
static func deposit_text(state: GameState, pid: int) -> String:
	var g := deposit_of(state, pid)
	if g == "":
		return ""
	if is_luxury(g):
		return "Luxe (%s) : %s" % [String(tier_def(int(luxury(g)["tier"]))["label"]).to_lower(), label(g)]
	return "Stratégique (ère %d) : %s" % [int(strategic(g)["era"]), label(g)]


# --- Exploitation (calculée chaque mois) -------------------------------------------------------

## Gisements exploités : {bien: {empire: n}} (colonie ou avant-poste établi d'un empire).
static func exploited(state: GameState) -> Dictionary:
	var out := {}
	var dep: Dictionary = state.goods.get("dep", {})
	var ids := dep.keys()
	ids.sort()
	for pid in ids:
		var c: Colony = state.colonies.get(int(pid))
		if c == null or not c.is_established() or c.owner < 0 or GameState.is_npc(c.owner):
			continue
		var g := String(dep[pid])
		var m: Dictionary = out.get(g, {})
		m[c.owner] = int(m.get(c.owner, 0)) + 1
		out[g] = m
	return out


## Gisements exploités par l'empire : {bien: n} (au dernier bilan).
static func owned(state: GameState, eid: int) -> Dictionary:
	return state.goods.get("own", {}).get(eid, {})


## Licences achetées par l'empire (luxes).
static func licences_bought(state: GameState, eid: int) -> Array[String]:
	var out: Array[String] = []
	for l: Dictionary in state.goods.get("lic", []):
		if int(l["buyer"]) == eid and not out.has(String(l["good"])):
			out.append(String(l["good"]))
	return out


static func licences_sold(state: GameState, eid: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l: Dictionary in state.goods.get("lic", []):
		if int(l["seller"]) == eid:
			out.append(l)
	return out


## Luxes dont l'empire profite (gisement ou licence), triés. Gardés en cache (lus à chaque calcul de
## stabilité) jusqu'au prochain changement d'exploitation ou de licence (_dirty).
static func luxuries_of(state: GameState, eid: int) -> Array[String]:
	var cache: Dictionary = state.goods.get("_lux", {})
	if cache.has(eid):
		return cache[eid]
	var out: Array[String] = []
	var own := owned(state, eid)
	var bought := licences_bought(state, eid)
	for g in luxury_ids():
		if int(own.get(g, 0)) > 0 or bought.has(g):
			out.append(g)
	if not state.goods.is_empty():
		cache[eid] = out
		state.goods["_lux"] = cache
	return out


static func _dirty(state: GameState) -> void:
	state.goods.erase("_lux")


static func has_luxury(state: GameState, eid: int, good: String) -> bool:
	return luxuries_of(state, eid).has(good)


## Effets des luxes (mêmes clés que les technologies ; fusionnés par Research.effects).
static func effects(state: GameState, eid: int) -> Dictionary:
	var out := {}
	if not active(state):
		return out
	for g in luxuries_of(state, eid):
		Research._merge(out, luxury(g).get("fx", {}))
	return out


## Stabilité de la diversité des luxes : une ligne par empire.
static func stability_parts(state: GameState, eid: int) -> Array:
	if not active(state):
		return []
	var lux := luxuries_of(state, eid)
	if lux.is_empty():
		return []
	var v := 0
	for g in lux:
		v += int(tier_def(int(luxury(g)["tier"])).get("stability", 0))
	return [["Luxes (%d)" % lux.size(), v]]


## Revenu mensuel des luxes (licences, monopoles, exemplaires en plus), calculé au dernier bilan.
static func income(state: GameState, eid: int) -> Dictionary:
	return state.goods.get("inc", {}).get(eid, {})


## Bilan du mois : exploitation, stratégiques, licences, monopoles, contrats, marché.
static func monthly(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if state.goods.is_empty():
		return added
	var before := {}
	for e in state.empires:
		before[e.id] = luxuries_of(state, e.id)
	var ex := exploited(state)
	var own := {}
	for g in ex:
		for eid in ex[g]:
			var m: Dictionary = own.get(int(eid), {})
			m[String(g)] = int(ex[g][eid])
			own[int(eid)] = m
	state.goods["own"] = own
	_dirty(state)
	var inc := {}
	if active(state):
		_strategic_yields(state, own)
		_check_licences(state, added)
		_licence_income(state, inc)
		_monopolies(state, ex, inc, added)
		# Exemplaires en plus : chacun se vend un peu.
		for eid in own:
			var n := 0
			for g in own[eid]:
				if is_luxury(String(g)):
					n += maxi(0, int(own[eid][g]) - 1)
			if n > 0:
				_add_inc(inc, int(eid), n * int(data()["extra_energy"]))
	state.goods["inc"] = inc
	_run_deals(state, added)
	_expire_offers(state)
	if market_on(state):
		_market_month(state, added)
	var changed := false
	for e in state.empires:
		if str(before.get(e.id, [])) != str(luxuries_of(state, e.id)):
			changed = true
	if changed:
		state.relic_rev += 1
	return added


static func _add_inc(inc: Dictionary, eid: int, n: int) -> void:
	var m: Dictionary = inc.get(eid, {})
	m["energy"] = int(m.get("energy", 0)) + n
	inc[eid] = m


static func _strategic_yields(state: GameState, own: Dictionary) -> void:
	for eid in own:
		var e := state.get_empire(int(eid))
		if e == null or e.eliminated:
			continue
		for g in own[eid]:
			var sd := strategic(String(g))
			if sd.is_empty() or Research.current_era(state, e.id) < int(sd["era"]):
				continue
			e.resources[String(g)] = int(e.resources.get(String(g), 0)) + int(own[eid][g])


## Le gisement d'un stratégique compte-t-il déjà pour cet empire (ère atteinte) ?
static func strategic_open(state: GameState, eid: int, good: String) -> bool:
	var sd := strategic(good)
	return not sd.is_empty() and Research.current_era(state, eid) >= int(sd["era"])


# --- Monopoles ---------------------------------------------------------------------------------

static func _monopolies(state: GameState, ex: Dictionary, inc: Dictionary, added: Array[Dictionary]) -> void:
	var md: Dictionary = data()["monopoly"]
	var old: Dictionary = state.goods.get("mono", {})
	var mono := {}
	for g in luxury_ids():
		var m: Dictionary = ex.get(g, {})
		var total := 0
		for eid in m:
			total += int(m[eid])
		if total < int(md["min_deposits"]):
			continue
		var ids := m.keys()
		ids.sort()
		for eid in ids:
			var n := int(m[eid])
			@warning_ignore("integer_division")
			var share := n * 100 / total
			if n >= int(md["min_deposits"]) and share >= int(md["share_pct"]):
				mono[g] = int(eid)
				var gain := 0
				for step in md["income"]:
					if share >= int(step[0]):
						gain = int(step[1])
				_add_inc(inc, int(eid), gain)
				if int(old.get(g, -1)) != int(eid):
					var e := state.get_empire(int(eid))
					added.append(state.add_chronicle("%s tient désormais le monopole %s. Les prix suivront, et les rancunes aussi." % [
							e.display_name(), _of(label(g))], Espionage.public_to(state, [int(eid)])))
					for o in state.empires:
						if o.id != int(eid) and not o.eliminated and o.contacts.has(int(eid)):
							Diplomacy.remember(state, o.id, int(eid), "hoarder")
	state.goods["mono"] = mono


static func _of(name: String) -> String:
	var first := name.substr(0, 1).to_lower()
	if "aeiouéèêh".contains(first):
		return "de l'" + name
	return "du " + name if not name.ends_with("s") else "des " + name


static func monopoly_of(state: GameState, good: String) -> int:
	return int(state.goods.get("mono", {}).get(good, -1))


# --- Licences ----------------------------------------------------------------------------------

## Prix mensuel d'une licence du vendeur à l'acheteur, en énergie.
static func licence_price(state: GameState, seller: int, buyer: int, good: String) -> int:
	var ld: Dictionary = data()["licence"]
	var p := int(tier_def(int(luxury(good).get("tier", 1))).get("licence_price", 3))
	var a := FactionTraits.capital_system(state, seller)
	var b := FactionTraits.capital_system(state, buyer)
	if a >= 0 and b >= 0:
		@warning_ignore("integer_division")
		p += int(FactionTraits.jumps_from(state.galaxy, a).get(b, 0)) / maxi(1, int(ld["per_jumps"]))
	if monopoly_of(state, good) == seller:
		@warning_ignore("integer_division")
		p = p * int(data()["monopoly"]["licence_mult_pct"]) / 100
	return p


static func sells_licence(state: GameState, seller: int, good: String) -> bool:
	return not (state.goods.get("closed", {}).get(seller, []) as Array).has(good)


## L'acheteur peut-il prendre une licence de ce luxe chez ce vendeur ? "" si oui.
static func check_licence(state: GameState, buyer: int, seller: int, good: String) -> String:
	if not active(state):
		return "pas de luxes dans cette partie"
	var b := state.get_empire(buyer)
	var s := state.get_empire(seller)
	if b == null or s == null or buyer == seller or s.eliminated:
		return "empire inconnu"
	if not is_luxury(good):
		return "luxe inconnu"
	if Trade.tier(state, buyer, seller) <= 0:
		return "il faut un traité de commerce avec cet empire"
	if Trade.embargoed(state, buyer, seller):
		return "un embargo interdit tout commerce"
	if int(owned(state, seller).get(good, 0)) <= 0:
		return "cet empire n'exploite pas ce luxe"
	if has_luxury(state, buyer, good):
		return "vous en profitez déjà"
	if not sells_licence(state, seller, good):
		return "cet empire ne vend pas ce luxe"
	if s.is_ai() and not AiGoods.sells_to(state, seller, buyer):
		return "%s refuse de vous vendre ses luxes" % s.short_name()
	if int(b.resources.get("energy", 0)) < licence_price(state, seller, buyer, good):
		return "pas assez d'énergie pour le premier mois (%d)" % licence_price(state, seller, buyer, good)
	return ""


static func buy_licence(state: GameState, buyer: int, seller: int, good: String) -> void:
	state.goods["lic"].append({"seller": seller, "buyer": buyer, "good": good, "since": state.tick})
	_dirty(state)
	var price := licence_price(state, seller, buyer, good)
	state.get_empire(buyer).resources["energy"] = int(state.get_empire(buyer).resources.get("energy", 0)) - price
	state.get_empire(seller).resources["energy"] = int(state.get_empire(seller).resources.get("energy", 0)) + price
	state.relic_rev += 1
	state.add_chronicle("%s achète à %s une licence %s." % [state.get_empire(buyer).display_name(), state.get_empire(seller).display_name(), _of(label(good))],
			Espionage.private_to(state, [buyer, seller]))


static func check_cancel_licence(state: GameState, eid: int, other: int, good: String) -> String:
	for l: Dictionary in state.goods.get("lic", []):
		if String(l["good"]) == good and ((int(l["buyer"]) == eid and int(l["seller"]) == other) or (int(l["seller"]) == eid and int(l["buyer"]) == other)):
			return ""
	return "aucune licence de ce luxe entre vous"


static func cancel_licence(state: GameState, eid: int, other: int, good: String) -> void:
	var keep := []
	for l: Dictionary in state.goods.get("lic", []):
		if String(l["good"]) == good and ((int(l["buyer"]) == eid and int(l["seller"]) == other) or (int(l["seller"]) == eid and int(l["buyer"]) == other)):
			continue
		keep.append(l)
	state.goods["lic"] = keep
	_dirty(state)
	state.relic_rev += 1


static func set_closed(state: GameState, eid: int, good: String, closed: bool) -> void:
	var c: Dictionary = state.goods.get("closed", {})
	var l: Array = c.get(eid, [])
	if closed and not l.has(good):
		l.append(good)
		l.sort()
	elif not closed:
		l.erase(good)
	if l.is_empty():
		c.erase(eid)
	else:
		c[eid] = l
	state.goods["closed"] = c


## Licences devenues impossibles (plus de traité, embargo, plus de gisement, guerre) : elles tombent.
static func _check_licences(state: GameState, added: Array[Dictionary]) -> void:
	var keep := []
	for l: Dictionary in state.goods.get("lic", []):
		var s := int(l["seller"])
		var b := int(l["buyer"])
		var se := state.get_empire(s)
		var be := state.get_empire(b)
		var ok := se != null and be != null and not se.eliminated and not be.eliminated and Trade.tier(state, s, b) > 0 \
				and not Trade.embargoed(state, s, b) and int(owned(state, s).get(String(l["good"]), 0)) > 0 \
				and int(be.resources.get("energy", 0)) >= licence_price(state, s, b, String(l["good"]))
		if ok:
			keep.append(l)
		elif be != null and se != null:
			added.append(state.add_chronicle("La licence %s que %s achetait à %s prend fin." % [_of(label(String(l["good"]))), be.display_name(), se.display_name()],
					Espionage.private_to(state, [s, b])))
	state.goods["lic"] = keep
	_dirty(state)


static func _licence_income(state: GameState, inc: Dictionary) -> void:
	for l: Dictionary in state.goods.get("lic", []):
		var p := licence_price(state, int(l["seller"]), int(l["buyer"]), String(l["good"]))
		_add_inc(inc, int(l["seller"]), p)
		_add_inc(inc, int(l["buyer"]), -p)


## Licences entre deux empires (dans les deux sens) : chacune ajoute de la valeur à leurs routes.
static func licences_between(state: GameState, a: int, b: int) -> int:
	var n := 0
	for l: Dictionary in state.goods.get("lic", []):
		if (int(l["buyer"]) == a and int(l["seller"]) == b) or (int(l["buyer"]) == b and int(l["seller"]) == a):
			n += 1
	return n


# --- Coûts en stratégiques ---------------------------------------------------------------------

## Stratégiques d'un module pour une taille de coque ({} si aucun).
static func module_strategic(mid: String, size: String) -> Dictionary:
	var m: Dictionary = data()["strategic_costs"]["modules"].get(mid, {})
	return m.get(size, {})


static func building_strategic(bid: String) -> Dictionary:
	return data()["strategic_costs"]["buildings"].get(bid, {})


## Ajoute à un coût les stratégiques demandés, si les stratégiques sont en jeu.
static func with_strategic(state: GameState, cost: Dictionary, extra: Dictionary) -> Dictionary:
	if extra.is_empty() or not active(state):
		return cost
	var out := cost.duplicate()
	for r in extra:
		out[r] = int(out.get(r, 0)) + int(extra[r])
	return out


# --- Marché intérieur --------------------------------------------------------------------------

## Ressources qui se vendent et s'achètent au marché.
static func market_ids(state: GameState) -> Array[String]:
	var out: Array[String] = []
	for r in data()["market"]["prices"]:
		out.append(String(r))
	if active(state):
		out.append_array(GameData.strategic_ids())
	return out


static func base_price(res: String) -> int:
	var p: Dictionary = data()["market"]["prices"]
	if p.has(res):
		return int(p[res])
	return int(strategic(res).get("price", 0))


static func price_mult(state: GameState, eid: int, res: String) -> int:
	return int(state.goods.get("mkt", {}).get(eid, {}).get(res, 1000))


static func fee_pct(state: GameState, eid: int) -> int:
	var md: Dictionary = data()["market"]
	return maxi(int(md["min_fee_pct"]), int(md["base_fee_pct"]) + Research.fx_int(state, eid, "market_fee_pct"))


## Facteur de prix après un échange de n unités (n > 0 achat, n < 0 vente).
static func _moved(mult: int, n: int) -> int:
	var md: Dictionary = data()["market"]
	@warning_ignore("integer_division")
	var steps := absi(n) / maxi(1, int(md["impact_per"]))
	var d := steps * int(md["impact_per_mille"]) * (1 if n > 0 else -1)
	return clampi(mult + d, int(md["min_mult"]), int(md["max_mult"]))


## Prix moyen des n unités, au facteur moyen entre avant et après (en énergie, arrondi).
@warning_ignore("integer_division")
static func _raw(state: GameState, eid: int, res: String, n: int) -> int:
	var m0 := price_mult(state, eid, res)
	var m1 := _moved(m0, n)
	return absi(n) * base_price(res) * (m0 + m1) / 2 / 1000


## Coût en énergie de n unités achetées (frais compris).
@warning_ignore("integer_division")
static func buy_cost(state: GameState, eid: int, res: String, n: int) -> int:
	return maxi(1, _raw(state, eid, res, n) * (100 + fee_pct(state, eid)) / 100)


## Énergie touchée pour n unités vendues (frais déduits).
@warning_ignore("integer_division")
static func sell_gain(state: GameState, eid: int, res: String, n: int) -> int:
	return _raw(state, eid, res, -n) * (100 - fee_pct(state, eid)) / 100


static func check_market(state: GameState, eid: int, res: String, n: int) -> String:
	var e := state.get_empire(eid)
	if e == null or e.eliminated:
		return "empire inconnu"
	if not market_on(state):
		return "pas de marché dans cette partie"
	if not market_ids(state).has(res):
		return "cette ressource ne se vend pas au marché"
	if n == 0 or absi(n) > 10000:
		return "quantité impossible"
	if n > 0 and int(e.resources.get("energy", 0)) < buy_cost(state, eid, res, n):
		return "pas assez d'énergie (%d)" % buy_cost(state, eid, res, n)
	if n < 0 and int(e.resources.get(res, 0)) < -n:
		return "pas assez de %s" % GameData.resource_label(res).to_lower()
	return ""


static func trade_market(state: GameState, eid: int, res: String, n: int) -> void:
	var e := state.get_empire(eid)
	if n > 0:
		e.resources["energy"] = int(e.resources.get("energy", 0)) - buy_cost(state, eid, res, n)
	else:
		e.resources["energy"] = int(e.resources.get("energy", 0)) + sell_gain(state, eid, res, -n)
	e.resources[res] = int(e.resources.get(res, 0)) + n
	var mk: Dictionary = state.goods.get("mkt", {})
	var m: Dictionary = mk.get(eid, {})
	m[res] = _moved(price_mult(state, eid, res), n)
	mk[eid] = m
	state.goods["mkt"] = mk


## Ordre mensuel : n unités achetées (n > 0) ou vendues (n < 0) à chaque bilan ; 0 l'annule.
static func check_order(state: GameState, eid: int, res: String, n: int) -> String:
	if state.get_empire(eid) == null:
		return "empire inconnu"
	if not market_on(state):
		return "pas de marché dans cette partie"
	if not market_ids(state).has(res):
		return "cette ressource ne se vend pas au marché"
	if absi(n) > 1000:
		return "quantité impossible"
	return ""


static func set_order(state: GameState, eid: int, res: String, n: int) -> void:
	var o: Dictionary = state.goods.get("orders", {})
	var m: Dictionary = o.get(eid, {})
	if n == 0:
		m.erase(res)
	else:
		m[res] = n
	if m.is_empty():
		o.erase(eid)
	else:
		o[eid] = m
	state.goods["orders"] = o


static func order_of(state: GameState, eid: int, res: String) -> int:
	return int(state.goods.get("orders", {}).get(eid, {}).get(res, 0))


static func _market_month(state: GameState, added: Array[Dictionary]) -> void:
	# Les prix reviennent vers leur base, puis les ordres mensuels passent.
	var md: Dictionary = data()["market"]
	var mk: Dictionary = state.goods.get("mkt", {})
	for eid in mk.keys():
		var m: Dictionary = mk[eid]
		for res in m.keys():
			@warning_ignore("integer_division")
			var v := int(m[res]) + (1000 - int(m[res])) * int(md["recover_pct"]) / 100
			if absi(v - 1000) < 5:
				m.erase(res)
			else:
				m[res] = v
		if m.is_empty():
			mk.erase(eid)
	var orders: Dictionary = state.goods.get("orders", {})
	var ids := orders.keys()
	ids.sort()
	for eid in ids:
		var m: Dictionary = orders[eid]
		var rs := m.keys()
		rs.sort()
		for res in rs:
			var n := int(m[res])
			if check_market(state, int(eid), String(res), n) == "":
				trade_market(state, int(eid), String(res), n)


# --- Contrats d'échange entre empires ----------------------------------------------------------

## Valeur en énergie d'un lot de ressources, aux prix du marché de l'empire.
static func value_of(state: GameState, eid: int, amounts: Dictionary) -> int:
	var v := 0
	for r in amounts:
		var p := base_price(String(r))
		if String(r) == "energy":
			p = 1
		elif String(r) == "influence":
			p = 4
		elif String(r) == "knowledge":
			p = 2
		@warning_ignore("integer_division")
		v += int(amounts[r]) * p * price_mult(state, eid, String(r)) / 1000
	return v


static func _clean(amounts: Dictionary) -> Dictionary:
	var out := {}
	for r in amounts:
		if int(amounts[r]) > 0 and GameData.stock_ids().has(String(r)) and String(r) != "knowledge":
			out[String(r)] = int(amounts[r])
	return out


static func check_offer(state: GameState, from: int, to: int, give: Dictionary, get_: Dictionary, months: int) -> String:
	var a := state.get_empire(from)
	var b := state.get_empire(to)
	if a == null or b == null or from == to or b.eliminated or a.eliminated:
		return "empire inconnu"
	if not a.contacts.has(to):
		return "vous n'avez jamais rencontré cet empire"
	if Combat.at_war(state, from, to):
		return "pas d'échange avec un ennemi"
	if Trade.embargoed(state, from, to):
		return "un embargo interdit tout commerce"
	if Diplomacy.no_treaties(state, from) or Diplomacy.no_treaties(state, to):
		return "l'Essaim n'échange rien"
	var g := _clean(give)
	var t := _clean(get_)
	if g.is_empty() and t.is_empty():
		return "l'échange est vide"
	if months != 0 and (months < 12 or months > int(data()["deals"]["max_months"])):
		return "durée impossible (un an à dix ans)"
	for r in g:
		if int(a.resources.get(r, 0)) < int(g[r]):
			return "pas assez de %s" % GameData.resource_label(r).to_lower()
	for o: Dictionary in state.goods.get("offers", []):
		if int(o["from"]) == from and int(o["to"]) == to:
			return "une proposition attend déjà sa réponse"
	return ""


## Propose un échange. Une IA répond tout de suite ; un joueur humain a proposal_days jours.
## Renvoie true si l'échange est conclu.
static func offer(state: GameState, from: int, to: int, give: Dictionary, get_: Dictionary, months: int) -> bool:
	var o := {"id": int(state.goods.get("next", 1)), "from": from, "to": to, "give": _clean(give), "get": _clean(get_), "months": months, "tick": state.tick}
	state.goods["next"] = int(o["id"]) + 1
	if state.get_empire(to).is_ai():
		var ev := AiGoods.evaluate_offer(state, to, o)
		if int(ev["score"]) >= 0:
			_conclude(state, o)
			return true
		if not state.get_empire(from).is_ai():
			state.add_chronicle("%s décline l'échange proposé par %s." % [state.get_empire(to).display_name(), state.get_empire(from).display_name()],
					Espionage.private_to(state, [from, to]))
		return false
	state.goods["offers"].append(o)
	return false


static func offer_by_id(state: GameState, id: int) -> Dictionary:
	for o: Dictionary in state.goods.get("offers", []):
		if int(o["id"]) == id:
			return o
	return {}


static func offers_to(state: GameState, eid: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for o: Dictionary in state.goods.get("offers", []):
		if int(o["to"]) == eid:
			out.append(o)
	return out


static func check_answer(state: GameState, eid: int, id: int, accept: bool) -> String:
	var o := offer_by_id(state, id)
	if o.is_empty() or int(o["to"]) != eid:
		return "proposition inconnue"
	if accept:
		var why := check_offer(state, int(o["from"]), eid, {}, {"energy": 1}, 0)
		if why != "" and why != "une proposition attend déjà sa réponse":
			return why
		for r in o["get"]:
			if int(state.get_empire(eid).resources.get(r, 0)) < int(o["get"][r]):
				return "pas assez de %s" % GameData.resource_label(String(r)).to_lower()
		for r in o["give"]:
			if int(state.get_empire(int(o["from"])).resources.get(r, 0)) < int(o["give"][r]):
				return "l'autre partie n'a plus de quoi payer"
	return ""


static func answer(state: GameState, id: int, accept: bool) -> void:
	var o := offer_by_id(state, id)
	state.goods["offers"].erase(o)
	if accept:
		_conclude(state, o)
	else:
		state.add_chronicle("%s décline l'échange proposé par %s." % [state.get_empire(int(o["to"])).display_name(), state.get_empire(int(o["from"])).display_name()],
				Espionage.private_to(state, [int(o["from"]), int(o["to"])]))


static func _expire_offers(state: GameState) -> void:
	var keep := []
	for o: Dictionary in state.goods.get("offers", []):
		if state.tick - int(o["tick"]) < int(data()["deals"]["proposal_days"]):
			keep.append(o)
	state.goods["offers"] = keep


static func _transfer(state: GameState, from: int, to: int, amounts: Dictionary) -> bool:
	var a := state.get_empire(from)
	var b := state.get_empire(to)
	for r in amounts:
		if int(a.resources.get(r, 0)) < int(amounts[r]):
			return false
	for r in amounts:
		a.resources[r] = int(a.resources.get(r, 0)) - int(amounts[r])
		b.resources[r] = int(b.resources.get(r, 0)) + int(amounts[r])
	return true


static func _conclude(state: GameState, o: Dictionary) -> void:
	var a := int(o["from"])
	var b := int(o["to"])
	_transfer(state, a, b, o["give"])
	_transfer(state, b, a, o["get"])
	var months := int(o["months"])
	if months > 0:
		state.goods["deals"].append({"id": int(o["id"]), "a": a, "b": b, "give": o["give"], "get": o["get"], "left": months - 1, "since": state.tick})
	state.add_chronicle("%s et %s concluent un échange%s : %s contre %s." % [state.get_empire(a).display_name(), state.get_empire(b).display_name(),
			(" pour %d mois" % months) if months > 0 else "", GameData.format_amounts(o["give"]) if not o["give"].is_empty() else "rien",
			GameData.format_amounts(o["get"]) if not o["get"].is_empty() else "rien"], Espionage.private_to(state, [a, b]))


static func deals_of(state: GameState, eid: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for d: Dictionary in state.goods.get("deals", []):
		if int(d["a"]) == eid or int(d["b"]) == eid:
			out.append(d)
	return out


static func check_cancel_deal(state: GameState, eid: int, id: int) -> String:
	for d: Dictionary in state.goods.get("deals", []):
		if int(d["id"]) == id and (int(d["a"]) == eid or int(d["b"]) == eid):
			return ""
	return "contrat inconnu"


static func cancel_deal(state: GameState, eid: int, id: int) -> void:
	for d: Dictionary in state.goods.get("deals", []):
		if int(d["id"]) == id:
			var other := int(d["b"]) if int(d["a"]) == eid else int(d["a"])
			state.goods["deals"].erase(d)
			Diplomacy.remember(state, other, eid, "deal_broken")
			state.add_chronicle("%s rompt son contrat d'échange avec %s." % [state.get_empire(eid).display_name(), state.get_empire(other).display_name()],
					Espionage.private_to(state, [eid, other]))
			return


static func _run_deals(state: GameState, added: Array[Dictionary]) -> void:
	var keep := []
	for d: Dictionary in state.goods.get("deals", []):
		var a := int(d["a"])
		var b := int(d["b"])
		var ea := state.get_empire(a)
		var eb := state.get_empire(b)
		if ea == null or eb == null or ea.eliminated or eb.eliminated or Combat.at_war(state, a, b) or Trade.embargoed(state, a, b):
			continue
		var ok_a := true
		for r in d["give"]:
			if int(ea.resources.get(r, 0)) < int(d["give"][r]):
				ok_a = false
		var ok_b := true
		for r in d["get"]:
			if int(eb.resources.get(r, 0)) < int(d["get"][r]):
				ok_b = false
		if not ok_a or not ok_b:
			var bad := a if not ok_a else b
			var other := b if bad == a else a
			Diplomacy.remember(state, other, bad, "deal_broken")
			added.append(state.add_chronicle("%s ne peut plus honorer son contrat d'échange avec %s : il prend fin." % [
					state.get_empire(bad).display_name(), state.get_empire(other).display_name()], Espionage.private_to(state, [a, b])))
			continue
		_transfer(state, a, b, d["give"])
		_transfer(state, b, a, d["get"])
		d["left"] = int(d["left"]) - 1
		if int(d["left"]) > 0:
			keep.append(d)
	state.goods["deals"] = keep


# --- Sauvegarde --------------------------------------------------------------------------------

static func to_dict(state: GameState) -> Dictionary:
	var g: Dictionary = state.goods
	if g.is_empty():
		return {}
	return {"mode": g.get("mode", "aucuns"), "market": g.get("market", false), "dep": _pairs(g.get("dep", {})),
			"lic": (g.get("lic", []) as Array).duplicate(true), "closed": _pairs(g.get("closed", {})), "mono": _pairs(g.get("mono", {})),
			"own": _pairs(g.get("own", {})), "inc": _pairs(g.get("inc", {})), "mkt": _pairs(g.get("mkt", {})), "orders": _pairs(g.get("orders", {})),
			"deals": (g.get("deals", []) as Array).duplicate(true), "offers": (g.get("offers", []) as Array).duplicate(true), "next": int(g.get("next", 1))}


static func from_dict(state: GameState, d: Dictionary) -> void:
	if d.is_empty():
		setup(state, "aucuns", false)
		return
	var g := {"mode": String(d.get("mode", "aucuns")), "market": bool(d.get("market", false)), "next": int(d.get("next", 1))}
	g["dep"] = _unpairs(d.get("dep", []), false)
	g["closed"] = _unpairs(d.get("closed", []), false)
	g["mono"] = {}
	for p in d.get("mono", []):
		g["mono"][String(p[0])] = int(p[1])
	g["own"] = _unpairs(d.get("own", []), true)
	g["inc"] = _unpairs(d.get("inc", []), true)
	g["mkt"] = _unpairs(d.get("mkt", []), true)
	g["orders"] = _unpairs(d.get("orders", []), true)
	for k in ["lic", "deals", "offers"]:
		var out := []
		for it: Dictionary in d.get(k, []):
			var v: Dictionary = GameData._to_ints(it)
			if v.has("good"):
				v["good"] = String(it["good"])
			for sub in ["give", "get"]:
				if it.has(sub):
					var m := {}
					for r in it[sub]:
						m[String(r)] = int(it[sub][r])
					v[sub] = m
			out.append(v)
		g[k] = out
	state.goods = g


## {int: valeur} -> [[clé, valeur], …] trié, pour le JSON.
static func _pairs(d: Dictionary) -> Array:
	var ids := d.keys()
	ids.sort()
	var out := []
	for k in ids:
		var v: Variant = d[k]
		out.append([k, v.duplicate(true) if v is Dictionary or v is Array else v])
	return out


## Inverse de _pairs : clés entières ; sub = valeurs {texte: entier}.
static func _unpairs(a: Array, sub: bool) -> Dictionary:
	var out := {}
	for p in a:
		var v: Variant = p[1]
		if sub and v is Dictionary:
			var m := {}
			for r in v:
				m[String(r)] = int(v[r])
			v = m
		elif v is Array:
			var l := []
			for x in v:
				l.append(String(x))
			v = l
		elif v is String:
			v = String(v)
		out[int(p[0])] = v
	return out
