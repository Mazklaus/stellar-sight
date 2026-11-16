class_name DefensesBridges
extends RefCounted
## Ponts des défenses spatiales avec les autres piliers (lot 3, prop. 27-35 ; voir Defenses).
##
## - Sabotage (prop. 27) : trois opérations de plus (data/espionage.json, « defenses ») : couper un
##   bouclier planétaire ou un inhibiteur pendant 30 jours, endommager les plates-formes.
## - Traité (prop. 28) : clause de paix « Démilitariser un système » (WarPeace.CLAUSES « demil ») : la
##   station et les plates-formes du système du vaincu le plus proche du vainqueur sont démontées, et
##   rien ne s'y rebâtit pendant 10 ans. Loi d'Amphictyonie : les Lois de la guerre au niveau Guerre
##   réglée interdisent les mines aux amphictyons.
## - Héros (prop. 31) : trait « Ingénieur de place » du gouverneur (capacité, réparations), et un
##   Général présent dans le système renforce le tir des défenses.
## - Terrain (prop. 32) : ceinture d'astéroïdes, cœur plus blindé ; nébuleuse, mines vite usées ;
##   tempête, inhibiteur coupé.
## - Hauts faits (prop. 33) : « Inviolée », capitale à station jamais assiégée pendant 50 ans.
## - Peuples mineurs (prop. 34) : une station selon leur âge technologique.
## - Économie (prop. 35) : l'entretien passe au budget comme celui des bâtiments ; une compagnie privée
##   peut payer une plate-forme dans un système à comptoir (Private, bâtiments privés).
## Aucun aléatoire.


static func cfg() -> Dictionary:
	return Defenses.cfg("bridges")


# --- Héros -------------------------------------------------------------------------------------

static func _governor(state: GameState, sid: int, owner: int) -> Dictionary:
	if state.heroes.is_empty():
		return {}
	return Heroes.at_post(state, "system", sid, owner)


static func capacity_bonus(state: GameState, sid: int, owner: int) -> int:
	var h := _governor(state, sid, owner)
	return Heroes.trait_fx(h, "defense_capacity") if not h.is_empty() else 0


static func repair_bonus(state: GameState, sid: int, owner: int) -> int:
	var h := _governor(state, sid, owner)
	return Heroes.trait_fx(h, "defense_repair") if not h.is_empty() else 0


## Bonus de tir des défenses fixes : un Général (poste Armée) dont la flotte est dans le système.
static func fixed_damage_pct(state: GameState, sid: int, owner: int) -> int:
	if state.heroes.is_empty():
		return 0
	return int(cfg().get("general_pct", 10)) if not Ground.generals_at(state, owner, sid).is_empty() else 0


# --- Terrain -----------------------------------------------------------------------------------

static func core_armor(state: GameState, sid: int, _owner: int) -> int:
	return int(cfg().get("asteroid_armor", 15)) if Terrain.at(state, sid).has("asteroides") else 0


static func in_nebula(state: GameState, sid: int) -> bool:
	var t := Terrain.at(state, sid)
	return t.has("nebuleuse") or t.has("nebuleuse_ionisee")


static func _storm(state: GameState, sid: int) -> bool:
	for t in Terrain.at(state, sid):
		if t.begins_with("tempete_"):
			return true
	return false


## Bouclier ("shield") ou inhibiteur ("inhib") coupé : sabotage en cours, ou tempête pour l'inhibiteur.
static func cut(state: GameState, sid: int, kind: String) -> bool:
	if kind == "inhib" and _storm(state, sid):
		return true
	var d: Dictionary = Defenses._sub(state, "cut").get(str(sid), {})
	return int(d.get(kind, 0)) > state.tick


# --- Peuples mineurs ---------------------------------------------------------------------------

## Station virtuelle d'un peuple mineur selon son âge (sur sa planète d'origine), {} sinon.
static func minor_station(state: GameState, sid: int, owner: int) -> Dictionary:
	if not Minors.enabled(state):
		return {}
	var m := Minors.get_m(state, owner)
	if m.is_empty() or int(m.get("sid", -1)) != sid:
		return {}
	var mc: Dictionary = cfg().get("minors", {})
	var t := int(mc.get("space_tier", 2))
	if Minors.is_pre(state, owner):
		var by_age: Array = mc.get("tier_by_age", [0, 0, 0, 0, 1, 1])
		t = int(by_age[clampi(int(m.get("age", 0)), 0, by_age.size() - 1)])
	var pid := int(m.get("planet", -1))
	var c: Colony = state.colonies.get(pid)
	if t <= 0 or c == null or c.owner != owner:
		return {}
	return {"t": t, "pid": pid, "o": owner}


