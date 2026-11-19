class_name Research
extends RefCounted
## La recherche : fonctions pures qui LISENT l'état (data/technologies.json).
## EconomySystem fait avancer la file au bilan mensuel, SimCommands valide les ordres, et l'interface
## affiche les mêmes coûts et les mêmes refus.
##
## - Quatre domaines (armement, génie, économie, société) sur cinq ères. Une ère s'ouvre dans un
##   domaine quand on y connaît assez de technologies de l'ère précédente (era_thresholds).
## - Une seule ressource, le Savoir, produite par la population et les bâtiments de recherche.
##   Il s'accumule dans le stock ; chaque mois, la technologie en tête de file en consomme
##   jusqu'à deux fois le revenu (spend_rate_pct).
## - Le coût monte avec chaque technologie connue et avec la taille de l'empire.
## - Une technologie peut demander des couches d'espèce (requires.species), être interdite à
##   certaines (forbidden), en remplacer une commune (replaces) ou être hérétique (heretic : plus
##   chère et coûteuse en ferveur). Tout passe par FactionTraits.species_matches, pour que les
##   peuples personnalisés de l'éditeur y aient droit aussi.
##
## Effets des technologies (champ effects, effects_exalted pendant l'Exaltation) : voir aggregate().

const MAX_QUEUE := 12


static func data() -> Dictionary:
	return GameData.technologies()


static func tech(id: String) -> Dictionary:
	return data().get("technologies", {}).get(id, {})


static func exists(id: String) -> bool:
	return data().get("technologies", {}).has(id)


## Identifiant à garder pour une technologie lue dans une sauvegarde : elle-même si elle existe, son
## héritière si elle a été renommée ou fondue dans une autre (champ « renamed » des réglages), "" si
## elle a disparu.
static func heir_of(id: String) -> String:
	if exists(id):
		return id
	var to := String(data().get("renamed", {}).get(id, ""))
	return to if to != "" and exists(to) else ""


static func domain_ids() -> Array[String]:
	var out: Array[String] = []
	for d: Dictionary in data().get("domains", []):
		out.append(String(d["id"]))
	return out


static func domain(id: String) -> Dictionary:
	for d: Dictionary in data().get("domains", []):
		if d["id"] == id:
			return d
	return {}


static func eras() -> int:
	return int(data().get("eras", 5))


# --- Technologies d'un peuple -------------------------------------------------------------------
## Ce qu'un peuple voit de l'arbre : couches d'espèce (requires, forbidden, replaces), capacités (needs :
## un peuple sans vaisseau ne voit pas les canons) et piliers coupés par les options de partie (pillar).
## Les capacités se lisent dans les couches (sortes insolites posées par une brique, archétype,
## gouvernement, régime), jamais dans l'identifiant du peuple : un peuple de l'éditeur y a droit aussi.
## Sans état (state = null), tous les piliers comptent comme en jeu.

static var _info_cache := {}


## Technologies de l'arbre d'une faction (toutes visibles dès le début), dans l'ordre des données.
static func visible_ids(faction: Dictionary, state: GameState = null, eid := -1) -> Array[String]:
	return _info(faction, state, eid)["ids"]


## Les mêmes, pour l'empire d'un état (piliers de la partie, condition du peuple).
static func visible_for(state: GameState, eid: int) -> Array[String]:
	var e := state.get_empire(eid)
	return visible_ids(e.faction(), state, eid) if e != null else ([] as Array[String])


static func is_visible(faction: Dictionary, tid: String, state: GameState = null, eid := -1) -> bool:
	return (_info(faction, state, eid)["set"] as Dictionary).has(tid)


## La technologie commune que celle-ci remplace pour ce peuple ("" si aucune).
static func replaced_by(faction: Dictionary, tid: String) -> String:
	return String((_info(faction, null, -1)["repl"] as Dictionary).get(tid, ""))


## Clé du cache : le peuple, les capacités qui lui manquent et les piliers coupés.
static var _lack_memo := {}


static func _info_key(faction: Dictionary, state: GameState, eid: int) -> String:
	var fid := String(faction.get("id", ""))
	var sh: int = faction.get("species", {}).hash()
	var m: Array = _lack_memo.get(fid, [])
	if m.is_empty() or not is_same(m[0], faction) or int(m[1]) != sh:
		var lack0 := PackedStringArray()
		var dyn := false
		for cap in capability_ids():
			if lacks(faction, cap):
				lack0.append(cap)
				if (capability(cap).get("until_arrived", []) as Array).has(Insolites.kind_of_faction(faction)):
					dyn = true
		m = [faction, sh, ",".join(lack0), dyn]
		_lack_memo[fid] = m
	var lack: String = m[2]
	if bool(m[3]) and state != null and eid >= 0:
		var l2 := PackedStringArray()
		for cap in capability_ids():
			if lacks(faction, cap, state, eid):
				l2.append(cap)
		lack = ",".join(l2)
	var off := ""
	if state != null:
		for p in pillar_ids():
			if not pillar_on(state, p):
				off += p + ","
		if eid >= 0 and not state.transcendence.is_empty():
			off += "voie:" + Transcendence.path_of(state, eid)
	return fid + "|" + lack + "|" + off + "|" + str(sh)


static func _info(faction: Dictionary, state: GameState, eid: int) -> Dictionary:
	var key := _info_key(faction, state, eid)
	if _info_cache.has(key):
		return _info_cache[key]
	var techs: Dictionary = data().get("technologies", {})
	var out: Array[String] = []
	var replaced := {}
	for tid in techs:
		var t: Dictionary = techs[tid]
		if not FactionTraits.species_matches(faction, t.get("requires", {}).get("species", {})):
			continue
		var forbid: Dictionary = t.get("forbidden", {}).get("species", {})
		if not forbid.is_empty() and FactionTraits.species_matches(faction, forbid):
			continue
		var useless := false
		for cap in t.get("needs", []):
			if lacks(faction, String(cap), state, eid):
				useless = true
		if useless or (state != null and t.has("pillar") and not pillar_on(state, String(t["pillar"]))):
			continue
		# Voie de transcendance (prop. 66 de l'arbre) : seule la voie choisie se montre.
		if t.has("path") and (state == null or eid < 0 or state.transcendence.is_empty() or Transcendence.path_of(state, eid) != String(t["path"])):
			continue
		if t.has("replaces"):
			replaced[String(t["replaces"])] = String(tid)
		out.append(String(tid))
	var kept: Array[String] = []
	var set := {}
	var counts := {}
	for tid in out:
		if not replaced.has(tid):
			kept.append(tid)
			set[tid] = true
			var t: Dictionary = techs[tid]
			if not t.has("mastery"):
				var ck := "%s:%d" % [String(t["domain"]), int(t.get("era", 1))]
				counts[ck] = int(counts.get(ck, 0)) + 1
	# Une Maîtrise suit sa parente : remplacée (technologie de peuple) ou sans objet, elle disparaît.
	var orphans := kept.filter(func(m): return techs[m].has("mastery") and not set.has(String(techs[m]["mastery"])))
	for m in orphans:
		kept.erase(m)
		set.erase(m)
	var repl := {}
	for tid in kept:
		if techs[tid].has("replaces"):
			repl[String(techs[tid]["replaces"])] = tid
	var info := {"ids": kept, "set": set, "repl": repl, "counts": counts}
	_info_cache[key] = info
	return info


## Une technologie qui en remplace une autre compte comme elle pour les prérequis. Un prérequis que ce
## peuple ne voit pas (sans objet pour lui, ou pilier coupé) ne bloque pas : vis = technologies visibles.
static func _satisfies(faction: Dictionary, have: Dictionary, pre: String, vis := {}) -> bool:
	if have.has(pre):
		return true
	var alt := replaced_by(faction, pre)
	if alt != "":
		return have.has(alt)
	return not vis.is_empty() and not vis.has(pre)


# --- Capacités et piliers ----------------------------------------------------------------------

static var _cap_ids: Array = []
static var _pillar_ids: Array = []


static func capability_ids() -> Array:
	if _cap_ids.is_empty():
		for k in data().get("capabilities", {}):
			if not String(k).begins_with("_"):
				_cap_ids.append(String(k))
	return _cap_ids


static func capability(cap: String) -> Dictionary:
	return data().get("capabilities", {}).get(cap, {})


## Le peuple n'a-t-il pas cette capacité ? (state, eid : condition qui change en partie, comme
## l'Exode posé sur la Terre promise, prop. 72 de l'étude de l'arbre.)
static func lacks(faction: Dictionary, cap: String, state: GameState = null, eid := -1) -> bool:
	var c := capability(cap)
	if c.is_empty():
		return false
	var sp := FactionTraits.species(faction)
	var kind := Insolites.kind_of_faction(faction)
	var lack := false
	if kind != "" and (c.get("kinds", []) as Array).has(kind):
		lack = true
	elif (c.get("archetypes", []) as Array).has(String(sp.get("archetype", ""))):
		lack = true
	elif (c.get("gouvernements", []) as Array).has(String(sp.get("gouvernement", ""))):
		lack = true
	elif bool(c.get("diet", false)) and faction.has("diet"):
		lack = true
	else:
		for k in c.get("zero", []):
			if faction.has(k) and int(faction[k]) == 0:
				lack = true
		for k in c.get("has", []):
			if faction.has(k):
				lack = true
	if lack and state != null and eid >= 0 and (c.get("until_arrived", []) as Array).has(kind):
		lack = int(Insolites.emp(state, eid).get("arrived", 0)) == 0
	return lack


