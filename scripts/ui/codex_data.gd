class_name CodexData
extends RefCounted
## Contenu du Codex de l'Archonte (glossaire en jeu, lot 2) : le manuel découpé en articles
## (data/codex_manual.json, écrit par docs/manuel/build.py --codex), les termes du glossaire,
## les fiches des catalogues et les fragments de lore. Identifiants d'articles :
##   <terme>            un terme du glossaire (data/glossary.json)
##   cat:<cat>:<clé>    une fiche de catalogue (CodexCatalogs)
##   man:<section>      une section du manuel (« 15z-ecologie#les-paliers », ou « 15z-ecologie » pour l'ouverture)
##   frag:<id>          un fragment de lore (Chroniques)
## Recherche plein texte (prop. 28) : sans accents, sans majuscules, pluriels en s/x ramenés au singulier.

const PATH := "res://data/codex_manual.json"
## Chapitres rangés dans Univers et dans Bestiaire et secrets (les autres sont des Mécanismes).
const UNIVERSE_CHAPTERS := ["00-prelude", "17-peuples", "18-creer-peuple"]
const BESTIARY_CHAPTERS := ["19-faune", "20-zone-scellee", "15a-crises"]

static var _loaded := false
static var chapters: Array = []
static var fragments: Array = []
static var edition := ""
static var _sections: Dictionary = {}
static var _section_chapter: Dictionary = {}
static var _chapter_by_file: Dictionary = {}
static var _fragment_by_id: Dictionary = {}
static var _norm_cache: Dictionary = {}


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	Glossary.ensure_loaded()
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_warning("Codex : %s introuvable (docs/manuel/build.py --codex)" % PATH)
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not d is Dictionary:
		return
	edition = String(d.get("edition", ""))
	chapters = d.get("chapters", [])
	fragments = d.get("fragments", [])
	for c: Dictionary in chapters:
		_chapter_by_file[String(c["file"])] = c
		for s: Dictionary in c.get("sections", []):
			_sections[String(s["id"])] = s
			_section_chapter[String(s["id"])] = c
	for fr: Dictionary in fragments:
		_fragment_by_id[String(fr["id"])] = fr


static func chapter(file: String) -> Dictionary:
	ensure_loaded()
	return _chapter_by_file.get(file, {})


static func section(sid: String) -> Dictionary:
	ensure_loaded()
	return _sections.get(sid, {})


static func section_chapter(sid: String) -> Dictionary:
	ensure_loaded()
	return _section_chapter.get(sid, {})


static func fragment(fid: String) -> Dictionary:
	ensure_loaded()
	return _fragment_by_id.get(fid, {})


## « Chapitre 44 · Le souffle des mondes ».
static func chapter_label(c: Dictionary) -> String:
	if c.is_empty():
		return ""
	var n := String(c.get("num", ""))
	return ("%s %s · %s" % [String(c.get("label", "Chapitre")), n, String(c["title"])]) if n != "" else String(c["title"])


static func chapter_family(file: String) -> String:
	if UNIVERSE_CHAPTERS.has(file):
		return "univers"
	if BESTIARY_CHAPTERS.has(file):
		return "bestiaire"
	return "meca"


## Famille d'un article.
static func family_of(aid: String) -> String:
	if aid.begins_with("man:"):
		return chapter_family(aid.substr(4).split("#")[0])
	if aid.begins_with("frag:"):
		return "chroniques"
	return String(Glossary.term(aid).get("family", "meca"))


## La section du manuel qui explique un terme : la première de ses chapitres où il est en gras.
static func section_for_term(tid: String) -> String:
	ensure_loaded()
	var t := Glossary.term(tid)
	var forms: Array = t.get("forms", [])
	if forms.is_empty():
		forms = [t.get("name", tid)]
	for file in t.get("chapters", []):
		var c := chapter(String(file))
		for s: Dictionary in c.get("sections", []):
			var low := String(s["text"]).to_lower()
			for fm in forms:
				if low.contains("[b]" + String(fm).to_lower()):
					return String(s["id"])
		if not c.is_empty() and not (c["sections"] as Array).is_empty():
			return String(c["sections"][0]["id"])
	return ""


# --- Recherche ---------------------------------------------------------------------------------

static func normalize(s: String) -> String:
	if _norm_cache.has(s):
		return _norm_cache[s]
	var low := s.to_lower()
	var out := ""
	const FROM := "àâäáãéèêëíìîïóòôöõúùûüçñœæÿ"
	const TO := ["a", "a", "a", "a", "a", "e", "e", "e", "e", "i", "i", "i", "i", "o", "o", "o", "o", "o", "u", "u", "u", "u", "c", "n", "oe", "ae", "y"]
	for ch in low:
		var k := FROM.find(ch)
		out += TO[k] if k >= 0 else ch
	var words := PackedStringArray()
	for w in out.split(" ", false):
		if w.length() > 3 and (w.ends_with("s") or w.ends_with("x")):
			w = w.left(-1)
		words.append(w)
	var r := " ".join(words)
	if _norm_cache.size() < 4000:
		_norm_cache[s] = r
	return r


## Résultats d'une recherche : [{id, title, family, score}], les noms d'abord, puis les textes.
static func search(query: String, unlocked: Callable, limit := 60) -> Array:
	ensure_loaded()
	var q := normalize(query.strip_edges())
	if q.length() < 2:
		return []
	var out: Array = []
	var add := func(aid: String, title: String, text: String) -> void:
		if not unlocked.call(aid):
			return
		var nt := normalize(title)
		var score := 0
		if nt == q:
			score = 100
		elif nt.begins_with(q):
			score = 60
		elif nt.contains(q):
			score = 40
		elif normalize(text).contains(q):
			score = 10
		if score > 0:
			out.append({"id": aid, "title": title, "family": family_of(aid), "score": score})
	for tid in Glossary.order:
		add.call(tid, Glossary.display_name(tid), String(Glossary.term(tid).get("summary", "")))
	for e: Dictionary in CodexCatalogs.all_entries():
		add.call(String(e["id"]), String(e["name"]), String(e.get("summary", "")))
	for c: Dictionary in chapters:
		for s: Dictionary in c.get("sections", []):
			var title := String(c["title"]) if String(s["title"]) == "Présentation" else String(s["title"])
			add.call("man:" + String(s["id"]), title, String(s["text"]))
	for fr: Dictionary in fragments:
		add.call("frag:" + String(fr["id"]), String(fr.get("source", "Fragment")), String(fr["text"]))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["score"]) > int(b["score"]) if int(a["score"]) != int(b["score"]) else String(a["title"]) < String(b["title"]))
	return out.slice(0, limit)


## Titre court d'un article.
static func title_of(aid: String) -> String:
	ensure_loaded()
	if aid.begins_with("man:"):
		var s := section(aid.substr(4))
		var c := section_chapter(aid.substr(4))
		if s.is_empty():
			return aid
		return String(c["title"]) if String(s["title"]) == "Présentation" else String(s["title"])
	if aid.begins_with("frag:"):
		var fr := fragment(aid.substr(5))
		return String(fr.get("source", "Fragment")) if not fr.is_empty() else aid
	return Glossary.display_name(aid)


static func exists(aid: String) -> bool:
	ensure_loaded()
	if aid.begins_with("man:"):
		return _sections.has(aid.substr(4))
	if aid.begins_with("frag:"):
		return _fragment_by_id.has(aid.substr(5))
	return Glossary.has(aid)
