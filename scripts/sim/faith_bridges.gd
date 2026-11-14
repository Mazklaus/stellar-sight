class_name FaithBridges
extends RefCounted
## Religion, lot 4 : les ponts avec les autres piliers (étude « Religion », v1 propositions 18 à 24,
## v2 « Ce qui change, ce qui reste pareil »).
## - Héros de foi : un héros à l'ambition Foi peut recevoir une vocation de Prophète, d'Inquisiteur ou
##   de Martyr (commande faith_voc).
## - Pèlerinages : les fidèles des autres empires viennent au monde saint par les routes commerciales ;
##   un blocus les coupe.
## - Politique : Autel dissident là où une autre foi domine, Autel coupé en deux au schisme, Conclave
##   nommé selon le zèle de la foi d'État.
## - Talents des 8 peuples autour de leurs natures préférées (bridges.talents).
## - Victoire spirituelle (option de partie, voir Victory) et événements religieux.

static func bd() -> Dictionary:
	return GameData.faiths()["bridges"]


# --- Héros de foi ------------------------------------------------------------------------------------

static func vocation(h: Dictionary) -> String:
	return String(h.get("voc", ""))


## Héros actif de l'empire qui a cette vocation ({} sinon).
static func voc_hero(state: GameState, eid: int, voc: String) -> Dictionary:
	if not state.faith_on:
		return {}
	var hids := state.heroes.keys()
	hids.sort()
	for hid in hids:
		var h: Dictionary = state.heroes[hid]
		if int(h.get("owner", -1)) == eid and vocation(h) == voc and Heroes.active(state, h):
			return h
	return {}


static func check_voc(state: GameState, player: int, hid: int, voc: String) -> String:
	if not state.faith_on:
		return "les religions ne sont pas actives dans cette partie"
	var h: Dictionary = state.heroes.get(hid, {})
	if h.is_empty() or int(h.get("owner", -1)) != player:
		return "héros inconnu"
	if not bd()["vocations"].has(voc):
		return "vocation inconnue"
	if String(h.get("amb", "")) != String(bd()["vocation_amb"]):
		return "seul un héros à l'ambition Foi entend l'appel"
	if vocation(h) != "":
		return "ce héros a déjà une vocation"
	var sf := Faiths.state_faith(state, player)
	if Faiths.faith(state, sf).is_empty():
		return "il faut une grande foi pour foi d'État"
	if not voc_hero(state, player, voc).is_empty():
		return "l'empire a déjà un %s" % String(bd()["vocations"][voc]["label"]).to_lower()
	return FaithWars._afford(state, player, bd()["vocation_cost"])


static func apply_voc(state: GameState, player: int, hid: int, voc: String) -> void:
	FaithWars._pay(state, player, bd()["vocation_cost"])
	var h: Dictionary = state.heroes[hid]
	h["voc"] = voc
	var sf := Faiths.state_faith(state, player)
	# Prophète : la foi débloque tout de suite son prochain précepte (une fois par foi).
	if voc == "prophete":
		var f := Faiths.faith(state, sf)
		if not bool(f.get("prophet_slot", false)) and int(f["slots"]) < 1 + (Faiths.data()["tiers"] as Array).size():
			f["slots"] = int(f["slots"]) + 1
			f["prophet_slot"] = true
	Relics.touch(state)
	state.add_chronicle("%s se découvre une vocation : %s de %s." % [String(h["name"]), String(bd()["vocations"][voc]["label"]), Faiths.name_of(state, sf)],
			Espionage.private_to(state, [player]))


## Pression des missions en plus (Prophète), en %.
static func mission_pct(state: GameState, eid: int) -> int:
	return int(bd()["vocations"]["prophete"]["mission_pct"]) if not voc_hero(state, eid, "prophete").is_empty() else 0


## Multiplicateur de prêche d'une colonie dont le système est gouverné par le Prophète.
static func source_x(state: GameState, c: Colony, fid: String) -> int:
	if not state.faith_on or GameState.is_npc(c.owner) or Faiths.state_faith(state, c.owner) != fid:
		return 1
	var h := voc_hero(state, c.owner, "prophete")
	if not h.is_empty() and String(h.get("post", "")) == "system" and int(h.get("target", -1)) == state.galaxy.get_planet(c.planet_id).system_id:
		return int(bd()["vocations"]["prophete"]["source_x"])
	return 1


static func has_inquisitor(state: GameState, eid: int) -> bool:
	return not voc_hero(state, eid, "inquisiteur").is_empty()


