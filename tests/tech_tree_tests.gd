extends RefCounted
## Tests du lot 1 de la refonte de l'arbre de recherche (étude https://claude.ai/artifact/2M77BwzqiBMt6zXSCKCq72) :
## catalogue ouvert data/tech/, champs et courants, capacités qui masquent le sans-objet, piliers coupés,
## Maîtrises, trouvailles, technologies dangereuses, spécialisations, bande Peuple, chemin planifié,
## corrections (fuite Grimdark, victoires en double, prérequis des victoires), règle d'or et cohérence
## de l'arbre pour chacun des peuples.

var _check: Callable

## Technologies qui ne débloquent encore rien (bonus chiffré seul) : le lot 2 leur donne un déblocage
## et fait de leur bonus une Maîtrise. La liste ne doit que raccourcir.
const AWAITING_LOT2 := []


func run(check: Callable) -> void:
	_check = check
	print("Arbre de recherche (lot 1) : catalogue, capacités, Maîtrises, cohérence…")
	_test_catalog()
	_test_corrections()
	_test_capabilities()
	_test_pillars()
	_test_kinds()
	_test_band_and_path()
	_test_golden_rule()
	_test_coherence()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _state(faction := "vael", options := {"ai_level": ""}) -> GameState:
	return GameState.create(4242, 150, 1800.0, faction, options)


func _test_catalog() -> void:
	var techs: Dictionary = GameData.technologies()["technologies"]
	var n := 0
	var files := 0
	for f in DirAccess.get_files_at("res://data/tech"):
		if String(f).ends_with(".json"):
			files += 1
			var part: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tech/" + String(f)))
			n += (part.get("technologies", {}) as Dictionary).size()
	_ok(files >= 6 and n == techs.size() and techs.size() >= 238, "catalogue ouvert : %d fichiers, %d technologies fusionnées" % [files, techs.size()])
	var cur_ids := []
	for c: Dictionary in GameData.politics()["currents"]:
		cur_ids.append(String(c["id"]))
	var bad := PackedStringArray()
	for tid: String in techs:
		var t: Dictionary = techs[tid]
		var fields := []
		for fd: Dictionary in Research.domain(String(t["domain"])).get("fields", []):
			fields.append(String(fd["id"]))
		if not cur_ids.has(String(t.get("current", ""))) or not (fields.has(String(t.get("field", ""))) or (t.has("victory") and t.get("field", "") == "destinee")):
			bad.append(tid)
	_ok(bad.is_empty(), "chaque technologie a un champ de son domaine et un courant politique (%s)" % ", ".join(bad))
	_ok(Research.heir_of("canons_masse") == "canons_masse" and Research.heir_of("technologie_disparue") == "", "sauvegardes : héritière ou oubli d'une technologie disparue")


func _test_corrections() -> void:
	var choeur := GameData.faction("choeur")
	for fid in ["kraal", "asphodele", "ferrocornes"]:
		var f := GameData.faction(fid)
		_ok(not Research.is_visible(f, "forges_psalmodiques") and not Research.is_visible(f, "esprits_lies") and Research.is_visible(f, "automatisation"),
				"%s : plus de forges du dieu-machine, l'Automatisation revient" % fid)
	_ok(Research.is_visible(choeur, "forges_psalmodiques") and Research.is_visible(choeur, "serviteurs"), "le Chœur garde ses technologies de la foi")
	var count := {}
	for f: Dictionary in GameData.factions():
		count[String(f["id"])] = Victory.people_ids_for(f).size()
	var twice := PackedStringArray()
	for fid in count:
		if int(count[fid]) > 1:
			twice.append("%s %d" % [fid, int(count[fid])])
	_ok(not Research.is_visible(GameData.faction("ysmer"), "silence_parfait") and not Research.is_visible(GameData.faction("vergemonde"), "biosphere_unique")
			and not Research.is_visible(GameData.faction("zambalu"), "legende"), "victoires en double corrigées (Silence, Biosphère, Légende)")
	_ok(twice.is_empty() or twice == PackedStringArray(["kraal 1"]), "au plus une victoire de peuple chacun (%s)" % ", ".join(twice))
	var gen := 0
	for tid: String in GameData.technologies()["technologies"]:
		if Research.tech(tid).has("victory") and (Research.tech(tid).get("pre", []) as Array).has("genetique"):
			gen += 1
	_ok(gen <= 1, "les victoires ont des prérequis à elles (%d demandent encore Génétique, la Moisson)" % gen)


