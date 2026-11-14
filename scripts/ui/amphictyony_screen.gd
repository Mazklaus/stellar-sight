class_name AmphictyonyScreen
extends RefCounted
## Écran de l'Amphictyonie (M) : l'assemblée galactique (voir Amphictyony).
## Colonne de gauche : état de l'assemblée, vos voix, la prochaine séance, et les gestes d'un empire
## (signer l'acte de fondation, adhérer, partir). Contenu : la séance en cours (proposition, président,
## vote secret jusqu'à la clôture, voix achetées) avec l'hémicycle du dernier vote ; la file des
## propositions classée par soutien ; le pupitre pour proposer (familles à deux voies, sanctions et
## bannissement contre les hors-la-loi) ; les résolutions en vigueur et le Nomos ; les membres.
## Lot 2 : la Haute Voûte et l'Arbitre des étoiles (veto, urgence, dénonciation, gel, clôture, trêve),
## les faveurs, le banc des observateurs, les crises et la coalition, l'aide d'urgence, les grands travaux.
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
		elif AmphInst.denounced(state, player):
			var dl := es._key_value(g, "Statut", "dénoncé")
			dl.add_theme_color_override("font_color", CONTRE)
		if AmphPower.imperator(state) == player:
			es._key_value(g, "Charge", "Impérateur (autorité %d)" % AmphPower.authority(state))
		elif AmphInst.arbiter(state) == player:
			es._key_value(g, "Charge", "Arbitre des étoiles")
		elif AmphInst.is_councillor(state, player):
			es._key_value(g, "Charge", "conseiller de la Haute Voûte")
		elif AmphInst.is_observer(state, player):
			es._key_value(g, "Banc", "observateur")
		if member:
			var amb := AmphInst.ambassador(state, player)
			es._key_value(g, "Ambassadeur", "%s (+%d %%)" % [String(amb["name"]), AmphInst.ambassador_pct(state, player)] if not amb.is_empty() else "aucun (écran Héros)")
			var owed := 0
			for d in AmphInst.debtors(state, player):
				owed += int(d[1])
			if owed > 0:
				es._key_value(g, "Faveurs dues", str(owed))
		if not ro:
			if member:
				_action(es, "leave", "Quitter l'Amphictyonie (%s)" % GameData.format_amounts(Amphictyony.leave_cost(state, player)), Amphictyony.check_leave(state, player),
						SimCommands.amph_leave(player), "Partir coûte une somme qui grandit avec l'empire, et interdit le retour pendant 10 ans.")
			else:
				_action(es, "join", "Adhérer (%s)" % GameData.format_amounts(Amphictyony.join_cost(state, player)), Amphictyony.check_join(state, player),
						SimCommands.amph_join(player), "Seuls les membres votent, profitent des résolutions et accèdent au marché commun ; mais ils sont liés par le Nomos.")
				var obs := AmphInst.is_observer(state, player)
				_action(es, "observe", "Quitter le banc des observateurs" if obs else "Observer les séances", AmphInst.check_observe(state, player),
						SimCommands.amph_act(player, "observe"), "Un observateur ne vote pas, mais il suit les séances, peut appeler à l'aide et, s'il est victime, convoquer une session extraordinaire.")
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
	if AmphInst.special_on(state) or AmphInst.coal_on(state) or not AmphInst.open_trigs(state).is_empty():
		col.add_child(_crisis_block(es))
	col.add_child(_queue_block(es))
	if Amphictyony.is_member(state, player) and not ro:
		col.add_child(_propose_block(es))
	col.add_child(_inst_block(es))
	col.add_child(_power_block(es))
	col.add_child(_mutual_block(es))
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


