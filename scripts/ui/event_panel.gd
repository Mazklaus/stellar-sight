class_name EventPanel
extends CanvasLayer
## Fenêtre d'événement (voir Events) : illustration à gauche, puis à droite titre, texte, puis un bouton par choix avec ses
## effets chiffrés et, pour un choix réservé à une couche d'espèce, l'étiquette de cette couche.
## main.gd l'ouvre quand une carte arrive dans la boîte du joueur (pause automatique en solo).
## « Réduire » la laisse dans la boîte : l'écran Chroniques (J) la rouvre. Sans réponse au bout de
## 30 jours, le choix par défaut s'applique tout seul.

const LONG_TEXT := 700  # au-delà, le récit défile
const LONG_HEIGHT := 330.0

signal choice_made(event_id: int, index: int)
signal locate_requested(system_id: int)
signal minimized

const WIDTH := 600.0

## Carte affichée (identifiant d'événement), -1 si fermée.
var event_id := -1
## Boutons des choix, par index de choix dans la carte (pour les tests).
var choice_buttons := {}
var _art: Widgets.ArtSlot
var _title: Label
var _when: Label
var _voice: Label  # premier contact : qui parle au nom du peuple rencontré
var _head: Widgets.NotchHeader
var _text: RichTextLabel
var _choices: VBoxContainer
var _locate: Widgets.RoundButton
var _system := -1


func _ready() -> void:
	# Illustration à gauche sur toute la hauteur (images générées en fin de projet : assets/art/event_<carte>).
	var box := AnnounceFrame.build(self, WIDTH, "Décision", 10, AnnounceFrame.ART_WIDTH)
	_art = AnnounceFrame.art_of(self)
	_title = UiTheme.title("", 28)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size = Vector2(WIDTH, 0)
	box.add_child(_title)
	_when = UiTheme.dim("", 13)
	box.add_child(_when)
	_voice = UiTheme.title("", 17)
	_voice.add_theme_color_override("font_color", UiTheme.GOLD)
	_voice.visible = false
	_voice.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_voice)
	_text = TipManager.paragraph(WIDTH - 20.0, 15)
	box.add_child(_text)
	_head = Widgets.NotchHeader.new("Votre décision", 14)
	box.add_child(_head)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 8)
	box.add_child(_choices)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 40)
	box.add_child(buttons)
	_locate = Widgets.RoundButton.new("next", "Montrer l'emplacement", 14)
	_locate.pressed.connect(func() -> void:
		if _system >= 0:
			locate_requested.emit(_system))
	buttons.add_child(_locate)
	var later := Widgets.RoundButton.new("back", "Réduire", 14)
	later.tooltip_text = "La carte reste dans votre boîte (Chroniques, touche J). Sans réponse, le choix par défaut s'appliquera."
	later.pressed.connect(func() -> void: minimized.emit())
	buttons.add_child(later)


## Affiche la carte item de la boîte de player.
func open(state: GameState, player: int, item: Dictionary) -> void:
	event_id = int(item["id"])
	var c := Events.card(String(item["card"]))
	_title.text = Events.fill(state, player, item, String(c.get("title", "")))
	var body := Events.fill(state, player, item, String(c.get("text", "")))
	TipManager.set_linked(_text, body)
	# Un récit long (chaînes, E7) défile dans la fenêtre au lieu de la faire déborder de l'écran.
	var long := body.length() > LONG_TEXT
	_text.fit_content = not long
	_text.scroll_active = long
	_text.custom_minimum_size.y = LONG_HEIGHT if long else 0.0
	var left := maxi(0, int(item["until"]) - state.tick)
	_when.text = "%s  ·  sans réponse dans %d jour%s, le choix par défaut s'appliquera" % [
			GameCalendar.date_string(int(item["tick"])), left, "s" if left > 1 else ""]
	var motif := "star"
	match String(c.get("trigger", "")):
		"curio":
			motif = "planet"
		"contact":
			motif = "faction"
	_art.set_art("event_%s" % String(item["card"]), Color(0.95, 0.78, 0.45), motif)
	# Premier contact (refonte, E4) : la scène du peuple rencontré, sa voix, son salut, puis votre réponse.
	var contact := bool(c.get("contact", false))
	var rival := state.get_empire(int(item.get("rival", -1)))
	# G2 : le motif de la chaîne revient à chacune de ses cartes. D7 : au premier contact, l'indicatif
	# du peuple rencontré, joué en entier et lentement.
	Son.chain_motif(String(c.get("chain", "")))
	if contact and rival != null:
		PeopleSound.hail(rival.faction_id, "contact", body)
	_voice.visible = contact and rival != null
	_head.text = "Votre réponse" if contact else "Votre décision"
	for n in _title.get_parent().get_children():
		if n is AnnounceFrame.DecisionBand:
			(n as AnnounceFrame.DecisionBand).tag = "PREMIER CONTACT" if contact else "DÉCISION"
			n.queue_redraw()
	_head.queue_redraw()
	if _voice.visible:
		_voice.text = Events.contact_voice(state, item)
		_voice.tooltip_text = "%s  ·  %s" % [String(rival.faction().get("registre", "")), rival.display_name()]
		_when.text = "%s  ·  sans réponse dans %d jour%s, vous garderez vos distances" % [
				GameCalendar.date_string(int(item["tick"])), left, "s" if left > 1 else ""]
		_art.set_art("faction_%s_scene" % rival.faction_id, rival.color(), "faction")
	_system = int(item.get("system", -1))
	if _system < 0 and int(item.get("planet", -1)) >= 0:
		_system = state.galaxy.get_planet(int(item["planet"])).system_id
	_locate.visible = _system >= 0
	for ch in _choices.get_children():
		ch.queue_free()
	choice_buttons.clear()
	for o: Dictionary in Events.choices(state, player, item):
		_choices.add_child(_choice_row(o))
	visible = true
	AnnounceFrame.fade_in(self)


func _choice_row(o: Dictionary) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var b := Button.new()
	b.theme_type_variation = &"PrimaryButton"
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(WIDTH, 0)
	var label := String(o["label"])
	if String(o["tag"]) != "":
		label = "[%s]  %s" % [o["tag"], label]
	if bool(o["risky"]):
		label += "  (pari : %d %%)" % int(o["pct"])
	b.text = label
	b.disabled = not bool(o["ok"])
	if not bool(o["ok"]):
		b.tooltip_text = String(o["why"])
	var index := int(o["index"])
	b.pressed.connect(func() -> void: choice_made.emit(event_id, index))
	row.add_child(b)
	choice_buttons[index] = b
	var lines: Array = (o["lines"] as Array).duplicate()
	if bool(o["risky"]):
		var win: Array = o["win"]
		var lose: Array = o["lose"]
		lines.append("Réussite : %s" % (", ".join(win) if not win.is_empty() else "rien de plus"))
		lines.append("Échec : %s" % (", ".join(lose) if not lose.is_empty() else "rien de plus"))
	if not lines.is_empty() or not bool(o["ok"]):
		var txt := "   ".join(lines)
		if not bool(o["ok"]):
			txt = (txt + "   " if txt != "" else "") + String(o["why"])
		var l := UiTheme.paragraph(txt, WIDTH - 20.0, 13)
		l.add_theme_color_override("font_color", UiTheme.TEXT_DIM if bool(o["ok"]) else UiTheme.BAD)
		row.add_child(l)
	return row


func close() -> void:
	visible = false
	event_id = -1


func is_open() -> bool:
	return visible