func _test_capabilities() -> void:
	var myrr := GameData.faction("myrr")
	var kraal := GameData.faction("kraal")
	var teyl := GameData.faction("teyl")
	_ok(Research.lacks(myrr, "vaisseaux") and not Research.is_visible(myrr, "torpilles") and not Research.is_visible(myrr, "coques_lourdes") and Research.is_visible(myrr, "canons_masse"),
			"la Sporemère (sans vaisseau) ne voit ni torpilles ni coques, mais garde les canons de ses bastions")
	_ok(Research.lacks(kraal, "chantier") and not Research.is_visible(kraal, "coques_lourdes") and Research.is_visible(kraal, "canons_masse"),
			"les Kraal (vaisseaux vivants) : pas de chantier, mais des armes")
	_ok(Research.lacks(teyl, "nourriture") and not Research.is_visible(teyl, "hydroponie"), "Teyl (sans nourriture) ne voit pas l'Hydroponie")
	_ok(not Research.lacks(GameData.faction("vael"), "vaisseaux") and Research.lacking_labels(GameData.faction("vael")).is_empty(), "un peuple classique ne perd rien")
	# Un peuple de l'éditeur : la capacité se lit dans ses couches, pas dans son nom.
	var custom := {"id": "test_spores", "species": {"archetype": "humanoide", "gouvernement": "republique", "credo": "raison", "traits": []}, "diet": "energy"}
	_ok(Research.lacks(custom, "nourriture") and not Research.is_visible(custom, "hydroponie"), "un peuple personnalisé au régime énergétique perd la nourriture")
	# Le Myrr avance quand même dans l'Armement : le seuil d'ère suit ce que son arbre propose.
	_ok(Research.era_need("armement", 2, myrr) <= Research.era_threshold(2), "seuil d'ère adapté à un arbre masqué")
	# L'Exode : pas de colonie avant l'Arrivée, l'arbre se met à jour après (prop. 72).
	var st := _state("exode")
	var e := st.get_empire(0)
	_ok(not Research.is_visible(e.faction(), "terraformation", st, 0), "l'Exode en route ne voit pas la Terraformation")
	Insolites.emp(st, 0)["arrived"] = st.tick + 1
	_ok(Research.is_visible(e.faction(), "terraformation", st, 0), "posé sur la Terre promise, l'Exode la voit")
	var sil := _state("silencieux")
	var free := ""
	for tid in Research.visible_for(sil, 0):
		if Research.tech(tid).get("pre", []).is_empty() and int(Research.tech(tid)["era"]) == 1:
			free = tid
			break
	_ok(Insolites.no_research(sil, 0) == false or Research.check_queue(sil, 0, free) != "", "les Silencieux ne mettent rien en file (catalogue des acquisitions)")


func _test_pillars() -> void:
	var st := _state("vael")
	_ok(not Research.is_visible(st.get_empire(0).faction(), "voiles_1", st, 0) and Research.is_visible(st.get_empire(0).faction(), "voiles_1"),
			"Furtivité coupée : ses technologies disparaissent de l'arbre de la partie")
	var st2 := _state("vael", {"ai_level": "", "stealth": "complete", "portals": "complets"})
	_ok(Stealth.enabled(st2) == Research.is_visible(st2.get_empire(0).faction(), "voiles_1", st2, 0), "Furtivité en jeu : elles reviennent")
	# Un prérequis d'un pilier coupé ne bloque pas : le Paradoxe stable demande la Précognition (psionique).
	var sab := _state("sablier")
	var why := Research.check_queue(sab, 0, "paradoxe_stable")
	_ok(not Research.is_visible(sab.get_empire(0).faction(), "precognition", sab, 0) and not why.contains("Précognition"),
			"un prérequis d'un pilier coupé ne bloque pas (%s)" % why)


