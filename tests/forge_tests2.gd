class_name ForgeTests2
extends RefCounted
## Forge des mondes, lot 2 : coquille, monde creux, planète sur mesure et commandes, démantèlement et
## levage, évacuation, mondes intouchables, Brise-monde, Grand Vide, Convention des mondes et Forge
## commune, réputation, sabotage, conquête d'un chantier, IA.

static var _check: Callable


static func run(check: Callable) -> void:
	_check = check
	print("  - shell / hollow")
	_test_shell()
	print("  - custom / order")
	_test_custom()
	print("  - dismantle")
	_test_dismantle()
	print("  - evacuate")
	_test_evacuate()
	print("  - untouchable / void")
	_test_untouchable()
	print("  - bridges")
	_test_bridges()
	print("  - war / spy")
	_test_war()
	print("  - ai")
	_test_ai()


static func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func _setup(faction := "ossarane", mode := "complete") -> GameState:
	var st := ForgeTests.new_game(mode, "aucun", faction)
	ForgeTests.all_techs(st, 0)
	MegasTests.rich(st, 0)
	MegasTests.architect(st, 0, ForgeTests.home_sys(st, 0))
	return st


static func _test_shell() -> void:
	var st := _setup("teyl")
	var sid := ForgeTests.home_sys(st, 0)
	var pid := ForgeTests.body(st, sid, "toxic", 3)
	var why := ForgeTests.cmd(st, 0, "start", {"op": "coquille", "s": sid, "p": pid})
	_ok(why == "", "coquille lancée (%s)" % why)
	ForgeTests.finish(st, ForgeTests.last_job(st))
	_ok(st.galaxy.get_planet(pid).type == "coquille" and int(GameData.planet_type("coquille").get("base_hab", 0)) == 80, "monde-coquille habitable à 80 %")
	_ok(int(WorldForge.income(st, 0)["gross"].get("knowledge", 0)) == 4, "Teyl : coques pensantes, 4 Savoir")
	why = ForgeTests.cmd(st, 0, "start", {"op": "creuser", "s": sid, "p": pid})
	_ok(why == "", "monde creux lancé (%s)" % why)
	ForgeTests.finish(st, ForgeTests.last_job(st))
	_ok(st.galaxy.get_planet(pid).type == "creux" and st.galaxy.get_planet(pid).size == 5, "monde creux : +2 tailles (5)")
	# Brisé, le monde creux sauve la moitié de ses habitants (prop. 20).
	var c := Colony.new()
	c.planet_id = pid
	c.owner = 0
	c.population = 6
	st.colonies[pid] = c
	st.rebuild_ownership()
	var added: Array[Dictionary] = []
	WorldForge.on_world_broken(st, 1, pid, added)
	var fled := false
	for e in added:
		if String(e["text"]).contains("creux"):
			fled = true
	_ok(fled and not st.colonies.has(pid), "monde creux brisé : la moitié fuit par les galeries")
	_ok(WorldForge.sub(st, "debris").has(str(pid)) and WorldForge.mass(st, 1) == WorldForge.r_int("debris_mass", 20), "débris et Masse pour le tireur")


