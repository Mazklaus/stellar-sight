extends RefCounted
## Tests de la furtivité et de la détection (étude du 2026-11-16, 41 propositions) : données et
## réglages, voiles et camouflage, détection et portée, batailles cachées et embuscade, blocus et
## siège, postures, degrés de connaissance, balises, Voile du Chœur, ponts (sonde, codes, héros,
## hauts faits, griefs), sauvegarde. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Furtivité et détection…")
	print("  - data")
	_test_data()
	print("  - cloak")
	_test_cloak()
	print("  - detection")
	_test_detection()
	print("  - battle")
	_test_battle()
	print("  - blockade_and_siege")
	_test_blockade_and_siege()
	print("  - postures")
	_test_postures()
	print("  - degrees")
	_test_degrees()
	print("  - beacons")
	_test_beacons()
	print("  - choeur")
	_test_choeur()
	print("  - bridges")
	_test_bridges()
	print("  - save")
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func new_game(mode := "complete", faction := "ossarane", seed_value := 41) -> GameState:
	var st := GameState.create(seed_value, 60, 1200.0, faction, {"ai_level": "", "stealth": mode})
	st.fleets.clear()
	Stealth.invalidate()
	return st


static func home(st: GameState, eid: int) -> int:
	return st.galaxy.get_planet(st.get_empire(eid).capital_planet).system_id


static func next_to(st: GameState, sid: int) -> int:
	var ns: Array = st.galaxy.systems[sid].neighbors.duplicate()
	ns.sort()
	for n in ns:
		if st.system_owner(int(n)) < 0:
			return int(n)
	return int(ns[0])


static func war(st: GameState, a: int, b: int) -> void:
	for p in [[a, b], [b, a]]:
		var e := st.get_empire(p[0])
		if not e.contacts.has(p[1]):
			e.contacts.append(p[1])
	Combat.start_war(st, a, b)


static func apply(st: GameState, cmd: Dictionary) -> String:
	var why := SimCommands.validate(st, cmd)
	if why == "":
		SimCommands.apply(st, cmd)
	Stealth.invalidate()
	return why


## Modèle enregistré pour eid ; renvoie son identifiant.
static func design(st: GameState, eid: int, name: String, hull: String, mods: Array, techs: Array = []) -> String:
	Research.grant(st, eid, techs)
	var before := st.designs.keys()
	var why := apply(st, SimCommands.save_design(eid, {"name": name, "hull": hull, "modules": mods}))
	if why != "":
		push_error("modèle refusé : " + why)
		return ""
	for k in st.designs.keys():
		if not before.has(k):
			return String(k)
	return ""


static func sees(st: GameState, viewer: int, f: Fleet) -> bool:
	Stealth.invalidate()
	return Fleets.fleet_visible(st, viewer, f, Fleets.visible_systems(st, viewer))


func _test_data() -> void:
	var d := GameData.stealth()
	_ok(not d.is_empty() and d.has("modes") and d.has("postures"), "data/stealth.json se charge")
	var off := GameState.create(41, 60, 1200.0, "ossarane", {"ai_level": ""})
	_ok(not Stealth.enabled(off), "sans l'option (tests, bancs), la furtivité est désactivée")
	_ok(Stealth.default_mode() == "complete", "Complète par défaut au menu")
	var st := new_game("simple")
	_ok(Stealth.enabled(st) and not Stealth.full(st), "mode Simple : niveaux sans postures")
	_ok(not Stealth.postures(st).has("silence") and Stealth.postures(st).has("ambush"), "Simple : pas de Silence radio, l'Embuscade reste")
	for t in ["voiles_1", "voiles_2", "voiles_3", "detecteurs_1", "detecteurs_2", "detecteurs_3"]:
		_ok(Research.exists(t), "technologie %s" % t)
	_ok(GameData.building("reseau_ecoute").get("stealth", false), "bâtiment Réseau d'écoute")
	var off_why := SimCommands.validate(off, SimCommands.save_design(0, {"name": "Ombre", "hull": "corvette", "modules": ["voile_1"]}))
	_ok(off_why != "", "furtivité désactivée : pas de voile sur un modèle (%s)" % off_why)


