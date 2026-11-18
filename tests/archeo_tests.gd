class_name ArcheoTests
extends RefCounted
## Tests de l'archéologie, « les Strates » (étude du 2026-11-17, 44 propositions) : réglage, sites
## enrichis, fouille hors de chez soi, méthode, chapitres à choix, antiquités, Extraire ou Classer, actions
## de fragments, gisements, sites nés de l'histoire, sauvegarde (lot 1). Les Disparus (lot 2) :
## ArcheoTests2 ; les ponts (lot 3) : ArcheoTests3. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Archéologie…")
	print("  - setup")
	_test_setup()
	print("  - dig rights")
	_test_rights()
	print("  - methods")
	_test_methods()
	print("  - finish")
	_test_finish()
	print("  - actions")
	_test_actions()
	print("  - history")
	_test_history()
	print("  - save")
	_test_save()
	ArcheoTests2.new().run(check)
	ArcheoTests3.new().run(check)


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func new_game(mode := "complete", faction := "vael", extra := {}) -> GameState:
	var opts := {"ai_level": "", "curios": "normales", "archaeology": mode}
	opts.merge(extra, true)
	return GameState.create(4243, 150, 1800.0, faction, opts)


static func eid_of(st: GameState, fid: String) -> int:
	for e in st.empires:
		if e.faction_id == fid:
			return e.id
	return -1


static func first_site(st: GameState) -> int:
	var keys := st.digs.keys()
	keys.sort()
	for k in keys:
		if int((st.digs[k] as Dictionary).get("rw", 0)) == 0 and int((st.digs[k] as Dictionary).get("only", -1)) < 0:
			return int(k)
	return int(keys[0])


static func own_system(st: GameState, sid: int, eid: int) -> void:
	var c := Colony.new()
	c.planet_id = st.galaxy.systems[sid].planet_ids[0]
	c.owner = eid
	c.kind = Colony.KIND_COLONY
	c.population = 4
	st.add_colony(c)
	st.get_empire(eid).explored[sid] = true


static func camp(st: GameState, sid: int, eid: int) -> Fleet:
	var e := st.get_empire(eid)
	e.explored[sid] = true
	return st.spawn_ship(eid, FactionTraits.ship_ids_for(e.faction_id)[0], sid)


static func rich(st: GameState, eid: int) -> void:
	for r in ["energy", "materials", "influence", "food", "knowledge"]:
		st.get_empire(eid).resources[r] = 5000


static func techs(st: GameState, eid: int, n: int) -> void:
	var ids := ["archeologie_stellaire", "dechiffrement_strates", "paleo_ingenierie"]
	for i in n:
		st.get_empire(eid).techs[ids[i]] = true


static func cmd(st: GameState, eid: int, act: String, d := {}) -> String:
	var c := SimCommands.ar_act(eid, act, d)
	var why := SimCommands.validate(st, c)
	if why == "":
		SimCommands.apply(st, c)
	return why


func _test_setup() -> void:
	_ok(not GameData.archaeology().is_empty() and Archaeology.mode_defs().size() == 3, "data/archaeology.json : trois réglages")
	_ok(Archaeology.type_ids().size() == 7 and Archaeology.disparus().size() == 5, "sept types de sites, cinq Disparus en catalogue")
	for t in ["archeologie_stellaire", "dechiffrement_strates", "paleo_ingenierie"]:
		_ok(not Research.tech(t).is_empty(), "technologie %s" % t)
	var cl := new_game("classique")
	_ok(cl.archaeo.is_empty() and not cl.digs.is_empty(), "Classique : les fouilles d'avant, rien de plus")
	var off := new_game("desactivee")
	_ok(off.archaeo.is_empty() and off.digs.is_empty(), "Désactivée : aucun site")
	var st := new_game()
	_ok(Archaeology.full(st) and Archaeology.in_game_disparus(st).size() == 3, "Complète : trois Disparus tirés")
	var all_ok := true
	for k in st.digs:
		var d: Dictionary = st.digs[k]
		if not (d.has("at") and d.has("sr") and d.has("or") and d.has("nm")):
			all_ok = false
	_ok(all_ok, "chaque site a un type, une strate, une origine et un nom")
	_ok(Archaeology.sub(st, "rw").size() >= 1, "au moins un monde-relique")
	_ok(Archaeology.sub(st, "cr").size() == 3, "un Monde-berceau par Disparu de la partie")
	var st2 := new_game()
	_ok(st2.archaeo.hash() == st.archaeo.hash(), "mise en place déterministe")


