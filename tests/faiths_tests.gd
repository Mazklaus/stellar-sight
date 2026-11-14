extends RefCounted
## Tests de la religion, lot 1 (propositions 1 à 10) : option coupée, fois de départ, cultes natals,
## Révélations par les cinq voies et limite, propagation (proximité, routes, ruches), naissances,
## fondations et migrants, préceptes et doctrines (chef de foi, paliers, réservation, effets, choix du fondateur), foi d'État (stabilité,
## opinion, délai), ferveur, ordres, IA, sauvegarde 43, déterminisme.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Religion (fidèles, grandes fois, Révélations, préceptes, propagation, foi d'État)…")
	_test_off()
	_test_setup()
	_test_native()
	_test_reveal()
	_test_hooks()
	_test_spread()
	_test_population()
	_test_precepts()
	_test_choice()
	_test_state()
	_test_fervor()
	_test_commands()
	_test_ai()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _state(on := true, ai := "") -> GameState:
	var st := GameState.create(4242, 150, 1800.0, "vael", {"ai_level": ai, "faiths": "actives" if on else "aucunes"})
	for e in st.empires:
		e.resources["energy"] = 5000
		e.resources["influence"] = 5000
		e.resources["materials"] = 5000
		e.resources["food"] = 5000
	# Fondateurs sans IA (tests) : le choix par défaut, comme si le délai était échu.
	for fid in Faiths.ids(st):
		var f := Faiths.faith(st, fid)
		if int(f["pending"]) > 0:
			var ch := Faiths.default_choice(st, int(f["founder"]), fid)
			Faiths.choose(st, fid, String(ch["nature"]), ch["doctrines"], String(ch["precept"]))
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


## Colonie établie sur une planète libre à exactement `jumps` sauts du système `from` (null sinon).
func _plant(st: GameState, owner: int, pop: int, from: int, jumps: int) -> Colony:
	var dist := FactionTraits.jumps_from(st.galaxy, from)
	var ids := dist.keys()
	ids.sort()
	for s in ids:
		if int(dist[s]) != jumps or st.system_owner(int(s)) >= 0:
			continue
		for pid in st.galaxy.systems[int(s)].planet_ids:
			if not st.colonies.has(pid):
				return _plant_at(st, owner, pid, pop)
	return null


func _plant_at(st: GameState, owner: int, pid: int, pop: int) -> Colony:
	var c := Colony.new()
	c.planet_id = pid
	c.owner = owner
	c.kind = Colony.KIND_COLONY
	c.population = pop
	st.add_colony(c)
	st.rebuild_ownership()
	return c


func _part(parts: Array, prefix: String) -> int:
	for p in parts:
		var label := String(p["label"]) if p is Dictionary else String(p[0])
		if label.begins_with(prefix):
			return int(p["value"]) if p is Dictionary else int(p[1])
	return 0


func _test_off() -> void:
	var st := _state(false)
	var ch := _id_of(st, "choeur")
	_ok(not st.faith_on and Faiths.ids(st).is_empty(), "sans l'option : aucune foi")
	_ok(Faiths.state_faith(st, ch) == Faiths.LAICITE and Faiths.effects(st, ch).is_empty(), "sans l'option : ni foi d'État ni effets")
	_ok(_cap(st, ch).faith.is_empty() and Faiths.is_faithful(st, _cap(st, ch)), "sans l'option : ferveur comme avant")
	var d := st.to_dict()
	_ok(not d.has("faiths") and not (d["colonies"] as Array)[0].has("faith"), "sans l'option : sauvegarde sans fidèles")


