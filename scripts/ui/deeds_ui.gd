class_name DeedsUi
extends RefCounted
## Onglets « Hauts faits » et « Annales » de l'écran Chroniques (props 22 et 24) :
## - Hauts faits : récompenses à choisir, Gloire et classement, titres, Trophées, âge d'or, puis le
##   catalogue en jeu par famille (à prendre, gagné par qui, votre avancée, les rivaux en quarts) ;
## - Annales : la frise des grands moments de l'empire (premiers actes, hauts faits, grands moments,
##   âges d'or), du plus récent au plus ancien, et le palmarès de la galaxie.
## Boutons enregistrés dans es.chronicle_buttons pour les tests : « deed:<entrée> ».

const SORT_LABELS := {"first": "Première", "record": "Record d'ère", "layer": "De couche", "infamous": "Infâme", "secret": "Secret"}
const ERA_NAMES := ["I", "II", "III", "IV", "V"]


static func build(es: EmpireScreens, col: VBoxContainer) -> void:
	var state := es._state
	var player := es._player
	if not Deeds.enabled(state):
		col.add_child(UiTheme.dim("Pas de hauts faits dans cette partie (réglage de la Nouvelle partie).", 15))
		return
	_inbox(es, col)
	_glory(es, col)
	var fams: Array = (Deeds.data()["families"] as Dictionary).keys()
	for fam in fams:
		var ids: Array[String] = []
		for id in Deeds.pool(state):
			if Deeds.family(String(id)) == String(fam):
				ids.append(String(id))
		if ids.is_empty():
			continue
		var blk := Widgets.Block.new(Deeds.family_label(String(fam)) + ("  (affinité : Gloire ×2)" if DeedsBridges.affinity(state, player, String(fam)) else ""))
		col.add_child(blk)
		for id in ids:
			blk.body.add_child(_deed_row(es, id))


static func _inbox(es: EmpireScreens, col: VBoxContainer) -> void:
	var state := es._state
	var player := es._player
	var box := Deeds.inbox(state, player)
	if box.is_empty():
		return
	var blk := Widgets.Block.new("Récompenses à choisir")
	col.add_child(blk)
	for item: Dictionary in box:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var b := Button.new()
		b.theme_type_variation = &"PrimaryButton"
		b.focus_mode = Control.FOCUS_NONE
		b.text = "Choisir"
		var iid := int(item["id"])
		b.pressed.connect(func() -> void: es.deed_requested.emit(iid))
		es.chronicle_buttons["deed:%d" % iid] = b
		row.add_child(b)
		var t := UiTheme.title(Deeds.label(String(item["deed"])), 18)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(t)
		var left := maxi(0, int(item["until"]) - state.tick)
		row.add_child(UiTheme.dim("encore %d jour%s" % [left, "s" if left > 1 else ""], 13))
		blk.body.add_child(row)


