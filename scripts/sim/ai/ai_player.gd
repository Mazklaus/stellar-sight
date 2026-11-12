class_name AiPlayer
extends RefCounted
## Le cerveau d'un empire IA. Appelé par AiSystem les jours où l'empire réfléchit.
##
## Organisation inspirée de l'IA d'Endless Space 2 (des objectifs qui reçoivent une « motivation »
## et se partagent les ressources) mais en beaucoup plus simple : une suite de modules, chacun
## examine l'état et donne des ordres ordinaires (SimCommands) tant que les ressources le permettent.
## Chaque ordre est validé puis appliqué tout de suite, si bien que le module suivant voit
## les ressources déjà dépensées.
##
## Modules, dans l'ordre :
## 1. talents du peuple (offrande du Chœur, vote d'urgence de Vael…) selon faction_use ;
## 2. bâtiments : ce qui manque à l'économie, avec le penchant du peuple ;
## 3. revendications sans vaisseau dans les systèmes déjà tenus ;
## 4. chantiers spatiaux : éclaireurs et vaisseaux colons (ou spores) ;
## 5. flottes : exploration automatique, vaisseaux colons vers la meilleure cible ;
## 6. militaire : déclarations de guerre (tempérament et rapport de forces), vaisseaux de guerre,
##    tactiques, défense des systèmes assiégés, offensives, sièges, invasions et retraites ;
## 7. diplomatie (AiDiplomacy) : propositions de traités, alliances quittées, talents diplomatiques
##    du peuple (héritier, arbitrage) ; puis espionnage (AiEspionage) : où placer ses cellules.
##
## Règles d'or : la simulation reste déterministe (aucun aléatoire hors de l'état : les « oublis »
## des niveaux bas viennent d'un hachage de la graine, du jour et de l'empire), l'IA ne lit que
## ce que son empire sait (systèmes explorés, routes connues), et tout passe par SimCommands.

## Valeur minimale d'une planète pour justifier un vaisseau colon.
const MIN_TARGET_VALUE := 12
## Matériaux gardés de côté pour un vaisseau colon quand il en manque un.
const COLONIZER_RESERVE := 100


## Réfléchit et agit pour l'empire e.
static func think(state: GameState, e: Empire) -> void:
	var ctx := {
		"state": state,
		"e": e,
		"lv": AiLevels.level(e.ai_level),
		"ai": AiLevels.personality(e),
		"salt": 0,
		"intent": "",
	}
	_faction_talents(ctx)
	_research(ctx)
	_victory(ctx)
	_buildings(ctx)
	_foothold_claims(ctx)
	_designs(ctx)
	_shipyards(ctx)
	_refits(ctx)
	_fleets(ctx)
	# Les niveaux qui réfléchissent très souvent ne revoient leur stratégie militaire qu'un jour sur
	# deux ou trois : la guerre se joue sur des semaines, et la simulation reste rapide.
	var every := maxi(1, int(ctx["lv"].get("think_days", 10)))
	if every >= 4 or posmod(state.tick + e.id * 3, 4) < every:
		_military(ctx)
	_diplomacy(ctx)
	AiHeroes.think(ctx)
	if String(ctx["intent"]) != "":
		e.ai_intent = ctx["intent"]


# --- Outils ------------------------------------------------------------------------------------

## Valide puis applique un ordre de l'IA. Renvoie true s'il a été appliqué.
static func _issue(ctx: Dictionary, cmd: Dictionary) -> bool:
	var state: GameState = ctx["state"]
	if SimCommands.validate(state, cmd) != "":
		return false
	SimCommands.apply(state, cmd)
	return true


## Les niveaux bas « oublient » parfois une décision (moins réactifs, comme dans Endless Space 2).
## Déterministe : hachage de la graine, du jour, de l'empire et d'un compteur.
static func _forgets(ctx: Dictionary) -> bool:
	var pct := int(ctx["lv"].get("mistake_pct", 0))
	if pct <= 0:
		return false
	var state: GameState = ctx["state"]
	ctx["salt"] = int(ctx["salt"]) + 1
	return posmod(hash([state.seed_value, state.tick, ctx["e"].id, ctx["salt"]]), 100) < pct


## Niveau d'usage des talents du peuple : 0 aucun, 1 les bases, 2 tout.
static func _use(ctx: Dictionary) -> int:
	return int(ctx["lv"].get("faction_use", 1))


static func _intent(ctx: Dictionary, text: String) -> void:
	if String(ctx["intent"]) == "":
		ctx["intent"] = text


## Bilan mensuel de l'empire, calculé une fois par réflexion : les ordres du jour (chantiers,
## fondations) ne changent la production qu'une fois achevés.
static func _net(ctx: Dictionary) -> Dictionary:
	if not ctx.has("net"):
		ctx["net"] = Economy.empire_income(ctx["state"], ctx["e"].id)["net"]
	return ctx["net"]


static func _res(ctx: Dictionary, r: String) -> int:
	return int(ctx["e"].resources.get(r, 0))


## Colonies établies de l'empire, par identifiant de planète.
static func _own_colonies(state: GameState, empire_id: int, established_only := true) -> Array[Colony]:
	var out: Array[Colony] = []
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == empire_id and (c.is_established() or not established_only):
			out.append(c)
	return out


## Colonies établies de l'empire qui réfléchit, gardées le temps d'une réflexion (ses ordres n'en
## établissent aucune) : les boucles par colonie ne reparcourent pas toutes les revendications.
static func _my_colonies(ctx: Dictionary) -> Array[Colony]:
	if not ctx.has("my_colonies"):
		ctx["my_colonies"] = _own_colonies(ctx["state"], ctx["e"].id)
	return ctx["my_colonies"]


## Classe de vaisseau colonisateur que l'empire construit ("" si aucune).
static func colonizer_class(e: Empire) -> String:
	for sid in FactionTraits.ship_ids_for(e.faction_id):
		if GameData.ship(sid).get("colonizer", false):
			return sid
	return ""


## Classe d'éclaireur : le vaisseau non colonisateur qui voit le plus loin.
static func scout_class(e: Empire) -> String:
	var best := ""
	for sid in FactionTraits.ship_ids_for(e.faction_id):
		var sd := GameData.ship(sid)
		if sd.get("colonizer", false):
			continue
		if best == "" or int(sd.get("vision", 0)) > int(GameData.ship(best).get("vision", 0)):
			best = sid
	return best


# --- Valeur des planètes et des cibles ---------------------------------------------------------

## Ce que vaut une planète libre pour l'empire : {"kind": colonie ou avant-poste, "value": int}.
## Les talents du peuple pèsent dès faction_use 1.
static func planet_value(state: GameState, e: Empire, p: Planet, use := 1) -> Dictionary:
	var ai := AiLevels.personality(e)
	var deposits := 0
	var crystals := false
	for d in p.deposits:
		deposits += 1
		crystals = crystals or d == "crystals"
	var maxp := Economy.max_pop(state, p, e.id)
	var kind := Colony.KIND_COLONY if maxp >= 1 else Colony.KIND_OUTPOST
	var value := 0
	if kind == Colony.KIND_COLONY:
		value = maxp * 3 + deposits * 6
		# Mondes que seul son corps peuple (lithoïdes : la roche nue) : personne ne les lui dispute.
		if use >= 1 and FactionTraits.hab_extra(e.faction(), p.type) > 0:
			value += int(ai.get("own_world_bonus", 0))
	else:
		var y: Dictionary = GameData.planet_type(p.type).get("outpost_yields", {})
		for r in y:
			value += int(y[r]) * 4
		value += deposits * 6
	# Les goûts du peuple pèsent à tous les niveaux ; la Recrue les suit sans réfléchir
	# (Ossarane court après les cristaux sans compter ce que coûtent les fiefs lointains).
	value += int(ai.get("colony_bonus", 0)) if kind == Colony.KIND_COLONY else int(ai.get("outpost_bonus", 0))
	if crystals:
		value += int(ai.get("crystal_bonus", 0))
	# Horde : la Terre promise, dès que les Chants de la route sont connus (une vraie colonie).
	if use >= 1 and kind == Colony.KIND_COLONY and FactionTraits.has_horde(e.faction()) \
			and Victory.has_tech(state, e.id, "terre_promise") and p.id == Victory.promised_planet(state, e.id):
		value += 80
	return {"kind": kind, "value": value}


## Meilleure planète à revendiquer dans un système pour l'empire : {"planet", "kind", "value"},
## ou {} s'il n'y a rien à prendre (déjà pris, ou système d'un autre empire).
## vis : systèmes que l'empire voit ce tick ; hors de vue, l'IA juge sur sa mémoire (Intel).
static func best_claim(state: GameState, e: Empire, system_id: int, use: int, vis: Dictionary) -> Dictionary:
	var owner := Intel.owner_in(state, e, vis, system_id)
	if owner != -1 and owner != e.id:
		return {}
	var best := {}
	for pid in state.galaxy.systems[system_id].planet_ids:
		var c: Colony = Intel.colony_in(state, e, vis, pid)
		var p := state.galaxy.get_planet(pid)
		var v := {}
		if c == null:
			v = planet_value(state, e, p, use)
		elif c.owner == e.id and c.kind == Colony.KIND_OUTPOST and c.is_established() and Economy.max_pop(state, p, e.id) >= 1:
			v = planet_value(state, e, p, use)  # un avant-poste habitable peut devenir colonie
			if v["kind"] != Colony.KIND_COLONY:
				continue
		else:
			continue
		if best.is_empty() or int(v["value"]) > int(best["value"]):
			best = {"planet": pid, "kind": v["kind"], "value": v["value"]}
	return best


## Systèmes déjà visés par l'empire : destinations de ses vaisseaux colons, et systèmes où une
## revendication est en cours de fondation.
static func _targeted(state: GameState, e: Empire, except_fleet := -1) -> Dictionary:
	var out := {}
	for f in Fleets.empire_fleets(state, e.id):
		if f.id != except_fleet and Fleets.colonizer_ship(f) != "":
			out[f.destination()] = true
	return out


