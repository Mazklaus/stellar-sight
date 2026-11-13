class_name SimCommands
extends RefCounted
## Les ordres des joueurs. C'est le SEUL moyen pour un joueur de modifier la partie.
##
## Un ordre est un simple dictionnaire (facile à envoyer sur le réseau ou à rejouer) :
##   {"type": "rename_system", "player": 0, "system": 12, "name": "Nouvelle-Aube"}
## Il est d'abord validé, puis appliqué par la Simulation à une frontière de tick.
## En multijoueur, les clients enverront leurs ordres à l'hôte, qui les validera,
## fixera leur ordre d'application et les rediffusera.

const NAME_MAX_LENGTH := 32


static func rename_system(player: int, system_id: int, new_name: String) -> Dictionary:
	return {"type": "rename_system", "player": player, "system": system_id, "name": new_name}


## Lance une colonie ("colony") ou un avant-poste ("outpost") sur une planète.
## Une colonie sur un de ses propres avant-postes le transforme en colonie.
## species : peuple de l'empire qui fondera la colonie (voir Peoples) ; "" = celui de l'empire.
static func colonize(player: int, planet_id: int, kind: String = Colony.KIND_COLONY, species := "") -> Dictionary:
	var cmd := {"type": "colonize", "player": player, "planet": planet_id, "kind": kind}
	if species != "":
		cmd["species"] = species
	return cmd


## Lance la construction d'un bâtiment sur une colonie ou un avant-poste.
static func build(player: int, planet_id: int, building_id: String) -> Dictionary:
	return {"type": "build", "player": player, "planet": planet_id, "building": building_id}


## Construit un vaisseau au chantier spatial d'une colonie.
static func build_ship(player: int, planet_id: int, ship_id: String) -> Dictionary:
	return {"type": "build_ship", "player": player, "planet": planet_id, "ship": ship_id}


## Envoie une flotte vers un système, par le plus court chemin connu.
static func move_fleet(player: int, fleet_id: int, system_id: int) -> Dictionary:
	return {"type": "move_fleet", "player": player, "fleet": fleet_id, "system": system_id}


## Arrête une flotte au prochain système (ou fait demi-tour si c'est plus près).
static func stop_fleet(player: int, fleet_id: int) -> Dictionary:
	return {"type": "stop_fleet", "player": player, "fleet": fleet_id}


## Donne (ou retire, avec "") un ordre permanent à une flotte : Fleet.ORDER_EXPLORE.
static func set_fleet_order(player: int, fleet_id: int, order: String) -> Dictionary:
	return {"type": "set_fleet_order", "player": player, "fleet": fleet_id, "order": order}


## Verse tous les vaisseaux d'une flotte dans une autre (même système, à l'arrêt).
static func merge_fleets(player: int, fleet_id: int, into_id: int) -> Dictionary:
	return {"type": "merge_fleets", "player": player, "fleet": fleet_id, "into": into_id}


## Détache un vaisseau d'une classe donnée dans une nouvelle flotte.
static func split_fleet(player: int, fleet_id: int, ship_id: String) -> Dictionary:
	return {"type": "split_fleet", "player": player, "fleet": fleet_id, "ship": ship_id}


## Chœur Éternel : sacrifie un fidèle d'une colonie (-1 population) pour nourrir la ferveur.
static func sacrifice(player: int, planet_id: int) -> Dictionary:
	return {"type": "sacrifice", "player": player, "planet": planet_id}


## Concorde de Vael : vote d'urgence, achève tout de suite le chantier ("building" ou "ship")
## d'une planète contre de l'influence.
static func rush(player: int, planet_id: int, what: String) -> Dictionary:
	return {"type": "rush", "player": player, "planet": planet_id, "what": what}


## Registre Cosmique : replier le temps sur un chantier ("building" ou "ship"), contre des échos.
static func fold(player: int, planet_id: int, what: String) -> Dictionary:
	return {"type": "fold", "player": player, "planet": planet_id, "what": what}


## Déclare la guerre à un empire rencontré (la guerre vaut dans les deux sens).
static func declare_war(player: int, target: int) -> Dictionary:
	return {"type": "declare_war", "player": player, "target": target}


## Propose un traité (Diplomacy.TREATY_IDS) à un empire rencontré. Une IA répond tout de suite,
## un joueur humain reçoit la proposition.
static func propose_treaty(player: int, target: int, treaty: String) -> Dictionary:
	return {"type": "propose_treaty", "player": player, "target": target, "treaty": treaty}


## Répond à une proposition reçue.
static func answer_proposal(player: int, proposal_id: int, accept: bool) -> Dictionary:
	return {"type": "answer_proposal", "player": player, "proposal": proposal_id, "accept": accept}


## Rompt un traité : "alliance", "peace" (après la trêve) ou "trade".
static func cancel_treaty(player: int, target: int, treaty: String) -> Dictionary:
	return {"type": "cancel_treaty", "player": player, "target": target, "treaty": treaty}


## Embargo contre un empire (voir Trade) : coupe le commerce et interdit d'en signer.
static func embargo(player: int, target: int) -> Dictionary:
	return {"type": "embargo", "player": player, "target": target}


## Lève l'embargo imposé à un empire.
static func lift_embargo(player: int, target: int) -> Dictionary:
	return {"type": "lift_embargo", "player": player, "target": target}


## Places de capacité commerciale réservées aux routes intérieures (vers les jeunes colonies).
static func trade_reserve(player: int, n: int) -> Dictionary:
	return {"type": "trade_reserve", "player": player, "n": n}


## Achète une licence d'un luxe à un partenaire commercial (voir Goods) : payée chaque mois.
static func licence_buy(player: int, seller: int, good: String) -> Dictionary:
	return {"type": "licence_buy", "player": player, "target": seller, "good": good}


## Met fin à une licence (achetée ou vendue) entre l'empire et un autre.
static func licence_cancel(player: int, other: int, good: String) -> Dictionary:
	return {"type": "licence_cancel", "player": player, "target": other, "good": good}


## Ferme (ou rouvre) la vente de licences d'un luxe.
static func licence_close(player: int, good: String, closed: bool) -> Dictionary:
	return {"type": "licence_close", "player": player, "good": good, "closed": closed}


