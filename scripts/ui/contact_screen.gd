class_name ContactScreen
extends RefCounted
## Écran Contact (voir Contact, prop. 43) : un onglet de l'écran Victoire. Les voies de capture, la
## jauge de déchiffrement et son détail, les couches, le dossier des Lointains, les décisions (part du
## Savoir, alertes, Plans, intuition), le Héraut et la Transmission, et la course dans la galaxie.

const COLOR := Color(0.7, 0.9, 1.0)
const W := 760.0


static func build(es: EmpireScreens) -> void:
	var state := es._state
	var player := es._player
	es._contact_sig = signature(es)
	es._side_header("screen_contact", "Contact", COLOR, "faction")
	TranscendenceScreen.tabs(es, "contact")
	var w := EmpireScreens.SIDE_WIDTH - 24.0
	if not Contact.applies(state, player):
		es._side_box.add_child(UiTheme.paragraph("Dans cette partie, le Contact n'est pas en jeu (Nouvelle partie : Contact).", w, 13))
		return
	var g := es._grid()
	es._side_box.add_child(g)
	es._key_value(g, "Réglage", "%s, %s, issue %s" % [Contact.mode_label(state), Contact.nature_mode_label(state).to_lower(), Contact.outcome_label(state).to_lower()])
	es._key_value(g, "Signal", _status(state, player))
	if Contact.route_count(state, player) > 0:
		es._key_value(g, "Déchiffrement", "%d %% (+%s par mois)" % [Contact.gauge_pct(state, player), _tenths(Contact.monthly_gain(state, player))])
		es._key_value(g, "Certitude", "%d / %d" % [Contact.certainty(state, player), Contact.c_int("certainty", "max", 10)])
	var t := Contact.talent(state, player)
	if t.has("label"):
		es._side_box.add_child(HSeparator.new())
		es._side_box.add_child(UiTheme.dim("Talent de votre peuple", 13))
		es._side_box.add_child(UiTheme.paragraph("%s : %s" % [String(t["label"]), String(t.get("text", ""))], w, 12))
	es._side_box.add_child(HSeparator.new())
	# Décisions.
	if Contact.route_count(state, player) > 0 and not Contact.done(state, player) and not Contact.failed(state, player):
		es._side_box.add_child(UiTheme.dim("Part du Savoir consacrée au Signal : %d %%" % Contact.share(state, player), 13))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var smax := Contact.c_int("gauge", "share_max", 30)
		for v in range(0, smax + 1, 10):
			var b := Button.new()
			b.text = "%d %%" % v
			b.toggle_mode = true
			b.button_pressed = v == Contact.share(state, player)
			b.focus_mode = Control.FOCUS_NONE
			var cmd := SimCommands.ct_act(player, "share", {"v": v})
			b.pressed.connect(func() -> void: es.command_requested.emit(cmd))
			es.contact_buttons["share:%d" % v] = b
			row.add_child(b)
		es._side_box.add_child(row)
	var al := Contact.pending_alert(state, player)
	if not al.is_empty() and int(al.get("verify", 0)) <= 0:
		es._side_box.add_child(UiTheme.dim("Un signal étrange vient d'être capté", 13))
		es._side_box.add_child(_btn(es, "L'annoncer à la galaxie", Contact.check(state, player, "announce", {}), Contact.event_line("alert_announce"),
				SimCommands.ct_act(player, "announce"), "announce"))
		es._side_box.add_child(_btn(es, "Vérifier d'abord (six mois)", Contact.check(state, player, "verify", {}), Contact.event_line("alert_verify"),
				SimCommands.ct_act(player, "verify"), "verify"))
	if Contact.has_layer(state, player, "plans") and Contact.plans_state(state, player) == "":
		es._side_box.add_child(UiTheme.dim("Les Plans", 13))
		es._side_box.add_child(_btn(es, "Bâtir les Plans tels quels", Contact.check(state, player, "plans_raw", {}), Contact.event_line("plans_raw"),
				SimCommands.ct_act(player, "plans_raw"), "plans_raw"))
		es._side_box.add_child(_btn(es, "Les auditer un an", Contact.check(state, player, "plans_audit", {}), Contact.event_line("plans_audit"),
				SimCommands.ct_act(player, "plans_audit"), "plans_audit"))
	if Contact.has_layer(state, player, "plans") and not Contact.abc_key(state, player) and not Contact.intuition_running(state, player):
		es._side_box.add_child(_btn(es, "Chercher la clé de lecture par intuition (2 ans)", Contact.check(state, player, "intuition", {}),
				"Sans fragment étranger, l'Abécédaire reste illisible : vos linguistes peuvent chercher la clé eux-mêmes, en deux ans.",
				SimCommands.ct_act(player, "intuition"), "intuition"))
	if not Contact.transmitting(state, player) and not Contact.done(state, player) and not Contact.failed(state, player) and Contact.has_layer(state, player, "plans"):
		es._side_box.add_child(_btn(es, "Répondre : lancer la Transmission (%s)" % Victory._days_text(Contact.tx_need(state, player)), Contact.check(state, player, "transmit", {}),
				"Le Héraut émet vers l'au-delà ; tant qu'il émet, toute la galaxie sait où il est. À la fin, l'issue dépend de ceux qui écoutent.",
				SimCommands.ct_act(player, "transmit"), "transmit"))
	if Contact.transmitting(state, player):
		es._side_box.add_child(UiTheme.dim("Débit de la Transmission (énergie : %d par mois)" % Contact.tx_cost(state, player), 13))
		var row2 := HBoxContainer.new()
		row2.add_theme_constant_override("separation", 4)
		for r in Contact.c_int("heraut", "rate_max", 3) + 1:
			var b := Button.new()
			b.text = "×%d" % (r + 1)
			b.toggle_mode = true
			b.button_pressed = r == Contact.tx_rate(state, player)
			b.focus_mode = Control.FOCUS_NONE
			b.tooltip_text = "+%d %% de vitesse, %d énergie par mois (jamais sous le plancher de deux ans)" % [Contact.c_int("heraut", "rate_pct", 33) * r, Contact.c_int("heraut", "energy_month", 8) * (r + 1)]
			var cmd2 := SimCommands.ct_act(player, "rate", {"v": r})
			b.pressed.connect(func() -> void: es.command_requested.emit(cmd2))
			es.contact_buttons["rate:%d" % r] = b
			row2.add_child(b)
		es._side_box.add_child(row2)
	for x in side_extra(es):
		es._side_box.add_child(x)
	es._side_box.add_child(HSeparator.new())
	es._side_box.add_child(UiTheme.paragraph("Quatre étapes : écouter (deux voies sur trois : une Oreille de la Bordure, un Écho fossile, la Grammaire des étoiles), déchiffrer quatre couches, décider, puis répondre par le Héraut. Tous les Lointains ne sont pas bienveillants : le dossier se resserre à chaque couche.", w, 12))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	es._content.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 18)
	scroll.add_child(col)

	# Écoute.
	var lb := Widgets.Block.new("L'écoute")
	col.add_child(lb)
	if not Contact.listens(state, player):
		lb.body.add_child(UiTheme.paragraph("Il faut la technologie %s pour tendre l'oreille." % String(Research.tech(Contact.listen_tech()).get("label", "Écoute profonde")), W, 13))
	for r in ["ear", "echo", "grammar"]:
		var got := Contact.routes(state, player).has(r)
		lb.body.add_child(UiTheme.paragraph("%s %s%s" % ["✓" if got else "○", Contact.route_label(r), " (le %s)" % GameCalendar.date_string(int(Contact.routes(state, player)[r])) if got else ""], W, 13))
	for x in Contact.ears_of(state, player):
		var sid := int(x[1])
		var extra := ""
		if Contact.deaf(state, sid):
			extra = ", sourde (nébuleuse)"
		elif Contact.amplified(state, sid):
			extra = ", amplifiée"
		lb.body.add_child(UiTheme.dim("Oreille à %s : %s%s" % [state.galaxy.systems[sid].system_name,
				"a fini d'écouter" if int(x[2]) >= int(x[3]) else "%d %% (%s)" % [100 * int(x[2]) / maxi(1, int(x[3])), "Bordure" if Contact.is_edge(state, sid) else "loin de la Bordure"], extra], 13))
	var known: PackedStringArray = []
	var me := state.get_empire(player)
	for sid in Contact.echo_sites(state):
		if es.see_all or me.explored.has(sid):
			known.append(state.galaxy.systems[sid].system_name)
	lb.body.add_child(UiTheme.dim("Échos fossiles connus : %s" % (", ".join(known) if not known.is_empty() else "aucun (explorez la galaxie)"), 13))

	# Déchiffrement.
	if Contact.route_count(state, player) > 0:
		var gb := Widgets.Block.new("Déchiffrement : %d %%" % Contact.gauge_pct(state, player))
		col.add_child(gb)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(500, 10)
		bar.max_value = Contact.gauge_max()
		bar.value = Contact.gauge(state, player)
		gb.body.add_child(bar)
		for x in Contact.gain_parts(state, player):
			gb.body.add_child(UiTheme.paragraph("%s : %+s par mois" % [x[0], _tenths(int(x[1]))], W, 13))
		if Contact.gauge(state, player) >= Contact.gauge_cap(state, player) and Contact.gauge(state, player) < Contact.gauge_max():
			gb.body.add_child(UiTheme.paragraph("Bloqué : %s." % ("il faut une deuxième voie" if Contact.partial(state, player) else "il manque la clé de lecture de l'Abécédaire"), W, 13))
		var ld := Contact.layer_defs()
		for i in ld.size():
			var d: Dictionary = ld[i]
			var got := Contact.layers(state, player) > i
			gb.body.add_child(UiTheme.paragraph("%s %s (%d %%)%s" % ["✓" if got else "○", String(d.get("label", "")), int(d.get("at", 0)) / 10,
					" : « %s »" % Contact.voice(state, player, String(d["id"])) if got else " : %s" % String(d.get("text", ""))], W, 12))
		# Dossier des Lointains.
		var nb := Widgets.Block.new("Le dossier des Lointains")
		col.add_child(nb)
		if Contact.nature_mode(state) == "sans_indices":
			nb.body.add_child(UiTheme.paragraph("Réglage « sans indices » : le Signal ne dit rien de ceux qui l'envoient.", W, 13))
		var pn := Contact.possible_natures(state, player)
		for n: Dictionary in Contact.nature_defs():
			var id := String(n["id"])
			nb.body.add_child(UiTheme.paragraph("%s %s : %s" % ["?" if pn.has(id) else "✗", String(n.get("label", id)), String(n.get("text", "")) if pn.has(id) else "écartés"], W, 12))
		var gifts: Array = Contact.sub(state, "gifts").get(str(player), [])
		for gid in gifts:
			var gd := Contact.gift_def(String(gid))
			nb.body.add_child(UiTheme.dim("Don des Plans : %s (%s)" % [String(gd.get("label", gid)), String(gd.get("text", ""))], 13))
		if Contact.plans_state(state, player) == "auditing":
			nb.body.add_child(UiTheme.dim("Audit des Plans jusqu'au %s" % GameCalendar.date_string(int(Contact.sub(state, "plans")[str(player)])), 13))
		if Contact.intuition_running(state, player):
			nb.body.add_child(UiTheme.dim("Intuition des linguistes jusqu'au %s" % GameCalendar.date_string(int(Contact.sub(state, "abc")[str(player)])), 13))

	# Héraut et Transmission.
	if Contact.has_layer(state, player, "plans") or Contact.transmitting(state, player):
		var hb := Widgets.Block.new("Le Héraut")
		col.add_child(hb)
		var hs := Contact.heraut_system(state, player)
		hb.body.add_child(UiTheme.paragraph("Héraut : %s" % (state.galaxy.systems[hs].system_name if hs >= 0 else "à bâtir (bâtiment, une colonie)"), W, 13))
		hb.body.add_child(UiTheme.paragraph("Durée de la Transmission : %s (Oreilles qui ont fini : %d ; plancher %s)" % [Victory._days_text(Contact.tx_need(state, player)),
				Contact.ears_done(state, player), Victory._days_text(Contact.c_int("heraut", "min_days", 720))], W, 13))
		if Contact.transmitting(state, player):
			hb.body.add_child(UiTheme.paragraph("En cours : %d %%, %s restants%s" % [Contact.tx_pct(state, player), Victory._days_text(Contact.tx_left(state, player)),
					" ; Héraut perdu, la Transmission attend" if int(Contact.tx(state, player).get("lost", 0)) > 0 else ""], W, 13))

	# Dans la galaxie.
	var gl := Widgets.Block.new("Dans la galaxie")
	col.add_child(gl)
	var any := false
	for e in state.empires:
		if e.id == player or e.eliminated or e.is_npc() or not (es.see_all or me.contacts.has(e.id)):
			continue
		if Contact.route_count(state, e.id) <= 0 and not Contact.transmitting(state, e.id):
			continue
		any = true
		var pct := Victory.visible_pct(state, -1 if es.see_all else player, e.id, "contact")
		var line := e.short_name()
		if Contact.transmitting(state, e.id):
			line += " : TRANSMET depuis %s" % state.galaxy.systems[Contact.heraut_system(state, e.id)].system_name if Contact.heraut_system(state, e.id) >= 0 else " : transmet"
		elif pct < 0:
			line += " : écoute, avancée cachée"
		else:
			line += " : %s" % " ; ".join(PackedStringArray(Victory.progress(state, e.id, "contact")["lines"]).slice(1))
		gl.body.add_child(UiTheme.paragraph(line, W, 13))
	for e in state.empires:
		if Contact.done(state, e.id) or Contact.failed(state, e.id):
			any = true
			gl.body.add_child(UiTheme.paragraph("%s : a reçu la réponse" % e.short_name(), W, 13))
	if not any:
		gl.body.add_child(UiTheme.dim("Aucun empire connu n'a capté le Signal.", 13))
	content_extra(es, col)


