extends RefCounted
## Tests des fouilles et des reliques (Relics, AiRelics) : sites, phases et jets, incidents, reprise
## par un conquérant, effets passifs (et reliques saintes de la Foi), Triomphe, porteurs, vol à la
## prise d'une capitale, Larcin de relique et fausse relique d'un réseau retourné, dons, ventes du
## Profit, trophée de l'Honneur, pillage des hordes, talents de curiosité ; sauvegarde 26 et
## déterminisme. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Fouilles et reliques…")
	_test_setup()
	_test_dig()
	_test_incident_and_conquest()
	_test_effects()
	_test_triumph()
	_test_bearer()
	_test_theft()
	_test_larcin()
	_test_gifts_and_sales()
	_test_trophy_and_pillage()
	_test_curio_talents()
	_test_ai()
	_test_save()
	_test_determinism()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(seed_value := 11, faction := "vael", curios := "normales", ai := "") -> GameState:
	return GameState.create(seed_value, 150, 1800.0, faction, {"ai_level": ai, "curios": curios})


## Donne à l'empire une colonie établie dans le système du premier site, et le lui fait connaître.
func _own_site(st: GameState, empire_id := 0) -> int:
	var keys := st.digs.keys()
	keys.sort()
	var sid := int(keys[0])
	var c := Colony.new()
	c.planet_id = st.galaxy.systems[sid].planet_ids[0]
	c.owner = empire_id
	c.kind = Colony.KIND_COLONY
	c.population = 4
	st.add_colony(c)
	st.get_empire(empire_id).explored[sid] = true
	return sid


func _rich(st: GameState, empire_id := 0) -> void:
	for r in ["energy", "materials", "influence", "food"]:
		st.get_empire(empire_id).resources[r] = 2000


func _test_setup() -> void:
	var none := _new(11, "vael", "aucune")
	_ok(none.digs.is_empty() and none.relics.is_empty(), "sans curiosités : ni fouilles ni reliques")
	var st := _new()
	_ok(st.relics.size() == Relics.ids().size() and Relics.ids().size() >= 24, "%d reliques nommées" % st.relics.size())
	_ok(st.digs.size() == st.galaxy.systems.size() / 30, "un site pour 30 systèmes (%d)" % st.digs.size())
	var far := true
	var relics := {}
	for sid in st.digs:
		relics[String(st.digs[sid]["relic"])] = true
		for e in st.empires:
			if int(FactionTraits.jumps_from(st.galaxy, FactionTraits.capital_system(st, e.id)).get(sid, 999)) < 3:
				far = false
	_ok(far, "les sites sont à trois sauts au moins des capitales")
	_ok(relics.size() == st.digs.size(), "une relique différente par site")


func _test_dig() -> void:
	var sim := Simulation.new(_new())
	var st := sim.state
	var sid := _own_site(st)
	_ok(Relics.check_start(st, 1, sid) != "", "un empire qui ne possède pas le système ne fouille pas")
	_rich(st)
	var before := int(st.get_empire(0).resources["energy"])
	sim.submit(SimCommands.dig_start(0, sid))
	sim.flush_commands()
	var d: Dictionary = st.digs[sid]
	_ok(int(d["by"]) == 0 and int(d["next"]) == st.tick + 90 and int(st.get_empire(0).resources["energy"]) == before - 60, "la fouille commence (60 énergie, 60 matériaux, phases de 90 jours)")
	_ok(Relics.skill(st, 0, sid) == 1 and Relics.success_pct(st, 0, sid) >= 0, "compétence 1 sans gouverneur Intendant")
	Relics.add_fragments(st, 0, 20)
	sim.submit(SimCommands.dig_clue(0, sid))
	sim.flush_commands()
	_ok(int(d["clues"]) == 1 and Relics.fragments(st, 0) == 5, "un indice s'achète 15 fragments")
	# Jets truqués : difficulté très basse, chaque phase réussit.
	d["diff"] = -20
	var rid := String(d["relic"])
	var chapters := int(d["chapters"])
	sim.advance(90 * chapters + 2)
	_ok(int(d["done"]) == 0 and int(st.relics[rid]["owner"]) == 0, "après %d chapitres, la relique est à l'empire" % chapters)
	_ok(Relics.fragments(st, 0) >= int(Relics.data()["digs"]["final_fragments"]), "des fragments à chaque chapitre et à la fin (%d)" % Relics.fragments(st, 0))
	_ok(int(st.get_empire(0).stats.get("collection", 0)) >= 1, "la relique compte dans la collection (Muséum de Cassivel)")
	var told := false
	for c: Dictionary in st.chronicle:
		if String(c["text"]).find(String(Relics.def(rid)["name"])) >= 0:
			told = true
	_ok(told, "la galaxie apprend la découverte")
	_ok(Victory.score(st, 0) >= Relics.rules()["score"], "les reliques comptent au score")


