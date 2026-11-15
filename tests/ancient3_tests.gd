extends RefCounted
## Tests des ponts des puissances anciennes (AncientsBridges, lot 3) : guerre sainte (colonisation,
## prise, bombardement), consécration et pèlerinage, reliques-clés (cachées, bouclier contre les
## ultimatums), coffres d'une ancienne abattue, trait Ami des anciens, talents par couche, origine
## Rejeton (même sans l'option) ; sauvegarde.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Ponts des anciennes…")
	_test_holy_war()
	_test_consecrate()
	_test_relics()
	_test_vaults()
	_test_friend()
	_test_talents()
	_test_scion()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(kinds: Array, extra := {}, faction := "vael") -> GameState:
	var o := {"ai_level": "", "ancients": "aucune", "curios": "normales", "faiths": "actives"}
	o.merge(extra, true)
	var st := GameState.create(11, 160, 1800.0, faction, o)
	st.ancients = {"mode": "normal", "wake": true, "list": {}, "holy": {}, "worlds": {}, "boons": {}}
	var starts: Array = []
	for e in st.empires:
		starts.append(FactionTraits.jumps_from(st.galaxy, FactionTraits.capital_system(st, e.id)))
	var homes: Array[int] = []
	for k in kinds:
		var pocket := Ancients._pick_pocket(st, String(k), starts, homes)
		if pocket.is_empty():
			continue
		homes.append(pocket[0])
		Ancients.create(st, String(k), pocket)
	AncientsBridges.place_relics(st)
	return st


func _cards(st: GameState, eid: int, card: String) -> int:
	var n := 0
	for it: Dictionary in Events.inbox(st, eid):
		if String(it["card"]) == card:
			n += 1
	return n


func _holy(st: GameState, id: int) -> int:
	for pid in st.ancients["holy"]:
		if int(st.ancients["holy"][pid]) == id and not st.colonies.has(int(pid)):
			return int(pid)
	return -1


func _test_holy_war() -> void:
	var st := _new(["hierophantes"])
	var id := Ancients.id_of_kind(st, "hierophantes")
	var pid := _holy(st, id)
	_ok(id >= 0 and pid >= 0, "Hiérophantes et Mondes saints placés")
	if pid < 0:
		return
	AncientsBridges.on_colonize(st, 0, pid)
	_ok(Ancients.at_war_with(st, id, 0), "coloniser un Monde saint : guerre sainte")
	_ok(not Ancients.asleep(st, id), "les Hiérophantes s'éveillent aussitôt, avant l'an 20")
	_ok(_cards(st, 0, "anc_guerre_sainte") == 1, "fenêtre de guerre sainte")
	var st2 := _new(["hierophantes"])
	var id2 := Ancients.id_of_kind(st2, "hierophantes")
	var pid2 := _holy(st2, id2)
	AncientsBridges.on_bombard(st2, st2.galaxy.get_planet(pid2).system_id, 1)
	_ok(Ancients.at_war_with(st2, id2, 1), "bombarder un Monde saint : guerre sainte")
	var st3 := _new(["hierophantes"], {"awakenings": false})
	st3.ancients["wake"] = false
	var id3 := Ancients.id_of_kind(st3, "hierophantes")
	AncientsBridges.on_colonize(st3, 0, _holy(st3, id3))
	_ok(Ancients.at_war_with(st3, id3, 0) and Ancients.asleep(st3, id3), "sans réveils : une Punition, sans éveil")


func _test_consecrate() -> void:
	var st := _new(["hierophantes"])
	var id := Ancients.id_of_kind(st, "hierophantes")
	var pid := _holy(st, id)
	var added: Array[Dictionary] = []
	Ancients.meet(st, id, 0, added)
	_ok(AncientsBridges.check_consecrate(st, 0, id, pid) != "", "pas de consécration sans vaisseau sur place")
	st.spawn_ship(0, "corvette", st.galaxy.get_planet(pid).system_id)
	st.empires[0].resources["influence"] = 200
	var why := AncientsBridges.check_consecrate(st, 0, id, pid)
	if Faiths.state_faith(st, 0) == Faiths.LAICITE:
		_ok(why != "", "une foi d'État est nécessaire")
		return
	_ok(why == "", "consécration possible (%s)" % why)
	var before := Ancients.opinion(st, id, 0)
	SimCommands.apply(st, SimCommands.anc_act(0, "consecrate", id, "", pid))
	_ok(Ancients.opinion(st, id, 0) >= before + 30, "consacrer : +30 d'opinion des Hiérophantes")
	_ok(AncientsBridges.check_consecrate(st, 0, id, pid) != "", "une seule fois par foi")


func _test_relics() -> void:
	var st := _new(["kheb", "bibliotheque"])
	var id := Ancients.id_of_kind(st, "kheb")
	var rid := AncientsBridges.key_relic("kheb")
	_ok(rid == "sceau_kheb", "relique-clé de Kheb : le Sceau")
	var site := -1
	for sid in st.digs:
		if String(st.digs[sid]["relic"]) == rid:
			site = int(sid)
	_ok(site >= 0, "cachée dans une fouille")
	if site >= 0:
		var j := int(FactionTraits.jumps_from(st.galaxy, int(Ancients.get_a(st, id)["home"])).get(site, 99))
		_ok(j >= 2 and j <= 4, "à 2 à 4 sauts de sa poche (%d)" % j)
	var others := 0
	for sid in st.digs:
		if Relics.is_ancient_relic(String(st.digs[sid]["relic"])):
			others += 1
	_ok(others <= Ancients.ids(st).size(), "les reliques-clés ne s'enfouissent pas au hasard")
	var added: Array[Dictionary] = []
	Ancients.meet(st, id, 0, added)
	var before := Ancients.base_opinion(st, id, 0)
	Relics.gain(st, 0, rid)
	_ok(AncientsBridges.holds_key(st, id, 0) and Ancients.base_opinion(st, id, 0) >= before + 50, "la tenir efface une colère (+50)")
	var item := {"id": -1, "card": "anc_kheb_exige", "anc": id, "system": -1, "planet": -1, "rival": -1, "hero": -1}
	Ancients.card_fx(st, 0, item, {"k": "ancient", "act": "defy"}, added)
	_ok(not Ancients.at_war_with(st, id, 0), "refuser l'ultimatum sans guerre, la relique en main")