## Achète (n > 0) ou vend (n < 0) au marché intérieur, contre de l'énergie.
static func market_trade(player: int, res: String, n: int) -> Dictionary:
	return {"type": "market_trade", "player": player, "res": res, "n": n}


## Ordre mensuel au marché : n unités achetées (n > 0) ou vendues (n < 0) à chaque bilan ; 0 l'annule.
static func market_order(player: int, res: String, n: int) -> Dictionary:
	return {"type": "market_order", "player": player, "res": res, "n": n}


## Propose un échange de ressources à un empire, en une fois (months 0) ou chaque mois.
static func deal_offer(player: int, target: int, give: Dictionary, get_: Dictionary, months: int) -> Dictionary:
	return {"type": "deal_offer", "player": player, "target": target, "give": give, "get": get_, "months": months}


static func deal_answer(player: int, offer_id: int, accept: bool) -> Dictionary:
	return {"type": "deal_answer", "player": player, "offer": offer_id, "accept": accept}


## Rompt un contrat d'échange en cours (souvenir « contrat rompu » chez l'autre).
static func deal_cancel(player: int, deal_id: int) -> Dictionary:
	return {"type": "deal_cancel", "player": player, "deal": deal_id}


## Achète un vaisseau d'occasion à la Bourse galactique (livré à la capitale).
static func used_ship_buy(player: int) -> Dictionary:
	return {"type": "used_ship_buy", "player": player}


## Achète n unités d'un stratégique au marché noir d'un port franc pirate.
static func black_buy(player: int, system_id: int, res: String, n: int) -> Dictionary:
	return {"type": "black_buy", "player": player, "system": system_id, "res": res, "n": n}


## Propose un accord de recherche (l'IA répond aussitôt, un joueur reçoit la proposition).
static func research_pact(player: int, target: int) -> Dictionary:
	return {"type": "research_pact", "player": player, "target": target}


## Demande une licence de technologie à un partenaire commercial.
static func tech_licence(player: int, seller: int, tech: String) -> Dictionary:
	return {"type": "tech_licence", "player": player, "target": seller, "tech": tech}


## Répond à une proposition d'accord de recherche ou à une demande de licence de technologie.
static func tech_answer(player: int, offer_id: int, accept: bool) -> Dictionary:
	return {"type": "tech_answer", "player": player, "offer": offer_id, "accept": accept}


## Soudoie l'héritier d'une dynastie féodale rivale (sa loyauté baisse).
static func bribe_heir(player: int, target: int) -> Dictionary:
	return {"type": "bribe_heir", "player": player, "target": target}


## Banquet des lignées : la dynastie regagne la loyauté de son héritier.
static func banquet(player: int) -> Dictionary:
	return {"type": "banquet", "player": player}


## Une dynastie féodale unit ses lignées à celles d'un allié (victoire de l'Élu des routes).
static func unite_lineages(player: int, target: int) -> Dictionary:
	return {"type": "unite_lineages", "player": player, "target": target}


## Une république fait arbitrer la guerre entre deux autres empires (paix imposée).
static func mediate(player: int, a: int, b: int) -> Dictionary:
	return {"type": "mediate", "player": player, "a": a, "b": b}


## Contrat de flotte entre un syndicat (merc) et un client en guerre contre target ; player est l'un des deux.
static func contract(player: int, merc: int, client: int, target: int) -> Dictionary:
	return {"type": "contract", "player": player, "merc": merc, "client": client, "target": target}


## Choisit la tactique de combat d'une flotte (Combat.tactic_ids()).
static func set_tactic(player: int, fleet_id: int, tactic: String) -> Dictionary:
	return {"type": "set_tactic", "player": player, "fleet": fleet_id, "tactic": tactic}


## Remet une flotte à niveau dans un chantier ami : ses vaisseaux prennent les marques actuelles.
static func refit(player: int, fleet_id: int) -> Dictionary:
	return {"type": "refit", "player": player, "fleet": fleet_id}


## Enregistre un modèle de vaisseau (voir Designs.check_save pour spec).
static func save_design(player: int, spec: Dictionary) -> Dictionary:
	return {"type": "save_design", "player": player, "spec": spec.duplicate(true)}


## Retire un modèle de la liste de construction (retired false : l'y remet). Ses vaisseaux restent.
static func retire_design(player: int, design_id: String, retired := true) -> Dictionary:
	return {"type": "retire_design", "player": player, "design": design_id, "retired": retired}


## Débarque les troupes d'une flotte sur le système ennemi où elle stationne : il change de mains.
static func invade(player: int, fleet_id: int) -> Dictionary:
	return {"type": "invade", "player": player, "fleet": fleet_id}


## Met une technologie dans la file de recherche (en tête avec front : elle devient la recherche en cours).
static func research(player: int, tech_id: String, front := false) -> Dictionary:
	return {"type": "research_queue", "player": player, "tech": tech_id, "front": front}


## Retire une technologie de la file de recherche (et celles qui en dépendaient).
static func research_remove(player: int, tech_id: String) -> Dictionary:
	return {"type": "research_remove", "player": player, "tech": tech_id}


## Affecte n cellules d'espionnage chez target (target == player : contre-espionnage chez soi).
static func spy_cells(player: int, target: int, n: int) -> Dictionary:
	return {"type": "spy_cells", "player": player, "target": target, "n": n}


## Lance une sonde vers un système connu hors de vue : relevé ponctuel.
static func probe(player: int, system_id: int) -> Dictionary:
	return {"type": "probe", "player": player, "system": system_id}


## Lance une opération d'espionnage (data/espionage.json "operations") chez target.
static func spy_op(player: int, target: int, op_id: String) -> Dictionary:
	return {"type": "spy_op", "player": player, "target": target, "op": op_id}


## Annule l'opération en cours chez target.
static func spy_cancel(player: int, target: int) -> Dictionary:
	return {"type": "spy_cancel", "player": player, "target": target}


## Répond à des espions démasqués chez soi : "expel" ou "reparation".
## Choisit un héros de l'offre en attente (index ; -1 = décline l'offre).
static func hero_pick(player: int, index: int) -> Dictionary:
	return {"type": "hero_pick", "player": player, "index": index}


## Répond à un événement de sa boîte (voir Events) : choix index de la carte.
static func event_choose(player: int, event_id: int, index: int) -> Dictionary:
	return {"type": "event_choose", "player": player, "event": event_id, "index": index}


