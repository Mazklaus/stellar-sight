class_name CodexScreen
extends CanvasLayer
## Le Codex de l'Archonte en jeu (glossaire en jeu, lot 2, prop. 23 à 36) : l'encyclopédie plein écran,
## ouverte par l'icône de livre de la barre d'empire, par Maj+F1, ou depuis un mot coloré d'une infobulle
## (clic, clic droit, F1). Mise en page de la Civilopédie (Civilization VI) en trois colonnes :
## à gauche la recherche et la liste, au centre l'article, à droite la fiche, l'illustration, les
## « voir aussi », le lien vers le manuel et l'épingle. Quatre familles en onglets : Mécanismes,
## Univers, Bestiaire et secrets, Chroniques. Précédent / Suivant comme un navigateur.
## Fonctionne en partie et depuis le menu principal (les secrets y restent scellés).

signal closed

const LEFT_W := 330.0
const RIGHT_W := 300.0
const NEW_COLOR := Color(0.38, 0.86, 0.92)
const HOME := "man:02-premiere-partie"

var family := "meca"
var current := ""
var history: Array[String] = []
var future: Array[String] = []
var _root: Control
var _tabs := {}
var _search: LineEdit
var _tree: Tree
var _kicker: Label
var _title: Label
var _quote: RichTextLabel
var _body: RichTextLabel
var _captures: VBoxContainer
var _scroll: ScrollContainer
var _art: Widgets.ArtSlot
var _rows: GridContainer
var _also: VBoxContainer
var _manual_btn: Button
var _pin_btn: Button
var _back_btn: Button
var _fwd_btn: Button
var _count: Label
var _search_timer := -1.0
var _tex_cache := {}


func _init() -> void:
	layer = 11
	name = "CodexScreen"
	visible = false


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UiTheme.theme()
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color(UiTheme.BG, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	var outer := MarginContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, 18)
	_root.add_child(outer)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	outer.add_child(v)

	# Bandeau : titre, familles, navigation, fermeture.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 22)
	v.add_child(head)
	var t := UiTheme.title("CODEX DE L'ARCHONTE", 24)
	head.add_child(t)
	for f: Dictionary in Glossary.families:
		var b := Button.new()
		b.theme_type_variation = &"TabButton"
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.text = String(f["label"]).to_upper()
		var fid := String(f["id"])
		b.pressed.connect(func() -> void: show_family(fid))
		head.add_child(b)
		_tabs[fid] = b
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_back_btn = _small_button("PRÉC.", "Article précédent")
	_back_btn.pressed.connect(go_back)
	head.add_child(_back_btn)
	_fwd_btn = _small_button("SUIV.", "Article suivant")
	_fwd_btn.pressed.connect(go_forward)
	head.add_child(_fwd_btn)
	var close := Widgets.IconButton.new("close", 30)
	close.tooltip_text = "Fermer le Codex (Échap, Maj+F1)"
	close.pressed.connect(close_codex)
	head.add_child(close)
	var rule := ColorRect.new()
	rule.color = UiTheme.LINE
	rule.custom_minimum_size = Vector2(0, 1)
	v.add_child(rule)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	v.add_child(body)

	# Colonne de gauche : recherche et liste.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(LEFT_W, 0)
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)
	_search = LineEdit.new()
	_search.placeholder_text = "Rechercher (sans accents ni pluriels)…"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void: _search_timer = 0.25)
	left.add_child(_search)
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PANEL, UiTheme.LINE, 6, 1))
	_tree.add_theme_font_override("font", UiTheme.body_font())
	_tree.add_theme_font_size_override("font_size", 14)
	_tree.item_selected.connect(_on_tree_selected)
	left.add_child(_tree)
	_count = UiTheme.dim("", 12)
	left.add_child(_count)

	# Centre : l'article.
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 8)
	_scroll.add_child(center)
	_kicker = UiTheme.dim("", 13)
	center.add_child(_kicker)
	_title = UiTheme.title("", 30)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	center.add_child(_title)
	_quote = _rich(15)
	_quote.add_theme_color_override("default_color", Color(0.85, 0.8, 0.68))
	center.add_child(_quote)
	_body = _rich(15)
	center.add_child(_body)
	_captures = VBoxContainer.new()
	_captures.add_theme_constant_override("separation", 6)
	center.add_child(_captures)

	# Colonne de droite : illustration, fiche, voir aussi.
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(RIGHT_W, 0)
	right.add_theme_constant_override("separation", 10)
	body.add_child(right)
	_art = Widgets.ArtSlot.new("", Vector2(RIGHT_W, 170))
	right.add_child(_art)
	_rows = GridContainer.new()
	_rows.columns = 2
	_rows.add_theme_constant_override("h_separation", 12)
	_rows.add_theme_constant_override("v_separation", 4)
	right.add_child(_rows)
	_manual_btn = _small_button("LIRE DANS LE MANUEL", "L'article du manuel qui l'explique en détail")
	right.add_child(_manual_btn)
	_pin_btn = _small_button("ÉPINGLER", "Garder cet article en tête de la liste")
	_pin_btn.pressed.connect(func() -> void:
		CodexPrefs.toggle_pin(current)
		_sync_pin()
		_build_tree())
	right.add_child(_pin_btn)
	right.add_child(UiTheme.section("Voir aussi"))
	_also = VBoxContainer.new()
	_also.add_theme_constant_override("separation", 2)
	right.add_child(_also)


