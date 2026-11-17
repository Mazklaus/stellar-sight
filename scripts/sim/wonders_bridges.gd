class_name WondersBridges
extends RefCounted
## Ponts des merveilles (lot 3) : guerre (chantier suspendu par une flotte ennemie, merveille ruinée
## par un long siège ou une crise, but de guerre « Prendre la merveille »), espionnage (sabotage,
## plans volés, auscultation), Amphictyonie (famille « Merveilles » : Patrimoine, Concours, Moratoire),
## œuvres collectives (Koinon, Amphictyonie, Front commun), plans offerts par les anciennes, haut fait
## du Bâtisseur et victoire des Grands Œuvres. Porte aussi les ordres « won_act » de tous les lots.


static func check_act(state: GameState, player: int, act: String, wid: String, x: int, n: int) -> String:
	if state.get_empire(player) == null:
		return "empire inconnu"
	if not Wonders.enabled(state):
		return "pas de merveilles dans cette partie"
	match act:
		"start":
			return Wonders.check_start(state, player, x, wid)
		"cancel":
			return Wonders.check_cancel(state, player, wid)
		"contribute":
			return Wonders.check_contribute(state, player, wid, x)
		"rush":
			return Wonders.check_rush(state, player, wid)
	return _check_more(state, player, act, wid, x, n)


static func act(state: GameState, player: int, act_id: String, wid: String, x: int, n: int, added: Array[Dictionary]) -> void:
	match act_id:
		"start":
			Wonders.start(state, player, x, wid, added)
		"cancel":
			Wonders.cancel(state, player, wid, added)
		"contribute":
			Wonders.contribute(state, player, wid, x)
		"rush":
			Wonders.rush(state, player, wid)
		_:
			_act_more(state, player, act_id, wid, x, n, added)


static func _check_more(state: GameState, player: int, act_id: String, wid: String, x: int, _n: int) -> String:
	match act_id:
		"give":
			return check_give(state, player, wid, x)
		"restore":
			return WondersCatalog.check_restore(state, player, wid)
		"tribunal":
			return WondersCatalog.check_tribunal(state, player)
	return "ordre inconnu : %s" % act_id


static func _act_more(state: GameState, player: int, act_id: String, wid: String, x: int, _n: int, added: Array[Dictionary]) -> void:
	match act_id:
		"give":
			give(state, player, wid, x)
		"restore":
			WondersCatalog.restore(state, player, wid, added)
		"tribunal":
			WondersCatalog.tribunal(state, player, added)


const MONTH := 30
const OFFSET := 23


# --- Victoire des Grands Œuvres (prop. 26) --------------------------------------------------------

static func oeuvres_on(state: GameState) -> bool:
	return Wonders.enabled(state) and Victory.enabled(state, "oeuvres")


## Grands Œuvres à tenir pour gagner, selon la taille de la galaxie.
static func oeuvres_needed(state: GameState) -> int:
	var n := 2
	for row in Wonders.rules().get("oeuvre_by_size", []):
		if state.galaxy.systems.size() >= int(row[0]):
			n = int(row[1])
	return n


static func victory(state: GameState, e: Empire, out: Dictionary) -> void:
	var have := Wonders.owned(state, e.id).count("grand_oeuvre") + MegasBridges.great_works(state, e.id)  # mégastructures de l'ère V
	var need := oeuvres_needed(state)
	out["lines"].append("Grands Œuvres tenus : %d sur %d" % [have, need])
	out["cond"] = have >= need
	Victory._timed(out, have, need)


# --- Œuvres collectives (prop. 22) ---------------------------------------------------------------

## Qui bâtit en commun : "koinon", "amph", "front" (Rempart de l'Aube pendant une crise) ou "".
static func collective_kind(wid: String) -> String:
	var d := Wonders.def(wid)
	if d.has("collective"):
		return String(d["collective"])
	return "front" if bool(d.get("front", false)) else ""