## Auteur d'une proposition : « un siège voilé » pour un peuple au Siège voilé (sauf pour lui-même).
static func pwho(state: GameState, viewer: int, eid: int) -> String:
	if eid != viewer and AmphPower.veiled(state, eid):
		return "un siège voilé"
	return who(state, viewer, eid)


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
				pwho(state, player, int(p["by"])), who(state, player, int(s["pres"])), GameCalendar.date_string(int(s["end"])),
				(s["votes"] as Dictionary).size(), "s" if (s["votes"] as Dictionary).size() > 1 else ""], 13))
		if AmphPower.sees_tally(state, player):
			var tt := Amphictyony.tally(state)
			var cl := UiTheme.dim("Consensus calculé : le vrai décompte, à %d jours de la clôture : %d voix pour, %d contre." % [maxi(0, int(s["end"]) - state.tick), int(tt["pour"]), int(tt["contre"])], 14)
			cl.add_theme_color_override("font_color", UiTheme.GOLD)
			b.body.add_child(cl)
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
			# Haute Voûte, Arbitre, faveurs.
			var row3 := HFlowContainer.new()
			row3.add_theme_constant_override("h_separation", 8)
			if AmphInst.is_councillor(state, player):
				row3.add_child(_btn(es, "veto", "Veto", AmphInst.check_veto(state, player), SimCommands.amph_act(player, "veto"),
						"La proposition tombe sur-le-champ, quel que soit le vote. Un veto par décennie et par conseiller."))
			if AmphInst.arbiter(state) == player:
				row3.add_child(_btn(es, "close", "Clore le vote", AmphInst.check_close(state, player), SimCommands.amph_act(player, "close"),
						"L'Arbitre clôt le vote tout de suite ; on compte les voix telles qu'elles sont."))
			for d in AmphInst.debtors(state, player):
				row3.add_child(_btn(es, "call:%d" % int(d[0]), "Appeler la faveur de %s (%d)" % [who(state, player, int(d[0])), int(d[1])], AmphInst.check_call(state, player, int(d[0])),
						SimCommands.amph_act(player, "call", int(d[0])), "10 % de ses voix votent comme vous pour ce seul vote ; la faveur est consommée."))
			if row3.get_child_count() > 0:
				b.body.add_child(row3)
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
		var by := UiTheme.dim(pwho(state, player, int(p["by"])), 13)
		by.custom_minimum_size = Vector2(170, 0)
		row.add_child(by)
		var sup := UiTheme.dim("soutien %d voix" % Amphictyony.support_weight(state, p), 13)
		sup.custom_minimum_size = Vector2(120, 0)
		row.add_child(sup)
		if int(p.get("frozen", 0)) > state.tick:
			var fz := UiTheme.dim("gelée jusqu'au %s" % GameCalendar.date_string(int(p["frozen"])), 13)
			fz.add_theme_color_override("font_color", Color(0.55, 0.75, 0.95))
			row.add_child(fz)
		if not member:
			continue
		if AmphInst.is_councillor(state, player):
			row.add_child(_btn(es, "urgent:%d" % int(p["id"]), "Urgence", AmphInst.check_urgent(state, player, int(p["id"])), SimCommands.amph_act(player, "urgent", int(p["id"])),
					"Ouvre la séance tout de suite sur cette proposition. Une fois par décennie et par conseiller."))
		if AmphInst.arbiter(state) == player:
			row.add_child(_btn(es, "freeze:%d" % int(p["id"]), "Geler", AmphInst.check_freeze(state, player, int(p["id"])), SimCommands.amph_act(player, "freeze", int(p["id"])),
					"La proposition ne peut pas passer en séance pendant deux ans."))
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
			var cost := Amphictyony.prop_cost(state, "step", fid, dir, player) if bool(st[0]) else {}
			if not cost.is_empty():
				text += " (%s)" % GameData.format_amounts(cost)
			row.add_child(_btn(es, "propose:%s:%d" % [fid, dir], text, Amphictyony.check_propose(state, player, "step", fid, dir, -1, ""),
					SimCommands.amph_propose(player, "step", fid, dir), String(f[way].get("text", ""))))
	_inst_props(es, b)
	for t in Amphictyony.sanctionables(state):
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
		if Amphictyony.is_member(state, t) and Amphictyony.outlaw(state, t):
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
		if AmphPower.imperator(state) == m:
			tags.append("Impérateur")
		elif AmphInst.arbiter(state) == m:
			tags.append("Arbitre des étoiles")
		elif AmphInst.is_councillor(state, m):
			tags.append("Haute Voûte")
		if Amphictyony.president(state) == m:
			tags.append("président de séance")
		if Amphictyony.outlaw(state, m):
			tags.append("hors-la-loi")
		if Amphictyony.galactic_follower(state, m):
			tags.append("foi galactique")
		if AmphInst.medal_pct(state, m) > 0:
			tags.append("médaillé")
		if AmphPower.submitted(state, m):
			tags.append("vassal de la Cour")
		if AmphPower.veiled(state, m):
			tags.append("siège voilé")
		for x in Amphictyony.members(state):
			if x < m and AmphPower.conclave(state, x, m):
				tags.append("Conclave")
				break
		row.add_child(UiTheme.dim(", ".join(tags), 13))
	var obs := AmphInst.observers(state)
	if not obs.is_empty():
		var names := PackedStringArray()
		for o in obs:
			names.append(who(state, player, o))
		b.body.add_child(UiTheme.dim("Au banc des observateurs : %s." % ", ".join(names), 13))
	return b


