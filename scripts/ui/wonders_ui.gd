class_name WondersUi
extends RefCounted
## Interface des merveilles (voir Wonders) : l'écran d'empire « Merveilles » (vos grands chantiers et
## leur course, celles à lancer par famille, celles achevées dans la galaxie) et les actions de la fiche
## de système (lancer ici, verser depuis cette colonie, presser, abandonner). Lit l'état, n'émet que des
## ordres « won_act ».

const W := 760.0


## Actions de la fiche de système pour une colonie à vous.
static func system_actions(state: GameState, player: int, p: Planet, emit: Callable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not Wonders.enabled(state):
		return out
	var c: Colony = state.colonies.get(p.id)
	if c == null or c.owner != player or not c.is_established():
		return out
	for wid in WondersCatalog.ruins_at(state, p.id):
		out.append(_act(state, SimCommands.won_act(player, "restore", wid), "Restaurer : %s" % Wonders.label(wid),
				"avance %s (total %s)  »  %s" % [GameData.format_amounts(Research.scaled_amounts(WondersCatalog.restore_cost(state, player, wid), Wonders.r_int("advance_pct") - 100)),
						GameData.format_amounts(WondersCatalog.restore_cost(state, player, wid)), Wonders.effect_text(wid)],
				"Une merveille d'un âge oublié gît ici. La relever coûte %d %% du prix et de la durée, hors de la limite des grands chantiers." % Wonders.r_int("restore_pct"), emit))
	for pair in Wonders.builds_by(state, player):
		var wid := String(pair[0])
		var entry: Dictionary = pair[1]
		if int(entry["p"]) == p.id:
			out.append(_act(state, SimCommands.won_act(player, "rush", wid), "Presser : %s" % Wonders.label(wid),
					"%d influence  »  achève le chantier (%d %%)" % [Wonders.rush_cost(state, player, wid), Wonders.pct(entry)],
					"Le dernier quart se presse contre de l'influence : 3 par point restant et par ère.", emit))
			out.append(_act(state, SimCommands.won_act(player, "cancel", wid), "Abandonner : %s" % Wonders.label(wid),
					"la moitié revient, ou toute la mise se reporte 90 jours",
					"La mise se reporte entière sur une merveille d'ère égale ou plus haute lancée dans les 90 jours ; sinon la moitié revient.", emit))
		else:
			var cmd := SimCommands.won_act(player, "contribute", wid, p.id)
			var why := SimCommands.validate(state, cmd)
			if not why.begins_with("trop loin"):
				out.append(_act(state, cmd, "Verser à %s" % Wonders.label(wid),
						"%s  »  +%d %% d'avancement" % [GameData.format_amounts(Wonders.contribute_cost(state, player, wid)), Wonders.r_int("contrib_pct")],
						"Une colonie à %d sauts ou moins verse une fois par mois une part du coût en matériaux : le chantier avance d'autant." % Wonders.r_int("contrib_jumps"), emit))
	for wid in Wonders.all_ids():
		if not Wonders.visible_for(state, player, wid) or not Wonders.unlocked(state, player, wid):
			continue
		if not Wonders.build_of(state, player, wid).is_empty() or Wonders.def(wid).has("collective"):
			continue
		if Wonders.galaxy_unique(wid) and Wonders.built_at(state, wid) >= 0:
			continue
		var cmd := SimCommands.won_act(player, "start", wid, p.id)
		var why := SimCommands.validate(state, cmd)
		if why.begins_with("il faut un") or why.begins_with("il faut dans") or why.begins_with("seulement") or why.begins_with("impossible"):
			continue  # mauvais site : on ne la propose pas ici
		out.append(_act(state, cmd, "Merveille : %s" % Wonders.label(wid),
				"avance %s (total %s), %d j  »  %s" % [GameData.format_amounts(Wonders.advance_cost(state, player, wid)),
						GameData.format_amounts(Wonders.total_cost(state, player, wid)), int(Wonders.def(wid).get("days", 360)), Wonders.family_label(Wonders.family(wid))],
				Wonders.fiche_text(wid), emit))
	return out


static func _act(state: GameState, cmd: Dictionary, text: String, detail: String, tip: String, emit: Callable) -> Dictionary:
	var why := SimCommands.validate(state, cmd)
	return {
		"text": text,
		"detail": detail,
		"reason": why,
		"tooltip": ("%s\n\n%s" % [why, tip]) if why != "" else tip,
		"action": func() -> void: emit.call(cmd),
	}


static func signature(es: EmpireScreens) -> String:
	var state := es._state
	var parts := PackedStringArray([str(state.tick / 30), str(Wonders.held(state).size())])
	for pair in Wonders.builds_by(state, es._player):
		parts.append("%s:%d" % [pair[0], Wonders.pct(pair[1])])
	return "|".join(parts)


static func build(es: EmpireScreens) -> void:
	var state := es._state
	var player := es._player
	es._wonders_sig = signature(es)
	es.wonder_cards.clear()
	es._side_header("screen_wonders", "Merveilles", Color(0.9, 0.78, 0.45), "faction")
	MegasUi.tabs(es, "wonders")
	if not Wonders.enabled(state):
		es._side_box.add_child(UiTheme.paragraph("Dans cette partie, les merveilles ne sont pas en jeu (Nouvelle partie : Merveilles).", EmpireScreens.SIDE_WIDTH - 24.0, 13))
		return
	var g := es._grid()
	es._side_box.add_child(g)
	es._key_value(g, "Grands chantiers", "%d / %d" % [Wonders.active_count(state, player), Wonders.max_builds(state, player)])
	es._key_value(g, "Merveilles tenues", str(Wonders.owned(state, player).size()))
	var carry: Dictionary = state.wonders.get("carry", {}).get(str(player), {})
	if not carry.is_empty() and state.tick <= int(carry["until"]):
		es._key_value(g, "Mise reportée", "%s (ère %d+, jusqu'au %s)" % [GameData.format_amounts(carry["amt"]), int(carry["era"]), GameCalendar.date_string(int(carry["until"]))])
	var deed := WondersBridges.builder_deed(state)
	if deed >= 0:
		es._key_value(g, "Bâtisseur de merveilles", state.get_empire(deed).short_name())
	if not state.wonders.get("contest", {}).is_empty():
		es._key_value(g, "Concours amphictyonique", "votre score %d, fin le %s" % [WondersBridges.contest_score(state, player), GameCalendar.date_string(int(state.wonders["contest"]["end"]))])
	if int(state.wonders.get("medals", {}).get(str(player), 0)) > 0:
		es._key_value(g, "Médailles des concours", str(int(state.wonders["medals"][str(player)])))
	if WondersCatalog.fx(state, player, "tribunal") > 0:
		var trow := HBoxContainer.new()
		es._side_box.add_child(trow)
		_button(es, trow, "Saisir le Tribunal (séance repoussée d'un an)", SimCommands.won_act(player, "tribunal"))
	es._side_box.add_child(HSeparator.new())
	es._side_box.add_child(UiTheme.paragraph("Une merveille est une course : plusieurs empires peuvent la bâtir en même temps, le premier qui l'achève l'emporte. Le lancement coûte une avance de %d %%, le reste se paie chaque mois ; le chantier n'occupe pas la file de la colonie. Les colonies à %d sauts ou moins peuvent verser une fois par mois, et le dernier quart se presse à l'influence. Le perdant garde toute sa mise %d jours pour une merveille d'ère égale ou plus haute ; sinon la moitié revient. Des rivaux, vous ne voyez que le quart atteint, et seulement si leur chantier est en vue ou sous votre réseau d'espions." % [
			Wonders.r_int("advance_pct"), Wonders.r_int("contrib_jumps"), Wonders.r_int("carry_days")], EmpireScreens.SIDE_WIDTH - 24.0, 12))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	es._content.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 18)
	scroll.add_child(col)

	var seen := Fleets.visible_systems(state, player)
	var mine := Wonders.builds_by(state, player)
	var bb := Widgets.Block.new("Vos grands chantiers")
	col.add_child(bb)
	if mine.is_empty():
		bb.body.add_child(UiTheme.paragraph("Aucun chantier. Lancez une merveille depuis la fiche d'une de vos colonies (ou ci-dessous).", W, 13))
	for pair in mine:
		var wid := String(pair[0])
		var entry: Dictionary = pair[1]
		var p := state.galaxy.get_planet(int(entry["p"]))
		var line := "%s sur %s : %d pts/jour, mensualité %s." % [Wonders.label(wid), p.display_name(state.galaxy),
				Wonders.speed(state, player, wid, p.id), GameData.format_amounts(Wonders.installment(state, player, wid, entry))]
		if not bool(entry.get("ok", 1)):
			line += " Mensualité impayée : le chantier est à l'arrêt."
		bb.body.add_child(UiTheme.paragraph(line, W, 13))
		bb.body.add_child(_race_bar("Vous", Wonders.pct(entry), state.get_empire(player).color(), false))
		for r in Wonders.rivals_known(state, player, wid, seen):
			var exact := WondersBridges.auscultated(state, player, int(r[0]))
			var rp := Wonders.pct(Wonders.build_of(state, int(r[0]), wid)) if exact else int(r[1]) * Wonders.r_int("quarter")
			bb.body.add_child(_race_bar(state.get_empire(int(r[0])).short_name(), rp, state.get_empire(int(r[0])).color(), not exact))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		bb.body.add_child(row)
		for a in [["Presser", SimCommands.won_act(player, "rush", wid)], ["Abandonner", SimCommands.won_act(player, "cancel", wid)]]:
			_button(es, row, String(a[0]), a[1])
		var best := _best_donor(state, player, wid)
		if best >= 0:
			_button(es, row, "Verser depuis %s" % state.galaxy.get_planet(best).display_name(state.galaxy), SimCommands.won_act(player, "contribute", wid, best))

	var shared := Widgets.Block.new("Œuvres communes")
	var any_shared := false
	var bmap: Dictionary = state.wonders.get("build", {})
	var bkeys := bmap.keys()
	bkeys.sort()
	for wid in bkeys:
		if WondersBridges.collective_kind(String(wid)) == "":
			continue
		var per: Dictionary = bmap[wid]
		for k in per:
			var builder := int(k)
			if builder == player or not WondersBridges.partners(state, builder, String(wid)).has(player):
				continue
			any_shared = true
			var entry: Dictionary = per[k]
			shared.body.add_child(UiTheme.paragraph("%s, chantier de %s : %d %%. Chaque mois, vous pouvez y verser %s ; l'effet se partage au prorata de ce que chacun a versé." % [
					Wonders.label(String(wid)), state.get_empire(builder).short_name(), Wonders.pct(entry), GameData.format_amounts(Wonders.contribute_cost(state, builder, String(wid)))], W, 12))
			var row := HBoxContainer.new()
			shared.body.add_child(row)
			_button(es, row, "Verser", SimCommands.won_act(player, "give", String(wid), builder))
	if any_shared:
		col.add_child(shared)

	var by_era := {}
	for wid in Wonders.all_ids():
		if not Wonders.visible_for(state, player, wid) or Wonders.def(wid).has("collective"):
			continue
		if not Wonders.build_of(state, player, wid).is_empty():
			continue
		var era := int(Wonders.def(wid).get("era", 1))
		if not by_era.has(era):
			by_era[era] = []
		by_era[era].append(wid)
	var eras := by_era.keys()
	eras.sort()
	for era: int in eras:
		var eb := Widgets.Block.new("Ère %s" % ["I", "II", "III", "IV", "V", "VI"][clampi(era - 1, 0, 5)])
		col.add_child(eb)
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 14)
		flow.add_theme_constant_override("v_separation", 14)
		eb.body.add_child(flow)
		# Celles qu'on peut encore viser d'abord, les achevées en dernier.
		var open_first: Array = (by_era[era] as Array).filter(func(w: String) -> bool: return String(card_state(state, player, w, seen)["id"]) != "done")
		open_first.append_array((by_era[era] as Array).filter(func(w: String) -> bool: return String(card_state(state, player, w, seen)["id"]) == "done"))
		for wid: String in open_first:
			flow.add_child(_card(es, wid, seen))

	var held := Wonders.held(state)
	if not held.is_empty():
		var hb := Widgets.Block.new("Merveilles de la galaxie")
		col.add_child(hb)
		for row in held:
			var pid := int(row[1])
			var known: bool = (state.colonies[pid] as Colony).owner == player or seen.has(state.galaxy.get_planet(pid).system_id) or Wonders.galaxy_unique(String(row[0]))
			if not known:
				continue
			var stg := Wonders.stage_at(state, String(row[0]), pid)
			hb.body.add_child(UiTheme.paragraph("%s : %s, sur %s%s" % [Wonders.label(String(row[0])), state.get_empire(int(row[2])).short_name(),
					state.galaxy.get_planet(pid).display_name(state.galaxy), (" (étape %d)" % stg) if stg > 0 else ""], W, 12))


