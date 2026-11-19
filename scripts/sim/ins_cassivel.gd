class_name InsCassivel
extends RefCounted
## Muséum de Sire Cassivel (props 65 à 70 ; voir Insolites, data/insolites.json "cassivel").
## Un seul immortel et ses serviteurs, qui veut un exemplaire de tout.
##   - Sire Cassivel règne pour toujours (succession « immortel », data/rulers.json) et voyage comme un
##     héros. S'il tombe, le Muséum entre en crise « Orphelin », sauf copie de sauvegarde payée d'avance :
##     il revient alors au bout de backup_days.
##   - Les Serviteurs : population multi-espèces, peu nombreuse, tournée vers la production.
##   - La Collection : cinq vitrines (espèces, reliques, héros captifs, créatures du Vivarium, prises de
##     guerre). Chaque pièce rayonne (Culture) ; une galerie complète (gallery_min pièces de chaque) rayonne
##     beaucoup plus et rapporte de l'influence.
##   - Acquérir : acheter un spécimen (accord commercial ou peuple mineur en contact), le voler
##     (opération d'espionnage « Acquisition discrète »), ou le capturer en prenant une colonie (une espèce
##     qui vit dans ses colonies compte).
##   - Victoire : le Musée vivant (un représentant de chaque espèce des empires et des mineurs rencontrés).
##   - Événements : un spécimen s'évade, un héros rival vient libérer un prisonnier, des visiteurs.
##
## État (Insolites.emp) : "hero" (identifiant du héros Cassivel, -1 s'il est tombé), "backup" (copie
## payée), "back" (jour de retour), "orphan" (fin de la crise), "spec": {espèce: jour d'acquisition}.


static func _c(key: String, def := 0) -> int:
	return Insolites.c_int("cassivel", key, def)


static func found(_state: GameState, _e: Empire, _sid: int, ed: Dictionary) -> void:
	ed["hero"] = -1
	ed["backup"] = 0
	ed["back"] = 0
	ed["orphan"] = 0
	ed["spec"] = {}


## Après la mise en place : Sire Cassivel entre en scène, héros et souverain.
static func after_setup(state: GameState, eid: int) -> void:
	_spawn_hero(state, eid)
	var r := Rulers.ruler(state, eid)
	if not r.is_empty():
		r["name"] = "Cassivel"
		r["g"] = "m"


static func _spawn_hero(state: GameState, eid: int) -> void:
	var cfg := Insolites.cfg("cassivel")
	var cand := Heroes.make_candidate(state, eid, String(cfg.get("hero_cls", "orateur")), ["cassivel", eid, state.tick])
	cand["name"] = String(cfg.get("hero_name", "Sire Cassivel"))
	cand["age"] = 30
	var id := Heroes.recruit(state, eid, cand)
	var h: Dictionary = state.heroes[id]
	h["lvl"] = maxi(int(h["lvl"]), _c("hero_lvl", 3))
	h["life"] = 100000
	h["cassivel"] = true
	Insolites.emp(state, eid)["hero"] = id


static func hero(state: GameState, eid: int) -> Dictionary:
	var id := int(Insolites.emp(state, eid).get("hero", -1))
	return state.heroes.get(id, {}) if id >= 0 else {}


static func orphan(state: GameState, eid: int) -> bool:
	return Insolites.kind(state, eid) == "cassivel" and int(Insolites.emp(state, eid).get("orphan", 0)) > state.tick


## Sire Cassivel tombe (Heroes.die) : retour de la copie de sauvegarde, ou crise « Orphelin ».
static func on_hero_death(state: GameState, h: Dictionary, out: Array[Dictionary]) -> void:
	if not bool(h.get("cassivel", false)):
		return
	var eid := int(h["owner"])
	var ed := Insolites.emp(state, eid)
	if ed.is_empty():
		return
	ed["hero"] = -1
	if int(ed.get("backup", 0)) > 0:
		ed["backup"] = 0
		ed["back"] = state.tick + _c("backup_days", 180)
		out.append(state.add_chronicle("Sire Cassivel est mort. Dans une crypte du Muséum, une cuve s'allume et un corps neuf commence à pousser : la copie de sauvegarde sera prête dans %d jours." % _c("backup_days", 180),
				Espionage.public_to(state, [eid])))
	else:
		ed["orphan"] = state.tick + _c("orphan_days", 1080)
		out.append(state.add_chronicle("Sire Cassivel est mort, sans copie. Le Muséum est Orphelin : les serviteurs époussettent des vitrines que personne ne regarde plus, et les pièces commencent à se demander pourquoi elles restent.",
				Espionage.public_to(state, [eid])))