## Libellés « sans vaisseau », « sans nourriture »... des capacités qui manquent au peuple.
static func lacking_labels(faction: Dictionary, state: GameState = null, eid := -1) -> PackedStringArray:
	var out := PackedStringArray()
	for cap in capability_ids():
		if lacks(faction, cap, state, eid):
			out.append(String(capability(cap).get("lack", cap)))
	return out


static func pillar_ids() -> Array:
	if _pillar_ids.is_empty():
		for k in data().get("pillars", {}):
			if not String(k).begins_with("_"):
				_pillar_ids.append(String(k))
	return _pillar_ids


static func pillar_label(p: String) -> String:
	return String(data().get("pillars", {}).get(p, p))


## Le pilier optionnel est-il en jeu dans cette partie ?
static func pillar_on(state: GameState, p: String) -> bool:
	match p:
		"terrain": return Terrain.active(state)
		"furtivite": return Stealth.enabled(state)
		"genetique": return Genetics.enabled(state)
		"psionique": return Psionics.enabled(state)
		"contact": return Contact.enabled(state)
		"archeologie": return Archaeology.enabled(state)
		"transcendance": return Transcendence.enabled(state)
		"portails": return Portals.enabled(state)
		"logistique": return Logistics.active(state)
		"megastructures": return Megastructures.enabled(state)
		"superarmes": return Megastructures.enabled(state) and Megastructures.kind_allowed(state, "brise_monde")
		"forge_mondes": return WorldForge.enabled(state)
		"ecologie": return Ecology.enabled(state)
		"religion": return state.faith_on
		"cour": return Court.enabled(state)
		"dynastie": return Rulers.enabled(state)
		"politique": return state.politics_on
		"koinon": return state.koinon_on
		"vassaux": return state.vassals_on
		"amphictyonie": return state.amph_on
		"economie_privee": return Private.enabled(state)
		"marche": return Goods.market_on(state)
		"populations": return state.peoples_on
		"pirates": return state.pirate_density != "aucun"
		"creatures": return String(state.fauna.get("density", "aucune")) != "aucune"
		"mineurs": return Minors.enabled(state)
		"mondes_vivants": return LivingWorlds.enabled(state)
		"frontieres": return Borders.active(state)
		"guerre": return state.wars_on
		"crises": return Crisis.enabled(state)
		"kardashev": return Kardashev.enabled(state)
	return true


## Lot 3 de l'arbre : verrou de partie d'une technologie ("" si elle est libre). kard = palier de
## Kardashev atteint (prop. 67) ; path = voie de transcendance choisie (prop. 66, voir aussi _info).
static func gate_reason(state: GameState, empire_id: int, tid: String) -> String:
	var t := tech(tid)
	if t.has("kard") and Kardashev.enabled(state) and Kardashev.tier(state, empire_id) < int(t["kard"]):
		return "il faut atteindre le type %s de Kardashev" % ["I", "II", "III"][clampi(int(t["kard"]) - 1, 0, 2)]
	if t.has("path") and Transcendence.path_of(state, empire_id) != String(t["path"]):
		return "réservée à la voie « %s »" % Transcendence.path_label(String(t["path"]))
	return ""


# --- Sortes de technologies ----------------------------------------------------------------------

## Maîtrise (prop. 3) : bonus facultatif accroché à une technologie parente ; jamais prérequis, elle ne
## compte pas pour ouvrir l'ère suivante.
static func is_mastery(tid: String) -> bool:
	return tech(tid).has("mastery")


## Maîtrises accrochées à une technologie.
static func masteries_of(tid: String) -> Array[String]:
	var out: Array[String] = []
	var techs: Dictionary = data().get("technologies", {})
	for k in techs:
		if String(techs[k].get("mastery", "")) == tid:
			out.append(String(k))
	return out


## Trouvaille (prop. 10) : ne se recherche pas ; elle s'obtient par une curiosité, une ruine, une
## strate, une quête, une prise, une puissance ancienne ou un haut fait (Research.grant).
static func is_find(tid: String) -> bool:
	return bool(tech(tid).get("find", false))


## Technologie dangereuse (prop. 11) : elle rapproche la fin de partie du pilier Crises.
static func is_dangerous(tid: String) -> bool:
	return tech(tid).has("danger") or Crisis.is_forbidden_tech(tid)


static func danger_text(tid: String) -> String:
	return String(tech(tid).get("danger", "Technologie dangereuse : elle rapproche la fin de partie du pilier Crises."))


## Groupe de spécialisation (prop. 12, doctrines comprises) : on n'en recherche qu'une ; les autres
## ne s'obtiennent plus que par échange, vol, épaves ou trouvaille.
static func spec_group(tid: String) -> String:
	return String(tech(tid).get("spec", ""))


static func spec_members(group: String) -> Array[String]:
	var out: Array[String] = []
	if group == "":
		return out
	var techs: Dictionary = data().get("technologies", {})
	for k in techs:
		if String(techs[k].get("spec", "")) == group:
			out.append(String(k))
	return out


## L'autre branche déjà choisie (connue ou en file) qui ferme celle-ci ("" sinon).
static func spec_taken(planned: Dictionary, tid: String) -> String:
	for o in spec_members(spec_group(tid)):
		if o != tid and planned.has(o):
			return o
	return ""


## Champ de rangement (prop. 5) : id et libellé.
static func field_of(tid: String) -> String:
	return String(tech(tid).get("field", ""))


static func field_label(domain_id: String, field_id: String) -> String:
	for fd: Dictionary in domain(domain_id).get("fields", []):
		if String(fd["id"]) == field_id:
			return String(fd["label"])
	return "Destinée" if field_id == "destinee" else field_id


## Bande Peuple (prop. 6 revue) : une technologie propre au peuple qui ne remplace aucune technologie
## commune et n'en prépare aucune, et les Destinées (victoires de peuple). Les autres technologies de
## peuple restent à leur place dans leur domaine.
static func in_band(faction: Dictionary, tid: String) -> bool:
	var t := tech(tid)
	if t.has("victory"):
		return true
	if not t.has("requires") or t.has("replaces"):
		return false
	var techs: Dictionary = data().get("technologies", {})
	for k in visible_ids(faction):
		if not techs[k].has("requires") and (techs[k].get("pre", []) as Array).has(tid):
			return false
	# Rattachée à la chaîne commune par ses propres prérequis ? Elle reste dans le domaine si l'un
	# d'eux est commun et qu'elle n'est pas une victoire.
	for p in t.get("pre", []):
		if not tech(String(p)).has("requires"):
			return false
	return true


static func is_heretic(faction: Dictionary, tid: String) -> bool:
	var h: Dictionary = tech(tid).get("heretic", {})
	return not h.is_empty() and FactionTraits.species_matches(faction, h.get("species", {}))


## Propre à un peuple (demande des couches d'espèce).
static func is_specific(tid: String) -> bool:
	return tech(tid).has("requires")


## Ce que la technologie débloque pour ce peuple : bâtiments, classes de vaisseaux, coques et modules
## du Chantier (libellés).
static func unlocks(faction: Dictionary, tid: String) -> PackedStringArray:
	var out := PackedStringArray()
	for u: Dictionary in unlock_entries(faction, tid):
		out.append(String(u["text"]))
	return out


## Sortes de déblocage, pour les icônes de l'arbre et le filtre « ce que ça débloque » (prop. 106).
const UNLOCK_KINDS := {
	"batiment": "Bâtiments", "projet": "Projets", "merveille": "Merveilles", "mega": "Mégastructures", "forge": "Forge des mondes",
	"vaisseau": "Vaisseaux", "coque": "Coques", "module": "Modules", "tactique": "Tactiques", "regiment": "Régiments",
	"loi": "Lois et traités", "maitrise": "Maîtrises", "regle": "Règles et bonus",
}


static var _unlock_cache := {}


## Déblocages détaillés : [{kind, id, label, text}] (text = libellé affiché dans la liste). Gardés en
## cache par peuple : l'arbre les redessine souvent.
static func unlock_entries(faction: Dictionary, tid: String) -> Array:
	var key := "%s|%s|%d" % [String(faction.get("id", "")), tid, GameData.ship_ids().size()]
	if not _unlock_cache.has(key):
		_unlock_cache[key] = _unlock_entries(faction, tid)
	return _unlock_cache[key]


