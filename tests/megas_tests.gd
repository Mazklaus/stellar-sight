class_name MegasTests
extends RefCounted
## Tests des mégastructures (étude du 2026-11-17, 46 propositions) : données et réglage, sites, Vaisseau-
## architecte et Chantier, étapes et capacité, effets et revenus, Essaim et Sphère, Monde-anneau, Kardashev,
## siège, réparation et prise, sauvegarde et anciennes sauvegardes (lot 1). Le catalogue, les ruines, la
## catapulte et les superarmes (lot 2) : MegasTests2 ; les ponts (lot 3) : MegasTests3.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Mégastructures…")
	print("  - data")
	_test_data()
	print("  - setup")
	_test_setup()
	print("  - architect")
	_test_architect()
	print("  - stages")
	_test_stages()
	print("  - dyson")
	_test_dyson()
	print("  - ring")
	_test_ring()
	print("  - war")
	_test_war()
	print("  - save")
	_test_save()
	MegasTests2.run(check)
	MegasTests3.run(check)


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func new_game(mode := "completes", ruins := "aucune", faction := "ossarane", extra := {}) -> GameState:
	var opts := {"ai_level": "", "megastructures": mode, "mega_ruins": ruins}
	opts.merge(extra, true)
	return GameState.create(4242, 150, 1800.0, faction, opts)


static func eid_of(st: GameState, fid: String) -> int:
	for e in st.empires:
		if e.faction_id == fid:
			return e.id
	return -1


static func cmd(st: GameState, eid: int, act: String, d := {}) -> String:
	var c := SimCommands.mega_act(eid, act, d)
	var why := SimCommands.validate(st, c)
	if why == "":
		SimCommands.apply(st, c)
	return why


static func rich(st: GameState, eid: int) -> void:
	var e := st.get_empire(eid)
	for r in ["energy", "materials", "food", "influence", "crystals", "knowledge"]:
		e.resources[r] = 99999


static func home_sys(st: GameState, eid: int) -> int:
	return st.galaxy.get_planet(st.get_empire(eid).capital_planet).system_id


static func architect(st: GameState, eid: int, sid: int) -> Fleet:
	return st.spawn_ship(eid, Megastructures.ship_id(), sid)


## Fait tourner les chantiers jusqu'à la fin de l'étape en cours (au plus max jours).
static func run_days(st: GameState, n: int) -> void:
	for i in n:
		st.tick += 1
		Megastructures.daily(st)


static func finish_running(st: GameState, id: int) -> void:
	var m := Megastructures.get_m(st, id)
	if m.is_empty() or not Megastructures.running(m):
		return
	m["w"] = 1
	Megastructures.daily(st)


## Pose et achève une mégastructure d'un coup (tests) : renvoie son identifiant.
static func build_full(st: GameState, eid: int, k: String, sid: int, pid := -1) -> int:
	var id := int(st.megas["next"])
	st.megas["next"] = id + 1
	Megastructures.entries(st)[str(id)] = {"id": id, "k": k, "o": eid, "s": sid, "p": pid, "st": Megastructures.stage_count(k), "w": 0}
	Megastructures.touch(st)
	return id


## Une planète libre du système (sans colonie), au type forcé si demandé ; -1 s'il n'y en a pas.
static func free_planet(st: GameState, sid: int, force_type := "") -> int:
	for pid in st.galaxy.systems[sid].planet_ids:
		if not st.colonies.has(pid):
			if force_type != "":
				st.override_planet(pid, {"type": force_type})
			return pid
	return -1


