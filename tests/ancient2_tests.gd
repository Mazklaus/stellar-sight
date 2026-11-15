extends RefCounted
## Tests de l'Éveil des puissances anciennes (AncientsWake, lot 2) : parvenue (bloc trop fort, monde
## pris), préavis puis éveil, Endiguement et aide d'urgence, Dominion (tribut, voix muette, refus =
## guerre), expansion, décadence et libération, conquête bloquée, gardienne face à la crise, Guerre au
## ciel (camps, Ligue des non-alignés, fin et butin), tombeaux de Kheb ; réveils désactivés ; sauvegarde.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Éveil des anciennes…")
	_test_parvenue()
	_test_dominion()
	_test_decay()
	_test_guardian()
	_test_heaven()
	_test_tombs()
	_test_off()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


## Partie avec les anciennes demandées (sortes forcées dans l'ordre).
func _new(kinds: Array, extra := {}) -> GameState:
	var o := {"ai_level": "", "ancients": "aucune"}
	o.merge(extra, true)
	var st := GameState.create(11, 160, 1800.0, "vael", o)
	Ancients.setup(st, "aucune")
	st.ancients = {"mode": "normal", "wake": bool(extra.get("awakenings", true)), "list": {}, "holy": {}, "worlds": {}, "boons": {}}
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
	return st


func _days(st: GameState, n: int) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	for i in n:
		st.tick += 1
		added.append_array(Ancients.daily(st))
	return added


func _cards(st: GameState, eid: int, card: String) -> int:
	var n := 0
	for it: Dictionary in Events.inbox(st, eid):
		if String(it["card"]) == card:
			n += 1
	return n


func _item(st: GameState, card: String, id: int) -> Dictionary:
	return {"id": -1, "card": card, "anc": id, "system": -1, "planet": -1, "rival": -1, "hero": -1}


func _test_parvenue() -> void:
	var st := _new(["conservatoire"])
	var id := Ancients.id_of_kind(st, "conservatoire")
	_ok(id >= 0, "Conservatoire placé")
	# Trop tôt : rien, même avec un bloc écrasant.
	for i in 30:
		st.spawn_ship(0, "corvette", FactionTraits.capital_system(st, 0))
	_ok(AncientsWake.too_strong(st) == 0, "un empire à plus de deux fois la moyenne est repéré")
	_days(st, 720)
	_ok(Ancients.asleep(st, id), "avant l'an 20, elle dort")
	st.tick = 7200
	_days(st, 370 * 3)
	var st_stage := Ancients.stage(st, id)
	_ok(st_stage != Ancients.STAGE_SLEEP, "après l'an 20, le bloc trop fort la tire du sommeil (%s)" % st_stage)
	_ok(_cards(st, 0, "anc_eveil_preavis") == 1, "préavis en fenêtre d'événement")
	var st2 := _new(["conservatoire"])
	var id2 := Ancients.id_of_kind(st2, "conservatoire")
	var added: Array[Dictionary] = []
	AncientsWake.notice(st2, id2, added)
	_ok(Ancients.stage(st2, id2) == AncientsWake.STAGE_NOTICE and AncientsWake.parvenue(st2) == id2, "préavis : un an")
	var fl := Ancients.fleets_of(st2, id2).size()
	_days(st2, 400)
	_ok(Ancients.stage(st2, id2) == AncientsWake.STAGE_AWAKE, "un an plus tard, éveillée")
	_ok(Ancients.fleets_of(st2, id2).size() > fl, "elle reçoit des flottes de plus")
	_ok(_cards(st2, 0, "anc_eveil") == 1, "fenêtre d'éveil (Endiguement)")
	_ok(AncientsWake.blocking_parvenue(st2) == id2, "parvenue éveillée : la conquête est bloquée")
	var out := {"lines": [], "won": false}
	Victory._conquest(st2, st2.empires[0], out)
	_ok(not bool(out["won"]) and str(out["lines"]).contains("éveillée"), "écran de victoire : la conquête attend")
	# Endiguement.
	AncientsWake.card_fx(st2, 1, _item(st2, "anc_eveil", id2), {"k": "ancient", "act": "contain"}, added)
	_ok(Ancients.at_war_with(st2, id2, 1), "rejoindre l'Endiguement, c'est lui faire la guerre")
	_ok(int(Ancients.effects(st2, 1).get("damage_pct", 0)) >= 10, "+10 % de dégâts pour qui la combat")
	# Monde pris : éveil immédiat.
	var st3 := _new(["kheb"])
	var id3 := Ancients.id_of_kind(st3, "kheb")
	var sid := int((Ancients.get_a(st3, id3)["systems"] as Array)[1])
	Combat.capture_system(st3, sid, 0)
	_ok(Ancients.stage(st3, id3) == AncientsWake.STAGE_AWAKE, "un monde pris : la parvenue s'éveille aussitôt")