static func _test_custom() -> void:
	var st := _setup()
	var sid := ForgeTests.home_sys(st, 0)
	_ok(ForgeTests.cmd(st, 0, "start", {"op": "sur_mesure", "s": sid, "p": -1, "a": "ocean"}).contains("Masse"), "il faut 60 Masse")
	WorldForge.add_mass(st, 0, 200)
	var n := st.galaxy.planets.size()
	var why := ForgeTests.cmd(st, 0, "start", {"op": "sur_mesure", "s": sid, "p": -1, "a": "ocean"})
	_ok(why == "" or why.contains("orbite"), "planète sur mesure lancée (%s)" % why)
	if why == "":
		_ok(WorldForge.mass(st, 0) == 140, "60 Masse consommées")
		ForgeTests.finish(st, ForgeTests.last_job(st))
		_ok(st.galaxy.planets.size() == n + 1 and st.galaxy.planets[n].type == "ocean" and st.galaxy.planets[n].size == 3, "un monde océan de taille 3")
		_ok(String(WorldForge.world(st, n).get("k", "")) == "custom", "compté comme planète sur mesure")
	for i in 3:
		WorldForge.sub(st, "worlds")["9%d" % i] = {"k": "custom", "o": 0}
	_ok(WorldForge.site_reason(st, 0, "sur_mesure", sid, -1, "ocean").contains("limite"), "trois par empire au plus")
	# Commande (prop. 13) : l'empire 1 commande à l'empire 0.
	var st2 := _setup("vael")
	var b := 1
	var bs := ForgeTests.home_sys(st2, b)
	MegasTests.rich(st2, b)
	WorldForge.add_mass(st2, b, 100)
	for i in 5:
		Diplomacy.remember(st2, 0, b, "world_ordered")
	_ok(WorldForgeWorld.sellers(st2, b).has(0), "l'empire 0 vend des planètes")
	var price := WorldForgeWorld.order_price(st2, 0)
	_ok(int(price.get("energy", 0)) == 450, "Vael : commande à 450 énergie")
	var e0 := int(st2.get_empire(0).resources["energy"])
	var c := SimCommands.forge_act(b, "order", {"seller": 0, "s": bs, "a": "desert"})
	var w2 := SimCommands.validate(st2, c)
	if w2 == "":
		SimCommands.apply(st2, c)
	_ok(w2 == "" or w2.contains("orbite"), "commande passée (%s)" % w2)
	if w2 == "":
		_ok(int(st2.get_empire(0).resources["energy"]) == e0 + 450, "le vendeur est payé")
		var id := ForgeTests.last_job(st2)
		var n2 := st2.galaxy.planets.size()
		ForgeTests.finish(st2, id)
		_ok(st2.galaxy.planets.size() == n2 + 1 and WorldForge.holder(st2, n2) == b or int(WorldForge.world(st2, n2).get("o", -1)) == b, "la planète est à l'acheteur")
		_ok(WorldForge.stat(st2, 0, "orders") == 1, "commande comptée chez le vendeur")


static func _test_dismantle() -> void:
	var st := _setup("brisecomete")
	var sid := ForgeTests.home_sys(st, 0)
	var pid := ForgeTests.body(st, sid, "barren", 2)
	var why := ForgeTests.cmd(st, 0, "start", {"op": "demanteler", "s": sid, "p": pid})
	_ok(why == "", "démantèlement lancé (%s)" % why)
	var id := ForgeTests.last_job(st)
	_ok(int(WorldForge.get_job(st, id)["w"]) == 900 + 270 * 2, "3 à 6 ans selon la taille (taille 2 : 1440 jours)")
	var inc := WorldForge.income(st, 0)
	_ok(int(inc["gross"].get("materials", 0)) == 20, "matériaux chaque mois (10 par taille)")
	var added: Array[Dictionary] = []
	WorldForgeBridges.monthly(st, added)
	_ok(WorldForge.mass(st, 0) == 4 * 150 / 100, "Masse du mois, +50 % (Brisecomète)")
	ForgeTests.finish(st, id)
	var p := st.galaxy.get_planet(pid)
	_ok(p.type == "asteroids" and p.size == 1, "la planète devient une ceinture")
	_ok(WorldForge.stat(st, 0, "dism") == 1 and WorldForge.kardashev_count(st, 0) == 1, "monde défait compté (Kardashev)")
	ForgeTests.cmd(st, 0, "start", {"op": "demanteler", "s": sid, "p": pid})
	ForgeTests.finish(st, ForgeTests.last_job(st))
	_ok(not st.galaxy.systems[sid].planet_ids.has(pid) and WorldForge.is_gone(st, pid), "une ceinture démantelée disparaît")
	var d := st.to_dict()
	var back := GameState.from_dict(d)
	_ok(back != null and not back.galaxy.systems[sid].planet_ids.has(pid), "relu : le corps a disparu")
	# Levage d'une géante (prop. 17) : une taille de moins par an, énergie chaque mois.
	var gp := ForgeTests.body(st, sid, "gas_giant", 4)
	ForgeTests.cmd(st, 0, "start", {"op": "demanteler", "s": sid, "p": gp})
	var gid := ForgeTests.last_job(st)
	_ok(int(WorldForge.income(st, 0)["gross"].get("energy", 0)) >= 60, "levage : énergie chaque mois")
	ForgeTests.run_days(st, 360)
	_ok(st.galaxy.get_planet(gp).size == 3, "la géante perd une taille par an")
	WorldForge.jobs(st).erase(str(gid))
	# Sans démantèlement : refusé.
	var sd := _setup("ossarane", "sans_demantelement")
	var s2 := ForgeTests.home_sys(sd, 0)
	var p2 := ForgeTests.body(sd, s2, "barren", 2)
	_ok(WorldForge.site_reason(sd, 0, "demanteler", s2, p2).contains("pas en jeu"), "Sans démantèlement : refusé")
	# La capitale, jamais.
	_ok(WorldForge.site_reason(st, 0, "demanteler", sid, st.get_empire(0).capital_planet).contains("capitale"), "jamais la capitale")


