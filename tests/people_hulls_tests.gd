extends RefCounted
## Tests des coques de peuple (étude « Les chantiers des peuples », lots 1 et 2) : catalogue ouvert par
## couches d'espèce, deux coques de ligne et une méga-coque par peuple officiel, règles des modules
## intégrés (concorde, larves, lien, calcul prédictif, bordée, abordage, bricolage, corsaires, déphasage,
## chant d'écho, sang-froid, ambassade, chaire, ponte, sauvegarde, marché, voile abyssal, pénitents),
## titan de peuple unique avec le titan commun, IA, sauvegarde 97 ; lot 3 : silhouettes (Chantier,
## rapport de bataille, carte, style choisi dans l'éditeur d'espèces).

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Coques de peuple…")
	_test_catalogue()
	_test_flags()
	_test_unique_titan()
	_test_concord()
	_test_linked_and_penitent()
	_test_untouchable_and_broadside()
	_test_predictive()
	_test_boarding()
	_test_larvae_and_echoes()
	_test_costs()
	_test_monthly()
	_test_logistics_trade()
	_test_battle_runs()
	_test_ai()
	_test_save()
	_test_silhouettes()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _state(seed_value := 4242, faction := "ossarane") -> GameState:
	return GameState.create(seed_value, 150, 1800.0, faction, {"ai_level": ""})


func _empire_of(st: GameState, faction: String) -> int:
	for e in st.empires:
		if e.faction_id == faction:
			return e.id
	return -1


func _empty_system(st: GameState) -> int:
	for s in st.galaxy.systems:
		if st.system_owner(s.id) == -1 and s.neighbors.size() >= 2:
			return s.id
	return -1


func _war(st: GameState, a: int, b: int) -> void:
	for p in [[a, b], [b, a]]:
		if not st.get_empire(p[0]).contacts.has(p[1]):
			st.get_empire(p[0]).contacts.append(p[1])
	Combat.start_war(st, a, b)


func _spawn(st: GameState, owner: int, ships: Array, sid: int) -> Fleet:
	var f := st.spawn_ship(owner, String(ships[0]), sid)
	for i in range(1, ships.size()):
		f.add_ship(String(ships[i]))
	f.troops = Combat.max_troops(f)
	return f


func _people_hulls(fid: String) -> Array:
	var out: Array = []
	for hid in Designs.hull_ids_for(fid):
		if PeopleHulls.is_people_hull(hid):
			out.append(hid)
	return out


func _test_catalogue() -> void:
	for fid in ["ossarane", "choeur", "vael", "khthari", "teyl", "ferrocornes", "brisecomete", "murmurants"]:
		var line := 0
		var mega := 0
		for hid in _people_hulls(fid):
			if Designs.hull(hid).has("echelon"):
				mega += 1
			else:
				line += 1
		_ok(line >= 2, "%s : au moins deux coques de ligne à lui (%d)" % [fid, line])
		_ok(mega >= 1, "%s : une méga-coque de peuple (%d)" % [fid, mega])
	# Toujours en plus : les coques communes restent.
	for fid in ["choeur", "teyl", "murmurants"]:
		var ids := Designs.hull_ids_for(fid)
		_ok(ids.has("fregate") and ids.has("titan"), "%s garde la frégate et le titan communs" % fid)
	# Catalogue ouvert : une espèce de l'éditeur obtient les coques de ses couches.
	var custom := {"registre": "Classique / hard SF", "species": {"archetype": "lithoide", "gouvernement": "theocratie", "credo": "profit", "traits": []}}
	var ok_l := FactionTraits.species_matches(custom, Designs.hull("asteroide_creuse")["requires"]["species"])
	var ok_t := FactionTraits.species_matches(custom, Designs.hull("nef_penitence")["requires"]["species"])
	var ok_p := FactionTraits.species_matches(custom, Designs.hull("epave_remontee")["requires"]["species"])
	var no_r := FactionTraits.species_matches(custom, Designs.hull("nef_taniere")["requires"]["species"])
	_ok(ok_l and ok_t and ok_p and not no_r, "une espèce créée reçoit les coques de ses couches, et seulement celles-là")
	_ok(PeopleHulls.opened_by("coursier").contains("trait"), "le Chantier dit quelle couche ouvre la coque : %s" % PeopleHulls.opened_by("coursier"))
	# Chaque coque de peuple a un module intégré et une classe d'origine que l'IA sait concevoir.
	var all_ok := true
	for hid in Designs.hull_ids():
		if bool(Designs.hull(hid).get("people", false)):
			var integ: Array = Designs.hull(hid).get("integrated", [])
			all_ok = all_ok and not integ.is_empty() and not Designs.module(String(integ[0])).is_empty()
			all_ok = all_ok and not GameData.ship(hid).is_empty() and Designs.class_role(hid) != ""
	_ok(all_ok, "chaque coque de peuple : un module intégré, une classe d'origine, un rôle pour l'IA")