## Lignes des voix (lot 3) dans la colonne latérale.
static func voices_side(es: EmpireScreens) -> Array[Control]:
	var out: Array[Control] = []
	var state := es._state
	var p := es._player
	if Contact.full(state) and Contact.route_count(state, p) > 0:
		var line := "Taiseux : %d / 100%s" % [ContactVoices.taiseux(state, p), " (au pouvoir)" if ContactVoices.silenced(state, p) else ""]
		if ContactVoices.no_debate(state, p):
			line = "Taiseux : pas de débat dans votre gouvernement%s" % (" ; votre foi tient le Signal pour une hérésie" if ContactVoices.silenced(state, p) else "")
		out.append(UiTheme.dim(line, 13))
	if Contact.has_layer(state, p, "plans") and not Contact.done(state, p) and not Contact.failed(state, p):
		if not Contact.abc_key(state, p) and ContactVoices.aster_id(state) >= 0:
			out.append(_btn(es, "Demander la clé à la Bibliothèque d'Aster", ContactVoices.check_aster(state, p), "La Grande Bibliothèque prête la clé de l'Abécédaire à qui elle estime, contre une requête.",
					SimCommands.ct_act(p, "aster"), "aster"))
		if Contact.t_int(state, p, "city_heraut") > 0 and not Contact.has_heraut(state, p):
			out.append(_btn(es, "Monter le Héraut sur la flotte-ville", ContactVoices.check_mount(state, p), "La flotte-ville porte l'émetteur ; elle devra rester à l'arrêt pendant la Transmission.",
					SimCommands.ct_act(p, "mount_heraut"), "mount_heraut"))
		if Contact.sub(state, "voyage").get(str(p), {}).is_empty() and not Contact.transmitting(state, p):
			out.append(_btn(es, "Le Voyage des Cinq (%s)" % GameData.format_amounts(ContactVoices.voyage_cost(state, p)), ContactVoices.check_voyage(state, p),
					"Bâtir la Machine des Plans et y envoyer jusqu'à cinq héros du Conseil, deux ans. S'ils reviennent, c'est la victoire ; sinon ils sont perdus.",
					SimCommands.ct_act(p, "voyage"), "voyage"))
	if Contact.route_count(state, p) > 0 and not Heroes.council(state, p).is_empty():
		var cur := ContactVoices.interpreter(state, p)
		out.append(UiTheme.dim("Interprète : %s" % (String(cur["name"]) if not cur.is_empty() else "aucun"), 13))
		for h in Heroes.council(state, p):
			if not cur.is_empty() and int(h["id"]) == int(cur["id"]):
				continue
			out.append(_btn(es, "Nommer %s Interprète" % String(h["name"]), ContactVoices.check(state, p, "interpreter", {"hero": int(h["id"])}),
					"+15 % de déchiffrement ; très loyal, il lit le Signal comme une arme sans que les voisins s'en offusquent.", SimCommands.ct_act(p, "interpreter", {"hero": int(h["id"])}), "interp:%d" % int(h["id"])))
	if out.size() > 0:
		out.push_front(HSeparator.new())
	return out


