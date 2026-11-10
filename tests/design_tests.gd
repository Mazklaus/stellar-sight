extends RefCounted
## Tests de l'éditeur de vaisseaux, lot 1 : coques à emplacements typés, modules, modèles d'origine
## calculés depuis leur coque, modèles enregistrés par empire, construction, sauvegarde.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Éditeur de vaisseaux : coques, modules, modèles…")
	_test_data()
	_test_origin()
	_test_fit()
	_test_save_design()
	_test_build_and_fight()
	_test_versions_and_retire()
	_test_savegame()
	_test_auto_design()
	_test_ai_designs()
	_test_target_priority()
	_test_miniaturisation()
	_test_hangars_and_titanic()
	_test_echelons()
	GameData.clear_custom_ships()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _state(faction := "choeur", seed_value := 5151) -> GameState:
	return GameState.create(seed_value, 150, 1800.0, faction, {"ai_level": ""})


func _apply(st: GameState, cmd: Dictionary) -> String:
	var why := SimCommands.validate(st, cmd)
	if why == "":
		SimCommands.apply(st, cmd)
	return why


func _test_data() -> void:
	var types := Designs.slot_types()
	_ok(types.has("titanic") and types.has("heavy"), "types d'emplacements en données, titanesque compris")
	var kinds_ok := true
	for mid in Designs.module_ids():
		var kind := String(Designs.module(mid).get("slot", ""))
		if kind == "integrated":
			continue
		var accepted := false
		for t in types:
			if (types[t].get("accepts", []) as Array).has(kind):
				accepted = true
		kinds_ok = kinds_ok and accepted
	_ok(kinds_ok, "chaque module a au moins un type d'emplacement qui l'accepte")
	var hulls_ok := true
	for hid in Designs.hull_ids():
		var h := Designs.hull(hid)
		for t in h.get("slots", {}):
			hulls_ok = hulls_ok and types.has(t)
		for mid in h.get("integrated", []):
			hulls_ok = hulls_ok and String(Designs.module(String(mid)).get("slot", "")) == "integrated"
		for k in Designs.STATS + ["days"]:
			hulls_ok = hulls_ok and int(h.get(k, 0)) >= 0
	_ok(hulls_ok, "coques cohérentes (types connus, modules intégrés, aucune valeur négative)")
	var techs_ok := true
	var techs: Dictionary = {}
	for t in GameData.technologies()["technologies"]:
		techs[String(t)] = true
	for mid in Designs.module_ids():
		for t in Designs.module(mid).get("requires_tech", []):
			techs_ok = techs_ok and techs.has(t)
	_ok(techs_ok, "les technologies demandées par les modules existent")
	_ok(int(Designs.hull("titan").get("slots", {}).get("titanic", 0)) == 1, "le titan a un emplacement titanesque")


