class_name BestiaryPanel
extends RefCounted
## Onglet Bestiaire de l'écran Chroniques (proposition 14) : une fiche par espèce rencontrée
## (tempérament, mœurs, force en fourchette, faiblesse une fois étudiée, nids repérés, gibier abattu)
## et les attitudes (Étudier, Chasser, Apprivoiser, Renoncer). Les espèces encore inconnues restent des
## silhouettes. Boutons enregistrés dans es.chronicle_buttons pour les tests : « fauna:<espèce>:<attitude> ».


static func build(es: EmpireScreens, col: VBoxContainer) -> void:
	var state := es._state
	var player := es._player
	if not Fauna.active(state):
		col.add_child(UiTheme.dim("Pas de créatures dans cette partie (réglage de la Nouvelle partie).", 15))
		return
	var known := Fauna.known_species(state, player)
	var intro := Widgets.Block.new("Bestiaire")
	col.add_child(intro)
	intro.body.add_child(UiTheme.paragraph("Les créatures ne colonisent rien et n'entrent jamais dans un système revendiqué : elles vivent autour de leur nid et migrent à quelques sauts. Tant que le nid vit, un troupeau abattu renaît au bout de trois ans. On ne lit jamais leur force exacte, seulement une fourchette, plus précise une fois l'espèce étudiée.", 900.0, 14))
	intro.body.add_child(UiTheme.dim("%d espèce%s rencontrée%s sur %d." % [known.size(), "s" if known.size() > 1 else "", "s" if known.size() > 1 else "", Fauna.species_ids().size()], 13))
	var tl := Fauna.talent_labels(state, player)
	for t: Array in tl:
		intro.body.add_child(UiTheme.dim("Talent du peuple : %s. %s" % [t[0], t[1]], 13))
	_vivarium(es, col)
	for sp in known:
		col.add_child(_species_block(es, sp))
	for i in Fauna.species_ids().size() - known.size():
		col.add_child(_unknown_block())
	_guardians(es, col)
	_plagues(es, col)


## Fléaux errants (lot 3) : ceux que l'empire a vus, et ce qu'ils sont devenus.
static func _plagues(es: EmpireScreens, col: VBoxContainer) -> void:
	var state := es._state
	var player := es._player
	var seen := Plagues.known(state, player)
	if Plagues.ids(state).is_empty() and Plagues.plan(state).is_empty():
		return
	var intro := Widgets.Block.new("☠ Fléaux errants")
	col.add_child(intro)
	intro.body.add_child(UiTheme.paragraph("Pas avant l'an 15, un fléau peut se lever : il va de colonie en colonie (jamais une capitale), dévore la population et repart au bout d'un an s'il n'est pas abattu. Abattu à plusieurs, son Triomphe se partage selon les dégâts.", 900.0, 14))
	if seen.is_empty():
		intro.body.add_child(UiTheme.dim("Aucun fléau en vue. Pour l'instant.", 13))
	for pid in seen:
		var p: Dictionary = Plagues.list(state)[pid]
		var kd := Plagues.kind_def(String(p["kind"]))
		var blk := Widgets.Block.new(String(kd.get("name", "Fléau")))
		blk.body.add_child(UiTheme.paragraph(String(kd.get("text", "")), 900.0, 14))
		var tr := "Trait : %s" % String(kd.get("trait", ""))
		if String(p["star"]) != "":
			tr += " Sa couleur : %s." % GalaxyGenerator.star_label(String(p["star"])).to_lower()
		blk.body.add_child(UiTheme.dim(tr, 13))
		var line := ""
		match String(p["status"]):
			"alive":
				var f := Plagues.fleet_of(state, pid)
				var pr := Fauna.power_range(state, player, f) if f != null else [0, 0]
				@warning_ignore("integer_division")
				line = "En maraude, puissance %d à %d. %d colonie%s ravagée%s ; il repart dans %d jours." % [pr[0], pr[1], int(p["eaten"]),
						"s" if int(p["eaten"]) > 1 else "", "s" if int(p["eaten"]) > 1 else "",
						maxi(0, int(p["born"]) + int(Plagues.data()["life_days"]) - state.tick)]
			"dead":
				var by := int(p["by"])
				line = "Abattu%s." % ((" ; la plus belle part revient à %s" % state.empires[by].display_name()) if by >= 0 and by < state.empires.size() else "")
			"gone":
				line = "Reparti, repu, après %d colonie%s ravagée%s." % [int(p["eaten"]), "s" if int(p["eaten"]) > 1 else "", "s" if int(p["eaten"]) > 1 else ""]
		blk.body.add_child(UiTheme.dim(line, 13))
		col.add_child(blk)


