class_name AmphictyonyScreen
extends RefCounted
## Écran de l'Amphictyonie (M) : l'assemblée galactique (voir Amphictyony).
## Colonne de gauche : état de l'assemblée, vos voix, la prochaine séance, et les gestes d'un empire
## (signer l'acte de fondation, adhérer, partir). Contenu : la séance en cours (proposition, président,
## vote secret jusqu'à la clôture, voix achetées) avec l'hémicycle du dernier vote ; la file des
## propositions classée par soutien ; le pupitre pour proposer (familles à deux voies, sanctions et
## bannissement contre les hors-la-loi) ; les résolutions en vigueur et le Nomos ; les membres.
## Un empire jamais rencontré apparaît comme « monde inconnu ».
## Construit dans les conteneurs d'EmpireScreens, dont il reprend les aides (_grid, _key_value…).

const POUR := Color(0.42, 0.78, 0.45)
const CONTRE := Color(0.86, 0.36, 0.33)
const ABST := Color(0.5, 0.53, 0.58)


## Hémicycle du dernier vote : un siège par tranche de voix, coloré par le vote du membre.
class Hemicycle:
	extends Control
	## [[sièges, couleur]] de gauche à droite.
	var parts: Array = []

	func _init() -> void:
		custom_minimum_size = Vector2(380, 200)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var total := 0
		for p in parts:
			total += int(p[0])
		var center := Vector2(size.x * 0.5, size.y - 12.0)
		var r_out := minf(size.x * 0.5, size.y) - 12.0
		if total <= 0:
			draw_arc(center, r_out * 0.7, PI, TAU, 48, Color(UiTheme.TEXT_DIM, 0.5), 2.0, true)
			return
		var rows := clampi(int(ceil(sqrt(float(total) / 6.0))), 1, 7)
		var seats: Array = []
		var cap_sum := 0.0
		var radii: Array[float] = []
		for k in rows:
			var r := r_out * (0.45 + 0.55 * float(k + 1) / float(rows))
			radii.append(r)
			cap_sum += r
		for k in rows:
			var n := maxi(1, int(round(float(total) * radii[k] / cap_sum)))
			for j in n:
				var a := PI + PI * (float(j) + 0.5) / float(n)
				seats.append([a, center + Vector2(cos(a), sin(a)) * radii[k]])
		seats.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
		var dot := clampf(r_out / float(rows) * 0.3, 2.5, 8.0)
		var s := 0
		for p in parts:
			for _j in int(p[0]):
				if s >= seats.size():
					break
				draw_circle(seats[s][1], dot, p[1])
				s += 1


