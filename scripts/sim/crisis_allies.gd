class_name CrisisAllies
extends RefCounted
## Crises de fin de partie, lot 3 : ce qui se range aux côtés des empires (ou contre eux).
## - Talents par couche d'espèce (prop. 27) : data/crises.json « talents », chacun lié à une sorte de crise
##   et à des couches (FactionTraits.species_matches), donc valable pour les peuples créés.
## - Gardiens et faune (prop. 19) : les gardiens éveillés chassent la crise près de leur tanière ; les
##   troupeaux fuient devant ses flottes.
## - Héros (prop. 24 et 28) : poste « Commandant du Front », traits gagnés « Tueur de crise » et
##   « Vétéran du Front », gouverneurs enlevés par certaines crises.
## Aucun aléatoire : hachages de la graine (Crisis._h).


static func data() -> Dictionary:
	return Crisis.data()


# --- Talents par couche (prop. 27) ------------------------------------------------------------------

static func talent_defs() -> Array:
	return data().get("talents", [])


## Talents de l'empire qui jouent contre cette sorte de crise (toutes si kind = "").
static func talents_of(state: GameState, eid: int, kind := "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var e := state.get_empire(eid)
	if e == null or GameState.is_npc(eid):
		return out
	for t: Dictionary in talent_defs():
		if kind != "" and String(t.get("kind", "")) != kind:
			continue
		if FactionTraits.species_matches(e.faction(), t.get("requires", {})):
			out.append(t)
	return out


## Somme d'une clé des talents de l'empire contre la crise en cours (0 sans crise).
static func tal(state: GameState, eid: int, key: String) -> int:
	if not Crisis.ongoing(state):
		return 0
	var n := 0
	for t in talents_of(state, eid, Crisis.kind(state)):
		n += int(t.get(key, 0))
	return n


static func tal_flag(state: GameState, eid: int, key: String) -> bool:
	if not Crisis.ongoing(state):
		return false
	for t in talents_of(state, eid, Crisis.kind(state)):
		if bool(t.get(key, false)):
			return true
	return false


## Applique un pourcentage de talent (-50 = moitié) à une valeur.
@warning_ignore("integer_division")
static func scaled(v: int, pct: int) -> int:
	return v * maxi(0, 100 + pct) / 100


## Empires qui pressentent la crise (présage privé, Déchirure).
static func foreseers(state: GameState, kind: String) -> Array[int]:
	var out: Array[int] = []
	for e in state.empires:
		if e.eliminated:
			continue
		for t in talents_of(state, e.id, kind):
			if int(t.get("foresight_days", 0)) > 0 and not out.has(e.id):
				out.append(e.id)
	return out


static func foresight_days(kind: String) -> int:
	var n := 0
	for t: Dictionary in talent_defs():
		if String(t.get("kind", "")) == kind:
			n = maxi(n, int(t.get("foresight_days", 0)))
	return n


## Production d'un monde tombé chez un peuple qui résiste au sort de la crise (ruches et Récif).
@warning_ignore("integer_division")
static func fate_prod(state: GameState, owner: int, pct: int) -> int:
	var r := tal(state, owner, "fate_resist_pct")
	if r <= 0:
		return pct
	return pct + (100 - pct) * mini(100, r) / 100


## Le monde résiste-t-il à cette ponction d'habitants ?
static func resists_drain(state: GameState, owner: int, sid: int) -> bool:
	var r := tal(state, owner, "fate_resist_pct")
	return r > 0 and Crisis._h(state, ["resiste", sid, state.tick]) % 100 < r


# --- Gardiens et faune (prop. 19) -------------------------------------------------------------------

## Un gardien éveillé (sauf les pacifiques) se bat contre la crise.
static func guardian_hunts(state: GameState, beast: Fleet) -> bool:
	if not Crisis.active(state):
		return false
	var gid := Guardians.of_fleet(state, beast)
	return gid != "" and not bool(Guardians.def(gid).get("pacific", false))


## Tous les dix jours : les gardiens chassent les flottes de la crise près de leur tanière, puis rentrent ;
## les troupeaux fuient les systèmes où elle se tient.
static func fauna_day(state: GameState, added: Array[Dictionary]) -> void:
	if state.fauna.is_empty() or state.tick % 10 != 0:
		return
	var gd: Dictionary = data().get("guardians", {})
	var reach := int(gd.get("reach", 3))
	var crisis_at := {}
	for f in Crisis.war_fleets(state):
		if not f.is_moving():
			crisis_at[f.system_id] = true
	for f in Crisis.stations(state):
		crisis_at[f.system_id] = true
	var c := Crisis.cur(state)
	var woke: Dictionary = c.get("woke", {})
	for gid in Guardians.ids(state):
		var g: Dictionary = Guardians.list(state)[gid]
		if String(g["status"]) != "awake" or bool(Guardians.def(gid).get("pacific", false)) or bool(Guardians.def(gid).get("sun_eater", false)):
			continue
		var f: Fleet = state.fleets.get(int(g["fleet"]))
		if f == null or f.is_moving() or state.battles.has(f.system_id):
			continue
		var home := int(g["sid"])
		var dist := FactionTraits.jumps_from(state.galaxy, home)
		var best := -1
		var best_d := reach + 1
		var keys := crisis_at.keys()
		keys.sort()
		for sid in keys:
			var d := int(dist.get(int(sid), 999))
			if d < best_d:
				best_d = d
				best = int(sid)
		var to := best if best >= 0 else home
		if to == f.system_id:
			continue
		if best >= 0 and not woke.has(int(g["fleet"])):
			woke[int(g["fleet"])] = state.tick
			added.append(state.add_chronicle(String(gd.get("text", "%s sort de sa tanière et fond sur %s.")) % [
					String(Guardians.def(gid).get("name", gid)), Crisis.obj_name(Crisis.name_of(Crisis.kind(state)))]))
		var plan := Fleets.plan_route(state, f, to)
		if not plan.is_empty():
			f.system_id = int(plan["system"])
			f.path.assign(plan["path"])
			f.progress = int(plan["progress"])
	c["woke"] = woke
	# Les troupeaux fuient.
	for hid in Fauna.herd_ids(state):
		var h: Fleet = state.fleets.get(hid)
		if h == null or h.is_moving() or state.battles.has(h.system_id) or not crisis_at.has(h.system_id):
			continue
		var away := -1
		var ns: Array = state.galaxy.systems[h.system_id].neighbors.duplicate()
		ns.sort()
		for n in ns:
			if not crisis_at.has(int(n)):
				away = int(n)
				break
		if away < 0:
			continue
		var plan2 := Fleets.plan_route(state, h, away)
		if not plan2.is_empty():
			h.system_id = int(plan2["system"])
			h.path.assign(plan2["path"])
			h.progress = int(plan2["progress"])


# --- Héros (prop. 24 et 28) -------------------------------------------------------------------------

## Le poste « Commandant du Front » : membre du Front commun, crise en cours.
static func check_front_post(state: GameState, player: int, target: int) -> String:
	if target != 0:
		return "poste inconnu"
	if not Crisis.active(state) or not Crisis.in_front(state, player):
		return "il faut être membre du Front commun"
	return ""


## Bonus de dégâts contre la crise : talents, Commandant du Front, traits de l'amiral.
static func damage_pct(state: GameState, f: Fleet) -> int:
	var pct := tal(state, f.owner, "damage_pct")
	if state.heroes.is_empty():
		return pct
	var cmd := Heroes.at_post(state, "front", 0, f.owner)
	if not cmd.is_empty():
		@warning_ignore("integer_division")
		pct += int(Heroes.data()["per_level"].get("front_damage_pct", 4)) * Heroes.half_levels(cmd, "front") / 2
	var adm := Heroes.at_post(state, "fleet", f.id, f.owner)
	if not adm.is_empty():
		pct += Heroes.trait_fx(adm, "crisis_damage_pct")
	return pct


## Fin d'une bataille contre la crise : les amiraux qui y étaient deviennent des vétérans du Front.
static func on_battle(state: GameState, b: Dictionary) -> void:
	if state.heroes.is_empty():
		return
	var vets: Dictionary = Crisis.cur(state).get("vets", {})
	for entry: Array in b.get("fleets", []):
		var f: Fleet = state.fleets.get(int(entry[0]))
		if f == null or GameState.is_npc(f.owner):
			continue
		var h := Heroes.at_post(state, "fleet", f.id, f.owner)
		if not h.is_empty():
			vets[int(h["id"])] = state.tick
	Crisis.cur(state)["vets"] = vets


## Un point faible ou le cœur tombe : l'amiral du vainqueur qui était là gagne « Tueur de crise ».
static func slayer(state: GameState, b: Dictionary, eid: int, added: Array[Dictionary]) -> void:
	if state.heroes.is_empty() or eid < 0:
		return
	for entry: Array in b.get("fleets", []):
		var f: Fleet = state.fleets.get(int(entry[0]))
		if f == null or f.owner != eid:
			continue
		var h := Heroes.at_post(state, "fleet", f.id, eid)
		if not h.is_empty():
			_give(state, h, "tueur_crise", added)
			return


## Victoire sur la crise : chaque vétéran encore en vie gagne « Vétéran du Front ».
static func on_victory(state: GameState, added: Array[Dictionary]) -> void:
	var vets: Dictionary = Crisis.cur(state).get("vets", {})
	var ids := vets.keys()
	ids.sort()
	for k in ids:
		var h := Heroes.get_hero(state, int(k))
		if not h.is_empty():
			_give(state, h, "veteran_front", added)


static func _give(state: GameState, h: Dictionary, trait_id: String, added: Array[Dictionary]) -> void:
	if (h["traits"] as Array).has(trait_id):
		return
	(h["traits"] as Array).append(trait_id)
	added.append(state.add_chronicle("%s gagne le trait « %s »." % [String(h["name"]), String(Heroes.trait_def(trait_id).get("label", trait_id))],
			Espionage.private_to(state, [int(h["owner"])])))


## Un système tombe : certaines crises enlèvent son gouverneur (Inspection, Déchirure).
static func on_fall(state: GameState, sid: int, owner: int, added: Array[Dictionary]) -> void:
	if state.heroes.is_empty() or owner < 0 or GameState.is_npc(owner):
		return
	var why := String(Crisis.kind_def(Crisis.kind(state)).get("hero_fate", ""))
	if why == "":
		return
	var h := Heroes.at_post(state, "system", sid, owner)
	if h.is_empty():
		return
	Heroes._wound(state, h, added, why, GameState.CRISIS_ID)
