extends RefCounted
## Tests de la religion, lot 3 : les 9 natures classiques (Église universelle, Patriarcats, Loi et
## Extase, Karma, Harmonie, Panthéon, Ancêtres, Dette de sang, Dieu présent), leurs contraintes de
## doctrine, leurs actions (commande faith_nat), l'IA et la sauvegarde 45.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Religion, lot 3 (les 9 natures classiques)…")
	_test_data()
	_test_eglise()
	_test_patriarcats()
	_test_loi_extase()
	_test_karma()
	_test_harmonie()
	_test_pantheon()
	_test_ancetres()
	_test_dette()
	_test_dieu()
	_test_commands()
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


func _cap(st: GameState, eid: int) -> Colony:
	return st.colonies.get(st.get_empire(eid).capital_planet)


func _sid(st: GameState, c: Colony) -> int:
	return st.galaxy.get_planet(c.planet_id).system_id


## La foi fondée par le Chœur passe à une autre nature (comme si son fondateur l'avait choisie).
func _with(nat: String, ai := "") -> Array:
	var st := _state(ai)
	var ch := _id_of(st, "choeur")
	var fc := Faiths.founded_by(st, ch)
	Faiths.faith(st, fc)["nature"] = nat
	FaithNatures.on_chosen(st, fc)
	return [st, ch, fc]


func _test_data() -> void:
	var nl: Dictionary = FaithWars.data()["natures"]["list"]
	var all := true
	for n in FaithNatures.CLASSIC:
		all = all and nl.has(n) and String(nl[n].get("src", "")) != ""
	_ok(all, "les 9 natures classiques sont en données, sourcées")
	_ok(FaithNatures.doctrine_block("patriarcats", "chef", "elu") != "", "Patriarcats : chef « Aucun » imposé")
	_ok(FaithNatures.doctrine_block("harmonie", "regard", "fondamentaliste") != "", "Harmonie : regard Fondamentaliste interdit")
	_ok(FaithNatures.doctrine_block("harmonie", "regard", "pluraliste") == "", "Harmonie : regard Pluraliste permis")
	_ok(FaithNatures.doctrine_block("dieu_present", "chef", "temporel") == "", "Dieu présent : chef Temporel permis")
	var dc := {"chef": "elu", "regard": "fondamentaliste"}
	FaithNatures.apply_forces("harmonie", dc)
	_ok(String(dc["regard"]) != "fondamentaliste", "doctrine interdite remplacée au choix de la nature")


func _test_eglise() -> void:
	var r := _with("eglise_universelle")
	var st: GameState = r[0]
	var ch: int = r[1]
	var fc: String = r[2]
	_ok(Faiths.doctrine(st, fc, "chef") == "elu", "Église universelle : chef Élu")
	_ok(FaithNatures.seats_taken(st, fc) == 1 and Faiths.head(st, fc) == ch, "le fondateur a un siège et il est Primat")
	_ok(int(FaithNatures.seat_cost(st, fc, ch)["influence"]) == 60, "siège suivant : 40 + 20 par siège tenu")
	FaithNatures.apply(st, ch, "seat", {})
	_ok(FaithNatures.seats_taken(st, fc) == 2, "siège acheté")
	_ok(FaithNatures.check(st, ch, "bull", {"kind": "mandat"}) == "", "le Primat émet une bulle")
	FaithNatures.apply(st, ch, "bull", {"kind": "mandat"})
	_ok(FaithNatures.pressure_pct(st, fc) == 25, "bulle de mandat : +25 % de pression")
	_ok(FaithNatures.check(st, ch, "bull", {"kind": "dime"}) != "", "une seule bulle à la fois")
	_ok(FaithNatures.reform(st, fc) >= 10, "une bulle nourrit le désir de réforme")
	FaithNatures.fdat(st, fc)["bull"] = {"kind": "croisade", "end": st.tick + 100}
	FaithNatures.fdat(st, fc)["free_crusade"] = true
	_ok(FaithNatures.free_crusade(st, fc), "bulle de croisade : une croisade offerte")
	FaithNatures.use_free_crusade(st, fc)
	_ok(not FaithNatures.free_crusade(st, fc), "croisade offerte consommée")
	# Élection : l'empire qui a le plus de sièges devient Primat à la fin du mandat.
	var t := _id_of(st, "teyl")
	st.faiths["state"][str(t)] = fc
	if Faiths.state_faith(st, t) == fc:
		FaithNatures.fdat(st, fc)["seats"][str(t)] = 5
		FaithNatures.fdat(st, fc)["term_end"] = st.tick
		FaithNatures._church_month(st, fc, _added())
		_ok(Faiths.head(st, fc) == t, "fumée blanche : le plus de sièges devient Primat")
	# Réforme : à 100, un schisme naît, avec les Patriarcats parmi les natures proposées.
	var n0 := Faiths.ids(st).size()
	var vc := _cap(st, _id_of(st, "vael"))
	vc.faith = {fc: vc.population}
	FaithNatures.fdat(st, fc)["reform"] = 100
	FaithNatures._reformation(st, fc, _added())
	_ok(Faiths.ids(st).size() == n0 + 1, "la Réforme fait naître une foi fille")
	_ok(FaithNatures.reform(st, fc) == 0, "désir de réforme remis à zéro")


