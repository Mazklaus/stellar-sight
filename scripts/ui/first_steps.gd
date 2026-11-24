class_name FirstSteps
extends RefCounted
## Premières minutes guidées (refonte D3d) : trois objectifs à la suite, qui apprennent les gestes de
## base. Rien n'est rangé dans la partie : chaque objectif se lit dans l'état (systèmes sondés,
## colonies, recherche), si bien qu'une sauvegarde reprise retrouve le fil où il en était. Le suivi
## disparaît quand les trois sont faits, ou passé deux ans de jeu. Les infobulles et le Codex restent
## pour tout le reste.

## Passé ce nombre de jours, on ne guide plus : la partie est lancée.
const LIMIT_DAYS := 720
## Avec autant de technologies connues, le joueur sait se servir de la recherche (Myrr en a deux au départ).
const RESEARCH_KNOWN := 4
## [id, objectif, geste] dans l'ordre où on les propose.
const STEPS := [
	["survey", "Sonder un système voisin", "Choisissez l'éclaireur, puis E : il part de lui-même vers le système inexploré le plus proche. Un clic droit sur une étoile l'y envoie."],
	["colonize", "Fonder une seconde colonie", "Envoyez le vaisseau colon d'un clic droit dans un système sondé, puis donnez l'ordre de coloniser dans la fiche de la flotte."],
	["research", "Choisir une recherche", "Ouvrez Savoir (F2) et cliquez une technologie : elle entre dans la file."],
]


## Nombre de colonies du joueur (monde natal compris, colonies en fondation comprises).
static func colonies(state: GameState, player: int) -> int:
	var n := 0
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		if c.owner == player and c.is_colony():
			n += 1
	return n


## Les objectifs qui valent pour ce peuple, par indice de STEPS. Un peuple sans monde natal (nomades,
## Signal…) n'est pas guidé : ses premiers gestes ne sont pas ceux-là. Un peuple qui ne colonise pas
## par vaisseau colon garde les deux autres objectifs.
static func steps(state: GameState, player: int) -> Array[int]:
	var out: Array[int] = []
	var e := state.get_empire(player) if state != null else null
	if e == null or e.is_ai() or colonies(state, player) < 1:
		return out
	out.append(0)
	var colon := colonies(state, player) >= 2
	if not colon:
		for fid in state.fleets:
			var f: Fleet = state.fleets[fid]
			if f.owner == player and Fleets.colonizer_ship(f) != "":
				colon = true
				break
	if colon:
		out.append(1)
	out.append(2)
	return out


## Ce qui est fait, objectif par objectif (indices de STEPS).
static func done(state: GameState, player: int) -> Array[bool]:
	var out: Array[bool] = [false, false, false]
	var e := state.get_empire(player) if state != null else null
	if e == null:
		return out
	out[0] = e.surveyed.size() >= 2
	out[1] = colonies(state, player) >= 2
	# Une file vide en tout début de partie ramène l'objectif : c'est le moment où le rappel sert.
	out[2] = not e.research_queue.is_empty() or e.techs.size() >= RESEARCH_KNOWN
	return out


## Le suivi se montre-t-il encore ?
static func active(state: GameState, player: int) -> bool:
	if state == null or state.tick > LIMIT_DAYS:
		return false
	return current(state, player) >= 0


## Indice (dans STEPS) du premier objectif à faire (-1 : tout est fait, ou peuple non guidé).
static func current(state: GameState, player: int) -> int:
	var d := done(state, player)
	for i in steps(state, player):
		if not d[i]:
			return i
	return -1


## Lignes du suivi : [[texte, couleur]...]. Les objectifs faits sont cochés, celui en cours dit le geste.
static func lines(state: GameState, player: int) -> Array:
	var out := []
	if not active(state, player):
		return out
	var d := done(state, player)
	var cur := current(state, player)
	for i in steps(state, player):
		if d[i]:
			out.append(["✓ %s" % STEPS[i][1], Color(UiTheme.GOOD, 0.75)])
		elif i == cur:
			out.append(["▸ %s" % STEPS[i][1], UiTheme.TEXT])
			out.append([String(STEPS[i][2]), Color(UiTheme.TEXT, 0.7)])
		else:
			out.append(["   %s" % STEPS[i][1], Color(UiTheme.TEXT, 0.45)])
	return out