## Propositions d'institutions et de grands travaux (dans le pupitre « Proposer »).
static func _inst_props(es: EmpireScreens, b: Widgets.Block) -> void:
	var state := es._state
	var player := es._player
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 6)
	b.body.add_child(row)
	var fl := Label.new()
	fl.text = "Institutions"
	fl.custom_minimum_size = Vector2(140, 0)
	fl.add_theme_font_size_override("font_size", 15)
	row.add_child(fl)
	var opts: Array = []
	if not AmphInst.council_on(state):
		opts.append(["council", "", 0, -1])
	else:
		opts.append(["council_size", "", 1, -1])
		opts.append(["council_size", "", -1, -1])
		if AmphInst.arbiter(state) < 0:
			for c in AmphInst.councillors(state):
				opts.append(["arbiter", "", 0, c])
		else:
			opts.append(["extend", "", 0, -1])
			opts.append(["defiance", "", 0, -1])
			opts.append(["term_lift", "", 0, -1])
			if AmphInst.arbiter(state) == player:
				opts.append(["full_powers", "", 0, -1])
	for o in opts:
		var p := {"kind": o[0], "by": player}
		p.merge(AmphInst.make_fields(state, String(o[0]), String(o[1]), int(o[2]), int(o[3])), true)
		var why := Amphictyony.check_propose(state, player, String(o[0]), String(o[1]), int(o[2]), int(o[3]), "")
		if String(o[0]) == "council_size" and why.begins_with("entre"):
			continue
		row.add_child(_btn(es, "inst:%s:%d:%d" % [String(o[0]), int(o[2]), int(o[3])], "%s (%s)" % [Amphictyony.cap(AmphInst.prop_label(state, p)), GameData.format_amounts(Amphictyony.prop_cost(state, String(o[0]), String(o[1]), int(o[2]), player))],
				why, SimCommands.amph_propose(player, String(o[0]), String(o[1]), int(o[2]), int(o[3])), AmphInst.prop_text(state, p)))
	var row2 := HFlowContainer.new()
	row2.add_theme_constant_override("h_separation", 8)
	b.body.add_child(row2)
	var wl := Label.new()
	wl.text = "Grands travaux"
	wl.custom_minimum_size = Vector2(140, 0)
	wl.add_theme_font_size_override("font_size", 15)
	row2.add_child(wl)
	for w: Dictionary in AmphInst.work_defs():
		var wid := String(w["id"])
		if AmphInst.work_done(state, wid):
			continue
		var p2 := {"kind": "work", "fam": wid, "by": player}
		row2.add_child(_btn(es, "work:%s" % wid, "%s (%s)" % [String(w["label"]), GameData.format_amounts(Amphictyony.prop_cost(state, "work", wid, 0, player))],
				Amphictyony.check_propose(state, player, "work", wid, 0, -1, ""), SimCommands.amph_propose(player, "work", wid), AmphInst.prop_text(state, p2)))