static func _unlock_entries(faction: Dictionary, tid: String) -> Array:
	var out: Array = []
	for bid in GameData.buildings():
		var bd := GameData.building(bid)
		if bd.get("requires_tech", []).has(tid) and FactionTraits.species_matches(faction, bd.get("requires", {}).get("species", {})):
			var l := String(bd.get("label", bid))
			var proj := bool(bd.get("project", false))
			out.append({"kind": "projet" if proj else "batiment", "id": bid, "label": l, "text": "%s (projet)" % l if proj else l})
	for wid in Wonders.all_ids():
		if Wonders.def(wid).get("requires_tech", []).has(tid):
			out.append({"kind": "merveille", "id": wid, "label": Wonders.label(wid), "text": "%s (merveille)" % Wonders.label(wid)})
	for k in Megastructures.kind_ids():
		var md := Megastructures.kind_def(k)
		if (md.get("tech", []) as Array).has(tid) and not bool(md.get("ruin_only", false)):
			out.append({"kind": "mega", "id": k, "label": Megastructures.label(k), "text": "%s (mégastructure)" % Megastructures.label(k)})
	for op in WorldForge.op_ids():
		if (WorldForge.op_def(op).get("tech", []) as Array).has(tid):
			out.append({"kind": "forge", "id": op, "label": WorldForge.op_label(op), "text": "%s (Forge des mondes)" % WorldForge.op_label(op)})
	for sid in FactionTraits.ship_ids_for(String(faction.get("id", ""))):
		if GameData.ship(sid).get("requires_tech", []).has(tid):
			var l := String(GameData.ship(sid).get("label", sid))
			out.append({"kind": "vaisseau", "id": sid, "label": l, "text": l})
	var seen := {}
	for u: Dictionary in out:
		seen[String(u["label"])] = true
	for hid in Designs.hull_ids_for(String(faction.get("id", ""))):
		var h := Designs.hull(hid)
		if h.get("requires_tech", []).has(tid) and not seen.has(String(h.get("label", hid))):
			out.append({"kind": "coque", "id": hid, "label": String(h.get("label", hid)), "text": "coque %s" % String(h.get("label", hid))})
	for mid in Designs.module_ids():
		var m := Designs.module(mid)
		if m.get("requires_tech", []).has(tid) and Designs.module_allowed_for(mid, faction):
			out.append({"kind": "module", "id": mid, "label": String(m.get("label", mid)), "text": "module %s" % String(m.get("label", mid))})
	for t in Ground.type_ids():
		var gd := Ground.type_def(t)
		if gd.get("requires_tech", []).has(tid) and FactionTraits.species_matches(faction, gd.get("requires", {}).get("species", {})):
			out.append({"kind": "regiment", "id": t, "label": String(gd.get("label", t)), "text": "régiment %s" % String(gd.get("label", t))})
	for t: Dictionary in Combat.data().get("tactics", []):
		if String(t.get("requires_tech", "")) == tid:
			out.append({"kind": "tactique", "id": String(t["id"]), "label": String(t["label"]), "text": "tactique %s" % String(t["label"])})
	# Lois et traités (lot 2, prop. 45 et 46).
	var tt := tech(tid)
	var tfx: Dictionary = tt.get("effects", {})
	if tfx.has("alliances"):
		out.append({"kind": "loi", "id": "alliance", "label": "Alliances", "text": "traité d'alliance"})
	if tfx.has("federation"):
		out.append({"kind": "loi", "id": "koinon", "label": "Fondation d'un Koinon", "text": "fondation d'un Koinon"})
	if tfx.has("treaty_migration"):
		out.append({"kind": "loi", "id": "migration", "label": "Traité de migration", "text": "traité de migration"})
	var lv := mini(4, int(tt.get("era", 1)))
	if String(tt.get("field", "")) == "etat" and not tt.has("mastery") and lv >= 2:
		out.append({"kind": "loi", "id": "lois_%d" % lv, "label": "Lois de niveau %d" % lv, "text": "lois de niveau %d (politique)" % lv})
	for hid in PeopleHulls.upgrades_of(tid):
		var hl := String(Designs.hull(hid).get("label", hid))
		out.append({"kind": "coque", "id": hid, "label": "%s amélioré" % hl, "text": "amélioration de la coque %s" % hl})
	for m in masteries_of(tid):
		out.append({"kind": "maitrise", "id": m, "label": String(tech(m).get("label", m)), "text": "Maîtrise : %s" % String(tech(m).get("label", m))})
	return out


## Sortes de déblocage d'une technologie (règle ou bonus si rien d'autre : effet chiffré ou règle
## décrite par son texte).
static func unlock_kinds(faction: Dictionary, tid: String) -> Array:
	var out := []
	for u: Dictionary in unlock_entries(faction, tid):
		if not out.has(u["kind"]):
			out.append(u["kind"])
	if out.is_empty() or (out.size() == 1 and out[0] == "maitrise"):
		out.append("regle")
	return out


## Chemin vers une technologie lointaine (prop. 107) : ce qu'il faut mettre en file, dans l'ordre, pour
## l'atteindre (prérequis manquants, puis de quoi ouvrir les ères : les moins chères de l'ère
## précédente). Ne compte que ce qui est déjà découvert ou en file. Vide si elle n'est pas atteignable.
static func plan_path(state: GameState, empire_id: int, target: String) -> Array[String]:
	var out: Array[String] = []
	var e := state.get_empire(empire_id)
	if e == null or not is_visible(e.faction(), target, state, empire_id) or e.techs.has(target) or is_find(target):
		return out
	var planned := e.techs.duplicate()
	for q in e.research_queue:
		planned[q] = true
	if planned.has(target):
		return out
	_plan_add(state, e, target, planned, out, 0)
	return out if out.has(target) else ([] as Array[String])


static func _plan_add(state: GameState, e: Empire, tid: String, planned: Dictionary, out: Array[String], depth: int) -> void:
	if planned.has(tid) or depth > 40:
		return
	var f := e.faction()
	var vis: Dictionary = _info(f, state, e.id)["set"]
	if not vis.has(tid) or is_find(tid) or spec_taken(planned, tid) != "":
		return
	var t := tech(tid)
	for p in t.get("pre", []):
		var pid := String(p)
		if _satisfies(f, planned, pid, vis):
			continue
		var alt := replaced_by(f, pid)
		_plan_add(state, e, alt if alt != "" else pid, planned, out, depth + 1)
	# Ères à ouvrir : de proche en proche, les technologies les moins chères des ères précédentes.
	var dom := String(t["domain"])
	for era in range(2, int(t.get("era", 1)) + 1):
		var guard := 0
		var tried := {}
		while not era_open(planned, dom, era, f, state, e.id) and guard < 16:
			guard += 1
			# D'abord celles dont les prérequis sont déjà prévus, puis les moins chères (avec leurs prérequis).
			var best := ""
			var best_key := 0
			for o in visible_for(state, e.id):
				var od := tech(o)
				if planned.has(o) or tried.has(o) or String(od["domain"]) != dom or int(od.get("era", 1)) != era - 1 or od.has("mastery") \
						or is_find(o) or od.has("victory") or od.has("requires") and not od.has("replaces") or spec_taken(planned, o) != "":
					continue
				var k := cost(state, e.id, o) + (0 if _pres_planned(f, planned, o, vis) else 1000000)
				if best == "" or k < best_key:
					best = o
					best_key = k
			if best == "":
				break
			tried[best] = true
			_plan_add(state, e, best, planned, out, depth + 1)
	for p in t.get("pre", []):
		if not _satisfies(f, planned, String(p), vis):
			return
	if era_open(planned, dom, int(t.get("era", 1)), f, state, e.id) and ultimate_ok(planned, tid):
		planned[tid] = true
		out.append(tid)


static func _pres_planned(f: Dictionary, planned: Dictionary, tid: String, vis: Dictionary) -> bool:
	for p in tech(tid).get("pre", []):
		if not _satisfies(f, planned, String(p), vis):
			return false
	return true


## Poids de la technologie pour l'IA selon son tempérament (champ ai {tempérament: %}, prop. 108),
## 100 par défaut.
static func ai_weight_pct(tid: String, temperament: String) -> int:
	return int(tech(tid).get("ai", {}).get(temperament, 100))


static func knows(state: GameState, empire_id: int, tid: String) -> bool:
	var e := state.get_empire(empire_id)
	return e != null and e.techs.has(tid)


## L'empire connaît-il toutes ces technologies ? Pour débloquer un bâtiment ou un vaisseau, il faut
## la technologie exacte : une variante de peuple débloque son propre bâtiment (Scriptorium à la place
## de l'Académie), pas celui de la technologie qu'elle remplace.
static func knows_all(state: GameState, empire_id: int, tids: Array) -> bool:
	var e := state.get_empire(empire_id)
	if e == null:
		return tids.is_empty()
	for t in tids:
		if not e.techs.has(String(t)):
			return false
	return true