## Blocs des voix (lot 3) dans la colonne principale.
static func voices_content(es: EmpireScreens, col: VBoxContainer) -> void:
	var state := es._state
	var p := es._player
	var v: Dictionary = Contact.sub(state, "voyage").get(str(p), {})
	var inc := Contact.sub(state, "incoming")
	if v.is_empty() and inc.is_empty() and ContactVoices.faith_reaction(state, p) == "":
		return
	var b := Widgets.Block.new("Les voix")
	col.add_child(b)
	if not v.is_empty():
		b.body.add_child(UiTheme.paragraph("Le Voyage des Cinq : %d héros partis, retour le %s." % [(v.get("heroes", []) as Array).size(), GameCalendar.date_string(int(v["until"]))], W, 13))
	var fr := ContactVoices.faith_reaction(state, p)
	if fr != "":
		b.body.add_child(UiTheme.paragraph("Votre foi voit dans le Signal %s." % {"revelation": "une révélation", "heresie": "une hérésie", "epreuve": "une épreuve"}.get(fr, fr), W, 13))
	for k in inc:
		if String(k) != "survive":
			b.body.add_child(UiTheme.paragraph("Quelque chose est en route vers la galaxie (%s)." % String(Crisis.kind_def(String(k)).get("name", k)), W, 13))


