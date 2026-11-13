extends RefCounted
## Tests des populations mixtes, lot 2 (statut et politique) : statuts permis, délai entre deux
## changements, intégration (conquête, montée annuelle), lignes de stabilité, production des
## assujettis, extermination, expulsion, assimilation, frictions, opinion mêlée des citoyens, lois,
## doléance « Des droits pour mon peuple », héros d'autres espèces, opinion diplomatique, sauvegarde 41.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Peuples mêlés, statut et politique (statuts, intégration, frictions, lois, droits, héros)…")
	_test_allowed()
	_test_cooldown()
	_test_integration()
	_test_stability()
	_test_production()
	_test_departures()
	_test_affinity()
	_test_nature()
	_test_laws()
	_test_rights()
	_test_heroes()
	_test_opinion()
	_test_ai()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _state(politics := false) -> GameState:
	var st := GameState.create(4242, 150, 1800.0, "vael", {"ai_level": "", "peoples": "actifs", "politics": "active" if politics else "aucune"})
	for e in st.empires:
		e.resources["energy"] = 5000
		e.resources["influence"] = 5000
		e.resources["materials"] = 5000
	return st


func _id_of(st: GameState, faction: String) -> int:
	for e in st.empires:
		if e.faction_id == faction:
			return e.id
	return -1


## Une colonie établie sur une planète habitable libre, dans un système libre.
func _plant(st: GameState, owner: int, pop: int) -> Colony:
	for s in st.galaxy.systems:
		if st.system_owner(s.id) >= 0:
			continue
		for pid in s.planet_ids:
			var p := st.galaxy.get_planet(pid)
			if Economy._pop_hab(st, owner, p.type) < 60:
				continue
			var c := Colony.new()
			c.planet_id = pid
			c.owner = owner
			c.kind = Colony.KIND_COLONY
			c.population = pop
			st.add_colony(c)
			st.rebuild_ownership()
			return c
	return null


func _sid(st: GameState, c: Colony) -> int:
	return st.galaxy.get_planet(c.planet_id).system_id


func _part(parts: Array, prefix: String) -> int:
	for p in parts:
		if String(p[0]).begins_with(prefix):
			return int(p[1])
	return 0


## Avance jusqu'au prochain bilan annuel (jour multiple de 360) et lance le bilan des peuples.
func _year(st: GameState) -> void:
	st.tick = (st.tick / 360 + 1) * 360
	Peoples.refresh(st)
	var added: Array[Dictionary] = []
	Peoples.monthly(st, added)


func _test_allowed() -> void:
	var st := _state()
	var v := _id_of(st, "vael")
	var k := _id_of(st, "khthari")
	var t := _id_of(st, "teyl")
	var o := _id_of(st, "ossarane")
	_ok(not Peoples.allowed_statuses(st, v, "ossarane").has("assujettis"), "la république n'assujettit pas")
	_ok(Peoples.allowed_statuses(st, o, "vael").has("assujettis") and Peoples.allowed_statuses(st, o, "vael").has("citoyens"), "Ossarane peut faire des Vael des citoyens ou des assujettis")
	var hive := Peoples.allowed_statuses(st, k, "vael")
	_ok(not hive.has("citoyens") and not hive.has("residents") and hive.has("assujettis"), "une ruche n'a que des assujettis (ou les chasse)")
	var syn := Peoples.allowed_statuses(st, t, "vael")
	_ok(not syn.has("citoyens") and syn.has("residents"), "une conscience n'a que des résidents ou des assujettis")
	_ok(not Peoples.allowed_statuses(st, o, "khthari").has("citoyens"), "les habitants d'une ruche ne deviennent pas citoyens")
	_ok(Peoples.allowed_statuses(st, o, "vael").has("extermines"), "l'extermination reste un choix possible")
	_ok(Peoples.status(st, k, "vael") == "assujettis" and Peoples.status(st, v, "ossarane") == "citoyens", "statuts par défaut")
	_ok(Peoples.status(st, v, "vael") == "citoyens", "l'espèce fondatrice est toujours citoyenne")
	_ok(SimCommands.validate(st, SimCommands.peoples_status(v, "vael", "residents")) != "", "on ne change pas le statut de son propre peuple")
	_ok(SimCommands.validate(st, SimCommands.peoples_status(v, "ossarane", "assujettis")) != "", "ordre refusé : république")


