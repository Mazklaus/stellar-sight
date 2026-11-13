class_name Heroes
extends RefCounted
## Héros, lot 1 (socle) : voir data/heroes.json et l'étude « Les héros dans Stellar Sigth ».
##
## Un héros est un personnage unique (nom, portrait de la galerie des héros, âge, classe, niveau 1 à
## 5, traits). Chaque empire en a un au départ. Ses actes (coloniser, gagner une bataille, réussir une
## opération, signer un traité, découvrir une technologie…) font monter son RENOM ; au seuil
## (base + step × héros déjà obtenus), on lui offre un héros « 1 parmi 3 », dont la classe penche vers
## ce qu'il a fait (Endless Space 2). Il en garde au plus cap (+ technologies hero_cap).
##
## Quatre classes, quatre postes : Stratège (amiral d'une flotte), Intendant (gouverneur d'un système),
## Orateur (siège au conseil), Ombre (agent d'un réseau d'espionnage). Un héros peut tenir n'importe
## quel poste ; l'effet est plein pour la classe qui en a l'habitude, à moitié pour les autres. Hors du
## système capital (et pour un agent), il lui faut travel_days pour arriver. Une flotte anéantie ou un
## système perdu le blesse (wound_days). Le conseil a council_seats sièges (+ technologies council_seats).
##
## Tout est déterministe : entiers, héros parcourus dans l'ordre des identifiants, tirages par hachage
## de la graine (jamais le générateur partagé), ordres des joueurs par SimCommands.
##
## Héros : state.heroes[id] = {"id", "owner", "name", "portrait", "cls", "lvl", "xp", "traits",
##   "born" (jour de naissance, négatif avant le début), "post" ("" | fleet | system | council | agent),
##   "target" (flotte, système, siège ou empire visé), "arrive" (jour où il prend son poste),
##   "wound" (jour de guérison, 0 = valide), "joined"}.
## Par empire : state.hero_meta[empire] = {"renown", "acts": {classe: points}, "got", "offer": [candidats],
##   "memorials": [{"name", "until", "credo"}], "election": jour de la dernière élection (république)}.
##
## Lot 2 (vie et mort) : chaque héros a une ambition ("amb", "" pour un Avatar) que servent certains
## actes de l'empire ("served" = dernier jour servi, "amb_n" = compte vers le grand objectif,
## "amb_done"), une loyauté "loy" (0-100 ; sous min_desert il peut déserter vers un rival), une
## espérance de vie "life" en années (0 = sans limite), des traits de son peuple tirés des couches
## d'espèce, des défauts avec l'âge. Une flotte anéantie ou un système pris peut le faire capturer :
## "jailer" = empire qui le tient (-1 libre), "foe" = dernier ennemi rencontré en bataille, "convert" =
## jour où sa conversion s'achève (0 = aucune). Le geôlier libère, convertit ou exécute ; la paix rend
## les prisonniers. Un héros de niveau min_lvl qui meurt laisse un souvenir selon le credo.
##
## Lot 3 (ombres et Légende) : opérations d'espionnage contre les héros (dossier, corruption,
## exfiltration, assassinat ; voir Espionage), l'héritier d'une dynastie devient un héros ("heir" : 1 ;
## sa loyauté reste Empire.heir_loyalty, gérée par Diplomacy), les héros d'un syndicat se louent
## ("for_hire", puis "lender" = empire qui le prête et "lend_until"), dossiers de héros par empire
## dans hero_meta[a]["files"] : [{"about", "day", "heroes": [{"name", "cls", "lvl", "post", "loy", "portrait"}]}].

const POSTS := ["fleet", "system", "council", "agent"]
const CLASSES := ["stratege", "intendant", "orateur", "ombre"]
const DAYS_PER_YEAR := 360


static func data() -> Dictionary:
	return GameData.heroes()


static func class_def(cls: String) -> Dictionary:
	return (data()["classes"] as Dictionary).get(cls, {})


static func trait_def(id: String) -> Dictionary:
	return (data()["traits"] as Dictionary).get(id, {})


static func post_label(post: String) -> String:
	return String((data()["posts"] as Dictionary).get(post, {}).get("label", post))


static func portrait_def(id: String) -> Dictionary:
	for p: Dictionary in data()["portraits"]:
		if String(p["id"]) == id:
			return p
	return {}


## « Héros », ou « Avatar » pour une ruche ou une conscience distribuée.
static func noun(state: GameState, empire_id: int, plural := false) -> String:
	var e := state.get_empire(empire_id)
	var avatar := e != null and (data().get("avatar_governments", []) as Array).has(String(e.faction().get("species", {}).get("gouvernement", "")))
	if avatar:
		return "Avatars" if plural else "Avatar"
	return "Héros"


## Talents de héros du peuple, lus dans ses couches d'espèce (data "talents") ; entiers additionnés.
static func talent(state: GameState, empire_id: int) -> Dictionary:
	var out := {}
	var e := state.get_empire(empire_id)
	if e == null:
		return out
	var f := e.faction()
	var sp: Dictionary = f.get("species", {})
	var table: Dictionary = data().get("talents", {})
	for layer in table:
		var v := String(f.get("registre", "")) if layer == "registre" else String(sp.get(layer, ""))
		var t: Dictionary = (table[layer] as Dictionary).get(v, {})
		for k in t:
			if k != "label" and k != "text":
				out[k] = int(out.get(k, 0)) + int(t[k])
	return out


## Talents à afficher : [[nom, texte], …].
static func talent_labels(state: GameState, empire_id: int) -> Array:
	var out := []
	var e := state.get_empire(empire_id)
	if e == null:
		return out
	var f := e.faction()
	var sp: Dictionary = f.get("species", {})
	var table: Dictionary = data().get("talents", {})
	for layer in table:
		var v := String(f.get("registre", "")) if layer == "registre" else String(sp.get(layer, ""))
		var t: Dictionary = (table[layer] as Dictionary).get(v, {})
		if not t.is_empty():
			out.append([String(t["label"]), String(t["text"])])
	return out


static func is_avatar(state: GameState, empire_id: int) -> bool:
	return int(talent(state, empire_id).get("avatar", 0)) > 0


## Réserve de traits du peuple, depuis ses couches (registre, archétype, gouvernement, credo).
static func people_traits(state: GameState, empire_id: int) -> Array[String]:
	var out: Array[String] = []
	var e := state.get_empire(empire_id)
	if e == null:
		return out
	var f := e.faction()
	var sp: Dictionary = f.get("species", {})
	var table: Dictionary = data().get("people_traits", {})
	for layer in ["registre", "archetype", "gouvernement", "credo"]:
		var v := String(f.get("registre", "")) if layer == "registre" else String(sp.get(layer, ""))
		for t in (table.get(layer, {}) as Dictionary).get(v, []):
			if not out.has(String(t)):
				out.append(String(t))
	return out


## Espérance de vie (années) d'un héros de ce peuple ; 0 = sans limite (synthétiques).
static func life_years(state: GameState, empire_id: int) -> int:
	var l: Dictionary = data()["life"]
	return int((l["archetype"] as Dictionary).get(_archetype_raw(state, empire_id), l["years"]))


static func _archetype_raw(state: GameState, empire_id: int) -> String:
	var e := state.get_empire(empire_id)
	return String(e.faction().get("species", {}).get("archetype", "humanoide")) if e else "humanoide"


static func ambition_def(id: String) -> Dictionary:
	return (data()["ambitions"] as Dictionary).get(id, {})


## Loyauté de départ : base, talent du peuple, traits.
static func base_loyalty(state: GameState, empire_id: int, h: Dictionary) -> int:
	return clampi(int(data()["loyalty"]["start"]) + int(talent(state, empire_id).get("loyalty", 0)) + trait_fx(h, "loyalty"), 0, 100)


# --- Création ----------------------------------------------------------------------------------

static func meta(state: GameState, empire_id: int) -> Dictionary:
	if not state.hero_meta.has(empire_id):
		state.hero_meta[empire_id] = {"renown": 0, "acts": {}, "got": 0, "offer": [], "memorials": [], "election": 0, "files": []}
	return state.hero_meta[empire_id]


static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "heros"] + parts))


static func _archetype(state: GameState, empire_id: int) -> String:
	var e := state.get_empire(empire_id)
	var a := String(e.faction().get("species", {}).get("archetype", "humanoide")) if e else "humanoide"
	return a if (data()["names"] as Dictionary).has(a) else "humanoide"


## Portraits de la galerie des héros pour un archétype (ceux des humanoïdes si aucun).
static func portraits_for(archetype: String) -> Array[String]:
	var out: Array[String] = []
	for p: Dictionary in data()["portraits"]:
		if (p.get("archetypes", []) as Array).has(archetype):
			out.append(String(p["id"]))
	if out.is_empty() and archetype != "humanoide":
		return portraits_for("humanoide")
	return out


