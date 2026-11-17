class_name MegasUi
extends RefCounted
## Écran Mégastructures (prop. 43) : un onglet de l'écran Merveilles, sans nouvelle lentille. Indice de
## Kardashev, étapes en chantier, vos mégastructures (lancer, réparer, abandonner, module, tirs), ce que
## vous pouvez bâtir et où ; au centre, le catalogue et les ruines connues. Actions sur l'écran Système.

const COLOR := Color(0.75, 0.88, 1.0)


## Onglets « Merveilles | Mégastructures » en tête des deux écrans (si les mégastructures sont en jeu).
static func tabs(es: EmpireScreens, active: String) -> void:
	if not Megastructures.enabled(es._state):
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for t in [["wonders", "Merveilles"], ["megas", "Mégastructures"]]:
		var b := Button.new()
		b.text = String(t[1])
		b.toggle_mode = true
		b.button_pressed = String(t[0]) == active
		b.focus_mode = Control.FOCUS_NONE
		var sid := String(t[0])
		b.pressed.connect(func() -> void: es.show_screen(sid))
		es.mega_buttons["tab:" + sid] = b
		row.add_child(b)
	es._side_box.add_child(row)


static func signature(es: EmpireScreens) -> String:
	var state := es._state
	if not Megastructures.enabled(state):
		return "off"
	var e := state.get_empire(es._player)
	@warning_ignore("integer_division")
	return "%d|%d|%s|%d|%d" % [e.techs.size(), state.tick / 30, str(Megastructures.entries(state)), Kardashev.index100(state, es._player), Megastructures.architects_of(state, es._player).size()]


static func _btn(es: EmpireScreens, text: String, command: Dictionary, tip: String, key: String) -> Button:
	var why := SimCommands.validate(es._state, command)
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = why != ""
	b.clip_text = true
	b.custom_minimum_size = Vector2(EmpireScreens.SIDE_WIDTH - 24.0, 0)
	b.tooltip_text = tip + ("\n\nImpossible : %s." % why if why != "" else "")
	b.pressed.connect(func() -> void: es.command_requested.emit(command))
	es.mega_buttons[key] = b
	return b


static func status_text(state: GameState, m: Dictionary) -> String:
	var k := String(m["k"])
	var n := Megastructures.stage_count(k)
	var s := "étape %d / %d" % [int(m["st"]), n]
	if Megastructures.is_ruin(m):
		s = "ruine (%d / %d étapes)" % [int(m["st"]), n]
		if bool(m.get("rs", 0)):
			s += ", restauration : %d jours" % int(m["w"])
		return s
	if Megastructures.complete(m):
		s = "achevée"
	if bool(m.get("dmg", 0)):
		s += ", étape ruinée"
	if Megastructures.running(m):
		var what := "réparation" if bool(m.get("rp", 0)) else String(Megastructures.stage_def(k, int(m["st"])).get("label", ""))
		s += ", en chantier (%s) : %d jours" % [what, int(m["w"])]
	if int(m.get("wear", 0)) > 0:
		s += ", usure %d %%" % int(m["wear"])
	if int(m.get("cd", 0)) > state.tick:
		s += ", recharge %d jours" % (int(m["cd"]) - state.tick)
	if String(m.get("mod", "")) != "":
		s += ", module %s" % String(((Megastructures.kind_def(k).get("modules", {}) as Dictionary).get(String(m["mod"]), {}) as Dictionary).get("label", m["mod"])).to_lower()
	return s