static func check_backup(state: GameState, eid: int) -> String:
	if Insolites.kind(state, eid) != "cassivel":
		return "seul Sire Cassivel se fait sauvegarder"
	var ed := Insolites.emp(state, eid)
	if int(ed.get("backup", 0)) > 0:
		return "une copie de sauvegarde attend déjà dans sa cuve"
	if hero(state, eid).is_empty():
		return "Sire Cassivel n'est pas là pour se faire copier"
	var cost: Dictionary = Insolites.cfg("cassivel").get("backup_cost", {})
	if not Economy.can_afford(state.get_empire(eid), cost):
		return "ressources insuffisantes (il faut %s)" % GameData.format_amounts(cost)
	return ""


static func backup(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	Economy.pay(state.get_empire(eid), Insolites.cfg("cassivel").get("backup_cost", {}))
	Insolites.emp(state, eid)["backup"] = 1
	added.append(state.add_chronicle("Sire Cassivel se fait copier. Il trouve la copie un peu pâle, et demande qu'on refasse le nez.", Espionage.private_to(state, [eid])))


# --- La Collection (prop. 67) ------------------------------------------------------------------------

## Espèces exposées : spécimens acquis, et espèces qui vivent dans ses colonies (capturées au combat).
static func species_held(state: GameState, eid: int) -> Array[String]:
	var out: Array[String] = []
	for k in (Insolites.emp(state, eid).get("spec", {}) as Dictionary):
		out.append(String(k))
	var own := state.get_empire(eid).faction_id
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != eid or not c.is_colony():
			continue
		for fid in c.species:
			if int(c.species[fid]) > 0 and String(fid) != own and not out.has(String(fid)):
				out.append(String(fid))
	out.sort()
	return out


static func prize_ships(state: GameState, eid: int) -> int:
	var n := 0
	for f in Fleets.empire_fleets(state, eid):
		for s in f.ships:
			if Capture.is_prize(String(s)):
				n += 1
	return n


## Pièces par vitrine : {"espece", "relique", "heros", "creature", "vaisseau"}.
static func showcases(state: GameState, eid: int) -> Dictionary:
	return {
		"espece": species_held(state, eid).size(),
		"relique": Relics.owned(state, eid).size(),
		"heros": Heroes.prisoners_of(state, eid).size(),
		"creature": WarBeasts.beasts(state, eid).size(),
		"vaisseau": prize_ships(state, eid),
	}


static func gallery_complete(sc: Dictionary) -> bool:
	for k in sc:
		if int(sc[k]) < _c("gallery_min", 3):
			return false
	return true


## Sources de Rayonnement (Culture.source_parts).
static func culture_parts(state: GameState, eid: int, out: Array) -> void:
	if Insolites.kind(state, eid) != "cassivel":
		return
	var sc := showcases(state, eid)
	var n := 0
	for k in sc:
		n += int(sc[k])
	if n > 0:
		out.append(["Collection du Muséum (%d pièces)" % n, n * _c("piece_radiance", 3)])
	if gallery_complete(sc):
		out.append(["Galerie complète", _c("gallery_radiance", 40)])


static func income(state: GameState, eid: int) -> Dictionary:
	return {"influence": _c("gallery_influence", 5)} if gallery_complete(showcases(state, eid)) else {}


# --- Acquérir (prop. 68) -----------------------------------------------------------------------------

## Espèce que vend un empire ou un mineur ("" s'il n'a rien à vendre).
static func species_of(state: GameState, who: int) -> String:
	if GameState.is_npc(who):
		return Minors.species_id(state, who) if not state.minors.is_empty() and Minors.get_m(state, who).size() > 0 else ""
	var e := state.get_empire(who)
	return e.faction_id if e != null and not e.eliminated and Insolites.kind(state, who) != "silencieux" else ""


static func check_acquire(state: GameState, eid: int, who: int) -> String:
	if Insolites.kind(state, eid) != "cassivel":
		return "seul le Muséum collectionne les espèces"
	var fid := species_of(state, who)
	if fid == "" or who == eid:
		return "rien à acquérir là"
	if species_held(state, eid).has(fid):
		return "la vitrine a déjà son spécimen"
	if int(Insolites.emp(state, eid).get("buy_cd", 0)) > state.tick:
		return "le Muséum attend sa prochaine vente aux enchères (%d jours)" % (int(Insolites.emp(state, eid)["buy_cd"]) - state.tick)
	if GameState.is_npc(who):
		if not Minors.in_contact(state, who, eid):
			return "vous ne les connaissez pas"
	elif not Diplomacy.has_trade(state, eid, who):
		return "il faut un accord commercial pour acheter un volontaire"
	var cost: Dictionary = Insolites.cfg("cassivel").get("buy_cost", {})
	if not Economy.can_afford(state.get_empire(eid), cost):
		return "ressources insuffisantes (il faut %s)" % GameData.format_amounts(cost)
	return ""


static func acquire(state: GameState, eid: int, who: int, added: Array[Dictionary]) -> void:
	var cost: Dictionary = Insolites.cfg("cassivel").get("buy_cost", {})
	Economy.pay(state.get_empire(eid), cost)
	if not GameState.is_npc(who):
		var seller := state.get_empire(who)
		for r in cost:
			seller.resources[r] = int(seller.resources.get(r, 0)) + int(cost[r]) / 2
	add_specimen(state, eid, species_of(state, who))
	Insolites.emp(state, eid)["buy_cd"] = state.tick + _c("buy_cd_days", 360)
	var name := Minors.name_of(state, who) if GameState.is_npc(who) else state.get_empire(who).display_name()
	added.append(state.add_chronicle("Le Muséum acquiert un spécimen auprès de %s : un volontaire, bien payé, qui demande si la vitrine a une fenêtre. Elle en a une, peinte." % name,
			Espionage.private_to(state, [eid, who])))


static func add_specimen(state: GameState, eid: int, fid: String) -> void:
	if fid == "":
		return
	(Insolites.emp(state, eid)["spec"] as Dictionary)[fid] = state.tick


## Opération « Acquisition discrète » (Espionage, drapeau "insolites") : un spécimen volé.
static func spy_steal(state: GameState, a: int, b: int) -> String:
	var fid := species_of(state, b)
	if fid == "" or species_held(state, a).has(fid):
		return "la vitrine était déjà pleine : les agents rentrent avec des souvenirs"
	add_specimen(state, a, fid)
	Diplomacy.remember(state, b, a, "ins_specimen_stolen")
	return "un spécimen de %s rejoint discrètement le Muséum" % state.get_empire(b).short_name()


# --- Événements (prop. 70) ---------------------------------------------------------------------------

static func daily(state: GameState, eid: int, ed: Dictionary, month: bool, added: Array[Dictionary]) -> void:
	if int(ed.get("back", 0)) > 0 and int(ed["back"]) <= state.tick:
		ed["back"] = 0
		_spawn_hero(state, eid)
		added.append(state.add_chronicle("Sire Cassivel sort de sa cuve, s'étire, et demande ce qu'il a manqué. On lui fait la liste ; il soupire.", Espionage.public_to(state, [eid])))
	if not month:
		return
	var spec: Dictionary = ed.get("spec", {})
	var h := hash([state.seed_value, state.tick, eid, "museum"])
	if not spec.is_empty() and posmod(h, 1000) < _c("escape_pmille", 15) * (3 if orphan(state, eid) else 1):
		var ks := spec.keys()
		ks.sort()
		var fid := String(ks[posmod(h / 1000, ks.size())])
		spec.erase(fid)
		added.append(state.add_chronicle("Évasion au Muséum ! Le spécimen %s a scié les barreaux de sa vitrine avec une cuillère de collection. Sire Cassivel fait inventorier les cuillères." % String(GameData.faction(fid).get("short", fid)),
				Espionage.private_to(state, [eid])))
	var pris := Heroes.prisoners_of(state, eid)
	if not pris.is_empty() and posmod(h / 7, 1000) < _c("rescue_pmille", 20):
		var hp: Dictionary = state.heroes[pris[posmod(h / 13, pris.size())]]
		Heroes._free(state, hp)
		added.append(state.add_chronicle("Un héros de %s s'introduit au Muséum pendant les heures de visite et repart avec %s, sous le bras, comme une pièce empruntée." % [
				state.get_empire(int(hp["owner"])).short_name() if state.get_empire(int(hp["owner"])) else "?", String(hp["name"])], Espionage.public_to(state, [eid, int(hp["owner"])])))
	if posmod(h / 17, 1000) < _c("visitors_pmille", 60):
		var e := state.get_empire(eid)
		e.resources["influence"] = int(e.resources.get("influence", 0)) + _c("visitors_influence", 15)
		added.append(state.add_chronicle("Une délégation étrangère visite le Muséum de Sire Cassivel. Ils repartent émerveillés, avec des cartes postales et une légère inquiétude.", Espionage.private_to(state, [eid])))


static func stability_parts(state: GameState, owner: int, out: Array) -> void:
	if orphan(state, owner):
		out.append(["Muséum Orphelin", _c("orphan_stab", -15)])


static func production_bonus(state: GameState, eid: int) -> int:
	return _c("orphan_prod_pct", -25) if orphan(state, eid) else 0


# --- Victoire : le Musée vivant (prop. 69) -----------------------------------------------------------

## Espèces de la partie à exposer : celles des autres empires vivants et des mineurs rencontrés.
static func wanted_species(state: GameState, eid: int) -> Array[String]:
	var out: Array[String] = []
	for o in state.empires:
		if o.id == eid or o.eliminated or o.is_npc():
			continue
		var fid := species_of(state, o.id)
		if fid != "" and not out.has(fid):
			out.append(fid)
	if not state.minors.is_empty():
		for mid in Minors.met(state, eid):
			var fid2 := Minors.species_id(state, mid)
			if fid2 != "" and not out.has(fid2):
				out.append(fid2)
	out.sort()
	return out


static func victory(state: GameState, e: Empire, out: Dictionary) -> void:
	var want := wanted_species(state, e.id)
	var held := species_held(state, e.id)
	var n := 0
	for fid in want:
		if held.has(fid):
			n += 1
	out["lines"].append("Espèces exposées : %d / %d" % [n, want.size()])
	out["cond"] = want.size() > 0 and n >= want.size()
	Victory._timed(out, n, maxi(1, want.size()))


static func status_lines(state: GameState, eid: int, ed: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var h := hero(state, eid)
	if not h.is_empty():
		out.append("Sire Cassivel : niveau %d%s" % [int(h.get("lvl", 1)), ", copie de sauvegarde prête" if int(ed.get("backup", 0)) > 0 else ""])
	elif int(ed.get("back", 0)) > state.tick:
		out.append("Sire Cassivel repousse dans sa cuve (%d jours)" % (int(ed["back"]) - state.tick))
	if orphan(state, eid):
		out.append("Muséum Orphelin encore %d jours" % (int(ed["orphan"]) - state.tick))
	var sc := showcases(state, eid)
	var labels: Dictionary = Insolites.cfg("cassivel").get("showcase_labels", {})
	var parts := PackedStringArray()
	for k in Insolites.cfg("cassivel").get("showcases", []):
		parts.append("%s %d" % [String(labels.get(k, k)), int(sc.get(k, 0))])
	out.append("Vitrines : %s%s" % [", ".join(parts), " (galerie complète)" if gallery_complete(sc) else ""])
	return out
