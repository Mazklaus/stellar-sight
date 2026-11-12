extends RefCounted
## Tests des curiosités et des événements (Curios, Events, EventSystem, AiEvents) : placement des
## curiosités, détection, sonde par un vaisseau sans armes (premier arrivé), éclaireur qui attend,
## piège ; tirage mensuel, choix chiffrés, choix par couche d'espèce, pari, réponse par défaut après
## 30 jours, choc des tons au premier contact, IA qui répond le jour même ; sauvegarde 25 et
## déterminisme. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Curiosités et événements…")
	_test_setup()
	_test_detection()
	_test_probe()
	_test_explore_wait()
	_test_trap()
	_test_draw()
	_test_choose()
	_test_layers()
	_test_risky()
	_test_default()
	_test_tones()
	_test_ai()
	_test_save()
	_test_determinism()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(seed_value := 11, faction := "vael", curios := "normales", events := "aucun", ai := "") -> GameState:
	return GameState.create(seed_value, 150, 1800.0, faction, {"ai_level": ai, "curios": curios, "events": events})


## Une curiosité ouverte de niveau <= lvl_max, dans un système sans empire ni flotte : [pid, sid].
func _curio(st: GameState, lvl_max := 2) -> Array:
	var ids := st.curios.keys()
	ids.sort()
	for pid in ids:
		var sid := st.galaxy.get_planet(int(pid)).system_id
		if int(st.curios[pid]["lvl"]) > lvl_max or st.system_owner(sid) >= 0 or Pirates.is_lair(st, sid):
			continue
		var busy := false
		for f: Fleet in st.fleets.values():
			if f.system_id == sid:
				busy = true
		var first := Curios.visible_in(st, 0, sid)
		if not busy and (first.is_empty() or first[0] == int(pid)):
			return [int(pid), sid]
	return [-1, -1]


func _test_setup() -> void:
	var none := _new(11, "vael", "aucune")
	_ok(none.curios.is_empty() and none.curio_density == "aucune", "réglage Aucune : pas de curiosité")
	var st := _new()
	var planets := 0
	for s in st.galaxy.systems:
		planets += s.planet_ids.size()
	_ok(st.curios.size() > planets / 10 and st.curios.size() < planets / 3, "réglage Normales : environ une planète sur six (%d sur %d)" % [st.curios.size(), planets])
	var levels_ok := true
	var near_ok := true
	var types := {}
	for pid in st.curios:
		var c: Dictionary = st.curios[pid]
		var sid := st.galaxy.get_planet(int(pid)).system_id
		levels_ok = levels_ok and int(c["lvl"]) >= 1 and int(c["lvl"]) <= 4 and st.system_owner(sid) < 0
		types[String(c["type"])] = true
		for e in st.empires:
			var j := int(FactionTraits.jumps_from(st.galaxy, FactionTraits.capital_system(st, e.id)).get(sid, 999))
			if j < 2 and int(c["lvl"]) > 1:
				near_ok = false
	_ok(levels_ok, "niveaux 1 à 4, jamais dans un système déjà pris")
	_ok(near_ok, "près des capitales, seulement des curiosités de niveau 1")
	_ok(types.size() == 5, "les cinq types de curiosités sont tirés (%d)" % types.size())
	var again := _new()
	_ok(str(again.curios) == str(st.curios), "même graine, mêmes curiosités")


func _test_detection() -> void:
	var st := _new()
	var high := -1
	for pid in st.curios:
		if int(st.curios[pid]["lvl"]) == 4:
			high = int(pid)
			break
	_ok(high >= 0, "il existe une curiosité de niveau 4")
	if high < 0:
		return
	var sid := st.galaxy.get_planet(high).system_id
	st.get_empire(0).explored[sid] = true
	_ok(Curios.detect(st, 0) == 2 and not Curios.sees(st, 0, high), "détection 2 au départ : le niveau 4 reste invisible")
	st.get_empire(0).techs["capteurs"] = 0
	_ok(Curios.detect(st, 0) == 3 and Curios.power(st, 0) >= 2, "les capteurs améliorent détection et puissance (%d, %d)" % [Curios.detect(st, 0), Curios.power(st, 0)])
	st.get_empire(0).techs["detecteurs_abysse"] = 0
	_ok(Curios.sees(st, 0, high), "avec deux technologies de détection, le niveau 4 apparaît")
	_ok(Curios.known(st, 0).has(high), "la curiosité figure dans la liste des curiosités repérées")


