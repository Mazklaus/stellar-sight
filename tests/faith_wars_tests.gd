extends RefCounted
## Tests de la religion, lot 2 (propositions 11 à 17 et 25, plus le Culte du Je) : zèle, natures,
## hérésies, schismes, concile et réécriture (Code saint), lois de culte et doléance, missions,
## guerre sainte et croisade, cultes cachés, prophétie plantée, drones dissidents des ruches,
## ordres, IA, sauvegarde 44.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Religion, lot 2 (zèle, hérésies, missions, guerre sainte, cultes cachés, prophéties, natures, Culte du Je)…")
	_test_zeal()
	_test_natures()
	_test_heresy()
	_test_code_saint()
	_test_laws()
	_test_missions()
	_test_holy_war()
	_test_secret()
	_test_prophecy()
	_test_je()
	_test_v2()
	_test_commands()
	_test_ai()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _state(on := true, ai := "", politics := false) -> GameState:
	var st := GameState.create(4242, 150, 1800.0, "vael", {"ai_level": ai, "faiths": "actives" if on else "aucunes",
			"politics": "active" if politics else "aucune"})
	for e in st.empires:
		e.resources["energy"] = 5000
		e.resources["influence"] = 5000
		e.resources["materials"] = 5000
		e.resources["food"] = 5000
		e.resources["knowledge"] = 5000
	# Fondateurs sans IA (tests) : le choix par défaut, comme si le délai était échu. Les tests du lot 2
	# gardent le Chœur en Code saint et le Murmure en Mème (depuis le lot 4, leurs natures préférées
	# sont le Dieu en chantier et la Chronolâtrie).
	var lot2 := {"choeur": "code_saint", "murmurants": "meme"}
	for fid in Faiths.ids(st):
		var f := Faiths.faith(st, fid)
		if int(f["pending"]) > 0:
			var ch := Faiths.default_choice(st, int(f["founder"]), fid)
			var nat := String(lot2.get(st.get_empire(int(f["founder"])).faction_id, ch["nature"]))
			Faiths.choose(st, fid, nat, ch["doctrines"], String(ch["precept"]))
	return st


func _id_of(st: GameState, faction: String) -> int:
	for e in st.empires:
		if e.faction_id == faction:
			return e.id
	return -1


func _cap(st: GameState, eid: int) -> Colony:
	return st.colonies.get(st.get_empire(eid).capital_planet)


func _sid(st: GameState, c: Colony) -> int:
	return st.galaxy.get_planet(c.planet_id).system_id


func _plant(st: GameState, owner: int, pop: int, from: int, jumps: int) -> Colony:
	var dist := FactionTraits.jumps_from(st.galaxy, from)
	var ids := dist.keys()
	ids.sort()
	for s in ids:
		if int(dist[s]) != jumps or st.system_owner(int(s)) >= 0:
			continue
		for pid in st.galaxy.systems[int(s)].planet_ids:
			if not st.colonies.has(pid):
				var c := Colony.new()
				c.planet_id = pid
				c.owner = owner
				c.kind = Colony.KIND_COLONY
				c.population = pop
				st.add_colony(c)
				st.rebuild_ownership()
				return c
	return null


func _part(parts: Array, prefix: String) -> int:
	for p in parts:
		var label := String(p["label"]) if p is Dictionary else String(p[0])
		if label.begins_with(prefix):
			return int(p["value"]) if p is Dictionary else int(p[1])
	return 0


func _added() -> Array[Dictionary]:
	return [] as Array[Dictionary]


func _test_zeal() -> void:
	var st := _state()
	var ch := _id_of(st, "choeur")
	var fc := Faiths.founded_by(st, ch)
	_ok(FaithWars.zeal(st, fc) == 50, "zèle de départ : 50")
	FaithWars.add_zeal(st, fc, 80)
	_ok(FaithWars.zeal(st, fc) == 100, "zèle plafonné à 100")
	var hi := int(Faiths.pressures(st).get(_cap(st, ch).planet_id, {}).get(fc, 0))
	FaithWars.add_zeal(st, fc, -100)
	var lo := int(Faiths.pressures(st).get(_cap(st, ch).planet_id, {}).get(fc, 0))
	_ok(hi > 0 and absi(lo * 3 - hi) <= 3, "zèle 0 : la foi prêche trois fois moins qu'à 100 (%d contre %d)" % [lo, hi])
	# Monde saint tenu par un empire de la foi : le zèle monte ; perdu : il baisse.
	Faiths.faith(st, fc)["zeal"] = 50
	FaithWars._zeal_month(st, fc)
	_ok(FaithWars.zeal(st, fc) == 52, "monde saint tenu : zèle +2 par mois")
	var v := _id_of(st, "vael")
	_cap(st, ch).owner = v
	Faiths.faith(st, fc)["zeal"] = 50
	FaithWars._zeal_month(st, fc)
	_cap(st, ch).owner = ch
	_ok(FaithWars.zeal(st, fc) <= 47, "monde saint aux mains d'un laïque : zèle -3 (et plus)")
	Faiths.faith(st, fc)["zeal"] = 90
	FaithWars._zeal_month(st, fc)
	_ok(FaithWars.zeal(st, fc) == 91, "au-dessus de 75 : le zèle retombe lentement (+2 -1)")