## Coût et durée d'une mission d'inquisition (Inquisiteur : gratuite, deux fois plus longue).
static func ward_free(state: GameState, eid: int) -> bool:
	return has_inquisitor(state, eid)


static func ward_x(state: GameState, eid: int) -> int:
	return int(bd()["vocations"]["inquisiteur"]["ward_x"]) if has_inquisitor(state, eid) else 1


static func inquisition_x(state: GameState, eid: int) -> int:
	return int(bd()["vocations"]["inquisiteur"]["inquisition_x"]) if has_inquisitor(state, eid) else 1


## Une hérésie peut-elle naître sur cette colonie ? (Inquisiteur : une fois sur deux.)
static func heresy_blocked(state: GameState, c: Colony) -> bool:
	if not has_inquisitor(state, c.owner):
		return false
	return FaithWars._h(state, ["inq", c.planet_id, state.tick]) % 100 >= int(bd()["vocations"]["inquisiteur"]["heresy_pct"])


## Mort d'un héros (Heroes.die) : un Martyr tué (exécution, assassinat) nourrit sa foi.
static func on_hero_death(state: GameState, h: Dictionary, killer: int, out: Array[Dictionary]) -> void:
	if vocation(h) != "martyr" or killer < 0:
		return
	var owner := int(h.get("owner", -1))
	var sf := Faiths.state_faith(state, owner)
	if Faiths.faith(state, sf).is_empty():
		return
	var md: Dictionary = bd()["vocations"]["martyr"]
	FaithWars.add_zeal(state, sf, int(md["zeal"]))
	Relics.add_fragments(state, owner, int(md["fragments"]))
	var text := "%s meurt en martyr de %s. Son sang fait plus pour la foi que tous ses sermons." % [String(h["name"]), Faiths.name_of(state, sf)]
	var rid := String(md["relic"])
	if state.relics.has(rid) and int(state.relics[rid].get("owner", -1)) < 0 and not Relics._buried(state, rid):
		Relics.gain(state, owner, rid)
		text += " On garde son bouclier : %s." % String(Relics.def(rid).get("name", rid))
	out.append(state.add_chronicle(text))


# --- Pèlerinages ---------------------------------------------------------------------------------------

## Empires de la foi dont les pèlerins atteignent le monde saint tenu par owner : une route commerciale
## non bloquée les relie.
static func pilgrims_to(state: GameState, fid: String, owner: int) -> Array[int]:
	var out: Array[int] = []
	var linked := {}
	for r: Dictionary in Trade.routes_of(state, owner):
		if String(r["kind"]) != "ext" or bool(r.get("blocked", false)):
			continue
		linked[int(r["to"]) if int(r["from"]) == owner else int(r["from"])] = true
	for e in state.empires:
		if not e.eliminated and e.id != owner and Faiths.state_faith(state, e.id) == fid and linked.has(e.id):
			out.append(e.id)
	return out


## Les pèlerins reviennent contents : opinion de a envers le maître du monde saint de sa foi.
static func opinion_parts(state: GameState, a: int, b: int, out: Array) -> void:
	var fa := Faiths.state_faith(state, a)
	var f := Faiths.faith(state, fa)
	if f.is_empty() or Faiths._fx_for_faith(state, fa, "pilgrims") <= 0:
		return
	var hc: Colony = state.colonies.get(int(f["holy"]))
	if hc != null and hc.owner == b and pilgrims_to(state, fa, b).has(a):
		out.append(["Pèlerins bien reçus", int(bd()["pilgrims"]["op"])])


# --- Politique -------------------------------------------------------------------------------------------

## Nom du Conclave d'une théocratie selon le zèle de sa foi d'État.
static func conclave_name(state: GameState, eid: int, base: String) -> String:
	if not state.faith_on or Politics.regime_id(state, eid) != "theocratie":
		return base
	var sf := Faiths.state_faith(state, eid)
	if Faiths.faith(state, sf).is_empty():
		return base
	var z := FaithWars.zeal(state, sf)
	for row in bd()["politics"]["conclave"]:
		if z >= int(row[0]):
			return String(row[1])
	return base


## Systèmes où l'Autel est dissident ce mois-ci : une autre grande foi y domine.
static func dissident(state: GameState, sid: int) -> bool:
	return state.faiths.get("dissident", {}).has(str(sid))