func _test_probe() -> void:
	var sim := Simulation.new(_new())
	var st := sim.state
	var pick := _curio(st, 1)
	_ok(pick[0] >= 0, "une curiosité de niveau 1 est disponible")
	if pick[0] < 0:
		return
	var pid: int = pick[0]
	var sid: int = pick[1]
	st.get_empire(0).explored[sid] = true
	st.get_empire(1).explored[sid] = true
	var d := Curios.duration(st, 0, pid)
	_ok(Curios.power(st, 0) == 2 and d == int(Curios.data()["days_by_gap"]["1"]), "Vael (Raison) : puissance 2 contre niveau 1, %d jours" % d)
	var scout := st.spawn_ship(0, "scout", sid)
	var armed := st.spawn_ship(1, "corvette", sid)
	_ok(Curios.can_probe(st, scout) and not Curios.can_probe(st, armed), "un éclaireur sonde, un vaisseau armé non")
	sim.advance(d - 1)
	_ok(Curios.is_open(st, pid) and Curios.progress(st, 0, pid) == d - 1, "la sonde avance d'un jour par jour")
	st.spawn_ship(1, "scout", sid)
	sim.advance(2)
	_ok(int(st.curios[pid]["done"]) == 0, "la curiosité revient au premier arrivé")
	_ok(not Curios.sees(st, 1, pid) and Curios.target_in(st, 1, sid) != pid and Curios.progress(st, 1, pid) == 0, "une curiosité sondée disparaît pour les autres")
	_ok(int(st.get_empire(0).stats.get("curios", 0)) == 1, "la sonde est comptée (eurêkas, héros)")
	var found := false
	for c: Dictionary in st.chronicle:
		if String(c["text"]).find(Curios.curio_name(st, pid)) >= 0:
			found = true
	_ok(found, "la chronique raconte la sonde")
	# Récompense chiffrée : selon le niveau et l'ère.
	_ok(Curios.amount(st, 0, 1, "energy") == 40 and Curios.amount(st, 0, 4, "energy") == 250, "montants par niveau (40 à 250 à l'ère I)")
	_ok(Curios.amount(st, 0, 3, "crystals") == 25, "cristaux : un sixième")


func _test_explore_wait() -> void:
	var sim := Simulation.new(_new())
	var st := sim.state
	var pick := _curio(st, 1)
	if pick[0] < 0:
		return
	var sid: int = pick[1]
	st.get_empire(0).explored[sid] = true
	var scout := st.spawn_ship(0, "scout", sid)
	scout.standing_order = Fleet.ORDER_EXPLORE
	_ok(Curios.wants_to_stay(st, scout), "un éclaireur en exploration automatique s'arrête sonder une curiosité rapide")
	sim.advance(3)
	_ok(scout.system_id == sid and not scout.is_moving(), "il reste sur place pendant la sonde")


func _test_trap() -> void:
	var sim := Simulation.new(_new())
	var st := sim.state
	var pick := _curio(st, 4)
	if pick[0] < 0:
		return
	var sid: int = pick[1]
	var f := Curios.spawn_trap(st, sid, 2)
	_ok(f != null and f.owner == GameState.PIRATE_ID and st.fleets.has(f.id), "piège : une flotte pirate surgit")
	sim.advance(int(Curios.data()["trap_days"]) + 2)
	_ok(not st.fleets.has(f.id) and st.curio_traps.is_empty(), "la flotte du piège repart au bout de 120 jours")


