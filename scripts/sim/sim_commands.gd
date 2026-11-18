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


## Déclare la guerre à un empire rencontré (la guerre vaut dans les deux sens). Avec les buts de
## guerre (voir Wars) : motif et but annoncés (vides : choisis au mieux), brk pour rompre une trêve.
static func declare_war(player: int, target: int, casus := "", goal := "", brk := false) -> Dictionary:
	var c := {"type": "declare_war", "player": player, "target": target}
	if casus != "":
		c["cb"] = casus
		c["goal"] = goal
	if brk:
		c["brk"] = true
	return c


## Buts de guerre (voir Wars.check_act) : "claim" (x = système), "goal" (x = ennemi, s = but du
## défenseur), "demand" (x = ennemi : exiger la reddition), "yield" (x = ennemi : se rendre).
static func war_act(player: int, act: String, x := -1, s := "") -> Dictionary:
	return {"type": "war_act", "player": player, "act": act, "x": x, "s": s}


## Souverain (voir Rulers) : act = power | post | law | educate | legacy | marry | abdicate.
static func ruler_act(player: int, act: String, x := -1, s := "") -> Dictionary:
	return {"type": "ruler_act", "player": player, "act": act, "x": x, "s": s}


## Cour et Grandes Maisons (voir Court.check_act).
static func court_act(player: int, act: String, x := -1, y := -1, s := "") -> Dictionary:
	return {"type": "court_act", "player": player, "act": act, "x": x, "y": y, "s": s}


## Frontières (voir Borders.check_act) : "policy" (x = empire, s = politique), "summon" (x = intrus),
## "pass" (x = propriétaire, y = flotte : laissez-passer), "toll" (x = péage), "arbiter" (x, y : libre-passage
## imposé par l'Arbitre), "answer_pass" (x = demande, y = 1 accepter / 0 refuser).
static func border_act(player: int, act: String, x := -1, y := -1, s := "") -> Dictionary:
	return {"type": "border_act", "player": player, "act": act, "x": x, "y": y, "s": s}


## Armées (voir Ground.check_act) : "recruit" (x = système, s = type, s2 = espèce), "embark" et
## "disembark" (x = flotte), "demob" (x = régiment), "retreat" (x = système de la bataille au sol).
static func ground_act(player: int, act: String, x := -1, s := "", s2 := "") -> Dictionary:
	return {"type": "ground_act", "player": player, "act": act, "x": x, "s": s, "s2": s2}


## Logistique : réquisition d'un système assiégé par une flotte (Logistics.check_requisition).
static func requisition(player: int, fleet_id: int) -> Dictionary:
	return {"type": "requisition", "player": player, "fleet": fleet_id}


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


## Choisit la récompense d'un haut fait (voir Deeds) : entrée item de sa boîte, choix index.
static func deed_choose(player: int, item: int, index: int) -> Dictionary:
	return {"type": "deed_choose", "player": player, "item": item, "index": index}


## Fouilles et reliques (voir Relics).
static func dig_start(player: int, system_id: int, method := "") -> Dictionary:
	return {"type": "dig_start", "player": player, "system": system_id, "method": method}


## Verse un lot d'énergie ou de matériaux au grand chantier commun contre la crise (Phare des Âges,
## Banque des Étoiles ; voir CrisisKinds).
static func crisis_fund(player: int, res: String) -> Dictionary:
	return {"type": "crisis_fund", "player": player, "res": res}


## Devenir la crise : prendre la voie de l'Ambition démesurée.
static func crisis_ambition(player: int) -> Dictionary:
	return {"type": "crisis_ambition", "player": player}


## Le Fléau des étoiles verse au grand œuvre.
static func crisis_oeuvre(player: int, res: String) -> Dictionary:
	return {"type": "crisis_oeuvre", "player": player, "res": res}


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


## Amphictyonie (voir Amphictyony) : signer l'acte de fondation, adhérer, partir.
static func amph_found(player: int) -> Dictionary:
	return {"type": "amph_found", "player": player}


static func amph_join(player: int) -> Dictionary:
	return {"type": "amph_join", "player": player}


static func amph_leave(player: int) -> Dictionary:
	return {"type": "amph_leave", "player": player}


## Déposer une proposition : kind "step" (famille fam, direction dir +1 voie A / -1 voie B),
## "sanction" (sanc contre target) ou "expel" (bannir target).
static func amph_propose(player: int, kind: String, fam := "", dir := 0, target := -1, sanc := "") -> Dictionary:
	return {"type": "amph_propose", "player": player, "kind": kind, "fam": fam, "dir": dir, "target": target, "sanc": sanc}


## Soutenir une proposition de la file (ou retirer son soutien).
static func amph_support(player: int, prop_id: int) -> Dictionary:
	return {"type": "amph_support", "player": player, "prop": prop_id}


static func amph_withdraw(player: int) -> Dictionary:
	return {"type": "amph_withdraw", "player": player}


## Vote en séance : 1 pour, -1 contre, 0 abstention (modifiable jusqu'à la clôture).
static func amph_vote(player: int, v: int) -> Dictionary:
	return {"type": "amph_vote", "player": player, "v": v}


## Acheter une tranche de voix pour le vote en cours (camp de son vote).
static func amph_buy(player: int) -> Dictionary:
	return {"type": "amph_buy", "player": player}


