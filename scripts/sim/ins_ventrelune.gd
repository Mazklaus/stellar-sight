class_name InsVentrelune
extends RefCounted
## Compagnie Ventrelune (props 35 à 41 ; voir Insolites, data/insolites.json "ventrelune").
## Un Siège et presque aucune colonie (coloniser coûte quatre fois plus d'influence) : la Compagnie
## possède des parts des colonies des autres. Acheter 10 % d'une colonie demande un accord commercial
## avec son propriétaire, qui touche le prix. Les parts versent chaque mois des dividendes (pris chez
## l'hôte, dans la limite de ses réserves) ; à 25 %, la Compagnie voit la colonie ; à 51 %, elle touche
## aussi l'impôt. Si l'accord commercial tombe, les parts deviennent « sans licence » : plus de
## dividendes, et un motif de guerre Expropriation contre le propriétaire. Celui-ci peut nationaliser
## (saisir les parts), contre une lourde perte d'opinion. Pas de dirigeant : un Conseil d'actionnaires
## vote chaque trimestre une directive. Mercenaires 30 % moins chers. Un défaut de paiement envers la
## Compagnie se rembourse en parts. Victoire : l'OPA galactique.
##
## État (Insolites.emp) : "shares": {"pid": %}, "nolic": {"pid": 1}, "dir": directive, "dir_next": jour.


static func _c(key: String, def := 0) -> int:
	return Insolites.c_int("ventrelune", key, def)


static func found(state: GameState, _e: Empire, _sid: int, ed: Dictionary) -> void:
	ed["shares"] = {}
	ed["nolic"] = {}
	ed["dir"] = "croissance"
	ed["dir_next"] = state.tick + _c("directive_days", 90)


static func directive_def(state: GameState, eid: int) -> Dictionary:
	var id := String(Insolites.emp(state, eid).get("dir", ""))
	for d: Dictionary in Insolites.cfg("ventrelune").get("directives", []):
		if String(d["id"]) == id:
			return d
	return {}


static func shares(state: GameState, eid: int) -> Dictionary:
	return Insolites.emp(state, eid).get("shares", {})


static func share(state: GameState, eid: int, pid: int) -> int:
	return int(shares(state, eid).get(str(pid), 0))


## La Compagnie de cet empire (la première, -1 sans Compagnie) qui détient des parts de la planète.
static func holder(state: GameState, pid: int) -> int:
	for eid in Insolites.nomad_ids(state):
		if Insolites.kind(state, eid) == "ventrelune" and share(state, eid, pid) > 0:
			return eid
	return -1


static func licensed(state: GameState, eid: int, pid: int) -> bool:
	return not (Insolites.emp(state, eid).get("nolic", {}) as Dictionary).has(str(pid))


## Prix de la prochaine tranche de parts (énergie).
static func price(state: GameState, eid: int, pid: int) -> int:
	var c: Colony = state.colonies.get(pid)
	var pop := c.population if c != null else 0
	var p := maxi(_c("share_price_min", 20), pop * _c("share_price_per_pop", 4))
	@warning_ignore("integer_division")
	return p * maxi(10, 100 + int(directive_def(state, eid).get("price_pct", 0))) / 100


static func check_buy(state: GameState, eid: int, pid: int) -> String:
	if Insolites.kind(state, eid) != "ventrelune":
		return "seule la Compagnie achète des parts de colonies"
	var c: Colony = state.colonies.get(pid)
	if c == null or not c.is_colony() or not c.is_established():
		return "il faut une colonie établie"
	if c.owner == eid:
		return "la Compagnie possède déjà ce monde"
	var o := state.get_empire(c.owner)
	if o == null or o.is_npc() or o.eliminated:
		return "pas de Bourse sur ce monde"
	if not state.get_empire(eid).contacts.has(c.owner):
		return "vous n'avez jamais rencontré son propriétaire"
	if not Diplomacy.has_trade(state, eid, c.owner):
		return "il faut un accord commercial avec %s (la licence)" % o.short_name()
	if Combat.at_war(state, eid, c.owner):
		return "pas de Bourse en temps de guerre"
	if share(state, eid, pid) >= 100:
		return "la Compagnie possède déjà tout ce monde"
	var h := holder(state, pid)
	if h >= 0 and h != eid:
		return "une autre Compagnie détient déjà ses parts"
	var cost := price(state, eid, pid)
	if int(state.get_empire(eid).resources.get("energy", 0)) < cost:
		return "énergie insuffisante (il faut %d)" % cost
	return ""