static func _status(state: GameState, player: int) -> String:
	if Contact.done(state, player):
		return "la réponse est arrivée"
	if Contact.failed(state, player):
		return "les Lointains ont répondu"
	if Contact.transmitting(state, player):
		return "Transmission %d %%" % Contact.tx_pct(state, player)
	if Contact.captured(state, player):
		return "capté (%d couche%s)" % [Contact.layers(state, player), "s" if Contact.layers(state, player) > 1 else ""]
	if Contact.partial(state, player):
		return "partiel (1 voie sur %d)" % Contact.c_int("capture", "need", 2)
	return "à l'écoute" if Contact.listens(state, player) else "pas encore à l'écoute"


## Lignes de la course et des voix (lots 2 et 3) dans la colonne latérale.
static func side_extra(es: EmpireScreens) -> Array[Control]:
	var out: Array[Control] = []
	var state := es._state
	var player := es._player
	for o: Dictionary in ContactRace.pending_offers(state, player):
		var from := int(o["from"])
		var kind := String(o["kind"])
		var what: String = {"frag_trade": "échanger vos fragments", "frag_demand": "exige votre fragment", "cons_invite": "fonder un Consortium du Signal"}.get(kind, kind)
		out.append(UiTheme.dim("%s propose : %s" % [state.get_empire(from).short_name(), what], 13))
		out.append(_btn(es, "Accepter", ContactRace.check(state, player, "accept", {"kind": kind, "from": from}), "", SimCommands.ct_act(player, "accept", {"kind": kind, "from": from}), "accept:%s:%d" % [kind, from]))
		out.append(_btn(es, "Refuser", ContactRace.check(state, player, "decline", {"kind": kind, "from": from}), "", SimCommands.ct_act(player, "decline", {"kind": kind, "from": from}), "decline:%s:%d" % [kind, from]))
	if ContactRace.cons_id(state, player) >= 0:
		out.append(_btn(es, "Quitter le Consortium", ContactRace.check(state, player, "cons_leave", {}), "Avant la Réponse, vos partenaires y verront une trahison.",
				SimCommands.ct_act(player, "cons_leave"), "cons_leave"))
	out.append_array(voices_side(es))
	return out


