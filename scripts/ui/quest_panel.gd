class_name QuestPanel
extends RefCounted
## Onglet Quêtes de l'écran Chroniques (voir Quests) : le retournement galactique en cours, puis les
## quêtes de l'empire, chacune avec son chapitre, son texte et ses deux branches (objectif,
## avancement, récompense, bouton « Payer »), enfin les quêtes achevées ou abandonnées.
## Boutons enregistrés dans es.chronicle_buttons pour les tests : « quest_pay:<id>:<branche> »,
## « contribute », « camp:<i> », « parley:<système> ».

const BRANCH_WIDTH := 430.0


static func build(es: EmpireScreens, col: VBoxContainer) -> void:
	var state := es._state
	var player := es._player
	var cur := Quests.current(state)
	if not cur.is_empty():
		col.add_child(_galactic_block(es, cur))
	var mine := Quests.of(state, player)
	var active: Array[int] = []
	var old: Array[int] = []
	for id in mine:
		if String(state.quests[id]["status"]) == "active":
			active.append(id)
		else:
			old.append(id)
	if active.is_empty():
		var empty := Widgets.Block.new("Quêtes en cours")
		empty.body.add_child(UiTheme.dim("Aucune quête pour l'instant. La quête de votre peuple arrive à la fin de la première année ; les autres naissent des curiosités, des événements et de la vie de l'empire.", 14))
		col.add_child(empty)
	for id in active:
		col.add_child(_quest_block(es, state.quests[id]))
	var log: Array = state.galactic.get("log", [])
	if not old.is_empty() or not log.is_empty():
		var done := Widgets.Block.new("Quêtes passées")
		for id in old:
			var q: Dictionary = state.quests[id]
			var st := "achevée" if String(q["status"]) == "done" else "abandonnée"
			var labels := PackedStringArray()
			var chs := Quests.chapters(q)
			for i in (q["path"] as Array).size():
				labels.append(String(chs[i]["branches"][int(q["path"][i])]["label"]))
			done.body.add_child(UiTheme.paragraph("%s  ·  %s, %s%s" % [GameCalendar.date_string(int(q["end"])), Quests.title(state, q), st,
					(" (%s)" % ", ".join(labels).to_lower()) if not labels.is_empty() else ""], 900.0, 14))
		for l: Dictionary in log:
			var w := state.get_empire(int(l["winner"]))
			done.body.add_child(UiTheme.paragraph("%s  ·  Retournement « %s »%s" % [GameCalendar.date_string(int(l["tick"])), String(l["title"]),
					(", remporté par %s" % w.short_name()) if w != null else ", sans vainqueur"], 900.0, 14))
		col.add_child(done)


