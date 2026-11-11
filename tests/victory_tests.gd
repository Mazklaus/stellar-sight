extends RefCounted
## Tests des victoires : données et couches d'espèce, conquête, domination, score à date limite,
## les quatre victoires de peuple (Élu des routes, Dernier Couplet, Charte, Moisson), technologie
## requise, visibilité et malus d'opinion, IA qui poursuit sa victoire, sauvegarde, anciennes
## sauvegardes et déterminisme. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Victoires…")
	_test_data()
	_test_rules()
	_test_conquest()
	_test_domination()
	_test_alliances()
	_test_score_deadline()
	_test_elu()
	_test_couplet()
	_test_charte()
	_test_moisson()
	_test_visibility_and_threat()
	_test_ai_pursuit()
	_test_save()
	_test_determinism()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


## Partie sans IA (rivaux inertes), le peuple voulu en empire 0.
func _state(faction := "ossarane", options := {}) -> GameState:
	var o := {"ai_level": ""}
	o.merge(options, true)
	return GameState.create(4242, 150, 1800.0, faction, o)


func _id_of(st: GameState, faction: String) -> int:
	for e in st.empires:
		if e.faction_id == faction:
			return e.id
	return -1


func _apply(st: GameState, cmd: Dictionary) -> String:
	var why := SimCommands.validate(st, cmd)
	if why == "":
		SimCommands.apply(st, cmd)
	return why


## Fait passer des bilans mensuels de victoire (sans le reste de la simulation).
@warning_ignore("integer_division")
func _months(st: GameState, n: int) -> void:
	for _i in n:
		st.tick = (st.tick / 30 + 1) * 30
		VictorySystem.process(st)


func _meet(st: GameState, a: int, b: int) -> void:
	for pair in [[a, b], [b, a]]:
		var e := st.get_empire(pair[0])
		if not e.contacts.has(pair[1]):
			e.contacts.append(pair[1])
			e.contacts.sort()


## Une revendication fondée sur la première planète libre du système.
func _claim(st: GameState, owner: int, system_id: int, kind := Colony.KIND_OUTPOST, pop := 0) -> Colony:
	for pid in st.galaxy.systems[system_id].planet_ids:
		if st.colonies.has(pid):
			continue
		var c := Colony.new()
		c.planet_id = pid
		c.owner = owner
		c.kind = kind
		c.days_left = 0
		c.population = pop
		st.add_colony(c)
		return c
	return null


func _home_system(st: GameState, id: int) -> int:
	return st.galaxy.get_planet(st.get_empire(id).home_planet).system_id


func _test_data() -> void:
	var ids := Victory.ids()
	_ok(ids.slice(0, 3) == ["conquete", "domination", "score"], "trois victoires classiques d'abord")
	var want := {"ossarane": ["elu"], "choeur": ["couplet"], "vael": ["charte"], "khthari": ["moisson"]}
	for f in want:
		_ok(Array(Victory.people_ids_for(GameData.faction(f))) == want[f], "%s : sa victoire de peuple (%s)" % [f, str(Victory.people_ids_for(GameData.faction(f)))])
	# Un peuple personnalisé y a droit par ses couches, pas par son nom.
	var custom := {"id": "perso", "species": {"archetype": "ruche", "gouvernement": "republique", "credo": "raison", "traits": []}}
	_ok(Array(Victory.people_ids_for(custom)) == ["charte", "moisson"], "peuple personnalisé : victoires selon ses couches")
	for id in ids:
		var t := Victory.tech_for(id)
		if Victory.is_people(id):
			_ok(Research.exists(t) and int(Research.tech(t)["era"]) == 4 and String(Research.tech(t)["domain"]) == "societe",
					"%s : technologie de Société de l'ère IV (%s)" % [id, t])
			_ok(not Victory.rule_text(id).contains("%d"), "%s : texte de règle complet" % id)
	_ok(not GameData.building("cathedrale").is_empty() and GameData.building("cathedrale")["requires_tech"] == ["dernier_couplet"], "Cathédrale-chœur débloquée par le Dernier Couplet")


