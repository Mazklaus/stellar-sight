class_name HeroFall
extends RefCounted
## Mort des héros au combat (étude « Souverain et dynastie », bloc D, prop. 27-32 ; data/heroes.json
## "combat_death"). La mort s'insère avant la capture, au même endroit que la blessure :
## - flotte anéantie : 10 % ; flotte qui perd son plus gros vaisseau sans être anéantie : 3 % ;
## - système perdu (gouverneur) ou armée vaincue au sol (général) : 5 % ;
## multiplié par le réglage de la partie (Jamais 0 %, Rare 50 %, Normale 100 %, Brutale 200 %) et par
## les traits (combat_death_pct : Trompe-la-mort -50, Téméraire +100) ; Capsules de survie : 3 points de
## moins. Les Avatars (ruche, conscience) meurent ×1,5 mais l'esprit commun en reforme un 180 jours plus
## tard, un niveau plus bas ; un héros synthétique revient de sa sauvegarde (technologie hero_backup)
## un an plus tard, un niveau plus bas. Le vainqueur compte comme tueur (Martyr, Ancêtres, rancunes),
## le credo Honneur garde toujours un souvenir des morts au combat. Un héros de niveau 3 ou plus ouvre
## la fenêtre d'événement « … est tombé » et figure au rapport de bataille.
##
## État : state.hero_death = {"mode", "back": [{"hero": fiche, "day": jour de retour, "why": "avatar" |
## "backup"}], "notes": {"id d'événement": {"name", "text"}}} ; {} = option absente (tests) : aucune mort.

static func cfg() -> Dictionary:
	return Heroes.data().get("combat_death", {})


static func mode_defs() -> Array:
	return cfg().get("modes", [])


static func default_mode() -> String:
	return String(cfg().get("default", "normale"))


static func mode_def(id: String) -> Dictionary:
	for m: Dictionary in mode_defs():
		if String(m["id"]) == id:
			return m
	return {}


static func setup(state: GameState, mode_id: String) -> void:
	state.hero_death = {}
	if mode_def(mode_id).is_empty():
		return
	state.hero_death = {"mode": mode_id, "back": [], "notes": {}}


static func mode(state: GameState) -> String:
	return String(state.hero_death.get("mode", "jamais"))


static func mode_pct(state: GameState) -> int:
	if state.hero_death.is_empty():
		return 0
	return int(mode_def(mode(state)).get("pct", 0))


static func worth_saving(state: GameState) -> bool:
	return not state.hero_death.is_empty()


static func to_dict(state: GameState) -> Dictionary:
	return Ancients._sorted(state.hero_death)


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.hero_death = {}
	if d.is_empty():
		return
	state.hero_death = GameData._to_ints(d.duplicate(true))


static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "mort_combat"] + parts))


## Chance (en %, arrondie) qu'un héros meure sous ce coup : kind = fleet | flagship | system | army.
static func chance(state: GameState, h: Dictionary, kind: String) -> int:
	@warning_ignore("integer_division")
	return chance_10000(state, h, kind) / 100


## Chance en dix-millièmes (garde les fractions des réglages Rare et Avatar).
static func chance_10000(state: GameState, h: Dictionary, kind: String) -> int:
	var pct := mode_pct(state)
	if pct <= 0:
		return 0
	var v := int(cfg().get(kind, 0)) * 100  # en dix-millièmes
	@warning_ignore("integer_division")
	v = v * pct / 100
	@warning_ignore("integer_division")
	v = v * maxi(0, 100 + Heroes.trait_fx(h, "combat_death_pct")) / 100
	if Heroes.is_avatar(state, int(h["owner"])):
		@warning_ignore("integer_division")
		v = v * int(cfg().get("avatar_pct", 150)) / 100
	if int(h.get("surv", 0)) > 0:
		v -= int(cfg().get("capsule_minus", 3)) * 100
	return maxi(0, v)


static func rolls_death(state: GameState, h: Dictionary, kind: String) -> bool:
	var c := chance_10000(state, h, kind)
	return c > 0 and _h(state, ["roll", int(h["id"]), state.tick, kind]) % 10000 < c


## Un coup du combat (flotte anéantie, système perdu, armée vaincue) : la mort d'abord, sinon la
## capture ou la blessure comme avant. Renvoie vrai si le héros est mort.
static func blow(state: GameState, h: Dictionary, out: Array[Dictionary], why: String, captor: int, kind: String) -> bool:
	if rolls_death(state, h, kind):
		fall(state, h, out, why, captor, kind)
		return true
	h.erase("surv")
	Heroes._wound(state, h, out, why, captor)
	return false


## Le plus gros vaisseau de sa flotte est perdu : seulement la mort possible (pas de blessure).
static func flagship_hit(state: GameState, h: Dictionary, out: Array[Dictionary]) -> bool:
	if not rolls_death(state, h, "flagship"):
		return false
	fall(state, h, out, "son vaisseau amiral a sauté sous le feu", int(h.get("foe", -1)), "flagship")
	return true


## Une flotte où se tient un héros ou le souverain ?
static func watched(state: GameState, f: Fleet) -> bool:
	if state.hero_death.is_empty() and state.rulers.is_empty():
		return false
	return not Heroes.assigned_to(state, "fleet", f.id, f.owner).is_empty() or Rulers.commands(state, f.owner, f.id)


static func top_strength(f: Fleet) -> int:
	var best := 0
	for sh in f.ships:
		best = maxi(best, Combat.ship_strength(sh))
	return best


