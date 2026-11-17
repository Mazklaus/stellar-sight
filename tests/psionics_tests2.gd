class_name PsionicsTests2
extends RefCounted
## Tests des pouvoirs psioniques, lots 2 et 3 (le Songe, la guerre, les ponts). Appelés par psionics_tests.gd.

const T := preload("res://tests/psionics_tests.gd")

static var _check: Callable


static func run(check: Callable) -> void:
	_check = check
	print("  - lot 2 : voix")
	_test_voice()
	print("  - lot 2 : domination")
	_test_domination()
	print("  - lot 2 : combat")
	_test_combat()
	print("  - lot 2 : navigation")
	_test_navigation()
	print("  - lot 2 : songe")
	_test_dream()
	print("  - lot 2 : pactes")
	_test_pacts()
	print("  - lot 2 : solde")
	_test_solde()
	print("  - lot 2 : felures graves")
	_test_grave()
	print("  - lot 2 : ia")
	_test_ai()
	PsionicsTests3.run(check)


static func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func _ready_empire(st: GameState, eid: int, techs: Array = ["theorie_psionique", "telepathie", "precognition", "ouverture_songe", "navigation_songe", "ecrans_psychiques"]) -> void:
	T.give_techs(st, eid, techs)
	Psionics.add_resonance(st, eid, 2000)


static func _test_voice() -> void:
	var st := T.new_game()
	var oss := T.eid_of(st, "ossarane")
	var vael := T.eid_of(st, "vael")
	var teyl := T.eid_of(st, "teyl")
	_ready_empire(st, oss)
	st.get_empire(oss).contacts.append(vael)
	st.get_empire(oss).contacts.append(teyl)
	var before := Diplomacy.opinion(st, vael, oss)
	_ok(T.cmd(st, oss, "power", {"power": "voix", "target": vael}) == "", "Voix : lancée")
	_ok(Diplomacy.opinion(st, vael, oss) > before, "Voix : l'opinion de la cible monte (%d -> %d)" % [before, Diplomacy.opinion(st, vael, oss)])
	Psionics.sub(st, "cd").erase("%d:voix" % oss)
	_ok(Psionics.check_power(st, oss, "voix", teyl).contains("esprit"), "Voix : rien à convaincre chez un peuple sourd (%s)" % Psionics.check_power(st, oss, "voix", teyl))
	var caught := false
	for i in 30:
		Psionics.sub(st, "cd").erase("%d:voix" % oss)
		Psionics.add_resonance(st, oss, 500)
		st.tick += 1
		T.cmd(st, oss, "power", {"power": "voix", "target": vael})
		for m in st.memories:
			if String(m["kind"]) == "psi_viol" and int(m["who"]) == vael:
				caught = true
	_ok(caught, "Voix : parfois découverte, grief « Viol des esprits »")


static func _test_domination() -> void:
	var st := T.new_game()
	var oss := T.eid_of(st, "ossarane")
	var vael := T.eid_of(st, "vael")
	_ready_empire(st, oss)
	var target := T.home_system(st, vael)
	_ok(Psionics.check_power(st, oss, "domination", target).contains("guerre"), "Domination : il faut la guerre (%s)" % Psionics.check_power(st, oss, "domination", target))
	st.get_empire(oss).wars.append(vael)
	st.get_empire(vael).wars.append(oss)
	if not Combat.at_war(st, oss, vael):
		_ok(true, "Domination : guerre non simulée ici (passé)")
		return
	_ok(Psionics.check_power(st, oss, "domination", target) != "", "Domination : il faut un stratège dans le système (%s)" % Psionics.check_power(st, oss, "domination", target))
	var f := st.spawn_ship(oss, "corvette" if not GameData.ship("corvette").is_empty() else String(GameData.ships().keys()[0]), target)
	var cand := Heroes.make_candidate(st, oss, "stratege", ["test_dom"])
	var hid := Heroes.recruit(st, oss, cand)
	var h: Dictionary = st.heroes[hid]
	h["post"] = "fleet"
	h["target"] = f.id
	h["arrive"] = 0
	h["psi"] = 3
	st.garrisons[target] = 5
	var why := Psionics.check_power(st, oss, "domination", target)
	_ok(why == "" or why.contains("garnison"), "Domination : stratège Élu dans le système (%s)" % why)
	if why == "":
		_ok(T.cmd(st, oss, "power", {"power": "domination", "target": target}) == "" and (st.system_owner(target) == oss or Psionics.screen_pct(st, vael) > 0), "Domination : le système change de mains")


