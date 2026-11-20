class_name GameData
extends RefCounted
## Données de jeu (factions, types de planètes, bâtiments, règles), lues dans res://data/*.json.
## Tout l'équilibrage vit dans ces fichiers : on ajuste les chiffres sans toucher au code,
## et le futur éditeur d'espèces écrira dans le même format.
##
## Les nombres entiers du JSON sont convertis en int : la simulation ne calcule qu'en entiers,
## pour rester identique à l'octet près sur toutes les machines (multijoueur).

const DATA_DIR := "res://data"

static var _cache := {}


## « de » + un nom, à la française : « de le Trône » -> « du Trône », « de les » -> « des »,
## « de Éclat » -> « d'Éclat ». Pour les textes de la chronique qui collent « de %s ».
static func de(name: String) -> String:
	for pair in [["le ", "du "], ["Le ", "du "], ["les ", "des "], ["Les ", "des "]]:
		if name.begins_with(pair[0]):
			return pair[1] + name.substr(pair[0].length())
	if name.begins_with("La ") or name.begins_with("L'"):
		return "de " + name[0].to_lower() + name.substr(1)
	if name != "" and "aeiouyhAEIOUYHÉÈÊÀÂÎÔÛéèêàâîôûœŒ".contains(name[0]) and not name.begins_with("la ") and not name.begins_with("l'"):
		return "d'" + name
	return "de " + name


static func rules() -> Dictionary:
	return _load("rules")


## Peuples officiels (data/factions.json), dans l'ordre des données.
static func factions() -> Array:
	return _load("factions")


## Peuples créés dans l'éditeur d'espèces (voir Species, SpeciesLibrary), au format de factions.json :
## - ceux de la bibliothèque du joueur (user://species/), chargés au démarrage ;
## - ceux de la partie en cours, recopiés dans la sauvegarde : ils passent avant la bibliothèque, pour
##   qu'une partie garde son peuple tel qu'il était au lancement même si le fichier a changé depuis.
static var _library_factions := {}
static var _game_factions := {}
## Augmente à chaque changement des peuples créés (bibliothèque ou partie) : Empire.faction() garde sa
## fiche tant qu'il ne bouge pas.
static var factions_gen := 0


## Fiche d'un peuple par identifiant : partie en cours, puis bibliothèque, puis officiels. {} si inconnu.
static func faction(id: String) -> Dictionary:
	if _game_factions.has(id):
		return _game_factions[id]
	if _library_factions.has(id):
		return _library_factions[id]
	# Fiches légères des peuples mineurs et des pré-conscients (voir Minors.species_fiche).
	if id.begins_with("mineur_") or id.begins_with("pres_"):
		if not _cache.has("minor_fiches"):
			_cache["minor_fiches"] = {}
		if not _cache["minor_fiches"].has(id):
			_cache["minor_fiches"][id] = Minors.species_fiche(id)
		return _cache["minor_fiches"][id]
	# Index des peuples officiels (appelé à chaque instant par la simulation : pas de parcours de liste).
	if not _cache.has("factions_by_id"):
		var idx := {}
		for f: Dictionary in factions():
			idx[f["id"]] = f
		_cache["factions_by_id"] = idx
	return _cache["factions_by_id"].get(id, {})


## Identifiants des peuples officiels seulement.
static func faction_ids() -> Array[String]:
	var ids: Array[String] = []
	for f: Dictionary in factions():
		ids.append(String(f["id"]))
	return ids


## Les huit peuples classiques : les officiels sans les peuples insolites (rivaux par défaut des tests,
## des bancs d'essai et des parties créées sans liste de rivaux).
static func classic_faction_ids() -> Array[String]:
	var ids: Array[String] = []
	for f: Dictionary in factions():
		if not bool(f.get("insolite", false)):
			ids.append(String(f["id"]))
	return ids


## Peuples insolites officiels (voir Insolites).
static func insolite_faction_ids() -> Array[String]:
	var ids: Array[String] = []
	for f: Dictionary in factions():
		if bool(f.get("insolite", false)):
			ids.append(String(f["id"]))
	return ids


## Peuples officiels puis peuples de la bibliothèque (triés), pour les listes de choix.
static func all_faction_ids() -> Array[String]:
	var ids := faction_ids()
	ids.append_array(library_faction_ids())
	return ids