func _test_origin() -> void:
	# Les classes principales gardent exactement leurs chiffres d'avant l'éditeur.
	var expect := {
		"corvette": {"hp": 80, "armor": 10, "shield": 0, "speed": 36, "troops": 2, "siege": 1, "weapons": {"kinetic": 24}, "cost": {"materials": 60, "energy": 10}, "days": 20},
		"fregate": {"hp": 150, "armor": 10, "shield": 30, "speed": 30, "troops": 4, "siege": 1, "weapons": {"beam": 30}, "cost": {"materials": 110, "energy": 30}, "days": 35},
		"croiseur": {"hp": 300, "armor": 30, "shield": 15, "speed": 24, "troops": 12, "siege": 3, "weapons": {"missile": 36, "kinetic": 12}, "cost": {"materials": 200, "energy": 60}, "days": 55},
		"cuirasse": {"hp": 520, "armor": 40, "shield": 25, "pd": 10, "speed": 20, "weapons": {"artillery": 70}, "cost": {"materials": 380, "energy": 120}, "days": 90},
		"porte_vaisseaux": {"hp": 380, "armor": 20, "shield": 30, "pd": 15, "vision": 2, "weapons": {"fighters": 44}, "days": 80},
		"titan": {"hp": 2600, "armor": 50, "shield": 40, "pd": 30, "pd_fleet": 10, "weapons": {"artillery": 70, "beam": 60, "kinetic": 50}, "cost": {"materials": 1800, "energy": 600, "crystals": 40}, "days": 300},
		"martyr": {"hp": 70, "weapons": {"martyr": 220}, "cost": {"materials": 50}, "days": 15},
		"ruche_mere": {"hp": 420, "weapons": {"fighters": 40}, "cost": {"materials": 120, "food": 120}, "pd": 10},
	}
	for sid in expect:
		var sd := GameData.ship(sid)
		var bad := PackedStringArray()
		for k in expect[sid]:
			if sd.get(k) != expect[sid][k]:
				bad.append("%s %s au lieu de %s" % [k, sd.get(k), expect[sid][k]])
		_ok(bad.is_empty(), "modèle d'origine %s : chiffres d'avant conservés %s" % [sid, ", ".join(bad)])
	_ok(GameData.ship("coursier").get("blockade_runner", false), "coursier : forcer les blocus vient de son module intégré")
	_ok(GameData.ship("fregate_quarante").get("adaptive", false), "frégate des Quarante : tactique adaptative intégrée")
	_ok(String(GameData.ship("escorteur").get("hull", "")) == "corvette", "l'escorteur est un modèle sur coque de corvette")
	var fits := true
	for sid in Designs.data().get("origin", {}):
		var o := Designs.origin(sid)
		fits = fits and Designs.check_fit(String(o["hull"]), o["modules"]) == ""
	_ok(fits, "chaque modèle d'origine tient dans les emplacements de sa coque")


func _test_fit() -> void:
	_ok(Designs.check_fit("corvette", ["canon_cinetique", "canon_cinetique", "plaques_blindage", "bouclier", "propulseurs"]) == "", "corvette pleine : 2 armes, 2 défenses, 1 soutien")
	_ok(Designs.check_fit("corvette", ["canon_cinetique", "canon_cinetique", "canon_cinetique"]) != "", "pas de 3e arme sur une corvette")
	_ok(Designs.check_fit("corvette", ["piece_artillerie"]) != "", "pas d'artillerie sur une corvette")
	_ok(Designs.check_fit("cuirasse", ["canon_cinetique", "canon_cinetique", "canon_cinetique", "canon_cinetique"]) == "", "un emplacement lourd accepte une arme normale")
	_ok(Designs.check_fit("cuirasse", ["piece_artillerie", "piece_artillerie", "piece_artillerie"]) != "", "pas plus de pièces lourdes que d'emplacements lourds")
	_ok(Designs.check_fit("martyr", ["charge_sacree"]) != "", "un module intégré ne se pose pas à la main")
	var empty := Designs.compute("croiseur", [])
	var full := Designs.compute("croiseur", ["lanceur_missiles", "lanceur_missiles", "canon_cinetique", "canon_cinetique"])
	_ok(int(empty["cost"]["materials"]) < int(full["cost"]["materials"]) and int(empty["days"]) < int(full["days"]),
			"un emplacement vide rend le vaisseau moins cher et plus vite construit")
	_ok(int(Designs.compute("fregate", ["batterie_rayons"])["weapons"]["beam"]) > int(Designs.compute("corvette", ["batterie_rayons"])["weapons"]["beam"]),
			"un module vaut plus sur une coque plus grande")


