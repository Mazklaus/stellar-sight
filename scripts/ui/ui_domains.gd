class_name UiDomains
extends RefCounted
## Les huit domaines de l'interface (refonte, proposition A1) : chaque écran d'empire est un onglet
## d'un domaine, ouvert par F1 à F8. Une adresse désigne un écran, ou un écran et son onglet interne :
## "economy", "order:admin", "trade:market", "chronicles:quests".
## Un onglet de domaine peut regrouper plusieurs adresses (le Journal réunit Quêtes, Événements et
## Crise) : l'écran garde alors sa propre rangée d'onglets, réduite à ce groupe.

## id, libellé, touche, pictogramme, onglets [libellé, adresses du groupe].
const DOMAINS := [
	{"id": "empire", "label": "Empire", "key": "F1", "glyph": "economy", "tabs": [
		["Bilan", ["economy"]], ["Colonies", ["colonies"]], ["Peuples", ["peoples"]], ["Ordre", ["order:ordre"]],
		["Administration", ["order:admin"]], ["Trésor", ["order:tresor"]],
		["Grands chantiers", ["wonders", "megas", "forge"]]]},
	{"id": "savoir", "label": "Savoir", "key": "F2", "glyph": "research", "tabs": [
		["Recherche", ["research"]], ["Génome", ["genome"]], ["Songe", ["psionics"]],
		["Fouilles", ["chronicles:archeo", "chronicles:relics"]]]},
	{"id": "forces", "label": "Forces", "key": "F3", "glyph": "armies", "tabs": [
		["Chantier", ["shipyard"]], ["Armées", ["armies"]]]},
	{"id": "diplomatie", "label": "Diplomatie", "key": "F4", "glyph": "diplomacy", "tabs": [
		["Empires", ["diplomacy"]], ["Assemblée", ["amphictyony"]], ["Renseignement", ["intel"]]]},
	{"id": "commerce", "label": "Commerce", "key": "F5", "glyph": "trade", "tabs": [
		["Routes", ["trade:routes"]], ["Marché", ["trade:market", "trade:resources"]],
		["Accords", ["trade:knowledge"]], ["Privé", ["trade:private"]], ["Réseau", ["trade:ports"]]]},
	{"id": "pouvoir", "label": "Pouvoir", "key": "F6", "glyph": "senate", "tabs": [
		["Trône", ["throne:trone"]], ["Cour", ["throne:cour"]], ["Sénat", ["senate"]], ["Foi", ["faith"]],
		["Rayonnement", ["culture"]], ["Panthéon", ["heroes"]]]},
	{"id": "chroniques", "label": "Chroniques", "key": "F7", "glyph": "chronicles", "tabs": [
		["Journal", ["chronicles:quests", "chronicles:events", "chronicles:crisis"]],
		["Annonces", ["chronicles:announces"]],
		["Annales", ["chronicles:annals", "chronicles:hours", "chronicles:deeds"]],
		["Bestiaire", ["chronicles:bestiary"]]]},
	{"id": "victoire", "label": "Victoire", "key": "F8", "glyph": "victory", "tabs": [
		["Victoires", ["victory"]], ["Transcendance", ["transcendence"]], ["Contact", ["contact"]],
		["L'Échelle", ["kardashev"]]]},
]
## Onglet par défaut des écrans à onglets internes.
const DEFAULT_SUB := {"order": "ordre", "throne": "trone", "trade": "routes", "chronicles": "quests"}


static func screen_of(addr: String) -> String:
	return addr.get_slice(":", 0)


static func sub_of(addr: String) -> String:
	return addr.get_slice(":", 1) if addr.contains(":") else ""


## [domaine, onglet] de l'adresse, [-1, -1] si elle n'appartient à aucun domaine.
static func locate(addr: String) -> Array:
	var screen := screen_of(addr)
	if not addr.contains(":") and DEFAULT_SUB.has(screen):
		addr = "%s:%s" % [screen, DEFAULT_SUB[screen]]
	for d in DOMAINS.size():
		var tabs: Array = DOMAINS[d]["tabs"]
		for t in tabs.size():
			if (tabs[t][1] as Array).has(addr):
				return [d, t]
	return [-1, -1]


## Domaine d'une adresse (-1 si aucun).
static func domain_of(addr: String) -> int:
	return int(locate(addr)[0])


## Adresses de l'onglet de domaine qui contient celle-ci (elle seule si elle n'est dans aucun).
static func group(addr: String) -> Array:
	var at := locate(addr)
	if int(at[0]) < 0:
		return [addr]
	return DOMAINS[int(at[0])]["tabs"][int(at[1])][1]


## L'adresse est-elle offerte dans cette partie, pour cet empire ? (Un pilier hors jeu cache son onglet.)
static func offered(state: GameState, player: int, addr: String) -> bool:
	if state == null:
		return true
	var sub := sub_of(addr)
	match screen_of(addr):
		"order":
			return sub != "admin" and sub != "tresor" or (sub == "admin" and Admin.applies(state, player)) \
					or (sub == "tresor" and Finance.applies(state, player))
		"throne":
			return sub != "cour" or Court.applies(state, player)
		"trade":
			if sub == "private":
				return Private.applies(state, player) or (state.get_empire(player) == null and Private.enabled(state))
			return sub != "ports" or Ports.enabled(state)
		"chronicles":
			return ChronicleScreen.tabs(state).has(sub)
		"peoples":
			return state.peoples_on
		"megas":
			return Megastructures.enabled(state)
		"forge":
			return WorldForge.enabled(state)
		"transcendence":
			return Transcendence.enabled(state)
		"contact":
			return Contact.enabled(state)
		"kardashev":
			return Kardashev.enabled(state)
	return true


## Première adresse offerte d'un onglet de domaine ("" si aucune).
static func first_offered(state: GameState, player: int, d: int, t: int) -> String:
	for a: String in DOMAINS[d]["tabs"][t][1]:
		if offered(state, player, a):
			return a
	return ""


## Première adresse offerte d'un domaine ("" si aucune).
static func first_of_domain(state: GameState, player: int, d: int) -> String:
	for t in (DOMAINS[d]["tabs"] as Array).size():
		var a := first_offered(state, player, d, t)
		if a != "":
			return a
	return ""


## Adresse de ce qu'affichent les écrans d'empire ("" si rien).
static func address(es: EmpireScreens) -> String:
	if es == null or es.current == "":
		return ""
	var sub := ""
	match es.current:
		"order":
			sub = OrderScreen.tab
		"throne":
			sub = ThroneScreen.tab
		"trade":
			sub = es.trade_tab
		"chronicles":
			sub = es.chron_tab
		_:
			return es.current
	var addr := "%s:%s" % [es.current, sub]
	if not offered(es._state, es._player, addr):
		addr = "%s:%s" % [es.current, DEFAULT_SUB[es.current]]
	return addr


## Règle l'onglet interne d'une adresse, sans afficher l'écran.
static func apply_sub(es: EmpireScreens, addr: String) -> void:
	var sub := sub_of(addr)
	if sub == "":
		return
	match screen_of(addr):
		"order":
			OrderScreen.tab = sub
		"throne":
			ThroneScreen.tab = sub
		"trade":
			es.trade_tab = sub
		"chronicles":
			es.chron_tab = sub