## Pénalité Ossarane : un fief lointain coûte des cristaux ; l'IA l'évite tant qu'elle ne peut pas
## les payer (faction_use 1 : évite tout fief lointain sans production de cristaux ; 2 : fait le
## compte exact des cristaux disponibles).
static func _far_fief_penalty(ctx: Dictionary, system_id: int) -> int:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var f := e.faction()
	if not FactionTraits.has_fiefs(f) or _use(ctx) < 1 or e.capital_planet < 0:
		return 0
	var cap_sys := state.galaxy.get_planet(e.capital_planet).system_id
	var jumps := int(FactionTraits.jumps_from(state.galaxy, cap_sys).get(system_id, 999))
	if jumps <= int(f["fiefs"]["far_jumps"]):
		return 0
	var crystal_net := int(_net(ctx).get("crystals", 0))
	var spare := crystal_net if _use(ctx) >= 2 else crystal_net - 1
	return 0 if spare >= int(f["fiefs"]["crystal_upkeep"]) else 1000


## Meilleure cible de colonisation pour une flotte colonisatrice : {"system", "planet", "kind", "value"}
## ou {}. Les niveaux qui planifient pèsent valeur et distance ; la Recrue prend la plus proche.
static func colonize_target(ctx: Dictionary, f: Fleet) -> Dictionary:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var use := _use(ctx)
	var plan := bool(ctx["lv"].get("plan_targets", true))
	var taken := _targeted(state, e, f.id)
	var res := Fleets._dijkstra(state, e.id, f.system_id)
	var speed := Fleets.speed(f, state)
	var best := {}
	var best_score := 0
	var ids: Array = res["dist"].keys()
	ids.sort()
	for k in ids:
		var sid := int(k)
		if not Fleets.is_explored(state, e.id, sid) or taken.has(sid) or Economy.has_foothold(state, e.id, sid):
			continue
		if _owner(ctx, sid) != -1:
			continue
		var claim := best_claim(state, e, sid, use, _seen(ctx))
		if claim.is_empty() or int(claim["value"]) < MIN_TARGET_VALUE:
			continue
		@warning_ignore("integer_division")
		var days := int(res["dist"][k]) / maxi(1, speed)
		var score := int(claim["value"]) * 10 - days * 2 if plan else 100000 - days
		score -= _far_fief_penalty(ctx, sid) * 10
		score += border_bias(ctx, sid)
		if best.is_empty() or score > best_score:
			best_score = score
			best = claim.duplicate()
			best["system"] = sid
	return best


## Distance en sauts de chaque système au plus proche système rival connu (au plus 3 sauts).
## Seuls comptent les systèmes rivaux que l'empire a explorés : l'IA ne devine pas les frontières.
static func rival_distance(ctx: Dictionary) -> Dictionary:
	if ctx.has("rival_dist"):
		return ctx["rival_dist"]
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var dist := {}
	var queue: Array[int] = []
	for sid in e.sorted_explored():
		var owner := _owner(ctx, int(sid))
		if owner != -1 and owner != e.id:
			dist[int(sid)] = 0
			queue.append(int(sid))
	var i := 0
	while i < queue.size():
		var cur := queue[i]
		i += 1
		if int(dist[cur]) >= 3:
			continue
		for n in state.galaxy.systems[cur].neighbors:
			if not dist.has(n):
				dist[n] = int(dist[cur]) + 1
				queue.append(n)
	ctx["rival_dist"] = dist
	return dist


## Effet du tempérament sur une cible de colonisation : un empire agressif est attiré par les
## systèmes voisins de ses rivaux (frontières, systèmes disputés), un pacifique les évite.
static func border_bias(ctx: Dictionary, system_id: int) -> int:
	var aggr := AiLevels.aggression(ctx["e"])
	if aggr == 0:
		return 0
	var d := int(rival_distance(ctx).get(system_id, 99))
	if d < 1 or d > 2:
		return 0
	return aggr * (3 - d) * (60 if aggr > 0 else 80)


## Y a-t-il au moins `need` systèmes libres qui mériteraient un vaisseau colon ?
static func _has_open_targets(state: GameState, e: Empire, use: int, need: int, vis: Dictionary) -> bool:
	var n := 0
	for sid in e.sorted_explored():
		if Intel.owner_in(state, e, vis, int(sid)) != -1:
			continue
		var claim := best_claim(state, e, int(sid), use, vis)
		if not claim.is_empty() and int(claim["value"]) >= MIN_TARGET_VALUE:
			n += 1
			if n >= need:
				return true
	return false


# --- 1. Talents du peuple ----------------------------------------------------------------------

static func _faction_talents(ctx: Dictionary) -> void:
	var use := _use(ctx)
	if use <= 0:
		_clumsy_talents(ctx)
		return
	var e: Empire = ctx["e"]
	var f := e.faction()
	if FactionTraits.has_fervor(f):
		_fervor(ctx, use)
	if FactionTraits.can_rush(f):
		_rush(ctx, use)
	if Echoes.has(f):
		_fold(ctx)