func _test_save_design() -> void:
	var st := _state()
	_ok(Designs.hull_ids_for("choeur").has("martyr") and not Designs.hull_ids_for("vael").has("martyr"), "coque de martyr : seulement pour un credo de la foi")
	_ok(Designs.hull_ids_for("ossarane").has("coursier") and Designs.hull_ids_for("ossarane").has("corvette"), "les Navigateurs ont la coque de coursier en plus de la corvette (option A : les coques de peuple s'ajoutent)")
	var spec := {"name": "Lame de l'aube", "hull": "corvette", "modules": ["canon_cinetique", "canon_cinetique", "plaques_blindage"], "line": "screen", "target": "smallest"}
	_ok(_apply(st, SimCommands.save_design(0, spec)) == "", "enregistrer un modèle valide")
	var id := "m0_0"
	_ok(st.designs.has(id), "le modèle a son identifiant")
	var sd := GameData.ship(id)
	_ok(String(sd.get("label", "")) == "Lame de l'aube" and int(sd["hp"]) == 100 and int(sd["armor"]) == 15 and int(sd["weapons"]["kinetic"]) == 24,
			"le modèle se lit comme une classe : coque + modules (%s pv, blindage %s)" % [sd.get("hp"), sd.get("armor")])
	_ok(String(sd["line"]) == "screen" and String(sd["target"]) == "smallest", "rang et priorité de cible enregistrés")
	_ok(Combat.is_military(id) and Combat.ship_strength(id) > 0, "le combat lit le modèle")
	var torp := {"name": "Aiguillon", "hull": "corvette", "modules": ["tube_torpilles"]}
	_ok(SimCommands.validate(st, SimCommands.save_design(0, torp)).begins_with("technologie requise"), "un module demande sa technologie")
	Research.grant(st, 0, ["torpilles"])
	_ok(SimCommands.validate(st, SimCommands.save_design(0, torp)) == "", "technologie acquise : le module se pose")
	_ok(SimCommands.validate(st, SimCommands.save_design(0, {"name": "Lame de l'aube", "hull": "corvette", "modules": []})) != "", "deux modèles actifs ne portent pas le même nom")
	_ok(SimCommands.validate(st, SimCommands.save_design(0, {"name": "", "hull": "corvette", "modules": []})) != "", "il faut un nom")
	_ok(SimCommands.validate(st, SimCommands.save_design(0, {"name": "Saint", "hull": "coursier", "modules": []})) != "", "pas de coque d'un autre peuple")
	Research.grant(st, 0, ["charge_sacree"])
	_ok(SimCommands.validate(st, SimCommands.save_design(0, {"name": "Saint", "hull": "martyr", "modules": ["plaques_blindage"]})) == "", "coque de peuple : module intégré + emplacements libres")
	_ok(SimCommands.validate(st, SimCommands.save_design(0, {"name": "X", "hull": "corvette", "modules": [], "line": "devant"})) != "", "rang inconnu refusé")


func _test_build_and_fight() -> void:
	var st := _state()
	_apply(st, SimCommands.save_design(0, {"name": "Lame", "hull": "corvette", "modules": ["canon_cinetique", "canon_cinetique", "plaques_blindage"], "line": "screen"}))
	var id := "m0_0"
	var e := st.get_empire(0)
	e.resources["materials"] = 5000
	e.resources["energy"] = 5000
	_ok(Designs.buildable_ids(st, 0).has(id) and Designs.buildable_ids(st, 0).has("corvette"), "liste de construction : classes du peuple puis modèles")
	var pid := e.capital_planet
	_ok(_apply(st, SimCommands.build_ship(0, pid, id)) == "", "mettre le modèle en chantier")
	var sim := Simulation.new(st)
	sim.advance(Fleets.ship_days(st, 0, id) + 1)
	var found: Fleet = null
	for f in Fleets.empire_fleets(st, 0):
		if f.count(id) > 0:
			found = f
	_ok(found != null, "le vaisseau du modèle sort des chantiers")
	if found != null:
		_ok(found.fleet_name.begins_with("Lame"), "la flotte porte le nom du modèle (%s)" % found.fleet_name)
		_ok(Fleets.composition(found).contains("Lame"), "la composition nomme le modèle")
	_ok(not Designs.buildable_ids(st, 1).has(id) and SimCommands.validate(st, SimCommands.build_ship(1, st.get_empire(1).capital_planet, id)) != "",
			"un autre empire ne construit pas ce modèle")


