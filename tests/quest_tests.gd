extends RefCounted
## Tests des quêtes (Quests, AiQuests) : quête de peuple selon le credo, branches (seuils relatifs,
## paiement, marque, délai entre chapitres), héros unique et relique de quête (ou faveur sans
## reliques), quêtes secondaires (curiosité, prime pirate, délai dépassé), quêtes galactiques
## (Passage, Rouille grise, Conclave des Phares, réveil des tombeaux et talent synthétique),
## IA, sauvegarde 27 et déterminisme. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Quêtes…")
	_test_setup()
	_test_branches()
	_test_rewards()
	_test_side()
	_test_passage()
	_test_plague()
	_test_conclave()
	_test_tombs()
	_test_ai()
	_test_save()
	_test_determinism()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(seed_value := 11, faction := "vael", quests := "toutes", curios := "normales", ai := "") -> GameState:
	return GameState.create(seed_value, 150, 1800.0, faction, {"ai_level": ai, "curios": curios, "quests": quests})


func _rich(st: GameState, empire_id := 0) -> void:
	for r in ["energy", "materials", "influence", "food"]:
		st.get_empire(empire_id).resources[r] = 5000


## Donne à l'empire une colonie établie dans ce système.
func _own(st: GameState, sid: int, empire_id := 0) -> void:
	var c := Colony.new()
	c.planet_id = st.galaxy.systems[sid].planet_ids[0]
	c.owner = empire_id
	c.kind = Colony.KIND_COLONY
	c.population = 4
	st.add_colony(c)
	st.get_empire(empire_id).explored[sid] = true