static func buy(state: GameState, eid: int, pid: int, added: Array[Dictionary]) -> void:
	var c: Colony = state.colonies[pid]
	var e := state.get_empire(eid)
	var o := state.get_empire(c.owner)
	var cost := price(state, eid, pid)
	e.resources["energy"] = int(e.resources.get("energy", 0)) - cost
	o.resources["energy"] = int(o.resources.get("energy", 0)) + cost  # le propriétaire vend à la Bourse
	var ed := Insolites.emp(state, eid)
	var sh: Dictionary = ed["shares"]
	var before := int(sh.get(str(pid), 0))
	sh[str(pid)] = mini(100, before + _c("share_step", 10))
	if bool(directive_def(state, eid).get("angry", false)):
		Diplomacy.remember(state, c.owner, eid, "ins_hostile_buy")
	var now := int(sh[str(pid)])
	if now >= _c("view_pct", 25):
		Insolites._explore(state, eid)  # droit de regard : la colonie entre dans la vue
	if before < _c("control_pct", 51) and now >= _c("control_pct", 51):
		added.append(state.add_chronicle("%s détient désormais la majorité de %s. Le gouverneur garde son bureau ; il a seulement un nouveau patron, et un nouveau logo sur sa porte." % [
				e.display_name(), state.galaxy.get_planet(pid).display_name(state.galaxy)], Espionage.public_to(state, [eid, c.owner])))


## Nationaliser (l'hôte saisit les parts de la Compagnie sur sa colonie).
static func check_nationalize(state: GameState, eid: int, pid: int) -> String:
	var c: Colony = state.colonies.get(pid)
	if c == null or c.owner != eid:
		return "seul le propriétaire de la colonie peut nationaliser"
	if holder(state, pid) < 0:
		return "aucune part étrangère sur ce monde"
	return ""


static func nationalize(state: GameState, eid: int, pid: int, added: Array[Dictionary]) -> void:
	var h := holder(state, pid)
	var ed := Insolites.emp(state, h)
	var pct := share(state, h, pid)
	(ed["shares"] as Dictionary).erase(str(pid))
	(ed["nolic"] as Dictionary).erase(str(pid))
	Diplomacy.remember(state, h, eid, String(Insolites.cfg("ventrelune").get("nationalize_opinion", "branch_expropriated")))
	Insolites.sub(state, "expro")["%d>%d" % [h, eid]] = state.tick + 3600
	added.append(state.add_chronicle("%s nationalise les %d %% de %s que détenait %s. Au Conseil d'actionnaires, une IA a calculé la perte à la décimale près, puis a demandé une minute de silence." % [
			state.get_empire(eid).display_name(), pct, state.galaxy.get_planet(pid).display_name(state.galaxy), state.get_empire(h).short_name()],
			Espionage.public_to(state, [eid, h])))


## Motif de guerre Expropriation (Wars, but "expropriated") : a contre b, qui a nationalisé ou rompu la licence.
static func expropriation_casus(state: GameState, a: int, b: int) -> bool:
	if Insolites.kind(state, a) != "ventrelune":
		return false
	if int((state.insolites.get("expro", {}) as Dictionary).get("%d>%d" % [a, b], 0)) > state.tick:
		return true
	var nolic: Dictionary = Insolites.emp(state, a).get("nolic", {})
	for k in nolic:
		var c: Colony = state.colonies.get(int(k))
		if c != null and c.owner == b:
			return true
	return false


## Défaut de paiement d'un débiteur de la Compagnie (Finance.bankrupt) : la dette devient des parts,
## posées sur ses colonies les plus peuplées.
static func on_default(state: GameState, debtor: int, lender: int, principal: int, added: Array[Dictionary]) -> void:
	if Insolites.kind(state, lender) != "ventrelune" or principal <= 0:
		return
	@warning_ignore("integer_division")
	var pts := principal / maxi(1, _c("default_share_per_energy", 10))
	var cols: Array = []
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == debtor and c.is_colony() and c.is_established():
			cols.append([-c.population, int(pid)])
	cols.sort()
	var sh: Dictionary = Insolites.emp(state, lender)["shares"]
	var got := 0
	for row in cols:
		if pts <= 0:
			break
		var pid := int(row[1])
		var h := holder(state, pid)
		if h >= 0 and h != lender:
			continue
		var n := mini(pts, 100 - int(sh.get(str(pid), 0)))
		if n <= 0:
			continue
		sh[str(pid)] = int(sh.get(str(pid), 0)) + n
		pts -= n
		got += n
	if got > 0:
		added.append(state.add_chronicle("%s ne paie plus : ses créances deviennent des parts. %s encaisse %d points de parts sur ses colonies, avec un mot de condoléances préimprimé." % [
				state.get_empire(debtor).short_name(), state.get_empire(lender).short_name(), got], Espionage.public_to(state, [debtor, lender])))


# --- Chaque mois -----------------------------------------------------------------------------------