func _test_versions_and_retire() -> void:
	var st := _state()
	_apply(st, SimCommands.save_design(0, {"name": "Lame", "hull": "corvette", "modules": ["canon_cinetique"]}))
	_ok(SimCommands.validate(st, SimCommands.save_design(0, {"name": "Lame II", "hull": "fregate", "modules": [], "previous": "m0_0"})) != "",
			"une nouvelle version garde la même coque")
	_ok(_apply(st, SimCommands.save_design(0, {"name": "Lame", "hull": "corvette", "modules": ["canon_cinetique", "canon_cinetique"], "previous": "m0_0"})) == "",
			"nouvelle version (même nom permis)")
	_ok(st.designs["m0_0"]["retired"] and int(st.designs["m0_1"]["version"]) == 2, "l'ancienne version est retirée, la nouvelle est la version 2")
	_ok(not Designs.buildable_ids(st, 0).has("m0_0") and Designs.buildable_ids(st, 0).has("m0_1"), "seule la dernière version se construit")
	_ok(_apply(st, SimCommands.retire_design(0, "m0_1")) == "" and not Designs.buildable_ids(st, 0).has("m0_1"), "retirer un modèle")
	_ok(_apply(st, SimCommands.retire_design(0, "m0_1", false)) == "" and Designs.buildable_ids(st, 0).has("m0_1"), "remettre un modèle en service")
	_ok(SimCommands.validate(st, SimCommands.retire_design(1, "m0_1")) != "", "on ne retire pas le modèle d'un autre empire")


func _test_savegame() -> void:
	var st := _state()
	_apply(st, SimCommands.save_design(0, {"name": "Lame", "hull": "corvette", "modules": ["canon_cinetique", "plaques_blindage"]}))
	var home := st.galaxy.get_planet(st.get_empire(0).capital_planet).system_id
	st.spawn_ship(0, "m0_0", home)
	var d := st.to_dict()
	_ok(int(d["version"]) == 10 and (d["designs"] as Array).size() == 1, "sauvegarde version 10 avec les modèles")
	var text := JSON.stringify(d)
	GameData.clear_custom_ships()
	var back := GameState.from_dict(JSON.parse_string(text))
	_ok(back != null, "recharger une partie avec un modèle (%s)" % GameState.last_error)
	if back != null:
		_ok(back.checksum() == st.checksum(), "empreinte identique après rechargement")
		_ok(int(GameData.ship("m0_0").get("hp", 0)) == 100, "le modèle est de nouveau lisible après chargement")
	var old: Dictionary = JSON.parse_string(JSON.stringify(_state().to_dict()))
	old["version"] = 9
	old.erase("designs")
	old.erase("next_design_id")
	var v9 := GameState.from_dict(old)
	_ok(v9 != null and v9.designs.is_empty(), "une sauvegarde version 9 se charge encore (sans modèles)")