func _day(st: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	st.tick += 1
	Quests.daily(st, added)
	return added


func _credo_quest(st: GameState, empire_id := 0) -> Dictionary:
	for id in Quests.of(st, empire_id):
		if Quests.is_credo(st.quests[id]):
			return st.quests[id]
	return {}


## Lance un retournement galactique précis tout de suite.
func _force(st: GameState, id: String) -> Dictionary:
	var seen := []
	for g in Quests.data()["galactic"]["order"]:
		if String(g) != id:
			seen.append(String(g))
	st.galactic["seen"] = seen
	st.galactic["cur"] = {}
	var added: Array[Dictionary] = []
	Quests._galactic_start(st, added)
	return Quests.current(st)


func _test_setup() -> void:
	var none := _new(11, "vael", "aucunes")
	none.tick = 400
	var added: Array[Dictionary] = []
	Quests.daily(none, added)
	_ok(none.quests.is_empty() and not Quests.enabled(none), "réglage Aucune : pas de quête")
	var st := _new(11, "vael")
	st.tick = 359
	_day(st)
	var q := _credo_quest(st)
	_ok(not q.is_empty() and String(q["tpl"]) == "credo_raison", "jour 360 : Vael (Raison) reçoit « %s »" % (Quests.title(st, q) if not q.is_empty() else "?"))
	var n := 0
	for e in st.empires:
		if not _credo_quest(st, e.id).is_empty():
			n += 1
			_ok(String(_credo_quest(st, e.id)["tpl"]) == "credo_" + Events.layer_value(st, e.id, "credo"), "%s : quête du credo %s" % [e.short_name(), Events.layer_value(st, e.id, "credo")])
	_ok(n == st.empires.size(), "chaque empire a sa quête de peuple (%d)" % n)
	_ok(int(q["subj"]["system"]) >= 0 and st.system_owner(int(q["subj"]["system"])) != 0, "la quête vise un système lointain qui n'est pas à soi")
	var ids := Relics.ids()
	var quest_rel := 0
	for rid in ids:
		if Relics.is_quest(rid):
			quest_rel += 1
			var buried := false
			for sid in st.digs:
				if String(st.digs[sid]["relic"]) == rid:
					buried = true
			_ok(not buried, "%s n'est enfouie dans aucune fouille" % rid)
	_ok(quest_rel == 7, "7 reliques de quête")


func _test_branches() -> void:
	var st := _new(12, "vael")
	st.tick = 359
	_day(st)
	var q := _credo_quest(st)
	var e := st.get_empire(0)
	# Chapitre 1 de la Raison : « 3 technologies » ou « 2 curiosités », seuils relatifs au départ.
	_ok(Quests.progress(st, q, 0) == [0, 3], "seuil relatif : 0 / 3 technologies au départ")
	e.stats["curios"] = int(e.stats.get("curios", 0)) + 2
	var renown := int(Heroes.meta(st, 0)["renown"])
	_day(st)
	_ok(int(q["ch"]) == 1 and (q["path"] as Array) == [1], "la branche remplie la première l'emporte (2 curiosités)")
	_ok(Events.has_mark(st, 0, "quete:credo_raison:0:1"), "la branche pose sa marque, lisible par les événements")
	_ok(int(Heroes.meta(st, 0)["renown"]) > renown, "un chapitre achevé rapporte du renom")
	_ok(int(q["wait"]) == st.tick + int(Quests.rules()["chapter_gap"]["credo"]), "le chapitre suivant s'ouvre plus tard (%d jours)" % int(Quests.rules()["chapter_gap"]["credo"]))
	_ok(Quests.check_pay(st, 0, int(q["id"]), 1) != "", "on ne paie pas un chapitre encore fermé")
	st.tick = int(q["wait"]) - 1
	_day(st)
	_ok(int(q["wait"]) == 0, "le chapitre 2 s'ouvre")
	_rich(st)
	var sim := Simulation.new(st)
	var influence := int(e.resources["energy"])
	sim.submit(SimCommands.quest_pay(0, int(q["id"]), 1))
	sim.flush_commands()
	_ok(int(q["ch"]) == 2 and int(e.resources["energy"]) < influence, "payer la branche « Acheter les relevés » achève le chapitre 2")
	_ok(SimCommands.validate(st, SimCommands.quest_pay(0, int(q["id"]), 0)) != "", "une branche sans paiement ne se paie pas")
	_ok(SimCommands.validate(st, SimCommands.quest_pay(1, int(q["id"]), 1)) != "", "on ne paie pas la quête d'un autre")


func _test_rewards() -> void:
	var st := _new(13, "vael")
	st.tick = 359
	_day(st)
	var q := _credo_quest(st)
	var added: Array[Dictionary] = []
	var heroes_before := Heroes.ids_of(st, 0).size()
	q["ch"] = 2
	q["wait"] = 0
	Quests._begin_chapter(st, q)
	Quests.complete_branch(st, q, 0, added)
	var found := false
	for hid in Heroes.ids_of(st, 0):
		if String(st.heroes[hid]["name"]) == "Docteure Quill Ombrelune" and int(st.heroes[hid].get("unique", 0)) == 1:
			found = true
	_ok(found and Heroes.ids_of(st, 0).size() == heroes_before + 1, "chapitre 3 : un héros unique rejoint l'empire")
	q["wait"] = 0
	Quests._begin_chapter(st, q)
	Quests.complete_branch(st, q, 0, added)
	_ok(String(q["status"]) == "done" and Relics.owned(st, 0).has("theoreme_ultime"), "fin de la quête : la relique Théorème Ultime")
	_ok(int(Quests.meta(st, 0)["credo_done"]) == 1 and Quests.score(st, 0) == int(Quests.rules()["score_credo"]), "la quête de peuple compte au score")
	var knowledge := Research.fx_sub(st, 0, "production_pct", "knowledge")
	_ok(int(knowledge) >= 15, "la relique agit (Savoir +%d %%)" % int(knowledge))
	# Sans curiosités, pas de reliques : l'effet devient une faveur permanente.
	var bare := _new(13, "vael", "toutes", "aucune")
	var before := int(Research.effects(bare, 0).get("production_pct", {}).get("knowledge", 0))
	Quests.give_relic(bare, 0, "theoreme_ultime")
	var after := int(Research.effects(bare, 0).get("production_pct", {}).get("knowledge", 0))
	_ok(after == before + 15, "sans reliques dans la partie, l'effet s'attache à l'empire (+15 %%)")
	# Faveur datée : elle s'en va à l'échéance.
	Quests.add_boon(bare, 0, "Essai", {"stability": 7}, 30)
	_ok(Research.fx_int(bare, 0, "stability") >= 7, "une faveur datée agit")
	bare.tick += 31
	Quests._boons(bare)
	_ok(Research.fx_int(bare, 0, "stability") < 7, "puis s'efface à l'échéance")


func _test_side() -> void:
	var st := _new(14, "vael")
	st.tick = 600
	var added: Array[Dictionary] = []
	var id := Quests.start(st, 0, "q_signal", {}, added)
	_ok(id >= 0, "une curiosité peut ouvrir « Le signal qui répond »")
	var q: Dictionary = st.quests[id]
	var sid := int(q["subj"]["system"])
	var f := st.spawn_ship(0, "scout", sid)
	_day(st)
	_ok(int(q["ch"]) == 1, "une flotte à l'arrêt sur place remplit « aller à »")
	st.fleets.erase(f.id)
	st.tick = int(q["until"]) + 1
	Quests.daily(st, added)
	_ok(String(q["status"]) == "failed", "délai dépassé : la quête est abandonnée")
	# Curiosité de ruines : la récompense « quest » lance la quête du type.
	var st2 := _new(15, "vael")
	var pid := -1
	for p in st2.curios:
		if String(st2.curios[p]["type"]) == "ruines":
			pid = int(p)
			break
	var got := Curios._give(st2, 0, pid, "quest", added)
	_ok(not Quests.of(st2, 0).is_empty() and String(st2.quests[Quests.of(st2, 0)[0]]["tpl"]) == "q_signal", "sonde de ruines : %s" % got)
	# Prime pirate : démanteler le repaire visé remplit la branche.
	var st3 := GameState.create(16, 150, 1800.0, "vael", {"quests": "toutes", "pirates": "normaux"})
	var lairs := Pirates.lair_ids(st3)
	if lairs.is_empty():
		_ok(false, "des repaires pour la prime")
		return
	st3.get_empire(0).explored[lairs[0]] = true
	var lid := Quests.start(st3, 0, "q_primes", {"lair": lairs[0], "system": lairs[0]}, added)
	_ok(lid >= 0, "quête de prime sur un repaire connu")
	Pirates.dismantle(st3, lairs[0], 0, added)
	var en := int(st3.get_empire(0).resources.get("energy", 0))
	_day(st3)
	_ok(String(st3.quests[lid]["status"]) == "done" and int(st3.get_empire(0).resources.get("energy", 0)) > en, "le repaire démantelé paie la prime")
	# Le même repaire démantelé par un autre fait échouer la prime.
	var lid2 := Quests.start(st3, 1, "q_primes", {"lair": lairs[1], "system": lairs[1]}, added) if lairs.size() > 1 else -1
	if lid2 >= 0:
		Pirates.dismantle(st3, lairs[1], 0, added)
		_day(st3)
		_ok(String(st3.quests[lid2]["status"]) == "failed", "repaire démantelé par un autre : la prime échoue")
	# Effet « quest » d'un choix d'événement.
	var st4 := _new(17, "brisecomete")
	var item := {"id": -1, "card": "", "system": -1, "planet": -1, "rival": 1, "hero": -1}
	Events.apply_fx(st4, 0, item, [{"k": "quest", "q": "q_contrebande"}], added)
	_ok(not Quests.of(st4, 0).is_empty(), "un choix d'événement ouvre une quête (contrebande de reliques)")


func _test_passage() -> void:
	var st := _new(18, "vael")
	st.tick = 1500
	var cur := _force(st, "passage")
	_ok(not cur.is_empty() and String(cur["id"]) == "passage" and (cur["path"] as Array).size() >= 10, "Le passage : un trajet de %d systèmes" % (cur.get("path", []) as Array).size())
	var sid := Quests.passage_system(cur)
	var f := st.spawn_ship(0, "corvette", sid)
	for i in 5:
		_day(st)
	_ok(int(cur["pts"].get(0, 0)) == 5, "une flotte près de l'artéfact : 1 point par jour")
	var fl := Heroes.ids_of(st, 0)
	if not fl.is_empty():
		var h: Dictionary = st.heroes[fl[0]]
		h["post"] = "fleet"
		h["target"] = f.id
		h["arrive"] = 0
		_day(st)
		_ok(int(cur["pts"][0]) == 7, "deux points si un héros commande la flotte")
	st.tick = int(cur["next_step"]) - 1
	_day(st)
	_ok(int(cur["step"]) == 1, "l'artéfact passe au système suivant")
	cur["step"] = (cur["path"] as Array).size() - 1
	cur["next_step"] = st.tick + 1
	f.system_id = Quests.passage_system(cur)
	_day(st)
	_ok(Quests.current(st).is_empty() and Relics.owned(st, 0).has("coeur_passage"), "au bout du trajet, le meilleur chercheur garde l'Éclat du Passage")
	_ok(int(st.galactic["next"]) > st.tick + 1000, "le prochain retournement attend plusieurs années")


func _test_plague() -> void:
	var st := _new(19, "vael")
	st.tick = 1500
	var all_before := int(Research.effects(st, 0).get("production_pct", {}).get("all", 0))
	var cur := _force(st, "fleau")
	_ok(String(cur["id"]) == "fleau", "La Rouille grise se répand")
	_ok(int(Research.effects(st, 0).get("production_pct", {}).get("all", 0)) == all_before - 8, "production −8 % pour tous pendant le fléau")
	_rich(st, 0)
	_rich(st, 1)
	var sim := Simulation.new(st)
	var target := int(cur["target"])
	for i in target - 1:
		sim.submit(SimCommands.quest_contribute(0 if i % 3 != 2 else 1))
		sim.flush_commands()
	_ok(int(cur["pool"]) == target - 1 and int(cur["gifts"][0]) > int(cur["gifts"][1]), "les dons s'additionnent (%d / %d)" % [int(cur["pool"]), target])
	sim.submit(SimCommands.quest_contribute(0))
	sim.flush_commands()
	_ok(Quests.current(st).is_empty(), "le remède financé met fin au fléau")
	var stab := 0
	for bn: Dictionary in Quests.meta(st, 0)["boons"]:
		if String(bn["label"]) == "Panacée de la Rouille":
			stab = int(bn["fx"].get("stability", 0))
	_ok(stab == 2 and int(Research.effects(st, 0).get("production_pct", {}).get("all", 0)) == all_before + 5, "le plus généreux reçoit la Panacée (production +5 %, stabilité +2)")
	_ok(SimCommands.validate(st, SimCommands.quest_contribute(0)) != "", "plus de don possible une fois le fléau vaincu")


func _test_conclave() -> void:
	var st := _new(20, "vael")
	st.tick = 1500
	var cur := _force(st, "conclave")
	_ok(String(cur["id"]) == "conclave" and String(cur["phase"]) == "choose", "le Conclave des Phares recrute")
	var sim := Simulation.new(st)
	sim.submit(SimCommands.quest_camp(0, 1))
	sim.flush_commands()
	_ok(Quests.camp_of(st, 0) == 1, "on choisit son camp (Briseurs de Phares)")
	st.tick = int(cur["until"]) - 1
	var added := _day(st)
	_ok(String(cur["phase"]) == "hold" and (cur["phares"] as Array).size() == 3, "les camps sont formés et trois Phares s'allument")
	var unset := 0
	for e in st.empires:
		if Quests.camp_of(st, e.id) < 0:
			unset += 1
	_ok(unset == 0, "les indécis sont répartis par le sort")
	var sid := int(cur["phares"][0])
	var owner := st.system_owner(sid)
	var hs := Heroes.ids_of(st, owner if owner >= 0 else 0)
	if hs.is_empty():
		_ok(false, "un héros pour tenir le Phare")
		return
	var h: Dictionary = st.heroes[hs[0]]
	h["post"] = "system"
	h["target"] = sid
	h["arrive"] = 0
	h["owner"] = owner if owner >= 0 else 0
	var camp := Quests.camp_of(st, int(h["owner"]))
	var sc := int(cur["score"][camp])
	_day(st)
	_ok(int(cur["score"][camp]) == sc + 1, "un héros gouverneur tient le Phare : +1 par jour pour son camp")
	cur["score"][camp] = int(Quests.gdef("conclave")["target"]) - 1
	cur["score"][1 - camp] = 0
	_day(st)
	_ok(Quests.current(st).is_empty(), "le camp qui atteint le seuil remporte le Conclave")
	var loser := -1
	for e in st.empires:
		var m: Dictionary = st.quest_meta.get(e.id, {})
		if int(m.get("no_offer", 0)) > st.tick:
			loser = e.id
	_ok(loser >= 0 and Quests.blocks_offers(st, loser), "les vaincus ne reçoivent plus d'offre de héros")
	if loser >= 0:
		var hm := Heroes.meta(st, loser)
		hm["renown"] = 99999
		hm["offer"] = []
		_ok(not Heroes._maybe_offer(st, loser), "même avec du renom en masse")


func _test_tombs() -> void:
	var st := _new(21, "teyl")
	st.tick = 1500
	_ok(not Quests.eligible(st, "tombeaux"), "pas de tombeaux sans fouille achevée")
	var keys := st.digs.keys()
	keys.sort()
	st.digs[keys[0]]["done"] = 1
	_ok(Quests.eligible(st, "tombeaux"), "une fouille achevée peut réveiller les tombeaux")
	var cur := _force(st, "tombeaux")
	_ok(String(cur["id"]) == "tombeaux" and (cur["tombs"] as Array).size() == 4, "quatre tombeaux s'éveillent")
	var t: Dictionary = cur["tombs"][0]
	_ok(int(t["sid"]) == int(keys[0]) and st.fleets.has(int(t["fleet"])), "le premier se dresse sur la fouille achevée, gardé par une flotte")
	var sid := int(t["sid"])
	_rich(st)
	_ok(Quests.check_parley(st, 0, sid) != "", "parlementer demande un système voisin")
	var near := -1
	var jumps := FactionTraits.jumps_from(st.galaxy, sid)
	for s in st.galaxy.systems:
		if int(jumps.get(s.id, 99)) == 1 and not s.planet_ids.is_empty() and st.system_owner(s.id) < 0:
			near = s.id
			break
	if near < 0:
		_ok(false, "un voisin pour parlementer")
		return
	_own(st, near)
	Quests._tombs_near(st, cur)
	_ok((cur["near"] as Array).has(0), "un tombeau voisin pèse sur la stabilité de l'empire")
	_ok(int(Quests.effects(st, 0).get("stability", 0)) == -3, "−3 de stabilité")
	_ok(Quests.check_parley(st, 1, sid) != "", "seul un peuple synthétique sait parlementer")
	var sim := Simulation.new(st)
	sim.submit(SimCommands.tomb_parley(0, sid))
	sim.flush_commands()
	_ok(int(t["alive"]) == 0 and int(t["by"]) == 0 and not st.fleets.has(int(t["fleet"])) and int(cur["pts"][0]) == 1, "Teyl (synthétique) parlemente : le tombeau se rendort")
	# Une bataille gagnée contre les gardiens rapporte aussi un point.
	var t2: Dictionary = cur["tombs"][1]
	st.fleets.erase(int(t2["fleet"]))
	Quests.on_battle(st, {"system": int(t2["sid"])}, 2)
	_ok(int(t2["by"]) == 2 and int(cur["pts"][2]) == 1, "abattre des gardiens rapporte un point au vainqueur")
	for x: Dictionary in cur["tombs"]:
		if st.fleets.has(int(x["fleet"])):
			st.fleets.erase(int(x["fleet"]))
	_day(st)
	_ok(Quests.current(st).is_empty() and (Relics.owned(st, 0).has("cle_tombeaux") or Relics.owned(st, 2).has("cle_tombeaux")), "tous rendormis : la Clé des Tombeaux au meilleur")


func _test_ai() -> void:
	var sim := Simulation.new(GameState.create(23, 150, 1800.0, "", {"ai_level": "normal", "curios": "normales", "quests": "toutes", "events": "normaux"}))
	sim.advance(360 * 6)
	var chapters := 0
	var side := 0
	for id in sim.state.quests:
		var q: Dictionary = sim.state.quests[id]
		chapters += (q["path"] as Array).size()
		if not Quests.is_credo(q):
			side += 1
	_ok(chapters >= 8, "les IA avancent leurs quêtes (%d chapitres en 6 ans)" % chapters)
	_ok(side >= 3, "des quêtes secondaires naissent (%d)" % side)
	_ok(not (sim.state.galactic["log"] as Array).is_empty() or not Quests.current(sim.state).is_empty(), "un retournement galactique a eu lieu")


func _test_save() -> void:
	var sim := Simulation.new(_new(24, "vael"))
	var st := sim.state
	st.tick = 359
	_day(st)
	var added: Array[Dictionary] = []
	Quests.start(st, 0, "q_signal", {}, added)
	Quests.add_boon(st, 0, "Essai", {"production_pct": {"energy": 5}}, 0)
	st.tick = 1500
	var cur := _force(st, "conclave")
	Quests.choose_camp(st, 0, 1)
	sim.advance(30)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_snapshot())))
	_ok(back != null, "sauvegarde 27 relue")
	if back == null:
		return
	_ok(back.checksum() == st.checksum(), "même empreinte après sauvegarde (quêtes, faveurs, Conclave)")
	_ok(Quests.camp_of(back, 0) == 1 and String(Quests.current(back)["phase"]) == String(cur["phase"]), "le Conclave reprend où il en était")
	_ok(Research.fx_sub(back, 0, "production_pct", "energy") == Research.fx_sub(st, 0, "production_pct", "energy") and Research.fx_sub(st, 0, "production_pct", "energy") >= 5, "la faveur agit encore après chargement")
	var a := Simulation.new(st)
	var b := Simulation.new(back)
	a.advance(250)
	b.advance(250)
	_ok(a.state.checksum() == b.state.checksum(), "la partie reprise continue à l'identique")
	var old := st.to_snapshot()
	old["version"] = 26
	old.erase("quests")
	var o := GameState.from_dict(JSON.parse_string(JSON.stringify(old)))
	_ok(o != null and o.quests.is_empty() and not Quests.enabled(o), "une sauvegarde 26 se relit (sans quêtes)")


func _test_determinism() -> void:
	var opts := {"curios": "nombreuses", "events": "frequents", "quests": "toutes", "ai_level": "normal"}
	var a := Simulation.new(GameState.create(53, 150, 1800.0, "", opts))
	var b := Simulation.new(GameState.create(53, 150, 1800.0, "", opts))
	a.advance(1700)
	b.advance(1700)
	_ok(a.state.checksum() == b.state.checksum() and not a.state.quests.is_empty(), "même graine, mêmes quêtes après 1700 jours")
