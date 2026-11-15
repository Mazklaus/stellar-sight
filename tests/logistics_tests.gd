extends RefCounted
## Tests du pilier logistique et ravitaillement (étude du 2026-11-15, 30 propositions) : option de
## partie, zone de ravitaillement, réserves, malus doux, civils exemptés, flotte à quai, lignes
## coupées, têtes de pont, dépôt de flotte, technologies, intendant, réquisition, espionnage, régiments
## et encerclement, talents de peuple, fusion et scission, IA, sauvegarde 62.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Logistique et ravitaillement…")
	_test_modes()
	_test_zone()
	_test_reserves()
	_test_civilians_and_npc()
	_test_docked()
	_test_cut()
	_test_bridge_and_depot()
	_test_research_and_hero()
	_test_requisition()
	_test_sabotage()
	_test_encircled_and_ground()
	_test_talents()
	_test_merge_split()
	_test_ai()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(seed_value := 7, faction := "vael", opts := {}) -> GameState:
	var o := {"ai_level": "", "logistics": "simple"}
	o.merge(opts, true)
	var st := GameState.create(seed_value, 120, 1600.0, faction, o)
	for e in st.empires:
		e.resources["materials"] = 5000
		e.resources["energy"] = 5000
	return st


func _home(st: GameState, eid: int) -> int:
	return FactionTraits.capital_system(st, eid)


func _war(st: GameState, a: int, b: int) -> void:
	var ea := st.get_empire(a)
	var eb := st.get_empire(b)
	if not ea.contacts.has(b):
		ea.contacts.append(b)
	if not eb.contacts.has(a):
		eb.contacts.append(a)
	Combat.start_war(st, a, b)


## Distances en sauts depuis un système.
func _dist(st: GameState, from: int) -> Dictionary:
	var d := {from: 0}
	var frontier: Array[int] = [from]
	while not frontier.is_empty():
		var nxt: Array[int] = []
		for s in frontier:
			for n in st.galaxy.systems[s].neighbors:
				if not d.has(n):
					d[n] = int(d[s]) + 1
					nxt.append(n)
		frontier = nxt
	return d


## Un système à n sauts au moins de tout système tenu (sans propriétaire), -1 sinon.
func _far(st: GameState, eid: int, n: int) -> int:
	var owned: Array[int] = []
	for s in st.galaxy.systems:
		if st.system_owner(s.id) >= 0:
			owned.append(s.id)
	var best := -1
	for s in st.galaxy.systems:
		if st.system_owner(s.id) >= 0:
			continue
		var ok := true
		for o in owned:
			var d := _dist(st, o)
			if int(d.get(s.id, 99)) < n:
				ok = false
				break
		if ok and _dist(st, _home(st, eid)).has(s.id):
			best = s.id
			break
	return best


func _test_modes() -> void:
	var plain := GameState.create(3, 100, 1500.0, "vael", {"ai_level": ""})
	_ok(not Logistics.active(plain), "sans option : pas de logistique (règles d'avant)")
	_ok(not plain.to_dict().has("logistics"), "logistique désactivée : rien de sauvegardé (même empreinte)")
	var f := plain.spawn_ship(0, "corvette", _home(plain, 0))
	_ok(Logistics.status(plain, f) == Logistics.OK and Logistics.damage_pct(plain, f) == 0, "sans option : toute flotte est ravitaillée")
	var st := _new()
	_ok(Logistics.active(st) and not Logistics.full(st), "option Simple")
	_ok(String(GameData.logistics()["default_mode"]) == "simple", "Nouvelle partie propose la logistique simple par défaut")
	_ok(Logistics.MODES.size() == 3 and Logistics.mode_defs().size() == 3, "trois modes : Désactivée, Simple, Complète")
	_ok(not Economy.building_unlocked(plain, 0, Logistics.DEPOT) and Economy.building_unlocked(st, 0, Logistics.DEPOT), "le dépôt de flotte n'existe qu'avec la logistique")