func _test_incident_and_conquest() -> void:
	var sim := Simulation.new(_new())
	var st := sim.state
	var sid := _own_site(st)
	_rich(st)
	sim.submit(SimCommands.dig_start(0, sid))
	sim.flush_commands()
	var d: Dictionary = st.digs[sid]
	d["clues"] = 2
	d["diff"] = 30
	sim.advance(91)
	_ok(int(d["clues"]) == 0 and int(d["ch"]) == 0, "un mauvais jet tourne à l'incident : indices perdus")
	d["diff"] = 6
	d["clues"] = 0
	sim.advance(90)
	_ok(int(d["ch"]) == 0, "un jet moyen ne finit pas le chapitre")
	# Un conquérant reprend la fouille.
	for pid in st.galaxy.systems[sid].planet_ids:
		var c: Colony = st.colonies.get(pid)
		if c != null:
			c.owner = 1
	st.rebuild_ownership()
	sim.advance(1)
	_ok(int(d["by"]) == 1 and int(d["next"]) >= 0, "un conquérant reprend la fouille où elle en est")


func _test_effects() -> void:
	var st := _new()
	var base := Research.fx_int(st, 0, "stability")
	Relics.gain(st, 0, "couronne_aube")
	_ok(Research.fx_int(st, 0, "stability") == base + 4, "Couronne de l'Aube : +4 stabilité")
	var growth := Research.fx_int(st, 0, "growth_pct")
	Relics.gain(st, 0, "graal_vide")
	_ok(Research.fx_int(st, 0, "growth_pct") == growth + 10, "relique sainte : effet normal hors de la Foi")
	var ch := _new(11, "choeur")
	var g2 := Research.fx_int(ch, 0, "growth_pct")
	Relics.gain(ch, 0, "graal_vide")
	_ok(Research.fx_int(ch, 0, "growth_pct") == g2 + 15, "Foi : relique sainte ×1,5")
	_ok(Relics.fx_text({"production_pct": {"energy": 8}, "stability": 4}) != "", "effets lisibles (%s)" % Relics.fx_text({"production_pct": {"energy": 8}, "stability": 4}))


