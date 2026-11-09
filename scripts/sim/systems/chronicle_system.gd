class_name ChronicleSystem
extends RefCounted
## Système de simulation d'exemple : de petits événements galactiques racontés
## par le chroniqueur. Il n'a pas d'effet de jeu ; il sert surtout à montrer comment
## un système de simulation consomme l'aléatoire de façon déterministe.

const PERIOD_DAYS := 15
const CHANCE := 0.4

const EVENTS := [
	"Une comète frôle %s. Les astrologues locaux annoncent, au choix, la fin du monde ou une bonne récolte.",
	"Une éruption de %s brouille les communications pendant trois jours. Personne ne s'en plaint vraiment.",
	"Des marchands affirment avoir vu une baleine stellaire près de %s. Le prix de leurs boissons a été revu.",
	"Un astéroïde d'or pur est repéré en orbite de %s. Après vérification : de la pyrite. Beaucoup de pyrite.",
	"Les sondes relèvent un signal régulier venant de %s. C'était un pulsar. Ou un très patient voisin.",
	"Une nébuleuse dérive lentement vers %s, dans un silence qui se veut majestueux.",
	"Un pèlerin solitaire traverse %s à pied. Personne ne sait comment, ni pourquoi.",
	"Les savants de la galaxie s'accordent à dire que %s est « assez joli, vu de loin ».",
]


## Fait avancer le système d'un tick. Renvoie les entrées de chronique ajoutées.
static func process(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if state.tick % PERIOD_DAYS != 0:
		return added
	if state.rng.randf() >= CHANCE:
		return added
	var sys := state.galaxy.systems[state.rng.randi_range(0, state.galaxy.systems.size() - 1)]
	var template: String = EVENTS[state.rng.randi_range(0, EVENTS.size() - 1)]
	added.append(state.add_chronicle(template % sys.system_name))
	return added
