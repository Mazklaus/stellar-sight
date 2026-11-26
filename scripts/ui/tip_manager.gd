class_name TipManager
extends CanvasLayer
## Les infobulles de tout le jeu (glossaire en jeu, prop. 8 à 22). Godot ne sait pas imbriquer ses
## infobulles : celles du moteur sont coupées (délai géant dans project.godot) et ce gestionnaire les
## remplace toutes, sans toucher aux tooltip_text des contrôles (et à leurs _get_tooltip).
## - Les termes du glossaire sont colorés à leur première apparition (Glossary.link) ;
## - survoler un terme ouvre son infobulle à côté, qui peut en ouvrir une autre (pile de quatre) ;
## - une infobulle se fige (verrouillage) après un instant (minuterie, fine jauge en bas) ou, en mode
##   « action », au clic molette ou tant que Maj est tenue : on peut alors y entrer ;
## - marge et délai de grâce : sortir d'un pixel ne ferme rien ; Échap ferme tout ;
## - clic (gauche ou droit) sur un terme, ou F1 pendant qu'une infobulle de terme est ouverte : le Codex.
## Les textes riches des fenêtres (annonces, événements…) se branchent avec attach_label().

signal article_requested(id: String)

const MAX_STACK := 4
const MARGIN := 10.0
const GRACE := 0.35
const OFFSET := Vector2(16, 22)
const MAX_WIDTH := 360.0
const MIN_WIDTH := 80.0
const NESTED_DELAY := 0.25

static var instance: TipManager

## Réglages (Options, UiSettings) : délai d'apparition, durée de verrouillage, mode.
var delay := 0.35
var lock_time := 0.8
var lock_mode := "minuterie"

var stack: Array[TipPanel] = []
var _owner: Control
var _owner_time := 0.0
var _owner_text := ""
var _owner_moved := Vector2.ZERO
## Lien survolé dans un texte de fenêtre (attach_label) : [label, id].
var _label_link: Array = []
var _label_time := 0.0
var _grace := -1.0


func _init() -> void:
	layer = 50
	name = "TipManager"
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	apply_settings()


func apply_settings() -> void:
	delay = UiSettings.tip_delay
	lock_time = UiSettings.tip_lock
	lock_mode = UiSettings.tip_lock_mode
	Glossary.links_enabled = UiSettings.glossary_links


func is_open() -> bool:
	return not stack.is_empty()


## Une infobulle est figée (le joueur peut y entrer) : Échap la ferme avant tout le reste.
func has_locked() -> bool:
	for t in stack:
		if t.locked:
			return true
	return false


func close_all() -> void:
	for t in stack:
		t.queue_free()
	stack.clear()
	_grace = -1.0
	_owner = null
	_owner_time = 0.0
	_label_link = []


func _mouse() -> Vector2:
	return get_viewport().get_mouse_position()


func _process(delta: float) -> void:
	if not visible:
		return
	var mouse := _mouse()
	if stack.is_empty():
		_idle(delta, mouse)
	else:
		_update_stack(delta, mouse)


# --- Infobulle de base : un contrôle survolé ---------------------------------------------------

func _idle(delta: float, mouse: Vector2) -> void:
	if not _label_link.is_empty():
		var lbl: Control = _label_link[0]
		if not is_instance_valid(lbl) or not lbl.is_visible_in_tree():
			_label_link = []
		else:
			_label_time += delta
			if _label_time >= delay:
				_open(Glossary.tip_text(String(_label_link[1])), String(_label_link[1]), lbl, mouse + OFFSET)
			return
	var owner := _tip_owner(get_viewport().gui_get_hovered_control())
	if owner != _owner:
		_owner = owner
		_owner_time = 0.0
		_owner_moved = mouse
		return
	if owner == null:
		return
	# Le curseur doit s'être posé : un passage rapide n'ouvre rien.
	if mouse.distance_to(_owner_moved) > 6.0:
		_owner_moved = mouse
		_owner_time = 0.0
		return
	_owner_time += delta
	if _owner_time >= delay:
		var text := _owner_tip(owner, mouse)
		if text != "":
			_owner_text = text
			_open(_render(owner, text), "", owner, mouse + OFFSET)


## Le contrôle dont l'infobulle s'applique sous le curseur (le survolé ou un parent), comme Godot.
func _tip_owner(c: Control) -> Control:
	var n: Node = c
	while n is Control:
		var ctl := n as Control
		if _is_ours(ctl):
			return null
		if ctl.tooltip_text != "" or ctl.has_method("_get_tooltip"):
			var t := ctl.get_tooltip(ctl.get_local_mouse_position())
			if t != "":
				return ctl
		if ctl.top_level:
			return null
		n = ctl.get_parent()
	return null