## Libellés des technologies manquantes d'une liste ("" si rien ne manque).
static func missing_text(state: GameState, empire_id: int, tids: Array) -> String:
	var e := state.get_empire(empire_id)
	var parts := PackedStringArray()
	for t in tids:
		if e == null or not e.techs.has(String(t)):
			parts.append(String(tech(String(t)).get("label", t)))
	return ", ".join(parts)


# --- Ères ---------------------------------------------------------------------------------------

## Nombre de technologies d'une ère, dans un domaine, parmi celles de `have` (Maîtrises exclues).
static func count_in(have: Dictionary, domain_id: String, era: int) -> int:
	var n := 0
	for tid in have:
		var t := tech(String(tid))
		if String(t.get("domain", "")) == domain_id and int(t.get("era", 0)) == era and not t.has("mastery"):
			n += 1
	return n


static func era_threshold(era: int) -> int:
	var th: Array = data().get("era_thresholds", [])
	return int(th[era - 1]) if era >= 1 and era <= th.size() else 0


## Une ère est ouverte dans un domaine si l'on y connaît assez de technologies de l'ère précédente.
## Avec le peuple (faction), le seuil ne dépasse jamais ce que son arbre propose dans l'ère précédente :
## un peuple sans vaisseau, à qui l'on masque l'essentiel de l'Armement, peut quand même avancer.
static func era_open(have: Dictionary, domain_id: String, era: int, faction := {}, state: GameState = null, eid := -1) -> bool:
	if era <= 1:
		return true
	return count_in(have, domain_id, era - 1) >= era_need(domain_id, era, faction, state, eid)


## Technologies de l'ère précédente qu'il faut connaître pour ouvrir cette ère.
static func era_need(domain_id: String, era: int, faction := {}, state: GameState = null, eid := -1) -> int:
	var th := era_threshold(era)
	if faction.is_empty():
		return th
	var counts: Dictionary = _info(faction, state, eid)["counts"]
	return mini(th, int(counts.get("%s:%d" % [domain_id, era - 1], 0)))


## Palier d'une ère dans un domaine ({label, text, effects} ; vide s'il n'y en a pas).
static func tier(domain_id: String, era: int) -> Dictionary:
	return data().get("tiers", {}).get(domain_id, {}).get(str(era), {})


## Paliers d'ère ouverts pour un empire (prop. 4) : [{domain, era, label, text, effects}], domaine par domaine.
static func open_tiers(state: GameState, empire_id: int) -> Array:
	var out: Array = []
	var e := state.get_empire(empire_id)
	if e == null:
		return out
	var f := e.faction()
	for d in domain_ids():
		for era in range(2, eras() + 1):
			var tr := tier(d, era)
			if tr.is_empty() or not era_open(e.techs, d, era, f, state, empire_id):
				continue
			var x := tr.duplicate()
			x["domain"] = d
			x["era"] = era
			out.append(x)
	return out


## Ère la plus avancée ouverte dans au moins un domaine.
static func current_era(state: GameState, empire_id: int) -> int:
	var e := state.get_empire(empire_id)
	if e == null:
		return 1
	var best := 1
	var f := e.faction()
	for d in domain_ids():
		for era in range(2, eras() + 1):
			if era_open(e.techs, d, era, f, state, empire_id):
				best = maxi(best, era)
	return best


# --- Coûts --------------------------------------------------------------------------------------

## Coût en Savoir d'une technologie pour un empire, à cet instant.
@warning_ignore("integer_division")
## colonies : nombre de colonies fondées s'il est déjà connu (l'IA qui compare toutes les technologies).
static func cost(state: GameState, empire_id: int, tid: String, colonies := -1) -> int:
	var d := data()
	var t := tech(tid)
	var e := state.get_empire(empire_id)
	var era := clampi(int(t.get("era", 1)), 1, eras())
	var c := int(d["base_cost"][era - 1]) * int(d.get("cost_scale_pct", 100)) / 100
	var known := e.techs.size() if e else 0
	c = c * (1000 + int(d.get("per_known_permille", 0)) * known) / 1000
	if colonies < 0:
		colonies = cost_colonies(state, empire_id)
	var extra := maxi(0, colonies - int(d.get("free_colonies", 0))) * int(d.get("per_colony_pct", 0))
	if not state.admin.is_empty() and e != null and not e.is_npc():
		extra = Admin.research_pct(state, empire_id)  # le pilier Administration remplace ce surcoût
	c = c * (100 + extra) / 100
	if e:
		var f := e.faction()
		var rs: Dictionary = f.get("research", {})
		c = c * int(rs.get("domain_cost_pct", {}).get(String(t.get("domain", "")), 100)) / 100
		for tag in t.get("tags", []):
			c = c * int(rs.get("tag_cost_pct", {}).get(String(tag), 100)) / 100
		if is_heretic(f, tid):
			c = c * int(t["heretic"].get("cost_pct", 100)) / 100
		# Brevets d'un peuple mineur absorbé (trait d'assimilation de Tharsis, voir Minors).
		var tc := 0 if e.is_npc() else fx_int(state, empire_id, "tech_cost_pct")
		if tc != 0:
			c = c * maxi(10, 100 + tc) / 100
		# Instituts (annexes de l'Académie) : leur domaine coûte moins cher, 25 % au plus.
		var inst := Economy.institute_pct(state, empire_id, String(t.get("domain", "")))
		if inst != 0:
			c = c * (100 + inst) / 100
		if not e.is_npc():
			var kt := WondersCatalog.tech_cost_pct(state, empire_id, tid)  # Collège universel
			if kt != 0:
				c = c * maxi(10, 100 + kt) / 100
			var ke := KardashevWorld.tech_cost_pct(state, empire_id, tid)  # Émulation (Kardashev)
			if ke != 0:
				c = c * maxi(10, 100 + ke) / 100
	return maxi(1, c)


## Colonies qui comptent dans le surcoût de recherche : les colonies fondées, moins celles que
## couvrent les Préfectures (free_colonies chacune).
static func cost_colonies(state: GameState, empire_id: int) -> int:
	var n := 0
	var free := 0
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		if c.owner == empire_id and c.is_colony() and c.is_established():
			n += 1
			for b in c.buildings:
				free += int(_free_colony_buildings().get(b, 0))
	return maxi(0, n - free)


static var _free_cache := {}
static var _free_cached := false


## Bâtiments qui couvrent des colonies (Préfecture) : id -> nombre, lu une fois dans les données.
static func _free_colony_buildings() -> Dictionary:
	if not _free_cached:
		for bid in GameData.buildings():
			var n := int(GameData.building(bid).get("free_colonies", 0))
			if n > 0:
				_free_cache[bid] = n
		_free_cached = true
	return _free_cache


static func colony_count(state: GameState, empire_id: int) -> int:
	var n := 0
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		if c.owner == empire_id and c.is_colony() and c.is_established():
			n += 1
	return n


## Savoir dépensable ce mois-ci : jusqu'à spend_rate_pct du revenu, dans la limite du stock. Une
## réserve accumulée (épaves, biomasse, file restée vide) s'écoule aussi, un douzième par mois au moins.
@warning_ignore("integer_division")
static func monthly_budget(stock: int, income: int) -> int:
	var cap := maxi(maxi(income, 5), stock / 12) * int(data().get("spend_rate_pct", 200)) / 100
	return clampi(stock, 0, cap)


## Mois restants estimés avant la fin de la technologie en tête de file (-1 si le Savoir ne vient pas).
static func months_left(state: GameState, empire_id: int, tid: String, income: int) -> int:
	var e := state.get_empire(empire_id)
	if e == null:
		return -1
	var left := cost(state, empire_id, tid) - (e.research_progress if not e.research_queue.is_empty() and e.research_queue[0] == tid else 0)
	if left <= 0:
		return 0
	if income <= 0:
		return -1
	@warning_ignore("integer_division")
	return (left + income - 1) / income


# --- Ordres -------------------------------------------------------------------------------------

