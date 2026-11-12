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
## Par empire : state.hero_meta[empire] = {"renown", "acts": {classe: points}, "got", "offer": [candidats]}.

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


# --- Création ----------------------------------------------------------------------------------

static func meta(state: GameState, empire_id: int) -> Dictionary:
	if not state.hero_meta.has(empire_id):
		state.hero_meta[empire_id] = {"renown": 0, "acts": {}, "got": 0, "offer": []}
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
	return {
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
		if c == cls or c == "":
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
	}
	meta(state, empire_id)["got"] = int(meta(state, empire_id)["got"]) + 1
	return id


## Héros de départ de chaque empire (création de partie).
static func setup(state: GameState) -> void:
	for e in state.empires:
		var cls: String = CLASSES[_h(state, ["start", e.id]) % CLASSES.size()]
		recruit(state, e.id, make_candidate(state, e.id, cls, ["start", e.id]))


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
	return int(data()["cap"]) + Research.fx_int(state, empire_id, "hero_cap")


static func seats(state: GameState, empire_id: int) -> int:
	return int(data()["council_seats"]) + Research.fx_int(state, empire_id, "council_seats")


static func age(state: GameState, h: Dictionary) -> int:
	@warning_ignore("integer_division")
	return (state.tick - int(h["born"])) / DAYS_PER_YEAR


static func is_wounded(state: GameState, h: Dictionary) -> bool:
	return int(h.get("wound", 0)) > state.tick


## Le héros tient son poste (affecté, arrivé, valide).
static func active(state: GameState, h: Dictionary) -> bool:
	return String(h["post"]) != "" and int(h["arrive"]) <= state.tick and not is_wounded(state, h)


static func renown_needed(state: GameState, empire_id: int) -> int:
	var r: Dictionary = data()["renown"]
	return int(r["base"]) + int(r["step"]) * int(meta(state, empire_id)["got"])


## Niveau effectif sur un poste, en demi-niveaux : 2 × niveau pour la classe qui en a l'habitude,
## niveau seul pour les autres (moitié d'effet).
static func half_levels(h: Dictionary, post: String) -> int:
	var own := String(class_def(String(h["cls"])).get("post", "")) == post
	return int(h["lvl"]) * (2 if own else 1)


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
		@warning_ignore("integer_division")
		n += v * half_levels(h, "council") / 2
	return n


# --- Effets ------------------------------------------------------------------------------------

## Bonus de dégâts (%) d'une flotte : son amiral, ses traits, et les Stratèges du conseil.
static func damage_pct(state: GameState, f: Fleet, day: int, home: bool) -> int:
	var pct := _council_sum(state, f.owner, "damage_pct")
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
	var pct := _council_sum(state, owner, "prod_pct")
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
	for id in ids_of(state, empire_id):
		var h: Dictionary = state.heroes[id]
		if not active(state, h):
			continue
		for t in h.get("traits", []):
			var inc: Dictionary = trait_def(String(t)).get("fx", {}).get("income", {})
			for r in inc:
				out[r] = int(out.get(r, 0)) + int(inc[r])
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


## Prépare une offre « 1 parmi 3 » si le renom atteint le seuil et qu'aucune offre n'attend.
static func _maybe_offer(state: GameState, empire_id: int) -> bool:
	var m := meta(state, empire_id)
	if not (m["offer"] as Array).is_empty() or int(m["renown"]) < renown_needed(state, empire_id):
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
		var pool := class_traits(String(h["cls"]))
		var free: Array[String] = []
		for t in pool:
			if not (h["traits"] as Array).has(t):
				free.append(t)
		var got := ""
		if not free.is_empty():
			got = free[_h(state, ["lvl", int(h["id"]), int(h["lvl"])]) % free.size()]
			(h["traits"] as Array).append(got)
		var owner := int(h["owner"])
		state.add_chronicle("%s passe au niveau %d%s." % [h["name"], int(h["lvl"]),
				(" et gagne le trait « %s »" % trait_def(got)["label"]) if got != "" else ""], Espionage.private_to(state, [owner]))


## Une bataille est finie : les amiraux du vainqueur gagnent de l'expérience.
static func on_battle(state: GameState, b: Dictionary, winner: int) -> void:
	if winner < 0 or state.heroes.is_empty():
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

## Chaque jour : postes devenus impossibles (blessure ou rappel) ; chaque mois : expérience, offres.
static func daily(state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state.heroes.is_empty() and state.hero_meta.is_empty():
		return out
	var monthly := posmod(state.tick, 30) == 0
	for id in ids_of(state, -1):
		var h: Dictionary = state.heroes[id]
		var owner := int(h["owner"])
		var e := state.get_empire(owner)
		if e == null or e.eliminated:
			continue
		var post := String(h["post"])
		var target := int(h["target"])
		match post:
			"fleet":
				var f: Fleet = state.fleets.get(target)
				if f == null or f.owner != owner:
					_wound(state, h, out, "sa flotte a été anéantie")
			"system":
				if state.system_owner(target) != owner:
					_wound(state, h, out, "%s est tombé" % state.galaxy.systems[target].system_name)
			"council":
				if target >= seats(state, owner):
					h["post"] = ""
					h["target"] = -1
			"agent":
				if Espionage.cells_on(state, owner, target) <= 0 or state.get_empire(target) == null or state.get_empire(target).eliminated:
					h["post"] = ""
					h["target"] = -1
		if monthly and active(state, h):
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
	if monthly:
		for e in state.empires:
			if not e.eliminated and _maybe_offer(state, e.id) and not e.is_ai():
				out.append(state.add_chronicle("Le renom de %s attire des candidats : trois %s se présentent (écran Panthéon)." % [e.display_name(), noun(state, e.id, true).to_lower()],
						[e.id]))
	return out


static func _wound(state: GameState, h: Dictionary, out: Array[Dictionary], why: String) -> void:
	var owner := int(h["owner"])
	var days := int(data()["wound_days"])
	@warning_ignore("integer_division")
	days = days * maxi(10, 100 + trait_fx(h, "wound_pct")) / 100
	h["wound"] = state.tick + days
	h["post"] = ""
	h["target"] = -1
	out.append(state.add_chronicle("%s est blessé : %s. Il reprendra du service dans %d jours." % [h["name"], why, days],
			Espionage.private_to(state, [owner])))


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
			for k in ["name", "portrait", "cls"]:
				c2[k] = String(c2[k])
			var tr: Array[String] = []
			for t in c2.get("traits", []):
				tr.append(String(t))
			c2["traits"] = tr
			offer.append(c2)
		m["offer"] = offer
		state.hero_meta[e] = m