## "" si l'empire peut lancer cette œuvre collective.
static func check_collective(state: GameState, eid: int, wid: String) -> String:
	match collective_kind(wid):
		"koinon":
			if not Koinon.is_member(state, eid):
				return "œuvre d'un Koinon : il faut en être membre"
		"amph":
			if not (Amphictyony.founded(state) and Amphictyony.is_member(state, eid)):
				return "œuvre de l'Amphictyonie : il faut en être membre"
	return ""


## Ceux qui peuvent verser au chantier de builder (lui exclu).
static func partners(state: GameState, builder: int, wid: String) -> Array[int]:
	var out: Array[int] = []
	match collective_kind(wid):
		"koinon":
			var lid := Koinon.league_of(state, builder)
			if lid >= 0:
				for m in Koinon.members_of(state, lid):
					if m != builder:
						out.append(m)
		"amph":
			if Amphictyony.founded(state):
				for m in Amphictyony.members(state):
					if m != builder:
						out.append(m)
		"front":
			if Crisis.active(state):
				for e in state.empires:
					if e.id != builder and not e.eliminated and Crisis.front_pair(state, builder, e.id):
						out.append(e.id)
	return out


## "" si player peut verser ce mois-ci au chantier de builder.
static func check_give(state: GameState, player: int, wid: String, builder: int) -> String:
	var entry := Wonders.build_of(state, builder, wid)
	if entry.is_empty():
		return "aucun chantier de cette œuvre"
	if player == builder:
		return "c'est votre propre chantier : versez depuis vos colonies"
	if not partners(state, builder, wid).has(player):
		return "seuls les partenaires de l'œuvre peuvent verser"
	@warning_ignore("integer_division")
	if int(Wonders._m(state, "cg").get("%s>%d" % [wid, player], -1)) == state.tick / MONTH:
		return "vous avez déjà versé ce mois-ci"
	if int(entry["pts"]) >= int(entry["need"]):
		return "le chantier s'achève"
	var amt := Wonders.contribute_cost(state, builder, wid)
	if not Economy.can_afford(state.get_empire(player), amt):
		return "il faut %s" % GameData.format_amounts(amt)
	return ""


static func give(state: GameState, player: int, wid: String, builder: int) -> void:
	var entry := Wonders.build_of(state, builder, wid)
	var amt := Wonders.contribute_cost(state, builder, wid)
	Economy.pay(state.get_empire(player), amt)
	var paid: Dictionary = entry["paid"]
	paid["materials"] = int(paid.get("materials", 0)) + int(amt.get("materials", 0))
	@warning_ignore("integer_division")
	entry["pts"] = mini(int(entry["need"]), int(entry["pts"]) + int(entry["need"]) * Wonders.r_int("contrib_pct") / 100)
	if not entry.has("sh"):
		entry["sh"] = {}
	entry["sh"][str(player)] = int(entry["sh"].get(str(player), 0)) + int(amt.get("materials", 0))
	@warning_ignore("integer_division")
	Wonders._m(state, "cg")["%s>%d" % [wid, player]] = state.tick / MONTH


## Parts de chacun dans une œuvre achevée (le bâtisseur garde le reste de ce qui fut versé).
static func on_complete_collective(state: GameState, wid: String, eid: int, pid: int, entry: Dictionary) -> void:
	if collective_kind(wid) == "" or not entry.has("sh"):
		return
	var sh: Dictionary = (entry["sh"] as Dictionary).duplicate()
	var others := 0
	for k in sh:
		others += int(sh[k])
	sh[str(eid)] = maxi(1, int((entry["paid"] as Dictionary).get("materials", 0)) - others)
	Wonders._m(state, "shares")["%s#%d" % [wid, pid]] = sh


static func shares_of(state: GameState, wid: String, pid: int) -> Dictionary:
	return state.wonders.get("shares", {}).get("%s#%d" % [wid, pid], {})


