class_name KardashevTests
extends RefCounted
## Tests de l'échelle de Kardashev (version resserrée du 2026-11-18) : données, indice logarithmique et
## rythme, puissance captée, verrous, migration depuis les mégastructures, prérogatives et sommeil,
## Émulation, Âge sombre et héroïque, signature thermique, Sobriété et Voile, opinion, commandes,
## hauts faits, sauvegarde. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Échelle de Kardashev…")
	_test_data()
	_test_index()
	_test_locks()
	_test_migrate()
	_test_perks()
	_test_emulation()
	_test_dark()
	_test_heat()
	_test_opinion()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func new_game(mode := "complete", megas := "completes", pace := "normal") -> GameState:
	return GameState.create(4242, 150, 1800.0, "ossarane", {"ai_level": "", "megastructures": megas, "mega_ruins": "aucune", "kardashev": mode, "kardashev_pace": pace})


static func majors(st: GameState) -> Array[int]:
	var out: Array[int] = []
	for e in st.empires:
		if not e.is_npc():
			out.append(e.id)
	return out


static func set_k(st: GameState, eid: int, k: int) -> void:
	Kardashev.sub(st, "k")[str(eid)] = k
	Kardashev.touch(st)


func _test_data() -> void:
	_ok(Kardashev.mode_defs().size() == 3 and Kardashev.default_mode() == "complete", "trois réglages, Complète par défaut")
	_ok(Kardashev.perk_ids().size() == 15, "15 prérogatives (%d)" % Kardashev.perk_ids().size())
	var each := true
	for lv in range(1, 6):
		each = each and Kardashev.perks_of_level(lv).size() == 3
	_ok(each, "trois prérogatives par demi-palier")
	var st := new_game("desactivee")
	_ok(st.kardashev.is_empty() and not Kardashev.enabled(st), "désactivée : rien en jeu")
	st = new_game()
	var m := majors(st)
	_ok(Kardashev.full(st) and Kardashev.index100(st, m[0]) == 70, "départ à 0,70")
	_ok(Kardashev.value_text(70) == "0,70" and Kardashev.value_text(205) == "2,05", "affichage au centième")


func _test_index() -> void:
	var st := new_game()
	_ok(Kardashev.index_of_power(st, 15) == 70, "15 de puissance : 0,70")
	_ok(Kardashev.index_of_power(st, 300) == 100, "300 : 1,00")
	_ok(Kardashev.index_of_power(st, 8000) == 200, "8 000 : 2,00")
	_ok(Kardashev.index_of_power(st, 120000) == 300, "120 000 : 3,00")
	var mid := Kardashev.index_of_power(st, 1550)
	_ok(mid > 140 and mid < 160, "entre deux ancres, l'échelle est logarithmique (1 550 : %s)" % Kardashev.value_text(mid))
	var mono := true
	var last := -1
	for p in [1, 5, 15, 40, 100, 300, 1000, 3000, 8000, 30000, 120000, 500000]:
		var k := Kardashev.index_of_power(st, p)
		mono = mono and k >= last
		last = k
	_ok(mono, "l'indice ne baisse jamais quand la puissance monte")
	var slow := new_game("complete", "completes", "lent")
	_ok(Kardashev.index_of_power(slow, 300) < 100 and Kardashev.index_of_power(slow, 450) == 100, "rythme Lent : moitié plus de puissance par palier")
	var p := Kardashev.power_parts(st, majors(st)[0])
	_ok(int(p["total"]) == int(p["colonies"]) + int(p["megas"]) + int(p["worlds"]), "puissance captée = colonies + mégastructures + mondes")


func _test_locks() -> void:
	var st := new_game()
	var me := majors(st)[0]
	_ok(not Kardashev.lock_ok(st, me, 1), "au départ, le verrou du type I n'est pas levé")
	var sid := MegasTests.home_sys(st, me)
	MegasTests.build_full(st, me, "sphere_dyson", sid)
	_ok(Kardashev.mega_power(st, me) >= 1000, "une Sphère achevée capte la puissance de l'étoile (%d)" % Kardashev.mega_power(st, me))
	Megastructures._kardashev(st, me, [])
	_ok(Kardashev.index100(st, me) == 99, "sans le verrou, l'indice plafonne à 0,99 (%s)" % Kardashev.value_text(Kardashev.index100(st, me)))
	Research.grant(st, me, ["fusion_compacte"])
	var cap: Colony = st.colonies[st.get_empire(me).capital_planet]
	for bid in ["ferme_hydroponique", "centrale_fusion", "complexe_minier", "forum"]:
		if cap.buildings.size() < 4 and not cap.buildings.has(bid):
			cap.buildings.append(bid)
	_ok(Kardashev.lock_ok(st, me, 1) and Kardashev.lock_ok(st, me, 2), "technologie et bâtiments : verrou I ; la Sphère : verrou II")
	var added: Array[Dictionary] = []
	Megastructures._kardashev(st, me, added)
	_ok(Kardashev.tier(st, me) >= 1, "verrou levé : le type I est franchi (%s)" % Kardashev.text(st, me))
	_ok(Kardashev.sub(st, "first").get("1", []).has(me), "le premier à franchir est noté")
	_ok(MegasBridges.deed_value(st, me, "mega_kard") == Kardashev.tier(st, me), "haut fait : le type vient de l'échelle")
	var st2 := new_game("complete", "desactivees")
	_ok(Kardashev.lock_missing(st2, majors(st2)[0], 2).size() == 1, "sans mégastructures, le type II reste fermé")


