class_name CultureBridges
extends RefCounted
## Rayonnement culturel, lot 3 (étude du 2026-11-15) : les actions et les ponts. Rayonnement religieux
## (prop. 11), Conservateurs (12), alliances et Koinon (19), ambassades culturelles (20), Troupes de
## spectacle (28 ; Civ VI : le concert du groupe de rock, au résultat aléatoire), lois Exception et
## Ouverture culturelles et pare-feu de la Propagande (29), opérations d'espionnage (30), famille de
## l'Amphictyonie (31), talents par couche (34, lus par Culture.talent), credo Plaisir et victoire de
## peuple « L'Idole des étoiles » (35, voir CultureLife.victory_idole).
##
## État ajouté à state.culture : "emb": {empire: [cibles]}, "troupes": [{"from", "to", "arrive"}],
## "ops": {"a>b": {"pct", "until"}}, "den": {empire: jour de fin}, "expo": {"host", "until"}.


static func data() -> Dictionary:
	return Culture.data()


# --- Sources (props 11 et 12) -------------------------------------------------------------------

## Conservateur : un gouverneur Orateur double les œuvres et merveilles de son système.
static func conservator_bonus(state: GameState, eid: int, sid: int, works: int) -> int:
	if state.heroes.is_empty():
		return 0
	var h := Heroes.at_post(state, "system", sid, eid)
	if h.is_empty() or String(h.get("cls", "")) != "orateur":
		return 0
	return works * (int(data()["sources"]["conservator_mult"]) - 1)


## Rayonnement religieux brut (siège d'une grande foi d'État, reliques saintes au Reliquaire).
static func religious(state: GameState, eid: int) -> int:
	if not state.faith_on:
		return 0
	var src: Dictionary = data()["sources"]
	var n := 0
	var fid := Faiths.state_faith(state, eid)
	if Faiths.has_state_faith(state, eid):
		var f := Faiths.faith(state, fid)
		if not f.is_empty():
			var hc: Colony = state.colonies.get(int(f.get("holy", -1)))
			if hc != null and hc.owner == eid:
				n += int(src["holy_seat"])
	if not state.relics.is_empty():
		for rid in Relics.in_reliquary(state, eid):
			if Relics.is_holy(rid):
				n += int(src["holy_relic"])
	@warning_ignore("integer_division")
	return n * maxi(0, 100 + Culture.tal(state, eid, "faith_pct")) / 100


static func extra_sources(state: GameState, eid: int) -> Array:
	var out := []
	var rel := religious(state, eid)
	if rel > 0:
		out.append(["Rayonnement religieux", rel])
	if not state.heroes.is_empty():
		var lv := 0
		for hid in Heroes.ids_of(state, eid):
			var h: Dictionary = state.heroes[hid]
			if String(h.get("post", "")) == "system" and String(h.get("cls", "")) == "orateur" and Heroes.active(state, h):
				lv += int(h.get("lvl", 1)) * int(data()["sources"]["governor_level"])
		if lv > 0:
			out.append(["Gouverneurs orateurs (niveaux)", lv])
	return out


## Pourcentages venus des lois, de l'Amphictyonie et de la Grande Exposition (clé « culture_<key> »).
static func law_pct(state: GameState, eid: int, key: String) -> int:
	var n := Research.fx_int(state, eid, "culture_" + key)
	if key == "radiance_pct" and int(state.culture.get("expo", {}).get("host", -1)) == eid and state.tick < int(state.culture.get("expo", {}).get("until", 0)):
		n += 50
	return n


# --- Diffusion (props 19, 20, 29, 30) -----------------------------------------------------------