func _test_cooldown() -> void:
	var st := _state()
	var v := _id_of(st, "vael")
	var cmd := SimCommands.peoples_status(v, "ossarane", "residents")
	_ok(SimCommands.validate(st, cmd) == "", "premier changement de statut accepté")
	SimCommands.apply(st, cmd)
	_ok(Peoples.status(st, v, "ossarane") == "residents", "les Ossarane sont résidents")
	_ok(SimCommands.validate(st, SimCommands.peoples_status(v, "ossarane", "citoyens")) != "", "pas de nouveau changement avant 5 ans")
	st.tick += int(Peoples.data()["status_days"])
	_ok(SimCommands.validate(st, SimCommands.peoples_status(v, "ossarane", "citoyens")) == "", "5 ans plus tard, c'est possible")


func _test_integration() -> void:
	var st := _state()
	var v := _id_of(st, "vael")
	var o := _id_of(st, "ossarane")
	var c := _plant(st, o, 6)
	Combat.capture_system(st, _sid(st, c), v)
	# (un habitant sur cinq fuit la conquête : lot 3)
	_ok(int(c.species.get("ossarane", 0)) == 5 and Peoples.integration(c, "ossarane") == 0, "monde conquis : intégration à 0 %")
	var rate := Peoples.integration_rate(st, c, "ossarane")
	# 5 + 2 (citoyens), +50 % pour le talent Pluriel des Vael (lot 3).
	_ok(rate == 10, "citoyens : +10 %% par an avec le talent Pluriel (%d)" % rate)
	_year(st)
	_ok(Peoples.integration(c, "ossarane") == 10, "un an plus tard : 10 %% (%d)" % Peoples.integration(c, "ossarane"))
	Peoples.set_status(st, v, "ossarane", "expulses")
	_ok(Peoples.integration_rate(st, c, "ossarane") == 0, "des expulsés ne s'intègrent pas")


func _test_stability() -> void:
	var st := _state()
	var f := _id_of(st, "ferrocornes")
	var c := _plant(st, f, 10)
	c.species = {"vael": 6}
	c.integ = {"vael": 0}
	var sid := _sid(st, c)
	var parts := Peoples.stability_parts(st, sid, f)
	_ok(_part(parts, "Peuples mal intégrés") < 0, "peuples mal intégrés : malus (%d)" % _part(parts, "Peuples mal intégrés"))
	_ok(_part(parts, "Assujettis") == 0, "pas d'assujettis par défaut")
	Peoples.set_status(st, f, "vael", "assujettis")
	parts = Peoples.stability_parts(st, sid, f)
	_ok(_part(parts, "Assujettis") == -10, "assujettis : -10 de stabilité")
	Peoples.set_status(st, f, "vael", "residents")
	parts = Peoples.stability_parts(st, sid, f)
	_ok(_part(parts, "Résidents") == -3, "résidents majoritaires : -3")
	c.integ = {"vael": 100}
	parts = Peoples.stability_parts(st, sid, f)
	_ok(_part(parts, "Peuples mal intégrés") == 0, "bien intégrés : plus de malus")
	var found := false
	for p in Stability.parts(st, sid):
		if String(p[0]).begins_with("Résidents"):
			found = true
	_ok(found, "la ligne apparaît dans l'ordre intérieur du système")


func _test_production() -> void:
	var st := _state()
	var f := _id_of(st, "ferrocornes")
	var c := _plant(st, f, 10)
	c.species = {"vael": 5}
	c.integ = {"vael": 100}
	var base := Economy.colony_yields(st, c)
	Peoples.set_status(st, f, "vael", "assujettis")
	var forced := Economy.colony_yields(st, c)
	var b0 := int(base["gross"].get("materials", 0)) + int(base["gross"].get("energy", 0))
	var b1 := int(forced["gross"].get("materials", 0)) + int(forced["gross"].get("energy", 0))
	_ok(b1 > b0, "les assujettis produisent plus (%d > %d)" % [b1, b0])
	_ok(Peoples.species_prod_mod(st, c, "vael") == 125, "+25 % de leur part")
	c.integ = {"vael": 0}
	Peoples.set_status(st, f, "vael", "citoyens")
	_ok(Peoples.species_prod_mod(st, c, "vael") == 75, "mal intégrés : -25 %")


