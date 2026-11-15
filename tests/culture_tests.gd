extends RefCounted
## Tests du rayonnement culturel, lot 1 (étude du 2026-11-15) : réglage et même empreinte sans le
## pilier ; Patrimoine de départ ; paliers ; sources (population sereine, Musée galactique et thème,
## stations de villégiature et beauté, merveilles culturelles) ; bâtiments et technologies ; diffusion
## (guerre, embargo, routes, sans lien, frontières fermées, gouvernements et credos) ; bilan mensuel
## (cumul, palier, annonce) ; Patrimoine nourri par l'influence ; revenu culturel ; sauvegarde 72 ;
## déterminisme. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Rayonnement culturel (socle)…")
	_test_setup()
	_test_tiers()
	_test_sources()
	_test_buildings()
	_test_flow()
	_test_monthly()
	_test_heritage()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func new_game(seed_value := 11, extra := {}) -> GameState:
	var o := {"ai_level": "", "culture": "actif"}
	o.merge(extra, true)
	return GameState.create(seed_value, 120, 1600.0, "vael", o)


## Met deux empires en contact (dans les deux sens).
static func meet(st: GameState, a: int, b: int) -> void:
	if not st.get_empire(a).contacts.has(b):
		st.get_empire(a).contacts.append(b)
	if not st.get_empire(b).contacts.has(a):
		st.get_empire(b).contacts.append(a)