## Fouilles et reliques (voir Relics).
static func dig_start(player: int, system_id: int) -> Dictionary:
	return {"type": "dig_start", "player": player, "system": system_id}


static func dig_clue(player: int, system_id: int) -> Dictionary:
	return {"type": "dig_clue", "player": player, "system": system_id}


static func relic_triumph(player: int, relic: String) -> Dictionary:
	return {"type": "relic_triumph", "player": player, "relic": relic}


## Confie une relique à un héros (hero_id = -1 : la rend au Reliquaire).
static func relic_assign(player: int, relic: String, hero_id: int) -> Dictionary:
	return {"type": "relic_assign", "player": player, "relic": relic, "hero": hero_id}


static func relic_gift(player: int, relic: String, to: int) -> Dictionary:
	return {"type": "relic_gift", "player": player, "relic": relic, "to": to}


static func relic_sell(player: int, relic: String) -> Dictionary:
	return {"type": "relic_sell", "player": player, "relic": relic}


static func fragments_gift(player: int, to: int) -> Dictionary:
	return {"type": "fragments_gift", "player": player, "to": to}


static func fragments_sell(player: int) -> Dictionary:
	return {"type": "fragments_sell", "player": player}


## Quêtes (voir Quests) : payer la branche d'un chapitre, financer le remède du fléau, choisir son camp
## au Conclave, parlementer avec un tombeau (peuple synthétique).
static func quest_pay(player: int, quest_id: int, branch: int) -> Dictionary:
	return {"type": "quest_pay", "player": player, "quest": quest_id, "branch": branch}


static func quest_contribute(player: int) -> Dictionary:
	return {"type": "quest_contribute", "player": player}


static func quest_camp(player: int, camp: int) -> Dictionary:
	return {"type": "quest_camp", "player": player, "camp": camp}


static func tomb_parley(player: int, system_id: int) -> Dictionary:
	return {"type": "tomb_parley", "player": player, "system": system_id}


## Affecte un héros : post = "fleet" (flotte), "system" (système), "council" (siège), "agent" (empire
## où l'on a un réseau) ; "" = le rappeler.
static func hero_assign(player: int, hero_id: int, post: String, target: int) -> Dictionary:
	return {"type": "hero_assign", "player": player, "hero": hero_id, "post": post, "target": target}


## Renvoie un héros (il quitte l'empire).
static func hero_dismiss(player: int, hero_id: int) -> Dictionary:
	return {"type": "hero_dismiss", "player": player, "hero": hero_id}


## Un syndicat met un héros en location (on) ou l'en retire.
static func hero_for_hire(player: int, hero_id: int, on: bool) -> Dictionary:
	return {"type": "hero_for_hire", "player": player, "hero": hero_id, "on": on}


## Un empire engage un héros à louer.
static func hero_hire(player: int, hero_id: int) -> Dictionary:
	return {"type": "hero_hire", "player": player, "hero": hero_id}


## Le geôlier décide du sort d'un prisonnier : "free", "convert" ou "execute".
static func hero_prisoner(player: int, hero_id: int, action: String) -> Dictionary:
	return {"type": "hero_prisoner", "player": player, "hero": hero_id, "action": action}


## Payer la rançon d'un héros que retiennent les pirates ou les rebelles.
static func hero_ransom(player: int, hero_id: int) -> Dictionary:
	return {"type": "hero_ransom", "player": player, "hero": hero_id}


## Soutien officiel à un courant pour la prochaine élection (Politics ; -1 retire le soutien).
## En théocratie et en horde, c'est le courant nommé.
static func politics_support(player: int, current: int) -> Dictionary:
	return {"type": "politics_support", "player": player, "current": current}


## Adopter une loi (Laws : loi d'un courant au pouvoir ou loi indépendante).
## Fixe le statut d'une espèce dans l'empire (voir Peoples.STATUSES).
static func peoples_status(player: int, species: String, status: String) -> Dictionary:
	return {"type": "peoples_status", "player": player, "species": species, "status": status}


## Change la foi d'État ("laicite", "incroyance" ou une grande foi, voir Faiths).
static func faith_state(player: int, faith: String) -> Dictionary:
	return {"type": "faith_state", "player": player, "faith": faith}


## Le chef de foi ajoute un dogme à sa foi (voir Faiths).
static func faith_dogma(player: int, faith: String, dogma: String) -> Dictionary:
	return {"type": "faith_dogma", "player": player, "faith": faith, "dogma": dogma}


## Politique d'accueil des réfugiés (voir Movements.POLICIES).
static func refugee_policy(player: int, policy: String) -> Dictionary:
	return {"type": "refugee_policy", "player": player, "policy": policy}


## Réponse à la revendication d'une diaspora : "systeme", "neutre" ou "refus" (voir Movements).
static func diaspora_answer(player: int, choice: String) -> Dictionary:
	return {"type": "diaspora_answer", "player": player, "choice": choice}


static func law_adopt(player: int, law: String) -> Dictionary:
	return {"type": "law_adopt", "player": player, "law": law}


static func law_revoke(player: int, law: String) -> Dictionary:
	return {"type": "law_revoke", "player": player, "law": law}


## Action électorale sur le courant soutenu (Laws : "campagne", "intimidation", "rachat").
static func politics_action(player: int, action: String) -> Dictionary:
	return {"type": "politics_action", "player": player, "action": action}


## Décret de stabilité sur un système (Stability : "loi_martiale", "fetes", "concessions").
static func decree(player: int, system_id: int, decree_id: String) -> Dictionary:
	return {"type": "decree", "player": player, "system": system_id, "decree": decree_id}


## Théocratie : sacrifie de la stabilité d'un système contre de la ferveur.
static func stab_offering(player: int, system_id: int) -> Dictionary:
	return {"type": "stab_offering", "player": player, "system": system_id}


## Réintègre un monde libre des Sans-Bannière qui touche votre territoire, contre de l'influence.
static func reintegrate(player: int, system_id: int) -> Dictionary:
	return {"type": "reintegrate", "player": player, "system": system_id}


## Patrouille : la flotte fait l'aller-retour entre sa position et system_id.
static func patrol_fleet(player: int, fleet_id: int, system_id: int) -> Dictionary:
	return {"type": "patrol_fleet", "player": player, "fleet": fleet_id, "system": system_id}