func _test_kinds() -> void:
	var st := _state("vael")
	var e := st.get_empire(0)
	# Maîtrise : facultative, jamais prérequise, hors seuil d'ère.
	var m := "reseaux_savants"
	_ok(Research.is_mastery(m) and Research.masteries_of("banques_donnees").has(m), "Réseaux savants est la Maîtrise des Banques de données")
	var as_pre := PackedStringArray()
	for tid: String in GameData.technologies()["technologies"]:
		for p in Research.tech(tid).get("pre", []):
			if Research.is_mastery(String(p)):
				as_pre.append(tid)
	_ok(as_pre.is_empty(), "aucune Maîtrise n'est prérequise (%s)" % ", ".join(as_pre))
	_ok(Research.count_in({m: true}, "economie", 3) == 0, "une Maîtrise ne compte pas pour ouvrir l'ère suivante")
	# Spécialisation : choisir l'une ferme l'autre.
	Research.grant(st, 0, ["rideau_acier"])
	_ok(Research.check_queue(st, 0, "frappe_profondeur").begins_with("spécialisation fermée"), "spécialisation : l'autre branche est fermée")
	_ok(Research.spec_members("doctrine_ecran").size() == 2, "groupe de spécialisation de deux doctrines")
	# Dangereuse.
	_ok(Research.is_dangerous("etoiles_captives") and not Research.is_dangerous("canons_masse") and Research.danger_text("etoiles_captives") != "",
			"technologie dangereuse marquée, avec son avertissement")
	# Trouvaille : une technologie ajoutée au catalogue ne se recherche pas, elle se donne.
	var techs: Dictionary = GameData.technologies()["technologies"]
	techs["test_trouvaille"] = {"label": "Trouvaille d'essai", "domain": "economie", "era": 1, "field": "production", "current": "forge", "text": "Essai.", "find": true}
	Research._info_cache.clear()
	_ok(Research.check_queue(st, 0, "test_trouvaille").begins_with("trouvaille") and not Research.is_available(st, 0, "test_trouvaille"), "une trouvaille ne se met pas en file")
	Research.grant(st, 0, ["test_trouvaille"])
	_ok(e.techs.has("test_trouvaille"), "une trouvaille se donne (curiosité, ruine…)")
	techs.erase("test_trouvaille")
	e.techs.erase("test_trouvaille")
	Research._info_cache.clear()
	# Courant politique : découvrir une technologie pousse son courant.
	_ok(int(GameData.politics()["acts"]["tech_current"]["all"]) > 0, "la technologie découverte pousse son courant")


func _test_band_and_path() -> void:
	var choeur := GameData.faction("choeur")
	_ok(Research.in_band(choeur, "dernier_couplet"), "la Destinée du Chœur est dans la bande Peuple")
	_ok(not Research.in_band(choeur, "scriptorium"), "le Scriptorium (remplace les Académies) reste à sa place")
	_ok(not Research.in_band(choeur, "forges_psalmodiques"), "les Forges psalmodiques (après l'Extraction) restent dans l'Économie")
	var st := _state("vael")
	var e := st.get_empire(0)
	var steps := Research.plan_path(st, 0, "terraformation")
	_ok(not steps.is_empty() and steps[steps.size() - 1] == "terraformation", "chemin planifié jusqu'à la Terraformation (%d étapes)" % steps.size())
	var ok := true
	for q in steps:
		if Research.check_queue(st, 0, q) != "":
			ok = false
			break
		Research.apply_queue(st, 0, q, false)
		if e.research_queue.size() >= Research.MAX_QUEUE:
			e.research_queue.clear()
			for p in steps.slice(0, steps.find(q) + 1):
				e.techs[p] = true
	_ok(ok, "chaque étape du chemin est valable dans l'ordre")
	var unl := Research.unlock_kinds(e.faction(), "academies")
	_ok(unl.has("batiment"), "icônes de déblocage : les Académies ouvrent un bâtiment")