func _test_setup() -> void:
	var st := _state()
	var ch := _id_of(st, "choeur")
	var mu := _id_of(st, "murmurants")
	var v := _id_of(st, "vael")
	_ok(st.empires.size() == 8 and Faiths.limit(st) == 5, "8 empires : au plus 5 grandes fois")
	var fc := Faiths.founded_by(st, ch)
	var fm := Faiths.founded_by(st, mu)
	_ok(fc != "" and fm != "" and Faiths.ids(st).size() == 2, "Chœur et Murmurants commencent avec leur foi")
	_ok(Faiths.name_of(st, fc) == "Liturgie du Dieu-Machine" and Faiths.name_of(st, fm) == "Le Murmure", "noms imposés des deux théocraties")
	_ok(int(Faiths.faith(st, fc)["holy"]) == st.get_empire(ch).capital_planet, "monde saint : la capitale")
	_ok(int(_cap(st, ch).faith.get(fc, 0)) == _cap(st, ch).population, "toute la capitale suit la foi")
	_ok(Faiths.state_faith(st, ch) == fc and Faiths.state_faith(st, v) == Faiths.LAICITE, "foi d'État : la leur ; laïcité pour les autres")
	_ok(String(Faiths.faith(st, fc)["via"]) == "origine" and st.chronicle.filter(func(x): return String(x["text"]).begins_with("Révélation")).is_empty(), "fondation d'origine : pas de chronique")
	var kh := _id_of(st, "khthari")
	_ok(Faiths.is_hive(st, kh) and Faiths.closed(st, kh) and Faiths.offer_natures(st, kh, "x", "relique") == ["communion"], "la ruche ne croit qu'en Communion")
	_ok(Faiths.head(st, fc) == ch, "chef de foi : le fondateur")


func _test_native() -> void:
	var st := _state()
	var v := _id_of(st, "vael")
	var off := _state(false)
	_ok(Research.production_bonus(st, v, "knowledge") == Research.production_bonus(off, v, "knowledge") + 5, "culte natal Vael (raison) : Savoir +5 %")
	var o := _id_of(st, "ossarane")
	_ok(Research.fx_int(st, o, "garrison_pct") == Research.fx_int(off, o, "garrison_pct") + 10, "culte natal Ossarane (honneur) : garnisons +10 %")
	_ok(Faiths.native_def(st, _id_of(st, "khthari")).is_empty(), "pas de culte natal pour la ruche")


func _test_reveal() -> void:
	var st := _state()
	var v := _id_of(st, "vael")
	var cap := _cap(st, v)
	cap.population = 9
	var added: Array[Dictionary] = []
	var fv := Faiths.reveal(st, v, "relique", -1, added)
	_ok(fv != "" and Faiths.founded_by(st, v) == fv, "Révélation : Vael fonde une foi")
	_ok(int(cap.faith.get(fv, 0)) == 5, "la colonie sainte se convertit à moitié, arrondi au-dessus (5 sur 9)")
	_ok(Faiths.state_faith(st, v) == fv, "devient foi d'État d'un empire laïque")
	_ok(added.size() == 1 and String(added[0]["text"]).contains("Révélation"), "chronique de la Révélation")
	_ok(Faiths.reveal(st, v, "gardien", -1, added) == "", "une seule foi fondée par empire")
	var o := _id_of(st, "ossarane")
	var t := _id_of(st, "teyl")
	var b := _id_of(st, "brisecomete")
	var f := _id_of(st, "ferrocornes")
	_ok(Faiths.reveal(st, o, "heros", -1, added) != "" and Faiths.reveal(st, t, "savoir", -1, added) != "", "4e et 5e foi")
	_ok(Faiths.ids(st).size() == 5 and Faiths.reveal(st, b, "prophete", -1, added) == "", "limite : pas de 6e grande foi")
	_ok(not Faiths.can_found(st, f), "plus aucun empire ne peut fonder")
	var names := {}
	for fid in Faiths.ids(st):
		names[Faiths.name_of(st, fid)] = true
	_ok(names.size() == 5, "cinq noms différents")


