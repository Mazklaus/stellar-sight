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
	_ok(Designs.hull_ids_for("ossarane").has("coursier") and not Designs.hull_ids_for("ossarane").has("corvette"), "les Navigateurs remplacent la corvette par le coursier")
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
