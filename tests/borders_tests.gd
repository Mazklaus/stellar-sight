extends RefCounted
## Tests du pilier frontières et droit de passage, lot 1 : option de partie, politiques, droit de
## passage (armés, sans armes, liens forts, traité, guerre), intrusions et délai de sortie, option
## Strictes (blocage, reconduite), itinéraires qui contournent, traités de libre-passage et de
## prospection, ordres, IA, interface, sauvegarde. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Frontières, lot 1…")
	_test_option()
	_test_rights()
	_test_intrusion()
	_test_grace()
	_test_strict()
	_test_paths()
	_test_treaties()
	_test_prospection()
	_test_commands()
	_test_ai()
	_test_ui()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(mode := "souples", seed_value := 7, opts := {}) -> GameState:
	var o := {"ai_level": "", "borders": mode}
	o.merge(opts, true)
	var st := GameState.create(seed_value, 120, 1600.0, "vael", o)
	for e in st.empires:
		if e.is_npc():
			continue
		for x in st.empires:
			if x.id != e.id and not x.is_npc() and not e.contacts.has(x.id):
				e.contacts.append(x.id)
	return st


func _cap(st: GameState, eid: int) -> int:
	return FactionTraits.capital_system(st, eid)


func _spawn(st: GameState, owner: int, ships: Array, sid: int) -> Fleet:
	var f := st.spawn_ship(owner, String(ships[0]), sid)
	for i in range(1, ships.size()):
		f.add_ship(String(ships[i]))
	return f


func _memory(st: GameState, who: int, about: int, kind: String) -> int:
	for m in st.memories:
		if int(m["who"]) == who and int(m["about"]) == about and String(m["kind"]) == kind:
			return int(m["count"])
	return 0


func _test_option() -> void:
	var st := _new("libres")
	_ok(not Borders.active(st), "Option Libres : aucune règle de frontière")
	var f := _spawn(st, 1, ["corvette"], _cap(st, 0))
	_ok(Borders.fleet_right(st, f, 0), "Libres : une flotte armée va partout")
	var st2 := _new("souples")
	_ok(Borders.active(st2) and not Borders.strict(st2), "Option Souples active")
	_ok(Borders.strict(_new("strictes")), "Option Strictes")
	_ok(GameData.borders()["default_mode"] == "souples", "Souples par défaut dans le menu")


func _test_rights() -> void:
	var st := _new()
	var sid := _cap(st, 0)
	var war := _spawn(st, 1, ["corvette"], sid)
	var scout := _spawn(st, 1, ["scout"], sid)
	_ok(Borders.policy(st, 0, 1) == Borders.GUARDED, "Politique Gardée par défaut")
	_ok(not Borders.fleet_right(st, war, 0), "Gardée : une flotte de guerre n'a pas le droit d'entrer")
	_ok(Borders.fleet_right(st, scout, 0), "Gardée : un éclaireur sans armes a le passage inoffensif")
	Borders.set_policy(st, 0, 1, Borders.CLOSED)
	_ok(not Borders.fleet_right(st, scout, 0), "Close : même l'éclaireur est en intrusion")
	_ok(_memory(st, 1, 0, "borders_closed") == 1, "Fermer ses frontières déplaît")
	Borders.set_policy(st, 0, 1, Borders.OPEN)
	_ok(Borders.fleet_right(st, war, 0) and Borders.fleet_right(st, scout, 0), "Ouverte : libre-passage accordé")
	_ok(_memory(st, 1, 0, "borders_opened") == 1, "Ouvrir ses frontières plaît")
	_ok(not Borders.grants(st, 1, 0), "La politique est à sens unique")
	Borders.set_policy(st, 0, 1, Borders.GUARDED)
	Diplomacy._rel_w(st, 0, 1)["pact"] = Diplomacy.ALLIANCE
	_ok(Borders.fleet_right(st, war, 0), "Alliés : libre-passage")
	Diplomacy._rel_w(st, 0, 1)["pact"] = Diplomacy.COLD
	_ok(not Borders.fleet_right(st, war, 0), "Fin de l'alliance : plus de droit")
	st.get_empire(0).wars.append(1)
	st.get_empire(1).wars.append(0)
	_ok(Borders.fleet_right(st, war, 0), "En guerre, aucune frontière ne tient (on se bat)")
	st.get_empire(0).wars.erase(1)
	st.get_empire(1).wars.erase(0)
	st.get_empire(0).contacts.erase(1)
	_ok(Borders.fleet_right(st, war, 0), "Sans contact, pas encore de frontière")
	st.get_empire(0).contacts.append(1)
	_ok(Borders.route_warning(st, war, [sid]) != "", "Avertissement d'itinéraire en espace interdit")
	_ok(Borders.access_text(st, 0, 1).begins_with("Gardée"), "Texte d'accès")


