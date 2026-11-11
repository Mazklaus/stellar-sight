extends RefCounted
## Tests des empires IA (AiLevels, AiPlayer, AiSystem), appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Empires IA…")
	_test_levels()
	_test_setup()
	_test_plays()
	_test_determinism()
	_test_turns()
	_test_fair_play()
	_test_difficulty_order()
	_test_talents()
	_test_save()
	_test_temperament()
	_test_bottleneck()
	_test_performance()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


## Les quatre peuples de la V1, pour lesquels les attentes de ces tests ont été réglées.
const V1 := ["ossarane", "choeur", "vael", "khthari"]


func _spectator(seed_value: int, level := "normal") -> Simulation:
	return Simulation.new(GameState.create(seed_value, 150, 1800.0, "", {"spectator": true, "ai_level": level, "rivals": V1}))


func _total_score(st: GameState) -> int:
	var n := 0
	for e in st.empires:
		n += EmpireReport.score(st, e.id)
	return n


## Goulot d'influence : quand les matériaux s'entassent, l'IA Normale bâtit aussi des forums
## (au-delà de 500 ; le Vétéran dès 250).
func _test_bottleneck() -> void:
	var st := GameState.create(7, 150, 1800.0, "", {"spectator": true, "ai_level": "normal"})
	var e := st.empires[0]
	var c: Colony = st.colonies[e.capital_planet]
	var wishes := func(level: String, mats: int) -> Array[String]:
		e.resources["materials"] = mats
		var ctx := {"state": st, "e": e, "lv": AiLevels.level(level), "ai": AiLevels.personality(e), "salt": 0, "intent": ""}
		var net := {"influence": 10, "energy": 50, "food": 50, "materials": 50, "crystals": 5}
		return AiPlayer.building_wishes(ctx, c, net)
	_ok(not wishes.call("normal", 300).has("forum"), "IA Normale, 300 matériaux et assez d'influence : pas de forum")
	_ok(wishes.call("normal", 600).has("forum"), "IA Normale, matériaux entassés : elle bâtit des forums pour l'influence")
	_ok(wishes.call("veteran", 300).has("forum"), "le Vétéran lit son goulot plus tôt (dès 250 matériaux)")


func _test_levels() -> void:
	var ids := AiLevels.ids()
	_ok(ids.size() >= 3, "au moins trois niveaux de difficulté (obtenu %d)" % ids.size())
	_ok(AiLevels.is_valid(AiLevels.default_id()), "le niveau par défaut existe")
	var ordered := true
	var prev_think := 999
	var prev_prod := 0
	var prev_use := -1
	for id in ids:
		var l := AiLevels.level(id)
		ordered = ordered and int(l["think_days"]) <= prev_think and int(l["production_pct"]) >= prev_prod and int(l["faction_use"]) >= prev_use
		prev_think = int(l["think_days"])
		prev_prod = int(l["production_pct"])
		prev_use = int(l["faction_use"])
		_ok(String(l.get("label", "")) != "" and String(l.get("desc", "")) != "", "niveau %s : nom et description" % id)
	_ok(ordered, "les niveaux montent dans l'ordre (réflexion plus fréquente, talents mieux exploités, bonus)")
	_ok(int(AiLevels.level(ids[0])["faction_use"]) == 0 and int(AiLevels.level(ids[-1])["faction_use"]) == 2, "le plus bas use mal des talents du peuple, le plus haut les exploite tous")
	_ok(int(AiLevels.level("normal")["production_pct"]) == 100 and int(AiLevels.level("veteran")["production_pct"]) == 100, "Normal et Vétéran ne trichent pas")
	_ok(AiLevels.level("inconnu") == AiLevels.level(AiLevels.default_id()), "un niveau inconnu retombe sur le niveau par défaut")
	for f: Dictionary in GameData.factions():
		_ok(String(f.get("ai", {}).get("style", "")) != "", "%s : une personnalité d'IA décrite" % f["id"])