## La Haute Voûte et l'Arbitre des étoiles.
static func _inst_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var b := Widgets.Block.new("Haute Voûte et Arbitre des étoiles")
	if not AmphInst.council_on(state):
		var left := int(state.amph["founded"]) + int(AmphInst.idata()["council"]["after_days"]) - state.tick
		@warning_ignore("integer_division")
		var months := (left + 29) / 30
		b.body.add_child(UiTheme.paragraph("Pas encore de Haute Voûte. Après 10 ans d'Amphictyonie, une résolution peut la bâtir : ses sièges iront aux plus fortes voix, avec un veto, une procédure d'urgence et le droit de dénoncer%s." % (
				" (encore %d mois)" % months if left > 0 else ""), 760.0, 14))
		return b
	var cs := AmphInst.councillors(state)
	var names := PackedStringArray()
	for c in cs:
		names.append(who(state, player, c))
	b.body.add_child(UiTheme.paragraph("%d siège%s : %s. Sièges redistribués le %s." % [AmphInst.seats(state), "s" if AmphInst.seats(state) > 1 else "",
			", ".join(names) if not names.is_empty() else "personne", GameCalendar.date_string(int(state.amph["council"]["reseat"]))], 760.0, 14))
	var arb := AmphInst.arbiter(state)
	b.body.add_child(UiTheme.dim("Arbitre des étoiles : %s" % ("%s, jusqu'au %s" % [who(state, player, arb), GameCalendar.date_string(AmphInst.arbiter_until(state))] if arb >= 0 else "aucun"), 14))
	var den := PackedStringArray()
	for k in state.amph["den"]:
		if AmphInst.denounced(state, int(k)):
			den.append(who(state, player, int(k)))
	if not den.is_empty():
		var dl := UiTheme.dim("Dénoncés : %s." % ", ".join(den), 14)
		dl.add_theme_color_override("font_color", CONTRE)
		b.body.add_child(dl)
	var e := state.get_empire(player)
	if e == null:
		return b
	if AmphInst.is_councillor(state, player):
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 8)
		row.add_theme_constant_override("v_separation", 6)
		b.body.add_child(row)
		row.add_child(UiTheme.dim("Dénoncer (%s) :" % GameData.format_amounts(AmphInst.denounce_cost()), 14))
		var ks: Array = e.contacts.duplicate()
		ks.sort()
		for o in ks:
			var oe := state.get_empire(int(o))
			if oe == null or oe.eliminated or oe.is_npc() or AmphInst.denounced(state, int(o)):
				continue
			row.add_child(_btn(es, "denounce:%d" % int(o), oe.short_name(), AmphInst.check_denounce(state, player, int(o)), SimCommands.amph_act(player, "denounce", int(o)),
					"Pendant 5 ans, il devient passible de sanctions. Il ne vous le pardonnera pas de sitôt."))
	if arb == player:
		var ms := Amphictyony.members(state)
		for a in ms:
			for c in ms:
				if a < c and Combat.at_war(state, a, c):
					b.body.add_child(_btn(es, "truce:%d:%d" % [a, c], "Imposer une trêve à %s et %s (%s)" % [who(state, player, a), who(state, player, c), GameData.format_amounts(AmphInst.truce_cost())],
							AmphInst.check_truce(state, player, a, c), SimCommands.amph_act(player, "truce", a, c), "La guerre cesse : paix et trêve habituelle."))
	return b


## Crises, session extraordinaire et coalition.
static func _crisis_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var b := Widgets.Block.new("Crises")
	var live := state.get_empire(player) != null
	if AmphInst.special_on(state):
		var s := AmphInst.special(state)
		var t := AmphInst.trig(state, int(s["trig"]))
		var tl := Label.new()
		tl.text = "Session extraordinaire : faut-il une coalition contre %s ?" % who(state, player, int(s["target"]))
		tl.add_theme_font_size_override("font_size", 18)
		tl.add_theme_color_override("font_color", CONTRE)
		b.body.add_child(tl)
		var st := AmphInst.stally(state)
		b.body.add_child(UiTheme.dim("%s · convoquée par %s · clôture le %s · %d voix pour, %d contre" % [Amphictyony.cap(AmphInst.crisis_label(state, t)) if not t.is_empty() else "",
				who(state, player, int(s["by"])), GameCalendar.date_string(int(s["end"])), int(st["pour"]), int(st["contre"])], 13))
		if live and Amphictyony.is_member(state, player) and player != int(s["target"]):
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			b.body.add_child(row)
			var mine := AmphInst.svote_of(state, player)
			for v in [1, -1, 0]:
				var lab := "Pour (rejoindre la coalition)" if v == 1 else ("Contre" if v == -1 else "Abstention")
				row.add_child(_btn(es, "svote:%d" % v, ("● " if mine == v else "") + lab, AmphInst.check_svote(state, player, v), SimCommands.amph_act(player, "svote", v),
						"Si la coalition est votée, ceux qui ont voté pour entrent en guerre contre le fautif, sans parjure."))
	if AmphInst.coal_on(state):
		var c := AmphInst.coal(state)
		var names := PackedStringArray()
		for m in c["members"]:
			names.append(who(state, player, int(m)))
		b.body.add_child(UiTheme.paragraph("Coalition contre %s : %s. But : %s, avant le %s. Chantiers des coalisés 20 %% plus rapides." % [who(state, player, int(c["target"])), ", ".join(names),
				String(AmphInst.idata()["crisis"]["goals"][String(c["goal"])]), GameCalendar.date_string(int(c["end"]))], 760.0, 14))
	for t2: Dictionary in AmphInst.open_trigs(state):
		var row2 := HBoxContainer.new()
		row2.add_theme_constant_override("separation", 10)
		b.body.add_child(row2)
		var l := Label.new()
		l.text = Amphictyony.cap(AmphInst.crisis_label(state, t2))
		l.custom_minimum_size = Vector2(420, 0)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row2.add_child(l)
		if live:
			row2.add_child(_btn(es, "convene:%d" % int(t2["id"]), "Convoquer (%s)" % GameData.format_amounts(AmphInst.convene_cost()), AmphInst.check_convene(state, player, int(t2["id"])),
					SimCommands.amph_act(player, "convene", int(t2["id"])), "Session extraordinaire de 2 mois : faut-il former une coalition contre le fautif ?"))
	return b