## Rendement d'une œuvre du Koinon : partagé chaque mois au prorata (la colonie n'en garde rien).
static func shared_yields(wid: String) -> bool:
	return collective_kind(wid) == "koinon"


static func _distribute(state: GameState, wid: String, pid: int, owner: int) -> void:
	var sh := shares_of(state, wid, pid)
	if sh.is_empty():
		sh = {str(owner): 1}
	var tot := 0
	for k in sh:
		tot += int(sh[k])
	var y: Dictionary = Wonders.def(wid).get("yields", {})
	for k in sh:
		var e := state.get_empire(int(k))
		if e == null or e.eliminated:
			continue
		for r in y:
			@warning_ignore("integer_division")
			e.resources[r] = int(e.resources.get(r, 0)) + int(y[r]) * int(sh[k]) / maxi(1, tot)


# --- Guerre (prop. 18) ----------------------------------------------------------------------------

## Une flotte armée ennemie à l'arrêt dans le système suspend le chantier (Civilization VII).
static func blocked(state: GameState, eid: int, entry: Dictionary) -> bool:
	return hostile_in(state, eid, state.galaxy.get_planet(int(entry["p"])).system_id)


static func hostile_in(state: GameState, eid: int, sid: int) -> bool:
	var e := state.get_empire(eid)
	if e == null:
		return false
	for f in Fleets.fleets_at(state, sid):
		if f.owner == eid or f.is_moving() or not Combat.is_armed(f):
			continue
		if f.owner == GameState.CRISIS_ID or e.wars.has(f.owner):
			return true
	return false


## Une merveille assiégée longtemps (ou tenue par la crise) tombe en ruine, sauf Patrimoine du Nomos.
static func _sieges(state: GameState, added: Array[Dictionary]) -> void:
	var sg: Dictionary = Wonders._m(state, "siege")
	var seen := {}
	for row in Wonders.held(state):
		var wid := String(row[0])
		var pid := int(row[1])
		var owner := int(row[2])
		if not Wonders.galaxy_unique(wid) or collective_kind(wid) != "" or GameState.is_npc(owner):
			continue
		var sid := state.galaxy.get_planet(pid).system_id
		var key := "%s#%d" % [wid, pid]
		if not (hostile_in(state, owner, sid) or (Crisis.active(state) and Crisis.is_held(state, sid))):
			continue
		seen[key] = true
		sg[key] = int(sg.get(key, 0)) + MONTH
		if int(sg[key]) < Wonders.r_int("ruin_days"):
			continue
		if Amphictyony.banned(state, "ruin_wonder") and Amphictyony.is_member(state, owner):
			continue  # Patrimoine des merveilles : on ne les ruine plus
		ruin(state, wid, pid, added)
		seen.erase(key)
	for k in sg.keys():
		if not seen.has(k):
			sg.erase(k)


static func ruin(state: GameState, wid: String, pid: int, added: Array[Dictionary]) -> void:
	var c: Colony = state.colonies.get(pid)
	if c != null:
		c.buildings.erase(wid)
	Wonders._m(state, "ruins")[wid] = pid
	Economy.clear_wonders()
	state.relic_rev += 1
	var p := state.galaxy.get_planet(pid)
	added.append(state.add_chronicle("%s, sur %s, s'effondre après des mois de siège. Il n'en reste qu'une ruine, que d'autres relèveront peut-être." % [
			Wonders.label(wid), p.display_name(state.galaxy)]))


## But de guerre « Prendre la merveille » : b tient-il une merveille hors de sa capitale ?
static func prize_system(state: GameState, b: int) -> int:
	var e := state.get_empire(b)
	if e == null or state.wonders.is_empty():
		return -1
	var home := state.galaxy.get_planet(e.capital_planet).system_id if e.capital_planet >= 0 else -1
	var best := -1
	var best_v := -1
	for row in Wonders.held(state):
		if int(row[2]) != b:
			continue
		var sid := state.galaxy.get_planet(int(row[1])).system_id
		var v := int(Wonders.def(String(row[0])).get("era", 1)) * 100 + int(Wonders.def(String(row[0])).get("score", 0))
		if sid != home and v > best_v:
			best = sid
			best_v = v
	return best