func _test_data() -> void:
	var d := GameData.megastructures()
	_ok(d.get("kinds", {}).size() == 19, "19 mégastructures au catalogue (18 bâties, la Forteresse dormante trouvée)")
	var bad := PackedStringArray()
	for k in Megastructures.kind_ids():
		for t in Megastructures.kind_def(k).get("tech", []):
			if Research.tech(String(t)).is_empty():
				bad.append("%s:%s" % [k, t])
		if Megastructures.stage_count(k) < 3:
			bad.append("%s:étapes" % k)
	_ok(bad.is_empty(), "technologies et étapes du catalogue valides (%s)" % ", ".join(bad))
	_ok(not Megastructures.is_kind("megamasse") and not Megastructures.is_kind("moteur_stellaire"), "Mégamasse et Moteur stellaire restent à discuter : absents")
	var w := GameData.wonders_list()
	_ok(not w.has("collecteur_stellaire") and not w.has("nexus_savoir") and not w.has("monde_anneau") and w.has("porte_stellaire"), "Dyson, Nexus et Monde-anneau quittent les merveilles ; la Porte stellaire reste")
	_ok(GameData.ship("architecte").get("architect", false), "Vaisseau-architecte au catalogue")
	_ok(Megastructures.mode_defs().size() == 4 and Megastructures.ruin_defs().size() == 3, "quatre réglages, trois quantités de ruines")
	var talents := 0
	for f in ["ossarane", "choeur", "vael", "khthari", "teyl", "ferrocornes", "brisecomete", "murmurants"]:
		if Megastructures.cfg("talents").has(f):
			talents += 1
	_ok(talents == 8, "un talent de mégastructures par peuple (8)")


func _test_setup() -> void:
	var off := GameState.create(4242, 150, 1800.0, "ossarane", {"ai_level": ""})
	_ok(off.megas.is_empty() and not Megastructures.enabled(off), "sans l'option : désactivées")
	var st0 := new_game("desactivees")
	_ok(st0.megas.is_empty(), "Désactivées : rien")
	Research.grant(st0, 0, ["architectes_stellaires"])
	rich(st0, 0)
	_ok(Fleets.check_build_ship(st0, 0, st0.get_empire(0).capital_planet, "architecte").contains("pas en jeu"), "Désactivées : pas de Vaisseau-architecte")
	var cl := new_game("classiques")
	_ok(Megastructures.kind_allowed(cl, "sphere_dyson") and Megastructures.kind_allowed(cl, "monde_anneau") and not Megastructures.kind_allowed(cl, "essaim_dyson"), "Classiques : les trois anciennes seulement")
	var sa := new_game("sans_armes")
	_ok(not Megastructures.kind_allowed(sa, "brise_monde") and Megastructures.kind_allowed(sa, "matriochka"), "Sans superarmes : ni Brise-monde ni Anneau d'extinction")
	var full := new_game("completes", "beaucoup")
	var ruins := MegasWorld.ruins(full)
	_ok(ruins.size() >= 2, "Ruines « Beaucoup » : des ruines posées (%d)" % ruins.size())
	var far_ok := true
	for m in ruins:
		if full.system_owner(int(m["s"])) >= 0 or int(m["o"]) != -1:
			far_ok = false
	_ok(far_ok, "ruines sans maître, dans des systèmes libres")
	var none := new_game("completes", "aucune")
	_ok(MegasWorld.ruins(none).is_empty(), "Ruines « Aucune » : aucune")