func _test_hooks() -> void:
	# Voie du savoir : trois technologies de Société de l'ère II.
	var st := _state()
	var t := _id_of(st, "teyl")
	var soc: Array = []
	for tid in Research.data()["technologies"]:
		var td: Dictionary = Research.data()["technologies"][tid]
		if String(td["domain"]) == "societe" and int(td["era"]) == 2:
			soc.append(String(tid))
	soc.sort()
	Research.grant(st, t, soc.slice(0, 2))
	var added: Array[Dictionary] = []
	Faiths.monthly(st, added)
	_ok(Faiths.founded_by(st, t) == "", "deux technologies de l'âme ne suffisent pas")
	Research.grant(st, t, soc.slice(2, 3))
	Faiths.monthly(st, added)
	_ok(Faiths.founded_by(st, t) != "" and String(Faiths.faith(st, Faiths.founded_by(st, t))["via"]) == "savoir", "voie du savoir : trois technologies de Société de l'ère II")
	# Héros à l'ambition Foi.
	var o := _id_of(st, "ossarane")
	Faiths.on_hero_level(st, {"amb": "foi", "lvl": 2, "owner": o})
	_ok(Faiths.founded_by(st, o) == "", "héros Foi de niveau 2 : rien")
	Faiths.on_hero_level(st, {"amb": "gloire", "lvl": 3, "owner": o})
	_ok(Faiths.founded_by(st, o) == "", "héros d'une autre ambition : rien")
	Faiths.on_hero_level(st, {"amb": "foi", "lvl": 3, "owner": o})
	_ok(Faiths.founded_by(st, o) != "", "voie du héros : ambition Foi au niveau 3")
	# Relique sainte.
	var v := _id_of(st, "vael")
	st.relics["graal_vide"] = {"owner": -1, "hero": -1, "found": -1, "ready": 0}
	Relics.gain(st, v, "graal_vide")
	_ok(Faiths.founded_by(st, v) != "" and String(Faiths.faith(st, Faiths.founded_by(st, v))["via"]) == "relique", "voie de la relique sainte")
	# Prophète des docks : choix « L'écouter ».
	var st2 := _state()
	var b := _id_of(st2, "brisecomete")
	var cap := _cap(st2, b)
	var item := {"id": -1, "card": "prophete_docks", "system": _sid(st2, cap), "planet": -1, "rival": -1, "hero": -1}
	var ev: Dictionary = {}
	for e: Dictionary in GameData.events()["cards"]:
		if String(e["id"]) == "prophete_docks":
			ev = e
	_ok(not ev.is_empty() and Events.fx_lines(st2, b, item, ev["choices"][0]["fx"]).has("Révélation : une grande foi peut naître ici"), "prophète : effet annoncé")
	Events.apply_fx(st2, b, item, ev["choices"][0]["fx"], added)
	var fb := Faiths.founded_by(st2, b)
	_ok(fb != "" and int(Faiths.faith(st2, fb)["holy"]) == cap.planet_id, "voie du prophète : monde saint là où il prêche")
	# Gardien vaincu : la colonie du système devient monde saint.
	var f := _id_of(st2, "teyl")
	var fc := _cap(st2, f)
	Guardians._reward(st2, String(Guardians.data()["guardians"][0]["id"]), f, _sid(st2, fc), added)
	_ok(Faiths.founded_by(st2, f) != "" and String(Faiths.faith(st2, Faiths.founded_by(st2, f))["via"]) == "gardien", "voie du gardien vaincu")


