class_name Designs
extends RefCounted
## Éditeur de vaisseaux : coques à emplacements typés, modules et modèles enregistrés (data/designs.json).
##
## Un modèle = une coque + ses modules intégrés (ceux du peuple, jamais retirables) + les modules posés
## par le joueur. Ses caractéristiques se calculent en additionnant la coque et les modules ; la valeur
## d'un module dépend de la taille de la coque (petite, moyenne, grande, titan).
##
## Les classes de combat de data/ships.json sont des « modèles d'origine » : leur coque et leurs modules
## sont décrits dans "origin", et GameData.ship() renvoie leurs caractéristiques calculées. Les modèles
## créés en partie vivent dans GameState.designs (sauvegardés) et sont enregistrés auprès de GameData
## pour que tout le reste du jeu (combat, construction, flottes) les lise comme une classe.
##
## Les types d'emplacements sont des données ("slot_types") : chacun dit quels emplacements de module il
## accepte. Chaque échelon de méga-coque au-delà du titan (Léviathan : colossal, Nef-monde : astral)
## ajoute son propre type, qui accepte aussi les modules des échelons inférieurs.

## Caractéristiques additives (coque + modules).
## fleet_speed : vitesse minimale de toute la flotte (moteur de trame).
const STATS := ["hp", "armor", "shield", "pd", "pd_fleet", "shield_fleet", "fleet_speed", "speed", "vision", "troops", "siege"]
## Drapeaux qu'un module transmet au vaisseau (fleet_repair : la flotte se répare partout comme chez
## elle ; fleet_barracks : ses troupes se reforment partout).
const FLAGS := ["blockade_runner", "adaptive", "fleet_repair", "fleet_barracks"]
const LINES := ["screen", "line", "rear"]
const TARGETS := ["nearest", "largest", "smallest", "rear"]
const NAME_MAX := 32
## Modèles actifs (non retirés) au plus par empire.
const MAX_ACTIVE := 40


static func data() -> Dictionary:
	return GameData.designs_data()


static func slot_types() -> Dictionary:
	return data().get("slot_types", {})


static func hull(id: String) -> Dictionary:
	return data().get("hulls", {}).get(id, {})


static func module(id: String) -> Dictionary:
	return data().get("modules", {}).get(id, {})


static func hull_ids() -> Array[String]:
	var out: Array[String] = []
	for k in data().get("hulls", {}):
		out.append(String(k))
	return out


static func module_ids() -> Array[String]:
	var out: Array[String] = []
	for k in data().get("modules", {}):
		out.append(String(k))
	return out


## Modèle d'origine d'une classe de data/ships.json ({"hull", "modules"}), ou {}.
static func origin(class_id: String) -> Dictionary:
	return data().get("origin", {}).get(class_id, {})


## Valeur d'un champ de module pour une taille de coque (les modules donnent {taille: valeur}).
static func _sized(v: Variant, size: String) -> Variant:
	if v is Dictionary and (v as Dictionary).has(size):
		return v[size]
	if v is Dictionary and (v.has("small") or v.has("medium") or v.has("large") or v.has("titan")):
		return 0
	return v