func _test_rules() -> void:
	var st := _state()
	_ok(Victory.deadline(st) == Victory.default_deadline() and Victory.default_deadline() == 21600, "date limite par défaut : 60 ans")
	_ok(Victory.enabled(st, "score") and Victory.enabled(st, "elu"), "score et victoires de peuple en jeu par défaut")
	var st2 := _state("ossarane", {"deadline": 0, "people_victories": false})
	_ok(not Victory.enabled(st2, "score") and not Victory.enabled(st2, "elu") and Victory.enabled(st2, "conquete"), "sans date limite ni victoires de peuple")
	_ok(Victory.ids_for(st2, 0) == ["conquete", "domination"], "victoires visées sans les options")
	for e in st.empires:
		_ok(e.home_planet == e.capital_planet and e.home_planet >= 0, "%s : capitale d'origine notée" % e.short_name())


@warning_ignore("integer_division")
func _test_conquest() -> void:
	var st := _state()
	var p := Victory.progress(st, 0, "conquete")
	_ok(int(p["pct"]) == 0 and not p["won"], "conquête : rien au départ")
	var rivals := st.empires.size() - 1
	for i in range(1, st.empires.size() - 1):
		Combat.capture_system(st, _home_system(st, i), 0)
	p = Victory.progress(st, 0, "conquete")
	_ok(not p["won"] and int(p["pct"]) == 100 * (rivals - 1) / rivals, "conquête : %d capitales sur %d (%d %%)" % [rivals - 1, rivals, int(p["pct"])])
	# Perdre sa propre capitale d'origine bloque la victoire.
	Combat.capture_system(st, _home_system(st, 0), st.empires.size() - 1)
	Combat.capture_system(st, _home_system(st, st.empires.size() - 1), 0)
	p = Victory.progress(st, 0, "conquete")
	_ok(not p["won"] and int(p["pct"]) < 100 and str(p["lines"]).contains("PERDUE"), "conquête : sans sa capitale d'origine, pas de victoire")
	Combat.capture_system(st, _home_system(st, 0), 0)
	_months(st, 1)
	_ok(st.winner.get("empire", -1) == 0 and st.winner.get("victory", "") == "conquete", "conquête : toutes les capitales, victoire proclamée")
	_ok(String(st.chronicle.back()["text"]).begins_with("VICTOIRE"), "conquête : la chronique l'annonce")
	var before := st.winner.duplicate()
	Combat.capture_system(st, _home_system(st, 0), 1)
	_months(st, 3)
	_ok(st.winner == before, "après la victoire, plus rien ne change le vainqueur")


func _test_domination() -> void:
	var st := _state()
	var need := Victory.domination_needed(st)
	_ok(need == 75, "domination : 50 %% des 150 systèmes (%d)" % need)
	var added := 0
	for s in st.galaxy.systems:
		if Victory.systems_held(st, 0) >= need:
			break
		if st.system_owner(s.id) < 0 and _claim(st, 0, s.id) != null:
			added += 1
	var p := Victory.progress(st, 0, "domination")
	_ok(p["cond"] and int(p["pct"]) == Victory.met_at(), "domination : condition remplie, %d %%" % int(p["pct"]))
	_months(st, 12)
	_ok(Victory.held(st, 0, "domination") == 360 and st.winner.is_empty(), "domination : un an tenu, pas encore gagné")
	_ok(Victory.cached_pct(st, 0, "domination") > Victory.met_at() and Victory.cached_pct(st, 0, "domination") < 100, "domination : avancée entre 75 et 100")
	# Perdre un système remet le compte à rebours à zéro.
	var lost := -1
	for pid in st.sorted_colony_ids():
		var c: Colony = st.colonies[pid]
		if c.owner == 0 and pid != st.get_empire(0).home_planet:
			lost = pid
			break
	st.colonies.erase(lost)
	st.rebuild_ownership()
	_months(st, 1)
	_ok(Victory.held(st, 0, "domination") == 0, "domination : un système perdu, le compte repart de zéro")
	var c := Colony.new()
	c.planet_id = lost
	c.owner = 0
	c.kind = Colony.KIND_OUTPOST
	c.days_left = 0
	st.add_colony(c)
	_months(st, 37)
	_ok(st.winner.get("victory", "") == "domination" and int(st.winner["empire"]) == 0, "domination : trois ans tenus, victoire")


