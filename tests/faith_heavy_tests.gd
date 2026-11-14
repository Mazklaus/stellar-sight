extends RefCounted
## Tests de la religion, lot 4 : les 5 natures SF lourdes (Chronolâtrie, Dieu en chantier, Entropisme,
## Communion, Astres vivants) et les ponts (héros de foi, pèlerinages, politique, talents des peuples,
## victoire spirituelle, événements, IA, sauvegarde 46).
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Religion, lot 4 (natures SF lourdes et ponts)…")
	_test_data()
	_test_chrono()
	_test_chantier()
	_test_entropie()
	_test_communion()
	_test_astres()
	_test_vocations()
	_test_pilgrims()
	_test_politics()
	_test_talents()
	_test_victory()
	_test_ai()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _added() -> Array[Dictionary]:
	return [] as Array[Dictionary]


func _state(ai := "") -> GameState:
	var st := GameState.create(4242, 150, 1800.0, "vael", {"ai_level": ai, "faiths": "actives"})
	for e in st.empires:
		for r in ["energy", "influence", "materials", "food", "knowledge"]:
			e.resources[r] = 5000
	for fid in Faiths.ids(st):
		var f := Faiths.faith(st, fid)
		if int(f["pending"]) > 0:
			var ch := Faiths.default_choice(st, int(f["founder"]), fid)
			Faiths.choose(st, fid, String(ch["nature"]), ch["doctrines"], String(ch["precept"]))
	return st


func _id_of(st: GameState, faction: String) -> int:
	for e in st.empires:
		if e.faction_id == faction:
			return e.id
	return -1


## La foi fondée par ce peuple passe à une autre nature (comme si son fondateur l'avait choisie).
func _with(nat: String, ai := "", people := "choeur") -> Array:
	var st := _state(ai)
	var ch := _id_of(st, people)
	var fc := Faiths.founded_by(st, ch)
	Faiths.faith(st, fc)["nature"] = nat
	FaithNatures.on_chosen(st, fc)
	return [st, ch, fc]


func _hero(st: GameState, eid: int, amb := "foi") -> int:
	var cand := Heroes.make_candidate(st, eid, "orateur", ["test", eid, st.next_hero_id])
	cand["amb"] = amb
	var hid := Heroes.recruit(st, eid, cand)
	# Au conseil : un héros sans poste n'agit pas.
	st.heroes[hid]["post"] = "council"
	st.heroes[hid]["arrive"] = 0
	return hid


func _test_data() -> void:
	var nl: Dictionary = FaithWars.data()["natures"]["list"]
	var all := true
	for n in FaithHeavy.HEAVY:
		all = all and nl.has(n) and String(nl[n].get("src", "")) != ""
	_ok(all, "les 5 natures lourdes sont en données, sourcées")
	_ok(nl.size() == 19, "19 natures au catalogue")
	var vo: Dictionary = FaithBridges.bd()["vocations"]
	_ok(vo.has("prophete") and vo.has("inquisiteur") and vo.has("martyr"), "3 vocations de foi en données")
	var tal: Dictionary = FaithBridges.bd()["talents"]
	_ok(["choeur", "murmurants", "ossarane", "vael", "khthari", "teyl", "ferrocornes", "brisecomete"].all(func(k): return tal.has(k)), "un talent de foi pour chacun des 8 peuples")
	_ok((GameData.victories()["victories"] as Dictionary).has("spirituelle"), "victoire spirituelle en données")


