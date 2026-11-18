class_name GlossaryTests
extends RefCounted
## Tests du glossaire en jeu (étude du 2026-11-18, 40 propositions) : cohérence du dictionnaire
## (prop. 7), liens dans les textes, infobulle d'un terme, Codex (contenu, recherche, verrous,
## Chroniques) et mémoire du Codex dans la sauvegarde 96.
##   TESTS=glossary_tests godot --headless --path . -s res://tests/_only.gd

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	CodexPrefs.persist = false
	print("Glossaire en jeu…")
	print("  - dictionnaire")
	_test_data()
	print("  - liens")
	_test_links()
	print("  - infobulle")
	_test_tip()
	print("  - codex")
	_test_codex()
	print("  - catalogues")
	_test_catalogs()
	print("  - recherche")
	_test_search()
	print("  - progression")
	_test_progress()
	print("  - chroniques")
	_test_chronicles()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _test_data() -> void:
	Glossary.reload_data()
	_ok(Glossary.order.size() >= 250, "au moins 250 termes (%d)" % Glossary.order.size())
	var forms_seen := {}
	var dup := []
	var bad := []
	for tid in Glossary.order:
		var t := Glossary.term(tid)
		if String(t.get("summary", "")).strip_edges() == "" or String(t.get("name", "")) == "":
			bad.append(tid)
		if not ["meca", "univers", "bestiaire", "chroniques"].has(String(t.get("family", ""))):
			bad.append(tid + " (famille)")
		for ch in t.get("chapters", []):
			if not FileAccess.file_exists("res://docs/manuel/chapitres/%s.md" % ch):
				bad.append("%s → %s" % [tid, ch])
		for fm in t.get("forms", []):
			var k := String(fm).to_lower()
			if forms_seen.has(k) and forms_seen[k] != tid:
				dup.append("%s (%s / %s)" % [k, forms_seen[k], tid])
			forms_seen[k] = tid
		for see in Glossary.see_also(tid):
			if not Glossary.has(see):
				bad.append("%s voir %s" % [tid, see])
	_ok(bad.is_empty(), "chaque terme a un nom, un résumé, une famille et des renvois valides %s" % [bad.slice(0, 5)])
	_ok(dup.is_empty(), "aucune forme n'appartient à deux termes %s" % [dup.slice(0, 5)])


func _test_links() -> void:
	Glossary.links_enabled = true
	var any := Glossary.order[0]
	var name := Glossary.display_name(any)
	var linked := Glossary.link("Ceci parle de %s, puis encore de %s." % [name, name])
	_ok(linked.count("[url=glo:") == 1, "un terme n'est relié qu'à sa première occurrence")
	_ok(Glossary.link("[b]%s[/b]" % name).contains("[url="), "les balises n'empêchent pas le lien")
	var once := Glossary.link(linked)
	_ok(once.count("[url=") == 1, "un texte déjà relié ne l'est pas deux fois")
	Glossary.links_enabled = false
	_ok(Glossary.link(name) == name, "liens désactivés : texte inchangé")
	Glossary.links_enabled = true
	_ok(Glossary.escape_bbcode("[x]") == "[lb]x]", "les crochets du texte brut sont neutralisés")
	var found := Glossary.find_terms("La %s et rien d'autre." % name)
	_ok(found.has(any), "find_terms repère le terme")


func _test_tip() -> void:
	var tid := Glossary.order[0]
	var tip := Glossary.tip_text(tid)
	_ok(tip.contains(Glossary.display_name(tid).to_upper()) and tip.contains("Codex"), "l'infobulle d'un terme : nom et renvoi au Codex")
	_ok(Glossary.meta_id("glo:" + tid) == tid, "identifiant de lien glo:")


func _test_codex() -> void:
	CodexData.ensure_loaded()
	_ok(CodexData.chapters.size() >= 40, "le manuel découpé est chargé (%d chapitres)" % CodexData.chapters.size())
	_ok(CodexData.fragments.size() >= 30, "des fragments de lore (%d)" % CodexData.fragments.size())
	_ok(CodexData.exists(CodexScreen.HOME), "l'article d'accueil existe")
	var missing := []
	for tid in Glossary.order:
		if not (Glossary.term(tid).get("chapters", []) as Array).is_empty() and CodexData.section_for_term(tid) == "":
			missing.append(tid)
	_ok(missing.is_empty(), "chaque terme rattaché trouve sa section du manuel %s" % [missing.slice(0, 5)])
	_ok(CodexData.normalize("Écologies") == "ecologie", "recherche : accents et pluriels")
	_ok(CodexData.chapter_family("17-peuples") == "univers" and CodexData.chapter_family("20-zone-scellee") == "bestiaire", "familles des chapitres")