func _test_triumph() -> void:
	var sim := Simulation.new(_new())
	var st := sim.state
	_rich(st)
	Relics.gain(st, 0, "coeur_etoile")
	Relics.gain(st, 0, "lame_veuve")
	Relics.add_fragments(st, 0, 100)
	var split := Relics.triumph_split(st, 0, "coeur_etoile")
	_ok(split[0] + split[1] * 2 == 50 and split[1] == 12, "Triomphe : la moitié payable en fragments (%s)" % str(split))
	var e := st.get_empire(0)
	var inf := int(e.resources["influence"])
	var prod := int(Research.effects(st, 0).get("production_pct", {}).get("energy", 0))
	sim.submit(SimCommands.relic_triumph(0, "coeur_etoile"))
	sim.flush_commands()
	_ok(int(e.resources["influence"]) == inf - split[0], "le Triomphe coûte l'influence annoncée")
	_ok(int(Research.effects(st, 0).get("production_pct", {}).get("energy", 0)) == prod + 30, "Embrasement : +30 % d'énergie pendant le Triomphe")
	_ok(Relics.check_triumph(st, 0, "lame_veuve") != "", "un seul Triomphe à la fois")
	sim.advance(361)
	_ok(int(Research.effects(st, 0).get("production_pct", {}).get("energy", 0)) == prod, "le Triomphe s'achève")
	_ok(Relics.check_triumph(st, 0, "coeur_etoile").begins_with("Triomphe en recharge"), "recharge de 10 ans")
	_ok(Relics.check_triumph(st, 0, "lame_veuve") == "", "une autre relique peut triompher ensuite")
	# Triomphe immédiat : Bal masqué rapporte de l'influence.
	Relics.gain(st, 0, "masque_mille")
	var inf2 := int(e.resources["influence"])
	var added: Array[Dictionary] = []
	Relics.triumph(st, 0, "masque_mille", added)
	_ok(int(e.resources["influence"]) > inf2 - Relics.triumph_cost("masque_mille"), "Bal masqué : l'influence revient")


func _test_bearer() -> void:
	var sim := Simulation.new(_new())
	var st := sim.state
	Relics.gain(st, 0, "os_titan")
	var hid: int = Heroes.ids_of(st, 0)[0]
	_ok(Relics.check_assign(st, 0, "os_titan", hid) == "", "un héros peut porter une relique")
	sim.submit(SimCommands.relic_assign(0, "os_titan", hid))
	sim.flush_commands()
	_ok(Relics.bearer_of(st, hid) == "os_titan" and Relics.in_reliquary(st, 0).is_empty(), "la relique quitte le Reliquaire")
	var xp := int(st.heroes[hid]["xp"])
	sim.advance(31)
	_ok(int(st.heroes[hid]["xp"]) > xp, "le porteur gagne de l'expérience")
	Relics.on_hero_captured(st, st.heroes[hid], 1)
	_ok(int(st.relics["os_titan"]["owner"]) == 1, "un héros capturé perd sa relique au profit du geôlier")


func _test_theft() -> void:
	var st := _new(11, "vael")
	Relics.gain(st, 0, "ancre_monde")
	var hits := {"x": 0, "h": 0}
	for t in 400:
		st.tick = t
		st.relics["ancre_monde"]["owner"] = 0
		var added: Array[Dictionary] = []
		Relics.on_capital_lost(st, 0, 1, added)
		if int(st.relics["ancre_monde"]["owner"]) == 1:
			hits["x"] += 1
	var fe := _new(11, "ferrocornes")
	var horde := -1
	for e in fe.empires:
		if Events.layer_value(fe, e.id, "gouvernement") == "horde":
			horde = e.id
	var victim := 1 if horde != 1 else 2
	for t in 400:
		fe.tick = t
		fe.relics["ancre_monde"]["owner"] = victim
		fe.relics["ancre_monde"]["hero"] = -1
		var added: Array[Dictionary] = []
		Relics.on_capital_lost(fe, victim, horde, added)
		if int(fe.relics["ancre_monde"]["owner"]) == horde:
			hits["h"] += 1
	_ok(hits["x"] > 15 and hits["x"] < 70, "prise de capitale : environ 10 %% de vol (%d sur 400)" % hits["x"])
	_ok(hits["h"] > 60 and hits["h"] < 150, "pour une horde, environ 25 %% (%d sur 400)" % hits["h"])


