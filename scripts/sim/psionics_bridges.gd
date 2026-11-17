class_name PsionicsBridges
extends RefCounted
## Pouvoirs psioniques, lot 3 : les ponts avec le reste du jeu (voir Psionics, data/psionics.json).
##
## - Le Phare du Songe (prop. 13) : grande œuvre allumée par le tribut des Nefs du Silence ; les flottes
##   de l'empire vont plus vite autour (zone gardée dans state.psionics["phz"], recalculée chaque mois).
## - L'Ambre de songe (prop. 14) : gisements posés au lancement (state.psionics["ambre"] : {planète: 1}),
##   Résonance et fêlures plus rares, puis l'habitude (state.psionics["amb"] : {eid: mois d'usage}).
## - Les Intouchables (prop. 15) : trait façonné « Néant psychique » (data/genetics.json, psi_null) :
##   aucun pouvoir ne prend dans un système où ils vivent.
## - La foi (prop. 32), la politique (prop. 33 : acte psi_regiment pour le Glaive), le programme de
##   lignées et la Souche du Songe à la cour (prop. 34), les talents des peuples (prop. 35, catalogue
##   « talents »), les Hiérophantes (prop. 36), l'espionnage et la furtivité (prop. 37).

static func cfg(k: String) -> Dictionary:
	return Psionics.cfg(k)


# --- Ambre de songe ----------------------------------------------------------------------------

## Pose les gisements d'ambre au lancement (déterministe : hachage de la graine).
static func place_ambre(state: GameState) -> void:
	if state.psionics.is_empty() or state.galaxy == null:
		return
	var a := cfg("ambre")
	var n := maxi(int(a.get("min", 2)), state.empires.size() / maxi(1, int(a.get("per_empires", 2))))
	var starts: Array = []
	for e in state.empires:
		var cs := FactionTraits.capital_system(state, e.id)
		if cs >= 0:
			starts.append(FactionTraits.jumps_from(state.galaxy, cs))
	var cands := []
	for s in state.galaxy.systems:
		if state.system_owner(s.id) >= 0 or s.planet_ids.is_empty():
			continue
		var near := 999
		for d: Dictionary in starts:
			near = mini(near, int(d.get(s.id, 999)))
		if near < int(a.get("min_jumps", 3)):
			continue
		cands.append([absi(hash([state.seed_value, "ambre", s.id])), int(s.planet_ids[absi(hash([state.seed_value, "ambre_p", s.id])) % s.planet_ids.size()])])
	cands.sort()
	var out := {}
	for i in mini(n, cands.size()):
		out[str(cands[i][1])] = 1
	state.psionics["ambre"] = out