## Les alliés comptent pour la conquête et la domination, et gagnent ensemble (Endless Space 2).
func _test_alliances() -> void:
	var st := _state("vael")
	var oss := _id_of(st, "ossarane")
	var choeur := _id_of(st, "choeur")
	var swarm := _id_of(st, "khthari")
	_meet(st, 0, oss)
	Diplomacy.sign_treaty(st, 0, oss, Diplomacy.PEACE)
	Diplomacy.sign_treaty(st, 0, oss, Diplomacy.ALLIANCE)
	_ok(Victory.bloc(st, 0) == [0, oss], "alliance : le bloc compte l'allié")
	_ok(Victory.domination_needed(st, 0) == 90 and Victory.domination_needed(st, choeur) == 75, "domination : +10 points par allié (90 systèmes au lieu de 75)")
	Combat.capture_system(st, _home_system(st, choeur), oss)
	var p := Victory.progress(st, 0, "conquete")
	_ok(str(p["lines"]).contains("Capitales rivales tenues : 1 / 2"), "conquête : la capitale prise par l'allié compte")
	Combat.capture_system(st, _home_system(st, swarm), 0)
	_months(st, 1)
	_ok(st.winner.get("victory", "") == "conquete" and Victory.is_winner(st, 0) and Victory.is_winner(st, oss) and not Victory.is_winner(st, choeur),
			"conquête : victoire partagée avec l'allié (%s)" % str(st.winner))
	_ok(String(st.chronicle.back()["text"]).contains("avec Ossarane"), "la chronique nomme l'allié")
	# Les victoires de peuple restent individuelles.
	var st2 := _state("khthari")
	_meet(st2, 1, 2)
	Diplomacy.sign_treaty(st2, 1, 2, Diplomacy.PEACE)
	Diplomacy.sign_treaty(st2, 1, 2, Diplomacy.ALLIANCE)
	var e := st2.get_empire(0)
	st2.colonies[e.home_planet].population = 300
	e.stats["digested"] = 100
	Research.grant(st2, 0, ["grande_moisson"])
	_months(st2, 25)
	_ok(st2.winner.get("victory", "") == "moisson" and Array(st2.winner["allies"]).is_empty(), "une victoire de peuple ne se partage pas")


func _test_score_deadline() -> void:
	var st := _state("vael", {"deadline": 45})
	var sim := Simulation.new(st)
	sim.advance(44)
	_ok(st.winner.is_empty(), "score : pas de vainqueur avant la date limite")
	sim.advance(1)
	var rank := Victory.ranking(st)
	_ok(st.winner.get("victory", "") == "score" and int(st.winner["empire"]) == int(rank[0]["id"]), "score : le meilleur l'emporte à la date limite")
	_ok(int(rank[0]["score"]) >= int(rank[-1]["score"]), "classement trié par score")
	_ok(EmpireReport.score(st, 0) == Victory.score(st, 0), "le tableau du spectateur montre le même score")
	var e := st.get_empire(0)
	var base := Victory.score(st, 0)
	e.techs["propagande"] = true
	e.stats["kills"] = int(e.stats.get("kills", 0)) + 3
	_ok(Victory.score(st, 0) == base + 5 + 6, "score : +5 par technologie, +2 par vaisseau détruit")