static func flow_extra(state: GameState, a: int, b: int) -> Array:
	var out := []
	var fb := Research.fx_int(state, b, "culture_foreign_pct")
	if fb != 0:
		out.append(["Lois et résolutions de la cible", fb])
	var fa := Research.fx_int(state, a, "culture_export_pct")
	if fa != 0:
		out.append(["Ouverture culturelle", fa])
	if Research.fx_int(state, b, "meme_firewall") > 0:
		out.append(["Pare-feu culturel de la cible (Propagande)", int(data()["firewall_pct"])])
	if (state.culture.get("emb", {}).get(str(a), []) as Array).has(b):
		out.append(["Ambassade culturelle", int(data()["embassy"]["pct"])])
	var op: Dictionary = state.culture.get("ops", {}).get(Culture._k(a, b), {})
	if not op.is_empty() and state.tick < int(op["until"]):
		out.append(["Campagne de propagande", int(op["pct"])])
	if state.tick < int(state.culture.get("den", {}).get(str(a), 0)):
		out.append(["Culture dénigrée (espionnage)", -25])
	return out


## Alliés et Koinon (prop. 19) : 20 % du Rayonnement de chaque allié et membre de la même ligue.
static func ally_share(state: GameState, a: int) -> int:
	var n := 0
	for o in Culture.living(state):
		if o != a and (Diplomacy.allied(state, a, o) or (state.koinon_on and Koinon.same_league(state, a, o))):
			n += Culture.radiance(state, o)
	@warning_ignore("integer_division")
	return n * int(data()["alliance_pct"]) / 100


## Une foi d'État différente chez la cible divise par deux la part religieuse (prop. 11).
static func adjust_received(state: GameState, a: int, b: int, got: int) -> int:
	if got <= 0 or not state.faith_on or GameState.is_minor(b):
		return got
	if Faiths.has_state_faith(state, b) and Faiths.state_faith(state, b) != Faiths.state_faith(state, a):
		var rel := religious(state, a) * Culture.radiance_pct(state, a) / 100
		@warning_ignore("integer_division")
		got -= mini(got, rel * (100 - int(data()["sources"]["other_faith_pct"])) / 100)
	return got


# --- Bilans -------------------------------------------------------------------------------------

static func daily(state: GameState, added: Array[Dictionary]) -> void:
	var tr: Array = state.culture.get("troupes", [])
	if tr.is_empty():
		return
	var keep := []
	for t: Dictionary in tr:
		if state.tick >= int(t["arrive"]):
			_perform(state, int(t["from"]), int(t["to"]), added)
		else:
			keep.append(t)
	state.culture["troupes"] = keep


static func monthly(state: GameState, ids: Array[int], added: Array[Dictionary]) -> void:
	# Ops expirées.
	var ops := Culture._m(state, "ops")
	for k in ops.keys():
		if state.tick >= int(ops[k]["until"]):
			ops.erase(k)
	var den := Culture._m(state, "den")
	for k in den.keys():
		if state.tick >= int(den[k]):
			den.erase(k)
	# Ambassades vers un empire disparu ou devenu du même credo.
	var emb := Culture._m(state, "emb")
	for k in emb.keys():
		var keep: Array = []
		for b in emb[k]:
			if embassy_ok(state, int(k), int(b)):
				keep.append(int(b))
		if keep.is_empty():
			emb.erase(k)
		else:
			emb[k] = keep
	# Grande Exposition (Amphictyonie) : chaque année, le membre qui rayonne le plus l'accueille.
	if state.amph_on and Amphictyony.founded(state) and Amphictyony.level_sum(state, "culture_expo") > 0:
		var ex: Dictionary = state.culture.get("expo", {})
		if ex.is_empty() or state.tick >= int(ex.get("until", 0)):
			var best := -1
			for eid in ids:
				if Amphictyony.is_member(state, eid) and (best < 0 or Culture.radiance(state, eid) > Culture.radiance(state, best)):
					best = eid
			if best >= 0:
				state.culture["expo"] = {"host": best, "until": state.tick + 360}
				added.append(state.add_chronicle("Grande Exposition galactique : %s accueille les pavillons de toute l'Amphictyonie pour un an. Rayonnement +50 %%, et des files d'attente jusqu'aux docks." % state.get_empire(best).display_name(), []))
	elif state.culture.has("expo"):
		state.culture.erase("expo")


# --- Ambassades culturelles (prop. 20) ----------------------------------------------------------

static func embassy_max(state: GameState, a: int) -> int:
	return int(data()["embassy"]["max"]) + Culture.tal(state, a, "embassies")