func _test_draw() -> void:
	var st := _new(17, "vael", "aucune", "frequents")
	_ok(Events.enabled(st) and st.event_freq == "frequents", "réglage Fréquents")
	var sim := Simulation.new(st)
	sim.advance(int(Events.data()["first_day"]) - 2)
	_ok(st.ev_meta.is_empty() or Events.inbox(st, 0).is_empty() and (Events.meta(st, 0)["log"] as Array).is_empty(), "aucun événement avant le jour 180")
	sim.advance(1500)
	var drawn := 0
	for eid in st.ev_meta:
		drawn += (st.ev_meta[eid]["log"] as Array).size() + (st.ev_meta[eid]["inbox"] as Array).size()
	_ok(drawn >= st.empires.size() * 3, "en quatre ans, plusieurs événements par empire (%d)" % drawn)
	var seen_twice := false
	for eid in st.ev_meta:
		var cards := {}
		for x: Dictionary in st.ev_meta[eid]["log"]:
			if cards.has(String(x["card"])) and not bool(Events.card(String(x["card"])).get("repeat", false)):
				seen_twice = true
			cards[String(x["card"])] = true
	_ok(not seen_twice, "une carte ne tombe qu'une fois par empire")
	var none := Simulation.new(_new(17, "vael", "aucune", "aucun"))
	none.advance(400)
	_ok(none.state.ev_meta.is_empty(), "réglage Aucun : pas d'événement")


func _test_choose() -> void:
	var sim := Simulation.new(_new(11, "vael", "aucune", "normaux"))
	var st := sim.state
	var home := FactionTraits.capital_system(st, 0)
	var e := st.get_empire(0)
	e.resources["food"] = 500
	e.resources["energy"] = 100
	var added: Array[Dictionary] = []
	Events.push(st, 0, "fete_moissons", {"system": home}, added)
	var item: Dictionary = Events.inbox(st, 0)[0]
	var opts := Events.choices(st, 0, item)
	_ok(opts.size() == 3 and bool(opts[1]["ok"]), "la fête des moissons propose trois choix")
	_ok(String(opts[1]["lines"][0]).find("60") >= 0, "les effets sont chiffrés (%s)" % str(opts[1]["lines"]))
	_ok(Events.check_choose(st, 0, int(item["id"]), 7) != "", "un choix inexistant est refusé")
	sim.submit(SimCommands.event_choose(0, int(item["id"]), 1))
	sim.flush_commands()
	_ok(int(e.resources["food"]) == 420 and int(e.resources["energy"]) == 160, "le choix s'applique (nourriture %d, énergie %d)" % [int(e.resources["food"]), int(e.resources["energy"])])
	_ok(Events.inbox(st, 0).is_empty() and (Events.meta(st, 0)["log"] as Array).size() == 1, "la carte passe au journal")
	# Choix trop cher : grisé, avec la raison.
	e.resources["food"] = 10
	Events.push(st, 0, "fete_moissons", {"system": home}, added)
	var it2: Dictionary = Events.inbox(st, 0)[0]
	var o2 := Events.choices(st, 0, it2)
	_ok(not bool(o2[0]["ok"]) and String(o2[0]["why"]).begins_with("pas assez"), "un choix trop cher est refusé (%s)" % String(o2[0]["why"]))
	_ok(not sim.submit(SimCommands.event_choose(0, int(it2["id"]), 0)) or Events.inbox(st, 0).size() == 1, "l'ordre trop cher n'est pas appliqué")
	sim.flush_commands()
	_ok(Events.inbox(st, 0).size() == 1, "la carte reste dans la boîte")
	# Effet de stabilité : visible dans le détail de la stabilité.
	e.resources["food"] = 500
	sim.submit(SimCommands.event_choose(0, int(it2["id"]), 0))
	sim.flush_commands()
	var found := false
	for p in Stability.parts(st, home):
		if String(p[0]) == "La fête des moissons":
			found = true
	_ok(found or not Stability.applies(st, 0), "la fête apparaît dans le détail de la stabilité")