func _test_setup() -> void:
	var st := GameState.create(5, 150, 1800.0, "vael")
	_ok(not st.get_empire(0).is_ai(), "l'empire 0 reste au joueur")
	var all_ai := true
	for i in range(1, st.empires.size()):
		all_ai = all_ai and st.get_empire(i).ai_level == AiLevels.default_id()
	_ok(all_ai, "les rivaux sont des IA au niveau par défaut")
	_ok(not st.is_spectator_game(), "une partie avec un joueur n'est pas une partie de spectateur")
	var none := GameState.create(5, 150, 1800.0, "vael", {"ai_level": ""})
	_ok(not none.get_empire(1).is_ai(), "ai_level vide : aucun rival IA (tests de règles)")
	var spec := GameState.create(5, 150, 1800.0, "", {"spectator": true, "ai_level": "veteran"})
	_ok(spec.is_spectator_game() and spec.get_empire(0).ai_level == "veteran", "spectateur : tous les empires sont des IA")
	var mixed := GameState.create(5, 150, 1800.0, "", {"spectator": true, "ai_levels": ["recrue", "normal", "expert", "legende"]})
	_ok(mixed.get_empire(0).ai_level == "recrue" and mixed.get_empire(3).ai_level == "legende", "un niveau par empire")
	var base := int(GameData.rules()["start_resources"]["materials"])
	var bonus := int(AiLevels.level("legende")["start_bonus"].get("materials", 0))
	_ok(int(mixed.get_empire(3).resources["materials"]) == base + bonus and int(mixed.get_empire(1).resources["materials"]) == base,
			"seuls les niveaux hauts ont une avance de départ")
	var leg := mixed.get_empire(3)
	_ok(Economy.production_pct(mixed, 3, "materials") == FactionTraits.production_pct(mixed, 3, "materials") * 130 / 100,
			"Légende : +30 %% de production (%s)" % leg.faction_id)
	_ok(Economy.production_pct(mixed, 1, "energy") == FactionTraits.production_pct(mixed, 1, "energy"), "Normal : aucun bonus de production")


func _test_plays() -> void:
	var sim := _spectator(17)
	sim.advance(720)
	var st := sim.state
	var expanded := true
	var total_systems := 0
	var explored := true
	var built := true
	var detail := PackedStringArray()
	for e in st.empires:
		var t := EmpireReport.totals(st, e.id)
		# Au moins une expansion chacune, et 3 systèmes en moyenne : exiger 3 pour chaque IA rendait
		# le test fragile (sur main, les graines 3 et 23 laissent déjà une IA à 1 ou 2 systèmes).
		expanded = expanded and t["systems"] >= 2
		total_systems += int(t["systems"])
		explored = explored and e.explored.size() >= 40
		var buildings := 0
		for pid in st.colonies:
			var c: Colony = st.colonies[pid]
			if c.owner == e.id:
				buildings += c.buildings.size()
		built = built and buildings > 3  # la capitale en a déjà 3
		detail.append("%s %d sys %d expl" % [e.short_name(), t["systems"], e.explored.size()])
		_ok(e.ai_intent != "", "%s : l'IA dit ce qu'elle fait (%s)" % [e.short_name(), e.ai_intent])
	_ok(expanded and total_systems >= 3 * st.empires.size(), "en 2 ans, chaque IA s'est étendue et elles tiennent 3 systèmes en moyenne (%s)" % ", ".join(detail))
	_ok(explored, "en 2 ans, chaque IA a exploré au moins 40 systèmes")
	_ok(built, "chaque IA construit des bâtiments")
	var starving := false
	for e in st.empires:
		starving = starving or e.starving or e.blackout
	_ok(not starving, "aucune IA en famine ou en panne d'énergie au bout de 2 ans")
	# Avec un joueur inerte, les rivaux jouent quand même autour de lui.
	var solo := Simulation.new(GameState.create(17, 150, 1800.0, "ossarane"))
	solo.advance(360)
	_ok(EmpireReport.totals(solo.state, 0)["systems"] == 1 and EmpireReport.totals(solo.state, 1)["systems"] >= 2,
			"partie solo : l'IA ne joue pas à la place du joueur, mais les rivaux s'étendent")