static func embassies(state: GameState, a: int) -> Array:
	if state.culture.is_empty():
		return []
	return state.culture.get("emb", {}).get(str(a), [])


static func embassy_ok(state: GameState, a: int, b: int) -> bool:
	var eb := state.get_empire(b)
	if eb == null or eb.eliminated or eb.is_npc() or a == b:
		return false
	var sa := FactionTraits.species(state.get_empire(a).faction())
	var sb := FactionTraits.species(eb.faction())
	return String(sa.get("credo", "")) != String(sb.get("credo", ""))


# --- Troupes de spectacle (prop. 28) ------------------------------------------------------------

static func troupe_cost(_state: GameState, _a: int) -> Dictionary:
	return {"energy": 120, "influence": 30}


static func troupes_of(state: GameState, a: int) -> Array:
	var out := []
	for t: Dictionary in state.culture.get("troupes", []):
		if int(t["from"]) == a:
			out.append(t)
	return out


static func _perform(state: GameState, a: int, b: int, added: Array[Dictionary]) -> void:
	var ea := state.get_empire(a)
	var eb := state.get_empire(b)
	if ea == null or eb == null or ea.eliminated or eb.eliminated:
		return
	var tp: Dictionary = data()["troupe"]
	var tot := 0
	for o: Dictionary in tp["outcomes"]:
		tot += int(o["weight"])
	var r := state.rng.randi_range(1, tot)
	var pick: Dictionary = tp["outcomes"][0]
	for o: Dictionary in tp["outcomes"]:
		r -= int(o["weight"])
		if r <= 0:
			pick = o
			break
	var burst := int(tp["burst"]) * int(pick["mult"]) * maxi(1, Culture.tal(state, a, "troupe_mult"))
	if burst > 0 and not Culture.at_war(state, a, b):
		var cum := Culture._m(state, "cum")
		var k := Culture._k(a, b)
		cum[k] = int(cum.get(k, 0)) + burst
	if int(pick.get("opinion", 0)) != 0:
		Diplomacy.remember(state, b, a, "culture_scandale")
	added.append(state.add_chronicle("Tournée de la Troupe de %s chez %s. %s%s" % [ea.short_name(), eb.display_name(), String(pick["text"]),
			(" (+%d de Rayonnement)" % burst) if burst > 0 else ""], [a, b]))


# --- Ordres du joueur (SimCommands.cul_act) -----------------------------------------------------

## act : "osmose" (n = 1 accepter, 0 refuser), "savoir" (s = technologie), "ambassade" / "fermer" (x = empire),
## "troupe" (x = empire).
static func check_act(state: GameState, eid: int, act: String, x: int, s: String, n: int) -> String:
	if state.culture.is_empty():
		return "pas de rayonnement dans cette partie"
	var e := state.get_empire(eid)
	if e == null or e.eliminated:
		return "empire inconnu"
	match act:
		"osmose":
			return CultureLife.check_answer(state, eid)
		"savoir":
			return CultureLife.check_tech(state, eid, s)
		"ambassade":
			if not e.contacts.has(x):
				return "empire jamais rencontré"
			if not embassy_ok(state, eid, x):
				return "une ambassade culturelle ne sert que chez un empire d'un autre credo"
			if embassies(state, eid).has(x):
				return "déjà une ambassade chez lui"
			if Culture.at_war(state, eid, x):
				return "pas d'ambassade chez un ennemi"
			if embassies(state, eid).size() >= embassy_max(state, eid):
				return "déjà %d ambassade(s) culturelle(s) : fermez-en une" % embassy_max(state, eid)
			if not Economy.can_afford(e, data()["embassy"]["cost"]):
				return "pas assez d'influence (%s)" % GameData.format_amounts(data()["embassy"]["cost"])
			return ""
		"fermer":
			return "" if embassies(state, eid).has(x) else "pas d'ambassade chez lui"
		"troupe":
			if Research.fx_int(state, eid, "culture_troupe") <= 0:
				return "technologie requise : Holovision"
			if not e.contacts.has(x) or GameState.is_npc(x) or x == eid:
				return "empire jamais rencontré"
			if Culture.at_war(state, eid, x):
				return "aucune salle ne veut de vous chez un ennemi"
			if not troupes_of(state, eid).is_empty():
				return "votre troupe est déjà en tournée"
			if not Economy.can_afford(e, troupe_cost(state, eid)):
				return "ressources insuffisantes (%s)" % GameData.format_amounts(troupe_cost(state, eid))
			return ""
	return "action inconnue : %s" % act