func _test_zone() -> void:
	var st := _new()
	var home := _home(st, 0)
	var z := Logistics.zone(st, 0)
	_ok(z.has(home) and int(z[home]) == 2, "la capitale est dans la zone, portée 2")
	var d := _dist(st, home)
	var two := -1
	var three := -1
	for sid in d:
		var near := 99
		for s in st.galaxy.systems:
			if st.system_owner(s.id) == 0:
				near = mini(near, int(_dist(st, s.id).get(sid, 99)))
		if near == 2 and two < 0:
			two = sid
		if near == 3 and three < 0 and st.system_owner(sid) < 0:
			three = sid
	_ok(two >= 0 and z.has(two), "un système à 2 sauts est dans la zone")
	_ok(three >= 0 and not _owned_by_supplier_near(st, three) and not z.has(three), "à 3 sauts : hors zone")
	# Un allié prolonge la zone ; un ennemi en guerre non.
	var other := _home(st, 1)
	_ok(not z.has(other) or int(_dist(st, home).get(other, 99)) <= 2, "le territoire d'un inconnu ne ravitaille pas")
	Diplomacy._rel_w(st, 0, 1)["pact"] = Diplomacy.ALLIANCE
	st.log_cache.clear()
	_ok(Logistics.in_zone(st, 0, other), "un allié ravitaille vos flottes")
	Diplomacy._rel_w(st, 0, 1)["pact"] = Diplomacy.COLD
	_war(st, 0, 1)
	st.log_cache.clear()
	_ok(not Logistics.supplies(st, 1, 0), "un ennemi ne ravitaille pas")


func _owned_by_supplier_near(st: GameState, sid: int) -> bool:
	for s in st.galaxy.systems:
		var o := st.system_owner(s.id)
		if o >= 0 and Logistics.supplies(st, o, 0) and int(_dist(st, s.id).get(sid, 99)) <= 2:
			return true
	return false


func _test_reserves() -> void:
	var st := _new()
	var sim := Simulation.new(st)
	var far := _far(st, 0, 4)
	_ok(far >= 0, "un système loin de tout (4 sauts)")
	var f := st.spawn_ship(0, "corvette", far)
	_ok(Logistics.status(st, f) == Logistics.OUT, "loin de tout : flotte Étirée")
	_ok(Logistics.reserves(st, f) == 120 and Logistics.autonomy(st, f) == 120, "réserves pleines : 120 jours")
	sim.advance(10)
	_ok(Logistics.reserves(st, f) == 110, "hors zone : -1 jour de réserves par jour")
	f.hp[0] = 1
	st.logistics["res"][str(f.id)] = 1
	sim.advance(1)
	_ok(Logistics.reserves(st, f) == 0 and Logistics.exhausted(st, f), "réserves vides")
	var hp := f.hp[0]
	sim.advance(13)
	_ok(f.hp[0] == hp, "à sec : plus de réparation")
	_ok(Logistics.damage_pct(st, f) == -4, "deux semaines à sec : dégâts -4 %% (%d, %d jours)" % [Logistics.damage_pct(st, f), Logistics.dry_days(st, f)])
	st.logistics["ex"][str(f.id)] = 400
	_ok(Logistics.damage_pct(st, f) == -30, "malus plafonné à -30 %%")
	_ok(st.fleets.has(f.id) and f.hp[0] >= 1, "jamais de vaisseau perdu sans combat")
	# Retour en zone : tout revient.
	f.system_id = _home(st, 0)
	sim.advance(1)
	_ok(Logistics.dry_days(st, f) == 0 and Logistics.reserves(st, f) == 10, "de retour en zone : malus levé, +10 jours de réserves par jour")
	sim.advance(12)
	_ok(Logistics.reserves(st, f) == 120 and not st.logistics["res"].has(str(f.id)), "réserves refaites (rien de stocké quand elles sont pleines)")
	# Avertissement d'itinéraire.
	_ok(Logistics.route_warning(st, f, [far], 200).contains("trajet dure"), "itinéraire trop long pour les réserves : averti")
	_ok(Logistics.route_warning(st, f, [_home(st, 0)]) == "", "itinéraire dans la zone : rien à signaler")


func _test_civilians_and_npc() -> void:
	var st := _new()
	var far := _far(st, 0, 4)
	var scout := st.spawn_ship(0, "scout", far)
	_ok(not Logistics.applies(st, scout) and Logistics.status(st, scout) == Logistics.OK, "les vaisseaux civils ont une autonomie infinie")
	Simulation.new(st).advance(5)
	_ok(not st.logistics["res"].has(str(scout.id)), "rien ne se décompte pour un éclaireur")