func _test_architect() -> void:
	var st := new_game()
	var sid := home_sys(st, 0)
	var home := st.get_empire(0).capital_planet
	_ok(Megastructures.site_reason(st, 0, "ascenseur_orbital", sid, home).contains("technologie"), "il faut la technologie")
	Research.grant(st, 0, ["architectes_stellaires"])
	rich(st, 0)
	_ok(Megastructures.site_reason(st, 0, "ascenseur_orbital", sid, home) == "", "Ascenseur orbital possible sur la capitale")
	_ok(cmd(st, 0, "plan", {"k": "ascenseur_orbital", "s": sid, "p": home}).contains("architecte"), "sans Vaisseau-architecte : refusé")
	_ok(Megastructures.unlocked(st, 0, "ascenseur_orbital") and Research.unlocks(st.get_empire(0).faction(), "architectes_stellaires").has("Ascenseur orbital (mégastructure)"), "la technologie annonce la mégastructure")
	var f := architect(st, 0, sid)
	var why := cmd(st, 0, "plan", {"k": "ascenseur_orbital", "s": sid, "p": home})
	_ok(why == "", "ordre « plan » accepté (%s)" % why)
	var mine := Megastructures.owned_by(st, 0)
	_ok(mine.size() == 1 and int(mine[0]["st"]) == 0 and Megastructures.running(mine[0]), "architecte sur place : le Chantier est posé tout de suite")
	_ok(Megastructures.architect_busy(st, f), "l'architecte est retenu par le Chantier")
	var id := int(mine[0]["id"])
	# L'architecte s'en va : le Chantier ne tient pas, il attend.
	var w := int(mine[0]["w"])
	f.system_id = st.galaxy.systems[sid].neighbors[0]
	run_days(st, 5)
	_ok(int(Megastructures.get_m(st, id)["w"]) == w, "architecte parti : le Chantier attend")
	f.system_id = sid
	run_days(st, 5)
	_ok(int(Megastructures.get_m(st, id)["w"]) == w - 5, "architecte revenu : le Chantier reprend")
	finish_running(st, id)
	_ok(int(Megastructures.get_m(st, id)["st"]) == 1 and not Megastructures.architect_busy(st, f), "le Chantier tient : l'architecte est libre")
	# Abandon d'un Chantier : la moitié revient.
	var st2 := new_game()
	Research.grant(st2, 0, ["architectes_stellaires"])
	rich(st2, 0)
	architect(st2, 0, home_sys(st2, 0))
	cmd(st2, 0, "plan", {"k": "ascenseur_orbital", "s": home_sys(st2, 0), "p": st2.get_empire(0).capital_planet})
	var id2 := int(Megastructures.owned_by(st2, 0)[0]["id"])
	var before := int(st2.get_empire(0).resources["materials"])
	_ok(cmd(st2, 0, "cancel", {"id": id2}) == "" and Megastructures.get_m(st2, id2).is_empty(), "Chantier abandonné")
	_ok(int(st2.get_empire(0).resources["materials"]) > before, "la moitié du coût revient")
	# Envoi depuis un autre système : l'architecte part et pose en arrivant.
	var st3 := new_game()
	Research.grant(st3, 0, ["architectes_stellaires"])
	rich(st3, 0)
	var s3 := home_sys(st3, 0)
	var nb := int(st3.galaxy.systems[s3].neighbors[0])
	var f3 := architect(st3, 0, nb)
	_ok(cmd(st3, 0, "plan", {"k": "ascenseur_orbital", "s": s3, "p": st3.get_empire(0).capital_planet}) == "" and f3.is_moving(), "architecte lointain : il se met en route")
	f3.system_id = s3
	f3.path.clear()
	f3.progress = 0
	run_days(st3, 1)
	_ok(Megastructures.owned_by(st3, 0).size() == 1, "arrivé : il pose le Chantier")