static func act(state: GameState, eid: int, act_id: String, x: int, s: String, n: int, added: Array[Dictionary]) -> void:
	match act_id:
		"osmose":
			CultureLife.answer_law(state, eid, n == 1, added)
		"savoir":
			CultureLife.buy_tech(state, eid, s, added)
		"ambassade":
			Economy.pay(state.get_empire(eid), data()["embassy"]["cost"])
			var emb := Culture._m(state, "emb")
			var lst: Array = emb.get(str(eid), [])
			lst.append(x)
			lst.sort()
			emb[str(eid)] = lst
			added.append(state.add_chronicle("%s ouvre une ambassade culturelle chez %s : expositions, cours de langue et buffets à volonté." % [
					state.get_empire(eid).display_name(), state.get_empire(x).display_name()], [eid, x]))
		"fermer":
			var emb2 := Culture._m(state, "emb")
			var l2: Array = emb2.get(str(eid), [])
			l2.erase(x)
			if l2.is_empty():
				emb2.erase(str(eid))
		"troupe":
			Economy.pay(state.get_empire(eid), troupe_cost(state, eid))
			if not state.culture.has("troupes"):
				state.culture["troupes"] = []
			(state.culture["troupes"] as Array).append({"from": eid, "to": x, "arrive": state.tick + int(data()["troupe"]["days"])})
			added.append(state.add_chronicle("La Troupe de spectacle de %s part en tournée chez %s : trois mois de route, de répétitions et de costumes froissés." % [
					state.get_empire(eid).display_name(), state.get_empire(x).display_name()], [eid]))


# --- Espionnage (prop. 30) ----------------------------------------------------------------------

static func spy_check(state: GameState, a: int, b: int, op_id: String) -> String:
	if state.culture.is_empty():
		return "pas de rayonnement dans cette partie"
	match op_id:
		"vol_oeuvre":
			if state.relics.is_empty() or (state.culture.get("exp", {}).get(str(b), []) as Array).is_empty():
				return "son Musée galactique n'expose aucune relique"
		"campagne_culturelle":
			if Culture.at_war(state, a, b):
				return "la guerre coupe la diffusion"
	return ""


static func spy_apply(state: GameState, a: int, b: int, o: Dictionary) -> String:
	match String(o["id"]):
		"campagne_culturelle":
			Culture._m(state, "ops")[Culture._k(a, b)] = {"pct": 50, "until": state.tick + 360}
			return "pendant un an, nos feuilletons passent en boucle sur ses écrans : diffusion +50 %."
		"denigrement":
			var top := Culture.top_influencer(state, b)
			var who := int(top[1]) if int(top[1]) >= 0 and int(top[1]) != a else -1
			if who < 0:
				return "il n'y avait aucune culture étrangère à salir chez lui. Les pamphlets finissent au recyclage."
			Culture._m(state, "den")[str(who)] = state.tick + 360
			return "la culture de %s est tournée en ridicule partout : sa diffusion baisse de 25 %% pendant un an." % state.get_empire(who).display_name()
		"vol_oeuvre":
			var ex: Array = state.culture.get("exp", {}).get(str(b), [])
			var rid := String(ex[0]) if not ex.is_empty() else ""
			if rid == "" or int(state.relics.get(rid, {}).get("owner", -1)) != b:
				return "la vitrine était vide : quelqu'un est passé avant nous."
			Relics.steal(state, a, rid)
			ex.erase(rid)
			return "« %s » quitte son Musée galactique pour le nôtre. Les gardiens dormaient, la vitrine non." % String(Relics.def(rid).get("name", rid))
	return ""
