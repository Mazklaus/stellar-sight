class_name PrivateUi
extends RefCounted
## Onglet « Privé » de l'écran Commerce (C ; voir Private, étude « Économie privée », prop. 7).
## Caisse privée, confiance des investisseurs (et ses raisons), bénéfice et impôt, fret et passagers ;
## leviers de l'État (subventionner, comptabilité créative, réquisition, contrats, priorité de la
## guilde) ; comptes du mois ; stations et chantiers privés ; gisements (licence, commande d'État,
## interdiction) ; vaisseaux commandés au privé ; compagnies (prospérité, charte, dirigeant,
## nationaliser, actions) ; filiales (ouvrir, exproprier, confisquer) ; zones militaires ; repaires
## des syndicats du crime. Lit l'état, n'émet que des ordres « private ».

const W := 760.0
const INK := Color(0.9, 0.72, 0.38)


static func build(es: EmpireScreens, col: VBoxContainer) -> void:
	var state := es._state
	var player := es._player
	if not Private.applies(state, player):
		col.add_child(UiTheme.dim("Pas de secteur privé dans cet empire.", 14))
		return
	col.add_child(_summary_block(es))
	col.add_child(_accounts_block(es))
	col.add_child(_stations_block(es))
	col.add_child(_mines_block(es))
	if not Private.planned(state, player):
		col.add_child(_ships_block(es))
	if Private.full(state):
		col.add_child(_companies_block(es))
		var fb := _foreign_block(es)
		if fb != null:
			col.add_child(fb)
		col.add_child(_zones_block(es))
		var cb := _crime_block(es)
		if cb != null:
			col.add_child(cb)


static func signature(es: EmpireScreens) -> String:
	var state := es._state
	if state.private.is_empty():
		return ""
	var en := Private.entry(state, es._player)
	return "%d|%d|%d|%d|%d|%d|%s|%s|%d" % [int(en.get("cap", 0)), int(en.get("conf", 0)), int(en.get("req", 0)), int(en.get("contract", 0)),
			(en.get("lic", []) as Array).size(), (en.get("q", []) as Array).size(), str(en.get("block", [])), String(en.get("focus", "")),
			hash([state.private.get("co", {}), state.private.get("br", {}), state.private.get("zone", {}), state.private.get("crime", {}), en.get("orders", [])])]


static func _ro(es: EmpireScreens) -> bool:
	return es._state.get_empire(es._player) == null


static func _button(es: EmpireScreens, row: Container, key: String, text: String, act: String, a := -1, b := -1, s := "") -> Button:
	var bt := Button.new()
	bt.focus_mode = Control.FOCUS_NONE
	bt.add_theme_font_size_override("font_size", 12)
	bt.text = text
	var player := es._player
	var why := Private.check(es._state, player, act, a, b, s) if not _ro(es) else "Spectateur"
	bt.disabled = why != ""
	bt.tooltip_text = why
	bt.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.private_act(player, act, a, b, s)))
	row.add_child(bt)
	es.trade_buttons[key] = bt
	return bt


static func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	return row