## Bilan culturel d'un mois, seul (sans le reste de la simulation).
static func month(st: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	Culture.monthly(st, added)
	return added


static func colony_of(st: GameState, eid: int) -> Colony:
	return st.colonies[st.get_empire(eid).capital_planet]


func _test_setup() -> void:
	var off := new_game(11, {"culture": "aucun"})
	_ok(not Culture.enabled(off) and not off.to_dict().has("culture"), "« Aucun » : pas de rayonnement, rien dans la sauvegarde")
	var plain := GameState.create(11, 120, 1600.0, "vael", {"ai_level": ""})
	_ok(plain.checksum() == off.checksum(), "sans l'option, même empreinte qu'avant le pilier")
	var st := new_game()
	_ok(Culture.enabled(st) and st.to_dict().has("culture"), "« Actif » : le rayonnement est en jeu et sauvegardé")
	_ok(Culture.defect_mode(st) == "rare", "défection culturelle « rare » par défaut")
	_ok(Culture.default_mode() == "actif", "Nouvelle partie : rayonnement actif par défaut")
	var all_start := true
	for e in st.empires:
		all_start = all_start and Culture.heritage(st, e.id) == int(Culture.data()["start_heritage"])
	_ok(all_start, "chaque empire part avec le même Patrimoine")
	var act := new_game(11, {"culture_defect": "active"})
	_ok(Culture.defect_mode(act) == "active", "réglage de défection repris")
	_ok(Culture.defect_mode(new_game(11, {"culture_defect": "nimporte"})) == "rare", "réglage inconnu : « rare »")


func _test_tiers() -> void:
	_ok(Culture.tier_for_pct(0) == 0 and Culture.tier_for_pct(9) == 0, "sous 10 % : Inconnu")
	_ok(Culture.tier_for_pct(10) == 1 and Culture.tier_for_pct(30) == 2 and Culture.tier_for_pct(60) == 3, "10 / 30 / 60 % : Exotique, Familier, En vogue")
	_ok(Culture.tier_for_pct(100) == 4 and Culture.tier_for_pct(199) == 4 and Culture.tier_for_pct(200) == 5, "100 % Influent, 200 % Dominant (Civ V)")
	_ok(Culture.tier_label(4) == "Influent" and Culture.tier_label(5) == "Dominant", "noms des paliers")
	var st := new_game()
	meet(st, 0, 1)
	st.culture["cum"]["0>1"] = Culture.heritage(st, 1)
	_ok(Culture.ratio_pct(st, 0, 1) == 100, "cumul égal au Patrimoine de la cible : 100 %")


func _test_sources() -> void:
	var st := new_game()
	var parts := Culture.source_parts(st, 0)
	var pop := false
	for p in parts:
		pop = pop or String(p[0]).begins_with("Population sereine")
	_ok(pop and Culture.compute_radiance(st, 0) > 0, "la population sereine rayonne dès le départ")
	# Une ruche ne rayonne pas (talent Une seule voix).
	var kh := -1
	for e in st.empires:
		if e.faction_id == "khthari":
			kh = e.id
	if kh >= 0:
		_ok(Culture.source_parts(st, kh).is_empty() and Culture.tal(st, kh, "heritage_mult") == 2, "Kh'thari (ruche) : pas de Rayonnement, Patrimoine double")
	# Révolte : la population ne rayonne plus.
	var sid := FactionTraits.capital_system(st, 0)
	var before := Culture.compute_radiance(st, 0)
	Stability._entry_w(st, sid)["v"] = 0
	_ok(Culture.compute_radiance(st, 0) < before, "un système en révolte ne rayonne plus")
	Stability._entry_w(st, sid)["v"] = 50
	# Musée galactique : +3, et les reliques exposées ; thème complet doublé.
	var c := colony_of(st, 0)
	c.buildings.append("musee_galactique")
	_ok(Culture.has_museum(st, 0), "Musée galactique reconnu")
	var r0 := Culture.compute_radiance(st, 0)
	_ok(r0 >= before + int(Culture.data()["sources"]["museum"]), "le Musée rayonne")
	if not st.relics.is_empty():
		var trophees: Array[String] = []
		for rid in Relics.ids():
			if (Relics.def(rid).get("tags", []) as Array).has("trophee") and trophees.size() < 3:
				trophees.append(rid)
		for rid in trophees:
			Relics.gain(st, 0, rid)
		var ex := Culture.exposed(st, 0)
		_ok(ex.size() == 3 and Culture.theme_of(ex) == "trophee", "trois trophées exposés : thème complet")
		var withx := Culture.compute_radiance(st, 0)
		_ok(withx - r0 >= 3 * int(Culture.data()["sources"]["relic"]) * 2 * Culture.radiance_pct(st, 0) / 100 - 1, "thème complet : reliques doublées")
	else:
		_ok(true, "pas de reliques dans cette partie (test du thème sauté)")
	# Beauté et station de villégiature.
	var bsid := -1
	for s in st.galaxy.systems:
		if s.star_type == "black_hole":
			bsid = s.id
			break
	if bsid >= 0:
		_ok(Culture.beauty(st, bsid) >= 3, "un trou noir : beau système")
	_ok(Culture.beauty(st, sid) >= 0 and Culture.beauty(st, sid) <= 10, "beauté de 0 à 10")
	var r1 := Culture.compute_radiance(st, 0)
	c.buildings.append("villegiature")
	var r2 := Culture.compute_radiance(st, 0)
	_ok(r2 - r1 == Culture.beauty(st, sid) * Culture.radiance_pct(st, 0) / 100 or Culture.beauty(st, sid) == 0, "la station rayonne selon la beauté")
	var inc := CultureLife.income_of(st, 0)
	_ok(int(inc.get("energy", 0)) > 0, "la station rapporte de l'énergie (population à trois sauts)")
	# Merveille culturelle : +valeur, +1 par ère franchie.
	c.buildings.append("bibliotheque_mondes")
	_ok(Culture.wonder_value(st, 0, "bibliotheque_mondes") == 4 + maxi(0, Research.current_era(st, 0) - 2), "merveille : valeur + ère franchie")
	Research.grant(st, 0, ["holovision"])
	_ok(Culture.radiance_pct(st, 0) >= 125, "Holovision : Rayonnement +25 %")


func _test_buildings() -> void:
	var off := new_game(11, {"culture": "aucun"})
	Research.grant(off, 0, ["arts_holographiques"])
	_ok(not Economy.building_unlocked(off, 0, "musee_galactique"), "sans rayonnement, pas de Musée")
	_ok(Economy.check_build(off, 0, off.get_empire(0).capital_planet, "musee_galactique") != "", "chantier refusé sans rayonnement")
	var st := new_game()
	_ok(not Economy.building_unlocked(st, 0, "musee_galactique"), "Musée : il faut les Arts holographiques")
	Research.grant(st, 0, ["arts_holographiques"])
	_ok(Economy.building_unlocked(st, 0, "musee_galactique") and Economy.building_unlocked(st, 0, "villegiature"), "Arts holographiques : Musée et villégiature")
	var n := 0
	for bid in GameData.buildings():
		if int(GameData.building(String(bid)).get("culture_wonder", 0)) > 0:
			n += 1
			_ok(bool(GameData.building(String(bid)).get("galaxy_unique", false)), "merveille culturelle unique dans la galaxie : %s" % bid)
	_ok(n == 8, "huit merveilles culturelles (%d)" % n)
	for t in ["arts_holographiques", "holovision", "reseau_mondes", "conversion_culturelle"]:
		_ok(Research.exists(t), "technologie %s" % t)
	_ok(GameData.building("villegiature").get("outpost_ok", false), "villégiature possible sur un avant-poste")


func _test_flow() -> void:
	var st := new_game(11, {"borders": "souples"})
	meet(st, 0, 1)
	var fp := Culture.flow_parts(st, 0, 1)
	_ok(String(fp["cut"]) == "" and not bool(fp["link"]), "rencontrés sans lien : diffusion ouverte mais réduite")
	var nolink := Culture.flow_pct(st, 0, 1)
	Diplomacy.sign_treaty(st, 0, 1, Diplomacy.PEACE)
	Diplomacy.sign_treaty(st, 0, 1, Diplomacy.TRADE)
	var withlink := Culture.flow_pct(st, 0, 1)
	_ok(withlink > nolink, "un accord commercial lève la pénalité « sans lien » (%d %% contre %d %%)" % [withlink, nolink])
	st.trade["routes"] = [{"kind": "ext", "from": 0, "to": 1, "blocked": false, "net": 5, "value": 5}, {"kind": "ext", "from": 1, "to": 0, "blocked": false, "net": 5, "value": 5}]
	_ok(Culture.flow_pct(st, 0, 1) == withlink + 50, "deux routes : +50 %")
	st.trade["routes"].append({"kind": "ext", "from": 0, "to": 1, "blocked": true, "net": 0, "value": 5})
	_ok(Culture.flow_pct(st, 0, 1) == withlink + 50, "une route bloquée ne compte pas")
	if Borders.active(st):
		Borders.set_policy(st, 1, 0, Borders.CLOSED)
		var closed := false
		for p in Culture.flow_parts(st, 0, 1)["parts"]:
			closed = closed or String(p[0]) == "Frontières fermées"
		_ok(closed, "frontières fermées : -50 %")
	Trade.embargo(st, 1, 0)
	_ok(Culture.flow_pct(st, 0, 1) == 0 and String(Culture.flow_parts(st, 0, 1)["cut"]) == "embargo", "l'embargo coupe la diffusion")
	var st2 := new_game()
	meet(st2, 0, 1)
	st2.get_empire(0).wars.append(1)
	st2.get_empire(1).wars.append(0)
	_ok(Culture.flow_pct(st2, 0, 1) == 0, "la guerre coupe la diffusion")
	# Gouvernements et credos : entre deux peuples différents, au moins une ligne apparaît.
	var st3 := new_game()
	var found := false
	for e in st3.empires:
		if e.id == 0:
			continue
		var sa := FactionTraits.species(st3.get_empire(0).faction())
		var sb := FactionTraits.species(e.faction())
		if String(sa["gouvernement"]) != String(sb["gouvernement"]):
			meet(st3, 0, e.id)
			for p in Culture.flow_parts(st3, 0, e.id)["parts"]:
				found = found or String(p[0]).begins_with("Gouvernements")
			break
	_ok(found, "gouvernements différents : la diffusion baisse")


func _test_monthly() -> void:
	var st := new_game()
	meet(st, 0, 1)
	Diplomacy.sign_treaty(st, 0, 1, Diplomacy.PEACE)
	Diplomacy.sign_treaty(st, 0, 1, Diplomacy.TRADE)
	colony_of(st, 0).buildings.append("musee_galactique")
	month(st)
	_ok(Culture.radiance(st, 0) > 0, "bilan : Rayonnement calculé")
	_ok(Culture.cumul(st, 0, 1) > 0 and Culture.last(st, 0, 1) == Culture.cumul(st, 0, 1), "bilan : le Rayonnement se cumule chez la cible")
	_ok(Culture.cumul(st, 0, 2) == 0 or st.get_empire(0).contacts.has(2), "rien chez un empire jamais rencontré")
	st.culture["cum"]["0>1"] = Culture.heritage(st, 1) * 3
	var added := month(st)
	_ok(Culture.tier(st, 0, 1) == 5, "300 % : Dominant")
	var said := false
	for a in added:
		said = said or String(a.get("text", "")).find("Dominant") >= 0
	_ok(said, "le changement de palier est annoncé")
	_ok(Culture.months_to_next(st, 0, 1) == 0, "au plus haut : plus de palier suivant")
	# Peuples mineurs : version simple.
	var sm := new_game(11, {"minors": "normal"})
	var mid := Minors.ids(sm)[0]
	Minors.get_m(sm, mid)["contact"][0] = 0
	colony_of(sm, 0).buildings.append("musee_galactique")
	_ok(Culture.targets(sm, 0).has(mid), "un peuple mineur en contact est une cible")
	month(sm)
	_ok(Culture.cumul(sm, 0, mid) > 0, "le Rayonnement atteint le peuple mineur")


func _test_heritage() -> void:
	var st := new_game()
	var h0 := Culture.heritage(st, 0)
	Culture.note_influence(st, 0, 12)
	month(st)
	_ok(Culture.heritage(st, 0) >= h0 + 12, "l'influence du mois nourrit le Patrimoine")
	# Le bilan économique le fait tout seul.
	var sim := Simulation.new(new_game())
	sim.advance(61)
	_ok(Culture.heritage(sim.state, 0) > int(Culture.data()["start_heritage"]), "en partie, le Patrimoine grandit chaque mois")


func _test_save() -> void:
	_ok(GameState.FORMAT_VERSION == 72 and GameState.READABLE_VERSIONS.has(71), "sauvegarde 72, la 71 reste lisible")
	var sim := Simulation.new(new_game(13, {"ai_level": "normal"}))
	var st := sim.state
	sim.advance(400)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_snapshot())))
	_ok(back != null and back.checksum() == st.checksum(), "sauvegarde 72 relue, même empreinte")
	if back == null:
		return
	_ok(Culture.radiance(back, 0) == Culture.radiance(st, 0) and Culture.heritage(back, 1) == Culture.heritage(st, 1), "Rayonnement et Patrimoine relus")
	var a := Simulation.new(st)
	var b := Simulation.new(back)
	a.advance(200)
	b.advance(200)
	_ok(a.state.checksum() == b.state.checksum(), "la partie reprise continue à l'identique")
	var c1 := Simulation.new(new_game(21, {"ai_level": "normal"}))
	var c2 := Simulation.new(new_game(21, {"ai_level": "normal"}))
	c1.advance(300)
	c2.advance(300)
	_ok(c1.state.checksum() == c2.state.checksum(), "déterminisme : même graine, même partie")