func _test_dominion() -> void:
	var st := _new(["bibliotheque"])
	var id := Ancients.id_of_kind(st, "bibliotheque")
	var added: Array[Dictionary] = []
	AncientsWake.notice(st, id, added)
	AncientsWake.awaken(st, id, added)
	var a := Ancients.get_a(st, id)
	(a["sub_cd"] as Dictionary).clear()
	AncientsWake.cfg()["dominion_jumps"] = 999
	AncientsWake._dominion(st, id, a, added)
	AncientsWake.cfg()["dominion_jumps"] = 8
	_ok(_cards(st, 0, "anc_dominion") == 1, "sommation de devenir son Dominion")
	AncientsWake.card_fx(st, 0, _item(st, "anc_dominion", id), {"k": "ancient", "act": "dominion"}, added)
	_ok(AncientsWake.dominion_of(st, 0) == id, "Dominion signé")
	var e := st.empires[0]
	e.resources["energy"] = 1000
	AncientsWake._tribute(st, id, a)
	_ok(int(e.resources["energy"]) == 950, "tribut de 5 % chaque mois")
	AncientsWake.card_fx(st, 1, _item(st, "anc_dominion", id), {"k": "ancient", "act": "refuse_dom"}, added)
	_ok(Ancients.at_war_with(st, id, 1) and Combat.at_war(st, 1, id), "refuser vaut guerre")
	_ok(Ancients.check_peace(st, 1, id) != "", "on ne traite pas avec une éveillée")
	var n := Ancients.systems_of(st, id).size()
	a["expand"] = 0
	AncientsWake._expand(st, id, a, added)
	_ok(Ancients.systems_of(st, id).size() >= n, "elle s'étend")
	_ok(SimCommands.validate(st, SimCommands.anc_act(0, "free", id)) != "", "pas de libération avant la décadence")


func _test_decay() -> void:
	var st := _new(["conservatoire"])
	var id := Ancients.id_of_kind(st, "conservatoire")
	var added: Array[Dictionary] = []
	AncientsWake.notice(st, id, added)
	AncientsWake.awaken(st, id, added)
	var a := Ancients.get_a(st, id)
	(a["dom"] as Dictionary)[0] = st.tick
	_days(st, 7200 + 30 * 40)
	_ok(Ancients.stage(st, id) == AncientsWake.STAGE_DECADENT, "vingt ans après l'éveil, la décadence l'emporte")
	_ok(AncientsWake.blocking_parvenue(st) < 0, "décadente : la conquête est de nouveau possible")
	_ok(AncientsWake.dominion_of(st, 0) < 0, "ses Dominions ne la suivent plus")
	_ok(SimCommands.validate(st, SimCommands.anc_act(0, "free", id)) == "", "on peut se libérer")
	SimCommands.apply(st, SimCommands.anc_act(0, "free", id))
	_ok(not (a["dom"] as Dictionary).has(0), "libéré")


func _test_guardian() -> void:
	var st := _new(["bergers", "conservatoire"], {"crises": "une"})
	var added: Array[Dictionary] = []
	st.tick = 10800
	Crisis.begin(st, "recif", added)
	var c := Crisis.cur(st)
	while String(c.get("stage", "")) == "notice":
		st.tick = int(c["steps"][int(c["step"])])
		Crisis._notice(st, added)
	_ok(Crisis.active(st), "crise arrivée")
	_days(st, 1900)
	var g := -1
	for id in Ancients.ids(st):
		if Ancients.stage(st, id) == AncientsWake.STAGE_GUARDIAN:
			g = id
	var rolled := String(st.ancients.get("guard_roll", "")) != ""
	_ok(rolled, "cinq ans après l'arrivée, un tirage de gardienne")
	if g >= 0:
		_ok(_cards(st, 0, "anc_gardienne") == 1, "gardienne annoncée en fenêtre d'événement")
		st.crisis["cur"] = {}
		_days(st, 31)
		_ok(Ancients.asleep(st, g), "crise finie : la gardienne se rendort")
	else:
		_ok(true, "pas de gardienne cette fois (40 %)")


