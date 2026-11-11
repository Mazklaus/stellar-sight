class_name StateDiff
extends RefCounted
## Compare deux états de partie (GameState.to_dict(), ou une sauvegarde) et liste les écarts, chemin
## par chemin : sert à trouver la cause d'une désynchronisation en multijoueur.
##   StateDiff.differences(a, b) -> ["empires[2].materials : 140 ≠ 141", …]


## Écarts entre a et b, au plus max_count (dans l'ordre des clés triées : le premier est le plus
## « haut » dans l'état). Liste vide = identiques.
static func differences(a: Variant, b: Variant, max_count := 20) -> Array[String]:
	var out: Array[String] = []
	_walk(a, b, "", out, max_count)
	return out


## Premier écart, ou "" si les deux états sont identiques.
static func first_difference(a: Variant, b: Variant) -> String:
	var d := differences(a, b, 1)
	return d[0] if not d.is_empty() else ""


static func _walk(a: Variant, b: Variant, path: String, out: Array[String], max_count: int) -> void:
	if out.size() >= max_count:
		return
	if a is Dictionary and b is Dictionary:
		var keys := {}
		for k in a.keys():
			keys[str(k)] = k
		for k in b.keys():
			keys[str(k)] = k
		var names := keys.keys()
		names.sort()
		for name: String in names:
			var k: Variant = keys[name]
			var sub := name if path == "" else "%s.%s" % [path, name]
			if not a.has(k):
				out.append("%s : absent ≠ %s" % [sub, _short(b[k])])
			elif not b.has(k):
				out.append("%s : %s ≠ absent" % [sub, _short(a[k])])
			else:
				_walk(a[k], b[k], sub, out, max_count)
			if out.size() >= max_count:
				return
	elif _is_list(a) and _is_list(b):
		for i in mini(a.size(), b.size()):
			_walk(a[i], b[i], "%s[%d]" % [path, i], out, max_count)
			if out.size() >= max_count:
				return
		if a.size() != b.size():
			out.append("%s : %d éléments ≠ %d" % [path, a.size(), b.size()])
	elif not _same(a, b):
		out.append("%s : %s ≠ %s" % [path, _short(a), _short(b)])


static func _is_list(v: Variant) -> bool:
	return v is Array or typeof(v) >= TYPE_PACKED_BYTE_ARRAY


## Égalité stricte, sauf entier et flottant de même valeur (le JSON relit tous les nombres en flottants).
static func _same(a: Variant, b: Variant) -> bool:
	var na := typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT
	var nb := typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT
	if na and nb:
		return float(a) == float(b)
	return typeof(a) == typeof(b) and a == b


static func _short(v: Variant) -> String:
	var s := JSON.stringify(v) if (v is Dictionary or v is Array) else str(v)
	return s if s.length() <= 80 else s.substr(0, 77) + "..."