# --- Amphictyonie ------------------------------------------------------------------------------

## Mines interdites à cet empire (amphictyon, loi Guerre réglée en vigueur).
static func mines_banned(state: GameState, eid: int) -> bool:
	return state.amph_on and Amphictyony.is_member(state, eid) and Amphictyony.banned(state, "mines")


# --- Économie privée ---------------------------------------------------------------------------

## Une compagnie peut-elle payer cette plate-forme ici ? (Colonie de la station, système à comptoir.)
static func private_ok(state: GameState, eid: int, c: Colony, bid: String) -> bool:
	if Defenses.role(bid) == "":
		return true
	if Defenses.check_build(state, eid, c, bid) != "":
		return false
	var sid := state.galaxy.get_planet(c.planet_id).system_id
	for pid in state.galaxy.systems[sid].planet_ids:
		var o: Colony = state.colonies.get(pid)
		if o != null and o.owner == eid and o.buildings.has(String(cfg().get("private_hub", "comptoir"))):
			return true
	return false


# --- Hauts faits -------------------------------------------------------------------------------

## Années depuis le dernier siège de la capitale (0 sans station à la capitale).
static func inviolate_years(state: GameState, eid: int) -> int:
	if not Defenses.enabled(state):
		return 0
	var cap := FactionTraits.capital_system(state, eid)
	if cap < 0 or Defenses.tier(state, cap) <= 0:
		return 0
	var last := int(Defenses._sub(state, "cs").get(str(eid), 0))
	@warning_ignore("integer_division")
	return maxi(0, state.tick - last) / GameCalendar.DAYS_PER_YEAR


# --- Jour par jour -----------------------------------------------------------------------------

static func daily(state: GameState, _added: Array[Dictionary]) -> void:
	# Capitales assiégées (haut fait Inviolée).
	if not state.sieges.is_empty():
		var cs := Defenses._sub(state, "cs")
		for k in state.sieges:
			var sid := int(k)
			var owner := state.system_owner(sid)
			if owner >= 0 and FactionTraits.capital_system(state, owner) == sid:
				cs[str(owner)] = state.tick
	# Sabotages et traités échus : on fait le ménage une fois par mois.
	if state.tick % int(GameData.rules()["month_days"]) != 0:
		return
	for sub in ["cut", "demil"]:
		var d := Defenses._sub(state, sub)
		for k in d.keys():
			var v: Dictionary = d[k]
			if sub == "demil":
				if int(v.get("t", 0)) <= state.tick:
					d.erase(k)
				continue
			for kind in v.keys():
				if int(v[kind]) <= state.tick:
					v.erase(kind)
			if v.is_empty():
				d.erase(k)


# --- Espionnage (prop. 27) ---------------------------------------------------------------------

## Système visé chez b : celui où a se bat ou assiège, sinon la capitale, sinon le premier qui a la
## cible ("shield", "inhib", "platform").
static func spy_target(state: GameState, a: int, b: int, kind: String) -> int:
	var cands: Array[int] = []
	var keys := state.sieges.keys() + state.battles.keys()
	keys.sort()
	for k in keys:
		if state.system_owner(int(k)) == b and not cands.has(int(k)):
			cands.append(int(k))
	var cap := FactionTraits.capital_system(state, b)
	if cap >= 0 and not cands.has(cap):
		cands.append(cap)
	for sid in EmpireReport.owned_systems(state, b):
		if not cands.has(sid):
			cands.append(sid)
	for sid in cands:
		if state.system_owner(sid) == b and _has_target(state, sid, kind):
			return sid
	return -1


static func _has_target(state: GameState, sid: int, kind: String) -> bool:
	match kind:
		"shield":
			return not Defenses.shield(state, sid).is_empty() and not cut(state, sid, "shield")
		"inhib":
			return Defenses.inhibits(state, sid)
		"platform":
			for el: Dictionary in Defenses.elements(state, sid):
				if String(el["kind"]) == "platform":
					return true
	return false