## Gardiens (lot 2) : ceux que l'empire a vus, avec leur lieu, leur trait et leur sort.
static func _guardians(es: EmpireScreens, col: VBoxContainer) -> void:
	var state := es._state
	var player := es._player
	if Guardians.ids(state).is_empty():
		return
	var seen := Guardians.known(state, player)
	var intro := Widgets.Block.new("☠ Gardiens")
	col.add_child(intro)
	intro.body.add_child(UiTheme.paragraph("Des êtres uniques veillent sur les plus beaux systèmes. On peut traverser leur domaine, pas s'y installer tant qu'ils vivent. Les abattre rapporte un trophée, parfois une technologie hors de l'arbre, et un Triomphe.", 900.0, 14))
	intro.body.add_child(UiTheme.dim("%d gardien%s repéré%s sur %d dans cette galaxie." % [seen.size(), "s" if seen.size() > 1 else "", "s" if seen.size() > 1 else "", Guardians.ids(state).size()], 13))
	for gid in seen:
		var gd := Guardians.def(gid)
		var g: Dictionary = Guardians.list(state)[gid]
		var blk := Widgets.Block.new("%s  ·  %s" % [String(gd["name"]), String(gd.get("register", ""))])
		blk.body.add_child(UiTheme.paragraph(String(gd.get("text", "")), 900.0, 14))
		blk.body.add_child(UiTheme.dim("Trait : %s" % String(gd.get("trait", "")), 13))
		var home := int(g["home"])
		var where := state.galaxy.systems[home].system_name if home >= 0 else "?"
		var line := "Domaine : %s.  " % where
		match String(g["status"]):
			"awake":
				var f: Fleet = state.fleets.get(int(g["fleet"]))
				if f != null:
					var pr := Fauna.power_range(state, player, f)
					line += "Éveillé, puissance %d à %d, %s." % [pr[0], pr[1], "hostile" if Guardians.hostile(state, gid, player) else "pacifique"]
			"dormant":
				line += "Endormi. Mieux vaut ne pas le réveiller."
			"dead":
				var by := int(g["by"])
				line += "Mort%s." % ((" sous les coups de %s" % state.empires[by].display_name()) if by >= 0 and by < state.empires.size() else "")
			"studied":
				line += "Étudié, il ne menace plus personne."
			"pact":
				line += "Lié par un pacte."
		blk.body.add_child(UiTheme.dim(line, 13))
		col.add_child(blk)


## Vivarium (lot 3) : bêtes capturées au filet gravitationnel, leur stade, et le bouton pour les lâcher.
static func _vivarium(es: EmpireScreens, col: VBoxContainer) -> void:
	var state := es._state
	var player := es._player
	var cap := WarBeasts.capacity(state, player)
	var l := WarBeasts.beasts(state, player)
	if cap == 0 and l.is_empty():
		return
	var blk := Widgets.Block.new("Vivarium")
	col.add_child(blk)
	blk.body.add_child(UiTheme.dim("%d bête%s sur %d place%s. Un Chalutier du vide (ou un modèle à filet gravitationnel) à l'arrêt près d'un troupeau apprivoisé en capture une par mois." % [
			l.size(), "s" if l.size() > 1 else "", cap, "s" if cap > 1 else ""], 13))
	var d := WarBeasts.data()
	for i in l.size():
		var b: Dictionary = l[i]
		var st := WarBeasts.stage(state, b)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var age := state.tick - int(b["born"])
		var next := ""
		if st == "jeune":
			next = " (adulte dans %d jours)" % (int(d["adult_days"]) - age)
		elif st == "adulte":
			next = " (ancienne dans %d jours)" % (int(d["elder_days"]) - age)
		row.add_child(UiTheme.title("%s · %s%s" % [String(Fauna.species(String(b["sp"]))["label"]), WarBeasts.stage_label(st), next], 14))
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.text = "Lâcher dans une flotte"
		btn.theme_type_variation = &"PrimaryButton"
		var why := WarBeasts.check_release(state, player, i)
		btn.disabled = why != ""
		var unit := WarBeasts.unit_for(String(b["sp"]), st)
		btn.tooltip_text = ("Devient : %s (vivres au lieu de matériaux)." % String(GameData.ship(unit).get("label", unit))) + ("\n" + why if why != "" else "")
		var idx: int = i
		btn.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.beast_release(player, idx)))
		es.chronicle_buttons["beast:%d" % i] = btn
		row.add_child(btn)
		blk.body.add_child(row)


static func _unknown_block() -> Control:
	var blk := Widgets.Block.new("Espèce inconnue")
	blk.body.add_child(UiTheme.dim("Des éclaireurs parlent de formes dans le vide. Rencontrez-la pour l'inscrire au Bestiaire.", 14))
	return blk