func _test_departures() -> void:
	var st := _state()
	var f := _id_of(st, "ferrocornes")
	var v := _id_of(st, "vael")
	var c := _plant(st, f, 10)
	c.species = {"vael": 4, "ossarane": 3}
	Peoples.set_status(st, f, "vael", "extermines")
	st.tick = 30
	Peoples.refresh(st)
	var added: Array[Dictionary] = []
	Peoples.monthly(st, added)
	_ok(int(c.species.get("vael", 0)) == 3 and c.population == 9, "extermination : un habitant de moins par mois")
	var hated := false
	var kin := false
	for m in st.memories:
		if int(m["about"]) == f and String(m["kind"]) == "exterminator":
			hated = true
		if int(m["about"]) == f and int(m["who"]) == v and String(m["kind"]) == "kin_exterminated":
			kin = true
	_ok(hated and kin, "toute la galaxie s'en souvient, et la Concorde plus encore")
	_ok(_part(Peoples.stability_parts(st, _sid(st, c), f), "Exterminés") == -15, "extermination : -15 de stabilité")
	Peoples.set_status(st, f, "vael", "citoyens")
	Peoples.set_status(st, f, "ossarane", "expulses")
	st.tick = 90 * 2  # trimestre
	Peoples.monthly(st, added)
	_ok(int(c.species.get("ossarane", 0)) == 2 and c.population == 8, "expulsion : un départ par trimestre")
	Peoples.set_status(st, f, "ossarane", "assimiler")
	_year(st)
	_ok(int(c.species.get("ossarane", 0)) == 1 and c.population == 8, "assimilation : un Ossarane devient Ferrocorne par an")


func _test_affinity() -> void:
	_ok(Peoples.affinity("vael", "khthari") < 0, "humanoïdes et ruche : friction (%d)" % Peoples.affinity("vael", "khthari"))
	_ok(Peoples.affinity("vael", "teyl") != Peoples.affinity("vael", "khthari"), "chaque paire a sa valeur")
	_ok(Peoples.affinity("teyl", "vael") == Peoples.affinity("vael", "teyl"), "symétrique")
	var st := _state()
	var o := _id_of(st, "ossarane")
	var c := _plant(st, o, 10)
	c.species = {"khthari": 5}
	var fr := _part(Peoples.stability_parts(st, _sid(st, c), o), "Frictions")
	_ok(fr < 0 and fr >= -5, "colonie mêlée en friction : malus plafonné à -5 (%d)" % fr)


func _test_nature() -> void:
	var st := _state()
	var ch := _id_of(st, "choeur")
	if ch < 0:
		_ok(true, "pas de Chœur dans cette partie")
		return
	var c := _plant(st, ch, 10)
	var sid := _sid(st, c)
	var nat := Politics.nature(st, ch)
	_ok(Peoples.system_nature(st, sid, ch, nat) == nat, "sans autre peuple, penchant du fondateur")
	c.species = {"teyl": 8}
	var mixed := Peoples.system_nature(st, sid, ch, nat)
	var ac := Politics.index_of("academie")
	_ok(int(mixed[ac]) > int(nat[ac]), "des citoyens de raison font monter l'Académie (%d > %d)" % [int(mixed[ac]), int(nat[ac])])
	var tot := 0
	for x in mixed:
		tot += int(x)
	_ok(tot == Politics.TOTAL, "l'opinion mêlée reste sur 1000")
	Peoples.set_status(st, ch, "teyl", "residents")
	_ok(Peoples.system_nature(st, sid, ch, nat) == nat, "des résidents ne votent pas")


func _test_laws() -> void:
	var off := GameState.create(4242, 150, 1800.0, "vael", {"ai_level": "", "politics": "active"})
	var v0 := _id_of(off, "vael")
	_ok(Laws.check_adopt(off, v0, "hospitalite") != "", "sans peuples mêlés, pas de loi Hospitalité")
	var st := _state(true)
	var v := _id_of(st, "vael")
	var o := _id_of(st, "ossarane")
	var c := _plant(st, o, 6)
	Combat.capture_system(st, _sid(st, c), v)
	var r0 := Peoples.integration_rate(st, c, "ossarane")
	var why := Laws.check_adopt(st, v, "hospitalite")
	_ok(why == "", "Hospitalité adoptable (%s)" % why)
	if why == "":
		Laws.adopt(st, v, "hospitalite")
		_ok(Peoples.integration_rate(st, c, "ossarane") > r0, "Hospitalité : intégration plus rapide")
		_ok(Laws.check_adopt(st, v, "preference_native") != "", "Préférence native incompatible avec Hospitalité")
		Laws.revoke(st, v, "hospitalite")
	why = Laws.check_adopt(st, v, "preference_native")
	if why == "":
		Laws.adopt(st, v, "preference_native")
		var home := FactionTraits.capital_system(st, v)
		_ok(_part(Peoples.stability_parts(st, home, v), "Préférence native") == 5, "Préférence native : +5 chez les siens")
		_ok(_part(Peoples.stability_parts(st, _sid(st, c), v), "Préférence native") == -5, "et -5 là où ils sont minoritaires")
	else:
		_ok(false, "Préférence native adoptable (%s)" % why)