static func _label(text: String, width := 0.0, color := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	if width > 0:
		l.custom_minimum_size = Vector2(width, 0)
	if color.a > 0:
		l.add_theme_color_override("font_color", color)
	return l


static func _parts_tip(title: String, parts: Array) -> String:
	var lines := PackedStringArray([title])
	for p in parts:
		lines.append("  %+d  %s" % [int(p[1]), String(p[0])])
	return "\n".join(lines)


# --- Synthèse et leviers ----------------------------------------------------------------------

static func _summary_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var en := Private.entry(state, player)
	var b := Widgets.Block.new("Secteur privé (%s)" % String(Private.mode_defs().filter(func(m: Dictionary) -> bool: return String(m["id"]) == Private.mode(state))[0]["label"]).to_lower())
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 24)
	b.body.add_child(g)
	var conf := int(en.get("conf", 0))
	var items := [
		["Caisse privée", "%d énergie" % int(en.get("cap", 0)), ""],
		["Confiance", "%d / 100 (cible %d)" % [conf, Private.confidence_target(state, player)], _parts_tip("Confiance des investisseurs, cible du mois :", Private.confidence_parts(state, player))],
		["Bénéfice du mois", "%+d" % int(en.get("profit", 0)), ""],
		["Impôt sur les bénéfices", "%d %% (%d versés)" % [Private.tax_rate(state, player), int(en.get("tax", 0))], "Selon le cran de la fiscalité ; une part peut fuir dans la corruption."],
		["Cargos", "%d / %d (fret %d %%)" % [Private.usable_cargos(state, player), Private.cargo_need(state, player), Private.freight_pct(state, player)], "Besoin : 1 pour 2 colonies ou routes, 1 par station privée. Sous le besoin, les mines livrent moins et les chantiers lointains ralentissent."],
		["Paquebots", "%d / %d (%d %%)" % [int(en.get("liners", 0)), Private.liner_need(state, player), Private.liner_pct(state, player)], "Assez de paquebots : migration +%d sauts, tourisme plein." % Private.c_int("liner", "jumps")],
	]
	for it in items:
		var k := _label(String(it[0]), 0, UiTheme.TEXT_DIM)
		g.add_child(k)
		var v := _label(String(it[1]))
		v.theme_type_variation = &"Numbers"
		if String(it[2]) != "":
			v.tooltip_text = String(it[2])
			v.mouse_filter = Control.MOUSE_FILTER_STOP
		if String(it[0]) == "Confiance":
			v.add_theme_color_override("font_color", Color(0.42, 0.75, 0.55) if conf >= 60 else (Color(0.85, 0.33, 0.31) if conf < 25 else Color(0.86, 0.76, 0.36)))
		g.add_child(v)
	var hint := "Le privé investit seul chaque mois selon sa caisse et la confiance : cargos, paquebots, mines sous licence, stations touristiques, bâtiments civils."
	if conf < Private.c_int("confidence", "min_invest"):
		hint = "Confiance trop basse : le privé n'investit plus rien."
	if Private.planned(state, player):
		hint = "Économie planifiée : l'activité privée va au Trésor, sans investissement ni compagnie nouvelle."
	b.body.add_child(UiTheme.paragraph(hint, W, 13))
	var row := _row()
	b.body.add_child(row)
	_button(es, row, "subsidize", "Subventionner (%d énergie)" % Private.c_int("subsidy", "energy"), "subsidize")
	_button(es, row, "creative", "Comptabilité créative", "creative")
	if Private.full(state):
		var req := int(en.get("req", 0)) > 0
		if req:
			_button(es, row, "requisition", "Rendre les cargos réquisitionnés (%d)" % int(en["req"]), "requisition", 0)
		else:
			_button(es, row, "requisition", "Réquisitionner (indemnisé)", "requisition", 1, 1)
			_button(es, row, "requisition_free", "Réquisitionner sans payer", "requisition", 1, 0)
		var on := int(en.get("contract", 0)) > 0
		_button(es, row, "contract", "Rompre le contrat de ravitaillement" if on else "Contrat de ravitaillement", "contract", 0 if on else 1)
	if bool(Private.talent(state, player).get("guild", false)):
		var frow := _row()
		b.body.add_child(frow)
		frow.add_child(_label("Priorité de la guilde :", 0, UiTheme.TEXT_DIM))
		for f: Dictionary in Private.data().get("focus", []):
			var bt := _button(es, frow, "focus:" + String(f["id"]), String(f["label"]), "focus", -1, -1, String(f["id"]))
			bt.toggle_mode = true
			bt.button_pressed = String(en.get("focus", "")) == String(f["id"])
	for tl in Private.talent_labels(state, player):
		b.body.add_child(UiTheme.paragraph("%s : %s" % [tl[0], tl[1]], W, 12))
	return b


static func _accounts_block(es: EmpireScreens) -> Control:
	var en := Private.entry(es._state, es._player)
	var b := Widgets.Block.new("Comptes du privé (mois dernier)")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	b.body.add_child(row)
	for side in [["Recettes", en.get("rev", {})], ["Dépenses", en.get("exp", {})]]:
		var c := VBoxContainer.new()
		c.custom_minimum_size = Vector2(340, 0)
		row.add_child(c)
		c.add_child(_label(String(side[0]), 0, INK))
		var d: Dictionary = side[1]
		if d.is_empty():
			c.add_child(UiTheme.dim("rien", 13))
		for k in d:
			var r := _row()
			r.add_child(_label(String(k), 260))
			var v := _label("%d" % int(d[k]))
			v.theme_type_variation = &"Numbers"
			r.add_child(v)
			c.add_child(r)
	var to: Dictionary = en.get("to", {})
	if not to.is_empty():
		b.body.add_child(UiTheme.paragraph("Versé à l'État au prochain bilan : %s." % GameData.format_amounts(to), W, 13))
	return b


# --- Stations, gisements, vaisseaux ------------------------------------------------------------