func _test_chrono() -> void:
	var r := _with("chronolatrie")
	var st: GameState = r[0]
	var ch: int = r[1]
	var fc: String = r[2]
	var d := FaithNatures.fdat(st, fc)
	_ok(int(d.get("oracle_next", 0)) == st.tick + 360, "Chronolâtrie : premier oracle dans un an")
	_ok(FaithHeavy.op_days_pct(st, ch, "prophetie") == -50, "prophéties plantées deux fois plus vite")
	# Une flotte de guerre en route : l'oracle l'annonce.
	var fl: Fleet = null
	var fids := st.fleets.keys()
	fids.sort()
	for flid in fids:
		var f2: Fleet = st.fleets[flid]
		if f2.owner == ch and Combat.is_warfleet(f2):
			fl = f2
			break
	if fl == null:
		_ok(true, "pas de flotte de guerre (test oracle sauté)")
		return
	var nb := int(st.galaxy.systems[fl.system_id].neighbors[0])
	fl.path.assign([nb])
	d["oracle_next"] = st.tick
	FaithHeavy._oracle_month(st, fc, _added())
	var o := FaithHeavy.oracle(st, fc)
	_ok(not o.is_empty(), "un oracle est rendu")
	_ok(FaithHeavy.oracle_text(st, o) != "", "texte d'oracle")
	if String(o.get("kind", "")) == "flotte" and int(o["fleet"]) == fl.id:
		var z := FaithWars.zeal(st, fc)
		fl.path.clear()
		fl.system_id = int(o["dest"])
		FaithHeavy._oracle_month(st, fc, _added())
		_ok(FaithHeavy.oracle(st, fc).is_empty() and FaithWars.zeal(st, fc) >= z, "oracle accompli : zèle")
	# Empêché : la flotte va ailleurs.
	var nb2 := -1
	for x in st.galaxy.systems[fl.system_id].neighbors:
		if int(x) != fl.system_id:
			nb2 = int(x)
	d["oracle"] = {"kind": "flotte", "fleet": fl.id, "eid": fl.owner, "dest": 9999, "deadline": st.tick + 100}
	fl.path.assign([nb2])
	var nfaith := Faiths.ids(st).size()
	FaithHeavy._oracle_month(st, fc, _added())
	_ok(FaithHeavy.oracle(st, fc).is_empty(), "oracle empêché : tranché")
	_ok(Faiths.ids(st).size() >= nfaith, "empêché : schisme chez le coupable ou zèle perdu")


func _test_chantier() -> void:
	var r := _with("dieu_en_chantier")
	var st: GameState = r[0]
	var ch: int = r[1]
	var fc: String = r[2]
	_ok(FaithHeavy.stage(st, fc) == 0, "Dieu en chantier : rien de bâti")
	if Faiths.state_faith(st, ch) != fc:
		st.faiths["state"][str(ch)] = fc
	var cost := FaithHeavy.stage_cost(st, fc, ch)
	var base: Dictionary = FaithHeavy.hd()["chantier"]["stages"][0]["cost"]
	_ok(int(cost.get("materials", 0)) < int(base.get("materials", 0)), "Chœur : étages moins chers")
	if Faiths.head(st, fc) != ch:
		_ok(true, "le Chœur n'est pas chef (test étages sauté)")
		return
	_ok(SimCommands.validate(st, SimCommands.faith_nat(ch, "stage", {})) == "", "ordre : poser un étage")
	SimCommands.apply(st, SimCommands.faith_nat(ch, "stage", {}))
	_ok(FaithHeavy.check(st, ch, "stage", {}) != "", "un seul étage en chantier à la fois")
	var fx0 := {}
	FaithHeavy.fx(st, ch, fc, fx0)
	_ok(fx0.is_empty(), "pas d'effet avant la fin de l'étage")
	st.tick = int(FaithNatures.fdat(st, fc)["build"]["end"])
	FaithHeavy._chantier_month(st, fc, _added())
	_ok(FaithHeavy.stage(st, fc) == 1, "étage 1 achevé")
	var fx1 := {}
	FaithHeavy.fx(st, ch, fc, fx1)
	_ok(not fx1.is_empty(), "l'étage donne son pouvoir")
	# Jusqu'à l'Éveil (le dernier étage du Chœur demande une cathédrale).
	FaithNatures.fdat(st, fc)["stage"] = 4
	_ok(FaithHeavy.check(st, ch, "stage", {}).contains("Cathédrale"), "Chœur : dernier étage = Cathédrale-chœur")
	FaithNatures.fdat(st, fc)["build"] = {"end": st.tick}
	FaithHeavy._chantier_month(st, fc, _added())
	_ok(FaithHeavy.stage(st, fc) == 5, "Éveil")
	_ok(not FaithNatures.live_god(st, fc).is_empty(), "le dieu bâti marche sur la carte")
	FaithNatures.fdat(st, fc)["zeal"] = 0
	FaithWars.add_zeal(st, fc, -1000)
	_ok(FaithHeavy.disobeys(st, fc), "zèle bas : le dieu désobéit")
	var nb := int(st.galaxy.systems[int(FaithNatures.live_god(st, fc)["sid"])].neighbors[0])
	st.get_empire(ch).explored[nb] = true
	_ok(FaithNatures.check(st, ch, "god_move", {"system": nb}) != "", "un dieu désobéissant ne se guide pas")


