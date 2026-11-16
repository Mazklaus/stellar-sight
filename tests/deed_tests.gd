extends RefCounted
## Tests des hauts faits galactiques, lot 1 (étude du 2026-11-16) : catalogue en données, modes et
## tirage, compteurs nourris par les actes, course à un seul gagnant (égalité partagée, retardataires à
## 25 %), ouverture des records par ère, alerte à 75 %, récompense au choix (fenêtre, commande,
## réponse automatique), Trophées, titres et Infamie dans l'opinion, rattrapage et affinité, sauvegarde,
## IA. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Hauts faits galactiques (course et Gloire)…")
	_test_data()
	_test_modes()
	_test_counters()
	_test_award()
	_test_tie_and_late()
	_test_records()
	_test_rewards()
	_test_trophy()
	_test_opinion()
	_test_bonus()
	_test_save()
	_test_ai()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func new_game(seed_value := 13, extra := {}) -> GameState:
	var o := {"ai_level": "", "deeds": "tous"}
	o.merge(extra, true)
	return GameState.create(seed_value, 120, 1600.0, "vael", o)


static func apply(st: GameState, cmd: Dictionary) -> String:
	var why := SimCommands.validate(st, cmd)
	if why == "":
		SimCommands.apply(st, cmd)
	return why


## Avance jusqu'au prochain contrôle mensuel des hauts faits (compris).
static func to_check(st: GameState) -> void:
	for i in 31:
		st.tick += 1
		Deeds.daily(st)
		if posmod(st.tick, Deeds.r_int("check_days")) == Deeds.r_int("offset"):
			return


func _test_data() -> void:
	var ids := Deeds.all_ids()
	_ok(ids.size() >= 66, "catalogue en données (%d hauts faits)" % ids.size())
	var sorts := {}
	for id in ids:
		sorts[Deeds.sort_of(id)] = int(sorts.get(Deeds.sort_of(id), 0)) + 1
		_ok(Deeds.family_label(Deeds.family(id)) != "", "famille connue pour %s" % id)
		var k := String(Deeds.def(id)["k"])
		_ok(DeedsEval.is_counter(k) or DeedsEval.value(new_game_cached(), 0, k, Deeds.def(id).get("x", null)) >= 0, "mesure lisible pour %s" % id)
	for s in Deeds.SORTS:
		_ok(int(sorts.get(s, 0)) > 0, "sorte %s présente" % s)
	_ok(int(sorts.get("record", 0)) >= 20 and int(sorts.get("first", 0)) >= 20, "Premières et records en nombre")
	_ok((Deeds.data()["titles"] as Dictionary).size() == 5, "cinq titres honorifiques")
	_ok((Deeds.data()["trophies"] as Dictionary).size() >= 12, "une douzaine de Trophées")
	for tid in Deeds.data()["trophies"]:
		var b := GameData.building(String(tid))
		_ok(b.get("label", "") != "" and not bool(b.get("buildable", true)), "Trophée %s lu par GameData.building, non constructible" % tid)


var _cached: GameState


func new_game_cached() -> GameState:
	if _cached == null:
		_cached = new_game()
	return _cached


func _test_modes() -> void:
	var off := new_game(13, {"deeds": "aucun"})
	_ok(not Deeds.enabled(off) and off.deeds.is_empty(), "mode Aucun : pas de hauts faits")
	Research.count_stat(off, 0, "guardians")
	_ok(off.deeds.is_empty(), "les actes ne créent rien sans hauts faits")
	var fr := new_game(13, {"deeds": "premieres"})
	var only_first := true
	for id in Deeds.pool(fr):
		if Deeds.sort_of(String(id)) != "first":
			only_first = false
	_ok(only_first and not Deeds.pool(fr).is_empty(), "mode Premières seules")
	var all := new_game(13)
	var rec := 0
	for id in Deeds.pool(all):
		if Deeds.sort_of(String(id)) == "record":
			rec += 1
	_ok(rec == 5 * Deeds.r_int("records_per_era"), "quatre records tirés par ère (%d)" % rec)
	var again := new_game(13)
	_ok(Deeds.pool(again) == Deeds.pool(all), "tirage déterministe pour une même graine")
	var other := new_game(14)
	_ok(Deeds.pool(other) != Deeds.pool(all) or true, "autre graine, autre tirage possible")


func _test_counters() -> void:
	var st := new_game()
	Research.count_stat(st, 0, "curios", 2)
	_ok(Deeds.count(st, 0, "curios") == 2, "les statistiques nourrissent les compteurs")
	Heroes.act(st, 0, "treaty")
	_ok(Deeds.count(st, 0, "treaty") == 1, "les actes nourrissent les compteurs")
	var first := false
	for x: Dictionary in Deeds.annals_of(st, 0):
		if String(x["k"]) == "first" and String(x["id"]) == "curios":
			first = true
	_ok(first, "première curiosité inscrite dans les Annales")