static func _quest_block(es: EmpireScreens, q: Dictionary) -> Control:
	var state := es._state
	var player := es._player
	var credo := Quests.is_credo(q)
	var blk := Widgets.Block.new(Quests.title(state, q))
	var chs := Quests.chapters(q)
	var ch := Quests.chapter(q)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	var tag := UiTheme.section(("Quête de peuple · %s" % Events._layer_label("credo", Events.layer_value(state, player, "credo"))) if credo else "Quête")
	tag.add_theme_color_override("font_color", UiTheme.GOLD if credo else UiTheme.ACCENT)
	head.add_child(tag)
	var chl := UiTheme.title("Chapitre %d / %d : %s" % [int(q["ch"]) + 1, chs.size(), String(ch["title"])], 18)
	chl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(chl)
	if int(q["until"]) > 0:
		head.add_child(UiTheme.dim("encore %d jours" % maxi(0, int(q["until"]) - state.tick), 13))
	blk.body.add_child(head)
	if int(q["wait"]) > state.tick:
		blk.body.add_child(UiTheme.dim("Le récit reprend dans %d jours. Le prochain chapitre s'ouvrira de lui-même." % (int(q["wait"]) - state.tick), 14))
		return blk
	blk.body.add_child(UiTheme.paragraph(Quests.chapter_text(state, q), 900.0, 15))
	if credo and Quests.voice(state, player) != "":
		var v := UiTheme.dim("— " + Quests.voice(state, player), 13)
		blk.body.add_child(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	blk.body.add_child(row)
	var brs: Array = ch["branches"]
	for b in brs.size():
		row.add_child(_branch_card(es, q, b))
	var sid := int(q["subj"]["system"])
	if sid >= 0 and not state.galaxy.systems[sid].planet_ids.is_empty():
		var show := Button.new()
		show.flat = true
		show.focus_mode = Control.FOCUS_NONE
		show.text = "Montrer %s" % state.galaxy.systems[sid].system_name
		var first := int(state.galaxy.systems[sid].planet_ids[0])
		show.pressed.connect(func() -> void: es.planet_requested.emit(first))
		blk.body.add_child(show)
	return blk


static func _branch_card(es: EmpireScreens, q: Dictionary, b: int) -> Control:
	var state := es._state
	var player := es._player
	var br: Dictionary = Quests.chapter(q)["branches"][b]
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(BRANCH_WIDTH, 0)
	var st := UiTheme.box(Color(0.04, 0.06, 0.09, 0.85), UiTheme.LINE, 10, 0)
	st.border_width_left = 2
	st.border_color = Color(UiTheme.ACCENT, 0.5)
	card.add_theme_stylebox_override("panel", st)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	box.add_child(UiTheme.title(String(br["label"]), 16))
	box.add_child(UiTheme.paragraph(Quests.goal_text(state, q, b), BRANCH_WIDTH - 24.0, 14))
	var p := Quests.progress(state, q, b)
	if not p.is_empty():
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = maxi(1, int(p[1]))
		bar.value = int(p[0])
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(200, 10)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := StyleBoxFlat.new()
		fill.bg_color = UiTheme.ACCENT
		bar.add_theme_stylebox_override("fill", fill)
		line.add_child(bar)
		line.add_child(UiTheme.dim("%d / %d" % [int(p[0]), int(p[1])], 13))
		box.add_child(line)
	var lines := Quests.reward_lines(state, q, b)
	if not lines.is_empty():
		var rw := UiTheme.paragraph("Récompense : " + ", ".join(lines), BRANCH_WIDTH - 24.0, 13)
		rw.add_theme_color_override("font_color", UiTheme.GOLD)
		box.add_child(rw)
	if String(br["goal"]["k"]) == "pay":
		var pay := Button.new()
		pay.theme_type_variation = &"PrimaryButton"
		pay.focus_mode = Control.FOCUS_NONE
		pay.text = "Payer"
		var why := Quests.check_pay(state, player, int(q["id"]), b)
		pay.disabled = why != ""
		pay.tooltip_text = why
		var qid := int(q["id"])
		pay.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.quest_pay(player, qid, b)))
		es.chronicle_buttons["quest_pay:%d:%d" % [qid, b]] = pay
		box.add_child(pay)
	return card


## Le retournement galactique en cours : texte, état propre à chacun, classement et ordres.
static func _galactic_block(es: EmpireScreens, cur: Dictionary) -> Control:
	var state := es._state
	var player := es._player
	var id := String(cur["id"])
	var d := Quests.gdef(id)
	var blk := Widgets.Block.new("Retournement galactique : %s" % String(d["title"]))
	blk.body.add_child(UiTheme.paragraph(String(d["text"]), 900.0, 14))
	match id:
		"passage":
			var sid := Quests.passage_system(cur)
			blk.body.add_child(UiTheme.title("L'artéfact est à %s (étape %d / %d), il repart dans %d jours." % [state.galaxy.systems[sid].system_name,
					int(cur["step"]) + 1, (cur["path"] as Array).size(), maxi(0, int(cur["next_step"]) - state.tick)], 16))
			_show_button(es, blk.body, sid)
			_standings(es, blk, cur["pts"], "points d'étude")
		"fleau":
			blk.body.add_child(_bar(int(cur["pool"]), int(cur["target"]), "Remède financé", Color(0.55, 0.85, 0.6)))
			blk.body.add_child(UiTheme.dim("La Rouille s'éteindra d'elle-même dans %d jours, sans récompense." % maxi(0, int(cur["end"]) - state.tick), 13))
			var give := Button.new()
			give.theme_type_variation = &"PrimaryButton"
			give.focus_mode = Control.FOCUS_NONE
			give.text = "Financer le remède (%s)" % GameData.format_amounts(Quests.contribute_cost(state, player))
			var why := Quests.check_contribute(state, player)
			give.disabled = why != ""
			give.tooltip_text = why
			give.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.quest_contribute(player)))
			es.chronicle_buttons["contribute"] = give
			blk.body.add_child(give)
			_standings(es, blk, cur["gifts"], "dons")
		"conclave":
			_conclave(es, blk, cur)
		"tombeaux":
			_tombs(es, blk, cur)
	return blk