func _test_auto_design() -> void:
	var st := _state()
	Research.grant(st, 0, ["coques_lourdes", "debarquement", "torpilles"])
	var all_fit := true
	for role in Designs.ROLES:
		for hid in ["corvette", "fregate", "croiseur"]:
			for q in 3:
				var spec := Designs.auto_design(st, 0, hid, role, q, 3)
				all_fit = all_fit and Designs.check_fit(hid, spec["modules"]) == "" \
						and Research.knows_all(st, 0, Designs.required_techs(hid, spec["modules"]))
	_ok(all_fit, "conception automatique : tout rôle, toute qualité, le modèle tient et n'utilise que des modules connus")
	var inv := Designs.auto_design(st, 0, "fregate", "invasion", 1)
	_ok((inv["modules"] as Array).count("soute_troupes") == 2 and GameData.combat() != null and Designs.compute("fregate", inv["modules"]).get("weapons", {}).is_empty(),
			"rôle Invasion : soutes à troupes, pas d'armes")
	var esc := Designs.auto_design(st, 0, "corvette", "escorte", 1)
	_ok((esc["modules"] as Array).has("antimissile") and String(esc["line"]) == "screen", "rôle Escorte : antimissile d'abord, à l'écran")
	_ok((Designs.auto_design(st, 0, "corvette", "torpilleur", 1)["modules"] as Array).has("tube_torpilles"), "rôle Torpilleur : tubes lance-torpilles")
	# Qualité 2 : les défenses suivent les armes vues en bataille.
	st.battle_reports.append({"units": [[0, "corvette", "screen", 0], [1, "fregate", "line", 0], [1, "fregate", "line", 0]]})
	var vs_beams := Designs.auto_design(st, 0, "fregate", "ligne", 2)
	_ok((vs_beams["modules"] as Array).count("bouclier") == 2, "Légende face à des rayons : boucliers (%s)" % ", ".join(vs_beams["modules"]))
	st.battle_reports.clear()
	st.battle_reports.append({"units": [[0, "corvette", "screen", 0], [1, "corvette", "screen", 0], [1, "corvette", "screen", 0]]})
	var vs_guns := Designs.auto_design(st, 0, "fregate", "ligne", 2)
	_ok((vs_guns["modules"] as Array).count("plaques_blindage") == 2, "face à des canons : blindage (%s)" % ", ".join(vs_guns["modules"]))
	var balanced := Designs.auto_design(st, 0, "fregate", "ligne", 1)
	_ok((balanced["modules"] as Array).has("plaques_blindage") and (balanced["modules"] as Array).has("bouclier"), "qualité 1 : blindage et bouclier équilibrés")


func _test_ai_designs() -> void:
	var sim := Simulation.new(GameState.create(23, 150, 1800.0, "", {"spectator": true, "ai_level": "veteran"}))
	sim.advance(420)
	var st := sim.state
	var every_ai := true
	var used := 0
	for e in st.empires:
		var mine := Designs.designs_of(st, e.id, true)
		every_ai = every_ai and not mine.is_empty()
		for f in Fleets.empire_fleets(st, e.id):
			for sh in f.ships:
				if st.designs.has(sh):
					used += 1
	for pid in st.colonies:
		if st.designs.has(String(st.colonies[pid].ship_build)):
			used += 1
	_ok(every_ai, "chaque IA a conçu ses propres modèles avec l'éditeur")
	_ok(used > 0, "les IA construisent leurs modèles (%d vaisseaux en service ou en chantier)" % used)
	var roles_ok := true
	for id in st.designs:
		var rec: Dictionary = st.designs[id]
		roles_ok = roles_ok and Designs.CLASS_ROLES.has(String(rec.get("role", ""))) and String(rec.get("sig", "")) != ""
	_ok(roles_ok, "un modèle d'IA dit quelle classe il remplace et quand il a été conçu")


func _test_target_priority() -> void:
	_ok(CombatSystem._prio_weight("largest", "cuirasse") > CombatSystem._prio_weight("largest", "corvette"), "« les plus gros » pèse plus sur une grande coque")
	_ok(CombatSystem._prio_weight("smallest", "corvette") > CombatSystem._prio_weight("smallest", "cuirasse"), "« les plus petits » pèse plus sur une petite coque")
	_ok(CombatSystem._prio_weight("rear", "porte_vaisseaux") > CombatSystem._prio_weight("rear", "fregate"), "« porteurs et arrière » vise les porteurs")
	var big := Fleet.new()
	big.add_ship("corvette")
	big.add_ship("croiseur")
	var list := [[big, 0, 3], [big, 1, 2]]
	var near: Array = CombatSystem._cumulate(list, false)
	var large: Array = CombatSystem._cumulate(list, false, "largest")
	_ok(int(near[0][0][2]) * 100 / int(near[1]) > int(large[0][0][2]) * 100 / int(large[1]),
			"avec « les plus gros », la corvette est moins souvent visée que le croiseur")
	var rear := [[big, 0, 0], [big, 1, 2]]
	_ok(int(CombatSystem._cumulate(rear, false, "rear")[0].size()) == 1, "l'arrière reste protégé tant que le front tient, quelle que soit la priorité")
	# En bataille : un modèle « les plus gros » tire surtout sur le croiseur.
	var rates := []
	for prio in ["nearest", "largest"]:
		var st := _state("vael", 6161)
		_apply(st, SimCommands.save_design(0, {"name": "Batteries", "hull": "fregate", "modules": ["batterie_rayons", "batterie_rayons", "batterie_rayons"], "target": prio}))
		var hits := _battle_hits(st, "m0_0")
		rates.append(hits[1] * 100 / maxi(1, hits[0] + hits[1]))
	_ok(int(rates[1]) > int(rates[0]) + 10, "en bataille, « les plus gros » vise bien plus le croiseur derrière l'écran de corvettes (%d %% des tirs contre %d %%)" % [rates[1], rates[0]])