## Caractéristiques d'une coque équipée : coque + modules intégrés + modules posés.
## Renvoie un dictionnaire au format d'une classe de data/ships.json (hp, weapons, cost, days…).
static func compute(hull_id: String, modules: Array) -> Dictionary:
	var h := hull(hull_id)
	if h.is_empty():
		return {}
	var size := String(h["size"])
	var out := {"size": size, "hull": hull_id, "military": true}
	for k in STATS:
		out[k] = int(h.get(k, 0))
	out["cost"] = (h.get("cost", {}) as Dictionary).duplicate()
	out["upkeep"] = (h.get("upkeep", {}) as Dictionary).duplicate()
	out["days"] = int(h.get("days", 1))
	var weapons := {}
	var all: Array = []
	all.append_array(h.get("integrated", []))
	all.append_array(modules)
	for mid in all:
		var m := module(String(mid))
		for k in STATS:
			if m.has(k):
				out[k] = int(out[k]) + int(_sized(m[k], size))
		for fam in m.get("weapons", {}):
			var p := int(_sized(m["weapons"][fam], size))
			if p != 0:
				weapons[fam] = int(weapons.get(fam, 0)) + p
		var raw: Dictionary = m.get("cost", {})
		var cost: Dictionary = raw.get(size, {}) if raw.has(size) else raw
		for r in cost:
			out["cost"][r] = int(out["cost"].get(r, 0)) + int(cost[r])
		# Méga-coques des échelons supérieurs : leurs équipes posent plusieurs modules à la fois.
		@warning_ignore("integer_division")
		out["days"] = int(out["days"]) + int(_sized(m.get("days", 0), size)) * int(h.get("module_days_pct", 100)) / 100
		for flag in FLAGS:
			if m.get(flag, false):
				out[flag] = true
	for k in STATS:
		out[k] = maxi(0, int(out[k]))
	out["speed"] = maxi(1, int(out["speed"]))
	out["vision"] = maxi(1, int(out["vision"]))
	out["days"] = maxi(1, int(out["days"]))
	out["hp"] = maxi(1, int(out["hp"]))
	if not weapons.is_empty():
		out["weapons"] = weapons
	var cost_out := {}
	for r in out["cost"]:
		if int(out["cost"][r]) > 0:
			cost_out[r] = int(out["cost"][r])
	out["cost"] = cost_out
	return out


## Répartit les modules posés dans les emplacements de la coque. Renvoie "" si tout tient,
## sinon la raison. Chaque module va d'abord dans un emplacement de son propre type, puis dans un
## type qui l'accepte aussi (un emplacement lourd accepte une arme, par exemple).
##
## extra (voir extras) : modules qui, grâce aux marques de l'empire, tiennent aussi dans d'autres types
## d'emplacements ou sur d'autres tailles de coque (miniaturisation).
static func check_fit(hull_id: String, modules: Array, extra := {}) -> String:
	var h := hull(hull_id)
	if h.is_empty():
		return "coque inconnue : %s" % hull_id
	var free := {}
	var slots: Dictionary = h.get("slots", {})
	for t in slots:
		free[t] = int(slots[t])
	var types := slot_types()
	# Les modules les plus exigeants (acceptés par le moins de types) se placent d'abord.
	var order: Array = modules.duplicate()
	var hosts := {}
	for mid in order:
		var m := module(String(mid))
		if m.is_empty():
			return "module inconnu : %s" % mid
		var kind := String(m.get("slot", ""))
		if kind == "integrated":
			return "%s est intégré à une coque de peuple : il ne se pose pas à la main" % String(m.get("label", mid))
		var sizes: Array = m.get("sizes", [])
		var more: Array = extra.get(mid, [])
		if not sizes.is_empty() and not sizes.has(String(h["size"])) and more.is_empty():
			return "%s ne tient pas sur une coque de cette taille" % String(m.get("label", mid))
		var can: Array = []
		for t in types:
			if (types[t].get("accepts", []) as Array).has(kind) and (sizes.is_empty() or sizes.has(String(h["size"]))):
				can.append(String(t))
		for t in more:
			if not can.has(t):
				can.append(String(t))
		hosts[mid] = can
	order.sort_custom(func(a, b): return (hosts[a] as Array).size() < (hosts[b] as Array).size())
	for mid in order:
		var m := module(String(mid))
		var kind := String(m.get("slot", ""))
		var placed := false
		if int(free.get(kind, 0)) > 0:
			free[kind] = int(free[kind]) - 1
			placed = true
		else:
			for t in hosts[mid]:
				if int(free.get(t, 0)) > 0:
					free[t] = int(free[t]) - 1
					placed = true
					break
		if not placed:
			return "plus d'emplacement libre pour %s (%s)" % [String(m.get("label", mid)), String(types.get(kind, {}).get("label", kind)).to_lower()]
	return ""