## Acte d'Amphictyonie du lot 2 (voir AmphInst.check_act) : veto, urgent (x = proposition), denounce (x),
## freeze (x), close, truce (x, y), call (x = débiteur), observe, convene (x = crise), svote (x = vote),
## aid_ask (s = ressource), aid_give (x = empire, y = quantité), work_give (x = quantité).
static func amph_act(player: int, act: String, x := -1, y := -1, s := "") -> Dictionary:
	return {"type": "amph_act", "player": player, "act": act, "x": x, "y": y, "s": s}


## Sujets et paix à conditions (voir Vassals.check_act) : "terms" (x = vaincu, terms = conditions),
## "surrender" / "protect" (x = vainqueur / protecteur), "freedom", "set_terms" (x = sujet, terms =
## clauses ou s = préréglage), "release", "integrate", "support" (x = sujet), "fealty" (x = rival, -1 retire).
static func vas_act(player: int, act: String, x := -1, s := "", terms := {}) -> Dictionary:
	return {"type": "vas_act", "player": player, "act": act, "x": x, "s": s, "terms": terms}


## Koinon (voir Koinon.check_act) : "found" (x = allié, s = forme), "join" (x = membre, s = "member" /
## "assoc"), "propose" (x = cible ou cran, s = "genre:détail"),
## "vote" : x = numéro du vote, s = "yes" / "no" ou l'id du candidat ; "leave", "grant" (x = membre, n = énergie), "consigne" (x = 1 pour / -1 contre / 0 libre).
static func koi_act(player: int, act: String, x := -1, s := "", n := 0) -> Dictionary:
	return {"type": "koi_act", "player": player, "act": act, "x": x, "s": s, "n": n}


## Puissances anciennes (voir Ancients.check_act) : "give" (x = ancienne, s = ressource), "war",
## "peace", "ask" (n = empire visé), et les actes de l'Éveil.
static func anc_act(player: int, act: String, x := -1, s := "", n := -1) -> Dictionary:
	return {"type": "anc_act", "player": player, "act": act, "x": x, "s": s, "n": n}


## Peuples mineurs (voir Minors.check_act) : "envoy" (n = intensité), "gift" (s = ressource), "post",
## "levy", "integrate", "war", "peace", "deliver", "trait" (s = sorte), et les actes des lots 2 et 3.
static func min_act(player: int, act: String, x := -1, s := "", n := -1) -> Dictionary:
	return {"type": "min_act", "player": player, "act": act, "x": x, "s": s, "n": n}


## Merveilles galactiques (WondersBridges.check_act) : start (s = merveille, x = planète), cancel,
## contribute (x = colonie qui verse), rush, restore (x = planète en ruine), plans, tribunal, join.
static func won_act(player: int, act: String, s := "", x := -1, n := -1) -> Dictionary:
	return {"type": "won_act", "player": player, "act": act, "s": s, "x": x, "n": n}


## Rayonnement culturel (CultureBridges.check_act) : osmose, savoir, ambassade, fermer, troupe.
static func cul_act(player: int, act: String, x := -1, s := "", n := -1) -> Dictionary:
	return {"type": "cul_act", "player": player, "act": act, "x": x, "s": s, "n": n}


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


## Le chef de foi ajoute un précepte à sa foi (voir Faiths).
static func faith_precept(player: int, faith: String, precept: String) -> Dictionary:
	return {"type": "faith_precept", "player": player, "faith": faith, "precept": precept}


## Le fondateur fixe sa foi : nature (parmi les 3 proposées), doctrines {axe: position} et premier
## précepte (un schisme ne choisit que sa nature : doctrines {} et précepte "").
static func faith_choose(player: int, faith: String, nature: String, doctrines: Dictionary, precept: String) -> Dictionary:
	return {"type": "faith_choose", "player": player, "faith": faith, "nature": nature, "doctrines": doctrines, "precept": precept}


## Concile : le chef de foi change une position de doctrine.
static func faith_concile(player: int, faith: String, axis: String, option: String) -> Dictionary:
	return {"type": "faith_concile", "player": player, "faith": faith, "axis": axis, "option": option}


## Le chef de foi excommunie un empire de sa foi.
static func faith_excom(player: int, target: int) -> Dictionary:
	return {"type": "faith_excom", "player": player, "target": target}


## Met en place ou lève la quarantaine contre le Parasite saint.
static func faith_quarantine(player: int) -> Dictionary:
	return {"type": "faith_quarantine", "player": player}


## Voies sacrées : le chef de foi bénit la route de saut a-b.
static func faith_bless(player: int, a: int, b: int) -> Dictionary:
	return {"type": "faith_bless", "player": player, "a": a, "b": b}


## Voies sacrées : réglage d'une route bénie ("open", "closed", "toll").
static func faith_lane(player: int, key: String, mode: String) -> Dictionary:
	return {"type": "faith_lane", "player": player, "lane": key, "mode": mode}


## Précepte Sacrifices : offrir un fidèle d'une colonie pour du zèle.
static func faith_sacrifice(player: int, planet_id: int) -> Dictionary:
	return {"type": "faith_sacrifice", "player": player, "planet": planet_id}


## Envoie une mission de prêche dans un système (voir FaithWars).
static func faith_mission(player: int, system_id: int) -> Dictionary:
	return {"type": "faith_mission", "player": player, "system": system_id}


## Chasse les missions étrangères d'un de ses systèmes (mission d'inquisition).
static func faith_ward(player: int, system_id: int) -> Dictionary:
	return {"type": "faith_ward", "player": player, "system": system_id}