static func library_faction_ids() -> Array[String]:
	var ids: Array[String] = []
	for k in _library_factions:
		ids.append(String(k))
	ids.sort()
	return ids


static func is_official(id: String) -> bool:
	return faction_ids().has(id)


static func register_library_faction(f: Dictionary) -> void:
	_library_factions[String(f["id"])] = f
	factions_gen += 1


static func unregister_library_faction(id: String) -> void:
	_library_factions.erase(id)
	factions_gen += 1


static func clear_library_factions() -> void:
	_library_factions.clear()
	factions_gen += 1


## Peuples créés de la partie en cours (GameState.custom_factions).
static func set_game_factions(d: Dictionary) -> void:
	_game_factions = d
	factions_gen += 1


static func clear_game_factions() -> void:
	_game_factions = {}
	factions_gen += 1


## Style des vaisseaux d'un peuple (sprites et modèles 3D d'un peuple officiel) : son identifiant
## pour un officiel, celui choisi dans l'éditeur pour un peuple créé.
static func ship_style(faction_id: String) -> String:
	return String(faction(faction_id).get("ship_style", faction_id))


## Illustration du peuple (Widgets.ArtSlot) : "faction_<id>" pour un officiel, "portrait_<portrait>"
## pour un peuple créé (portrait choisi dans l'éditeur).
static func portrait_art(faction_id: String) -> String:
	var f := faction(faction_id)
	if f.has("portrait"):
		return "portrait_" + String(f["portrait"])
	return "faction_" + faction_id


## Briques de l'éditeur d'espèces (data/species_parts.json).
static func species_parts() -> Dictionary:
	return _load("species_parts")


static func planet_types() -> Dictionary:
	return _load("planet_types")


static func planet_type(id: String) -> Dictionary:
	return planet_types().get(id, {})


static func buildings() -> Dictionary:
	return _load("buildings")


## Lot 4 de l'arbre : un bâtiment de peuple (replaces_building) compte comme le bâtiment commun qu'il
## remplace (Tribune = Forum, Campement de clan = Dépôt de flotte…). Renvoie l'identifiant commun.
static func building_kind(id: String) -> String:
	var k: Variant = _kind_memo.get(id)
	if k == null:
		k = String(buildings().get(id, {}).get("replaces_building", id))
		_kind_memo[id] = k
	return k


## Mémos des lectures les plus fréquentes (grande passe d'optimisation) : les données du jeu ne
## changent pas en cours de partie.
static var _kind_memo := {}
static var _bld_memo := {}


## Bâtiments de peuple qui remplacent ce bâtiment commun.
static var _variants := {}
static func building_variants(id: String) -> Array[String]:
	if _variants.is_empty():
		for k in buildings():
			var base := String(buildings()[k].get("replaces_building", ""))
			if base != "":
				if not _variants.has(base):
					_variants[base] = [] as Array[String]
				(_variants[base] as Array[String]).append(String(k))
		_variants["_"] = [] as Array[String]
		for base in _variants:
			(_variants[base] as Array[String]).sort()
	var out: Array[String] = []
	out.assign(_variants.get(id, []))
	return out


static func building(id: String) -> Dictionary:
	var m: Variant = _bld_memo.get(id)
	if m != null:
		return m
	var b: Dictionary = buildings().get(id, {})
	if b.is_empty():
		b = wonders_list().get(id, {})  # merveilles et mégastructures (data/wonders.json)
	if b.is_empty():
		b = deeds().get("trophies", {}).get(id, {})  # Trophées des hauts faits (data/deeds.json)
		if not b.is_empty() and not b.has("buildable"):
			b["buildable"] = false
	if not b.is_empty():
		_bld_memo[id] = b
	return b


## Hauts faits galactiques (data/deeds.json) : réglages, familles, titres, récompenses, Trophées, catalogue.
static func deeds() -> Dictionary:
	return _load("deeds")


## Souverains et dynasties (data/rulers.json) : réglages, titres, archétypes, lois, surnoms, ambitions,
## héritages, funérailles, galerie de portraits, cartes.
static func rulers() -> Dictionary:
	return _load("rulers")


static func court() -> Dictionary:
	return _load("court")


static func administration() -> Dictionary:
	return _load("administration")


static func defenses() -> Dictionary:
	return _load("defenses")


static func stealth() -> Dictionary:
	return _load("stealth")


static func genetics() -> Dictionary:
	return _load("genetics")


static func psionics() -> Dictionary:
	return _load("psionics")