func _test_entropie() -> void:
	var r := _with("entropisme")
	var st: GameState = r[0]
	var ch: int = r[1]
	var fc: String = r[2]
	st.faiths["state"][str(ch)] = fc
	_ok(FaithHeavy.clock(st, fc) == 0, "Entropisme : horloge à zéro")
	FaithHeavy._entropy_month(st, fc, _added())
	_ok(FaithHeavy.clock(st, fc) == 1, "l'horloge avance d'un cran par mois")
	var z := FaithWars.zeal(st, fc)
	FaithHeavy.on_capture(st, ch)
	_ok(FaithHeavy.clock(st, fc) == 4 and FaithWars.zeal(st, fc) == mini(100, z + 2), "une conquête nourrit l'horloge et le zèle")
	FaithNatures.fdat(st, fc)["clock"] = 99
	FaithHeavy._entropy_month(st, fc, _added())
	_ok(int(FaithNatures.fdat(st, fc).get("glory_end", 0)) > st.tick, "la Fin du cycle sonne")
	var fx := {}
	FaithHeavy.fx(st, ch, fc, fx)
	_ok(not fx.is_empty(), "deux ans de puissance")
	st.tick = int(FaithNatures.fdat(st, fc)["glory_end"])
	FaithHeavy._entropy_month(st, fc, _added())
	_ok(not Faiths.ids(st).has(fc), "puis la foi s'effondre")
	_ok(Faiths.state_faith(st, ch) == Faiths.LAICITE, "ses empires redeviennent laïques")


func _test_communion() -> void:
	var r := _with("communion")
	var st: GameState = r[0]
	var fc: String = r[2]
	var kh := _id_of(st, "khthari")
	_ok(Faiths.offer_natures(st, kh, fc, "relique") == ["communion"], "une ruche ne peut fonder que la Communion")
	st.faiths["state"][str(kh)] = fc
	_ok(not Faiths.closed(st, kh), "en Communion, la ruche s'ouvre à la foi")
	Faiths.hive_join(st, kh, fc)
	var c: Colony = st.colonies.get(st.get_empire(kh).capital_planet)
	_ok(Faiths.majority(c) == fc, "toute la ruche rejoint la Communion")
	# Un second membre : le fonds commun.
	st.faiths["state"][str(r[1])] = fc
	_ok(FaithNatures.members(st, fc).size() >= 2, "deux empires en Communion")
	var before := 0
	for eid in FaithNatures.members(st, fc):
		before += int(st.get_empire(eid).resources["energy"])
	FaithHeavy._communion_month(st, fc)
	var after := 0
	for eid in FaithNatures.members(st, fc):
		after += int(st.get_empire(eid).resources["energy"])
	_ok(before == after, "le fonds commun ne crée ni ne détruit rien")
	_ok(FaithNatures.fdat(st, fc).has("pull"), "la stabilité est tirée vers la moyenne")