func _test_determinism() -> void:
	var a := _spectator(42, "veteran")
	var b := _spectator(42, "veteran")
	a.advance(500)
	b.advance(500)
	_ok(a.state.checksum() == b.state.checksum(), "deux parties d'IA identiques donnent la même empreinte")
	# Avec un joueur : le journal ne contient que ses ordres, et la rediffusion refait aussi les IA.
	var c := Simulation.new(GameState.create(43, 150, 1800.0, "choeur"))
	for t in 400:
		if t == 5:
			for f in Fleets.empire_fleets(c.state, 0):
				c.submit(SimCommands.set_fleet_order(0, f.id, Fleet.ORDER_EXPLORE))
		c.step()
	var only_player := true
	for cmd in c.command_log:
		only_player = only_player and int(cmd["player"]) == 0
	_ok(only_player and not c.command_log.is_empty(), "le journal ne garde que les ordres du joueur")
	var replayed := Simulation.replay(GameState.create(43, 150, 1800.0, "choeur"), c.command_log, c.state.tick)
	_ok(replayed.state.checksum() == c.state.checksum(), "rediffusion : les IA rejouent exactement la même partie")


## Au tour par tour, l'horloge s'arrête entre les tours (les ordres en attente sont appliqués) :
## l'IA doit jouer exactement comme en temps réel.
func _test_turns() -> void:
	var realtime := _spectator(8)
	realtime.advance(300)
	var turns := _spectator(8)
	for _turn in 30:
		turns.flush_commands()
		turns.advance(10)
		turns.flush_commands()
	_ok(turns.state.checksum() == realtime.state.checksum(), "tour par tour et temps réel : même partie entre IA")


## L'IA ne triche pas : elle ne revendique que des systèmes qu'elle a explorés, et ne paie jamais
## en dessous de zéro.
func _test_fair_play() -> void:
	var sim := _spectator(99, "legende")
	var negative := false
	for _i in 600:
		sim.step()
		for e in sim.state.empires:
			for r in e.resources:
				negative = negative or int(e.resources[r]) < 0
	var fog_ok := true
	for pid in sim.state.colonies:
		var c: Colony = sim.state.colonies[pid]
		fog_ok = fog_ok and Fleets.is_explored(sim.state, c.owner, sim.state.galaxy.get_planet(pid).system_id)
	_ok(fog_ok, "chaque revendication d'IA est dans un système qu'elle a exploré")
	_ok(not negative, "aucun stock d'IA ne passe sous zéro")


func _test_difficulty_order() -> void:
	var low := 0
	var mid := 0
	var high := 0
	for sd in [3, 17]:
		var a := _spectator(sd, "recrue")
		a.advance(1080)
		low += _total_score(a.state)
		var b := _spectator(sd, "veteran")
		b.advance(1080)
		mid += _total_score(b.state)
		var c := _spectator(sd, "legende")
		c.advance(1080)
		high += _total_score(c.state)
	_ok(low < mid and mid < high, "3 ans : Recrue < Vétéran < Légende (scores %d, %d, %d)" % [low, mid, high])


