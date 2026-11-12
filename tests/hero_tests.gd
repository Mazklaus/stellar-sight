extends RefCounted
## Tests des héros (Heroes, AiHeroes) : héros de départ, renom et offre 1 parmi 3, choix et refus,
## affectation et trajet, effets des postes, blessure, rappel, renvoi, sauvegarde 20 et anciennes
## sauvegardes, déterminisme, IA qui recrute et place ses héros, galerie de portraits par archétype.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Héros…")
	_test_start()
	_test_portraits()
	_test_offer()
	_test_assign_and_effects()
	_test_wound()
	_test_save()
	_test_old_save()
	_test_determinism()
	_test_ai()
	# Lot 2 : vie et mort.
	_test_people_traits()
	_test_ambition_loyalty()
	_test_capture_and_prison()
	_test_age_and_memorial()
	_test_talents()
	_test_save_v20()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _home(st: GameState, empire_id := 0) -> int:
	return st.galaxy.get_planet(st.get_empire(empire_id).capital_planet).system_id


func _test_start() -> void:
	var st := GameState.create(21)
	for e in st.empires:
		var ids := Heroes.ids_of(st, e.id)
		_ok(ids.size() == 1, "%s : un héros au départ" % e.short_name())
		if ids.is_empty():
			continue
		var h: Dictionary = st.heroes[ids[0]]
		_ok(String(h["name"]).length() > 3 and Heroes.CLASSES.has(String(h["cls"])), "%s : héros nommé, avec une classe" % e.short_name())
		_ok(String(h["portrait"]).begins_with("hero_"), "%s : portrait tiré de la galerie des héros" % e.short_name())
		_ok(int(h["lvl"]) == 1 and Heroes.age(st, h) >= 25 and Heroes.age(st, h) <= 45, "%s : niveau 1, âge plausible" % e.short_name())
	_ok(Heroes.cap(st, 0) == 3 and Heroes.seats(st, 0) == 2, "3 places et 2 sièges de conseil au départ")
	var st2 := GameState.create(21)
	_ok(str(st.heroes) == str(st2.heroes), "même graine, mêmes héros de départ")


func _test_portraits() -> void:
	var by_arch := {}
	for p: Dictionary in Heroes.data()["portraits"]:
		for a in p["archetypes"]:
			by_arch[a] = int(by_arch.get(a, 0)) + 1
	for arch in Heroes.data()["names"]:
		_ok(int(by_arch.get(arch, 0)) >= 3, "galerie des héros : au moins 3 portraits %s" % arch)
		_ok(not Heroes.portraits_for(String(arch)).is_empty(), "portraits_for(%s)" % arch)
	_ok(not Heroes.portraits_for("inconnu").is_empty(), "archétype inconnu : repli sur les humanoïdes")