func _test_astres() -> void:
	var r := _with("astres_vivants")
	var st: GameState = r[0]
	var ch: int = r[1]
	var fc: String = r[2]
	var sac := FaithHeavy.sacred(st, fc)
	var holy_sid := st.galaxy.get_planet(int(Faiths.faith(st, fc)["holy"])).system_id
	_ok(sac.size() == 3 and int(sac[0]) == holy_sid, "Astres vivants : 3 systèmes sacrés, le monde saint d'abord")
	var press := {}
	var targets := {}
	for pid in st.sorted_colony_ids():
		var c: Colony = st.colonies[pid]
		var s := st.galaxy.get_planet(pid).system_id
		if not targets.has(s):
			targets[s] = []
		targets[s].append(pid)
	FaithHeavy.extra_pressures(st, press, targets)
	var any := false
	for pid in press:
		any = any or press[pid].has(fc)
	_ok(any, "les systèmes sacrés prêchent")
	# Profanation : un avant-poste dans un système sacré.
	var vic := _id_of(st, "vael")
	var placed := false
	for s in sac:
		for pid in st.galaxy.systems[int(s)].planet_ids:
			if not st.colonies.has(pid):
				var oc := Colony.new()
				oc.planet_id = pid
				oc.owner = vic
				oc.kind = Colony.KIND_OUTPOST
				st.colonies[pid] = oc
				placed = true
				break
		if placed:
			break
	if placed:
		FaithHeavy._astres_month(st, fc, _added())
		_ok((FaithNatures.fdat(st, fc).get("profaners", []) as Array).has(vic), "un avant-poste sacré profane les Astres")
		st.faiths["state"][str(ch)] = fc
		var parts := []
		FaithHeavy.opinion_parts(st, ch, vic, parts)
		_ok(not parts.is_empty(), "les fidèles en veulent au profanateur")
	FaithNatures.fdat(st, fc)["profaned"] = {str(vic): st.tick + 100}
	st.faiths["state"][str(ch)] = fc
	_ok(FaithHeavy.casus(st, ch, vic) != "", "avatar abattu : motif de guerre sainte")


func _test_vocations() -> void:
	var st := _state()
	var ch := _id_of(st, "choeur")
	var fc := Faiths.founded_by(st, ch)
	st.faiths["state"][str(ch)] = fc
	var h1 := _hero(st, ch, "gloire")
	_ok(FaithBridges.check_voc(st, ch, h1, "prophete") != "", "seul un héros à l'ambition Foi entend l'appel")
	var h2 := _hero(st, ch)
	var slots := int(Faiths.faith(st, fc)["slots"])
	_ok(SimCommands.validate(st, SimCommands.faith_voc(ch, h2, "prophete")) == "", "ordre : vocation de Prophète")
	SimCommands.apply(st, SimCommands.faith_voc(ch, h2, "prophete"))
	_ok(FaithBridges.vocation(st.heroes[h2]) == "prophete", "Prophète nommé")
	_ok(int(Faiths.faith(st, fc)["slots"]) == mini(slots + 1, 1 + (Faiths.data()["tiers"] as Array).size()), "le Prophète débloque un précepte en avance")
	_ok(FaithBridges.mission_pct(st, ch) == 50, "le Prophète renforce les missions")
	var h3 := _hero(st, ch)
	_ok(FaithBridges.check_voc(st, ch, h3, "prophete") != "", "un seul Prophète par empire")
	FaithBridges.apply_voc(st, ch, h3, "inquisiteur")
	_ok(FaithBridges.ward_free(st, ch) and FaithBridges.ward_x(st, ch) == 2 and FaithBridges.inquisition_x(st, ch) == 2, "l'Inquisiteur : garde gratuite et doublée, inquisition doublée")
	var h4 := _hero(st, ch)
	FaithBridges.apply_voc(st, ch, h4, "martyr")
	var z := FaithWars.zeal(st, fc)
	var out := _added()
	FaithBridges.on_hero_death(st, st.heroes[h4], -1, out)
	_ok(FaithWars.zeal(st, fc) == z, "mort naturelle : pas de martyre")
	FaithBridges.on_hero_death(st, st.heroes[h4], _id_of(st, "vael"), out)
	_ok(FaithWars.zeal(st, fc) == mini(100, z + 15) and not out.is_empty(), "martyr tué : zèle et fragments")