static func build(es: EmpireScreens) -> void:
	var state := es._state
	var player := es._player
	es._megas_sig = signature(es)
	es._side_header("screen_megas", "Mégastructures", COLOR, "faction")
	tabs(es, "megas")
	var w := EmpireScreens.SIDE_WIDTH - 24.0
	if not Megastructures.applies(state, player):
		es._side_box.add_child(UiTheme.paragraph("Dans cette partie, les mégastructures ne sont pas en jeu (Nouvelle partie : Mégastructures).", w, 13))
		return
	var g := es._grid()
	es._side_box.add_child(g)
	es._key_value(g, "Réglage", Megastructures.mode_label(state))
	if Kardashev.enabled(state):
		es._key_value(g, "Indice de Kardashev", Kardashev.text(state, player))
	es._key_value(g, "Étapes en chantier", "%d / %d" % [Megastructures.busy(state, player), Megastructures.slots(state, player)])
	es._key_value(g, "Vaisseaux-architectes", str(Megastructures.architects_of(state, player).size()))
	var t := Megastructures.talent(state, player)
	if t.has("label"):
		es._side_box.add_child(HSeparator.new())
		es._side_box.add_child(UiTheme.dim("Talent de votre peuple", 13))
		es._side_box.add_child(UiTheme.paragraph("%s : %s" % [String(t["label"]), String(t.get("text", ""))], w, 12))
	es._side_box.add_child(HSeparator.new())
	var mine := Megastructures.owned_by(state, player)
	if not mine.is_empty():
		es._side_box.add_child(UiTheme.dim("Vos mégastructures", 13))
	for m in mine:
		for b in actions_for(es, m):
			es._side_box.add_child(b)
	es._side_box.add_child(UiTheme.dim("Bâtir", 13))
	var any := false
	for k in Megastructures.kind_ids():
		if not Megastructures.kind_allowed(state, k) or not Megastructures.unlocked(state, player, k) or bool(Megastructures.kind_def(k).get("ruin_only", false)):
			continue
		var s := Megastructures.sites(state, player, k, 1)
		if s.is_empty():
			continue
		any = true
		var site: Array = s[0]
		var where := Megastructures.site_name(state, {"s": int(site[0]), "p": int(site[1])})
		es._side_box.add_child(_btn(es, "%s : %s (%s)" % [Megastructures.label(k), where, GameData.format_amounts(Megastructures.stage_cost(state, player, k, 0, int(site[0])))],
				SimCommands.mega_act(player, "plan", {"k": k, "s": int(site[0]), "p": int(site[1])}),
				"Le Vaisseau-architecte libre le plus proche part poser le Chantier ; il doit rester sur place jusqu'à ce qu'il tienne.\n\n" + String(Megastructures.kind_def(k).get("text", "")),
				"plan:" + k))
	if not any:
		es._side_box.add_child(UiTheme.paragraph("Aucun site disponible : il faut la technologie, un système tenu qui convient et la place dans les limites du type.", w, 12))
	es._side_box.add_child(HSeparator.new())
	es._side_box.add_child(UiTheme.paragraph("Une mégastructure se pose sur un astre précis d'un système que vous tenez. Un Vaisseau-architecte pose le Chantier et reste jusqu'à ce qu'il tienne ; chaque étape suivante se lance à part, payée au lancement, et l'empire n'en avance que %d à la fois au départ. Une flotte ennemie qui tient le système %d mois ruine l'étape la plus haute ; la prise du système donne l'ouvrage au vainqueur." % [
			Megastructures.r_int("slots", 1), Megastructures.r_int("siege_months", 3)], w, 12))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	es._content.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 18)
	scroll.add_child(col)

	if Kardashev.enabled(state):
		var kb := Widgets.Block.new("Échelle de Kardashev : %s" % Kardashev.text(state, player))
		col.add_child(kb)
		kb.body.add_child(UiTheme.paragraph("Chaque étape achevée d'une mégastructure qui capte l'énergie d'un astre fait monter votre puissance captée, et donc votre indice ; le type II demande une Sphère de Dyson ou trois Essaims achevés. Le détail est dans l'écran Victoires, onglet L'Échelle.", 760.0, 13))

	var seen := Fleets.visible_systems(state, player)
	var known := Widgets.Block.new("Mégastructures connues")
	col.add_child(known)
	var n_known := 0
	for m in Megastructures.all_sorted(state):
		var sid := int(m["s"])
		if not (es.see_all or int(m["o"]) == player or seen.has(sid) or Fleets.is_explored(state, player, sid)):
			continue
		n_known += 1
		var o := state.get_empire(int(m["o"]))
		known.body.add_child(UiTheme.paragraph("%s : %s%s" % [Megastructures.name_of(state, m), status_text(state, m), (", à %s" % o.short_name()) if o != null and not Megastructures.is_ruin(m) else ""], 760.0, 13))
	if n_known == 0:
		known.body.add_child(UiTheme.dim("Aucune pour l'instant.", 13))

	var cb := Widgets.Block.new("Catalogue")
	col.add_child(cb)
	for k in Megastructures.kind_ids():
		if not Megastructures.kind_allowed(state, k):
			continue
		var d := Megastructures.kind_def(k)
		var st := PackedStringArray()
		for i in Megastructures.stage_count(k):
			var sd := Megastructures.stage_def(k, i)
			st.append("%s (%s, %d j)" % [String(sd.get("label", "")), GameData.format_amounts(sd.get("cost", {})), int(sd.get("days", 0))])
		var tech := "" if Megastructures.unlocked(state, player, k) else " — technologie : %s" % Research.missing_text(state, player, d.get("tech", []))
		cb.body.add_child(UiTheme.paragraph("%s (ère %d)%s\n%s\nÉtapes : %s\n« %s »" % [Megastructures.label(k), int(d.get("era", 1)), tech, String(d.get("text", "")), ", ".join(st), String(d.get("quote", ""))], 760.0, 12))