static func _stations_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var en := Private.entry(state, player)
	var st := Private.stations_of(state, player)
	var b := Widgets.Block.new("Stations privées (%d)" % st.size())
	for pid in st:
		var s := Private.station(state, pid)
		var sid := int(s["sid"])
		var mine := String(s["k"]) == "mine"
		var what := ""
		if mine:
			var y := Private.mine_yield(state, pid)
			what = "Station minière, %s : %s pour l'État, %d pour le privé" % [state.galaxy.get_planet(pid).display_name(state.galaxy), GameData.format_amounts(y["state"]), int(y["private"])]
		else:
			what = "Station touristique, %s : %d énergie par mois" % [state.galaxy.systems[sid].system_name, Private.resort_income(state, pid)]
		if Private.in_zone(state, sid):
			what += " (zone militaire : à l'arrêt)"
		b.body.add_child(_label(what))
	for it: Dictionary in en.get("q", []):
		var k := String(it["k"])
		var label := {"cargo": "Cargo", "liner": "Paquebot", "mine": "Station minière", "resort": "Station touristique"}.get(k, k) as String
		if k == "mine":
			label += " (%s)" % state.galaxy.get_planet(int(it["pid"])).display_name(state.galaxy)
		elif k == "resort":
			label += " (%s)" % state.galaxy.systems[int(it["sid"])].system_name
		b.body.add_child(UiTheme.dim("En chantier : %s, livré le %s" % [label, GameCalendar.date_string(int(it["done"]))], 13))
	for pid in (en.get("pb", {}) as Dictionary):
		var bid := Private.private_building(state, int(pid))
		if bid != "":
			b.body.add_child(UiTheme.dim("Le privé bâtit %s sur %s" % [String(GameData.building(bid).get("label", bid)), state.galaxy.get_planet(int(pid)).display_name(state.galaxy)], 13))
	if st.is_empty() and (en.get("q", []) as Array).is_empty():
		b.body.add_child(UiTheme.dim("Aucune station : accordez des licences minières, le privé fera le reste.", 13))
	return b


static func _mines_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var en := Private.entry(state, player)
	var sites := Private.mine_sites(state, player)
	var b := Widgets.Block.new("Gisements libres (%d)" % sites.size())
	b.body.add_child(UiTheme.paragraph("Licence : %s, le privé y bâtira une station minière à ses frais. Commande d'État : vous payez la station (%d énergie), il la bâtit tout de suite. Interdire : le privé ne s'installe pas de lui-même dans ce système." % [
			GameData.format_amounts(Private.cfg("mine")["licence"]), Private.order_price(state, player)], W, 13))
	for pid in sites.slice(0, 10):
		var row := _row()
		var y := Private.mine_yield(state, pid)
		var sid := state.galaxy.get_planet(pid).system_id
		var lic := (en.get("lic", []) as Array).has(pid)
		row.add_child(_label("%s : %s%s" % [state.galaxy.get_planet(pid).display_name(state.galaxy), GameData.format_amounts(y["state"]), " (licence)" if lic else ""], 340))
		if not lic:
			_button(es, row, "licence:%d" % pid, "Licence", "licence", pid)
		_button(es, row, "order:%d" % pid, "Commande d'État", "order", pid)
		var blocked := (en.get("block", []) as Array).has(sid)
		_button(es, row, "block:%d" % sid, "Autoriser" if blocked else "Interdire", "block", sid)
		b.body.add_child(row)
	return b


static func _ships_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var en := Private.entry(state, player)
	var b := Widgets.Block.new("Vaisseaux commandés au privé")
	b.body.add_child(UiTheme.paragraph("Chantiers loués : un vaisseau coûte %+d %% mais sort %d %% plus vite, sans occuper le chantier de la colonie (une commande à la fois par colonie)." % [
			Private.c_int("ship_order", "cost_pct"), -Private.c_int("ship_order", "days_pct")], W, 13))
	for o: Dictionary in en.get("orders", []):
		b.body.add_child(UiTheme.dim("%s pour %s, livré le %s" % [String(GameData.ship(String(o["ship"])).get("label", o["ship"])),
				state.galaxy.get_planet(int(o["pid"])).display_name(state.galaxy), GameCalendar.date_string(int(o["done"]))], 13))
	var cap := FactionTraits.capital_system(state, player)
	var pid := -1
	for c in Private.colonies_of(state, player):
		if c.is_colony() and state.galaxy.get_planet(c.planet_id).system_id == cap:
			pid = c.planet_id
			break
	if pid < 0:
		return b
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	b.body.add_child(row)
	row.add_child(_label("À la capitale :", 0, UiTheme.TEXT_DIM))
	var n := 0
	for sh in Designs.buildable_ids(state, player):
		if n >= 6:
			break
		if Private.check_ship_order(state, player, pid, sh) == "le privé ne construit ni vaisseaux colons ni méga-vaisseaux" or not Fleets.ship_unlocked(state, player, sh):
			continue
		var bt := _button(es, row, "ship:%s" % sh, "%s (%s)" % [String(GameData.ship(sh).get("label", sh)), GameData.format_amounts(Private.ship_order_cost(state, player, sh))], "ship", pid, -1, sh)
		bt.custom_minimum_size = Vector2(0, 0)
		n += 1
	return b


