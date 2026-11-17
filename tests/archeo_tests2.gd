class_name ArcheoTests2
extends RefCounted
## Archéologie, lot 2 : pistes et vestiges, site de piste, Monde-berceau et Chute, premier venu, Secrets,
## technologies anciennes, Reconstitutions, gabarits, sites scellés, Avertissement contre une crise.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("  - trail")
	_test_trail()
	print("  - cradle")
	_test_cradle()
	print("  - reco")
	_test_reco()
	print("  - gabarit")
	_test_gabarit()
	print("  - sealed")
	_test_sealed()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _test_trail() -> void:
	var st := ArcheoTests.new_game()
	var d := Archaeology.in_game_disparus(st)[0]
	for sys in st.galaxy.systems:
		st.get_empire(0).explored[sys.id] = true
	var n := st.digs.size()
	var added: Array[Dictionary] = []
	ArchaeoWorld.add_vestiges(st, 0, d, 3, added)
	var only := 0
	for k in st.digs:
		if int(st.digs[k].get("only", -1)) == 0:
			only += 1
	_ok(st.digs.size() == n + 1 and only == 1, "3 vestiges : un site de piste que vous seul voyez")
	_ok(not ArchaeoWorld.cradle_known(st, 0, d), "pas encore de Monde-berceau")
	ArchaeoWorld.add_vestiges(st, 0, d, 3, added)
	_ok(ArchaeoWorld.cradle_known(st, 0, d), "6 vestiges : le Monde-berceau se révèle")
	var fall := String(Archaeology.disparu_def(d)["fall"])
	_ok(ArchaeoWorld.warned(st, 0, fall), "la Chute : Avertissement contre %s" % fall)
	_ok(ArchaeoWorld.crisis_seers(st, fall).has(0) and ArchaeoWorld.presage_days(st, [0], fall) > 0, "présage vu plus tôt")


func _test_cradle() -> void:
	var st := ArcheoTests.new_game()
	var d := Archaeology.in_game_disparus(st)[0]
	var added: Array[Dictionary] = []
	ArchaeoWorld.add_vestiges(st, 0, d, 6, added)
	ArchaeoWorld.add_vestiges(st, 1, d, 6, added)
	var c := ArchaeoWorld.cradle_of(st, d)
	var sid := int(c["s"])
	var kn := int(st.get_empire(0).resources.get("knowledge", 0))
	ArcheoTests.camp(st, sid, 0)
	ArchaeoWorld.daily(st, added)
	_ok(int(c["first"]) == 0, "le premier qui pose une flotte sur le Monde-berceau")
	_ok(int(st.get_empire(0).resources.get("knowledge", 0)) > kn, "il gagne gros (Savoir)")
	var rid := String(Archaeology.disparu_def(d)["relic"])
	_ok(int(st.relics[rid]["owner"]) == 0, "et la relique unique du Disparu")
	_ok(ArchaeoWorld.gabarits_of(st, 0).has(d), "et un Gabarit")
	# Les suivants : Secrets.
	ArcheoTests.rich(st, 1)
	_ok(ArcheoTests.cmd(st, 1, "secrets", {"d": d}) != "", "Secrets : il faut 300 fragments")
	Relics.add_fragments(st, 1, 400)
	_ok(ArcheoTests.cmd(st, 1, "secrets", {"d": d}) == "", "Secrets lancés")
	st.tick += Archaeology.r_int("secrets_days", 720)
	ArchaeoWorld.daily(st, added)
	_ok(ArchaeoWorld.secrets_done(st, 1, d) and ArchaeoWorld.has_ancient(st, 1, d, "civ"), "Secrets percés : bonus permanent et technologie ancienne")
	var fx: Dictionary = (Archaeology.disparu_def(d)["civ"] as Dictionary)["fx"]
	var k := String(fx.keys()[0])
	_ok(Research.effects(st, 1).has(k), "la technologie ancienne agit (%s)" % k)
	# Les mondes-reliques : colonisables après deux fouilles.
	var rw := Archaeology.sub(st, "rw")
	var pid := int(rw.keys()[0])
	_ok(ArchaeoWorld.colony_block(st, pid) != "", "monde-relique : pas de colonie avant deux fouilles")
	rw[str(pid)]["done"] = 2
	_ok(ArchaeoWorld.colony_block(st, pid) == "", "après deux fouilles, on s'y installe")


func _test_reco() -> void:
	var st := ArcheoTests.new_game()
	var d := Archaeology.in_game_disparus(st)[0]
	ArcheoTests.techs(st, 0, 2)
	for i in 3:
		Archaeology.add_antiq(st, 0, -1, "d:" + d)
	_ok(ArchaeoWorld.check_reco(st, 0, d) == "", "trois antiquités d'un même Disparu : Reconstitution possible")
	_ok(ArcheoTests.cmd(st, 0, "reco", {"d": d}) == "", "Reconstitution")
	_ok(ArchaeoWorld.antiqs_of_disparu(st, 0, d).is_empty(), "les pièces sont consommées")
	_ok(ArcheoTests.cmd(st, 0, "reco", {"d": d}) != "", "une seule Reconstitution par Disparu")
	_ok(int(st.get_empire(0).stats.get("archaeo_reco", 0)) == 1, "statistique pour le haut fait")
	var fe := ArcheoTests.new_game("complete", "ferrocornes")
	var fid := ArcheoTests.eid_of(fe, "ferrocornes")
	_ok(ArchaeoWorld.reco_need(fe, fid) == 2, "Forge-reliques des Ferrocornes : deux pièces suffisent")


func _test_gabarit() -> void:
	var st := ArcheoTests.new_game()
	var d := Archaeology.in_game_disparus(st)[0]
	var hid := String(Archaeology.disparu_def(d)["hull"])
	_ok(not Designs.hull(hid).is_empty(), "coque ancienne %s en données" % hid)
	_ok(not Designs.hull_ids_for(st.get_empire(0).faction_id).has(hid), "aucun peuple n'a les Gabarits d'office")
	Archaeology.emp(st, "gab", 0)[d] = 1
	_ok(Designs.hull_ids_of(st, 0).has(hid), "le Gabarit ouvre la coque dans l'éditeur")


func _test_sealed() -> void:
	var st := ArcheoTests.new_game()
	var sid := ArcheoTests.first_site(st)
	ArcheoTests.own_system(st, sid, 0)
	st.digs[sid]["seal"] = 1
	st.digs[sid]["me"] = "methodique"
	var woke := false
	var n := st.fleets.size()
	for i in 12:
		st.tick += 1
		ArchaeoWorld.on_finish(st, sid, 0, [] as Array[Dictionary])
		if st.fleets.size() > n:
			woke = true
			break
	_ok(woke, "un site scellé peut réveiller le Gardien des Strates")
	_ok(Archaeology.site_desc(st, 0, sid).contains("dort"), "le sceau est annoncé")