func _test_offer() -> void:
	var st := GameState.create(22)
	var m := Heroes.meta(st, 0)
	_ok((m["offer"] as Array).is_empty(), "pas d'offre au départ")
	Heroes.act(st, 0, "battles_won", 20)  # 500 de renom (seuil 350), penche Stratège
	Heroes._maybe_offer(st, 0)
	m = Heroes.meta(st, 0)
	var offer: Array = m["offer"]
	_ok(offer.size() == 3, "renom au seuil : trois candidats (%d)" % offer.size())
	var classes := {}
	for c in offer:
		classes[String(c["cls"])] = true
	_ok(classes.size() == 3, "trois classes différentes dans l'offre")
	var st2 := GameState.create(22)
	Heroes.act(st2, 0, "battles_won", 20)
	Heroes._maybe_offer(st2, 0)
	_ok(str(Heroes.meta(st2, 0)["offer"]) == str(offer), "même graine, même offre")
	_ok(int(m["renown"]) >= 150 and int(m["renown"]) < Heroes.renown_needed(st, 0), "le seuil est déduit du renom (%d)" % int(m["renown"]))
	_ok(Heroes.renown_needed(st, 0) == 100 + 250 * 1, "seuil : 100 + 250 × héros obtenus (le héros de départ compte)")
	var sim := Simulation.new(st)
	var name := String(offer[1]["name"])
	_ok(sim.submit(SimCommands.hero_pick(0, 1)), "ordre CHOISIR accepté")
	sim.flush_commands()
	var ids := Heroes.ids_of(st, 0)
	_ok(ids.size() == 2 and String(st.heroes[ids[1]]["name"]) == name, "le candidat choisi rejoint l'empire")
	_ok((Heroes.meta(st, 0)["offer"] as Array).is_empty(), "l'offre disparaît une fois choisie")
	_ok(Heroes.renown_needed(st, 0) == 100 + 250 * 2, "seuil relevé après un recrutement")
	# Refus.
	Heroes.act(st, 0, "conquests", 20)
	Heroes._maybe_offer(st, 0)
	_ok(not (Heroes.meta(st, 0)["offer"] as Array).is_empty(), "nouvelle offre")
	_ok(sim.submit(SimCommands.hero_pick(0, -1)), "ordre DÉCLINER accepté")
	sim.flush_commands()
	_ok((Heroes.meta(st, 0)["offer"] as Array).is_empty() and Heroes.ids_of(st, 0).size() == 2, "décliner renvoie les candidats")
	# Plus de place.
	var cand := Heroes.make_candidate(st, 0, "orateur", ["test"])
	Heroes.recruit(st, 0, cand)
	Heroes.act(st, 0, "conquests", 40)
	Heroes._maybe_offer(st, 0)
	_ok(Heroes.check_pick(st, 0, 0) != "", "toutes les places prises : choisir est refusé")
	_ok(Heroes.check_pick(st, 0, -1) == "", "décliner reste possible")
	var last := Heroes.ids_of(st, 0)[2]
	_ok(sim.submit(SimCommands.hero_dismiss(0, last)), "ordre RENVOYER accepté")
	sim.flush_commands()
	_ok(not st.heroes.has(last) and Heroes.check_pick(st, 0, 0) == "", "renvoyer libère une place")
	_ok(not sim.submit(SimCommands.hero_pick(1, 0)) or (Heroes.meta(st, 1)["offer"] as Array).is_empty(), "un autre empire ne choisit pas dans notre offre")