static func _test_evacuate() -> void:
	var st := _setup()
	var sid := ForgeTests.home_sys(st, 0)
	var pid := ForgeTests.body(st, sid, "continental", 3)
	var c := Colony.new()
	c.planet_id = pid
	c.owner = 0
	c.population = 8
	st.colonies[pid] = c
	st.rebuild_ownership()
	_ok(WorldForge.site_reason(st, 0, "demanteler", sid, pid).contains("évacuez"), "un monde peuplé s'évacue d'abord")
	var why := ForgeTests.cmd(st, 0, "start", {"op": "evacuer", "s": sid, "p": pid})
	_ok(why == "", "évacuation lancée sans architecte (%s)" % why)
	var id := ForgeTests.last_job(st)
	_ok(int(WorldForge.get_job(st, id)["w"]) == 360, "un an")
	var cap: Colony = st.colonies[st.get_empire(0).capital_planet]
	var before := cap.population
	ForgeTests.finish(st, id)
	_ok(not st.colonies.has(pid), "le monde est vide")
	var relog := false
	for ch in st.chronicle:
		if String(ch["text"]).contains("relogés"):
			relog = true
	_ok(relog and cap.population >= before, "les habitants partent ailleurs")
	_ok(WorldForge.site_reason(st, 0, "demanteler", sid, pid) == "", "ensuite, il peut être démantelé")
	# Kh'thari : digestion.
	var kh := _setup("khthari")
	var ks := ForgeTests.home_sys(kh, 0)
	var kp := ForgeTests.body(kh, ks, "barren", 2)
	var kc := Colony.new()
	kc.planet_id = kp
	kc.owner = 0
	kc.population = 4
	kh.colonies[kp] = kc
	kh.rebuild_ownership()
	_ok(WorldForge.site_reason(kh, 0, "demanteler", ks, kp) == "", "Kh'thari : démantèlement d'un monde peuplé")
	var food := int(kh.get_empire(0).resources["food"])
	ForgeTests.cmd(kh, 0, "start", {"op": "demanteler", "s": ks, "p": kp})
	_ok(int(kh.get_empire(0).resources["food"]) == food + 4 * 25 and not kh.colonies.has(kp), "la population est digérée en nourriture")


static func _test_untouchable() -> void:
	var st := _setup()
	var sid := ForgeTests.home_sys(st, 0)
	var pid := ForgeTests.body(st, sid, "gaia", 3)
	var why := WorldForgeBridges.untouchable(st, 0, pid)
	_ok(why.has("un monde-jardin"), "un monde-jardin est intouchable")
	var op1 := Diplomacy.opinion(st, 1, 0)
	ForgeTests.cmd(st, 0, "start", {"op": "demanteler", "s": sid, "p": pid})
	_ok(Diplomacy.opinion(st, 1, 0) < op1, "indignation : les autres s'en souviennent")
	# Grand Vide : un système dont on démantèle tout.
	var st2 := _setup()
	var vs := -1
	for s in st2.galaxy.systems:
		if s.planet_ids.size() == 1 and st2.system_owner(s.id) < 0 and not WorldForge.has_habitable(st2, s.id):
			vs = s.id
			break
	if vs < 0:
		_ok(true, "pas de système à un corps (Grand Vide non testé)")
		return
	var vp: int = st2.galaxy.systems[vs].planet_ids[0]
	st2.override_planet(vp, {"type": "asteroids", "size": 1})
	var j := {"id": 99, "op": "demanteler", "o": 0, "s": vs, "p": vp, "w": 0, "tot": 1, "a": "", "for": -1, "b": 0}
	var added: Array[Dictionary] = []
	WorldForgeBridges.dismantle_done(st2, j, added)
	_ok(WorldForge.sub(st2, "void").has(str(vs)) and WorldForge.stat(st2, 0, "void") == 1, "Le Grand Vide : il ne reste que l'étoile")
	_ok(WorldForge.mega_cost_pct(st2, "sphere_dyson", vs) == -25, "Sphère de Dyson 25 % moins chère")
	_ok(WorldForgeBridges.deed_value(st2, 0, "forge_void") == 1, "haut fait « Le Grand Vide »")