func _test_natures() -> void:
	var st := _state()
	var ch := _id_of(st, "choeur")
	var mu := _id_of(st, "murmurants")
	var fc := Faiths.founded_by(st, ch)
	var fm := Faiths.founded_by(st, mu)
	_ok(String(Faiths.faith(st, fc)["offer"][0]) == "dieu_en_chantier" and String(Faiths.faith(st, fm)["offer"][0]) == "chronolatrie", "natures préférées : Dieu en chantier (Chœur), Chronolâtrie (Murmurants)")
	_ok(FaithWars.data()["natures"]["list"].size() == 19, "dix-neuf natures de foi (10 SF + 9 classiques)")
	var v := _id_of(st, "vael")
	var fv := Faiths.reveal(st, v, "relique", -1, _added())
	_ok(FaithWars.nature(st, fv) == "" and (Faiths.faith(st, fv)["offer"] as Array).has("precurseurs"), "Révélation par relique : les Précurseurs parmi les trois natures proposées")
	Faiths.choose(st, fv, "precurseurs", Faiths.DEFAULT_DOCTRINES, "charite")
	_ok(FaithWars.nature(st, fv) == "precurseurs", "nature choisie par le fondateur")
	# Voies sacrées : vitesse des flottes.
	Faiths.faith(st, fv)["nature"] = "voies_sacrees"
	Faiths.faith(st, fv)["doctrines"]["chef"] = "elu"
	st.faiths["state"][str(v)] = fv
	Relics.touch(st)
	var vs := _sid(st, _cap(st, v))
	var nb := int(st.galaxy.systems[vs].neighbors[0])
	_ok(FaithWars.check_bless(st, v, vs, nb) == "", "Voies sacrées : le chef de foi bénit une route")
	FaithWars.bless(st, v, vs, nb)
	var t0 := _id_of(st, "teyl")
	_ok(FaithWars.lane_pct(st, v, vs, nb) == 150 and FaithWars.lane_pct(st, t0, nb, vs) == 100, "route bénie : fidèles +50 %, infidèles normaux")
	var key := FaithWars.lane_key(vs, nb)
	FaithWars.set_lane_mode(st, key, "closed")
	_ok(FaithWars.lane_pct(st, t0, vs, nb) == 50, "route fermée : infidèles à moitié vitesse")
	FaithWars.set_lane_mode(st, key, "toll")
	var e0 := int(st.get_empire(t0).resources["energy"])
	FaithWars.on_lane_crossed(st, t0, vs, nb)
	_ok(int(st.get_empire(t0).resources["energy"]) == e0 - 5, "route à péage : 5 d'énergie au chef de foi")
	st.faiths["blessed"].clear()
	# Parasite saint : ne prêche que dans son système, croissance -10 %, conquête à moitié convertie.
	Faiths.faith(st, fv)["nature"] = "parasite"
	Relics.touch(st)
	var far := _plant(st, v, 6, _sid(st, _cap(st, v)), 2)
	st.faiths["state"][str(v)] = Faiths.LAICITE
	var pm: Dictionary = Faiths.pressures(st)
	_ok(far != null and int(pm.get(far.planet_id, {}).get(fv, 0)) == 0, "Parasite saint : pas de prêche à distance")
	st.faiths["state"][str(v)] = fv
	far.faith = {fv: 6}
	_ok(FaithWars.growth_pct(st, far) == -10, "Parasite saint : -10 % de croissance là où il domine")
	var t := _id_of(st, "teyl")
	var tc := _cap(st, t)
	tc.faith = {}
	tc.population = 10
	FaithWars.on_conquest(st, tc, v)
	_ok(int(tc.faith.get(fv, 0)) == 5, "Parasite saint : un monde conquis se convertit à moitié")
	# Flotte du parasite : pression dans son système.
	var fl: Fleet = Fleets.empire_fleets(st, v)[0]
	fl.path.clear()
	fl.system_id = _sid(st, tc)
	pm = Faiths.pressures(st)
	_ok(int(pm.get(tc.planet_id, {}).get(fv, 0)) > 0, "Parasite saint : la flotte porte l'organisme")
	# Mème : routes x2 et réseau d'espionnage jusqu'à la capitale.
	Faiths.faith(st, fv)["nature"] = "meme"
	_ok(FaithWars.nature_route_pct(st, fv) == 100, "Mème : routes deux fois plus prêcheuses")
	st.networks["%d>%d" % [v, t]] = {"a": v, "b": t, "level": 10}
	var before := int(Faiths.pressures(st).get(tc.planet_id, {}).get(fv, 0))
	_ok(before > 0, "Mème : un réseau d'espionnage porte la foi jusqu'à la capitale")
	st.networks.clear()
	# Précurseurs : la capitale d'un empire de la foi qui tient des reliques prêche comme un monde saint.
	Faiths.faith(st, fv)["nature"] = "precurseurs"
	_ok(FaithWars.secondary_holy_x(st, fv, _cap(st, v)) == 1, "Précurseurs : sans relique, pas de second monde saint")


