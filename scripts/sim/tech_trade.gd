class_name TechTrade
extends RefCounted
## Commerce, lot 3A (étude « Le commerce galactique », propositions 17 à 19 ; data/trade.json,
## section "research") : le Savoir circule entre empires, sans échange brut de technologies.
##   - Accord de recherche (Civilization V) : deux empires en paix depuis un an paient chacun de
##     l'énergie ; trois ans plus tard, chacun reçoit un bond de Savoir sur sa recherche en cours. La
##     guerre l'annule et l'énergie est perdue.
##   - Licence de technologie (Civilization IV, option sans courtage) : un partenaire commercial vend
##     une technologie qu'il a trouvée lui-même ; l'acheteur reçoit une part de son coût en Savoir et
##     la paie en énergie au vendeur.
##   - Diffusion (Civilization VI) : une route vers un empire plus avancé rapporte du Savoir (voir
##     Trade.compute, qui appelle diffusion()).
## État dans state.goods (sauvegardé par Goods) :
##   pacts : [{id, a, b, start, end}] accords en cours ;
##   toff : [{id, kind ("pact" | "licence"), from, to, tech, until}] propositions qui attendent la
##          réponse d'un joueur humain (l'IA répond aussitôt) ;
##   tlic : {empire: [technologies obtenues par licence]} (elles ne se revendent pas).
## Les identifiants viennent du compteur partagé state.goods["next"].


static func data() -> Dictionary:
	return GameData.trade()["research"]


static func _ok_empire(state: GameState, eid: int) -> bool:
	var e := state.get_empire(eid)
	return e != null and not e.eliminated and not e.is_npc()


static func _next_id(state: GameState) -> int:
	var id := int(state.goods.get("next", 1))
	state.goods["next"] = id + 1
	return id


static func _list(state: GameState, key: String) -> Array:
	if not state.goods.has(key):
		state.goods[key] = []
	return state.goods[key]


# --- Accords de recherche ------------------------------------------------------------------------

static func pact_era(state: GameState, a: int, b: int) -> int:
	return maxi(Research.current_era(state, a), Research.current_era(state, b))


## Énergie que paie chacun des deux empires.
static func pact_cost(state: GameState, a: int, b: int) -> int:
	var c: Dictionary = data()["pact_cost"]
	return int(c["base"]) + int(c["per_era"]) * pact_era(state, a, b)


## Savoir reçu par l'empire à la fin de l'accord.
static func pact_bonus(state: GameState, eid: int) -> int:
	var c: Dictionary = data()["pact_bonus"]
	return int(c["base"]) + int(c["per_era"]) * Research.current_era(state, eid)