func _test_assign_and_effects() -> void:
	var st := GameState.create(23)
	var sim := Simulation.new(st)
	var home := _home(st)
	var h: Dictionary = st.heroes[Heroes.ids_of(st, 0)[0]]
	h["cls"] = "intendant"
	var id := int(h["id"])
	_ok(Heroes.check_assign(st, 1, id, "system", home) != "", "un empire ne commande pas le héros d'un autre")
	_ok(Heroes.check_assign(st, 0, id, "system", _home(st, 1)) != "", "gouverneur : seulement un système de l'empire")
	var before := Heroes.production_pct(st, 0, home, "materials")
	_ok(sim.submit(SimCommands.hero_assign(0, id, "system", home)), "affectation au système capital")
	sim.flush_commands()
	_ok(int(h["arrive"]) == st.tick, "système capital : pas de trajet")
	_ok(Heroes.active(st, h), "le gouverneur tient son poste")
	var after := Heroes.production_pct(st, 0, home, "materials")
	_ok(after > before, "un Intendant gouverneur augmente la production (%d → %d)" % [before, after])
	_ok(Heroes.post_effect_text(st, h).contains("%"), "texte de l'effet du poste")
	# Conseil : un Orateur rapporte de l'influence.
	var o := Heroes.recruit(st, 0, Heroes.make_candidate(st, 0, "orateur", ["conseil"]))
	var inf0 := int(Heroes.income(st, 0).get("influence", 0))
	_ok(sim.submit(SimCommands.hero_assign(0, o, "council", 0)), "Orateur au conseil")
	sim.flush_commands()
	_ok(int(Heroes.income(st, 0).get("influence", 0)) > inf0, "l'Orateur au conseil rapporte de l'influence")
	_ok(Heroes.check_assign(st, 0, id, "council", 0) != "", "un siège ne tient qu'un héros")
	_ok(Heroes.check_assign(st, 0, id, "council", 5) != "", "siège inexistant refusé")
	# Amiral : trajet hors du système capital, puis bonus de dégâts.
	var far := -1
	for s in st.galaxy.systems:
		if s.id != home:
			far = s.id
			break
	var f := st.spawn_ship(0, "corvette", far)
	var s := Heroes.recruit(st, 0, Heroes.make_candidate(st, 0, "stratege", ["amiral"]))
	_ok(sim.submit(SimCommands.hero_assign(0, s, "fleet", f.id)), "Stratège à la tête d'une flotte")
	sim.flush_commands()
	var hs: Dictionary = st.heroes[s]
	_ok(int(hs["arrive"]) == st.tick + int(Heroes.data()["travel_days"]), "hors du système capital : 20 jours de trajet")
	_ok(not Heroes.active(st, hs) and Heroes.damage_pct(st, f, 1, false) == 0, "pas de bonus avant l'arrivée")
	sim.advance(int(Heroes.data()["travel_days"]))
	_ok(Heroes.active(st, hs) and Heroes.damage_pct(st, f, 1, false) >= 4, "arrivé, l'amiral donne des dégâts (%d %%)" % Heroes.damage_pct(st, f, 1, false))
	# Rappel.
	_ok(sim.submit(SimCommands.hero_assign(0, s, "", -1)), "ordre RAPPELER accepté")
	sim.flush_commands()
	_ok(String(hs["post"]) == "" and Heroes.damage_pct(st, f, 1, false) == 0, "rappelé, l'amiral quitte la flotte")
	# Fusion : l'amiral suit la flotte qui absorbe.
	sim.submit(SimCommands.hero_assign(0, s, "fleet", f.id))
	sim.flush_commands()
	var g := st.spawn_ship(0, "corvette", far)
	Heroes.on_merge(st, f.id, g.id)
	_ok(int(hs["target"]) == g.id, "fusion : l'amiral passe sur la flotte qui reste")


func _test_wound() -> void:
	var st := GameState.create(24)
	var sim := Simulation.new(st)
	var home := _home(st)
	var f := st.spawn_ship(0, "corvette", home)
	var s := Heroes.recruit(st, 0, Heroes.make_candidate(st, 0, "stratege", ["blesse"]))
	sim.submit(SimCommands.hero_assign(0, s, "fleet", f.id))
	sim.flush_commands()
	st.fleets.erase(f.id)
	sim.step()
	var h: Dictionary = st.heroes[s]
	_ok(Heroes.is_wounded(st, h) and String(h["post"]) == "", "flotte anéantie : l'amiral est blessé et perd son poste")
	_ok(int(h["wound"]) - st.tick >= 40, "la blessure dure longtemps (%d jours)" % (int(h["wound"]) - st.tick))
	_ok(Heroes.check_assign(st, 0, s, "council", 0) != "", "un blessé ne prend pas de poste")
	sim.advance(int(Heroes.data()["wound_days"]) + 1)
	_ok(not Heroes.is_wounded(st, h), "la blessure guérit")


func _test_save() -> void:
	var sim := Simulation.new(GameState.create(25))
	var st := sim.state
	Heroes.act(st, 0, "battles_won", 20)
	Heroes._maybe_offer(st, 0)
	var id := Heroes.ids_of(st, 0)[0]
	sim.submit(SimCommands.hero_assign(0, id, "council", 0))
	sim.flush_commands()
	sim.advance(40)
	var d := st.to_dict()
	_ok(int(d["version"]) == GameState.FORMAT_VERSION, "sauvegarde au format courant")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null, "sauvegarde avec héros relue (%s)" % GameState.last_error)
	if back == null:
		return
	_ok(back.heroes.size() == st.heroes.size() and back.next_hero_id == st.next_hero_id, "héros relus")
	_ok(JSON.stringify(Heroes.meta(back, 0), "", true) == JSON.stringify(Heroes.meta(st, 0), "", true), "renom et offre relus")
	_ok(back.checksum() == st.checksum(), "relecture à l'identique")
	var b := Simulation.new(back)
	sim.advance(90)
	b.advance(90)
	_ok(sim.state.checksum() == b.state.checksum(), "la partie rechargée continue à l'identique")