func _test_stages() -> void:
	var st := new_game()
	var sid := home_sys(st, 0)
	var home := st.get_empire(0).capital_planet
	Research.grant(st, 0, ["architectes_stellaires", "anneau_orbital"])
	rich(st, 0)
	architect(st, 0, sid)
	architect(st, 0, sid)
	cmd(st, 0, "plan", {"k": "ascenseur_orbital", "s": sid, "p": home})
	cmd(st, 0, "plan", {"k": "anneau_orbital", "s": sid, "p": home})
	_ok(Megastructures.owned_by(st, 0).size() == 1 and Megastructures.sub(st, "plans").size() == 1, "une étape à la fois au départ : le second architecte attend (prop. 5)")
	_ok(Megastructures.check_pose(st, 0, Megastructures.architects_of(st, 0)[1].id, "anneau_orbital", home).contains("trop d'étapes"), "« trop d'étapes en chantier »")
	Megastructures.sub(st, "plans").clear()
	var id := int(Megastructures.owned_by(st, 0)[0]["id"])
	finish_running(st, id)
	var e := st.get_empire(0)
	var mat := int(e.resources["materials"])
	_ok(cmd(st, 0, "advance", {"id": id}) == "", "étape suivante lancée")
	_ok(int(e.resources["materials"]) < mat, "payée au lancement (prop. 4)")
	_ok(cmd(st, 0, "advance", {"id": id}).contains("déjà en cours"), "une seule étape en cours par mégastructure")
	finish_running(st, id)
	cmd(st, 0, "advance", {"id": id})
	finish_running(st, id)
	var m := Megastructures.get_m(st, id)
	_ok(Megastructures.complete(m), "Ascenseur orbital achevé")
	_ok(Research.fx_int(st, 0, "ship_cost_pct") < 0, "effet de l'Ascenseur : vaisseaux moins chers (%d %%)" % Research.fx_int(st, 0, "ship_cost_pct"))
	Research.grant(st, 0, ["mega_ingenierie_avancee"])
	_ok(Megastructures.slots(st, 0) == 2, "Méga-ingénierie avancée : deux étapes à la fois")
	# Anneau orbital et son module.
	var aid := -1
	_ok(cmd(st, 0, "plan", {"k": "anneau_orbital", "s": sid, "p": home}) == "", "Anneau orbital posé")
	for x in Megastructures.owned_by(st, 0):
		if String(x["k"]) == "anneau_orbital":
			aid = int(x["id"])
	for i in Megastructures.stage_count("anneau_orbital"):
		finish_running(st, aid)
		cmd(st, 0, "advance", {"id": aid})
	_ok(Megastructures.complete(Megastructures.get_m(st, aid)), "Anneau orbital achevé")
	var cap := Economy.max_pop(st, st.galaxy.get_planet(home), 0, st.colonies[home].buildings)
	_ok(cmd(st, 0, "module", {"id": aid, "m": "habitation"}) == "", "module Habitation")
	_ok(Economy.max_pop(st, st.galaxy.get_planet(home), 0, st.colonies[home].buildings) == cap + 3, "+3 population maximale")
	_ok(Megastructures.capacity_bonus(st, sid, 0) == 8, "places de défense de l'anneau (8)")
	# Talent des Ferrocornes : une étape de plus.
	var fc := new_game("completes", "aucune", "ferrocornes")
	_ok(Megastructures.slots(fc, eid_of(fc, "ferrocornes")) == 2, "Ferrocornes : une étape de plus à la fois")