static func transcendence() -> Dictionary:
	return _load("transcendence")


static func contact() -> Dictionary:
	return _load("contact")


## Archéologie, les Strates (data/archaeology.json).
static func archaeology() -> Dictionary:
	return _load("archaeology")


## Annonces : familles, gravités, types (data/announcements.json, voir Announce).
static func announcements() -> Dictionary:
	return _load("announcements")


static func portals() -> Dictionary:
	return _load("portals")


static func private_eco() -> Dictionary:
	return _load("private")


static func ports() -> Dictionary:
	return _load("ports")


static func finance() -> Dictionary:
	return _load("finance")


## Mégastructures (data/megastructures.json) : réglages, règles, Kardashev, talents, catalogue.
static func megastructures() -> Dictionary:
	return _load("megastructures")


## La Forge des mondes (data/worldforge.json) : réglages, règles, mondes façonnés, chantiers, talents.
static func worldforge() -> Dictionary:
	return _load("worldforge")


## Échelle de Kardashev (data/kardashev.json).
static func kardashev() -> Dictionary:
	return _load("kardashev")


## Mondes vivants (data/livingworlds.json).
static func livingworlds() -> Dictionary:
	return _load("livingworlds")
## Écologie et climat des mondes (data/ecology.json).
static func ecology() -> Dictionary:
	return _load("ecology")


## Prises de guerre (voir Capture).
static func capture() -> Dictionary:
	return _load("capture")


## Peuples insolites (voir Insolites, data/insolites.json).
static func insolites() -> Dictionary:
	return _load("insolites")


## Merveilles galactiques (data/wonders.json) : réglages, modes, cartes, catalogue.
static func wonders() -> Dictionary:
	return _load("wonders")


## Catalogue des merveilles : identifiant -> fiche (lue aussi par GameData.building).
static func wonders_list() -> Dictionary:
	return wonders().get("wonders", {})


## Classes de vaisseaux (data/ships.json), par identifiant. Les classes de combat sont des modèles
## d'origine de l'éditeur (Designs) : leurs caractéristiques sont calculées une fois depuis leur coque
## et leurs modules (data/designs.json), puis gardées en cache avec le reste.
static func ships() -> Dictionary:
	if not _cache.has("ships_built"):
		var raw: Dictionary = _load("ships")
		for sid in raw:
			var o := Designs.origin(String(sid))
			if o.is_empty():
				continue
			var computed := Designs.compute(String(o["hull"]), o.get("modules", []))
			var sd: Dictionary = raw[sid]
			for k in computed:
				if not sd.has(k) or k in Designs.STATS or k in ["weapons", "cost", "days", "upkeep", "hull"] or k in Designs.FLAGS:
					sd[k] = computed[k]
			sd["modules"] = (o.get("modules", []) as Array).duplicate()
		_cache["ships_built"] = true
	return _load("ships")


## Coques, modules et modèles d'origine de l'éditeur de vaisseaux (data/designs.json).
static func designs_data() -> Dictionary:
	return _load("designs")


## Modèles conçus en partie (voir Designs.register_all) : identifiant -> caractéristiques.
## Ils se lisent comme des classes, partout où le jeu lit GameData.ship().
static var _custom := {}


static var _ids_cache: Array[String] = []
static var _class_ids_cache: Array[String] = []


static func register_custom_ship(id: String, stats: Dictionary) -> void:
	_custom[id] = stats
	_ids_cache = []


static func clear_custom_ships() -> void:
	_custom.clear()
	_ids_cache = []
	Capture.clear_cache()


static func ship(id: String) -> Dictionary:
	if _custom.has(id):
		return _custom[id]
	if id.contains("~"):
		return Capture.prize_stats(id) if not id.ends_with("~copie") else {}  # prises de guerre (voir Capture)
	# Créatures (data/creatures.json, « units ») : elles se lisent comme des classes au combat, sans
	# figurer parmi les classes que l'on construit.
	if id.begins_with("crise_"):
		return crises().get("units", {}).get(id, {})
	if id.begins_with("ancien_"):
		return ancients().get("units", {}).get(id, {})
	if id.begins_with("vivant_"):
		return livingworlds().get("units", {}).get(id, {})  # nef-graine des mondes vivants
	if id.begins_with("def_"):
		return Defenses.unit(id)  # défenses fixes (data/defenses.json)
	if id.begins_with("bete_"):
		var u: Dictionary = creatures().get("units", {}).get(id, {})
		return u if not u.is_empty() else guardians().get("units", {}).get(id, {})
	return ships().get(id, {})