static func build(es: EmpireScreens) -> void:
	var state := es._state
	var player := es._player
	es._amph_sig = signature(es)
	es.amph_buttons.clear()
	es._side_header("screen_amphictyony", "Amphictyonie", Color(0.82, 0.7, 0.38), "faction")
	var g := es._grid()
	es._side_box.add_child(g)
	var w := EmpireScreens.SIDE_WIDTH - 24.0
	var ro := state.get_empire(player) == null
	if not state.amph_on:
		es._side_box.add_child(UiTheme.paragraph("Cette partie se joue sans Amphictyonie (réglage de Nouvelle partie).", w, 13))
	elif not Amphictyony.founded(state):
		es._key_value(g, "Statut", "pas encore fondée")
		es._key_value(g, "Galaxie rencontrée", "%d %%" % Amphictyony.met_pct(state, player) if not ro else "—")
		if Amphictyony.offer_open(state):
			var yes: Array = state.amph["offer"]["yes"]
			es._key_value(g, "Signatures", "%d / %d" % [yes.size(), int(Amphictyony.data()["found"]["founders"])])
			if not ro:
				_action(es, "found", "Signer l'acte de fondation", Amphictyony.check_found(state, player), SimCommands.amph_found(player),
						"Il faut trois signatures pour fonder l'Amphictyonie. Les fondateurs y siègent d'office.")
		else:
			es._side_box.add_child(UiTheme.paragraph("Quand un empire aura rencontré 70 % des autres (et pas avant l'an 8), l'acte de fondation circulera : il faudra trois signatures.", w, 13))
	else:
		var member := Amphictyony.is_member(state, player)
		es._key_value(g, "Fondée le", GameCalendar.date_string(int(state.amph["founded"])))
		es._key_value(g, "Amphictyons", str(Amphictyony.members(state).size()))
		var vl := es._key_value(g, "Vos voix", "%d / %d" % [Amphictyony.weight(state, player), Amphictyony.total_weight(state)] if member else "non-membre")
		if member and Amphictyony.voix_pct(state, player) != 0:
			vl.text += "  (%+d %%)" % Amphictyony.voix_pct(state, player)
		@warning_ignore("integer_division")
		var months := (Amphictyony.days_left(state) + 29) / 30
		es._key_value(g, "Clôture du vote" if Amphictyony.in_session(state) else "Prochaine séance", "dans %d mois" % maxi(1, months) if months > 0 else "ce mois-ci")
		if Amphictyony.outlaw(state, player):
			var ol := es._key_value(g, "Statut", "HORS-LA-LOI")
			ol.add_theme_color_override("font_color", CONTRE)
		if not ro:
			if member:
				_action(es, "leave", "Quitter l'Amphictyonie (%s)" % GameData.format_amounts(Amphictyony.leave_cost(state, player)), Amphictyony.check_leave(state, player),
						SimCommands.amph_leave(player), "Partir coûte une somme qui grandit avec l'empire, et interdit le retour pendant 10 ans.")
			else:
				_action(es, "join", "Adhérer (%s)" % GameData.format_amounts(Amphictyony.join_cost(state, player)), Amphictyony.check_join(state, player),
						SimCommands.amph_join(player), "Seuls les membres votent, profitent des résolutions et accèdent au marché commun ; mais ils sont liés par le Nomos.")
	es._side_box.add_child(HSeparator.new())
	es._side_box.add_child(UiTheme.paragraph(String(EmpireBar.screen_info("amphictyony").get("why", "")), w, 13))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	es._content.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 18)
	scroll.add_child(col)
	if not Amphictyony.founded(state):
		var b := Widgets.Block.new(Amphictyony.cap(Amphictyony.name_long()))
		col.add_child(b)
		b.body.add_child(UiTheme.paragraph("Une assemblée de tous les empires qui le veulent : une tribune, des voix pesées, des résolutions qui tordent les règles du commerce, du savoir, de la guerre, de la foi, des peuples, des ombres et des périls ; et une loi commune, le Nomos, dont la première ligne interdit les atrocités. Elle naît quand assez d'empires se connaissent." if state.amph_on
				else "Pas d'assemblée galactique dans cette partie.", 760.0, 15))
		return
	col.add_child(_session_block(es))
	col.add_child(_queue_block(es))
	if Amphictyony.is_member(state, player) and not ro:
		col.add_child(_propose_block(es))
	col.add_child(_law_block(es))
	col.add_child(_members_block(es))


## Ce qui change l'écran : mois, séance, file, résolutions, peines, membres.
static func signature(es: EmpireScreens) -> String:
	var state := es._state
	var e := state.get_empire(es._player)
	@warning_ignore("integer_division")
	return "%d|%s|%s|%s" % [state.tick / 30, str(state.amph), str(e.resources.get("influence", 0)) if e != null else "", str(state.amph_on)]