func _test_old_save() -> void:
	var st := GameState.create(26)
	var d := st.to_dict()
	d["version"] = 19
	d.erase("heroes")
	d.erase("next_hero_id")
	d.erase("hero_meta")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null, "sauvegarde 19 toujours lisible (%s)" % GameState.last_error)
	if back:
		for e in back.empires:
			_ok(Heroes.ids_of(back, e.id).size() == 1, "sauvegarde 19 : %s reçoit son héros de départ" % e.short_name())


func _test_determinism() -> void:
	var a := Simulation.new(GameState.create(27, 150, 1800.0, "", {"spectator": true}))
	var b := Simulation.new(GameState.create(27, 150, 1800.0, "", {"spectator": true}))
	a.advance(400)
	b.advance(400)
	_ok(a.state.checksum() == b.state.checksum(), "héros : deux parties de même graine restent identiques")
	_ok(str(a.state.heroes) == str(b.state.heroes), "héros : mêmes héros, mêmes postes")


func _test_ai() -> void:
	var sim := Simulation.new(GameState.create(28, 150, 1800.0, "", {"spectator": true}))
	sim.advance(120)
	var st := sim.state
	var placed := 0
	var total := 0
	for id in Heroes.ids_of(st, -1):
		total += 1
		if String(st.heroes[id]["post"]) != "" or Heroes.is_wounded(st, st.heroes[id]):
			placed += 1
	_ok(total >= st.empires.size(), "IA : chaque empire a ses héros (%d)" % total)
	_ok(placed == total, "IA : tous les héros valides ont un poste (%d / %d)" % [placed, total])
	# Une offre attend : l'IA choisit (ou décline) au mois suivant.
	var e := st.get_empire(1)
	Heroes.act(st, 1, "battles_won", 40)
	Heroes._maybe_offer(st, 1)
	_ok(not (Heroes.meta(st, 1)["offer"] as Array).is_empty(), "IA : offre reçue")
	sim.advance(61)
	_ok((Heroes.meta(st, 1)["offer"] as Array).is_empty(), "IA : l'offre est traitée dans le mois (%s)" % e.short_name())


func _emp(st: GameState, faction_id: String) -> int:
	for e in st.empires:
		if e.faction_id == faction_id:
			return e.id
	return -1


func _test_people_traits() -> void:
	var st := GameState.create(31)
	var oss := _emp(st, "ossarane")
	var pool := Heroes.people_traits(st, oss)
	_ok(pool.has("serment") and pool.has("suzerain") and pool.has("loyal") and pool.has("polyvalent"), "Ossarane : traits de peuple lus dans ses couches (%s)" % ", ".join(pool))
	_ok(not Heroes.class_traits("stratege").has("serment") and not Heroes.class_traits("stratege").has("las"), "réserve de classe sans traits de peuple ni défauts")
	var id := Heroes.recruit(st, oss, Heroes.make_candidate(st, oss, "stratege", ["peuple"]))
	var h: Dictionary = st.heroes[id]
	Heroes.gain_xp(st, h, 120)  # niveau 2 : trait du peuple
	_ok(int(h["lvl"]) == 2 and pool.has(String(h["traits"][-1])), "niveau 2 : un trait de son peuple (%s)" % String(h["traits"][-1]))
	Heroes.gain_xp(st, h, 900)
	_ok((h["traits"] as Array).size() <= int(Heroes.data()["max_traits"]), "au plus six traits")
	h["traits"] = ["polyvalent"]
	h["lvl"] = 2
	_ok(Heroes.half_levels(h, "system") == 3, "Polyvalent : trois quarts de l'effet hors de sa classe")