static func daily(state: GameState, eid: int, ed: Dictionary, month: bool, added: Array[Dictionary]) -> void:
	if state.tick >= int(ed.get("dir_next", 0)):
		_vote(state, eid, ed, added)
	if not month:
		return
	var sh: Dictionary = ed["shares"]
	var nolic: Dictionary = ed["nolic"]
	var keys := sh.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	var e := state.get_empire(eid)
	var div_pct := 100 + int(directive_def(state, eid).get("dividend_pct", 0))
	for key in keys:
		var c: Colony = state.colonies.get(int(key))
		if c == null or not c.is_colony() or c.owner == eid or GameState.is_npc(c.owner):
			sh.erase(key)
			nolic.erase(key)
			continue
		if not Diplomacy.has_trade(state, eid, c.owner):
			if not nolic.has(key):
				nolic[key] = state.tick
				added.append(state.add_chronicle("Plus d'accord commercial : les parts de %s sur %s sont « sans licence ». La Compagnie a déjà imprimé le motif de guerre." % [
						e.short_name(), state.galaxy.get_planet(int(key)).display_name(state.galaxy)], Espionage.private_to(state, [eid, c.owner])))
			continue
		nolic.erase(key)
		var pct := int(sh[key])
		@warning_ignore("integer_division")
		var due := c.population * _c("dividend_per_pop", 1) * pct * div_pct / 10000
		if pct >= _c("control_pct", 51):
			@warning_ignore("integer_division")
			due += c.population / maxi(1, _c("tax_per_pop_div", 2))
		var host := state.get_empire(c.owner)
		var n := mini(due, maxi(0, int(host.resources.get("energy", 0))))
		if n > 0:
			host.resources["energy"] = int(host.resources.get("energy", 0)) - n
			e.resources["energy"] = int(e.resources.get("energy", 0)) + n


## Le Conseil d'actionnaires vote la directive du trimestre (règle fixe : pas de dirigeant).
static func _vote(state: GameState, eid: int, ed: Dictionary, added: Array[Dictionary]) -> void:
	ed["dir_next"] = state.tick + _c("directive_days", 90)
	var e := state.get_empire(eid)
	var en := int(e.resources.get("energy", 0))
	var partners := 0
	for o in state.empires:
		if o.id != eid and not o.is_npc() and not o.eliminated and Diplomacy.has_trade(state, eid, o.id):
			partners += 1
	var pick := "croissance"
	if en < 100:
		pick = "dividendes"
	elif partners >= 2 and en >= int(Insolites.cfg("ai").get("ventrelune_buy_reserve", 150)) * 2:
		pick = "rachat"
	if pick != String(ed.get("dir", "")):
		ed["dir"] = pick
		added.append(state.add_chronicle("Conseil d'actionnaires de %s : la directive « %s » est adoptée par %d voix contre %d, toutes artificielles." % [
				e.short_name(), String(directive_def(state, eid).get("label", pick)), 7 + posmod(state.tick, 5), posmod(state.tick, 4)], Espionage.private_to(state, [eid])))


# --- Victoire : l'OPA galactique (prop. 41) ----------------------------------------------------------

## Part pondérée par la population (en %) que la Compagnie détient d'un empire.
static func weighted_share(state: GameState, eid: int, target: int) -> int:
	var tot := 0
	var mine := 0
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != target or not c.is_colony():
			continue
		tot += maxi(1, c.population)
		if licensed(state, eid, int(pid)):
			mine += maxi(1, c.population) * share(state, eid, int(pid))
	@warning_ignore("integer_division")
	return mine / tot if tot > 0 else 0


static func victory(state: GameState, e: Empire, out: Dictionary) -> void:
	var vc: Dictionary = Insolites.cfg("victories").get("opa", {})
	var want := int(vc.get("pct", 51))
	var rivals := []
	for o in state.empires:
		if o.id != e.id and not o.is_npc() and not o.eliminated and Stability.colony_systems(state, o.id) > 0:
			rivals.append(o.id)  # un peuple sans colonie n'a pas de parts à vendre
	var need := mini(int(vc.get("rivals", 3)), rivals.size())
	var got := 0
	for r in rivals:
		var w := weighted_share(state, e.id, int(r))
		if w >= want:
			got += 1
		if w > 0:
			out["lines"].append("%s : %d %%" % [state.get_empire(int(r)).short_name(), w])
	out["lines"].insert(0, "Empires rivaux contrôlés : %d / %d (majorité pondérée : %d %%)" % [got, need, want])
	out["cond"] = need > 0 and got >= need
	Victory._timed(out, mini(got, need), maxi(1, need))


static func status_lines(state: GameState, eid: int, ed: Dictionary) -> Array[String]:
	var out: Array[String] = []
	out.append("Directive du Conseil : %s (prochain vote dans %d jours)" % [String(directive_def(state, eid).get("label", "?")), maxi(0, int(ed.get("dir_next", 0)) - state.tick)])
	var sh: Dictionary = ed.get("shares", {})
	var maj := 0
	for k in sh:
		if int(sh[k]) >= _c("control_pct", 51):
			maj += 1
	out.append("Parts : %d colonies, dont %d en majorité ; sans licence : %d" % [sh.size(), maj, (ed.get("nolic", {}) as Dictionary).size()])
	return out