static func _op_kind(op_id: String) -> String:
	match op_id:
		"couper_bouclier":
			return "shield"
		"couper_inhibiteur":
			return "inhib"
		"saboter_plates_formes":
			return "platform"
	return ""


static func spy_check(state: GameState, a: int, b: int, op_id: String) -> String:
	var kind := _op_kind(op_id)
	if kind == "":
		return ""
	if not Defenses.enabled(state) or (kind != "shield" and not Defenses.full(state)):
		return "les défenses spatiales %s ne sont pas en jeu dans cette partie" % ("complètes" if Defenses.enabled(state) else "")
	if spy_target(state, a, b, kind) < 0:
		return "rien à saboter chez lui"
	return ""


static func spy_apply(state: GameState, a: int, b: int, o: Dictionary) -> String:
	var kind := _op_kind(String(o.get("id", "")))
	var sid := spy_target(state, a, b, kind)
	if sid < 0:
		return "les plans étaient faux. L'ingénieur qui les a vendus a changé de nom."
	var nm := state.galaxy.systems[sid].system_name
	var sc: Dictionary = cfg().get("sabotage", {})
	if kind == "platform":
		var hpd := Defenses._sub(state, "hp")
		if not hpd.has(str(sid)):
			hpd[str(sid)] = {}
		var d: Dictionary = hpd[str(sid)]
		for el: Dictionary in Defenses.elements(state, sid):
			if String(el["kind"]) != "platform":
				continue
			var k := String(el["k"])
			var hp := Defenses.hp_of(state, sid, k, String(el["u"]))
			@warning_ignore("integer_division")
			d[k] = maxi(1, hp * (100 - int(sc.get("platform_pct", 50))) / 100)
		return "des charges posées sur les plates-formes de %s : elles tiennent encore, de justesse." % nm
	var cd := Defenses._sub(state, "cut")
	if not cd.has(str(sid)):
		cd[str(sid)] = {}
	(cd[str(sid)] as Dictionary)[kind] = state.tick + int(sc.get("days", 30))
	if kind == "shield":
		return "le générateur du bouclier de %s grille dans un nuage d'étincelles : un mois sans bouclier." % nm
	return "l'inhibiteur de saut de %s se tait : un mois où l'on passe sans s'arrêter." % nm


# --- Traité (prop. 28) -------------------------------------------------------------------------

## Système du vaincu à démilitariser : celui à station le plus proche du vainqueur (-1 sinon).
static func demil_target(state: GameState, winner: int, loser: int) -> int:
	if not Defenses.enabled(state):
		return -1
	var best := -1
	var bj := 1 << 30
	for sid in EmpireReport.owned_systems(state, loser):
		if state.system_owner(sid) != loser or Defenses.tier(state, sid) <= 0:
			continue
		if GameState.is_minor(loser):
			continue
		var j := Wars.jumps_to(state, winner, sid)
		if j < bj:
			bj = j
			best = sid
	return best


## Démonte la station et les plates-formes du système visé, interdit d'y rebâtir pendant 10 ans.
static func demilitarize(state: GameState, winner: int, loser: int) -> int:
	var sid := demil_target(state, winner, loser)
	if sid < 0:
		return -1
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c == null or c.owner != loser:
			continue
		var keep: Array[String] = []
		for b in c.buildings:
			var r := Defenses.role(b)
			if r != "station" and r != "module" and r != "platform":
				keep.append(b)
		c.buildings.assign(keep)
		if c.construction != "" and Defenses.role(c.construction) in ["station", "module", "platform"]:
			c.construction = ""
			c.construction_days = 0
	var k := str(sid)
	for sub in ["hp", "gen", "sil"]:
		Defenses._sub(state, sub).erase(k)
	Defenses._sub(state, "demil")[k] = {"o": loser, "t": state.tick + int(cfg().get("demil_days", 3600))}
	state.add_chronicle("Traité : les défenses de %s sont démontées pièce par pièce, sous l'œil des inspecteurs de %s." % [
			state.galaxy.systems[sid].system_name, state.get_empire(winner).short_name()], Espionage.public_to(state, [winner, loser]))
	return sid