## Tribut à un repaire pirate connu : un an sans raid de ce repaire contre vous.
static func pirate_tribute(player: int, system_id: int) -> Dictionary:
	return {"type": "pirate_tribute", "player": player, "system": system_id}


## Engage un repaire pirate connu contre un rival (commanditaire caché).
static func pirate_hire(player: int, system_id: int, victim: int) -> Dictionary:
	return {"type": "pirate_hire", "player": player, "system": system_id, "victim": victim}


## Prime anonyme sur un empire : les raids le visent en priorité.
## Port franc : louer une flotte de mercenaires ("fleet") ou recruter un héros ("hero").
static func port_deal(player: int, system_id: int, kind: String) -> Dictionary:
	return {"type": "port_deal", "player": player, "system": system_id, "kind": kind}


static func pirate_bounty(player: int, victim: int) -> Dictionary:
	return {"type": "pirate_bounty", "player": player, "victim": victim}


## Faune : étudier ("etude"), chasser ("chasse"), apprivoiser ("apprivoise") une espèce rencontrée,
## ou renoncer ("renoncer") à la chasse ou à l'apprivoisement (voir Fauna).
static func beast_release(player: int, index: int) -> Dictionary:
	return {"type": "beast_release", "player": player, "index": index}


static func fauna_attitude(player: int, species_id: String, attitude: String) -> Dictionary:
	return {"type": "fauna_attitude", "player": player, "species": species_id, "attitude": attitude}


static func spy_answer(player: int, case_id: int, choice: String) -> Dictionary:
	return {"type": "spy_answer", "player": player, "case": case_id, "choice": choice}


## Renvoie "" si l'ordre est applicable à cet état, sinon la raison du refus.
## Multijoueur : confie un empire à un humain (ai_level "") ou à l'IA (un niveau d'AiLevels), quand un
## joueur rejoint ou quitte la partie. Seul l'hôte l'émet (la session refuse celui d'un client) ;
## comme tout ordre, il passe dans le flux commun pour s'appliquer au même jour sur chaque machine.
static func seat(empire_id: int, ai_level: String) -> Dictionary:
	return {"type": "seat", "player": empire_id, "ai": ai_level}