## Identifiants des classes de vaisseaux, triés (ordre stable pour l'interface et la simulation),
## puis ceux des modèles conçus en partie, triés aussi.
## Liste gardée en cache (refaite quand un modèle est enregistré) : ne pas la modifier.
static func ship_ids() -> Array[String]:
	if _ids_cache.is_empty():
		var ids: Array[String] = class_ids().duplicate()
		var custom: Array[String] = []
		for k in _custom:
			custom.append(String(k))
		custom.sort()
		ids.append_array(custom)
		_ids_cache = ids
	return _ids_cache


## Identifiants des classes de data/ships.json seulement, triés (cache, ne pas modifier).
static func class_ids() -> Array[String]:
	if _class_ids_cache.is_empty():
		var ids: Array[String] = []
		for k in ships():
			ids.append(String(k))
		ids.sort()
		_class_ids_cache = ids
	return _class_ids_cache


static func ai() -> Dictionary:
	return _load("ai")


## Règles du combat (data/combat.json) : phases, armes, tactiques, siège.
static func combat() -> Dictionary:
	return _load("combat")


## Diplomatie (data/diplomacy.json) : traités, opinion, souvenirs, talents des peuples, IA.
static func diplomacy() -> Dictionary:
	return _load("diplomacy")


## Commerce (data/trade.json) : paliers de traité, routes, comptoirs, piraterie des routes.
static func trade() -> Dictionary:
	return _load("trade")


static func goods() -> Dictionary:
	return _load("goods")


## Identifiants des ressources stratégiques (Goods) : elles vivent dans le stock de l'empire comme les
## autres, mais restent hors des bilans et des barres (resource_ids ne les liste pas).
static func strategic_ids() -> Array[String]:
	if not _cache.has("strategic_ids"):
		var ids: Array[String] = []
		for d: Dictionary in goods()["strategic"]:
			ids.append(String(d["id"]))
		_cache["strategic_ids"] = ids
	return _cache["strategic_ids"]


## Toutes les ressources d'un stock : les six de base puis les stratégiques.
static func stock_ids() -> Array[String]:
	var ids := resource_ids()
	ids.append_array(strategic_ids())
	return ids


## Stabilité des systèmes (data/stability.json).
static func stability() -> Dictionary:
	return _load("stability")


## Pirates (data/pirates.json) : repaires, raids, tribut, contrats, primes.
static func pirates() -> Dictionary:
	return _load("pirates")


## Crises de fin de partie (data/crises.json) : réglages, sortes de crise, unités, cartes.
static func crises() -> Dictionary:
	return _load("crises")


## Peuples mineurs (data/minors.json) : catalogue, réglages, cartes.
static func minors() -> Dictionary:
	return _load("minors")


## Rayonnement culturel (data/culture.json) : réglages, paliers, sources, modificateurs, talents.
static func culture() -> Dictionary:
	return _load("culture")


## Puissances anciennes (data/ancients.json) : catalogue, réglages, unités, cartes.
static func ancients() -> Dictionary:
	return _load("ancients")


static func creatures() -> Dictionary:
	return _load("creatures")


static func guardians() -> Dictionary:
	return _load("guardians")


static func events() -> Dictionary:
	return _load("events")


static func relics() -> Dictionary:
	return _load("relics")


static func quests() -> Dictionary:
	return _load("quests")


## Religion (data/faiths.json) : cultes natals, noms, doctrines, préceptes, natures, propagation.
static func faiths() -> Dictionary:
	return _load("faiths")


static func politics() -> Dictionary:
	return _load("politics")


## L'Amphictyonie (data/amphictyony.json) : fondation, voix, séances, familles de résolutions.
static func amphictyony() -> Dictionary:
	return _load("amphictyony")


## Fin des guerres à conditions et sujets (voir Vassals).
static func vassals() -> Dictionary:
	return _load("vassals")


## Le Koinon : ligues d'empires (voir Koinon).
## Frontières et droit de passage (voir Borders).
static func borders() -> Dictionary:
	return _load("borders")


static func wars() -> Dictionary:
	return _load("wars")


## Habillage des vues de bataille (voir BattleScene, BattleBackdrop) : purement visuel.
static func battle_visuals() -> Dictionary:
	return _load("battle_visuals")