func _test_heresy() -> void:
	var st := _state()
	var ch := _id_of(st, "choeur")
	var v := _id_of(st, "vael")
	var fc := Faiths.founded_by(st, ch)
	var vc := _cap(st, v)
	vc.population = 10
	vc.faith = {fc: 10}
	var limit := Faiths.revealed_count(st)
	var hid := FaithWars.spawn_heresy(st, fc, vc.planet_id, _added())
	_ok(Faiths.parent_of(st, hid) == fc and String(Faiths.faith(st, hid)["via"]) == "heresie", "hérésie : foi fille de la Liturgie")
	_ok(int(vc.faith.get(hid, 0)) == 5 and int(vc.faith.get(fc, 0)) == 5, "la moitié des fidèles suit l'hérésie")
	_ok(Faiths.revealed_count(st) == limit, "une hérésie ne compte pas dans la limite des grandes fois")
	_ok(FaithWars.zeal(st, hid) == 70, "hérésie : zèle de jeunesse (70)")
	_ok((Faiths.name_of(st, hid).contains(" de ") or Faiths.name_of(st, hid).contains(" d'")), "nom : « %s »" % Faiths.name_of(st, hid))
	# Pas d'hérésie quand le zèle est haut.
	var n := Faiths.ids(st).size()
	Faiths.faith(st, fc)["zeal"] = 90
	for i in 24:
		st.tick += 30
		FaithWars._heresy_month(st, fc, _added())
	_ok(Faiths.ids(st).size() == n, "zèle au-dessus de 40 : pas d'hérésie")
	# Schisme : un tiers des fidèles.
	_cap(st, ch).faith = {fc: 3}
	vc.population = 12
	vc.faith = {hid: 12}
	FaithWars._schism_month(st, hid, _added())
	_ok(Faiths.parent_of(st, hid) == "" and String(Faiths.faith(st, hid).get("schism_of", "")) == fc, "schisme : l'hérésie devient grande foi")
	Faiths.set_state(st, v, hid)
	var rg := Faiths.doctrine(st, hid, "regard")
	_ok(_part(Faiths.opinion_parts(st, v, ch), "Foi sœur") == int(Faiths.data()["hostility"]["sister"][rg]) and rg == Faiths.doctrine(st, fc, "regard"), "foi mère et schisme : fois sœurs, hostilité selon le regard (hérité)")
	_ok(int(Faiths.faith(st, hid)["pending"]) > 0 and (Faiths.faith(st, hid)["offer"] as Array).size() == 3, "schisme : trois natures proposées à son fondateur")
	_ok(Faiths.check_choose(st, v, hid, String(Faiths.faith(st, hid)["offer"][0]), {}, "") == "", "un schisme ne choisit que sa nature")
	_ok(FaithWars.casus(st, ch, v) != "", "le schisme est un motif de guerre sainte")


func _test_code_saint() -> void:
	var st := _state()
	var ch := _id_of(st, "choeur")
	var v := _id_of(st, "vael")
	var fc := Faiths.founded_by(st, ch)
	var vc := _cap(st, v)
	vc.faith = {fc: vc.population}
	var hid := FaithWars.spawn_heresy(st, fc, vc.planet_id, _added())
	_ok(FaithWars.check_council(st, v, hid) != "", "concile : seul le chef de foi")
	_ok(FaithWars.check_council(st, ch, fc) != "", "concile : seulement une hérésie")
	_ok(FaithWars.check_council(st, ch, hid) == "", "concile possible pour le Chœur (Code saint)")
	var k := int(st.get_empire(ch).resources["knowledge"])
	var total := Faiths.followers(st, fc) + Faiths.followers(st, hid)
	FaithWars.council(st, ch, hid)
	_ok(Faiths.faith(st, hid).is_empty() and Faiths.followers(st, fc) == total, "concile : l'hérésie rentre dans la foi mère")
	_ok(int(st.get_empire(ch).resources["knowledge"]) == k - 200, "concile : 200 Savoir")
	_ok(FaithWars.check_rewrite(st, ch, fc, String(Faiths.faith(st, Faiths.founded_by(st, _id_of(st, "murmurants")))["precepts"][0])).contains("déjà pris"), "réécriture : pas un précepte d'une autre foi")
	_ok(FaithWars.check_rewrite(st, ch, fc, "charite") == "", "réécriture d'un précepte libre")
	FaithWars.rewrite(st, ch, fc, "charite")
	_ok((Faiths.faith(st, fc)["precepts"] as Array) == ["charite"], "réécriture : le plus ancien précepte est remplacé")
	var fv := Faiths.reveal(st, v, "relique", -1, _added())
	Faiths.faith(st, fv)["nature"] = "meme"
	_ok(FaithWars.check_rewrite(st, v, fv, "ascetisme") != "", "réécriture : seulement le Code saint")


