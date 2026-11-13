class_name TradeLinks
extends RefCounted
## Commerce, lot 3B (étude « Le commerce galactique », propositions 22 à 24 ; data/trade.json,
## sections "links" et "talents") : ce qui relie le commerce aux autres piliers.
##   - Talents de peuple, par couche d'espèce (credo, gouvernement), pour marcher aussi avec les
##     peuples créés : courtiers du Profit, pèlerinages de la Foi, troc de la Survie, comptoirs du
##     Syndicat, convois rançonnés par la Horde, Ruche sans commerce civil.
##   - Espionnage : contrebande d'un luxe (state.goods.smug), délit d'initié (state.goods.insider),
##     convoi détourné (voir Espionage).
## Les lois (Protectionnisme, Compagnies à charte) passent par les effets ordinaires (Research.fx_int)
## et les actes politiques (libre-échange, embargo) par Heroes.act.

const LAYERS := ["archetype", "gouvernement", "credo", "registre"]

static var _talent_cache := {}


static func data() -> Dictionary:
	return GameData.trade()["links"]


## Talents commerciaux de l'empire (clés additionnées sur ses couches d'espèce).
static func talent(state: GameState, eid: int) -> Dictionary:
	var e := state.get_empire(eid)
	if e == null or e.is_npc():
		return {}
	var ck := "%s:%d" % [e.faction_id, GameData.factions_gen]
	if _talent_cache.has(ck):
		return _talent_cache[ck]
	var out := {}
	var sp: Dictionary = e.faction().get("species", {})
	var table: Dictionary = GameData.trade().get("talents", {})
	for layer in LAYERS:
		var t: Dictionary = (table.get(layer, {}) as Dictionary).get(String(sp.get(layer, "")), {})
		for k in t:
			if k == "label" or k == "text":
				continue
			var v: Variant = t[k]
			out[k] = v if v is bool else int(out.get(k, 0)) + int(v)
	_talent_cache[ck] = out
	return out


static func talent_int(state: GameState, eid: int, key: String) -> int:
	return int(talent(state, eid).get(key, 0))


static func has_talent(state: GameState, eid: int, key: String) -> bool:
	return bool(talent(state, eid).get(key, false))


## Talents à afficher : [[nom, texte], …].
static func talent_labels(state: GameState, eid: int) -> Array:
	var e := state.get_empire(eid)
	var out := []
	if e == null or e.is_npc():
		return out
	var sp: Dictionary = e.faction().get("species", {})
	var table: Dictionary = GameData.trade().get("talents", {})
	for layer in LAYERS:
		var t: Dictionary = (table.get(layer, {}) as Dictionary).get(String(sp.get(layer, "")), {})
		if not t.is_empty():
			out.append([String(t["label"]), String(t["text"])])
	return out


## Les deux empires partagent-ils le même credo ?
static func same_credo(state: GameState, a: int, b: int) -> bool:
	var ea := state.get_empire(a)
	var eb := state.get_empire(b)
	if ea == null or eb == null:
		return false
	var ca := String(ea.faction().get("species", {}).get("credo", ""))
	return ca != "" and ca == String(eb.faction().get("species", {}).get("credo", ""))


# --- Contrebande -------------------------------------------------------------------------------

## Luxes reçus en contrebande par l'empire.
static func smuggled(state: GameState, eid: int) -> Array[String]:
	var out: Array[String] = []
	for s: Dictionary in state.goods.get("smug", []):
		if int(s["buyer"]) == eid and not out.has(String(s["good"])):
			out.append(String(s["good"]))
	return out


## Le luxe que la contrebande prendrait à la victime ("" si aucun) : le plus rare qu'elle exploite et
## que le voleur n'a pas.
static func smuggle_pick(state: GameState, thief: int, victim: int) -> String:
	if not Goods.active(state):
		return ""
	var have := Goods.luxuries_of(state, thief)
	var own := Goods.owned(state, victim)
	var best := ""
	var tier := 0
	for g in Goods.luxury_ids():
		if int(own.get(g, 0)) > 0 and not have.has(g):
			var t := int(Goods.luxury(g).get("tier", 1))
			if t > tier:
				best = g
				tier = t
	return best