func _test_spread() -> void:
	var st := _state()
	var ch := _id_of(st, "choeur")
	var fc := Faiths.founded_by(st, ch)
	var cap := _cap(st, ch)
	var csid := _sid(st, cap)
	var v := _id_of(st, "vael")
	var near := _plant(st, v, 5, csid, 1)
	var far := _plant(st, v, 5, csid, 5)
	var hive := _plant(st, _id_of(st, "khthari"), 5, csid, 1)
	_ok(near != null and far != null and hive != null, "colonies d'essai plantées")
	var p := Faiths.pressures(st)
	_ok(Faiths.doctrine(st, fc, "diffusion") == "missionnaire", "le Chœur est missionnaire (prêche +25 %)")
	var expect := cap.population * 2 * 4 * 125 / 100
	_ok(int(p.get(near.planet_id, {}).get(fc, 0)) == expect, "pression à 1 saut : fidèles x 2 x 4 (monde saint), +25 % (Missionnaire)")
	_ok(int(p.get(far.planet_id, {}).get(fc, 0)) == 0, "pas de pression à 5 sauts")
	_ok(not p.has(hive.planet_id), "une ruche ne subit aucune pression")
	_ok(Faiths.threshold(st, near, fc) == 40 + 10 * 5, "seuil de conversion : 40 + 10 x population")
	for i in 12:
		Faiths._spread(st)
	_ok(int(near.faith.get(fc, 0)) > 0 and near.faith.get(fc, 0) <= near.population, "la foi gagne la colonie voisine")
	_ok(far.faith.is_empty() and hive.faith.is_empty(), "ni la colonie lointaine ni la ruche")
	# Route commerciale extérieure : les deux bouts se poussent.
	st.trade["routes"] = [{"from": ch, "to": v, "kind": "ext", "path": [csid, _sid(st, far)], "blocked": false}]
	p = Faiths.pressures(st)
	_ok(int(p.get(far.planet_id, {}).get(fc, 0)) == cap.population * 4 * 2 * 125 / 100, "route commerciale : poids 2 jusqu'au bout")
	st.trade["routes"][0]["blocked"] = true
	p = Faiths.pressures(st)
	_ok(int(p.get(far.planet_id, {}).get(fc, 0)) == 0, "route bloquée : plus de prêche")
	# Poussée de la foi d'État.
	Faiths.set_state(st, v, fc)
	p = Faiths.pressures(st)
	_ok(int(p.get(far.planet_id, {}).get(fc, 0)) == 5 * 125 / 100, "foi d'État : poussée de 5 sur chaque colonie")
	# Loi Ordres missionnaires : prêche +25 %.
	_ok(Laws.law_def("ordres_missionnaires").get("fx", {}).has("faith_pressure_pct"), "Ordres missionnaires : prêche renforcé")


func _test_population() -> void:
	var st := _state()
	var ch := _id_of(st, "choeur")
	var fc := Faiths.founded_by(st, ch)
	var cap := _cap(st, ch)
	# Fondation : les colons suivent la foi d'État.
	var c := _plant(st, ch, 3, _sid(st, cap), 2)
	Faiths.on_founded(st, c)
	_ok(int(c.faith.get(fc, 0)) == 3, "les colons suivent la foi d'État")
	var v := _id_of(st, "vael")
	var cv := _plant(st, v, 3, _sid(st, cap), 3)
	Faiths.on_founded(st, cv)
	_ok(cv.faith.is_empty(), "colons d'un empire laïque : cultes natals")
	# Naissance.
	cv.population = 4
	cv.faith = {fc: 3}
	cv.population += 1
	Faiths.on_birth(st, cv)
	_ok(int(cv.faith[fc]) == 4, "naissance : l'enfant suit la foi de plus de la moitié")
	cv.faith = {fc: 2}
	cv.population = 5
	Faiths.on_birth(st, cv)
	_ok(int(cv.faith[fc]) == 2, "naissance sans majorité : cultes natals")
	# Pertes : la plus grande foi perd d'abord.
	cv.faith = {fc: 4, "incroyance": 1}
	cv.population = 3
	Faiths.normalize(cv)
	_ok(int(cv.faith[fc]) == 2 and int(cv.faith["incroyance"]) == 1, "pertes : la plus grande foi d'abord")
	# Migrants : ils emportent la croyance majoritaire.
	cv.faith = {fc: 3}
	cv.population = 4
	var dest := _plant(st, v, 2, _sid(st, cap), 4)
	Movements.remove_one(st, cv, Peoples.founder_of(st, v))
	Movements.add_one(st, dest, Peoples.founder_of(st, v), 100)
	_ok(int(cv.faith.get(fc, 0)) == 2 and int(dest.faith.get(fc, 0)) == 1 and dest.population == 3, "le migrant emporte sa foi")
	# Conquête : les fidèles restent.
	dest.owner = ch
	_ok(int(dest.faith.get(fc, 0)) == 1, "conquête : les fidèles gardent leur foi")