static func _action(es: EmpireScreens, key: String, text: String, why: String, cmd: Dictionary, tip: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.text = text
	b.disabled = why != ""
	b.tooltip_text = tip + ("\n" + why if why != "" else "")
	b.pressed.connect(func() -> void: es.command_requested.emit(cmd))
	es._side_box.add_child(b)
	es.amph_buttons[key] = b
	return b


static func _btn(es: EmpireScreens, key: String, text: String, why: String, cmd: Dictionary, tip := "") -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.text = text
	b.disabled = why != ""
	b.tooltip_text = tip + (("\n" if tip != "" else "") + why if why != "" else "")
	b.pressed.connect(func() -> void: es.command_requested.emit(cmd))
	es.amph_buttons[key] = b
	return b


## Nom d'un empire pour l'observateur (« monde inconnu » s'il ne l'a jamais rencontré).
static func who(state: GameState, viewer: int, eid: int) -> String:
	var e := state.get_empire(eid)
	if e == null:
		return "?"
	var v := state.get_empire(viewer)
	if v != null and viewer != eid and not v.contacts.has(eid):
		return "monde inconnu"
	return e.display_name()


static func _session_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var b := Widgets.Block.new("Séance")
	var member := Amphictyony.is_member(state, player)
	if Amphictyony.in_session(state):
		var s := Amphictyony.session(state)
		var p: Dictionary = s["prop"]
		var tl := Label.new()
		tl.text = Amphictyony.cap(Amphictyony.prop_label(state, p))
		tl.add_theme_font_size_override("font_size", 19)
		tl.add_theme_color_override("font_color", UiTheme.GOLD)
		b.body.add_child(tl)
		b.body.add_child(UiTheme.paragraph(Amphictyony.prop_text(state, p), 760.0, 14))
		@warning_ignore("integer_division")
		b.body.add_child(UiTheme.dim("Proposée par %s · présidée par %s · clôture le %s · %d amphictyon%s ont voté (vote secret jusqu'à la clôture)" % [
				who(state, player, int(p["by"])), who(state, player, int(s["pres"])), GameCalendar.date_string(int(s["end"])),
				(s["votes"] as Dictionary).size(), "s" if (s["votes"] as Dictionary).size() > 1 else ""], 13))
		if member and state.get_empire(player) != null:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			b.body.add_child(row)
			var mine := Amphictyony.vote_of(state, player)
			row.add_child(UiTheme.dim("Votre vote :", 14))
			for v in [1, -1, 0]:
				var lab := "Pour" if v == 1 else ("Contre" if v == -1 else "Abstention")
				var bt := _btn(es, "vote:%d" % v, ("● " if mine == v else "") + lab, Amphictyony.check_vote(state, player, v), SimCommands.amph_vote(player, v),
						"Modifiable jusqu'à la clôture. L'abstention ne compte pas.")
				row.add_child(bt)
			var bc := Amphictyony.buy_cost(state, player)
			var buy := _btn(es, "buy", "Acheter des voix (+%d, %s)" % [Amphictyony.buy_voix(state), GameData.format_amounts(bc)], Amphictyony.check_buy(state, player), SimCommands.amph_buy(player),
					"Pour ce seul vote, dans le camp de votre vote. Chaque tranche coûte plus cher que la précédente ; remboursées à moitié si votre camp perd.")
			row.add_child(buy)
			if Amphictyony.bought(state, player) > 0:
				row.add_child(UiTheme.dim("%d tranche%s achetée%s" % [Amphictyony.bought(state, player), "s" if Amphictyony.bought(state, player) > 1 else "", "s" if Amphictyony.bought(state, player) > 1 else ""], 13))
	else:
		var q := (state.amph["queue"] as Array).size()
		b.body.add_child(UiTheme.paragraph("Pas de séance en cours. La prochaine s'ouvrira le %s avec la proposition la plus soutenue de la file (%d en attente) ; son président peut y placer la sienne, sans frais." % [
				GameCalendar.date_string(int(state.amph["next"])), q], 760.0, 14))
	var hist: Array = state.amph["hist"]
	if not hist.is_empty():
		var h: Dictionary = hist[hist.size() - 1]
		var row2 := HBoxContainer.new()
		row2.add_theme_constant_override("separation", 20)
		b.body.add_child(row2)
		var hc := Hemicycle.new()
		var pour := 0
		var contre := 0
		var abst := 0
		var hv: Dictionary = h.get("votes", {})
		for m in Amphictyony.members(state):
			@warning_ignore("integer_division")
			var seats := maxi(1, Amphictyony.weight(state, m) / 10)
			var v := int(hv.get(str(m), 0))
			if v > 0:
				pour += seats
			elif v < 0:
				contre += seats
			else:
				abst += seats
		hc.parts = [[pour, POUR], [abst, ABST], [contre, CONTRE]]
		row2.add_child(hc)
		var side := VBoxContainer.new()
		row2.add_child(side)
		side.add_child(UiTheme.dim("Dernier vote, le %s" % GameCalendar.date_string(int(h["day"])), 13))
		var rl := Label.new()
		rl.text = ("ADOPTÉE : " if bool(h["pass"]) else "REJETÉE : ") + Amphictyony.prop_label(state, h["prop"])
		rl.add_theme_color_override("font_color", POUR if bool(h["pass"]) else CONTRE)
		rl.add_theme_font_size_override("font_size", 16)
		rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rl.custom_minimum_size = Vector2(340, 0)
		side.add_child(rl)
		side.add_child(UiTheme.dim("%d voix pour, %d contre" % [int(h["pour"]), int(h["contre"])], 14))
	return b


static func _queue_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var b := Widgets.Block.new("File des propositions")
	var q := Amphictyony.sorted_queue(state)
	if q.is_empty():
		b.body.add_child(UiTheme.dim("La file est vide : chaque amphictyon peut y déposer une proposition.", 14))
		return b
	var member := Amphictyony.is_member(state, player) and state.get_empire(player) != null
	for p: Dictionary in q:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		b.body.add_child(row)
		var nl := Label.new()
		nl.text = Amphictyony.cap(Amphictyony.prop_label(state, p))
		nl.custom_minimum_size = Vector2(380, 0)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.add_theme_font_size_override("font_size", 15)
		nl.mouse_filter = Control.MOUSE_FILTER_STOP
		nl.tooltip_text = Amphictyony.prop_text(state, p)
		row.add_child(nl)
		var by := UiTheme.dim(who(state, player, int(p["by"])), 13)
		by.custom_minimum_size = Vector2(170, 0)
		row.add_child(by)
		var sup := UiTheme.dim("soutien %d voix" % Amphictyony.support_weight(state, p), 13)
		sup.custom_minimum_size = Vector2(120, 0)
		row.add_child(sup)
		if not member:
			continue
		if int(p["by"]) == player:
			row.add_child(_btn(es, "withdraw", "Retirer", Amphictyony.check_withdraw(state, player), SimCommands.amph_withdraw(player), "Sans remboursement."))
		else:
			var on := (p["sup"] as Array).has(player)
			row.add_child(_btn(es, "support:%d" % int(p["id"]), "Soutenu" if on else "Soutenir", Amphictyony.check_support(state, player, int(p["id"])),
					SimCommands.amph_support(player, int(p["id"])), "Vos voix s'ajoutent à son soutien : la plus soutenue passe en séance."))
	return b


static func _propose_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var b := Widgets.Block.new("Proposer")
	var mine := Amphictyony.proposal_of(state, player)
	if not mine.is_empty():
		b.body.add_child(UiTheme.dim("Votre proposition : %s. Une seule à la fois." % Amphictyony.prop_label(state, mine), 14))
		return b
	for f: Dictionary in Amphictyony.family_defs():
		var fid := String(f["id"])
		if not Amphictyony.family_available(state, fid):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		b.body.add_child(row)
		var fl := Label.new()
		fl.text = String(f["label"])
		fl.custom_minimum_size = Vector2(140, 0)
		fl.add_theme_font_size_override("font_size", 15)
		row.add_child(fl)
		var v := Amphictyony.fam_value(state, fid)
		var cur := UiTheme.dim(Amphictyony.level_name(fid, v) if v != 0 else "—", 13)
		cur.custom_minimum_size = Vector2(170, 0)
		row.add_child(cur)
		for dir in [1, -1]:
			var st := Amphictyony.step_to(state, fid, dir)
			var way := "a" if dir > 0 else "b"
			var text := ""
			if not bool(st[0]):
				text = "%s : au sommet" % String(f[way]["label"])
			elif Amphictyony.is_repeal(v, int(st[1])):
				text = "Abroger %s" % Amphictyony.level_name(fid, v)
			else:
				text = Amphictyony.level_name(fid, int(st[1]))
			var cost := Amphictyony.prop_cost(state, "step", fid, dir) if bool(st[0]) else {}
			if not cost.is_empty():
				text += " (%s)" % GameData.format_amounts(cost)
			row.add_child(_btn(es, "propose:%s:%d" % [fid, dir], text, Amphictyony.check_propose(state, player, "step", fid, dir, -1, ""),
					SimCommands.amph_propose(player, "step", fid, dir), String(f[way].get("text", ""))))
	for t in Amphictyony.outlaws(state):
		if t == player:
			continue
		var row2 := HBoxContainer.new()
		row2.add_theme_constant_override("separation", 10)
		b.body.add_child(row2)
		var tl := Label.new()
		tl.text = "Contre %s" % who(state, player, t)
		tl.custom_minimum_size = Vector2(310, 0)
		tl.add_theme_color_override("font_color", CONTRE)
		row2.add_child(tl)
		for s: Dictionary in Amphictyony.sanction_defs():
			var sid := String(s["id"])
			row2.add_child(_btn(es, "sanction:%d:%s" % [t, sid], "%s %d" % [String(s["label"]), Amphictyony.sanction_degree(state, t, sid) + 1],
					Amphictyony.check_propose(state, player, "sanction", "", 0, t, sid), SimCommands.amph_propose(player, "sanction", "", 0, t, sid), String(s.get("text", ""))))
		if Amphictyony.is_member(state, t):
			row2.add_child(_btn(es, "expel:%d" % t, "Bannir", Amphictyony.check_propose(state, player, "expel", "", 0, t, ""),
					SimCommands.amph_propose(player, "expel", "", 0, t), "Il perd son siège pour 10 ans."))
	return b


static func _law_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var b := Widgets.Block.new("Résolutions et Nomos")
	var act := Amphictyony.active(state)
	if act.is_empty():
		b.body.add_child(UiTheme.dim("Aucune résolution en vigueur.", 14))
	for r: Dictionary in act:
		var l := Label.new()
		l.text = "%s : %s (%s %s)" % [String(Amphictyony.family_def(String(r["fam"]))["label"]), String(r["name"]), String(r["way"]), Amphictyony._roman(absi(int(r["v"])))]
		l.add_theme_font_size_override("font_size", 15)
		b.body.add_child(l)
	var bans := PackedStringArray()
	for k in Amphictyony.bans(state):
		bans.append(Amphictyony.breach_label(k))
	b.body.add_child(UiTheme.paragraph("Nomos (interdits pour les membres) : %s." % "; ".join(bans), 760.0, 14))
	for t in Amphictyony.outlaws(state):
		var o: Dictionary = state.amph["outlaw"][str(t)]
		var sc: Dictionary = (state.amph["sanc"] as Dictionary).get(str(t), {})
		var parts := PackedStringArray()
		for sid in sc:
			parts.append("%s %d" % [String(Amphictyony.sanction_def(String(sid)).get("label", sid)), int(sc[sid])])
		var ol := UiTheme.dim("Hors-la-loi : %s, jusqu'au %s (%s)%s" % [who(state, player, t), GameCalendar.date_string(int(o["until"])), Amphictyony.breach_label(String(o["why"])),
				(" · " + ", ".join(parts)) if not parts.is_empty() else ""], 14)
		ol.add_theme_color_override("font_color", CONTRE)
		b.body.add_child(ol)
	return b


static func _members_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var b := Widgets.Block.new("Amphictyons")
	var ms := Amphictyony.members(state)
	ms.sort_custom(func(x: int, y: int) -> bool: return Amphictyony.weight(state, x) > Amphictyony.weight(state, y))
	for m in ms:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		b.body.add_child(row)
		var sw := ColorRect.new()
		var known := who(state, player, m) != "monde inconnu"
		sw.color = state.get_empire(m).color() if known else ABST
		sw.custom_minimum_size = Vector2(10, 20)
		row.add_child(sw)
		var nl := Label.new()
		nl.text = who(state, player, m)
		nl.custom_minimum_size = Vector2(260, 0)
		nl.add_theme_font_size_override("font_size", 15)
		row.add_child(nl)
		var vl := UiTheme.dim("%d voix" % Amphictyony.weight(state, m), 14)
		vl.custom_minimum_size = Vector2(90, 0)
		row.add_child(vl)
		var tags := PackedStringArray()
		if Amphictyony.president(state) == m:
			tags.append("président de séance")
		if Amphictyony.outlaw(state, m):
			tags.append("hors-la-loi")
		if Amphictyony.galactic_follower(state, m):
			tags.append("foi galactique")
		row.add_child(UiTheme.dim(", ".join(tags), 13))
	return b