func _test_catalogs() -> void:
	var total := CodexCatalogs.all_entries().size()
	_ok(total > 100, "les catalogues ont des fiches (%d)" % total)
	_ok(not CodexCatalogs.entries("peuples").is_empty(), "catalogue des peuples")
	_ok(not CodexCatalogs.entries("technologies").is_empty(), "catalogue des technologies")
	var e: Dictionary = CodexCatalogs.entries("peuples")[0]
	_ok(CodexCatalogs.entry(String(e["id"])).get("name", "") == e["name"], "une fiche se retrouve par son identifiant")


func _test_search() -> void:
	var all := func(_id: String) -> bool: return true
	var tid := Glossary.order[0]
	var res := CodexData.search(Glossary.display_name(tid), all)
	_ok(not res.is_empty() and String(res[0]["id"]) == tid, "le nom exact vient en tête")
	_ok(CodexData.search("a", all).is_empty(), "une lettre ne suffit pas")
	var none := func(_id: String) -> bool: return false
	_ok(CodexData.search(Glossary.display_name(tid), none).is_empty(), "les articles scellés sont exclus")


func _test_progress() -> void:
	var st := GameState.create(4343, 150, 1800.0, "ossarane", {"ai_level": ""})
	var me := st.empires[0].id
	var own := "cat:peuples:" + st.empires[0].faction_id
	_ok(CodexProgress.known_now(st, me).has(own), "son propre peuple est connu")
	CodexProgress.monthly(st)
	_ok(CodexProgress.unlocked(st, me, own), "mémorisé chaque mois")
	_ok(not CodexProgress.unlocked(st, me, "cat:gardiens:inexistant"), "un gardien non croisé reste scellé")
	var back := GameState.from_dict(st.to_dict())
	_ok(back.codex == st.codex and not back.codex.is_empty(), "sauvegarde 96 : mémoire du Codex rechargée")
	_ok(GameState.FORMAT_VERSION >= 96 and GameState.READABLE_VERSIONS.has(95), "format 96 ou plus, 95 lisible")
	var old := st.to_dict()
	old.erase("codex")
	old["version"] = 95
	var ob := GameState.from_dict(old)
	_ok(ob != null and ob.codex.is_empty(), "sauvegarde 95 : Codex vide")
	# Le Codex suit la partie : le peuple du joueur est ouvert, un gardien non.
	CodexPrefs.reset()
	CodexPrefs.set_game(st, me)
	_ok(CodexPrefs.unlocked(own), "Codex : fiche de son peuple ouverte")
	var secret := ""
	for e: Dictionary in CodexCatalogs.entries("gardiens"):
		secret = String(e["id"])
		break
	if secret != "":
		_ok(not CodexPrefs.unlocked(secret), "Codex : gardien scellé tant qu'il n'est pas croisé")
		CodexPrefs.set_game(null, -1)
		_ok(not CodexPrefs.unlocked(secret), "hors partie : les fiches secrètes restent scellées")
	CodexPrefs.set_game(null, -1)


func _test_chronicles() -> void:
	CodexPrefs.reset()
	var free := 0
	for fr: Dictionary in CodexData.fragments:
		if CodexPrefs.chronicle_unlocked(String(fr["id"])):
			free += 1
	_ok(free > 0 and free < CodexData.fragments.size(), "les fragments de l'ouverture sont acquis d'emblée, pas les autres")
	var st := GameState.create(4343, 150, 1800.0, "ossarane", {"ai_level": ""})
	var me := st.empires[0].id
	CodexPrefs.set_game(st, me)
	CodexPrefs.scan()
	# Un terme d'un chapitre encore scellé, nommé dans la chronique publique.
	var target := ""
	var term := ""
	for fr: Dictionary in CodexData.fragments:
		if CodexPrefs.chronicle_unlocked(String(fr["id"])):
			continue
		for tid in Glossary.order:
			if (Glossary.term(tid).get("chapters", []) as Array).has(fr["chapter"]) and not Glossary.is_locked(tid):
				target = String(fr["id"])
				term = tid
				break
		if target != "":
			break
	_ok(target != "", "un fragment scellé à débloquer")
	if target == "":
		return
	st.chronicle.append({"day": 1, "text": "On parle de %s." % Glossary.display_name(term)})
	var got := CodexPrefs.scan()
	_ok(got.size() == 1, "un terme nommé débloque un fragment de son chapitre")
	_ok(CodexPrefs.is_new("frag:" + got[0]) and CodexPrefs.has_new(), "le fragment est signalé « nouveau »")
	CodexPrefs.read["frag:" + got[0]] = true
	CodexPrefs.fresh.erase(got[0])
	_ok(not CodexPrefs.is_new("frag:" + got[0]), "lu : plus « nouveau »")
	_ok(CodexPrefs.scan().is_empty(), "une entrée ne se lit qu'une fois")
	CodexPrefs.reset()
	CodexPrefs.set_game(null, -1)