## Aide d'urgence et grands travaux.
static func _mutual_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var b := Widgets.Block.new("Entraide et grands travaux")
	var e := state.get_empire(player)
	var member := Amphictyony.is_member(state, player)
	var step := int(AmphInst.idata()["aid"]["step"])
	var ks := (state.amph["aid"] as Dictionary).keys()
	ks.sort()
	for k in ks:
		var ai := AmphInst.aid_of(state, int(k))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		b.body.add_child(row)
		var l := Label.new()
		l.text = "Appel de %s : %d / %d %s (jusqu'au %s)" % [who(state, player, int(k)), int(ai["got"]), int(ai["need"]), GameData.resource_label(String(ai["res"])), GameCalendar.date_string(int(ai["end"]))]
		l.custom_minimum_size = Vector2(480, 0)
		row.add_child(l)
		if member and e != null and int(k) != player:
			row.add_child(_btn(es, "aid:%s" % k, "Donner %d" % step, AmphInst.check_aid_give(state, player, int(k), step), SimCommands.amph_act(player, "aid_give", int(k), step),
					"Chaque tranche vaut une faveur, et un bon souvenir."))
	if e != null and (member or AmphInst.is_observer(state, player)):
		var row2 := HBoxContainer.new()
		row2.add_theme_constant_override("separation", 8)
		b.body.add_child(row2)
		for res in AmphInst.idata()["aid"]["res"]:
			row2.add_child(_btn(es, "ask:%s" % String(res), "Appeler à l'aide (%s)" % GameData.resource_label(String(res)), AmphInst.check_aid_ask(state, player, String(res)),
					SimCommands.amph_act(player, "aid_ask", -1, -1, String(res)), "Quand vous êtes presque à sec : les membres peuvent vous envoyer 300 en 6 mois."))
	if AmphInst.work_on(state):
		var wk := AmphInst.work(state)
		var w := AmphInst.work_def(String(wk["id"]))
		var row3 := HBoxContainer.new()
		row3.add_theme_constant_override("separation", 10)
		b.body.add_child(row3)
		var wl := Label.new()
		wl.text = "Grand chantier : %s, %d / %d %s (jusqu'au %s)" % [String(w["label"]), AmphInst.work_total(state), int(w["need"]), GameData.resource_label(String(w["res"])), GameCalendar.date_string(int(wk["end"]))]
		wl.custom_minimum_size = Vector2(480, 0)
		wl.tooltip_text = String(w.get("text", ""))
		wl.mouse_filter = Control.MOUSE_FILTER_STOP
		row3.add_child(wl)
		if member and e != null:
			for n in [step, step * 4]:
				row3.add_child(_btn(es, "give:%d" % n, "Donner %d" % n, AmphInst.check_work_give(state, player, n), SimCommands.amph_act(player, "work_give", n),
						"Les trois plus gros donateurs reçoivent une médaille : des voix en plus, pour toujours."))
	for d: Dictionary in state.amph["done"]:
		var w2 := AmphInst.work_def(String(d["id"]))
		var md := PackedStringArray()
		var metals := ["or", "argent", "bronze"]
		for i in (d["medals"] as Array).size():
			md.append("%s %s" % [metals[i], who(state, player, int(d["medals"][i]))])
		b.body.add_child(UiTheme.dim("%s, achevé le %s (%s)" % [String(w2.get("label", "?")), GameCalendar.date_string(int(d["day"])), ", ".join(md)], 14))
	if b.body.get_child_count() == 0:
		b.body.add_child(UiTheme.dim("Aucun appel à l'aide, aucun grand chantier.", 14))
	return b