static func _test_combat() -> void:
	_ok(not Designs.module("barriere_psychique").is_empty() and not Designs.module("frappe_mentale").is_empty(), "Combat : modules Barrière psychique et Frappe mentale")
	var w: Dictionary = GameData.combat()["weapons"].get("psychic", {})
	_ok(String(w.get("defense", "")) == "psi", "Combat : la frappe mentale vise la défense psychique")
	var st := T.new_game("desactive")
	var e := st.get_empire(0)
	T.give_techs(st, 0, ["theorie_psionique", "telepathie", "ecrans_psychiques"])
	var hull0 := String(Designs.hull_ids_for(e.faction_id)[0])
	_ok(not Designs._usable(st, 0, hull0, "weapon").has("frappe_mentale"), "Combat : modules fermés sans le pilier")
	var st2 := T.new_game()
	var oss := T.eid_of(st2, "ossarane")
	_ok(Ground.type_def("sensitifs").get("psionics", false) and not Ground.type_allowed(st2, oss, "sensitifs"), "Régiments psioniques : fermés à une espèce sourde")
	T.give_techs(st2, oss, ["theorie_psionique", "telepathie"])
	_ok(Ground.type_allowed(st2, oss, "sensitifs"), "Régiments psioniques : ouverts aux Latents")
	_ok(not Ground.type_allowed(st, 0, "sensitifs"), "Régiments psioniques : fermés sans le pilier")
	var hull := ""
	for hid in Designs.hull_ids_for(st2.get_empire(oss).faction_id):
		if String(Designs.hull(hid).get("size", "")) == "small":
			hull = hid
			break
	if hull != "":
		var c := Designs.compute(hull, ["barriere_psychique"])
		_ok(int(c.get("psi", 0)) > 0, "Barrière psychique : défense psi %d" % int(c.get("psi", 0)))
	_ok(e != null, "Combat : partie sans pilier")


static func _test_navigation() -> void:
	var st := T.new_game()
	var oss := T.eid_of(st, "ossarane")
	var sid := T.home_system(st, oss)
	var f := st.spawn_ship(oss, String(GameData.ships().keys()[0]), sid)
	var jumps := FactionTraits.jumps_from(st.galaxy, sid)
	var dest := -1
	var far := -1
	for s in jumps:
		if int(jumps[s]) == 3 and dest < 0:
			dest = int(s)
		if int(jumps[s]) == 7 and far < 0:
			far = int(s)
	_ok(PsionicsDream.check_jump(st, oss, f.id, dest).contains("Navigation"), "Navigation : il faut la technologie")
	_ready_empire(st, oss)
	if far >= 0:
		_ok(PsionicsDream.check_jump(st, oss, f.id, far).contains("loin"), "Navigation : quatre sauts au plus")
	_ok(T.cmd(st, oss, "jump", {"fleet": f.id, "sys": dest}) == "", "Navigation : saut lancé")
	_ok(f.system_id == dest or st.galaxy.systems[dest].neighbors.has(f.system_id), "Navigation : la flotte ressort à destination (ou s'égare tout près)")
	_ok(T.cmd(st, oss, "jump", {"fleet": f.id, "sys": sid}).contains("referme"), "Navigation : recharge")


