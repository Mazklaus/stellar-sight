extends RefCounted
## Tests du Contact, lot 2 (la course) : fragments et échanges, Consortium et victoire partagée,
## l'Écho et les lectures, brouillage, Forêt sombre, espionnage, Amphictyonie, « Faire taire », IA.
## Lot 3 (les voix) : contact_tests3.gd. Appelés par ContactTests.

const T := preload("res://tests/contact_tests.gd")

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Contact, la course…")
	print("  - fragments")
	_test_fragments()
	print("  - consortium")
	_test_consortium()
	print("  - echo_readings")
	_test_echo_readings()
	print("  - jam_dark_forest")
	_test_jam_dark_forest()
	print("  - spy_amph_war")
	_test_spy_amph_war()
	if ResourceLoader.exists("res://tests/contact_tests3.gd"):
		(load("res://tests/contact_tests3.gd") as GDScript).new().run(check)


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


## Deux empires du jeu (hors Kh'thari), qui se connaissent.
static func pair(st: GameState) -> Array[int]:
	var out: Array[int] = []
	for e in st.empires:
		if not e.is_npc() and Contact.t_int(st, e.id, "no_trade") == 0:
			out.append(e.id)
		if out.size() == 2:
			break
	for p in [[out[0], out[1]], [out[1], out[0]]]:
		if not st.get_empire(p[0]).contacts.has(p[1]):
			st.get_empire(p[0]).contacts.append(p[1])
	return out


func _test_fragments() -> void:
	var st := T.new_game()
	var p := pair(st)
	var a := p[0]
	var b := p[1]
	T.capture(st, a)
	_ok(T.cmd(st, a, "frag_trade", {"to": b}) != "", "Échanger : il faut que l'autre ait capté")
	_ok(T.cmd(st, a, "frag_give", {"to": b}) == "", "Donner son fragment")
	_ok(ContactRace.holds(st, b, a) and ContactRace.has_own(st, a), "Donner ne le fait pas perdre")
	T.capture(st, b)
	_ok(ContactRace.foreign_count(st, b) == 1 and Contact.abc_key(st, b), "Un fragment étranger : +1, et la clé de l'Abécédaire")
	var pct := 0
	for x in ContactRace.gauge_pct_parts(st, b):
		pct += int(x[1])
	_ok(pct == 20, "Un fragment : +20 %% de vitesse (%d)" % pct)
	# Échange avec un empire joueur : une offre à accepter.
	var st3 := T.new_game()
	var r := pair(st3)
	T.capture(st3, r[0])
	T.capture(st3, r[1])
	_ok(T.cmd(st3, r[1], "frag_trade", {"to": r[0]}) == "", "Proposer un échange")
	_ok(ContactRace.pending_offers(st3, r[0]).size() == 1, "L'offre attend la réponse")
	_ok(T.cmd(st3, r[0], "accept", {"kind": "frag_trade", "from": r[1]}) == "", "Accepter l'échange")
	_ok(ContactRace.holds(st3, r[0], r[1]) and ContactRace.holds(st3, r[1], r[0]), "Échange accepté : chacun a le fragment de l'autre")
	var kh := T.eid_of(st, "khthari")
	if kh >= 0:
		st.get_empire(a).contacts.append(kh)
		T.capture(st, kh)
		_ok(T.cmd(st, a, "frag_trade", {"to": kh}) != "", "Les Kh'thari ne négocient pas")
	var off := T.new_game("victoire")
	var q := pair(off)
	T.capture(off, q[0])
	_ok(T.cmd(off, q[0], "frag_give", {"to": q[1]}) != "", "Victoire seule : pas de fragments")


func _test_consortium() -> void:
	var st := T.new_game("complete", "ossarane", {"contact_nature": "bienveillants"})
	var p := pair(st)
	var a := p[0]
	var b := p[1]
	T.capture(st, a)
	T.capture(st, b)
	_ok(T.cmd(st, a, "cons_invite", {"to": b}) == "", "Inviter au Consortium")
	_ok(T.cmd(st, b, "accept", {"kind": "cons_invite", "from": a}) == "", "Accepter le Consortium")
	_ok(ContactRace.partners(st, a) == [b] and ContactRace.partners(st, b) == [a], "Consortium fondé")
	_ok(ContactRace.foreign_count(st, a) >= 1, "Le Consortium met en commun les fragments")
	Contact.sub(st, "gauge")[str(a)] = 600
	Contact.sub(st, "gauge")[str(b)] = 100
	ContactRace.monthly(st, [])
	_ok(Contact.gauge(st, b) >= 350, "Jauge tirée vers le plus avancé (%d)" % Contact.gauge(st, b))
	# Victoire partagée.
	T.rich(st, a)
	Contact.add_gauge(st, a, 750, [])
	(st.colonies[st.get_empire(a).capital_planet] as Colony).buildings.append("heraut")
	Contact.start_tx(st, a, [])
	Contact.tx(st, a)["prog"] = 99999
	Contact.tx(st, a)["start"] = -2000
	T.months(st, 1)
	_ok(Contact.done(st, a) and Contact.done(st, b), "La réponse vaut pour tout le Consortium")
	_ok(not bool(Victory.progress(st, b, "contact")["won"]) and bool(Victory.progress(st, a, "contact")["won"]), "Seul l'émetteur est proclamé")
	VictorySystem._monthly(st, 30, [])
	_ok(String(st.winner.get("victory", "")) == "contact" and int(st.winner["empire"]) == a and Array(st.winner["allies"]).has(b), "Victoire partagée avec le Consortium")
	# Quitter.
	var st2 := T.new_game()
	var q := pair(st2)
	T.capture(st2, q[0])
	T.capture(st2, q[1])
	ContactRace._join(st2, q[0], q[1], [])
	_ok(T.cmd(st2, q[1], "cons_leave") == "" and ContactRace.cons_id(st2, q[0]) < 0, "Quitter : le Consortium à deux se dissout")
	var grief := false
	for m in st2.memories:
		if String(m["kind"]) == "ct_cons_quit" and int(m["about"]) == q[1]:
			grief = true
	_ok(grief, "Quitter avant la Réponse : un grief")