## Tirs d'un modèle sur 3 corvettes et 1 croiseur ennemis pendant le premier jour d'une bataille :
## [tirs sur des corvettes, tirs sur le croiseur].
func _battle_hits(st: GameState, design_id: String) -> Array:
	var home := st.galaxy.get_planet(st.get_empire(0).capital_planet).system_id
	var mine := st.spawn_ship(0, design_id, home)
	for _i in 5:
		mine.add_ship(design_id)
	var foe := st.spawn_ship(1, "croiseur", home)
	for _i in 3:
		foe.add_ship("corvette")
	# Le croiseur est en ligne, les corvettes à l'écran : sans priorité, les corvettes prennent l'essentiel.
	Combat.start_war(st, 0, 1)
	var sim := Simulation.new(st)
	sim.advance(2)
	var counts := [0, 0]
	for r in [st.battles.values(), st.battle_reports]:
		for b: Dictionary in r:
			var units: Array = b.get("units", [])
			for day: Dictionary in b.get("log", []):
				if int(day.get("day", 0)) != 1:
					continue  # le premier jour seulement : ensuite l'écran tombe et tout va au croiseur
				for shot: Array in day.get("shots", []):
					if int(shot[0]) < 0 or int(shot[1]) < 0 or String(units[int(shot[0])][1]) != design_id:
						continue
					counts[1 if String(units[int(shot[1])][1]) == "croiseur" else 0] += 1
	return counts


func _test_miniaturisation() -> void:
	var st := _state("vael", 7171)
	Research.grant(st, 0, ["coques_lourdes", "artillerie"])
	var spec := {"name": "Croiseur d'artillerie", "hull": "croiseur", "modules": ["piece_artillerie", "piece_artillerie"]}
	_ok(SimCommands.validate(st, SimCommands.save_design(0, spec)) != "", "sans marque III, pas d'artillerie sur un croiseur")
	Research.grant(st, 0, ["canons_rail", "obusiers"])
	_ok(SimCommands.validate(st, SimCommands.save_design(0, spec)) == "", "artillerie marque III : deux pièces sur un croiseur (%s)" % SimCommands.validate(st, SimCommands.save_design(0, spec)))
	var pd := {"name": "Corvette bouclier", "hull": "corvette", "modules": ["antimissile", "antimissile", "antimissile"]}
	_ok(SimCommands.validate(st, SimCommands.save_design(0, pd)) != "", "sans marque III, l'antimissile reste en défense")
	Research.grant(st, 0, ["interception", "phase_dense"])
	_ok(SimCommands.validate(st, SimCommands.save_design(0, pd)) == "", "antimissile marque III : il tient aussi en soutien")
	Research.grant(st, 0, ["chasse", "antimatiere"])
	var fr := {"name": "Frégate porteuse", "hull": "fregate", "modules": ["hangar_chasseurs"]}
	_ok(SimCommands.validate(st, SimCommands.save_design(0, fr)) == "" and int(Designs.compute("fregate", ["hangar_chasseurs"])["weapons"]["fighters"]) > 0,
			"chasseurs marque III : un hangar léger sur une frégate")
	var auto := Designs.auto_design(st, 0, "croiseur", "artillerie", 1)
	_ok((auto["modules"] as Array).has("piece_artillerie"), "la conception automatique profite de la miniaturisation (%s)" % ", ".join(auto["modules"]))