## Pertes du jour : flotte anéantie (capsules notées pour le coup du lendemain) ou plus gros vaisseau perdu.
static func on_losses(state: GameState, f: Fleet, top: int, surv: bool) -> void:
	var h := Heroes.assigned_to(state, "fleet", f.id, f.owner)
	var hit := not f.ships.is_empty() and top_strength(f) < top
	if not h.is_empty():
		if f.ships.is_empty():
			h["surv"] = 1 if surv else 0
		elif hit:
			h["flag_hit"] = 1
	Rulers.on_fleet_losses(state, f, f.ships.is_empty(), hit, surv)


## Le héros meurt au combat.
static func fall(state: GameState, h: Dictionary, out: Array[Dictionary], why: String, captor: int, kind: String) -> void:
	var owner := int(h["owner"])
	var killer := captor if captor >= 0 and captor != owner and captor != GameState.FAUNA_ID else -1
	h.erase("surv")
	h.erase("flag_hit")
	h["fell"] = 1
	var copy: Dictionary = h.duplicate(true)
	var name := String(h["name"])
	var lvl := int(h["lvl"])
	Heroes.die(state, h, "tombe au combat : %s" % why, out, killer)
	if state.heroes.has(int(h["id"])):
		return  # ressuscité (Parasite saint)
	# Avatars : l'esprit commun en reforme un ; synthétiques : la sauvegarde.
	var back := ""
	var days := 0
	if Heroes.is_avatar(state, owner):
		back = "avatar"
		days = int(cfg().get("avatar_days", 180))
	elif Heroes._archetype_raw(state, owner) == "synthetique" and Research.fx_int(state, owner, "hero_backup") > 0:
		back = "backup"
		days = int(cfg().get("backup_days", 360))
	if back != "" and not state.hero_death.is_empty():
		(state.hero_death["back"] as Array).append({"hero": copy, "day": state.tick + days, "why": back})
	_note_report(state, owner, name, kind)
	if lvl >= int(cfg().get("fallen_card_lvl", 3)) and state.get_empire(owner) != null:
		var eid := state.next_event_id
		Events.push(state, owner, "hero_fallen", {}, out)
		if not state.hero_death.is_empty():
			var txt := "%s, %s de niveau %d, %s." % [name, String(Heroes.class_def(String(copy["cls"])).get("label", "")).to_lower(), lvl, why]
			if killer >= 0:
				txt += " Le coup est venu de %s." % state.get_empire(killer).display_name()
			if back == "avatar":
				txt += " L'esprit commun en reformera un autre dans %d jours." % days
			elif back == "backup":
				txt += " Sa sauvegarde le ramènera dans un an, un peu moins expérimenté."
			(state.hero_death["notes"] as Dictionary)[str(eid)] = {"name": name, "text": txt}
			_trim_notes(state)


static func _trim_notes(state: GameState) -> void:
	var notes: Dictionary = state.hero_death["notes"]
	var keys := notes.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	while keys.size() > 20:
		notes.erase(keys.pop_front())


## Le rapport de la bataille qui vient de finir (même empire, il y a au plus deux jours) cite les morts.
static func _note_report(state: GameState, owner: int, name: String, kind: String) -> void:
	if kind != "fleet" and kind != "flagship":
		return
	for i in range(state.battle_reports.size() - 1, -1, -1):
		var r: Dictionary = state.battle_reports[i]
		if state.tick - int(r.get("end", -100)) > 2:
			break
		for s: Dictionary in r.get("sides", []):
			if int(s["empire"]) == owner:
				if not r.has("fallen"):
					r["fallen"] = []
				(r["fallen"] as Array).append(name)
				return


## Jetons des cartes : {fallen_name}, {fallen_text}.
static func fill(state: GameState, item: Dictionary, s: String) -> String:
	if not s.contains("{fallen_"):
		return s
	var n: Dictionary = (state.hero_death.get("notes", {}) as Dictionary).get(str(int(item.get("id", -1))), {})
	return s.replace("{fallen_name}", String(n.get("name", "Un héros"))).replace("{fallen_text}", String(n.get("text", "Il est tombé au combat.")))


## Retours du jour (Avatars reformés, sauvegardes synthétiques).
static func daily(state: GameState, out: Array[Dictionary]) -> void:
	if state.hero_death.is_empty():
		return
	var back: Array = state.hero_death["back"]
	var i := 0
	while i < back.size():
		var b: Dictionary = back[i]
		if state.tick < int(b["day"]):
			i += 1
			continue
		back.remove_at(i)
		var h: Dictionary = b["hero"]
		var owner := int(h["owner"])
		var e := state.get_empire(owner)
		if e == null or e.eliminated or Heroes.ids_of(state, owner).size() >= Heroes.cap(state, owner):
			continue
		var id := state.next_hero_id
		state.next_hero_id += 1
		h["id"] = id
		h["lvl"] = maxi(1, int(h["lvl"]) - 1)
		h["xp"] = 0
		h["post"] = ""
		h["target"] = -1
		h["wound"] = 0
		h["jailer"] = -1
		h["foe"] = -1
		h["convert"] = 0
		h["fell"] = 0
		h.erase("heir")
		state.heroes[id] = h
		var txt := "L'esprit commun de %s reforme %s, un peu moins aguerri." if String(b["why"]) == "avatar" \
				else "%s restaure %s depuis sa dernière sauvegarde ; quelques souvenirs manquent."
		out.append(state.add_chronicle(txt % [e.display_name(), h["name"]], Espionage.private_to(state, [owner])))