static func _test_bridges() -> void:
	# Convention des mondes : interdits pour les membres de l'Amphictyonie.
	var st := _setup()
	_ok(Amphictyony.family_available(st, "mondes") or not st.amph_on, "famille « Mondes » disponible avec la Forge complète")
	var sd := _setup("ossarane", "sans_demantelement")
	_ok(not Amphictyony.family_available(sd, "mondes"), "sans démantèlement : pas de Convention des mondes")
	# Réputation (prop. 31) : voisins d'un monde habitable défait.
	var st2 := _setup()
	var sid := ForgeTests.home_sys(st2, 0)
	var pid := ForgeTests.body(st2, sid, "desert", 2)
	var mem0 := Diplomacy.opinion(st2, 1, 0)
	ForgeTests.cmd(st2, 0, "start", {"op": "demanteler", "s": sid, "p": pid})
	_ok(Diplomacy.opinion(st2, 1, 0) <= mem0, "un monde habitable défait : les voisins s'en souviennent")
	# Forge commune du Koinon : part de la Masse.
	_ok(WorldForge.r_int("koinon_share_pct") == 25, "Forge commune : 25 % de la Masse aux alliés")
	# Grande Braderie (prop. 42).
	st2.forge["total_dism"] = 9
	var added: Array[Dictionary] = []
	var vp := ForgeTests.body(st2, sid, "asteroids", 1)
	WorldForgeBridges.dismantle_done(st2, {"id": 98, "op": "demanteler", "o": 0, "s": sid, "p": vp, "w": 0, "tot": 1, "a": "", "for": -1, "b": 0}, added)
	_ok(WorldForge.trend_pct(st2, "materials") == -30 and Goods.trend_pct(st2, "materials") <= -30, "la Grande Braderie fait chuter les matériaux")


static func _test_war() -> void:
	var st := _setup()
	var sid := ForgeTests.home_sys(st, 0)
	var pid := ForgeTests.body(st, sid, "asteroids", 1)
	ForgeTests.cmd(st, 0, "start", {"op": "agglomerer", "s": sid, "p": pid})
	var id := ForgeTests.last_job(st)
	# Sabotage (prop. 32).
	_ok(WorldForgeBridges.spy_check(st, 1, 0, "breche_monde") == "", "sabotage possible : il a un chantier")
	var w := int(WorldForge.get_job(st, id)["w"])
	var txt := WorldForgeBridges.spy_apply(st, 1, 0, {"id": "breche_monde"})
	_ok(int(WorldForge.get_job(st, id)["w"]) == w + 120 and txt != "", "Brèche : 120 jours de retard")
	_ok(WorldForgeBridges.spy_check(st, 1, 2, "breche_monde") != "", "rien à saboter chez qui n'a rien")
	# Conquête (prop. 33) : le chantier suit le maître du système.
	var j := WorldForge.get_job(st, id)
	j["o"] = 1
	j["b"] = 1
	var added: Array[Dictionary] = []
	WorldForge._sync_owner(st, j, added)
	_ok(int(j["o"]) == 0, "un chantier suit le maître de son système")


static func _test_ai() -> void:
	var st := ForgeTests.new_game("complete", "aucun", "ossarane", {"ai_level": "normal"})
	var e := st.get_empire(1)
	ForgeTests.all_techs(st, 1)
	MegasTests.rich(st, 1)
	var sid := ForgeTests.home_sys(st, 1)
	ForgeTests.body(st, sid, "gas_giant", 4)
	MegasTests.architect(st, 1, sid)
	var ctx := {"state": st, "e": e, "lv": AiLevels.level("normal"), "ai": AiLevels.personality(e), "salt": 0, "intent": ""}
	ctx["lv"] = {"mistake_pct": 0}
	st.tick = 30
	AiForge.think(ctx)
	_ok(WorldForge.busy(st, 1) >= 1 or not WorldForge.sub(st, "plans").is_empty(), "l'IA lance un chantier planétaire (%s)" % String(ctx["intent"]))
	# Elle ne démantèle jamais un monde habitable.
	var hp := ForgeTests.body(st, sid, "continental", 3)
	_ok(not AiForge._wants_dismantle(st, e, hp), "l'IA ne démantèle pas un monde habitable")
	e.ai_temperament = "pacifique"
	var bp := ForgeTests.body(st, sid, "barren", 2)
	_ok(not AiForge._wants_dismantle(st, e, bp), "pacifique : pas même un monde stérile")