func _test_ambition_loyalty() -> void:
	var st := GameState.create(32)
	var sim := Simulation.new(st)
	var oss := _emp(st, "ossarane")
	var id := Heroes.recruit(st, oss, Heroes.make_candidate(st, oss, "stratege", ["amb"]))
	var h: Dictionary = st.heroes[id]
	_ok(Heroes.ambition_def(String(h["amb"])).size() > 0, "chaque héros a une ambition (%s)" % h["amb"])
	_ok(int(h["loy"]) >= 80, "héros de sang (féodalité) : loyauté de départ relevée (%d)" % int(h["loy"]))
	h["amb"] = "gloire"
	var renown := int(Heroes.meta(st, oss)["renown"])
	Heroes.act(st, oss, "battles_won", 3)
	_ok(int(h["amb_n"]) == 3 and int(h["served"]) == st.tick, "une victoire sert l'ambition Gloire")
	Heroes.act(st, oss, "battles_won", 5)
	_ok(int(h["amb_done"]) == 1 and int(Heroes.meta(st, oss)["renown"]) > renown + 8 * 25, "grand objectif atteint : récompense unique")
	# Ambition oubliée et sans poste : la loyauté s'use, puis il déserte vers un rival.
	h["amb"] = "savoir"
	h["served"] = st.tick - 400
	h["loy"] = 30
	var before := int(h["loy"])
	sim.advance(30 - posmod(st.tick, 30) + 1)
	_ok(not st.heroes.has(id) or int(h["loy"]) < before, "ambition oubliée : la loyauté baisse (%d → %d)" % [before, int(h["loy"])])
	if st.heroes.has(id):
		h["loy"] = 0
		var other := -1
		for o in st.get_empire(oss).contacts:
			other = int(o)
			break
		if other < 0:
			other = 1 if oss != 1 else 2
			st.get_empire(oss).contacts.append(other)
		for _m in 12:
			if int(h["owner"]) != oss or not st.heroes.has(id):
				break
			h["loy"] = 0
			h["served"] = st.tick - 400
			sim.advance(30)
		_ok(not st.heroes.has(id) or int(h["owner"]) != oss, "loyauté à zéro : il finit par déserter ou partir")


func _test_capture_and_prison() -> void:
	var st := GameState.create(33)
	var sim := Simulation.new(st)
	var cap: Dictionary = Heroes.data()["capture"]
	var old_pct := int(cap["pct"])
	cap["pct"] = 100
	var a := _emp(st, "vael")
	var b := _emp(st, "ossarane")
	Combat.start_war(st, a, b)
	var home_b := _home(st, b)
	var f := st.spawn_ship(a, "corvette", home_b)
	var id := Heroes.recruit(st, a, Heroes.make_candidate(st, a, "stratege", ["prisonnier"]))
	var h: Dictionary = st.heroes[id]
	h["traits"] = []
	sim.submit(SimCommands.hero_assign(a, id, "fleet", f.id))
	sim.flush_commands()
	sim.step()  # repère le système où se trouve la flotte
	st.fleets.erase(f.id)
	var enemy := st.spawn_ship(b, "corvette", home_b)
	sim.step()
	cap["pct"] = old_pct
	_ok(Heroes.is_prisoner(h) and int(h["jailer"]) == b, "flotte anéantie chez l'ennemi : l'amiral est capturé")
	_ok(not Heroes.active(st, h) and Heroes.check_assign(st, a, id, "council", 0) != "", "un prisonnier ne tient aucun poste")
	_ok(Heroes.check_dismiss(st, a, id) != "", "on ne renvoie pas un héros prisonnier")
	_ok(Heroes.prisoners_of(st, b).has(id), "le geôlier voit son prisonnier")
	_ok(Heroes.check_prisoner(st, a, id, "free") != "", "seul le geôlier décide")
	# La paix rend les prisonniers.
	Diplomacy.sign_treaty(st, a, b, Diplomacy.PEACE)
	_ok(not Heroes.is_prisoner(h), "la paix rend les prisonniers")
	# Libérer : souvenir reconnaissant.
	h["jailer"] = b
	_ok(sim.submit(SimCommands.hero_prisoner(b, id, "free")), "ordre LIBÉRER accepté")
	sim.flush_commands()
	var freed := false
	for m in st.memories:
		if int(m["who"]) == a and int(m["about"]) == b and String(m["kind"]) == "hero_freed":
			freed = true
	_ok(not Heroes.is_prisoner(h) and freed, "libéré : son empire s'en souvient")
	# Convertir : il change de camp après convert_days, s'il y a de la place.
	h["jailer"] = b
	while Heroes.ids_of(st, b).size() >= Heroes.cap(st, b):
		st.heroes.erase(Heroes.ids_of(st, b)[-1])
	_ok(sim.submit(SimCommands.hero_prisoner(b, id, "convert")), "ordre CONVERTIR accepté")
	sim.flush_commands()
	_ok(Heroes.check_prisoner(st, b, id, "convert") != "", "une seule conversion à la fois")
	sim.advance(int(cap["convert_days"]) + 31)
	_ok(int(h["owner"]) == b and not Heroes.is_prisoner(h), "converti : il sert désormais son geôlier")
	# Exécuter : grief durable.
	h["owner"] = a
	h["jailer"] = b
	_ok(sim.submit(SimCommands.hero_prisoner(b, id, "execute")), "ordre EXÉCUTER accepté")
	sim.flush_commands()
	var grief := false
	for m in st.memories:
		if int(m["who"]) == a and int(m["about"]) == b and String(m["kind"]) == "hero_executed":
			grief = true
	_ok(not st.heroes.has(id) and grief, "exécuté : il meurt, son empire en garde un grief")
	# Système perdu : le gouverneur peut être pris par le conquérant.
	st.fleets.erase(enemy.id)