## Ossarane : unions sur des alliances de longue date, héritier loyal, deux ans.
@warning_ignore("integer_division")
func _test_elu() -> void:
	var st := _state("ossarane")
	var vael := _id_of(st, "vael")
	var choeur := _id_of(st, "choeur")
	var swarm := _id_of(st, "khthari")
	var e := st.get_empire(0)
	e.resources["influence"] = 1000
	e.resources["crystals"] = 100
	_ok(Victory.unions_needed(st, 0) == 2, "Élu : deux dynasties à unir (l'Essaim ne signe rien)")
	_ok(Victory.check_union(st, 0, vael).contains("technologie"), "Élu : il faut la technologie")
	Research.grant(st, 0, ["lignees_croisees"])
	_ok(Victory.check_union(st, 0, vael).contains("alliance"), "Élu : il faut une alliance")
	_ok(Victory.check_union(st, 0, swarm).contains("ne signe rien"), "Élu : pas d'union avec l'Essaim")
	for o in [vael, choeur]:
		_meet(st, 0, o)
		Diplomacy.sign_treaty(st, 0, o, Diplomacy.PEACE)
		Diplomacy.sign_treaty(st, 0, o, Diplomacy.ALLIANCE)
	_ok(Victory.check_union(st, 0, vael).contains("durer"), "Élu : l'alliance doit durer")
	st.tick += 200
	var inf := int(e.resources["influence"])
	_ok(_apply(st, SimCommands.unite_lineages(0, vael)) == "", "Élu : union avec Vael")
	_ok(int(e.resources["influence"]) == inf - 50 and Victory.united(st, 0, vael), "Élu : l'union coûte et tient")
	_ok(_apply(st, SimCommands.unite_lineages(0, vael)) != "", "Élu : pas deux fois la même union")
	var p := Victory.progress(st, 0, "elu")
	_ok(not p["cond"] and int(p["pct"]) == (Victory.met_at() - 1) / 2, "Élu : une union sur deux (%d %%)" % int(p["pct"]))
	_apply(st, SimCommands.unite_lineages(0, choeur))
	e.heir_loyalty = 60
	p = Victory.progress(st, 0, "elu")
	_ok(p["cond"] and int(p["pct"]) == Victory.met_at(), "Élu : toutes les lignées unies, l'Élu se prépare")
	_months(st, 6)
	_ok(Victory.held(st, 0, "elu") == 180, "Élu : six mois de gestation")
	e.heir_loyalty = 30  # un rival a soudoyé l'héritier
	_months(st, 1)
	_ok(Victory.held(st, 0, "elu") == 0, "Élu : héritier déloyal, tout est à refaire")
	e.heir_loyalty = 70
	Diplomacy.cancel(st, choeur, 0, Diplomacy.ALLIANCE)
	_months(st, 1)
	_ok(not Victory.united(st, 0, choeur) and not Diplomacy.rel(st, 0, choeur).has("union"), "Élu : l'union tombe avec l'alliance")
	# On recommence, et on tient deux ans.
	Diplomacy.sign_treaty(st, 0, choeur, Diplomacy.ALLIANCE)
	st.tick += 200
	_ok(_apply(st, SimCommands.unite_lineages(0, choeur)) == "", "Élu : nouvelle union après une nouvelle alliance")
	_months(st, 25)
	_ok(st.winner.get("victory", "") == "elu" and int(st.winner["empire"]) == 0, "Élu : deux ans, victoire de l'Élu des routes")


## Chœur : trois cathédrales dans trois systèmes, puis l'Exaltation tenue deux ans.
func _test_couplet() -> void:
	var st := _state("choeur")
	var e := st.get_empire(0)
	var systems: Array[int] = []
	for s in st.galaxy.systems:
		if systems.size() >= 3:
			break
		if st.system_owner(s.id) < 0 and s.planet_count > 0:
			var c := _claim(st, 0, s.id, Colony.KIND_COLONY, 4)
			c.buildings.append("cathedrale")
			systems.append(s.id)
	e.fervor = 90
	var p := Victory.progress(st, 0, "couplet")
	_ok(not p["cond"] and int(p["pct"]) == Victory.met_at() - 1, "Couplet : sans la technologie, plafonné à %d %%" % int(p["pct"]))
	_months(st, 3)
	_ok(Victory.held(st, 0, "couplet") == 0, "Couplet : sans la technologie, le chant ne commence pas")
	Research.grant(st, 0, ["dernier_couplet"])
	_ok(Victory.cathedral_systems(st, 0).size() == 3, "Couplet : trois cathédrales comptées")
	_months(st, 4)
	_ok(Victory.held(st, 0, "couplet") == 120, "Couplet : quatre mois de chant")
	e.fervor = 10
	_months(st, 2)
	_ok(Victory.held(st, 0, "couplet") == 120 and Victory.progress(st, 0, "couplet")["lines"].has("Compte à rebours en pause : 1 an 8 mois"),
			"Couplet : sans Exaltation, le chant se met en pause")
	# Une cathédrale prise : il faut tout reprendre.
	var lost := -1
	for pid in st.colonies:
		if st.colonies[pid].owner == 0 and st.colonies[pid].buildings.has("cathedrale"):
			lost = pid
	st.colonies[lost].owner = 1
	st.rebuild_ownership()
	_months(st, 1)
	_ok(Victory.held(st, 0, "couplet") == 0, "Couplet : une cathédrale tombée, le chant repart de zéro")
	st.colonies[lost].owner = 0
	st.rebuild_ownership()
	e.fervor = 90
	_months(st, 24)
	_ok(st.winner.get("victory", "") == "couplet", "Couplet : deux ans d'Exaltation, l'hymne s'achève")
	# Ordre de construction : seulement avec la technologie, et pas pour les autres peuples.
	var st2 := _state("choeur")
	var home := st2.get_empire(0).home_planet
	st2.get_empire(0).resources["materials"] = 5000
	st2.get_empire(0).resources["energy"] = 5000
	_ok(_apply(st2, SimCommands.build(0, home, "cathedrale")) != "", "Cathédrale : refusée sans la technologie")
	Research.grant(st2, 0, ["dernier_couplet"])
	_ok(_apply(st2, SimCommands.build(0, home, "cathedrale")) == "", "Cathédrale : construite avec la technologie")
	_ok(Research.check_queue(st2, _id_of(st2, "vael"), "dernier_couplet") != "", "Le Dernier Couplet n'est pas dans l'arbre de Vael")