## Le chef de foi appelle à la croisade contre un empire.
static func faith_crusade(player: int, target: int) -> Dictionary:
	return {"type": "faith_crusade", "player": player, "target": target}


## Concile (Code saint) : une hérésie rentre dans la foi mère.
static func faith_council(player: int, heresy: String) -> Dictionary:
	return {"type": "faith_council", "player": player, "faith": heresy}


## Réécriture (Code saint) : le plus ancien précepte est remplacé.
static func faith_rewrite(player: int, faith: String, precept: String) -> Dictionary:
	return {"type": "faith_rewrite", "player": player, "faith": faith, "precept": precept}


## Culte du Je : "ecraser" ou "tolerer" les drones dissidents d'une colonie de ruche.
## Action d'une nature classique de foi (FaithNatures.check / apply) : act et ses arguments.
static func faith_nat(player: int, act: String, args := {}) -> Dictionary:
	return {"type": "faith_nat", "player": player, "act": act, "args": args}


## Religion, lot 4 : vocation de foi d'un héros (prophete, inquisiteur, martyr).
static func faith_voc(player: int, hero_id: int, voc: String) -> Dictionary:
	return {"type": "faith_voc", "player": player, "hero": hero_id, "voc": voc}


static func faith_je(player: int, planet_id: int, what: String) -> Dictionary:
	return {"type": "faith_je", "player": player, "planet": planet_id, "what": what}


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
## Administration : effort administratif, intégration d'un système, transfert de capitale.
static func admin_effort(player: int, effort_id: String) -> Dictionary:
	return {"type": "admin_effort", "player": player, "effort": effort_id}


static func admin_integrate(player: int, system_id: int) -> Dictionary:
	return {"type": "admin_integrate", "player": player, "system": system_id}


static func admin_capital(player: int, planet_id: int) -> Dictionary:
	return {"type": "admin_capital", "player": player, "planet": planet_id}


## Fiscalité : cran d'impôt, solde, impôt de guerre, approche de crise, emprunts, prêts, planche à billets, franchises.
static func finance_tax(player: int, tax_id: String) -> Dictionary:
	return {"type": "finance_tax", "player": player, "tax": tax_id}


static func finance_pay(player: int, pay_id: String) -> Dictionary:
	return {"type": "finance_pay", "player": player, "pay": pay_id}


static func finance_war_tax(player: int, on: bool) -> Dictionary:
	return {"type": "finance_war_tax", "player": player, "on": on}


static func finance_approach(player: int, approach_id: String) -> Dictionary:
	return {"type": "finance_approach", "player": player, "approach": approach_id}


static func finance_borrow(player: int, lender: String, amount: int) -> Dictionary:
	return {"type": "finance_borrow", "player": player, "lender": lender, "amount": amount}


static func finance_repay(player: int, loan_id: int, amount: int) -> Dictionary:
	return {"type": "finance_repay", "player": player, "loan": loan_id, "amount": amount}


static func finance_lend(player: int, borrower: int, amount: int) -> Dictionary:
	return {"type": "finance_lend", "player": player, "borrower": borrower, "amount": amount}


static func finance_repudiate(player: int, loan_id: int) -> Dictionary:
	return {"type": "finance_repudiate", "player": player, "loan": loan_id}


static func finance_mint(player: int) -> Dictionary:
	return {"type": "finance_mint", "player": player}


static func finance_franchise(player: int, system_id: int) -> Dictionary:
	return {"type": "finance_franchise", "player": player, "system": system_id}


## Économie privée (voir Private.check) : subventionner, licence, commande, charte, nationaliser…
static func private_act(player: int, act: String, a := -1, b := -1, s := "") -> Dictionary:
	return {"type": "private", "player": player, "act": act, "a": a, "b": b, "s": s}


## Ingénierie des espèces (voir Genetics.check) : "mod" (d : fid, add, rem, bio), "cyber", "transfer"
## (d : fid), "cancel" (d : id), "path" (d : path), "renounce", et ceux du lot 2/3 (GeneticsBridges).
static func gen_act(player: int, act: String, d := {}) -> Dictionary:
	return {"type": "genetics", "player": player, "act": act, "d": d}


## Pouvoirs psioniques (voir Psionics.check) : "path" (L'Éveil), "power" (d : power, target), et ceux
## du Songe (PsionicsDream).
static func psi_act(player: int, act: String, d := {}) -> Dictionary:
	return {"type": "psionics", "player": player, "act": act, "d": d}


## Transcendance (voir Transcendence.check) : "path" (d : path), "oeuvre" (d : sys), "join" (d : host),
## "renounce", et ceux des ponts (TranscendenceBridges).
static func tr_act(player: int, act: String, d := {}) -> Dictionary:
	return {"type": "transcendence", "player": player, "act": act, "d": d}


## Mégastructures (voir Megastructures.check) : "plan" (k, s, p, f?), "pose" (f, k, p), "advance" (id),
## "repair" (id), "restore" (id), "cancel" (id), "module" (id, m), "launch" (id, f, t), "fire" (id, t),
## "purge" (id), et ceux des ponts (MegasBridges).
static func mega_act(player: int, act: String, d := {}) -> Dictionary:
	return {"type": "megastructures", "player": player, "act": act, "d": d}