func _test_hangars_and_titanic() -> void:
	var st := _state("vael", 8181)
	Research.grant(st, 0, ["baies", "chasse", "torpilles", "coques_lourdes"])
	var carrier := Designs.auto_design(st, 0, "porte_vaisseaux", "porteur", 1)
	_ok((carrier["modules"] as Array).has("hangar_chasseurs") and (carrier["modules"] as Array).has("hangar_bombardiers"), "un porteur mélange chasseurs et bombardiers (%s)" % ", ".join(carrier["modules"]))
	_ok(Combat.weapon_bonus(st, 0, "bombers", {"fighters": 3}) == Combat.weapon_bonus(st, 0, "fighters", {"fighters": 3}), "les bombardiers suivent la marque des chasseurs")
	var vs_big := Combat.shot_damage("bombers", 26, 2, "equilibre", 100, "cuirasse", "equilibre")
	var vs_small := Combat.shot_damage("bombers", 26, 2, "equilibre", 100, "corvette", "equilibre")
	_ok(vs_big > vs_small, "les bombardiers frappent plus fort les grosses coques (%d contre %d)" % [vs_big, vs_small])
	var inter := Designs.compute("porte_vaisseaux", ["hangar_intercepteurs"])
	_ok(int(inter["pd_fleet"]) > int(Designs.compute("porte_vaisseaux", [])["pd_fleet"]), "les intercepteurs couvrent la flotte")
	_ok(Designs.check_fit("titan", ["lance_stellaire"]) == "" and Designs.check_fit("titan", ["lance_stellaire", "hangar_geant"]) != "", "un seul module titanesque sur le titan")
	_ok(Designs.check_fit("cuirasse", ["lance_stellaire"]) != "", "pas de module titanesque hors des méga-coques")
	Research.grant(st, 0, ["lances_stellaires", "boucliers_phase"])
	_ok((Designs.auto_design(st, 0, "titan", "ligne", 1)["modules"] as Array).has("lance_stellaire"), "titan de ligne : lance stellaire")
	_ok((Designs.auto_design(st, 0, "titan", "escorte", 1)["modules"] as Array).has("bouclier_flotte"), "titan d'escorte : bouclier de flotte")
	var bare := Combat.shot_damage("beam", 30, 1, "equilibre", 100, "fregate", "equilibre")
	var covered := Combat.shot_damage("beam", 30, 1, "equilibre", 100, "fregate", "equilibre", 0, {}, 20)
	_ok(covered < bare, "le bouclier de flotte protège contre les rayons (%d contre %d)" % [covered, bare])