## "" si l'empire peut mettre cette technologie en file, sinon la raison du refus.
## Les prérequis et les seuils d'ère comptent ce qui est déjà en file (on peut planifier une chaîne).
static func check_queue(state: GameState, empire_id: int, tid: String, front := false) -> String:
	var e := state.get_empire(empire_id)
	if e == null:
		return "empire inconnu : %d" % empire_id
	if not exists(tid):
		return "technologie inconnue : %s" % tid
	var f := e.faction()
	if not is_visible(f, tid, state, empire_id):
		return "cette technologie n'est pas pour votre peuple"
	if e.techs.has(tid):
		return "déjà découverte"
	if Insolites.no_research(state, empire_id):
		return "votre peuple n'invente rien : il prend (épaves, prises, ruines)"
	if is_find(tid):
		return "trouvaille : elle ne se recherche pas, elle se trouve (curiosités, ruines, Strates, quêtes, prises)"
	if e.research_queue.has(tid):
		if not front:
			return "déjà dans la file"
		if e.research_queue[0] == tid:
			return "déjà la recherche en cours"
		return ""  # passer devant : déjà validée quand elle est entrée dans la file
	if e.research_queue.size() >= MAX_QUEUE:
		return "la file est pleine (%d technologies)" % MAX_QUEUE
	var planned := e.techs.duplicate()
	for q in e.research_queue:
		planned[q] = true
	var t := tech(tid)
	var other := spec_taken(planned, tid)
	if other != "":
		return "spécialisation fermée : vous avez choisi « %s » (définitif ; celle-ci ne s'obtient plus que par échange, vol, épaves ou trouvaille)" % \
				String(tech(other).get("label", other))
	var vis: Dictionary = _info(f, state, empire_id)["set"]
	var missing := PackedStringArray()
	for p in t.get("pre", []):
		if not _satisfies(f, planned, String(p), vis):
			var shown := replaced_by(f, String(p))
			missing.append(String(tech(shown if shown != "" else String(p)).get("label", p)))
	if not missing.is_empty():
		return "il faut d'abord : %s" % ", ".join(missing)
	var gate := gate_reason(state, empire_id, tid)
	if gate != "":
		return gate
	var era := int(t.get("era", 1))
	if not era_open(planned, String(t["domain"]), era, f, state, empire_id):
		return "ère %d fermée en %s : il faut %d technologies de l'ère %d (%d)" % [
				era, String(domain(String(t["domain"])).get("label", t["domain"])), era_need(String(t["domain"]), era, f, state, empire_id), era - 1,
				count_in(planned, String(t["domain"]), era - 1)]
	if not ultimate_ok(planned, tid):
		return "technologie ultime : il faut %d autres technologies de l'ère %d en %s (%d)" % [
				int(t["ultimate"]), era, String(domain(String(t["domain"])).get("label", t["domain"])),
				count_in(planned, String(t["domain"]), era)]
	return ""


## Technologie ultime (champ ultimate = n) : il faut n autres technologies de sa propre ère dans son
## domaine, quelles qu'elles soient (comme les technologies de l'Endless d'Endless Space 2).
static func ultimate_ok(have: Dictionary, tid: String) -> bool:
	var t := tech(tid)
	if not t.has("ultimate"):
		return true
	var n := count_in(have, String(t["domain"]), int(t.get("era", 1)))
	if have.has(tid):
		n -= 1
	return n >= int(t["ultimate"])


## Technologie ultime ?
static func is_ultimate(tid: String) -> bool:
	return tech(tid).has("ultimate")


## Une technologie peut-elle être recherchée tout de suite (prérequis et ère, sans compter la file) ?
## Les trouvailles ne le sont jamais (elles se trouvent) ; le vol et l'échange passent par ici.
static func is_available(state: GameState, empire_id: int, tid: String) -> bool:
	var e := state.get_empire(empire_id)
	if e == null or e.techs.has(tid) or is_find(tid):
		return false
	var f := e.faction()
	var vis: Dictionary = _info(f, state, empire_id)["set"]
	if not vis.has(tid):
		return false
	var t := tech(tid)
	for p in t.get("pre", []):
		if not _satisfies(f, e.techs, String(p), vis):
			return false
	return era_open(e.techs, String(t["domain"]), int(t.get("era", 1)), f, state, empire_id) and ultimate_ok(e.techs, tid) \
			and gate_reason(state, empire_id, tid) == ""


static func check_remove(state: GameState, empire_id: int, tid: String) -> String:
	var e := state.get_empire(empire_id)
	if e == null:
		return "empire inconnu : %d" % empire_id
	if not e.research_queue.has(tid):
		return "pas dans la file"
	return ""


## Ajoute une technologie à la file (en tête si front : elle devient la recherche en cours).
## Le Savoir déjà investi dans une recherche interrompue est mis de côté (research_shelf) et
## retrouvé quand on y revient.
static func apply_queue(state: GameState, empire_id: int, tid: String, front: bool) -> void:
	var e := state.get_empire(empire_id)
	if front and e.research_queue.has(tid):
		e.research_queue.erase(tid)
	if front and not e.research_queue.is_empty():
		# Changer de recherche en cours : le travail entamé est mis de côté, pas perdu.
		if e.research_progress > 0:
			e.research_shelf[e.research_queue[0]] = e.research_progress
		e.research_queue.insert(0, tid)
		_fix_order(state, e)  # ses prérequis encore en file passent devant elle
		e.research_progress = int(e.research_shelf.get(e.research_queue[0], 0))
		e.research_shelf.erase(e.research_queue[0])
	else:
		e.research_queue.append(tid)
		if e.research_queue.size() == 1:
			e.research_progress = int(e.research_shelf.get(tid, 0))
			e.research_shelf.erase(tid)


## Retire une technologie de la file, et celles qui en dépendaient.
static func apply_remove(state: GameState, empire_id: int, tid: String) -> void:
	var e := state.get_empire(empire_id)
	var was_first := not e.research_queue.is_empty() and e.research_queue[0] == tid
	if was_first and e.research_progress > 0:
		e.research_shelf[tid] = e.research_progress
	e.research_queue.erase(tid)
	# Ce qui dépendait d'elle (prérequis ou seuil d'ère) quitte la file aussi.
	var changed := true
	while changed:
		changed = false
		var planned := e.techs.duplicate()
		var keep: Array[String] = []
		for q in e.research_queue:
			if _plannable(state, e, planned, q):
				planned[q] = true
				keep.append(q)
			else:
				changed = true
		e.research_queue = keep
	if was_first:
		e.research_progress = 0
		if not e.research_queue.is_empty():
			e.research_progress = int(e.research_shelf.get(e.research_queue[0], 0))
			e.research_shelf.erase(e.research_queue[0])


static func _plannable(state: GameState, e: Empire, planned: Dictionary, tid: String) -> bool:
	var t := tech(tid)
	var f := e.faction()
	var vis: Dictionary = _info(f, state, e.id)["set"]
	for p in t.get("pre", []):
		if not _satisfies(f, planned, String(p), vis):
			return false
	return era_open(planned, String(t["domain"]), int(t.get("era", 1)), f, state, e.id) and ultimate_ok(planned, tid)


## Après une insertion en tête, remet en ordre la file pour que chaque technologie suive ses prérequis.
static func _fix_order(state: GameState, e: Empire) -> void:
	var planned := e.techs.duplicate()
	var rest: Array[String] = e.research_queue.duplicate()
	var out: Array[String] = []
	var guard := 0
	while not rest.is_empty() and guard < 64:
		guard += 1
		var placed := false
		for q in rest:
			if _plannable(state, e, planned, q):
				out.append(q)
				planned[q] = true
				rest.erase(q)
				placed = true
				break
		if not placed:
			break
	e.research_queue = out


# --- Avancée mensuelle --------------------------------------------------------------------------

## Fait avancer la recherche d'un empire au bilan mensuel. `income` = Savoir net du mois.
## Renvoie les technologies achevées.
static func advance(state: GameState, empire_id: int, income: int) -> Array[String]:
	var done: Array[String] = []
	var e := state.get_empire(empire_id)
	if e == null or e.research_queue.is_empty() or Insolites.no_research(state, empire_id):
		return done
	var budget := monthly_budget(int(e.resources.get("knowledge", 0)), income)
	while budget > 0 and not e.research_queue.is_empty():
		var tid := e.research_queue[0]
		var need := cost(state, empire_id, tid) - e.research_progress
		var spend := mini(budget, maxi(0, need))
		e.research_progress += spend
		e.resources["knowledge"] = int(e.resources.get("knowledge", 0)) - spend
		budget -= spend
		if e.research_progress < cost(state, empire_id, tid):
			break
		complete(state, empire_id, tid)
		done.append(tid)
	return done


## Découvre une technologie (fin de recherche, épave, ou test) : effets ponctuels compris.
static func complete(state: GameState, empire_id: int, tid: String) -> void:
	var e := state.get_empire(empire_id)
	if e == null or e.techs.has(tid):
		return
	e.techs[tid] = true
	Heroes.act(state, empire_id, "tech")
	Politics.on_tech(state, empire_id, String(tech(tid).get("current", "")))  # la recherche dessine la vie politique
	Crisis.on_tech(state, empire_id, tid)  # technologie interdite : la fin de partie approche
	if not e.research_queue.is_empty() and e.research_queue[0] == tid:
		e.research_queue.remove_at(0)
		e.research_progress = 0
		if not e.research_queue.is_empty():
			e.research_progress = int(e.research_shelf.get(e.research_queue[0], 0))
			e.research_shelf.erase(e.research_queue[0])
	else:
		e.research_queue.erase(tid)
	e.research_shelf.erase(tid)
	var f := e.faction()
	if FactionTraits.has_fervor(f):
		var t := tech(tid)
		var gain := int(t.get("fervor", 0))
		gain += int(f.get("research", {}).get("fervor_per_domain", {}).get(String(t.get("domain", "")), 0))
		if is_heretic(f, tid):
			gain += int(t["heretic"].get("fervor", 0))
		e.fervor = clampi(e.fervor + gain, 0, int(f["fervor"]["max"]))
	e.tech_fx_n = -1