## Registre Cosmique : replier le temps d'abord sur un vaisseau colon, puis sur le chantier le plus long.
static func _fold(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if e.echoes < Echoes.fold_cost(state, e.id):
		return
	var best := -1
	var best_what := ""
	@warning_ignore("integer_division")
	var best_days := Echoes.fold_days(state, e.id) / 2
	for c in _my_colonies(ctx):
		if c.ship_build != "" and GameData.ship(c.ship_build).get("colonizer", false) and c.ship_days > 10:
			if _issue(ctx, SimCommands.fold(e.id, c.planet_id, Echoes.SHIP)):
				_intent(ctx, "Replier le temps : un vaisseau colon")
			return
		if c.construction != "" and c.construction_days > best_days:
			best = c.planet_id
			best_what = Echoes.BUILDING
			best_days = c.construction_days
		if c.ship_build != "" and c.ship_days > best_days:
			best = c.planet_id
			best_what = Echoes.SHIP
			best_days = c.ship_days
	if best >= 0 and _issue(ctx, SimCommands.fold(e.id, best, best_what)):
		_intent(ctx, "Replier le temps sur un chantier")


## Recrue : elle connaît les talents de son peuple, mais s'en sert très mal.
## - Chœur : attend que le dieu se taise pour réagir, et sacrifie dans sa plus petite colonie
##   (celle qui avait le plus besoin de grandir).
## - Vael : vote l'urgence sur des chantiers presque finis, au prix plancher, sans garder d'influence
##   pour ses revendications.
## - Ossarane et Kh'thari : voir planet_value (court après ses goûts sans compter les cristaux)
##   et _best_yard (lance les spores depuis ses colonies les plus fragiles).
static func _clumsy_talents(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var f := e.faction()
	if FactionTraits.has_fervor(f) and e.fervor <= 0 and not _forgets(ctx):
		var smallest: Colony = null
		for c in _my_colonies(ctx):
			if FactionTraits.check_sacrifice(state, e.id, c.planet_id) == "" and (smallest == null or c.population < smallest.population):
				smallest = c
		if smallest and _issue(ctx, SimCommands.sacrifice(e.id, smallest.planet_id)):
			_intent(ctx, "Offrande tardive, sur une colonie qui n'en demandait pas tant")
	if FactionTraits.can_rush(f):
		for c in _my_colonies(ctx):
			if _forgets(ctx):
				continue
			if c.construction != "" and c.construction_days <= 8 and _issue(ctx, SimCommands.rush(e.id, c.planet_id, FactionTraits.RUSH_BUILDING)):
				_intent(ctx, "Vote d'urgence… sur un chantier presque fini")
			elif c.ship_build != "" and c.ship_days <= 8 and _issue(ctx, SimCommands.rush(e.id, c.planet_id, FactionTraits.RUSH_SHIP)):
				_intent(ctx, "Vote d'urgence… sur un vaisseau presque fini")


## Chœur Éternel : offrande quand la ferveur va manquer. Les bases évitent le Silence du dieu ;
## le registre complet entretient l'Exaltation (+25 % de production).
static func _fervor(ctx: Dictionary, use: int) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var fv: Dictionary = e.faction()["fervor"]
	var next := e.fervor + FactionTraits.fervor_delta(state, e.id)
	var floor_wanted := int(fv["exalted_at"]) if use >= 2 else int(fv["decay"]) * 2
	if use >= 1 and _singing(ctx):
		floor_wanted = int(fv["exalted_at"])  # le Dernier Couplet ne se chante qu'en Exaltation
	if next >= floor_wanted or _forgets(ctx):
		return
	# Le fidèle vient de la colonie la plus peuplée (jamais en dessous de 3 : on garde de quoi grandir).
	# Pour entretenir l'Exaltation, le registre complet ne prend que dans une colonie pleine (elle
	# regrandit sans rien perdre) ou très peuplée ; contre le Silence du dieu, toute colonie fait l'affaire.
	var silent := next <= 0
	var best: Colony = null
	for c in _my_colonies(ctx):
		if not c.is_colony() or c.population < maxi(3, int(fv["sacrifice_min_pop"])):
			continue
		if use >= 2 and not silent:
			var cap := Economy.max_pop(state, state.galaxy.get_planet(c.planet_id), e.id, c.buildings)
			if c.population < cap and c.population < 6:
				continue
		if best == null or c.population > best.population:
			best = c
	if best and _issue(ctx, SimCommands.sacrifice(e.id, best.planet_id)):
		_intent(ctx, "Offrande pour raviver la ferveur" if use < 2 else "Offrande : garder le dieu exalté")


## Vael : vote d'urgence. Les bases votent quand l'influence déborde largement ; le registre complet
## vote dès qu'il reste de quoi payer la prochaine revendication, et sur des chantiers plus courts.
static func _rush(ctx: Dictionary, use: int) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var keep := int(Economy.claim_cost(Colony.KIND_COLONY).get("influence", 0)) + (60 if use < 2 else 0)
	for c in _my_colonies(ctx):
		if c.ship_build != "" and c.ship_days > 4 and GameData.ship(c.ship_build).get("colonizer", false):
			var cost := FactionTraits.rush_cost(state, e.id, c.planet_id, FactionTraits.RUSH_SHIP)
			if cost >= 0 and _res(ctx, "influence") - cost >= keep and not _forgets(ctx):
				if _issue(ctx, SimCommands.rush(e.id, c.planet_id, FactionTraits.RUSH_SHIP)):
					_intent(ctx, "Vote d'urgence : un vaisseau colon de plus")
	var min_days := 20 if use < 2 else 10
	for c in _my_colonies(ctx):
		if c.construction != "" and c.construction_days > min_days:
			var cost := FactionTraits.rush_cost(state, e.id, c.planet_id, FactionTraits.RUSH_BUILDING)
			if cost >= 0 and _res(ctx, "influence") - cost >= keep:
				if _issue(ctx, SimCommands.rush(e.id, c.planet_id, FactionTraits.RUSH_BUILDING)):
					_intent(ctx, "Vote d'urgence sur un chantier")


# --- Victoire de peuple ------------------------------------------------------------------------

## Poursuivre sa victoire de peuple : cathédrales du Dernier Couplet, unions de l'Élu des routes.
## La Charte (paix et commerce avec tous) et la Moisson (croître et digérer) se jouent avec les modules
## habituels. La Recrue s'y prend mal : cathédrale sur sa plus petite colonie, unions oubliées.
static func _victory(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if Victory.applies(state, e.id, "couplet") and Victory.has_tech(state, e.id, "couplet"):
		_cathedrals(ctx)
	if Victory.applies(state, e.id, "elu") and Victory.has_tech(state, e.id, "elu"):
		for other in Diplomacy.allies(state, e.id):
			if _forgets(ctx):
				continue
			if _issue(ctx, SimCommands.unite_lineages(e.id, other)):
				_intent(ctx, "Unit ses lignées à celles de %s" % state.get_empire(other).short_name())


## Systèmes qui ont (ou auront) une cathédrale de l'empire.
static func _cathedral_sites(ctx: Dictionary) -> Dictionary:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var b := String(Victory.info("couplet")["building"])
	var sites := {}
	for c in _own_colonies(state, e.id, false):
		if c.buildings.has(b) or c.construction == b:
			sites[state.galaxy.get_planet(c.planet_id).system_id] = true
	return sites


static func _cathedrals(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var b := String(Victory.info("couplet")["building"])
	var sites := _cathedral_sites(ctx)
	if sites.size() >= int(Victory.info("couplet")["sites"]) or _forgets(ctx):
		return
	var use := _use(ctx)
	var best: Colony = null
	for c in _my_colonies(ctx):
		if not c.is_colony() or c.construction != "" or sites.has(state.galaxy.get_planet(c.planet_id).system_id):
			continue
		if Economy.check_build(state, e.id, c.planet_id, b) != "":
			continue
		# Les bonnes IA bâtissent sur leurs mondes les plus peuplés (plus durs à prendre), la Recrue au hasard du plus petit.
		if best == null or (c.population > best.population if use >= 1 else c.population < best.population):
			best = c
	if best and _issue(ctx, SimCommands.build(e.id, best.planet_id, b)):
		_intent(ctx, "Bâtit une Cathédrale-chœur sur %s" % state.galaxy.get_planet(best.planet_id).display_name(state.galaxy))


## Le Chœur chante-t-il (ou peut-il chanter) le Dernier Couplet : toutes ses cathédrales debout ?
static func _singing(ctx: Dictionary) -> bool:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	return Victory.applies(state, e.id, "couplet") and Victory.cathedral_systems(state, e.id).size() >= int(Victory.info("couplet")["sites"])


# --- 2. Bâtiments ------------------------------------------------------------------------------

static func _buildings(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var net := _net(ctx).duplicate()
	var reserve := _material_reserve(ctx)
	var late := _knows_late(ctx)
	for c in _my_colonies(ctx):
		if c.construction != "" or _forgets(ctx):
			continue
		var full := Economy.building_slots_used(c) >= Economy.building_slots(state, c)
		if full and not late:
			continue
		var urgent := urgent_needs(ctx, net)
		var wishes := late_wishes(ctx, c, net) if late else ([] as Array[String])
		if not full:
			wishes.append_array(building_wishes(ctx, c, net))
		for b in wishes:
			if not Economy.building_unlocked(state, e.id, b):
				continue
			var cost := Economy.building_cost(state, e.id, b)
			if _res(ctx, "materials") - int(cost.get("materials", 0)) < reserve and not urgent.has(b):
				continue  # on garde de quoi lancer le vaisseau colon
			if _issue(ctx, SimCommands.build(e.id, c.planet_id, b)):
				if b == String(ctx.get("lab", "")):
					ctx["lab_count"] = int(ctx["lab_count"]) + 1
				var bd := GameData.building(b)
				for r in bd.get("yields", {}):
					net[r] = int(net.get(r, 0)) + int(bd["yields"][r])
				for r in bd.get("upkeep", {}):
					net[r] = int(net.get(r, 0)) - int(bd["upkeep"][r])
				break


## Technologies qui débloquent les chantiers tardifs (2e rang, préfectures, projets, merveilles).
const LATE_TECHS := ["arcologies_productives", "prefectures", "terraformation", "collecteur_stellaire",
		"nexus_savoir", "abondance", "assemblee", "mondes_jardins", "arcologie_planetaire"]


static func _knows_late(ctx: Dictionary) -> bool:
	var e: Empire = ctx["e"]
	for t in LATE_TECHS:
		if e.techs.has(t):
			return true
	return false


## Chantiers tardifs souhaités pour une colonie (ceux sans emplacement passent même si elle est pleine) :
## bâtiments de 2e rang, Préfecture, mégastructures et merveilles sur la colonie principale, puis
## terraformation des colonies pleines quand les matériaux s'entassent.
static func late_wishes(ctx: Dictionary, c: Colony, net: Dictionary) -> Array[String]:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var out: Array[String] = []
	var mat := _res(ctx, "materials")
	if not c.is_colony():
		if e.techs.has("collecteur_stellaire") and mat >= 1700 and not _empire_has_building(ctx, "collecteur_stellaire"):
			out.append("collecteur_stellaire")
		return out
	if e.techs.has("arcologies_productives") and mat >= 350:
		if c.buildings.has("complexe_minier"):
			out.append("mine_profonde")
		if c.buildings.has("centrale_fusion"):
			out.append("centrale_confinement")
		if c.buildings.has("ferme_hydroponique"):
			out.append("ferme_verticale")
	if e.techs.has("prefectures") and c.population >= 10 and mat >= 400:
		out.append("prefecture")
	if _is_main_yard(ctx, c):
		for w in ["bourse_mille_soleils", "assemblee", "nexus_savoir", "collecteur_stellaire"]:
			var need := int(GameData.building(w).get("cost", {}).get("materials", 0)) + 500
			if Economy.building_unlocked(state, e.id, w) and mat >= need and not _empire_has_building(ctx, w):
				out.append(w)
	if mat >= 1500:
		var p := state.galaxy.get_planet(c.planet_id)
		var cap := Economy.max_pop(state, p, e.id, c.buildings)
		if c.population >= cap - 1:
			var hab := Economy._pop_hab(state, e.id, p.type)
			if Economy.building_unlocked(state, e.id, "ecumenopole") and mat >= 2200 and c.population >= 12:
				# La ville ne nourrit plus personne : seulement si la nourriture déborde assez.
				var lost := int(Economy.pop_yields(p.type).get("food", 0)) * c.population
				@warning_ignore("integer_division")
				if int(net.get("food", 0)) >= lost + c.population / 2 + 10:
					out.append("ecumenopole")
			if hab < 100 and Economy.building_unlocked(state, e.id, "monde_jardin"):
				out.append("monde_jardin")
			if hab < 80 and Economy.building_unlocked(state, e.id, "terraformeur"):
				out.append("terraformeur")
	return out


## Bâtiments qui comblent un manque (famine ou panne d'énergie en vue) : ils passent avant
## la réserve gardée pour le vaisseau colon.
static func urgent_needs(ctx: Dictionary, net: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var food_margin := 2 + (int(ctx["ai"].get("food_margin", 0)) if _use(ctx) >= 1 else 0)
	# Un peuple qui mange la roche manque de matériaux, pas de nourriture : des mines, pas des fermes.
	var diet := FactionTraits.diet(ctx["e"].faction())
	if diet != "food":
		if int(net.get(diet, 0)) < food_margin:
			out.append({"materials": "complexe_minier", "energy": "centrale_fusion"}.get(diet, "complexe_minier"))
	elif int(net.get("food", 0)) < food_margin:
		out.append("ferme_hydroponique")
	if int(net.get("energy", 0)) < 3:
		out.append("centrale_fusion")
	return out


## Bâtiments souhaités pour une revendication, du plus urgent au moins urgent :
## d'abord ce qui manque (nourriture, énergie, cristaux), puis le penchant du peuple, puis l'industrie
## (les matériaux paient les vaisseaux colons et tout le reste), et la nourriture ou l'énergie
## seulement si elles ne débordent pas déjà.
static func building_wishes(ctx: Dictionary, c: Colony, net: Dictionary) -> Array[String]:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var use := _use(ctx)
	var ai: Dictionary = ctx["ai"]
	var p := state.galaxy.get_planet(c.planet_id)
	var out := urgent_needs(ctx, net)
	# Le bâtiment de recherche du peuple (Académie, Scriptorium, Université, Ganglion), sur les colonies
	# déjà peuplées : le Savoir paie toutes les technologies.
	# (bâtiment, quota et compte gardés dans ctx : sinon chaque colonie recompterait tout l'empire)
	if not ctx.has("lab"):
		ctx["lab"] = research_building(ctx)
		@warning_ignore("integer_division")
		ctx["lab_quota"] = _my_colonies(ctx).size() / 5
		ctx["lab_count"] = _lab_count(ctx)
	var lab: String = ctx["lab"]
	if lab != "" and c.is_colony() and c.population >= 4 and not c.buildings.has(lab) and int(ctx["lab_count"]) <= int(ctx["lab_quota"]):
		out.append(lab)
	# Lire son goulot : quand les matériaux s'entassent, c'est l'influence qui freine l'expansion
	# (chaque revendication en coûte) ; les forums passent alors devant. Le Vétéran le voit dès 250,
	# les autres niveaux à 500 (sans quoi le Chœur entassait des milliers de matériaux inutiles).
	if c.is_colony() and _res(ctx, "materials") >= (250 if use >= 2 else 500):
		out.append("forum")
	# En guerre, les systèmes du front se fortifient (dès le niveau Normal).
	if not e.wars.is_empty() and _skill(ctx) >= 1 and int(rival_distance(ctx).get(p.system_id, 99)) <= 2 \
			and Combat.battery(state, p.system_id).is_empty():
		out.push_front("bastion")
	# Arsenal (cuirassés, porte-vaisseaux) puis chantier titanesque, sur la plus grande colonie seulement.
	if c.is_colony() and _skill(ctx) >= 1 and _is_main_yard(ctx, c):
		if not _empire_has_building(ctx, "arsenal") and (not e.wars.is_empty() or _res(ctx, "materials") >= 400):
			out.push_front("arsenal")
		elif _skill(ctx) >= 2 and c.buildings.has("arsenal") and not _empire_has_building(ctx, "chantier_titanesque") \
				and _res(ctx, "materials") >= 1200:
			out.push_front("chantier_titanesque")
	if p.deposits.has("crystals"):
		var fiefs := FactionTraits.has_fiefs(e.faction()) and use >= 1
		if fiefs or int(net.get("crystals", 0)) < 1:
			out.append("raffinerie")
	if use >= 1 and ai.has("building_bias"):
		var bias := String(ai["building_bias"])
		var plenty := {"ferme_hydroponique": "food", "centrale_fusion": "energy"}
		if not plenty.has(bias) or int(net.get(plenty[bias], 0)) < 20:
			out.append(bias)
	if c.is_colony():
		var cap := Economy.max_pop(state, p, e.id, c.buildings)
		if c.population >= cap - 1:
			out.append("habitats")
		if int(net.get("influence", 0)) < 4:
			out.append("forum")
		out.append("complexe_minier")
		if int(net.get("energy", 0)) < 10:
			out.append("centrale_fusion")
		if int(net.get("food", 0)) < 10 and FactionTraits.diet(e.faction()) == "food":
			out.append("ferme_hydroponique")
	return out


## Un bâtiment existe-t-il (ou est-il en chantier) dans une colonie de l'empire ?
static func _empire_has_building(ctx: Dictionary, building_id: String) -> bool:
	for c in _my_colonies(ctx):
		if c.buildings.has(building_id) or c.construction == building_id:
			return true
	return false


## La colonie la plus peuplée de l'empire (à égalité, la plus ancienne identifiant) : là où vont les
## chantiers lourds.
static func _is_main_yard(ctx: Dictionary, c: Colony) -> bool:
	if not ctx.has("main_yard"):
		var best: Colony = null
		for o in _my_colonies(ctx):
			if o.is_colony() and (best == null or o.population > best.population):
				best = o
		ctx["main_yard"] = best.planet_id if best != null else -1
	return int(ctx["main_yard"]) == c.planet_id


## Matériaux à garder pour le prochain vaisseau colon, s'il en manque un.
static func _material_reserve(ctx: Dictionary) -> int:
	if ctx.has("reserve"):
		return ctx["reserve"]
	ctx["reserve"] = _compute_reserve(ctx)
	return ctx["reserve"]


static func _compute_reserve(ctx: Dictionary) -> int:
	var e: Empire = ctx["e"]
	var cls := colonizer_class(e)
	if cls == "" or _colonizer_count(ctx["state"], e) >= int(ctx["lv"].get("colonizers", 1)):
		return 0
	return int(GameData.ship(cls).get("cost", {}).get("materials", 0))


# --- 3. Revendications sans vaisseau -----------------------------------------------------------

static func _foothold_claims(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var use := _use(ctx)
	var max_claims := mini(int(ctx["lv"].get("max_claims", 2)) + Research.fx_int(state, e.id, "max_projects"),
			Economy.max_projects_for(state, e.id))
	var reserve_inf := int(ctx["lv"].get("reserve_influence", 0))
	for sid in EmpireReport.owned_systems(state, e.id):
		if Economy.active_projects(state, e.id) >= max_claims:
			return
		if not Economy.has_foothold(state, e.id, sid) or _forgets(ctx):
			continue
		var claim := best_claim(state, e, sid, use, _seen(ctx))
		if claim.is_empty():
			continue
		var cost := Economy.claim_cost_for(state, e.id, int(claim["planet"]), String(claim["kind"]))
		if _res(ctx, "influence") - int(cost.get("influence", 0)) < reserve_inf and int(cost.get("influence", 0)) > 0:
			continue
		if _issue(ctx, SimCommands.colonize(e.id, int(claim["planet"]), String(claim["kind"]))):
			_intent(ctx, "Développe %s" % state.galaxy.systems[sid].system_name)


# --- 4. Chantiers spatiaux ---------------------------------------------------------------------

static func _colonizer_count(state: GameState, e: Empire) -> int:
	var n := 0
	for f in Fleets.empire_fleets(state, e.id):
		for s in f.ships:
			if GameData.ship(s).get("colonizer", false):
				n += 1
	for c in _own_colonies(state, e.id):
		if c.ship_build != "" and GameData.ship(c.ship_build).get("colonizer", false):
			n += 1
	return n


static func _scout_count(state: GameState, e: Empire, scout: String) -> int:
	var n := 0
	for f in Fleets.empire_fleets(state, e.id):
		n += f.count(scout)
	for c in _own_colonies(state, e.id):
		if c.ship_build == scout:
			n += 1
	return n


## Versions mémorisées le temps d'une réflexion (elles ne changent pas d'un module à l'autre).
static func _frontier(ctx: Dictionary) -> bool:
	if not ctx.has("frontier"):
		ctx["frontier"] = _frontier_left(ctx["state"], ctx["e"])
	return ctx["frontier"]


static func _open(ctx: Dictionary) -> bool:
	if not ctx.has("open"):
		ctx["open"] = _has_open_targets(ctx["state"], ctx["e"], _use(ctx), 1, _seen(ctx))
	return ctx["open"]


## Reste-t-il des systèmes connus mais inexplorés ?
static func _frontier_left(state: GameState, e: Empire) -> bool:
	for sid in e.sorted_explored():
		for n in state.galaxy.systems[int(sid)].neighbors:
			if not e.explored.has(n):
				return true
	return false


static func _shipyards(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var use := _use(ctx)
	var cls := colonizer_class(e)
	var wanted := int(ctx["lv"].get("colonizers", 1))
	var have := _colonizer_count(state, e)
	if cls != "" and have < wanted and _has_open_targets(state, e, use, have + 1, _seen(ctx)) and not _forgets(ctx):
		var yard := _best_yard(ctx, cls)
		if yard and _issue(ctx, SimCommands.build_ship(e.id, yard.planet_id, cls)):
			_intent(ctx, "Prépare une expansion")
	# Horde : une flotte-ville perdue se reconstruit dès que possible, avant tout le reste.
	var city := FactionTraits.city_ship(e.faction())
	if city != "" and Fleets.count_same_hull(state, e.id, city) == 0 and not _forgets(ctx):
		var cy := _best_yard(ctx, city)
		if cy and _issue(ctx, SimCommands.build_ship(e.id, cy.planet_id, city)):
			_intent(ctx, "Reforge la flotte-ville")
	var scout := scout_class(e)
	var scouts := int(ctx["lv"].get("scouts", 1)) + (int(ctx["ai"].get("scouts", 0)) if use >= 1 else 0)
	if scout != "" and _scout_count(state, e, scout) < scouts and _frontier(ctx) and not _forgets(ctx):
		var yard := _best_yard(ctx, scout)
		if yard and _res(ctx, "materials") - int(GameData.ship(scout).get("cost", {}).get("materials", 0)) >= _material_reserve(ctx):
			_issue(ctx, SimCommands.build_ship(e.id, yard.planet_id, scout))


## Remise à niveau : en paix, les flottes armées à quai dans un système à soi prennent les dernières
## marques (si l'on peut payer sans entamer la réserve du prochain vaisseau colon).
static func _refits(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not e.wars.is_empty() or e.marks_log.is_empty():
		return
	for f in Fleets.empire_fleets(state, e.id):
		if f.is_moving() or f.refit_left > 0 or not Combat.is_armed(f) or _forgets(ctx):
			continue
		if Fleets.outdated_count(state, f) == 0:
			continue
		var cost := Fleets.refit_cost(state, f)
		if _res(ctx, "materials") - int(cost.get("materials", 0)) < _material_reserve(ctx):
			continue
		_issue(ctx, SimCommands.refit(e.id, f.id))


## Chantier spatial libre le plus adapté : la colonie la plus peuplée (un vaisseau-spore emporte
## de la population ; l'Essaim au registre complet préfère une colonie pleine, qui regrandit vite).
static func _best_yard(ctx: Dictionary, ship_id: String) -> Colony:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var best: Colony = null
	var best_score := -1
	for c in _my_colonies(ctx):
		if not c.is_colony() or c.ship_build != "":
			continue
		if Fleets.check_build_ship(state, e.id, c.planet_id, ship_id) != "":
			continue
		var score := c.population * 10
		if _use(ctx) <= 0 and int(GameData.ship(ship_id).get("pop_cost", 0)) > 0:
			score = 1000 - c.population  # la Recrue de l'Essaim vide ses colonies les plus fragiles
		if _use(ctx) >= 2 and e.faction().has("biomass"):
			var cap := Economy.max_pop(state, state.galaxy.get_planet(c.planet_id), e.id, c.buildings)
			if c.population >= cap:
				score += 1000
		if score > best_score:
			best_score = score
			best = c
	return best


# --- 5. Flottes --------------------------------------------------------------------------------

static func _fleets(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	for f in Fleets.empire_fleets(state, e.id):
		if not state.fleets.has(f.id):
			continue  # dissoute par une colonisation plus haut dans la boucle
		if Fleets.colonizer_ship(f) != "":
			_colonizer(ctx, f)
		elif FactionTraits.is_city_fleet(f):
			_move_city(ctx, f)
		elif f.is_idle() and not Combat.is_warfleet(f) and _frontier(ctx) and not _forgets(ctx):
			_issue(ctx, SimCommands.set_fleet_order(e.id, f.id, Fleet.ORDER_EXPLORE))


## Horde : la flotte-ville campe dans le système le plus peuplé du clan (le campement y rapporte le
## plus), loin des flottes ennemies. La Recrue la laisse où elle est née.
static func _move_city(ctx: Dictionary, f: Fleet) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if f.is_moving() or _use(ctx) <= 0 or _forgets(ctx):
		return
	var target := city_camp(ctx)
	if target >= 0 and target != f.system_id:
		if _issue(ctx, SimCommands.move_fleet(e.id, f.id, target)):
			_intent(ctx, "Lève le camp vers %s" % state.galaxy.systems[target].system_name)


## Meilleur campement : le système à soi où la population fondée est la plus forte, sans flotte ennemie
## armée (à égalité, le plus petit identifiant). -1 si aucun.
static func city_camp(ctx: Dictionary) -> int:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var pops := {}
	for c in _my_colonies(ctx):
		var sid := state.galaxy.get_planet(c.planet_id).system_id
		pops[sid] = int(pops.get(sid, 0)) + c.population * 10 + 1
	var emap := _enemy_power_map(ctx)
	# Terre promise : une fois la colonie fondée, la flotte-ville va y camper (victoire de peuple).
	if Victory.has_tech(state, e.id, "terre_promise"):
		var tp := Victory.promised_planet(state, e.id)
		var tc: Colony = state.colonies.get(tp) if tp >= 0 else null
		if tc != null and tc.owner == e.id and tc.is_established():
			var tsys := state.galaxy.get_planet(tp).system_id
			if not emap.has(tsys):
				return tsys
	var best := -1
	var best_pop := -1
	var keys := pops.keys()
	keys.sort()
	for sid in keys:
		if emap.has(sid) or state.system_owner(int(sid)) != e.id:
			continue
		if int(pops[sid]) > best_pop:
			best_pop = int(pops[sid])
			best = int(sid)
	return best


## Un vaisseau colon : s'il est arrivé sur sa cible, il fonde ; sinon il part vers la meilleure.
static func _colonizer(ctx: Dictionary, f: Fleet) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if f.is_moving():
		# En route : on vérifie que la cible est toujours libre (un rival a pu passer avant).
		var dest := f.destination()
		var owner := _owner(ctx, dest)
		if owner == -1 or owner == e.id:
			return
	elif not _forgets(ctx):
		var here := best_claim(state, e, f.system_id, _use(ctx), _seen(ctx))
		if not here.is_empty() and int(here["value"]) >= MIN_TARGET_VALUE and not Economy.has_foothold(state, e.id, f.system_id):
			# Le vaisseau colon passe avant les revendications sans vaisseau : il a déjà coûté cher.
			if _issue(ctx, SimCommands.colonize(e.id, int(here["planet"]), String(here["kind"]))):
				_intent(ctx, "Fonde %s à %s" % ["une colonie" if here["kind"] == Colony.KIND_COLONY else "un avant-poste", state.galaxy.systems[f.system_id].system_name])
			# Sinon, pas les moyens pour l'instant (influence, chantiers pleins) : on attend sur place.
			return
	else:
		return
	if not _open(ctx):
		return
	var target := colonize_target(ctx, f)
	if target.is_empty():
		return
	if int(target["system"]) == f.system_id:
		return
	if _issue(ctx, SimCommands.move_fleet(e.id, f.id, int(target["system"]))):
		var sname := state.galaxy.systems[int(target["system"])].system_name
		var border := int(rival_distance(ctx).get(int(target["system"]), 99)) <= 1
		_intent(ctx, ("Expansion vers %s, à la frontière d'un rival" if border else "Expansion vers %s") % sname)




# --- 6. Militaire ------------------------------------------------------------------------------
## Le niveau règle le savoir-faire (military.skill : 0 maladroit, 1 les bases, 2 tout), le tempérament
## règle l'envie d'en découdre (AiLevels.aggression : quand déclarer la guerre, combien armer).
## La Recrue ne s'abstient pas : elle arme, attaque et choisit ses tactiques, mais mal (toujours à
## l'assaut, flottes envoyées une par une, jamais de retraite), comme pour les talents de son peuple.

static func _mil(ctx: Dictionary) -> Dictionary:
	return ctx["lv"].get("military", {})


static func _skill(ctx: Dictionary) -> int:
	return int(_mil(ctx).get("skill", 1))


static func _warfleets(ctx: Dictionary) -> Array[Fleet]:
	var out: Array[Fleet] = []
	for f in Fleets.empire_fleets(ctx["state"], ctx["e"].id):
		if Combat.is_warfleet(f):
			out.append(f)
	return out


static func _my_power(ctx: Dictionary) -> int:
	var n := 0
	for f in _warfleets(ctx):
		n += Combat.fleet_power(f)
	return n


## Propriétaire d'un système tel que l'empire le connaît : en direct s'il le voit, sinon sa mémoire
## (dernière information connue). L'IA a les mêmes yeux que le joueur.
static func _owner(ctx: Dictionary, system_id: int) -> int:
	return Intel.owner_in(ctx["state"], ctx["e"], _seen(ctx), system_id)


## Systèmes que l'empire voit aujourd'hui (mémorisés le temps d'une réflexion).
static func _seen(ctx: Dictionary) -> Dictionary:
	if not ctx.has("seen"):
		var state: GameState = ctx["state"]
		var e: Empire = ctx["e"]
		# Calculé par l'exploration plus tôt dans le même tick (identique sur toutes les machines).
		if state.seen_tick == state.tick and e.id < state.seen_cache.size():
			ctx["seen"] = state.seen_cache[e.id]
		else:
			ctx["seen"] = Fleets.visible_systems(state, e.id)
	return ctx["seen"]


## Force estimée d'un rival : ses flottes armées que l'on voit, plus une part pour chacun de ses systèmes
## connus (garnisons, flottes cachées). La Recrue ne compte que ce qu'elle voit.
static func enemy_power(ctx: Dictionary, other: int) -> int:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var n := 0
	for f in Fleets.empire_fleets(state, other):
		if Combat.is_armed(f) and Fleets.fleet_visible(state, e.id, f, _seen(ctx)):
			n += Combat.fleet_power(f)
	if _skill(ctx) >= 1:
		# (une somme : l'ordre de parcours ne compte pas, inutile de trier)
		for sid in e.explored:
			if _owner(ctx, int(sid)) == other:
				n += 6
	return n


## Un rival a-t-il un système (exploré) à `reach` sauts ou moins des nôtres ?
static func _borders(ctx: Dictionary, other: int, reach := 2) -> bool:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var dist := {}
	var queue: Array[int] = []
	for sid in EmpireReport.owned_systems(state, e.id):
		dist[sid] = 0
		queue.append(sid)
	var i := 0
	while i < queue.size():
		var cur := queue[i]
		i += 1
		if e.explored.has(cur) and _owner(ctx, cur) == other:
			return true
		if int(dist[cur]) >= reach:
			continue
		for n in state.galaxy.systems[cur].neighbors:
			if not dist.has(n):
				dist[n] = int(dist[cur]) + 1
				queue.append(n)
	return false


static func _military(ctx: Dictionary) -> void:
	_declare_wars(ctx)
	_build_warships(ctx)
	_command_warfleets(ctx)


## Déclarer la guerre : seulement passé le délai de grâce, à un voisin, avec un rapport de forces
## qui dépend du tempérament (data/ai.json, war.declare_ratio_pct). Un pacifique ne déclare jamais.
## Les niveaux qui savent jouer n'ouvrent pas un second front tant qu'une guerre est à leurs portes,
## sauf les tempéraments les plus belliqueux.
static func _declare_wars(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var war: Dictionary = GameData.ai().get("war", {})
	if state.tick < int(war.get("grace_days", 240)):
		return
	var aggr := AiLevels.aggression(e)
	if _swarm_coalition(ctx):
		return
	if _skill(ctx) >= 1 and aggr < 2:
		for w in e.wars:
			if _borders(ctx, w):
				return  # déjà une guerre à nos portes : pas de second front (sauf les plus belliqueux)
	var ratios: Dictionary = war.get("declare_ratio_pct", {})
	if not ratios.has(str(aggr)):
		return
	var need := int(ratios[str(aggr)])
	var mine := _my_power(ctx)
	if mine <= 0:
		return
	for other in e.contacts:
		var o := state.get_empire(other)
		# Plus le tempérament est agressif, plus il va chercher loin ses ennemis.
		if o == null or o.eliminated or e.wars.has(other) or not _borders(ctx, other, 2 + maxi(0, aggr)):
			continue
		if SimCommands.validate(state, SimCommands.declare_war(e.id, other)) != "":
			continue  # trêve, alliance
		# L'opinion pèse : on attaque plus volontiers ceux qu'on déteste. Rompre un traité (parjure)
		# est réservé aux plus belliqueux, et seulement contre un empire qu'ils haïssent.
		var op := Diplomacy.opinion(state, e.id, other)
		if Diplomacy.has_pact(state, e.id, other) and (aggr < 2 or op > -20):
			continue
		var need_here := need + maxi(0, op) * 2
		# Un empire dont le compte à rebours de victoire tourne : on l'attaque même un peu plus fort que soi.
		var threat := Victory.best_cached(state, other)
		if String(threat["id"]) != "" and Victory.visible_pct(state, e.id, other, String(threat["id"])) >= Victory.met_at() and _skill(ctx) >= 1:
			@warning_ignore("integer_division")
			need_here = need_here * 2 / 3
		if mine * 100 < need_here * maxi(10, enemy_power(ctx, other)) or _forgets(ctx):
			continue
		if _issue(ctx, SimCommands.declare_war(e.id, other)):
			_intent(ctx, "Déclare la guerre à %s" % o.short_name())
			return


## Coalition contre l'Essaim : dès qu'un Essaim voisin a goûté au sang (une première conquête) et
## qu'il tient au moins 25 % de systèmes de plus que soi, ses autres voisins entrent en guerre contre
## lui sans compter les forces, même s'ils ont déjà un front ; sauf les pacifiques et la Recrue, qui
## ne voit pas venir le danger.
static func _swarm_coalition(ctx: Dictionary) -> bool:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if _skill(ctx) < 1 or AiLevels.aggression(e) <= -2:
		return false
	for other in e.contacts:
		var o := state.get_empire(int(other))
		if o == null or o.eliminated or e.wars.has(o.id) or not Combat.hunts(state, o.id):
			continue
		if int(o.stats.get("conquests", 0)) <= 0 or not _borders(ctx, o.id, 3):
			continue
		# La peur suit la menace : on ne rejoint la coalition que contre un Essaim plus grand que soi.
		@warning_ignore("integer_division")
		if Victory.systems_held(state, o.id) * 4 < Victory.systems_held(state, e.id) * 5:
			continue
		if SimCommands.validate(state, SimCommands.declare_war(e.id, o.id)) != "" or _forgets(ctx):
			continue
		if _issue(ctx, SimCommands.declare_war(e.id, o.id)):
			_intent(ctx, "Rejoint la coalition contre %s" % o.short_name())
			return true
	return false


## Combien de vaisseaux de guerre l'empire veut : la base du niveau, plus selon ses colonies,
## doublée en guerre ; le tempérament l'augmente ou la réduit.
static func wanted_warships(ctx: Dictionary) -> int:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var mil := _mil(ctx)
	var n := int(mil.get("warships", 2))
	var per := int(mil.get("per_colonies", 0))
	if per > 0:
		@warning_ignore("integer_division")
		n += _my_colonies(ctx).size() / per
	# Syndicats : une flotte à louer, même en temps de paix.
	n += int(ctx["ai"].get("extra_warships", 0))
	var aggr := AiLevels.aggression(e)
	if not e.wars.is_empty():
		n = n * 2 + 2
		# Armer selon la menace vue : de quoi tenir 80 % de la plus grosse force ennemie estimée.
		var threat := 0
		for w in e.wars:
			threat = maxi(threat, enemy_power(ctx, int(w)))
		var ships := 0
		for f in _warfleets(ctx):
			ships += f.ships.size()
		@warning_ignore("integer_division")
		var per_ship := maxi(6, _my_power(ctx) / ships) if ships > 0 else 12
		@warning_ignore("integer_division")
		n = maxi(n, mini(threat * 8 / 10 / per_ship, n * 3))
	elif _swarm_near(ctx) >= 0:
		@warning_ignore("integer_division")
		n = n * 3 / 2 + 1  # un Essaim qui chasse à nos portes : on arme sans attendre d'être sa proie
	elif aggr < 0:
		@warning_ignore("integer_division")
		n = maxi(1, n * 2 / 3)
	return n + maxi(0, aggr)


## Un Essaim rencontré, en chasse, qui a un système à 3 sauts des nôtres : son identifiant, sinon -1.
static func _swarm_near(ctx: Dictionary) -> int:
	if ctx.has("swarm_near"):
		return ctx["swarm_near"]
	var state: GameState = ctx["state"]
	var out := -1
	for other in ctx["e"].contacts:
		var o := state.get_empire(int(other))
		if o != null and not o.eliminated and Combat.hunts(state, o.id) and _borders(ctx, o.id, 3):
			out = o.id
			break
	ctx["swarm_near"] = out
	return out


static func _warship_count(ctx: Dictionary) -> int:
	var n := 0
	for f in _warfleets(ctx):
		n += f.ships.size()
	for c in _my_colonies(ctx):
		if c.ship_build != "" and Combat.is_military(c.ship_build):
			n += 1
	return n


static func _build_warships(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var at_war := not e.wars.is_empty()
	var missing := wanted_warships(ctx) - _warship_count(ctx)
	var built := 0
	while missing > 0 and built < 2:
		if _forgets(ctx):
			return
		var cls := _own_design(ctx, _pick_warship(ctx))
		var yard := _best_yard(ctx, cls)
		if yard == null:
			return
		var cost: Dictionary = GameData.ship(cls).get("cost", {})
		# En paix, on garde de quoi lancer le prochain vaisseau colon ; en guerre, l'armée passe avant.
		var reserve := 0 if at_war else _material_reserve(ctx)
		if _res(ctx, "materials") - int(cost.get("materials", 0)) < reserve:
			return
		if not _issue(ctx, SimCommands.build_ship(e.id, yard.planet_id, cls)):
			return
		ctx.erase("buildable_warships")
		missing -= 1
		built += 1
		_intent(ctx, "Arme la flotte (%s)" % String(GameData.ship(cls)["label"]).to_lower())


## Éditeur de vaisseaux : une fois par mois, l'IA conçoit ses propres modèles avec l'outil du bouton
## « Concevoir pour moi », un par classe d'origine qu'elle sait construire (même rôle, même coque), et
## les renouvelle quand elle a découvert des technologies ou vu beaucoup de combats. La qualité suit
## son niveau militaire : la Recrue pose des modules au hasard parmi ceux qui conviennent, le Normal
## équilibre, le Vétéran et au-delà adaptent défenses et armes à ce qu'ils ont affronté.
static func _designs(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	# Une fenêtre de la largeur du rythme de réflexion : chaque IA y réfléchit exactement une fois par mois.
	var every := maxi(1, int(ctx["lv"].get("think_days", 10)))
	if posmod(state.tick + e.id * 7, 30) >= mini(every, 30):
		return
	var quality := clampi(_skill(ctx), 0, 2)
	@warning_ignore("integer_division")
	var sig := "%d|%d" % [e.techs.size(), (int(e.stats.get("kills", 0)) + int(e.stats.get("ships_lost", 0))) / 10]
	var mine := _ai_designs(ctx)
	for sid in FactionTraits.ship_ids_for(e.faction_id):
		var role := String(Designs.CLASS_ROLES.get(sid, ""))
		var sd := GameData.ship(sid)
		if role == "" or not sd.has("hull") or not Fleets.ship_unlocked(state, e.id, sid):
			continue
		var old: Dictionary = mine.get(sid, {})
		if not old.is_empty() and String(old.get("sig", "")) == sig:
			continue
		var hid := String(sd["hull"])
		if quality >= 1:
			# Méga-vaisseaux : chaque IA a sa variante préférée (bataille, porteuse, bastion ou siège).
			var options := Designs.variants_of(hid)
			hid = options[posmod(hash([state.seed_value, e.id, "mega"]), options.size())]
			role = String(Designs.HULL_ROLES.get(hid, role))
		var spec := Designs.auto_design(state, e.id, hid, role, quality, e.techs.size())
		if (spec["modules"] as Array).is_empty() and role != "invasion":
			continue
		if not old.is_empty() and old["modules"] == spec["modules"] and String(old["line"]) == String(spec["line"]):
			continue
		var version := int(old.get("version", 0)) + 1
		spec["name"] = "%s Mk %d" % [String(sd["label"]), version]
		spec["role"] = sid
		spec["sig"] = sig
		if not old.is_empty():
			spec["previous"] = String(old["id"])
		if _issue(ctx, SimCommands.save_design(e.id, spec)):
			ctx.erase("ai_designs")
			mine = _ai_designs(ctx)


## Derniers modèles actifs de l'IA, par classe d'origine remplacée.
static func _ai_designs(ctx: Dictionary) -> Dictionary:
	if ctx.has("ai_designs"):
		return ctx["ai_designs"]
	var out := {}
	for rec in Designs.designs_of(ctx["state"], ctx["e"].id, true):
		if rec.has("role"):
			out[String(rec["role"])] = rec
	ctx["ai_designs"] = out
	return out


## Le modèle de l'IA qui remplace cette classe, s'il peut être lancé maintenant ; sinon la classe.
static func _own_design(ctx: Dictionary, cls: String) -> String:
	if cls == "":
		return cls
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var rec: Dictionary = _ai_designs(ctx).get(cls, {})
	if rec.is_empty():
		return cls
	var id := String(rec["id"])
	if not Fleets.ship_unlocked(state, e.id, id) or not Economy.can_afford(e, Fleets.ship_cost(state, e.id, id)):
		return cls
	return id


## Classe de vaisseau de guerre à construire, parmi celles qu'un chantier peut lancer tout de suite
## (bâtiment requis, ressources, titan unique). Les classes de peuple remplacent leur modèle commun
## (`_variant` : le Coursier de saut d'Ossarane à la place de la corvette, par exemple).
## - Recrue : au petit bonheur (hachage de la graine et du jour), titan compris.
## - Normal : corvettes tant qu'on est pauvre, frégates ensuite, un escorteur de temps en temps,
##   des troupes (transport ou croiseur) quand la guerre en manque.
## - Vétéran et plus : un méga-vaisseau dès qu'il est possible (le plus haut échelon d'abord) ; des troupes quand il en manque ; un écran
##   quand la flotte n'en a pas assez (escorteurs contre missiles et chasseurs) ; des torpilleurs
##   contre les grosses coques ennemies ; cuirassés ou porte-vaisseaux une fois l'arsenal bâti ;
##   une bombarde pour les sièges ; sinon ce qui contre la flotte ennemie la plus visible.
static func _pick_warship(ctx: Dictionary) -> String:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var classes := _buildable_warships(ctx)
	if classes.is_empty():
		return ""
	var skill := _skill(ctx)
	if skill <= 0:
		return classes[posmod(hash([state.seed_value, state.tick, e.id, "warship"]), classes.size())]
	var mats := _res(ctx, "materials")
	var at_war := not e.wars.is_empty()
	var troops := 0
	var mine := {}
	var total := 0
	for f in _warfleets(ctx):
		troops += f.troops
		for sh in f.ships:
			mine[Combat.ship_line(sh)] = int(mine.get(Combat.ship_line(sh), 0)) + 1
			total += 1
	@warning_ignore("integer_division")
	var turn := state.tick / 10 + e.id
	if skill == 1:
		if at_war and troops < 20 and posmod(turn, 3) == 0:
			var t := _first(classes, ["transport", "croiseur"])
			if t != "":
				return t
		if posmod(turn, 5) == 0 and classes.has("escorteur"):
			return "escorteur"
		var base := _variant(classes, "corvette") if mats < 200 else _variant(classes, "fregate")
		return base if base != "" else classes[0]
	# Méga-vaisseaux : l'échelon le plus haut qu'on sait lancer (un seul de chaque par empire).
	for mega in ["nef_monde", "leviathan", "titan"]:
		if classes.has(mega):
			return mega
	if at_war and troops < 24:
		var t := _first(classes, ["transport", "croiseur"])
		if t != "":
			return t
	# Ce que montre la flotte ennemie la plus visible.
	var shields := 0
	var bare := 0
	var big := 0
	var interceptable := 0
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.owner == e.id or not Combat.is_armed(f) or not Fleets.fleet_visible(state, e.id, f, _seen(ctx)):
			continue
		for sh in f.ships:
			if int(GameData.ship(sh).get("shield", 0)) >= 20:
				shields += 1
			else:
				bare += 1
			if ["large", "titan"].has(Combat.ship_size(sh)):
				big += 1
			for k in Combat.weapons(sh):
				if Combat.data()["weapons"][k].get("intercept", false):
					interceptable += 1
	if total >= 3 and int(mine.get("screen", 0)) * 3 < total:
		if interceptable >= 2 and classes.has("escorteur"):
			return "escorteur"
		if at_war and classes.has("martyr") and posmod(turn, 2) == 0:
			return "martyr"
		var sc := _variant(classes, "corvette")
		if sc != "":
			return sc
	if big >= 2 and classes.has("torpilleur"):
		return "torpilleur"
	if mats >= 450:
		var heavy := _variant(classes, "porte_vaisseaux") if interceptable < 3 else ""
		if heavy == "":
			heavy = _first(classes, ["cuirasse"])
		if heavy != "":
			return heavy
	if at_war and classes.has("bombarde") and posmod(turn, 4) == 0:
		return "bombarde"
	var pick := ""
	if shields > bare:
		pick = _variant(classes, "croiseur") if mats >= 300 else _variant(classes, "corvette")
	else:
		pick = _variant(classes, "fregate") if mats >= 140 else _variant(classes, "corvette")
	return pick if pick != "" else classes[0]


## Classes de guerre lançables tout de suite quelque part : bâtiment requis présent, titan pas encore
## construit, ressources et population suffisantes. Vérification légère, gardée pour la réflexion.
static func _buildable_warships(ctx: Dictionary) -> Array[String]:
	if ctx.has("buildable_warships"):
		return ctx["buildable_warships"]
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var have := {}
	var free_yard := false
	var max_pop := 0
	for c in _my_colonies(ctx):
		if not c.is_colony():
			continue
		for b in c.buildings:
			have[b] = true
		if c.ship_build == "":
			free_yard = true
			max_pop = maxi(max_pop, c.population)
	var out: Array[String] = []
	if free_yard:
		for sid in FactionTraits.ship_ids_for(e.faction_id):
			var sd := GameData.ship(sid)
			if not Combat.is_military(sid) or not Fleets.ship_unlocked(state, e.id, sid) \
					or not Economy.can_afford(e, Fleets.ship_cost(state, e.id, sid)):
				continue
			if int(sd.get("pop_cost", 0)) >= max_pop and int(sd.get("pop_cost", 0)) > 0:
				continue
			var req: Dictionary = sd.get("requires", {})
			if req.has("building") and not have.has(String(req["building"])):
				continue
			if req.get("unique_per_empire", false) and Fleets.count_same_hull(state, e.id, sid) > 0:
				continue
			out.append(sid)
	ctx["buildable_warships"] = out
	return out


## La classe `base` si elle est au catalogue, sinon la classe de peuple qui la remplace ("" sinon).
static func _variant(classes: Array[String], base: String) -> String:
	if classes.has(base):
		return base
	for sid in classes:
		if String(GameData.ship(sid).get("replaces", "")) == base:
			return sid
	return ""


## La première des classes voulues (ou leur variante de peuple) qui est au catalogue.
static func _first(classes: Array[String], wanted: Array) -> String:
	for w in wanted:
		var v := _variant(classes, String(w))
		if v != "":
			return v
	return ""


## Tactique adaptée à une flotte : selon ses armes (Vétéran et plus), toujours la même pour les autres.
static func tactic_for(ctx: Dictionary, f: Fleet) -> String:
	var skill := _skill(ctx)
	if skill <= 0:
		return "assaut"  # la Recrue charge, même avec des missiles
	# Une flotte qui peut suivre l'Adaptative (Frégate des Quarante) la prend dès que le peuple est connu.
	if _use(ctx) >= 1 and Combat.tactic_ids_for(f).has("adaptatif"):
		return "adaptatif"
	if skill == 1:
		return Combat.default_tactic()
	var by_phase := [0, 0, 0]
	for s in f.ships:
		var w := Combat.weapons(s)
		for k in w:
			for i in 3:
				by_phase[i] += int(w[k]) * Combat.weapon_eff(String(k), i)
	if by_phase[0] > by_phase[2] * 5 / 4:
		return "distance"
	if by_phase[2] > by_phase[0] * 5 / 4:
		return "assaut"
	return Combat.default_tactic()


## Système d'un empire ennemi le plus facile à prendre : garnison, flottes vues sur place, distance.
static func war_target(ctx: Dictionary, from: int) -> int:
	var key := "target_%d" % from
	if not ctx.has(key):
		ctx[key] = _war_target(ctx, from)
	return ctx[key]


static func _war_target(ctx: Dictionary, from: int) -> int:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var res := Fleets._dijkstra(state, e.id, from)
	var best := -1
	var best_score := 0
	var ids: Array = res["dist"].keys()
	ids.sort()
	for k in ids:
		var sid := int(k)
		var owner := _owner(ctx, sid)
		if owner < 0 or not e.wars.has(owner) or not e.explored.has(sid):
			continue
		var defense := Intel.garrison_in(state, e, _seen(ctx), sid) + _defense_at(ctx, sid) * 2
		@warning_ignore("integer_division")
		var score := defense * 10 + int(res["dist"][k]) / 20
		if best == -1 or score < best_score:
			best = sid
			best_score = score
	return best


## Puissance armée ennemie vue dans un système.
static func _defense_at(ctx: Dictionary, sid: int) -> int:
	return int(_enemy_power_map(ctx).get(sid, 0))


## Puissance armée ennemie (en guerre avec nous) vue à l'arrêt, par système : calculée une fois par réflexion.
static func _enemy_power_map(ctx: Dictionary) -> Dictionary:
	if ctx.has("enemy_map"):
		return ctx["enemy_map"]
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var out := {}
	if not e.wars.is_empty():
		var seen := _seen(ctx)
		for fid in state.sorted_fleet_ids():
			var f: Fleet = state.fleets[fid]
			if f.is_moving() or not e.wars.has(f.owner) or not seen.has(f.system_id) or not Combat.is_armed(f):
				continue
			out[f.system_id] = int(out.get(f.system_id, 0)) + Combat.fleet_power(f)
	ctx["enemy_map"] = out
	return out


static func _capital_system(ctx: Dictionary) -> int:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	return FactionTraits.capital_system(state, e.id)


static func _command_warfleets(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var mil := _mil(ctx)
	var skill := _skill(ctx)
	var home := _capital_system(ctx)
	if home < 0:
		return
	var fleets := _warfleets(ctx)
	# Tactiques.
	for f in fleets:
		var tac := tactic_for(ctx, f)
		if Combat.fleet_tactic(f) != tac:
			_issue(ctx, SimCommands.set_tactic(e.id, f.id, tac))
	# Rassembler les flottes à l'arrêt dans un même système (sauf la Recrue, qui les envoie une par une).
	if bool(mil.get("concentrate", true)):
		var first := {}
		for f in fleets:
			if f.is_moving() or not state.fleets.has(f.id):
				continue
			if first.has(f.system_id):
				_issue(ctx, SimCommands.merge_fleets(e.id, f.id, int(first[f.system_id])))
			else:
				first[f.system_id] = f.id
		fleets = _warfleets(ctx)
	# Systèmes à secourir : assiégés, ou avec une flotte ennemie armée.
	var threatened := -1
	for k in state.sieges:
		if state.system_owner(int(k)) == e.id and (threatened == -1 or int(k) < threatened):
			threatened = int(k)
	if threatened == -1:
		var emap := _enemy_power_map(ctx)
		var keys := emap.keys()
		keys.sort()
		for k in keys:
			if state.system_owner(int(k)) == e.id:
				threatened = int(k)
				break
	for f in fleets:
		if not state.fleets.has(f.id):
			continue
		_command_fleet(ctx, f, home, threatened)


static func _command_fleet(ctx: Dictionary, f: Fleet, home: int, threatened: int) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var mil := _mil(ctx)
	var here := f.system_id
	# Retraite : en bataille et nettement dominé (pas la Recrue).
	if not f.is_moving() and bool(mil.get("retreat", false)) and not Combat.battle_at(state, here).is_empty():
		var enemy := _defense_at(ctx, here)
		if Combat.fleet_power(f) * 100 < enemy * 60 and here != home:
			if _issue(ctx, SimCommands.move_fleet(e.id, f.id, home)):
				_intent(ctx, "Sonne la retraite vers la capitale")
			return
	if f.is_moving():
		return
	# Sur un système ennemi : invasion si possible, sinon on tient le siège.
	var owner := state.system_owner(here)
	if owner >= 0 and e.wars.has(owner):
		if _issue(ctx, SimCommands.invade(e.id, f.id)):
			_intent(ctx, "Envahit %s" % state.galaxy.systems[here].system_name)
		return
	if not Combat.battle_at(state, here).is_empty():
		return  # on tient la position jusqu'à la fin de la bataille
	# Défense d'un système menacé.
	if threatened >= 0 and threatened != here and not _forgets(ctx):
		if _issue(ctx, SimCommands.move_fleet(e.id, f.id, threatened)):
			_intent(ctx, "Vole au secours de %s" % state.galaxy.systems[threatened].system_name)
		return
	if e.wars.is_empty() or threatened == here:
		if here != home and threatened < 0:
			_issue(ctx, SimCommands.move_fleet(e.id, f.id, home))
		return
	# Offensive : passé le délai de grâce (les premiers mois servent à s'installer), et quand la flotte
	# est assez forte pour la cible (la Recrue part sans compter).
	if state.tick < int(GameData.ai().get("war", {}).get("grace_days", 360)):
		return
	var target := war_target(ctx, home)
	if target < 0 or _forgets(ctx):
		return
	var need := int(mil.get("attack_ratio_pct", 130))
	@warning_ignore("integer_division")
	var defense := _defense_at(ctx, target) + Intel.garrison_in(state, e, _seen(ctx), target) / 4
	if _skill(ctx) >= 1 and Combat.fleet_power(f) * 100 < need * maxi(8, defense):
		if here != home:
			_issue(ctx, SimCommands.move_fleet(e.id, f.id, home))  # on rentre grossir la flotte
		return
	if _issue(ctx, SimCommands.move_fleet(e.id, f.id, target)):
		_intent(ctx, "Lance une offensive sur %s" % state.galaxy.systems[target].system_name)


# --- 7. Diplomatie -----------------------------------------------------------------------------

## Diplomatie : voir AiDiplomacy. L'Essaim Kh'thari n'y entre jamais.
static func _diplomacy(ctx: Dictionary) -> void:
	AiDiplomacy.think(ctx)
	AiEspionage.think(ctx)


# --- Recherche ---------------------------------------------------------------------------------

## Poids de base de chaque domaine pour l'IA (×10), avant le tempérament et la guerre.
const RESEARCH_WEIGHTS := {"armement": 14, "genie": 11, "economie": 12, "societe": 10}
## Technologies connues avant que l'IA ne pousse le chemin de sa victoire de peuple.
const VICTORY_PATH_AFTER := 20
## Une technologie d'ère plus avancée vaut plus que son prix : ×1,8 par ère (en centièmes).
const ERA_VALUE := [100, 180, 324, 583, 1050]


## Garde deux technologies en file. Le choix pèse l'intérêt du domaine (tempérament du peuple et de
## l'IA, guerre, penchant de recherche du peuple) contre le coût. La Recrue choisit avec du bruit,
## et ne voit pas qu'une technologie hérétique fâche son dieu ; les autres l'évitent.
static func _research(ctx: Dictionary) -> void:
	var e: Empire = ctx["e"]
	var guard := 0
	while e.research_queue.size() < 2 and guard < 3:
		guard += 1
		if _forgets(ctx):
			return
		var tid := research_pick(ctx)
		if tid == "" or not _issue(ctx, SimCommands.research(e.id, tid)):
			return
		if e.research_queue.size() == 1:
			_intent(ctx, "Recherche : %s" % String(Research.tech(tid).get("label", tid)))


## Meilleure technologie à mettre en file ("" si aucune).
static func research_pick(ctx: Dictionary) -> String:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var f := e.faction()
	var use := _use(ctx)
	var weights := research_weights(ctx)
	var labs := _lab_techs()
	var victory_techs: Array[String] = []
	if Victory.people_enabled(state):
		victory_techs = Victory.people_techs(f)
	# Le chemin vers la victoire de peuple ne passe qu'après les bases (bâtiment de recherche, économie).
	var path := victory_path(state, e, victory_techs) if e.techs.size() >= VICTORY_PATH_AFTER else {}
	var bias_techs: Array = []
	if use >= 1 and ctx["ai"].has("building_bias"):
		bias_techs = GameData.building(String(ctx["ai"]["building_bias"])).get("requires_tech", [])
	var best := ""
	var best_score := -1
	var colonies := Research.cost_colonies(state, e.id)
	for tid in Research.visible_ids(f):
		if e.techs.has(tid) or e.research_queue.has(tid) or Research.check_queue(state, e.id, tid) != "":
			continue
		if use >= 1 and Research.is_heretic(f, tid):
			continue
		var t := Research.tech(tid)
		var era := clampi(int(t.get("era", 1)), 1, ERA_VALUE.size())
		var w := int(weights.get(String(t["domain"]), 10))
		if labs.has(tid) or bias_techs.has(tid):
			w *= 3  # le bâtiment de recherche et celui du penchant du peuple d'abord (Raffinerie d'Ossarane)
		if victory_techs.has(tid):
			w *= 6 if use >= 1 else 2  # la technologie de sa victoire de peuple, dès que l'ère s'ouvre
		elif path.has(tid):
			w *= int(path[tid]) if use >= 1 else 2  # le chemin qui y mène : ses prérequis, puis l'ère à ouvrir
		@warning_ignore("integer_division")
		var score := w * int(ERA_VALUE[era - 1]) * 1000 / maxi(1, Research.cost(state, e.id, tid, colonies) - int(e.research_shelf.get(tid, 0)))
		if use == 0:
			score = score * (50 + posmod(hash([state.seed_value, e.id, tid, e.techs.size()]), 100)) / 100
		if score > best_score:
			best_score = score
			best = tid
	return best


## Chemin vers les technologies de victoire pas encore connues : id -> multiplicateur de poids.
## Leurs prérequis (récursivement) comptent ×5 ; les technologies des ères précédentes de leur
## domaine comptent ×4 tant que l'ère n'est pas ouverte (il en faut assez pour l'ouvrir) : sans quoi
## les peuples guerriers, qui pèsent surtout l'armement, n'atteignent jamais l'ère IV de Société.
static func victory_path(_state: GameState, e: Empire, victory_techs: Array[String]) -> Dictionary:
	var out := {}
	for vt in victory_techs:
		if e.techs.has(vt):
			continue
		var t := Research.tech(vt)
		var dom := String(t.get("domain", ""))
		var era := int(t.get("era", 1))
		if not Research.era_open(e.techs, dom, era):
			for tid in Research.visible_ids(e.faction()):
				var o := Research.tech(tid)
				if String(o["domain"]) == dom and int(o["era"]) < era:
					out[tid] = 4
		var todo: Array = Array(t.get("pre", []))
		while not todo.is_empty():
			var p := String(todo.pop_back())
			if e.techs.has(p) or int(out.get(p, 0)) == 5:
				continue
			out[p] = 5
			todo.append_array(Research.tech(p).get("pre", []))
	return out


## Poids des domaines pour cet empire : tempérament (armement contre société), guerre en cours,
## penchant du peuple (bloc ai.research_bias de data/factions.json).
static func research_weights(ctx: Dictionary) -> Dictionary:
	var e: Empire = ctx["e"]
	var w := RESEARCH_WEIGHTS.duplicate()
	var a := AiLevels.aggression(e)
	w["armement"] = int(w["armement"]) + 2 * a
	w["societe"] = int(w["societe"]) - a
	if not e.wars.is_empty():
		w["armement"] = int(w["armement"]) + 6
		w["genie"] = int(w["genie"]) + 3
	var bias: Dictionary = ctx["ai"].get("research_bias", {}) if _use(ctx) >= 1 else {}
	for d in bias:
		w[d] = int(w.get(d, 10)) + int(bias[d])
	for d in w:
		w[d] = maxi(2, int(w[d]))
	return w


static var _labs_cache := {}


## Technologies qui débloquent un bâtiment producteur de Savoir.
static func _lab_techs() -> Dictionary:
	if _labs_cache.is_empty():
		for bid in GameData.buildings():
			var bd := GameData.building(bid)
			if int(bd.get("yields", {}).get("knowledge", 0)) > 0:
				for t in bd.get("requires_tech", []):
					_labs_cache[String(t)] = true
		_labs_cache["_"] = true
	return _labs_cache


## Bâtiments de recherche de l'empire (achevés ou en chantier) : un pour cinq revendications au plus,
## le reste des emplacements nourrit l'économie.
static func _lab_count(ctx: Dictionary) -> int:
	var n := 0
	for c in _my_colonies(ctx):
		for b in c.buildings:
			if int(GameData.building(b).get("yields", {}).get("knowledge", 0)) > 0:
				n += 1
		if c.construction != "" and int(GameData.building(c.construction).get("yields", {}).get("knowledge", 0)) > 0:
			n += 1
	return n


## Bâtiment de recherche débloqué pour ce peuple ("" si aucun encore).
static func research_building(ctx: Dictionary) -> String:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	for bid in GameData.buildings():
		var bd := GameData.building(bid)
		if not bd.has("requires_tech") or int(bd.get("yields", {}).get("knowledge", 0)) <= 0:
			continue
		if Economy.building_unlocked(state, e.id, bid):
			return String(bid)
	return ""