## Miniaturisation (façon Master of Orion II) : à partir d'une marque donnée, certains modules tiennent
## dans d'autres emplacements. Renvoie {module: [types d'emplacements en plus]} pour cette coque.
static func extras(state: GameState, empire_id: int, hull_id: String) -> Dictionary:
	var out := {}
	var size := String(hull(hull_id).get("size", ""))
	var marks := Research.marks(state, empire_id) if state != null else {}
	for r: Dictionary in data().get("miniaturisation", []):
		if int(marks.get(String(r["family"]), 1)) < int(r["mark"]) or not (r.get("sizes", []) as Array).has(size):
			continue
		for mid in r["modules"]:
			if not out.has(mid):
				out[mid] = []
			if not (out[mid] as Array).has(String(r["slot"])):
				out[mid].append(String(r["slot"]))
	return out


## Règle de miniaturisation qui concerne un module ({} s'il n'y en a pas).
static func miniaturisation_of(mid: String) -> Dictionary:
	for r: Dictionary in data().get("miniaturisation", []):
		if (r["modules"] as Array).has(mid):
			return r
	return {}


## Coques qu'un peuple peut utiliser, dans l'ordre des données. Comme pour les classes, une coque
## de peuple demande des couches d'espèce ("requires"."species"), jamais un id de faction, et peut
## en remplacer une autre ("replaces").
static func hull_ids_for(faction_id: String) -> Array[String]:
	var f := GameData.faction(faction_id)
	var out: Array[String] = []
	var replaced := {}
	for hid in hull_ids():
		var h := hull(hid)
		if not FactionTraits.species_matches(f, h.get("requires", {}).get("species", {})):
			continue
		if h.has("replaces"):
			replaced[String(h["replaces"])] = true
		out.append(hid)
	var kept: Array[String] = []
	for hid in out:
		if not replaced.has(hid):
			kept.append(hid)
	return kept


## Technologies qu'il faut pour une coque équipée (coque + modules posés), sans doublon.
static func required_techs(hull_id: String, modules: Array) -> Array:
	var out: Array = []
	for t in hull(hull_id).get("requires_tech", []):
		if not out.has(t):
			out.append(t)
	for mid in modules:
		for t in module(String(mid)).get("requires_tech", []):
			if not out.has(t):
				out.append(t)
	return out


# --- Modèles enregistrés ------------------------------------------------------------------------

## Caractéristiques d'un modèle enregistré, au format d'une classe (lues par GameData.ship()).
static func stats_of(rec: Dictionary) -> Dictionary:
	var hid := String(rec.get("hull", ""))
	var mods: Array = rec.get("modules", [])
	var sd := compute(hid, mods)
	if sd.is_empty():
		return {}
	var h := hull(hid)
	var name := String(rec.get("name", h.get("label", hid)))
	sd["label"] = name
	sd["plural"] = name
	sd["line"] = String(rec.get("line", h.get("line", "line")))
	sd["target"] = String(rec.get("target", "nearest"))
	sd["owner"] = int(rec.get("owner", -1))
	sd["design"] = true
	sd["custom"] = true
	sd["version"] = int(rec.get("version", 1))
	sd["modules"] = mods.duplicate()
	sd["description"] = "Modèle conçu par l'amirauté sur une coque de %s." % String(h.get("label", hid)).to_lower()
	sd["requires_tech"] = required_techs(hid, mods)
	var req: Dictionary = (h.get("requires", {}) as Dictionary).duplicate(true)
	req.erase("species")
	if not req.is_empty():
		sd["requires"] = req
	if h.has("pop_cost"):
		sd["pop_cost"] = int(h["pop_cost"])
	return sd


## Enregistre les modèles d'une partie auprès de GameData (au chargement et à la création).
static func register_all(state: GameState) -> void:
	GameData.clear_custom_ships()
	for id in state.designs:
		GameData.register_custom_ship(String(id), stats_of(state.designs[id]))


## Modèles d'un empire, triés par identifiant ; active_only écarte les modèles retirés.
static func designs_of(state: GameState, empire_id: int, active_only := false) -> Array[Dictionary]:
	var ids := state.designs.keys()
	ids.sort()
	var out: Array[Dictionary] = []
	for id in ids:
		var rec: Dictionary = state.designs[id]
		if int(rec["owner"]) == empire_id and (not active_only or not rec.get("retired", false)):
			out.append(rec)
	return out