func _test_laws() -> void:
	var off := _state(false, "", true)
	var v := _id_of(off, "vael")
	_ok(Laws.check_adopt(off, v, "tolerance").contains("religions"), "Tolérance refusée sans religions")
	var st := _state(true, "", true)
	_ok(Laws.check_adopt(st, v, "inquisition").contains("foi d'État"), "pas d'Inquisition sans foi d'État")
	var ch := _id_of(st, "choeur")
	var fc := Faiths.founded_by(st, ch)
	var fv := Faiths.reveal(st, v, "relique", -1, _added())
	_ok(Laws.law_def("tolerance").has("excludes") and (Laws.law_def("tolerance")["excludes"] as Array).has("inquisition"), "Tolérance et Inquisition s'excluent")
	# Inquisition : un fidèle par colonie et par trimestre passe à la foi d'État.
	var vc := _cap(st, v)
	vc.population = 10
	vc.faith = {fv: 6, fc: 4}
	Politics._emp_w(st, v)["laws"] = ["inquisition"]
	Relics.touch(st)
	_ok(Research.fx_int(st, v, "faith_inquisition") > 0, "Inquisition en vigueur")
	st.tick = 3 * int(GameData.rules()["month_days"])
	FaithWars._cult_month(st, st.get_empire(v), _added())
	_ok(int(vc.faith.get(fc, 0)) == 3 and int(vc.faith.get(fv, 0)) == 7, "Inquisition : un fidèle converti de force")
	_ok(_part(Faiths.opinion_parts(st, ch, v), "Persécute") == -10, "les fidèles persécutés s'en souviennent (-10)")
	_ok(FaithWars.casus(st, ch, v) != "", "la persécution est un motif de guerre sainte")
	# Doléance « Liberté de culte » : au moins 25 % d'une autre foi.
	Politics._emp_w(st, v)["laws"] = []
	Relics.touch(st)
	FaithWars._cult_month(st, st.get_empire(v), _added())
	_ok(FaithWars.demand(st, v) > st.tick, "minorité de 30 % : doléance « Liberté de culte »")
	_ok(FaithWars.law_score(st, st.get_empire(v), "tolerance", 0) == 60, "l'IA veut la Tolérance pendant la doléance")
	Politics._emp_w(st, v)["laws"] = ["tolerance"]
	Relics.touch(st)
	FaithWars._cult_month(st, st.get_empire(v), _added())
	var sid := _sid(st, vc)
	_ok(_part(FaithWars.stability_parts(st, sid, v), "Liberté de culte accordée") == 5, "doléance satisfaite : +5 de stabilité")
	_ok(_part(Faiths.stability_parts(st, sid, v), "Autre foi") == 0, "Tolérance : plus de malus d'autre foi majoritaire")


func _test_missions() -> void:
	var st := _state()
	var ch := _id_of(st, "choeur")
	var t := _id_of(st, "teyl")
	var v := _id_of(st, "vael")
	var tsid := _sid(st, _cap(st, t))
	st.get_empire(ch).explored[tsid] = true
	_ok(FaithWars.check_mission(st, v, tsid) != "", "mission : il faut une foi d'État")
	_ok(FaithWars.check_mission(st, ch, tsid) == "", "mission possible chez les Teyl")
	var fc := Faiths.founded_by(st, ch)
	var before := int(Faiths.pressures(st).get(_cap(st, t).planet_id, {}).get(fc, 0))
	FaithWars.mission(st, ch, tsid)
	var after := int(Faiths.pressures(st).get(_cap(st, t).planet_id, {}).get(fc, 0))
	_ok(after > before, "mission : la foi prêche chez les Teyl (%d → %d)" % [before, after])
	_ok(FaithWars.check_mission(st, ch, tsid) != "", "une seule mission par système")
	_ok(_part(Faiths.opinion_parts(st, t, ch), "Missionnaires") == -5, "les Teyl n'aiment pas les missionnaires (-5)")
	_ok(FaithWars.check_ward(st, t, tsid) == "", "inquisition possible pour le maître du système")
	FaithWars.ward(st, t, tsid)
	_ok(FaithWars.missions_by(st, ch).is_empty(), "mission chassée")
	_ok(FaithWars.check_mission(st, ch, tsid) != "", "système protégé deux ans")
	# Échéance.
	var osid := _sid(st, _cap(st, v))
	st.get_empire(ch).explored[osid] = true
	FaithWars.mission(st, ch, osid)
	st.tick += 400
	FaithWars.monthly(st, _added())
	_ok(FaithWars.missions_by(st, ch).is_empty(), "mission terminée après un an")


