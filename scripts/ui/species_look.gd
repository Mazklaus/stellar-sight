class_name SpeciesLook
extends RefCounted
## Allure visuelle d'un peuple sur le champ de bataille (étude visuel des combats, lot 3, prop. 29 à 33) :
## corps des figurines selon l'archétype, équipement, véhicules et couleur des tirs selon le registre,
## surcharges par peuple, troupes dédiées, et style de ses villes. Tout vient du bloc "species" et
## "cities" de data/battle_visuals.json. Un peuple créé dans l'éditeur hérite de ses couches.


static func _cfg(block: String) -> Dictionary:
	return GameData.battle_visuals().get(block, {})


static func _pick(table: Dictionary, key: String) -> Dictionary:
	return table.get(key, table.get("_default", {}))


static func archetype_of(fid: String) -> String:
	return String(GameData.faction(fid).get("species", {}).get("archetype", "")) if fid != "" else ""


static func registre_of(fid: String) -> String:
	return String(GameData.faction(fid).get("registre", "")) if fid != "" else ""


## Allure d'une troupe : {body, gear, vehicle, air, corpse, gait, scale, glow, shot}.
static func look(fid: String, troop: String = "") -> Dictionary:
	var sp := _cfg("species")
	var out := {"body": "bipede", "gear": "blaster", "vehicle": "chenilles", "air": "chasseur", "corpse": "corps",
			"gait": 9.0, "scale": 1.0, "glow": false, "shot": [1.0, 0.86, 0.45]}
	out.merge(_pick(sp.get("archetypes", {}), archetype_of(fid)), true)
	out.merge(_pick(sp.get("registres", {}), registre_of(fid)), true)
	# Surcharges propres à un peuple officiel ; un peuple créé suit ses couches.
	var people: Dictionary = sp.get("peoples", {})
	if people.has(fid):
		out.merge(people[fid], true)
	if troop != "":
		out.merge(sp.get("troops", {}).get(troop, {}), true)
	if troop == "milice":
		out["gear"] = "aucun"
	return out


static func shot_color(fid: String) -> Color:
	var c: Array = look(fid).get("shot", [1.0, 0.86, 0.45])
	return Color(float(c[0]), float(c[1]), float(c[2]))


## Identifiant du style de ville d'un peuple : peuple, sinon archétype, sinon registre.
static func city_style_id(fid: String) -> String:
	var c := _cfg("cities")
	var people: Dictionary = c.get("peoples", {})
	if people.has(fid):
		return String(people[fid])
	# Un peuple créé suit ses couches (archétype, registre) plutôt que le style de vaisseau emprunté.
	var arch: Dictionary = c.get("archetypes", {})
	if arch.has(archetype_of(fid)):
		return String(arch[archetype_of(fid)])
	var reg: Dictionary = c.get("registres", {})
	return String(reg.get(registre_of(fid), reg.get("_default", "heroique")))


static func city_style(fid: String) -> Dictionary:
	var styles: Dictionary = _cfg("cities").get("styles", {})
	return styles.get(city_style_id(fid), styles.get("heroique", {}))


static func city_biome(ter: String) -> Dictionary:
	return _pick(_cfg("cities").get("biomes", {}), ter)
