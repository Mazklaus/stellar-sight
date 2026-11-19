extends RefCounted
## Tests du lot 4 de la refonte de l'arbre de recherche (étude https://claude.ai/artifact/2M77BwzqiBMt6zXSCKCq72) :
## branches d'archétype (props 73 à 77), credos (79), peuples du GDD (81 à 88) : technologies propres,
## bâtiments de peuple qui remplacent un bâtiment commun, coques améliorées, trois talents de recherche.

var _check: Callable

const LOT4 := {"geophagie": "gravea", "cristallisation": "gravea", "strates_vivantes": "quietude",
		"condensateurs_ame": "murmurants", "resonance_stellaire": "ysmer", "corps_denses": "murmurants",
		"chaines_flux": "teyl", "chassis_specialises": "teyl", "chassis_etanches": "teyl",
		"cocons_guerre": "khthari", "ganglion_mere": "khthari", "grandes_serres": "vergemonde",
		"racines_profondes": "vergemonde", "dissemination": "vergemonde",
		"comptabilite_occulte": "brisecomete", "grandes_fetes": "zambalu", "normalisation": "bureau",
		"abris_profonds": "khthari", "signes_presages": "exode", "seuils": "ysmer", "longue_patience": "gravea",
		"discretion": "quietude", "inventaire": "cassivel",
		"routes_saphene": "ossarane", "traducteurs_universels": "vael", "maillage": "teyl", "noeuds_relais": "teyl",
		"campements_fortifies": "ferrocornes", "pillage_methodique": "ferrocornes", "planques": "brisecomete", "contrats_chaine": "brisecomete",
		"faux_papiers": "brisecomete", "voile_profond": "murmurants", "chorale": "murmurants"}

const VARIANTS := {"donjon_lignee": "camp_recrutement", "reliquaire_forge": "arsenal", "tribune": "forum",
		"bassin_ponte": "cale_seche", "fonderie_chassis": "clinique", "campement_clan": "depot_flotte",
		"tripot_portuaire": "maison_spectacles"}


func run(check: Callable) -> void:
	_check = check
	print("Arbre de recherche (lot 4) : couches d'espèce et peuples du GDD…")
	_test_data()
	_test_variants()
	_test_talents()
	_test_effects()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _state(faction := "vael", options := {}) -> GameState:
	var o := {"ai_level": ""}
	o.merge(options, true)
	return GameState.create(4242, 150, 1800.0, faction, o)


func _home(st: GameState, eid := 0) -> Colony:
	return st.colonies[st.get_empire(eid).capital_planet]


func _test_data() -> void:
	var vael := GameData.faction("vael")
	for tid: String in LOT4:
		var t := Research.tech(tid)
		_ok(not t.is_empty() and t.has("requires"), "lot 4 : %s existe et appartient à une couche d'espèce" % tid)
		_ok(Research.is_visible(GameData.faction(String(LOT4[tid])), tid), "lot 4 : %s se voit chez %s" % [tid, LOT4[tid]])
		if tid != "traducteurs_universels":
			_ok(not Research.is_visible(vael, tid), "lot 4 : %s ne se voit pas chez la Concorde de Vael" % tid)
	_ok(Research.is_visible(vael, "traducteurs_universels"), "lot 4 : la Concorde a ses Traducteurs universels")
	_ok(String(Research.tech("monopole")["label"]) == "Charte des cristaux" and int(Research.tech("monopole")["effects"].get("toll_x", 0)) == 1,
			"prop. 81 : le Monopole devient la Charte des cristaux (péages doublés)")
	# Chaque peuple du GDD a au moins quatre technologies propres.
	for fid in ["ossarane", "choeur", "vael", "khthari", "teyl", "ferrocornes", "brisecomete", "murmurants"]:
		var f := GameData.faction(fid)
		var n := 0
		for tid in Research.visible_ids(f):
			if Research.tech(tid).has("requires") and not Research.tech(tid).has("victory"):
				n += 1
		_ok(n >= 4, "props 81 à 88 : %s a %d technologies de peuple" % [fid, n])
	# Coques améliorées.
	for pair in [["cocons_guerre", "ruche_mere"], ["noeuds_relais", "noosphere_mere"], ["faux_papiers", "cargo_corsaire"],
			["chorale", "abysse_chantante"], ["campements_fortifies", "belier_clan"], ["forges_nefs", "cathedrale"]]:
		_ok(PeopleHulls.upgrades_of(pair[0]).has(pair[1]), "coques de peuple : %s améliore %s" % pair)
	for b: String in VARIANTS:
		_ok(GameData.building_kind(b) == VARIANTS[b] and GameData.building_variants(VARIANTS[b]).has(b),
				"bâtiments de peuple : %s remplace %s" % [b, VARIANTS[b]])