func _test_migrate() -> void:
	var st := MegasTests.new_game("completes", "aucune")
	var me := majors(st)[0]
	_ok(st.kardashev.is_empty(), "partie de mégastructures sans échelle")
	st.megas["kard"] = {str(me): 15}
	var d := st.to_dict()
	d["version"] = 90
	d.erase("kardashev")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and Kardashev.full(back), "ancienne sauvegarde : l'échelle passe en Complète")
	if back != null:
		_ok(Kardashev.index100(back, me) == 150 and Kardashev._gi(back, "best", me) == 1, "l'ancien indice 1,5 devient 1,50, type I")
		_ok(not back.megas.has("kard"), "l'indice quitte les mégastructures")


func _test_perks() -> void:
	var st := new_game()
	var me := majors(st)[0]
	set_k(st, me, 160)
	var added: Array[Dictionary] = []
	KardashevWorld.on_update(st, me, 0, 1, 0, added)
	_ok(Kardashev.pending(st, me) == [1, 2], "1,60 : deux prérogatives à choisir (1,0 et 1,5)")
	var off := Kardashev.offer(st, me)
	_ok(off.size() == 3 and off.has("climat_maitrise"), "trois au choix au premier niveau")
	_ok(Kardashev.check(st, me, "perk", {"id": "forge_soleils"}) != "", "pas une prérogative d'un niveau à venir")
	var c := SimCommands.kd_act(me, "perk", {"id": "climat_maitrise"})
	_ok(SimCommands.validate(st, c) == "", "la commande passe")
	SimCommands.apply(st, c)
	_ok(Kardashev.has_perk(st, me, "climat_maitrise") and Kardashev.pending(st, me) == [2], "prérogative prise, la suivante attend")
	_ok(Research.fx_int(st, me, "building_slots_all") >= 1, "Climat maîtrisé : un emplacement de plus partout")
	Kardashev.apply(st, me, "perk", {"id": "ateliers_moleculaires"})
	set_k(st, me, 140)
	_ok(Kardashev.awake(st, me, "climat_maitrise") and not Kardashev.awake(st, me, "ateliers_moleculaires"), "retombé à 1,40 : la prérogative de 1,5 dort")
	set_k(st, me, 105)
	Kardashev.sub(st, "perks")[str(me)] = ["climat_maitrise", "ateliers_moleculaires", "archives_pierre"]
	Kardashev.touch(st)
	_ok(KardashevWorld.no_theft(st, me), "Archives de pierre éveillée : pas de vol de technologies")
	var st2 := new_game("indice")
	_ok(Kardashev.check(st2, majors(st2)[0], "perk", {"id": "climat_maitrise"}) != "", "Indice seul : pas de prérogatives")


func _test_emulation() -> void:
	var st := new_game()
	var m := majors(st)
	var before := Research.cost(st, m[0], "fusion_compacte")
	Kardashev.sub(st, "first")["1"] = [m[1]]
	_ok(KardashevWorld.emulation_pct(st, m[0], 1) == 25, "un rival au type I : Émulation de 25 %")
	_ok(Research.cost(st, m[0], "fusion_compacte") < before, "la technologie du verrou coûte moins cher (%d < %d)" % [Research.cost(st, m[0], "fusion_compacte"), before])
	Kardashev.sub(st, "first")["1"] = [m[1], m[2], m[3], m[4]] if m.size() > 4 else [m[1], m[2], m[3]]
	_ok(KardashevWorld.emulation_pct(st, m[0], 1) <= 55, "Émulation plafonnée à 55 %")
	_ok(KardashevWorld.mega_cost_pct(st, m[0], "sphere_dyson") == 0, "pas de rabais sur la Sphère tant que nul n'a franchi le type II")
	Kardashev.sub(st, "first")["2"] = [m[1]]
	_ok(KardashevWorld.mega_cost_pct(st, m[0], "sphere_dyson") == -25, "type II franchi par un rival : la Sphère coûte 25 % de moins")


