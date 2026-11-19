extends RefCounted
## Tests du lot 3 de la refonte de l'arbre de recherche (étude https://claude.ai/artifact/2M77BwzqiBMt6zXSCKCq72) :
## les technologies des piliers (props 48 à 68), leurs effets branchés dans chaque module, les
## trouvailles de crise, d'anciennes et de hauts faits, les voies de transcendance, les Maîtrises de
## Kardashev et les eurêkas de pilier (prop. 16).

var _check: Callable

const LOT3 := ["cryptographie", "contre_espionnage", "agents_dormants", "theologie_comparee", "grands_temples", "schisme_reforme",
		"doctrine_commandement", "generaux_corps", "legendes_vivantes", "protocole_cour", "genealogies", "grands_mariages",
		"sondages", "institutions", "droit_federal", "clienteles", "diplomatie_multilaterale", "droit_societes", "courtage",
		"xenologie", "patrouilles_stellaires", "amnistie", "xenozoologie", "dressage", "biologie_leviathans", "protectorats",
		"elevation", "biosemiotique", "symbioses_planetaires", "douanes_stellaires", "cartographie_juridique", "droit_guerre",
		"logistique_occupation", "restauration_ecologique"]


func run(check: Callable) -> void:
	_check = check
	print("Arbre de recherche (lot 3) : les technologies des piliers…")
	_test_data()
	_test_pillars()
	_test_espionage_faith_heroes()
	_test_court_politics_diplomacy()
	_test_economy_peoples()
	_test_creatures_minors_worlds()
	_test_borders_war()
	_test_finds()
	_test_transcendence_kardashev()
	_test_eurekas()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _state(faction := "vael", options := {}) -> GameState:
	var o := {"ai_level": ""}
	o.merge(options, true)
	return GameState.create(4242, 150, 1800.0, faction, o)


func _home(st: GameState, eid := 0) -> Colony:
	return st.colonies[st.get_empire(eid).capital_planet]


func _open(st: GameState, domain: String, era: int) -> void:
	var techs: Dictionary = GameData.technologies()["technologies"]
	var f := st.get_empire(0).faction()
	for tid: String in techs:
		var t: Dictionary = techs[tid]
		if String(t["domain"]) == domain and int(t.get("era", 1)) < era and Research.is_visible(f, tid) \
				and not t.has("mastery") and not t.has("find") and not t.has("spec"):
			Research.grant(st, 0, [tid])


func _test_data() -> void:
	for tid in LOT3:
		var t := Research.tech(tid)
		_ok(not t.is_empty(), "lot 3 : %s existe" % tid)
		_ok(t.has("eureka") and Research.eureka_text(tid) != "", "lot 3 : %s a une eurêka lisible (prop. 16)" % tid)
	for pid in Research.pillar_ids():
		_ok(Research.pillar_label(pid) != pid or pid == "", "piliers : %s a un libellé" % pid)
	# Bâtiments déplacés vers leur technologie de pilier.
	var moved := {"bureau_renseignement": "cryptographie", "institut_heros": "doctrine_commandement", "grand_temple": "grands_temples",
			"grand_mausolee": "grands_temples", "quartiers_accueil": "xenologie", "reserve_integrale": "restauration_ecologique"}
	for b in moved:
		_ok((GameData.building(b).get("requires_tech", []) as Array).has(moved[b]), "bâtiments : %s vient de %s" % [b, moved[b]])


func _test_pillars() -> void:
	var st := _state()
	var f := st.get_empire(0).faction()
	_ok(not Research.is_visible(f, "theologie_comparee", st, 0), "piliers : sans religions, pas de Théologie comparée")
	_ok(not Research.is_visible(f, "sondages", st, 0), "piliers : sans politique, pas de Sondages")
	_ok(Research.is_visible(f, "cryptographie", st, 0), "piliers : la Cryptographie est toujours là")
	st.faith_on = true
	_ok(Research.is_visible(f, "theologie_comparee", st, 0), "piliers : avec les religions, la Théologie comparée apparaît")
	var st2 := _state("vael", {"politics": "active", "court": Court.default_mode(), "rulers": "mortels"})
	var f2 := st2.get_empire(0).faction()
	_ok(Research.is_visible(f2, "sondages", st2, 0), "piliers : avec la politique, les Sondages apparaissent")
	_ok(Research.is_visible(f2, "protocole_cour", st2, 0) == Court.enabled(st2), "piliers : le Protocole de cour suit la cour")