## Forge des mondes (voir WorldForge.check) : "start" / "plan" (op, s, p, a), "cancel" (id), "melt" (n),
## "unplan" (f), "move" (p, t), "rosette" (s), "ram" (p, t), "order" (seller, s, a).
static func forge_act(player: int, act: String, d := {}) -> Dictionary:
	return {"type": "worldforge", "player": player, "act": act, "d": d}


## Contact (voir Contact.check) : "share" (d : v), "intuition", "transmit", "rate" (d : v), "announce",
## "verify", "plans_raw", "plans_audit", et ceux de la course (ContactRace) et des voix (ContactVoices).
static func ct_act(player: int, act: String, d := {}) -> Dictionary:
	return {"type": "contact", "player": player, "act": act, "d": d}


## Archéologie (voir Archaeology.check) : actions de fragments "fa_*", "forge" (k : nature), "reco" (d), "secrets" (d), "permit"
## (host, share), "restitute" (id), "sell_antiq" (id), "aster", "collector_buy" (i), "collector_sell" (id).
static func ar_act(player: int, act: String, d := {}) -> Dictionary:
	return {"type": "archaeology", "player": player, "act": act, "d": d}


## Échelle de Kardashev (voir Kardashev.check) : "perk" (id), "sober" (on), "veil", "relight" (s).
static func kd_act(player: int, act: String, d := {}) -> Dictionary:
	return {"type": "kardashev", "player": player, "act": act, "d": d}


## Mondes vivants (voir LivingWorlds.check) : "invite", "listen", "seed", "fuse" (p = planète).
static func living_act(player: int, act: String, d := {}) -> Dictionary:
	return {"type": "living", "player": player, "act": act, "d": d}


## Furtivité : "pose" (a = flotte, s = posture : "", "silence", "scan", "ambush"), "beacon" (a = flotte).
static func stealth_act(player: int, act: String, a := -1, b := -1, s := "") -> Dictionary:
	return {"type": "stealth", "player": player, "act": act, "a": a, "b": b, "s": s}


## Défenses spatiales : "guard"/"unguard" (a = flotte), "modernize" (a = système).
## Portails de saut : l'occupant rase le portail d'un système (voir Portals).
static func portal_raze(player: int, system_id: int) -> Dictionary:
	return {"type": "portal_raze", "player": player, "system": system_id}