## Un candidat tiré par hachage : nom, portrait, âge, classe et un premier trait de sa classe.
static func make_candidate(state: GameState, empire_id: int, cls: String, salt: Array) -> Dictionary:
	var arch := _archetype(state, empire_id)
	var names: Dictionary = data()["names"][arch]
	var first: Array = names["first"]
	var last: Array = names["last"]
	var pics := portraits_for(arch)
	var ages: Array = data()["age"]
	var age := int(ages[0]) + _h(state, salt + ["age"]) % (int(ages[1]) - int(ages[0]) + 1)
	var pool := class_traits(cls)
	var traits: Array[String] = []
	if not pool.is_empty():
		traits.append(pool[_h(state, salt + ["trait"]) % pool.size()])
	var ambs := (data()["ambitions"] as Dictionary).keys()
	ambs.sort()
	return {
		"amb": "" if is_avatar(state, empire_id) else String(ambs[_h(state, salt + ["amb"]) % ambs.size()]),
		"name": "%s %s" % [first[_h(state, salt + ["first"]) % first.size()], last[_h(state, salt + ["last"]) % last.size()]],
		"portrait": pics[_h(state, salt + ["pic"]) % pics.size()] if not pics.is_empty() else "",
		"cls": cls,
		"age": age,
		"traits": traits,
	}


## Traits que peut tirer un héros de cette classe (ceux de la classe, puis ceux de toutes les classes).
static func class_traits(cls: String) -> Array[String]:
	var out: Array[String] = []
	var ids := (data()["traits"] as Dictionary).keys()
	ids.sort()
	for id in ids:
		var c := String(data()["traits"][id].get("cls", ""))
		var td: Dictionary = data()["traits"][id]
		if td.get("earned", false):
			continue  # gagné par un exploit, jamais tiré au sort
		if c == cls or (c == "" and not td.get("people", false) and not td.get("flaw", false)):
			out.append(String(id))
	return out


## Fait entrer un candidat dans l'empire (renvoie l'identifiant du héros).
static func recruit(state: GameState, empire_id: int, cand: Dictionary) -> int:
	var id := state.next_hero_id
	state.next_hero_id += 1
	var traits: Array = []
	for t in cand.get("traits", []):
		traits.append(String(t))
	state.heroes[id] = {
		"id": id, "owner": empire_id, "name": String(cand["name"]), "portrait": String(cand["portrait"]),
		"cls": String(cand["cls"]), "lvl": 1, "xp": 0, "traits": traits,
		"born": state.tick - int(cand.get("age", 30)) * DAYS_PER_YEAR,
		"post": "", "target": -1, "arrive": 0, "wound": 0, "joined": state.tick,
		"amb": String(cand.get("amb", "")), "served": state.tick, "amb_n": 0, "amb_done": 0,
		"foe": -1, "jailer": -1, "convert": 0, "life": life_years(state, empire_id),
	}
	state.heroes[id]["loy"] = base_loyalty(state, empire_id, state.heroes[id])
	meta(state, empire_id)["got"] = int(meta(state, empire_id)["got"]) + 1
	return id


## Héros de départ de chaque empire (création de partie).
static func setup(state: GameState) -> void:
	for e in state.empires:
		var cls: String = CLASSES[_h(state, ["start", e.id]) % CLASSES.size()]
		recruit(state, e.id, make_candidate(state, e.id, cls, ["start", e.id]))
		ensure_heir(state, e)


# --- Héritier (dynastie Ossarane) ---------------------------------------------------------------

## Au moins un héros vivant, libre et à soi (pas loué) : condition de la Légende.
static func has_free_hero(state: GameState, empire_id: int) -> bool:
	for id in ids_of(state, empire_id):
		var h: Dictionary = state.heroes[id]
		if not is_prisoner(h) and int(h.get("lender", -1)) < 0:
			return true
	return false


static func heir_of(state: GameState, empire_id: int) -> Dictionary:
	for id in ids_of(state, empire_id):
		if int(state.heroes[id].get("heir", 0)) > 0:
			return state.heroes[id]
	return {}


## Une dynastie a toujours son héritier parmi ses héros (une place à part) : s'il meurt, un autre
## prend son rang, et la loyauté de la lignée repart de sa valeur de départ.
static func ensure_heir(state: GameState, e: Empire) -> void:
	if e.eliminated or not Diplomacy.has_heir(state, e.id) or not heir_of(state, e.id).is_empty():
		return
	var gen := int(meta(state, e.id).get("heirs", 0))
	meta(state, e.id)["heirs"] = gen + 1
	var cls: String = CLASSES[_h(state, ["heir", e.id, gen]) % CLASSES.size()]
	var cand := make_candidate(state, e.id, cls, ["heir", e.id, gen])
	cand["amb"] = ""
	cand["age"] = 22
	var id := recruit(state, e.id, cand)
	meta(state, e.id)["got"] = int(meta(state, e.id)["got"]) - 1  # l'héritier ne compte pas pour le renom
	var h: Dictionary = state.heroes[id]
	h["heir"] = 1
	h["name"] = "%s, l'Héritier" % String(h["name"]).split(" ")[0]
	if gen > 0:
		e.heir_loyalty = int(Diplomacy.ability("heir")["start"])
		state.add_chronicle("%s prend le rang d'héritier de %s. On lui a déjà fait essayer la couronne, pour voir." % [h["name"], e.display_name()],
				Espionage.private_to(state, [e.id]))


# --- Lecture -----------------------------------------------------------------------------------

## Identifiants des héros d'un empire (tous si empire_id < 0), triés.
static func ids_of(state: GameState, empire_id: int) -> Array[int]:
	var ids := state.heroes.keys()
	ids.sort()
	var out: Array[int] = []
	for id in ids:
		if empire_id < 0 or int(state.heroes[id]["owner"]) == empire_id:
			out.append(int(id))
	return out


static func get_hero(state: GameState, id: int) -> Dictionary:
	return state.heroes.get(id, {})


static func cap(state: GameState, empire_id: int) -> int:
	var n := int(data()["cap"]) + Research.fx_int(state, empire_id, "hero_cap") + int(talent(state, empire_id).get("cap", 0))
	return n + (1 if not heir_of(state, empire_id).is_empty() else 0)


static func seats(state: GameState, empire_id: int) -> int:
	return int(data()["council_seats"]) + Research.fx_int(state, empire_id, "council_seats") + int(talent(state, empire_id).get("seats", 0))


static func age(state: GameState, h: Dictionary) -> int:
	@warning_ignore("integer_division")
	return (state.tick - int(h["born"])) / DAYS_PER_YEAR


static func is_wounded(state: GameState, h: Dictionary) -> bool:
	return int(h.get("wound", 0)) > state.tick


## Le héros tient son poste (affecté, arrivé, valide).
static func active(state: GameState, h: Dictionary) -> bool:
	return String(h["post"]) != "" and int(h["arrive"]) <= state.tick and not is_wounded(state, h) and int(h.get("jailer", -1)) < 0


static func is_prisoner(h: Dictionary) -> bool:
	return int(h.get("jailer", -1)) >= 0


static func renown_needed(state: GameState, empire_id: int) -> int:
	var r: Dictionary = data()["renown"]
	return int(r["base"]) + int(r["step"]) * int(meta(state, empire_id)["got"])


## Niveau effectif sur un poste, en demi-niveaux : 2 × niveau pour la classe qui en a l'habitude,
## niveau seul pour les autres (moitié d'effet).
static func half_levels(h: Dictionary, post: String) -> int:
	var own := String(class_def(String(h["cls"])).get("post", "")) == post
	if own:
		return int(h["lvl"]) * 2
	@warning_ignore("integer_division")
	return int(h["lvl"]) * 3 / 2 if trait_fx(h, "versatile") > 0 else int(h["lvl"])


## Somme d'un effet de trait (entier) pour un héros.
static func trait_fx(h: Dictionary, key: String) -> int:
	var n := 0
	for t in h.get("traits", []):
		n += int(trait_def(String(t)).get("fx", {}).get(key, 0))
	return n


static func trait_fx_sub(h: Dictionary, key: String, sub: String) -> int:
	var n := 0
	for t in h.get("traits", []):
		n += int((trait_def(String(t)).get("fx", {}).get(key, {}) as Dictionary).get(sub, 0))
	return n


## Héros actif à un poste donné (cible), {} sinon.
static func at_post(state: GameState, post: String, target: int, owner := -1) -> Dictionary:
	for id in ids_of(state, owner):
		var h: Dictionary = state.heroes[id]
		if String(h["post"]) == post and int(h["target"]) == target and active(state, h):
			return h
	return {}


## Héros affecté (même en route) à un poste, {} sinon.
static func assigned_to(state: GameState, post: String, target: int, owner := -1) -> Dictionary:
	for id in ids_of(state, owner):
		var h: Dictionary = state.heroes[id]
		if String(h["post"]) == post and int(h["target"]) == target:
			return h
	return {}


