class_name GoodsScreen
extends RefCounted
## Onglets Ressources et Marché de l'écran Commerce (voir Goods).
## Ressources : vos luxes (effet, gisements ou licence, monopole, vente de licences ouverte ou fermée),
## les licences vendues et achetées, les luxes à acheter chez vos partenaires, vos stratégiques et les
## monopoles de la galaxie. Marché : achats et ventes contre de l'énergie, ordres mensuels, puis les
## échanges avec les empires (propositions reçues, contrats en cours, brouillon d'une proposition) ;
## lot 2B : tendances des prix, Bourse galactique (marché commun, vaisseaux d'occasion) et marché noir
## des ports francs pirates.

const DURATIONS := [[0, "En une fois"], [12, "Chaque mois, 1 an"], [60, "Chaque mois, 5 ans"], [120, "Chaque mois, 10 ans"]]
const STEPS := [10, 100]


static func _ro(es: EmpireScreens) -> bool:
	return es._state.get_empire(es._player) == null


static func _btn(es: EmpireScreens, text: String, why: String, cmd: Dictionary, key: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.disabled = why != "" or _ro(es)
	b.tooltip_text = why
	b.pressed.connect(func() -> void: es.command_requested.emit(cmd))
	es.trade_buttons[key] = b
	return b


static func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	return row


static func _label(text: String, width := 0.0, size := 14, col := UiTheme.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if width > 0.0:
		l.custom_minimum_size = Vector2(width, 0)
		l.clip_text = true
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


static func _name(state: GameState, eid: int) -> String:
	var e := state.get_empire(eid)
	return e.display_name() if e else "?"


# --- Ressources --------------------------------------------------------------------------------

static func build_resources(es: EmpireScreens, col: VBoxContainer) -> void:
	var state := es._state
	var player := es._player
	if state.goods.is_empty() or not Goods.active(state):
		col.add_child(UiTheme.paragraph("Cette partie se joue sans luxes ni stratégiques (réglage de Nouvelle partie).", 760.0, 14))
		return
	var mine := Widgets.Block.new("Vos luxes (%d sur %d)" % [Goods.luxuries_of(state, player).size(), Goods.luxury_ids().size()])
	col.add_child(mine)
	mine.body.add_child(UiTheme.paragraph("Le premier exemplaire de chaque luxe, gisement ou licence, donne de la stabilité dans tous vos systèmes et son effet ; chaque gisement de plus rapporte %d énergie par mois." % int(Goods.data()["extra_energy"]), 760.0, 13))
	var own := Goods.owned(state, player)
	var bought := Goods.licences_bought(state, player)
	for g in Goods.luxury_ids():
		var n := int(own.get(g, 0))
		if n <= 0 and not bought.has(g):
			continue
		var d := Goods.luxury(g)
		var row := _row()
		var nl := _label(Goods.label(g), 210.0, 16, Color(0.95, 0.82, 0.5))
		nl.tooltip_text = String(d.get("text", ""))
		nl.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(nl)
		row.add_child(_label(String(Goods.tier_def(int(d["tier"]))["label"]), 100.0, 13, UiTheme.TEXT_DIM))
		row.add_child(_label(Relics.fx_text(d.get("fx", {})), 220.0, 13))
		var src := ("%d gisement%s" % [n, "s" if n > 1 else ""]) if n > 0 else "licence"
		if Goods.monopoly_of(state, g) == player:
			src += " · MONOPOLE"
		row.add_child(_label(src, 170.0, 13, UiTheme.GOLD if Goods.monopoly_of(state, g) == player else UiTheme.TEXT))
		if n > 0:
			var open := Goods.sells_licence(state, player, g)
			row.add_child(_btn(es, "Licences : ouvertes" if open else "Licences : fermées", "", SimCommands.licence_close(player, g, open), "close_" + g))
		mine.body.add_child(row)
	if own.is_empty() and bought.is_empty():
		mine.body.add_child(UiTheme.dim("Aucun luxe : fondez une colonie ou un avant-poste sur un gisement, ou achetez une licence.", 14))
	var lic := []
	for l: Dictionary in state.goods.get("lic", []):
		if int(l["buyer"]) == player or int(l["seller"]) == player:
			lic.append(l)
	if not lic.is_empty():
		var lb := Widgets.Block.new("Licences en cours")
		col.add_child(lb)
		for l: Dictionary in lic:
			var buyer := int(l["buyer"]) == player
			var other := int(l["seller"]) if buyer else int(l["buyer"])
			var price := Goods.licence_price(state, int(l["seller"]), int(l["buyer"]), String(l["good"]))
			var row := _row()
			row.add_child(_label(Goods.label(String(l["good"])), 210.0, 15))
			row.add_child(_label(("achetée à %s" if buyer else "vendue à %s") % _name(state, other), 260.0, 14))
			row.add_child(_label("%+d énergie par mois" % (-price if buyer else price), 170.0, 14, UiTheme.delta_color(-price if buyer else price)))
			row.add_child(_btn(es, "Mettre fin", "", SimCommands.licence_cancel(player, other, String(l["good"])), "cancel_%d_%s" % [other, l["good"]]))
			lb.body.add_child(row)
	var offers := []
	for o in Trade.partners(state, player):
		for g in Goods.luxury_ids():
			if int(Goods.owned(state, o).get(g, 0)) > 0 and not Goods.has_luxury(state, player, g):
				offers.append([o, g])
	var ob := Widgets.Block.new("Luxes à acheter chez vos partenaires")
	col.add_child(ob)
	if offers.is_empty():
		ob.body.add_child(UiTheme.dim("Aucun : il faut un traité de commerce avec un empire qui exploite un luxe qui vous manque.", 14))
	for it in offers:
		var o := int(it[0])
		var g := String(it[1])
		var row := _row()
		row.add_child(_label(Goods.label(g), 210.0, 15, Color(0.95, 0.82, 0.5)))
		row.add_child(_label("chez %s" % _name(state, o), 260.0, 14))
		row.add_child(_label("%d énergie par mois" % Goods.licence_price(state, o, player, g), 170.0, 14))
		row.add_child(_btn(es, "Acheter la licence", Goods.check_licence(state, player, o, g), SimCommands.licence_buy(player, o, g), "buy_%d_%s" % [o, g]))
		ob.body.add_child(row)
	var sb := Widgets.Block.new("Ressources stratégiques")
	col.add_child(sb)
	sb.body.add_child(UiTheme.paragraph("Chaque gisement exploité en donne 1 par mois une fois son ère atteinte. Les armes lourdes, les hangars et les modules titanesques en consomment ; le marché en vend toujours quand il est ouvert.", 760.0, 13))
	var me := state.get_empire(player)
	for s in GameData.strategic_ids():
		var d := Goods.strategic(s)
		var row := _row()
		var nl := _label(Goods.label(s), 210.0, 16, Color(0.6, 0.85, 1.0))
		nl.tooltip_text = String(d.get("text", ""))
		nl.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(nl)
		row.add_child(_label("ère %d" % int(d["era"]), 100.0, 13, UiTheme.TEXT_DIM))
		row.add_child(_label("stock %d" % (int(me.resources.get(s, 0)) if me else 0), 140.0, 14))
		var n := int(own.get(s, 0))
		row.add_child(_label("%d gisement%s%s" % [n, "s" if n > 1 else "", "" if Goods.strategic_open(state, player, s) or n == 0 else " (pas encore à cette ère)"], 300.0, 13))
		sb.body.add_child(row)
	var mono: Dictionary = state.goods.get("mono", {})
	if not mono.is_empty():
		var mb := Widgets.Block.new("Monopoles de la galaxie")
		col.add_child(mb)
		var ids := mono.keys()
		ids.sort()
		for g in ids:
			mb.body.add_child(_label("%s : %s" % [Goods.label(String(g)), _name(state, int(mono[g]))], 0.0, 14))


# --- Marché et échanges ------------------------------------------------------------------------

static func build_market(es: EmpireScreens, col: VBoxContainer) -> void:
	var state := es._state
	var player := es._player
	var me := state.get_empire(player)
	if not state.goods.is_empty() and Goods.market_on(state) and me != null:
		var common := Goods.common_market(state)
		var mb := Widgets.Block.new("%s (frais %d %%)" % ["Marché commun" if common else "Marché intérieur", Goods.fee_pct(state, player)])
		col.add_child(mb)
		mb.body.add_child(UiTheme.paragraph(("Achetez et vendez contre de l'énergie, frais compris. Depuis la Bourse galactique, les prix sont les mêmes pour tous : l'achat d'un autre empire renchérit aussi pour vous." if common else
				"Achetez et vendez contre de l'énergie, frais compris. Votre achat fait monter votre prix, votre vente le fait baisser ; chaque mois il revient à moitié vers son prix de base.")
				+ " Guerres, paix, fléaux, monopoles, krachs et envolées font aussi bouger les prix (survolez la tendance).", 760.0, 13))
		for res in Goods.market_ids(state):
			var row := _row()
			row.add_child(_label(GameData.resource_label(res), 150.0, 15))
			row.add_child(_label("stock %d" % int(me.resources.get(res, 0)), 110.0, 13))
			row.add_child(_label("achat %d · vente %d (les 10)" % [Goods.buy_cost(state, player, res, 10), Goods.sell_gain(state, player, res, 10)], 230.0, 13, UiTheme.TEXT_DIM))
			row.add_child(_trend(state, res))
			for n in STEPS:
				row.add_child(_btn(es, "+%d" % n, Goods.check_market(state, player, res, n), SimCommands.market_trade(player, res, n), "buy_%s_%d" % [res, n]))
			for n in STEPS:
				row.add_child(_btn(es, "−%d" % n, Goods.check_market(state, player, res, -n), SimCommands.market_trade(player, res, -n), "sell_%s_%d" % [res, n]))
			var o := Goods.order_of(state, player, res)
			row.add_child(_label("chaque mois : %s" % ("rien" if o == 0 else ("%+d" % o)), 140.0, 13, UiTheme.GOLD if o != 0 else UiTheme.TEXT_DIM))
			row.add_child(_btn(es, "−", "", SimCommands.market_order(player, res, o - 10), "order_%s_-" % res))
			row.add_child(_btn(es, "+", "", SimCommands.market_order(player, res, o + 10), "order_%s_+" % res))
			mb.body.add_child(row)
	else:
		col.add_child(UiTheme.paragraph("Cette partie se joue sans marché intérieur (réglage de Nouvelle partie). Les échanges avec les autres empires restent possibles.", 760.0, 14))
	if me == null or state.goods.is_empty():
		return
	_bourse(es, col)
	_black_market(es, col)
	var inbox := Goods.offers_to(state, player)
	if not inbox.is_empty():
		var ib := Widgets.Block.new("Échanges proposés")
		col.add_child(ib)
		for o: Dictionary in inbox:
			var row := _row()
			row.add_child(_label("%s offre %s contre %s%s" % [_name(state, int(o["from"])), _amounts(o["give"]), _amounts(o["get"]), _dur(int(o["months"]))], 560.0, 14))
			row.add_child(_btn(es, "Accepter", Goods.check_answer(state, player, int(o["id"]), true), SimCommands.deal_answer(player, int(o["id"]), true), "accept_%d" % int(o["id"])))
			row.add_child(_btn(es, "Refuser", "", SimCommands.deal_answer(player, int(o["id"]), false), "refuse_%d" % int(o["id"])))
			ib.body.add_child(row)
	var deals := Goods.deals_of(state, player)
	if not deals.is_empty():
		var db := Widgets.Block.new("Contrats en cours")
		col.add_child(db)
		for d: Dictionary in deals:
			var a := int(d["a"]) == player
			var row := _row()
			row.add_child(_label("Avec %s : vous donnez %s, vous recevez %s, encore %d mois" % [_name(state, int(d["b"]) if a else int(d["a"])),
					_amounts(d["give"] if a else d["get"]), _amounts(d["get"] if a else d["give"]), int(d["left"])], 600.0, 14))
			row.add_child(_btn(es, "Rompre", "", SimCommands.deal_cancel(player, int(d["id"])), "break_%d" % int(d["id"])))
			db.body.add_child(row)
	_deal_builder(es, col)


## Tendance du mois d'une ressource (flèche et %), avec ses raisons en infobulle.
static func _trend(state: GameState, res: String) -> Label:
	var t := Goods.trend_pct(state, res)
	var l := _label("—" if t == 0 else ("▲ +%d %%" % t if t > 0 else "▼ %d %%" % t), 80.0, 13,
			UiTheme.TEXT_DIM if t == 0 else (UiTheme.BAD if t > 0 else UiTheme.GOOD))
	var lines := []
	for p in Goods.trend_parts(state, res):
		lines.append("%s : %+d %%" % [String(p[0]), int(p[1])])
	l.tooltip_text = "Prix stable ce mois-ci." if lines.is_empty() else "\n".join(lines)
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	return l


static func _bourse(es: EmpireScreens, col: VBoxContainer) -> void:
	var state := es._state
	var player := es._player
	var host := Goods.bourse_host(state)
	var bb := Widgets.Block.new("Bourse galactique")
	col.add_child(bb)
	if host < 0:
		bb.body.add_child(UiTheme.paragraph("Aucune Bourse galactique n'est encore bâtie. Le premier empire qui l'élève (Bourses interstellaires, ère III) fonde le marché commun, en devient l'hôte et y vend des vaisseaux d'occasion." if not Goods.common_market(state)
				else "La Bourse galactique est tombée aux mains de personne : le marché commun tient, mais plus aucun vaisseau d'occasion n'est en vente.", 760.0, 13))
		return
	var lic := Goods.trend_pct(state, "_lic")
	bb.body.add_child(UiTheme.paragraph("Hôte : %s%s. Vaisseaux d'occasion livrés à votre capitale, remis en état à 70 %%, pour l'hôte et ceux qui commercent avec lui.%s" % [
			_name(state, host), " (vous : frais réduits, influence sur les échanges des autres)" if host == player else "",
			"" if lic == 0 else " Licences de luxe : %+d %% ce mois-ci." % lic], 760.0, 13))
	var u := Goods.used_offer(state)
	if u.is_empty():
		return
	var row := _row()
	var ship := String(u["ship"])
	row.add_child(_label("%s d'occasion · encore %d · %d énergie" % [String(GameData.ship(ship).get("label", ship)), int(u["left"]), Goods.used_price(state, player)], 420.0, 14))
	row.add_child(_label("prochain arrivage le %s" % GameCalendar.date_string(int(u["next"])), 220.0, 13, UiTheme.TEXT_DIM))
	row.add_child(_btn(es, "Acheter", Goods.check_used(state, player), SimCommands.used_ship_buy(player), "used_buy"))
	bb.body.add_child(row)


static func _black_market(es: EmpireScreens, col: VBoxContainer) -> void:
	var state := es._state
	var player := es._player
	if not Goods.active(state):
		return
	var ports := Pirates.known_ports(state, player)
	if ports.is_empty():
		return
	var sid := ports[0]
	var kb := Widgets.Block.new("Marché noir · %s" % Pirates.port_name(state, sid))
	col.add_child(kb)
	kb.body.add_child(UiTheme.paragraph("Des stratégiques sans traité ni marché, au double du prix et sans frais, %d unités au plus ce mois-ci. Ceux qui vous connaissent finiront par l'apprendre." % maxi(0, Goods.black_left(state, player)), 760.0, 13))
	for res in GameData.strategic_ids():
		var row := _row()
		row.add_child(_label(Goods.label(res), 150.0, 15))
		row.add_child(_label("10 pour %d énergie" % Goods.black_price(state, res, 10), 200.0, 13, UiTheme.TEXT_DIM))
		row.add_child(_btn(es, "+10", Goods.check_black(state, player, sid, res, 10), SimCommands.black_buy(player, sid, res, 10), "black_%s" % res))
		kb.body.add_child(row)


# --- Savoir (lot 3A : accords de recherche, licences de technologie, diffusion) ----------------

const LICENCES_SHOWN := 6


static func _tech_label(tid: String) -> String:
	return String(Research.tech(tid).get("label", tid))


static func build_knowledge(es: EmpireScreens, col: VBoxContainer) -> void:
	var state := es._state
	var player := es._player
	var me := state.get_empire(player)
	if me == null or state.goods.is_empty():
		col.add_child(UiTheme.paragraph("Rien à afficher.", 760.0, 14))
		return
	# Propositions reçues.
	var inbox := TechTrade.offers_to(state, player)
	if not inbox.is_empty():
		var ib := Widgets.Block.new("Propositions reçues")
		col.add_child(ib)
		for o: Dictionary in inbox:
			var row := _row()
			var who := _name(state, int(o["from"]))
			var text := "%s propose un accord de recherche (%d énergie chacun)" % [who, TechTrade.pact_cost(state, int(o["from"]), player)] if String(o["kind"]) == "pact" \
					else "%s demande une licence de %s : il vous paierait %d énergie" % [who, _tech_label(String(o["tech"])), TechTrade.licence_price(state, int(o["from"]), String(o["tech"]))]
			row.add_child(_label(text, 600.0, 14))
			row.add_child(_btn(es, "Accepter", TechTrade.check_answer(state, player, int(o["id"]), true), SimCommands.tech_answer(player, int(o["id"]), true), "tech_accept_%d" % int(o["id"])))
			row.add_child(_btn(es, "Refuser", "", SimCommands.tech_answer(player, int(o["id"]), false), "tech_refuse_%d" % int(o["id"])))
			ib.body.add_child(row)
	# Accords de recherche.
	var pb := Widgets.Block.new("Accords de recherche (%d / %d)" % [TechTrade.pacts_of(state, player).size(), int(TechTrade.data()["pact_max"])])
	col.add_child(pb)
	pb.body.add_child(UiTheme.paragraph("Deux empires en paix depuis un an versent chacun de l'énergie ; trois ans plus tard, chacun reçoit un bond de Savoir sur sa recherche en cours (%d pour vous aujourd'hui). Une guerre entre vous annule l'accord et l'énergie est perdue." % TechTrade.pact_bonus(state, player), 760.0, 13))
	for p: Dictionary in TechTrade.pacts_of(state, player):
		var other := int(p["b"]) if int(p["a"]) == player else int(p["a"])
		pb.body.add_child(_label("En cours avec %s, jusqu'au %s" % [_name(state, other), GameCalendar.date_string(int(p["end"]))], 0.0, 14, UiTheme.GOLD))
	for o in me.contacts:
		var oe := state.get_empire(int(o))
		if oe == null or oe.eliminated or oe.is_npc() or not TechTrade.pact_between(state, player, int(o)).is_empty():
			continue
		var row := _row()
		row.add_child(_label(oe.display_name(), 260.0, 14))
		row.add_child(_label("%d énergie chacun" % TechTrade.pact_cost(state, player, int(o)), 160.0, 13, UiTheme.TEXT_DIM))
		var why := TechTrade.check_pact(state, player, int(o))
		row.add_child(_btn(es, "Proposer", why, SimCommands.research_pact(player, int(o)), "pact_%d" % int(o)))
		if why != "":
			row.add_child(_label(why, 320.0, 12, UiTheme.TEXT_DIM))
		pb.body.add_child(row)
	# Licences de technologie.
	var lb := Widgets.Block.new("Licences de technologie")
	col.add_child(lb)
	lb.body.add_child(UiTheme.paragraph("Un partenaire commercial peut vous vendre une technologie qu'il a trouvée lui-même (ni de peuple, ni de méga-vaisseau, une ère d'avance au plus) : vous recevez %d %% de son coût en Savoir et le payez en énergie. Une technologie achetée ne se revend pas." % int(TechTrade.data()["licence_share_pct"]), 760.0, 13))
	var any := false
	for o in Trade.partners(state, player):
		var offered := TechTrade.licences_offered(state, player, o)
		if offered.is_empty():
			continue
		any = true
		lb.body.add_child(_label(_name(state, o), 0.0, 15, UiTheme.GOLD))
		offered.sort_custom(func(x: String, y: String) -> bool: return TechTrade.licence_price(state, player, x) < TechTrade.licence_price(state, player, y))
		for tid in offered.slice(0, LICENCES_SHOWN):
			var row := _row()
			row.add_child(_label(_tech_label(tid), 260.0, 14))
			row.add_child(_label("%d Savoir pour %d énergie" % [TechTrade.licence_knowledge(state, player, tid), TechTrade.licence_price(state, player, tid)], 220.0, 13, UiTheme.TEXT_DIM))
			row.add_child(_btn(es, "Acheter", TechTrade.check_licence(state, player, o, tid), SimCommands.tech_licence(player, o, tid), "tlic_%d_%s" % [o, tid]))
			lb.body.add_child(row)
	if not any:
		lb.body.add_child(_label("Aucun partenaire commercial n'a de technologie à vous vendre.", 0.0, 13, UiTheme.TEXT_DIM))
	for o2: Dictionary in TechTrade.offers_from(state, player):
		lb.body.add_child(_label("En attente : %s auprès de %s" % ["accord de recherche" if String(o2["kind"]) == "pact" else "licence de " + _tech_label(String(o2["tech"])), _name(state, int(o2["to"]))], 0.0, 13, UiTheme.TEXT_DIM))
	# Diffusion.
	var db := Widgets.Block.new("Diffusion : %d Savoir ce mois-ci" % int(Trade.income(state, player).get("knowledge", 0)))
	col.add_child(db)
	db.body.add_child(UiTheme.paragraph("Chaque route active vers un empire qui connaît plus de technologies que vous rapporte 1 Savoir par technologie d'écart, au plus %d par route et %d en tout." % [int(TechTrade.data()["diffusion_route_max"]), int(TechTrade.data()["diffusion_max"])], 760.0, 13))
	for o in Trade.partners(state, player):
		var gap := TechTrade.tech_gap(state, player, o)
		db.body.add_child(_label("%s : %d technologie%s d'avance sur vous%s" % [_name(state, o), gap, "s" if gap > 1 else "", (", +%d par route" % TechTrade.route_diffusion(state, player, o)) if gap > 0 else ""], 0.0, 13, UiTheme.TEXT if gap > 0 else UiTheme.TEXT_DIM))


static func _amounts(a: Dictionary) -> String:
	return GameData.format_amounts(a) if not a.is_empty() else "rien"


static func _dur(months: int) -> String:
	return "" if months <= 0 else ", chaque mois pendant %d mois" % months


## Brouillon d'échange : partenaire, ce que l'on donne, ce que l'on demande, la durée.
static func _deal_builder(es: EmpireScreens, col: VBoxContainer) -> void:
	var state := es._state
	var player := es._player
	var me := state.get_empire(player)
	var others: Array[int] = []
	for o in me.contacts:
		var e := state.get_empire(o)
		if e != null and not e.eliminated and not GameState.is_npc(o):
			others.append(o)
	var bb := Widgets.Block.new("Proposer un échange")
	col.add_child(bb)
	if others.is_empty():
		bb.body.add_child(UiTheme.dim("Aucun empire rencontré.", 14))
		return
	var d := es.trade_deal
	if not others.has(int(d.get("to", -1))):
		d["to"] = others[0]
	var res_ids: Array[String] = ["energy", "materials", "food", "influence", "crystals"]
	if Goods.active(state):
		res_ids.append_array(GameData.strategic_ids())
	for k in ["give_res", "get_res"]:
		if not res_ids.has(String(d.get(k, ""))):
			d[k] = "materials" if k == "give_res" else "energy"
	for k in ["give", "get", "months"]:
		d[k] = int(d.get(k, 0))
	var row := _row()
	row.add_child(_label("Avec", 60.0, 14))
	row.add_child(_cycle(es, _name(state, int(d["to"])), func() -> void: d["to"] = others[(others.find(int(d["to"])) + 1) % others.size()]))
	bb.body.add_child(row)
	for side in [["give", "Vous donnez"], ["get", "Vous demandez"]]:
		var k := String(side[0])
		var r2 := _row()
		r2.add_child(_label(String(side[1]), 120.0, 14))
		r2.add_child(_cycle(es, GameData.resource_label(String(d[k + "_res"])), func() -> void: d[k + "_res"] = res_ids[(res_ids.find(String(d[k + "_res"])) + 1) % res_ids.size()]))
		for step in [-50, -10, 10, 50]:
			var stp: int = step
			r2.add_child(_cycle(es, "%+d" % stp, func() -> void: d[k] = maxi(0, int(d[k]) + stp)))
		r2.add_child(_label(str(int(d[k])), 60.0, 15, UiTheme.GOLD))
		bb.body.add_child(r2)
	var r3 := _row()
	r3.add_child(_label("Durée", 120.0, 14))
	var di := 0
	for i in DURATIONS.size():
		if int(DURATIONS[i][0]) == int(d["months"]):
			di = i
	r3.add_child(_cycle(es, String(DURATIONS[di][1]), func() -> void: d["months"] = int(DURATIONS[(di + 1) % DURATIONS.size()][0])))
	bb.body.add_child(r3)
	var give := {String(d["give_res"]): int(d["give"])} if int(d["give"]) > 0 else {}
	var get_ := {String(d["get_res"]): int(d["get"])} if int(d["get"]) > 0 else {}
	var why := Goods.check_offer(state, player, int(d["to"]), give, get_, int(d["months"]))
	var r4 := _row()
	var verdict := ""
	var target := state.get_empire(int(d["to"]))
	if why == "" and target != null and target.is_ai():
		var ev := AiGoods.evaluate_offer(state, int(d["to"]), {"from": player, "to": int(d["to"]), "give": give, "get": get_, "months": int(d["months"])})
		var lines := PackedStringArray()
		for l in ev["lines"]:
			lines.append("%+d  %s" % [int(l[1]), String(l[0])])
		verdict = ("Accepterait (%+d)" if int(ev["score"]) >= 0 else "Refuserait (%+d)") % int(ev["score"])
		var vl := _label(verdict, 220.0, 14, UiTheme.delta_color(int(ev["score"]) + 1))
		vl.tooltip_text = "\n".join(lines)
		vl.mouse_filter = Control.MOUSE_FILTER_STOP
		r4.add_child(vl)
	elif why == "":
		r4.add_child(_label("Il devra répondre", 220.0, 14, UiTheme.TEXT_DIM))
	r4.add_child(_btn(es, "Proposer", why, SimCommands.deal_offer(player, int(d["to"]), give, get_, int(d["months"])), "propose"))
	if why != "":
		r4.add_child(_label(why, 400.0, 13, UiTheme.TEXT_DIM))
	bb.body.add_child(r4)


## Bouton qui modifie le brouillon puis redessine l'écran.
static func _cycle(es: EmpireScreens, text: String, change: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(func() -> void:
		change.call()
		es.show_screen("trade"))
	return b


## Ce qui change ces onglets : luxes, licences, monopoles, stocks, prix, ordres, échanges.
static func signature(es: EmpireScreens) -> String:
	var state := es._state
	if state.goods.is_empty():
		return ""
	var e := state.get_empire(es._player)
	var res := ""
	if e != null:
		for r in Goods.market_ids(state):
			res += "%d," % int(e.resources.get(r, 0))
		res += str(e.resources.get("energy", 0))
	return "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [es.trade_tab, str(state.goods.get("own", {})), str(state.goods.get("lic", [])), str(state.goods.get("mono", {})),
			str(state.goods.get("mkt", {}).get(Goods.market_key(state, es._player), {})), str(state.goods.get("trend", {})), str(state.goods.get("used", {})), str(state.goods.get("bm", {}).get(es._player, 0)), Goods.bourse_host(state), str(state.goods.get("orders", {}).get(es._player, {})), str(state.goods.get("offers", [])),
			str(state.goods.get("deals", [])), res if es.trade_tab != "routes" else "", str(state.goods.get("closed", {})) + str(state.goods.get("pacts", [])) + str(state.goods.get("toff", [])) + str(state.goods.get("tlic", {})) + str(Trade.income(state, es._player).get("knowledge", 0))]
