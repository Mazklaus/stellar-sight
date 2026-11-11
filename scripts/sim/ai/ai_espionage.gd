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