func _test_rights() -> void:
	var st := new_game()
	var sid := first_site(st)
	rich(st, 0)
	st.digs[sid]["sr"] = 1
	_ok(Archaeology.dig_reason(st, 0, sid) != "", "système libre sans flotte : pas de fouille")
	camp(st, sid, 0)
	_ok(Relics.check_start(st, 0, sid) == "", "système libre avec une flotte à l'arrêt : fouille permise (%s)" % Relics.check_start(st, 0, sid))
	var st2 := new_game()
	var sid2 := first_site(st2)
	var other := 1
	own_system(st2, sid2, other)
	rich(st2, 0)
	st2.get_empire(0).explored[sid2] = true
	_ok(Archaeology.dig_reason(st2, 0, sid2).contains("permis"), "chez un autre empire : il faut un permis")
	ArchaeoBridges.grant_permit(st2, other, 0, 0, [] as Array[Dictionary])
	_ok(Archaeology.dig_reason(st2, 0, sid2) == "", "avec le permis, on fouille chez lui")
	# Strate Première : détection 3.
	var st3 := new_game()
	var sid3 := first_site(st3)
	st3.digs[sid3]["sr"] = 0
	st3.get_empire(0).explored[sid3] = true
	_ok(not Relics.knows(st3, 0, sid3) or Curios.detect(st3, 0) >= 3, "strate Première : invisible sans détection 3")


func _test_methods() -> void:
	var st := new_game()
	var sid := first_site(st)
	own_system(st, sid, 0)
	rich(st, 0)
	var base := int(Relics.data()["digs"]["phase_days"])
	SimCommands.apply(st, SimCommands.dig_start(0, sid, "prudente"))
	_ok(String(st.digs[sid]["me"]) == "prudente", "méthode Prudente retenue")
	_ok(Archaeology.phase_days(st, 0, sid) == base * 3 / 2, "Prudente : phases 50 %% plus longues (%d)" % Archaeology.phase_days(st, 0, sid))
	st.digs[sid]["me"] = "pillage"
	_ok(Archaeology.phase_days(st, 0, sid) == Archaeology.r_int("pillage_days", 45), "Pillage : phases de 45 jours")
	var rw := -1
	for k in st.digs:
		if int(st.digs[k].get("rw", 0)) == 1:
			rw = int(k)
	_ok(rw >= 0 and Archaeology.method_reason(st, 0, rw, "pillage") != "", "on ne pille pas un monde-relique")
	# Incident grave en Prudente : rien de grave.
	st.digs[sid]["me"] = "prudente"
	st.digs[sid]["clues"] = 2
	var added: Array[Dictionary] = []
	for i in 20:
		st.tick += 1
		Archaeology.incident(st, sid, 0, added)
	_ok(int(st.digs[sid]["clues"]) >= 2, "Prudente : aucun incident ne coûte d'indice")
	# Kh'thari : phases plus courtes.
	var kh := new_game("complete", "khthari")
	var ks := first_site(kh)
	_ok(Archaeology.phase_days(kh, 0, ks) < base, "Fouisseurs Kh'thari : phases plus courtes")


func _test_finish() -> void:
	var st := new_game()
	var sid := first_site(st)
	own_system(st, sid, 0)
	rich(st, 0)
	techs(st, 0, 1)
	SimCommands.apply(st, SimCommands.dig_start(0, sid, ""))
	var d: Dictionary = st.digs[sid]
	var rid := String(d["relic"])
	d["ch"] = int(d["chapters"]) - 1
	d["clues"] = 20
	d["next"] = st.tick
	var added: Array[Dictionary] = []
	Relics._roll(st, sid, added)
	_ok(int(d.get("pend", 0)) == 1 and int(d["done"]) == 0, "dernier chapitre : la relique attend le choix")
	_ok(rid == "" or int(st.relics[rid]["owner"]) == -1, "la relique n'est pas encore emportée")
	var inbox: Array = Events.meta(st, 0)["inbox"]
	var card := {}
	for it: Dictionary in inbox:
		if String(it["card"]) == "archeo_fin":
			card = it
	_ok(not card.is_empty(), "carte « Extraire ou classer »")
	_ok(Archaeology.choice_ok(st, 0, card, "classify"), "Classer possible")
	Archaeology.event_act(st, 0, card, "classify", added)
	_ok(Archaeology.sub(st, "hl").has(str(sid)), "le site devient un Haut lieu")
	_ok(rid == "" or Archaeology.relic_locked(st, rid), "la relique reste en place")
	_ok(not Archaeology.stability_parts(st, sid, 0).is_empty(), "le Haut lieu donne de la stabilité au système")
	# Extraire, sur une autre partie.
	var st2 := new_game()
	var s2 := first_site(st2)
	own_system(st2, s2, 0)
	rich(st2, 0)
	techs(st2, 0, 1)
	SimCommands.apply(st2, SimCommands.dig_start(0, s2, "prudente"))
	var d2: Dictionary = st2.digs[s2]
	var r2 := String(d2["relic"])
	d2["ch"] = int(d2["chapters"]) - 1
	d2["clues"] = 20
	Relics._roll(st2, s2, added)
	var before := Archaeology.antiqs_of(st2, 0).size()
	Archaeology.event_act(st2, 0, {"system": s2}, "extract", added)
	_ok(r2 == "" or int(st2.relics[r2]["owner"]) == 0, "Extraire : la relique part pour l'empire")
	_ok(Archaeology.antiqs_of(st2, 0).size() == before + 2, "Prudente : deux antiquités à l'extraction")
	_ok(not Archaeology.antiq_fx(st2, Archaeology.antiqs_of(st2, 0)[0]).is_empty(), "une antiquité a un petit effet")
	# Étudier / Exploiter.
	var e := st2.get_empire(0)
	var en := int(e.resources.get("energy", 0))
	Archaeology.event_act(st2, 0, {"system": s2}, "study", added)
	_ok(int(d2.get("stu", 0)) >= 1, "Étudier compte pour la fin du site")
	_ok(Archaeology.event_line(st2, 0, {"system": s2}, "exploit") != "", "Exploiter a une ligne d'effet")
	_ok(int(e.resources.get("energy", 0)) == en, "Étudier ne donne pas de ressources")
	# Gisement : des fragments chaque mois au maître du système.
	Archaeology.sub(st2, "dep")[str(s2)] = 2
	var f0 := Relics.fragments(st2, 0)
	Archaeology._deposits(st2)
	_ok(Relics.fragments(st2, 0) == f0 + 2, "gisement : +2 fragments par mois")