func _test_pilgrims() -> void:
	var st := _state()
	var ch := _id_of(st, "choeur")
	var va := _id_of(st, "vael")
	var fc := Faiths.founded_by(st, ch)
	st.faiths["state"][str(va)] = fc
	_ok(not FaithBridges.pilgrims_to(st, fc, ch).has(va), "sans route commerciale, pas de pèlerins")
	if not st.trade.has("routes"):
		st.trade["routes"] = []
	var route := {"from": va, "to": ch, "kind": "ext", "path": [], "value": 1, "tier": 0}
	st.trade["routes"].append(route)
	_ok(FaithBridges.pilgrims_to(st, fc, ch).has(va), "les pèlerins suivent la route commerciale")
	route["blocked"] = true
	_ok(not FaithBridges.pilgrims_to(st, fc, ch).has(va), "un blocus coupe les pèlerins")


func _test_politics() -> void:
	var st := _state()
	var ch := _id_of(st, "choeur")
	var fc := Faiths.founded_by(st, ch)
	st.faiths["state"][str(ch)] = fc
	if Politics.regime_id(st, ch) == "theocratie":
		FaithNatures.fdat(st, fc)
		FaithWars.add_zeal(st, fc, 200)
		_ok(FaithBridges.conclave_name(st, ch, "Assemblée") == "Conclave ardent", "zèle haut : Conclave ardent")
		FaithWars.add_zeal(st, fc, -200)
		_ok(FaithBridges.conclave_name(st, ch, "Assemblée") == "Conclave tiède", "zèle bas : Conclave tiède")
	_ok(FaithBridges.conclave_name(st, _id_of(st, "vael"), "Sénat") == "Sénat", "hors théocratie, le nom reste")
	# Autel dissident : une autre foi domine un système.
	var c: Colony = st.colonies.get(st.get_empire(ch).capital_planet)
	var other := ""
	for fid in Faiths.ids(st):
		if fid != fc:
			other = fid
			break
	if other != "" and st.politics_on:
		c.faith.clear()
		c.faith[other] = c.population
		FaithBridges._politics_month(st)
		var sid := st.galaxy.get_planet(c.planet_id).system_id
		_ok(FaithBridges.dissident(st, sid), "une autre foi domine : Autel dissident")
	else:
		_ok(true, "Autel dissident sauté (pas d'autre foi)")


func _test_talents() -> void:
	var st := _state()
	var mu := _id_of(st, "murmurants")
	_ok(int(FaithHeavy.talent(st, mu).get("oracle_days", 0)) == 180, "Murmurants : oracles deux fois plus fréquents")
	var os := _id_of(st, "ossarane")
	_ok(FaithWars.voies_max(st, os) > FaithWars.voies_max(st, _id_of(st, "vael")) or FaithWars.voies_max(st, os) >= 2, "Ossarane : plus de Voies")
	var te := _id_of(st, "teyl")
	st.faiths["state"][str(te)] = Faiths.INCROYANCE
	_ok(FaithBridges.unbelief_pct(st, te) == 50, "Teyl : le doute est contagieux")
	var fe := _id_of(st, "ferrocornes")
	_ok(int(FaithHeavy.talent(st, fe).get("ancestors", 0)) == 4, "Ferrocornes : 4 ancêtres actifs")
	var bc := _id_of(st, "brisecomete")
	var bf := Faiths.founded_by(st, bc)
	if bf != "" and Faiths.state_faith(st, bc) == bf:
		_ok(not FaithBridges.sale_price(st, _id_of(st, "vael"), bf).is_empty(), "Brisecomète : leur foi est à vendre")
	else:
		_ok(true, "Brisecomète sans foi d'État (test vente sauté)")
	var kh := _id_of(st, "khthari")
	_ok(String(FaithHeavy.talent(st, kh).get("force", {}).get("diffusion", "")) == "secrete", "Kh'thari : culte toujours caché")


