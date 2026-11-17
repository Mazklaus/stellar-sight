class_name AnnounceTests
extends RefCounted
## Fenêtre d'événement généralisée : annonces typées (registre, premières, gravité selon la distance,
## types toujours visibles, réglages du poste), sauvegarde 90, seuils d'alerte de victoire.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	AnnounceSettings.persist = false
	AnnounceSettings.reset()
	print("  - catalogue")
	_test_catalogue()
	print("  - record")
	_test_record()
	print("  - gravity")
	_test_gravity()
	print("  - settings")
	_test_settings()
	print("  - save")
	_test_save()
	print("  - war")
	_test_war()
	AnnounceSettings.reset()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func new_game() -> GameState:
	return GameState.create(5151, 120, 1600.0, "vael", {"ai_level": ""})


func _test_catalogue() -> void:
	var fams := Announce.family_ids()
	_ok(fams.size() == 10, "dix familles d'annonces (%d)" % fams.size())
	var fanfares := 0
	for k in Announce.kind_ids():
		var kd := Announce.kind_def(k)
		_ok(fams.has(String(kd.get("family", ""))), "%s : famille connue" % k)
		_ok((kd.get("g", []) as Array).size() == 3, "%s : trois gravités (soi, proche, lointain)" % k)
		_ok(Announce.data()["needs"].has(String(kd.get("need", ""))), "%s : besoin connu" % k)
		if int((kd["g"] as Array)[0]) >= Announce.FANFARE:
			fanfares += 1
	_ok(Announce.kind_ids().size() >= 40, "au moins 40 types (%d)" % Announce.kind_ids().size())
	_ok(fanfares >= 15, "au moins 15 Fanfares (%d)" % fanfares)
	_ok(AnnounceSettings.PRESETS.size() == 3 and Announce.data()["presets"].size() == 3, "trois préréglages")


func _test_record() -> void:
	var st := new_game()
	var before := st.announces.size()
	Announce.next(st, "revolt", {"target": 0, "system": 0})
	var entry := st.add_chronicle("Révolte de test.")
	_ok(st.announces.size() == before + 1, "add_chronicle enregistre l'annonce posée par next()")
	_ok(String(entry.get("kind", "")) == "revolt" and int(entry.get("aid", 0)) == Announce.last_id(st), "la ligne de chronique porte son type et son annonce")
	_ok(st.announce_next.is_empty(), "l'étiquette est consommée")
	st.add_chronicle("Ligne sans type.")
	_ok(st.announces.size() == before + 1, "une ligne sans étiquette n'est pas une annonce")
	var rec := Announce.find(st, int(entry["aid"]))
	_ok(not rec.is_empty() and String(rec["x"]) == "Révolte de test.", "recherche par identifiant")
	# Première de la galaxie : publique et au moins Fenêtre, une seule fois.
	Announce.next(st, "wonder_done", {"actor": 1})
	st.add_chronicle("Première merveille.", [1])
	var first := st.announces.back() as Dictionary
	_ok(int(first.get("f", 0)) == 1 and not first.has("w"), "première de la galaxie : publique (%s)" % str(first))
	_ok(Announce.gravity(st, first, 0) >= Announce.WINDOW, "une première est au moins une Fenêtre pour tous")
	Announce.next(st, "wonder_done", {"actor": 2})
	st.add_chronicle("Deuxième merveille.", [2])
	var second := st.announces.back() as Dictionary
	_ok(int(second.get("f", 0)) == 0 and second.has("w"), "la deuxième n'est plus une première et garde ses lecteurs")
	_ok(not Announce.can_see(second, 0) and Announce.can_see(second, 2) and Announce.can_see(second, -1), "même règle de lecture que la chronique")
	_ok(Announce.readable(st, 0).size() == st.announces.size() - 1, "lisibles par l'empire 0 : toutes sauf la nouvelle privée")
	# Plafond du registre.
	var cap := int(Announce.rhythm("registry_max", 1200))
	for i in cap + 5:
		Announce.next(st, "pirate_raid", {"target": 0})
		st.add_chronicle("Raid %d." % i)
	_ok(st.announces.size() == cap, "le registre est plafonné (%d)" % st.announces.size())