static func council(state: GameState, empire_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in ids_of(state, empire_id):
		var h: Dictionary = state.heroes[id]
		if String(h["post"]) == "council" and active(state, h):
			out.append(h)
	return out


static func _council_sum(state: GameState, empire_id: int, key: String) -> int:
	var per: Dictionary = data()["per_level"]["council"]
	var n := 0
	for h in council(state, empire_id):
		var v := int((per.get(String(h["cls"]), {}) as Dictionary).get(key, 0))
		if v == 0:
			continue
		# Chef de courant (voir Laws) : bonus de Conseil plus fort si son courant gouverne.
		if state.politics_on:
			@warning_ignore("integer_division")
			v = v * (100 + Laws.council_pct(state, h)) / 100
		@warning_ignore("integer_division")
		n += v * half_levels(h, "council") / 2
	return n


# --- Effets ------------------------------------------------------------------------------------

## Bonus de dégâts (%) d'une flotte : son amiral, ses traits, et les Stratèges du conseil.
static func damage_pct(state: GameState, f: Fleet, day: int, home: bool) -> int:
	var pct := _council_sum(state, f.owner, "damage_pct") + memorial_fx(state, f.owner, "damage_pct")
	var h := at_post(state, "fleet", f.id, f.owner)
	if not h.is_empty():
		@warning_ignore("integer_division")
		pct += int(data()["per_level"]["fleet_damage_pct"]) * half_levels(h, "fleet") / 2
		pct += trait_fx(h, "damage_pct")
		if day == 1:
			pct += trait_fx(h, "first_day_pct")
		if home:
			pct += trait_fx(h, "home_damage_pct")
	return pct


## Bonus de production (%) d'une ressource pour une colonie : gouverneur du système (et ses traits),
## Intendants du conseil.
static func production_pct(state: GameState, owner: int, system_id: int, resource: String) -> int:
	if state.heroes.is_empty():
		return 0
	var all := production_pcts(state, owner, system_id)
	return int(all.get(resource, all["*"]))


## Les mêmes bonus pour toutes les ressources d'un coup : "*" pour toutes, plus une entrée par
## ressource que favorise un trait du gouverneur (un seul parcours des héros par colonie).
static func production_pcts(state: GameState, owner: int, system_id: int) -> Dictionary:
	var pct := _council_sum(state, owner, "prod_pct") + memorial_fx(state, owner, "prod_pct")
	var out := {}
	var h := at_post(state, "system", system_id, owner)
	if not h.is_empty():
		@warning_ignore("integer_division")
		pct += int(data()["per_level"]["system_prod_pct"]) * half_levels(h, "system") / 2
		for t in h.get("traits", []):
			var rp: Dictionary = trait_def(String(t)).get("fx", {}).get("res_pct", {})
			for r in rp:
				out[r] = int(out.get(r, pct)) + int(rp[r])
	out["*"] = pct
	return out


## Revenu mensuel des héros : Orateurs du conseil, traits « quel que soit son poste » (héros affectés).
static func income(state: GameState, empire_id: int) -> Dictionary:
	var out := {}
	var inf := _council_sum(state, empire_id, "influence")
	if inf != 0:
		out["influence"] = inf
	for m: Dictionary in meta(state, empire_id).get("memorials", []):
		if int(m["until"]) > state.tick:
			var inc0: Dictionary = (data()["memorial"]["credo"] as Dictionary).get(String(m["credo"]), {}).get("fx", {}).get("income", {})
			for r in inc0:
				out[r] = int(out.get(r, 0)) + int(inc0[r])
	for id in ids_of(state, empire_id):
		var h: Dictionary = state.heroes[id]
		if not active(state, h):
			continue
		for t in h.get("traits", []):
			var inc: Dictionary = trait_def(String(t)).get("fx", {}).get("income", {})
			for r in inc:
				out[r] = int(out.get(r, 0)) + int(inc[r])
	# Location des héros d'un syndicat : le client paie, le prêteur encaisse.
	for id in ids_of(state, -1):
		var h: Dictionary = state.heroes[id]
		var lender := int(h.get("lender", -1))
		if lender < 0:
			continue
		var fee := hire_fee(h)
		if int(h["owner"]) == empire_id:
			out["energy"] = int(out.get("energy", 0)) - fee
		elif lender == empire_id:
			out["energy"] = int(out.get("energy", 0)) + fee
	return out


## Chiffrement en plus (Ombres du conseil) : un point par tranche de deux niveaux, arrondi au-dessus.
static func encryption(state: GameState, empire_id: int) -> int:
	var n := 0
	for h in council(state, empire_id):
		if String(h["cls"]) == "ombre" or int((data()["per_level"]["council"].get(String(h["cls"]), {}) as Dictionary).get("encryption_half", 0)) > 0:
			@warning_ignore("integer_division")
			n += (half_levels(h, "council") + 1) / 2
	return n


## Agent du réseau de a chez b (actif), {} sinon.
static func agent(state: GameState, a: int, b: int) -> Dictionary:
	return at_post(state, "agent", b, a)


static func agent_growth(state: GameState, a: int, b: int) -> int:
	var h := agent(state, a, b)
	if h.is_empty():
		return 0
	@warning_ignore("integer_division")
	return int(data()["per_level"]["agent_growth"]) * half_levels(h, "agent") / 2 + trait_fx(h, "growth")


static func agent_chance(state: GameState, a: int, b: int) -> int:
	var h := agent(state, a, b)
	if h.is_empty():
		return 0
	@warning_ignore("integer_division")
	return int(data()["per_level"]["agent_chance"]) * half_levels(h, "agent") / 2 + trait_fx(h, "op_chance")


static func agent_discovery(state: GameState, a: int, b: int) -> int:
	var h := agent(state, a, b)
	return 0 if h.is_empty() else trait_fx(h, "discovery")


## Texte court de l'effet d'un héros à son poste (fiche, infobulles).
static func post_effect_text(state: GameState, h: Dictionary) -> String:
	var post := String(h["post"])
	if post == "":
		return "Sans affectation."
	var hl := half_levels(h, post)
	var per: Dictionary = data()["per_level"]
	var txt: String = data()["posts"][post]["text"]
	match post:
		"fleet":
			@warning_ignore("integer_division")
			return txt % (int(per["fleet_damage_pct"]) * hl / 2)
		"system":
			@warning_ignore("integer_division")
			return txt % (int(per["system_prod_pct"]) * hl / 2)
		"agent":
			@warning_ignore("integer_division")
			return txt % [int(per["agent_growth"]) * hl / 2, int(per["agent_chance"]) * hl / 2]
		"council":
			var c: Dictionary = per["council"].get(String(h["cls"]), {})
			var v := 0
			for k in c:
				if k != "text":
					v = int(c[k])
			@warning_ignore("integer_division")
			var amount := (hl + 1) / 2 if c.has("encryption_half") else v * hl / 2
			return String(c.get("text", "")) % amount
	return ""


# --- Renom et offres ---------------------------------------------------------------------------

## Un acte de l'empire (clé de data "acts", ou statistique de Research.count_stat) fait monter son renom.
static func act(state: GameState, empire_id: int, kind: String, n := 1) -> void:
	Politics.on_act(state, empire_id, kind, n)
	var a: Dictionary = (data()["acts"] as Dictionary).get(kind, {})
	if a.is_empty() or state.get_empire(empire_id) == null or state.heroes.is_empty() and state.hero_meta.is_empty():
		return
	var pts := int(a["renown"]) * n
	var bonus_key := "renown_battle_pct" if kind == "battles_won" else ("renown_treaty_pct" if kind == "treaty" else "")
	if bonus_key != "":
		var best := 0
		for id in ids_of(state, empire_id):
			if active(state, state.heroes[id]):
				best = maxi(best, trait_fx(state.heroes[id], bonus_key))
		@warning_ignore("integer_division")
		pts = pts * (100 + best) / 100
	var m := meta(state, empire_id)
	m["renown"] = int(m["renown"]) + pts
	var cls := String(a["cls"])
	var acts: Dictionary = m["acts"]
	acts[cls] = int(acts.get(cls, 0)) + pts
	_serve(state, empire_id, kind, n)


## Les actes de l'empire servent l'ambition de ses héros (libres) : loyauté entretenue, et au grand
## objectif, une récompense unique.
static func _serve(state: GameState, empire_id: int, kind: String, n: int) -> void:
	for id in ids_of(state, empire_id):
		var h: Dictionary = state.heroes[id]
		var ad := ambition_def(String(h.get("amb", "")))
		if ad.is_empty() or is_prisoner(h) or not (ad["acts"] as Array).has(kind):
			continue
		h["served"] = state.tick
		h["amb_n"] = int(h.get("amb_n", 0)) + n
		if int(h.get("amb_done", 0)) == 0 and int(h["amb_n"]) >= int(ad["grand"]):
			h["amb_done"] = 1
			var rw: Dictionary = data()["grand_reward"]
			h["loy"] = mini(100, int(h.get("loy", 50)) + int(rw["loyalty"]))
			var m := meta(state, empire_id)
			m["renown"] = int(m["renown"]) + int(rw["renown"])
			state.add_chronicle("%s a vu son ambition comblée (%s) : %s ne jure plus que par %s." % [h["name"], String(ad["grand_text"]),
					h["name"], state.get_empire(empire_id).short_name()], Espionage.private_to(state, [empire_id]))


## Somme d'un effet des souvenirs encore vivants d'un empire (héros morts de niveau min_lvl).
static func memorial_fx(state: GameState, empire_id: int, key: String) -> int:
	var m: Dictionary = state.hero_meta.get(empire_id, {})
	var n := 0
	for x: Dictionary in m.get("memorials", []):
		if int(x["until"]) > state.tick:
			n += int((data()["memorial"]["credo"] as Dictionary).get(String(x["credo"]), {}).get("fx", {}).get(key, 0))
	return n


## Prépare une offre « 1 parmi 3 » si le renom atteint le seuil et qu'aucune offre n'attend.
static func _maybe_offer(state: GameState, empire_id: int) -> bool:
	var m := meta(state, empire_id)
	if not (m["offer"] as Array).is_empty() or int(m["renown"]) < renown_needed(state, empire_id):
		return false
	# Vaincus du Conclave des Phares (voir Quests) : plus d'offre de héros pendant un temps.
	if Quests.blocks_offers(state, empire_id):
		return false
	m["renown"] = int(m["renown"]) - renown_needed(state, empire_id)
	var acts: Dictionary = m["acts"]
	var weights := {}
	for c in CLASSES:
		weights[c] = int(data()["class_base_weight"]) + int(acts.get(c, 0))
	var offer := []
	var got := int(m["got"])
	for i in int(data()["offer_size"]):
		var total := 0
		for c in CLASSES:
			total += int(weights[c])
		if total <= 0:
			break
		var roll := _h(state, ["offer", empire_id, got, i]) % total
		var pick := CLASSES[0]
		for c in CLASSES:
			roll -= int(weights[c])
			if roll < 0:
				pick = c
				break
		weights[pick] = 0  # trois classes différentes tant que possible
		offer.append(make_candidate(state, empire_id, pick, ["offer", empire_id, got, i]))
	m["offer"] = offer
	m["acts"] = {}
	return true


static func check_pick(state: GameState, player: int, index: int) -> String:
	var e := state.get_empire(player)
	if e == null or e.eliminated:
		return "empire inconnu"
	var offer: Array = meta(state, player)["offer"]
	if offer.is_empty():
		return "aucune offre"
	if index < -1 or index >= offer.size():
		return "candidat inconnu"
	if index >= 0 and ids_of(state, player).size() >= cap(state, player):
		return "plus de place : renvoyez d'abord un %s" % noun(state, player).to_lower()
	return ""


## Choisit le candidat index de l'offre (-1 : décline l'offre).
static func pick(state: GameState, player: int, index: int) -> void:
	var m := meta(state, player)
	var offer: Array = m["offer"]
	m["offer"] = []
	if index < 0:
		return
	var id := recruit(state, player, offer[index])
	var h: Dictionary = state.heroes[id]
	state.add_chronicle("%s accueille %s, %s : %s." % [state.get_empire(player).display_name(), h["name"],
			String(class_def(String(h["cls"]))["label"]).to_lower(), _flavor(h)], Espionage.private_to(state, [player]))


static func _flavor(h: Dictionary) -> String:
	match String(h["cls"]):
		"stratege":
			return "on dit qu'il a déjà gagné trois batailles, dont deux contre lui-même aux échecs"
		"intendant":
			return "ses registres sont si bien tenus qu'ils servent de manuel"
		"orateur":
			return "ses discours durent moins d'une heure, ce qui est déjà un exploit"
		"ombre":
			return "personne ne se souvient de l'avoir vu arriver"
	return "la galaxie retient son souffle"


# --- Affectation -------------------------------------------------------------------------------

static func _capital_system(state: GameState, empire_id: int) -> int:
	var e := state.get_empire(empire_id)
	if e == null or e.capital_planet < 0:
		return -1
	var p := state.galaxy.get_planet(e.capital_planet)
	return p.system_id if p else -1


static func check_assign(state: GameState, player: int, hero_id: int, post: String, target: int) -> String:
	var h := get_hero(state, hero_id)
	if h.is_empty() or int(h["owner"]) != player:
		return "héros inconnu"
	if is_prisoner(h):
		return "prisonnier de %s" % state.get_empire(int(h["jailer"])).short_name()
	if is_wounded(state, h):
		return "blessé"
	if post == "":
		return ""
	if not POSTS.has(post):
		return "poste inconnu"
	var other := assigned_to(state, post, target, player)
	if not other.is_empty() and int(other["id"]) != hero_id:
		return "poste déjà tenu par %s" % other["name"]
	match post:
		"fleet":
			var f: Fleet = state.fleets.get(target)
			if f == null or f.owner != player:
				return "flotte inconnue"
		"system":
			if state.galaxy.get_system(target) == null or state.system_owner(target) != player:
				return "système hors de l'empire"
		"council":
			if target < 0 or target >= seats(state, player):
				return "siège inconnu"
		"agent":
			if target == player or Espionage.cells_on(state, player, target) <= 0:
				return "aucun réseau chez cet empire"
	return ""


## Affecte un héros (post "" : le rappelle). Le trajet dépend du poste.
static func assign(state: GameState, player: int, hero_id: int, post: String, target: int) -> void:
	var h: Dictionary = state.heroes[hero_id]
	if String(h["post"]) == post and int(h["target"]) == target:
		return
	h["post"] = post
	h["target"] = target if post != "" else -1
	h["arrive"] = state.tick + _travel(state, player, post, target)


static func _travel(state: GameState, player: int, post: String, target: int) -> int:
	var days := int(data()["travel_days"])
	match post:
		"", "council":
			return 0
		"fleet":
			var f: Fleet = state.fleets.get(target)
			return 0 if f != null and f.system_id == _capital_system(state, player) else days
		"system":
			return 0 if target == _capital_system(state, player) else days
	return days


static func check_dismiss(state: GameState, player: int, hero_id: int) -> String:
	var h := get_hero(state, hero_id)
	if h.is_empty() or int(h["owner"]) != player:
		return "héros inconnu"
	if is_prisoner(h):
		return "prisonnier : il faut d'abord le libérer"
	if int(h.get("heir", 0)) > 0:
		return "on ne renvoie pas l'héritier de la lignée"
	if int(h.get("lender", -1)) >= 0:
		return "héros loué : il rentrera chez son syndicat au terme du contrat"
	return ""


static func dismiss(state: GameState, player: int, hero_id: int) -> void:
	var h: Dictionary = state.heroes[hero_id]
	state.heroes.erase(hero_id)
	state.add_chronicle("%s quitte le service de %s avec une pension et quelques rancunes." % [h["name"], state.get_empire(player).display_name()],
			Espionage.private_to(state, [player]))


## Deux flottes fusionnent : l'amiral de la flotte absorbée passe sur l'autre si elle n'en a pas.
static func on_merge(state: GameState, from_id: int, into_id: int) -> void:
	for id in ids_of(state, -1):
		var h: Dictionary = state.heroes[id]
		if String(h["post"]) == "fleet" and int(h["target"]) == from_id:
			if assigned_to(state, "fleet", into_id, int(h["owner"])).is_empty():
				h["target"] = into_id
			else:
				h["post"] = ""
				h["target"] = -1


# --- Expérience --------------------------------------------------------------------------------

static func gain_xp(state: GameState, h: Dictionary, n: int) -> void:
	if n <= 0:
		return
	@warning_ignore("integer_division")
	h["xp"] = int(h["xp"]) + n * (100 + trait_fx(h, "xp_pct")) / 100
	var levels: Array = data()["xp_levels"]
	while int(h["lvl"]) < levels.size() and int(h["xp"]) >= int(levels[int(h["lvl"])]):
		h["lvl"] = int(h["lvl"]) + 1
		var got := ""
		var free := _free_traits(state, h, posmod(int(h["lvl"]), 2) == 0)
		if (h["traits"] as Array).size() < int(data()["max_traits"]) and not free.is_empty():
			got = free[_h(state, ["lvl", int(h["id"]), int(h["lvl"])]) % free.size()]
			(h["traits"] as Array).append(got)
		var owner := int(h["owner"])
		state.add_chronicle("%s passe au niveau %d%s." % [h["name"], int(h["lvl"]),
				(" et gagne le trait « %s »" % trait_def(got)["label"]) if got != "" else ""], Espionage.private_to(state, [owner]))


## Traits qu'un héros peut encore gagner : ceux de son peuple (people) ou de sa classe, sinon l'autre réserve.
static func _free_traits(state: GameState, h: Dictionary, people: bool) -> Array[String]:
	var pools := [people_traits(state, int(h["owner"])), class_traits(String(h["cls"]))]
	if not people:
		pools.reverse()
	for pool: Array[String] in pools:
		var free: Array[String] = []
		for t in pool:
			if not (h["traits"] as Array).has(t):
				free.append(t)
		if not free.is_empty():
			return free
	return []


## Une bataille est finie : les amiraux du vainqueur gagnent de l'expérience.
static func on_battle(state: GameState, b: Dictionary, winner: int) -> void:
	if state.heroes.is_empty():
		return
	# Les héros des flottes engagées retiennent qui les a combattus (pour une capture éventuelle).
	var sides := {}
	for entry: Array in b.get("fleets", []):
		var f: Fleet = state.fleets.get(int(entry[0]))
		if f:
			sides[f.owner] = true
	for entry: Array in b.get("fleets", []):
		var h0 := assigned_to(state, "fleet", int(entry[0]))
		if h0.is_empty():
			continue
		var foe := winner if winner >= 0 and winner != int(h0["owner"]) else -1
		if foe < 0:
			for o in sides:
				if int(o) != int(h0["owner"]) and Combat.at_war(state, int(h0["owner"]), int(o)):
					foe = int(o)
					break
		if foe >= 0:
			h0["foe"] = foe
	if winner < 0:
		return
	for entry: Array in b.get("fleets", []):
		var h := at_post(state, "fleet", int(entry[0]), winner)
		if not h.is_empty():
			gain_xp(state, h, int(data()["xp"]["battle_won"]))


## Une colonie est fondée : le gouverneur de son système gagne de l'expérience.
static func on_colony(state: GameState, owner: int, system_id: int) -> void:
	act(state, owner, "colony")
	var h := at_post(state, "system", system_id, owner)
	if not h.is_empty():
		gain_xp(state, h, int(data()["xp"]["colony"]))


## Une opération réussie : l'agent du réseau gagne de l'expérience.
static func on_operation(state: GameState, a: int, b: int) -> void:
	var h := agent(state, a, b)
	if not h.is_empty():
		gain_xp(state, h, int(data()["xp"]["operation"]))


# --- Jour par jour ------------------------------------------------------------------------------

## Chaque jour : postes devenus impossibles (blessure, capture ou rappel) ; chaque mois : expérience,
## loyauté et désertion, conversion des prisonniers, vieillesse et défauts, élections, offres.
static func daily(state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state.heroes.is_empty() and state.hero_meta.is_empty():
		return out
	var monthly := posmod(state.tick, 30) == 0
	for id in ids_of(state, -1):
		if not state.heroes.has(id):
			continue
		var h: Dictionary = state.heroes[id]
		var owner := int(h["owner"])
		var e := state.get_empire(owner)
		if is_prisoner(h):
			if monthly:
				_prison_month(state, h, out)
			continue
		if e == null or e.eliminated:
			continue
		var post := String(h["post"])
		var target := int(h["target"])
		match post:
			"fleet":
				var f: Fleet = state.fleets.get(target)
				if f == null or f.owner != owner:
					_wound(state, h, out, "sa flotte a été anéantie", _fleet_captor(state, h))
				else:
					h["at"] = f.system_id
			"system":
				if state.system_owner(target) != owner:
					var captor := state.system_owner(target)
					_wound(state, h, out, "%s est tombé" % state.galaxy.systems[target].system_name,
							captor if captor >= 0 and Combat.at_war(state, owner, captor) else -1)
			"council":
				if target >= seats(state, owner):
					h["post"] = ""
					h["target"] = -1
			"agent":
				if Espionage.cells_on(state, owner, target) <= 0 or state.get_empire(target) == null or state.get_empire(target).eliminated:
					h["post"] = ""
					h["target"] = -1
		if not monthly or not state.heroes.has(id):
			continue
		if active(state, h):
			var xp := int(data()["xp"]["day"]) * 30
			if String(h["post"]) == "system":
				var pop := 0
				for pid in state.sorted_colony_ids():
					var c: Colony = state.colonies[pid]
					if c.owner == owner and c.is_colony() and state.galaxy.get_planet(pid).system_id == int(h["target"]):
						pop += c.population
				@warning_ignore("integer_division")
				xp += pop / maxi(1, int(data()["xp"]["pop_month_div"]))
			gain_xp(state, h, xp)
		if _age_month(state, h, out):
			continue
		_loyalty_month(state, h, out)
	if monthly:
		for e in state.empires:
			if e.eliminated:
				continue
			_election(state, e, out)
			ensure_heir(state, e)
	if monthly:
		_hire_month(state, out)
	if monthly:
		for e in state.empires:
			if e.eliminated:
				continue
			if _maybe_offer(state, e.id) and not e.is_ai():
				out.append(state.add_chronicle("Le renom de %s attire des candidats : trois %s se présentent (écran Panthéon)." % [e.display_name(), noun(state, e.id, true).to_lower()],
						[e.id]))
	return out


## Qui capture l'amiral d'une flotte anéantie : son dernier adversaire en bataille s'il est toujours en
## guerre, sinon l'ennemi qui a le plus de vaisseaux dans le système où la flotte se trouvait.
static func _fleet_captor(state: GameState, h: Dictionary) -> int:
	var owner := int(h["owner"])
	var foe := int(h.get("foe", -1))
	if foe >= 0 and Combat.at_war(state, owner, foe):
		return foe
	var at := int(h.get("at", -1))
	if at < 0:
		return -1
	var best := -1
	var most := 0
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.system_id == at and f.owner != owner and Combat.at_war(state, owner, f.owner) and f.ships.size() > most:
			most = f.ships.size()
			best = f.owner
	return best


static func _wound(state: GameState, h: Dictionary, out: Array[Dictionary], why: String, captor := -1) -> void:
	var owner := int(h["owner"])
	h["post"] = ""
	h["target"] = -1
	h["foe"] = -1
	if captor == GameState.FAUNA_ID:
		captor = -1  # les bêtes ne font pas de prisonniers
	# Capture : chance de base, traits, jamais un Avatar.
	if captor >= 0 and captor != owner and not is_avatar(state, owner):
		var pct := int(data()["capture"]["pct"]) + trait_fx(h, "capture_pct")
		if pct > 0 and _h(state, ["capture", int(h["id"]), state.tick]) % 100 < pct:
			h["jailer"] = captor
			h["convert"] = 0
			h["wound"] = 0
			Relics.on_hero_captured(state, h, captor)
			if GameState.is_npc(captor):
				h["ransom"] = state.tick + int(data()["capture"]["ransom"]["days"])
				out.append(state.add_chronicle("%s est capturé par %s : %s. Ils demandent une rançon (%s), payable dans les deux ans (écran Panthéon)." % [
						h["name"], state.get_empire(captor).display_name(), why, GameData.format_amounts(ransom_cost(h))], Espionage.private_to(state, [owner])))
				return
			out.append(state.add_chronicle("%s est capturé par %s : %s. Les geôliers ont déjà une cellule à sa taille." % [
					h["name"], state.get_empire(captor).display_name(), why], Espionage.public_to(state, [owner, captor])))
			return
	var days := int(data()["wound_days"])
	@warning_ignore("integer_division")
	days = days * maxi(10, 100 + trait_fx(h, "wound_pct")) / 100
	h["wound"] = state.tick + days
	out.append(state.add_chronicle("%s est blessé : %s. Il reprendra du service dans %d jours." % [h["name"], why, days],
			Espionage.private_to(state, [owner])))


# --- Loyauté et désertion ----------------------------------------------------------------------

## Loyauté du mois : une ambition servie récemment la nourrit, oubliée elle s'use (un héros sans poste
## s'ennuie aussi). Sous min_desert, il peut passer chez un rival qui a de la place, ou partir.
static func _loyalty_month(state: GameState, h: Dictionary, out: Array[Dictionary]) -> void:
	if String(h.get("amb", "")) == "" or int(h.get("lender", -1)) >= 0:
		return
	var cfg: Dictionary = data()["loyalty"]
	var owner := int(h["owner"])
	var loy := int(h.get("loy", 50))
	if state.tick - int(h.get("served", 0)) <= int(cfg["grace_days"]):
		loy += int(cfg["served_gain"])
	else:
		loy -= int(cfg["neglect_loss"])
	if String(h["post"]) == "" and not is_wounded(state, h):
		loy -= int(cfg["idle_loss"])
	# Au Conseil alors que son courant est dans l'opposition (voir Laws).
	if String(h["post"]) == "council" and Laws.hero_backing(state, h) < 0:
		loy -= int(Politics.data()["heroes"]["loyalty_out"])
	loy = clampi(loy, 0, mini(100, base_loyalty(state, owner, h) + 30))
	h["loy"] = loy
	if loy >= int(cfg["min_desert"]):
		return
	var pct := (int(cfg["min_desert"]) - loy) * int(cfg["desert_pct_per_point"])
	if _h(state, ["desert", int(h["id"]), state.tick]) % 100 >= pct:
		return
	var to := _suitor(state, owner, int(h.get("suitor", -1)))
	var e := state.get_empire(owner)
	if to >= 0:
		var name := String(h["name"])
		h["owner"] = to
		h["post"] = ""
		h["target"] = -1
		h["loy"] = int(cfg["defector_value"])
		h["served"] = state.tick
		out.append(state.add_chronicle("%s déserte %s et passe au service de %s. On dit qu'on lui avait promis davantage, et qu'on a tenu parole." % [
				name, e.display_name(), state.get_empire(to).display_name()], Espionage.public_to(state, [owner, to])))
	elif loy <= int(cfg["leave_at"]):
		state.heroes.erase(int(h["id"]))
		out.append(state.add_chronicle("%s quitte le service de %s sans un mot. Sa chaise reste vide, son ardoise aussi." % [h["name"], e.display_name()],
				Espionage.private_to(state, [owner])))


## Le rival qui courtise un héros mécontent : un empire rencontré, pas allié, qui a une place libre,
## et le plus de renom.
static func _suitor(state: GameState, owner: int, prefer := -1) -> int:
	var pe := state.get_empire(prefer)
	if pe != null and not pe.eliminated and prefer != owner and ids_of(state, prefer).size() < cap(state, prefer) and not is_avatar(state, prefer):
		return prefer
	var best := -1
	var most := -1
	for o in state.get_empire(owner).contacts:
		var oe := state.get_empire(int(o))
		if oe == null or oe.eliminated or Diplomacy.allied(state, owner, int(o)) or is_avatar(state, int(o)):
			continue
		if ids_of(state, int(o)).size() >= cap(state, int(o)):
			continue
		var r := int(meta(state, int(o))["renown"]) + int(meta(state, int(o))["got"]) * 1000
		if r > most:
			most = r
			best = int(o)
	return best


# --- Vieillesse et mort ------------------------------------------------------------------------

## Vieillesse du mois : défauts après from_age, mort possible à l'approche de l'espérance de vie.
## Renvoie vrai si le héros est mort.
static func _age_month(state: GameState, h: Dictionary, out: Array[Dictionary]) -> bool:
	var a := age(state, h)
	var fl: Dictionary = data()["flaws"]
	if a >= int(fl["from_age"]) and posmod(state.tick - int(h["born"]), DAYS_PER_YEAR) < 30:
		var have := 0
		for t in h["traits"]:
			if trait_def(String(t)).get("flaw", false):
				have += 1
		if have < int(fl["max"]) and _h(state, ["flaw", int(h["id"]), a]) % 100 < int(fl["pct"]):
			var ids := (data()["traits"] as Dictionary).keys()
			ids.sort()
			var free: Array[String] = []
			for t in ids:
				if trait_def(String(t)).get("flaw", false) and not (h["traits"] as Array).has(t):
					free.append(String(t))
			if not free.is_empty():
				var got := free[_h(state, ["flaw_pick", int(h["id"]), a]) % free.size()]
				(h["traits"] as Array).append(got)
				out.append(state.add_chronicle("%s prend de l'âge : %s." % [h["name"], String(trait_def(got)["label"]).to_lower()],
						Espionage.private_to(state, [int(h["owner"])])))
	var life := int(h.get("life", 0))
	if life <= 0:
		return false
	var from := life - int(data()["life"]["warn"])
	if a < from:
		return false
	# Chance mensuelle qui grandit chaque année au-delà du seuil (per_year_pct par an, divisé par 12).
	var per_mille := (a - from + 1) * int(data()["life"]["per_year_pct"]) * 10 / 12
	if _h(state, ["death", int(h["id"]), state.tick]) % 1000 >= per_mille:
		return false
	die(state, h, "s'éteint à %d ans, entouré de ses souvenirs et de quelques créanciers" % a, out)
	return true


## Un héros meurt : souvenir (niveau min_lvl ou plus, ou toujours chez les Saints), ferveur des Saints.
static func die(state: GameState, h: Dictionary, why: String, out: Array[Dictionary]) -> void:
	var owner := int(h.get("lender", -1)) if int(h.get("lender", -1)) >= 0 else int(h["owner"])
	h["owner"] = owner
	var e := state.get_empire(owner)
	state.heroes.erase(int(h["id"]))
	Relics.on_hero_gone(state, int(h["id"]))
	var tl := talent(state, owner)
	var mem: Dictionary = data()["memorial"]
	var credo := String(e.faction().get("species", {}).get("credo", "")) if e else ""
	var text := "%s %s." % [h["name"], why]
	if e and (int(h["lvl"]) >= int(mem["min_lvl"]) or int(tl.get("saint", 0)) > 0) and (mem["credo"] as Dictionary).has(credo):
		var m := meta(state, owner)
		if not m.has("memorials"):
			m["memorials"] = []
		(m["memorials"] as Array).append({"name": String(h["name"]), "until": state.tick + int(mem["years"]) * DAYS_PER_YEAR, "credo": credo})
		text += " Son souvenir reste : %s pendant %d ans." % [String(mem["credo"][credo]["text"]), int(mem["years"])]
	if e and int(tl.get("saint_fervor", 0)) > 0 and FactionTraits.has_fervor(e.faction()):
		e.fervor = mini(int(e.faction()["fervor"]["max"]), e.fervor + int(tl["saint_fervor"]))
		text += " Un saint de plus : la ferveur monte."
	out.append(state.add_chronicle(text, Espionage.private_to(state, [owner])))


# --- Prisonniers -------------------------------------------------------------------------------

## Mois en prison : conversion qui s'achève, geôlier ou maître disparu.
static func _prison_month(state: GameState, h: Dictionary, out: Array[Dictionary]) -> void:
	var jailer := int(h["jailer"])
	var owner := int(h["owner"])
	var je := state.get_empire(jailer)
	var oe := state.get_empire(owner)
	if je == null or je.eliminated:
		_free(state, h)
		return
	if GameState.is_npc(jailer):
		# Pirates et rebelles ne convertissent pas : ils attendent la rançon, puis s'impatientent.
		if oe == null or oe.eliminated or state.tick >= int(h.get("ransom", 0)):
			die(state, h, "est exécuté par %s : la rançon n'est jamais venue" % je.display_name(), out)
		return
	if (oe == null or oe.eliminated) and int(h.get("convert", 0)) == 0:
		h["convert"] = state.tick
	if int(h.get("convert", 0)) > 0 and int(h["convert"]) <= state.tick:
		if ids_of(state, jailer).size() >= cap(state, jailer):
			return  # pas de place : il attend
		h["owner"] = jailer
		h["jailer"] = -1
		h["convert"] = 0
		h["post"] = ""
		h["target"] = -1
		h["loy"] = int(data()["loyalty"]["convert_value"])
		h["served"] = state.tick
		out.append(state.add_chronicle("%s, longtemps prisonnier, prête serment à %s. On ne saura jamais si c'était la conviction ou l'ordinaire de la cantine." % [
				h["name"], je.display_name()], Espionage.public_to(state, [owner, jailer])))


static func _free(state: GameState, h: Dictionary) -> void:
	h["jailer"] = -1
	h["convert"] = 0
	h.erase("ransom")
	h["post"] = ""
	h["target"] = -1


## Prisonniers que tient un empire (identifiants triés).
static func prisoners_of(state: GameState, jailer: int) -> Array[int]:
	var out: Array[int] = []
	for id in ids_of(state, -1):
		if int(state.heroes[id].get("jailer", -1)) == jailer:
			out.append(id)
	return out


const PRISON_ACTIONS := ["free", "convert", "execute"]


static func check_prisoner(state: GameState, player: int, hero_id: int, action: String) -> String:
	var h := get_hero(state, hero_id)
	if h.is_empty() or int(h.get("jailer", -1)) != player:
		return "prisonnier inconnu"
	if not PRISON_ACTIONS.has(action):
		return "action inconnue"
	if action == "convert" and int(h.get("convert", 0)) > 0:
		return "conversion déjà en cours"
	return ""


## Le geôlier décide : libérer (souvenir reconnaissant), convertir (il rejoint nos rangs après
## convert_days, s'il y a de la place), exécuter (grief durable).
static func prisoner(state: GameState, player: int, hero_id: int, action: String) -> void:
	var h: Dictionary = state.heroes[hero_id]
	var owner := int(h["owner"])
	var je := state.get_empire(player)
	match action:
		"free":
			_free(state, h)
			Diplomacy.remember(state, owner, player, "hero_freed")
			state.add_chronicle("%s libère %s, qui rentre chez %s avec une lettre très polie." % [je.display_name(), h["name"], state.get_empire(owner).display_name()],
					Espionage.public_to(state, [owner, player]))
		"convert":
			h["convert"] = state.tick + int(data()["capture"]["convert_days"])
			state.add_chronicle("%s entreprend de rallier %s à sa cause : longues conversations, meilleurs repas." % [je.display_name(), h["name"]],
					Espionage.private_to(state, [player]))
		"execute":
			Diplomacy.remember(state, owner, player, "hero_executed")
			var out: Array[Dictionary] = []
			h["owner"] = owner
			die(state, h, "est exécuté sur ordre de %s. On ne lui pardonnera pas" % je.display_name(), out)


## Rançon d'un héros que retiennent les pirates ou les rebelles.
static func ransom_cost(h: Dictionary) -> Dictionary:
	var rd: Dictionary = data()["capture"]["ransom"]
	return {"energy": int(rd["energy"]) + int(rd["per_level"]) * int(h.get("lvl", 1))}


## Héros de l'empire que des pirates ou des rebelles retiennent contre rançon (identifiants triés).
static func held_for_ransom(state: GameState, empire_id: int) -> Array[int]:
	var out: Array[int] = []
	for id in ids_of(state, -1):
		var h: Dictionary = state.heroes[id]
		if int(h["owner"]) == empire_id and is_prisoner(h) and GameState.is_npc(int(h["jailer"])):
			out.append(id)
	return out


static func check_ransom(state: GameState, player: int, hero_id: int) -> String:
	var h := get_hero(state, hero_id)
	if h.is_empty() or int(h["owner"]) != player:
		return "héros inconnu"
	if not is_prisoner(h) or not GameState.is_npc(int(h["jailer"])):
		return "ce héros n'est pas retenu contre rançon"
	var e := state.get_empire(player)
	if e == null or e.eliminated:
		return "empire inconnu"
	if not Economy.can_afford(e, ransom_cost(h)):
		return "pas assez de ressources (%s)" % GameData.format_amounts(ransom_cost(h))
	return ""


static func ransom(state: GameState, player: int, hero_id: int) -> void:
	var h: Dictionary = state.heroes[hero_id]
	var je := state.get_empire(int(h["jailer"]))
	Economy.pay(state.get_empire(player), ransom_cost(h))
	_free(state, h)
	state.add_chronicle("%s paie la rançon de %s, que %s relâchent avec ses bottes, mais sans ses médailles." % [
			state.get_empire(player).display_name(), h["name"], je.display_name()], Espionage.private_to(state, [player]))


## Démanteler un repaire libère les héros de cet empire que les pirates retenaient. Renvoie leurs noms.
static func free_from_pirates(state: GameState, empire_id: int) -> Array[String]:
	var names: Array[String] = []
	for id in held_for_ransom(state, empire_id):
		var h: Dictionary = state.heroes[id]
		if int(h["jailer"]) == GameState.PIRATE_ID:
			_free(state, h)
			names.append(String(h["name"]))
	return names


## La paix rend les prisonniers que les deux empires se tiennent.
static func release_between(state: GameState, a: int, b: int) -> void:
	var n := 0
	for id in ids_of(state, -1):
		var h: Dictionary = state.heroes[id]
		var j := int(h.get("jailer", -1))
		if (j == a and int(h["owner"]) == b) or (j == b and int(h["owner"]) == a):
			_free(state, h)
			n += 1
	if n > 0:
		state.add_chronicle("La paix rend les prisonniers : %d %s rentrent chez eux." % [n, "héros" if n > 1 else "héros"], Espionage.public_to(state, [a, b]))


# --- Talents de peuple --------------------------------------------------------------------------

## République : le conseil est réélu tous les election_years ans ; ses membres rendent leur siège.
static func _election(state: GameState, e: Empire, out: Array[Dictionary]) -> void:
	var years := int(talent(state, e.id).get("election_years", 0))
	if years <= 0:
		return
	var m := meta(state, e.id)
	if state.tick - int(m.get("election", 0)) < years * DAYS_PER_YEAR:
		return
	m["election"] = state.tick
	var n := 0
	for h in council(state, e.id):
		h["post"] = ""
		h["target"] = -1
		n += 1
	if n > 0:
		out.append(state.add_chronicle("Élections chez %s : le conseil est renouvelé. Les sortants rendent leur siège, et leurs clés, en principe." % e.display_name(),
				Espionage.private_to(state, [e.id])))


## Horde : l'amiral d'une flotte qui pille gagne un trait (jusqu'à max_traits).
static func on_loot(state: GameState, empire_id: int, system_id: int) -> void:
	if int(talent(state, empire_id).get("loot_trait", 0)) <= 0:
		return
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.owner != empire_id or f.system_id != system_id:
			continue
		var h := at_post(state, "fleet", f.id, empire_id)
		if h.is_empty() or (h["traits"] as Array).size() >= int(data()["max_traits"]):
			continue
		var free := _free_traits(state, h, false)
		if free.is_empty():
			continue
		var got := free[_h(state, ["loot", int(h["id"]), state.tick]) % free.size()]
		(h["traits"] as Array).append(got)
		state.add_chronicle("Le champion %s revient du pillage avec un nouveau titre : %s." % [h["name"], String(trait_def(got)["label"]).to_lower()],
				Espionage.private_to(state, [empire_id]))


## Picaresque : chaque exploit nouveau rapporte du renom.
static func on_exploit(state: GameState, empire_id: int) -> void:
	var r := int(talent(state, empire_id).get("exploit_renown", 0))
	if r > 0 and not (state.heroes.is_empty() and state.hero_meta.is_empty()):
		var m := meta(state, empire_id)
		m["renown"] = int(m["renown"]) + r


# --- Ombres : opérations contre les héros ------------------------------------------------------

## Le héros qu'une opération vise chez b : le plus haut niveau (puis le plus ancien), libre ;
## corruptible : jamais un Avatar.
static func op_target(state: GameState, b: int, corruptible: bool) -> int:
	if corruptible and is_avatar(state, b):
		return -1
	var best := -1
	var lvl := -1
	for id in ids_of(state, b):
		var h: Dictionary = state.heroes[id]
		if is_prisoner(h) or int(h.get("lender", -1)) >= 0:
			continue
		if int(h["lvl"]) > lvl:
			lvl = int(h["lvl"])
			best = id
	return best


## Un héros de a que b retient prisonnier (le plus ancien), -1 sinon.
static func exfil_target(state: GameState, a: int, b: int) -> int:
	for id in ids_of(state, a):
		if int(state.heroes[id].get("jailer", -1)) == b:
			return id
	return -1


## Dossier des héros de b, tenu par a (fake : réseau retourné, b ne montre que des seconds couteaux).
static func write_file(state: GameState, a: int, b: int, fake: bool) -> void:
	var rows := []
	for id in ids_of(state, b):
		var h: Dictionary = state.heroes[id]
		if is_prisoner(h):
			continue
		rows.append({"name": String(h["name"]), "cls": String(h["cls"]), "lvl": 1 if fake else int(h["lvl"]),
				"post": "" if fake else String(h["post"]), "loy": 95 if fake else loyalty(state, h), "portrait": String(h["portrait"])})
	var m := meta(state, a)
	var files: Array = m.get("files", [])
	var kept := []
	for f: Dictionary in files:
		if int(f["about"]) != b:
			kept.append(f)
	kept.append({"about": b, "day": state.tick, "heroes": rows})
	m["files"] = kept


static func hero_file(state: GameState, a: int, b: int) -> Dictionary:
	for f: Dictionary in meta(state, a).get("files", []):
		if int(f["about"]) == b:
			return f
	return {}


## Loyauté affichée : celle de la lignée pour un héritier, sinon la sienne.
static func loyalty(state: GameState, h: Dictionary) -> int:
	if int(h.get("heir", 0)) > 0:
		return state.get_empire(int(h["owner"])).heir_loyalty
	return int(h.get("loy", 100))


static func corrupt(state: GameState, a: int, b: int, loss: int) -> String:
	var id := op_target(state, b, true)
	if id < 0:
		return "le héros visé n'est plus là. L'enveloppe reste cachetée."
	var h: Dictionary = state.heroes[id]
	if int(h.get("heir", 0)) > 0:
		var eb := state.get_empire(b)
		eb.heir_loyalty = maxi(0, eb.heir_loyalty - loss)
		eb.heir_suitor = a
	else:
		h["loy"] = maxi(0, int(h.get("loy", 50)) - loss)
		h["suitor"] = a
	return "%s accepte nos égards, et notre or (loyauté %d). S'il part, c'est chez nous qu'il viendra." % [h["name"], loyalty(state, h)]


static func exfiltrate(state: GameState, a: int, b: int) -> String:
	var id := exfil_target(state, a, b)
	if id < 0:
		return "la cellule était vide : il avait déjà été libéré."
	var h: Dictionary = state.heroes[id]
	_free(state, h)
	return "%s s'évade par les conduits d'aération et rentre au pays, un peu poussiéreux." % h["name"]


static func assassinate(state: GameState, a: int, b: int) -> String:
	var id := op_target(state, b, false)
	if id < 0:
		return "la cible avait changé de chambre. Le poison reste dans la carafe."
	var h: Dictionary = state.heroes[id]
	var name := String(h["name"])
	die(state, h, "meurt assassiné. On parle d'un empoisonnement, d'une chute, d'un « accident de chasse »", [] as Array[Dictionary])
	return "%s ne se relèvera pas. Les nôtres étaient déjà loin quand on a trouvé le corps." % name


## Sabotage d'un chantier : le gouverneur du système (s'il y en a un) est blessé dans l'explosion.
static func sabotage_governor(state: GameState, b: int, system_id: int) -> String:
	var h := at_post(state, "system", system_id, b)
	if h.is_empty():
		return ""
	var days := int(data()["wound_days"])
	@warning_ignore("integer_division")
	h["wound"] = state.tick + days * maxi(10, 100 + trait_fx(h, "wound_pct")) / 200
	h["post"] = ""
	h["target"] = -1
	return String(h["name"])


# --- Héros à louer (syndicat) ------------------------------------------------------------------

static func hire_fee(h: Dictionary) -> int:
	var c: Dictionary = data()["hire"]
	return int(c["fee_base"]) + int(c["fee_per_level"]) * int(h["lvl"])


static func check_for_hire(state: GameState, player: int, hero_id: int, on: bool) -> String:
	var h := get_hero(state, hero_id)
	if h.is_empty() or int(h["owner"]) != player:
		return "héros inconnu"
	if int(talent(state, player).get("hire", 0)) <= 0:
		return "seul un syndicat loue ses héros"
	if on:
		if is_prisoner(h) or int(h.get("heir", 0)) > 0 or int(h.get("lender", -1)) >= 0:
			return "ce héros ne peut pas être loué"
		if String(h["post"]) != "":
			return "rappelez-le d'abord de son poste"
	return ""


static func set_for_hire(state: GameState, player: int, hero_id: int, on: bool) -> void:
	state.heroes[hero_id]["for_hire"] = 1 if on else 0


## Héros à louer que client peut engager (syndicats rencontrés, pas en guerre avec lui).
static func for_hire(state: GameState, client: int) -> Array[int]:
	var out: Array[int] = []
	for id in ids_of(state, -1):
		var h: Dictionary = state.heroes[id]
		if int(h.get("for_hire", 0)) > 0 and check_hire(state, client, id) == "":
			out.append(id)
	return out


static func check_hire(state: GameState, client: int, hero_id: int) -> String:
	var h := get_hero(state, hero_id)
	var ec := state.get_empire(client)
	if h.is_empty() or ec == null or ec.eliminated:
		return "héros inconnu"
	var owner := int(h["owner"])
	if owner == client:
		return "c'est déjà le vôtre"
	if int(h.get("for_hire", 0)) <= 0 or String(h["post"]) != "" or is_prisoner(h) or int(h.get("lender", -1)) >= 0:
		return "ce héros n'est pas à louer"
	if not ec.contacts.has(owner):
		return "empire jamais rencontré"
	if Combat.at_war(state, client, owner):
		return "on ne loue pas un héros à un ennemi"
	if is_avatar(state, client):
		return "un esprit commun n'engage personne"
	if ids_of(state, client).size() >= cap(state, client):
		return "plus de place pour un héros"
	if int(ec.resources.get("energy", 0)) < hire_fee(h):
		return "pas assez d'énergie pour le premier mois (%d)" % hire_fee(h)
	return ""


## Le client engage le héros pour hire.days jours ; il rentre chez son syndicat au terme.
static func hire(state: GameState, client: int, hero_id: int) -> void:
	var h: Dictionary = state.heroes[hero_id]
	var owner := int(h["owner"])
	h["lender"] = owner
	h["owner"] = client
	h["for_hire"] = 0
	h["lend_until"] = state.tick + int(data()["hire"]["days"])
	h["post"] = ""
	h["target"] = -1
	state.add_chronicle("%s engage %s, héros de %s, pour %d énergie par mois. Le contrat tient en une page ; les clauses en petits caractères, en douze." % [
			state.get_empire(client).display_name(), h["name"], state.get_empire(owner).display_name(), hire_fee(h)],
			Espionage.public_to(state, [owner, client]))


## Fin des contrats de location : terme, guerre entre les deux, client disparu ou à sec.
static func _hire_month(state: GameState, out: Array[Dictionary]) -> void:
	for id in ids_of(state, -1):
		var h: Dictionary = state.heroes[id]
		var lender := int(h.get("lender", -1))
		if lender < 0:
			continue
		var client := int(h["owner"])
		var ec := state.get_empire(client)
		var el := state.get_empire(lender)
		var why := ""
		if el == null or el.eliminated:
			# Le syndicat a disparu : le héros reste chez son client.
			h["lender"] = -1
			continue
		if ec == null or ec.eliminated:
			why = "son client a disparu"
		elif Combat.at_war(state, client, lender):
			why = "la guerre rompt le contrat"
		elif int(ec.resources.get("energy", 0)) < 0:
			why = "le client ne paie plus"
		elif state.tick >= int(h.get("lend_until", 0)):
			why = "le contrat est arrivé à son terme"
			Diplomacy.remember(state, lender, client, "hero_hired")
		if why == "":
			continue
		h["owner"] = lender
		h["lender"] = -1
		h["post"] = ""
		h["target"] = -1
		h["served"] = state.tick
		if int(h.get("jailer", -1)) == lender:
			_free(state, h)
		out.append(state.add_chronicle("%s rentre chez %s : %s." % [h["name"], el.display_name(), why], Espionage.public_to(state, [lender, client])))


# --- Sauvegarde --------------------------------------------------------------------------------

static func to_list(state: GameState) -> Array:
	var out := []
	for id in ids_of(state, -1):
		out.append((state.heroes[id] as Dictionary).duplicate(true))
	return out


static func meta_to_list(state: GameState) -> Array:
	var ids := state.hero_meta.keys()
	ids.sort()
	var out := []
	for k in ids:
		var m: Dictionary = (state.hero_meta[k] as Dictionary).duplicate(true)
		m["empire"] = int(k)
		out.append(m)
	return out


static func from_lists(state: GameState, heroes: Array, metas: Array) -> void:
	for raw: Dictionary in heroes:
		var h: Dictionary = GameData._to_ints(raw)
		for k in ["name", "portrait", "cls", "post"]:
			h[k] = String(h.get(k, ""))
		var traits: Array = []
		for t in h.get("traits", []):
			traits.append(String(t))
		h["traits"] = traits
		# Sauvegarde 20 (lot 1) : les champs du lot 2 manquent ; ambition tirée par hachage.
		if not h.has("amb"):
			var ambs := (data()["ambitions"] as Dictionary).keys()
			ambs.sort()
			h["amb"] = "" if is_avatar(state, int(h["owner"])) else String(ambs[_h(state, ["amb_old", int(h["id"])]) % ambs.size()])
			h["served"] = state.tick
			h["amb_n"] = 0
			h["amb_done"] = 0
			h["foe"] = -1
			h["jailer"] = -1
			h["convert"] = 0
			h["life"] = life_years(state, int(h["owner"]))
			h["loy"] = base_loyalty(state, int(h["owner"]), h)
		h["amb"] = String(h["amb"])
		state.heroes[int(h["id"])] = h
	for raw: Dictionary in metas:
		var m: Dictionary = GameData._to_ints(raw)
		var e := int(m["empire"])
		m.erase("empire")
		var acts := {}
		for c in (m.get("acts", {}) as Dictionary):
			acts[String(c)] = int(m["acts"][c])
		m["acts"] = acts
		var offer := []
		for cand: Dictionary in m.get("offer", []):
			var c2 := cand.duplicate(true)
			for k in ["name", "portrait", "cls", "amb"]:
				c2[k] = String(c2.get(k, ""))
			var tr: Array[String] = []
			for t in c2.get("traits", []):
				tr.append(String(t))
			c2["traits"] = tr
			offer.append(c2)
		m["offer"] = offer
		var mems := []
		for x: Dictionary in m.get("memorials", []):
			mems.append({"name": String(x["name"]), "until": int(x["until"]), "credo": String(x["credo"])})
		m["memorials"] = mems
		m["election"] = int(m.get("election", 0))
		var files := []
		for f: Dictionary in m.get("files", []):
			var rows := []
			for r: Dictionary in f.get("heroes", []):
				rows.append({"name": String(r["name"]), "cls": String(r["cls"]), "lvl": int(r["lvl"]), "post": String(r["post"]),
						"loy": int(r["loy"]), "portrait": String(r["portrait"])})
			files.append({"about": int(f["about"]), "day": int(f["day"]), "heroes": rows})
		m["files"] = files
		state.hero_meta[e] = m