static func defense_act(player: int, act: String, a := -1, b := -1, s := "") -> Dictionary:
	return {"type": "defense", "player": player, "act": act, "a": a, "b": b, "s": s}


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
		"amph_found":
			return Amphictyony.check_found(state, int(cmd["player"]))
		"amph_join":
			return Amphictyony.check_join(state, int(cmd["player"]))
		"amph_leave":
			return Amphictyony.check_leave(state, int(cmd["player"]))
		"amph_propose":
			return Amphictyony.check_propose(state, int(cmd["player"]), String(cmd.get("kind", "")), String(cmd.get("fam", "")), int(cmd.get("dir", 0)), int(cmd.get("target", -1)), String(cmd.get("sanc", "")))
		"amph_support":
			return Amphictyony.check_support(state, int(cmd["player"]), int(cmd.get("prop", -1)))
		"amph_withdraw":
			return Amphictyony.check_withdraw(state, int(cmd["player"]))
		"amph_vote":
			return Amphictyony.check_vote(state, int(cmd["player"]), int(cmd.get("v", 9)))
		"amph_buy":
			return Amphictyony.check_buy(state, int(cmd["player"]))
		"anc_act":
			return Ancients.check_act(state, int(cmd["player"]), String(cmd.get("act", "")), int(cmd.get("x", -1)), String(cmd.get("s", "")), int(cmd.get("n", -1)))
		"min_act":
			return Minors.check_act(state, int(cmd["player"]), String(cmd.get("act", "")), int(cmd.get("x", -1)), String(cmd.get("s", "")), int(cmd.get("n", -1)))
		"won_act":
			return WondersBridges.check_act(state, int(cmd["player"]), String(cmd.get("act", "")), String(cmd.get("s", "")), int(cmd.get("x", -1)), int(cmd.get("n", -1)))
		"cul_act":
			return CultureBridges.check_act(state, int(cmd["player"]), String(cmd.get("act", "")), int(cmd.get("x", -1)), String(cmd.get("s", "")), int(cmd.get("n", -1)))
		"koi_act":
			return Koinon.check_act(state, int(cmd["player"]), String(cmd.get("act", "")), int(cmd.get("x", -1)), String(cmd.get("s", "")), int(cmd.get("n", 0)))
		"vas_act":
			var vt: Variant = cmd.get("terms", {})
			return Vassals.check_act(state, int(cmd["player"]), String(cmd.get("act", "")), int(cmd.get("x", -1)), String(cmd.get("s", "")), vt if vt is Dictionary else {})
		"amph_act":
			return AmphInst.check_act(state, int(cmd["player"]), String(cmd.get("act", "")), int(cmd.get("x", -1)), int(cmd.get("y", -1)), String(cmd.get("s", "")))
		"politics_support":
			return Politics.check_support(state, int(cmd["player"]), int(cmd.get("current", -2)))
		"peoples_status":
			return Peoples.check_status(state, int(cmd["player"]), String(cmd.get("species", "")), String(cmd.get("status", "")))
		"faith_state":
			return Faiths.check_state(state, int(cmd["player"]), String(cmd.get("faith", "")))
		"faith_precept":
			return Faiths.check_precept(state, int(cmd["player"]), String(cmd.get("faith", "")), String(cmd.get("precept", "")))
		"faith_choose":
			var dc: Variant = cmd.get("doctrines", {})
			return Faiths.check_choose(state, int(cmd["player"]), String(cmd.get("faith", "")), String(cmd.get("nature", "")),
					dc if dc is Dictionary else {}, String(cmd.get("precept", "")))
		"faith_concile":
			return FaithWars.check_concile(state, int(cmd["player"]), String(cmd.get("faith", "")), String(cmd.get("axis", "")), String(cmd.get("option", "")))
		"faith_excom":
			return FaithWars.check_excom(state, int(cmd["player"]), int(cmd.get("target", -1)))
		"faith_quarantine":
			return FaithWars.check_quarantine(state, int(cmd["player"]))
		"faith_bless":
			return FaithWars.check_bless(state, int(cmd["player"]), int(cmd.get("a", -1)), int(cmd.get("b", -1)))
		"faith_lane":
			return FaithWars.check_lane_mode(state, int(cmd["player"]), String(cmd.get("lane", "")), String(cmd.get("mode", "")))
		"faith_sacrifice":
			return FaithWars.check_sacrifice(state, int(cmd["player"]), int(cmd.get("planet", -1)))
		"faith_mission":
			return FaithWars.check_mission(state, int(cmd["player"]), int(cmd.get("system", -1)))
		"faith_ward":
			return FaithWars.check_ward(state, int(cmd["player"]), int(cmd.get("system", -1)))
		"faith_crusade":
			return FaithWars.check_crusade(state, int(cmd["player"]), int(cmd.get("target", -1)))
		"faith_council":
			return FaithWars.check_council(state, int(cmd["player"]), String(cmd.get("faith", "")))
		"faith_rewrite":
			return FaithWars.check_rewrite(state, int(cmd["player"]), String(cmd.get("faith", "")), String(cmd.get("precept", "")))
		"faith_nat":
			var na: Variant = cmd.get("args", {})
			return FaithNatures.check(state, int(cmd["player"]), String(cmd.get("act", "")), na if na is Dictionary else {})
		"faith_voc":
			return FaithBridges.check_voc(state, int(cmd["player"]), int(cmd.get("hero", -1)), String(cmd.get("voc", "")))
		"faith_je":
			return FaithWars.check_je(state, int(cmd["player"]), int(cmd.get("planet", -1)), String(cmd.get("what", "")))
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
		"admin_effort":
			return Admin.check_effort(state, int(cmd["player"]), String(cmd.get("effort", "")))
		"admin_integrate":
			return Admin.check_integrate(state, int(cmd["player"]), int(cmd.get("system", -1)))
		"admin_capital":
			return Admin.check_move_capital(state, int(cmd["player"]), int(cmd.get("planet", -1)))
		"finance_tax":
			return Finance.check_tax(state, int(cmd["player"]), String(cmd.get("tax", "")))
		"finance_pay":
			return Finance.check_pay(state, int(cmd["player"]), String(cmd.get("pay", "")))
		"finance_war_tax":
			return Finance.check_war_tax(state, int(cmd["player"]), bool(cmd.get("on", false)))
		"finance_approach":
			return Finance.check_approach(state, int(cmd["player"]), String(cmd.get("approach", "")))
		"finance_borrow":
			return Finance.check_borrow(state, int(cmd["player"]), String(cmd.get("lender", "bank")), int(cmd.get("amount", 0)))
		"finance_repay":
			return Finance.check_repay(state, int(cmd["player"]), int(cmd.get("loan", -1)), int(cmd.get("amount", 0)))
		"finance_lend":
			return Finance.check_lend(state, int(cmd["player"]), int(cmd.get("borrower", -1)), int(cmd.get("amount", 0)))
		"finance_repudiate":
			return Finance.check_repudiate(state, int(cmd["player"]), int(cmd.get("loan", -1)))
		"finance_mint":
			return Finance.check_mint(state, int(cmd["player"]))
		"finance_franchise":
			return Finance.check_franchise(state, int(cmd["player"]), int(cmd.get("system", -1)))
		"genetics":
			return Genetics.check(state, int(cmd["player"]), String(cmd.get("act", "")), cmd.get("d", {}) as Dictionary)
		"psionics":
			return Psionics.check(state, int(cmd["player"]), String(cmd.get("act", "")), cmd.get("d", {}) as Dictionary)
		"megastructures":
			return Megastructures.check(state, int(cmd["player"]), String(cmd.get("act", "")), cmd.get("d", {}) as Dictionary)
		"worldforge":
			return WorldForge.check(state, int(cmd["player"]), String(cmd.get("act", "")), cmd.get("d", {}) as Dictionary)
		"transcendence":
			return Transcendence.check(state, int(cmd["player"]), String(cmd.get("act", "")), cmd.get("d", {}) as Dictionary)
		"archaeology":
			return Archaeology.check(state, int(cmd["player"]), String(cmd.get("act", "")), cmd.get("d", {}) as Dictionary)
		"kardashev":
			return Kardashev.check(state, int(cmd["player"]), String(cmd.get("act", "")), cmd.get("d", {}) as Dictionary)
		"living":
			return LivingWorlds.check(state, int(cmd["player"]), String(cmd.get("act", "")), cmd.get("d", {}) as Dictionary)
		"contact":
			return Contact.check(state, int(cmd["player"]), String(cmd.get("act", "")), cmd.get("d", {}) as Dictionary)
		"stealth":
			return Stealth.check(state, int(cmd["player"]), String(cmd.get("act", "")), int(cmd.get("a", -1)), int(cmd.get("b", -1)), String(cmd.get("s", "")))
		"portal_raze":
			return Portals.check_raze(state, int(cmd["player"]), int(cmd.get("system", -1)))
		"defense":
			return Defenses.check(state, int(cmd["player"]), String(cmd.get("act", "")), int(cmd.get("a", -1)), int(cmd.get("b", -1)), String(cmd.get("s", "")))
		"private":
			return Private.check(state, int(cmd["player"]), String(cmd.get("act", "")), int(cmd.get("a", -1)), int(cmd.get("b", -1)), String(cmd.get("s", "")))
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
			var dw := Combat.check_declare_war(state, int(cmd["player"]), int(cmd.get("target", -1)), bool(cmd.get("brk", false)))
			if dw == "" and state.wars_on and String(cmd.get("cb", "")) != "":
				dw = Wars.check_choice(state, int(cmd["player"]), int(cmd["target"]), String(cmd["cb"]), String(cmd.get("goal", "")))
			return dw
		"requisition":
			return Logistics.check_requisition(state, int(cmd["player"]), int(cmd.get("fleet", -1)))
		"ground_act":
			return Ground.check_act(state, int(cmd["player"]), String(cmd.get("act", "")), int(cmd.get("x", -1)), String(cmd.get("s", "")), String(cmd.get("s2", "")))
		"border_act":
			return Borders.check_act(state, int(cmd["player"]), String(cmd.get("act", "")), int(cmd.get("x", -1)), int(cmd.get("y", -1)), String(cmd.get("s", "")))
		"war_act":
			return Wars.check_act(state, int(cmd["player"]), String(cmd.get("act", "")), int(cmd.get("x", -1)), String(cmd.get("s", "")))
		"court_act":
			return Court.check_act(state, int(cmd["player"]), String(cmd.get("act", "")), int(cmd.get("x", -1)), int(cmd.get("y", -1)), String(cmd.get("s", "")))
		"ruler_act":
			return Rulers.check_act(state, int(cmd["player"]), String(cmd.get("act", "")), int(cmd.get("x", -1)), String(cmd.get("s", "")))
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
		"deed_choose":
			return Deeds.check_choose(state, int(cmd["player"]), int(cmd.get("item", -1)), int(cmd.get("index", -1)))
		"dig_start":
			return Relics.check_start(state, int(cmd["player"]), int(cmd.get("system", -1)), String(cmd.get("method", "")))
		"dig_clue":
			return Relics.check_clue(state, int(cmd["player"]), int(cmd.get("system", -1)))
		"crisis_fund":
			return CrisisKinds.check_fund(state, int(cmd["player"]), String(cmd.get("res", "")))
		"crisis_ambition":
			return CrisisNemesis.check_ambition(state, int(cmd["player"]))
		"crisis_oeuvre":
			return CrisisNemesis.check_oeuvre(state, int(cmd["player"]), String(cmd.get("res", "")))
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
			Vassals.on_found(state, e.id, Economy.claim_cost_for(state, e.id, pid, kind))
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
			c.days_left = LivingWorlds.claim_days(state, e.id, pid, Economy.claim_days(kind))  # monde vivant Méfiant : deux fois plus long
			var sp := String(cmd.get("species", ""))
			c.founder = sp if kind == Colony.KIND_COLONY and sp != e.faction_id else ""
			state.add_colony(c)
			AncientsBridges.on_colonize(state, e.id, pid)  # Monde saint : guerre sainte
		"build":
			if Wonders.is_wonder(String(cmd["building"])):
				var wb_added: Array[Dictionary] = []
				Wonders.start(state, int(cmd["player"]), int(cmd["planet"]), String(cmd["building"]), wb_added)
				return
			var e := state.get_empire(int(cmd["player"]))
			var c: Colony = state.colonies[int(cmd["planet"])]
			var b := GameData.building(String(cmd["building"]))
			Economy.pay(e, Economy.building_cost(state, e.id, String(cmd["building"])))
			c.construction = String(cmd["building"])
			# Loi « Cadences » : chantiers plus courts.
			c.construction_days = maxi(1, Research.scaled(int(b["days"]), Research.fx_int(state, e.id, "building_days_pct")))
			# Contact : Oreilles bâties plus vite par les Lignées d'Ossarane.
			if bool(b.get("contact", false)) and not state.contact.is_empty():
				c.construction_days = ContactVoices.build_days(state, e.id, String(cmd["building"]), c.construction_days)
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
			Ground.on_merge(state, f.id, into.id)
			Logistics.on_merge(state, f.id, into.id)
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
			Ground.on_split(state, f, nf)
			Logistics.on_split(state, f, nf)
		"sacrifice":
			var e := state.get_empire(int(cmd["player"]))
			var c: Colony = state.colonies[int(cmd["planet"])]
			var fv: Dictionary = e.faction()["fervor"]
			c.population -= 1
			c.growth = 0
			e.fervor = mini(int(fv["max"]), e.fervor + FactionTraits.sacrifice_gain(state, e.id))
			Research.count_stat(state, e.id, "sacrifices")
			FaithNatures.on_offering(state, e.id)
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
		"amph_found":
			Amphictyony.found_sign(state, int(cmd["player"]))
		"amph_join":
			Amphictyony.join(state, int(cmd["player"]))
		"amph_leave":
			Amphictyony.leave(state, int(cmd["player"]))
		"amph_propose":
			Amphictyony.propose(state, int(cmd["player"]), String(cmd["kind"]), String(cmd.get("fam", "")), int(cmd.get("dir", 0)), int(cmd.get("target", -1)), String(cmd.get("sanc", "")))
		"amph_support":
			Amphictyony.support(state, int(cmd["player"]), int(cmd["prop"]))
		"amph_withdraw":
			Amphictyony.withdraw(state, int(cmd["player"]))
		"amph_vote":
			Amphictyony.vote(state, int(cmd["player"]), int(cmd["v"]))
		"amph_buy":
			Amphictyony.buy(state, int(cmd["player"]))
		"anc_act":
			var an_added: Array[Dictionary] = []
			Ancients.act(state, int(cmd["player"]), String(cmd["act"]), int(cmd.get("x", -1)), String(cmd.get("s", "")), int(cmd.get("n", -1)), an_added)
		"min_act":
			var mi_added: Array[Dictionary] = []
			Minors.act(state, int(cmd["player"]), String(cmd["act"]), int(cmd.get("x", -1)), String(cmd.get("s", "")), int(cmd.get("n", -1)), mi_added)
		"won_act":
			var wo_added: Array[Dictionary] = []
			WondersBridges.act(state, int(cmd["player"]), String(cmd["act"]), String(cmd.get("s", "")), int(cmd.get("x", -1)), int(cmd.get("n", -1)), wo_added)
		"cul_act":
			var cu_added: Array[Dictionary] = []
			CultureBridges.act(state, int(cmd["player"]), String(cmd["act"]), int(cmd.get("x", -1)), String(cmd.get("s", "")), int(cmd.get("n", -1)), cu_added)
		"koi_act":
			Koinon.act(state, int(cmd["player"]), String(cmd["act"]), int(cmd.get("x", -1)), String(cmd.get("s", "")), int(cmd.get("n", 0)))
		"vas_act":
			Vassals.act(state, int(cmd["player"]), String(cmd["act"]), int(cmd.get("x", -1)), String(cmd.get("s", "")), cmd.get("terms", {}))
		"amph_act":
			AmphInst.act(state, int(cmd["player"]), String(cmd["act"]), int(cmd.get("x", -1)), int(cmd.get("y", -1)), String(cmd.get("s", "")))
		"politics_support":
			Politics.support(state, int(cmd["player"]), int(cmd["current"]))
		"peoples_status":
			Peoples.set_status(state, int(cmd["player"]), String(cmd["species"]), String(cmd["status"]))
		"faith_state":
			Faiths.set_state(state, int(cmd["player"]), String(cmd["faith"]))
		"faith_precept":
			Faiths.add_precept(state, String(cmd["faith"]), String(cmd["precept"]))
		"faith_choose":
			Faiths.choose(state, String(cmd["faith"]), String(cmd["nature"]), cmd.get("doctrines", {}), String(cmd.get("precept", "")))
		"faith_concile":
			FaithWars.concile(state, int(cmd["player"]), String(cmd["faith"]), String(cmd["axis"]), String(cmd["option"]))
		"faith_excom":
			FaithWars.excommunicate(state, int(cmd["player"]), int(cmd["target"]))
		"faith_quarantine":
			FaithWars.toggle_quarantine(state, int(cmd["player"]))
		"faith_bless":
			FaithWars.bless(state, int(cmd["player"]), int(cmd["a"]), int(cmd["b"]))
		"faith_lane":
			FaithWars.set_lane_mode(state, String(cmd["lane"]), String(cmd["mode"]))
		"faith_sacrifice":
			FaithWars.sacrifice(state, int(cmd["player"]), int(cmd["planet"]))
		"faith_mission":
			FaithWars.mission(state, int(cmd["player"]), int(cmd["system"]))
		"faith_ward":
			FaithWars.ward(state, int(cmd["player"]), int(cmd["system"]))
		"faith_crusade":
			FaithWars.crusade(state, int(cmd["player"]), int(cmd["target"]))
		"faith_council":
			FaithWars.council(state, int(cmd["player"]), String(cmd["faith"]))
		"faith_rewrite":
			FaithWars.rewrite(state, int(cmd["player"]), String(cmd["faith"]), String(cmd["precept"]))
		"faith_nat":
			FaithNatures.apply(state, int(cmd["player"]), String(cmd["act"]), cmd.get("args", {}))
		"faith_voc":
			FaithBridges.apply_voc(state, int(cmd["player"]), int(cmd["hero"]), String(cmd["voc"]))
		"faith_je":
			FaithWars.je_act(state, int(cmd["player"]), int(cmd["planet"]), String(cmd["what"]))
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
		"admin_effort":
			Admin.set_effort(state, int(cmd["player"]), String(cmd["effort"]))
		"admin_integrate":
			Admin.integrate(state, int(cmd["player"]), int(cmd["system"]))
		"admin_capital":
			Admin.move_capital(state, int(cmd["player"]), int(cmd["planet"]))
		"finance_tax":
			Finance.set_tax(state, int(cmd["player"]), String(cmd["tax"]))
		"finance_pay":
			Finance.set_pay(state, int(cmd["player"]), String(cmd["pay"]))
		"finance_war_tax":
			Finance.set_war_tax(state, int(cmd["player"]), bool(cmd["on"]))
		"finance_approach":
			Finance.set_approach(state, int(cmd["player"]), String(cmd["approach"]))
		"finance_borrow":
			Finance.borrow(state, int(cmd["player"]), String(cmd["lender"]), int(cmd["amount"]))
		"finance_repay":
			Finance.repay(state, int(cmd["player"]), int(cmd["loan"]), int(cmd["amount"]))
		"finance_lend":
			Finance.lend(state, int(cmd["player"]), int(cmd["borrower"]), int(cmd["amount"]))
		"finance_repudiate":
			Finance.repudiate(state, int(cmd["player"]), int(cmd["loan"]), [] as Array[Dictionary])
		"finance_mint":
			Finance.mint(state, int(cmd["player"]))
		"finance_franchise":
			Finance.toggle_franchise(state, int(cmd["player"]), int(cmd["system"]))
		"genetics":
			Genetics.apply(state, int(cmd["player"]), String(cmd["act"]), cmd.get("d", {}) as Dictionary)
		"psionics":
			Psionics.apply(state, int(cmd["player"]), String(cmd["act"]), cmd.get("d", {}) as Dictionary)
		"transcendence":
			Transcendence.apply(state, int(cmd["player"]), String(cmd["act"]), cmd.get("d", {}) as Dictionary)
		"megastructures":
			Megastructures.apply(state, int(cmd["player"]), String(cmd["act"]), cmd.get("d", {}) as Dictionary)
		"worldforge":
			WorldForge.apply(state, int(cmd["player"]), String(cmd["act"]), cmd.get("d", {}) as Dictionary)
		"archaeology":
			Archaeology.apply(state, int(cmd["player"]), String(cmd["act"]), cmd.get("d", {}) as Dictionary)
		"kardashev":
			Kardashev.apply(state, int(cmd["player"]), String(cmd["act"]), cmd.get("d", {}) as Dictionary)
		"living":
			LivingWorlds.apply(state, int(cmd["player"]), String(cmd["act"]), cmd.get("d", {}) as Dictionary)
		"contact":
			Contact.apply(state, int(cmd["player"]), String(cmd["act"]), cmd.get("d", {}) as Dictionary)
		"stealth":
			Stealth.apply(state, int(cmd["player"]), String(cmd["act"]), int(cmd.get("a", -1)), int(cmd.get("b", -1)), String(cmd.get("s", "")))
		"portal_raze":
			Portals.raze(state, int(cmd["player"]), int(cmd["system"]))
		"defense":
			Defenses.apply(state, int(cmd["player"]), String(cmd["act"]), int(cmd.get("a", -1)), int(cmd.get("b", -1)), String(cmd.get("s", "")))
		"private":
			Private.apply(state, int(cmd["player"]), String(cmd["act"]), int(cmd.get("a", -1)), int(cmd.get("b", -1)), String(cmd.get("s", "")))
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
		"deed_choose":
			var de_added: Array[Dictionary] = []
			Deeds.choose(state, int(cmd["player"]), int(cmd["item"]), int(cmd["index"]), de_added)
		"dig_start":
			Relics.start(state, int(cmd["player"]), int(cmd["system"]), String(cmd.get("method", "")))
		"dig_clue":
			Relics.buy_clue(state, int(cmd["player"]), int(cmd["system"]))
		"crisis_fund":
			var cf_added: Array[Dictionary] = []
			CrisisKinds.fund(state, int(cmd["player"]), String(cmd["res"]), cf_added)
		"crisis_ambition":
			var ca_added: Array[Dictionary] = []
			CrisisNemesis.take(state, int(cmd["player"]), ca_added)
		"crisis_oeuvre":
			var co_added: Array[Dictionary] = []
			CrisisNemesis.fund(state, int(cmd["player"]), String(cmd["res"]), co_added)
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
			if state.wars_on and String(cmd.get("cb", "")) != "":
				Wars.set_pending(state, int(cmd["player"]), int(cmd["target"]), String(cmd["cb"]), String(cmd.get("goal", "")))
			Combat.start_war(state, int(cmd["player"]), int(cmd["target"]))
		"requisition":
			Logistics.requisition(state, int(cmd["player"]), int(cmd["fleet"]))
		"ground_act":
			Ground.act(state, int(cmd["player"]), String(cmd["act"]), int(cmd.get("x", -1)), String(cmd.get("s", "")), String(cmd.get("s2", "")))
		"border_act":
			Borders.act(state, int(cmd["player"]), String(cmd["act"]), int(cmd.get("x", -1)), int(cmd.get("y", -1)), String(cmd.get("s", "")))
		"war_act":
			Wars.act(state, int(cmd["player"]), String(cmd["act"]), int(cmd.get("x", -1)), String(cmd.get("s", "")))
		"court_act":
			var ca_added: Array[Dictionary] = []
			Court.act(state, int(cmd["player"]), String(cmd["act"]), int(cmd.get("x", -1)), int(cmd.get("y", -1)), String(cmd.get("s", "")), ca_added)
		"ruler_act":
			var ra_added: Array[Dictionary] = []
			Rulers.act(state, int(cmd["player"]), String(cmd["act"]), int(cmd.get("x", -1)), String(cmd.get("s", "")), ra_added)
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
			Stealth.drop(state, f)  # débarquer fait tomber le voile
			if Ground.full(state):
				Ground.land(state, f)  # bataille au sol (voir Ground)
				return
			f.troops -= Combat.garrison(state, sid)  # les défenseurs se battent jusqu'au dernier
			if not WarPeace.invade(state, sid, f.owner):  # occupation (buts de guerre), sinon conquête
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