static func take_prize(state: GameState, winner: int, loser: int) -> String:
	var sid := prize_system(state, loser)
	if sid < 0 or state.system_owner(sid) != loser:
		return ""
	Combat.capture_system(state, sid, winner)
	return state.galaxy.systems[sid].system_name


## Phare de la Concorde : déclarer la guerre à un autre membre coûte de l'influence.
static func war_cost(state: GameState, a: int, b: int) -> int:
	if state.wonders.is_empty() or Wonders.built_at(state, "phare_concorde") < 0 or not Amphictyony.founded(state):
		return 0
	if Amphictyony.is_member(state, a) and Amphictyony.is_member(state, b):
		return Wonders.r_int("phare_war_influence")
	return 0


static func check_war(state: GameState, a: int, b: int) -> String:
	var c := war_cost(state, a, b)
	if c > 0 and int(state.get_empire(a).resources.get("influence", 0)) < c:
		return "le Phare de la Concorde l'interdit sans %d influence" % c
	return ""


static func on_war(state: GameState, a: int, b: int) -> void:
	var c := war_cost(state, a, b)
	if c > 0:
		var e := state.get_empire(a)
		e.resources["influence"] = int(e.resources.get("influence", 0)) - c


# --- Espionnage (prop. 19) -----------------------------------------------------------------------

## Grand chantier le plus avancé de b : [merveille, chantier] ou [].
static func top_build(state: GameState, b: int) -> Array:
	var best: Array = []
	for pair in Wonders.builds_by(state, b):
		if best.is_empty() or Wonders.pct(pair[1]) > Wonders.pct(best[1]):
			best = pair
	return best


## Sabotage de chantier : vise d'abord un grand chantier de merveille. "" s'il n'y en a pas.
static func sabotage(state: GameState, b: int, days: int) -> String:
	var top := top_build(state, b)
	if top.is_empty():
		return ""
	var entry: Dictionary = top[1]
	entry["pts"] = maxi(0, int(entry["pts"]) - days * 100)
	return "le chantier de %s prend %d jours de retard. Les échafaudages s'effondrent mystérieusement." % [Wonders.label(String(top[0])), days]


static func spy_check(state: GameState, _a: int, b: int, op_id: String) -> String:
	if not Wonders.enabled(state):
		return "pas de merveilles dans cette partie"
	match op_id:
		"voler_plans", "ausculter":
			if top_build(state, b).is_empty():
				return "aucun grand chantier de merveille chez lui"
	return ""


static func spy_apply(state: GameState, a: int, b: int, o: Dictionary) -> String:
	match String(o["id"]):
		"voler_plans":
			var top := top_build(state, b)
			if top.is_empty():
				return "le chantier était déjà fini. Les plans ne valent plus rien."
			Wonders._m(state, "plans")["%s>%d" % [String(top[0]), a]] = Wonders.r_int("plans_cost_pct")
			return "les plans de %s sont à nous : elle nous coûtera %d %% de moins." % [Wonders.label(String(top[0])), -Wonders.r_int("plans_cost_pct")]
		"ausculter":
			var lines := PackedStringArray()
			for pair in Wonders.builds_by(state, b):
				var e: Dictionary = pair[1]
				var sp := maxi(1, Wonders.speed(state, b, String(pair[0]), int(e["p"])))
				@warning_ignore("integer_division")
				var left := maxi(0, int(e["need"]) - int(e["pts"])) / sp
				lines.append("%s à %d %% (achèvement vers le %s)" % [Wonders.label(String(pair[0])), Wonders.pct(e), GameCalendar.date_string(state.tick + left)])
			Wonders._m(state, "aus")["%d>%d" % [a, b]] = state.tick + 360
			return "ses grands chantiers : %s." % "; ".join(lines)
	return ""


