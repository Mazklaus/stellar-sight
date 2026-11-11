class_name AiEspionage
extends RefCounted
## Espionnage des empires IA (lot 1 : affecter les cellules, voir Espionage).
##
## Une fois par mois environ, l'IA répartit ses cellules :
## - une chez elle (contre-espionnage) dès qu'elle a rencontré quelqu'un ;
## - les autres chez sa cible principale : l'ennemi en guerre (le plus petit identifiant d'abord),
##   sinon l'empire rencontré qu'elle aime le moins ; une cellule va à une deuxième cible quand elle
##   en a trois ou plus à placer. Pas d'espionnage des alliés (le lot 2 rendra cela risqué).
## La Recrue « utilise mal » : tout chez le premier empire rencontré, rien chez elle.
## Opérations (lot 2) : une à la fois, quand l'influence le permet (une réserve gardée de côté).
## En guerre : saboter puis voler ; en paix, selon le tempérament : voler (pas les pacifiques) ou
## commander un rapport. La Recrue lance la première qui passe, sans regarder ses chances ; les
## autres veulent au moins 50 % de succès et, en paix, au plus 40 % de risque d'être prises.
## Lot 3 : en guerre, elle corrompt l'héritier d'une dynastie et sème la discorde chez l'ennemi après
## les sabotages ; en paix, un tempérament agressif tente aussi l'héritier.
## Réponse à des espions démasqués : à partir de Vétéran, retourner le réseau quand elle a des agents
## chez elle pour le mener ; sinon expulser un ennemi ou un empire mal aimé, sinon exiger réparation.
## Registre Picaresque : en paix aussi, le siphon est permis ; les opérations qui donnent un exploit
## manquant passent en premier (victoire de la Légende), et être pris fait moins peur (60 % de risque
## au plus, puisque cela fait parler de soi).
## Déterministe : ordre des identifiants, opinions entières, aucun aléatoire.


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var every := maxi(1, int(ctx["lv"].get("think_days", 10)))
	if posmod(state.tick + e.id * 7, 30) >= every:
		return
	var want := plan(state, e, int(ctx["lv"].get("faction_use", 1)))
	# D'abord rappeler les cellules en trop, puis affecter les libres.
	var ks := want.keys()
	ks.sort()
	var current := []
	for k in state.networks.keys():
		var net: Dictionary = state.networks[k]
		if int(net["a"]) == e.id and int(net["cells"]) > 0:
			current.append(int(net["b"]))
	current.sort()
	for b in current:
		var n := int(want.get(b, 0))
		if Espionage.cells_on(state, e.id, b) > n:
			AiPlayer._issue(ctx, SimCommands.spy_cells(e.id, b, n))
	for b in ks:
		var n := int(want[b])
		if Espionage.cells_on(state, e.id, b) != n:
			AiPlayer._issue(ctx, SimCommands.spy_cells(e.id, b, n))
	_operation(ctx)


const OP_RESERVE := 100
const WAR_OPS := ["sabotage_chantier", "archives", "heritier", "discorde", "vol_techno", "siphon", "rapport"]
const PEACE_OPS := ["vol_techno", "heritier", "rapport"]
const CALM_OPS := ["rapport"]
const ROGUE_PEACE_OPS := ["vol_techno", "siphon", "heritier", "rapport"]
## Exploit de la Légende que donne chaque opération réussie.
const OP_EXPLOITS := {"vol_techno": "vol", "siphon": "siphon", "sabotage_chantier": "sabotage", "archives": "archives",
		"discorde": "discorde", "heritier": "heritier", "rapport": "rapport"}


static func _operation(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if AiPlayer._forgets(ctx):
		return
	var use := int(ctx["lv"].get("faction_use", 1))
	var calm := AiLevels.aggression(e) < 0
	var rogue := use > 0 and Reputation.has(e.faction())
	var ks := state.networks.keys()
	ks.sort()
	for k in ks:
		var net: Dictionary = state.networks[k]
		var b := int(net["b"])
		if int(net["a"]) != e.id or b == e.id or Diplomacy.allied(state, e.id, b):
			continue
		if not Espionage.running(state, e.id, b).is_empty():
			continue
		var war := Combat.at_war(state, e.id, b)
		var menu: Array = WAR_OPS if war else (CALM_OPS if calm else PEACE_OPS)
		if rogue:
			menu = _rogue_menu(e, WAR_OPS if war else ROGUE_PEACE_OPS)
		for op_id in menu:
			if Espionage.check_op(state, e.id, b, op_id) != "":
				continue
			var cost := Espionage.op_cost(state, e.id, op_id)
			if int(e.resources.get("influence", 0)) - int(cost.get("influence", 0)) < OP_RESERVE:
				continue
			if use > 0:
				var ch := Espionage.chances(state, e.id, b, op_id)
				if int(ch["success"]) < 50 or (not war and int(ch["discovery"]) > (60 if rogue else 40)):
					continue
			if AiPlayer._issue(ctx, SimCommands.spy_op(e.id, b, op_id)):
				return


## Les opérations d'abord qui donneraient un exploit encore manquant, dans l'ordre du menu.
static func _rogue_menu(e: Empire, base: Array) -> Array:
	var first := []
	var then := []
	for op_id in base:
		if e.exploits.has(String(OP_EXPLOITS.get(op_id, ""))):
			then.append(op_id)
		else:
			first.append(op_id)
	return first + then


## Réponse de l'IA victime : "turn", "expel" ou "reparation".
static func response(state: GameState, victim: int, spy: int) -> String:
	var ev := state.get_empire(victim)
	if int(AiLevels.level(ev.ai_level).get("faction_use", 1)) >= 2 and Espionage.check_turn(state, victim, spy) == "":
		return "turn"
	if Combat.at_war(state, victim, spy) or Diplomacy.opinion(state, victim, spy) < -30:
		return "expel"
	return "reparation"


## Répartition voulue {empire visé: cellules} (l'empire lui-même = contre-espionnage).
static func plan(state: GameState, e: Empire, use: int) -> Dictionary:
	var total := Espionage.cells_total(state, e.id)
	var alive: Array[int] = []
	for o in e.contacts:
		var oe := state.get_empire(o)
		if oe != null and not oe.eliminated:
			alive.append(o)
	var out := {}
	if alive.is_empty() or total <= 0:
		return out
	if use <= 0:
		out[alive[0]] = total
		return out
	out[e.id] = 1
	var left := total - 1
	var targets: Array[int] = []
	for o in alive:
		if Combat.at_war(state, e.id, o):
			targets.append(o)
	var others: Array = []
	for o in alive:
		if targets.has(o) or Diplomacy.allied(state, e.id, o):
			continue
		others.append([Diplomacy.opinion(state, e.id, o), o])
	others.sort()
	for pair in others:
		targets.append(int(pair[1]))
	if targets.is_empty() or left <= 0:
		return out
	if left >= 3 and targets.size() >= 2:
		out[targets[1]] = 1
		left -= 1
	out[targets[0]] = left
	return out