static func _politics_month(state: GameState) -> void:
	var dis := {}
	if state.politics_on:
		var autel := Politics.index_of("autel")
		for s in state.galaxy.systems:
			var owner := state.system_owner(s.id)
			if owner < 0 or GameState.is_npc(owner) or Faiths.closed(state, owner) or not Politics.applies(state, owner):
				continue
			var sf := Faiths.state_faith(state, owner)
			var cnt := {}
			for pid in s.planet_ids:
				var c: Colony = state.colonies.get(pid)
				if c == null or c.owner != owner or not c.is_colony():
					continue
				var m := Faiths.majority(c)
				cnt[m] = int(cnt.get(m, 0)) + c.population
			var best := ""
			for k in Faiths._sorted_keys(cnt):
				if best == "" or int(cnt[k]) > int(cnt[best]):
					best = k
			if best != "" and best != sf and not Faiths.faith(state, best).is_empty():
				dis[str(s.id)] = best
				Politics.push(state, s.id, autel, int(bd()["politics"]["dissident_push"]))
	state.faiths["dissident"] = dis


## Ligne de stabilité : l'Autel dissident gronde quand l'Autel officiel est au pouvoir.
static func stability_parts(state: GameState, sid: int, owner: int, out: Array) -> void:
	if state.politics_on and dissident(state, sid) and Politics.in_power(state, owner, Politics.index_of("autel")):
		out.append(["Autel dissident", int(bd()["politics"]["dissident_stab"])])


## Schisme : l'Autel se coupe en deux là où la foi fille a des fidèles chez un empire de la foi mère.
static func on_schism(state: GameState, parent: String, child: String) -> void:
	if not state.politics_on:
		return
	var pct := int(bd()["politics"]["schism_split_pct"])
	var autel := Politics.index_of("autel")
	var done := {}
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if int(c.faith.get(child, 0)) <= 0 or Faiths.state_faith(state, c.owner) != parent or not Politics.applies(state, c.owner):
			continue
		var sid := state.galaxy.get_planet(pid).system_id
		if done.has(sid):
			continue
		done[sid] = true
		var en: Dictionary = state.politics["sys"].get(sid, {})
		if en.is_empty():
			continue
		var op: Array = en["op"]
		# L'Autel perd la moitié de sa part, rendue aux autres courants (Politics.push en sens inverse).
		@warning_ignore("integer_division")
		var lost := int(op[autel]) * pct / 100
		if lost <= 0:
			continue
		op[autel] = int(op[autel]) - lost
		var others := 0
		for k in op.size():
			if k != autel:
				others += 1
		@warning_ignore("integer_division")
		var each := lost / maxi(1, others)
		var rest := lost - each * others
		for k in op.size():
			if k != autel:
				op[k] = int(op[k]) + each + (rest if rest > 0 else 0)
				rest = 0


# --- Talents de peuple -----------------------------------------------------------------------------------

## Foi à vendre (Brisecomète) : prix pour adopter leur foi sans fidèles ({} si elle n'est pas à vendre).
static func sale_price(state: GameState, player: int, fid: String) -> Dictionary:
	var f := Faiths.faith(state, fid)
	if f.is_empty():
		return {}
	var seller := int(f["founder"])
	var se := state.get_empire(seller)
	if se == null or se.eliminated or seller == player or Faiths.state_faith(state, seller) != fid:
		return {}
	return FaithHeavy.talent(state, seller).get("sell_price", {})


static func buy_faith(state: GameState, player: int, fid: String) -> void:
	var price := sale_price(state, player, fid)
	if price.is_empty():
		return
	var seller := int(Faiths.faith(state, fid)["founder"])
	Economy.pay(state.get_empire(player), price)
	var se := state.get_empire(seller)
	for r in price:
		se.resources[r] = int(se.resources.get(r, 0)) + int(price[r])
	state.add_chronicle("%s achète sa foi : %s, livrée clés en main par %s. Satisfait ou ressuscité." % [
			state.get_empire(player).display_name(), Faiths.name_of(state, fid), se.display_name()])


## Pression en plus d'une source d'incroyance (Teyl : le doute est contagieux), en %.
static func unbelief_pct(state: GameState, owner: int) -> int:
	if Faiths.state_faith(state, owner) != Faiths.INCROYANCE:
		return 0
	return int(FaithHeavy.talent(state, owner).get("unbelief_pressure_pct", 0))


# --- Victoire spirituelle ---------------------------------------------------------------------------------