## Boutons d'une de vos mégastructures (écran et fiche).
static func actions_for(es: EmpireScreens, m: Dictionary) -> Array[Button]:
	var state := es._state
	var player := es._player
	var out: Array[Button] = []
	var id := int(m["id"])
	var k := String(m["k"])
	var nm := Megastructures.name_of(state, m)
	var holder := Button.new()
	holder.text = "%s : %s" % [nm, status_text(state, m)]
	holder.flat = true
	holder.disabled = true
	holder.clip_text = true
	holder.tooltip_text = String(Megastructures.kind_def(k).get("text", ""))
	out.append(holder)
	if Megastructures.is_ruin(m):
		return out
	var n := int(m["st"])
	if bool(m.get("dmg", 0)):
		out.append(_btn(es, "Réparer (%s)" % GameData.format_amounts(Megastructures.repair_cost(state, player, m)), SimCommands.mega_act(player, "repair", {"id": id}),
				"L'étape ruinée se répare pour la moitié de son coût, en deux fois moins de temps.", "repair:%d" % id))
	elif n < Megastructures.stage_count(k) and not Megastructures.running(m) and n > 0:
		var sd := Megastructures.stage_def(k, n)
		out.append(_btn(es, "Lancer « %s » (%s)" % [String(sd.get("label", "")), GameData.format_amounts(Megastructures.stage_cost(state, player, k, n, int(m["s"])))],
				SimCommands.mega_act(player, "advance", {"id": id}), "Étape payée au lancement ; %d jours." % Megastructures.stage_days(state, player, k, n, int(m["s"])), "advance:%d" % id))
		if not state.private.is_empty() and Private.full(state):
			out.append(_btn(es, "Faire financer l'étape par une compagnie", SimCommands.mega_act(player, "fund", {"id": id}),
					"Une compagnie privée paie l'étape, contre %d %% des rendements de l'ouvrage pendant %d ans." % [MegasBridges.c_int("private", "share_pct", 25), MegasBridges.c_int("private", "years", 10)], "fund:%d" % id))
	if n == 0:
		out.append(_btn(es, "Abandonner le chantier", SimCommands.mega_act(player, "cancel", {"id": id}), "La moitié du coût du Chantier revient.", "cancel:%d" % id))
	if bool(Megastructures.special(m, "module", false)):
		for mod in (Megastructures.kind_def(k).get("modules", {}) as Dictionary):
			var md: Dictionary = Megastructures.kind_def(k)["modules"][mod]
			if String(m.get("mod", "")) != String(mod):
				out.append(_btn(es, "Module : %s" % String(md.get("label", mod)), SimCommands.mega_act(player, "module", {"id": id, "m": String(mod)}), String(md.get("text", "")), "module:%d:%s" % [id, mod]))
	if k == "catapulte_quantique" and int(Megastructures.special(m, "range", 0)) > 0:
		var j := FactionTraits.jumps_from(state.galaxy, int(m["s"]))
		var rng := int(Megastructures.special(m, "range", 0))
		for fid in state.sorted_fleet_ids():
			var f: Fleet = state.fleets[fid]
			if f.owner != player or f.system_id != int(m["s"]) or f.is_moving() or Megastructures.is_architect_fleet(f):
				continue
			var dests: Array = []
			for sid in j:
				if int(j[sid]) <= rng and int(j[sid]) > 0 and Fleets.is_explored(state, player, int(sid)):
					dests.append([int(j[sid]), int(sid)])
			dests.sort()
			dests.reverse()
			for x in dests.slice(0, 5):
				out.append(_btn(es, "Catapulter %s vers %s (%d sauts)" % [f.fleet_name, state.galaxy.systems[int(x[1])].system_name, int(x[0])],
						SimCommands.mega_act(player, "launch", {"id": id, "f": f.id, "t": int(x[1])}),
						"%d %% de risque d'arriver à côté ; %s." % [int(Megastructures.special(m, "miss", 0)), GameData.format_amounts(Megastructures.kind_def(k).get("launch_cost", {}))],
						"launch:%d:%d:%d" % [id, f.id, int(x[1])]))
			break
	if k == "brise_monde" and bool(Megastructures.special(m, "fire", false)):
		var j := FactionTraits.jumps_from(state.galaxy, int(m["s"]))
		var shown := 0
		for pid in state.sorted_colony_ids():
			var c: Colony = state.colonies[pid]
			if c.owner == player or int(j.get(state.galaxy.get_planet(pid).system_id, 99)) > 8:
				continue
			var cmd := SimCommands.mega_act(player, "fire", {"id": id, "t": pid})
			if SimCommands.validate(state, cmd) != "":
				continue
			out.append(_btn(es, "Briser %s" % state.galaxy.get_planet(pid).display_name(state.galaxy), cmd,
					"Détruit la planète et sa colonie. Toute la galaxie s'en souviendra.", "fire:%d:%d" % [id, pid]))
			shown += 1
			if shown >= 5:
				break
	if k == "anneau_extinction" and bool(Megastructures.special(m, "purge", false)):
		out.append(_btn(es, "Allumer l'Anneau d'extinction", SimCommands.mega_act(player, "purge", {"id": id}),
				"Anéantit les flottes de la crise à 6 sauts ou moins ; la moitié des habitants de la zone meurt aussi.", "purge:%d" % id))
	return out