func _test_victory() -> void:
	var st := _state()
	_ok(not Victory.enabled(st, "spirituelle"), "victoire spirituelle : désactivée par défaut")
	st.victory_rules["spirituelle"] = true
	_ok(Victory.enabled(st, "spirituelle"), "elle s'active en option")
	var ch := _id_of(st, "choeur")
	var fc := Faiths.founded_by(st, ch)
	st.faiths["state"][str(ch)] = fc
	var p := Victory.progress(st, ch, "spirituelle")
	_ok(not bool(p["cond"]), "au départ, la foi ne domine pas la galaxie")
	for pid in st.sorted_colony_ids():
		var c: Colony = st.colonies[pid]
		if not GameState.is_npc(c.owner):
			c.faith.clear()
			c.faith[fc] = maxi(1, c.population)
	p = Victory.progress(st, ch, "spirituelle")
	_ok(bool(p["cond"]), "la foi majoritaire partout : condition remplie")
	var off := _state()
	off.faith_on = false
	_ok(not Victory.enabled(off, "spirituelle"), "sans religions, pas de victoire spirituelle")


func _test_ai() -> void:
	var r := _with("dieu_en_chantier", "normal")
	var st: GameState = r[0]
	var ch: int = r[1]
	var fc: String = r[2]
	st.faiths["state"][str(ch)] = fc
	FaithHeavy.ai(st, st.get_empire(ch))
	_ok(Faiths.head(st, fc) != ch or not (FaithNatures.fdat(st, fc).get("build", {}) as Dictionary).is_empty(), "l'IA pose un étage du dieu")
	var h := _hero(st, ch)
	FaithBridges.ai(st)
	_ok(FaithBridges.vocation(st.heroes[h]) != "" or not FaithBridges.voc_hero(st, ch, "martyr").is_empty() or not FaithBridges.voc_hero(st, ch, "prophete").is_empty(), "l'IA donne une vocation à un héros de foi")
	# Une ruche IA entre en Communion.
	var r2 := _with("communion", "normal")
	var st2: GameState = r2[0]
	var kh := _id_of(st2, "khthari")
	st2.faiths["state"].erase(str(kh))
	FaithBridges.ai(st2)
	_ok(Faiths.state_faith(st2, kh) == r2[2] or Faiths.check_state(st2, kh, r2[2]) != "", "la ruche IA adopte la Communion")


func _test_save() -> void:
	var r := _with("dieu_en_chantier")
	var st: GameState = r[0]
	var fc: String = r[2]
	FaithNatures.fdat(st, fc)["stage"] = 2
	FaithNatures.fdat(st, fc)["build"] = {"end": st.tick + 50}
	var d := st.to_dict()
	_ok(int(d["version"]) == 52, "sauvegarde version 52")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and FaithHeavy.stage(back, fc) == 2, "étage du dieu relu")
	_ok(back != null and back.checksum() == st.checksum(), "même empreinte après relecture (lot 4)")
	var r2 := _with("astres_vivants")
	var st2: GameState = r2[0]
	var back2 := GameState.from_dict(JSON.parse_string(JSON.stringify(st2.to_dict())))
	_ok(back2 != null and FaithHeavy.sacred(back2, r2[2]) == FaithHeavy.sacred(st2, r2[2]), "systèmes sacrés relus")
	_ok(back2 != null and back2.checksum() == st2.checksum(), "même empreinte avec les Astres vivants")