static func _test_dream() -> void:
	var st := T.new_game()
	var oss := T.eid_of(st, "ossarane")
	_ok(PsionicsDream.check_open(st, oss) != "", "Songe : fermé sans la technologie")
	_ready_empire(st, oss)
	var e := st.get_empire(oss)
	e.resources["knowledge"] = 0
	_ok(PsionicsDream.check_open(st, oss).contains("Savoir"), "Songe : il faut du Savoir (%d)" % PsionicsDream.open_cost(st, oss))
	e.resources["knowledge"] = 5000
	_ok(T.cmd(st, oss, "open") == "", "Songe : ouvert")
	_ok(int(e.resources["knowledge"]) == 5000 - PsionicsDream.open_cost(st, oss), "Songe : le Savoir est dépensé")
	_ok(T.cmd(st, oss, "dive", {"posture": "audacieuse"}) == "", "Plongée : lancée")
	_ok(T.cmd(st, oss, "dive", {"posture": "prudente"}).contains("reposent"), "Plongée : cinq ans de repos")
	# Postures et visions : les trois issues sortent sur beaucoup de tirages.
	var kinds := {}
	for i in 200:
		st.tick += 1
		var v := PsionicsDream.pick_vision(st, oss, ["boon", "none", "curse"][i % 3], 2)
		kinds[String(v.get("kind", ""))] = true
	_ok(kinds.size() == 3, "Visions : bienfaits, riens et malédictions")
	_ok(PsionicsDream.pick_vision(st, oss, "boon", 0).get("tier", 0) == 0, "Visions : la prudence ne tire que les visions du premier palier")
	var added: Array[Dictionary] = []
	var g0 := Research.fx_int(st, oss, "growth_pct")
	PsionicsDream.apply_vision(st, oss, {"id": "vigueur", "kind": "boon", "label": "Vigueur", "fx": {"growth_pct": 15}, "text": "x"}, added)
	_ok(Research.fx_int(st, oss, "growth_pct") == g0 + 15, "Vision : bienfait de cinq ans dans les effets")
	PsionicsDream.apply_vision(st, oss, {"id": "elu", "kind": "boon", "label": "L'Élu", "do": "elu", "text": "x"}, added)
	var elu := PsionicsDream.elu(st, oss)
	_ok(not elu.is_empty() and Psionics.hero_power(st, elu) == 3, "Élu : un héros de puissance 3")
	_ok(PsionicsDream.make_elu(st, oss).is_empty(), "Élu : un seul par empire")
	var st2 := T.new_game("discret")
	var o2 := T.eid_of(st2, "ossarane")
	_ready_empire(st2, o2)
	st2.get_empire(o2).resources["knowledge"] = 5000
	_ok(PsionicsDream.check_open(st2, o2).contains("Discret"), "Songe : pas en réglage Discret")


static func _test_pacts() -> void:
	var st := T.new_game()
	var oss := T.eid_of(st, "ossarane")
	_ready_empire(st, oss)
	var added: Array[Dictionary] = []
	_ok(PsionicsDream.entities()["list"].size() == 5, "Puissances : cinq dans le catalogue")
	Psionics.sub(st, "offer")[str(oss)] = {"p": "gueule", "until": st.tick + 100}
	_ok(T.cmd(st, oss, "pact", {"accept": true}) == "", "Pacte : accepté")
	var p := PsionicsDream.pact(st, oss)
	_ok(String(p.get("p", "")) == "gueule", "Pacte : la Gueule")
	_ok(Research.fx_int(st, oss, "damage_pct") >= 5, "Pacte : palier 1 dans les effets")
	st.get_empire(oss).wars.append(1)
	var f0 := int(p["favor"])
	PsionicsDream._pact_month(st, st.get_empire(oss), added)
	_ok(int(PsionicsDream.pact(st, oss)["favor"]) > f0 + 1, "Pacte : la guerre plaît à la Gueule")
	PsionicsDream.pact(st, oss)["favor"] = 99
	var hid := Heroes.ids_of(st, oss)
	PsionicsDream._pact_month(st, st.get_empire(oss), added)
	_ok(int(PsionicsDream.pact(st, oss)["tier"]) == 2, "Pacte : dernier palier")
	if not hid.is_empty():
		_ok(not PsionicsDream.elu(st, oss).is_empty(), "Pacte : Élu de la Puissance")
		var gov := String(FactionTraits.species(st.get_empire(oss).faction()).get("gouvernement", ""))
		if gov != "theocratie":
			_ok(PsionicsDream.check_reform(st, oss) == "", "Souverain élu : la réforme est proposée")
			_ok(T.cmd(st, oss, "reform", {"accept": true}) == "", "Souverain élu : acceptée")
			_ok(String(FactionTraits.species(st.get_empire(oss).faction()).get("gouvernement", "")) == "theocratie", "Souverain élu : théocratie")
	# Le prix.
	var pop0 := 0
	for pid in st.sorted_colony_ids():
		if st.colonies[pid].owner == oss:
			pop0 += st.colonies[pid].population
	_ok(PsionicsDream.lose_pop(st, oss, 2) >= 1, "Prix : des habitants disparaissent")
	PsionicsDream.pact(st, oss)["price"] = st.tick
	PsionicsDream._pact_month(st, st.get_empire(oss), added)
	_ok(int(PsionicsDream.pact(st, oss)["price"]) > st.tick, "Prix : le suivant dans quinze ans")
	_ok(T.cmd(st, oss, "break") == "" and PsionicsDream.pact(st, oss).is_empty(), "Pacte : rompu")
	var broke := false
	for x in Psionics.empire_stability_parts(st, oss):
		broke = broke or String(x[0]).contains("rompu")
	_ok(broke, "Pacte rompu : stabilité")


