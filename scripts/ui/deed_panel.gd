class_name DeedPanel
extends CanvasLayer
## Fenêtre de haut fait (voir Deeds, prop. 23) : illustration, nom du haut fait, ce qu'il a fallu
## accomplir, la Gloire gagnée, puis un bouton par récompense tirée (trois au plus).
## main.gd l'ouvre quand un haut fait arrive dans la boîte du joueur (pause automatique en solo).
## « Réduire » la laisse dans la boîte : l'onglet Hauts faits des Chroniques (J) la rouvre. Sans
## réponse au bout de 30 jours, la première récompense possible est prise.

signal choice_made(item_id: int, index: int)
signal minimized

const WIDTH := 600.0

## Entrée affichée (identifiant de boîte), -1 si fermée.
var item_id := -1
## Boutons des récompenses, par index (pour les tests).
var choice_buttons := {}
var _art: Widgets.ArtSlot
var _title: Label
var _sub: Label
var _text: Label
var _flavor: Label
var _choices: VBoxContainer


func _ready() -> void:
	layer = 7
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.03, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var window := PanelContainer.new()
	window.theme_type_variation = &"WindowPanel"
	center.add_child(window)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(WIDTH, 0)
	box.add_theme_constant_override("separation", 10)
	window.add_child(box)
	# Emplacement d'illustration (images générées en fin de projet : assets/art/deed_<haut fait>).
	_art = Widgets.ArtSlot.new("", Vector2(WIDTH, 150), Color(0.95, 0.82, 0.4), "star")
	box.add_child(_art)
	var head := UiTheme.dim("HAUT FAIT GALACTIQUE", 13)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	_title = UiTheme.title("", 28)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_title)
	_sub = UiTheme.dim("", 13)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_sub)
	_text = UiTheme.paragraph("", WIDTH - 20.0, 15)
	box.add_child(_text)
	_flavor = UiTheme.paragraph("", WIDTH - 20.0, 14)
	_flavor.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	box.add_child(_flavor)
	box.add_child(Widgets.NotchHeader.new("Choisissez votre récompense", 14))
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 8)
	box.add_child(_choices)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)
	var later := Widgets.RoundButton.new("back", "Réduire", 14)
	later.tooltip_text = "Le choix reste dans votre boîte (Chroniques, touche J, onglet Hauts faits). Sans réponse, la première récompense sera prise."
	later.pressed.connect(func() -> void: minimized.emit())
	buttons.add_child(later)


## Affiche l'entrée item de la boîte de player.
func open(state: GameState, player: int, item: Dictionary) -> void:
	item_id = int(item["id"])
	var id := String(item["deed"])
	var d := Deeds.def(id)
	var fam := Deeds.family(id)
	_title.text = Deeds.label(id)
	var left := maxi(0, int(item["until"]) - state.tick)
	var g := 0
	for x: Dictionary in Deeds.annals_of(state, player):
		if String(x["id"]) == id and String(x["k"]) == "deed":
			g = int(x["g"])
	_sub.text = "%s  ·  %s  ·  +%d Gloire  ·  sans réponse dans %d jour%s, la première récompense sera prise" % [
			Deeds.family_label(fam), GameCalendar.date_string(int(item["tick"])), g, left, "s" if left > 1 else ""]
	var txt := String(d.get("text", ""))
	var t := String(d.get("title", ""))
	if t != "" and Deeds.title_holder(state, t) == player:
		txt += "  Titre honorifique : %s." % Deeds.title_label(t)
	_text.text = txt
	_flavor.text = "« %s »" % String(d.get("flavor", "")) if String(d.get("flavor", "")) != "" else ""
	_art.set_art("deed_%s" % id, Deeds.family_color(fam), "star")
	for ch in _choices.get_children():
		ch.queue_free()
	choice_buttons.clear()
	var opts := Deeds.reward_options(state, player)
	var i := 0
	for rid in item["ch"]:
		_choices.add_child(_choice_row(state, player, String(rid), i, opts.has(String(rid))))
		i += 1
	visible = true


func _choice_row(state: GameState, player: int, rid: String, index: int, ok: bool) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var b := Button.new()
	b.theme_type_variation = &"PrimaryButton"
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(WIDTH, 0)
	b.text = String(Deeds.reward_def(rid).get("label", rid))
	b.disabled = not ok
	b.pressed.connect(func() -> void: choice_made.emit(item_id, index))
	row.add_child(b)
	choice_buttons[index] = b
	var l := UiTheme.paragraph(Deeds.reward_text(state, player, rid) if ok else "N'est plus disponible.", WIDTH - 20.0, 13)
	l.add_theme_color_override("font_color", UiTheme.TEXT_DIM if ok else UiTheme.BAD)
	row.add_child(l)
	return row


func close() -> void:
	visible = false
	item_id = -1


func is_open() -> bool:
	return visible