## Auscultation récente : a voit l'avancement exact des chantiers de b pendant un an.
static func auscultated(state: GameState, a: int, b: int) -> bool:
	return int(state.wonders.get("aus", {}).get("%d>%d" % [a, b], 0)) > state.tick


# --- Amphictyonie (prop. 21) ---------------------------------------------------------------------

static func check_nomos(state: GameState, eid: int, wid: String) -> String:
	if Wonders.family(wid) == "mega" and state.amph_on and Amphictyony.banned(state, "megastructure") and Amphictyony.is_member(state, eid):
		return "le Moratoire des mégastructures l'interdit aux amphictyons"
	return ""


static func _contest_on(state: GameState) -> bool:
	return state.amph_on and Amphictyony._level_flag(state, "wonder_contest")


## Concours amphictyonique : 5 ans ; chaque jour de chantier des membres et chaque merveille achevée
## comptent ; or, argent et bronze à la fin.
static func _contest(state: GameState, added: Array[Dictionary]) -> void:
	var c: Dictionary = state.wonders.get("contest", {})
	if c.is_empty():
		if _contest_on(state):
			state.wonders["contest"] = {"end": state.tick + Wonders.r_int("contest_days"), "sc": {}}
			added.append(state.add_chronicle("L'Amphictyonie ouvre un Concours des bâtisseurs : dans cinq ans, l'or, l'argent et le bronze iront aux plus grands chantiers."))
		return
	var sc: Dictionary = c["sc"]
	for m in Amphictyony.members(state):
		var n := Wonders.builds_by(state, m).size()
		if n > 0:
			sc[str(m)] = int(sc.get(str(m), 0)) + n
	if state.tick < int(c["end"]):
		return
	var rank: Array = sc.keys()
	rank.sort_custom(func(x: Variant, y: Variant) -> bool: return int(sc[x]) > int(sc[y]) if int(sc[x]) != int(sc[y]) else int(x) < int(y))
	var prizes: Array = Wonders.rules().get("contest_prizes", [300, 150, 75])
	var names := ["l'or", "l'argent", "le bronze"]
	var parts := PackedStringArray()
	for i in mini(3, rank.size()):
		var e := state.get_empire(int(rank[i]))
		if e == null:
			continue
		e.resources["influence"] = int(e.resources.get("influence", 0)) + int(prizes[i])
		Wonders._m(state, "medals")[str(e.id)] = int(state.wonders["medals"].get(str(e.id), 0)) + (3 - i)
		parts.append("%s à %s" % [names[i], e.short_name()])
	state.wonders.erase("contest")
	added.append(state.add_chronicle("Concours amphictyonique des bâtisseurs : %s." % (", ".join(parts) if not parts.is_empty() else "aucun prix, faute de chantiers")))


static func contest_score(state: GameState, eid: int) -> int:
	return int(state.wonders.get("contest", {}).get("sc", {}).get(str(eid), 0))


# --- Haut fait du Bâtisseur (prop. 25), anciennes (prop. 23) -------------------------------------

static func builder_deed(state: GameState) -> int:
	return int(state.wonders.get("deed", -1))


static func _deed(state: GameState, added: Array[Dictionary]) -> void:
	if builder_deed(state) >= 0:
		return
	var count := {}
	for row in Wonders.held(state):
		if Wonders.galaxy_unique(String(row[0])) and not GameState.is_npc(int(row[2])):
			count[int(row[2])] = int(count.get(int(row[2]), 0)) + 1
	var keys := count.keys()
	keys.sort()
	for eid in keys:
		if int(count[eid]) >= Wonders.r_int("deed_count"):
			state.wonders["deed"] = int(eid)
			added.append(state.add_chronicle("Haut fait : %s tient %d merveilles galactiques et reçoit le titre de Bâtisseur. On lui demande des conseils de chantier jusque dans les cours rivales." % [
					state.get_empire(int(eid)).display_name(), int(count[eid])], Espionage.public_to(state, [int(eid)])))
			return