func _test_larcin() -> void:
	var st := _new(11, "brisecomete")
	Relics.gain(st, 1, "plume_scribe")
	var o := Espionage.op_def("larcin_relique")
	_ok(not o.is_empty() and String(o["family"]) == "larcin", "opération Larcin de relique (famille larcin)")
	var txt := Espionage._apply(st, 0, 1, o)
	_ok(int(st.relics["plume_scribe"]["owner"]) == 0 and txt != "", "le larcin vole une relique du Reliquaire")
	_ok(st.get_empire(0).exploits.has("relique_plume_scribe"), "chaque relique volée est un exploit Picaresque")
	_ok(Espionage.check_op(st, 0, 1, "larcin_relique") != "", "plus rien à voler : opération refusée")
	# Réseau retourné : une fausse relique.
	Relics.gain(st, 1, "harpe_spheres")
	var fake := Relics.give_fake(st, 0, 1)
	_ok(fake == "harpe_spheres" and int(st.relics["harpe_spheres"]["owner"]) == 1 and (Relics.meta(st, 0)["fakes"] as Array).size() == 1,
			"un réseau retourné refile une copie : la vraie reste chez lui")
	var sim := Simulation.new(st)
	sim.advance(int(Relics.rules()["fake_days"]) + 1)
	_ok((Relics.meta(st, 0)["fakes"] as Array).is_empty(), "la copie se révèle au bout d'un an")


func _test_gifts_and_sales() -> void:
	var st := _new(11, "brisecomete")
	st.get_empire(0).contacts.append(1)
	st.get_empire(1).contacts.append(0)
	Relics.gain(st, 0, "semence_eden")
	_ok(Relics.check_gift(st, 0, "semence_eden", 1) == "", "une relique s'offre à un empire rencontré")
	var sim := Simulation.new(st)
	sim.submit(SimCommands.relic_gift(0, "semence_eden", 1))
	sim.flush_commands()
	var mem := false
	for m: Dictionary in st.memories:
		if String(m["kind"]) == "relic_gift" and int(m["who"]) == 1 and int(m["about"]) == 0:
			mem = true
	_ok(int(st.relics["semence_eden"]["owner"]) == 1 and mem, "le don change de mains et laisse un bon souvenir")
	Relics.add_fragments(st, 0, 30)
	var en := int(st.get_empire(0).resources["energy"])
	sim.submit(SimCommands.fragments_sell(0))
	sim.flush_commands()
	_ok(Relics.fragments(st, 0) == 20 and int(st.get_empire(0).resources["energy"]) > en, "le Profit vend ses fragments")
	Relics.gain(st, 0, "graine_noire")
	sim.submit(SimCommands.relic_sell(0, "graine_noire"))
	sim.flush_commands()
	_ok(int(st.relics["graine_noire"]["owner"]) == Relics.MARKET, "une relique vendue part au marché noir")
	_ok(Relics.check_sell_fragments(_new(), 0) != "", "seul le Profit tient boutique")


func _test_trophy_and_pillage() -> void:
	var st := _new(11, "ossarane")
	Combat.start_war(st, 0, 1)
	var b := {"sides": [{"empire": 0, "engaged": {"corvette": 1}, "lost": {}}, {"empire": 1, "engaged": {"corvette": 3}, "lost": {"corvette": 2}}]}
	var added: Array[Dictionary] = []
	Relics.on_battle(st, b, 0, added)
	_ok(Relics.fragments(st, 0) == 2 + int(Relics.rules()["trophy_fragments"]), "Honneur : trophée après une victoire contre plus fort, et fragments d'épaves (%d)" % Relics.fragments(st, 0))
	var v := _new(11, "vael")
	Combat.start_war(v, 0, 1)
	Relics.on_battle(v, b, 0, added)
	_ok(Relics.fragments(v, 0) == 2, "sans Honneur, seulement les épaves")
	# Pillage d'une horde.
	var fe := _new(11, "ferrocornes")
	var horde := 0
	var sid := _own_site(fe, 1)
	_rich(fe, 1)
	var sim := Simulation.new(fe)
	sim.submit(SimCommands.dig_start(1, sid))
	sim.flush_commands()
	fe.digs[sid]["clues"] = 2
	Combat.start_war(fe, horde, 1)
	var f := fe.spawn_ship(horde, "corvette", sid)
	fe.garrisons[sid] = 0
	var guard := 0
	while posmod(fe.tick + 1, 30) != 0 and guard < 40:
		sim.advance(1)
		guard += 1
	var frag := Relics.fragments(fe, horde)
	sim.advance(1)
	_ok(f != null and (Relics.fragments(fe, horde) > frag or fe.battles.has(sid)), "une horde en guerre pille le chantier (ou s'y bat)")