## Vael : paix (ou alliance) et commerce avec tous les survivants, l'Essaim doit disparaître.
func _test_charte() -> void:
	var st := _state("vael")
	var oss := _id_of(st, "ossarane")
	var choeur := _id_of(st, "choeur")
	var swarm := _id_of(st, "khthari")
	Research.grant(st, 0, ["charte"])
	for o in [oss, choeur]:
		_meet(st, 0, o)
		Diplomacy.sign_treaty(st, 0, o, Diplomacy.PEACE)
		Diplomacy.sign_treaty(st, 0, o, Diplomacy.TRADE)
	_ok(Victory.signatories(st, 0) == [oss, choeur], "Charte : deux signataires")
	var p := Victory.progress(st, 0, "charte")
	_ok(not p["cond"] and str(p["lines"]).contains("Ne signera jamais"), "Charte : l'Essaim la bloque tant qu'il existe")
	for pid in st.colonies.keys():
		if st.colonies[pid].owner == swarm:
			st.colonies.erase(pid)
	CombatSystem.eliminate(st, st.get_empire(swarm))
	st.rebuild_ownership()
	p = Victory.progress(st, 0, "charte")
	_ok(p["cond"], "Charte : l'Essaim disparu, tous les survivants ont signé")
	_months(st, 12)
	Diplomacy.cancel(st, oss, 0, Diplomacy.TRADE)
	_months(st, 1)
	_ok(Victory.held(st, 0, "charte") == 0, "Charte : une défection, la ratification repart de zéro")
	Diplomacy.sign_treaty(st, 0, oss, Diplomacy.TRADE)
	_months(st, 24)
	_ok(st.winner.get("victory", "") == "charte" and int(st.winner["empire"]) == 0, "Charte : deux ans de ratification, victoire")


## Kh'thari : la moitié de la population de la galaxie, et assez de peuples digérés.
func _test_moisson() -> void:
	var st := _state("khthari")
	var e := st.get_empire(0)
	st.colonies[e.home_planet].population = 200
	var p := Victory.progress(st, 0, "moisson")
	_ok(not p["won"] and int(p["pct"]) == 0, "Moisson : rien de digéré, 0 %")
	e.stats["digested"] = 50
	p = Victory.progress(st, 0, "moisson")
	_ok(not p["won"] and int(p["pct"]) == (Victory.met_at() - 1) / 2, "Moisson : la moitié digérée (%d %%)" % int(p["pct"]))
	e.stats["digested"] = 100
	Research.grant(st, 0, ["grande_moisson"])
	_months(st, 1)
	p = Victory.progress(st, 0, "moisson")
	_ok(st.winner.is_empty() and p["cond"] and int(p["pct"]) >= Victory.met_at(), "Moisson : seuils atteints, le compte à rebours démarre (%d %%)" % int(p["pct"]))
	_months(st, 24)
	_ok(st.winner.get("victory", "") == "moisson", "Moisson : faite après deux ans tenus")
	# La digestion d'une conquête est bien comptée.
	var st2 := _state("khthari")
	var victim := _id_of(st2, "vael")
	st2.colonies[st2.get_empire(victim).home_planet].population = 9
	Combat.capture_system(st2, _home_system(st2, victim), 0)
	_ok(int(st2.get_empire(0).stats.get("digested", 0)) == 8, "Moisson : population digérée à la conquête (%d)" % int(st2.get_empire(0).stats.get("digested", 0)))


