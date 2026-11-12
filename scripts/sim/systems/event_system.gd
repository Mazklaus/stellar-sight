class_name EventSystem
extends RefCounted
## Curiosités et événements, exécutés à chaque tick (voir Curios et Events) : les sondes avancent et
## aboutissent, les pièges s'en vont, les réponses en retard prennent le choix par défaut, et chaque
## empire, une fois par mois, peut tirer une carte. Tirages par hachage de la graine.


static func process(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	Curios.daily(state, added)
	Events.daily(state, added)
	Relics.daily(state, added)
	return added
