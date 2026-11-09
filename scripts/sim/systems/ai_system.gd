class_name AiSystem
extends RefCounted
## Empires IA, exécutés à la fin de chaque tick.
##
## Chaque IA réfléchit à son rythme (think_days de son niveau), en décalé selon son identifiant
## pour que toutes ne pensent pas le même jour. Elle ne voit que ce que voit son empire
## (systèmes explorés, routes connues) et n'agit que par des ordres ordinaires (SimCommands),
## validés comme ceux d'un joueur : elle ne peut rien faire qu'un humain ne puisse pas faire.
##
## Tout est déterministe (aucun aléatoire hors de l'état, parcours dans l'ordre des identifiants) :
## l'IA marche à l'identique en temps réel et au tour par tour, dans une rediffusion,
## et sur toutes les machines d'une partie en réseau.


static func process(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	for e in state.empires:
		if not e.is_ai() or e.eliminated or not should_think(state, e):
			continue
		var last: Variant = state.chronicle.back() if not state.chronicle.is_empty() else null
		AiPlayer.think(state, e)
		# Les ordres appliqués ont pu écrire dans la chronique (offrande…) : on les remonte,
		# du plus récent jusqu'à la dernière entrée d'avant la réflexion.
		var fresh: Array[Dictionary] = []
		for i in range(state.chronicle.size() - 1, -1, -1):
			if last != null and is_same(state.chronicle[i], last):
				break
			fresh.push_front(state.chronicle[i])
		added.append_array(fresh)
	return added


## L'IA de cet empire réfléchit-elle ce jour-ci ?
static func should_think(state: GameState, e: Empire) -> bool:
	var every := maxi(1, int(AiLevels.level(e.ai_level).get("think_days", 10)))
	return posmod(state.tick + e.id * 3, every) == 0