func _test_dyson() -> void:
	var st := new_game()
	var sid := home_sys(st, 0)
	Research.grant(st, 0, ["architectes_stellaires", "essaim_dyson"])
	rich(st, 0)
	architect(st, 0, sid)
	var why := cmd(st, 0, "plan", {"k": "essaim_dyson", "s": sid, "p": -1})
	_ok(why == "" or st.galaxy.systems[sid].star_type == "black_hole", "Essaim de Dyson posé autour de l'étoile (%s)" % why)
	if why != "":
		return
	var id := int(Megastructures.owned_by(st, 0)[0]["id"])
	for i in Megastructures.stage_count("essaim_dyson"):
		finish_running(st, id)
		cmd(st, 0, "advance", {"id": id})
	var m := Megastructures.get_m(st, id)
	_ok(Megastructures.complete(m), "Essaim achevé")
	var y := Megastructures.yields_of(st, m)
	var star := int(Megastructures.cfg("stars").get(st.galaxy.systems[sid].star_type, 100))
	@warning_ignore("integer_division")
	var want := 28 * star / 100
	_ok(int(y.get("energy", 0)) == want, "rendement selon l'étoile : %d énergie (%d %%)" % [int(y.get("energy", 0)), star])
	var inc := Economy.empire_income(st, 0)
	_ok(int(Megastructures.income(st, 0)["gross"].get("energy", 0)) == want, "revenu de l'empire compris")
	# Usure faute d'entretien.
	st.get_empire(0).resources["materials"] = 0
	MegasWorld.monthly(st, [])
	_ok(int(Megastructures.get_m(st, id).get("wear", 0)) == 10, "voiles usées sans entretien (10 %)")
	rich(st, 0)
	MegasWorld.monthly(st, [])
	_ok(int(Megastructures.get_m(st, id).get("wear", 0)) == 0, "entretenues, elles se réparent")
	# Sphère sur l'Essaim : moins chère, l'Essaim est absorbé.
	Research.grant(st, 0, ["collecteur_stellaire", "mega_ingenierie"])
	var full_cost := Research.scaled_amounts(Megastructures.stage_def("sphere_dyson", 0).get("cost", {}), 0)
	var cost := Megastructures.stage_cost(st, 0, "sphere_dyson", 0, sid)
	_ok(int(cost.get("materials", 0)) < int(full_cost.get("materials", 0)), "Sphère sur un Essaim achevé : moins chère")
	why = cmd(st, 0, "plan", {"k": "sphere_dyson", "s": sid, "p": -1})
	_ok(why == "", "Sphère posée sur l'Essaim (%s)" % why)
	_ok(Megastructures.get_m(st, id).is_empty(), "l'Essaim est absorbé")
	var sp := -1
	for x in Megastructures.owned_by(st, 0):
		if String(x["k"]) == "sphere_dyson":
			sp = int(x["id"])
	for i in Megastructures.stage_count("sphere_dyson"):
		finish_running(st, sp)
		cmd(st, 0, "advance", {"id": sp})
	_ok(Megastructures.complete(Megastructures.get_m(st, sp)), "Sphère achevée")
	var frozen := true
	for pid in st.galaxy.systems[sid].planet_ids:
		var t := st.galaxy.get_planet(pid).type
		if not ["gas_giant", "asteroids", "anneau", "barren", "arctic"].has(t):
			frozen = false
	_ok(frozen, "Sphère achevée : les mondes du système gèlent")
	# Kardashev : la Sphère lève le verrou du type II et compte dans la puissance captée.
	Kardashev.setup(st, "complete")
	Megastructures._kardashev(st, 0, [])
	_ok(Kardashev.lock_ok(st, 0, 2) and Kardashev.mega_power(st, 0) >= 1000, "Kardashev : la Sphère lève le verrou II et capte %d (%s)" % [Kardashev.mega_power(st, 0), Megastructures.kardashev_text(st, 0)])
	_ok(inc.has("gross"), "revenus calculés")
	# Matriochka sur la Sphère : mange son énergie.
	Research.grant(st, 0, ["matriochka"])
	why = cmd(st, 0, "plan", {"k": "matriochka", "s": sid, "p": -1})
	_ok(why == "", "Cerveau Matriochka posé sur la Sphère (%s)" % why)
	var mid := -1
	for x in Megastructures.owned_by(st, 0):
		if String(x["k"]) == "matriochka":
			mid = int(x["id"])
	finish_running(st, mid)
	cmd(st, 0, "advance", {"id": mid})
	finish_running(st, mid)
	_ok(not Megastructures.yields_of(st, Megastructures.get_m(st, sp)).has("energy"), "la Sphère ne donne plus d'énergie : le Cerveau la mange")
	_ok(int(Megastructures.yields_of(st, Megastructures.get_m(st, mid)).get("knowledge", 0)) > 0, "le Cerveau donne du Savoir")


func _test_ring() -> void:
	var st := new_game("classiques")
	var e := st.get_empire(0)
	var sid := home_sys(st, 0)
	Research.grant(st, 0, ["architectes_stellaires", "spatioports", "mega_ingenierie"])
	rich(st, 0)
	_ok(Megastructures.site_reason(st, 0, "monde_anneau", sid, -1).contains("peuplé"), "Monde-anneau : pas dans un système peuplé")
	# Un système libre voisin, tenu par un avant-poste.
	var target := -1
	for nb in st.galaxy.systems[sid].neighbors:
		if st.system_owner(nb) < 0 and not st.galaxy.systems[nb].planet_ids.is_empty() and st.galaxy.systems[nb].star_type != "black_hole":
			target = nb
			break
	if target < 0:
		_ok(true, "pas de système voisin libre (test sauté)")
		return
	var c := Colony.new()
	c.planet_id = st.galaxy.systems[target].planet_ids[0]
	c.owner = 0
	c.kind = Colony.KIND_OUTPOST
	st.add_colony(c)
	architect(st, 0, target)
	var why := cmd(st, 0, "plan", {"k": "monde_anneau", "s": target, "p": -1})
	_ok(why == "", "Monde-anneau posé autour d'une étoile sans peuple (%s)" % why)
	if why != "":
		return
	var id := int(Megastructures.owned_by(st, 0)[0]["id"])
	for i in Megastructures.stage_count("monde_anneau"):
		finish_running(st, id)
		cmd(st, 0, "advance", {"id": id})
	var rings := 0
	for pid in st.galaxy.systems[target].planet_ids:
		if st.galaxy.get_planet(pid).type == "anneau":
			rings += 1
	_ok(Megastructures.complete(Megastructures.get_m(st, id)) and rings >= 1, "Monde-anneau fermé : des segments d'anneau (%d)" % rings)
	_ok(Megastructures.first_of(st, "monde_anneau") == e.id, "premier Monde-anneau noté")


