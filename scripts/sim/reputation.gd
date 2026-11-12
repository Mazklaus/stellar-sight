class_name Reputation
extends RefCounted
## Registre Picaresque : la réputation (« on parle de nous »), de 0 à 100, et les exploits qui
## nourrissent la victoire de la Légende. Règles dans le champ "reputation" de la fiche (couche
## registre de data/species_parts.json).
##
## Inspiration : étude « l'espionnage comme pilier de Stellar Sigth » (proposition 9, validée le
## 2026-11-11) : chaque opération réussie ou découverte fait monter la réputation, qui renchérit les
## contrats de flotte et facilite les intrigues ; être pris coûte moins d'estime. Le document de game
## design donne au registre « contrats, réputation, vol de technologies, coups de chance » et au
## Syndicat Brisecomète « vit de sa réputation ».

## Exploits de la Légende, dans l'ordre d'affichage : [id, libellé].
const EXPLOITS := [
	["david", "Vaincre une flotte trois fois plus forte"],
	["vol", "Voler une technologie"],
	["siphon", "Siphonner l'énergie d'un rival"],
	["sabotage", "Saboter un chantier"],
	["archives", "Brûler des archives"],
	["discorde", "Semer la discorde entre deux amis"],
	["heritier", "Corrompre un héritier"],
	["rapport", "Obtenir un rapport complet"],
	["contrat", "Mener un contrat de flotte à terme"],
	["double_jeu", "Démasquer un réseau retourné"],
	["renommee", "Atteindre 100 de réputation"],
]

static func has(faction: Dictionary) -> bool:
	return faction.has("reputation")


static func cfg(state: GameState, empire_id: int) -> Dictionary:
	var e := state.get_empire(empire_id)
	return {} if e == null else e.faction().get("reputation", {})


static func of(state: GameState, empire_id: int) -> int:
	var e := state.get_empire(empire_id)
	return 0 if e == null or not has(e.faction()) else e.reputation


## Fait varier la réputation d'un empire picaresque (sans effet pour les autres).
static func gain(state: GameState, empire_id: int, key: String) -> void:
	var c := cfg(state, empire_id)
	if c.is_empty():
		return
	add(state, empire_id, int(c.get(key, 0)))


static func add(state: GameState, empire_id: int, amount: int) -> void:
	var e := state.get_empire(empire_id)
	if e == null or not has(e.faction()) or amount == 0:
		return
	var mx := int(e.faction()["reputation"].get("max", 100))
	e.reputation = clampi(e.reputation + amount, 0, mx)
	if e.reputation >= mx:
		exploit(state, empire_id, "renommee")


## Note un exploit (une fois par sorte) ; chaque nouvel exploit fait aussi parler de soi.
static func exploit(state: GameState, empire_id: int, id: String) -> void:
	var e := state.get_empire(empire_id)
	if e == null or not has(e.faction()) or e.exploits.has(id):
		return
	e.exploits[id] = state.tick
	var label := id
	if id.begins_with("relique_"):
		label = "Voler %s" % String(Relics.def(id.trim_prefix("relique_")).get("name", "une relique"))
	for x in EXPLOITS:
		if String(x[0]) == id:
			label = String(x[1])
	state.add_chronicle("Exploit de %s : %s. Les tavernes de trois secteurs en font déjà une chanson, avec des couplets inventés." % [
			e.display_name(), label.to_lower()], Espionage.private_to(state, [empire_id]))
	if id != "renommee":
		add(state, empire_id, int(e.faction()["reputation"].get("exploit", 0)))
	Heroes.on_exploit(state, empire_id)


## Bilan du mois : la réputation s'use (ce qu'elle rapporte passe par Economy.empire_income).
static func monthly(state: GameState) -> void:
	for e in state.empires:
		if e.eliminated or not has(e.faction()):
			continue
		e.reputation = maxi(0, e.reputation - int(e.faction()["reputation"].get("decay", 0)))


## Énergie par mois que rapporte la réputation actuelle (« crédits »).
static func income(state: GameState, empire_id: int) -> int:
	var per := int(cfg(state, empire_id).get("energy_per", 0))
	@warning_ignore("integer_division")
	return 0 if per <= 0 else of(state, empire_id) / per


## Majoration en % du prix des contrats de flotte du mercenaire.
static func fee_pct(state: GameState, empire_id: int) -> int:
	var per := int(cfg(state, empire_id).get("fee_per", 0))
	@warning_ignore("integer_division")
	return 0 if per <= 0 else of(state, empire_id) / per


## Bonus de réussite (points de %) aux opérations d'intrigue.
static func intrigue_bonus(state: GameState, empire_id: int) -> int:
	var per := int(cfg(state, empire_id).get("intrigue_per", 0))
	@warning_ignore("integer_division")
	return 0 if per <= 0 else of(state, empire_id) / per


## Souvenir laissé à la victime quand des espions de cet empire sont pris.
static func caught_memory(state: GameState, empire_id: int) -> String:
	return String(cfg(state, empire_id).get("caught_memory", "spy_caught"))


## Fin d'une bataille : exploit contre plus fort, et réputation des vaincus.
static func battle(state: GameState, b: Dictionary, winner: int) -> void:
	if winner < 0:
		return
	var own := 0
	var foes := 0
	for s: Dictionary in b["sides"]:
		var power := 0
		for ship in s["engaged"]:
			power += Combat.ship_strength(String(ship)) * int(s["engaged"][ship])
		if int(s["empire"]) == winner:
			own += power
		elif Combat.at_war(state, winner, int(s["empire"])):
			foes += power
			gain(state, int(s["empire"]), "battle_lost")
	if own > 0 and foes >= 3 * own and has(state.get_empire(winner).faction()):
		gain(state, winner, "david")
		exploit(state, winner, "david")


static func exploit_count(state: GameState, empire_id: int) -> int:
	var e := state.get_empire(empire_id)
	return 0 if e == null else e.exploits.size()


static func gauge(state: GameState, empire_id: int) -> Dictionary:
	var e := state.get_empire(empire_id)
	var c: Dictionary = e.faction()["reputation"]
	var tip := "Réputation %d / %d (-%d par mois) : +%d énergie par mois" % [e.reputation, int(c.get("max", 100)), int(c.get("decay", 0)), income(state, empire_id)]
	if intrigue_bonus(state, empire_id) > 0:
		tip += ", intrigues +%d %%" % intrigue_bonus(state, empire_id)
	if Diplomacy.has_ability(state, empire_id, "mercenary"):
		var ct := Diplomacy.contract_of(state, empire_id)
		if ct.is_empty():
			tip += "\nFlottes libres : %s par mois à la location (+%d %% de réputation)." % [
					GameData.format_amounts(Diplomacy.contract_fee(state, empire_id)), fee_pct(state, empire_id)]
		else:
			tip += "\nFlottes louées à %s contre %s : %s par mois." % [state.get_empire(int(ct["client"])).short_name(),
					state.get_empire(int(ct["target"])).short_name(), GameData.format_amounts(ct["fee"])]
	tip += "\nExploits : %d / %d" % [e.exploits.size(), EXPLOITS.size()]
	return {"label": "Réputation", "value": "%d" % e.reputation, "tip": tip}