## Combat au sol et armées (voir Ground).
static func ground() -> Dictionary:
	return _load("ground")


## Logistique et ravitaillement (data/logistics.json) : zone, réserves, dépôts, talents.
static func logistics() -> Dictionary:
	return _load("logistics")


## Terrain galactique et environnements de bataille (voir Terrain).
static func terrain() -> Dictionary:
	return _load("terrain")


static func koinon() -> Dictionary:
	return _load("koinon")


## Espionnage (data/espionage.json) : cellules, réseaux, paliers, sondes.
static func espionage() -> Dictionary:
	return _load("espionage")


## Héros (data/heroes.json) : classes, postes, traits, renom, galerie de portraits.
static func heroes() -> Dictionary:
	return _load("heroes")


## Technologies : réglages (data/technologies.json : domaines, champs, ères, coûts, capacités) et
## catalogue ouvert data/tech/*.json fusionné sous "technologies" : d'abord les fichiers de « catalog »
## dans cet ordre, puis tout autre fichier du dossier par ordre alphabétique (un futur peuple ou pilier
## ajoute le sien sans toucher au reste). Une technologie déjà vue garde sa première définition.
static func technologies() -> Dictionary:
	if not _cache.has("technologies"):
		var d: Dictionary = _load("technologies_settings_raw")
		var out := d.duplicate()
		var techs := {}
		var names: Array = (d.get("catalog", []) as Array).duplicate()
		var extra: Array = []
		for f in DirAccess.get_files_at(DATA_DIR + "/tech"):
			var fn := String(f).trim_suffix(".remap")
			if fn.ends_with(".json") and not names.has(fn.get_basename()) and not extra.has(fn.get_basename()):
				extra.append(fn.get_basename())
		extra.sort()
		names.append_array(extra)
		for n in names:
			var path := "%s/tech/%s.json" % [DATA_DIR, n]
			if not FileAccess.file_exists(path):
				continue
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if not parsed is Dictionary:
				push_error("Données de jeu illisibles : %s" % path)
				continue
			var part: Dictionary = _to_ints(parsed).get("technologies", {})
			for tid in part:
				if not techs.has(tid):
					techs[tid] = part[tid]
		out["technologies"] = techs
		_cache["technologies"] = out
	return _cache["technologies"]


## Conditions de victoire (data/victories.json) : classiques, de peuple, date limite, score.
static func victories() -> Dictionary:
	return _load("victories")


static func deposit(id: String) -> Dictionary:
	if not _cache.has("deposits_by_id"):
		var idx := {}
		for d: Dictionary in rules()["deposits"]:
			if not idx.has(d["id"]):
				idx[d["id"]] = d
		_cache["deposits_by_id"] = idx
	return _cache["deposits_by_id"].get(id, {})


static func resource_ids() -> Array[String]:
	var ids: Array[String] = []
	for r: Dictionary in rules()["resources"]:
		ids.append(String(r["id"]))
	return ids


static func resource_label(id: String, short := false) -> String:
	for r: Dictionary in rules()["resources"]:
		if r["id"] == id:
			return r["short"] if short else r["label"]
	for r: Dictionary in goods()["strategic"]:
		if r["id"] == id:
			return r["short"] if short else r["label"]
	return id


## Coût ou rendement lisible : {"materials": 80, "energy": 30} -> "80 Mat, 30 Én".
static func format_amounts(amounts: Dictionary, signed := false) -> String:
	var parts := PackedStringArray()
	for r in stock_ids():
		var v := int(amounts.get(r, 0))
		if v != 0:
			parts.append(("%+d %s" if signed else "%d %s") % [v, resource_label(r, true)])
	return ", ".join(parts) if not parts.is_empty() else "rien"


static func _load(name: String) -> Variant:
	if not _cache.has(name):
		var path := "%s/%s.json" % [DATA_DIR, name.trim_suffix("_settings_raw")]
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed == null:
			push_error("Données de jeu illisibles : %s" % path)
			parsed = {}
		_cache[name] = _to_ints(parsed)
	return _cache[name]


static func _to_ints(v: Variant) -> Variant:
	if v is float and is_equal_approx(v, roundf(v)):
		return int(v)
	if v is Array:
		var out := []
		for x in v:
			out.append(_to_ints(x))
		return out
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _to_ints(v[k])
		return out
	return v