## Accorde des technologies sans les rechercher (scénarios, tests, IA de démonstration).
static func grant(state: GameState, empire_id: int, tids: Array) -> void:
	for t in tids:
		complete(state, empire_id, String(t))
		# Trouvaille (prop. 10) : elle dispense de rechercher sa cousine.
		var cousin := String(tech(String(t)).get("find_of", ""))
		if cousin != "" and not knows(state, empire_id, cousin):
			complete(state, empire_id, cousin)


## Trouvaille offerte par une source (curio, ancients, strates, capture) : la première du catalogue,
## dans l'ordre des ères, que le peuple voit et n'a pas encore (ni sa cousine), choisie sans hasard
## parmi celles de la plus basse ère disponible. Renvoie son id ("" si aucune).
static func grant_find(state: GameState, empire_id: int, source: String) -> String:
	var e := state.get_empire(empire_id)
	if e == null or e.is_npc():
		return ""
	var f := e.faction()
	var best: Array[String] = []
	var best_era := 99
	var techs: Dictionary = data().get("technologies", {})
	for tid in techs:
		var t: Dictionary = techs[tid]
		if not t.get("find", false) or not (t.get("find_sources", []) as Array).has(source):
			continue
		if e.techs.has(tid) or e.techs.has(String(t.get("find_of", ""))) or not is_visible(f, String(tid), state, empire_id):
			continue
		var era := int(t.get("era", 1))
		if era > current_era(state, empire_id) + 1:
			continue  # pas une trouvaille de deux ères d'avance
		if era < best_era:
			best_era = era
			best.clear()
		if era == best_era:
			best.append(String(tid))
	if best.is_empty():
		return ""
	var pick := best[posmod(hash([state.seed_value, empire_id, state.tick, source]), best.size())]
	grant(state, empire_id, [pick])
	return pick


## Accorde à un empire toutes les technologies de son arbre (tests du contenu verrouillé).
static func grant_all(state: GameState, empire_id: int) -> void:
	var e := state.get_empire(empire_id)
	if e:
		grant(state, empire_id, visible_ids(e.faction()))


# --- Marques d'armes et de défenses -------------------------------------------------------------

## Familles à marques (6 armes, 3 défenses), dans l'ordre d'affichage.
static func mark_families() -> Array:
	return data().get("marks", {}).get("families", [])


static func mark_label(fam: String) -> String:
	return String(data().get("marks", {}).get("labels", {}).get(fam, fam))


## Bonus d'une marque, en points de % (+20 par marque au-delà de la première).
static func mark_bonus(mark: int) -> int:
	return int(data().get("marks", {}).get("step_pct", 20)) * maxi(0, mark - 1)


## Marques actuelles de l'empire {famille: 1..5} : ce que reçoit un vaisseau neuf ou remis à niveau.
static func marks(state: GameState, empire_id: int) -> Dictionary:
	var e := state.get_empire(empire_id)
	if e == null:
		return {}
	effects(state, empire_id)
	return e.tech_marks


## Indice de l'état actuel des marques dans Empire.marks_log (ajouté s'il a changé) : le vaisseau
## qui sort du chantier le garde jusqu'à sa prochaine remise à niveau.
static func mark_gen(state: GameState, empire_id: int) -> int:
	var e := state.get_empire(empire_id)
	if e == null:
		return -1
	var now := marks(state, empire_id)
	if e.marks_log.is_empty() or e.marks_log[e.marks_log.size() - 1] != now:
		e.marks_log.append(now.duplicate())
	return e.marks_log.size() - 1


## Marques d'un vaisseau d'après son indice (-1 : celles de l'empire, toujours à jour).
static func marks_of_gen(state: GameState, empire_id: int, g: int) -> Dictionary:
	var e := state.get_empire(empire_id)
	if e == null:
		return {}
	if g < 0 or g >= e.marks_log.size():
		return marks(state, empire_id)
	return e.marks_log[g]


## Le vaisseau a-t-il des marques en retard sur celles de l'empire ?
static func gen_outdated(state: GameState, empire_id: int, g: int) -> bool:
	return g >= 0 and marks_of_gen(state, empire_id, g) != marks(state, empire_id)


## Technologie qui rapproche de la marque suivante d'une famille (épaves) : les marques viennent des
## paliers d'Armement (prop. 4), donc la technologie d'Armement la moins avancée que l'empire ne connaît
## pas encore (ni Maîtrise ni trouvaille) ; "" s'il n'y en a plus ou si la famille est déjà au maximum.
static func next_mark_tech(state: GameState, empire_id: int, fam: String) -> String:
	var e := state.get_empire(empire_id)
	if e == null:
		return ""
	if int(marks(state, empire_id).get(fam, 1)) >= int(data().get("marks", {}).get("max", 5)):
		return ""
	# L'ère d'Armement la plus avancée déjà ouverte : ses technologies ouvrent le palier suivant.
	var f := e.faction()
	var top := 1
	for era in range(2, eras() + 1):
		if era_open(e.techs, "armement", era, f, state, empire_id):
			top = era
	var best := ""
	var best_era := 99
	for tid in visible_for(state, empire_id):
		var t := tech(tid)
		if e.techs.has(tid) or String(t.get("domain", "")) != "armement" or t.has("mastery") or t.has("find") or t.has("requires"):
			continue
		var era := int(t.get("era", 1))
		if era > top:
			continue
		# (l'ère ouverte la plus avancée d'abord, puis les précédentes)
		var rank := top - era
		if rank < best_era:
			best_era = rank
			best = tid
	return best


# --- Épaves et eurêkas ---------------------------------------------------------------------------

## Ajoute du Savoir déjà acquis à une technologie (épave, eurêka) : à la recherche en cours s'il
## s'agit d'elle, sinon mis de côté. Une technologie entièrement payée ainsi est découverte aussitôt
## (c'est la seule façon d'obtenir l'autre branche d'une doctrine). Renvoie true si elle l'est.
static func add_progress(state: GameState, empire_id: int, tid: String, amount: int) -> bool:
	var e := state.get_empire(empire_id)
	if e == null or amount <= 0 or e.techs.has(tid):
		return false
	if not e.research_queue.is_empty() and e.research_queue[0] == tid:
		e.research_progress += amount
		return false  # achevée au prochain bilan, avec le reste de la recherche
	var have := int(e.research_shelf.get(tid, 0)) + amount
	if have >= cost(state, empire_id, tid) and not e.research_queue.has(tid):
		complete(state, empire_id, tid)
		return true
	e.research_shelf[tid] = have
	return false


# --- Technologies à voler (opération « Voler une technologie », dividende du credo Profit) --------
## Inspiration : l'opération « Steal Technology » de l'espionnage de Stellaris (une technologie que la
## cible connaît et pas vous). Voir Espionage.

## La technologie qu'on volerait à la victime : la plus chère de celles qu'elle connaît et que le
## voleur peut chercher (à égalité, l'ordre des identifiants). "" si rien.
static func steal_target(state: GameState, thief: int, victim: int) -> String:
	var e := state.get_empire(thief)
	var oe := state.get_empire(victim)
	if e == null or oe == null or oe.eliminated:
		return ""
	var pick := ""
	for tid in oe.sorted_techs():
		var t := String(tid)
		if not is_available(state, thief, t):
			continue
		if pick == "" or cost(state, thief, t) > cost(state, thief, pick):
			pick = t
	return pick


## Savoir déjà acquis pour une technologie (en cours ou mis de côté).
static func progress_of(state: GameState, empire_id: int, tid: String) -> int:
	var e := state.get_empire(empire_id)
	if e == null:
		return 0
	if not e.research_queue.is_empty() and e.research_queue[0] == tid:
		return e.research_progress
	return int(e.research_shelf.get(tid, 0))


## Pourcentage de bonus des épaves pour un peuple (Reliques saintes ×2, Mémoire génétique ×3).
static func wreck_mult(faction: Dictionary) -> int:
	return int(faction.get("research", {}).get("wreck_pct", 100))