## Ce qu'un empire peut mettre en chantier : classes de son peuple (modèles d'origine compris)
## puis ses propres modèles actifs.
static func buildable_ids(state: GameState, empire_id: int) -> Array[String]:
	var e := state.get_empire(empire_id)
	if e == null:
		return []
	var out: Array[String] = FactionTraits.ship_ids_for(e.faction_id).duplicate()
	for rec in designs_of(state, empire_id, true):
		out.append(String(rec["id"]))
	return out


## Un empire peut-il construire ce vaisseau (classe de son peuple, ou modèle à lui non retiré) ?
static func can_build_id(state: GameState, empire_id: int, ship_id: String) -> bool:
	if state.designs.has(ship_id):
		var rec: Dictionary = state.designs[ship_id]
		if int(rec["owner"]) != empire_id or rec.get("retired", false):
			return false
		var e := state.get_empire(empire_id)
		return e != null and hull_ids_for(e.faction_id).has(String(rec["hull"]))
	var e2 := state.get_empire(empire_id)
	return e2 != null and FactionTraits.ship_ids_for(e2.faction_id).has(ship_id)


## Vérifie un modèle avant de l'enregistrer. spec : {"name", "hull", "modules", "line", "target",
## "previous" (identifiant du modèle dont c'est une nouvelle version, facultatif)}.
static func check_save(state: GameState, empire_id: int, spec: Dictionary) -> String:
	var e := state.get_empire(empire_id)
	if e == null:
		return "empire inconnu : %d" % empire_id
	var name := String(spec.get("name", "")).strip_edges()
	if name == "":
		return "il faut un nom pour le modèle"
	if name.length() > NAME_MAX:
		return "nom trop long (%d caractères au plus)" % NAME_MAX
	var hid := String(spec.get("hull", ""))
	if hull(hid).is_empty():
		return "coque inconnue : %s" % hid
	if not hull_ids_for(e.faction_id).has(hid):
		return "votre peuple n'utilise pas la coque %s" % String(hull(hid)["label"])
	var mods: Array = spec.get("modules", [])
	var why := check_fit(hid, mods, extras(state, empire_id, hid))
	if why != "":
		return why
	var techs := required_techs(hid, mods)
	if not Research.knows_all(state, empire_id, techs):
		return "technologie requise : %s" % Research.missing_text(state, empire_id, techs)
	if not LINES.has(String(spec.get("line", "line"))):
		return "rang inconnu : %s" % spec.get("line")
	if not TARGETS.has(String(spec.get("target", "nearest"))):
		return "priorité de cible inconnue : %s" % spec.get("target")
	var prev := String(spec.get("previous", ""))
	if prev != "":
		var old: Dictionary = state.designs.get(prev, {})
		if old.is_empty() or int(old["owner"]) != empire_id:
			return "modèle inconnu : %s" % prev
		if String(old["hull"]) != hid:
			return "une nouvelle version garde la même coque (construisez un autre modèle pour changer de coque)"
	elif designs_of(state, empire_id, true).size() >= MAX_ACTIVE:
		return "trop de modèles actifs (%d au plus) : retirez-en un" % MAX_ACTIVE
	for rec in designs_of(state, empire_id, true):
		if String(rec["name"]) == name and String(rec["id"]) != prev:
			return "un autre modèle porte déjà ce nom"
	return ""