func _test_layers() -> void:
	var a := _new(11, "choeur", "aucune", "normaux")
	var b := _new(11, "vael", "aucune", "normaux")
	var added: Array[Dictionary] = []
	for st: GameState in [a, b]:
		Events.push(st, 0, "comete", {"system": FactionTraits.capital_system(st, 0)}, added)
	var oa := Events.choices(a, 0, Events.inbox(a, 0)[0])
	var ob := Events.choices(b, 0, Events.inbox(b, 0)[0])
	_ok(oa.size() == 3 and ob.size() == 2, "le choix réservé à la Foi n'apparaît que pour le Chœur (%d / %d)" % [oa.size(), ob.size()])
	_ok(String(oa[2]["tag"]) != "", "le choix de couche porte une étiquette (%s)" % String(oa[2]["tag"]))
	_ok(Events.layer_value(a, 0, "registre") == "Grimdark" and Events.layer_value(a, 0, "credo") == "foi", "couches lues sur le peuple")
	_ok(not Events.conditions_ok(b, 0, {"layers": {"gouvernement": ["feodalite"]}}, {}) and Events.conditions_ok(_new(11, "ossarane"), 0, {"layers": {"gouvernement": ["feodalite"]}}, {}),
			"une carte de féodalité ne tombe que chez Ossarane")


func _test_risky() -> void:
	var results := {}
	for s in [3, 5, 7, 9, 13, 21, 34, 55]:
		var st := _new(s, "vael", "aucune", "normaux")
		var e := st.get_empire(0)
		e.resources["energy"] = 500
		var added: Array[Dictionary] = []
		Events.push(st, 0, "comete", {"system": FactionTraits.capital_system(st, 0)}, added)
		var item: Dictionary = Events.inbox(st, 0)[0]
		var idx := -1
		for o: Dictionary in Events.choices(st, 0, item):
			if bool(o["risky"]):
				idx = int(o["index"])
		if idx < 0:
			continue
		Events.choose(st, 0, int(item["id"]), idx, added)
		var label := String((Events.meta(st, 0)["log"] as Array)[0]["label"])
		results["win" if label.find("réussite") >= 0 else ("lose" if label.find("échec") >= 0 else "?")] = true
	_ok(results.has("win") and results.has("lose") and not results.has("?"), "un pari peut réussir ou échouer selon la graine (%s)" % str(results.keys()))


func _test_default() -> void:
	var sim := Simulation.new(_new(11, "vael", "aucune", "normaux"))
	var st := sim.state
	st.get_empire(0).resources["food"] = 500
	var added: Array[Dictionary] = []
	Events.push(st, 0, "fete_moissons", {"system": FactionTraits.capital_system(st, 0)}, added)
	sim.advance(int(Events.data()["answer_days"]) + 1)
	var log: Array = Events.meta(st, 0)["log"]
	_ok(Events.inbox(st, 0).is_empty() and log.size() == 1 and int(log[0]["choice"]) == 1, "sans réponse en 30 jours, le choix par défaut s'applique")


func _test_tones() -> void:
	var st := GameState.create(11, 150, 1800.0, "vael", {"ai_level": "", "events": "normaux"})
	var a := st.get_empire(0)
	var b: Empire = null
	for e in st.empires:
		if e.faction_id == "choeur":
			b = e
	if b == null:
		var st2 := GameState.create(11, 150, 1800.0, "vael", {"ai_level": "", "events": "normaux", "rivals": ["choeur"]})
		st = st2
		a = st.get_empire(0)
		for e in st.empires:
			if e.faction_id == "choeur":
				b = e
	_ok(b != null, "le Chœur est dans la partie")
	if b == null:
		return
	var added: Array[Dictionary] = []
	Events.on_contact(st, a, b, added)
	var ca: Array = Events.inbox(st, a.id).map(func(it: Dictionary) -> String: return String(it["card"]))
	var cb: Array = Events.inbox(st, b.id).map(func(it: Dictionary) -> String: return String(it["card"]))
	_ok(ca.has("t_heros_fanatiques") and cb.has("t_heros_fanatiques"), "Space opera contre Grimdark : chacun reçoit la carte du choc des tons")
	var mem := false
	for m: Dictionary in st.memories:
		if String(m["kind"]) == "tones_clash" and int(m["who"]) == a.id and int(m["about"]) == b.id:
			mem = true
	_ok(mem, "le souvenir du choc des tons est posé d'office")
	Events.on_contact(st, a, b, added)
	_ok(Events.inbox(st, a.id).size() == ca.size(), "la carte ne revient pas")