## Épaves (Stellaris) : le vainqueur d'une bataille étudie ce que le vaincu avait de plus avancé.
## Chaque famille où le vaincu a une meilleure marque donne wreck_pct % (10 %) de la technologie de la
## marque suivante ; chaque doctrine du vaincu que le vainqueur n'a pas, autant. Renvoie les
## technologies touchées [[id, Savoir, découverte ?]...].
@warning_ignore("integer_division")
static func study_wrecks(state: GameState, winner: int, loser: int) -> Array:
	var out: Array = []
	var w := state.get_empire(winner)
	var l := state.get_empire(loser)
	if w == null or l == null:
		return out
	var pct := int(data().get("wreck_pct", 10)) * wreck_mult(w.faction()) / 100
	var mine := marks(state, winner)
	var theirs := marks(state, loser)
	var targets: Array[String] = []
	for fam in mark_families():
		if int(theirs.get(fam, 1)) > int(mine.get(fam, 1)):
			var tid := next_mark_tech(state, winner, String(fam))
			if tid != "" and not targets.has(tid):
				targets.append(tid)
	for tid in l.sorted_techs():
		if tech(String(tid)).get("doctrine", false) and not w.techs.has(tid) and is_visible(w.faction(), String(tid)):
			targets.append(String(tid))
	for tid in targets:
		var amount := maxi(1, cost(state, winner, tid) * pct / 100)
		out.append([tid, amount, add_progress(state, winner, tid, amount)])
	if not targets.is_empty():
		FaithWars.on_wreck(state, winner)
	return out


const CLAIM_KINDS := ["colonies", "pop", "building", "deposit", "planet", "claim"]

## Eurêkas de pilier (prop. 16) : objectif en clair de chaque compteur de count_stat utilisé.
const STAT_TEXTS := {
	"operations": "réussir %d opérations d'espionnage",
	"refugees": "accueillir %d vagues de réfugiés",
	"beasts": "abattre %d créatures",
	"digs": "mener %d fouilles",
	"quests": "achever %d quêtes",
	"curios": "étudier %d curiosités",
	"prizes": "faire %d prises",
}


## Ce que tiennent les revendications fondées d'un empire, pour les eurêkas en attente `tids` (tous
## ceux de son arbre si vide) : {"kind:what": total}. Un seul passage sur les revendications.
static func claims_summary(state: GameState, empire_id: int, tids: Array = []) -> Dictionary:
	var e := state.get_empire(empire_id)
	var want: Array = []
	for tid in (tids if not tids.is_empty() else visible_ids(e.faction())):
		var eu: Dictionary = tech(String(tid)).get("eureka", {})
		if CLAIM_KINDS.has(String(eu.get("kind", ""))):
			var pair := [String(eu["kind"]), String(eu.get("what", ""))]
			if not want.has(pair):
				want.append(pair)
	var out := {}
	for pair in want:
		out[pair[0] + ":" + pair[1]] = 0
	if want.is_empty():
		return out
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		if c.owner != empire_id or not c.is_established():
			continue
		var p := state.galaxy.get_planet(pid)
		for pair in want:
			var what: String = pair[1]
			var n := 0
			match String(pair[0]):
				"colonies": n = 1 if c.is_colony() else 0
				"pop": n = c.population if c.is_colony() else 0
				"building": n = 1 if c.buildings.has(what) else 0
				"deposit": n = 1 if p.deposits.has(what) else 0
				"planet": n = 1 if c.is_colony() and p.type == what else 0
				"claim": n = 1 if p.type == what else 0
			if n != 0:
				var k: String = pair[0] + ":" + what
				out[k] = int(out[k]) + n
	return out


## Avancement d'un eurêka : [valeur actuelle, objectif]. Les conditions lisent l'état sans le changer.
## summary : claims_summary déjà calculé (plusieurs eurêkas d'affilée), sinon calculé ici.
static func eureka_status(state: GameState, empire_id: int, tid: String, summary := {}) -> Array:
	var eu: Dictionary = tech(tid).get("eureka", {})
	var e := state.get_empire(empire_id)
	if eu.is_empty() or e == null:
		return [0, 0]
	var n := int(eu.get("n", 1))
	var what := String(eu.get("what", ""))
	var have := 0
	match String(eu.get("kind", "")):
		"kills", "ships_lost", "battles_won", "conquests", "besieged", "wars", "built", "sacrifices":
			have = int(e.stats.get(String(eu["kind"]), 0))
		"stat":
			have = int(e.stats.get(what, 0))  # compteur de Research.count_stat (eurêkas de pilier, prop. 16)
		"contacts":
			have = e.contacts.size()
		"explored":
			have = e.explored.size()
		"techs":
			have = e.techs.size()
		"exalted":
			have = 1 if FactionTraits.is_exalted(state, empire_id) else 0
		"trade", "peace":
			for c in e.contacts:
				var r: Dictionary = state.relations.get(Diplomacy.key(empire_id, c), {})
				if String(eu["kind"]) == "trade" and int(r.get("trade", 0)) != 0:
					have += 1
				elif String(eu["kind"]) == "peace" and String(r.get("pact", "")) != "":
					have += 1
		_:
			var k := String(eu["kind"]) + ":" + what
			if not summary.has(k):
				summary = claims_summary(state, empire_id, [tid])
			have = int(summary.get(k, 0))
	return [have, n]


## Objectif d'un eurêka, en clair ("" s'il n'y en a pas).
static func eureka_text(tid: String) -> String:
	var eu: Dictionary = tech(tid).get("eureka", {})
	if eu.is_empty():
		return ""
	var n := int(eu.get("n", 1))
	var what := String(eu.get("what", ""))
	var plural := "s" if n > 1 else ""
	match String(eu.get("kind", "")):
		"kills": return "détruire %d vaisseau%s ennemi%s" % [n, "x" if n > 1 else "", plural]
		"ships_lost": return "perdre %d vaisseau%s au combat" % [n, "x" if n > 1 else ""]
		"battles_won": return "gagner %d bataille%s" % [n, plural]
		"conquests": return "conquérir %d système%s" % [n, plural]
		"besieged": return "subir un siège"
		"wars": return "entrer en guerre"
		"built": return "construire %d vaisseau%s" % [n, "x" if n > 1 else ""]
		"sacrifices": return "faire %d offrande%s" % [n, plural]
		"stat": return String(STAT_TEXTS.get(what, "%s : %d")) % n if STAT_TEXTS.has(what) else "%s : %d" % [what, n]
		"contacts": return "rencontrer %d empire%s" % [n, plural]
		"explored": return "explorer %d systèmes" % n
		"techs": return "connaître %d technologies" % n
		"exalted": return "atteindre l'Exaltation"
		"trade": return "commercer (signer un palier de commerce)"
		"peace": return "signer une paix"
		"colonies": return "fonder %d colonies" % n
		"pop": return "atteindre %d de population" % n
		"building": return "avoir %d %s" % [n, String(GameData.building(what).get("label", what)).to_lower()]
		"deposit": return "tenir %d gisement%s de %s" % [n, plural, String(GameData.deposit(what).get("label", what)).to_lower()]
		"planet": return "coloniser un monde %s" % String(GameData.planet_type(what).get("label", what)).to_lower()
		"claim": return "revendiquer une planète %s" % String(GameData.planet_type(what).get("label", what)).to_lower()
	return ""


## Eurêkas (Civilization VI) atteints ce mois-ci : chacun paie eureka_pct % (40 %) de la technologie,
## une seule fois. Renvoie les technologies concernées.
@warning_ignore("integer_division")
static func check_eurekas(state: GameState, empire_id: int) -> Array[String]:
	var out: Array[String] = []
	var e := state.get_empire(empire_id)
	if e == null:
		return out
	var pct := int(data().get("eureka_pct", 40))
	var pending: Array = []
	for tid in visible_ids(e.faction()):
		if not e.techs.has(tid) and not e.eurekas.has(tid) and tech(tid).has("eureka"):
			pending.append(tid)
	var summary := claims_summary(state, empire_id, pending) if not pending.is_empty() else {}
	for tid in pending:
		var st := eureka_status(state, empire_id, tid, summary)
		if int(st[0]) < int(st[1]):
			continue
		e.eurekas[tid] = true
		add_progress(state, empire_id, tid, maxi(1, cost(state, empire_id, tid) * pct / 100))
		out.append(tid)
	return out


static func count_stat(state: GameState, empire_id: int, key: String, n := 1) -> void:
	var e := state.get_empire(empire_id)
	if e and not e.is_npc():
		e.stats[key] = int(e.stats.get(key, 0)) + n
		Heroes.act(state, empire_id, key, n)
		CrisisNemesis.on_stat(state, empire_id, key, n)


# --- Effets -------------------------------------------------------------------------------------