func _test_espionage_faith_heroes() -> void:
	var st := _state()
	var enc := Espionage.encryption(st, 0)
	var dec := Espionage.decryption(st, 0)
	Research.grant(st, 0, ["cryptographie"])
	_ok(Espionage.encryption(st, 0) == enc + 1 and Espionage.decryption(st, 0) == dec + 1, "Cryptographie : chiffrement et déchiffrement +1")
	Research.grant(st, 0, ["contre_espionnage"])
	_ok(Research.fx_int(st, 0, "counter_x") == 1, "Contre-espionnage : les cellules à domicile pèsent une fois de plus")
	Research.grant(st, 0, ["agents_dormants"])
	_ok(Research.fx_int(st, 0, "sleepers") == 1, "Agents dormants : effet en place")
	# Héros
	var mt := Heroes.max_traits(st, 0)
	Research.grant(st, 0, ["doctrine_commandement", "legendes_vivantes"])
	_ok(Heroes.max_traits(st, 0) == mt + 1, "Légendes vivantes : un trait de plus (%d → %d)" % [mt, Heroes.max_traits(st, 0)])
	var h := {"id": 999, "owner": 0, "xp": 0, "lvl": 1, "traits": [], "cls": "stratege", "name": "Test", "sp": ""}
	Heroes.gain_xp(st, h, 100)
	_ok(int(h["xp"]) >= 125, "Doctrine de commandement : +25 % d'expérience (%d)" % int(h["xp"]))
	# Généraux de corps : le général mène aussi le sol du système voisin.
	var sid := st.galaxy.get_planet(st.get_empire(0).capital_planet).system_id
	var nb: int = st.galaxy.get_system(sid).neighbors[0]
	var fl: Fleet = null
	for fid in st.fleets:
		if (st.fleets[fid] as Fleet).owner == 0:
			fl = st.fleets[fid]
			break
	_ok(fl != null and not st.heroes.is_empty(), "lot 3 : option héros en jeu pour le test")
	if fl != null and not st.heroes.is_empty():
		var hid: int = Heroes.ids_of(st, 0)[0] if not Heroes.ids_of(st, 0).is_empty() else -1
		if hid >= 0:
			var hh: Dictionary = st.heroes[hid]
			hh["post"] = "army"
			hh["target"] = fl.id
			hh["arrive"] = 0
			fl.system_id = sid
			_ok(Ground.generals_at(st, 0, nb, true).is_empty(), "Généraux de corps : sans la technologie, rien au système voisin")
			Research.grant(st, 0, ["generaux_corps"])
			_ok(not Ground.generals_at(st, 0, nb, true).is_empty(), "Généraux de corps : le général mène le système voisin")
			_ok(Ground.generals_at(st, 0, nb).is_empty(), "Généraux de corps : la capture reste au seul système de la flotte")


func _test_court_politics_diplomacy() -> void:
	var st := _state()
	var mc := Court.max_count(st, 0)
	Research.grant(st, 0, ["protocole_cour"])
	_ok(Court.max_count(st, 0) == mc + 1, "Protocole de cour : une maison de plus")
	var mp := AmphPower.max_props(st, 0)
	Research.grant(st, 0, ["diplomatie_multilaterale"])
	_ok(AmphPower.max_props(st, 0) == mp + 1, "Diplomatie multilatérale : une proposition de plus")
	var st2 := _state("vael", {"politics": "active"})
	_ok(Politics.applies(st2, 0) and Politics.mode(st2, 0) != "continuous", "lot 3 : option politique en jeu pour le test")
	if Politics.applies(st2, 0) and Politics.mode(st2, 0) != "continuous":
		var before := Politics.sees_forecast(st2, 0)
		Research.grant(st2, 0, ["sondages"])
		_ok(not before and Politics.sees_forecast(st2, 0), "Sondages : le résultat de l'élection se voit avant le vote")
		Research.grant(st2, 0, ["institutions"])
		var sid := st2.galaxy.get_planet(st2.get_empire(0).capital_planet).system_id
		var op: Array = Politics.opinion(st2, sid)
		var i := 0
		var was := int(op[i])
		Politics.push(st2, sid, i, Politics.TOTAL)
		_ok(int(Politics.opinion(st2, sid)[i]) - was <= Politics.TOTAL / 5 + 5, "Institutions : pas plus d'un cinquième d'un coup")


func _test_economy_peoples() -> void:
	var st := _state("vael", {"private": "complete"})
	_ok(Private.enabled(st), "lot 3 : option économie privée en jeu pour le test")
	if Private.enabled(st):
		var cm := Private.charter_max(st, 0)
		Research.grant(st, 0, ["droit_societes"])
		_ok(Private.charter_max(st, 0) == cm + 1, "Droit des sociétés : une charte de plus")
	var st2 := _state("vael", {"peoples": "actifs"})
	var c := _home(st2)
	var r0 := Peoples.integration_rate(st2, c, "ossarane")
	Research.grant(st2, 0, ["xenologie"])
	var r1 := Peoples.integration_rate(st2, c, "ossarane")
	c.buildings.append("quartiers_accueil")
	var r2 := Peoples.integration_rate(st2, c, "ossarane")
	_ok(r1 > r0 and r2 > r1, "Xénologie et Quartiers d'accueil : l'intégration va plus vite (%d → %d → %d)" % [r0, r1, r2])


