class_name CrisisPanel
extends RefCounted
## Onglet Crise de l'écran Chroniques (prop. 13 et 30 des crises de fin de partie) : fiche lisible de la
## crise en cours (ce qu'elle veut, son point faible, l'arme conseillée), son avancée vers la défaite
## commune, ses points faibles connus, la contribution de chaque empire et le Front commun ; puis les
## crises passées. Avant la fin de partie : la date et les réglages. Voir Crisis.


static func build(es: EmpireScreens, col: VBoxContainer) -> void:
	var state := es._state
	var player := es._player
	if not Crisis.enabled(state):
		col.add_child(_dim("Pas de crise de fin de partie dans cette partie (réglage de la Nouvelle partie).", 15))
		return
	var c := Crisis.cur(state)
	if c.is_empty():
		col.add_child(_waiting(state))
	elif String(c["stage"]) == "notice" and not Crisis.known(state, player):
		col.add_child(_waiting(state))  # présage privé d'autres peuples : on ne sait rien
	elif String(c["stage"]) == "notice":
		col.add_child(_notice(state, player))
	else:
		col.add_child(_sheet(state, player))
		if not CrisisKinds.project(state).is_empty():
			col.add_child(_project(es))
		col.add_child(_progress(state, player))
		if bool(Crisis.kind_def(Crisis.kind(state)).get("fleetless", false)):
			col.add_child(_fleetless(state, player))
		else:
			col.add_child(_weak_points(es))
	var tl := CrisisAllies.talents_of(state, player)
	if not tl.is_empty():
		var tb := Widgets.Block.new("Votre peuple face aux crises")
		for t: Dictionary in tl:
			tb.body.add_child(UiTheme.paragraph("%s (%s) : %s" % [String(t["label"]), Crisis.name_of(String(t["kind"])), String(t["text"])], 900.0, 13))
		col.add_child(tb)
	if CrisisNemesis.enabled(state):
		col.add_child(_nemesis(es))
	for p: Dictionary in (state.crisis.get("past", []) as Array):
		col.add_child(_past(state, p))


static func _waiting(state: GameState) -> Control:
	var blk := Widgets.Block.new("☄ La fin de partie")
	var day := Crisis.endgame_day(state)
	var cr := state.crisis
	var txt := "Quelque part, au-delà de la bordure ou sous le vernis des choses, quelque chose attend son heure."
	if state.tick < day:
		txt += " La fin de partie commence le %s ; ensuite, tous les deux ans, la menace peut se lever, de plus en plus sûrement." % GameCalendar.date_string(day)
	elif String(cr["mode"]) == "une" and int(cr["count"]) >= 1:
		txt = "La grande crise de cette partie est passée. On en parlera longtemps."
	else:
		txt += " La fin de partie a commencé : tous les deux ans, la menace peut se lever."
	blk.body.add_child(UiTheme.paragraph(txt, 900.0, 14))
	if int(cr.get("pull", 0)) > 0:
		@warning_ignore("integer_division")
		blk.body.add_child(_dim("Des actes imprudents (technologies interdites, reliques, atrocités) l'ont avancée de %d ans." % (int(cr["pull"]) / 360), 13))
	var mode := String(Crisis._find(Crisis.mode_defs(), String(cr["mode"])).get("label", cr["mode"]))
	var strength := String(Crisis._find(Crisis.strength_defs(), String(cr["str"])).get("label", cr["str"]))
	blk.body.add_child(_dim("Réglages : crises %s, force %s." % [mode.to_lower(), strength.to_lower()], 13))
	return blk


static func _notice(state: GameState, player: int) -> Control:
	var c := Crisis.cur(state)
	var blk := Widgets.Block.new("☄ Présages")
	var off := 1 if c.has("seers") else 0
	if off == 1 and (c["seers"] as Array).has(player):
		blk.body.add_child(UiTheme.paragraph("Vos mystiques l'ont senti avant tout le monde : %s s'ouvrira près de %s." % [
				Crisis.name_of(Crisis.kind(state)), state.galaxy.systems[int(c["origin"])].system_name if int(c["origin"]) >= 0 else "la bordure"], 900.0, 14))
	for i in range(off, int(c["step"])):
		blk.body.add_child(UiTheme.paragraph(Crisis.step_text(state, i - off), 900.0, 14))
	var steps: Array = c["steps"]
	if int(c["step"]) < steps.size():
		blk.body.add_child(_dim("Prochain signe dans %d jours environ." % maxi(0, int(steps[int(c["step"])]) - state.tick), 13))
	return blk