func _test_precepts() -> void:
	var st := _state()
	var v := _id_of(st, "vael")
	var ch := _id_of(st, "choeur")
	var mu := _id_of(st, "murmurants")
	var fc := Faiths.founded_by(st, ch)
	var fm := Faiths.founded_by(st, mu)
	_ok(Faiths.precept_ids().size() == 20, "catalogue de 20 préceptes")
	var fam := {}
	for pid in Faiths.precept_ids():
		fam[String(Faiths.precept_def(pid)["family"])] = true
	_ok(fam.size() == 4, "4 familles de préceptes")
	# L'IA fondatrice a fixé sa foi tout de suite : nature proposée, doctrines, premier précepte.
	var f := Faiths.faith(st, fc)
	_ok(int(f["pending"]) == 0 and (f["offer"] as Array).has(String(f["nature"])), "l'IA fixe sa foi dès la Révélation, nature parmi les trois proposées")
	_ok((f["precepts"] as Array) == ["liturgie"], "credo Foi : la Liturgie d'abord")
	_ok(Faiths.free_slots(st, fc) == 0, "un seul précepte à la fondation")
	_ok(Faiths.check_precept(st, v, fc, "ethique_travail") != "", "seul le chef de foi choisit")
	_ok(Faiths.check_precept(st, ch, fc, "inconnu") != "", "précepte inconnu refusé")
	_ok(Faiths.check_precept(st, ch, fc, "ethique_travail").contains("25"), "plus de place : il faut 25 fidèles")
	# Palier de 25 fidèles.
	_cap(st, ch).faith[fc] = 30
	_cap(st, ch).population = 30
	Faiths._update_slots(st)
	_ok(Faiths.free_slots(st, fc) == 1, "palier de 25 fidèles : un précepte de plus")
	_ok(Faiths.check_precept(st, ch, fc, "liturgie") != "", "pas deux fois le même précepte")
	var taken := String(Faiths.faith(st, fm)["precepts"][0])
	_ok(Faiths.check_precept(st, ch, fc, taken).contains("déjà pris"), "un précepte n'appartient qu'à une foi dans la galaxie")
	var before := Research.production_bonus(st, ch, "materials")
	_ok(Faiths.check_precept(st, ch, fc, "ethique_travail") == "", "précepte libre accepté")
	Faiths.add_precept(st, fc, "ethique_travail")
	_ok(Research.production_bonus(st, ch, "materials") == before + 8, "Éthique du travail : matériaux +8 %")
	# Un coreligionnaire profite des préceptes.
	var vb := Research.production_bonus(st, v, "materials")
	Faiths.set_state(st, v, fc)
	_ok(Research.production_bonus(st, v, "materials") == vb + 8, "les préceptes s'appliquent à tous les empires de cette foi")
	_cap(st, ch).population = 1
	_cap(st, ch).faith[fc] = 1
	Faiths._update_slots(st)
	_ok(int(Faiths.faith(st, fc)["slots"]) == 2, "les places de précepte ne se reperdent pas")
	# Chef de foi : celui qui a le plus de fidèles (doctrine Élu, par défaut).
	_cap(st, v).faith[fc] = _cap(st, v).population
	Faiths.faith(st, fc)["doctrines"]["chef"] = "elu"
	_ok(Faiths.head(st, fc) == v and Faiths.has_head(st, fc), "chef Élu : l'empire qui compte le plus de fidèles")
	Faiths.faith(st, fc)["doctrines"]["chef"] = "aucun"
	_ok(not Faiths.has_head(st, fc), "doctrine Aucun : pas de vrai chef de foi")
	Faiths.faith(st, fc)["doctrines"]["chef"] = "temporel"
	_ok(Faiths.head(st, fc) == ch, "chef Temporel : le maître du monde saint")


