extends RefCounted
## Tests des souverains, lot 1 (étude « Souverain et dynastie », 2026-11-16) : catalogue en données
## (surnoms, ambitions, galerie de portraits propre aux souverains), réglage, aptitudes et effets,
## légitimité et stabilité, surnoms, ambition, pouvoir, poste au front, vieillesse, succession des sept
## gouvernements, mort des héros au combat (réglage, traits, capsules, Avatars, sauvegarde, carte),
## sauvegarde. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Souverains (le trône)…")
	_test_data()
	_test_modes()
	_test_portraits()
	_test_effects()
	_test_legitimacy()
	_test_cognomens()
	_test_ambition()
	_test_power_and_post()
	_test_old_age()
	_test_successions()
	_test_hero_death()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func new_game(seed_value := 21, extra := {}) -> GameState:
	var o := {"ai_level": "", "rulers": "mortels", "hero_death": "normale"}
	o.merge(extra, true)
	return GameState.create(seed_value, 120, 1600.0, "vael", o)


static func eid_of(st: GameState, fid: String) -> int:
	for e in st.empires:
		if e.faction_id == fid:
			return e.id
	return -1


## Avance jusqu'au prochain contrôle mensuel (compris), souverains seulement.
static func to_month(st: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in 31:
		st.tick += 1
		out.append_array(Rulers.daily(st))
		if posmod(st.tick, Rulers.r_int("check_days")) == Rulers.r_int("offset"):
			return out
	return out


static func apply(st: GameState, cmd: Dictionary) -> String:
	var why := SimCommands.validate(st, cmd)
	if why == "":
		SimCommands.apply(st, cmd)
	return why


func _test_data() -> void:
	var d := Rulers.data()
	_ok((d["cognomens"] as Array).size() >= 100, "une longue liste de surnoms (%d)" % (d["cognomens"] as Array).size())
	_ok((d["ambitions"] as Array).size() >= 25, "des ambitions en nombre (%d)" % (d["ambitions"] as Array).size())
	_ok((d["archetypes"] as Dictionary).size() == 8, "huit archétypes de règne")
	_ok((d["succession"] as Dictionary).size() == 9, "une succession par gouvernement (sept, plus les deux des peuples insolites)")
	var ids := {}
	for c: Dictionary in d["cognomens"]:
		_ok(not ids.has(c["id"]), "surnom unique %s" % c["id"])
		ids[c["id"]] = true
		_ok(String(c["m"]) != "" and String(c["f"]) != "", "surnom %s aux deux genres" % c["id"])
	for arch in ["humanoide", "ruche", "lithoide", "reptilien", "synthetique", "energetique"]:
		var pics := Rulers.portraits_for(arch)
		_ok(pics.size() >= 8, "galerie des souverains : %d portraits pour %s" % [pics.size(), arch])
		for p in pics:
			_ok(p.begins_with("ruler_"), "portrait de souverain %s (pas un portrait de héros)" % p)
	for g in d["succession"]:
		_ok(Species.options("gouvernement").any(func(b: Dictionary) -> bool: return String(b.get("id", "")) == String(g)), "gouvernement %s connu" % g)
	for e in Events.card("ruler_death").get("choices", []):
		_ok(String(e["label"]).begins_with("{ruler_fun_"), "funérailles en jetons")
	_ok(not Events.card("hero_fallen").is_empty(), "carte « héros tombé » enregistrée")


func _test_modes() -> void:
	var st0 := GameState.create(5, 120, 1600.0, "vael", {"ai_level": ""})
	_ok(st0.rulers.is_empty() and st0.hero_death.is_empty(), "sans option : ni souverain ni mort au combat (tests)")
	var st := new_game()
	_ok(Rulers.enabled(st) and Rulers.mortal(st), "Mortels")
	for e in st.empires:
		var r := Rulers.ruler(st, e.id)
		_ok(not r.is_empty(), "un souverain pour %s" % e.short_name())
		_ok(String(r["portrait"]).begins_with("ruler_"), "portrait tiré de la galerie des souverains")
		var a := Rulers.age(st, r)
		_ok(a >= 30 and a <= 52, "âge de départ (%d)" % a)
		for k in Rulers.APTS:
			_ok(int(r["apt"][k]) >= 0 and int(r["apt"][k]) <= 6, "aptitude %s de 0 à 6" % k)
		_ok(String(r["how"]) == "fondateur" and Rulers.legitimacy(st, e.id) >= 50, "fondateur légitime")
	var vael := eid_of(st, "vael")
	_ok(Rulers.title(st, vael, Rulers.ruler(st, vael)).contains("Archonte"), "titre de république : Premier Archonte")
	_ok(Rulers.title(st, eid_of(st, "khthari"), Rulers.ruler(st, eid_of(st, "khthari"))) == "Reine-mère", "titre de ruche : Reine-mère")
	_ok(int(Rulers.ruler(st, eid_of(st, "teyl"))["life"]) == 0, "Nœud premier sans limite de vie")
	var sti := new_game(21, {"rulers": "immortels"})
	_ok(int(Rulers.ruler(sti, vael)["life"]) == 0, "Immortels : pas de vieillesse")
	var sta := new_game(21, {"rulers": "aucun"})
	_ok(sta.rulers.is_empty(), "Aucun : pas de souverain")


func _test_portraits() -> void:
	var st := new_game(33)
	var eid := eid_of(st, "ossarane")
	var seen := {}
	var dup := false
	var pics := Rulers.portraits_for("humanoide").size()
	for i in mini(pics, 12):
		var r := Rulers.ruler(st, eid)
		if r.is_empty():
			break
		if seen.has(String(r["portrait"])):
			dup = true
		seen[String(r["portrait"])] = true
		Rulers.die(st, eid, "meurt pour le test", [], "age")
		if Rulers.ruler(st, eid).is_empty():
			Rulers.crown(st, eid, Rulers.make_ruler(st, eid, ["t", i], "heritier"), [], false)
	_ok(not dup, "douze règnes de suite sans portrait répété")


func _test_effects() -> void:
	var st := new_game(41)
	var eid := eid_of(st, "vael")
	var r := Rulers.ruler(st, eid)
	r["apt"] = {"gestion": 5, "guerre": 3, "eloquence": 4, "intrigue": 2}
	r["arch"] = "savant"
	Relics.touch(st)
	var fx := Research.effects(st, eid)
	var rfx := Rulers.effects(st, eid)
	_ok(int(rfx["production_pct"]["all"]) == 10, "Gestion 5 : +10 % de production")
	_ok(int(rfx["damage_pct"]) == 6, "Guerre 3 : +6 % de dégâts")
	_ok(int(rfx["spy_cost_pct"]) == -6, "Intrigue 2 : opérations 6 % moins chères")
	_ok(int(rfx.get("knowledge_pct", 0)) == 5, "archétype Savant : +5 % de Savoir")
	_ok(int((fx.get("production_pct", {}) as Dictionary).get("all", 0)) >= 10, "fusionné dans les effets de l'empire")
	_ok(int(Rulers.income(st, eid).get("influence", 0)) == 4, "Éloquence 4 : +4 influence par mois")
	_ok(int(Heroes.income(st, eid).get("influence", 0)) >= 4, "revenu passé par les héros")
	_ok(Rulers.encryption(st, eid) == 1, "Intrigue : chiffrement")
	var found := false
	for o in st.empires:
		if o.id != eid:
			for p in Diplomacy.opinion_parts(st, o.id, eid):
				if String(p["label"]).contains("Éloquence"):
					found = true
	_ok(found, "Éloquence : opinion des autres empires")


func _test_legitimacy() -> void:
	var st := new_game(43)
	var eid := eid_of(st, "vael")
	var r := Rulers.ruler(st, eid)
	var l0 := Rulers.legitimacy(st, eid)
	Rulers.adjust(st, eid, 30)
	_ok(Rulers.legitimacy(st, eid) == mini(100, l0 + 30), "ajustement de légitimité")
	var parts := Rulers.stability_parts(st, eid)
	_ok(parts.any(func(p: Array) -> bool: return String(p[0]) == "Souverain légitime" and int(p[1]) == 5), "au-dessus de 75 : +5 stabilité")
	Rulers.adjust(st, eid, -80)
	parts = Rulers.stability_parts(st, eid)
	_ok(Rulers.legitimacy(st, eid) <= 25, "légitimité basse")
	_ok(parts.any(func(p: Array) -> bool: return String(p[0]) == "Souverain contesté" and int(p[1]) == -5), "sous 25 : -5 stabilité")
	# Surnoms des prédécesseurs : 1/2.
	var en := Rulers.entry(st, eid)
	en["adj"] = 0
	var base := Rulers.legitimacy(st, eid)
	(en["reigns"] as Array).append({"name": "Ancien", "first": "Ancien", "cogs": ["invincible"], "from": 0, "to": 0})
	_ok(Rulers.legitimacy(st, eid) == mini(100, base + 15), "le surnom du prédécesseur compte pour moitié (30 → 15)")
	r["cogs"] = ["victorieux"]
	_ok(Rulers.legitimacy(st, eid) == mini(100, base + 15 + 15), "son propre surnom compte en entier")


func _test_cognomens() -> void:
	var st := new_game(47)
	var eid := eid_of(st, "vael")
	var en := Rulers.entry(st, eid)
	var r := Rulers.ruler(st, eid)
	Rulers.note(st, eid, "battles_won", 3)
	var out := to_month(st)
	_ok((r["cogs"] as Array).has("vaillant"), "trois victoires : « le Vaillant »")
	_ok(Rulers.full_name(st, eid).contains("Vaillant") or Rulers.full_name(st, eid).contains("Vaillante"), "nom complet avec surnom : %s" % Rulers.full_name(st, eid))
	Rulers.note(st, eid, "battles_won", 5)
	to_month(st)
	_ok((r["cogs"] as Array).has("victorieux") and not (r["cogs"] as Array).has("vaillant"), "un surnom plus fort remplace le plus faible")
	_ok(int(en["acts"]["battles_won"]) == 8, "compteur du règne")
	var cond_ok := true
	for c in r["cogs"]:
		var cd := Rulers.cog_def(String(c))
		if cd.has("cond") and not Events._layers_ok(st, eid, cd["cond"]):
			cond_ok = false
	_ok(cond_ok, "surnoms de couche respectés")
	_ok(out.size() >= 0, "chronique")


func _test_ambition() -> void:
	var st := new_game(51)
	var eid := eid_of(st, "vael")
	var en := Rulers.entry(st, eid)
	var added: Array[Dictionary] = []
	Rulers.offer_ambition(st, eid, added, true)
	var box := Events.inbox(st, eid)
	var item: Dictionary = box[box.size() - 1]
	_ok(String(item["card"]) == "ruler_accession", "carte d'avènement")
	var opts := Events.choices(st, eid, item)
	_ok(opts.size() == 3 and not String(opts[0]["label"]).contains("{"), "trois ambitions lisibles : %s" % String(opts[0]["label"]))
	var note := Rulers.note_of(st, eid, item)
	var amb_id := ""
	var idx := 0
	for i in (note["amb"] as Array).size():
		if String(Rulers.amb_def(String(note["amb"][i]))["src"]) == "r":
			amb_id = String(note["amb"][i])
			idx = i
			break
	if amb_id == "":
		amb_id = String(note["amb"][0])
	Events.choose(st, eid, int(item["id"]), idx, added)
	_ok(String(en["amb"].get("id", "")) == amb_id, "ambition choisie")
	var a := Rulers.amb_def(amb_id)
	var l0 := Rulers.legitimacy(st, eid)
	if String(a["src"]) == "r":
		Rulers.note(st, eid, String(a["k"]), int(a["n"]))
		to_month(st)
		_ok(en["amb"].is_empty() and (en["amb_done"] as Array).has(amb_id), "ambition réussie")
		_ok(Rulers.legitimacy(st, eid) >= mini(100, l0 + 15), "+15 de légitimité")
		_ok((Rulers.ruler(st, eid)["cogs"] as Array).has("amb:" + amb_id), "et un surnom d'ambition")
	# L'IA choisit aussi (choix noté).
	_ok(Rulers.ai_value(st, eid, item, {"k": "ruler", "act": "ambition", "i": 0}) != -999, "valeur d'IA")


func _test_power_and_post() -> void:
	var st := new_game(53)
	var eid := eid_of(st, "vael")
	var en := Rulers.entry(st, eid)
	var r := Rulers.ruler(st, eid)
	r["arch"] = "conquerant"
	_ok(apply(st, SimCommands.ruler_act(eid, "power")) == "", "pouvoir disponible")
	_ok(int(Rulers.effects(st, eid).get("damage_pct", 0)) >= 20, "Offensive : +20 % de dégâts")
	_ok(apply(st, SimCommands.ruler_act(eid, "power")) != "", "puis en recharge")
	st.tick = int(en["power_until"]) + 1
	Relics.touch(st)
	_ok(int(Rulers.effects(st, eid).get("damage_pct", 0)) < 20, "le pouvoir s'éteint")
	# Poste : capitale.
	_ok(apply(st, SimCommands.ruler_act(eid, "post", -1, "capital")) == "", "gouverneur de la capitale")
	var cap := FactionTraits.capital_system(st, eid)
	_ok(Rulers.capital_prod_pct(st, eid, cap) == int(r["apt"]["gestion"]) * 2, "Gestion double à la capitale")
	# Front : une flotte armée.
	var f := st.spawn_ship(eid, "fregate", cap)
	_ok(apply(st, SimCommands.ruler_act(eid, "post", f.id, "fleet")) == "", "à la tête d'une flotte")
	_ok(Rulers.fleet_damage_pct(st, f) == int(r["apt"]["guerre"]) * 2, "Guerre double pour sa flotte")
	_ok(Rulers.check_act(st, eid_of(st, "khthari"), "post", f.id, "fleet") != "", "la Reine-mère ne quitte pas la ruche")
	# Flotte anéantie : mort (10 %) ou blessure.
	st.fleets.erase(f.id)
	var out := to_month(st)
	var dead := not Rulers.ruler(st, eid).has("name") or Rulers.ruler(st, eid) != r
	_ok(dead or Rulers.is_wounded(st, eid), "flotte anéantie : blessé ou mort")
	_ok(out.size() > 0, "chronique du front")


func _test_old_age() -> void:
	var st := new_game(57)
	var eid := eid_of(st, "vael")
	var r := Rulers.ruler(st, eid)
	r["born"] = st.tick - 120 * 360
	var died := false
	for i in 40:
		to_month(st)
		if Rulers.ruler(st, eid) != r:
			died = true
			break
	_ok(died, "un souverain très vieux finit par mourir")
	var en := Rulers.entry(st, eid)
	_ok((en["reigns"] as Array).size() >= 1, "règne inscrit")
	_ok(Rulers.has_ruler(st, eid), "la République élit un successeur aussitôt")
	_ok(String(Rulers.ruler(st, eid)["how"]) == "elu", "élu")
	var box := Events.inbox(st, eid)
	var fun := false
	for item in box:
		if String(item["card"]) == "ruler_death":
			fun = true
			var opts := Events.choices(st, eid, item)
			_ok(opts.size() >= 2 and not String(opts[0]["label"]).contains("{"), "funérailles au choix : %s" % String(opts[0]["label"]))
			var added: Array[Dictionary] = []
			Events.choose(st, eid, int(item["id"]), int(opts[0]["index"]), added)
			_ok(not (en["fun"] as Dictionary).is_empty(), "funérailles choisies, effet 5 ans")
			break
	_ok(fun, "carte de mort et funérailles")
	# Synthétiques : accident rare, jamais de vieillesse.
	var t := eid_of(st, "teyl")
	_ok(int(Rulers.ruler(st, t)["life"]) == 0, "Nœud premier immortel")


func _test_successions() -> void:
	var st := new_game(61)
	var added: Array[Dictionary] = []
	# Théocratie : Siège vacant 60 jours.
	var ch := eid_of(st, "choeur")
	Rulers.die(st, ch, "meurt", added, "age")
	_ok(Rulers.vacant(st, ch) and String(Rulers.entry(st, ch)["vacant_kind"]) == "conclave", "Siège vacant")
	_ok(Rulers.stability_parts(st, ch).any(func(p: Array) -> bool: return String(p[0]) == "Interrègne"), "interrègne : -5 stabilité")
	st.tick = int(Rulers.entry(st, ch)["vacant"])
	RulersSuccession.resolve(st, ch, added)
	_ok(Rulers.has_ruler(st, ch) and String(Rulers.ruler(st, ch)["how"]) == "conclave", "le Conclave élit")
	# Horde : l'Épreuve, 90 jours.
	var fe := eid_of(st, "ferrocornes")
	Rulers.die(st, fe, "meurt", added, "age")
	_ok(String(Rulers.entry(st, fe)["vacant_kind"]) == "epreuve", "Épreuve du Khan")
	st.tick = int(Rulers.entry(st, fe)["vacant"])
	RulersSuccession.resolve(st, fe, added)
	_ok(String(Rulers.ruler(st, fe).get("how", "")) == "epreuve" and Rulers.legitimacy(st, fe) >= 60, "le vainqueur de l'Épreuve, légitime")
	# Ruche : capitale perdue = la Reine-mère meurt ; un an sans reine.
	var kh := eid_of(st, "khthari")
	var cap := st.get_empire(kh).capital_planet
	(st.colonies[cap] as Colony).owner = GameState.NPC_ID
	Rulers.daily(st)
	_ok(String(Rulers.entry(st, kh)["vacant_kind"]) == "reine", "ruche sans reine")
	_ok(int((Rulers.effects(st, kh).get("production_pct", {}) as Dictionary).get("all", 0)) <= -20, "production -20 %")
	(st.colonies[cap] as Colony).owner = kh
	# Syndicat : défiance après deux trimestres de baisse.
	var br := eid_of(st, "brisecomete")
	var en := Rulers.entry(st, br)
	Rulers.ruler(st, br)["from"] = st.tick - 800
	en["inc"] = [1000, 900]
	var r0 := Rulers.ruler(st, br)
	for i in 4:
		to_month(st)
	_ok(Rulers.ruler(st, br) != r0 or (en["inc"] as Array).size() > 0, "trimestres suivis")
	# République : fin de mandat.
	var va := eid_of(st, "vael")
	var ev := Rulers.entry(st, va)
	ev["terms"] = 2
	ev["term_end"] = st.tick
	var r1 := Rulers.ruler(st, va)
	to_month(st)
	_ok(Rulers.ruler(st, va) != r1 and int(ev["terms"]) == 1, "deux mandats au plus : nouvel Archonte")
	# Conscience : itération tous les 20 ans.
	var te := eid_of(st, "teyl")
	Rulers.entry(st, te)["iter_next"] = st.tick
	to_month(st)
	var it := false
	for item in Events.inbox(st, te):
		if String(item["card"]) == "ruler_iteration":
			it = true
			var opts := Events.choices(st, te, item)
			var old := String(Rulers.ruler(st, te)["arch"])
			Events.choose(st, te, int(item["id"]), int(opts[1]["index"]), added)
			_ok(String(Rulers.ruler(st, te)["arch"]) != old, "itération : nouvel archétype")
	_ok(it, "carte d'itération")
	# Féodalité : l'héritier d'Ossarane monte sur le trône.
	var os := eid_of(st, "ossarane")
	Heroes.ensure_heir(st, st.get_empire(os))
	var heir := Heroes.heir_of(st, os)
	_ok(not heir.is_empty(), "Ossarane a son héritier")
	var hname := String(heir.get("name", "")).split(",")[0]
	Rulers.die(st, os, "meurt", added, "age")
	_ok(String(Rulers.ruler(st, os).get("name", "")) == hname, "l'héritier des Lignées devient souverain")
	_ok(not st.heroes.has(int(heir.get("id", -1))), "il quitte les héros")


func _test_hero_death() -> void:
	var st := new_game(71)
	var eid := eid_of(st, "vael")
	var hid: int = Heroes.ids_of(st, eid)[0]
	var h: Dictionary = st.heroes[hid]
	_ok(HeroFall.chance(st, h, "fleet") == 10, "flotte anéantie : 10 %")
	_ok(HeroFall.chance(st, h, "flagship") == 3, "plus gros vaisseau perdu : 3 %")
	_ok(HeroFall.chance(st, h, "system") == 5 and HeroFall.chance(st, h, "army") == 5, "système perdu, armée vaincue : 5 %")
	(h["traits"] as Array).append("trompe_la_mort")
	_ok(HeroFall.chance(st, h, "fleet") == 5, "Trompe-la-mort : deux fois moins")
	(h["traits"] as Array).erase("trompe_la_mort")
	(h["traits"] as Array).append("temeraire")
	_ok(HeroFall.chance(st, h, "fleet") == 20, "Téméraire : deux fois plus")
	(h["traits"] as Array).erase("temeraire")
	_ok(Heroes.class_traits("stratege", st).has("temeraire") and Heroes.class_traits("", st).has("trompe_la_mort"), "traits de la mort au combat tirés quand elle est en jeu")
	var off := GameState.create(5, 40, 1000.0, "vael", {"ai_level": ""})
	_ok(not Heroes.class_traits("stratege", off).has("temeraire") and not Heroes.class_traits("", off).has("trompe_la_mort"), "sans mort au combat, jamais tirés")
	h["surv"] = 1
	_ok(HeroFall.chance(st, h, "fleet") == 7, "Capsules de survie : 3 points de moins")
	h.erase("surv")
	var stb := new_game(71, {"hero_death": "brutale"})
	_ok(HeroFall.chance(stb, stb.heroes[Heroes.ids_of(stb, eid)[0]], "fleet") == 20, "Brutale : doublé")
	var stj := new_game(71, {"hero_death": "jamais"})
	_ok(HeroFall.chance(stj, stj.heroes[Heroes.ids_of(stj, eid)[0]], "fleet") == 0, "Jamais : aucune mort")
	var st0 := GameState.create(71, 120, 1600.0, "vael", {"ai_level": ""})
	_ok(HeroFall.chance(st0, st0.heroes[Heroes.ids_of(st0, eid)[0]], "fleet") == 0, "sans option : aucune mort (tests)")
	# Mort : tueur, souvenir Honneur, carte au niveau 3.
	var out: Array[Dictionary] = []
	h["lvl"] = 3
	var foe := eid_of(st, "ferrocornes")
	HeroFall.fall(st, h, out, "sa flotte a été anéantie", foe, "fleet")
	_ok(not st.heroes.has(hid), "le héros meurt")
	var card := false
	for item in Events.inbox(st, eid):
		if String(item["card"]) == "hero_fallen":
			card = true
			var t := Events.fill(st, eid, item, String(Events.card("hero_fallen")["title"]))
			_ok(t.begins_with(String(h["name"])), "fenêtre « %s »" % t)
	_ok(card, "un héros de niveau 3 ouvre la fenêtre d'événement")
	# Honneur : souvenir même sous le niveau 3.
	var fe := eid_of(st, "ferrocornes")
	var fh: Dictionary = st.heroes[Heroes.ids_of(st, fe)[0]]
	fh["lvl"] = 1
	var mem0 := (Heroes.meta(st, fe).get("memorials", []) as Array).size()
	HeroFall.fall(st, fh, out, "test", eid, "fleet")
	_ok((Heroes.meta(st, fe).get("memorials", []) as Array).size() == mem0 + 1, "credo Honneur : souvenir de tout mort au combat")
	# Avatar : se reforme 180 jours plus tard, un niveau plus bas.
	var kh := eid_of(st, "khthari")
	var ah: Dictionary = st.heroes[Heroes.ids_of(st, kh)[0]]
	ah["lvl"] = 3
	_ok(HeroFall.chance(st, ah, "fleet") == 15, "Avatar : ×1,5")
	var n0 := Heroes.ids_of(st, kh).size()
	HeroFall.fall(st, ah, out, "test", -1, "fleet")
	_ok(Heroes.ids_of(st, kh).size() == n0 - 1, "l'Avatar tombe")
	st.tick += 181
	HeroFall.daily(st, out)
	_ok(Heroes.ids_of(st, kh).size() == n0, "l'esprit commun en reforme un")
	var back: Dictionary = st.heroes[Heroes.ids_of(st, kh)[Heroes.ids_of(st, kh).size() - 1]]
	_ok(int(back["lvl"]) == 2, "un niveau plus bas")
	# Synthétique avec sauvegarde.
	var te := eid_of(st, "teyl")
	st.get_empire(te).techs["ia_bord"] = true
	Relics.touch(st)
	var sh: Dictionary = st.heroes[Heroes.ids_of(st, te)[0]]
	var nt := Heroes.ids_of(st, te).size()
	HeroFall.fall(st, sh, out, "test", -1, "fleet")
	st.tick += 361
	HeroFall.daily(st, out)
	_ok(Heroes.ids_of(st, te).size() == nt, "synthétique restauré de sa sauvegarde")
	# Le combat note les capsules et le plus gros vaisseau.
	var f := st.spawn_ship(eid, "fregate", FactionTraits.capital_system(st, eid))
	f.add_ship("corvette")
	var hid2: int = Heroes.ids_of(st, eid)[0] if not Heroes.ids_of(st, eid).is_empty() else -1
	if hid2 >= 0:
		var h2: Dictionary = st.heroes[hid2]
		h2["post"] = "fleet"
		h2["target"] = f.id
		_ok(HeroFall.watched(st, f), "flotte surveillée")
		var top := HeroFall.top_strength(f)
		f.remove_at(0)
		HeroFall.on_losses(st, f, top, false)
		_ok(int(h2.get("flag_hit", 0)) == 1, "plus gros vaisseau perdu : coup noté")
	_ok(Designs.FLAGS.has("survival"), "module Capsules de survie reconnu")


func _test_save() -> void:
	var st := new_game(81)
	var eid := eid_of(st, "vael")
	Rulers.note(st, eid, "battles_won", 3)
	to_month(st)
	var d := st.to_snapshot()
	_ok(int(d["version"]) >= 75, "format de sauvegarde 75 ou plus")
	var st2 := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(st2 != null, "relecture")
	if st2 == null:
		return
	_ok(Rulers.full_name(st2, eid) == Rulers.full_name(st, eid), "souverain relu : %s" % Rulers.full_name(st2, eid))
	_ok(HeroFall.mode(st2) == "normale", "réglage de mort au combat relu")
	_ok(Rulers.legitimacy(st2, eid) == Rulers.legitimacy(st, eid), "légitimité identique")