func _small_button(text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.theme_type_variation = &"TabButton"
	return b


func _rich(size: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.selection_enabled = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_font_override("normal_font", UiTheme.body_font())
	r.add_theme_font_override("bold_font", UiTheme.numbers_font())
	r.add_theme_font_override("italics_font", UiTheme.font(300))
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_font_size_override("italics_font_size", size)
	r.add_theme_color_override("default_color", UiTheme.TEXT)
	r.add_theme_constant_override("line_separation", 3)
	return r


func _process(delta: float) -> void:
	if _search_timer >= 0.0:
		_search_timer -= delta
		if _search_timer < 0.0:
			_build_tree()


# --- Ouverture -------------------------------------------------------------------------------------

func is_open() -> bool:
	return visible


func open(aid := "") -> void:
	CodexData.ensure_loaded()
	CodexPrefs.scan()
	visible = true
	if aid == "" or not CodexData.exists(aid):
		aid = current if current != "" else HOME
	navigate(aid)  # un article demandé s'ajoute à l'historique : Préc. ramène où l'on était


func close_codex() -> void:
	if not visible:
		return
	visible = false
	if TipManager.instance != null:
		TipManager.instance.close_all()
	closed.emit()


func toggle(aid := "") -> void:
	if visible and aid == "":
		close_codex()
	else:
		open(aid)


func show_family(fid: String) -> void:
	family = fid
	for f in _tabs:
		(_tabs[f] as Button).set_pressed_no_signal(f == fid)
	_build_tree()


# --- Navigation ------------------------------------------------------------------------------------

func navigate(aid: String, push := true) -> void:
	if not CodexData.exists(aid):
		return
	if push and current != "" and current != aid:
		history.append(current)
		future.clear()
	current = aid
	var fam := CodexData.family_of(aid)
	if fam != family or _tree.get_root() == null:
		show_family(fam)
	_show(aid)
	_select_in_tree(aid)


func go_back() -> void:
	if history.is_empty():
		return
	future.append(current)
	navigate(history.pop_back(), false)


func go_forward() -> void:
	if future.is_empty():
		return
	history.append(current)
	navigate(future.pop_back(), false)


# --- Liste -----------------------------------------------------------------------------------------

func _build_tree() -> void:
	_tree.clear()
	var root := _tree.create_item()
	var q := _search.text.strip_edges()
	if q.length() >= 2:
		var res := CodexData.search(q, CodexPrefs.unlocked)
		var groups := {}
		for r: Dictionary in res:
			var fl := String(r["family"])
			if not groups.has(fl):
				groups[fl] = _group(root, "%s" % Glossary.family_label(fl), false)
			_leaf(groups[fl], String(r["id"]), String(r["title"]))
		_count.text = "%d résultat%s" % [res.size(), "s" if res.size() > 1 else ""] if not res.is_empty() else "Aucun résultat."
		return
	_count.text = ""
	if not CodexPrefs.pins.is_empty() and family == "meca":
		var pg := _group(root, "Épinglés", false)
		for aid in CodexPrefs.pins:
			if CodexData.exists(aid):
				_leaf(pg, aid, CodexData.title_of(aid))
	match family:
		"meca":
			_lexicon(root)
			_manual(root, "meca")
			_catalogs(root, "meca")
		"univers":
			_catalogs(root, "univers")
			_manual(root, "univers")
		"bestiaire":
			_catalogs(root, "bestiaire")
			_manual(root, "bestiaire")
		"chroniques":
			_chronicles(root)
	_select_in_tree(current)


func _group(parent: TreeItem, text: String, collapsed := true) -> TreeItem:
	var it := _tree.create_item(parent)
	it.set_text(0, text.to_upper())
	it.set_selectable(0, false)
	it.set_custom_color(0, UiTheme.TEXT_DIM)
	it.collapsed = collapsed
	return it


func _leaf(parent: TreeItem, aid: String, text: String) -> TreeItem:
	var it := _tree.create_item(parent)
	var locked := not CodexPrefs.unlocked(aid)
	var label := text
	if locked:
		label = "Fragment scellé" if aid.begins_with("frag:") else Glossary.LOCKED_NAME
	if CodexPrefs.is_new(aid):
		label = "• " + label
		it.set_custom_color(0, NEW_COLOR)
	elif locked:
		it.set_custom_color(0, UiTheme.TEXT_DIM)
	it.set_text(0, label)
	it.set_metadata(0, aid)
	return it


func _lexicon(root: TreeItem) -> void:
	var lex := _group(root, "Lexique (%d)" % Glossary.order.size())
	var letters := {}
	for tid in Glossary.order:
		if String(Glossary.term(tid).get("family", "meca")) != "meca":
			continue
		var l := CodexData.normalize(Glossary.display_name(tid).substr(0, 1)).to_upper()
		if not letters.has(l):
			letters[l] = _group(lex, l)
		_leaf(letters[l], tid, Glossary.display_name(tid))


func _manual(root: TreeItem, fam: String) -> void:
	var man := _group(root, "Le manuel" if fam == "meca" else "Dans le manuel", fam != "meca")
	for c: Dictionary in CodexData.chapters:
		if CodexData.chapter_family(String(c["file"])) != fam:
			continue
		var secret := bool(c.get("secret", false))
		var ch := _group(man, CodexData.chapter_label(c))
		ch.set_custom_color(0, UiTheme.TEXT)
		for s: Dictionary in c.get("sections", []):
			var aid := "man:" + String(s["id"])
			var title := String(s["title"])
			if secret and not CodexPrefs.unlocked(aid):
				title = "Section scellée"
			_leaf(ch, aid, title)


func _catalogs(root: TreeItem, fam: String) -> void:
	for c: Dictionary in CodexCatalogs.CATALOGS:
		if String(c["family"]) != fam:
			continue
		var es := CodexCatalogs.entries(String(c["id"]))
		var g := _group(root, "%s (%d)" % [String(c["label"]), es.size()], fam == "meca")
		for e: Dictionary in es:
			_leaf(g, String(e["id"]), String(e["name"]))


func _chronicles(root: TreeItem) -> void:
	var n := CodexPrefs.chronicle_count()
	_count.text = "%d fragment%s sur %d. Ils se débloquent quand la chronique de vos parties nomme un mot de leur chapitre, et restent acquis d'une partie à l'autre." % [n.x, "s" if n.x > 1 else "", n.y]
	var by_ch := {}
	for fr: Dictionary in CodexData.fragments:
		var ch := String(fr["chapter"])
		if not by_ch.has(ch):
			by_ch[ch] = _group(root, CodexData.chapter_label(CodexData.chapter(ch)), false)
		_leaf(by_ch[ch], "frag:" + String(fr["id"]), String(fr.get("source", "Fragment")))


func _on_tree_selected() -> void:
	var it := _tree.get_selected()
	if it == null:
		return
	var aid: Variant = it.get_metadata(0)
	if aid is String and String(aid) != current:
		navigate(String(aid))


func _select_in_tree(aid: String) -> void:
	var root := _tree.get_root()
	if root == null:
		return
	var it := _find_item(root, aid)
	if it != null:
		var p := it.get_parent()
		while p != null:
			p.collapsed = false
			p = p.get_parent()
		_tree.set_block_signals(true)
		it.select(0)
		_tree.set_block_signals(false)
		_tree.scroll_to_item(it)


func _find_item(it: TreeItem, aid: String) -> TreeItem:
	if it.get_metadata(0) is String and String(it.get_metadata(0)) == aid:
		return it
	var c := it.get_first_child()
	while c != null:
		var r := _find_item(c, aid)
		if r != null:
			return r
		c = c.get_next()
	return null


# --- Article ---------------------------------------------------------------------------------------

func _show(aid: String) -> void:
	for c in _rows.get_children() + _also.get_children() + _captures.get_children():
		c.queue_free()
	_quote.text = ""
	_quote.visible = false
	_manual_btn.visible = false
	for cn in _manual_btn.pressed.get_connections():
		_manual_btn.pressed.disconnect(cn["callable"])
	_back_btn.disabled = history.is_empty()
	_fwd_btn.disabled = future.is_empty()
	var locked := not CodexPrefs.unlocked(aid)
	var seen := {}
	var also: Array[String] = []
	var art_id := ""
	if aid.begins_with("man:"):
		var sid := aid.substr(4)
		var s := CodexData.section(sid)
		var c := CodexData.section_chapter(sid)
		_kicker.text = ("%s · %s" % [Glossary.family_label(CodexData.chapter_family(String(c["file"]))), CodexData.chapter_label(c)]).to_upper()
		_title.text = CodexData.title_of(aid)
		if locked:
			_body.text = "[i]Cette page de la zone scellée ne s'ouvre qu'à ceux qui ont croisé ce qu'elle décrit.[/i]"
		else:
			if String(s["title"]) == "Présentation" and String(c.get("epigraph", "")) != "":
				_set_quote(String(c["epigraph"]), String(c.get("signature", "")))
			_body.text = Glossary.link(String(s["text"]), seen)
			for p in s.get("captures", []):
				_add_capture(String(p))
			also = _terms_of(seen, 6)
			art_id = String(c["file"])
	elif aid.begins_with("frag:"):
		var fr := CodexData.fragment(aid.substr(5))
		var c := CodexData.chapter(String(fr["chapter"]))
		_kicker.text = ("Chroniques · %s" % CodexData.chapter_label(c)).to_upper()
		if locked:
			_title.text = "Fragment scellé"
			_body.text = "[i]Ce fragment se débloquera quand la chronique d'une de vos parties nommera un mot de ce chapitre.[/i]"
		else:
			_title.text = String(fr.get("source", "Fragment"))
			var txt := "[i]%s[/i]" % Glossary.link(Glossary.escape_bbcode(String(fr["text"])), seen)
			if String(fr.get("signature", "")) != "":
				txt += "\n\n[right]— %s[/right]" % Glossary.escape_bbcode(String(fr["signature"]))
			_body.text = txt
			_manual_link("man:" + String(fr["chapter"]))
	else:
		var t := Glossary.term(aid)
		var cat := String(t.get("cat", ""))
		var where := String(CodexCatalogs.catalog_def(cat).get("label", "Lexique")) if cat != "" else "Lexique"
		_kicker.text = ("%s · %s" % [Glossary.family_label(String(t.get("family", "meca"))), where]).to_upper()
		_title.text = Glossary.display_name(aid)
		if locked:
			_body.text = "[i]Pas encore rencontré. L'article se remplira quand vous le croiserez dans la galaxie.[/i]"
		elif cat != "":
			if String(t.get("quote", "")) != "":
				_set_quote(String(t["quote"]), "")
			_body.text = Glossary.link(_md_bold(String(t.get("body", t.get("summary", "")))), seen, aid)
			for r in t.get("rows", []):
				_add_row(String(r[0]), String(r[1]))
			also = _terms_of(seen, 6)
			art_id = "codex_" + aid.replace(":", "_")
			if not (t.get("chapters", []) as Array).is_empty():
				_manual_link("man:" + String(t["chapters"][0]))
		else:
			seen[aid] = true
			var summ := String(t.get("summary", ""))
			var senses := summ.split(" ; et ")
			var txt := ""
			if senses.size() > 1:
				for k in senses.size():
					txt += "%d. %s\n" % [k + 1, Glossary.link(Glossary.escape_bbcode(senses[k].strip_edges()), seen, aid)]
			else:
				txt = Glossary.link(Glossary.escape_bbcode(summ), seen, aid) + "\n"
			var sid := CodexData.section_for_term(aid)
			if sid != "":
				var s := CodexData.section(sid)
				var c := CodexData.section_chapter(sid)
				var place := CodexData.chapter_label(c).to_upper()
				if CodexData.title_of("man:" + sid) != String(c.get("title", "")):
					place += " · " + CodexData.title_of("man:" + sid).to_upper()
				txt += "\n[color=#7f8a96][font_size=13]DANS LE MANUEL · %s[/font_size][/color]\n\n%s" % [place, Glossary.link(String(s["text"]), seen, aid)]
				_manual_link("man:" + sid)
			_body.text = txt
			also = Glossary.see_also(aid, 6)
			for nums in t.get("chapters", []):
				var c2 := CodexData.chapter(String(nums))
				if not c2.is_empty():
					_add_row("Chapitre", CodexData.chapter_label(c2))
	_art.set_art(art_id, UiTheme.ACCENT)
	_art.visible = art_id != ""
	for a in also:
		if a == aid or not CodexData.exists(a):
			continue
		var b := Button.new()
		b.text = CodexData.title_of(a)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_color_override("font_color", Color(Glossary.LINK_COLOR))
		b.pressed.connect(navigate.bind(a))
		_also.add_child(b)
	_sync_pin()
	_body.meta_underlined = true
	TipManager.attach_label(_body, false)  # déjà relié, sans le terme de l'article lui-même
	_scroll.scroll_vertical = 0
	if not locked:
		CodexPrefs.mark_read(aid)
	_refresh_new_marks(aid)


## Le gras Markdown des données (**…**) en BBCode.
func _md_bold(text: String) -> String:
	var re := RegEx.create_from_string("\\*\\*(.+?)\\*\\*")
	return re.sub(text, "[b]$1[/b]", true)


func _terms_of(seen: Dictionary, n: int) -> Array[String]:
	var out: Array[String] = []
	for k: String in seen:
		if out.size() >= n:
			break
		if k != current:
			out.append(k)
	return out


func _set_quote(text: String, sig: String) -> void:
	_quote.visible = true
	_quote.text = "[i]« %s »[/i]%s" % [Glossary.escape_bbcode(text.trim_prefix("« ").trim_suffix(" »")), ("\n[right][font_size=13]— %s[/font_size][/right]" % Glossary.escape_bbcode(sig)) if sig != "" else ""]


func _add_row(k: String, v: String) -> void:
	var a := UiTheme.dim(k, 13)
	_rows.add_child(a)
	var b := Label.new()
	b.text = v
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(RIGHT_W - 110.0, 0)
	b.add_theme_font_size_override("font_size", 13)
	_rows.add_child(b)


func _manual_link(target: String) -> void:
	if not CodexData.exists(target) or target == current:
		return
	_manual_btn.visible = true
	_manual_btn.pressed.connect(navigate.bind(target))


func _sync_pin() -> void:
	_pin_btn.text = "DÉSÉPINGLER" if CodexPrefs.pins.has(current) else "ÉPINGLER"


## Captures du manuel dans l'article (prop. 36), lues directement dans docs/.
func _add_capture(path: String) -> void:
	var tex: Texture2D = _tex_cache.get(path)
	if tex == null:
		var img := Image.load_from_file(ProjectSettings.globalize_path("res://" + path))
		if img == null or img.is_empty():
			return
		tex = ImageTexture.create_from_image(img)
		_tex_cache[path] = tex
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	var w := 640.0
	tr.custom_minimum_size = Vector2(w, w * tex.get_height() / maxf(1.0, tex.get_width()))
	_captures.add_child(tr)


## La pastille d'un article lu s'éteint dans la liste.
func _refresh_new_marks(aid: String) -> void:
	var root := _tree.get_root()
	if root == null:
		return
	var it := _find_item(root, aid)
	if it != null and it.get_text(0).begins_with("• "):
		it.set_text(0, it.get_text(0).substr(2))
		it.clear_custom_color(0)


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		if key.keycode == KEY_ESCAPE:
			close_codex()
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_F1 and key.shift_pressed:
			close_codex()
			get_viewport().set_input_as_handled()
