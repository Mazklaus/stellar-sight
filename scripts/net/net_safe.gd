class_name NetSafe
extends RefCounted
## Contrôles des données venues du réseau, avant qu'elles touchent la partie : seulement des types
## simples (nombres finis, textes courts, booléens, listes et dictionnaires peu profonds), avec des
## plafonds de taille. bytes_to_var ne recrée déjà jamais d'objet ; ceci écarte le reste (Vector2,
## textes géants, imbrications sans fin) qui ferait planter une vérification sur toutes les machines.

const ORDER_STRING_MAX := 256
const ORDER_ITEMS_MAX := 256
const ORDER_DEPTH_MAX := 3


## Une valeur ne contient-elle que des types simples, dans les limites ? `budget` compte les éléments.
static func is_plain(v: Variant, depth := ORDER_DEPTH_MAX, max_str := ORDER_STRING_MAX, budget: Array = [ORDER_ITEMS_MAX]) -> bool:
	budget[0] = int(budget[0]) - 1
	if int(budget[0]) < 0:
		return false
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT:
			return true
		TYPE_FLOAT:
			return is_finite(v)
		TYPE_STRING, TYPE_STRING_NAME:
			return String(v).length() <= max_str
		TYPE_ARRAY:
			if depth <= 0:
				return false
			for x in v:
				if not is_plain(x, depth - 1, max_str, budget):
					return false
			return true
		TYPE_DICTIONARY:
			if depth <= 0:
				return false
			for k in v:
				if not (k is String or k is StringName) or String(k).length() > 64:
					return false
				if not is_plain(v[k], depth - 1, max_str, budget):
					return false
			return true
	return false


## "" si l'ordre a une forme acceptable (type texte, joueur entier, valeurs simples), sinon la raison.
## Le contenu lui-même est ensuite vérifié par la simulation (SimCommands.validate).
static func check_order(c: Variant) -> String:
	if not c is Dictionary:
		return "ordre mal formé"
	var d: Dictionary = c
	if not d.get("type") is String or String(d["type"]).length() > 32:
		return "ordre mal formé"
	if not d.get("player") is int:
		return "ordre mal formé"
	if not is_plain(d):
		return "ordre trop gros ou mal formé"
	return ""


## Forme d'un peuple créé envoyé au salon, avant Species.check : listes là où il en faut, nombres
## et textes ailleurs (Species.check suppose ces types).
static func species_shape_ok(spec: Variant) -> bool:
	if not spec is Dictionary or not is_plain(spec, 2, 2048):
		return false
	var s: Dictionary = spec
	if not s.get("biomes") is Array:
		return false
	if s.has("traits") and not s["traits"] is Array:
		return false
	if s.has("temperament") and not (s["temperament"] is int or s["temperament"] is float):
		return false
	for k in s:
		if k not in ["biomes", "traits", "temperament"] and not (s[k] is String or s[k] is int or s[k] is float or s[k] is bool):
			return false
	return true