func _test_echo_readings() -> void:
	var st := T.new_game()
	var p := pair(st)
	var a := p[0]
	T.capture(st, a)
	Contact.add_gauge(st, a, 500, [])
	_ok(Contact.has_layer(st, a, "echo") and not Contact.sub(st, "echo_hit").is_empty(), "L'Écho ressort la vieille émission d'un empire")
	var target := int(Contact.sub(st, "echo_hit").keys()[0])
	_ok(target != a, "Pas le lecteur lui-même")
	var hit: Dictionary = Contact.sub(st, "echo_hit")[str(target)][0]
	var label_seen := false
	for x in ContactRace.opinion_parts(st, a if a != target else p[1], target):
		if String(x[0]).begins_with("L'Écho"):
			label_seen = true
	_ok(label_seen or String(hit["k"]) == "hymne" or not Contact.applies(st, target), "Opinion : l'Écho (%s)" % hit["k"])
	Contact.read_layer(st, a, "menace")
	var neg := 0
	for x in ContactRace.opinion_parts(st, p[1], a):
		if String(x[0]).contains("arme"):
			neg = int(x[1])
	_ok(neg == -10, "Lecture menace : -10 d'opinion chez les autres (%d)" % neg)
	_ok(int(Research.effects(st, a).get("damage_pct", 0)) >= 3, "Lecture menace : +3 %% de dégâts")


func _test_jam_dark_forest() -> void:
	var st := T.new_game()
	st.contact["nature"] = "affames"
	var p := pair(st)
	var a := p[0]
	var b := p[1]
	T.capture(st, a)
	Contact.add_gauge(st, a, 500, [])
	_ok(ContactRace.jammed(st) == a, "Brouillage : le plus avancé")
	_ok(int((Research.effects(st, a).get("production_pct", {}) as Dictionary).get("knowledge", 0)) <= -20 + 3, "Brouillage : -10 %% de Savoir par couche")
	_ok(T.cmd(st, a, "dark_forest", {"to": b}) != "", "Forêt sombre : il faut savoir, et un Héraut")
	Contact.eliminate(st, a, 0, true)
	(st.colonies[st.get_empire(a).capital_planet] as Colony).buildings.append("heraut")
	var be := st.get_empire(b)
	be.resources["energy"] = 500
	be.resources["influence"] = 100
	_ok(T.cmd(st, a, "dark_forest", {"to": b}) == "", "Forêt sombre : la menace")
	_ok(int(be.resources["energy"]) == 300 and ContactRace.marked_target(st) < 0, "La cible cède et paie")
	be.resources["energy"] = 0
	Contact.eliminate(st, a, 0, true)
	_ok(T.cmd(st, a, "dark_forest", {"to": b}) == "" and ContactRace.marked_target(st) == b, "Elle ne peut pas payer : désignée aux Affamés")
	var st2 := T.new_game()
	st2.contact["nature"] = "batisseurs"
	var q := pair(st2)
	T.capture(st2, q[0])
	Contact.add_gauge(st2, q[0], 500, [])
	_ok(ContactRace.jammed(st2) < 0, "Pas de brouillage sans Affamés")


func _test_spy_amph_war() -> void:
	var st := T.new_game()
	var p := pair(st)
	var a := p[0]
	var b := p[1]
	T.capture(st, b)
	_ok(ContactRace.spy_check(st, a, b, "copier_releves") == "", "Copier les relevés : possible")
	ContactRace.spy_apply(st, a, b, {"id": "copier_releves"})
	_ok(ContactRace.holds(st, a, b), "Fragment volé")
	Contact.sub(st, "gauge")[str(b)] = 400
	ContactRace.spy_apply(st, a, b, {"id": "fragment_empoisonne"})
	_ok(Contact.gauge(st, b) == 300, "Fragment empoisonné : -10 %%")
	_ok(ContactRace.spy_check(st, a, b, "saboter_heraut") != "", "Saboter le Héraut : il faut qu'il transmette")
	var ops := 0
	for o: Dictionary in GameData.espionage()["operations"]:
		if bool(o.get("contact", false)):
			ops += 1
	_ok(ops == 3, "Trois opérations d'espionnage")
	_ok(not Amphictyony.family_def("signal").is_empty(), "Famille « Signal » de l'Amphictyonie")
	# Faire taire.
	Contact.add_gauge(st, b, 750, [])
	(st.colonies[st.get_empire(b).capital_planet] as Colony).buildings.append("heraut")
	T.rich(st, b)
	Contact.start_tx(st, b, [])
	_ok(Wars.casus_list(st, a, b).has("faire_taire"), "Casus belli « Faire taire » contre l'émetteur")
	_ok(not Wars.casus_list(st, b, a).has("faire_taire"), "Pas contre qui ne transmet pas")
	var t := Contact.tx(st, b)
	t["prog"] = 500
	ContactRace.spy_apply(st, a, b, {"id": "saboter_heraut"})
	_ok(int(t["prog"]) <= 410 and int(t["prog"]) >= 320, "Saboter le Héraut : 3 à 6 mois de retard (%d)" % int(t["prog"]))
	ContactRace.silence(st, a, b)
	_ok(not Contact.has_heraut(st, b), "Faire taire : le Héraut est démoli")
	_ok(typeof(ContactRace.objector(st, a)) == TYPE_BOOL, "Objecteurs : décision de l'IA")