func _test_war() -> void:
	var st := new_game()
	var sid := home_sys(st, 0)
	var id := build_full(st, 0, "reseau_veille", sid)
	Research.grant(st, 0, ["reseau_veille"])
	var seen := Fleets.visible_systems(st, 0)
	_ok(seen.size() == st.galaxy.systems.size(), "Réseau de veille achevé : toute la galaxie en vue")
	# Siège : une flotte ennemie armée tient le système trois mois.
	var foe := 1
	st.get_empire(0).wars.append(foe)
	st.get_empire(foe).wars.append(0)
	for fid in st.sorted_fleet_ids():
		var f: Fleet = st.fleets[fid]
		if f.owner == 0 and f.system_id == sid:
			f.system_id = st.galaxy.systems[sid].neighbors[0]
	var war := st.spawn_ship(foe, "fregate", sid) if not GameData.ship("fregate").is_empty() else null
	if war == null:
		for sh in GameData.ship_ids():
			if Combat.is_armed_ship(sh):
				war = st.spawn_ship(foe, sh, sid)
				break
	for i in 3:
		MegasWorld.monthly(st, [])
	var m := Megastructures.get_m(st, id)
	_ok(bool(m.get("dmg", 0)) and not Megastructures.complete(m), "trois mois de siège : l'étape la plus haute est ruinée (prop. 32)")
	_ok(Fleets.visible_systems(st, 0).size() < st.galaxy.systems.size(), "étape ruinée : son effet s'éteint")
	st.fleets.erase(war.id)
	rich(st, 0)
	_ok(cmd(st, 0, "repair", {"id": id}) == "", "réparation lancée")
	finish_running(st, id)
	_ok(Megastructures.complete(Megastructures.get_m(st, id)), "réparée")
	# Prise : le système change de maître, l'ouvrage aussi.
	for pid in st.galaxy.systems[sid].planet_ids:
		var c: Colony = st.colonies.get(pid)
		if c != null:
			c.owner = foe
	st.rebuild_ownership()
	Megastructures.monthly(st, [])
	_ok(int(Megastructures.get_m(st, id)["o"]) == foe, "système pris : la mégastructure change de maître (prop. 31)")


func _test_save() -> void:
	var st := new_game("completes", "peu")
	var sid := home_sys(st, 0)
	build_full(st, 0, "essaim_dyson", sid)
	Megastructures._kardashev(st, 0, [])
	var d := st.to_dict()
	_ok(int(d["version"]) == GameState.FORMAT_VERSION and GameState.FORMAT_VERSION >= 88 and d.has("megas"), "Sauvegarde 88")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and JSON.stringify(back.to_dict()) == JSON.stringify(d), "Sauvegarde : aller-retour identique")
	# Ancienne sauvegarde : une Sphère de Dyson bâtie comme merveille devient une mégastructure.
	var old := GameState.create(4242, 150, 1800.0, "ossarane", {"ai_level": ""})
	var od := old.to_dict()
	od["version"] = 86
	od.erase("megas")
	var home := old.get_empire(0).capital_planet
	for cd: Dictionary in od["colonies"]:
		if int(cd["planet"]) == home:
			cd["buildings"].append("collecteur_stellaire")
	var ob := GameState.from_dict(JSON.parse_string(JSON.stringify(od)))
	_ok(ob != null, "ancienne sauvegarde relue (%s)" % GameState.last_error)
	if ob == null:
		return
	_ok(Megastructures.mode(ob) == "classiques" and Megastructures.complete_count(ob, 0, "sphere_dyson") == 1, "ancienne Sphère convertie en mégastructure (Classiques)")
	_ok(not ob.colonies[home].buildings.has("collecteur_stellaire"), "le bâtiment de merveille disparaît")