func _test_holy_war() -> void:
	var st := _state()
	var ch := _id_of(st, "choeur")
	var v := _id_of(st, "vael")
	var t := _id_of(st, "teyl")
	var fc := Faiths.founded_by(st, ch)
	_ok(FaithWars.casus(st, ch, v) == "", "pas de motif de guerre sainte contre un voisin quelconque")
	# Vael prend le monde saint.
	var holy := _cap(st, ch)
	holy.owner = v
	st.rebuild_ownership()
	_ok(FaithWars.casus(st, ch, v) != "", "motif : il tient notre monde saint")
	var refuge := _plant(st, ch, 6, _sid(st, holy), 2)
	refuge.faith = {fc: 6}
	_ok(Faiths.head(st, fc) == ch, "le chef de foi reste un empire de la foi, pas le conquérant")
	for e in st.empires:
		for x in [v, ch]:
			if e.id != x and not e.contacts.has(x):
				e.contacts.append(x)
	Faiths.set_state(st, t, fc)
	var z := FaithWars.zeal(st, fc)
	_ok(FaithWars.check_crusade(st, ch, v) == "", "le chef de foi peut prêcher la croisade (%s)" % FaithWars.check_crusade(st, ch, v))
	SimCommands.apply(st, SimCommands.faith_crusade(ch, v))
	_ok(Combat.at_war(st, ch, v), "croisade : guerre déclarée")
	_ok(not FaithWars.crusade_of(st, fc).is_empty(), "croisade en cours")
	_ok(Combat.at_war(st, t, v), "un coreligionnaire répond à l'appel")
	_ok(FaithWars.zeal(st, fc) > z, "guerre sainte : le zèle monte")
	_ok(_part(Faiths.opinion_parts(st, t, ch), "Mène la guerre sainte") == 10, "les fidèles applaudissent le croisé (+10)")
	_ok(FaithWars.check_crusade(st, ch, v) != "", "une seule croisade à la fois")
	# Le monde saint repris : triomphe.
	holy.owner = ch
	st.rebuild_ownership()
	FaithWars._crusade_month(st, _added())
	_ok(FaithWars.crusade_of(st, fc).is_empty(), "monde saint repris : la croisade triomphe")


func _test_secret() -> void:
	var st := _state()
	var mu := _id_of(st, "murmurants")
	var v := _id_of(st, "vael")
	var fm := Faiths.founded_by(st, mu)
	Faiths.faith(st, fm)["doctrines"]["diffusion"] = "secrete"
	_ok(FaithWars.is_secret(st, fm), "le Murmure se cache (diffusion Secrète)")
	var vc := _cap(st, v)
	vc.population = 10
	vc.faith = {fm: 6}
	_ok(not FaithWars.visible_to(st, fm, v) and FaithWars.visible_to(st, fm, mu), "invisible pour Vael, visible pour ses fidèles")
	_ok(not Faiths.visible_counts(st, vc, v).has(fm), "Vael ne voit pas les fidèles cachés chez lui")
	_ok(_part(Faiths.stability_parts(st, _sid(st, vc), v), "Autre foi") == 0, "une foi cachée ne trouble pas la stabilité")
	# Une flotte de la foi en guerre arrive : soulèvement.
	Combat.start_war(st, mu, v)
	var fl: Fleet = Fleets.empire_fleets(st, mu)[0]
	fl.path.clear()
	fl.system_id = _sid(st, vc)
	FaithWars._secret_month(st, _added())
	_ok(_part(FaithWars.stability_parts(st, _sid(st, vc), v), "Soulèvement") == -25, "soulèvement : -25 de stabilité")
	_ok(FaithWars.visible_to(st, fm, v), "le soulèvement révèle le culte")


func _test_prophecy() -> void:
	var st := _state()
	var ch := _id_of(st, "choeur")
	var v := _id_of(st, "vael")
	var kh := _id_of(st, "khthari")
	var fc := Faiths.founded_by(st, ch)
	_ok(FaithWars.check_prophecy(st, v, ch) != "", "prophétie : il faut une foi d'État")
	_ok(FaithWars.check_prophecy(st, ch, kh) != "", "une ruche n'écoute pas les prophètes")
	_ok(FaithWars.check_prophecy(st, ch, v) == "", "prophétie possible contre Vael")
	_ok(Espionage.op_def("prophetie").get("faiths", false) == true, "opération d'intrigue « Semer une prophétie »")
	FaithWars.plant(st, ch, v)
	var vc := _cap(st, v)
	_ok(st.faiths["prophecies"].has(str(vc.planet_id)), "prophétie semée sur la capitale de Vael")
	# Un héros amiral du Chœur arrive.
	var hid := Heroes.recruit(st, ch, Heroes.make_candidate(st, ch, "amiral", ["prophetie"]))
	var fl: Fleet = Fleets.empire_fleets(st, ch)[0]
	fl.path.clear()
	fl.system_id = _sid(st, vc)
	Heroes.assign(st, ch, hid, "fleet", fl.id)
	st.heroes[hid]["arrive"] = 0
	FaithWars._prophecy_month(st, _added())
	_ok(int(vc.faith.get(fc, 0)) == vc.population, "prophétie accomplie : tout le monde se convertit")
	_ok(_part(FaithWars.stability_parts(st, _sid(st, vc), v), "Prophétie") == -20, "et la stabilité vacille (-20)")


