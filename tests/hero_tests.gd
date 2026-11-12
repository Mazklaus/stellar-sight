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
	_ok(int(m["renown"]) == 150, "le seuil est déduit du renom (%d)" % int(m["renown"]))
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
	_ok(int(d["version"]) == 20, "sauvegarde au format 20")
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