## Enregistre un modèle (déjà vérifié par check_save) et renvoie son identifiant. Une nouvelle
## version retire l'ancienne de la liste de construction : ses vaisseaux, eux, restent tels quels.
static func save(state: GameState, empire_id: int, spec: Dictionary) -> String:
	var n := int(state.next_design_id)
	state.next_design_id = n + 1
	var id := "m%d_%d" % [empire_id, n]
	var mods: Array = []
	for m in spec.get("modules", []):
		mods.append(String(m))
	var rec := {
		"id": id,
		"owner": empire_id,
		"name": String(spec["name"]).strip_edges(),
		"hull": String(spec["hull"]),
		"modules": mods,
		"line": String(spec.get("line", hull(String(spec["hull"])).get("line", "line"))),
		"target": String(spec.get("target", "nearest")),
		"version": 1,
		"retired": false,
		"created": state.tick,
	}
	# Modèles d'IA : la classe d'origine qu'ils remplacent, et l'état de l'empire quand ils ont été conçus.
	if spec.has("role"):
		rec["role"] = String(spec["role"])
	if spec.has("sig"):
		rec["sig"] = String(spec["sig"])
	var prev := String(spec.get("previous", ""))
	if prev != "":
		var old: Dictionary = state.designs[prev]
		rec["version"] = int(old.get("version", 1)) + 1
		rec["previous"] = prev
		old["retired"] = true
	state.designs[id] = rec
	GameData.register_custom_ship(id, stats_of(rec))
	return id


static func check_retire(state: GameState, empire_id: int, design_id: String) -> String:
	var rec: Dictionary = state.designs.get(design_id, {})
	if rec.is_empty() or int(rec["owner"]) != empire_id:
		return "modèle inconnu : %s" % design_id
	return ""


## Nom lisible d'un vaisseau (modèle ou classe).
static func label(ship_id: String) -> String:
	return String(GameData.ship(ship_id).get("label", ship_id))


# --- Conception automatique -----------------------------------------------------------------------
# Le bouton « Concevoir pour moi » du Chantier et les IA utilisent le même outil. Un rôle dit ce que le
# modèle doit faire (portée préférée, défense, soutien) ; la qualité dit à quel point le choix est
# réfléchi : 0 maladroit (modules au hasard parmi ceux qui conviennent), 1 équilibré, 2 adapté à
# l'adversaire (défenses contre ses armes, armes contre ses défenses).

## Rôles : libellé, poids des phases (longue, moyenne, courte), arme préférée, rang, soutien voulu.
const ROLES := {
	"assaut": {"label": "Assaut", "phases": [0, 1, 3], "line": "screen", "support": ["propulseurs", "belier_siege"]},
	"ligne": {"label": "Ligne", "phases": [1, 3, 1], "line": "line", "support": ["soute_troupes", "propulseurs"]},
	"escorte": {"label": "Escorte", "phases": [1, 1, 1], "line": "screen", "defense_first": "antimissile", "support": ["reseau_antimissile"]},
	"torpilleur": {"label": "Torpilleur", "phases": [0, 2, 2], "prefer": "torpedo", "line": "line", "support": ["propulseurs"]},
	"artillerie": {"label": "Artillerie", "phases": [3, 1, 0], "line": "rear", "support": ["capteurs", "propulseurs"]},
	"porteur": {"label": "Porteur", "phases": [1, 1, 1], "prefer": "fighters", "line": "rear", "support": ["reseau_antimissile", "capteurs"]},
	"invasion": {"label": "Invasion", "phases": [0, 0, 0], "line": "rear", "unarmed": true, "support": ["soute_troupes"]},
	"siege": {"label": "Siège", "phases": [1, 1, 1], "line": "rear", "support": ["belier_siege", "soute_troupes"]},
}
## Rôle de chaque modèle d'origine (l'IA remplace ses classes par ses propres modèles de même rôle).
const CLASS_ROLES := {
	"corvette": "assaut", "coursier": "assaut", "martyr": "assaut", "fregate": "ligne", "fregate_quarante": "ligne",
	"croiseur": "ligne", "escorteur": "escorte", "torpilleur": "torpilleur", "transport": "invasion",
	"bombarde": "siege", "cuirasse": "artillerie", "porte_vaisseaux": "porteur", "ruche_mere": "porteur", "titan": "ligne",
	"leviathan": "ligne", "nef_monde": "ligne",
}