func _test_flags() -> void:
	var expect := {"corvette_concorde": "concord", "sporange": "larvae", "chassis_relie": "linked", "noeud_calcul": "predictive",
		"affut_roc": "broadside", "belier_clan": "boarding", "epave_remontee": "wreck_discount", "cargo_corsaire": "privateer",
		"onde_nef": "phased", "diapason": "echo_song", "nef_taniere": "cold_blood", "arche_concorde": "embassy", "cathedrale": "pulpit",
		"mere_monde": "brood", "noosphere_mere": "backup", "comete_marche": "market", "abysse_chantante": "first_salvo",
		"nef_penitence": "penitent", "galere_fief": "fleet_barracks", "asteroide_creuse": "fleet_repair", "grand_voilier": "blockade_runner"}
	for sid in expect:
		_ok(PeopleHulls.flag(sid, String(expect[sid])), "%s porte la règle %s" % [sid, expect[sid]])
	_ok(int(GameData.ship("galere_fief").get("troops", 0)) >= 16, "Galère de fief : un ost à bord")
	var oc: Dictionary = Designs.hull("onde_nef")["cost"]
	_ok(not oc.has("materials") and int(GameData.ship("onde_nef").get("armor", 0)) == 0, "Onde-nef : une coque payée en énergie, sans blindage")
	_ok(GameData.ship("asteroide_creuse").get("upkeep", {}).is_empty(), "Astéroïde creusé : aucun entretien")
	_ok(GameData.ship("sporange")["cost"].has("food"), "Sporange : payé en nourriture")
	_ok(int(GameData.ship("grand_voilier").get("speed", 0)) > int(GameData.ship("titan").get("speed", 0)), "le Grand Voilier est le plus rapide des titans")


func _test_unique_titan() -> void:
	var st := _state(91, "choeur")
	var me := _empire_of(st, "choeur")
	_ok(Fleets.unique_key("cathedrale") == Fleets.unique_key("titan"), "la Cathédrale compte comme le titan de l'empire")
	_ok(FactionTraits.ship_ids_for("choeur").has("cathedrale") and not FactionTraits.ship_ids_for("vael").has("cathedrale"), "la Cathédrale va au credo Foi seulement")
	_spawn(st, me, ["titan"], _empty_system(st))
	_ok(Fleets.count_same_hull(st, me, "cathedrale") == 1, "avec un titan commun, pas de Cathédrale en plus")


func _test_concord() -> void:
	var st := _state(5, "vael")
	var me := _empire_of(st, "vael")
	var other := (me + 1) % st.empires.size()
	var f := _spawn(st, me, ["corvette_concorde", "corvette_concorde"], _empty_system(st))
	_ok(PeopleHulls.concord_right(st, f, other), "une flotte de corvettes de concorde entre chez un empire en paix")
	f.add_ship("fregate")
	_ok(not PeopleHulls.concord_right(st, f, other), "une seule frégate ordinaire et le pavillon ne couvre plus la flotte")
	f.remove_ship("fregate")
	_war(st, me, other)
	_ok(not PeopleHulls.concord_right(st, f, other), "en guerre, le pavillon ne vaut rien")