## Le fondateur humain fixe sa foi (nature parmi trois, doctrines, premier précepte), ou le délai tranche.
func _test_choice() -> void:
	var st := _state()
	var v := _id_of(st, "vael")
	var ch := _id_of(st, "choeur")
	var fv := Faiths.reveal(st, v, "relique", -1, [] as Array[Dictionary])
	var f := Faiths.faith(st, fv)
	var offer: Array = f["offer"]
	_ok(offer.size() == 3 and int(f["pending"]) > st.tick, "trois natures proposées, le choix attend le joueur")
	_ok(Faiths.free_slots(st, fv) == 0, "pas de précepte tant que la foi n'est pas fixée")
	var dc := {"chef": "aucun", "regard": "pluraliste", "clerge": "laic", "diffusion": "secrete"}
	_ok(Faiths.check_choose(st, ch, fv, String(offer[0]), dc, "doute_sacre") != "", "seul le fondateur fixe la foi")
	var other := ""
	for n in Faiths.nature_ids():
		if not offer.has(n):
			other = n
	_ok(other == "" or Faiths.check_choose(st, v, fv, other, dc, "doute_sacre") != "", "nature non proposée refusée")
	_ok(Faiths.check_choose(st, v, fv, String(offer[1]), {"chef": "aucun"}, "doute_sacre") != "", "il faut une position sur chaque axe")
	_ok(Faiths.check_choose(st, v, fv, String(offer[1]), dc, "liturgie").contains("déjà pris"), "premier précepte déjà pris refusé")
	_ok(SimCommands.validate(st, SimCommands.faith_choose(v, fv, String(offer[1]), dc, "doute_sacre")) == "", "ordre de choix valide")
	SimCommands.apply(st, SimCommands.faith_choose(v, fv, String(offer[1]), dc, "doute_sacre"))
	f = Faiths.faith(st, fv)
	_ok(String(f["nature"]) == String(offer[1]) and int(f["pending"]) == 0, "nature fixée")
	_ok(Faiths.doctrine(st, fv, "diffusion") == "secrete" and FaithWars.is_secret(st, fv), "doctrine Secrète : culte caché")
	_ok((f["precepts"] as Array) == ["doute_sacre"], "premier précepte fixé")
	_ok(Faiths.check_choose(st, v, fv, String(offer[0]), dc, "charite") != "", "une foi fixée ne se refixe pas")
	# Délai échu : le clergé choisit.
	var st2 := _state()
	var v2 := _id_of(st2, "vael")
	var fv2 := Faiths.reveal(st2, v2, "relique", -1, [] as Array[Dictionary])
	st2.tick = int(Faiths.faith(st2, fv2)["pending"])
	Faiths.monthly(st2, [] as Array[Dictionary])
	var f2 := Faiths.faith(st2, fv2)
	_ok(int(f2["pending"]) == 0 and String(f2["nature"]) == String(f2["offer"][0]) and (f2["precepts"] as Array).size() == 1, "délai échu : choix par défaut")