static func pacts_of(state: GameState, eid: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Dictionary in state.goods.get("pacts", []):
		if int(p["a"]) == eid or int(p["b"]) == eid:
			out.append(p)
	return out


static func pact_between(state: GameState, a: int, b: int) -> Dictionary:
	for p in pacts_of(state, a):
		if int(p["a"]) == b or int(p["b"]) == b:
			return p
	return {}


static func _pending(state: GameState, kind: String, a: int, b: int, tech := "") -> bool:
	for o: Dictionary in state.goods.get("toff", []):
		if String(o["kind"]) == kind and String(o.get("tech", "")) == tech \
				and ((int(o["from"]) == a and int(o["to"]) == b) or (kind == "pact" and int(o["from"]) == b and int(o["to"]) == a)):
			return true
	return false


## Peut-on proposer (ou conclure) un accord de recherche entre ces deux empires ? "" si oui.
static func check_pact(state: GameState, a: int, b: int, offer := true) -> String:
	if not _ok_empire(state, a) or not _ok_empire(state, b) or a == b:
		return "empire inconnu"
	if not state.get_empire(a).contacts.has(b):
		return "pas de contact"
	if Combat.at_war(state, a, b) or not Diplomacy.has_pact(state, a, b):
		return "il faut la paix"
	var need := int(data()["pact_peace_days"])
	if Diplomacy.pact_days(state, a, b) < need:
		return "il faut un an de paix (encore %d jours)" % (need - Diplomacy.pact_days(state, a, b))
	if not pact_between(state, a, b).is_empty():
		return "un accord est déjà en cours"
	if offer and _pending(state, "pact", a, b):
		return "proposition déjà envoyée"
	for eid in [a, b]:
		if pacts_of(state, eid).size() >= int(data()["pact_max"]):
			return "%s mène déjà %d accords" % ["vous" if eid == a else state.get_empire(eid).display_name(), int(data()["pact_max"])]
	var cost := pact_cost(state, a, b)
	for eid in [a, b]:
		if int(state.get_empire(eid).resources.get("energy", 0)) < cost:
			return "pas assez d'énergie chez %s (%d)" % ["vous" if eid == a else state.get_empire(eid).display_name(), cost]
	return ""


## Propose un accord. L'IA répond aussitôt ; un joueur humain reçoit une proposition. Renvoie true si
## l'accord est signé.
static func propose_pact(state: GameState, a: int, b: int) -> bool:
	var target := state.get_empire(b)
	if target.is_ai():
		if AiTechTrade.accepts_pact(state, b, a):
			_sign_pact(state, a, b)
			return true
		state.add_chronicle("%s décline l'accord de recherche proposé par %s." % [target.display_name(), state.get_empire(a).display_name()], [a, b])
		return false
	_list(state, "toff").append({"id": _next_id(state), "kind": "pact", "from": a, "to": b, "tech": "",
			"until": state.tick + int(data()["offer_days"])})
	return false


static func _sign_pact(state: GameState, a: int, b: int) -> void:
	var cost := pact_cost(state, a, b)
	for eid in [a, b]:
		var e := state.get_empire(eid)
		e.resources["energy"] = int(e.resources.get("energy", 0)) - cost
	_list(state, "pacts").append({"id": _next_id(state), "a": mini(a, b), "b": maxi(a, b), "start": state.tick,
			"end": state.tick + int(data()["pact_days"])})
	state.add_chronicle("Accord de recherche entre %s et %s : chacun verse %d énergie, les savants mettront trois ans à rendre leurs conclusions." % [
			state.get_empire(a).display_name(), state.get_empire(b).display_name(), cost], Espionage.public_to(state, [a, b]))


# --- Licences de technologie ---------------------------------------------------------------------

## Technologies obtenues par licence (on ne les revend pas).
static func licensed(state: GameState, eid: int) -> Array:
	return state.goods.get("tlic", {}).get(eid, [])


## Le vendeur peut-il vendre cette technologie (trouvée par lui, ni de peuple ni interdite) ?
static func sellable(state: GameState, seller: int, tid: String) -> bool:
	var e := state.get_empire(seller)
	return e != null and e.techs.has(tid) and not licensed(state, seller).has(tid) \
			and not Research.is_specific(tid) and not (data()["licence_banned"] as Array).has(tid)


## Savoir apporté par la licence.
static func licence_knowledge(state: GameState, buyer: int, tid: String) -> int:
	var left := maxi(0, Research.cost(state, buyer, tid) - Research.progress_of(state, buyer, tid))
	@warning_ignore("integer_division")
	return mini(left, Research.cost(state, buyer, tid) * int(data()["licence_share_pct"]) / 100)


## Prix en énergie, payé par l'acheteur au vendeur.
static func licence_price(state: GameState, buyer: int, tid: String) -> int:
	@warning_ignore("integer_division")
	return maxi(1, licence_knowledge(state, buyer, tid) * int(data()["licence_energy_per_knowledge_pct"]) / 100)


static func check_licence(state: GameState, buyer: int, seller: int, tid: String, offer := true) -> String:
	if not _ok_empire(state, buyer) or not _ok_empire(state, seller) or buyer == seller:
		return "empire inconnu"
	if Trade.tier(state, buyer, seller) <= 0 or Trade.embargoed(state, buyer, seller):
		return "il faut un palier de commerce"
	if not Research.exists(tid) or not sellable(state, seller, tid):
		return "technologie qui ne se vend pas"
	if state.get_empire(buyer).techs.has(tid):
		return "déjà connue"
	if not Research.is_available(state, buyer, tid):
		return "il faut d'abord ses prérequis"
	if int(Research.tech(tid).get("era", 1)) > Research.current_era(state, buyer) + int(data()["licence_max_era_gap"]):
		return "trop avancée pour vous (une ère d'écart au plus)"
	if licence_knowledge(state, buyer, tid) <= 0:
		return "déjà presque trouvée"
	if offer and _pending(state, "licence", buyer, seller, tid):
		return "demande déjà envoyée"
	if int(state.get_empire(buyer).resources.get("energy", 0)) < licence_price(state, buyer, tid):
		return "pas assez d'énergie (%d)" % licence_price(state, buyer, tid)
	return ""


## Technologies que l'acheteur pourrait acheter à ce vendeur.
static func licences_offered(state: GameState, buyer: int, seller: int) -> Array[String]:
	var out: Array[String] = []
	var e := state.get_empire(seller)
	if e == null:
		return out
	for t in e.sorted_techs():
		var tid := String(t)
		if sellable(state, seller, tid) and not state.get_empire(buyer).techs.has(tid) and Research.is_available(state, buyer, tid) \
				and int(Research.tech(tid).get("era", 1)) <= Research.current_era(state, buyer) + int(data()["licence_max_era_gap"]):
			out.append(tid)
	return out


## Demande une licence. Un vendeur IA répond aussitôt ; un vendeur humain reçoit la demande.
static func request_licence(state: GameState, buyer: int, seller: int, tid: String) -> bool:
	var s := state.get_empire(seller)
	if s.is_ai():
		if AiTechTrade.sells_licence(state, seller, buyer, tid):
			_sell_licence(state, buyer, seller, tid)
			return true
		state.add_chronicle("%s refuse de vendre %s à %s." % [s.display_name(), String(Research.tech(tid).get("label", tid)), state.get_empire(buyer).display_name()], [buyer, seller])
		return false
	_list(state, "toff").append({"id": _next_id(state), "kind": "licence", "from": buyer, "to": seller, "tech": tid,
			"until": state.tick + int(data()["offer_days"])})
	return false


static func _sell_licence(state: GameState, buyer: int, seller: int, tid: String) -> void:
	var price := licence_price(state, buyer, tid)
	var k := licence_knowledge(state, buyer, tid)
	var be := state.get_empire(buyer)
	var se := state.get_empire(seller)
	be.resources["energy"] = int(be.resources.get("energy", 0)) - price
	se.resources["energy"] = int(se.resources.get("energy", 0)) + price
	var got := Research.add_progress(state, buyer, tid, k)
	var tl: Dictionary = state.goods.get("tlic", {})
	var l: Array = tl.get(buyer, [])
	if not l.has(tid):
		l.append(tid)
		l.sort()
	tl[buyer] = l
	state.goods["tlic"] = tl
	state.add_chronicle("%s achète à %s une licence de %s (%d Savoir, %d énergie)%s." % [be.display_name(), se.display_name(),
			String(Research.tech(tid).get("label", tid)), k, price, " : la technologie est acquise" if got else ""], Espionage.private_to(state, [buyer, seller]))


# --- Propositions en attente ----------------------------------------------------------------------

static func offers_to(state: GameState, eid: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for o: Dictionary in state.goods.get("toff", []):
		if int(o["to"]) == eid:
			out.append(o)
	return out


static func offers_from(state: GameState, eid: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for o: Dictionary in state.goods.get("toff", []):
		if int(o["from"]) == eid:
			out.append(o)
	return out


static func offer_by_id(state: GameState, id: int) -> Dictionary:
	for o: Dictionary in state.goods.get("toff", []):
		if int(o["id"]) == id:
			return o
	return {}


static func check_answer(state: GameState, eid: int, id: int, accept: bool) -> String:
	var o := offer_by_id(state, id)
	if o.is_empty() or int(o["to"]) != eid:
		return "proposition inconnue"
	if not accept:
		return ""
	if String(o["kind"]) == "pact":
		return check_pact(state, int(o["from"]), eid, false)
	return check_licence(state, int(o["from"]), eid, String(o["tech"]), false)


static func answer(state: GameState, id: int, accept: bool) -> void:
	var o := offer_by_id(state, id)
	if o.is_empty():
		return
	(state.goods["toff"] as Array).erase(o)
	var a := int(o["from"])
	var b := int(o["to"])
	if not accept:
		state.add_chronicle("%s refuse %s de %s." % [state.get_empire(b).display_name(),
				"l'accord de recherche" if String(o["kind"]) == "pact" else "la demande de licence", state.get_empire(a).display_name()], [a, b])
		return
	if String(o["kind"]) == "pact":
		_sign_pact(state, a, b)
	else:
		_sell_licence(state, a, b, String(o["tech"]))


# --- Diffusion ---------------------------------------------------------------------------------

## Technologies que l'autre connaît et pas moi (de mon arbre).
static func tech_gap(state: GameState, eid: int, other: int) -> int:
	var e := state.get_empire(eid)
	var o := state.get_empire(other)
	if e == null or o == null:
		return 0
	var f := e.faction()
	var n := 0
	for t in o.techs:
		if not e.techs.has(t) and Research.is_visible(f, String(t)):
			n += 1
	return n


## Savoir d'une route vers ce partenaire (0 s'il n'est pas plus avancé).
static func route_diffusion(state: GameState, eid: int, other: int) -> int:
	var d := data()
	return mini(int(d["diffusion_route_max"]), tech_gap(state, eid, other) * int(d["diffusion_per_tech"]))


## Savoir de diffusion par empire pour les routes du mois : {empire: n}.
static func diffusion(state: GameState, routes: Array) -> Dictionary:
	var out := {}
	for r: Dictionary in routes:
		if String(r["kind"]) != "ext" or bool(r.get("blocked", false)):
			continue
		for pair in [[int(r["from"]), int(r["to"])], [int(r["to"]), int(r["from"])]]:
			var n := route_diffusion(state, int(pair[0]), int(pair[1]))
			if n > 0:
				out[int(pair[0])] = mini(int(data()["diffusion_max"]), int(out.get(int(pair[0]), 0)) + n)
	return out


# --- Bilan mensuel -----------------------------------------------------------------------------

static func monthly(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if state.goods.is_empty():
		return added
	var keep := []
	for p: Dictionary in state.goods.get("pacts", []):
		var a := int(p["a"])
		var b := int(p["b"])
		if not _ok_empire(state, a) or not _ok_empire(state, b):
			continue
		if Combat.at_war(state, a, b):
			added.append(state.add_chronicle("La guerre entre %s et %s met fin à leur accord de recherche : les laboratoires ferment, l'énergie versée est perdue." % [
					state.get_empire(a).display_name(), state.get_empire(b).display_name()], Espionage.public_to(state, [a, b])))
			continue
		if int(p["end"]) <= state.tick:
			for eid in [a, b]:
				_bonus(state, eid)
			added.append(state.add_chronicle("L'accord de recherche entre %s et %s porte ses fruits : %d et %d Savoir." % [
					state.get_empire(a).display_name(), state.get_empire(b).display_name(), pact_bonus(state, a), pact_bonus(state, b)], Espionage.public_to(state, [a, b])))
			continue
		keep.append(p)
	state.goods["pacts"] = keep
	var offers := []
	for o: Dictionary in state.goods.get("toff", []):
		if int(o["until"]) > state.tick and _ok_empire(state, int(o["from"])) and _ok_empire(state, int(o["to"])):
			offers.append(o)
	state.goods["toff"] = offers
	return added


static func _bonus(state: GameState, eid: int) -> void:
	var e := state.get_empire(eid)
	var n := pact_bonus(state, eid)
	if not e.research_queue.is_empty():
		Research.add_progress(state, eid, e.research_queue[0], n)
	else:
		e.resources["knowledge"] = int(e.resources.get("knowledge", 0)) + n


# --- Sauvegarde (dans celle de Goods) -------------------------------------------------------------

static func to_dict(g: Dictionary) -> Dictionary:
	var tl := []
	var ks: Array = (g.get("tlic", {}) as Dictionary).keys()
	ks.sort()
	for k in ks:
		tl.append([int(k), (g["tlic"][k] as Array).duplicate()])
	return {"pacts": (g.get("pacts", []) as Array).duplicate(true), "toff": (g.get("toff", []) as Array).duplicate(true), "tlic": tl}


static func from_dict(g: Dictionary, d: Dictionary) -> void:
	g["pacts"] = []
	for p: Dictionary in d.get("pacts", []):
		g["pacts"].append(GameData._to_ints(p))
	g["toff"] = []
	for o: Dictionary in d.get("toff", []):
		var v: Dictionary = GameData._to_ints(o)
		v["kind"] = String(o["kind"])
		v["tech"] = String(o.get("tech", ""))
		g["toff"].append(v)
	g["tlic"] = {}
	for p in d.get("tlic", []):
		var l := []
		for t in p[1]:
			l.append(String(t))
		g["tlic"][int(p[0])] = l