func _test_gravity() -> void:
	var st := new_game()
	for e in st.empires:
		e.contacts.clear()
	var rec := {"id": 1, "t": 0, "k": "war_declared", "x": "", "r": {"actor": 1, "target": 0}}
	_ok(Announce.distance(st, rec, 0) == Announce.SELF and Announce.gravity(st, rec, 0) == Announce.FANFARE, "guerre déclarée au joueur : Fanfare")
	_ok(Announce.distance(st, rec, 2) == Announce.FAR and Announce.gravity(st, rec, 2) == Announce.MURMUR, "guerre lointaine : chronique seule")
	st.get_empire(2).contacts.append(1)
	_ok(Announce.distance(st, rec, 2) == Announce.NEAR and Announce.gravity(st, rec, 2) == Announce.WINDOW, "guerre d'un voisin connu : Fenêtre")
	_ok(Announce.need(rec, 0) == "threat", "ton de la cible : menace")
	var hist := Announce.hours(st, 0)
	_ok(hist.is_empty(), "pas d'heures sans registre")
	var none := {"id": 2, "t": 0, "k": "crisis_start", "x": "", "r": {}}
	_ok(Announce.distance(st, none, 3) == Announce.NEAR, "une annonce sans empire touche toute la galaxie")


func _test_settings() -> void:
	var st := new_game()
	var rec := {"id": 1, "t": 0, "k": "war_declared", "x": "", "r": {"actor": 1, "target": 0}}
	AnnounceSettings.looks["war_declared"] = Announce.MURMUR
	_ok(AnnounceSettings.final_gravity(st, rec, 0) == Announce.AVIS, "un type toujours visible ne descend pas sous l'Avis pour l'empire concerné")
	AnnounceSettings.looks.erase("war_declared")
	AnnounceSettings.cycle_look("revolt")
	_ok(AnnounceSettings.look_of("revolt") == Announce.MURMUR and AnnounceSettings.look_label("revolt") == Announce.gravity_label(0), "cycle d'apparence : Auto puis Chronique")
	for i in 4:
		AnnounceSettings.cycle_look("revolt")
	_ok(AnnounceSettings.look_of("revolt") == AnnounceSettings.AUTO, "le cycle revient à Auto")
	_ok(AnnounceSettings.pauses_for("x", Announce.FANFARE) and not AnnounceSettings.pauses_for("x", Announce.WINDOW), "par défaut, seule la Fanfare met en pause")
	AnnounceSettings.toggle_pause("revolt", Announce.WINDOW)
	_ok(AnnounceSettings.pauses_for("revolt", Announce.WINDOW), "pause imposée par type")
	AnnounceSettings.set_auto_open("revolt", false)
	_ok(not AnnounceSettings.auto_open("revolt"), "interrupteur « Ouvrir d'elle-même »")
	AnnounceSettings.cycle_preset()
	_ok(AnnounceSettings.preset == "silence", "préréglage suivant : Silence")
	AnnounceSettings.reset()
	_ok(AnnounceSettings.preset == "stratege" and AnnounceSettings.auto_open("revolt") and AnnounceSettings.anim_seconds() > 0.0, "valeurs par défaut")


func _test_save() -> void:
	var st := new_game()
	Announce.next(st, "hero_death", {"target": 0, "name": "Ilya", "hero": 3, "lvl": 4, "born": 0})
	st.add_chronicle("Ilya est mort.", [0])
	Announce.next(st, "kardashev", {"actor": 0})
	st.add_chronicle("Échelle franchie.")
	var sum := st.checksum()
	var json := JSON.stringify(st.to_dict())
	var back := GameState.from_dict(JSON.parse_string(json))
	_ok(back != null and back.checksum() == sum, "sauvegarde 90 : le registre des annonces revient à l'identique")
	if back:
		_ok(back.announces.size() == st.announces.size() and typeof(back.announces[0]["r"]["lvl"]) == TYPE_INT, "les nombres redeviennent entiers")
		_ok(int(back.announce_meta.get("firsts", {}).get("kardashev", 0)) > 0, "les premières de la galaxie sont gardées")
		_ok(String(back.chronicle.back().get("kind", "")) == "kardashev", "la chronique garde le type de ses lignes")
	_ok(GameState.FORMAT_VERSION == 90, "format de sauvegarde 90")


func _test_war() -> void:
	var st := new_game()
	var n := st.announces.size()
	Combat.start_war(st, 0, 1)
	var found := false
	for i in range(n, st.announces.size()):
		if String(st.announces[i]["k"]) == "war_declared":
			found = true
	_ok(found, "une déclaration de guerre est une annonce typée")
	var warn: Array = GameData.victories().get("warn_at", [])
	_ok(warn == [50, 75, 90], "alertes de victoire à 50, 75 et 90 %% (%s)" % str(warn))