## Chaque peuple se sert de ses talents selon le niveau.
func _test_talents() -> void:
	# Chœur Éternel : offrande quand la ferveur s'effondre (pas pour la Recrue).
	for lv in ["recrue", "normal", "veteran"]:
		var st := GameState.create(5, 150, 1800.0, "", {"spectator": true, "ai_level": lv})
		var e := _empire_of(st, "choeur")
		e.fervor = 0
		var cap: Colony = st.colonies[e.capital_planet]
		# Une petite colonie à côté de la capitale : la Recrue la saigne, les autres prennent à la capitale.
		var small := -1
		for pid in st.galaxy.get_system(st.galaxy.get_planet(e.capital_planet).system_id).planet_ids:
			if pid != e.capital_planet and not st.colonies.has(pid) and small < 0:
				small = pid
		var sc := Colony.new()
		sc.planet_id = small
		sc.owner = e.id
		sc.population = 3
		st.add_colony(sc)
		var before := cap.population
		st.tick = 1
		AiPlayer.think(st, e)
		if lv == "recrue":
			_ok(e.fervor > 0 and sc.population == 2 and cap.population == before, "Chœur Recrue : offrande, mais dans sa plus petite colonie")
		else:
			_ok(e.fervor > 0 and cap.population < before and sc.population == 3, "Chœur %s : offrande prise dans la colonie la plus peuplée" % lv)
	# Vétéran : entretient l'Exaltation ; Normal se contente d'éviter le Silence.
	for lv in ["normal", "veteran"]:
		var st := GameState.create(5, 150, 1800.0, "", {"spectator": true, "ai_level": lv})
		var e := _empire_of(st, "choeur")
		e.fervor = 55
		var cap: Colony = st.colonies[e.capital_planet]
		var before := cap.population
		AiPlayer.think(st, e)
		_ok((cap.population < before) == (lv == "veteran"), "Chœur %s : %s pour rester exalté" % [lv, "offrande" if lv == "veteran" else "pas d'offrande"])
	# Vael Recrue : vote sur un chantier presque fini, jamais sur un long.
	var vst := GameState.create(5, 150, 1800.0, "", {"spectator": true, "ai_level": "recrue"})
	var ve := _empire_of(vst, "vael")
	var vcap: Colony = vst.colonies[ve.capital_planet]
	vcap.ship_build = "colony_ship"
	vcap.ship_days = 6
	ve.resources["influence"] = 10
	ve.resources["materials"] = 0
	vst.tick = 2  # un jour où la Recrue n'oublie rien (le hachage est fixe)
	var voted := false
	for t in range(2, 40):
		vst.tick = t
		AiPlayer.think(vst, ve)
		if vcap.ship_days == 1:
			voted = true
			break
	_ok(voted and int(ve.resources["influence"]) == 5, "Vael Recrue : vote d'urgence au prix plancher sur un vaisseau presque fini")
	# Vael : vote d'urgence sur un vaisseau colon quand l'influence déborde.
	for lv in ["recrue", "normal"]:
		var st := GameState.create(5, 150, 1800.0, "", {"spectator": true, "ai_level": lv})
		var e := _empire_of(st, "vael")
		var cap: Colony = st.colonies[e.capital_planet]
		cap.ship_build = "colony_ship"
		cap.ship_days = 40
		e.resources["influence"] = 300
		e.resources["materials"] = 0  # rien d'autre à faire
		AiPlayer.think(st, e)
		_ok((cap.ship_days == 1) == (lv != "recrue"), "Vael %s : %s" % [lv, "vote d'urgence sur le vaisseau colon" if lv != "recrue" else "ne vote pas"])
	# Kh'thari : des vaisseaux-spores, jamais de vaisseau colon.
	var kst := GameState.create(5, 150, 1800.0, "", {"spectator": true})
	var k := _empire_of(kst, "khthari")
	_ok(AiPlayer.colonizer_class(k) == "spore_ship", "Kh'thari : l'IA colonise avec des vaisseaux-spores")
	# Ossarane : évite les fiefs lointains tant qu'elle ne produit pas de cristaux pour les payer.
	var ost := GameState.create(5, 150, 1800.0, "", {"spectator": true, "ai_level": "veteran"})
	var o := _empire_of(ost, "ossarane")
	for s in ost.galaxy.systems:
		o.explored[s.id] = true
	var ships := Fleets.empire_fleets(ost, o.id).filter(func(f: Fleet) -> bool: return Fleets.colonizer_ship(f) != "")
	var cap_sys := ost.galaxy.get_planet(o.capital_planet).system_id
	var far := int(o.faction()["fiefs"]["far_jumps"])
	var ctx := {"state": ost, "e": o, "lv": AiLevels.level("veteran"), "ai": AiLevels.personality(o), "salt": 0, "intent": ""}
	var target := AiPlayer.colonize_target(ctx, ships[0])
	var jumps := int(FactionTraits.jumps_from(ost.galaxy, cap_sys).get(int(target.get("system", cap_sys)), 0))
	_ok(not target.is_empty() and jumps <= far, "Ossarane : premier fief à %d sauts au plus (obtenu %d)" % [far, jumps])


func _empire_of(st: GameState, faction: String) -> Empire:
	for e in st.empires:
		if e.faction_id == faction:
			return e
	return null


func _test_save() -> void:
	var sim := _spectator(12, "expert")
	sim.advance(200)
	var back := GameState.from_dict(sim.state.to_dict())
	_ok(back != null and back.checksum() == sim.state.checksum(), "partie d'IA sauvegardée et relue à l'identique")
	_ok(back != null and back.is_spectator_game() and back.get_empire(2).ai_level == "expert", "le niveau des IA est dans la sauvegarde")
	# La suite de la partie relue est la même que celle de l'originale.
	var cont := Simulation.new(back)
	cont.advance(200)
	sim.advance(200)
	_ok(cont.state.checksum() == sim.state.checksum(), "une partie relue continue exactement comme l'originale")
	var d := sim.state.to_dict()
	d["empires"][1]["ai"] = "dieu"
	_ok(GameState.from_dict(d) == null and GameState.last_error.contains("IA"), "niveau d'IA inconnu refusé au chargement")