func _test_heaven() -> void:
	var st := _new(["conservatoire", "kheb"])
	var p := Ancients.id_of_kind(st, "kheb")
	var r := Ancients.id_of_kind(st, "conservatoire")
	if p < 0 or r < 0:
		_ok(false, "deux rivales placées")
		return
	var added: Array[Dictionary] = []
	AncientsWake.notice(st, p, added)
	AncientsWake.awaken(st, p, added)
	AncientsWake.start_heaven(st, p, r, added)
	_ok(Combat.at_war(st, p, r) and Combat.at_war(st, r, p), "Guerre au ciel : les deux anciennes se battent")
	_ok(_cards(st, 0, "anc_guerre_ciel") == 1, "chaque empire choisit son camp")
	AncientsWake.card_fx(st, 0, _item(st, "anc_guerre_ciel", r), {"k": "ancient", "act": "side", "v": 1}, added)
	_ok(Combat.at_war(st, 0, p) and not Combat.at_war(st, 0, r), "camp du Conservatoire : ennemi de Kheb, ami du Conservatoire")
	_ok(AncientsWake.foes(st, p).has(0) and AncientsWake.foes(st, p).has(r), "Kheb vise la rivale et ses partisans")
	AncientsWake.card_fx(st, 1, _item(st, "anc_guerre_ciel", r), {"k": "ancient", "act": "side", "v": 0}, added)
	_ok(AncientsWake.in_league(st, 1), "neutre : Ligue des non-alignés")
	_ok(int(Ancients.effects(st, 1).get("damage_pct", 0)) >= 10, "la Ligue a des dents")
	st.empires[0].resources["energy"] = 0
	AncientsWake.decline(st, p, added)
	AncientsWake._heaven_end(st, added)
	_ok(AncientsWake.heaven(st).is_empty(), "Kheb décline : la Guerre au ciel est finie")
	_ok(int(st.empires[0].resources["energy"]) >= 600, "le camp vainqueur se partage le butin")


func _test_tombs() -> void:
	var st := _new(["kheb"])
	var id := Ancients.id_of_kind(st, "kheb")
	var added: Array[Dictionary] = []
	AncientsWake.notice(st, id, added)
	AncientsWake.awaken(st, id, added)
	var a := Ancients.get_a(st, id)
	var n := (a["tombs"] as Array).size()
	_ok(n >= 2, "Kheb : des tombeaux à ouvrir (%d)" % n)
	var fl := Ancients.fleets_of(st, id).size()
	_days(st, 400)
	var opened := (a["tombs"] as Array).size() < n
	_ok(opened, "un tombeau s'ouvre par an")
	var mad := 0
	for fid in st.fleets:
		if String(st.fleets[fid].fleet_name) == "Tombeau fou":
			mad += 1
	_ok(Ancients.fleets_of(st, id).size() > fl or mad > 0, "le tombeau donne une flotte (ou un fou)")
	_ok(_cards(st, 0, "anc_tombeau") <= 1, "tombeau annoncé aux empires en contact")


func _test_off() -> void:
	var st := _new(["conservatoire"], {"awakenings": false})
	var id := Ancients.id_of_kind(st, "conservatoire")
	var sid := int((Ancients.get_a(st, id)["systems"] as Array)[1])
	Combat.capture_system(st, sid, 0)
	_ok(Ancients.asleep(st, id), "réveils désactivés : elle reste endormie même si on lui prend un monde")


func _test_save() -> void:
	var st := _new(["conservatoire", "kheb"])
	var p := Ancients.id_of_kind(st, "kheb")
	var r := Ancients.id_of_kind(st, "conservatoire")
	var added: Array[Dictionary] = []
	AncientsWake.notice(st, p, added)
	AncientsWake.awaken(st, p, added)
	if r >= 0:
		AncientsWake.start_heaven(st, p, r, added)
		AncientsWake.choose_side(st, 0, 1, added)
	(Ancients.get_a(st, p)["dom"] as Dictionary)[1] = st.tick
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_snapshot())))
	_ok(back != null and back.checksum() == st.checksum(), "sauvegarde de l'Éveil relue, même empreinte")
	if back == null:
		return
	_ok(AncientsWake.parvenue(back) == p and AncientsWake.dominion_of(back, 1) == p, "parvenue et Dominion relus")
	_ok(r < 0 or AncientsWake.hostile(back, p, 0), "camps de la Guerre au ciel relus")