func _owner_tip(owner: Control, _mouse_pos: Vector2) -> String:
	if not is_instance_valid(owner):
		return ""
	return owner.get_tooltip(owner.get_local_mouse_position())


func _is_ours(c: Node) -> bool:
	var n := c
	while n != null:
		if n == self:
			return true
		n = n.get_parent()
	return false


## Texte d'un contrôle -> BBCode lié. Les infobulles de RichTipPanel (ou qui portent déjà des balises
## fermantes) sont du BBCode ; les autres sont du texte brut, échappé.
func _render(owner: Control, text: String) -> String:
	var bb := owner is Widgets.RichTipPanel or text.contains("[/")
	return Glossary.link(text if bb else Glossary.escape_bbcode(text), {})


# --- Pile --------------------------------------------------------------------------------------

func _open(bbcode: String, term_id: String, origin: Control, at: Vector2, parent: TipPanel = null) -> TipPanel:
	if stack.size() >= MAX_STACK:
		var old: TipPanel = stack.pop_front()
		old.queue_free()
	var t := TipPanel.new()
	t.term_id = term_id
	t.origin = origin
	t.parent_tip = parent
	add_child(t)
	t.set_text(bbcode, MAX_WIDTH, MIN_WIDTH)
	t.meta_entered.connect(_on_meta_entered.bind(t))
	t.meta_left.connect(_on_meta_left.bind(t))
	t.meta_activated.connect(func(id: String) -> void: open_article(id))
	stack.append(t)
	t.anchor = at
	t.placer = _replace
	_place(t, at, parent)
	_grace = -1.0
	return t


func _replace(t: TipPanel) -> void:
	_place(t, t.anchor, t.parent_tip if is_instance_valid(t.parent_tip) else null)


## Pose l'infobulle près du point d'ancrage (le pointeur) : en dessous et à droite, sinon au-dessus ou
## à gauche. Rappelée par TipPanel._process quand le texte s'est enroulé et que la vraie taille est
## connue : la première mesure, faite avant l'enroulement, peut être bien plus haute que l'écran.
func _place(t: TipPanel, at: Vector2, parent: TipPanel) -> void:
	if not is_instance_valid(t) or not t.is_inside_tree():
		return
	var vp := get_viewport().get_visible_rect().size
	var sz := t.get_combined_minimum_size()
	t.size = sz
	var pos := at
	if parent != null:
		# À côté de la précédente plutôt que dessus (prop. 21).
		var pr := parent.get_global_rect()
		pos = Vector2(pr.end.x + 6.0, at.y - 18.0)
		if pos.x + sz.x > vp.x - 4.0:
			pos.x = pr.position.x - sz.x - 6.0
	else:
		if pos.x + sz.x > vp.x - 4.0:
			pos.x = at.x - OFFSET.x * 2.0 - sz.x
	if pos.y + sz.y > vp.y - 4.0:
		pos.y = (at.y - OFFSET.y * 2.0 - sz.y) if parent == null else vp.y - 4.0 - sz.y
	pos.x = clampf(pos.x, 4.0, maxf(4.0, vp.x - sz.x - 4.0))
	pos.y = clampf(pos.y, 4.0, maxf(4.0, vp.y - sz.y - 4.0))
	t.position = pos