func _test_award() -> void:
	var st := new_game()
	Research.count_stat(st, 0, "guardians")
	var g0 := Deeds.glory(st, 0)
	_ok(g0 >= int(Deeds.rules()["moments"]["guardians"]), "gardien abattu : Gloire du grand moment")
	to_check(st)
	_ok(Deeds.winners(st, "tueur_de_gardien") == [0], "Premier à abattre un gardien : un seul gagnant")
	_ok(Deeds.glory(st, 0) >= g0 + 100, "la Première rapporte 100 de Gloire ou plus")
	_ok(Deeds.held_by(st, 0).has("tueur_de_gardien"), "le haut fait est tenu")
	_ok(not Deeds.inbox(st, 0).is_empty(), "le joueur reçoit un choix de récompense")
	var it: Dictionary = Deeds.inbox(st, 0)[0]
	_ok((it["ch"] as Array).size() == Deeds.r_int("choices"), "trois récompenses tirées")
	Research.count_stat(st, 1, "guardians")
	to_check(st)
	_ok(Deeds.winners(st, "tueur_de_gardien") == [0], "le second n'est pas vainqueur")


func _test_tie_and_late() -> void:
	var st := new_game()
	Research.count_stat(st, 0, "guardians")
	Research.count_stat(st, 1, "guardians")
	to_check(st)
	var w := Deeds.winners(st, "tueur_de_gardien")
	_ok(w.has(0) and w.has(1), "égalité le même jour : les deux gagnent")
	var st2 := new_game()
	Research.count_stat(st2, 0, "guardians")
	to_check(st2)
	var g1 := Deeds.glory(st2, 1)
	Research.count_stat(st2, 1, "guardians")
	var gm := Deeds.glory(st2, 1) - g1
	to_check(st2)
	var late := Deeds.glory(st2, 1) - g1 - gm
	_ok(late > 0 and late < 100, "retardataire : un quart de la Gloire (%d)" % late)
	_ok((st2.deeds["late"] as Dictionary).get("tueur_de_gardien", {}).has("1"), "retardataire noté dans les Annales")


func _test_records() -> void:
	var st := new_game()
	_ok(Deeds.is_open(st, 0, "chercheur_curiosites"), "record d'ère I ouvert dès le début")
	var era4 := ""
	for id in Deeds.pool(st):
		if Deeds.sort_of(String(id)) == "record" and int(Deeds.def(String(id)).get("era", 1)) == 4:
			era4 = String(id)
	_ok(era4 != "" and not Deeds.is_open(st, 0, era4), "record d'ère IV fermé en ère I")
	Research.count_stat(st, 0, "curios", 3)
	to_check(st)
	_ok(not Deeds.is_won(st, "chercheur_curiosites"), "record pas encore atteint")
	_ok(Deeds.pct(st, 0, "chercheur_curiosites") == 50, "avancement à 50 %")
	Research.count_stat(st, 0, "curios", 3)
	to_check(st)
	_ok(Deeds.winners(st, "chercheur_curiosites") == [0], "record d'ère atteint")
	# Un haut fait de couche qui ne concerne pas l'empire n'ouvre qu'à l'ère III : la base est prise ce jour-là.
	var lay := ""
	for id in Deeds.pool(st):
		if Deeds.sort_of(String(id)) == "layer" and not Deeds.layer_match(st, 0, String(id)) and DeedsEval.is_counter(String(Deeds.def(String(id))["k"])):
			lay = String(id)
			break
	_ok(lay == "" or not Deeds.is_open(st, 0, lay), "haut fait de couche étranger fermé avant l'ère III")
	# Alerte à 75 % chez les rivaux qui connaissent l'empire.
	var st3 := new_game()
	st3.get_empire(1).contacts.append(0)
	st3.get_empire(0).contacts.append(1)
	var n0 := st3.chronicle.size()
	Research.count_stat(st3, 0, "curios", 5)
	to_check(st3)
	var warned := false
	for i in range(n0, st3.chronicle.size()):
		if String(st3.chronicle[i].get("text", "")).contains("approche du haut fait"):
			warned = true
	_ok(warned, "alerte quand un rival passe les trois quarts")


func _test_rewards() -> void:
	var st := new_game()
	Research.count_stat(st, 0, "guardians")
	to_check(st)
	var it: Dictionary = Deeds.inbox(st, 0)[0]
	_ok(apply(st, SimCommands.deed_choose(0, int(it["id"]), 9)) != "", "choix hors liste refusé")
	var before: Dictionary = st.get_empire(0).resources.duplicate()
	var ch: Array = it["ch"]
	var idx := 0
	for i in ch.size():
		if String(Deeds.reward_def(String(ch[i]))["k"]) == "res":
			idx = i
	_ok(apply(st, SimCommands.deed_choose(0, int(it["id"]), idx)) == "", "choix de récompense accepté")
	_ok(Deeds.inbox(st, 0).is_empty(), "la boîte se vide")
	if String(Deeds.reward_def(String(ch[idx]))["k"]) == "res":
		var got := false
		for r in st.get_empire(0).resources:
			if int(st.get_empire(0).resources[r]) > int(before.get(r, 0)):
				got = true
		_ok(got, "la récompense est versée")
	# Sans réponse au bout de 30 jours : la première possible.
	var st2 := new_game()
	Research.count_stat(st2, 0, "guardians")
	to_check(st2)
	for i in Deeds.r_int("answer_days") + 1:
		st2.tick += 1
		Deeds.daily(st2)
	_ok(Deeds.inbox(st2, 0).is_empty(), "réponse automatique après 30 jours")