## État d'une merveille pour l'empire : {id, text, color, detail}.
## id : "done" (achevée par un empire), "ruin", "locked", "race" (des rivaux y travaillent), "free", "nosite".
static func card_state(state: GameState, player: int, wid: String, seen: Dictionary) -> Dictionary:
	var at := Wonders.built_at(state, wid)
	if Wonders.galaxy_unique(wid) and at >= 0:
		var o: Colony = state.colonies[at]
		return {"id": "done", "text": "ACHEVÉE PAR %s" % state.get_empire(o.owner).short_name().to_upper(), "color": UiTheme.TEXT_DIM, "detail": ""}
	var rp := WondersCatalog.ruin_of(state, wid)
	if rp >= 0:
		var where := state.galaxy.get_planet(rp).display_name(state.galaxy) if Fleets.is_explored(state, player, state.galaxy.get_planet(rp).system_id) else "un monde inexploré"
		return {"id": "ruin", "text": "EN RUINE", "color": UiTheme.WARN, "detail": "Sur %s : qui tient cette planète peut la restaurer." % where}
	if not Wonders.unlocked(state, player, wid):
		return {"id": "locked", "text": "VERROUILLÉE", "color": UiTheme.TEXT_DIM,
				"detail": Wonders.check_start(state, player, state.get_empire(player).capital_planet, wid)}
	var riv := Wonders.rivals_known(state, player, wid, seen)
	var site := _first_site(state, player, wid)
	var detail := ("Site possible : %s." % state.galaxy.get_planet(site).display_name(state.galaxy)) if site >= 0 else "Aucun site convenable pour l'instant."
	if not riv.is_empty():
		return {"id": "race", "text": "EN COURSE CHEZ %d RIVA%s" % [riv.size(), "UX" if riv.size() > 1 else "L"], "color": Color(0.95, 0.62, 0.3), "detail": detail}
	if site < 0:
		return {"id": "nosite", "text": "SANS SITE", "color": UiTheme.TEXT_DIM, "detail": detail}
	return {"id": "free", "text": "LIBRE", "color": UiTheme.GOOD, "detail": detail}