static func ambre_planets(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for k in Psionics.sub(state, "ambre"):
		out.append(int(k))
	out.sort()
	return out


## Gisements d'ambre exploités par l'empire (colonie établie dessus).
static func ambre_of(state: GameState, eid: int) -> int:
	var n := 0
	for pid in ambre_planets(state):
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == eid and c.is_established():
			n += 1
	return n


static func ambre_res(state: GameState, eid: int) -> int:
	return ambre_of(state, eid) * int(cfg("ambre").get("res", 10))


static func ambre_felure_pct(state: GameState, eid: int) -> int:
	var a := cfg("ambre")
	return maxi(int(a.get("max_felure_pct", -30)), ambre_of(state, eid) * int(a.get("felure_pct", -10)))


static func ambre_habit(state: GameState, eid: int) -> bool:
	return int(Psionics.sub(state, "amb").get(str(eid), 0)) >= int(cfg("ambre").get("habit_months", 60))


# --- Phare du Songe ----------------------------------------------------------------------------

static func phare_system(state: GameState, eid: int) -> int:
	var b := String(cfg("phare").get("building", "phare_songe"))
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == eid and c.buildings.has(b):
			return state.galaxy.get_planet(pid).system_id
	return -1


static func phare_lit(state: GameState, eid: int) -> bool:
	if phare_system(state, eid) < 0:
		return false
	return Laws.is_enacted(state, eid, "nefs_silence") or bool(Psionics.talent(state, eid).get("phare_free", false))


## Vitesse en % d'une flotte (Phare du Songe allumé à portée).
static func phare_pct(state: GameState, f: Fleet) -> int:
	var owners: Array = Psionics.sub(state, "phz").get(str(f.system_id), [])
	return 100 + int(cfg("phare").get("speed_pct", 25)) if owners.has(f.owner) else 100


static func _phare_zone(state: GameState, added: Array[Dictionary]) -> void:
	var zone := {}
	var radius := int(cfg("phare").get("radius", 3))
	for e in state.empires:
		if not Psionics.applies(state, e.id) or not phare_lit(state, e.id):
			continue
		if Psionics.stat(state, e.id, "phare") == 0:
			Psionics._stat(state, e.id, "phare", 1)
			added.append(state.add_chronicle("Le Phare du Songe de %s s'allume : ses navigateurs l'entendent à trois sauts, comme une chanson qu'on connaît par cœur." % e.display_name(),
					Espionage.public_to(state, [e.id])))
		var j := FactionTraits.jumps_from(state.galaxy, phare_system(state, e.id))
		for sid in j:
			if int(j[sid]) <= radius:
				var l: Array = zone.get(str(sid), [])
				l.append(e.id)
				zone[str(sid)] = l
	state.psionics["phz"] = zone


# --- Intouchables ------------------------------------------------------------------------------

## Des Intouchables (espèce psi_null) vivent-ils dans ce système ?
static func null_in(state: GameState, sid: int) -> bool:
	if sid < 0 or sid >= state.galaxy.systems.size():
		return false
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c == null or c.owner < 0 or not c.is_colony() or state.get_empire(c.owner) == null:
			continue
		var cnt := Peoples.counts(state, c) if not c.species.is_empty() else {state.get_empire(c.owner).faction_id: c.population}
		for fid in cnt:
			if int(cnt[fid]) > 0 and bool(Genetics.fiche(state, c.owner, String(fid)).get("psi_null", false)):
				return true
	return false


# --- Foi, cour, Anciennes, espionnage ----------------------------------------------------------

## Ce que la foi d'État fait des sensitifs : "sacred", "hunt" ou "".
static func faith_stance(state: GameState, eid: int) -> String:
	if not state.faith_on:
		return ""
	var sf := Faiths.state_faith(state, eid)
	if sf == "":
		return ""
	var nat := FaithWars.nature(state, sf)
	var fd := cfg("faith")
	if (fd.get("sacred", []) as Array).has(nat):
		return "sacred"
	if (fd.get("hunt", []) as Array).has(nat):
		return "hunt"
	return ""


static func voyant(state: GameState, eid: int) -> Dictionary:
	return FaithBridges.voc_hero(state, eid, "voyant")


## Modificateurs de fêlure du lot 3 : [[libellé, points de %]].
static func felure_parts(state: GameState, eid: int) -> Array:
	var out := []
	var a := ambre_felure_pct(state, eid)
	if a != 0:
		out.append(["Ambre de songe", a])
	if faith_stance(state, eid) == "sacred":
		out.append(["Foi : sensitifs sacrés", int(cfg("faith").get("sacred_felure_pct", -15))])
	var c := Research.fx_int(state, eid, "psi_felure_pct")
	if c != 0:
		out.append(["Souche du Songe", c])
	return out


## Résonance du lot 3 : [[libellé, valeur]] (ambre) et % (foi sacrée).
static func gain_parts(state: GameState, eid: int) -> Array:
	var out := []
	var r := ambre_res(state, eid)
	if r > 0:
		out.append(["Ambre de songe", r])
	return out


static func res_pct(state: GameState, eid: int) -> int:
	return int(cfg("faith").get("sacred_res_pct", 15)) if faith_stance(state, eid) == "sacred" else 0


static func cost_pct(state: GameState, eid: int, power: String) -> int:
	if power == "prescience" and not voyant(state, eid).is_empty():
		return int(cfg("faith").get("voyant_prescience_pct", -50))
	return 0


## Hiérophantes de l'Aube Première : maîtres du Songe.
static func hierophantes(state: GameState) -> int:
	if not Ancients.enabled(state):
		return -1
	return Ancients.id_of_kind(state, String(cfg("ancients").get("kind", "hierophantes")))


static func open_pct(state: GameState, eid: int) -> int:
	var h := hierophantes(state)
	if h < 0 or not Ancients.met(state, eid).has(h):
		return 0
	return int(cfg("ancients").get("teach_pct", -50)) if Ancients.opinion(state, h, eid) >= int(cfg("ancients").get("teach_op", 25)) else 0


static func on_pact(state: GameState, eid: int) -> void:
	var h := hierophantes(state)
	if h >= 0:
		Ancients.add_op(state, h, eid, int(cfg("ancients").get("pact_op", -30)))


static func encryption(state: GameState, eid: int) -> int:
	if state.psionics.is_empty() or not Psionics.applies(state, eid):
		return 0
	return Psionics.law_fx(state, eid, "encryption")


## Détection en plus de viewer contre l'empire against (Lecture des esprits réussie).
static func detect_bonus(state: GameState, viewer: int, against: int) -> int:
	if state.psionics.is_empty() or against < 0:
		return 0
	return int(cfg("espionage").get("detect", 2)) if not Psionics.fx_active(state, viewer, "lecture", against).is_empty() else 0


# --- Foire aux visions, lignées ----------------------------------------------------------------

static func foire(state: GameState, eid: int, target: int, added: Array[Dictionary]) -> void:
	var pd := Psionics.power_def("foire")
	var e := state.get_empire(eid)
	var inc: Dictionary = pd.get("income", {})
	for r in inc:
		e.resources[r] = int(e.resources.get(r, 0)) + int(inc[r])
	var fake := Psionics._h(state, ["foire", eid, target, state.tick]) % 100 < int(pd.get("false_pct", 33))
	if fake:
		Diplomacy.remember(state, target, eid, "psi_foire")
	added.append(state.add_chronicle("Les médiums de %s vendent des visions à %s (%s)%s." % [e.display_name(), state.get_empire(target).display_name(), GameData.format_amounts(inc),
			" ; celle-ci était fausse, et ça se saura" if fake else ""], Espionage.private_to(state, [eid])))


static func lineage_until(state: GameState, eid: int) -> int:
	return int(Psionics.sub(state, "lineage").get(str(eid), 0))


static func check_lineage(state: GameState, eid: int) -> String:
	if Psionics.best_level(state, eid) <= 0:
		return "aucune de vos espèces n'entend %s" % Psionics.form_label(state, eid).to_lower()
	if lineage_until(state, eid) > 0:
		return "un programme de lignées est déjà en cours (jusqu'au %s)" % GameCalendar.date_string(lineage_until(state, eid))
	if not Economy.can_afford(state.get_empire(eid), cfg("lineage").get("cost", {})):
		return "il faut %s" % GameData.format_amounts(cfg("lineage").get("cost", {}))
	return ""


static func start_lineage(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	Economy.pay(state.get_empire(eid), cfg("lineage").get("cost", {}))
	Psionics.sub(state, "lineage")[str(eid)] = state.tick + int(cfg("lineage").get("years", 10)) * Heroes.DAYS_PER_YEAR
	added.append(state.add_chronicle("%s lance un programme de lignées : des mariages arrangés, des registres secrets, et l'espoir d'un enfant qui rêvera juste." % state.get_empire(eid).display_name(),
			Espionage.private_to(state, [eid])))


static func _lineage_done(state: GameState, e: Empire, added: Array[Dictionary]) -> void:
	Psionics.sub(state, "lineage").erase(str(e.id))
	Psionics._stat(state, e.id, "lineage", 1)
	if not PsionicsDream.make_elu(state, e.id, "", added).is_empty():
		return
	var young := {}
	for id in Heroes.ids_of(state, e.id):
		var h: Dictionary = state.heroes[id]
		if young.is_empty() or int(h.get("born", 0)) > int(young.get("born", 0)):
			young = h
	var tr := String(cfg("heroes").get("trait", "psionique"))
	if not young.is_empty() and not (young["traits"] as Array).has(tr):
		(young["traits"] as Array).append(tr)
	added.append(state.add_chronicle("Le programme de lignées de %s s'achève : %s." % [e.display_name(),
			("%s naît sensitif" % young["name"]) if not young.is_empty() else "aucun héritier ne répond, cette fois"], Espionage.private_to(state, [e.id])))


# --- Stabilité ---------------------------------------------------------------------------------

static func empire_stability_parts(state: GameState, eid: int) -> Array:
	var out := []
	if ambre_habit(state, eid) and ambre_of(state, eid) == 0:
		out.append(["Manque d'ambre de songe", int(cfg("ambre").get("withdrawal", -8))])
	if bool(Psionics.talent(state, eid).get("nefs_calm", false)) and Laws.is_enacted(state, eid, "nefs_silence"):
		var fx: Dictionary = Laws.law_def("nefs_silence").get("fx", {})
		if int(fx.get("stability", 0)) < 0:
			out.append(["Nefs du Silence bénies", -int(fx["stability"])])
	return out


static func system_stability_parts(state: GameState, sid: int, owner: int) -> Array:
	var out := []
	if faith_stance(state, owner) != "hunt":
		return out
	var b := String(cfg("college").get("building", "college_sensitifs"))
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == owner and c.buildings.has(b):
			out.append(["La foi chasse les sensitifs", int(cfg("faith").get("hunt_college_stability", -2))])
	return out


# --- Chaque mois -------------------------------------------------------------------------------

static func monthly(state: GameState, month: int, added: Array[Dictionary]) -> void:
	_phare_zone(state, added)
	for e in state.empires:
		if not Psionics.applies(state, e.id):
			continue
		if ambre_of(state, e.id) > 0:
			Psionics.sub(state, "amb")[str(e.id)] = int(Psionics.sub(state, "amb").get(str(e.id), 0)) + 1
		var lu := lineage_until(state, e.id)
		if lu > 0 and state.tick >= lu:
			_lineage_done(state, e, added)
		# Tribut des Nefs du Silence, une fois par an.
		if posmod(month, 12) == posmod(e.id + 6, 12) and Laws.is_enacted(state, e.id, "nefs_silence"):
			var n := PsionicsDream.lose_pop(state, e.id, int(cfg("phare").get("tribute_pop", 1)))
			if n > 0:
				Psionics._stat(state, e.id, "tribute", n)
				added.append(state.add_chronicle("Les Nefs du Silence de %s passent : on ne revoit pas les sensitifs qu'elles emportent.%s" % [e.display_name(),
						" Le Phare brille un peu plus." if phare_system(state, e.id) >= 0 else ""], Espionage.private_to(state, [e.id])))