## Fiche lisible (prop. 13) : nom, registre, texte, ce qu'elle veut, son point faible, l'arme conseillée.
static func _sheet(state: GameState, player: int) -> Control:
	var k := Crisis.kind(state)
	var kd := Crisis.kind_def(k)
	var blk := Widgets.Block.new("☄ %s  ·  %s" % [Crisis.name_of(k), String(kd.get("register", ""))])
	blk.body.add_child(UiTheme.paragraph(String(kd.get("text", "")), 900.0, 14))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 18)
	blk.body.add_child(g)
	for row in [["Ce qu'elle veut", String(kd.get("wants", ""))], ["Son point faible", String(kd.get("weak", ""))], ["Arme conseillée", String(kd.get("tip", ""))]]:
		g.add_child(UiTheme.dim(String(row[0]), 13))
		g.add_child(UiTheme.paragraph(String(row[1]), 720.0, 13))
	var fate := Crisis.fate_of(state)
	if fate.has("prod_pct") and bool(kd.get("fleetless", false)):
		blk.body.add_child(_dim("Une étoile éteinte ne produit plus qu'à %d %%, et ses habitants s'en vont." % int(fate["prod_pct"]), 13))
	elif fate.has("prod_pct"):
		blk.body.add_child(_dim("Un système tombé ne produit plus qu'à %d %%, tant qu'une de ses flottes y reste." % int(fate["prod_pct"]), 13))
	var lines: Array[String] = []
	for b: Dictionary in Crisis.boons(state, player):
		var left := "jusqu'à la fin de la crise" if bool(b.get("end", false)) else "encore %d mois" % (maxi(0, int(b["until"]) - state.tick) / 30)
		lines.append("%s (%s, %s)" % [String(b["label"]), Relics.fx_text(b["fx"]), left])
	if not lines.is_empty():
		blk.body.add_child(_dim("Vos préparatifs : " + " ; ".join(lines), 13))
	return blk


## Grand chantier commun (Phare des Âges, Banque des Étoiles) : avancée et boutons pour y verser.
static func _project(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var pj := CrisisKinds.project(state)
	var c := Crisis.cur(state)
	var blk := Widgets.Block.new("⚒ %s" % String(pj.get("name", "Grand chantier")))
	blk.body.add_child(UiTheme.paragraph(String(pj.get("text", "")), 900.0, 14))
	var bar := ProgressBar.new()
	bar.max_value = 100
	bar.value = CrisisKinds.project_pct(state)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(600, 14)
	blk.body.add_child(bar)
	blk.body.add_child(_dim("%d sur %d versés (%d %%). Chaque lot compte pour votre part de gloire." % [int(c.get("fund", 0)), int(c.get("need", 0)), CrisisKinds.project_pct(state)], 13))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	for res in ["energy", "materials"]:
		var b := Button.new()
		var pack := int(pj.get("pack", 100))
		b.text = "Verser %d %s" % [pack, GameData.resource_label(res).to_lower()]
		b.focus_mode = Control.FOCUS_NONE
		var why := CrisisKinds.check_fund(state, player, res)
		b.disabled = why != ""
		b.tooltip_text = why
		var r := String(res)
		b.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.crisis_fund(player, r)))
		es.chronicle_buttons["crisis_fund:%s" % res] = b
		row.add_child(b)
	blk.body.add_child(row)
	return blk


## Crises sans flotte : étoiles éteintes (Nuit) ou empires touchés (Krach).
static func _fleetless(state: GameState, player: int) -> Control:
	var c := Crisis.cur(state)
	var blk := Widgets.Block.new("État de la galaxie")
	match String(c["kind"]):
		"nuit":
			blk.body.add_child(_dim("Étoiles éteintes : %d sur %d (la galaxie a perdu à %d %%). Prochain anneau dans %d jours." % [
					CrisisKinds.dark_count(state), state.galaxy.systems.size(), int(Crisis.kind_def("nuit")["night"]["defeat_pct"]), maxi(0, int(c.get("night_next", 0)) - state.tick)], 13))
			blk.body.add_child(_dim("Arches : %s." % ("construites, vos réfugiés rejoignent la capitale" if (c.get("arks", {}) as Dictionary).has(player) else "aucune"), 13))
		"krach":
			var names: Array[String] = []
			for k in (c.get("infected", {}) as Dictionary).keys():
				var e := state.get_empire(int(k))
				if e != null:
					names.append(e.short_name())
			names.sort()
			blk.body.add_child(_dim("Empires touchés : %s." % (", ".join(names) if not names.is_empty() else "aucun"), 13))
			var left := int(Crisis.kind_def("krach")["krach"]["limit_days"]) - (state.tick - int(c.get("arrived", state.tick)))
			blk.body.add_child(_dim("Sans relance, la Grande Dépression dans %d mois." % maxi(0, left / 30), 13))
			if CrisisKinds.infected(state, player):
				blk.body.add_child(_dim("Vous êtes touché : réserves d'énergie -3 % par mois, commerce divisé par deux, stabilité -10, faillites sur les mondes instables, pirates nés de la ruine.", 13))
	return blk