func _test_linked_and_penitent() -> void:
	var st := _state(7, "teyl")
	var me := _empire_of(st, "teyl")
	var f := _spawn(st, me, ["chassis_relie", "chassis_relie", "chassis_relie", "corvette"], _empty_system(st))
	var pending := {Vector2i(f.id, 0): 90, Vector2i(f.id, 3): 50}
	var fl: Array[Fleet] = [f]
	PeopleHulls.share_linked(fl, pending)
	_ok(int(pending.get(Vector2i(f.id, 0), 0)) == 30 and int(pending.get(Vector2i(f.id, 1), 0)) == 30 and int(pending.get(Vector2i(f.id, 2), 0)) == 30,
			"Lien de noosphère : 90 dégâts sur un châssis = 30 sur chacun des trois")
	_ok(int(pending.get(Vector2i(f.id, 3), 0)) == 50, "la corvette non reliée garde ses dégâts")
	var g := _spawn(st, me, ["nef_penitence", "fregate"], _empty_system(st))
	var fi := g.ships.find("fregate")
	g.hp[fi] = 10
	PeopleHulls.on_ship_lost(st, g, g.ships.find("nef_penitence"))
	_ok(int(g.hp[fi]) == 10 + Fleet.max_hp_of("fregate") / 10, "la Nef de pénitence tombe : la frégate retrouve un dixième de sa coque")


func _test_untouchable_and_broadside() -> void:
	_ok(PeopleHulls.untouchable("onde_nef", 0, 3) and not PeopleHulls.untouchable("onde_nef", 1, 3), "Déphasage : intouchable en phase longue seulement")
	_ok(PeopleHulls.untouchable("abysse_chantante", 2, 1) and not PeopleHulls.untouchable("abysse_chantante", 0, 2), "Voile abyssal : intouchable le premier jour seulement")
	_ok(Combat.weapon_eff("artillery", 2) <= 0, "l'artillerie ne tire pas au contact d'ordinaire")
	_ok(PeopleHulls.shot_phase("affut_roc", "artillery", 2) == 1 and PeopleHulls.shot_phase("croiseur", "artillery", 2) == 2, "Bordée : l'artillerie de l'Affût de roc tire au contact")
	var st := _state(7, "choeur")
	var f := _spawn(st, _empire_of(st, "choeur"), ["cathedrale", "martyr"], _empty_system(st))
	_ok(PeopleHulls.shot_pct(f, "martyr", "martyr", 3) == 150, "Chaire de proue : les Martyrs frappent une fois et demie plus fort")
	_ok(PeopleHulls.shot_pct(f, "abysse_chantante", "beam", 1) == 150 and PeopleHulls.shot_pct(f, "abysse_chantante", "beam", 2) == 100, "Voile abyssal : salve +50 % le premier jour")


func _test_predictive() -> void:
	var st := _state(7, "teyl")
	var me := _empire_of(st, "teyl")
	var foe := (me + 1) % st.empires.size()
	var sid := _empty_system(st)
	var mine := _spawn(st, me, ["noeud_calcul", "fregate"], sid)
	var theirs := _spawn(st, foe, ["corvette", "corvette"], sid)
	theirs.hp[0] = 5
	var fl: Array[Fleet] = [mine, theirs]
	var shots := [[Vector2i(mine.id, 1), Vector2i(theirs.id, 0), 20], [Vector2i(theirs.id, 0), Vector2i(mine.id, 1), 40], [Vector2i(theirs.id, 1), Vector2i(mine.id, 1), 7]]
	var pending := {Vector2i(theirs.id, 0): 20, Vector2i(mine.id, 1): 47}
	var out := PeopleHulls.predictive(fl, shots, pending)
	_ok(int(out.get(Vector2i(mine.id, 1), 0)) == 7, "Calcul prédictif : la corvette abattue d'abord ne riposte pas (%d)" % int(out.get(Vector2i(mine.id, 1), 0)))
	var plain := _spawn(st, me, ["fregate"], sid)
	var fl2: Array[Fleet] = [plain, theirs]
	_ok(PeopleHulls.predictive(fl2, shots, pending) == pending, "sans Nœud de calcul, les tirs restent simultanés")


