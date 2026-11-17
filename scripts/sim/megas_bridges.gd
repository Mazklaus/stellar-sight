class_name MegasBridges
extends RefCounted
## Les mégastructures et les autres piliers (lot 3, prop. 33-42 ; voir Megastructures, data/megastructures.json
## « bridges »). Espionnage (saboter, voler les plans), but de guerre « Saisir la mégastructure »,
## Amphictyonie (Moratoire, famille « Grands chantiers »), Koinon (cofinancement fédéral), religion
## (sacrilège, opinion des credos), Transcendance (site de l'Exodium, Matriochka et jauge), économie
## privée (une compagnie finance une étape), héros (trait Architecte) et cour (Grand Architecte), hauts
## faits et victoire des Grands Œuvres. Les talents des peuples sont lus dans Megastructures.


static func cfg() -> Dictionary:
	return Megastructures.cfg("bridges")


static func c_int(key: String, sub := "", def := 0) -> int:
	if sub == "":
		return int(cfg().get(key, def))
	return int((cfg().get(key, {}) as Dictionary).get(sub, def))


# --- Coûts, vitesse, capacité --------------------------------------------------------------------

## Pour cent de coût : plans volés, Chantiers partagés de l'Amphictyonie, cofinancement du Koinon.
static func cost_pct(state: GameState, eid: int, k: String) -> int:
	if not Megastructures.full(state):
		return 0
	var pct := 0
	var stolen: Dictionary = Megastructures.sub(state, "plans_stolen").get(str(eid), {})
	if stolen.has(k):
		pct += c_int("spy", "plans_pct", -25)
	if state.amph_on and Amphictyony.founded(state) and Amphictyony.is_member(state, eid):
		pct += Amphictyony.level_sum(state, "mega_shared_pct")
	if bool(Megastructures.kind_def(k).get("federal", false)) and state.koinon_on and Koinon.is_member(state, eid):
		var n := Koinon.members_of(state, Koinon.league_of(state, eid)).size() - 1
		pct += maxi(c_int("koinon", "max_pct", -30), n * c_int("koinon", "per_member_pct", -10))
	return pct


## Pour cent de vitesse : gouverneur du système au trait Architecte (prop. 41).
static func speed_pct(state: GameState, eid: int, sid: int) -> int:
	if sid < 0 or state.heroes.is_empty():
		return 0
	var h := Heroes.at_post(state, "system", sid, eid)
	if not h.is_empty() and (h.get("traits", []) as Array).has("architecte"):
		return c_int("hero_speed_pct", "", 30)
	return 0


## Étapes de plus à la fois : le Grand Architecte de la cour (prop. 41).
static func slots_bonus(state: GameState, eid: int) -> int:
	if state.court.is_empty() or not Court.applies(state, eid):
		return 0
	return 1 if Court.minor_apt(state, eid, "grand_architecte") > 0 else 0


# --- Interdits (Amphictyonie, prop. 35) -----------------------------------------------------------

static func _member(state: GameState, eid: int) -> bool:
	return state.amph_on and Amphictyony.founded(state) and Amphictyony.is_member(state, eid)


static func site_reason(state: GameState, eid: int, k: String, sid: int, _pid: int) -> String:
	if not _member(state, eid):
		return ""
	if Amphictyony.banned(state, "megastructure"):
		return "le Moratoire des mégastructures l'interdit aux amphictyons"
	if bool(Megastructures.kind_def(k).get("weapon", false)) and Amphictyony.banned(state, "mega_weapon"):
		return "le Patrimoine stellaire interdit les superarmes aux amphictyons"
	if Megastructures.body(k) == "star" and Amphictyony.banned(state, "mega_foreign_star"):
		for pid in state.galaxy.systems[sid].planet_ids:
			var c: Colony = state.colonies.get(pid)
			if c != null and c.owner != eid and c.is_colony() and c.population > 0:
				return "le Patrimoine stellaire interdit d'emmailloter l'étoile d'un autre peuple"
	return ""