func _test_visibility_and_threat() -> void:
	var st := _state("ossarane")
	var vael := _id_of(st, "vael")
	_meet(st, 0, vael)
	var ev := st.get_empire(vael)
	ev.victory["charte"] = {"pct": 40, "held": 0, "warn": 0}
	_ok(Victory.visible_pct(st, 0, vael, "charte") == -1, "une victoire de peuple rivale reste cachée sous 50 %")
	_ok(Victory.visible_pct(st, -1, vael, "charte") == 40 and Victory.visible_pct(st, vael, vael, "charte") == 40, "le spectateur et l'empire lui-même la voient")
	var before := Diplomacy.opinion(st, 0, vael)
	ev.victory["charte"]["pct"] = 60
	_ok(Victory.visible_pct(st, 0, vael, "charte") == 60, "visible à partir de 50 %")
	_ok(Diplomacy.opinion(st, 0, vael) == before - 15, "menace pour la galaxie : -15 à 50 %")
	ev.victory["charte"]["pct"] = 80
	_ok(Diplomacy.opinion(st, 0, vael) == before - 30, "menace pour la galaxie : -30 à 75 %")
	var swarm := _id_of(st, "khthari")
	st.get_empire(swarm).victory["domination"] = {"pct": 90, "held": 0, "warn": 0}
	_ok(Victory.visible_pct(st, 0, swarm, "domination") == -1, "un empire jamais rencontré : rien de visible")
	# Alertes à 50 et 75 % dans la chronique.
	var st2 := _state("khthari")
	var e := st2.get_empire(0)
	st2.colonies[e.home_planet].population = 300
	e.stats["digested"] = 70  # 70 % du chemin d'approche (74 %) : un peu plus de la moitié
	_months(st2, 1)
	_ok(String(st2.chronicle.back()["text"]).contains("mi-chemin"), "alerte à mi-chemin")
	var n := st2.chronicle.size()
	_months(st2, 1)
	_ok(st2.chronicle.size() == n, "une alerte ne sonne qu'une fois")


func _ctx(st: GameState, id: int, level := "veteran") -> Dictionary:
	var e := st.get_empire(id)
	e.ai_level = level
	return {"state": st, "e": e, "lv": AiLevels.level(level), "ai": AiLevels.personality(e), "salt": 0, "intent": ""}