func _test_intrusion() -> void:
	var st := _new()
	var sid := _cap(st, 0)
	var war := _spawn(st, 1, ["corvette"], sid)
	var sim := Simulation.new(st)
	sim.step()
	_ok(Borders.intruders(st, 0, 1).has(war.id), "Flotte armée sans droit : intrusion enregistrée")
	# Ossarane (Navigateurs, « Gens du voyage ») : la première intrusion est pardonnée.
	_ok(bool(Borders.talent(st, 1).get("first_free", false)) and _memory(st, 0, 1, "intrusion") == 0 and st.borders["first"].has("0>1"),
			"Gens du voyage : la première intrusion ne compte pas")
	war = _spawn(st, 1, ["corvette"], sid)
	sim.step()
	_ok(_memory(st, 0, 1, "intrusion") == 1, "Intrusion vue : souvenir chez le propriétaire")
	_ok(Diplomacy.opinion_parts(st, 0, 1).size() >= 0 and Diplomacy.opinion(st, 0, 1) <= Diplomacy.opinion(st, 1, 0) + 5, "L'intrusion pèse sur l'opinion")
	sim.step()
	_ok(_memory(st, 0, 1, "intrusion") == 1, "Une intrusion ne compte qu'une fois tant que la flotte reste")
	_ok(Borders.intrusions_in(st, 0).size() == 2, "Liste des intrusions chez soi")
	for i in 65:
		sim.step()
	Borders.monthly(st)
	_ok(_memory(st, 0, 1, "intr_stay") >= 1, "Stationner sans droit aggrave la faute chaque mois")
	# Un éclaireur sans armes passe sans intrusion.
	var scout := _spawn(st, 1, ["scout"], sid)
	sim.step()
	_ok(not Borders.intruders(st, 0, 1).has(scout.id), "L'éclaireur n'est pas un intrus")
	# Trêve : intrusion doublée.
	var st2 := _new()
	var r := Diplomacy._rel_w(st2, 0, 1)
	r["pact"] = Diplomacy.PEACE
	r["truce"] = st2.tick + 1000
	var truce := Diplomacy.in_truce(st2, 0, 1)
	st2.borders["first"]["0>1"] = 1
	_spawn(st2, 1, ["corvette"], _cap(st2, 0))
	Simulation.new(st2).step()
	_ok(not truce or _memory(st2, 0, 1, "intrusion") == 2, "Pendant une trêve, l'intrusion compte double")


func _test_grace() -> void:
	var st := _new()
	var sid := _cap(st, 0)
	Borders.set_policy(st, 0, 1, Borders.OPEN)
	var war := _spawn(st, 1, ["corvette"], sid)
	var sim := Simulation.new(st)
	sim.step()
	_ok(Borders.intruders(st, 0, 1).is_empty(), "Ouverte : aucune intrusion")
	Borders.set_policy(st, 0, 1, Borders.GUARDED)
	for i in 10:
		sim.step()
	_ok(Borders.intruders(st, 0, 1).is_empty(), "Le droit retiré laisse un délai pour sortir")
	for i in int(Borders.data()["grace_days"]):
		sim.step()
	_ok(Borders.intruders(st, 0, 1).has(war.id), "Délai écoulé : la flotte devient intruse")