func _test_boarding() -> void:
	var st := _state(11, "ferrocornes")
	var me := _empire_of(st, "ferrocornes")
	var foe := (me + 1) % st.empires.size()
	var sid := _empty_system(st)
	_war(st, me, foe)
	var mine := _spawn(st, me, ["belier_clan", "belier_clan"], sid)
	var theirs := _spawn(st, foe, ["corvette", "fregate"], sid)
	theirs.hp[0] = 5
	var fl: Array[Fleet] = [mine, theirs]
	var got := 0
	for _i in 12:
		got += PeopleHulls.boarding(st, fl, 2).size()
		if got > 0:
			break
	_ok(got == 1 and mine.ships.has("corvette") and not theirs.ships.has("corvette"), "Éperon d'abordage : la corvette brisée change de camp")
	_ok(PeopleHulls.boarding(st, fl, 1).is_empty(), "pas d'abordage avant la phase courte")
	_ok(theirs.ships.size() == 1, "on ne vide pas une flotte par abordage")


func _test_larvae_and_echoes() -> void:
	var st := _state(13, "khthari")
	var me := _empire_of(st, "khthari")
	var sid := _empty_system(st)
	var f := _spawn(st, me, ["sporange"], sid)
	var sides := [{"empire": me, "lost": {"sporange": 4}}]
	PeopleHulls.after_battle(st, sid, sides, me)
	_ok(f.count("sporange") == 3, "Larves : quatre sporanges perdus, deux repoussent")
	PeopleHulls.after_battle(st, sid, sides, -1)
	_ok(f.count("sporange") == 3, "pas de larves sans victoire")
	var st2 := _state(13, "murmurants")
	var mu := _empire_of(st2, "murmurants")
	var e := st2.get_empire(mu)
	e.echoes = 0
	var sid2 := _empty_system(st2)
	_spawn(st2, mu, ["diapason", "diapason"], sid2)
	PeopleHulls.after_battle(st2, sid2, [{"empire": mu, "lost": {}}], -1)
	_ok(e.echoes == 2 * PeopleHulls.ECHOES_PER_SONG, "Chant d'écho : chaque diapason survivant rapporte des Échos")


func _test_costs() -> void:
	var st := _state(17, "brisecomete")
	var me := _empire_of(st, "brisecomete")
	var e := st.get_empire(me)
	var pid := e.capital_planet
	var sid := st.galaxy.get_planet(pid).system_id
	var base := int(Fleets.ship_cost(st, me, "epave_remontee", pid).get("materials", 0))
	st.battle_wrecks[sid] = 7
	var cheap := int(Fleets.ship_cost(st, me, "epave_remontee", pid).get("materials", 0))
	_ok(cheap * 100 <= base * 41, "Bricolage : 60 %% de matériaux en moins sur un cimetière d'épaves (%d -> %d)" % [base, cheap])
	_ok(int(Fleets.ship_cost(st, me, "fregate", pid).get("materials", 0)) == int(Fleets.ship_cost(st, me, "fregate").get("materials", 0)), "une coque ordinaire ne profite pas des épaves")
	var c: Colony = st.colonies[pid]
	PeopleHulls.on_build(st, me, pid, "epave_remontee", c)
	_ok(int(st.battle_wrecks.get(sid, 0)) == 2, "les épaves remontées quittent le cimetière")
	# Noyau de sauvegarde (Teyl).
	var st2 := _state(17, "teyl")
	var te := _empire_of(st2, "teyl")
	var f := _spawn(st2, te, ["noosphere_mere", "corvette"], _empty_system(st2))
	var full := Fleets.ship_cost(st2, te, "noosphere_mere")
	PeopleHulls.on_ship_lost(st2, f, f.ships.find("noosphere_mere"))
	var half := Fleets.ship_cost(st2, te, "noosphere_mere")
	_ok(int(half.get("materials", 0)) * 2 <= int(full.get("materials", 0)) + 1, "Noyau de sauvegarde : la Noosphère-mère détruite se reconstruit à moitié prix")
	var c2: Colony = st2.colonies[st2.get_empire(te).capital_planet]
	c2.ship_days = 100
	PeopleHulls.on_build(st2, te, c2.planet_id, "noosphere_mere", c2)
	_ok(c2.ship_days == 50 and not PeopleHulls.has_backup(st2, te, "noosphere_mere"), "et en moitié moins de temps, une seule fois")


