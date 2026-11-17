class_name KardashevScreen
extends RefCounted
## Écran L'Échelle (voir Kardashev, prop. 44) : un onglet de l'écran Victoires. À gauche, votre indice,
## sa puissance captée par source, le verrou du type suivant, les prérogatives (à choisir, éveillées,
## dormantes), la Sobriété, le Voile et l'Allumeur d'étoiles ; au centre, l'échelle des empires connus,
## la chaleur et le catalogue des prérogatives. Construit dans les conteneurs d'EmpireScreens.

const COLOR := Color(1.0, 0.86, 0.6)
const W := 760.0


static func signature(es: EmpireScreens) -> String:
	var state := es._state
	if not Kardashev.enabled(state):
		return "off"
	var p := es._player
	var ks := PackedStringArray()
	for e in state.empires:
		if not e.is_npc():
			ks.append(str(Kardashev.index100(state, e.id)))
	@warning_ignore("integer_division")
	return "%d|%s|%s|%s|%d|%d|%d|%d" % [state.relic_rev, ",".join(ks), str(Kardashev.pending(state, p)), str(Kardashev.perks(state, p)),
			int(Kardashev.sober(state, p)), Kardashev._gi(state, "veil_cd", p), int(Kardashev.sub(state, "relight").has(str(p))), state.tick / 30]


static func _btn(es: EmpireScreens, text: String, tip: String, command: Dictionary, key: String) -> Button:
	var why := SimCommands.validate(es._state, command)
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = why != ""
	b.clip_text = true
	b.custom_minimum_size = Vector2(EmpireScreens.SIDE_WIDTH - 24.0, 0)
	b.tooltip_text = tip + ("\n\nImpossible : %s." % why if why != "" else "")
	b.pressed.connect(func() -> void: es.command_requested.emit(command))
	es.kardashev_buttons[key] = b
	return b