static func validate(state: GameState, cmd: Dictionary) -> String:
	if not cmd.has("type") or not cmd.has("player"):
		return "ordre incomplet"
	match String(cmd["type"]):
		"rename_system":
			var id := int(cmd.get("system", -1))
			if state.galaxy.get_system(id) == null:
				return "système inconnu : %d" % id
			var n := String(cmd.get("name", "")).strip_edges()
			if n.is_empty():
				return "nom vide"
			if n.length() > NAME_MAX_LENGTH:
				return "nom trop long (%d caractères max)" % NAME_MAX_LENGTH
			return ""
		"colonize":
			return Economy.check_colonize(state, int(cmd["player"]), int(cmd.get("planet", -1)), String(cmd.get("kind", "")), String(cmd.get("species", "")))
		"build":
			return Economy.check_build(state, int(cmd["player"]), int(cmd.get("planet", -1)), String(cmd.get("building", "")))
		"build_ship":
			return Fleets.check_build_ship(state, int(cmd["player"]), int(cmd.get("planet", -1)), String(cmd.get("ship", "")))
		"move_fleet":
			return Fleets.check_move(state, int(cmd["player"]), int(cmd.get("fleet", -1)), int(cmd.get("system", -1)))
		"stop_fleet":
			return Fleets.check_stop(state, int(cmd["player"]), int(cmd.get("fleet", -1)))
		"set_fleet_order":
			return Fleets.check_order(state, int(cmd["player"]), int(cmd.get("fleet", -1)), String(cmd.get("order", "")))
		"merge_fleets":
			return Fleets.check_merge(state, int(cmd["player"]), int(cmd.get("fleet", -1)), int(cmd.get("into", -1)))
		"split_fleet":
			return Fleets.check_split(state, int(cmd["player"]), int(cmd.get("fleet", -1)), String(cmd.get("ship", "")))
		"politics_support":
			return Politics.check_support(state, int(cmd["player"]), int(cmd.get("current", -2)))
		"peoples_status":
			return Peoples.check_status(state, int(cmd["player"]), String(cmd.get("species", "")), String(cmd.get("status", "")))
		"faith_state":
			return Faiths.check_state(state, int(cmd["player"]), String(cmd.get("faith", "")))
		"faith_dogma":
			return Faiths.check_dogma(state, int(cmd["player"]), String(cmd.get("faith", "")), String(cmd.get("dogma", "")))
		"refugee_policy":
			return Movements.check_policy(state, int(cmd["player"]), String(cmd.get("policy", "")))
		"diaspora_answer":
			return Movements.check_claim(state, int(cmd["player"]), String(cmd.get("choice", "")))
		"law_adopt":
			return Laws.check_adopt(state, int(cmd["player"]), String(cmd.get("law", "")))
		"law_revoke":
			return Laws.check_revoke(state, int(cmd["player"]), String(cmd.get("law", "")))
		"politics_action":
			return Laws.check_action(state, int(cmd["player"]), String(cmd.get("action", "")))
		"decree":
			return Stability.check_decree(state, int(cmd["player"]), int(cmd.get("system", -1)), String(cmd.get("decree", "")))
		"stab_offering":
			return Stability.check_offering(state, int(cmd["player"]), int(cmd.get("system", -1)))
		"reintegrate":
			return Stability.check_reintegrate(state, int(cmd["player"]), int(cmd.get("system", -1)))
		"patrol_fleet":
			return Fleets.check_patrol(state, int(cmd["player"]), int(cmd.get("fleet", -1)), int(cmd.get("system", -1)))
		"pirate_tribute":
			return Pirates.check_tribute(state, int(cmd["player"]), int(cmd.get("system", -1)))
		"pirate_hire":
			return Pirates.check_hire(state, int(cmd["player"]), int(cmd.get("system", -1)), int(cmd.get("victim", -1)))
		"port_deal":
			return Pirates.check_port(state, int(cmd["player"]), int(cmd.get("system", -1)), String(cmd.get("kind", "")))
		"pirate_bounty":
			return Pirates.check_bounty(state, int(cmd["player"]), int(cmd.get("victim", -1)))
		"beast_release":
			return WarBeasts.check_release(state, int(cmd["player"]), int(cmd.get("index", -1)))
		"fauna_attitude":
			return Fauna.check_attitude(state, int(cmd["player"]), String(cmd.get("species", "")), String(cmd.get("attitude", "")))
		"sacrifice":
			return FactionTraits.check_sacrifice(state, int(cmd["player"]), int(cmd.get("planet", -1)))
		"rush":
			return FactionTraits.check_rush(state, int(cmd["player"]), int(cmd.get("planet", -1)), String(cmd.get("what", "")))
		"fold":
			return Echoes.check_fold(state, int(cmd["player"]), int(cmd.get("planet", -1)), String(cmd.get("what", "")))
		"declare_war":
			return Combat.check_declare_war(state, int(cmd["player"]), int(cmd.get("target", -1)))
		"propose_treaty":
			return Diplomacy.check_propose(state, int(cmd["player"]), int(cmd.get("target", -1)), String(cmd.get("treaty", "")))
		"answer_proposal":
			return Diplomacy.check_answer(state, int(cmd["player"]), int(cmd.get("proposal", -1)), bool(cmd.get("accept", false)))
		"cancel_treaty":
			return Diplomacy.check_cancel(state, int(cmd["player"]), int(cmd.get("target", -1)), String(cmd.get("treaty", "")))
		"embargo":
			return Trade.check_embargo(state, int(cmd["player"]), int(cmd.get("target", -1)))
		"lift_embargo":
			return Trade.check_lift(state, int(cmd["player"]), int(cmd.get("target", -1)))
		"trade_reserve":
			return Trade.check_reserve(state, int(cmd["player"]), int(cmd.get("n", -1)))
		"licence_buy":
			return Goods.check_licence(state, int(cmd["player"]), int(cmd.get("target", -1)), String(cmd.get("good", "")))
		"licence_cancel":
			return Goods.check_cancel_licence(state, int(cmd["player"]), int(cmd.get("target", -1)), String(cmd.get("good", "")))
		"licence_close":
			return "" if state.get_empire(int(cmd["player"])) != null and Goods.is_luxury(String(cmd.get("good", ""))) else "luxe inconnu"
		"market_trade":
			return Goods.check_market(state, int(cmd["player"]), String(cmd.get("res", "")), int(cmd.get("n", 0)))
		"market_order":
			return Goods.check_order(state, int(cmd["player"]), String(cmd.get("res", "")), int(cmd.get("n", 0)))
		"deal_offer":
			return Goods.check_offer(state, int(cmd["player"]), int(cmd.get("target", -1)), cmd.get("give", {}), cmd.get("get", {}), int(cmd.get("months", 0)))
		"deal_answer":
			return Goods.check_answer(state, int(cmd["player"]), int(cmd.get("offer", -1)), bool(cmd.get("accept", false)))
		"deal_cancel":
			return Goods.check_cancel_deal(state, int(cmd["player"]), int(cmd.get("deal", -1)))
		"used_ship_buy":
			return Goods.check_used(state, int(cmd["player"]))
		"research_pact":
			return TechTrade.check_pact(state, int(cmd["player"]), int(cmd.get("target", -1)))
		"tech_licence":
			return TechTrade.check_licence(state, int(cmd["player"]), int(cmd.get("target", -1)), String(cmd.get("tech", "")))
		"tech_answer":
			return TechTrade.check_answer(state, int(cmd["player"]), int(cmd.get("offer", -1)), bool(cmd.get("accept", false)))
		"black_buy":
			return Goods.check_black(state, int(cmd["player"]), int(cmd.get("system", -1)), String(cmd.get("res", "")), int(cmd.get("n", 0)))
		"bribe_heir":
			return Diplomacy.check_bribe(state, int(cmd["player"]), int(cmd.get("target", -1)))
		"banquet":
			return Diplomacy.check_banquet(state, int(cmd["player"]))
		"unite_lineages":
			return Victory.check_union(state, int(cmd["player"]), int(cmd.get("target", -1)))
		"mediate":
			return Diplomacy.check_mediate(state, int(cmd["player"]), int(cmd.get("a", -1)), int(cmd.get("b", -1)))
		"contract":
			return Diplomacy.check_propose_contract(state, int(cmd["player"]), int(cmd.get("merc", -1)), int(cmd.get("client", -1)), int(cmd.get("target", -1)))
		"set_tactic":
			return Combat.check_tactic(state, int(cmd["player"]), int(cmd.get("fleet", -1)), String(cmd.get("tactic", "")))
		"save_design":
			return Designs.check_save(state, int(cmd["player"]), cmd.get("spec", {}))
		"retire_design":
			return Designs.check_retire(state, int(cmd["player"]), String(cmd.get("design", "")))
		"refit":
			return Fleets.check_refit(state, int(cmd["player"]), int(cmd.get("fleet", -1)))
		"invade":
			return Combat.check_invade(state, int(cmd["player"]), int(cmd.get("fleet", -1)))
		"research_queue":
			return Research.check_queue(state, int(cmd["player"]), String(cmd.get("tech", "")), bool(cmd.get("front", false)))
		"research_remove":
			return Research.check_remove(state, int(cmd["player"]), String(cmd.get("tech", "")))
		"spy_cells":
			return Espionage.check_cells(state, int(cmd["player"]), int(cmd.get("target", -1)), int(cmd.get("n", -1)))
		"spy_op":
			return Espionage.check_op(state, int(cmd["player"]), int(cmd.get("target", -1)), String(cmd.get("op", "")))
		"spy_cancel":
			return Espionage.check_cancel(state, int(cmd["player"]), int(cmd.get("target", -1)))
		"hero_pick":
			return Heroes.check_pick(state, int(cmd["player"]), int(cmd.get("index", -2)))
		"event_choose":
			return Events.check_choose(state, int(cmd["player"]), int(cmd.get("event", -1)), int(cmd.get("index", -1)))
		"dig_start":
			return Relics.check_start(state, int(cmd["player"]), int(cmd.get("system", -1)))
		"dig_clue":
			return Relics.check_clue(state, int(cmd["player"]), int(cmd.get("system", -1)))
		"relic_triumph":
			return Relics.check_triumph(state, int(cmd["player"]), String(cmd.get("relic", "")))
		"relic_assign":
			return Relics.check_assign(state, int(cmd["player"]), String(cmd.get("relic", "")), int(cmd.get("hero", -1)))
		"relic_gift":
			return Relics.check_gift(state, int(cmd["player"]), String(cmd.get("relic", "")), int(cmd.get("to", -1)))
		"relic_sell":
			return Relics.check_sell(state, int(cmd["player"]), String(cmd.get("relic", "")))
		"fragments_gift":
			return Relics.check_gift_fragments(state, int(cmd["player"]), int(cmd.get("to", -1)))
		"fragments_sell":
			return Relics.check_sell_fragments(state, int(cmd["player"]))
		"quest_pay":
			return Quests.check_pay(state, int(cmd["player"]), int(cmd.get("quest", -1)), int(cmd.get("branch", -1)))
		"quest_contribute":
			return Quests.check_contribute(state, int(cmd["player"]))
		"quest_camp":
			return Quests.check_camp(state, int(cmd["player"]), int(cmd.get("camp", -1)))
		"tomb_parley":
			return Quests.check_parley(state, int(cmd["player"]), int(cmd.get("system", -1)))
		"hero_assign":
			return Heroes.check_assign(state, int(cmd["player"]), int(cmd.get("hero", -1)), String(cmd.get("post", "?")), int(cmd.get("target", -1)))
		"hero_dismiss":
			return Heroes.check_dismiss(state, int(cmd["player"]), int(cmd.get("hero", -1)))
		"hero_for_hire":
			return Heroes.check_for_hire(state, int(cmd["player"]), int(cmd.get("hero", -1)), bool(cmd.get("on", false)))
		"hero_hire":
			return Heroes.check_hire(state, int(cmd["player"]), int(cmd.get("hero", -1)))
		"hero_ransom":
			return Heroes.check_ransom(state, int(cmd["player"]), int(cmd.get("hero", -1)))
		"hero_prisoner":
			return Heroes.check_prisoner(state, int(cmd["player"]), int(cmd.get("hero", -1)), String(cmd.get("action", "")))
		"spy_answer":
			return Espionage.check_answer(state, int(cmd["player"]), int(cmd.get("case", -1)), String(cmd.get("choice", "")))
		"probe":
			return Espionage.check_probe(state, int(cmd["player"]), int(cmd.get("system", -1)))
		"seat":
			if state.get_empire(int(cmd["player"])) == null:
				return "empire inconnu"
			var lv := String(cmd.get("ai", ""))
			if lv != "" and not AiLevels.is_valid(lv):
				return "niveau d'IA inconnu : %s" % lv
			return ""
		_:
			return "type d'ordre inconnu : %s" % cmd["type"]