static func _glory(es: EmpireScreens, col: VBoxContainer) -> void:
	var state := es._state
	var player := es._player
	var blk := Widgets.Block.new("Gloire")
	col.add_child(blk)
	blk.body.add_child(UiTheme.paragraph("La Gloire ne se perd jamais. Une Première rapporte 100, un record d'ère de 50 (ère I) à 150 (ère V), un haut fait de couche 100 ; doublée dans les familles chères à votre peuple, et +25 % pour les empires de la moitié basse du classement. Les grands moments (merveille, crise vaincue, gardien, quête galactique, ancienne vaincue, paix imposée) en donnent aussi.", 900.0, 14))
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 24)
	blk.body.add_child(g)
	var me := state.get_empire(player)
	var rank := 1
	for eid in DeedsBridges.ranking(state):
		if eid != player and not me.contacts.has(eid):
			continue
		var e := state.get_empire(eid)
		var name := UiTheme.title("%d. %s" % [rank, e.short_name()], 16, e.color() if eid != player else UiTheme.ACCENT)
		g.add_child(name)
		g.add_child(UiTheme.dim("%d Gloire" % Deeds.glory(state, eid), 14))
		g.add_child(UiTheme.dim("%d haut%s fait%s" % [Deeds.held_by(state, eid).size(), "s" if Deeds.held_by(state, eid).size() > 1 else "", "s" if Deeds.held_by(state, eid).size() > 1 else ""], 14))
		var tags: Array[String] = []
		for t in Deeds.titles_of(state, eid):
			tags.append(Deeds.title_label(t))
		if DeedsBridges.in_golden(state, eid):
			tags.append("Âge d'or")
		if DeedsBridges.infamous(state, eid):
			tags.append("Infâme")
		g.add_child(UiTheme.dim(", ".join(tags), 14))
		rank += 1
	var lines: Array[String] = []
	var th: Array[String] = []
	var held := Deeds.trophies_held(state)
	for tid in held:
		var c: Colony = state.colonies.get(int(held[tid]))
		if c != null and c.owner == player:
			th.append(String(Deeds.trophy_def(String(tid))["label"]))
	lines.append("Vos Trophées : %s." % (", ".join(th) if not th.is_empty() else "aucun pour l'instant"))
	lines.append("Trophées encore libres dans la galaxie : %d." % Deeds.free_trophies(state).size())
	if DeedsBridges.golden_on(state):
		if DeedsBridges.in_golden(state, player):
			lines.append("Âge d'or en cours jusqu'au %s (+%d stabilité, +%d %% Savoir et matériaux)." % [
					GameCalendar.date_string(int(DeedsBridges.golden_of(state, player)["until"])), int(Deeds.rules()["golden"]["stability"]), int(Deeds.rules()["golden"]["pct"])])
		else:
			lines.append("Prochain âge d'or : %d de Gloire gagnés sur la décennie en cours (vous en êtes à %d)." % [DeedsBridges.golden_threshold(state, player), DeedsBridges.golden_gained(state, player)])
	if Victory.enabled(state, "annales"):
		lines.append("Les Annales : détenir %d hauts faits et être premier en Gloire pendant deux ans." % DeedsBridges.annales_needed(state))
	for l in lines:
		blk.body.add_child(UiTheme.dim(l, 13))


static func _deed_row(es: EmpireScreens, id: String) -> Control:
	var state := es._state
	var player := es._player
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 1)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	row.add_child(head)
	var shown := Deeds.revealed(state, player, id)
	var t := UiTheme.title(Deeds.label(id) if shown else "???", 16, Deeds.family_color(Deeds.family(id)))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var tag := String(SORT_LABELS.get(Deeds.sort_of(id), ""))
	if Deeds.sort_of(id) == "record":
		tag += " %s" % ERA_NAMES[clampi(int(Deeds.def(id).get("era", 1)) - 1, 0, 4)]
	head.add_child(UiTheme.dim("%s  ·  %d Gloire" % [tag, Deeds.glory_for(state, player, id)], 13))
	if not shown:
		row.add_child(UiTheme.dim("Haut fait secret : on ne le découvre qu'en l'accomplissant.", 13))
		return row
	var status := ""
	var col := UiTheme.TEXT_DIM
	var w := Deeds.winners(state, id)
	if not w.is_empty():
		var names: Array[String] = []
		for eid in w:
			names.append(state.get_empire(int(eid)).short_name())
		status = "Accompli par %s le %s." % [" et ".join(names), GameCalendar.date_string(Deeds.won_day(state, id))]
		if w.has(player):
			col = UiTheme.GOOD
		elif (state.deeds.get("late", {}) as Dictionary).get(id, {}).has(str(player)):
			status += " Vous l'avez accompli à votre tour."
	elif not Deeds.is_open(state, player, id):
		status = "S'ouvre à l'ère %s." % ERA_NAMES[clampi((int(Deeds.def(id).get("era", 3)) if Deeds.sort_of(id) == "record" else 3) - 1, 0, 4)]
	else:
		var p := Deeds.progress(state, player, id)
		status = "À prendre. Votre avancée : %d / %d (%d %%)." % [mini(int(p[0]), int(p[1])), int(p[1]), Deeds.pct(state, player, id)]
		var rivals: Array[String] = []
		for o in state.empires:
			if o.id == player or o.eliminated or o.is_npc() or not state.get_empire(player).contacts.has(o.id):
				continue
			var q := Deeds.quarter(state, o.id, id)
			if q > 0:
				rivals.append("%s %d/4" % [o.short_name(), q])
		if not rivals.is_empty():
			status += " Rivaux : %s." % ", ".join(rivals)
			col = UiTheme.WARN
	var text := String(Deeds.def(id).get("text", ""))
	var tl := String(Deeds.def(id).get("title", ""))
	if tl != "":
		text += " Titre : %s." % Deeds.title_label(tl)
	row.add_child(UiTheme.dim(text, 13))
	var s := UiTheme.dim(status, 13)
	s.add_theme_color_override("font_color", col)
	row.add_child(s)
	return row


