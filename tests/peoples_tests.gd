extends RefCounted
## Tests des populations mixtes, lot 1 (Peoples) : mosaïque gardée à la conquête, option absente,
## mise d'accord après une perte, production et nourriture par espèce, plafond de la meilleure espèce,
## naissances, colonisation avec une autre espèce, bonus de collection, sécession et sauvegarde 40.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Populations mixtes (mosaïque, naissances, colonisation, collection)…")
	_test_conquest()
	_test_off()
	_test_normalize()
	_test_yields()
	_test_cap()
	_test_births()
	_test_colonize()
	_test_collection()
	_test_transfer()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _state(on := true) -> GameState:
	var st := GameState.create(4242, 150, 1800.0, "vael", {"ai_level": "", "peoples": "actifs" if on else "aucuns"})
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


## Une colonie établie sur une planète libre d'un type donné ("" = n'importe lequel). Renvoie la colonie.
func _plant(st: GameState, owner: int, pop: int, ptype := "") -> Colony:
	for s in st.galaxy.systems:
		if st.system_owner(s.id) >= 0:
			continue
		for pid in s.planet_ids:
			var p := st.galaxy.get_planet(pid)
			if ptype != "" and p.type != ptype:
				continue
			if ptype == "" and (GameState.is_npc(owner) or Economy._pop_hab(st, owner, p.type) < 60):
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


func _test_conquest() -> void:
	var st := _state()
	var v := _id_of(st, "vael")
	var k := _id_of(st, "khthari")
	var c := _plant(st, k, 6)
	_ok(c != null, "colonie Kh'thari posée")
	var sid := st.galaxy.get_planet(c.planet_id).system_id
	Combat.capture_system(st, sid, v)
	_ok(c.owner == v, "monde pris par la Concorde")
	_ok(int(c.species.get("khthari", 0)) == 6 and c.population == 6, "les 6 Kh'thari gardent leur espèce")
	var cnt := Peoples.counts(st, c)
	_ok(cnt.size() == 1 and int(cnt.get("khthari", 0)) == 6 and Peoples.own_count(c) == 0, "aucun Vael dans la mosaïque")
	# Reprise par l'Essaim : les Kh'thari redeviennent l'espèce du propriétaire.
	Combat.capture_system(st, sid, k)
	_ok(c.species.is_empty(), "repris par l'Essaim : plus de mosaïque")


func _test_off() -> void:
	var st := _state(false)
	var v := _id_of(st, "vael")
	var c := _plant(st, _id_of(st, "khthari"), 5)
	Combat.capture_system(st, st.galaxy.get_planet(c.planet_id).system_id, v)
	_ok(c.species.is_empty() and c.population == 5, "sans l'option, les habitants prennent l'espèce du conquérant")
	_ok(Peoples.colonist_species(st, v).size() == 1, "sans l'option, une seule espèce colonisatrice")


func _test_normalize() -> void:
	var c := Colony.new()
	c.kind = Colony.KIND_COLONY
	c.population = 4
	c.species = {"khthari": 5, "teyl": 3}
	Peoples.normalize(c)
	var total := 0
	for f in c.species:
		total += int(c.species[f])
	_ok(total == 4, "la mosaïque suit le total après une perte")
	_ok(int(c.species.get("teyl", 0)) == 3 and int(c.species.get("khthari", 0)) == 1, "la plus nombreuse perd les siens d'abord")


func _test_yields() -> void:
	var st := _state()
	var v := _id_of(st, "vael")
	var c := _plant(st, v, 8)
	var base := Economy.colony_yields(st, c)
	var food0 := int(base["upkeep"].get("food", 0))
	# Moitié de Ferrocornes (sang-froid : 30 % de nourriture en moins).
	c.species = {"ferrocornes": 4}
	var mixed := Economy.colony_yields(st, c)
	var food1 := int(mixed["upkeep"].get("food", 0))
	_ok(food1 < food0, "les Ferrocornes mangent moins (%d < %d)" % [food1, food0])
	# Des Teyl synthétiques ne mangent pas de nourriture : ils consomment de l'énergie.
	c.species = {"teyl": 8}
	var syn := Economy.colony_yields(st, c)
	_ok(int(syn["upkeep"].get("food", 0)) == 0, "une colonie de synthétiques ne mange pas de nourriture")


func _test_cap() -> void:
	var st := _state()
	var v := _id_of(st, "vael")
	# Un monde toxique : 100 % pour les Kh'thari, le plancher de 60 % pour les Vael.
	var c := _plant(st, v, 2, "toxic")
	if c == null:
		_ok(true, "pas de monde toxique libre (graine)")
		return
	var p := st.galaxy.get_planet(c.planet_id)
	var cap_v := Economy.max_pop(st, p, v)
	c.species = {"khthari": 1}
	var cap_mix := Economy.max_pop(st, p, v)
	_ok(cap_mix >= cap_v, "le plafond suit la meilleure espèce présente (%d ≥ %d)" % [cap_mix, cap_v])
	_ok(Peoples.hab(st, v, "khthari", "toxic") == 100, "les Kh'thari sont chez eux sur un monde toxique")