## Ce que montrent les adversaires dans les batailles où l'empire s'est battu : part des armes arrêtées
## par le blindage ou le bouclier, armes interceptables, et défenses de leurs coques.
static func threat(state: GameState, empire_id: int) -> Dictionary:
	var out := {"armor": 0, "shield": 0, "intercept": 0, "their_armor": 0, "their_shield": 0, "seen": 0}
	var table: Dictionary = GameData.combat().get("weapons", {})
	for r: Dictionary in state.battle_reports:
		var mine := false
		for u in r.get("units", []):
			if int(u[0]) == empire_id:
				mine = true
				break
		if not mine:
			continue
		for u in r.get("units", []):
			if int(u[0]) == empire_id:
				continue
			var sd := GameData.ship(String(u[1]))
			for fam in sd.get("weapons", {}):
				var w: Dictionary = table.get(fam, {})
				var p := int(sd["weapons"][fam])
				out[String(w.get("defense", "armor"))] = int(out.get(String(w.get("defense", "armor")), 0)) + p
				if w.get("intercept", false):
					out["intercept"] = int(out["intercept"]) + p
			out["their_armor"] = int(out["their_armor"]) + int(sd.get("armor", 0))
			out["their_shield"] = int(out["their_shield"]) + int(sd.get("shield", 0))
			out["seen"] = int(out["seen"]) + 1
	return out


## Modules posables par l'empire sur cette coque, pour un type d'emplacement donné.
static func _usable(state: GameState, empire_id: int, hull_id: String, slot_type: String) -> Array[String]:
	var size := String(hull(hull_id).get("size", "small"))
	var accepts: Array = slot_types().get(slot_type, {}).get("accepts", [])
	var extra := extras(state, empire_id, hull_id)
	var out: Array[String] = []
	for mid in module_ids():
		var m := module(mid)
		var sizes: Array = m.get("sizes", [])
		var native := accepts.has(String(m.get("slot", ""))) and (sizes.is_empty() or sizes.has(size))
		if not native and not (extra.get(mid, []) as Array).has(slot_type):
			continue
		if not Research.knows_all(state, empire_id, m.get("requires_tech", [])):
			continue
		out.append(mid)
	return out


## Intérêt d'une arme pour un rôle : dégâts pondérés par phase, et (qualité 2) contre les défenses vues.
@warning_ignore("integer_division")
static func _weapon_score(mid: String, size: String, role: Dictionary, quality: int, th: Dictionary) -> int:
	var m := module(mid)
	var table: Dictionary = GameData.combat().get("weapons", {})
	var phases: Array = role.get("phases", [1, 1, 1])
	var score := 0
	for fam in m.get("weapons", {}):
		var p := int(_sized(m["weapons"][fam], size))
		var eff: Array = table.get(fam, {}).get("eff", [0, 0, 0])
		var s := 0
		for i in 3:
			s += p * int(eff[i]) * int(phases[i])
		if String(role.get("prefer", "")) == fam:
			s = s * 3 + 1000
		if quality >= 2 and int(th.get("seen", 0)) > 0:
			var def := String(table.get(fam, {}).get("defense", "armor"))
			var theirs := int(th.get("their_" + def, 0))
			var other := int(th.get("their_shield" if def == "armor" else "their_armor", 0))
			if theirs * 2 < other:
				s = s * 13 / 10
			elif theirs > other * 2:
				s = s * 7 / 10
		score += s
	return score


## Défense choisie pour le n-ième emplacement de défense.
static func _defense_pick(options: Array[String], n: int, role: Dictionary, quality: int, th: Dictionary) -> String:
	var first := String(role.get("defense_first", ""))
	if n == 0 and first != "" and options.has(first):
		return first
	var armor := options.has("plaques_blindage")
	var shield := options.has("bouclier")
	if quality >= 2 and int(th.get("seen", 0)) > 0:
		if int(th.get("intercept", 0)) * 2 > int(th.get("armor", 0)) + int(th.get("shield", 0)) and options.has("antimissile") and n == 1:
			return "antimissile"
		var want_shield := int(th.get("shield", 0)) > int(th.get("armor", 0))
		if want_shield and shield:
			return "bouclier"
		if armor:
			return "plaques_blindage"
	# Équilibré : blindage et bouclier en alternance.
	if armor and shield:
		return "plaques_blindage" if posmod(n, 2) == 0 else "bouclier"
	return options[0] if not options.is_empty() else ""