static func build(es: EmpireScreens) -> void:
	var state := es._state
	var player := es._player
	es._kardashev_sig = signature(es)
	es._side_header("screen_kardashev", "L'Échelle", COLOR, "faction")
	TranscendenceScreen.tabs(es, "kardashev")
	var w := EmpireScreens.SIDE_WIDTH - 24.0
	if not Kardashev.applies(state, player):
		es._side_box.add_child(UiTheme.paragraph("Dans cette partie, l'échelle de Kardashev n'est pas en jeu (Nouvelle partie : Échelle de Kardashev).", w, 13))
		return
	var k := Kardashev.index100(state, player)
	var t := Kardashev.tier(state, player)
	var g := es._grid()
	es._side_box.add_child(g)
	es._key_value(g, "Réglage", "%s, rythme %s" % [Kardashev.mode_label(state), Kardashev.pace_label(state).to_lower()])
	es._key_value(g, "Indice", Kardashev.value_text(k))
	es._key_value(g, "Rang", Kardashev.title(t))
	var best := Kardashev._gi(state, "best", player)
	if best > t:
		es._key_value(g, "Meilleur type atteint", Kardashev.roman(best))
	var pp := Kardashev.power_parts(state, player)
	es._key_value(g, "Puissance captée", str(int(pp["total"])))
	es._key_value(g, "  dont colonies", str(int(pp["colonies"])))
	if int(pp["megas"]) > 0 or not state.megas.is_empty():
		es._key_value(g, "  dont mégastructures", str(int(pp["megas"])))
	if int(pp["worlds"]) > 0:
		es._key_value(g, "  dont mondes forgés", str(int(pp["worlds"])))
	if int(pp["sober_pct"]) < 100:
		es._key_value(g, "  Sobriété thermique", "%d %%" % int(pp["sober_pct"]))
	var anc := Kardashev.anchors(state)
	if t < 3:
		es._key_value(g, "Pour le type %s" % Kardashev.roman(t + 1), "%d de puissance" % int(anc[t + 1]))
	es._side_box.add_child(HSeparator.new())
	if t < 3:
		var miss := Kardashev.lock_missing(state, player, t + 1)
		es._side_box.add_child(UiTheme.dim("Verrou du type %s" % Kardashev.roman(t + 1), 13))
		es._side_box.add_child(UiTheme.paragraph("Levé : il ne manque que la puissance." if miss.is_empty() else "Il manque : %s. Sans lui, l'indice plafonne à %s." % ["; ".join(miss), Kardashev.value_text((t + 1) * 100 - 1)], w, 12))
	if not Kardashev.full(state):
		return
	if KardashevWorld.dark_age(state, player):
		es._side_box.add_child(UiTheme.paragraph("Âge sombre : vous êtes retombé sous le type %s. Stabilité %+d, réparations et relèvements %+d %%. Remonter ouvre un Âge héroïque (une prérogative de plus)." % [
				Kardashev.roman(best), Kardashev.c_int("dark", "stability", -2), Kardashev.c_int("dark", "repair_pct", -50)], w, 12))
	for tt in range(1, 4):
		var em := KardashevWorld.emulation_pct(state, player, tt)
		if em > 0:
			es._side_box.add_child(UiTheme.paragraph("Émulation : un rival a franchi le type %s avant vous ; ce qui y mène vous coûte %d %% de moins." % [Kardashev.roman(tt), em], w, 12))
	# Prérogatives à choisir.
	var off := Kardashev.offer(state, player)
	if not off.is_empty():
		es._side_box.add_child(HSeparator.new())
		var lv := int(Kardashev.pending(state, player)[0])
		es._side_box.add_child(UiTheme.dim("Prérogative à choisir (%s)" % ("Âge héroïque" if lv == 0 else Kardashev.value_text(int(Kardashev.data()["levels"][lv - 1]))), 13))
		for pid in off:
			var pd := Kardashev.perk_def(pid)
			es._side_box.add_child(_btn(es, String(pd["label"]), String(pd.get("text", "")), SimCommands.kd_act(player, "perk", {"id": pid}), "perk:" + pid))
	var mine := Kardashev.perks(state, player)
	if not mine.is_empty():
		es._side_box.add_child(HSeparator.new())
		es._side_box.add_child(UiTheme.dim("Vos prérogatives", 13))
		for pid in mine:
			var pd := Kardashev.perk_def(String(pid))
			var awake := Kardashev.awake(state, player, String(pid))
			var l := UiTheme.paragraph("%s%s : %s" % [String(pd.get("label", pid)), "" if awake else " (dort)", String(pd.get("text", ""))], w, 12)
			if not awake:
				l.modulate = Color(1, 1, 1, 0.55)
			es._side_box.add_child(l)
	# Chaleur et actions.
	es._side_box.add_child(HSeparator.new())
	es._side_box.add_child(UiTheme.dim("Chaleur", 13))
	var sig := KardashevWorld.signature(state, player)
	es._side_box.add_child(UiTheme.paragraph("Signature thermique : %s%s." % [Kardashev.value_text(sig), " (Voile stellaire tiré)" if KardashevWorld.veiled(state, player) else ""], w, 12))
	var on := Kardashev.sober(state, player)
	es._side_box.add_child(_btn(es, "Lever la Sobriété thermique" if on else "Proclamer la Sobriété thermique",
			"Signature %+d, puissance captée %d %% : moins visible, moins visé par les crises, mais l'indice monte moins vite." % [-Kardashev.c_int("signature", "sober_minus", 50), Kardashev.c_int("signature", "sober_power_pct", 85)],
			SimCommands.kd_act(player, "sober", {"on": not on}), "sober"))
	if Kardashev.has_perk(state, player, "voile_stellaire"):
		es._side_box.add_child(_btn(es, "Tirer le Voile stellaire", "Votre signature s'éteint %d jours ; une fois tous les %d jours." % [Kardashev.c_int("signature", "veil_days", 120), Kardashev.c_int("signature", "veil_cooldown", 360)],
				SimCommands.kd_act(player, "veil"), "veil"))
	if Kardashev.has_perk(state, player, "allumeur_etoiles"):
		var rl: Dictionary = Kardashev.sub(state, "relight").get(str(player), {})
		if not rl.is_empty():
			es._side_box.add_child(UiTheme.paragraph("L'étoile de %s se rallume : encore %d jours." % [state.galaxy.systems[int(rl["s"])].name, maxi(0, int(rl["until"]) - state.tick)], w, 12))
		else:
			var n := 0
			for sid in state.galaxy.systems.size():
				if n >= 4 or Kardashev.check(state, player, "relight", {"s": sid}) != "":
					continue
				n += 1
				es._side_box.add_child(_btn(es, "Rallumer l'étoile de %s" % state.galaxy.systems[sid].name, "Une naine %s devient une naine jaune au bout de %d jours." % [
						"rouge" if KardashevWorld.star_type(state, sid) == "red" else "blanche", Kardashev.c_int("relight", "days", 360)],
						SimCommands.kd_act(player, "relight", {"s": sid}), "relight:%d" % sid))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	es._content.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 18)
	scroll.add_child(col)
	ladder(es, col)
	if Kardashev.full(state):
		catalogue(es, col)