func _test_state() -> void:
	var st := _state()
	var v := _id_of(st, "vael")
	var ch := _id_of(st, "choeur")
	var mu := _id_of(st, "murmurants")
	var fc := Faiths.founded_by(st, ch)
	var fm := Faiths.founded_by(st, mu)
	var cap := _cap(st, v)
	Faiths.faith(st, fc)["doctrines"]["regard"] = "juste"
	Faiths.faith(st, fm)["doctrines"]["diffusion"] = "missionnaire"
	_ok(Faiths.check_state(st, v, fc).contains("20"), "adopter une foi étrangère : 20 % sur une colonie")
	cap.faith = {fc: cap.population}
	_ok(Faiths.check_state(st, v, fc) == "", "adoption possible")
	Faiths.set_state(st, v, fc)
	var parts := Stability.parts(st, _sid(st, cap))
	_ok(_part(parts, "Changement de foi d'État") == -10, "changement de foi d'État : stabilité -10")
	_ok(_part(parts, "Foi d'État majoritaire") == 5, "foi d'État majoritaire : +5")
	_ok(Faiths.check_state(st, v, Faiths.LAICITE).contains("jours"), "délai de 3 ans entre deux changements")
	st.tick += 1080
	_ok(Faiths.check_state(st, v, Faiths.INCROYANCE) == "", "après le délai, changement possible")
	parts = Stability.parts(st, _sid(st, cap))
	_ok(_part(parts, "Changement de foi d'État") == 0, "le malus de changement s'efface après un an")
	cap.faith = {fm: cap.population}
	parts = Stability.parts(st, _sid(st, cap))
	_ok(_part(parts, "Autre foi majoritaire") == -5, "une autre foi majoritaire : -5 (regard Juste)")
	Faiths.faith(st, fc)["doctrines"]["regard"] = "fondamentaliste"
	_ok(_part(Stability.parts(st, _sid(st, cap)), "Autre foi majoritaire") == -8, "Fondamentaliste : -8")
	_ok(_part(Diplomacy.opinion_parts(st, v, mu), "Autre foi") == -20, "Fondamentaliste : autre foi -20")
	Faiths.faith(st, fc)["doctrines"]["regard"] = "pluraliste"
	_ok(_part(Stability.parts(st, _sid(st, cap)), "Autre foi majoritaire") == -2, "Pluraliste : -2")
	Faiths.faith(st, fc)["doctrines"]["regard"] = "juste"
	# Opinion.
	_ok(_part(Diplomacy.opinion_parts(st, v, ch), "Même foi") == 10, "même foi d'État : opinion +10")
	_ok(_part(Diplomacy.opinion_parts(st, v, mu), "Autre foi") == -10, "autre foi, regard Juste : opinion -10")
	_ok(_part(Diplomacy.opinion_parts(st, v, _id_of(st, "teyl")), "Autre") == 0, "pas d'avis religieux envers un laïque")
	# Incroyance.
	Faiths.set_state(st, v, Faiths.INCROYANCE)
	_ok(Faiths.name_of(st, Faiths.INCROYANCE) == "Incroyance" and _part(Diplomacy.opinion_parts(st, v, ch), "Incroyance") == -5, "l'incroyance, vue par un regard juste : -5")
	# Une conscience collective n'a pas de foi.
	_ok(Faiths.check_state(st, _id_of(st, "khthari"), fc) != "", "la ruche refuse toute foi")


func _test_fervor() -> void:
	var st := _state()
	var ch := _id_of(st, "choeur")
	var fc := Faiths.founded_by(st, ch)
	var cap := _cap(st, ch)
	var d0 := FactionTraits.fervor_delta(st, ch)
	var c := _plant(st, ch, 4, _sid(st, cap), 1)
	var d1 := FactionTraits.fervor_delta(st, ch)
	_ok(d1 == d0, "colonie aux cultes natals : pas de ferveur")
	c.faith = {fc: 4}
	_ok(FactionTraits.fervor_delta(st, ch) > d0, "colonie fidèle : la ferveur monte")
	c.faith = {}
	_ok(FactionTraits.check_sacrifice(st, ch, c.planet_id).contains("foi d'État"), "pas d'offrande sur une colonie infidèle")


func _test_commands() -> void:
	var st := _state()
	var v := _id_of(st, "vael")
	var ch := _id_of(st, "choeur")
	var fc := Faiths.founded_by(st, ch)
	_ok(SimCommands.validate(st, SimCommands.faith_state(v, Faiths.INCROYANCE)) == "", "ordre : adopter l'incroyance")
	SimCommands.apply(st, SimCommands.faith_state(v, Faiths.INCROYANCE))
	_ok(Faiths.state_faith(st, v) == Faiths.INCROYANCE, "ordre appliqué")
	Faiths.faith(st, fc)["slots"] = 2
	_ok(SimCommands.validate(st, SimCommands.faith_precept(v, fc, "ascetisme")) != "", "ordre de précepte refusé hors chef")
	_ok(SimCommands.validate(st, SimCommands.faith_precept(ch, fc, "ascetisme")) == "", "ordre de précepte du chef")
	SimCommands.apply(st, SimCommands.faith_precept(ch, fc, "ascetisme"))
	_ok((Faiths.faith(st, fc)["precepts"] as Array).has("ascetisme"), "précepte ajouté")
	_ok(SimCommands.validate(_state(false), SimCommands.faith_state(v, Faiths.INCROYANCE)) != "", "ordre refusé sans l'option")