func _update_stack(delta: float, mouse: Vector2) -> void:
	# Nettoie les origines disparues (écran fermé…).
	if stack[0].origin != null and not is_instance_valid(stack[0].origin):
		close_all()
		return
	for t in stack:
		t.age += delta
	# Verrouillage (prop. 11 et 12).
	var action := lock_mode == "action"
	for i in stack.size():
		var t := stack[i]
		if t.locked:
			continue
		if action:
			if Input.is_key_pressed(KEY_SHIFT):
				t.set_locked(true)
		elif t.age >= lock_time and _origin_hovered(i, mouse):
			t.set_locked(true)
		t.lock_progress = 0.0 if action else clampf(t.age / maxf(0.05, lock_time), 0.0, 1.0)
	# Infobulle de base encore liée à son contrôle : texte vivant, fermeture dès qu'on le quitte.
	var deepest := -1
	for i in stack.size():
		if stack[i].locked and stack[i].get_global_rect().grow(MARGIN).has_point(mouse):
			deepest = i
	var base := stack[0]
	if deepest < 0 and not base.locked:
		if _origin_hovered(0, mouse):
			if base.term_id == "" and is_instance_valid(base.origin):
				var text := _owner_tip(base.origin, mouse)
				if text != _owner_text and text != "":
					_owner_text = text
					base.set_text(_render(base.origin, text), MAX_WIDTH, MIN_WIDTH)
			return
		close_all()
		return
	# Les infobulles au-dessus de la plus profonde où se trouve le curseur.
	var keep := deepest
	if keep < 0:
		keep = 0 if _origin_hovered(0, mouse) and base.locked else -1
	if keep < stack.size() - 1:
		# La suivante, ouverte sur le lien que le curseur survole encore : on la garde.
		var nxt := stack[keep + 1] if keep >= 0 else null
		if nxt != null and stack[keep].hovered_meta == nxt.term_id:
			keep += 1
		if keep < stack.size() - 1:
			if _grace < 0.0:
				_grace = GRACE
			_grace -= delta
			if _grace <= 0.0:
				_close_from(keep + 1)
				_grace = -1.0
			return
	_grace = -1.0
	if keep < 0:
		close_all()
		return
	# Lien survolé dans la plus haute : ouvrir l'infobulle du terme (prop. 10).
	var top := stack[stack.size() - 1]
	if top.locked and top.hovered_meta != "" and top.meta_time >= NESTED_DELAY:
		var id := top.hovered_meta
		top.meta_time = -INF
		_open(Glossary.tip_text(id), id, top, mouse, top)


func _close_from(i: int) -> void:
	while stack.size() > i:
		var t: TipPanel = stack.pop_back()
		t.queue_free()


## L'origine de l'infobulle i est-elle survolée ? (contrôle ou lien de fenêtre pour la base, lien de
## l'infobulle précédente pour les autres)
func _origin_hovered(i: int, mouse: Vector2) -> bool:
	var t := stack[i]
	if i == 0 or t.parent_tip == null:
		if not is_instance_valid(t.origin):
			return false
		if t.term_id != "" and not _label_link.is_empty() and _label_link[0] == t.origin:
			return true
		if t.term_id != "" and t.origin is RichTextLabel:
			return (t.origin as Control).get_global_rect().has_point(mouse) and not _label_link.is_empty()
		var hov := get_viewport().gui_get_hovered_control()
		if hov == null:
			return false
		return hov == t.origin or t.origin.is_ancestor_of(hov)
	return stack.find(t.parent_tip) >= 0 and t.parent_tip.hovered_meta == t.term_id


func _on_meta_entered(id: String, t: TipPanel) -> void:
	t.meta_time = 0.0


func _on_meta_left(_id: String, _t: TipPanel) -> void:
	pass


func _input(event: InputEvent) -> void:
	if stack.is_empty():
		return
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_MIDDLE and lock_mode == "action":
		for t in stack:
			t.set_locked(true)
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE and has_locked():
		close_all()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_F1 and not key.shift_pressed:
		# F1 pendant qu'une infobulle de terme est ouverte : son article (prop. 15). Sinon, F1 reste l'Économie.
		for i in range(stack.size() - 1, -1, -1):
			var id := stack[i].hovered_meta if stack[i].hovered_meta != "" else stack[i].term_id
			if id != "":
				open_article(id)
				get_viewport().set_input_as_handled()
				return


func open_article(id: String) -> void:
	close_all()
	article_requested.emit(id)


# --- Textes riches des fenêtres (prop. 20) ------------------------------------------------------

## Un paragraphe de fenêtre (annonce, événement) dont les termes du glossaire sont soulignés.
static func paragraph(width: float, size := 15) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.custom_minimum_size = Vector2(width, 0)
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	return r


## Pose un texte brut dans un paragraphe et y relie les termes du glossaire.
static func set_linked(rtl: RichTextLabel, plain: String) -> void:
	rtl.text = Glossary.escape_bbcode(plain)
	attach_label(rtl)


## Lie les termes d'un RichTextLabel déjà rempli et branche le survol de ses liens.
static func attach_label(rtl: RichTextLabel, relink := true) -> void:
	rtl.bbcode_enabled = true
	if relink:
		rtl.text = Glossary.link(rtl.text, {})
	if rtl.has_meta("tip_attached"):
		return
	rtl.set_meta("tip_attached", true)
	rtl.meta_underlined = true
	rtl.meta_hover_started.connect(func(meta: Variant) -> void:
		var id := Glossary.meta_id(meta)
		if id != "" and instance != null and instance.stack.is_empty():
			instance._label_link = [rtl, id]
			instance._label_time = 0.0)
	rtl.meta_hover_ended.connect(func(_meta: Variant) -> void:
		if instance != null and not instance._label_link.is_empty() and instance._label_link[0] == rtl:
			instance._label_link = [])
	rtl.meta_clicked.connect(func(meta: Variant) -> void:
		var id := Glossary.meta_id(meta)
		if id != "" and instance != null:
			instance.open_article(id))