func _test_strict() -> void:
	var st := _new("strictes")
	var sid := _cap(st, 0)
	var war := _spawn(st, 1, ["corvette"], sid)
	_ok(not Borders.can_enter(st, war, sid), "Strictes : l'espace interdit est infranchissable")
	Simulation.new(st).step()
	_ok(war.system_id != sid and not Borders.forbidden(st, war, war.system_id), "Strictes : la flotte sans droit est reconduite hors des frontières")
	_ok(Borders.intruders(st, 0, 1).is_empty(), "Strictes : pas d'intrusion, la flotte est repoussée")


func _test_paths() -> void:
	var st := _new("strictes")
	for sys in st.galaxy.systems:
		st.get_empire(1).explored[sys.id] = true
	var cap0 := _cap(st, 0)
	var cap1 := _cap(st, 1)
	var war := _spawn(st, 1, ["corvette"], cap1)
	var scout := _spawn(st, 1, ["scout"], cap1)
	var pw := Fleets.find_path(st, war.owner, cap1, cap0, Borders.path_flags(st, war))
	_ok(Borders.path_flags(st, war) & Borders.PATH_ARMED and Borders.path_flags(st, scout) & Borders.PATH_CIVIL, "Drapeaux d'itinéraire armé et civil")
	var ps := Fleets.find_path(st, scout.owner, cap1, cap0, Borders.path_flags(st, scout))
	_ok(not ps.is_empty(), "L'éclaireur trouve un chemin vers la capitale voisine")
	var bad := false
	for i in range(0, pw.size() - 1):
		var o := st.system_owner(int(pw[i]))
		if o == 0:
			bad = true
	_ok(not bad, "Strictes : l'itinéraire armé ne traverse pas l'espace interdit")
	Borders.set_policy(st, 0, 1, Borders.OPEN)
	var po := Fleets.find_path(st, war.owner, cap1, cap0, Borders.path_flags(st, war))
	_ok(not po.is_empty(), "Frontière ouverte : la flotte armée peut y aller")


func _test_treaties() -> void:
	var st := _new()
	var war := _spawn(st, 1, ["corvette"], _cap(st, 0))
	_ok(Diplomacy.check_terms(st, 0, 1, Diplomacy.PASSAGE) == "", "Traité de libre-passage possible")
	Diplomacy.sign_treaty(st, 0, 1, Diplomacy.PASSAGE)
	_ok(Borders.has_treaty(st, 0, 1) and Borders.fleet_right(st, war, 0), "Libre-passage : les flottes de guerre passent")
	_ok(Borders.grants(st, 1, 0), "Le traité est réciproque")
	_ok(Diplomacy.check_cancel(st, 0, 1, Diplomacy.PASSAGE) == "", "Le libre-passage se dénonce")
	Diplomacy.cancel(st, 0, 1, Diplomacy.PASSAGE)
	_ok(Borders.has_treaty(st, 0, 1) and Borders.treaty_end(st, 0, 1) > st.tick, "Dénonciation avec préavis")
	st.tick = Borders.treaty_end(st, 0, 1)
	Borders.treaties_daily(st)
	_ok(not Borders.has_treaty(st, 0, 1), "Préavis échu : fin du libre-passage")
	Diplomacy.sign_treaty(st, 0, 1, Diplomacy.PASSAGE)
	Borders.on_war(st, 0, 1)
	_ok(not Borders.has_treaty(st, 0, 1), "La guerre déchire le libre-passage")
	_ok(Diplomacy.check_terms(_new("libres"), 0, 1, Diplomacy.PASSAGE) != "", "Pas de libre-passage sans frontières")