# --- Compagnies et filiales --------------------------------------------------------------------

static func _companies_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var mine := Private.companies_of(state, player)
	var b := Widgets.Block.new("Compagnies (%d / %d) — chartes %d / %d" % [mine.size(), Private.company_max(state, player), Private.charters_used(state, player), Private.charter_max(state, player)])
	if mine.is_empty():
		b.body.add_child(UiTheme.dim("Aucune compagnie : elles naissent quand la caisse privée atteint %d énergie." % Private.c_int("companies", "found_at"), 13))
	for c in mine:
		var cid := int(c["id"])
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		b.body.add_child(box)
		var head := _row()
		box.add_child(head)
		var nl := _label(String(c["n"]), 330, INK)
		head.add_child(nl)
		var pr := int(c["pr"])
		var pl := _label("%s · siège %s · prospérité %d" % [Private.sector_label(String(c["sec"])), state.galaxy.systems[int(c["hq"])].system_name, pr])
		pl.add_theme_color_override("font_color", Color(0.42, 0.75, 0.55) if pr >= Private.c_int("companies", "bonus_from") else (Color(0.85, 0.33, 0.31) if pr < Private.c_int("companies", "ruin_below") else UiTheme.TEXT))
		pl.tooltip_text = _parts_tip("Prospérité visée : %d (effet du secteur à partir de %d : %s)" % [Private.company_target(state, c), Private.c_int("companies", "bonus_from"), String(Private.sector_def(String(c["sec"])).get("text", ""))], Private.company_parts(state, c))
		pl.mouse_filter = Control.MOUSE_FILTER_STOP
		head.add_child(pl)
		var info := PackedStringArray()
		if bool(c.get("nat", false)):
			info.append("nationalisée")
		else:
			info.append("charte : %s" % Private.charter_label(String(c.get("ch", ""))))
		var d: Dictionary = c.get("dir", {})
		if not d.is_empty():
			info.append("dirigeant : %s (%s)" % [String(d["name"]), String(Private.trait_def(String(d.get("trait", ""))).get("label", "?"))])
		var hid := int(c.get("house", -1))
		if hid >= 0 and not state.court.is_empty():
			info.append("aux mains de %s" % String(Court.house(state, player, hid).get("name", "?")))
		var sold := 0
		for k in c.get("sh", {}):
			sold += int(c["sh"][k])
		if sold > 0:
			info.append("%d0 %% des parts à l'étranger" % sold)
		box.add_child(UiTheme.dim(" · ".join(info), 13))
		if bool(c.get("nat", false)):
			continue
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 6)
		box.add_child(row)
		for ch: Dictionary in Private.cfg("charters").get("list", []):
			var chid := String(ch["id"])
			if chid == String(c.get("ch", "")):
				continue
			var bt := _button(es, row, "charter:%d:%s" % [cid, chid], String(ch["label"]), "charter", cid, -1, chid)
			if bt.tooltip_text == "":
				bt.tooltip_text = String(ch.get("text", ""))
		if String(c.get("ch", "")) != "":
			_button(es, row, "charter:%d:" % cid, "Retirer la charte", "charter", cid, -1, "")
		if not d.is_empty():
			_button(es, row, "recruit:%d" % cid, "Recruter le dirigeant", "recruit", cid)
		_button(es, row, "nationalize:%d" % cid, "Nationaliser (%d influence)" % Private.c_int("nationalize", "influence"), "nationalize", cid)
		# Filiale : la colonie la plus peuplée d'un partenaire.
		var target := -1
		var pop := 0
		for o in Trade.partners(state, player):
			for col in Private.colonies_of(state, int(o)):
				if col.is_colony() and col.population > pop and not (state.private["br"] as Dictionary).has(str(col.planet_id)):
					pop = col.population
					target = col.planet_id
		if target >= 0:
			_button(es, row, "branch:%d" % cid, "Filiale à %s (%d énergie privée)" % [state.galaxy.get_planet(target).display_name(state.galaxy), Private.branch_cost(state, cid, target)], "branch", cid, target)
	return b