static func advance_reason(state: GameState, eid: int, m: Dictionary) -> String:
	var sp: Dictionary = Megastructures.stage_def(String(m["k"]), int(m["st"])).get("special", {})
	if bool(sp.get("awaken", false)) and not ancient_awake(state) and Megastructures.complete_count(state, eid, "anneau_extinction") == 0:
		return "l'Éveil attend le réveil d'une puissance ancienne (ou votre Anneau d'extinction achevé)"
	if _member(state, eid) and Amphictyony.banned(state, "megastructure") and int(m["st"]) == 0:
		return "le Moratoire des mégastructures l'interdit aux amphictyons"
	return ""


## Une puissance ancienne est-elle réveillée (Forteresse dormante, prop. 30) ?
static func ancient_awake(state: GameState) -> bool:
	if not Ancients.enabled(state):
		return false
	for id in Ancients.ids(state):
		if not Ancients.asleep(state, id):
			return true
	return false


# --- Ordres des ponts : « fund » (une compagnie finance une étape, prop. 39) ----------------------

static func check(state: GameState, eid: int, act: String, d: Dictionary) -> String:
	match act:
		"fund":
			return check_fund(state, eid, int(d.get("id", -1)))
	return "ordre inconnu : %s" % act


static func apply(state: GameState, eid: int, act: String, d: Dictionary, added: Array[Dictionary]) -> void:
	match act:
		"fund":
			fund(state, eid, int(d["id"]), added)


static func check_fund(state: GameState, eid: int, id: int) -> String:
	if state.private.is_empty() or not Private.full(state) or not Private.applies(state, eid):
		return "l'économie privée complète n'est pas en jeu"
	var m := Megastructures.get_m(state, id)
	if m.is_empty() or int(m["o"]) != eid:
		return "ce n'est pas votre mégastructure"
	if int(m.get("co", 0)) > state.tick:
		return "une compagnie la finance déjà"
	var why := Megastructures.check_advance(state, eid, id)
	if why != "" and not why.begins_with("il faut "):
		return why
	return ""


static func fund(state: GameState, eid: int, id: int, added: Array[Dictionary]) -> void:
	var m := Megastructures.get_m(state, id)
	var k := String(m["k"])
	var n := int(m["st"])
	m["w"] = Megastructures.stage_days(state, eid, k, n, int(m["s"]))
	m["co"] = state.tick + c_int("private", "years", 10) * 360
	Megastructures._stat(state, eid, "funded", 1)
	added.append(state.add_chronicle("Une compagnie privée finance l'étape « %s » de %s, contre %d %% de ses rendements pendant %d ans. Les actionnaires parlent déjà de « leur » ouvrage." % [
			String(Megastructures.stage_def(k, n).get("label", "")), Megastructures.name_of(state, m), c_int("private", "share_pct", 25), c_int("private", "years", 10)], [eid]))


## Part des rendements laissée à la compagnie (en pour cent du rendement).
static func company_share(state: GameState, m: Dictionary) -> int:
	return c_int("private", "share_pct", 25) if int(m.get("co", 0)) > state.tick else 0


# --- Espionnage (prop. 33) -----------------------------------------------------------------------

static func spy_check(state: GameState, a: int, b: int, op_id: String) -> String:
	if not Megastructures.full(state):
		return "les mégastructures ne sont pas en jeu dans cette partie"
	match op_id:
		"saboter_chantier":
			if _running_of(state, b).is_empty():
				return "aucun chantier de mégastructure en cours chez lui"
		"voler_plans_mega":
			if _plans_target(state, a, b) == "":
				return "il ne tient aucune mégastructure achevée dont vous n'avez pas les plans"
	return ""


static func spy_apply(state: GameState, a: int, b: int, o: Dictionary) -> String:
	var be := state.get_empire(b)
	match String(o.get("id", "")):
		"saboter_chantier":
			var m := _running_of(state, b)
			if m.is_empty():
				return ""
			m["w"] = int(m["w"]) + c_int("spy", "sabotage_days", 120)
			return "nos agents ont saboté le chantier de %s chez %s : l'étape en cours perd %d jours." % [Megastructures.name_of(state, m), be.display_name(), c_int("spy", "sabotage_days", 120)]
		"voler_plans_mega":
			var k := _plans_target(state, a, b)
			if k == "":
				return ""
			var st := Megastructures.sub(state, "plans_stolen")
			var mine: Dictionary = st.get(str(a), {})
			mine[k] = 1
			st[str(a)] = mine
			return "nous avons copié les plans de %s de %s : ses étapes nous coûteront %d %% de moins." % [Megastructures.label(k), be.display_name(), -c_int("spy", "plans_pct", -25)]
	return ""