func _test_variants() -> void:
	var st := _state("vael")
	var c := _home(st)
	_ok(Economy.variant_for(st, 0, "forum") == "forum" or Research.knows(st, 0, "assemblees"), "Tribune : pas avant les Assemblées")
	Research.grant(st, 0, ["assemblees"])
	_ok(Economy.variant_for(st, 0, "forum") == "tribune", "Tribune : remplace le Forum chez la Concorde")
	_ok(not Economy.building_unlocked(st, 0, "forum") and Economy.building_unlocked(st, 0, "tribune"), "Tribune : le Forum disparaît de la liste")
	var why := Economy.check_build(st, 0, c.planet_id, "forum")
	_ok(not why.begins_with("réservé") and not why.begins_with("technologie"), "Tribune : demander un Forum construit la Tribune (%s)" % why)
	c.buildings.erase("forum")
	c.buildings.append("tribune")
	_ok(c.has_kind("forum") and c.kind_index("forum") == c.buildings.find("tribune"), "Tribune : compte comme un Forum")
	_ok(Economy.check_build(st, 0, c.planet_id, "forum") == "déjà construit sur cette planète", "Tribune : pas de Forum en plus")
	# Ailleurs : un autre peuple garde son Forum.
	var st2 := _state("choeur")
	Research.grant(st2, 0, ["assemblees"])
	_ok(Economy.variant_for(st2, 0, "forum") == "forum", "Tribune : le Chœur garde son Forum")
	# Le 2e rang d'un bâtiment remplacé accepte le bâtiment de peuple.
	var st3 := _state("ossarane")
	var c3 := _home(st3)
	Research.grant(st3, 0, ["conscription_planetaire", "vassalite", "medecine_campagne"])
	_ok(Economy.variant_for(st3, 0, "camp_recrutement") == "donjon_lignee", "Donjon de lignée : remplace le Camp de recrutement")
	c3.buildings.append("donjon_lignee")
	var p3 := st3.galaxy.get_planet(c3.planet_id)
	_ok(not Economy.check_special(st3, 0, c3, p3, "academie_militaire").begins_with("remplace"), "Donjon de lignée : l'Académie militaire peut le remplacer")
	# Stabilité : la Tribune compte comme le Forum.
	var bsrc: Dictionary = GameData.stability()["sources"]["buildings"]
	_ok(int(bsrc.get("forum", 0)) > 0, "stabilité : le Forum en donne")


func _test_talents() -> void:
	# Compilation (Teyl) : une technologie de même domaine et de même champ rend la suivante moins chère.
	var st := _state("teyl")
	var e := st.get_empire(0)
	var same := "raffinage"
	var other := "banques_donnees"
	var g := "extraction" if not e.techs.has("extraction") else "hydroponie"
	_ok(not e.techs.has(same) and not e.techs.has(other) and not e.techs.has(g), "Compilation : technologies de test inconnues au départ")
	var s0 := Research.cost(st, 0, same)
	var o0 := Research.cost(st, 0, other)
	Research.grant(st, 0, [g])
	var s1 := Research.cost(st, 0, same)
	var o1 := Research.cost(st, 0, other)
	_ok(s1 * o0 < o1 * s0, "Compilation : la production suivante coûte relativement moins (%d → %d, savoir %d → %d)" % [s0, s1, o0, o1])
	# Écoute des abysses (Murmurants) : +1 % de Savoir pour 4 Échos, 25 % au plus.
	var st2 := _state("murmurants")
	var m := st2.get_empire(0)
	m.echoes = 40
	_ok(Economy.echo_knowledge_pct(st2, 0) == 10, "Écoute des abysses : 40 Échos, +10 % de Savoir")
	m.echoes = 400
	_ok(Economy.echo_knowledge_pct(st2, 0) == 25, "Écoute des abysses : plafond à 25 %")
	_ok(Economy.echo_knowledge_pct(_state("vael"), 0) == 0, "Écoute des abysses : rien chez les autres")
	var gain := Echoes.monthly_gain(st2, 0)
	Research.grant(st2, 0, ["chorale"])
	_ok(Echoes.monthly_gain(st2, 0) == gain + 2, "Chorale des abysses : +2 Échos par mois")
	# Butin de clan (Ferrocornes).
	_ok(int(GameData.faction("ferrocornes")["research"].get("loot_knowledge_pct", 0)) == 50, "Butin de clan : la moitié du butin en Savoir")


func _test_effects() -> void:
	var st := _state("brisecomete")
	var h0: Dictionary = Pirates.hire_cost(st, 0)
	Research.grant(st, 0, ["contrats_chaine"])
	var h1: Dictionary = Pirates.hire_cost(st, 0)
	var k := String(h0.keys()[0]) if not h0.is_empty() else ""
	_ok(k != "" and int(h1[k]) < int(h0[k]), "Contrats à la chaîne : engager des pirates coûte moins (%s → %s)" % [h0, h1])
	Research.grant(st, 0, ["faux_papiers"])
	_ok(Research.fx_int(st, 0, "forged_papers") == 1, "Faux papiers : effet en place")
	var st2 := _state("teyl")
	var n0 := FactionTraits.network_systems(st2, 0).size()
	Research.grant(st2, 0, ["maillage", "noeuds_relais"])
	_ok(FactionTraits.network_systems(st2, 0).size() >= n0, "Maillage et Nœuds relais : le réseau ne rétrécit pas")
	var st3 := _state("murmurants")
	Research.grant(st3, 0, ["voile_profond"])
	_ok(Research.fx_int(st3, 0, "cloak") == 1, "Voile profond : camouflage +1")
	var st4 := _state("gravea")
	Research.grant(st4, 0, ["geophagie", "adaptation", "strates_vivantes"])
	_ok(Research.fx_sub(st4, 0, "hab_set", "barren") == 50,
			"Strates vivantes : mondes stériles à 50 % au moins")