const CARD_WIDTH := 236.0
const FAMILY_TINTS := {"galactique": Color(0.9, 0.78, 0.45), "mega": Color(0.55, 0.75, 0.95), "registre": Color(0.6, 0.85, 0.7),
		"credo": Color(0.8, 0.6, 0.9), "collective": Color(0.9, 0.6, 0.5), "oeuvre": Color(0.95, 0.9, 0.7)}


## Carte de catalogue (merveilles, mégastructures, forge) : image, nom, état, coût, effet, précision.
## Rend [carte, corps] : le corps reçoit les boutons éventuels.
static func catalog_card(art_id: String, tint: Color, title: String, badge: String, badge_col: Color, meta: String, text: String, detail: String, faded: bool) -> Array:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.box(Color(1, 1, 1, 0.035), UiTheme.LINE, 0, 1))
	panel.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	if faded:
		panel.modulate = Color(1, 1, 1, 0.62)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	var art := Widgets.ArtSlot.new(art_id, Vector2(CARD_WIDTH, 96), tint, "star")
	art.variant = art_id.hash() % 97
	art.set_caption(title, 17)
	col.add_child(art)
	var pad := MarginContainer.new()
	for side in ["left", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 10)
	col.add_child(pad)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	pad.add_child(body)
	var bl := Label.new()
	bl.theme_type_variation = &"Numbers"
	bl.text = badge
	bl.add_theme_font_size_override("font_size", 12)
	bl.add_theme_color_override("font_color", badge_col)
	bl.clip_text = true
	body.add_child(bl)
	if meta != "":
		var ml := UiTheme.paragraph(meta, CARD_WIDTH - 20.0, 11)
		ml.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		body.add_child(ml)
	body.add_child(UiTheme.paragraph(text, CARD_WIDTH - 20.0, 12))
	if detail != "":
		var dl := UiTheme.paragraph(detail, CARD_WIDTH - 20.0, 11)
		dl.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		body.add_child(dl)
	return [panel, body]