func _test_je() -> void:
	var st := _state()
	var kh := _id_of(st, "khthari")
	var c := _cap(st, kh)
	c.population = 10
	_ok(FaithWars.check_je(st, kh, c.planet_id, "ecraser") != "", "pas de drones dissidents au départ")
	st.faiths["je"][str(c.planet_id)] = {"n": 4, "tol": false}
	_ok(FaithWars.je_blocks_growth(st, c), "4 drones dissidents : la ponte s'arrête")
	FaithWars.je_act(st, kh, c.planet_id, "tolerer")
	_ok(not FaithWars.je_blocks_growth(st, c), "tolérés : la ponte reprend")
	var k := int(st.get_empire(kh).resources["knowledge"])
	st.tick = 0
	FaithWars._je_month(st, st.get_empire(kh), _added())
	_ok(int(st.get_empire(kh).resources["knowledge"]) > k, "tolérés : les drones pensants rapportent du Savoir")
	FaithWars.je_act(st, kh, c.planet_id, "ecraser")
	_ok(FaithWars.je(st, c.planet_id).is_empty() and c.population < 10, "écrasés : des drones en moins, plus de dissidents")
	_ok(int(st.faiths["je"].get("block:" + str(c.planet_id), 0)) > st.tick, "écrasés : rien ne repousse pendant trois ans")
	# Non tolérés jusqu'à 12 : la colonie fait sécession.
	st.faiths["je"].erase("block:" + str(c.planet_id))
	var c2: Colony = null
	for j in range(1, 6):
		if c2 == null:
			c2 = _plant(st, kh, 8, _sid(st, c), j)
	st.faiths["je"][str(c2.planet_id)] = {"n": 12, "tol": false}
	FaithWars._je_month(st, st.get_empire(kh), _added())
	_ok(c2.owner != kh, "12 drones dissidents : la colonie se détache de la ruche")
	# Une ruche n'a ni foi ni lois de culte : rien chez les autres peuples.
	var v := _id_of(st, "vael")
	_ok(FaithWars.check_je(st, v, _cap(st, v).planet_id, "ecraser") != "", "le Culte du Je ne touche que les ruches")