func _test_curio_talents() -> void:
	var st := _new(11, "khthari")
	var pid := -1
	for p in st.curios:
		if String(st.curios[p]["type"]) == "vivante":
			pid = int(p)
			break
	if pid < 0:
		return
	var cap: Colony = st.colonies[st.get_empire(0).capital_planet]
	var pop := cap.population
	var txt := Curios._layer_bonus(st, 0, pid)
	_ok(cap.population == pop + 1 and txt != "", "l'Essaim dévore les curiosités vivantes (+1 population)")
	var mu := _new(11, "murmurants")
	var e0 := mu.get_empire(0)
	var echoes := e0.echoes
	Curios._layer_bonus(mu, 0, mu.curios.keys()[0])
	_ok(e0.echoes > echoes, "un peuple cosmique tire des Échos des curiosités")


func _test_ai() -> void:
	var sim := Simulation.new(_new(23, "vael", "normales", "normal"))
	sim.advance(360 * 6)
	var started := 0
	for sid in sim.state.digs:
		if int(sim.state.digs[sid]["by"]) >= 0:
			started += 1
	var frag := 0
	for k in sim.state.relic_meta:
		frag += int(sim.state.relic_meta[k]["frag"])
	_ok(started > 0, "les IA lancent des fouilles (%d en 6 ans)" % started)
	_ok(frag > 0, "les fragments circulent (%d)" % frag)


func _test_save() -> void:
	var sim := Simulation.new(_new(13))
	var st := sim.state
	var sid := _own_site(st)
	_rich(st)
	sim.submit(SimCommands.dig_start(0, sid))
	sim.flush_commands()
	Relics.gain(st, 0, "horloge_fin")
	Relics.add_fragments(st, 0, 40)
	var added: Array[Dictionary] = []
	Relics.triumph(st, 0, "horloge_fin", added)
	Relics.gain(st, 1, "cloche_rappel")
	Relics.give_fake(st, 0, 1)
	sim.advance(40)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_snapshot())))
	_ok(back != null, "sauvegarde 26 relue")
	if back == null:
		return
	_ok(back.checksum() == st.checksum(), "même empreinte après sauvegarde (fouilles, reliques, Triomphe, copie)")
	_ok(Research.fx_int(back, 0, "building_cost_pct") == Research.fx_int(st, 0, "building_cost_pct"), "le Triomphe en cours agit encore après chargement")
	var a := Simulation.new(st)
	var b := Simulation.new(back)
	a.advance(200)
	b.advance(200)
	_ok(a.state.checksum() == b.state.checksum(), "la partie reprise continue à l'identique")
	var old := st.to_snapshot()
	old["version"] = 25
	old.erase("relics")
	var o := GameState.from_dict(JSON.parse_string(JSON.stringify(old)))
	_ok(o != null and o.relics.is_empty() and o.digs.is_empty(), "une sauvegarde 25 se relit (sans reliques)")


func _test_determinism() -> void:
	var a := Simulation.new(GameState.create(53, 150, 1800.0, "", {"curios": "nombreuses", "events": "frequents"}))
	var b := Simulation.new(GameState.create(53, 150, 1800.0, "", {"curios": "nombreuses", "events": "frequents"}))
	a.advance(1200)
	b.advance(1200)
	_ok(a.state.checksum() == b.state.checksum() and not a.state.digs.is_empty(), "même graine, mêmes fouilles et reliques après 1200 jours")