static func _running_of(state: GameState, b: int) -> Dictionary:
	for m in Megastructures.owned_by(state, b):
		if Megastructures.running(m):
			return m
	return {}


static func _plans_target(state: GameState, a: int, b: int) -> String:
	var stolen: Dictionary = Megastructures.sub(state, "plans_stolen").get(str(a), {})
	for m in Megastructures.owned_by(state, b):
		var k := String(m["k"])
		if Megastructures.complete(m) and not stolen.has(k) and Megastructures.count_kind(state, a, k) == 0:
			return k
	return ""


# --- Guerre (prop. 34) ------------------------------------------------------------------------------

## Système de la plus grande mégastructure de b (hors capitale), pour le but « Saisir la mégastructure ».
static func prize_system(state: GameState, b: int) -> int:
	var e := state.get_empire(b)
	if e == null or not Megastructures.enabled(state):
		return -1
	var home := state.galaxy.get_planet(e.capital_planet).system_id if e.capital_planet >= 0 else -1
	var best := -1
	var best_v := -1
	for m in Megastructures.owned_by(state, b):
		var sid := int(m["s"])
		if sid == home or Megastructures.is_ruin(m) or int(m["st"]) < 1 or state.system_owner(sid) != b:
			continue
		var v := int(Megastructures.kind_def(String(m["k"])).get("era", 1)) * 100 + int(m["st"])
		if v > best_v:
			best_v = v
			best = sid
	return best


static func take_prize(state: GameState, winner: int, loser: int) -> String:
	var sid := prize_system(state, loser)
	if sid < 0:
		return ""
	Combat.capture_system(state, sid, winner)
	var added: Array[Dictionary] = []
	for m in Megastructures.in_system(state, sid):
		Megastructures._sync_owner(state, m, added)
	return state.galaxy.systems[sid].system_name


## L'IA vise les chantiers de ses rivaux en guerre (prop. 34).
static func strike_target(state: GameState, owner: int, sid: int) -> bool:
	if state.megas.is_empty():
		return false
	for m in Megastructures.in_system(state, sid):
		if int(m["o"]) == owner and (Megastructures.running(m) or int(Megastructures.kind_def(String(m["k"])).get("era", 1)) >= 4):
			return true
	return false


# --- Religion (prop. 37) -----------------------------------------------------------------------------

## Pose d'un Chantier : emmailloter l'étoile d'un lieu saint est un sacrilège.
static func on_pose(state: GameState, m: Dictionary, added: Array[Dictionary]) -> void:
	if not Megastructures.full(state) or int(m["p"]) != -1:
		return
	var eid := int(m["o"])
	var sid := int(m["s"])
	var angry: Array[int] = []
	if state.faith_on:
		var fl: Dictionary = state.faiths.get("list", {})
		var keys := fl.keys()
		keys.sort()
		for fid in keys:
			var f: Dictionary = fl[fid]
			var holy := int(f.get("holy", -1))
			var founder := int(f.get("founder", -1))
			if holy >= 0 and state.galaxy.get_planet(holy).system_id == sid and founder >= 0 and founder != eid and not angry.has(founder):
				angry.append(founder)
	for x in angry:
		Diplomacy.remember(state, x, eid, "mega_sacrilege")
	if not angry.is_empty():
		added.append(state.add_chronicle("Sacrilège : %s emmaillote l'étoile d'un lieu saint. Les fidèles de %s ne l'oublieront pas." % [
				state.get_empire(eid).short_name(), ", ".join(PackedStringArray(angry.map(func(x: int) -> String: return state.get_empire(x).short_name())))]))
	var hw := AncientsBridges.holy_world_in(state, sid)
	if hw >= 0:
		AncientsBridges.holy_war(state, Ancients.holy_owner(state, hw), eid, "emmaillote l'étoile d'un Monde saint", added)