static func opinion_parts(state: GameState, a: int, b: int) -> Array:
	var out: Array = []
	if builder_deed(state) == b and a != b:
		out.append(["Bâtisseur de merveilles", Wonders.r_int("deed_opinion")])
	var at := Wonders.built_at(state, "phare_concorde")
	if at >= 0 and Amphictyony.founded(state) and Amphictyony.is_member(state, a) and Amphictyony.is_member(state, b):
		if shares_of(state, "phare_concorde", at).has(str(b)):
			out.append(["Bâtisseur du Phare de la Concorde", 10])
	return out


## Une ancienne amie offre les plans d'une merveille à sa portée (−50 %), une fois.
static func _ancient_plans(state: GameState, added: Array[Dictionary]) -> void:
	if not Ancients.enabled(state):
		return
	var given: Dictionary = Wonders._m(state, "agift")
	for id in Ancients.ids(state):
		for e in state.empires:
			var k := "%d>%d" % [id, e.id]
			if e.eliminated or given.has(k) or not Ancients.in_contact(state, id, e.id) or Ancients.opinion(state, id, e.id) < 60:
				continue
			for wid in Wonders.all_ids():
				if Wonders.unlocked(state, e.id, wid) and Wonders.galaxy_unique(wid) and Wonders.built_at(state, wid) < 0 and collective_kind(wid) == "":
					given[k] = state.tick
					Wonders._m(state, "plans")["%s>%d" % [wid, e.id]] = Wonders.r_int("anc_plans_pct")
					added.append(state.add_chronicle("%s confie à %s les plans de %s, tracés avant notre ère : elle lui coûtera moitié moins." % [
							Ancients.name_of(state, id), e.short_name(), Wonders.label(wid)], Espionage.private_to(state, [e.id])))
					break


# --- Chaque jour ---------------------------------------------------------------------------------

static func daily(state: GameState, added: Array[Dictionary]) -> void:
	if posmod(state.tick, MONTH) != OFFSET:
		return
	for row in Wonders.held(state):
		if shared_yields(String(row[0])):
			_distribute(state, String(row[0]), int(row[1]), int(row[2]))
	_sieges(state, added)
	_deed(state, added)
	if state.amph_on:
		_contest(state, added)
	_ancient_plans(state, added)


static func on_complete(_state: GameState, _wid: String, _eid: int, _pid: int, _added: Array[Dictionary]) -> void:
	pass


## Ponts de l'IA : restaurer ses ruines, verser aux œuvres de ses partenaires.
static func ai_think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var mat := AiPlayer._res(ctx, "materials")
	var reserve := AiPlayer._material_reserve(ctx)
	var r: Dictionary = state.wonders.get("ruins", {})
	var rk := r.keys()
	rk.sort()
	for wid in rk:
		if WondersCatalog.check_restore(state, e.id, String(wid)) == "" and mat > reserve + 600:
			if AiPlayer._issue(ctx, SimCommands.won_act(e.id, "restore", String(wid))):
				AiPlayer._intent(ctx, "Relève %s" % Wonders.label(String(wid)))
	var b: Dictionary = state.wonders.get("build", {})
	var bk := b.keys()
	bk.sort()
	for wid in bk:
		if collective_kind(String(wid)) == "":
			continue
		var per: Dictionary = b[wid]
		var ek := per.keys()
		ek.sort()
		for k in ek:
			if int(k) != e.id and AiPlayer._res(ctx, "materials") > reserve + 400 and check_give(state, e.id, String(wid), int(k)) == "":
				AiPlayer._issue(ctx, SimCommands.won_act(e.id, "give", String(wid), int(k)))