## Blocs de la course et des voix (lots 2 et 3) dans la colonne principale.
static func content_extra(es: EmpireScreens, col: VBoxContainer) -> void:
	var state := es._state
	var player := es._player
	if ContactRace.full(state) and Contact.route_count(state, player) > 0:
		var db := Widgets.Block.new("Fragments et Consortium")
		col.add_child(db)
		var held := ContactRace.held_from(state, player)
		var names := PackedStringArray()
		for x in held:
			names.append(state.get_empire(x).short_name())
		db.body.add_child(UiTheme.paragraph("Fragments étrangers : %s" % (", ".join(names) if not names.is_empty() else "aucun"), W, 13))
		var ms := ContactRace.partners(state, player)
		if not ms.is_empty():
			var mn := PackedStringArray()
			for m in ms:
				mn.append(state.get_empire(m).short_name())
			db.body.add_child(UiTheme.paragraph("Consortium : %s (vous gagnerez ensemble)" % ", ".join(mn), W, 13))
		var me := state.get_empire(player)
		for oid in me.contacts:
			var o := state.get_empire(oid)
			if o == null or o.eliminated or not Contact.applies(state, oid):
				continue
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			var lab := Label.new()
			lab.text = o.short_name()
			lab.custom_minimum_size = Vector2(140, 0)
			row.add_child(lab)
			for a in [["frag_trade", "Échanger"], ["frag_give", "Donner"], ["frag_demand", "Exiger"], ["cons_invite", "Consortium"], ["dark_forest", "Forêt sombre"]]:
				var why := Contact.check(state, player, String(a[0]), {"to": oid})
				if String(a[0]) == "dark_forest" and why != "" and not Contact.knows_nature(state, player):
					continue
				var b := Button.new()
				b.text = String(a[1])
				b.focus_mode = Control.FOCUS_NONE
				b.disabled = why != ""
				b.tooltip_text = why
				var cmd := SimCommands.ct_act(player, String(a[0]), {"to": oid})
				b.pressed.connect(func() -> void: es.command_requested.emit(cmd))
				es.contact_buttons["%s:%d" % [a[0], oid]] = b
				row.add_child(b)
			db.body.add_child(row)
		var jam := ContactRace.jammed(state)
		if jam == player:
			db.body.add_child(UiTheme.paragraph("Brouillage : quelque chose, au loin, gêne vos savants (%+d %% de Savoir)." % (-Contact.c_int("jamming", "pct_per_layer", 10) * Contact.layers(state, player)), W, 13))
	voices_content(es, col)