## Opinion des credos envers qui tient une grande mégastructure (ère IV et plus).
static func opinion_parts(state: GameState, a: int, b: int) -> Array:
	var out := []
	if not Megastructures.full(state) or GameState.is_npc(a) or GameState.is_npc(b):
		return out
	var great := 0
	for m in Megastructures.owned_by(state, b):
		if Megastructures.complete(m) and int(Megastructures.kind_def(String(m["k"])).get("era", 1)) >= 4:
			great += 1
	if great == 0:
		return out
	var credo := String(FactionTraits.species(state.get_empire(a).faction()).get("credo", ""))
	var v := int((cfg().get("credo_opinion", {}) as Dictionary).get(credo, 0))
	if v != 0:
		out.append([("Admire ses mégastructures" if v > 0 else "Ses mégastructures défient l'ordre des étoiles"), v])
	return out


# --- Transcendance (prop. 38) --------------------------------------------------------------------

## Une mégastructure achevée (ère IV et plus) dans le système de l'Exodium : la première étape est d'avance.
static func exodium_site(state: GameState, eid: int, sid: int) -> bool:
	if not Megastructures.full(state) or sid < 0:
		return false
	for m in Megastructures.in_system(state, sid):
		if int(m["o"]) == eid and Megastructures.complete(m) and int(Megastructures.kind_def(String(m["k"])).get("era", 1)) >= c_int("exodium_era", "", 4):
			return true
	return false


## Le Cerveau Matriochka nourrit la jauge du Songe et du Téléversement.
static func gain_parts(state: GameState, eid: int) -> Array:
	var out := []
	if not Megastructures.full(state):
		return out
	var path := Transcendence.path_of(state, eid)
	var eb: Dictionary = Megastructures.kind_def("matriochka").get("elevation_bonus", {})
	if not eb.has(path):
		return out
	for m in Megastructures.owned_by(state, eid):
		if String(m["k"]) == "matriochka" and Megastructures.eff_stage(m) > 0:
			out.append(["Cerveau Matriochka", int(eb[path]) * Megastructures.eff_stage(m)])
			break
	return out


# --- Achèvement, prise, Kardashev ----------------------------------------------------------------

static func on_complete(state: GameState, m: Dictionary, added: Array[Dictionary]) -> void:
	var eid := int(m["o"])
	# Le gouverneur du système gagne le trait Architecte (prop. 41).
	if not state.heroes.is_empty():
		var h := Heroes.at_post(state, "system", int(m["s"]), eid)
		if not h.is_empty():
			CrisisAllies._give(state, h, "architecte", added)
	# Les credos de foi nourrissent le zèle en voyant l'ouvrage (rien de plus ici : opinion_parts).
	if Megastructures.full(state) and String(m["k"]) == "monde_anneau" and Megastructures.first_of(state, "monde_anneau") == eid:
		added.append(state.add_chronicle("%s achève le premier Monde-anneau de la galaxie. Les cartographes doivent tout redessiner." % state.get_empire(eid).short_name()))


static func on_taken(state: GameState, _m: Dictionary, before: int, after: int, _added: Array[Dictionary]) -> void:
	if before >= 0 and after >= 0:
		Diplomacy.remember(state, before, after, "mega_taken")


static func on_kardashev(_state: GameState, _eid: int, _tier: int, _added: Array[Dictionary]) -> void:
	pass  # hauts faits Kardashev II et III : DeedsEval (« mega_kard »)


# --- Hauts faits et victoire (prop. 42) ----------------------------------------------------------

static func deed_value(state: GameState, eid: int, k: String) -> int:
	if k == "mega_kard":
		return Kardashev.tier(state, eid)
	if not Megastructures.enabled(state):
		return 0
	match k:
		"mega_rings":
			return Megastructures.complete_count(state, eid, "monde_anneau")
	return 0


## Grands Œuvres : chaque mégastructure de l'ère V achevée compte, chacune dans son système.
static func great_works(state: GameState, eid: int) -> int:
	if not Megastructures.enabled(state):
		return 0
	var seen := {}
	for m in Megastructures.owned_by(state, eid):
		if Megastructures.complete(m) and int(Megastructures.kind_def(String(m["k"])).get("era", 1)) >= 5:
			seen[int(m["s"])] = true
	return seen.size()