## Effets cumulés des technologies connues : les nombres s'additionnent, les tables aussi, clé par clé.
## Pendant l'Exaltation (Chœur Éternel), les effects_exalted s'ajoutent.
## Clés : production_pct {res|"all"} (« all » hors Savoir), growth_pct, colony_start_pop, max_projects,
## building_slots, building_cost_pct, hab_bonus {type|"all"}, hab_set {type}, weapon_pct {famille},
## damage_pct, defense_pct {armor, shield, pd}, troops_pct, home_damage_pct, reinforcement_pct,
## garrison_pct, fleet_speed_pct, ship_days_pct, ship_cost_pct, upkeep_pct, claim_vision, alliances,
## fervor_big_colony, sacrifice_gain, fief_influence, biomass_bonus, marks {famille} (marques en plus),
## doctrines : screen_taken_pct, deep_strike_pct, phase_damage_pct {long|medium|short}, repair_pct,
## siege_pct, first_day_damage_pct.
static func effects(state: GameState, empire_id: int) -> Dictionary:
	var e := state.get_empire(empire_id)
	if e == null:
		return {}
	if e.tech_fx_n != e.techs.size() + 1000 * state.relic_rev:
		var base := {}
		var exalted := {}
		var has_exalted := false
		var ids: Array = e.techs.keys()
		ids.sort()
		for tid in ids:
			var t := tech(String(tid))
			_merge(base, t.get("effects", {}))
			_merge(exalted, t.get("effects", {}))
			if t.has("effects_exalted"):
				has_exalted = true
				_merge(exalted, t["effects_exalted"])
		# Paliers d'ère (prop. 4 de l'étude de l'arbre) : ouvrir une ère dans un domaine les donne.
		for tr: Dictionary in open_tiers(state, empire_id):
			_merge(base, tr.get("effects", {}))
			_merge(exalted, tr.get("effects", {}))
		# Reliques et Triomphe en cours (voir Relics) : mêmes clés que les technologies.
		var rfx := Relics.effects(state, empire_id)
		_merge(base, rfx)
		_merge(exalted, rfx)
		# Faveurs des quêtes et quêtes galactiques en cours (voir Quests) : même empreinte relic_rev.
		var qfx := Quests.effects(state, empire_id)
		_merge(base, qfx)
		_merge(exalted, qfx)
		# Espèces de la faune étudiées (voir Fauna) : même empreinte relic_rev.
		var ffx := Fauna.effects(state, empire_id)
		_merge(base, ffx)
		_merge(exalted, ffx)
		# Luxes dont l'empire profite (voir Goods) : même empreinte relic_rev.
		var gfx := Goods.effects(state, empire_id)
		_merge(base, gfx)
		_merge(exalted, gfx)
		# Lois en vigueur (voir Laws) : même empreinte relic_rev, sans la stabilité (ligne à part).
		if state.politics_on:
			var lfx := Laws.research_effects(state, empire_id)
			_merge(base, lfx)
			_merge(exalted, lfx)
		# Culte natal, doctrines et préceptes de la foi d'État (voir Faiths) : même empreinte relic_rev.
		if state.faith_on:
			var rfx2 := Faiths.effects(state, empire_id)
			_merge(base, rfx2)
			_merge(exalted, rfx2)
		# Résolutions de l'Amphictyonie et sanctions (voir Amphictyony) : même empreinte relic_rev.
		if state.amph_on:
			var afx := Amphictyony.effects(state, empire_id)
			_merge(base, afx)
			_merge(exalted, afx)
		# Préparatifs contre la crise de fin de partie (voir Crisis) : même empreinte relic_rev.
		if not state.crisis.is_empty():
			var cfx := Crisis.effects(state, empire_id)
			_merge(base, cfx)
			_merge(exalted, cfx)
		# Faveurs et postes des puissances anciennes (voir Ancients).
		if not state.ancients.is_empty():
			var nfx := Ancients.effects(state, empire_id)
			_merge(base, nfx)
			_merge(exalted, nfx)
		# Cadeaux de suzerain et traits d'assimilation des peuples mineurs (voir Minors).
		if not state.minors.is_empty():
			var mfx := Minors.effects(state, empire_id)
			_merge(base, mfx)
			_merge(exalted, mfx)
		# Âge d'or (voir DeedsBridges) : même empreinte relic_rev.
		if not state.deeds.is_empty():
			var dfx := DeedsBridges.effects(state, empire_id)
			_merge(base, dfx)
			_merge(exalted, dfx)
		# Merveilles tenues (voir Wonders) : même empreinte relic_rev.
		if not state.wonders.is_empty():
			var wfx := Wonders.effects(state, empire_id)
			_merge(base, wfx)
			_merge(exalted, wfx)
		# Souverain : aptitudes, archétype, pouvoir, héritages, funérailles (voir Rulers).
		if not state.rulers.is_empty():
			var rfx3 := Rulers.effects(state, empire_id)
			_merge(base, rfx3)
			_merge(exalted, rfx3)
		# Cour et Grandes Maisons : sièges, grands offices, faste, style (voir Court).
		if not state.court.is_empty():
			var cfx := Court.effects(state, empire_id)
			_merge(base, cfx)
			_merge(exalted, cfx)
		# Fiscalité : crans d'impôt, solde, impôt de guerre, crise de la dette, faillite (voir Finance).
		if not state.finance.is_empty():
			var ffx2 := Finance.effects(state, empire_id)
			_merge(base, ffx2)
			_merge(exalted, ffx2)
		# Économie privée : secteurs des compagnies prospères, chartes, réquisition (voir Private).
		if not state.private.is_empty():
			var pfx := Private.effects(state, empire_id)
			_merge(base, pfx)
			_merge(exalted, pfx)
		# Pouvoirs psioniques : bienfaits et malédictions du Songe, paliers de pacte (voir PsionicsDream).
		if not state.psionics.is_empty():
			var sfx := PsionicsDream.effects(state, empire_id)
			_merge(base, sfx)
			_merge(exalted, sfx)
		# Transcendance : Renoncement, effacement du Passage, credo (voir Transcendence).
		if not state.transcendence.is_empty():
			var tfx := Transcendence.effects(state, empire_id)
			_merge(base, tfx)
			_merge(exalted, tfx)
		# Mégastructures : effets des étapes (voir Megastructures).
		if not state.megas.is_empty():
			var mfx := Megastructures.effects(state, empire_id)
			_merge(base, mfx)
			_merge(exalted, mfx)
		# Forge des mondes : Rayonnement des mondes créés (voir WorldForge).
		if not state.forge.is_empty():
			var wfx := WorldForge.effects(state, empire_id)
			_merge(base, wfx)
			_merge(exalted, wfx)
		# Contact : dons des Plans, lectures, brouillage (voir Contact).
		if not state.contact.is_empty():
			var ctfx := Contact.effects(state, empire_id)
			_merge(base, ctfx)
			_merge(exalted, ctfx)
		# Archéologie : antiquités, actions de fragments, Disparus (voir Archaeology ; jamais Research ici).
		if not state.archaeo.is_empty():
			var arfx := Archaeology.effects(state, empire_id)
			_merge(base, arfx)
			_merge(exalted, arfx)
		# Échelle de Kardashev : culture du type, prérogatives, Âge sombre (voir Kardashev).
		if not state.kardashev.is_empty():
			var kdfx := Kardashev.effects(state, empire_id)
			_merge(base, kdfx)
			_merge(exalted, kdfx)
		e.tech_fx = base
		e.tech_fx_exalted = exalted
		e.tech_fx_has_exalted = has_exalted
		var md: Dictionary = data().get("marks", {})
		var bonus: Dictionary = base.get("marks", {})
		var marks := {}
		for fam in md.get("families", []):
			marks[String(fam)] = mini(int(md.get("max", 5)), 1 + int(bonus.get(fam, 0)))
		e.tech_marks = marks
		e.tech_fx_n = e.techs.size() + 1000 * state.relic_rev
	# (appelé des centaines de milliers de fois par partie : l'exaltation n'est testée que si elle compte)
	if e.tech_fx_has_exalted and FactionTraits.is_exalted(state, empire_id):
		return e.tech_fx_exalted
	return e.tech_fx


static func _merge(into: Dictionary, fx: Dictionary) -> void:
	for k in fx:
		var v: Variant = fx[k]
		if v is Dictionary:
			# (sous-dictionnaires à plusieurs niveaux : outpost_yields {type: {ressource: n}})
			var sub: Dictionary = into.get(k, {})
			_merge(sub, v)
			into[k] = sub
		else:
			into[k] = int(into.get(k, 0)) + int(v)


static func fx_int(state: GameState, empire_id: int, key: String) -> int:
	return int(effects(state, empire_id).get(key, 0))


static func fx_sub(state: GameState, empire_id: int, key: String, sub: String) -> int:
	return int(effects(state, empire_id).get(key, {}).get(sub, 0))


## Bonus de production d'une ressource, en points de pourcentage (« all » ne compte pas le Savoir).
static func production_bonus(state: GameState, empire_id: int, resource: String) -> int:
	var fx := effects(state, empire_id)
	var t: Dictionary = fx.get("production_pct", {})
	var b := int(t.get(resource, 0))
	if resource != "knowledge":
		b += int(t.get("all", 0))
	return b


## Applique un pourcentage de technologie (ex. ship_cost_pct = -10) à une valeur entière.
@warning_ignore("integer_division")
static func scaled(v: int, pct_bonus: int) -> int:
	return v * maxi(0, 100 + pct_bonus) / 100


static func scaled_amounts(amounts: Dictionary, pct_bonus: int) -> Dictionary:
	if pct_bonus == 0:
		return amounts
	var out := {}
	for r in amounts:
		out[r] = scaled(int(amounts[r]), pct_bonus)
	return out