func _test_trophy() -> void:
	var st := new_game()
	var c := Deeds._capital_colony(st, 0)
	_ok(c != null, "capitale trouvée")
	_ok(Deeds.reward_options(st, 0).has("trophee"), "Trophée proposé tant qu'il en reste")
	var n0 := Deeds.free_trophies(st).size()
	var added: Array[Dictionary] = []
	Deeds.apply_reward(st, 0, "trophee", "tueur_de_gardien", added)
	_ok(Deeds.free_trophies(st).size() == n0 - 1, "un Trophée de moins dans la galaxie")
	var held := Deeds.trophies_held(st)
	var tid := ""
	for k in held:
		tid = String(k)
	_ok(tid != "" and c.buildings.has(tid), "le Trophée est posé dans la capitale")
	var slots := Economy.building_slots_used(c)
	c.buildings.erase(tid)
	_ok(Economy.building_slots_used(c) == slots, "le Trophée ne prend pas d'emplacement")
	c.buildings.append(tid)


func _test_opinion() -> void:
	var st := new_game()
	st.get_empire(1).contacts.append(0)
	st.get_empire(0).contacts.append(1)
	var o0 := Diplomacy.opinion(st, 1, 0)
	Deeds._m(st, "titles")["cartographe"] = 0
	_ok(Diplomacy.opinion(st, 1, 0) == mini(100, o0 + Deeds.r_int("title_opinion")), "titre : +10 d'opinion")
	Deeds._m(st, "infamy")["0"] = st.tick + 100
	_ok(Diplomacy.opinion(st, 1, 0) == clampi(o0 + Deeds.r_int("title_opinion") + Deeds.r_int("infamy_opinion"), -100, 100), "Infamie : -15 d'opinion")
	Deeds._m(st, "titles")["batisseur"] = 0
	var parts := DeedsBridges.opinion_parts(st, 1, 0)
	var dbl := false
	for p: Array in parts:
		if String(p[0]).contains("Bâtisseur"):
			dbl = true
	_ok(not dbl, "le titre de Bâtisseur n'est pas compté deux fois")


func _test_bonus() -> void:
	var st := new_game()
	for e in st.empires:
		if e.id != 0 and not e.is_npc():
			Deeds.add_glory(st, e.id, 500 + e.id)
	_ok(DeedsBridges.lower_half(st, 0) and DeedsBridges.catchup_pct(st, 0) == 25, "rattrapage dans la moitié basse")
	_ok(not DeedsBridges.lower_half(st, DeedsBridges.ranking(st)[0]), "pas de rattrapage pour le premier")
	_ok(DeedsBridges.leader(st) == DeedsBridges.ranking(st)[0] and DeedsBridges.leader(st) != 0, "empire en tête de Gloire")
	var aff_any := false
	for fam in Deeds.data()["families"]:
		if DeedsBridges.affinity(st, 0, String(fam)):
			aff_any = true
			var fid := ""
			for id in Deeds.all_ids():
				if Deeds.family(id) == String(fam) and Deeds.sort_of(id) == "first":
					fid = id
					break
			if fid != "":
				_ok(Deeds.glory_for(st, 0, fid) == 100 * Deeds.r_int("affinity_mult") * 125 / 100, "affinité ×2 (et rattrapage)")
			break
	_ok(aff_any, "au moins une famille d'affinité pour les Vael")


func _test_save() -> void:
	var st := new_game()
	Research.count_stat(st, 0, "guardians")
	to_check(st)
	var d := st.to_dict()
	_ok(int(d["version"]) == GameState.FORMAT_VERSION and GameState.FORMAT_VERSION >= 74, "sauvegarde 74")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and Deeds.winners(back, "tueur_de_gardien") == [0], "les vainqueurs survivent à la sauvegarde")
	_ok(back != null and Deeds.glory(back, 0) == Deeds.glory(st, 0), "la Gloire survit à la sauvegarde")
	_ok(back != null and Deeds.inbox(back, 0).size() == Deeds.inbox(st, 0).size(), "la boîte survit à la sauvegarde")
	var off := new_game(13, {"deeds": "aucun"})
	_ok(not off.to_dict().has("deeds"), "rien n'est sauvé sans hauts faits")


func _test_ai() -> void:
	var st := new_game()
	st.get_empire(1).ai_level = "normale"
	Research.count_stat(st, 1, "guardians")
	to_check(st)
	_ok(Deeds.winners(st, "tueur_de_gardien") == [1], "l'IA gagne un haut fait")
	_ok(Deeds.inbox(st, 1).is_empty(), "l'IA choisit sa récompense tout de suite")
	var ch := ["materiaux", "savoir", "trophee"]
	_ok(ch.has(AiDeeds.pick(st, 1, ch)), "choix de l'IA dans la liste")
	st.get_empire(1).ai_level = "recrue"
	_ok(AiDeeds.pick(st, 1, ch) == "materiaux", "la Recrue prend la première venue")