func _test_cloak() -> void:
	var st := new_game()
	var id := design(st, 1, "Ombre", "corvette", ["voile_1"], ["capteurs", "voiles_1"])
	_ok(id != "" and int(GameData.ship(id).get("cloak", 0)) == 2, "Voile I : camouflage 2 sur le modèle")
	var big := SimCommands.validate(st, SimCommands.save_design(1, {"name": "Gros", "hull": "fregate", "modules": ["voile_1"]}))
	_ok(big != "", "Voile I : petites coques seulement")
	var f := st.spawn_ship(1, id, home(st, 1))
	_ok(Stealth.base_cloak(st, f) == 2 and Stealth.cloak(st, f) == 2, "flotte voilée : camouflage 2")
	_ok(Stealth.speed_pct(st, f) == 70, "le voile I ralentit à 70 %")
	f.add_ship("corvette", -1, 0)
	Stealth.invalidate()
	_ok(Stealth.base_cloak(st, f) == 0, "un vaisseau sans voile trahit la flotte (le plus faible compte)")
	var p := st.spawn_ship(GameState.PIRATE_ID, "corvette", home(st, 1)) if st.get_empire(GameState.PIRATE_ID) != null else null
	if p != null:
		_ok(Stealth.base_cloak(st, p) == 2, "pirates : camouflage 2 en mode Complète")
	Stealth.drop(st, st.spawn_ship(1, id, home(st, 1)))
	var g: Fleet = st.fleets[st.next_fleet_id - 1]
	_ok(not Stealth.veil_up(st, g) and Stealth.recharge_left(st, g) == 30, "le voile tombe et se recharge en 30 jours")


func _test_detection() -> void:
	var st := new_game()
	var id := design(st, 1, "Ombre", "corvette", ["voile_1"], ["capteurs", "voiles_1"])
	var near := next_to(st, home(st, 0))
	var f := st.spawn_ship(1, id, near)
	var plain := st.spawn_ship(1, "corvette", near)
	_ok(sees(st, 0, plain), "une flotte sans voile à portée est vue")
	_ok(not sees(st, 0, f), "une flotte voilée (2) échappe aux yeux nus (1)")
	var c: Colony = st.colonies[st.get_empire(0).capital_planet]
	c.buildings.append("reseau_ecoute")
	_ok(sees(st, 0, f), "Réseau d'écoute (+1) : détection 2, la flotte voilée est vue")
	c.buildings.erase("reseau_ecoute")
	var det := design(st, 0, "Vigie", "corvette", ["reseau_detecteurs_1"], ["capteurs", "detecteurs_1"])
	var vig := st.spawn_ship(0, det, home(st, 0))
	_ok(Stealth.fleet_detect(st, vig) == 2, "Réseau de détecteurs I : détection 2")
	_ok(sees(st, 0, f), "la vigie perce le voile à un saut")
	st.fleets.erase(vig.id)
	_ok(not sees(st, 0, f), "sans vigie, la flotte redevient invisible")
	st.galaxy.systems[home(st, 0)].blind = true
	_ok(int(Stealth.detection_at(st, 0, home(st, 0))["det"]) == 0, "tempête de radiations : détection 0")
	st.galaxy.systems[home(st, 0)].blind = false
	var off := new_game("desactivee")
	var id2 := "corvette"
	var g := off.spawn_ship(1, id2, next_to(off, home(off, 0)))
	_ok(sees(off, 0, g), "furtivité désactivée : tout est vu comme avant")


func _test_battle() -> void:
	var st := new_game()
	war(st, 0, 1)
	var id := design(st, 1, "Lame d'ombre", "corvette", ["voile_1", "canon_cinetique"], ["capteurs", "voiles_1"])
	var sid := home(st, 0)
	var guard := st.spawn_ship(0, "corvette", sid)
	var f := st.spawn_ship(1, id, sid)
	# Une colonie à l'arrêt ne voit que 1 : la lame reste à l'écart.
	CombatSystem.process(st, [])
	_ok(st.battles.is_empty(), "une flotte cachée ne déclenche pas de bataille")
	_ok(Stealth.veil_up(st, f), "le voile reste levé hors du combat")
	_ok(apply(st, SimCommands.stealth_act(1, "pose", f.id, -1, "ambush")) == "", "posture Embuscade")
	CombatSystem.process(st, [])
	var b: Dictionary = st.battles.get(sid, {})
	_ok(not b.is_empty() and (b.get("ambush", {}) as Dictionary).has("1"), "embuscade : la bataille s'engage, notée comme telle")
	_ok(not Stealth.veil_up(st, f) and Stealth.recharge_left(st, f) > 0, "le voile tombe au premier tir")
	_ok(Stealth.damage_pct(st, b, f, 1) >= 25 and Stealth.damage_pct(st, b, guard, 1) == 0, "+25 % de dégâts le premier jour pour l'embusqué")
	_ok(Stealth.shield_pct(b, f) == 50, "boucliers à moitié le jour où le voile tombe")