func _test_ai() -> void:
	var sim := Simulation.new(_new(23, "vael", "normales", "frequents", "normal"))
	var st := sim.state
	sim.advance(900)
	var ai_waiting := 0
	var ai_answered := 0
	for e in st.empires:
		if e.id == 0 or not st.ev_meta.has(e.id):
			continue
		ai_waiting += (st.ev_meta[e.id]["inbox"] as Array).size()
		ai_answered += (st.ev_meta[e.id]["log"] as Array).size()
	_ok(ai_answered > 0 and ai_waiting <= 1, "les IA répondent à leurs événements (%d réponses, %d en attente)" % [ai_answered, ai_waiting])
	var probed := 0
	for pid in st.curios:
		if int(st.curios[pid]["done"]) > 0:
			probed += 1
	_ok(probed > 0, "les éclaireurs des IA sondent des curiosités (%d)" % probed)
	# Valeur d'un choix : un belliqueux aime les paris plus qu'un pacifique.
	var added: Array[Dictionary] = []
	Events.push(st, 1, "comete", {"system": FactionTraits.capital_system(st, 1)}, added)
	var item: Dictionary = Events.inbox(st, 1).back()
	var risky := -1
	for o: Dictionary in Events.choices(st, 1, item):
		if bool(o["risky"]):
			risky = int(o["index"])
	_ok(risky >= 0 and AiEvents.value(st, 1, item, risky, 2) > AiEvents.value(st, 1, item, risky, -2), "un belliqueux prise davantage un pari qu'un pacifique")


func _test_save() -> void:
	var sim := Simulation.new(_new(13, "vael", "normales", "frequents"))
	var st := sim.state
	sim.advance(400)
	var pick := _curio(st, 2)
	if pick[0] >= 0:
		st.get_empire(0).explored[pick[1]] = true
		st.spawn_ship(0, "scout", pick[1])
		sim.advance(5)
	var added: Array[Dictionary] = []
	Events.push(st, 0, "fete_moissons", {"system": FactionTraits.capital_system(st, 0)}, added)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_snapshot())))
	_ok(back != null, "sauvegarde 25 relue")
	if back == null:
		return
	_ok(back.checksum() == st.checksum(), "même empreinte après sauvegarde (curiosités, boîte, journal)")
	_ok(back.curio_density == "normales" and back.event_freq == "frequents" and back.curios.size() == st.curios.size(), "réglages et curiosités relus")
	if pick[0] >= 0:
		_ok(Curios.progress(back, 0, pick[0]) == Curios.progress(st, 0, pick[0]), "avancement des sondes relu")
	var a := Simulation.new(st)
	var b := Simulation.new(back)
	a.advance(200)
	b.advance(200)
	_ok(a.state.checksum() == b.state.checksum(), "la partie reprise continue à l'identique")
	var old := st.to_snapshot()
	old["version"] = 24
	for k in ["curios", "curio_traps", "curio_density", "ev_meta", "next_event_id", "event_freq"]:
		old.erase(k)
	var o := GameState.from_dict(JSON.parse_string(JSON.stringify(old)))
	_ok(o != null and o.curios.is_empty() and not Events.enabled(o), "une sauvegarde 24 se relit (sans curiosités ni événements)")


func _test_determinism() -> void:
	var a := Simulation.new(GameState.create(53, 150, 1800.0, "", {"curios": "nombreuses", "events": "frequents"}))
	var b := Simulation.new(GameState.create(53, 150, 1800.0, "", {"curios": "nombreuses", "events": "frequents"}))
	a.advance(900)
	b.advance(900)
	_ok(a.state.checksum() == b.state.checksum() and not a.state.ev_meta.is_empty(), "même graine, mêmes curiosités et événements après 900 jours")
