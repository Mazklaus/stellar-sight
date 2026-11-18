class_name Glossary
extends RefCounted
## Le dictionnaire du jeu (data/glossary.json), commun aux infobulles imbriquées, au Codex de
## l'Archonte et à l'annexe B du manuel (glossaire en jeu, prop. 1 à 7).
## link() repère les termes dans un texte (BBCode) et en fait des liens « glo:<id> », colorés et
## soulignés, à leur première apparition seulement ; TipManager ouvre leur infobulle au survol.
## Les fiches des catalogues (peuples, créatures, gardiens, crises, anciennes, merveilles) sont aussi
## des termes reconnus (CodexCatalogs) : verrouillées, elles ne se colorent qu'une fois rencontrées.

const PATH := "res://data/glossary.json"
const LINK_PREFIX := "glo:"
## Couleur des termes (l'accent de l'interface, un peu adouci) : très peu de couleur, comme ES2.
const LINK_COLOR := "#86dbe6"
const LOCKED_NAME := "???"

static var _loaded := false
## Termes et fiches : {id: {id, name, forms, family, summary, chapters, strict?, qualifier?, see?, cat?, locked?}}.
static var terms: Dictionary = {}
## Ordre alphabétique des termes du glossaire (sans les fiches de catalogue).
static var order: Array[String] = []
static var families: Array = []
static var _re: RegEx
## Forme en minuscules -> {id, strict}.
static var _forms: Dictionary = {}
## Interrupteur des Options : les infobulles colorent-elles les termes ? (prop. 16)
static var links_enabled := true
## Dit si une fiche verrouillée est connue du joueur (posé par CodexProgress) : func(id) -> bool.
static var unlock_check: Callable = Callable()


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	terms.clear()
	order.clear()
	_forms.clear()
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_warning("Glossaire introuvable : %s" % PATH)
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not d is Dictionary:
		push_warning("Glossaire illisible")
		return
	families = (d as Dictionary).get("families", [])
	for t: Dictionary in (d as Dictionary).get("terms", []):
		terms[String(t["id"])] = t
		order.append(String(t["id"]))
	for t: Dictionary in CodexCatalogs.linkables():
		if not terms.has(String(t["id"])):
			terms[String(t["id"])] = t
	_build_regex()


## Recharge (tests, ou après une modification du fichier).
static func reload_data() -> void:
	_loaded = false
	ensure_loaded()


static func _build_regex() -> void:
	var all: Array[String] = []
	for id: String in terms:
		var t: Dictionary = terms[id]
		var fs: Array = t.get("forms", [])
		if fs.is_empty():
			fs = [t["name"]]
		for fm in fs:
			var low := String(fm).strip_edges().to_lower()
			if low.length() < 3 or _forms.has(low):
				continue
			_forms[low] = {"id": id, "strict": bool(t.get("strict", false))}
			all.append(low)
	# Les formes les plus longues d'abord : « Grand chantier commun » avant « Grand chantier ».
	all.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length() if a.length() != b.length() else a < b)
	var parts := PackedStringArray()
	for s in all:
		parts.append(_escape(s))
	_re = RegEx.new()
	if parts.is_empty():
		return
	var err := _re.compile("(*UCP)(?i)(?<![\\w-])(" + "|".join(parts) + ")(?:s|x)?(?![\\w-])")
	if err != OK:
		push_warning("Glossaire : expression des termes invalide")
		_re = null


static func _escape(s: String) -> String:
	var out := ""
	for c in s:
		out += ("\\" + c) if "\\^$.|?*+()[]{}".contains(c) else c
	return out


# --- Lecture ---------------------------------------------------------------------------------------

static func has(id: String) -> bool:
	ensure_loaded()
	return terms.has(id)


static func term(id: String) -> Dictionary:
	ensure_loaded()
	return terms.get(id, {})


static func is_locked(id: String) -> bool:
	var t := term(id)
	if not bool(t.get("locked", false)):
		return false
	return not (unlock_check.is_valid() and bool(unlock_check.call(id)))


## Nom affiché (avec sa précision : « Héritage (maison) »), ou ??? pour une fiche encore inconnue.
static func display_name(id: String) -> String:
	if is_locked(id):
		return LOCKED_NAME
	var t := term(id)
	var n := String(t.get("name", id))
	if t.has("qualifier") and not n.contains("("):
		n += " (%s)" % String(t["qualifier"])
	return n


static func family_label(fid: String) -> String:
	ensure_loaded()
	for f: Dictionary in families:
		if String(f["id"]) == fid:
			return String(f["label"])
	return fid


static func family_glyph(fid: String) -> String:
	ensure_loaded()
	for f: Dictionary in families:
		if String(f["id"]) == fid:
			return String(f.get("glyph", "chronicles"))
	return "chronicles"


## Le terme reconnu pour un mot exact du texte ("" s'il n'en est pas un).
static func id_for(word: String) -> String:
	ensure_loaded()
	var low := word.to_lower()
	if _forms.has(low):
		return String(_forms[low]["id"])
	for suffix in ["s", "x"]:
		if low.ends_with(suffix) and _forms.has(low.left(-1)):
			return String(_forms[low.left(-1)]["id"])
	return ""