## L'échelle des empires que vous connaissez, du plus puissant au plus faible.
static func ladder(es: EmpireScreens, col: VBoxContainer) -> void:
	var state := es._state
	var player := es._player
	var b := Widgets.Block.new("L'échelle de Kardashev")
	col.add_child(b)
	var rows := []
	for e in state.empires:
		if e.is_npc() or e.eliminated or not (es.see_all or e.id == player or state.get_empire(player).contacts.has(e.id)):
			continue
		rows.append([Kardashev.index100(state, e.id), e.id])
	rows.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0] or (x[0] == y[0] and x[1] < y[1]))
	for r in rows:
		var eid := int(r[1])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var nl := Label.new()
		nl.text = state.get_empire(eid).short_name() + (" (vous)" if eid == player else "")
		nl.custom_minimum_size = Vector2(200, 0)
		row.add_child(nl)
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = 300
		bar.value = int(r[0])
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(320, 14)
		row.add_child(bar)
		var v := Label.new()
		v.text = "%s  %s" % [Kardashev.value_text(int(r[0])), Kardashev.title(Kardashev.tier(state, eid))]
		row.add_child(v)
		b.body.add_child(row)
	b.body.add_child(UiTheme.paragraph("L'indice mesure la puissance captée (énergie brute des colonies, mégastructures, mondes forgés) sur une échelle logarithmique : de 0,70 au départ à 1,00 (type I), 2,00 (type II) et 3,00 (type III). Chaque type entier ne se franchit qu'avec son verrou et donne du Rayonnement. Un empire d'un type au-dessus du vôtre inspire révérence si vous êtes en paix, crainte sinon.", W, 12))


## La chaleur et les prérogatives de chaque demi-palier.
static func catalogue(es: EmpireScreens, col: VBoxContainer) -> void:
	var state := es._state
	var hb := Widgets.Block.new("La chaleur trahit les puissants")
	col.add_child(hb)
	hb.body.add_child(UiTheme.paragraph("À %s de signature, la capitale et les mégastructures d'un empire sont connues de tous ; à %s, tous ses systèmes peuplés. Les crises visent d'abord les signatures les plus fortes, à distance comparable. La Sobriété thermique et le Voile stellaire la font baisser." % [
			Kardashev.value_text(Kardashev.c_int("signature", "capital_at", 150)), Kardashev.value_text(Kardashev.c_int("signature", "all_at", 250))], W, 12))
	var pb := Widgets.Block.new("Prérogatives")
	col.add_child(pb)
	var levels: Array = Kardashev.data().get("levels", [])
	for lv in range(1, levels.size() + 1):
		var parts := PackedStringArray()
		for pid in Kardashev.perks_of_level(lv):
			var pd := Kardashev.perk_def(pid)
			parts.append("%s%s : %s" % [String(pd["label"]), " ✓" if Kardashev.has_perk(state, es._player, pid) else "", String(pd.get("text", ""))])
		pb.body.add_child(UiTheme.dim("À %s" % Kardashev.value_text(int(levels[lv - 1])), 13))
		pb.body.add_child(UiTheme.paragraph("\n".join(parts), W, 12))
	pb.body.add_child(UiTheme.paragraph("Une prérogative par demi-palier atteint, choisie une fois pour toutes. Celles d'un palier perdu dorment jusqu'à ce que vous y remontiez.", W, 12))