## Une infobulle : un panneau sobre et un texte riche, avec la jauge de verrouillage sur son bord bas.
class TipPanel:
	extends PanelContainer
	signal meta_entered(id: String)
	signal meta_left(id: String)
	signal meta_activated(id: String)
	var term_id := ""
	var origin: Control
	var parent_tip: TipPanel
	var locked := false
	var age := 0.0
	var lock_progress := 0.0:
		set(v):
			if absf(v - lock_progress) > 0.01 or (v == 1.0 and lock_progress != 1.0):
				lock_progress = v
				queue_redraw()
	var hovered_meta := ""
	var meta_time := 0.0
	var rtl: RichTextLabel
	## Point d'ancrage (pointeur à l'ouverture) et placement à rejouer quand la taille change.
	var anchor := Vector2.ZERO
	var placer: Callable

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := UiTheme.box(Color(0.03, 0.04, 0.06, 0.96), UiTheme.LINE_STRONG, 0, 1)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 7
		sb.content_margin_bottom = 8
		add_theme_stylebox_override("panel", sb)
		rtl = RichTextLabel.new()
		rtl.bbcode_enabled = true
		rtl.fit_content = true
		rtl.scroll_active = false
		rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rtl.meta_underlined = true
		rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rtl.add_theme_font_override("normal_font", UiTheme.body_font())
		rtl.add_theme_font_override("bold_font", UiTheme.numbers_font())
		rtl.add_theme_font_size_override("normal_font_size", 14)
		rtl.add_theme_font_size_override("bold_font_size", 14)
		rtl.add_theme_color_override("default_color", UiTheme.TEXT)
		add_child(rtl)
		rtl.meta_hover_started.connect(func(meta: Variant) -> void:
			var id := Glossary.meta_id(meta)
			if id != "":
				hovered_meta = id
				meta_entered.emit(id))
		rtl.meta_hover_ended.connect(func(meta: Variant) -> void:
			var id := Glossary.meta_id(meta)
			if id == hovered_meta:
				hovered_meta = ""
				meta_left.emit(id))
		rtl.meta_clicked.connect(func(meta: Variant) -> void:
			var id := Glossary.meta_id(meta)
			if id != "":
				meta_activated.emit(id))
		rtl.gui_input.connect(func(ev: InputEvent) -> void:
			var mb := ev as InputEventMouseButton
			if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and hovered_meta != "":
				meta_activated.emit(hovered_meta))

	func _process(delta: float) -> void:
		if hovered_meta != "" and meta_time > -INF:
			meta_time += delta
		# Le texte s'enroule une fois sa largeur connue : le panneau reprend alors sa vraie hauteur.
		var want := get_combined_minimum_size()
		if absf(size.y - want.y) > 1.0 or absf(size.x - want.x) > 1.0:
			size = want
			if placer.is_valid():
				placer.call(self)
				return
			var vp := get_viewport_rect().size
			position = Vector2(clampf(position.x, 4.0, maxf(4.0, vp.x - want.x - 4.0)), clampf(position.y, 4.0, maxf(4.0, vp.y - want.y - 4.0)))

	## Largeur : celle du texte, entre min_w et max_w (une ligne courte ne fait pas un pavé).
	func set_text(bb: String, max_w: float, min_w: float) -> void:
		rtl.text = bb
		var plain := rtl.get_parsed_text()
		var widest := 0.0
		var f := UiTheme.body_font()
		for line in plain.split("\n"):
			widest = maxf(widest, f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x)
		rtl.custom_minimum_size = Vector2(clampf(widest + 6.0, min_w, max_w), 0)
		reset_size()

	func set_locked(v: bool) -> void:
		if locked == v:
			return
		locked = v
		lock_progress = 1.0 if v else 0.0
		mouse_filter = Control.MOUSE_FILTER_STOP if v else Control.MOUSE_FILTER_IGNORE
		rtl.mouse_filter = Control.MOUSE_FILTER_PASS if v else Control.MOUSE_FILTER_IGNORE
		queue_redraw()

	func _draw() -> void:
		# Jauge de verrouillage : un filet qui se remplit sur le bord bas (prop. 11).
		if lock_progress <= 0.0:
			return
		var w := size.x * lock_progress
		draw_line(Vector2(0, size.y - 1.0), Vector2(w, size.y - 1.0), Color(UiTheme.ACCENT, 0.85 if locked else 0.55), 2.0)