func _test_prospection() -> void:
	var st := _new("souples", 7, {"curios": "nombreuses"})
	var sid := _cap(st, 0)
	_ok(not Borders.may_probe(st, 1, sid), "Sans traité, on ne sonde pas les curiosités d'autrui")
	_ok(Borders.may_probe(st, 0, sid), "Chez soi, on sonde")
	if not st.curios.is_empty():
		Diplomacy.sign_treaty(st, 0, 1, Diplomacy.PROSP)
		_ok(Borders.may_probe(st, 1, sid), "Traité de prospection : on sonde chez l'autre")


func _test_commands() -> void:
	var st := _new()
	var c := SimCommands.border_act(0, "policy", 1, -1, Borders.CLOSED)
	_ok(SimCommands.validate(st, c) == "", "Ordre de politique valide")
	SimCommands.apply(st, c)
	_ok(Borders.policy(st, 0, 1) == Borders.CLOSED, "Ordre de politique appliqué")
	_ok(SimCommands.validate(st, c) != "", "Même politique refusée")
	_ok(SimCommands.validate(st, SimCommands.border_act(0, "policy", 1, -1, "bidon")) != "", "Politique inconnue refusée")
	_ok(SimCommands.validate(_new("libres"), SimCommands.border_act(0, "policy", 1, -1, Borders.OPEN)) != "", "Sans frontières, pas d'ordre")


func _test_ai() -> void:
	var st := _new()
	for i in 4:
		Diplomacy.remember(st, 1, 0, "intrusion")
	Diplomacy.remember(st, 1, 0, "summons_ignored")
	Diplomacy.remember(st, 1, 0, "summons_ignored")
	var want := AiBorders.wanted_policy(st, 1, 0)
	var op := Diplomacy.opinion(st, 1, 0)
	_ok(op > int(AiBorders.cfg()["close_at"]) or want == Borders.CLOSED, "L'IA ferme ses frontières à qui elle déteste (opinion %d)" % op)
	st.get_empire(1).ai_level = "veteran"
	AiBorders.think_state(st, 1)
	_ok(Borders.policy(st, 1, 0) == want, "L'IA applique la politique voulue")
	var st2 := _new()
	_ok(AiBorders.wanted_policy(st2, 1, 0) == Borders.default_policy(st2, 1) or Diplomacy.opinion(st2, 1, 0) >= 40, "Neutre : politique par défaut")


func _test_ui() -> void:
	var st := _new()
	var buttons := {}
	var box := BordersUi.relation(st, 0, 1, func(_c: Dictionary) -> void: pass, buttons)
	_ok(buttons.has("policy_open") and buttons.has("policy_closed") and buttons["policy_guarded"].disabled, "Interface : trois politiques, l'actuelle grisée")
	_ok(buttons.has("access"), "Interface : accès affiché")
	box.free()
	var side := BordersUi.side(st, 0, 300)
	_ok(side.get_child_count() > 0, "Colonne frontières")
	side.free()
	var none := {}
	var b2 := BordersUi.relation(_new("libres"), 0, 1, func(_c: Dictionary) -> void: pass, none)
	_ok(none.is_empty(), "Interface : rien sans frontières")
	b2.free()


func _test_save() -> void:
	var st := _new()
	Borders.set_policy(st, 0, 1, Borders.CLOSED)
	_spawn(st, 1, ["corvette"], _cap(st, 0))
	Simulation.new(st).step()
	var d := st.to_dict()
	_ok(int(d["version"]) == GameState.FORMAT_VERSION and d.has("borders"), "Sauvegarde : frontières enregistrées")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and back.checksum() == st.checksum() and Borders.policy(back, 0, 1) == Borders.CLOSED and Borders.intruders(back, 0, 1).size() == 1,
			"Sauvegarde : politiques et intrusions relues")
	_ok(not _new("libres").to_dict().has("borders"), "Sans frontières, rien de plus dans la sauvegarde")