func _test_births() -> void:
	var st := _state()
	var v := _id_of(st, "vael")
	var c := _plant(st, v, 8)
	c.species = {"brisecomete": 4}
	var before := c.population
	var seen := {}
	for i in 12:
		st.tick += 1
		if i == 0:
			_ok(Peoples.birth_weights(st, c).size() >= 1, "au moins une espèce peut naître")
		seen[Peoples.birth_species(st, c)] = true
		Peoples.on_birth(st, c)
	_ok(c.population == before + 12, "12 naissances")
	var total := 0
	for f in c.species:
		total += int(c.species[f])
	_ok(total <= c.population and Peoples.own_count(c) + total == c.population, "la mosaïque reste d'accord avec le total")
	_ok(seen.size() == 2, "les deux espèces naissent tour à tour")
	# Déterminisme : même jour, même planète, même résultat.
	_ok(Peoples.birth_species(st, c) == Peoples.birth_species(st, c), "tirage déterministe")


func _test_colonize() -> void:
	var st := _state()
	var v := _id_of(st, "vael")
	var c := _plant(st, v, 6)
	c.species = {"ferrocornes": 3}
	_ok(not Peoples.colonist_species(st, v).has("ferrocornes"), "avant le bilan mensuel, pas encore colonisatrice")
	Peoples.refresh(st)
	_ok(Peoples.colonist_species(st, v).has("ferrocornes"), "3 Ferrocornes : ils peuvent fonder une colonie")
	# Une planète d'un monde où la Concorde a un pied (on lui donne un avant-poste établi dans le système).
	var target: Planet = null
	for s in st.galaxy.systems:
		if st.system_owner(s.id) >= 0 or s.planet_ids.size() < 2:
			continue
		for pid in s.planet_ids:
			var p := st.galaxy.get_planet(pid)
			if Peoples.hab(st, v, "ferrocornes", p.type) > 0:
				target = p
				break
		if target != null:
			var o := Colony.new()
			for pid in s.planet_ids:
				if pid != target.id:
					o.planet_id = pid
					break
			o.owner = v
			o.kind = Colony.KIND_OUTPOST
			st.add_colony(o)
			st.rebuild_ownership()
			break
	_ok(target != null, "un monde pour les Ferrocornes")
	if target == null:
		return
	var cmd := SimCommands.colonize(v, target.id, Colony.KIND_COLONY, "ferrocornes")
	var why := SimCommands.validate(st, cmd)
	_ok(why == "", "colonisation par les Ferrocornes acceptée (%s)" % why)
	if why != "":
		return
	SimCommands.apply(st, cmd)
	var nc: Colony = st.colonies[target.id]
	_ok(nc.founder == "ferrocornes", "les colons attendus sont des Ferrocornes")
	var added: Array[Dictionary] = []
	for i in nc.days_left + 1:
		st.tick += 1
		EconomySystem._process_colony(st, nc, added)
	_ok(nc.is_established() and int(nc.species.get("ferrocornes", 0)) == nc.population and nc.population > 0, "la colonie fondée est peuplée de Ferrocornes")
	_ok(SimCommands.validate(st, SimCommands.colonize(v, target.id, Colony.KIND_COLONY, "murmurants")) != "", "une espèce absente de l'empire est refusée")


func _test_collection() -> void:
	var st := _state()
	var v := _id_of(st, "vael")
	var c := _plant(st, v, 14)
	c.species = {"teyl": 11}
	Peoples.refresh(st)
	var col := Peoples.collections(st, v)
	_ok(col.size() == 1 and int(col[0]["tier"]) == 1, "11 Teyl : premier palier de collection")
	var r := Peoples.strong_resource("teyl")
	_ok(Peoples.collection_pct(st, v, r) == 5, "+5 %% de %s" % r)
	c.population = 40
	c.species = {"teyl": 30}
	Peoples.refresh(st)
	_ok(Peoples.collection_pct(st, v, r) == 10, "30 Teyl : deuxième palier")


func _test_transfer() -> void:
	var st := _state()
	var v := _id_of(st, "vael")
	var c := _plant(st, v, 5)
	c.species = {"khthari": 2}
	var sid := st.galaxy.get_planet(c.planet_id).system_id
	Stability._transfer(st, sid, v, GameState.NPC_ID)
	_ok(int(c.species.get("vael", 0)) == 3 and int(c.species.get("khthari", 0)) == 2, "sécession : chaque espèce garde les siens")
	Stability._transfer(st, sid, GameState.NPC_ID, v)
	_ok(not c.species.has("vael") and int(c.species.get("khthari", 0)) == 2 and Peoples.own_count(c) == 3, "réintégration : les Vael redeviennent l'espèce du propriétaire")


func _test_save() -> void:
	var st := _state()
	var v := _id_of(st, "vael")
	var c := _plant(st, v, 7)
	c.species = {"teyl": 3}
	c.founder = ""
	Peoples.refresh(st)
	var d := st.to_dict()
	_ok(int(d["version"]) == 40, "sauvegarde version 40")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and back.peoples_on, "option des peuples mêlés relue")
	var bc: Colony = back.colonies[c.planet_id]
	_ok(int(bc.species.get("teyl", 0)) == 3, "mosaïque relue")
	_ok(back.checksum() == st.checksum(), "même empreinte après relecture")