func _test_actions() -> void:
	var st := new_game()
	rich(st, 0)
	Relics.add_fragments(st, 0, 10000)
	_ok(Relics.fragments(st, 0) == Archaeology.frag_cap(st), "fragments plafonnés à %d" % Archaeology.frag_cap(st))
	_ok(cmd(st, 0, "fa_sell") != "", "actions de fragments : il faut Déchiffrement des Strates")
	techs(st, 0, 2)
	_ok(Relics.can_trade(st, 0) or cmd(st, 0, "fa_sell") != "", "Vendre aux collectionneurs : seulement pour qui vend ses reliques")
	_ok(cmd(st, 0, "fa_reverse") == "", "Rétro-ingénierie (%s)" % Archaeology.check(st, 0, "fa_reverse", {}))
	_ok(Relics.fragments(st, 0) == Archaeology.frag_cap(st) - 150, "150 fragments dépensés")
	_ok(cmd(st, 0, "fa_reverse") != "", "délai avant de recommencer")
	var dmg := Research.fx_int(st, 0, "damage_pct")
	_ok(cmd(st, 0, "fa_military") == "" and Research.fx_int(st, 0, "damage_pct") == dmg + 10, "Applications militaires : +10 % de dégâts")
	# Trois natures de fragments (prop. 5).
	_ok(Archaeology.nature_ids().size() == 3 and Archaeology.nature_of_type("cite") == "savoir", "trois natures de fragments, liées aux types de sites")
	_ok(cmd(st, 0, "forge", {"k": "arme"}) != "", "Forger : il faut trois fragments identiques")
	Archaeology.emp(st, "nat", 0)["arme"] = 3
	var owned := Relics.owned(st, 0).size()
	_ok(cmd(st, 0, "forge", {"k": "arme"}) == "" and Archaeology.nat(st, 0, "arme") == 0, "trois fragments d'Arme forgés")
	_ok(Relics.owned(st, 0).size() == owned + 1 or (Archaeology.sub(st, "fx").get("0", {}) as Dictionary).has("nat:arme"), "une relique libre, ou le bienfait de la nature")
	var n := st.digs.size()
	_ok(cmd(st, 0, "fa_query") == "" or ArchaeoWorld.query_target(st, 0) < 0, "Interroger les Strates")
	_ok(st.digs.size() >= n, "un site caché de plus (ou aucun système libre)")


func _test_history() -> void:
	var st := new_game()
	var sid := -1
	for sys in st.galaxy.systems:
		if not st.digs.has(sys.id) and not sys.planet_ids.is_empty() and st.system_owner(sys.id) < 0:
			sid = sys.id
			break
	ArchaeoWorld.queue_history(st, sid, "b", "champ")
	_ok((st.archaeo["hist"] as Array).size() == 1, "un cimetière d'épaves met un site en file")
	st.tick += Archaeology.r_int("hist_delay_days", 7200) + (30 - posmod(st.tick + Archaeology.r_int("hist_delay_days", 7200), 30))
	var added: Array[Dictionary] = []
	ArchaeoWorld.daily(st, added)
	_ok(st.digs.has(sid) and int(st.digs[sid].get("hist", 0)) == 1 and int(st.digs[sid]["sr"]) == 2, "vingt ans plus tard : un site daté de la partie, strate Récente")


func _test_save() -> void:
	var st := new_game()
	techs(st, 0, 1)
	var sid := first_site(st)
	Archaeology.add_antiq(st, 0, sid)
	var d := st.to_dict()
	_ok(int(d["version"]) >= 89, "sauvegarde 89 ou plus")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and JSON.stringify(back.to_dict()) == JSON.stringify(d), "aller-retour identique")
	_ok(String(back.digs[sid].get("nm", "")) == String(st.digs[sid].get("nm", "")), "les sites gardent leur nom")
	_ok(Archaeology.antiqs_of(back, 0).size() == 1, "les antiquités survivent")
	var cl := new_game("classique")
	var dc := cl.to_dict()
	_ok(not dc.has("archaeo"), "Classique : rien de plus dans la sauvegarde")