## Refonte v2 : excommunication, concile, quarantaine, sacrifices, Peuple élu, Réforme, chef « Aucun »,
## temple et Liturgie, pare-feu du Mème, Précurseurs, résurrection du Parasite, Tolérance interdite.
func _test_v2() -> void:
	var st := _state()
	var ch := _id_of(st, "choeur")
	var v := _id_of(st, "vael")
	var t := _id_of(st, "teyl")
	var fc := Faiths.founded_by(st, ch)
	_ok(Faiths.has_head(st, fc) and Faiths.head(st, fc) == ch, "le Chœur, chef de sa foi")
	# Excommunication.
	_ok(FaithWars.check_excom(st, ch, v) != "", "on n'excommunie qu'un empire de sa foi")
	Faiths.set_state(st, v, fc)
	_ok(FaithWars.check_excom(st, v, ch) != "", "seul le chef de foi excommunie")
	_ok(FaithWars.check_excom(st, ch, v) == "", "excommunication possible")
	FaithWars.excommunicate(st, ch, v)
	_ok(FaithWars.excommunicated(st, fc, v), "Vael excommunié")
	_ok(_part(Faiths.opinion_parts(st, ch, v), "Excommunié") == -20, "excommunié : opinion -20 des fidèles")
	_ok(_part(FaithWars.stability_parts(st, _sid(st, _cap(st, v)), v), "Excommunié") == -5, "excommunié : stabilité -5 chez lui")
	_ok(FaithWars.casus(st, ch, v).contains("excommunié"), "excommunié : cible légitime de croisade")
	st.tick += 3601
	_ok(not FaithWars.excommunicated(st, fc, v), "l'excommunication tombe après dix ans")
	# Concile : changer une doctrine, puis attendre cinq ans.
	var inf := int(st.get_empire(ch).resources["influence"])
	var cost := FaithWars.concile_cost(st, fc)
	_ok(FaithWars.check_concile(st, v, fc, "regard", "pluraliste") != "", "concile : seul le chef de foi")
	_ok(FaithWars.check_concile(st, ch, fc, "regard", Faiths.doctrine(st, fc, "regard")) != "", "concile : pas pour la doctrine actuelle")
	var target := "pluraliste" if Faiths.doctrine(st, fc, "regard") != "pluraliste" else "juste"
	_ok(FaithWars.check_concile(st, ch, fc, "regard", target) == "", "concile possible")
	SimCommands.apply(st, SimCommands.faith_concile(ch, fc, "regard", target))
	_ok(Faiths.doctrine(st, fc, "regard") == target, "concile : la doctrine change")
	_ok(cost.has("knowledge") or int(st.get_empire(ch).resources["influence"]) == inf - int(cost.get("influence", 0)), "concile payé")
	_ok(FaithWars.check_concile(st, ch, fc, "regard", "juste" if target != "juste" else "fondamentaliste").contains("récent"), "un concile tous les cinq ans")
	# Chef « Aucun » : pas de croisade ni d'excommunication.
	Faiths.faith(st, fc)["doctrines"]["chef"] = "aucun"
	_ok(FaithWars.check_crusade(st, ch, t).contains("sans chef"), "sans chef, pas de croisade")
	_ok(FaithWars.check_excom(st, ch, v) != "", "sans chef, pas d'excommunication")
	Faiths.faith(st, fc)["doctrines"]["chef"] = "elu"
	# Tolérance interdite sous une foi d'État fondamentaliste.
	var sp := _state(true, "", true)
	Faiths.faith(sp, Faiths.founded_by(sp, ch))["doctrines"]["regard"] = "fondamentaliste"
	_ok(Laws.check_adopt(sp, ch, "tolerance").contains("fondamentaliste"), "Fondamentaliste : pas de Tolérance (%s)" % Laws.check_adopt(sp, ch, "tolerance"))
	# Quarantaine.
	SimCommands.apply(st, SimCommands.faith_quarantine(t))
	_ok(FaithWars.quarantined(st, t) and _part(FaithWars.stability_parts(st, _sid(st, _cap(st, t)), t), "Quarantaine") == -2, "quarantaine : -2 de stabilité")
	SimCommands.apply(st, SimCommands.faith_quarantine(t))
	_ok(not FaithWars.quarantined(st, t), "quarantaine levée")
	# Sacrifices.
	var cc := _cap(st, ch)
	_ok(FaithWars.check_sacrifice(st, ch, cc.planet_id) != "", "sans le précepte, pas de sacrifice")
	Faiths.faith(st, fc)["precepts"] = ["sacrifices"]
	Relics.touch(st)
	cc.faith = {fc: cc.population}
	var z := FaithWars.zeal(st, fc)
	var pop := cc.population
	_ok(FaithWars.check_sacrifice(st, ch, cc.planet_id) == "", "sacrifice possible")
	SimCommands.apply(st, SimCommands.faith_sacrifice(ch, cc.planet_id))
	_ok(cc.population == pop - 1 and FaithWars.zeal(st, fc) == mini(100, z + 5), "sacrifice : un habitant de moins, zèle +5")
	# Liturgie : stabilité des systèmes à temple.
	Faiths.faith(st, fc)["precepts"] = ["liturgie"]
	Relics.touch(st)
	cc.buildings.append("temple")
	_ok(_part(Faiths.stability_parts(st, _sid(st, cc), ch), "Temple") == 3, "Liturgie : temple +3 de stabilité")
	# Peuple élu : seuls les habitants du peuple d'origine se convertissent.
	Faiths.faith(st, fc)["doctrines"]["diffusion"] = "peuple_elu"
	_ok(Faiths.chosen_people(st, fc) == Peoples.founder_of(st, ch), "Peuple élu : le peuple du fondateur")
	_ok(Faiths.cap_in(st, _cap(st, t), fc) == int(Peoples.counts(st, _cap(st, t)).get(Peoples.founder_of(st, ch), 0)), "Peuple élu : plafond des fidèles chez les autres")
	Faiths.faith(st, fc)["doctrines"]["diffusion"] = "missionnaire"
	_ok(Faiths.cap_in(st, _cap(st, t), fc) == _cap(st, t).population, "Missionnaire : tout le monde peut se convertir")
	# Réforme d'un culte natal.
	_ok(not Faiths.can_reform(st, t), "Réforme : il faut trois colonies et un temple")
	_ok(Faiths.native_name(st, t) != "", "cultes natals nommés selon le registre (%s)" % Faiths.native_name(st, t))
	# Mème : le pare-feu (Propagande) coupe ses routes.
	var fm := Faiths.founded_by(st, _id_of(st, "murmurants"))
	Faiths.faith(st, fm)["nature"] = "meme"
	var tsid := _sid(st, _cap(st, t))
	_ok(not FaithWars.firewalled(st, fm, tsid), "sans Propagande, pas de pare-feu")
	Research.grant(st, t, ["propagande"])
	Relics.touch(st)
	_ok(FaithWars.firewalled(st, fm, tsid), "Propagande : pare-feu contre le Mème")
	# Précurseurs : une fouille donne du zèle.
	Faiths.faith(st, fc)["nature"] = "precurseurs"
	z = FaithWars.zeal(st, fc)
	FaithWars.on_dig(st, ch)
	_ok(FaithWars.zeal(st, fc) == mini(100, z + 3), "Précurseurs : fouille, zèle +3")
	# Parasite saint : un héros ressuscite une fois.
	Faiths.faith(st, fc)["nature"] = "parasite"
	var h := {"name": "Essai", "owner": ch}
	_ok(FaithWars.try_resurrect(st, h, _added()), "Parasite saint : le héros se relève")
	_ok(not FaithWars.try_resurrect(st, h, _added()), "une seule fois")