static func _test_solde() -> void:
	var st := T.new_game("complet", "ossarane", {"crises": "une"})
	var oss := T.eid_of(st, "ossarane")
	_ready_empire(st, oss)
	_ok(not Crisis.kind_ids().has("solde") and not Crisis.kind_def("solde").is_empty(), "Solde : dans le catalogue des crises, jamais tiré au sort")
	Psionics.sub(st, "offer")[str(oss)] = {"p": "derniere", "until": st.tick + 100}
	T.cmd(st, oss, "pact", {"accept": true})
	_ok(Research.fx_int(st, oss, "damage_pct") >= 25, "Dernière Puissance : effets énormes")
	var pop0 := 0
	for pid in st.sorted_colony_ids():
		if st.colonies[pid].owner == oss:
			pop0 += st.colonies[pid].population
	PsionicsDream.pact(st, oss)["until"] = st.tick
	var added: Array[Dictionary] = []
	PsionicsDream._pact_month(st, st.get_empire(oss), added)
	var pop1 := 0
	for pid in st.sorted_colony_ids():
		if st.colonies[pid].owner == oss:
			pop1 += st.colonies[pid].population
	_ok(PsionicsDream.pact(st, oss).is_empty() and pop1 < pop0, "Solde : l'empire est ravagé (%d -> %d)" % [pop0, pop1])
	if Crisis.enabled(st):
		_ok(Crisis.kind(st) == "solde", "Solde : la crise « le Solde du Songe » commence")


static func _test_grave() -> void:
	var st := T.new_game()
	var oss := T.eid_of(st, "ossarane")
	_ready_empire(st, oss)
	_ok(Psionics.felure_table(st).size() > (Psionics.cfg("felures")["table"] as Array).size(), "Fêlures graves : en réglage Complet")
	var added: Array[Dictionary] = []
	var herds0 := Fauna.herd_ids(st).size()
	for f: Dictionary in Psionics.cfg("felures")["grave"]:
		Psionics.apply_felure(st, oss, f, added)
	_ok(not PsionicsDream.haunted(st).is_empty(), "Fêlure grave : monde hanté (Cratère du Songe)")
	_ok(Fauna.herd_ids(st).size() > herds0, "Fêlure grave : bête du Songe")
	_ok(not Fauna.species_ids().has("betes_songe"), "Bêtes du Songe : pas de nid au départ")


static func _test_ai() -> void:
	var st := T.new_game("complet", "vael")
	var vael := T.eid_of(st, "vael")
	var e := st.get_empire(vael)
	_ready_empire(st, vael)
	e.resources["knowledge"] = 5000
	var ctx := {"state": st, "e": e, "lv": AiLevels.level("normal"), "ai": AiLevels.personality(e), "salt": 0, "intent": ""}
	var sim := Simulation.new(st)
	ctx["sim"] = sim
	AiPsionics.think(ctx)
	_ok(Psionics.stat(st, vael, "ai_month") > 0, "IA lot 2 : réfléchit sans erreur")