func _test_patriarcats() -> void:
	var r := _with("patriarcats")
	var st: GameState = r[0]
	var ch: int = r[1]
	var fc: String = r[2]
	_ok(Faiths.doctrine(st, fc, "chef") == "aucun", "Patriarcats : chef Aucun imposé")
	_ok(FaithNatures.authority(st, ch) == 30, "autorité patriarcale de départ : 30")
	_ok(FaithNatures.heresy_pct(st, fc) == 50, "hérésies deux fois plus rares")
	_ok(FaithNatures.check(st, ch, "icon", {"kind": "stabilite"}) != "", "icône refusée sous 50 d'autorité")
	FaithNatures.add_authority(st, ch, 40)
	_ok(FaithNatures.check(st, ch, "icon", {"kind": "stabilite"}) == "", "icône possible à 70 d'autorité")
	FaithNatures.apply(st, ch, "icon", {"kind": "stabilite"})
	_ok(FaithNatures.authority(st, ch) == 20, "l'icône coûte 50 d'autorité")
	var sid := _sid(st, _cap(st, ch))
	var has := false
	for p in Faiths.stability_parts(st, sid, ch):
		has = has or String(p[0]) == "Icône de paix"
	_ok(has, "icône de paix : ligne de stabilité")
	FaithNatures.on_inquisition(st, ch)
	_ok(FaithNatures.authority(st, ch) == 15, "conversions forcées : -5 d'autorité")
	var auth := FaithNatures.authority(st, ch)
	FaithNatures._authority_month(st, st.get_empire(ch))
	_ok(FaithNatures.authority(st, ch) > auth, "l'autorité remonte avec le monde saint tenu")


func _test_loi_extase() -> void:
	var r := _with("loi_extase")
	var st: GameState = r[0]
	var ch: int = r[1]
	_ok(FaithNatures.piety(st, ch) == 0, "piété de départ : 0")
	FaithNatures.add_piety(st, ch, 60)
	var sid := _sid(st, _cap(st, ch))
	var has := false
	for p in Faiths.stability_parts(st, sid, ch):
		has = has or String(p[0]) == "Voie de la Loi"
	_ok(has, "Loi (piété 50 et plus) : +2 de stabilité")
	_ok(int(Faiths.effects(st, ch).get("law_upkeep_pct", 0)) <= -25, "Loi : lois moins chères à tenir")
	FaithNatures.add_piety(st, ch, -120)
	_ok(FaithNatures.piety(st, ch) == -60, "piété bornée et descendue vers l'Extase")
	_ok(FaithNatures.mission_pct(st, ch) == -50 and FaithNatures.hero_xp_pct(st, ch) == 25, "Extase : missions -50 %, héros +25 % d'expérience")
	FaithNatures.on_ward(st, ch)
	_ok(FaithNatures.piety(st, ch) == -57, "l'inquisition tire vers la Loi")
	_ok(FaithNatures.check(st, ch, "school", {"school": "mystique"}) == "", "choix d'une école")
	FaithNatures.apply(st, ch, "school", {"school": "mystique"})
	_ok(FaithNatures.check(st, ch, "school", {"school": "litterale"}) != "", "on ne change d'école qu'une fois tous les dix ans")