## Avancée vers la victoire spirituelle (Victory.progress) : la foi d'État majoritaire dans plus de la
## moitié des colonies de chaque empire survivant (le sien compris), tenue 5 ans.
static func spiritual(state: GameState, e: Empire, out: Dictionary) -> void:
	var sf := Faiths.state_faith(state, e.id)
	if not state.faith_on or Faiths.faith(state, sf).is_empty():
		out["lines"].append("Il faut une grande foi pour foi d'État.")
		return
	var need := int(bd()["victory"]["share_pct"])
	var done := 0
	var total := 0
	for o in state.empires:
		if o.eliminated or GameState.is_npc(o.id):
			continue
		total += 1
		var n := 0
		var k := 0
		for pid in state.sorted_colony_ids():
			var c: Colony = state.colonies[pid]
			if c.owner == o.id and c.is_colony() and c.is_established():
				n += 1
				if Faiths.majority(c) == sf:
					k += 1
		if n > 0 and k * 100 > n * need:
			done += 1
		else:
			out["lines"].append("%s : %d colonies sur %d suivent %s" % [o.short_name(), k, n, Faiths.name_of(state, sf)])
	out["cond"] = total > 0 and done == total
	out["keep"] = false
	Victory._timed(out, done, maxi(1, total))


# --- Événements religieux -----------------------------------------------------------------------------------

static func _events_month(state: GameState, added: Array[Dictionary]) -> void:
	var ev: Dictionary = bd()["events"]
	for fid in Faiths.ids(state):
		var f := Faiths.faith(state, fid)
		if int(f.get("pending", 0)) > 0 or Faiths.parent_of(state, fid) != "":
			continue
		if state.tick <= int(f["founded"]) or (state.tick - int(f["founded"])) % int(ev["days"]) >= int(GameData.rules()["month_days"]):
			continue
		var roll := FaithWars._h(state, ["miracle", fid, state.tick]) % 1000
		if roll >= int(ev["pmille"]):
			continue
		var hc: Colony = state.colonies.get(int(f["holy"]))
		var name := Faiths.name_of(state, fid)
		match roll % 3:
			0:
				FaithWars.add_zeal(state, fid, int(ev["miracle_zeal"]))
				if hc != null:
					FaithWars.add_stab(state, state.galaxy.get_planet(hc.planet_id).system_id, "Miracle", int(ev["miracle_stab"]), int(ev["miracle_days"]))
				added.append(state.add_chronicle("Miracle au monde saint de %s ! Les témoins ne s'accordent pas sur ce qu'ils ont vu, mais tous ont vu quelque chose." % name))
			1:
				if hc != null and not GameState.is_npc(hc.owner) and not pilgrims_to(state, fid, hc.owner).is_empty():
					var he := state.get_empire(hc.owner)
					he.resources["influence"] = int(he.resources.get("influence", 0)) + int(ev["pilgrim_wave_influence"])
					added.append(state.add_chronicle("Grand pèlerinage vers le monde saint de %s : les routes débordent de fidèles, et les aubergistes de %s de reconnaissance." % [name, he.short_name()]))
			2:
				var h := voc_hero(state, Faiths.head(state, fid), "prophete")
				if not h.is_empty():
					Heroes.gain_xp(state, h, int(ev["prophet_xp"]))
					added.append(state.add_chronicle("Le prophète %s a une vision. Ce qu'elle dit reste flou ; qu'elle le grandit, non." % String(h["name"])))


# --- Mois et IA -------------------------------------------------------------------------------------------

static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	if not state.faith_on:
		return
	_politics_month(state)
	_events_month(state, added)


static func ai(state: GameState) -> void:
	if not state.faith_on:
		return
	var ac: Dictionary = GameData.faiths()["ai"]["heavy"]
	for e in state.empires:
		if e.eliminated or not e.is_ai() or GameState.is_npc(e.id):
			continue
		# Une ruche entre en Communion dès qu'elle en connaît une.
		if Faiths.is_hive(state, e.id) and not Faiths.has_state_faith(state, e.id):
			for fid in Faiths.ids(state):
				if FaithWars.nature(state, fid) == "communion" and Faiths.check_state(state, e.id, fid) == "":
					Faiths.set_state(state, e.id, fid)
					break
		# Vocation de foi pour un héros à l'ambition Foi.
		var credo := Events.layer_value(state, e.id, "credo")
		var voc := String(ac["vocation_by_credo"].get(credo, ac["vocation_by_credo"]["default"]))
		for hid in Heroes.ids_of(state, e.id):
			if check_voc(state, e.id, hid, voc) == "":
				apply_voc(state, e.id, hid, voc)
				break