## Avancée vers la défaite commune, contribution et Front commun.
static func _progress(state: GameState, player: int) -> Control:
	var c := Crisis.cur(state)
	var blk := Widgets.Block.new("Le front")
	var need := Crisis._defeat_need(state)
	if bool(Crisis.kind_def(String(c["kind"])).get("fleetless", false)):
		need = 0
	var bar := ProgressBar.new()
	bar.max_value = 100
	bar.value = Crisis.menace_pct(state)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(600, 14)
	bar.tooltip_text = "Si la crise tient %d systèmes (la moitié des systèmes habités à son arrivée), la galaxie a perdu." % need
	if need > 0:
		blk.body.add_child(bar)
		blk.body.add_child(_dim("Systèmes tombés : %d sur %d avant la défaite commune.  ·  Tombés en tout : %d, libérés : %d." % [
				Crisis.held(state).size(), need, int(c.get("fallen", 0)), int(c.get("freed", 0))], 13))
	var pacts: Array[String] = []
	for e in state.empires:
		if not e.eliminated and Crisis.pacted(state, e.id):
			pacts.append(e.short_name())
	if not pacts.is_empty():
		blk.body.add_child(_dim("Ont pactisé avec elle : %s." % ", ".join(pacts), 13))
	var dl := Victory.deadline(state)
	if dl > 0 and dl != int(state.victory_rules.get("deadline", 0)):
		blk.body.add_child(_dim("La date limite de la partie est repoussée tant que la crise vit (au plus vingt ans).", 13))
	var sh := Crisis.shares(state)
	if sh.is_empty():
		blk.body.add_child(_dim("Personne ne l'a encore combattue.", 13))
	else:
		var parts: Array[String] = []
		for s: Array in sh:
			var e := state.get_empire(int(s[0]))
			if e != null:
				parts.append("%s %d %%" % [e.short_name(), int(s[1])])
		blk.body.add_child(_dim("Part de gloire : " + ", ".join(parts), 13))
	var fr: Array[String] = []
	for e in state.empires:
		if not e.eliminated and Crisis.in_front(state, e.id):
			fr.append(e.short_name())
	if fr.is_empty():
		blk.body.add_child(_dim("Front commun : personne pour l'instant.", 13))
	else:
		blk.body.add_child(_dim("Front commun (vision partagée, passage libre, +%d %% de dégâts contre elle) : %s." % [int(Crisis.data()["front"]["damage_pct"]), ", ".join(fr)], 13))
	if not Crisis.in_front(state, player) and (c.get("aloof", {}) as Dictionary).has(player):
		blk.body.add_child(_dim("Vous êtes resté à l'écart du Front.", 13))
	return blk


## Points faibles connus (stations de la crise, visibles de tous sur la carte, prop. 17).
static func _weak_points(es: EmpireScreens) -> Control:
	var state := es._state
	var blk := Widgets.Block.new("Points faibles")
	var sts := Crisis.stations(state)
	if sts.is_empty():
		blk.body.add_child(_dim("Aucun point faible en vue.", 13))
	for f in sts:
		var heart := Crisis.role_of(state, f.id) == Crisis.ROLE_HEART
		var what := "le cœur" if heart else "point faible"
		blk.body.add_child(_dim("%s %s (%s) à %s, puissance %d" % ["♦" if heart else "◆", f.fleet_name, what, state.galaxy.systems[f.system_id].system_name, Combat.fleet_power(f)], 13))
	return blk


static func _past(state: GameState, p: Dictionary) -> Control:
	var k := String(p["kind"])
	var blk := Widgets.Block.new("%s  ·  %s" % [Crisis.name_of(k), {"victoire": "vaincue", "defaite": "victorieuse", "fizzle": "dissipée", "depression": "Grande Dépression"}.get(String(p["result"]), "")])
	@warning_ignore("integer_division")
	var years := maxi(1, (int(p["tick"]) - int(p["since"])) / 360)
	var line := "De %s à %s (%d an%s). %d système%s tombé%s, %d libéré%s." % [GameCalendar.date_string(int(p["since"])), GameCalendar.date_string(int(p["tick"])),
			years, "s" if years > 1 else "", int(p.get("fallen", 0)), "s" if int(p.get("fallen", 0)) > 1 else "", "s" if int(p.get("fallen", 0)) > 1 else "",
			int(p.get("freed", 0)), "s" if int(p.get("freed", 0)) > 1 else ""]
	var by := int(p.get("by", -1))
	if by >= 0 and by < state.empires.size():
		line += " Coup final : %s." % state.empires[by].display_name()
	blk.body.add_child(_dim(line, 13))
	return blk