func _test_karma() -> void:
	var r := _with("karma")
	var st: GameState = r[0]
	var ch: int = r[1]
	var t := _id_of(st, "teyl")
	var sid := _sid(st, _cap(st, ch))
	var has := false
	for p in Faiths.stability_parts(st, sid, ch):
		has = has or String(p[0]) == "Karma en équilibre"
	_ok(has, "karma en équilibre : +2 de stabilité")
	FaithNatures.on_war(st, ch, t, false)
	_ok(FaithNatures.karma(st, ch) == -15, "déclarer une guerre : -15 de karma")
	FaithNatures.on_treaty(st, ch, t, "peace")
	_ok(FaithNatures.karma(st, ch) == -5, "signer la paix : +10")
	FaithNatures.on_status(st, ch, "citoyens", "extermines")
	_ok(FaithNatures.karma(st, ch) == -30, "exterminer : -25")
	FaithNatures.on_war(st, ch, t, false)
	_ok(FaithNatures.karma(st, ch) == -45, "deuxième guerre : karma sombre")
	_ok(int(Faiths.effects(st, ch).get("damage_pct", 0)) >= 10, "karma sombre : +10 % de dégâts")
	var op := 0
	for p in Faiths.opinion_parts(st, t, ch):
		if String(p[0]) == "Karma sombre":
			op = int(p[1])
	_ok(op == -10, "karma sombre : les autres se méfient (-10)")
	FaithNatures.on_status(st, ch, "assujettis", "citoyens")
	_ok(FaithNatures.karma(st, ch) == -35, "libérer un peuple : +10")
	FaithNatures.monthly(st, _added())
	_ok(FaithNatures.karma(st, ch) == -34, "le karma revient lentement vers l'équilibre")


func _test_harmonie() -> void:
	var r := _with("harmonie")
	var st: GameState = r[0]
	var ch: int = r[1]
	var fc: String = r[2]
	_ok(Faiths.doctrine(st, fc, "regard") != "fondamentaliste", "Harmonie : jamais Fondamentaliste")
	_ok(FaithNatures.harmony(st, ch) == 50, "harmonie de départ : 50")
	var other := ""
	for fid in Faiths.ids(st):
		if fid != fc and not (Faiths.faith(st, fid).get("precepts", []) as Array).is_empty():
			other = fid
			break
	_ok(FaithNatures.minor_exempt(st, ch, other), "harmonie 50 et plus : les autres fois ne coûtent pas de stabilité")
	var pid := String(Faiths.faith(st, other)["precepts"][0])
	var cc := _cap(st, ch)
	cc.faith[other] = 1
	Faiths.normalize(cc)
	_ok(FaithNatures.check(st, ch, "harmonize", {"faith": other, "precept": pid}) == "", "harmoniser une foi présente chez soi")
	FaithNatures.apply(st, ch, "harmonize", {"faith": other, "precept": pid})
	_ok(FaithNatures.harmony(st, ch) == 10, "harmoniser coûte 40")
	_ok(not FaithNatures.minor_exempt(st, ch, other), "harmonie basse : plus d'exemption (foi pas encore harmonisée)")
	FaithNatures.emp(st, ch)["harm"][0]["end"] = st.tick
	FaithNatures._harmony_month(st, st.get_empire(ch), _added())
	_ok((FaithNatures.fdat(st, fc).get("extra", []) as Array).has(pid), "dix ans plus tard : le précepte est copié")
	_ok(FaithNatures.no_hostility(st, ch, other), "foi harmonisée : plus d'hostilité")