## Applique un ordre déjà validé.
static func apply(state: GameState, cmd: Dictionary) -> void:
	match String(cmd["type"]):
		"rename_system":
			var sys := state.galaxy.get_system(int(cmd["system"]))
			var old_name := sys.system_name
			sys.system_name = String(cmd["name"]).strip_edges()
			if old_name != sys.system_name:
				state.add_chronicle("Les cartographes rebaptisent %s : on dira désormais %s." % [old_name, sys.system_name], Espionage.private_to(state, [int(cmd["player"])]))
		"colonize":
			var e := state.get_empire(int(cmd["player"]))
			var pid := int(cmd["planet"])
			var kind := String(cmd["kind"])
			Economy.pay(e, Economy.claim_cost_for(state, e.id, pid, kind))
			var p := state.galaxy.get_planet(pid)
			if Economy.needs_ship(state, e.id, pid):
				# Le vaisseau colon se démonte : ses modules deviennent les premiers bâtiments.
				var f := Fleets.colonizer_fleet(state, e.id, p.system_id)
				f.remove_ship(Fleets.colonizer_ship(f))
				if f.ships.is_empty():
					state.fleets.erase(f.id)
			var c: Colony = state.colonies.get(pid)
			if c == null:
				c = Colony.new()
				c.planet_id = pid
				c.owner = e.id
			c.kind = kind
			c.days_left = Economy.claim_days(kind)
			var sp := String(cmd.get("species", ""))
			c.founder = sp if kind == Colony.KIND_COLONY and sp != e.faction_id else ""
			state.add_colony(c)
		"build":
			var e := state.get_empire(int(cmd["player"]))
			var c: Colony = state.colonies[int(cmd["planet"])]
			var b := GameData.building(String(cmd["building"]))
			Economy.pay(e, Economy.building_cost(state, e.id, String(cmd["building"])))
			c.construction = String(cmd["building"])
			# Loi « Cadences » : chantiers plus courts.
			c.construction_days = maxi(1, Research.scaled(int(b["days"]), Research.fx_int(state, e.id, "building_days_pct")))
		"build_ship":
			var e := state.get_empire(int(cmd["player"]))
			var c: Colony = state.colonies[int(cmd["planet"])]
			var sd := GameData.ship(String(cmd["ship"]))
			Economy.pay(e, Fleets.ship_cost(state, e.id, String(cmd["ship"])))
			c.population -= int(sd.get("pop_cost", 0))
			c.ship_build = String(cmd["ship"])
			c.ship_days = Fleets.ship_days(state, e.id, String(cmd["ship"]))
		"move_fleet":
			var f: Fleet = state.fleets[int(cmd["fleet"])]
			var plan := Fleets.plan_route(state, f, int(cmd["system"]))
			f.standing_order = ""  # un ordre donné à la main reprend la main sur l'exploration
			f.system_id = int(plan["system"])
			f.path.assign(plan["path"])
			f.progress = int(plan["progress"])
		"stop_fleet":
			var f: Fleet = state.fleets[int(cmd["fleet"])]
			f.standing_order = ""
			var lane := Fleets.lane_length(state.galaxy, f.system_id, f.path[0])
			if f.progress * 2 >= lane:
				f.path.resize(1)  # finir la route en cours
			else:
				var back := f.system_id
				f.system_id = f.path[0]
				f.path.assign([back])
				f.progress = lane - f.progress
		"set_fleet_order":
			var f: Fleet = state.fleets[int(cmd["fleet"])]
			f.standing_order = String(cmd["order"])
			if f.is_exploring():
				FleetSystem.explore_step(state, f)  # cap immédiat sur la frontière, sans attendre le tick
		"merge_fleets":
			var f: Fleet = state.fleets[int(cmd["fleet"])]
			var into: Fleet = state.fleets[int(cmd["into"])]
			for i in f.ships.size():
				into.add_ship(f.ships[i], f.hp[i], f.gen[i])
			into.troops += f.troops
			Heroes.on_merge(state, f.id, into.id)
			state.fleets.erase(f.id)
		"split_fleet":
			var f: Fleet = state.fleets[int(cmd["fleet"])]
			var ship_id := String(cmd["ship"])
			var before := Combat.max_troops(f, state)
			var ship_hp := f.remove_ship_hp(ship_id)
			var nf := state.spawn_ship(f.owner, ship_id, f.system_id)
			nf.hp[0] = ship_hp
			nf.gen[0] = f.last_gen
			nf.tactic = f.tactic
			# Les troupes se répartissent selon la capacité de chaque flotte.
			@warning_ignore("integer_division")
			nf.troops = f.troops * Combat.max_troops(nf, state) / maxi(1, before)
			f.troops -= nf.troops
		"sacrifice":
			var e := state.get_empire(int(cmd["player"]))
			var c: Colony = state.colonies[int(cmd["planet"])]
			var fv: Dictionary = e.faction()["fervor"]
			c.population -= 1
			c.growth = 0
			e.fervor = mini(int(fv["max"]), e.fervor + FactionTraits.sacrifice_gain(state, e.id))
			Research.count_stat(state, e.id, "sacrifices")
			state.add_chronicle("Offrande sur %s : un fidèle rejoint le dieu-machine. Il paraît que c'est un honneur ; il paraît surtout que c'est obligatoire." % [
					state.galaxy.get_planet(c.planet_id).display_name(state.galaxy)], Espionage.private_to(state, [e.id], state.galaxy.get_planet(c.planet_id).system_id))
		"rush":
			var e := state.get_empire(int(cmd["player"]))
			var pid := int(cmd["planet"])
			var what := String(cmd["what"])
			e.resources["influence"] = int(e.resources["influence"]) - FactionTraits.rush_cost(state, e.id, pid, what)
			var c: Colony = state.colonies[pid]
			# Le chantier s'achève au prochain jour de simulation, comme s'il était arrivé à terme.
			if what == FactionTraits.RUSH_BUILDING:
				c.construction_days = 1
			else:
				c.ship_days = 1
		"fold":
			Echoes.fold(state, int(cmd["player"]), int(cmd["planet"]), String(cmd["what"]))
		"politics_support":
			Politics.support(state, int(cmd["player"]), int(cmd["current"]))
		"peoples_status":
			Peoples.set_status(state, int(cmd["player"]), String(cmd["species"]), String(cmd["status"]))
		"faith_state":
			Faiths.set_state(state, int(cmd["player"]), String(cmd["faith"]))
		"faith_dogma":
			Faiths.add_dogma(state, String(cmd["faith"]), String(cmd["dogma"]))
		"refugee_policy":
			Movements.set_policy(state, int(cmd["player"]), String(cmd["policy"]))
		"diaspora_answer":
			Movements.answer_claim(state, int(cmd["player"]), String(cmd["choice"]), [] as Array[Dictionary])
		"law_adopt":
			Laws.adopt(state, int(cmd["player"]), String(cmd["law"]))
		"law_revoke":
			Laws.revoke(state, int(cmd["player"]), String(cmd["law"]))
		"politics_action":
			Laws.do_action(state, int(cmd["player"]), String(cmd["action"]))
		"decree":
			Stability.decree(state, int(cmd["player"]), int(cmd["system"]), String(cmd["decree"]))
		"stab_offering":
			Stability.offering(state, int(cmd["player"]), int(cmd["system"]))
		"reintegrate":
			Stability.reintegrate(state, int(cmd["player"]), int(cmd["system"]))
		"patrol_fleet":
			var f: Fleet = state.fleets[int(cmd["fleet"])]
			var start := f.destination()
			var plan := Fleets.plan_route(state, f, int(cmd["system"]))
			f.system_id = int(plan["system"])
			f.path.assign(plan["path"])
			f.progress = int(plan["progress"])
			f.standing_order = Fleet.ORDER_PATROL
			f.patrol.assign([start if start != int(cmd["system"]) else f.system_id, int(cmd["system"])])
		"pirate_tribute":
			Pirates.tribute(state, int(cmd["player"]), int(cmd["system"]))
		"pirate_hire":
			Pirates.hire(state, int(cmd["player"]), int(cmd["system"]), int(cmd["victim"]))
		"port_deal":
			Pirates.port_deal(state, int(cmd["player"]), int(cmd["system"]), String(cmd["kind"]))
		"pirate_bounty":
			Pirates.bounty(state, int(cmd["player"]), int(cmd["victim"]))
		"fauna_attitude":
			Fauna.set_attitude(state, int(cmd["player"]), String(cmd["species"]), String(cmd["attitude"]))
		"beast_release":
			WarBeasts.release(state, int(cmd["player"]), int(cmd["index"]))
		"spy_cells":
			Espionage.set_cells(state, int(cmd["player"]), int(cmd["target"]), int(cmd["n"]))
		"spy_op":
			Espionage.launch(state, int(cmd["player"]), int(cmd["target"]), String(cmd["op"]))
		"spy_cancel":
			Espionage.cancel(state, int(cmd["player"]), int(cmd["target"]))
		"hero_pick":
			Heroes.pick(state, int(cmd["player"]), int(cmd["index"]))
		"event_choose":
			var ev_added: Array[Dictionary] = []
			Events.choose(state, int(cmd["player"]), int(cmd["event"]), int(cmd["index"]), ev_added)
		"dig_start":
			Relics.start(state, int(cmd["player"]), int(cmd["system"]))
		"dig_clue":
			Relics.buy_clue(state, int(cmd["player"]), int(cmd["system"]))
		"relic_triumph":
			var rt_added: Array[Dictionary] = []
			Relics.triumph(state, int(cmd["player"]), String(cmd["relic"]), rt_added)
		"relic_assign":
			Relics.assign(state, String(cmd["relic"]), int(cmd["hero"]))
		"relic_gift":
			var rg_added: Array[Dictionary] = []
			Relics.gift(state, int(cmd["player"]), String(cmd["relic"]), int(cmd["to"]), rg_added)
		"relic_sell":
			var rs_added: Array[Dictionary] = []
			Relics.sell(state, int(cmd["player"]), String(cmd["relic"]), rs_added)
		"fragments_gift":
			Relics.gift_fragments(state, int(cmd["player"]), int(cmd["to"]))
		"fragments_sell":
			Relics.sell_fragments(state, int(cmd["player"]))
		"quest_pay":
			var qp_added: Array[Dictionary] = []
			Quests.pay(state, int(cmd["player"]), int(cmd["quest"]), int(cmd["branch"]), qp_added)
		"quest_contribute":
			var qc_added: Array[Dictionary] = []
			Quests.contribute(state, int(cmd["player"]), qc_added)
		"quest_camp":
			Quests.choose_camp(state, int(cmd["player"]), int(cmd["camp"]))
		"tomb_parley":
			var tp_added: Array[Dictionary] = []
			Quests.parley(state, int(cmd["player"]), int(cmd["system"]), tp_added)
		"hero_assign":
			Heroes.assign(state, int(cmd["player"]), int(cmd["hero"]), String(cmd["post"]), int(cmd["target"]))
		"hero_dismiss":
			Heroes.dismiss(state, int(cmd["player"]), int(cmd["hero"]))
		"hero_for_hire":
			Heroes.set_for_hire(state, int(cmd["player"]), int(cmd["hero"]), bool(cmd["on"]))
		"hero_hire":
			Heroes.hire(state, int(cmd["player"]), int(cmd["hero"]))
		"hero_ransom":
			Heroes.ransom(state, int(cmd["player"]), int(cmd["hero"]))
		"hero_prisoner":
			Heroes.prisoner(state, int(cmd["player"]), int(cmd["hero"]), String(cmd["action"]))
		"spy_answer":
			Espionage.answer(state, int(cmd["player"]), int(cmd["case"]), String(cmd["choice"]))
		"probe":
			Espionage.probe(state, int(cmd["player"]), int(cmd["system"]))
		"declare_war":
			Combat.start_war(state, int(cmd["player"]), int(cmd["target"]))
		"propose_treaty":
			Diplomacy.propose(state, int(cmd["player"]), int(cmd["target"]), String(cmd["treaty"]))
		"answer_proposal":
			Diplomacy.answer(state, int(cmd["proposal"]), bool(cmd["accept"]))
		"cancel_treaty":
			Diplomacy.cancel(state, int(cmd["player"]), int(cmd["target"]), String(cmd["treaty"]))
		"embargo":
			Trade.embargo(state, int(cmd["player"]), int(cmd["target"]))
		"lift_embargo":
			Trade.lift(state, int(cmd["player"]), int(cmd["target"]))
		"trade_reserve":
			Trade.set_reserve(state, int(cmd["player"]), int(cmd["n"]))
		"licence_buy":
			Goods.buy_licence(state, int(cmd["player"]), int(cmd["target"]), String(cmd["good"]))
		"licence_cancel":
			Goods.cancel_licence(state, int(cmd["player"]), int(cmd["target"]), String(cmd["good"]))
		"licence_close":
			Goods.set_closed(state, int(cmd["player"]), String(cmd["good"]), bool(cmd["closed"]))
		"market_trade":
			Goods.trade_market(state, int(cmd["player"]), String(cmd["res"]), int(cmd["n"]))
		"market_order":
			Goods.set_order(state, int(cmd["player"]), String(cmd["res"]), int(cmd["n"]))
		"deal_offer":
			Goods.offer(state, int(cmd["player"]), int(cmd["target"]), cmd["give"], cmd["get"], int(cmd["months"]))
		"deal_answer":
			Goods.answer(state, int(cmd["offer"]), bool(cmd["accept"]))
		"deal_cancel":
			Goods.cancel_deal(state, int(cmd["player"]), int(cmd["deal"]))
		"used_ship_buy":
			Goods.buy_used(state, int(cmd["player"]))
		"research_pact":
			TechTrade.propose_pact(state, int(cmd["player"]), int(cmd["target"]))
		"tech_licence":
			TechTrade.request_licence(state, int(cmd["player"]), int(cmd["target"]), String(cmd["tech"]))
		"tech_answer":
			TechTrade.answer(state, int(cmd["offer"]), bool(cmd["accept"]))
		"black_buy":
			Goods.buy_black(state, int(cmd["player"]), int(cmd["system"]), String(cmd["res"]), int(cmd["n"]))
		"bribe_heir":
			Diplomacy.bribe(state, int(cmd["player"]), int(cmd["target"]))
		"banquet":
			Diplomacy.banquet(state, int(cmd["player"]))
		"unite_lineages":
			Victory.union(state, int(cmd["player"]), int(cmd["target"]))
		"mediate":
			Diplomacy.mediate(state, int(cmd["player"]), int(cmd["a"]), int(cmd["b"]))
		"contract":
			Diplomacy.propose_contract(state, int(cmd["player"]), int(cmd["merc"]), int(cmd["client"]), int(cmd["target"]))
		"set_tactic":
			state.fleets[int(cmd["fleet"])].tactic = String(cmd["tactic"])
		"save_design":
			Designs.save(state, int(cmd["player"]), cmd["spec"])
		"retire_design":
			state.designs[String(cmd["design"])]["retired"] = bool(cmd.get("retired", true))
		"refit":
			var f: Fleet = state.fleets[int(cmd["fleet"])]
			Economy.pay(state.get_empire(f.owner), Fleets.refit_cost(state, f))
			f.refit_left = Fleets.refit_days()
		"invade":
			var f: Fleet = state.fleets[int(cmd["fleet"])]
			var sid := f.system_id
			f.troops -= Combat.garrison(state, sid)  # les défenseurs se battent jusqu'au dernier
			Combat.capture_system(state, sid, f.owner)
		"research_queue":
			Research.apply_queue(state, int(cmd["player"]), String(cmd["tech"]), bool(cmd.get("front", false)))
		"research_remove":
			Research.apply_remove(state, int(cmd["player"]), String(cmd["tech"]))
		"seat":
			var e := state.get_empire(int(cmd["player"]))
			e.ai_level = String(cmd["ai"])
			if e.ai_level != "" and not AiLevels.is_valid_temperament(e.ai_temperament):
				e.ai_temperament = AiLevels.default_temperament()