func _test_monthly() -> void:
	var st := _state(19, "khthari")
	var me := _empire_of(st, "khthari")
	var f := _spawn(st, me, ["mere_monde"], _empty_system(st))
	var added: Array[Dictionary] = []
	for _i in 8:
		PeopleHulls.monthly(st, added)
	_ok(f.count("sporange") == PeopleHulls.BROOD_MAX, "Ponte : un sporange par mois, six au plus (%d)" % f.count("sporange"))
	var st2 := _state(19, "brisecomete")
	var b := _empire_of(st2, "brisecomete")
	var e := st2.get_empire(b)
	_spawn(st2, b, ["comete_marche"], _empty_system(st2))
	var before := int(e.resources.get("energy", 0))
	PeopleHulls.monthly(st2, added)
	_ok(int(e.resources.get("energy", 0)) >= before + PeopleHulls.MARKET_BASE, "Marché flottant : de l'énergie chaque mois")
	# Ambassade : l'Arche chez un voisin en paix.
	var st3 := _state(23, "vael")
	var v := _empire_of(st3, "vael")
	var other := (v + 1) % st3.empires.size()
	var host_sys := st3.galaxy.get_planet(st3.get_empire(other).capital_planet).system_id
	var arche := _spawn(st3, v, ["arche_concorde"], host_sys)
	_ok(PeopleHulls.embassy_host(st3, arche) == other, "l'Arche stationnée chez un empire en paix y fait ambassade")
	var ev := st3.get_empire(v)
	var inf := int(ev.resources.get("influence", 0))
	PeopleHulls.monthly(st3, added)
	_ok(int(ev.resources.get("influence", 0)) == inf + PeopleHulls.EMBASSY_INFLUENCE, "Salle des Quarante : influence chaque mois")
	var parts := Diplomacy.opinion_parts(st3, other, v)
	var seen := false
	for p in parts:
		seen = seen or String(p["label"]).contains("Arche")
	_ok(seen, "et l'hôte en pense du bien")


func _test_logistics_trade() -> void:
	var st := _state(29, "ferrocornes")
	var me := _empire_of(st, "ferrocornes")
	var sid := _empty_system(st)
	var plain := _spawn(st, me, ["fregate"], sid)
	var cold := _spawn(st, me, ["nef_taniere"], sid)
	_ok(Logistics.autonomy(st, cold) >= Logistics.autonomy(st, plain) * 2 - 1, "Sang-froid : autonomie doublée")
	var st2 := _state(29, "brisecomete")
	var b := _empire_of(st2, "brisecomete")
	var sid2 := _empty_system(st2)
	_spawn(st2, b, ["cargo_corsaire"], sid2)
	_ok(PeopleHulls.privateer_at(st2, b, sid2) and not PeopleHulls.privateer_at(st2, b, sid2 + 1), "Soute franche : les corsaires rançonnent là où ils sont postés")


