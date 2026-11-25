extends RefCounted
## Pictogrammes (GameIcon) : chaque technologie, bâtiment, haut fait, relique, précepte, nature de foi,
## type de fouille et ressource a sa case sur la planche, et la planche couvre bien ces cases.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Pictogrammes…")
	_test_every_entry_has_icon()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _test_every_entry_has_icon() -> void:
	var want: Array[String] = []
	for tid in Research.data()["technologies"]:
		want.append("tech/%s" % tid)
	for bid in GameData.buildings():
		want.append("batiment/%s" % bid)
	for id in Deeds.data()["deeds"]:
		want.append("haut_fait/%s" % id)
	for r: Dictionary in Relics.data()["relics"]:
		want.append("relique/%s" % String(r["id"]))
	for pid in Faiths.precept_ids():
		want.append("precepte/%s" % pid)
	for nid in FaithWars.data()["natures"]["list"]:
		want.append("nature/%s" % nid)
	var arch: Dictionary = Archaeology.data()
	for part in ["site_types", "disparus", "natures", "methods"]:
		for k in arch[part]:
			if arch[part][k] is Dictionary:
				want.append("fouille/%s" % k)
	for g in Goods.luxury_ids():
		want.append("ressource/%s" % g)
	for s in GameData.strategic_ids():
		want.append("ressource/%s" % s)
	_ok(want.size() > 700, "le jeu compte plus de 700 entrées à icône (%d)" % want.size())
	var missing: Array[String] = []
	for key in want:
		var parts := key.split("/")
		if not GameIcon.has(parts[0], parts[1]):
			missing.append(key)
	_ok(missing.is_empty(), "chaque entrée a son pictogramme (manquent : %s)" % ", ".join(missing.slice(0, 12)))
	# Aucune case orpheline : une entrée retirée des données doit quitter tools/icons/table.py.
	var extra: Array[String] = []
	for key in GameIcon.keys():
		if not want.has(String(key)):
			extra.append(String(key))
	_ok(extra.is_empty(), "aucun pictogramme sans entrée (en trop : %s)" % ", ".join(extra.slice(0, 12)))
	# La planche contient bien chaque case, et aucune case n'est vide.
	var tex := load(GameIcon.ATLAS) as Texture2D
	_ok(tex != null, "la planche des pictogrammes se charge")
	if tex != null and not want.is_empty():
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		var empty: Array[String] = []
		for key in want:
			var parts := key.split("/")
			var r := GameIcon.region(parts[0], parts[1])
			if r.end.x > img.get_width() or r.end.y > img.get_height():
				empty.append(key + " (hors planche)")
				continue
			var seen := false
			for y in range(int(r.position.y) + 8, int(r.end.y) - 8, 6):
				for x in range(int(r.position.x) + 8, int(r.end.x) - 8, 6):
					if img.get_pixel(x, y).a > 0.5:
						seen = true
						break
				if seen:
					break
			if not seen:
				empty.append(key)
		_ok(empty.is_empty(), "aucune case vide sur la planche (%s)" % ", ".join(empty.slice(0, 12)))
	# Texture d'une entrée, et rien pour une entrée inconnue.
	_ok(GameIcon.texture("batiment", "temple") is AtlasTexture, "un bâtiment donne une texture pour un bouton")
	_ok(GameIcon.texture("batiment", "n_existe_pas") == null, "une entrée inconnue ne donne pas de texture")
	for fam in GameIcon.FRAMES:
		_ok(GameIcon.frame_points(fam, Vector2(50, 50), 40.0).size() >= 4, "le cadre de la famille %s a un contour" % fam)