static func _tenths(n: int) -> String:
	@warning_ignore("integer_division")
	return "%d,%d %%" % [n / 10, absi(n) % 10] if n % 10 != 0 else "%d %%" % (n / 10)


static func _btn(es: EmpireScreens, text: String, why: String, tip: String, command: Dictionary, key: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = why != ""
	b.clip_text = true
	b.custom_minimum_size = Vector2(EmpireScreens.SIDE_WIDTH - 24.0, 0)
	b.tooltip_text = tip + ("\n\nImpossible : %s." % why if why != "" else "")
	b.pressed.connect(func() -> void: es.command_requested.emit(command))
	es.contact_buttons[key] = b
	return b


static func signature(es: EmpireScreens) -> String:
	var state := es._state
	if not Contact.applies(state, es._player):
		return "off"
	var e := state.get_empire(es._player)
	var p := es._player
	@warning_ignore("integer_division")
	return "%d|%d|%d|%d|%d|%s|%s|%s|%d|%s" % [e.techs.size(), state.tick / 30, Contact.gauge(state, p) / 10, Contact.route_count(state, p), Contact.layers(state, p),
			str(Contact.tx(state, p)), str(Contact.pending_alert(state, p)), Contact.plans_state(state, p), e.contacts.size(), str(Contact.sub(state, "done"))]