func _test_rights() -> void:
	var st := _state()
	var o := _id_of(st, "ossarane")
	var c := _plant(st, o, 60)
	c.species = {"vael": 40}
	Peoples.set_status(st, o, "vael", "residents")
	st.tick = 30
	Peoples.refresh(st)
	var added: Array[Dictionary] = []
	Peoples.monthly(st, added)
	var d := Peoples.rights_demand(st, o)
	_ok(String(d.get("fid", "")) == "vael", "les Vael (plus de 20 %) réclament la citoyenneté")
	st.tick += int(Peoples.data()["status_days"])
	Peoples.set_status(st, o, "vael", "citoyens")
	Peoples.monthly(st, added)
	_ok(Peoples.rights_demand(st, o).is_empty(), "doléance satisfaite")
	_ok(_part(Peoples.stability_parts(st, _sid(st, c), o), "Droits des") == 5, "+5 de stabilité là où ils vivent")


func _test_heroes() -> void:
	var st := _state()
	var o := _id_of(st, "ossarane")
	var c := _plant(st, o, 4)
	c.species = {"teyl": 3}
	var c2 := _plant(st, o, 40)
	c2.species = {"teyl": 40}
	Peoples.refresh(st)
	_ok(Peoples.hero_species(st, o).has("teyl"), "les Teyl citoyens peuvent donner des héros")
	var seen := false
	for i in 20:
		if Heroes._offer_species(st, o, ["t", i]) == "teyl":
			seen = true
	_ok(seen, "un candidat teyl finit par se présenter")
	var cand := Heroes.make_candidate(st, o, "stratege", ["t"], "teyl")
	_ok(String(cand.get("sp", "")) == "teyl", "le candidat est un Teyl")
	var id := Heroes.recruit(st, o, cand)
	_ok(String(st.heroes[id].get("sp", "")) == "teyl", "le héros garde son espèce")
	var t := _id_of(st, "teyl")
	var found := false
	for p in Diplomacy.opinion_parts(st, t, o):
		if String(p["label"]).begins_with("Un des nôtres"):
			found = true
	_ok(found, "un héros teyl compte pour la diplomatie")
	Peoples.set_status(st, o, "teyl", "residents")
	_ok(Peoples.hero_species(st, o).is_empty(), "des résidents ne donnent pas de héros")


func _test_opinion() -> void:
	var st := _state()
	var f := _id_of(st, "ferrocornes")
	var v := _id_of(st, "vael")
	var c := _plant(st, f, 8)
	c.species = {"vael": 5}
	Peoples.refresh(st)
	var o0 := Diplomacy.opinion(st, v, f)
	Peoples.set_status(st, f, "vael", "assujettis")
	var o1 := Diplomacy.opinion(st, v, f)
	_ok(o1 < o0, "la Concorde n'aime pas voir les siens assujettis (%d < %d)" % [o1, o0])


func _test_ai() -> void:
	var st := _state()
	var f := _id_of(st, "ferrocornes")
	var e := st.get_empire(f)
	_ok(AiPeoples.desired(st, e, "vael", 3, {}) == "assujettis", "IA belliqueuse : assujettit")
	_ok(AiPeoples.desired(st, e, "vael", -3, {}) == "citoyens", "IA pacifique : citoyens")
	var k := st.get_empire(_id_of(st, "khthari"))
	_ok(AiPeoples.desired(st, k, "vael", -3, {}) == "assujettis", "la ruche n'a pas le choix")
	_ok(AiPeoples.desired(st, e, "vael", 0, {"fid": "vael"}) == "citoyens", "IA modérée : cède à la doléance")


func _test_save() -> void:
	var st := _state()
	var f := _id_of(st, "ferrocornes")
	var c := _plant(st, f, 9)
	c.species = {"vael": 4}
	c.integ = {"vael": 35}
	Peoples.set_status(st, f, "vael", "residents")
	Peoples.refresh(st)
	var d := st.to_dict()
	_ok(int(d["version"]) >= 41, "sauvegarde version 41 ou plus")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and Peoples.status(back, f, "vael") == "residents", "statut relu")
	var bc: Colony = back.colonies[c.planet_id]
	_ok(Peoples.integration(bc, "vael") == 35, "intégration relue")
	_ok(back.checksum() == st.checksum(), "même empreinte après relecture")