static func smuggle(state: GameState, thief: int, victim: int) -> String:
	var g := smuggle_pick(state, thief, victim)
	if g == "":
		return ""
	if not state.goods.has("smug"):
		state.goods["smug"] = []
	(state.goods["smug"] as Array).append({"buyer": thief, "seller": victim, "good": g, "until": state.tick + int(data()["smuggle_days"])})
	Goods._dirty(state)
	state.relic_rev += 1
	return g


# --- Délit d'initié ----------------------------------------------------------------------------

## Le prochain krach ou la prochaine envolée ({} si aucun dans les insider_years ans).
static func next_shock(state: GameState) -> Dictionary:
	var every := int(Goods.data()["trends"]["shock"]["every_days"])
	if every <= 0 or not Goods.market_on(state):
		return {}
	@warning_ignore("integer_division")
	var k := state.tick / every + 1
	for i in int(data()["insider_years"]):
		var s := Goods.shock_roll(state, k + i)
		if not s.is_empty():
			return s
	return {}


static func insider_of(state: GameState, eid: int) -> Dictionary:
	var d: Dictionary = state.goods.get("insider", {}).get(eid, {})
	if d.is_empty() or int(d.get("tick", 0)) < state.tick:
		return {}
	return d


static func learn_insider(state: GameState, eid: int) -> Dictionary:
	var s := next_shock(state)
	if not state.goods.has("insider"):
		state.goods["insider"] = {}
	if s.is_empty():
		state.goods["insider"].erase(eid)
	else:
		state.goods["insider"][eid] = s
	return s


# --- Convoi détourné ---------------------------------------------------------------------------

static func convoy_value(state: GameState, victim: int) -> int:
	var e := state.get_empire(victim)
	if e == null:
		return 0
	var inc := maxi(0, int(Trade.income(state, victim).get("energy", 0)))
	return mini(int(data()["convoy_max"]), mini(inc, maxi(0, int(e.resources.get("energy", 0)))))


# --- Bilan mensuel -----------------------------------------------------------------------------

static func monthly(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if state.goods.is_empty():
		return added
	var keep := []
	var changed := false
	for s: Dictionary in state.goods.get("smug", []):
		if int(s["until"]) > state.tick and int(Goods.owned(state, int(s["seller"])).get(String(s["good"]), 0)) > 0:
			keep.append(s)
		else:
			changed = true
	state.goods["smug"] = keep
	if changed:
		Goods._dirty(state)
		state.relic_rev += 1
	var ins: Dictionary = state.goods.get("insider", {})
	for eid in ins.keys():
		if int(ins[eid].get("tick", 0)) < state.tick:
			ins.erase(eid)
	return added


# --- Sauvegarde (dans celle de Goods) -------------------------------------------------------------

static func to_dict(g: Dictionary) -> Dictionary:
	var ins := []
	var ks: Array = (g.get("insider", {}) as Dictionary).keys()
	ks.sort()
	for k in ks:
		ins.append([int(k), (g["insider"][k] as Dictionary).duplicate()])
	return {"smug": (g.get("smug", []) as Array).duplicate(true), "insider": ins}


static func from_dict(g: Dictionary, d: Dictionary) -> void:
	g["smug"] = []
	for s: Dictionary in d.get("smug", []):
		var v: Dictionary = GameData._to_ints(s)
		v["good"] = String(s["good"])
		g["smug"].append(v)
	g["insider"] = {}
	for p in d.get("insider", []):
		var v: Dictionary = GameData._to_ints(p[1])
		v["res"] = String(p[1]["res"])
		g["insider"][int(p[0])] = v