static func _species_block(es: EmpireScreens, sp: String) -> Control:
	var state := es._state
	var player := es._player
	var sd := Fauna.species(sp)
	var blk := Widgets.Block.new(String(sd["label"]))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	var temper := UiTheme.title("%s" % Fauna.temper_label(sp), 16)
	temper.tooltip_text = String((Fauna.data()["tempers"][Fauna.temper(sp)] as Dictionary).get("text", ""))
	temper.mouse_filter = Control.MOUSE_FILTER_STOP
	head.add_child(temper)
	head.add_child(UiTheme.dim(_relation_text(state, player, sp), 14))
	blk.body.add_child(head)
	blk.body.add_child(UiTheme.paragraph(String(sd["text"]), 900.0, 14))
	var p := Fauna.species_power(sp)
	var spread := 15 if Fauna.studied(state, player, sp) else 40
	@warning_ignore("integer_division")
	var lo := maxi(1, p * (100 - spread) / 100 / 5 * 5)
	@warning_ignore("integer_division")
	var hi := (p * (100 + spread) / 100 + 4) / 5 * 5
	blk.body.add_child(UiTheme.paragraph("Troupeau type : %d %s, puissance %d à %d." % [int(sd.get("herd", 1)),
			String(GameData.ship(String(sd["unit"])).get("plural", "")).to_lower(), lo, hi], 900.0, 14))
	if Fauna.studied(state, player, sp):
		blk.body.add_child(UiTheme.paragraph("Faiblesse : %s" % String(sd["weakness"]), 900.0, 14))
		blk.body.add_child(UiTheme.paragraph("Étude terminée : %s" % String(sd.get("study_text", "")), 900.0, 14))
	elif Fauna.study_end(state, player, sp) > 0:
		blk.body.add_child(UiTheme.dim("Étude en cours : encore %d jours avant de connaître leur faiblesse." % (Fauna.study_end(state, player, sp) - state.tick), 14))
	else:
		blk.body.add_child(UiTheme.dim("Faiblesse inconnue : étudiez l'espèce.", 14))
	var nests: Array[String] = []
	for sid in Fauna.nest_ids(state):
		if String(Fauna.nests(state)[sid]["sp"]) == sp and Fleets.is_explored(state, player, sid):
			nests.append(state.galaxy.systems[sid].system_name)
	blk.body.add_child(UiTheme.dim(("Nid repéré : %s." % ", ".join(nests)) if not nests.is_empty() else "Aucun nid repéré.", 13))
	if Fauna.kills(state, player, sp) > 0:
		blk.body.add_child(UiTheme.dim("Abattues par vos flottes : %d." % Fauna.kills(state, player, sp), 13))
	var orders := HBoxContainer.new()
	orders.add_theme_constant_override("separation", 10)
	for att in ["etude", "chasse", "apprivoise", "renoncer"]:
		if att == "apprivoise" and not Fauna.tamable(state, player, sp):
			continue
		if att == "renoncer" and Fauna.stance(state, player, sp) == "":
			continue
		if att == "etude" and Fauna.study_end(state, player, sp) != 0:
			continue
		if (att == "chasse" or att == "apprivoise") and Fauna.stance(state, player, sp) == att:
			continue
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		var ad := Fauna.attitude_def(att)
		var cost := Fauna.attitude_cost_for(state, player, att)
		b.text = String(ad.get("label", "Renoncer")) + ((" (%s)" % GameData.format_amounts(cost)) if not cost.is_empty() else "")
		if att != "renoncer":
			b.theme_type_variation = &"PrimaryButton"
		var why := Fauna.check_attitude(state, player, sp, att)
		b.disabled = why != ""
		var text := String(ad.get("text", "Retour à l'humeur naturelle de l'espèce."))
		b.tooltip_text = text + ("\n" + why if why != "" else "")
		var a: String = att
		b.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.fauna_attitude(player, sp, a)))
		es.chronicle_buttons["fauna:%s:%s" % [sp, att]] = b
		orders.add_child(b)
	blk.body.add_child(orders)
	return blk


static func _relation_text(state: GameState, player: int, sp: String) -> String:
	match Fauna.stance(state, player, sp):
		"chasse":
			return "Votre gibier : +%d %% de dégâts contre elle." % int(Fauna.attitude_def("chasse").get("damage_pct", 0))
		"apprivoise":
			return "Apprivoisée : vos flottes et ses troupeaux se croisent en paix."
	return "Hostile à vos flottes." if Fauna.species_hostile(state, player, sp) else "Vous laisse passer."


## Ce qui change l'onglet.
static func signature(es: EmpireScreens) -> String:
	var state := es._state
	if not Fauna.active(state):
		return ""
	var s := str(Fauna._meta_r(state, es._player)) + str(Fauna.nest_ids(state)) + str(Guardians.known(state, es._player))
	for gid in Guardians.ids(state):
		s += String(Guardians.list(state)[gid]["status"])
	s += str(Plagues.known(state, es._player)) + str(WarBeasts.beasts(state, es._player)) + str(WarBeasts.capacity(state, es._player)) + str(state.tick / 30)
	for pid in Plagues.ids(state):
		s += String(Plagues.list(state)[pid]["status"]) + str(Plagues.list(state)[pid]["eaten"])
	for sp in Fauna.known_species(state, es._player):
		for att in Fauna.ATTITUDES:
			s += Fauna.check_attitude(state, es._player, sp, att)
	return s