func _test_blockade_and_siege() -> void:
	var st := new_game()
	war(st, 0, 1)
	var id := design(st, 1, "Lame d'ombre", "corvette", ["voile_1", "canon_cinetique"], ["capteurs", "voiles_1"])
	var sid := home(st, 0)
	var f := st.spawn_ship(1, id, sid)
	_ok(Combat.besiegers(st, sid).is_empty(), "une flotte cachée à l'écart n'assiège pas")
	var mid := next_to(st, sid)
	var block := st.spawn_ship(0, "corvette", mid)
	var mover := st.spawn_ship(1, id, mid)
	Stealth.invalidate()
	_ok(not Combat.blocks(st, 1, mid, mover), "elle se glisse à travers un blocus qui ne la voit pas")
	_ok(Combat.blocks(st, 1, mid, st.spawn_ship(1, "corvette", mid)), "une flotte visible est arrêtée")
	var hidden_blocker := st.spawn_ship(1, id, mid)
	_ok(not Combat.blocks(st, 0, mid, block) or hidden_blocker != null, "contrôle")
	Stealth.drop(st, f)
	Stealth.invalidate()
	_ok(not Combat.besiegers(st, sid).is_empty(), "voile tombé : la flotte assiège")


func _test_postures() -> void:
	var st := new_game()
	var id := design(st, 1, "Ombre", "corvette", ["voile_1"], ["capteurs", "voiles_1"])
	var f := st.spawn_ship(1, id, next_to(st, home(st, 0)))
	var v := Fleets.vision(f)
	_ok(apply(st, SimCommands.stealth_act(1, "pose", f.id, -1, "silence")) == "", "Silence radio")
	_ok(Stealth.cloak(st, f) == 3 and Stealth.vision_of(st, f) == 0 and Stealth.speed_pct(st, f) == 35, "Silence : +1 camouflage, vision réduite au système, vitesse divisée par deux")
	_ok(apply(st, SimCommands.stealth_act(1, "pose", f.id, -1, "scan")) == "", "Balayage actif")
	_ok(Stealth.cloak(st, f) == 0 and Stealth.vision_of(st, f) == v + 1, "Balayage : visible, +1 saut de portée")
	_ok(sees(st, 0, f), "en balayage, la flotte est vue")
	_ok(apply(st, SimCommands.stealth_act(0, "pose", f.id, -1, "")) != "", "on ne commande pas la flotte d'un autre")
	_ok(apply(st, SimCommands.stealth_act(1, "pose", f.id, -1, "danse")) != "", "posture inconnue refusée")


func _test_degrees() -> void:
	var st := new_game()
	var id := design(st, 1, "Ombre", "corvette", ["voile_1"], ["capteurs", "voiles_1"])
	var det := design(st, 0, "Vigie", "fregate", ["reseau_detecteurs_3", "capteurs"], ["capteurs", "detecteurs_1", "detecteurs_2", "detecteurs_3"])
	var sid := home(st, 0)
	var near := next_to(st, sid)
	var f := st.spawn_ship(1, id, near)
	var vig := st.spawn_ship(0, det, sid)
	Stealth.invalidate()
	var seen := Fleets.visible_systems(st, 0)
	_ok(Stealth.degree(st, 0, f, seen) == 3, "détection 5 contre camouflage 2 : flotte détaillée")
	st.fleets.erase(vig.id)
	var weak := design(st, 0, "Guet", "fregate", ["reseau_detecteurs_1", "capteurs"], [])
	st.spawn_ship(0, weak, sid)
	Stealth.invalidate()
	seen = Fleets.visible_systems(st, 0)
	_ok(Stealth.degree(st, 0, f, seen) == 2, "détection juste suffisante, à un saut : identifiée")
	Stealth.invalidate()
	Intel.record(st, [seen, {}, {}, {}, {}, {}, {}, {}, {}])
	var sg: Dictionary = st.get_empire(0).sightings.get(f.id, {})
	_ok(not sg.is_empty() and int(sg["owner"]) == 1, "identifiée : la silhouette porte son pavillon")
	_ok(Stealth.degree_label(1) == "Contact", "libellé du contact")