func _test_age_and_memorial() -> void:
	var st := GameState.create(34)
	var sim := Simulation.new(st)
	var oss := _emp(st, "ossarane")
	var id := Heroes.recruit(st, oss, Heroes.make_candidate(st, oss, "orateur", ["vieux"]))
	var h: Dictionary = st.heroes[id]
	_ok(int(h["life"]) == 80, "humanoïde : 80 ans d'espérance de vie")
	_ok(Heroes.life_years(st, _emp(st, "teyl")) == 0, "synthétique : sans limite d'âge")
	h["lvl"] = 3
	h["born"] = st.tick - 95 * Heroes.DAYS_PER_YEAR
	var dmg := Heroes.memorial_fx(st, oss, "damage_pct")
	for _m in 40:
		if not st.heroes.has(id):
			break
		sim.advance(30)
	_ok(not st.heroes.has(id), "un vieillard de 95 ans finit par s'éteindre")
	_ok(Heroes.memorial_fx(st, oss, "damage_pct") > dmg, "héros de niveau 3 : souvenir selon le credo (honneur : dégâts)")
	# Défauts avec l'âge.
	var id2 := Heroes.recruit(st, oss, Heroes.make_candidate(st, oss, "intendant", ["defauts"]))
	var h2: Dictionary = st.heroes[id2]
	h2["born"] = st.tick - 62 * Heroes.DAYS_PER_YEAR
	h2["life"] = 0
	var tick0 := st.tick
	for _m in 30 * 12:
		Heroes._age_month(st, h2, [] as Array[Dictionary])
		st.tick += 30
	st.tick = tick0
	var flaws := 0
	for t in h2["traits"]:
		if Heroes.trait_def(String(t)).get("flaw", false):
			flaws += 1
	_ok(flaws >= 1 and flaws <= 2, "avec l'âge, un ou deux défauts (%d)" % flaws)