static func _foreign_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var rows := []
	for c in Private.all_companies(state):
		if int(c["o"]) != player and Trade.tier(state, player, int(c["o"])) >= 1:
			rows.append(c)
	var abroad := []
	var home := []
	for k in state.private.get("br", {}):
		var br: Dictionary = state.private["br"][k]
		var col: Colony = state.colonies.get(int(k))
		if col == null:
			continue
		if int(br["o"]) == player:
			abroad.append(int(k))
		elif col.owner == player:
			home.append(int(k))
	if rows.is_empty() and abroad.is_empty() and home.is_empty():
		return null
	var b := Widgets.Block.new("Filiales et actions")
	for pid in abroad:
		b.body.add_child(_label("Notre filiale à %s : %d énergie par mois" % [state.galaxy.get_planet(pid).display_name(state.galaxy), Private.branch_value(state, pid)]))
	for pid in home:
		var br: Dictionary = state.private["br"][str(pid)]
		var row := _row()
		row.add_child(_label("Filiale de %s à %s" % [String(Private.company(state, int(br["c"])).get("n", "?")), state.galaxy.get_planet(pid).display_name(state.galaxy)], 420))
		_button(es, row, "expropriate:%d" % pid, "Exproprier", "expropriate", pid)
		b.body.add_child(row)
	var me := state.get_empire(player)
	if me != null:
		for o in me.wars:
			if not Private.branches_in(state, player, int(o)).is_empty():
				var row2 := _row()
				_button(es, row2, "confiscate:%d" % int(o), "Confisquer les comptes de %s" % state.get_empire(int(o)).short_name(), "confiscate", int(o))
				b.body.add_child(row2)
	for c in rows.slice(0, 8):
		var row3 := _row()
		var mine_sh := int((c.get("sh", {}) as Dictionary).get(str(player), 0))
		row3.add_child(_label("%s (%s, prospérité %d)%s" % [String(c["n"]), state.get_empire(int(c["o"])).short_name(), int(c["pr"]), (" — vous : %d0 %%" % mine_sh) if mine_sh > 0 else ""], 420))
		_button(es, row3, "shares:%d" % int(c["id"]), "Acheter 10 %% (%d énergie)" % Private.share_price(c), "shares", int(c["id"]))
		b.body.add_child(row3)
	return b


# --- Zones militaires, crime -------------------------------------------------------------------

static func _zones_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var b := Widgets.Block.new("Zones militaires")
	b.body.add_child(UiTheme.paragraph("Un système en zone militaire est interdit aux civils : pas de cargo perdu sur ses routes, mais ses stations privées s'arrêtent et aucune station touristique ne s'y ouvre.", W, 13))
	var list := []
	for sid in Stability.systems_of(state, player):
		var stations := 0
		for k in ["mine", "resort"]:
			if Private.station_at(state, sid, k) >= 0:
				stations += 1
		list.append([0 if Private.in_zone(state, sid) else 1, -Trade.risk_at(state, sid), -stations, sid])
	list.sort()
	for it in list.slice(0, 6):
		var sid := int(it[3])
		var row := _row()
		row.add_child(_label("%s (risque pirate %d)" % [state.galaxy.systems[sid].system_name, Trade.risk_at(state, sid)], 340))
		_button(es, row, "zone:%d" % sid, "Lever la zone" if Private.in_zone(state, sid) else "Déclarer zone militaire", "zone", sid)
		b.body.add_child(row)
	return b


static func _crime_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var dens := PrivateBridges.dens_of(state, player)
	if dens.is_empty():
		return null
	var b := Widgets.Block.new("Syndicats du crime (%d)" % dens.size())
	var tol := PrivateBridges.tolerated(state, player)
	b.body.add_child(UiTheme.paragraph("Chaque repaire vole de l'énergie et nourrit la corruption ; il essaime une fois l'an. Descente de police : %d influence, %d %% de réussite." % [
			Private.c_int("crime", "raid_influence"), Private.c_int("crime", "raid_pct")] if not tol else "On s'arrange avec le milieu : les repaires ne volent rien et rapportent un peu.", W, 13))
	for sid in dens:
		var row := _row()
		row.add_child(_label("%s : %s" % [state.galaxy.systems[sid].system_name, "toléré" if tol else "-%d énergie par mois" % PrivateBridges.den_theft(state, sid)], 340))
		_button(es, row, "raid:%d" % sid, "Descente de police", "raid", sid)
		b.body.add_child(row)
	return b