## Actions de l'écran Système pour une de vos colonies p : bâtir sur la planète (ou autour de l'étoile, sur
## la première colonie du système), relever une ruine du système, avancer une mégastructure du système.
static func system_actions(state: GameState, player: int, p: Planet, emit: Callable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not Megastructures.applies(state, player):
		return out
	var sid := p.system_id
	var first := -1
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == player and c.is_established():
			first = pid
			break
	for k in Megastructures.kind_ids():
		if not Megastructures.kind_allowed(state, k) or not Megastructures.unlocked(state, player, k):
			continue
		var b := Megastructures.body(k)
		var targets: Array[int] = []
		if b == "star":
			if p.id == first:
				targets.append(-1)
		elif b == "colony":
			targets.append(p.id)
		else:
			for pid in state.galaxy.systems[sid].planet_ids:
				if p.id == first:
					targets.append(pid)
		for tp in targets:
			if Megastructures.site_reason(state, player, k, sid, tp) != "":
				continue
			var where := Megastructures.site_name(state, {"s": sid, "p": tp})
			out.append(WondersUi._act(state, SimCommands.mega_act(player, "plan", {"k": k, "s": sid, "p": tp}), "Mégastructure : %s" % Megastructures.label(k),
					"%s  »  %s" % [GameData.format_amounts(Megastructures.stage_cost(state, player, k, 0, sid)), where],
					"Un Vaisseau-architecte part poser le Chantier et reste jusqu'à ce qu'il tienne.\n\n" + String(Megastructures.kind_def(k).get("text", "")), emit))
	if p.id != first:
		return out
	for m in Megastructures.in_system(state, sid):
		var id := int(m["id"])
		if Megastructures.is_ruin(m) and not bool(m.get("rs", 0)):
			out.append(WondersUi._act(state, SimCommands.mega_act(player, "restore", {"id": id}), "Relever : %s" % Megastructures.label(String(m["k"])),
					"%s  »  %d jours" % [GameData.format_amounts(MegasWorld.restore_cost(state, player, m)), MegasWorld.restore_days(state, player)],
					"Une mégastructure d'un âge oublié gît ici. Un Vaisseau-architecte libre sur place la relève, avec les étapes qu'elle garde.", emit))
		elif int(m["o"]) == player and int(m["st"]) > 0 and not Megastructures.running(m) and not Megastructures.complete(m) and not bool(m.get("dmg", 0)):
			var k := String(m["k"])
			out.append(WondersUi._act(state, SimCommands.mega_act(player, "advance", {"id": id}), "%s : « %s »" % [Megastructures.label(k), String(Megastructures.stage_def(k, int(m["st"])).get("label", ""))],
					GameData.format_amounts(Megastructures.stage_cost(state, player, k, int(m["st"]), sid)), "Étape suivante, payée au lancement.", emit))
	return out