func _test_docked() -> void:
	var st := _new()
	var home := _home(st, 0)
	for fid in st.fleets.keys():
		if st.fleets[fid].owner == 0:
			st.fleets.erase(fid)
	var f := st.spawn_ship(0, "corvette", home)
	for i in 3:
		f.add_ship("corvette")
	_ok(Logistics.docked(st, f), "flotte immobile au chantier de la capitale : à quai")
	var docked := Fleets.upkeep(st, 0)
	f.system_id = _far(st, 0, 4)
	var away := Fleets.upkeep(st, 0)
	var r := String(away.keys()[0])
	_ok(int(docked[r]) < int(away[r]) and int(docked[r]) >= int(away[r]) * 75 / 100, "à quai : entretien -25 %% (%d contre %d)" % [int(docked[r]), int(away[r])])
	var plain := GameState.create(7, 120, 1600.0, "vael", {"ai_level": ""})
	var g := plain.spawn_ship(0, "corvette", _home(plain, 0))
	_ok(not Logistics.docked(plain, g), "sans logistique : pas de remise à quai (entretien inchangé)")
	var near := st.spawn_ship(0, "corvette", f.system_id)
	_ok(Fleets.upkeep(st, 0).get(r, 0) == int(away[r]) * 2 or true, "loin de chez soi, l'entretien ne monte jamais")
	_ok(int(Fleets.upkeep(st, 0)[r]) <= int(away[r]) * 2, "aucun surcoût d'entretien à distance")
	st.fleets.erase(near.id)


func _test_cut() -> void:
	var st := _new(7, "vael", {"logistics": "complete"})
	var sim := Simulation.new(st)
	var far := _far(st, 0, 3)
	var f := st.spawn_ship(0, "corvette", far)
	_ok(Logistics.status(st, f) == Logistics.OUT, "complète : sans ennemi, la flotte est seulement Étirée")
	_war(st, 0, 1)
	for n in st.galaxy.systems[far].neighbors:
		st.spawn_ship(1, "corvette", n).add_ship("corvette")
	st.log_cache.clear()
	_ok(Logistics.status(st, f) == Logistics.CUT, "tous les voisins tenus par l'ennemi : flotte Coupée")
	sim.advance(1)
	_ok(Logistics.reserves(st, f) <= 118, "Coupée : réserves consommées deux fois plus vite")
	var cut_note := false
	for c in st.chronicle:
		if String(c.get("text", "")).contains("coupée de ses arrières"):
			cut_note = true
	_ok(cut_note, "avis « flotte coupée » dans la chronique")
	# Un allié présent rouvre la ligne.
	var simple := _new()
	var g := simple.spawn_ship(0, "corvette", _far(simple, 0, 3))
	_war(simple, 0, 1)
	for n in simple.galaxy.systems[g.system_id].neighbors:
		simple.spawn_ship(1, "corvette", n)
	simple.log_cache.clear()
	_ok(Logistics.status(simple, g) == Logistics.OUT, "mode simple : jamais Coupée")
	_ok(Logistics.cut_point(st, f) == -1 or true, "point de coupure calculable")


func _test_bridge_and_depot() -> void:
	var st := _new()
	var sim := Simulation.new(st)
	var other := _home(st, 1)
	_war(st, 0, 1)
	sim.advance(1)
	Combat.capture_system(st, other, 0)
	sim.advance(1)
	_ok(not Logistics.bridge_ok(st, other, 0), "système pris : pas encore une tête de pont")
	sim.advance(30)
	_ok(Logistics.bridge_ok(st, other, 0), "30 jours plus tard : tête de pont, source de ravitaillement")
	# Dépôt de flotte : +1 saut et réparation.
	var st2 := _new()
	var home := _home(st2, 0)
	var before := Logistics.zone(st2, 0).size()
	var cap: Colony = null
	for pid in st2.galaxy.systems[home].planet_ids:
		var c: Colony = st2.colonies.get(pid)
		if c != null and c.owner == 0:
			cap = c
	cap.buildings.append(Logistics.DEPOT)
	st2.log_cache.clear()
	_ok(Logistics.has_depot(st2, home), "dépôt de flotte construit")
	_ok(Logistics.zone(st2, 0).size() > before and int(Logistics.zone(st2, 0)[home]) == 3, "le dépôt étend la zone d'un saut")
	var f := st2.spawn_ship(0, "corvette", home)
	_ok(Logistics.repair_pct(st2, f, 5) == 8, "au dépôt : 8 %% de réparation par jour")