## Ce qui change l'onglet.
static func signature(es: EmpireScreens) -> String:
	var state := es._state
	if not Crisis.enabled(state):
		return ""
	var c := Crisis.cur(state)
	@warning_ignore("integer_division")
	return str(CrisisNemesis.nem(state)) + "%s|%s|%d|%d|%s|%s|%d|%d|%s|%s|%s|%s" % [String(c.get("stage", "")), str(c.get("step", 0)), Crisis.held(state).size(), Crisis.stations(state).size(),
			str(c.get("contrib", {})), str(c.get("front", {})), (state.crisis.get("past", []) as Array).size(), state.tick / 30,
			str(c.get("fund", 0)), str(c.get("pact", {})), str(c.get("infected", {})), str(Crisis.boons(state, es._player).size())]


## Devenir la crise (prop. 23) : la voie de l'Ambition démesurée, sa Menace, ses paliers, le grand œuvre.
static func _nemesis(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var nd := CrisisNemesis.data()
	var w := CrisisNemesis.who(state)
	var blk := Widgets.Block.new("♛ %s" % String(nd.get("name", "Ambition démesurée")))
	blk.body.add_child(UiTheme.paragraph(String(nd.get("text", "")), 900.0, 14))
	var nm := CrisisNemesis.nem(state)
	if w == player:
		var t := CrisisNemesis.tier(state)
		var next := CrisisNemesis.tier_def(t + 1)
		blk.body.add_child(_dim("Menace : %d%s. Palier : %s." % [int(nm["menace"]), " (prochain palier à %d)" % int(next["at"]) if not next.is_empty() else "",
				String(CrisisNemesis.tier_def(t).get("label", "aucun")) if t > 0 else "aucun"], 13))
		var lines: Array[String] = []
		for td: Dictionary in CrisisNemesis.tiers():
			lines.append("%d : %s (%s)%s" % [int(td["at"]), String(td["label"]), Relics.fx_text(td.get("fx", {})), ", point de non-retour" if bool(td.get("final", false)) else ""])
		blk.body.add_child(_dim("Paliers : " + " ; ".join(lines), 13))
		if CrisisNemesis.is_scourge(state, player):
			var od: Dictionary = nd.get("oeuvre", {})
			blk.body.add_child(UiTheme.paragraph("%s : %s" % [_upper_first(String(od.get("name", ""))), String(od.get("text", ""))], 900.0, 13))
			var bar := ProgressBar.new()
			bar.max_value = 100
			bar.value = CrisisNemesis.pct(state)
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(600, 14)
			blk.body.add_child(bar)
			blk.body.add_child(_dim("%d sur %d." % [int(nm["fund"]), int(nm["need"])], 13))
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			for res in ["energy", "materials"]:
				var b := Button.new()
				b.text = "Verser %d %s" % [int(od.get("pack", 200)), GameData.resource_label(res).to_lower()]
				b.focus_mode = Control.FOCUS_NONE
				var why := CrisisNemesis.check_oeuvre(state, player, res)
				b.disabled = why != ""
				b.tooltip_text = why
				var r := String(res)
				b.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.crisis_oeuvre(player, r)))
				es.chronicle_buttons["crisis_oeuvre:%s" % res] = b
				row.add_child(b)
			blk.body.add_child(row)
	elif w >= 0 and CrisisNemesis.tier(state) >= 2:
		var we := state.get_empire(w)
		var t2 := CrisisNemesis.tier(state)
		blk.body.add_child(_dim("%s : %s.%s" % [we.display_name(), String(CrisisNemesis.tier_def(t2).get("label", "")),
				" Son grand œuvre avance : %d %%. Vos flottes le frappent %d %% plus fort." % [CrisisNemesis.pct(state), int(nd.get("foes_damage_pct", 10))] if CrisisNemesis.is_scourge(state, w) else ""], 13))
	else:
		var b2 := Button.new()
		b2.text = "Prendre la voie de l'Ambition démesurée"
		b2.focus_mode = Control.FOCUS_NONE
		var why2 := CrisisNemesis.check_ambition(state, player)
		b2.disabled = why2 != ""
		b2.tooltip_text = why2 if why2 != "" else "Votre Menace montera avec vos conquêtes, vos guerres, vos atrocités et vos technologies interdites. Au dernier palier, toute la galaxie vous fera la guerre."
		b2.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.crisis_ambition(player)))
		es.chronicle_buttons["crisis_ambition"] = b2
		blk.body.add_child(b2)
	return blk


static func _upper_first(t: String) -> String:
	return t.substr(0, 1).to_upper() + t.substr(1) if t != "" else t


## Ligne grisée qui passe à la ligne (les blocs gardent la largeur de l'écran).
static func _dim(text: String, size := 13) -> Label:
	var l := UiTheme.paragraph(text, 900.0, size)
	l.theme_type_variation = &"Dim"
	return l