static func _card(es: EmpireScreens, wid: String, seen: Dictionary) -> Control:
	var state := es._state
	var player := es._player
	var st := card_state(state, player, wid, seen)
	var fam := Wonders.family(wid)
	var made := catalog_card("wonder_" + wid, FAMILY_TINTS.get(fam, Color(0.9, 0.78, 0.45)), Wonders.label(wid), String(st["text"]), st["color"],
			"%s · %s · %d j" % [Wonders.family_label(fam), GameData.format_amounts(Wonders.total_cost(state, player, wid)), int(Wonders.def(wid).get("days", 360))],
			Wonders.fiche_text(wid), String(st["detail"]), String(st["id"]) == "done" or String(st["id"]) == "locked")
	if String(st["id"]) == "free" or String(st["id"]) == "race":
		var site := _first_site(state, player, wid)
		if site >= 0:
			var row := HBoxContainer.new()
			(made[1] as VBoxContainer).add_child(row)
			_button(es, row, "Lancer sur %s" % state.galaxy.get_planet(site).display_name(state.galaxy), SimCommands.won_act(player, "start", wid, site))
	es.wonder_cards[wid] = made[0]
	return made[0]


## Barre d'avancement d'un concurrent dans la course à une merveille.
static func _race_bar(who: String, pct: int, color: Color, at_least: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var n := Label.new()
	n.text = who
	n.custom_minimum_size = Vector2(150, 0)
	n.clip_text = true
	n.add_theme_font_size_override("font_size", 13)
	row.add_child(n)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 100
	bar.value = pct
	bar.custom_minimum_size = Vector2(W - 260.0, 8)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	var v := Label.new()
	v.theme_type_variation = &"Numbers"
	v.text = "avancement inconnu" if at_least and pct <= 0 else "%d %%%s" % [pct, " au moins" if at_least else ""]
	row.add_child(v)
	return row


static func _button(es: EmpireScreens, row: HBoxContainer, text: String, cmd: Dictionary) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	var why := SimCommands.validate(es._state, cmd)
	b.disabled = why != ""
	b.tooltip_text = why
	b.pressed.connect(func() -> void: es.command_requested.emit(cmd))
	es.wonder_buttons["%s:%s" % [cmd.get("act", ""), cmd.get("s", "")]] = b
	row.add_child(b)


## Première colonie qui peut lancer cette merveille (capitale d'abord), -1 sinon.
static func _first_site(state: GameState, eid: int, wid: String) -> int:
	var ids := state.sorted_colony_ids()
	var cap := state.get_empire(eid).capital_planet
	if ids.has(cap):
		ids.erase(cap)
		ids.push_front(cap)
	for pid in ids:
		var c: Colony = state.colonies[pid]
		if c.owner == eid and Wonders.check_start(state, eid, pid, wid) == "":
			return pid
	return -1


static func _best_donor(state: GameState, eid: int, wid: String) -> int:
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == eid and Wonders.check_contribute(state, eid, wid, pid) == "":
			return pid
	return -1