func _test_dark() -> void:
	var st := new_game()
	var me := majors(st)[0]
	Kardashev.sub(st, "best")[str(me)] = 2
	Kardashev.sub(st, "half")[str(me)] = 3
	set_k(st, me, 150)
	var added: Array[Dictionary] = []
	KardashevWorld.on_update(st, me, 2, 1, 3, added)
	_ok(KardashevWorld.dark_age(st, me), "retombé du type II au type I : Âge sombre")
	_ok(KardashevWorld.repair_pct(st, me) == -50, "Âge sombre : réparations moitié moins chères")
	_ok(int(Kardashev.effects(st, me).get("stability", 0)) <= -2, "Âge sombre : stabilité en baisse")
	set_k(st, me, 200)
	KardashevWorld.on_update(st, me, 1, 2, 3, added)
	_ok(not KardashevWorld.dark_age(st, me) and Kardashev.pending(st, me).has(0), "revenu au type II : Âge héroïque, une prérogative de plus")
	_ok(Kardashev.offer(st, me).size() >= 9, "Âge héroïque : au choix parmi les paliers atteints")


func _test_heat() -> void:
	var st := new_game()
	var m := majors(st)
	var me := m[0]
	set_k(st, me, 120)
	_ok(KardashevWorld.revealed_systems(st, me).is_empty(), "sous 1,50, la chaleur ne trahit rien")
	set_k(st, me, 260)
	var rev := KardashevWorld.revealed_systems(st, me)
	_ok(rev.has(FactionTraits.capital_system(st, me)), "à 2,60, la capitale est connue de tous")
	KardashevWorld.monthly(st, [])
	_ok(int(st.get_empire(m[1]).intel.get(FactionTraits.capital_system(st, me), {}).get("day", -1)) == st.tick, "les autres empires en prennent un relevé")
	Kardashev.apply(st, me, "sober", {"on": true})
	_ok(KardashevWorld.signature(st, me) == 210 and int(Kardashev.power_parts(st, me)["sober_pct"]) == 85, "Sobriété : signature −0,50, puissance 85 %")
	_ok(KardashevWorld.crisis_score(st, me) < KardashevWorld.crisis_score(st, m[1]), "les crises visent d'abord la plus forte signature")
	_ok(Kardashev.check(st, me, "veil", {}) != "", "pas de Voile sans la prérogative")
	Kardashev.sub(st, "perks")[str(me)] = ["voile_stellaire"]
	Kardashev.touch(st)
	_ok(Kardashev.check(st, me, "veil", {}) == "", "Voile stellaire éveillé : on peut le tirer")
	Kardashev.apply(st, me, "veil", {})
	_ok(KardashevWorld.signature(st, me) == 0 and KardashevWorld.revealed_systems(st, me).is_empty(), "sous le Voile, plus de signature")
	_ok(Kardashev.check(st, me, "veil", {}) != "", "un seul Voile à la fois")


func _test_opinion() -> void:
	var st := new_game()
	var m := majors(st)
	set_k(st, m[1], 210)
	set_k(st, m[0], 80)
	var parts := Kardashev.opinion_parts(st, m[0], m[1])
	_ok(not parts.is_empty(), "un empire de deux types au-dessus : révérence ou crainte")
	var total := 0
	for p in parts:
		total += int(p[1])
	_ok(total == 8 or total == -16, "crainte doublée pour deux types d'écart, ou révérence (%d)" % total)
	_ok(Kardashev.opinion_parts(st, m[1], m[0]).is_empty(), "le plus puissant ne craint pas le plus faible")


func _test_save() -> void:
	var st := new_game()
	var me := majors(st)[0]
	set_k(st, me, 155)
	Kardashev.sub(st, "perks")[str(me)] = ["climat_maitrise"]
	Kardashev.sub(st, "first")["1"] = [me]
	var d := st.to_dict()
	_ok(int(d["version"]) == GameState.FORMAT_VERSION and GameState.FORMAT_VERSION >= 92 and d.has("kardashev"), "Sauvegarde 92")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and JSON.stringify(back.to_dict()) == JSON.stringify(d), "Sauvegarde : aller-retour identique")
	var off := new_game("desactivee")
	_ok(not off.to_dict().has("kardashev"), "désactivée : rien dans la sauvegarde")