func _test_vaults() -> void:
	var st := _new(["bibliotheque"])
	var id := Ancients.id_of_kind(st, "bibliotheque")
	var digs_before := st.digs.size()
	for sid in (Ancients.get_a(st, id)["systems"] as Array).duplicate():
		Combat.capture_system(st, int(sid), 0)
	_ok(Ancients.stage(st, id) == "fallen", "plus aucun monde : l'ancienne est abattue")
	var vaults := 0
	var crisis_v := 0
	for sid in st.digs:
		if st.digs[sid].has("vault"):
			vaults += 1
			if bool(st.digs[sid].get("vault_crisis", false)):
				crisis_v = int(sid)
	_ok(vaults >= 2 and vaults <= 3 and st.digs.size() > digs_before, "elle laisse 2 à 3 coffres (%d)" % vaults)
	if crisis_v > 0:
		var c := Colony.new()
		c.planet_id = st.galaxy.systems[crisis_v].planet_ids[0]
		c.owner = 0
		c.kind = Colony.KIND_COLONY
		c.population = 3
		if not st.colonies.has(c.planet_id):
			st.add_colony(c)
		st.empires[0].resources["energy"] = 500
		st.empires[0].resources["materials"] = 500
		_ok(Relics.check_start(st, 0, crisis_v).contains("crise"), "le dernier coffre attend une crise")


func _test_friend() -> void:
	var st := _new(["conservatoire"], {"heroes": true})
	var id := Ancients.id_of_kind(st, "conservatoire")
	var h := {"id": 900, "owner": 0, "name": "Testa", "cls": "stratege", "traits": [], "xp": 50}
	st.heroes[900] = h
	AncientsBridges.on_post(st, id, 0, "conservateur")
	_ok((h["traits"] as Array).has("ami_anciens"), "poste honorifique : le héros devient Ami des anciens")
	_ok(AncientsBridges.talent_op(st, id, 0) >= 25, "+25 d'opinion de toutes les anciennes")
	st.heroes.erase(900)


func _test_talents() -> void:
	var st := _new(["bibliotheque", "bergers"])
	var found := {}
	for e in st.empires:
		for t in AncientsBridges.talents_of(st, e.id):
			found[String(t["label"])] = e.id
	_ok(found.size() >= 1, "talents de couche trouvés chez les peuples (%s)" % str(found.keys()))
	for e in st.empires:
		if Events.layer_value(st, e.id, "credo") == "profit":
			_ok(Ancients.give_cost(st, e.id, "energy") == 75, "profit : contributions 25 % moins chères")
		if Events.layer_value(st, e.id, "credo") == "honneur":
			_ok(AncientsBridges.mission_mult(st, e.id) == 200, "honneur : missions doublées")
		if Events.layer_value(st, e.id, "gouvernement") == "ruche" or Events.layer_value(st, e.id, "archetype") == "ruche":
			_ok(not AncientsBridges.hears(st, e.id, e.id), "ruche : aucune requête")
		if Events.layer_value(st, e.id, "archetype") == "synthetique":
			_ok(AncientsBridges.wins_bets(st, e.id, "anc_bergers_greffe"), "synthétique : les Bergers parient pour lui")


func _test_scion() -> void:
	var st := GameState.create(11, 160, 1800.0, "vael", {"ai_level": "", "ancients": "aucune"})
	_ok(not Ancients.enabled(st), "option sur Aucune")
	var id := AncientsBridges.make_scion(st, 0)
	_ok(id >= 0 and Ancients.enabled(st), "Rejeton : une petite ancienne apparaît quand même")
	if id < 0:
		return
	var a := Ancients.get_a(st, id)
	_ok((a["systems"] as Array).size() == 1 and Ancients.fleets_of(st, id).size() == 1, "un seul système, une seule flotte")
	_ok(Ancients.in_contact(st, id, 0) and Ancients.opinion(st, id, 0) >= 150, "protectrice : +150 d'opinion")
	st.empires[0].resources["energy"] = 1000
	var added: Array[Dictionary] = []
	st.tick = 720
	AncientsBridges._scions(st, added)
	_ok(int(st.empires[0].resources["energy"]) == 980, "tribut léger de 2 %")
	_ok(_cards(st, 0, "anc_cadeau") >= 1, "cadeau de la protectrice")
	_ok(not Species.brick("origine", "rejeton").is_empty(), "origine Rejeton dans l'éditeur d'espèces")


func _test_save() -> void:
	var st := _new(["hierophantes", "kheb"], {"faiths": "aucunes"})
	var id := Ancients.id_of_kind(st, "hierophantes")
	var pid := _holy(st, id)
	if pid >= 0:
		st.ancients["consecrated"] = {pid: "x"}
	AncientsBridges.make_scion(st, 1)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_snapshot())))
	_ok(back != null and back.checksum() == st.checksum(), "sauvegarde des ponts relue, même empreinte")