## L'arme qui apporte le plus à ce rôle parmi les options, avec des rendements décroissants : une
## deuxième famille d'armes vaut mieux qu'un sixième tube. "" s'il n'y a aucune arme.
static func _best_weapon(options: Array[String], mods: Array, size: String, role: Dictionary, quality: int, th: Dictionary) -> String:
	var best := -1
	var pick := ""
	for mid in options:
		if module(mid).get("weapons", {}).is_empty():
			continue
		@warning_ignore("integer_division")
		var sc := _weapon_score(mid, size, role, quality, th) / (1 + mods.count(mid))
		if sc > best:
			best = sc
			pick = mid
	return pick


## Modèle conçu automatiquement : {"hull", "modules", "line", "target"} (le nom reste à donner).
## salt rend les choix maladroits (qualité 0) différents d'un appel à l'autre, de façon déterministe.
static func auto_design(state: GameState, empire_id: int, hull_id: String, role_id: String, quality := 1, salt := 0) -> Dictionary:
	var role: Dictionary = ROLES.get(role_id, ROLES["ligne"])
	var size := String(hull(hull_id).get("size", "small"))
	var th := threat(state, empire_id) if quality >= 2 else {}
	var counts: Dictionary = hull(hull_id).get("slots", {})
	var mods: Array = []
	var n_def := 0
	var k := 0
	for t in slot_types():
		for i in int(counts.get(t, 0)):
			k += 1
			var options := _usable(state, empire_id, hull_id, String(t))
			if options.is_empty():
				continue
			var pick := ""
			if quality <= 0:
				pick = options[posmod(hash([state.seed_value, empire_id, hull_id, role_id, salt, k]), options.size())]
			elif t == "defense":
				pick = _defense_pick(options, n_def, role, quality, th)
				n_def += 1
			elif t == "support":
				# Au plus deux fois le même soutien, sauf pour les rôles qui en vivent (invasion, siège).
				var specialist := role_id in ["invasion", "siege"]
				for want in role.get("support", []):
					if not options.has(want):
						continue
					if want == "belier_siege" and mods.count("belier_siege") > 0 and role_id != "siege":
						continue
					if not specialist and mods.count(want) >= 2:
						continue
					pick = want
					break
			elif role.get("unarmed", false):
				pick = ""
			elif t == "heavy" and role_id == "porteur" and quality >= 1:
				# Un porteur mélange ses hangars : chasseurs, puis bombardiers, puis intercepteurs.
				var hangars := ["hangar_chasseurs", "hangar_bombardiers", "hangar_intercepteurs"]
				var known: Array = []
				for hgr in hangars:
					if options.has(hgr):
						known.append(hgr)
				if not known.is_empty():
					pick = known[posmod(mods.filter(func(x): return hangars.has(x)).size(), known.size())]
			elif t == "titanic" and role_id == "escorte" and options.has("bouclier_flotte"):
				pick = "bouclier_flotte"
			elif t == "colossal" or t == "astral":
				# Échelons supérieurs : la forge pour qui tient la durée, le brise-monde pour qui assiège,
				# sinon le canon à singularité et le moteur de trame ; à défaut, la meilleure arme.
				var support_role := role_id in ["escorte", "invasion", "siege"]
				var wish := ["forge_mobile", "canon_singularite"] if support_role else ["canon_singularite", "forge_mobile"]
				if t == "astral":
					wish = ["brise_monde", "moteur_trame"] if role_id in ["siege", "artillerie"] else ["moteur_trame", "brise_monde"]
				for want in wish:
					if options.has(want):
						pick = want
						break
				if pick == "":
					pick = _best_weapon(options, mods, size, role, quality, th)
			else:
				pick = _best_weapon(options, mods, size, role, quality, th)
			if pick != "":
				mods.append(pick)
	# Le placement final passe par la même règle que le joueur : on retire ce qui ne tiendrait pas.
	var extra := extras(state, empire_id, hull_id)
	while not mods.is_empty() and check_fit(hull_id, mods, extra) != "":
		mods.pop_back()
	return {"hull": hull_id, "modules": mods, "line": String(role.get("line", "line")), "target": "largest" if role_id in ["torpilleur", "artillerie"] else "nearest"}