func _test_pantheon() -> void:
	var r := _with("pantheon")
	var st: GameState = r[0]
	var ch: int = r[1]
	var fc: String = r[2]
	var gods: Array = FaithNatures.fdat(st, fc)["gods"]
	_ok(gods.size() == 4, "4 dieux au panthéon")
	var g0 := String(gods[0])
	var fx0: Dictionary = FaithNatures.cd()["pantheon"]["domains"][g0]["fx"]
	var k := String(fx0.keys()[0])
	var base := Faiths.effects(st, ch)
	Faiths.faith(st, fc)["zeal"] = 50
	if Faiths.head(st, fc) != ch:
		Faiths.faith(st, fc)["doctrines"]["chef"] = "temporel"
	_ok(FaithNatures.check(st, ch, "omen", {"kind": g0}) == "", "présage possible")
	FaithNatures.apply(st, ch, "omen", {"kind": g0})
	_ok(FaithWars.zeal(st, fc) == 40, "un présage coûte 10 de zèle")
	_ok(str(Faiths.effects(st, ch).get(k, 0)) != str(base.get(k, 0)), "présage : l'effet du dieu est triplé")
	_ok(FaithNatures.check(st, ch, "omen", {"kind": g0}) != "", "un présage tous les cinq ans")
	var nw := ""
	for d in FaithNatures.cd()["pantheon"]["domains"]:
		if not gods.has(d):
			nw = String(d)
			break
	FaithNatures.apply(st, ch, "god_swap", {"old": String(gods[1]), "new": nw})
	_ok((FaithNatures.fdat(st, fc)["gods"] as Array).has(nw), "dieu remplacé")
	var h := {"owner": ch, "name": "Héros test", "cls": "stratege", "lvl": 5, "traits": []}
	FaithNatures.on_hero_death(st, h, -1, _added())
	_ok(not (FaithNatures.fdat(st, fc).get("hero_god", {}) as Dictionary).is_empty(), "apothéose d'un héros de niveau 5")


func _test_ancetres() -> void:
	var r := _with("ancetres")
	var st: GameState = r[0]
	var ch: int = r[1]
	var fc: String = r[2]
	var cc := _cap(st, ch)
	_ok(FaithNatures.check_mausoleum(st, ch, cc.planet_id) == "", "mausolée constructible sur la capitale")
	_ok(Economy.building_unlocked(st, ch, "mausolee"), "mausolée débloqué par la nature")
	var t := _id_of(st, "teyl")
	_ok(not Economy.building_unlocked(st, t, "mausolee"), "pas de mausolée pour une autre nature")
	for i in 4:
		FaithNatures.on_hero_death(st, {"owner": ch, "name": "Aïeul %d" % i, "cls": "stratege", "lvl": 1, "traits": []}, -1, _added())
	_ok(FaithNatures.active_ancestors(st, ch).size() == 3, "seuls les 3 derniers ancêtres sont actifs")
	var e0 := Faiths.effects(st, ch).duplicate(true)
	cc.buildings.append("mausolee")
	Relics.touch(st)
	_ok(Faiths.effects(st, ch) != e0, "le mausolée réveille les ancêtres")
	FaithNatures.on_hero_death(st, {"owner": ch, "name": "Aïeul tué", "cls": "stratege", "lvl": 1, "traits": []}, t, _added())
	var mem := false
	for m in st.memories:
		mem = mem or (String(m["kind"]) == "faith_hero_slain" and int(m["about"]) == t)
	_ok(mem, "héros tué : les fidèles s'en souviennent")
	var zeal := FaithWars.zeal(st, fc)
	FaithNatures._profane(st, ch, t, cc.planet_id, _added())
	_ok(FaithWars.zeal(st, fc) == zeal - 20, "profanation : -20 de zèle")
	_ok(FaithNatures.casus(st, ch, t) != "", "profanation : motif de guerre sainte contre le profanateur")


func _test_dette() -> void:
	var r := _with("dette_sang")
	var st: GameState = r[0]
	var ch: int = r[1]
	var fc: String = r[2]
	_ok(FaithNatures.debt(st, fc) == 30, "dette de départ : 30")
	_ok(int(Faiths.effects(st, ch).get("damage_pct", 0)) >= 10, "dette basse : +10 % de dégâts")
	FaithNatures._debt_month(st, fc, _added())
	_ok(FaithNatures.debt(st, fc) == 31, "la dette monte chaque mois")
	var cc := _cap(st, ch)
	var pop := cc.population
	FaithNatures.apply(st, ch, "offer", {"planet": cc.planet_id})
	_ok(cc.population == pop - 1 and FaithNatures.debt(st, fc) == 23, "offrande : un habitant, -8 de dette")
	FaithNatures.fdat(st, fc)["debt"] = 99
	FaithNatures._debt_month(st, fc, _added())
	_ok(FaithNatures.debt(st, fc) == 50, "dette échue : remise à 50")


