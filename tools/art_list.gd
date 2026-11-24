extends SceneTree
## Écrit assets/art/EMPLACEMENTS.md (tous les emplacements d'illustration, lus par ArtCatalog) et
## assets/art/CONSIGNES.md (une consigne de génération par emplacement, tirée des textes du jeu).
##   godot --headless --path . -s res://tools/art_list.gd

const FRAMING := {"16:9": "plan large, horizon bas, sujet au tiers droit", "3:4": "buste de trois quarts, regard vers le spectateur, fond sobre",
		"2:1": "bandeau panoramique, sujet décentré à droite, gauche dégagée pour le titre", "4:3": "sujet centré, vu de l'espace ou à hauteur d'homme",
		"3:1": "bandeau très large, sujet à droite, gauche sombre pour le texte", "4:1": "bandeau très large, galaxie vue par la tranche"}
const PALETTE := {"accueil": "bleu nuit et cyan, une lueur chaude", "peuples": "couleur du peuple en dominante, fond sombre", "scenes": "couleur du peuple en dominante, ciel profond",
		"ecrans": "bleu nuit, accents cyan, peu de couleurs", "mondes": "teintes naturelles du monde sur fond d'espace noir", "annonces": "sombre, une seule couleur vive selon la famille de l'annonce",
		"evenements": "ambre et brun sur fond sombre, lumière de fin de jour", "merveilles": "or pâle et bleu nuit", "megastructures": "acier froid, lueur de l'étoile voisine",
		"forge": "orange de fonderie sur noir", "quetes": "or et cyan, lumière rasante", "faune": "vert d'eau et noir, bioluminescence", "portraits": "teinte unie sombre, liseré clair"}


func _json(file: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % file))


func _first(s: String, n := 2) -> String:
	var parts := s.replace("\n", " ").split(". ")
	var out := ". ".join(parts.slice(0, n)).strip_edges()
	return out if out.ends_with(".") or out == "" else out + "."


## Ce que le jeu dit déjà de la chose, pour guider l'image.
func _subject(s: Dictionary) -> String:
	var id := String(s["id"])
	match String(s["family"]):
		"mondes":
			return String((_json("planet_types")[id.trim_prefix("planet_")] as Dictionary).get("lore", ""))
		"merveilles":
			return _first(String((_json("wonders")["wonders"][id.trim_prefix("wonder_")] as Dictionary).get("lore", (_json("wonders")["wonders"][id.trim_prefix("wonder_")] as Dictionary).get("text", ""))), 1)
		"evenements":
			for file: String in ["events", "ancients", "minors"]:
				for c: Dictionary in (_json(file) as Dictionary).get("cards", []):
					if "event_" + String(c["id"]) == id and not String(c.get("text", "")).contains("{"):
						return _first(String(c["text"]))
					elif "event_" + String(c["id"]) == id:
						return _first(String(c["text"]).replace("{system}", "la colonie").replace("{rival}", "l'autre empire").replace("{hero}", "le héros"), 2)
		"annonces":
			return String((_json("announcements")["kinds"][id.trim_prefix("annonces/")] as Dictionary).get("lead", ""))
		"faune":
			return _first(String((_json("creatures")["species"][id.trim_prefix("fauna_")] as Dictionary).get("text", "")))
		"megastructures":
			return _first(String((_json("megastructures")["kinds"][id.trim_prefix("mega_")] as Dictionary).get("text", "")), 1)
		"peuples", "scenes":
			for f: Dictionary in _json("factions"):
				if GameData.portrait_art(String(f["id"])) == id or "faction_%s_scene" % String(f["id"]) == id:
					return "Registre : %s. %s" % [String(f.get("registre", "")), _first(String(f.get("text", f.get("blurb", ""))), 1)]
	return ""


func _initialize() -> void:
	var list := "# Emplacements d'illustration\n\nListe tirée des données du jeu par `tools/art_list.gd`. Déposez l'image sous le nom indiqué, en PNG, JPG ou WebP, dans `assets/art/` : elle remplace le tableau provisoire. La même liste se lit dans le Codex, à « Galerie des illustrations ».\n"
	var brief := "# Consignes de génération\n\nUne consigne par emplacement : le sujet tel que le jeu le décrit, le cadrage et la palette. Fichier écrit par `tools/art_list.gd`.\n"
	var total := 0
	for fam: Dictionary in ArtCatalog.FAMILIES:
		var rows := ""
		var n := 0
		brief += "\n## %s\n" % String(fam["label"])
		for s: Dictionary in ArtCatalog.slots():
			if String(s["family"]) != String(fam["id"]):
				continue
			n += 1
			rows += "| `%s` | %s | %s |\n" % [String(s["id"]), String(s["label"]), String(s["format"])]
			var subj := _subject(s)
			brief += "\n**%s** (`%s`, %s)\n\n- Sujet : %s%s\n- Cadrage : %s.\n- Palette : %s.\n" % [String(s["label"]), String(s["id"]), String(s["format"]), String(s["label"]),
					(". " + subj) if subj != "" else ".", String(FRAMING.get(String(s["format"]), "sujet centré")), String(PALETTE.get(String(fam["id"]), "sombre, accents cyan"))]
		total += n
		list += "\n## %s (%d, rang %d)\n\n| Fichier | Sujet | Format |\n| --- | --- | --- |\n%s" % [String(fam["label"]), n, int(fam["rank"]), rows]
	list = list.replace("Liste tirée", "%d emplacements. Liste tirée" % total)
	FileAccess.open("res://assets/art/EMPLACEMENTS.md", FileAccess.WRITE).store_string(list)
	FileAccess.open("res://assets/art/CONSIGNES.md", FileAccess.WRITE).store_string(brief)
	print("%d emplacements" % total)
	quit()