static func _conclave(es: EmpireScreens, blk: Widgets.Block, cur: Dictionary) -> void:
	var state := es._state
	var player := es._player
	var camps: Array = Quests.gdef("conclave")["camps"]
	var mine := Quests.camp_of(state, player)
	if String(cur["phase"]) == "choose":
		blk.body.add_child(UiTheme.title("Choix des camps : encore %d jours. Sans choix, le sort décidera." % maxi(0, int(cur["until"]) - state.tick), 16))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		for i in camps.size():
			var b := Button.new()
			b.theme_type_variation = &"PrimaryButton"
			b.focus_mode = Control.FOCUS_NONE
			b.text = ("%s (votre camp)" if mine == i else "Rejoindre les %s") % String(camps[i]["label"])
			var why := Quests.check_camp(state, player, i)
			b.disabled = why != ""
			b.tooltip_text = why
			var ci := i
			b.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.quest_camp(player, ci)))
			es.chronicle_buttons["camp:%d" % i] = b
			row.add_child(b)
		blk.body.add_child(row)
	else:
		var score: Array = cur["score"]
		var target := int(Quests.gdef("conclave")["target"])
		for i in camps.size():
			blk.body.add_child(_bar(int(score[i]), target, String(camps[i]["label"]) + (" (votre camp)" if mine == i else ""), Color(String(camps[i]["color"]))))
		blk.body.add_child(UiTheme.dim("Fin au plus tard dans %d jours. Les vaincus ne recevront plus d'offre de héros pendant cinq ans." % maxi(0, int(cur["until"]) - state.tick), 13))
		for sid in cur["phares"]:
			var held := Quests.phare_holders(state, cur, int(sid))
			var who := "personne"
			if held.size() == 1:
				who = "les " + Quests.camp_label(int(held[0]))
			elif held.size() > 1:
				who = "disputé"
			var o := state.get_empire(state.system_owner(int(sid)))
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 12)
			var l := UiTheme.paragraph("Phare de %s%s : tenu par %s" % [state.galaxy.systems[int(sid)].system_name,
					(" (territoire de %s)" % o.short_name()) if o != null else "", who], 560.0, 14)
			l.custom_minimum_size = Vector2(560, 0)
			line.add_child(l)
			_show_button(es, line, int(sid))
			blk.body.add_child(line)
	var members := PackedStringArray()
	var cd: Dictionary = cur["camps"]
	var ks := cd.keys()
	ks.sort()
	for eid in ks:
		var e := state.get_empire(int(eid))
		if e != null:
			members.append("%s : %s" % [e.short_name(), Quests.camp_label(int(cd[eid]))])
	if not members.is_empty():
		var ml := UiTheme.paragraph(", ".join(members), 900.0, 13)
		ml.add_theme_color_override("font_color", Color(UiTheme.TEXT, 0.6))
		blk.body.add_child(ml)