## Règle d'or (prop. 1) : toute technologie principale débloque quelque chose (bâtiment, vaisseau,
## module, règle décrite par son effet), hors celles qui attendent le lot 2.
func _test_golden_rule() -> void:
	var techs: Dictionary = GameData.technologies()["technologies"]
	var fails := PackedStringArray()
	var stale := PackedStringArray()
	for tid: String in techs:
		var t: Dictionary = techs[tid]
		if t.has("mastery") or t.has("victory") or t.has("requires"):
			continue
		var unlock := false
		for f: Dictionary in GameData.factions():
			if Research.is_visible(f, tid):
				for u: Dictionary in Research.unlock_entries(f, tid):
					if String(u["kind"]) != "maitrise":
						unlock = true
				break
		var fx: Dictionary = t.get("effects", {})
		if fx.is_empty() or t.has("pillar"):
			unlock = true  # règle tenue par le code (pilier, projet, action)
		for k in fx:
			var ks := String(k)
			# Les règles nouvelles (hab_set, migration, detect_veil, hero_backup…) comptent comme déblocage (lot 2).
			if not (ks.ends_with("_pct") or ks in ["marks", "hab_bonus", "hab_min", "max_projects", "stability_threshold",
					"curio_power", "troops_pct", "building_slots", "building_slots_all", "outpost_slots",
					"trade_routes", "opinion_all", "council_seats", "alliances", "hero_cap", "colony_start_pop", "landing_days",
					"admin_cap", "stability", "culture_museum", "stability_threshold_off", "tribun", "detect"]):
				unlock = true
		if not unlock and not AWAITING_LOT2.has(tid):
			fails.append(tid)
		if unlock and AWAITING_LOT2.has(tid):
			stale.append(tid)
	_ok(fails.is_empty(), "règle d'or : chaque technologie principale débloque quelque chose (%s)" % ", ".join(fails))
	_ok(true, "liste d'attente du lot 2 : %d technologies (débloquent déjà : %s)" % [AWAITING_LOT2.size(), ", ".join(stale)])


## Cohérence (prop. 110) pour chaque peuple : rien de visible sans objet, tout l'arbre atteignable de
## proche en proche (ères et Destinée comprises), aucune Maîtrise visible sans sa parente.
func _test_coherence() -> void:
	for f: Dictionary in GameData.factions():
		var vis := Research.visible_ids(f)
		var set := {}
		for tid in vis:
			set[tid] = true
		var useless := PackedStringArray()
		for tid in vis:
			for cap in Research.tech(tid).get("needs", []):
				if Research.lacks(f, String(cap)):
					useless.append(tid)
			var m := String(Research.tech(tid).get("mastery", ""))
			if m != "" and not set.has(m):
				useless.append(tid)
		# Atteignable : on ajoute de proche en proche tout ce qui est disponible.
		var have := {}
		var changed := true
		var guard := 0
		while changed and guard < 400:
			changed = false
			guard += 1
			for tid in vis:
				if have.has(tid) or Research.is_find(tid) or Research.spec_taken(have, tid) != "":
					continue
				var t := Research.tech(tid)
				var ok := true
				for p in t.get("pre", []):
					if not Research._satisfies(f, have, String(p), set):
						ok = false
				if ok and Research.era_open(have, String(t["domain"]), int(t.get("era", 1)), f) and Research.ultimate_ok(have, tid):
					have[tid] = true
					changed = true
		var missing := PackedStringArray()
		for tid in vis:
			if not have.has(tid) and not Research.is_find(tid) and Research.spec_taken(have, tid) == "":
				missing.append(tid)
		_ok(useless.is_empty() and missing.is_empty(), "%s : arbre de %d technologies cohérent (sans objet : %s ; injoignables : %s)" % [
				String(f["short"]), vis.size(), ", ".join(useless), ", ".join(missing)])