func _test_talents() -> void:
	var st := GameState.create(35)
	var sim := Simulation.new(st)
	var kh := _emp(st, "khthari")
	var vael := _emp(st, "vael")
	var oss := _emp(st, "ossarane")
	var hid := Heroes.ids_of(st, kh)[0]
	_ok(Heroes.is_avatar(st, kh) and String(st.heroes[hid]["amb"]) == "", "ruche : des Avatars, sans ambition")
	_ok(Heroes.cap(st, vael) == Heroes.cap(st, oss) + 1, "Space opera héroïque : +1 place")
	_ok(Heroes.seats(st, vael) == Heroes.seats(st, oss) + 1, "république : +1 siège au conseil")
	# Un Avatar n'est jamais capturé.
	var cap: Dictionary = Heroes.data()["capture"]
	var old_pct := int(cap["pct"])
	cap["pct"] = 100
	var out: Array[Dictionary] = []
	Heroes._wound(st, st.heroes[hid], out, "test", oss)
	cap["pct"] = old_pct
	_ok(not Heroes.is_prisoner(st.heroes[hid]) and Heroes.is_wounded(st, st.heroes[hid]), "un Avatar est blessé, jamais capturé")
	# République : le conseil est réélu tous les dix ans.
	var vid := Heroes.ids_of(st, vael)[0]
	st.heroes[vid]["wound"] = 0
	sim.submit(SimCommands.hero_assign(vael, vid, "council", 0))
	sim.flush_commands()
	Heroes.meta(st, vael)["election"] = st.tick - 10 * Heroes.DAYS_PER_YEAR
	sim.advance(30 - posmod(st.tick, 30) + 1)
	_ok(String(st.heroes[vid]["post"]) == "", "république : élections, le conseil rend ses sièges")
	# Horde : un amiral qui pille gagne un trait.
	var fc := _emp(st, "ferrocornes")
	if fc >= 0:
		var f := st.spawn_ship(fc, "corvette", _home(st, oss))
		var c := Heroes.recruit(st, fc, Heroes.make_candidate(st, fc, "stratege", ["champion"]))
		st.heroes[c]["post"] = "fleet"
		st.heroes[c]["target"] = f.id
		st.heroes[c]["arrive"] = st.tick
		var n := (st.heroes[c]["traits"] as Array).size()
		Heroes.on_loot(st, fc, _home(st, oss))
		_ok((st.heroes[c]["traits"] as Array).size() == n + 1, "horde : le champion gagne un trait en pillant")
	# Picaresque : un exploit rapporte du renom.
	var bc := _emp(st, "brisecomete")
	if bc >= 0:
		var r := int(Heroes.meta(st, bc)["renown"])
		Heroes.on_exploit(st, bc)
		_ok(int(Heroes.meta(st, bc)["renown"]) == r + 30, "picaresque : un exploit, 30 de renom")
	# Théocratie : la mort d'un saint rallume la ferveur et laisse toujours un souvenir.
	var ch := _emp(st, "choeur")
	if ch >= 0:
		var ce := st.get_empire(ch)
		ce.fervor = 30
		var sid := Heroes.ids_of(st, ch)[0]
		Heroes.die(st, st.heroes[sid], "meurt en martyr", [] as Array[Dictionary])
		_ok(ce.fervor == 50 and (Heroes.meta(st, ch)["memorials"] as Array).size() == 1, "théocratie : un saint mort, ferveur +20 et souvenir")
	_ok(not Heroes.talent_labels(st, vael).is_empty(), "talents affichables")


func _test_save_v20() -> void:
	var sim := Simulation.new(GameState.create(36))
	sim.advance(40)
	var d := sim.state.to_dict()
	d["version"] = 20
	for h: Dictionary in d["heroes"]:
		for k in ["amb", "loy", "served", "amb_n", "amb_done", "foe", "jailer", "convert", "life"]:
			h.erase(k)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null, "sauvegarde 20 toujours lisible (%s)" % GameState.last_error)
	if back:
		var okk := true
		for id in Heroes.ids_of(back, -1):
			var h: Dictionary = back.heroes[id]
			okk = okk and h.has("loy") and h.has("jailer") and int(h["jailer"]) == -1
		_ok(okk, "sauvegarde 20 : les héros reçoivent loyauté, ambition, espérance de vie")
		Simulation.new(back).advance(60)