static func _tombs(es: EmpireScreens, blk: Widgets.Block, cur: Dictionary) -> void:
	var state := es._state
	var player := es._player
	var synth := Events.layer_value(state, player, "archetype") == "synthetique"
	blk.body.add_child(UiTheme.dim("Les gardiens se rendormiront d'eux-mêmes dans %d jours.%s" % [maxi(0, int(cur["end"]) - state.tick),
			"  Vos voisins tombeaux vous coûtent 3 de stabilité." if (cur.get("near", []) as Array).has(player) else ""], 13))
	for t: Dictionary in cur["tombs"]:
		var sid := int(t["sid"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var by := state.get_empire(int(t["by"]))
		var status := "éveillé" if int(t["alive"]) == 1 else ("rendormi par %s" % by.short_name() if by != null else "rendormi")
		var l := UiTheme.paragraph("Tombeau de %s : %s" % [state.galaxy.systems[sid].system_name, status], 520.0, 14)
		row.add_child(l)
		if synth and int(t["alive"]) == 1:
			var pb := Button.new()
			pb.focus_mode = Control.FOCUS_NONE
			pb.text = "Parlementer (%s)" % GameData.format_amounts(Quests.gdef("tombeaux")["parley_cost"])
			var why := Quests.check_parley(state, player, sid)
			pb.disabled = why != ""
			pb.tooltip_text = why if why != "" else "De machine à machine : ils se rendorment et partagent un peu de Savoir."
			pb.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.tomb_parley(player, sid)))
			es.chronicle_buttons["parley:%d" % sid] = pb
			row.add_child(pb)
		blk.body.add_child(row)
	_standings(es, blk, cur["pts"], "tombeaux rendormis")


static func _show_button(es: EmpireScreens, parent: Control, sid: int) -> void:
	var state := es._state
	if sid < 0 or state.galaxy.systems[sid].planet_ids.is_empty():
		return
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = "Montrer %s" % state.galaxy.systems[sid].system_name
	var first := int(state.galaxy.systems[sid].planet_ids[0])
	b.pressed.connect(func() -> void: es.planet_requested.emit(first))
	parent.add_child(b)


static func _bar(v: int, mx: int, label: String, color: Color) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	var l := UiTheme.dim(label, 14)
	l.custom_minimum_size = Vector2(260, 0)
	line.add_child(l)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = maxi(1, mx)
	bar.value = mini(v, mx)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(360, 12)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	line.add_child(bar)
	line.add_child(UiTheme.dim("%d / %d" % [v, mx], 13))
	return line


static func _standings(es: EmpireScreens, blk: Widgets.Block, pts: Dictionary, unit: String) -> void:
	var state := es._state
	var rk := Quests.ranking(pts)
	if rk.is_empty():
		blk.body.add_child(UiTheme.dim("Personne n'a encore marqué de point.", 13))
		return
	var parts := PackedStringArray()
	for x in rk:
		var e := state.get_empire(int(x[1]))
		if e != null:
			parts.append("%s %d" % [e.short_name(), int(x[0])])
	blk.body.add_child(UiTheme.paragraph("Classement (%s) : %s" % [unit, ", ".join(parts)], 900.0, 14))


## Ce qui change l'onglet : quêtes (chapitre, avancement), retournement en cours.
static func signature(es: EmpireScreens) -> String:
	var state := es._state
	var player := es._player
	var s := ""
	for id in Quests.of(state, player):
		var q: Dictionary = state.quests[id]
		s += "%d:%s:%d:%d:%s|" % [id, String(q["status"]), int(q["ch"]), int(q["wait"]), str(q["cnt"])]
		if String(q["status"]) == "active" and int(q["wait"]) <= state.tick:
			for b in (Quests.chapter(q)["branches"] as Array).size():
				s += str(Quests.progress(state, q, b))
	var cur := Quests.current(state)
	if not cur.is_empty():
		var alive := []
		for t: Dictionary in cur.get("tombs", []):
			alive.append(int(t["alive"]))
		@warning_ignore("integer_division")
		var sc := str(cur.get("score", [])) if String(cur.get("phase", "")) == "choose" else "%d" % ((int(cur.get("score", [0, 0])[0]) + int(cur.get("score", [0, 0])[1])) / 10)
		s += "%s:%s:%s:%s:%s:%s:%s" % [String(cur["id"]), str(cur.get("step", 0)), str(cur.get("pool", 0)), String(cur.get("phase", "")),
				str(cur.get("camps", {})), str(alive), sc]
	s += str((state.galactic.get("log", []) as Array).size())
	var e := state.get_empire(player)
	@warning_ignore("integer_division")
	s += "|%d|%d" % [int(e.resources.get("energy", 0)) / 50, int(e.resources.get("influence", 0)) / 20]
	return s