func _test_dieu() -> void:
	var r := _with("dieu_present")
	var st: GameState = r[0]
	var ch: int = r[1]
	var fc: String = r[2]
	_ok(Faiths.doctrine(st, fc, "chef") == "temporel", "Dieu présent : chef Temporel imposé")
	var g := FaithNatures.live_god(st, fc)
	_ok(not g.is_empty(), "le dieu apparaît au monde saint")
	var holy_sid := st.galaxy.get_planet(int(Faiths.faith(st, fc)["holy"])).system_id
	_ok(int(g["sid"]) == holy_sid, "le dieu est au monde saint")
	_ok(Faiths.head(st, fc) == st.system_owner(holy_sid) or Faiths.head(st, fc) == -1, "le chef de foi est l'empire qui l'abrite")
	var nb := int(st.galaxy.systems[holy_sid].neighbors[0])
	st.get_empire(ch).explored[nb] = true
	if Faiths.head(st, fc) == ch:
		_ok(FaithNatures.check(st, ch, "god_move", {"system": nb}) == "", "le chef guide le dieu")
		FaithNatures.apply(st, ch, "god_move", {"system": nb})
		FaithNatures.fdat(st, fc)["god"]["next"] = st.tick
		FaithNatures._god_month(st, fc, _added())
		_ok(int(FaithNatures.live_god(st, fc)["sid"]) == nb, "le dieu avance d'un saut")
	FaithNatures.fdat(st, fc)["god"]["dead_until"] = st.tick + 10
	_ok(FaithNatures.live_god(st, fc).is_empty() and Faiths.head(st, fc) == -1, "dieu mort : plus de chef")
	st.tick += 10
	FaithNatures._god_month(st, fc, _added())
	_ok(int(FaithNatures.live_god(st, fc)["sid"]) == holy_sid, "il revient au monde saint")


func _test_commands() -> void:
	var r := _with("loi_extase")
	var st: GameState = r[0]
	var ch: int = r[1]
	_ok(SimCommands.validate(st, SimCommands.faith_nat(ch, "school", {"school": "litterale"})) == "", "ordre : école")
	SimCommands.apply(st, SimCommands.faith_nat(ch, "school", {"school": "litterale"}))
	_ok(FaithNatures.school(st, ch) == "litterale", "ordre d'école appliqué")
	_ok(SimCommands.validate(st, SimCommands.faith_nat(ch, "icon", {"kind": "guerre"})) != "", "ordre refusé hors de la bonne nature")
	_ok(SimCommands.validate(st, SimCommands.faith_nat(ch, "rien", {})) != "", "action inconnue refusée")


func _test_ai() -> void:
	var r := _with("eglise_universelle", "normal")
	var st: GameState = r[0]
	var fc: String = r[2]
	FaithNatures.ai(st)
	for i in 3:
		FaithNatures.monthly(st, _added())
		FaithNatures.ai(st)
	_ok(FaithNatures.seats_taken(st, fc) >= 2, "l'IA achète des sièges au Collège")
	_ok(not (FaithNatures.fdat(st, fc).get("bull", {}) as Dictionary).is_empty(), "l'IA Primat émet une bulle")
	var r2 := _with("loi_extase", "normal")
	FaithNatures.ai(r2[0])
	_ok(FaithNatures.school(r2[0], r2[1]) != "", "l'IA choisit une école")


func _test_save() -> void:
	var r := _with("karma")
	var st: GameState = r[0]
	var ch: int = r[1]
	FaithNatures.add_karma(st, ch, -40)
	var d := st.to_dict()
	_ok(int(d["version"]) == 49, "sauvegarde version 49")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and FaithNatures.karma(back, ch) == -40, "karma relu")
	_ok(back != null and back.checksum() == st.checksum(), "même empreinte après relecture (lot 3)")
	var r2 := _with("dieu_present")
	var d2 := (r2[0] as GameState).to_dict()
	var back2 := GameState.from_dict(JSON.parse_string(JSON.stringify(d2)))
	_ok(back2 != null and not FaithNatures.live_god(back2, r2[2]).is_empty(), "dieu présent relu")
	_ok(back2 != null and back2.checksum() == (r2[0] as GameState).checksum(), "même empreinte avec un dieu présent")