func _test_echelons() -> void:
	var st := _state("choeur", 9191)
	var e := st.get_empire(0)
	var cap := e.capital_planet
	var c: Colony = st.colonies[cap]
	var home := st.galaxy.get_planet(cap).system_id
	for r in GameData.resource_ids():
		e.resources[r] = 50000
	# Données : chaque échelon a son emplacement propre, qui accepte aussi les modules inférieurs.
	_ok(int(Designs.hull("leviathan").get("slots", {}).get("colossal", 0)) == 1 and int(Designs.hull("nef_monde").get("slots", {}).get("astral", 0)) == 1, "Léviathan : emplacement colossal ; Nef-monde : astral")
	_ok(Designs.check_fit("leviathan", ["lance_stellaire", "hangar_geant", "canon_siege"]) == "", "l'emplacement colossal accepte un module titanesque")
	_ok(Designs.check_fit("titan", ["forge_mobile"]) != "" and Designs.check_fit("leviathan", ["moteur_trame"]) != "", "pas de module d'un échelon supérieur sur une coque inférieure")
	_ok(Designs.check_fit("nef_monde", ["moteur_trame", "forge_mobile"]) == "", "la Nef-monde porte modules astral et colossal")
	var titan := GameData.ship("titan")
	var lev := GameData.ship("leviathan")
	var nef := GameData.ship("nef_monde")
	_ok(int(lev.get("hp", 0)) > int(titan.get("hp", 0)) and int(nef.get("hp", 0)) > int(lev.get("hp", 0)), "chaque échelon dépasse le précédent (%d, %d, %d)" % [int(titan.get("hp", 0)), int(lev.get("hp", 0)), int(nef.get("hp", 0))])
	_ok(lev.get("fleet_repair", false) and nef.get("fleet_barracks", false) and int(nef.get("fleet_speed", 0)) > 0, "modèles d'origine : forge mobile, cité de bord, moteur de trame")
	# Construction : technologie, chantier titanesque, un seul de chaque coque par empire.
	_ok(Fleets.check_build_ship(st, 0, cap, "leviathan") != "", "Léviathan verrouillé au départ")
	Research.grant_all(st, 0)
	c.buildings.append("arsenal")
	c.buildings.append("chantier_titanesque")
	_ok(Fleets.check_build_ship(st, 0, cap, "leviathan") == "", "Léviathan possible avec sa technologie et le chantier titanesque")
	st.spawn_ship(0, "titan", home)
	_ok(Fleets.check_build_ship(st, 0, cap, "leviathan") == "", "posséder un titan n'empêche pas le Léviathan")
	st.spawn_ship(0, "leviathan", home)
	_ok(Fleets.check_build_ship(st, 0, cap, "leviathan").contains("un seul"), "un seul Léviathan par empire")
	# Moteur de trame : la flotte entière avance à la vitesse de la trame.
	var slow := st.spawn_ship(0, "transport", home)
	var before := Fleets.speed(slow)
	slow.add_ship("nef_monde")
	_ok(Fleets.speed(slow) >= int(nef["fleet_speed"]) and Fleets.speed(slow) > before, "le moteur de trame entraîne toute la flotte (%d → %d)" % [before, Fleets.speed(slow)])
	# Canon à singularité : ignore blindage et boucliers.
	var vs_armor := Combat.shot_damage("singularity", 100, 1, "equilibre", 100, "cuirasse", "equilibre")
	var vs_bare := Combat.shot_damage("singularity", 100, 1, "equilibre", 100, "corvette", "equilibre")
	var art := Combat.shot_damage("artillery", 100, 1, "equilibre", 100, "cuirasse", "equilibre")
	_ok(vs_armor > art and vs_armor > vs_bare, "la singularité traverse le blindage et broie les grosses coques (%d, %d contre %d)" % [vs_armor, vs_bare, art])
	# Forge mobile et cité de bord : réparation et troupes loin de chez soi.
	var away := -1
	for sys in st.galaxy.systems:
		if st.system_owner(sys.id) == -1:
			away = sys.id
			break
	var a := st.spawn_ship(0, "leviathan", away)
	var b := st.spawn_ship(0, "titan", away)
	a.hp[0] = 1000
	b.hp[0] = 1000
	a.troops = 0
	CombatSystem._repairs(st, {})
	var pa := (a.hp[0] - 1000) * 1000 / Fleet.max_hp_of("leviathan")
	var pb := (b.hp[0] - 1000) * 1000 / Fleet.max_hp_of("titan")
	_ok(pa > pb, "la forge mobile répare comme à la maison (%d ‰ contre %d ‰)" % [pa, pb])
	var w := st.spawn_ship(0, "nef_monde", away)
	w.troops = 0
	CombatSystem._repairs(st, {})
	_ok(w.troops > 0 and a.troops == 0, "la cité de bord reforme les troupes loin de chez elles")
	# Conception automatique et IA.
	var siege := Designs.auto_design(st, 0, "nef_monde", "siege", 1)["modules"] as Array
	var line := Designs.auto_design(st, 0, "nef_monde", "ligne", 1)["modules"] as Array
	_ok(siege.has("brise_monde") and line.has("moteur_trame") and line.has("canon_singularite"), "auto : brise-monde pour le siège, trame et singularité pour la ligne")
	_ok(Designs.CLASS_ROLES.has("leviathan") and Designs.CLASS_ROLES.has("nef_monde"), "les IA conçoivent aussi leurs méga-vaisseaux")