## « Voir aussi » d'un terme : sa liste see, sinon les termes de son résumé puis ceux de son chapitre (4 au plus).
static func see_also(id: String, limit := 4) -> Array[String]:
	ensure_loaded()
	var t := term(id)
	var out: Array[String] = []
	for s in t.get("see", []):
		if terms.has(String(s)) and not out.has(String(s)):
			out.append(String(s))
	if out.size() < limit:
		for m in find_terms(String(t.get("summary", ""))):
			if m != id and not out.has(m) and not is_locked(m):
				out.append(m)
	if out.size() < limit and not (t.get("chapters", []) as Array).is_empty():
		var ch := String(t["chapters"][0])
		for oid in order:
			if out.size() >= limit * 2:
				break
			if oid != id and not out.has(oid) and (terms[oid].get("chapters", []) as Array).has(ch):
				out.append(oid)
	return out.slice(0, limit)


## Identifiants des termes présents dans un texte brut, dans l'ordre d'apparition, sans doublon.
static func find_terms(text: String) -> Array[String]:
	ensure_loaded()
	var out: Array[String] = []
	if _re == null:
		return out
	for m in _re.search_all(text):
		var id := _accept(m)
		if id != "" and not out.has(id):
			out.append(id)
	return out


static func _accept(m: RegExMatch) -> String:
	var form := m.get_string(1)
	var info: Variant = _forms.get(form.to_lower())
	if info == null:
		return ""
	if bool(info["strict"]):
		var first := form.substr(0, 1)
		if first != first.to_upper() or first == first.to_lower():
			return ""
	return String(info["id"])


# --- Liens -----------------------------------------------------------------------------------------

## Fait des termes d'un texte BBCode des liens, à leur première apparition (seen garde les termes
## déjà liés, d'un appel à l'autre ; exclude = le terme qu'on est en train d'expliquer).
## Rien n'est touché à l'intérieur d'une balise ni d'un lien [url] existant.
static func link(text: String, seen: Dictionary = {}, exclude := "") -> String:
	ensure_loaded()
	if not links_enabled or _re == null or text == "":
		return text
	var out := ""
	var i := 0
	var in_url := 0
	var n := text.length()
	while i < n:
		var open := text.find("[", i)
		var chunk_end := n if open < 0 else open
		if chunk_end > i:
			var chunk := text.substr(i, chunk_end - i)
			out += chunk if in_url > 0 else _link_chunk(chunk, seen, exclude)
		if open < 0:
			break
		var close := text.find("]", open)
		if close < 0:
			out += text.substr(open)
			break
		var tag := text.substr(open, close - open + 1)
		if tag.begins_with("[url"):
			in_url += 1
			if tag.begins_with("[url=" + LINK_PREFIX):
				seen[tag.substr(5 + LINK_PREFIX.length(), tag.length() - 6 - LINK_PREFIX.length())] = true
		elif tag == "[/url]":
			in_url = maxi(0, in_url - 1)
		out += tag
		i = close + 1
	return out


static func _link_chunk(chunk: String, seen: Dictionary, exclude: String) -> String:
	var out := ""
	var pos := 0
	for m in _re.search_all(chunk):
		var id := _accept(m)
		if id == "" or id == exclude or seen.has(id) or is_locked(id):
			continue
		seen[id] = true
		out += chunk.substr(pos, m.get_start() - pos)
		out += "[url=%s%s][color=%s]%s[/color][/url]" % [LINK_PREFIX, id, LINK_COLOR, m.get_string()]
		pos = m.get_end()
	return out + chunk.substr(pos)


## Le terme visé par un lien (meta d'un RichTextLabel), "" si ce n'est pas un lien de glossaire.
static func meta_id(meta: Variant) -> String:
	var s := str(meta)
	return s.substr(LINK_PREFIX.length()) if s.begins_with(LINK_PREFIX) else ""


## Échappe un texte brut pour l'afficher tel quel en BBCode.
static func escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]")


## Contenu de l'infobulle d'un terme (prop. 14) : nom, famille, résumé (ses termes liés), voir aussi, aide.
static func tip_text(id: String) -> String:
	var t := term(id)
	if t.is_empty():
		return ""
	if is_locked(id):
		return "[b]%s[/b]\n[color=#9aa3ad]Pas encore rencontré : l'article se remplira quand vous le croiserez.[/color]" % LOCKED_NAME
	var seen := {id: true}
	var s := "[b]%s[/b]   [color=#7f8a96][font_size=12]%s[/font_size][/color]\n" % [display_name(id).to_upper(), family_label(String(t.get("family", "meca"))).to_upper()]
	var summ := String(t.get("summary", ""))
	var senses := summ.split(" ; et ")
	if senses.size() > 1:
		# Deux sens (prop. 4) : chacun sur sa ligne.
		var lines := PackedStringArray()
		for k in senses.size():
			lines.append("%d. %s" % [k + 1, link(escape_bbcode(senses[k].strip_edges()), seen, id)])
		s += "\n".join(lines)
	else:
		s += link(escape_bbcode(summ), seen, id)
	var also := see_also(id, 3)
	if not also.is_empty():
		var names := PackedStringArray()
		for a in also:
			if seen.has(a):
				continue
			seen[a] = true
			names.append("[url=%s%s][color=%s]%s[/color][/url]" % [LINK_PREFIX, a, LINK_COLOR, display_name(a)])
		if not names.is_empty():
			s += "\n[color=#7f8a96]Voir aussi :[/color] " + ", ".join(names)
	s += "\n[color=#6b7580][font_size=12]Clic droit ou F1 : ouvrir le Codex[/font_size][/color]"
	return s