func _test_commands() -> void:
	var st := _state()
	var ch := _id_of(st, "choeur")
	var t := _id_of(st, "teyl")
	var tsid := _sid(st, _cap(st, t))
	st.get_empire(ch).explored[tsid] = true
	_ok(SimCommands.validate(st, SimCommands.faith_mission(ch, tsid)) == "", "ordre : mission")
	SimCommands.apply(st, SimCommands.faith_mission(ch, tsid))
	_ok(FaithWars.missions_by(st, ch).size() == 1, "ordre de mission appliqué")
	_ok(SimCommands.validate(st, SimCommands.faith_ward(t, tsid)) == "", "ordre : inquisition")
	_ok(SimCommands.validate(st, SimCommands.faith_crusade(ch, t)) != "", "ordre de croisade refusé sans motif")
	_ok(SimCommands.validate(st, SimCommands.faith_je(ch, _cap(st, ch).planet_id, "ecraser")) != "", "ordre du Culte du Je refusé hors ruche")
	_ok(SimCommands.validate(_state(false), SimCommands.faith_mission(ch, tsid)) != "", "ordre refusé sans l'option")


func _test_ai() -> void:
	var st := _state(true, "normal")
	var mu := _id_of(st, "murmurants")
	var fm := Faiths.founded_by(st, mu)
	Faiths.monthly(st, _added())
	_ok(Faiths.doctrine(st, fm, "diffusion") == "secrete", "l'IA murmurante choisit la diffusion Secrète")
	var opts := {"ai_level": "normal", "faiths": "actives"}
	var a := Simulation.new(GameState.create(4242, 150, 1800.0, "vael", opts))
	var b := Simulation.new(GameState.create(4242, 150, 1800.0, "vael", opts))
	a.advance(1080)
	b.advance(1080)
	_ok(a.state.checksum() == b.state.checksum(), "trois ans de partie avec le lot 2 : déterministe")
	var zeals := []
	for fid in Faiths.ids(a.state):
		zeals.append(FaithWars.zeal(a.state, fid))
	_ok(not zeals.is_empty() and zeals != [50, 50], "le zèle bouge au fil des ans : %s" % str(zeals))


func _test_save() -> void:
	var st := _state()
	var ch := _id_of(st, "choeur")
	var t := _id_of(st, "teyl")
	var v := _id_of(st, "vael")
	var kh := _id_of(st, "khthari")
	var fc := Faiths.founded_by(st, ch)
	var tsid := _sid(st, _cap(st, t))
	st.get_empire(ch).explored[tsid] = true
	FaithWars.mission(st, ch, tsid)
	FaithWars.add_zeal(st, fc, 13)
	var vc := _cap(st, v)
	vc.faith = {fc: vc.population}
	FaithWars.spawn_heresy(st, fc, vc.planet_id, _added())
	st.faiths["je"][str(_cap(st, kh).planet_id)] = {"n": 3, "tol": true}
	FaithWars.add_stab(st, tsid, "Soulèvement de test", -25, 100)
	FaithWars.plant(st, ch, t)
	var d := st.to_dict()
	_ok(int(d["version"]) == 50, "sauvegarde version 50")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and FaithWars.zeal(back, fc) == 63, "zèle relu")
	_ok(back != null and FaithWars.missions_by(back, ch).size() == 1, "missions relues")
	_ok(back != null and FaithWars.nature(back, fc) == "code_saint", "nature relue")
	_ok(back != null and back.checksum() == st.checksum(), "même empreinte après relecture (lot 2)")
	var old := d.duplicate(true)
	old["version"] = 43
	for f in old["faiths"]["list"]:
		old["faiths"]["list"][f].erase("zeal")
		old["faiths"]["list"][f].erase("nature")
	for k in ["missions", "wards", "crusades", "holy_wars", "seen", "prophecies", "je", "stab", "demands"]:
		old["faiths"].erase(k)
	var back2 := GameState.from_dict(JSON.parse_string(JSON.stringify(old)))
	_ok(back2 != null and FaithWars.zeal(back2, fc) == 50 and FaithWars.missions_by(back2, ch).is_empty(), "sauvegarde 43 : zèle 50, rien du lot 2")