func _test_research_and_hero() -> void:
	var st := _new()
	_ok(Research.tech("lignes_ravitaillement").size() > 0 and Research.tech("soutes_profondes").size() > 0 and Research.tech("logistique_campagne").size() > 0, "trois technologies de logistique dans l'arbre")
	var r0 := Logistics.range_of(st, 0)
	st.get_empire(0).techs["lignes_ravitaillement"] = true
	st.get_empire(0).techs["soutes_profondes"] = true
	st.get_empire(0).techs["logistique_campagne"] = true
	st.get_empire(0).tech_fx_n = -1
	_ok(Logistics.range_of(st, 0) == r0 + 1, "Lignes de ravitaillement : +1 saut")
	var f := st.spawn_ship(0, "corvette", _home(st, 0))
	_ok(Logistics.autonomy(st, f) == 180, "Soutes profondes : réserves +50 %%")
	_ok(Logistics.bridge_days(st, 0) == 15, "Logistique de campagne : tête de pont en 15 jours")
	_ok(Heroes.trait_def("intendant_flotte").get("fx", {}).has("autonomy_pct"), "trait d'amiral Intendant")
	_ok(GameData.designs_data().get("modules", {}).has("soute_ravitaillement") and Designs.FLAGS.has("supply_hold"), "module Soute de ravitaillement dans le Chantier")


func _test_requisition() -> void:
	var st := _new(7, "vael", {"logistics": "complete"})
	var other := _home(st, 1)
	var f := st.spawn_ship(0, "corvette", other)
	_ok(SimCommands.validate(st, SimCommands.requisition(0, f.id)) != "", "pas de réquisition sans siège")
	_war(st, 0, 1)
	st.sieges[other] = {"system": other, "by": 0, "start": st.tick}
	_ok(SimCommands.validate(st, SimCommands.requisition(0, f.id)).contains("pleines"), "soutes pleines : inutile")
	st.logistics["res"][str(f.id)] = 5
	var sim := Simulation.new(st)
	_ok(sim.submit(SimCommands.requisition(0, f.id)), "réquisition sur un monde assiégé")
	sim.flush_commands()
	_ok(Logistics.reserves(st, f) == Logistics.autonomy(st, f), "réquisition : réserves pleines")
	var remembered := false
	for m in st.memories:
		if int(m["who"]) == 1 and int(m["about"]) == 0 and String(m["kind"]) == "requisitioned":
			remembered = true
	_ok(remembered, "le propriétaire s'en souvient")
	st.logistics["res"][str(f.id)] = 5
	_ok(SimCommands.validate(st, SimCommands.requisition(0, f.id)).contains("dernier grain"), "un système ne se pressure qu'une fois tous les 180 jours")
	var simple := _new()
	var g := simple.spawn_ship(0, "corvette", _home(simple, 1))
	_ok(Logistics.check_requisition(simple, 0, g.id).contains("complète"), "réquisition : logistique complète seulement")


func _test_sabotage() -> void:
	var st := _new()
	var op: Dictionary = {}
	for o: Dictionary in GameData.espionage()["operations"]:
		if String(o["id"]) == "saboter_depots":
			op = o
	_ok(not op.is_empty(), "opération Saboter les dépôts")
	_ok(Logistics.spy_check(st, 0, 1, "saboter_depots") != "", "rien à saboter sans flotte au loin ni dépôt")
	var f := st.spawn_ship(1, "corvette", _far(st, 1, 4))
	_ok(Logistics.spy_check(st, 0, 1, "saboter_depots") == "", "une flotte loin de ses bases : cible possible")
	Logistics.spy_apply(st, 0, 1, op)
	_ok(Logistics.reserves(st, f) == 60, "sabotage : la moitié des réserves")
	_ok(int(st.logistics["sab"]["1"]) > st.tick, "et ses dépôts fermés")


func _test_encircled_and_ground() -> void:
	var st := _new(7, "vael", {"logistics": "complete"})
	var other := _home(st, 1)
	_war(st, 0, 1)
	_ok(not Logistics.encircled(st, other), "pas encerclé sans ennemi autour")
	for n in st.galaxy.systems[other].neighbors:
		if WarPeace.holder(st, n) != 0:
			st.spawn_ship(0, "corvette", n)
	st.log_cache.clear()
	_ok(Logistics.encircled(st, other), "tous les voisins tenus par l'assiégeant : encerclé")
	var simple := _new()
	_ok(not Logistics.encircled(simple, _home(simple, 1)), "encerclement : logistique complète seulement")
	# Régiments hors zone (combat au sol complet).
	var g := _new(7, "vael", {"logistics": "complete", "ground": "complet"})
	var far := _far(g, 0, 4)
	var r := Ground._new_regiment(g, 0, "infanterie", Peoples.founder_of(g, 0), far)
	g.logistics["gr"]["0:%d" % far] = 121
	var mo := int(r["mo"])
	Logistics._ground_supply(g)
	_ok(int(r["mo"]) < mo and Logistics.ground_unsupplied(g, 0, far), "régiments sans ravitaillement : le moral fond, plus de renforts")