func _test_ai_pursuit() -> void:
	# Recherche : sa technologie de victoire passe devant dès que l'ère IV de Société s'ouvre.
	var st := _state("choeur")
	var tree := Research.visible_ids(st.get_empire(0).faction())
	var pre: Array = []
	for tid in tree:
		var t := Research.tech(tid)
		if int(t["era"]) <= 3 and not Research.is_heretic(st.get_empire(0).faction(), tid):
			pre.append(tid)
	Research.grant(st, 0, pre)
	_ok(Research.check_queue(st, 0, "dernier_couplet") == "", "IA : le Dernier Couplet est accessible")
	_ok(AiPlayer.research_pick(_ctx(st, 0)) == "dernier_couplet", "IA : la technologie de victoire en tête (%s)" % AiPlayer.research_pick(_ctx(st, 0)))
	# Cathédrales : sur les mondes les plus peuplés, un système chacun.
	Research.grant(st, 0, ["dernier_couplet"])
	var e := st.get_empire(0)
	e.resources["materials"] = 10000
	e.resources["energy"] = 10000
	var made := 0
	for s in st.galaxy.systems:
		if made >= 4:
			break
		if st.system_owner(s.id) < 0 and s.planet_count > 0:
			_claim(st, 0, s.id, Colony.KIND_COLONY, 3 + made)
			made += 1
	var ctx := _ctx(st, 0)
	AiPlayer._victory(ctx)
	var building := 0
	for pid in st.colonies:
		if st.colonies[pid].owner == 0 and st.colonies[pid].construction == "cathedrale":
			building += 1
	_ok(building == 1, "IA : une cathédrale lancée par réflexion")
	for _i in 4:
		AiPlayer._victory(_ctx(st, 0))
	var sites := {}
	for pid in st.colonies:
		var c: Colony = st.colonies[pid]
		if c.owner == 0 and c.construction == "cathedrale":
			sites[st.galaxy.get_planet(pid).system_id] = true
	_ok(sites.size() == 3, "IA : trois cathédrales dans trois systèmes, pas plus (%d)" % sites.size())
	# Ossarane : unit ses lignées à ses alliés de longue date.
	var st2 := _state("ossarane")
	var vael := _id_of(st2, "vael")
	Research.grant(st2, 0, ["lignees_croisees"])
	st2.get_empire(0).resources["influence"] = 500
	st2.get_empire(0).resources["crystals"] = 50
	_meet(st2, 0, vael)
	Diplomacy.sign_treaty(st2, 0, vael, Diplomacy.PEACE)
	Diplomacy.sign_treaty(st2, 0, vael, Diplomacy.ALLIANCE)
	st2.tick += 200
	AiPlayer._victory(_ctx(st2, 0))
	_ok(Victory.united(st2, 0, vael), "IA : Ossarane unit ses lignées à son allié")


func _test_save() -> void:
	var st := _state("ossarane", {"deadline": 10800, "people_victories": true})
	var vael := _id_of(st, "vael")
	_meet(st, 0, vael)
	Diplomacy.sign_treaty(st, 0, vael, Diplomacy.PEACE)
	Diplomacy.sign_treaty(st, 0, vael, Diplomacy.ALLIANCE)
	Diplomacy._rel_w(st, 0, vael)["union"] = 5
	st.get_empire(0).victory["elu"] = {"pct": 40, "held": 60, "warn": 0}
	st.winner = {"empire": 0, "victory": "elu", "tick": 99, "allies": []}
	var d := st.to_dict()
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and back.checksum() == st.checksum(), "sauvegarde : victoires relues à l'identique")
	_ok(back.victory_rules == {"deadline": 10800, "people": true, "conquete": true, "domination": true, "allies": true} and back.winner == st.winner, "sauvegarde : règles et vainqueur")
	_ok(Victory.united(back, 0, vael) and Victory.held(back, 0, "elu") == 60, "sauvegarde : union et compte à rebours")
	# Ancienne sauvegarde (version 10, sans victoires) : sans date limite, capitale d'origine = capitale.
	var old: Dictionary = JSON.parse_string(JSON.stringify(_state("vael").to_dict()))
	old["version"] = 10
	old.erase("victory_rules")
	old.erase("winner")
	for ed: Dictionary in old["empires"]:
		ed.erase("home")
		ed.erase("victory")
	var ost := GameState.from_dict(old)
	_ok(ost != null and Victory.deadline(ost) == 0 and Victory.people_enabled(ost) and ost.winner.is_empty(), "ancienne sauvegarde : se charge sans date limite")
	_ok(ost != null and ost.get_empire(1).home_planet == ost.get_empire(1).capital_planet, "ancienne sauvegarde : capitale d'origine reprise")


func _test_determinism() -> void:
	var a := Simulation.new(GameState.create(77, 150, 1800.0, "", {"spectator": true, "ai_level": "veteran", "deadline": 600}))
	var b := Simulation.new(GameState.create(77, 150, 1800.0, "", {"spectator": true, "ai_level": "veteran", "deadline": 600}))
	a.advance(600)
	b.advance(600)
	_ok(a.state.checksum() == b.state.checksum(), "déterminisme : même partie, mêmes victoires")
	_ok(a.state.winner.get("victory", "") == "score" or not a.state.winner.is_empty(), "une partie entre IA se termine à la date limite")
	var c := Simulation.new(GameState.from_dict(JSON.parse_string(JSON.stringify(a.state.to_dict()))))
	_ok(c.state.checksum() == a.state.checksum(), "déterminisme : sauvegarde relue identique")