# --- Annales (prop. 22) ---------------------------------------------------------------------------

static func build_annals(es: EmpireScreens, col: VBoxContainer) -> void:
	var state := es._state
	var player := es._player
	if not Deeds.enabled(state):
		col.add_child(UiTheme.dim("Pas d'Annales dans cette partie (hauts faits désactivés).", 15))
		return
	var blk := Widgets.Block.new("Les Annales de %s" % state.get_empire(player).short_name())
	col.add_child(blk)
	var a := Deeds.annals_of(state, player)
	if a.is_empty():
		blk.body.add_child(UiTheme.dim("Rien encore. L'histoire commence par une première colonie, une première bataille, un premier traité.", 14))
	var shown := 0
	for i in range(a.size() - 1, -1, -1):
		var x: Dictionary = a[i]
		blk.body.add_child(_annal_row(state, x))
		shown += 1
		if shown >= 80:
			break
	var gal := Widgets.Block.new("Palmarès de la galaxie")
	col.add_child(gal)
	var any := false
	for id in Deeds.pool(state):
		var w := Deeds.winners(state, String(id))
		if w.is_empty() or Deeds.sort_of(String(id)) == "secret" and not w.has(player):
			continue
		any = true
		var names: Array[String] = []
		for eid in w:
			names.append(state.get_empire(int(eid)).short_name())
		gal.body.add_child(UiTheme.dim("%s  ·  « %s »  ·  %s" % [GameCalendar.date_string(Deeds.won_day(state, String(id))), Deeds.label(String(id)), " et ".join(names)], 13))
	if not any:
		gal.body.add_child(UiTheme.dim("Aucun haut fait accompli pour l'instant. Tout reste à prendre.", 13))


static func _annal_row(state: GameState, x: Dictionary) -> Control:
	var id := String(x["id"])
	var txt := ""
	match String(x["k"]):
		"first":
			txt = String(DeedsBridges.FIRSTS.get(id, id))
		"deed":
			txt = "Haut fait : « %s »" % Deeds.label(id)
		"late":
			txt = "À son tour : « %s »" % Deeds.label(id)
		"moment":
			txt = String({"wonder": "Merveille achevée", "crisis": "Crise vaincue", "guardians": "Gardien abattu", "quests": "Quête galactique remportée",
					"ancient_world": "Monde ancien pris", "imposed_peace": "Paix imposée"}.get(id, id))
		"golden":
			txt = "Début d'un âge d'or"
	if int(x["g"]) > 0:
		txt += "  (+%d Gloire)" % int(x["g"])
	return UiTheme.dim("%s  ·  %s" % [GameCalendar.date_string(int(x["d"])), txt], 13)


static func signature(es: EmpireScreens) -> String:
	var state := es._state
	if not Deeds.enabled(state):
		return ""
	return "%d|%d|%s|%d" % [Deeds.glory(state, es._player), (state.deeds["annals"] as Array).size(), str(state.deeds.get("won", {}).keys().size()),
			Deeds.inbox(state, es._player).size()]