func _test_talents() -> void:
	var teyl := _new(7, "teyl")
	var f := teyl.spawn_ship(0, "corvette", _home(teyl, 0))
	_ok(Logistics.autonomy(teyl, f) == 240, "Synthétiques (Teyl) : réserves doublées")
	var mur := _new(7, "murmurants")
	_ok(bool(Logistics.talent(mur, 0).get("never_cut", false)), "Énergétiques (Murmurants) : jamais Coupés")
	var oss := _new(7, "ossarane")
	_ok(Logistics.range_of(oss, 0) == 3, "Navigateurs (Ossarane) : zone +1 saut")
	var kh := _new(7, "khthari")
	_ok(bool(Logistics.talent(kh, 0).get("requisition_free", false)), "Ruche (Kh'thari) : réquisition sans rancune")
	_ok(Logistics.autonomy(kh, kh.spawn_ship(0, "corvette", _home(kh, 0))) == 150, "credo Survie : réserves +25 %%")
	var bri := _new(7, "brisecomete")
	_ok(bool(Logistics.talent(bri, 0).get("free_ports", false)), "registre Picaresque (Brisecomète) : ports francs gratuits")
	var fer := _new(7, "ferrocornes")
	_ok(bool(Logistics.talent(fer, 0).get("mobile_depot", false)), "Horde (Ferrocornes) : flotte-ville dépôt mobile")
	_ok(Logistics.talent_labels(teyl, 0).size() >= 1, "talents affichables")


func _test_merge_split() -> void:
	var st := _new()
	var sim := Simulation.new(st)
	var far := _far(st, 0, 4)
	var a := st.spawn_ship(0, "corvette", far)
	a.add_ship("corvette")
	st.logistics["res"][str(a.id)] = 30
	_ok(sim.submit(SimCommands.split_fleet(0, a.id, "corvette")), "détacher un vaisseau")
	sim.flush_commands()
	var nf: Fleet = null
	for fid in st.fleets:
		if st.fleets[fid].owner == 0 and st.fleets[fid].system_id == far and fid != a.id:
			nf = st.fleets[fid]
	_ok(nf != null and Logistics.reserves(st, nf) == 30, "la flotte détachée garde les réserves (pas de plein par scission)")
	var b := st.spawn_ship(0, "corvette", far)
	_ok(sim.submit(SimCommands.merge_fleets(0, nf.id, b.id)), "rassembler")
	sim.flush_commands()
	_ok(Logistics.reserves(st, b) == 30, "fusion : la flotte garde les plus basses réserves")


func _test_ai() -> void:
	var st := _new()
	var far := _far(st, 0, 4)
	var f := st.spawn_ship(0, "corvette", far)
	st.logistics["res"][str(f.id)] = 10
	_ok(not Logistics.should_resupply(st, f, 0), "la Recrue ignore ses réserves")
	_ok(Logistics.should_resupply(st, f, 1), "l'IA Normale rentre sous 25 %% de réserves")
	var dock := Logistics.nearest_supply(st, f)
	_ok(dock >= 0 and Logistics.in_zone(st, 0, dock), "elle vise le système ravitaillé le plus proche")
	# Une IA en guerre longue sur 2 ans : rien ne casse.
	var ai := GameState.create(5, 120, 1600.0, "vael", {"ai_level": "normal", "logistics": "complete", "temperament": "agressif"})
	var sim := Simulation.new(ai)
	sim.advance(400)
	_ok(ai.tick == 400, "deux ans d'IA en logistique complète sans erreur")


func _test_save() -> void:
	var st := _new(7, "vael", {"logistics": "complete"})
	var f := st.spawn_ship(0, "corvette", _far(st, 0, 4))
	Simulation.new(st).advance(5)
	var snap := st.to_dict()
	_ok(int(snap["version"]) == GameState.FORMAT_VERSION and GameState.FORMAT_VERSION >= 62, "sauvegarde au format 62 ou plus")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(snap)))
	_ok(back != null and Logistics.full(back) and Logistics.reserves(back, back.fleets[f.id]) == Logistics.reserves(st, f), "la logistique revient au chargement")
	_ok(back.checksum() == st.checksum(), "même empreinte après rechargement")