func _test_ai() -> void:
	var st := _state(true, "normal")
	var ch := _id_of(st, "choeur")
	var fc := Faiths.founded_by(st, ch)
	var added: Array[Dictionary] = []
	Faiths.faith(st, fc)["slots"] = 2
	Faiths.monthly(st, added)
	_ok((Faiths.faith(st, fc)["precepts"] as Array).size() == 2, "l'IA choisit un précepte à chaque palier")
	var t := _id_of(st, "teyl")
	var tc := _cap(st, t)
	tc.faith = {fc: tc.population}
	Faiths.monthly(st, added)
	_ok(Faiths.state_faith(st, t) == fc, "l'IA adopte la foi de la majorité de son peuple")
	# Quelques années de partie complète : déterministe.
	var a := Simulation.new(_state(true, "normal"))
	var b := Simulation.new(_state(true, "normal"))
	a.advance(720)
	b.advance(720)
	_ok(a.state.checksum() == b.state.checksum(), "deux ans de partie avec religions : déterministe")
	var n := 0
	for pid in a.state.colonies:
		for fid in a.state.colonies[pid].faith:
			n += int(a.state.colonies[pid].faith[fid])
	_ok(n > 0, "des fidèles après deux ans (%d)" % n)


func _test_save() -> void:
	var st := _state()
	var v := _id_of(st, "vael")
	var fv := Faiths.reveal(st, v, "relique", -1, [] as Array[Dictionary])
	Faiths.choose(st, fv, String(Faiths.faith(st, fv)["offer"][0]), {"chef": "temporel", "regard": "fondamentaliste", "clerge": "laic", "diffusion": "peuple_elu"}, "ascetisme")
	st.faiths["prog"][str(_cap(st, v).planet_id)] = {fv: 17}
	var d := st.to_dict()
	_ok(int(d["version"]) == 47, "sauvegarde version 47")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and back.faith_on and Faiths.founded_by(back, v) == fv, "fois relues")
	_ok(back != null and int(_cap(back, v).faith.get(fv, 0)) == int(_cap(st, v).faith.get(fv, 0)), "fidèles des colonies relus")
	_ok(back != null and (Faiths.faith(back, fv)["precepts"] as Array) == ["ascetisme"], "préceptes relus")
	_ok(back != null and Faiths.doctrine(back, fv, "diffusion") == "peuple_elu" and FaithWars.nature(back, fv) == FaithWars.nature(st, fv), "doctrines et nature relues")
	# Une foi du premier lot 2 (dogmes) se relit en préceptes et doctrines.
	var od := st.to_dict()
	var of: Dictionary = od["faiths"]["list"][fv]
	of.erase("precepts")
	of.erase("doctrines")
	of["dogmas"] = ["monachisme", "secret", "pacifisme"]
	var back3 := GameState.from_dict(JSON.parse_string(JSON.stringify(od)))
	_ok(back3 != null and (Faiths.faith(back3, fv)["precepts"] as Array) == ["ascetisme", "pacifisme"] and Faiths.doctrine(back3, fv, "diffusion") == "secrete", "anciens dogmes convertis")
	_ok(back != null and back.checksum() == st.checksum(), "même empreinte après relecture")
	var old := d.duplicate(true)
	old.erase("faiths")
	old["version"] = 42
	var back2 := GameState.from_dict(JSON.parse_string(JSON.stringify(old)))
	_ok(back2 != null and not back2.faith_on, "sauvegarde 42 : sans religions")