func _test_battle_runs() -> void:
	# Une vraie bataille avec les nouvelles règles : elle va à son terme sans erreur.
	var st := _state(31, "teyl")
	st.fleets.clear()
	var me := _empire_of(st, "teyl")
	var foe := _empire_of(st, "ferrocornes")
	var sid := _empty_system(st)
	_war(st, me, foe)
	_spawn(st, me, ["chassis_relie", "chassis_relie", "noeud_calcul", "onde_nef"], sid)
	_spawn(st, foe, ["belier_clan", "affut_roc", "corvette", "nef_penitence"], sid)
	var n := st.battle_reports.size()
	var sim := Simulation.new(st)
	for _i in Combat.battle_days() + 2:
		sim.step()
	_ok(st.battle_reports.size() > n, "une bataille entre coques de peuple se termine et laisse un rapport")


func _test_ai() -> void:
	var classes: Array[String] = ["corvette", "sporange", "fregate"]
	var seen := {}
	for t in 4:
		seen[AiPlayer._variant(classes, "corvette", t)] = true
	_ok(seen.has("corvette") and seen.has("sporange"), "l'IA alterne la corvette et la coque de peuple qui s'y ajoute")
	var megas: Array[String] = ["titan", "cathedrale"]
	_ok(AiPlayer._variant(megas, "titan", 0) != "", "l'IA connaît le titan de son peuple")


func _test_save() -> void:
	var st := _state(37, "teyl")
	st.people_hulls = {"backup": {"2": "noosphere_mere"}}
	var d := st.to_dict()
	_ok(int(d["version"]) >= 97, "sauvegarde 97 ou plus")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and String(back.people_hulls.get("backup", {}).get("2", "")) == "noosphere_mere", "la sauvegarde de la Noosphère-mère traverse la sauvegarde")


func _test_silhouettes() -> void:
	# Chaque coque de peuple a sa forme dédiée, et les formes ne se répètent pas trop.
	var forms := {}
	for hid in Designs.data().get("hulls", {}):
		if PeopleHulls.is_people_hull(String(hid)):
			_ok(HullArt.shape_of_hull(String(hid)) == String(hid), "forme dédiée : " + String(hid))
			forms[String(HullArt._shape(String(hid)).get("form", ""))] = true
	_ok(forms.size() >= 8, "au moins huit profils différents parmi les coques de peuple")
	var a := HullArt.icon("fuseau", "cathedrale", Color.WHITE)
	var b := HullArt.icon("roc", "cathedrale", Color.WHITE)
	_ok(a != null and b != null and a.get_image().get_data() != b.get_image().get_data(), "la signature du style change la silhouette")
	var t := HullArt.hull_texture("brique", "nef_penitence", ["canon_cinetique", "plaque_blindage", "plaque_blindage"], Color.WHITE)
	_ok(t != null and t.get_width() > 0, "silhouette du Chantier avec ses modules")
	# Un peuple créé dessine ses coques au style officiel choisi dans l'éditeur.
	var custom := "_test_style_coques"
	GameData.register_library_faction({"id": custom, "name": "Test", "ship_style": "khthari"})
	_ok(SpeciesLook.hull_style(custom) == SpeciesLook.hull_style("khthari"), "un peuple créé emprunte le style de coque choisi")
	GameData.unregister_library_faction(custom)
	# Rapport de bataille : vignettes par classe et prises d'abordage.
	var st := _state(41, "khthari")
	var me := _empire_of(st, "khthari")
	var panel := BattleReportPanel.new()
	panel._state = st
	var box := panel._vignettes(st.get_empire(me), {"engaged": {"corvette": 2, "mere_monde": 1}, "lost": {"corvette": 2}, "captured": {"fregate": 1}})
	_ok(box.get_child_count() == 3, "le rapport montre une vignette par classe engagée et par prise")
	_ok((box.get_child(0) as TextureRect).tooltip_text.begins_with(String(GameData.ship("mere_monde")["label"])), "la plus grosse coque vient en tête")
	box.free()
	panel.free()
	# Carte : l'option des silhouettes de flotte existe et est coupée par défaut.
	_ok(UiSettings.fleet_silhouettes == false, "silhouettes de flotte sur la carte : coupées par défaut")