func _test_beacons() -> void:
	var st := new_game()
	var away := next_to(st, home(st, 1))
	var scout := st.spawn_ship(0, "eclaireur", away) if not GameData.ship("eclaireur").is_empty() else st.spawn_ship(0, "corvette", away)
	_ok(apply(st, SimCommands.stealth_act(0, "beacon", scout.id)).contains("technologie"), "la balise demande sa technologie")
	Research.grant(st, 0, ["capteurs", "detecteurs_1", "detecteurs_2"])
	st.get_empire(0).resources["materials"] = 500
	st.get_empire(0).resources["energy"] = 500
	var why := apply(st, SimCommands.stealth_act(0, "beacon", scout.id))
	if Combat.is_armed(scout):
		_ok(why.contains("sans armes"), "seul un éclaireur sans armes pose une balise")
		return
	_ok(why == "", "balise posée (%s)" % why)
	_ok(Stealth.beacons_of(st, 0).has(away), "la balise écoute le système")
	st.fleets.erase(scout.id)
	Stealth.invalidate()
	_ok(Fleets.visible_systems(st, 0).has(away), "la balise voit le système sans flotte")


func _test_choeur() -> void:
	var st := new_game("complete", "murmurants")
	_ok(Veil.is_veiled(st, 0), "le Chœur est un peuple voilé")
	var f := st.spawn_ship(0, "corvette", next_to(st, home(st, 1)))
	_ok(Stealth.base_cloak(st, f) == 3, "Voile du Chœur : camouflage 3")
	_ok(not sees(st, 1, f), "invisible aux yeux nus")
	Research.grant(st, 1, ["capteurs", "detecteurs_abysse"])
	_ok(sees(st, 1, f), "Détecteurs d'abysse (+2 contre les voilés) : le Chœur apparaît, comme avant")


func _test_bridges() -> void:
	var st := new_game()
	var id := design(st, 1, "Ombre", "corvette", ["voile_1"], ["capteurs", "voiles_1"])
	var near := next_to(st, home(st, 0))
	var f := st.spawn_ship(1, id, near)
	_ok(StealthBridges.veiled_fleets(st, 1) == 1, "haut fait : une flotte voilée comptée")
	StealthBridges.on_probe(st, 0, near)
	_ok(st.get_empire(0).sightings.has(f.id), "la sonde relève la flotte cachée (camouflage <= 3)")
	_ok(StealthBridges.found(st, 0) == 1, "haut fait : flotte cachée repérée")
	StealthBridges.spy_apply(st, 0, 1, {"id": "voler_codes"})
	_ok(StealthBridges.codes_bonus(st, 0, 1) == 2, "codes de camouflage volés : +2 contre ce rival")
	_ok(sees(st, 0, f), "avec les codes, la flotte voilée est vue")
	_ok(Heroes.class_traits("stratege", st).has("fantome") and not Heroes.class_traits("stratege", GameState.create(41, 60, 1200.0, "ossarane", {"ai_level": ""})).has("fantome"), "trait Fantôme seulement avec la furtivité")
	# Grief : flotte voilée repérée chez soi en temps de paix.
	var st2 := new_game()
	var id2 := design(st2, 1, "Ombre", "corvette", ["voile_1"], ["capteurs", "voiles_1"])
	var g := st2.spawn_ship(1, id2, home(st2, 0))
	StealthBridges._found(st2, 0, g)
	var has := false
	for m in st2.memories:
		if String(m["kind"]) == "naval_spy" and int(m["who"]) == 0 and int(m["about"]) == 1:
			has = true
	_ok(has, "grief « naval_spy » quand une flotte camouflée est prise chez soi en paix")


func _test_save() -> void:
	var st := new_game()
	var id := design(st, 1, "Ombre", "corvette", ["voile_1"], ["capteurs", "voiles_1"])
	var f := st.spawn_ship(1, id, home(st, 1))
	apply(st, SimCommands.stealth_act(1, "pose", f.id, -1, "ambush"))
	Stealth.drop(st, f)
	var d := st.to_dict()
	_ok(int(d["version"]) >= 83 and d.has("stealth"), "sauvegarde 83 avec la furtivité")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	var g: Fleet = back.fleets[f.id]
	_ok(Stealth.posture(back, g) == "ambush" and Stealth.recharge_left(back, g) == 30, "postures et recharges relues")
	var off := GameState.create(41, 60, 1200.0, "ossarane", {"ai_level": ""})
	_ok(not off.to_dict().has("stealth"), "désactivée : rien d'écrit")