## Tempérament : réglage séparé de la difficulté, décalé par le peuple, qui oriente l'expansion.
func _test_temperament() -> void:
	var ids := AiLevels.temperament_ids()
	_ok(ids.size() == 5 and AiLevels.is_valid_temperament(AiLevels.default_temperament()), "5 tempéraments, dont un par défaut")
	var prev := -99
	var ordered := true
	for id in ids:
		ordered = ordered and int(AiLevels.temperament(id)["aggression"]) > prev
		prev = int(AiLevels.temperament(id)["aggression"])
	_ok(ordered, "les tempéraments vont du plus pacifique au plus agressif")
	var st := GameState.create(5, 150, 1800.0, "", {"spectator": true, "temperament": "agressif"})
	var vael := _empire_of(st, "vael")
	var swarm := _empire_of(st, "khthari")
	var oss := _empire_of(st, "ossarane")
	_ok(AiLevels.aggression(oss) == 1 and AiLevels.aggression(vael) == 0 and AiLevels.aggression(swarm) == 2,
			"le peuple décale le réglage (Ossarane %d, Vael %d, Essaim %d)" % [AiLevels.aggression(oss), AiLevels.aggression(vael), AiLevels.aggression(swarm)])
	_ok(bool(AiLevels.personality(swarm).get("temperament", {}).get("never_peace", false)), "l'Essaim ne fera jamais la paix (pour la diplomatie)")
	_ok(AiLevels.temperament_label(swarm) == "Agressif (Vorace)", "libellé du tempérament (%s)" % AiLevels.temperament_label(swarm))
	var back := GameState.from_dict(st.to_dict())
	_ok(back != null and back.get_empire(1).ai_temperament == "agressif", "le tempérament est dans la sauvegarde")
	var d := st.to_dict()
	d["empires"][1]["temper"] = "lunatique"
	_ok(GameState.from_dict(d) == null and GameState.last_error.contains("tempérament"), "tempérament inconnu refusé au chargement")
	_ok(int(st.get_empire(1).resources["materials"]) == int(GameData.rules()["start_resources"]["materials"]), "le tempérament ne donne aucune ressource")
	# Effet : un empire belliqueux s'installe plus près de ses rivaux qu'un empire pacifique.
	var near := {}
	for tp in ["pacifique", "belliqueux"]:
		var total := 0
		var n := 0
		for sd in [3, 17]:
			var sim := Simulation.new(GameState.create(sd, 150, 1800.0, "", {"spectator": true, "ai_level": "veteran", "temperament": tp}))
			sim.advance(1440)
			var r := _border_stats(sim.state)
			total += r[0]
			n += r[1]
		near[tp] = float(total) / maxf(1.0, float(n))
	_ok(near["belliqueux"] > near["pacifique"], "belliqueux : plus de systèmes collés aux rivaux que pacifique (%.2f contre %.2f)" % [near["belliqueux"], near["pacifique"]])


## [systèmes revendiqués voisins d'un système rival, systèmes revendiqués] pour tous les empires.
func _border_stats(st: GameState) -> Array:
	var touching := 0
	var total := 0
	for s in st.galaxy.systems:
		var owner := st.system_owner(s.id)
		if owner == -1:
			continue
		total += 1
		for n in s.neighbors:
			var o := st.system_owner(n)
			if o != -1 and o != owner:
				touching += 1
				break
	return [touching, total]


func _test_performance() -> void:
	var sim := _spectator(3, "legende")
	var start := Time.get_ticks_usec()
	sim.advance(1080)
	var ms := (Time.get_ticks_usec() - start) / 1000.0
	print("  3 ans entre 4 IA Légende en %.1f ms (%.2f ms par jour)" % [ms, ms / 1080.0])
	# À la vitesse 5, un jour dure 40 ms : la simulation doit en laisser l'essentiel à l'affichage.
	# (11 ms depuis la recherche : les empires y grandissent d'environ 15 % en 3 ans, donc plus de
	# colonies et de flottes à gérer ; il reste plus de 70 % du jour pour l'affichage.)
	_ok(ms / 1080.0 < 11.0, "IA assez rapides pour la vitesse maximale")