func _test_creatures_minors_worlds() -> void:
	var st := _state()
	var c := _home(st)
	c.buildings.append("vivarium")
	var cap := WarBeasts.capacity(st, 0)
	Research.grant(st, 0, ["xenozoologie", "dressage"])
	_ok(WarBeasts.capacity(st, 0) == cap + 2, "Dressage : deux places de plus au Vivarium (%d → %d)" % [cap, WarBeasts.capacity(st, 0)])
	_ok(String(Minors.data()["presapients"]["tech"]) == "elevation", "Élévation : c'est elle qui ouvre l'élévation des pré-conscients")
	_ok(not Research.tech("elevation").has("needs"), "Élévation : ouverte aux peuples sans naissance (variante de Quiétude)")
	# Écologie : la Réserve intégrale soigne en plus de la Réserve naturelle.
	c.buildings.append("reserve_naturelle")
	var care0 := Ecology.care(st, c.planet_id)
	c.buildings.append("reserve_integrale")
	_ok(Ecology.care(st, c.planet_id) == care0 + 25, "Restauration écologique : +25 de soins avec la Réserve intégrale")


func _test_borders_war() -> void:
	var st := _state()
	Research.grant(st, 0, ["douanes_stellaires", "cartographie_juridique", "droit_guerre", "logistique_occupation"])
	_ok(Research.fx_int(st, 0, "customs") == 1 and Research.fx_int(st, 0, "claim_reach") == 2, "Douanes et cartographie : effets en place")
	_ok(Research.fx_int(st, 0, "laws_of_war") == 1 and Research.fx_int(st, 0, "occupation") == 1, "Droit de la guerre et occupation : effets en place")


func _test_finds() -> void:
	var st := _state()
	var got := Research.grant_find(st, 0, "deeds")
	_ok(got != "" and Research.is_find(got), "trouvailles : un haut fait en donne une (%s)" % got)
	var got2 := Research.grant_find(_state(), 0, "ancients")
	_ok(got2 != "" and Research.is_find(got2), "trouvailles : une puissance ancienne en donne une (%s)" % got2)
	var st2 := _state("vael", {"crises": "une"})
	_ok(Crisis.enabled(st2), "lot 3 : option crises en jeu pour le test")
	if Crisis.enabled(st2):
		_open(st2, "armement", 3)
		var cf := Research.grant_find(st2, 0, "crisis")
		_ok(cf == "contre_mesures_crise", "trouvailles : le présage d'une crise donne les Contre-mesures (%s)" % cf)


func _test_transcendence_kardashev() -> void:
	var st := _state("vael", {"transcendence": "complete"})
	var f := st.get_empire(0).faction()
	_ok(not Research.is_visible(f, "voie_songe", st, 0), "voies : aucune technologie de voie avant d'en choisir une")
	Transcendence.sub(st, "path")["0"] = "mue"
	_ok(Research.is_visible(f, "voie_mue", st, 0) and not Research.is_visible(f, "voie_songe", st, 0), "voies : seule la voie choisie se montre")
	Research.grant(st, 0, ["voie_mue"])
	_ok(Transcendence.gain_parts(st, 0).any(func(x): return String(x[0]).begins_with("Voie approfondie")), "voies : la technologie de voie remplit la jauge")
	var st2 := _state("vael", {"kardashev": "complete"})
	_ok(Kardashev.enabled(st2), "lot 3 : option Kardashev en jeu pour le test")
	if Kardashev.enabled(st2):
		Research.grant(st2, 0, ["fusion_compacte"])
		Kardashev.sub(st2, "k")["0"] = 50
		_ok(Research.gate_reason(st2, 0, "reseau_planetaire") != "", "Kardashev : la Maîtrise attend le type I")
		Kardashev.sub(st2, "k")["0"] = 100
		_ok(Research.gate_reason(st2, 0, "reseau_planetaire") == "", "Kardashev : type I atteint, la Maîtrise s'ouvre")


func _test_eurekas() -> void:
	var st := _state()
	var e := st.get_empire(0)
	var s0 := Research.eureka_status(st, 0, "cryptographie")
	_ok(int(s0[1]) == 2, "eurêkas de pilier : la Cryptographie demande deux opérations")
	e.stats["operations"] = 2
	_ok(int(Research.eureka_status(st, 0, "cryptographie")[0]) == 2, "eurêkas de pilier : le compteur d'opérations est lu")
	_ok(Research.eureka_text("xenozoologie").contains("créatures"), "eurêkas de pilier : texte des créatures abattues")