## Lot 3 : pleins pouvoirs, Chancelier des étoiles, souveraineté, talents de peuple.
static func _power_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var b := Widgets.Block.new("Pouvoir et légitimité")
	var e := state.get_empire(player)
	var member := Amphictyony.is_member(state, player)
	# Impérateur.
	if AmphPower.imp_on(state):
		var im: Dictionary = state.amph["imp"]
		var subs := PackedStringArray()
		for s in im["sub"]:
			subs.append(who(state, player, int(s)))
		var rebs := PackedStringArray()
		for r in im["reb"]:
			rebs.append(who(state, player, int(r)))
		b.body.add_child(UiTheme.paragraph("Impérateur : %s, autorité %d / %d. Vassaux : %s. Rebelles : %s.%s" % [who(state, player, AmphPower.imperator(state)), AmphPower.authority(state),
				int(AmphPower.pdata()["auth_max"]), ", ".join(subs) if not subs.is_empty() else "aucun", ", ".join(rebs) if not rebs.is_empty() else "aucun",
				(" Réponse attendue avant le %s ; sans réponse, on se soumet." % GameCalendar.date_string(int(im["until"]))) if AmphPower.choosing(state) else ""], 760.0, 14))
		if e != null and member and player != AmphPower.imperator(state):
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			b.body.add_child(row)
			if not AmphPower.submitted(state, player):
				row.add_child(_btn(es, "submit", "Se soumettre", AmphPower.check_submit(state, player), SimCommands.amph_act(player, "submit"),
						"Tribut de %s par mois ; vous entrez en guerre aux côtés de la Cour quand on l'attaque." % GameData.format_amounts(AmphPower.pdata()["tribute"])))
			row.add_child(_btn(es, "rebel", "Se soulever", AmphPower.check_rebel(state, player), SimCommands.amph_act(player, "rebel"),
					"Vous quittez l'Amphictyonie (retour interdit 10 ans) et entrez en guerre contre l'Impérateur et ses vassaux. Chaque mois de résistance lui coûte de l'autorité."))
	elif AmphPower.life(state):
		b.body.add_child(UiTheme.dim("L'Arbitre des étoiles (%s) siège à vie. Il peut réclamer les pleins pouvoirs." % who(state, player, AmphInst.arbiter(state)), 14))
	# Chancelier des étoiles.
	var cd := AmphPower.cdata()
	if AmphPower.dip_enabled(state):
		if AmphPower.chan_on(state):
			var c := AmphPower.chan(state)
			var cands: Array = c["cands"]
			b.body.add_child(UiTheme.paragraph("Élection du Chancelier des étoiles : %s contre %s, clôture le %s. Il faut %d %% de toutes les voix de l'assemblée (abstentions comprises)." % [
					who(state, player, int(cands[0])), who(state, player, int(cands[1])), GameCalendar.date_string(int(c["end"])), int(cd["win_pct"])], 760.0, 14))
			if e != null and member and not cands.has(player):
				var row2 := HBoxContainer.new()
				row2.add_theme_constant_override("separation", 8)
				b.body.add_child(row2)
				var mine := AmphPower.cvote_of(state, player)
				for x in cands + [-1]:
					var lab := ("Voter %s" % who(state, player, int(x))) if int(x) >= 0 else "S'abstenir"
					row2.add_child(_btn(es, "cvote:%d" % int(x), ("● " if mine == int(x) else "") + lab, AmphPower.check_cvote(state, player, int(x)), SimCommands.amph_act(player, "cvote", int(x)),
							"Vote secret, modifiable jusqu'à la clôture."))
		else:
			var why := AmphPower.check_ready(state)
			b.body.add_child(UiTheme.dim("Prochaine élection du Chancelier des étoiles : le %s%s." % [GameCalendar.date_string(AmphPower.next_election(state)),
					(" (pour l'heure, %s)" % why) if why != "" else ""], 14))
		if not AmphPower.dip(state).is_empty():
			var d := AmphPower.dip(state)
			if int(d["war"]) > 0:
				var wl := UiTheme.dim("Dernière Guerre : %s contre %s, jusqu'au %s." % [who(state, player, int(d["eid"])), who(state, player, int(d["loser"])), GameCalendar.date_string(int(d["war_end"]))], 14)
				wl.add_theme_color_override("font_color", CONTRE)
				b.body.add_child(wl)
			elif AmphPower.pending_verdict(state):
				b.body.add_child(UiTheme.dim("%s est élu Chancelier ; %s peut refuser le verdict jusqu'au %s." % [who(state, player, int(d["eid"])), who(state, player, int(d["loser"])), GameCalendar.date_string(int(d["until"]))], 14))
				if int(d["loser"]) == player and e != null:
					var row3 := HBoxContainer.new()
					row3.add_theme_constant_override("separation", 8)
					b.body.add_child(row3)
					row3.add_child(_btn(es, "accept", "S'incliner", AmphPower.check_accept(state, player), SimCommands.amph_act(player, "accept"), "Le Chancelier élu gagne la partie (avec ses alliés)."))
					row3.add_child(_btn(es, "refuse", "Refuser le verdict", AmphPower.check_refuse(state, player), SimCommands.amph_act(player, "refuse"),
							"La Dernière Guerre : ceux qui ont voté pour l'élu marchent contre vous. Tenez votre capitale 10 ans, et le titre retourne aux archives."))
	# Souveraineté et conflits de lois.
	if e != null and member and state.politics_on:
		for c in AmphPower.conflicts(state, player):
			var fl := UiTheme.dim("Votre loi %s se heurte au Nomos (%s) : %d de stabilité dans tout l'empire." % [String(Laws.law_def(String(c["law"])).get("label", "")),
					String(Amphictyony.family_def(String(c["fam"]))["label"]), int(AmphPower.poldata()["conflict_stability"])], 14)
			fl.add_theme_color_override("font_color", CONTRE)
			b.body.add_child(fl)
		if Laws.is_enacted(state, player, "souverainete"):
			var row4 := HFlowContainer.new()
			row4.add_theme_constant_override("h_separation", 8)
			b.body.add_child(row4)
			row4.add_child(UiTheme.dim("Invoquer sa souveraineté :", 14))
			for f: Dictionary in Amphictyony.family_defs():
				var fid := String(f["id"])
				if Amphictyony.fam_value(state, fid) == 0:
					continue
				var lab2 := String(f["label"]) + (" (jusqu'au %s)" % GameCalendar.date_string(int(state.amph["sov"][str(player)][fid])) if AmphPower.sovereign(state, player, fid) else "")
				row4.add_child(_btn(es, "sov:%s" % fid, lab2, AmphPower.check_sovereign(state, player, fid), SimCommands.amph_act(player, "sovereign", -1, -1, fid),
						"Un an sans les effets ni les interdits de cette famille. Une fois par an ; les autres membres vous en veulent."))
	# Talents de peuple.
	if e != null:
		for tl: Dictionary in AmphPower.talents_of(state, player):
			b.body.add_child(UiTheme.paragraph("%s : %s" % [String(tl["label"]), String(tl["text"])], 760.0, 14))
			match String(tl["id"]):
				"anatheme":
					var row5 := HFlowContainer.new()
					row5.add_theme_constant_override("h_separation", 8)
					b.body.add_child(row5)
					var ks: Array = e.contacts.duplicate()
					ks.sort()
					for o in ks:
						var oe := state.get_empire(int(o))
						if oe == null or oe.eliminated or oe.is_npc():
							continue
						if AmphPower.check_anathema(state, player, int(o)) == "":
							row5.add_child(_btn(es, "anath:%d" % int(o), "Anathème contre %s" % oe.short_name(), "", SimCommands.amph_act(player, "anathema", int(o)),
									"Une session extraordinaire s'ouvre contre lui (%s)." % GameData.format_amounts(tl["cost"])))
				"plus_fort":
					var h := AmphPower.duel_target(state, player)
					if not h.is_empty():
						b.body.add_child(_btn(es, "duel", "Duel de champions contre « %s »" % Amphictyony.prop_label(state, h["prop"]), AmphPower.check_duel(state, player), SimCommands.amph_act(player, "duel"),
								"Si votre flotte pèse plus que celle de son auteur, la résolution est abrogée (%s)." % GameData.format_amounts(tl["cost"])))
	if b.body.get_child_count() == 0:
		b.body.add_child(UiTheme.dim("Ni Impérateur, ni élection en vue.", 14))
	return b
