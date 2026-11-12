class_name Diplomacy
extends RefCounted
## Règles de la diplomatie : statuts, traités, opinion, souvenirs, talents diplomatiques des peuples.
## Fonctions pures qui LISENT l'état, sauf celles qui l'écrivent explicitement (sign, cancel, remember,
## on_war_declared, add_war_score, les talents), appelées par les ordres et par DiplomacySystem.
## L'interface et l'IA s'en servent pour afficher et décider avec exactement les mêmes calculs.
##
## Inspiration (data/diplomacy.json, "_sources") : Endless Space 2 en référence principale
## (guerre froide par défaut, paix, alliance qui partage les guerres, échange de cartes, accord
## commercial, trêve forcée par un arbitre, verrous temporels), la confiance et la friction de frontière
## de Stellaris, les griefs qui s'effacent de Civilization VI, et le document de game design
## (opinion selon les registres, les credos et l'histoire commune).
##
## Statuts entre deux empires qui se sont rencontrés :
## - guerre froide (aucun traité) : pas de combat, chacun peut déclarer la guerre ;
## - guerre (Empire.wars, géré par Combat) ;
## - paix (traité) : aucune attaque ; une trêve d'un an suit la signature ;
## - alliance (traité, après six mois de paix) : les guerres et les cartes se partagent.
## L'accord commercial s'ajoute à la paix ou à l'alliance ; l'échange de cartes est ponctuel.
##
## Tout est déterministe : entiers, parcours dans l'ordre des identifiants, aucun aléatoire.

const COLD := ""
const PEACE := "peace"
const ALLIANCE := "alliance"
const TRADE := "trade"
const MAPS := "maps"
const TREATY_IDS: Array[String] = ["peace", "alliance", "trade", "maps"]


static func data() -> Dictionary:
	return GameData.diplomacy()


static func treaty_info(treaty: String) -> Dictionary:
	return data()["treaties"].get(treaty, {})


static func treaty_label(treaty: String) -> String:
	return String(treaty_info(treaty).get("label", treaty))


static func days(key: String, default := 0) -> int:
	return int(data().get(key, default))


# --- Relations ---------------------------------------------------------------------------------

static func key(a: int, b: int) -> String:
	return "%d-%d" % [mini(a, b), maxi(a, b)]


## Relation entre deux empires (lecture ; {} si rien n'a jamais été signé).
static func rel(state: GameState, a: int, b: int) -> Dictionary:
	return state.relations.get(key(a, b), {})


## Relation modifiable (créée au besoin).
static func _rel_w(state: GameState, a: int, b: int) -> Dictionary:
	var k := key(a, b)
	if not state.relations.has(k):
		state.relations[k] = {"key": k, "pact": COLD, "since": state.tick, "truce": 0, "trade": 0,
				"trust": 0, "score": [0, 0], "cool": {}}
	return state.relations[k]


## Traité principal : "" (guerre froide), "peace" ou "alliance".
static func pact(state: GameState, a: int, b: int) -> String:
	return String(rel(state, a, b).get("pact", COLD))


static func has_pact(state: GameState, a: int, b: int) -> bool:
	return pact(state, a, b) != COLD


static func allied(state: GameState, a: int, b: int) -> bool:
	return pact(state, a, b) == ALLIANCE


## Équipe commune de a et b (alliance verrouillée choisie à la création de la partie), 0 sinon.
static func team_of(state: GameState, a: int, b: int) -> int:
	return int(rel(state, a, b).get("team", 0))


## Équipe : alliance verrouillée dès le premier jour (sans trêve ni délai de paix).
static func form_team(state: GameState, a: int, b: int, team: int) -> void:
	var r := _rel_w(state, a, b)
	r["pact"] = ALLIANCE
	r["since"] = state.tick
	r["team"] = team


static func has_trade(state: GameState, a: int, b: int) -> bool:
	return int(rel(state, a, b).get("trade", 0)) != 0


static func in_truce(state: GameState, a: int, b: int) -> bool:
	return int(rel(state, a, b).get("truce", 0)) > state.tick


static func truce_left(state: GameState, a: int, b: int) -> int:
	return maxi(0, int(rel(state, a, b).get("truce", 0)) - state.tick)


## Jours depuis la signature du traité en vigueur (ou depuis le début de la guerre).
static func pact_days(state: GameState, a: int, b: int) -> int:
	return state.tick - int(rel(state, a, b).get("since", state.tick))


static func trust(state: GameState, a: int, b: int) -> int:
	return int(rel(state, a, b).get("trust", 0))


## Statut lisible : "none" (pas de contact), "war", "alliance", "peace", "cold".
static func status(state: GameState, a: int, b: int) -> String:
	var ea := state.get_empire(a)
	if ea == null or not ea.contacts.has(b):
		return "none"
	if Combat.at_war(state, a, b):
		return "war"
	var p := pact(state, a, b)
	return p if p != COLD else "cold"


static func status_label(st: String) -> String:
	return {"none": "Aucun contact", "war": "En guerre", "alliance": "Alliance", "peace": "Paix",
			"cold": "Guerre froide"}.get(st, st)


## Statut lisible de a envers b ; une alliance d'équipe s'écrit « Équipe N ».
static func status_text(state: GameState, a: int, b: int) -> String:
	var st := status(state, a, b)
	if st == ALLIANCE and team_of(state, a, b) > 0:
		return "Équipe %d" % team_of(state, a, b)
	return status_label(st)


## Alliés d'un empire (encore en jeu), triés.
static func allies(state: GameState, a: int) -> Array[int]:
	var out: Array[int] = []
	for e in state.empires:
		if e.id != a and not e.eliminated and allied(state, a, e.id):
			out.append(e.id)
	return out


## Score de guerre de a contre b : ce que a a gagné (vaisseaux détruits, systèmes pris) moins ce que b a gagné.
static func war_score(state: GameState, a: int, b: int) -> int:
	var s: Array = rel(state, a, b).get("score", [0, 0])
	var mine := int(s[0]) if a < b else int(s[1])
	var theirs := int(s[1]) if a < b else int(s[0])
	return mine - theirs


## Enregistre des points de guerre pour winner contre loser (s'ils sont en guerre).
static func add_war_score(state: GameState, winner: int, loser: int, points: int) -> void:
	if points <= 0 or GameState.is_npc(winner) or GameState.is_npc(loser) or not Combat.at_war(state, winner, loser):
		return
	var r := _rel_w(state, winner, loser)
	var s: Array = r["score"]
	var i := 0 if winner < loser else 1
	s[i] = int(s[i]) + points


## Système pris par la force : points de guerre et souvenir chez le vaincu.
static func note_conquest(state: GameState, conqueror: int, victim: int) -> void:
	if GameState.is_npc(conqueror) or GameState.is_npc(victim) or not Combat.at_war(state, conqueror, victim):
		return
	add_war_score(state, conqueror, victim, 20)
	remember(state, victim, conqueror, "conquest")


# --- Talents des peuples -----------------------------------------------------------------------
# Liés aux couches d'espèce (gouvernement, credo…), pas à une faction précise : une espèce de
# l'éditeur qui partage la combinaison les obtient aussi (voir FactionTraits.species_matches).

static func ability(name: String) -> Dictionary:
	return data()["abilities"].get(name, {})


static func has_ability_faction(faction: Dictionary, name: String) -> bool:
	var ab := ability(name)
	if ab.is_empty():
		return false
	return FactionTraits.species_matches(faction, ab.get("requires", {}))


static func has_ability(state: GameState, empire_id: int, name: String) -> bool:
	var e := state.get_empire(empire_id)
	return e != null and has_ability_faction(e.faction(), name)


## Talents diplomatiques d'une faction, pour l'interface : [{label, text}].
static func faction_abilities(faction: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for name in ["no_treaties", "heir", "mediation", "crusade"]:
		if has_ability_faction(faction, name):
			out.append({"id": name, "label": ability(name)["label"], "text": ability(name)["text"]})
	return out


## L'empire refuse tout traité (l'Essaim Kh'thari et toute ruche qui ne vit que pour survivre).
static func no_treaties(state: GameState, empire_id: int) -> bool:
	return has_ability(state, empire_id, "no_treaties")


static func _species(state: GameState, empire_id: int) -> Dictionary:
	return FactionTraits.species(state.get_empire(empire_id).faction())


# --- Opinion -----------------------------------------------------------------------------------

## Ce que l'empire a pense de l'empire b, détaillé : [{label, value}] (sans les lignes nulles).
static func opinion_parts(state: GameState, a: int, b: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cfg: Dictionary = data()["opinion"]
	var sa := _species(state, a)
	var sb := _species(state, b)
	# Choc des tons : dissonance entre registres (document de game design).
	var ra := String(sa.get("registre", ""))
	var rb := String(sb.get("registre", ""))
	var dis := int(cfg["registre_same"]) if ra == rb else _pair_value(cfg["registre_pairs"], ra, rb)
	_part(out, "Registres : %s / %s" % [ra, rb] if ra != rb else "Même registre", dis * int(cfg["registre_scale"]))
	var ca := String(sa.get("credo", ""))
	var cb := String(sb.get("credo", ""))
	if ca != "" and ca == cb:
		_part(out, "Même credo", int(cfg["credo_same"]))
	else:
		_part(out, "Credos opposés", _pair_value(cfg["credo_pairs"], ca, cb))
	var ga := String(sa.get("gouvernement", ""))
	var gb := String(sb.get("gouvernement", ""))
	if ga != "" and ga == gb:
		_part(out, "Même gouvernement", int(cfg["gouvernement_same"]))
	else:
		_part(out, "Gouvernements rivaux", _pair_value(cfg["gouvernement_pairs"], ga, gb))
	var arch := String(sb.get("archetype", ""))
	if arch != String(sa.get("archetype", "")):
		_part(out, "Horreur biologique" if arch == "ruche" else "Archétype", int(cfg["archetype_seen"].get(arch, 0)))
	for t in sa.get("traits", []):
		var to: Dictionary = cfg["traits_observer"].get(t, {})
		if to.is_empty():
			continue
		var v := int(to.get("all", 0))
		if to.has("other_credo") and ca != cb:
			v += int(to["other_credo"])
		_part(out, String(to.get("label", t)), v)
	# Frontières (friction de Stellaris, pression de frontière d'Endless Space 2).
	var touching := border_systems(state, a, b)
	_part(out, "Frontières communes (%d)" % touching, maxi(int(cfg["border_max"]), touching * int(cfg["border_per_system"])))
	# Statut et confiance.
	var st := status(state, a, b)
	if st == "war":
		_part(out, "En guerre", int(cfg["at_war"]))
	elif st == ALLIANCE or st == PEACE:
		_part(out, "Traité : %s" % treaty_label(st), int(cfg[st]))
	if has_trade(state, a, b):
		_part(out, "Accord commercial", int(cfg["trade"]))
	_part(out, "Confiance", trust(state, a, b))
	# Ambassades permanentes de b, et merveilles qui lui valent l'estime de tous (Assemblée interstellaire).
	_part(out, "Ambassades permanentes", Research.fx_int(state, b, "opinion_all"))
	var w := Economy.wonders(state)
	for key in w:
		if int(w[key]) == b:
			var bid := String(key).get_slice("#", 0)
			var op := int(GameData.building(bid).get("opinion", 0))
			if op != 0:
				_part(out, String(GameData.building(bid).get("label", bid)), op)
	var common := common_enemies(state, a, b)
	_part(out, "Ennemi commun", int(cfg["common_enemy"]) * mini(2, common.size()))
	# Menace : b approche d'une victoire que a peut voir (data/victories.json, threat_opinion).
	var best := Victory.best_cached(state, b)
	if String(best["id"]) != "" and Victory.visible_pct(state, a, b, String(best["id"])) >= 0:
		var malus := 0
		for step: Array in Victory.data().get("threat_opinion", []):
			if int(best["pct"]) >= int(step[0]):
				malus = int(step[1])
		_part(out, "Menace pour la galaxie : %s" % Victory.label(String(best["id"])), malus)
	# Histoire commune : les souvenirs qui ne sont pas encore effacés.
	for m in state.memories:
		if int(m["who"]) == a and int(m["about"]) == b:
			var md: Dictionary = data()["memories"].get(String(m["kind"]), {})
			_part(out, String(md.get("label", m["kind"])), memory_value(state, m))
	return out


static func _part(out: Array[Dictionary], label: String, value: int) -> void:
	if value != 0:
		out.append({"label": label, "value": value})


static func _pair_value(pairs: Array, x: String, y: String) -> int:
	for p: Array in pairs:
		if (String(p[0]) == x and String(p[1]) == y) or (String(p[0]) == y and String(p[1]) == x):
			return int(p[2])
	return 0


## Ce que le registre reg vaut d'opinion auprès de chaque registre (même registre compris), pour
## l'éditeur de peuples : [[registre, points], …] du plus aimé au plus détesté.
static func registre_opinions(reg: String) -> Array:
	var cfg: Dictionary = data()["opinion"]
	var out := []
	for b: Dictionary in Species.options("registre"):
		var other := String(b["id"])
		var dis := int(cfg["registre_same"]) if other == reg else _pair_value(cfg["registre_pairs"], reg, other)
		out.append([other, dis * int(cfg["registre_scale"])])
	out.sort_custom(func(x: Array, y: Array) -> bool: return int(x[1]) > int(y[1]) or (int(x[1]) == int(y[1]) and String(x[0]) < String(y[0])))
	return out


## Opinion de a sur b, de -100 à 100.
static func opinion(state: GameState, a: int, b: int) -> int:
	var n := 0
	for p in opinion_parts(state, a, b):
		n += int(p["value"])
	var cfg: Dictionary = data()["opinion"]
	return clampi(n, int(cfg["min"]), int(cfg["max"]))


static func opinion_label(value: int) -> String:
	for lv: Array in data()["opinion"]["levels"]:
		if value >= int(lv[0]):
			return String(lv[1])
	return "Hostile"


## Nombre de systèmes de a voisins (à un saut) d'un système de b.
static func border_systems(state: GameState, a: int, b: int) -> int:
	var n := 0
	for sid in EmpireReport.owned_systems(state, a):
		for nb in state.galaxy.systems[sid].neighbors:
			if state.system_owner(nb) == b:
				n += 1
				break
	return n


## Empires en guerre à la fois avec a et avec b.
static func common_enemies(state: GameState, a: int, b: int) -> Array[int]:
	var out: Array[int] = []
	var ea := state.get_empire(a)
	var eb := state.get_empire(b)
	for w in ea.wars:
		if eb.wars.has(w) and not state.get_empire(w).eliminated:
			out.append(w)
	return out


# --- Souvenirs ---------------------------------------------------------------------------------

## L'empire who se souvient d'un geste de about. Un souvenir du même genre se rafraîchit
## (et s'empile jusqu'à "stack" fois pour certains, comme les conquêtes).
static func remember(state: GameState, who: int, about: int, kind: String) -> void:
	if who == about or who < 0 or about < 0 or GameState.is_npc(who) or GameState.is_npc(about):
		return
	var md: Dictionary = data()["memories"].get(kind, {})
	if md.is_empty():
		return
	for m in state.memories:
		if int(m["who"]) == who and int(m["about"]) == about and String(m["kind"]) == kind:
			m["tick"] = state.tick
			m["count"] = mini(int(md.get("stack", 1)), int(m["count"]) + 1)
			return
	state.memories.append({"who": who, "about": about, "kind": kind, "tick": state.tick, "count": 1})


## Valeur actuelle d'un souvenir : il s'efface en ligne droite jusqu'à sa durée.
static func memory_value(state: GameState, m: Dictionary) -> int:
	var md: Dictionary = data()["memories"].get(String(m["kind"]), {})
	var d := maxi(1, int(md.get("days", 360)))
	var age := state.tick - int(m["tick"])
	if age >= d:
		return 0
	@warning_ignore("integer_division")
	return int(md.get("value", 0)) * int(m["count"]) * (d - age) / d


static func prune_memories(state: GameState) -> void:
	var kept: Array[Dictionary] = []
	for m in state.memories:
		if memory_value(state, m) != 0:
			kept.append(m)
	state.memories = kept


# --- Propositions et traités -------------------------------------------------------------------

static func pending(state: GameState, from: int, to: int, treaty: String) -> Dictionary:
	for p in state.proposals:
		if int(p["from"]) == from and int(p["to"]) == to and String(p["treaty"]) == treaty:
			return p
	return {}


static func proposal(state: GameState, id: int) -> Dictionary:
	for p in state.proposals:
		if int(p["id"]) == id:
			return p
	return {}


## Propositions reçues par un empire, des plus anciennes aux plus récentes.
static func proposals_for(state: GameState, to: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in state.proposals:
		if int(p["to"]) == to:
			out.append(p)
	return out


## Jours à attendre avant de reproposer ce traité à cet empire (0 = possible).
static func cooldown_left(state: GameState, from: int, to: int, treaty: String) -> int:
	var cool: Dictionary = rel(state, from, to).get("cool", {})
	return maxi(0, int(cool.get("%d:%s" % [from, treaty], 0)) - state.tick)


static func _set_cooldown(state: GameState, from: int, to: int, treaty: String, n_days: int) -> void:
	var r := _rel_w(state, from, to)
	r["cool"]["%d:%s" % [from, treaty]] = state.tick + n_days


## Le traité peut-il exister entre a et b aujourd'hui ? "" si oui, sinon la raison (sans tenir compte
## des propositions en attente ni des délais entre deux propositions).
static func check_terms(state: GameState, a: int, b: int, treaty: String) -> String:
	var ea := state.get_empire(a)
	var eb := state.get_empire(b)
	if ea == null or eb == null or a == b:
		return "empire inconnu"
	if ea.eliminated or eb.eliminated:
		return "cet empire a disparu"
	if not ea.contacts.has(b):
		return "vous n'avez jamais rencontré cet empire"
	if not TREATY_IDS.has(treaty):
		return "traité inconnu : %s" % treaty
	if no_treaties(state, a) or no_treaties(state, b):
		return "l'Essaim ne signe rien : il digère"
	var at_war := Combat.at_war(state, a, b)
	match treaty:
		PEACE:
			if has_pact(state, a, b):
				return "un traité est déjà en vigueur"
		ALLIANCE:
			if at_war:
				return "on ne s'allie pas avec un ennemi"
			if pact(state, a, b) == ALLIANCE:
				return "vous êtes déjà alliés"
			if Research.fx_int(state, a, "alliances") <= 0:
				return "il faut d'abord les Chancelleries (recherche, Société)"
			if Research.fx_int(state, b, "alliances") <= 0:
				return "%s n'a pas encore de chancelleries pour signer une alliance" % state.get_empire(b).short_name()
			if pact(state, a, b) != PEACE:
				return "il faut d'abord signer la paix"
			if pact_days(state, a, b) < days("alliance_after_days", 180):
				return "une alliance exige %d jours de paix (encore %d)" % [days("alliance_after_days", 180),
						days("alliance_after_days", 180) - pact_days(state, a, b)]
		TRADE:
			if not has_pact(state, a, b):
				return "un accord commercial exige la paix"
			if has_trade(state, a, b):
				return "un accord commercial est déjà en vigueur"
		MAPS:
			if at_war:
				return "on n'échange pas ses cartes avec un ennemi"
	return ""


static func check_propose(state: GameState, from: int, to: int, treaty: String) -> String:
	var why := check_terms(state, from, to, treaty)
	if why != "":
		return why
	if not pending(state, from, to, treaty).is_empty():
		return "proposition déjà envoyée"
	if not pending(state, to, from, treaty).is_empty():
		return "ils vous proposent déjà ce traité : répondez-leur"
	var left := cooldown_left(state, from, to, treaty)
	if left > 0:
		return "trop tôt pour reproposer (%d jours)" % left
	return ""


## Applique une proposition validée. Un empire IA répond tout de suite (AiDiplomacy.evaluate) ;
## un joueur humain la reçoit dans son écran Diplomatie et a proposal_days jours pour répondre.
## Renvoie true si le traité est signé.
static func propose(state: GameState, from: int, to: int, treaty: String) -> bool:
	var et := state.get_empire(to)
	var ef := state.get_empire(from)
	if et.is_ai():
		var ev := AiDiplomacy.evaluate(state, to, from, treaty)
		if int(ev["score"]) >= int(data()["ai"]["accept_at"]):
			sign_treaty(state, from, to, treaty)
			return true
		_set_cooldown(state, from, to, treaty, days("refusal_cooldown_days", 60) if not ef.is_ai() else days("ai_cooldown_days", 120))
		if not ef.is_ai():
			state.add_chronicle("%s décline %s proposé%s par %s. Le messager repart avec une réponse polie et un sourire qui l'est moins." % [
					et.display_name(), _treaty_phrase(treaty), "e" if treaty != MAPS and treaty != PEACE else "", ef.display_name()], Espionage.private_to(state, [from, to]))
		return false
	state.proposals.append({"id": state.next_proposal_id, "from": from, "to": to, "treaty": treaty, "tick": state.tick})
	state.next_proposal_id += 1
	_set_cooldown(state, from, to, treaty, days("proposal_days", 30))
	state.add_chronicle("%s propose %s à %s. Les chancelleries retiennent leur souffle." % [
			ef.display_name(), String(treaty_info(treaty).get("verb", treaty)), et.display_name()], Espionage.private_to(state, [from, to]))
	return false


static func _treaty_phrase(treaty: String) -> String:
	return {"peace": "la paix", "alliance": "l'alliance", "trade": "l'accord commercial", "maps": "l'échange de cartes", "contract": "le contrat de flotte"}.get(treaty, treaty)


static func check_answer(state: GameState, player: int, proposal_id: int, accept: bool) -> String:
	var p := proposal(state, proposal_id)
	if p.is_empty():
		return "proposition inconnue ou expirée"
	if int(p["to"]) != player:
		return "cette proposition ne vous est pas adressée"
	if accept:
		if String(p["treaty"]) == CONTRACT:
			return check_contract(state, int(p["merc"]), int(p["client"]), int(p["target"]))
		return check_terms(state, player, int(p["from"]), String(p["treaty"]))
	return ""


static func answer(state: GameState, proposal_id: int, accept: bool) -> void:
	var p := proposal(state, proposal_id)
	state.proposals.erase(p)
	var from := int(p["from"])
	var to := int(p["to"])
	if accept and String(p["treaty"]) == CONTRACT:
		sign_contract(state, int(p["merc"]), int(p["client"]), int(p["target"]))
	elif accept:
		sign_treaty(state, from, to, String(p["treaty"]))
	else:
		_set_cooldown(state, from, to, String(p["treaty"]), days("ai_cooldown_days", 120))
		state.add_chronicle("%s repousse %s offert%s par %s." % [state.get_empire(to).display_name(),
				_treaty_phrase(String(p["treaty"])), "" if String(p["treaty"]) == MAPS or String(p["treaty"]) == PEACE else "e",
				state.get_empire(from).display_name()], Espionage.private_to(state, [from, to]))


## Signe un traité (conditions déjà vérifiées).
static func sign_treaty(state: GameState, a: int, b: int, treaty: String) -> void:
	var ea := state.get_empire(a)
	var eb := state.get_empire(b)
	_drop_proposals(state, a, b, treaty)
	Heroes.act(state, a, "treaty")
	Heroes.act(state, b, "treaty")
	match treaty:
		PEACE:
			var was_war := Combat.at_war(state, a, b)
			if was_war:
				end_war(state, a, b)
			var r := _rel_w(state, a, b)
			r["pact"] = PEACE
			r["since"] = state.tick
			r["truce"] = state.tick + days("truce_days", 360)
			r["score"] = [0, 0]
			remember(state, a, b, "peace_signed")
			remember(state, b, a, "peace_signed")
			Heroes.release_between(state, a, b)
			if was_war:
				state.add_chronicle("Paix entre %s et %s. On signe en bas, on enterre les morts, et l'on jure que c'était la dernière fois." % [
						ea.display_name(), eb.display_name()], Espionage.public_to(state, [a, b]))
			else:
				state.add_chronicle("%s et %s signent un traité de paix. Les frontières restent, les canons se taisent." % [
						ea.display_name(), eb.display_name()], Espionage.public_to(state, [a, b]))
		ALLIANCE:
			var r := _rel_w(state, a, b)
			r["pact"] = ALLIANCE
			r["since"] = state.tick
			share_maps(state, a, b)
			state.add_chronicle("Alliance entre %s et %s : désormais, qui frappe l'un devra compter avec l'autre." % [
					ea.display_name(), eb.display_name()], Espionage.public_to(state, [a, b]))
		TRADE:
			_rel_w(state, a, b)["trade"] = 1
			state.add_chronicle("Accord commercial entre %s et %s. Les cargos partent pleins, les douaniers reviennent riches." % [
					ea.display_name(), eb.display_name()], Espionage.public_to(state, [a, b]))
		MAPS:
			share_maps(state, a, b)
			_set_cooldown(state, a, b, MAPS, days("maps_cooldown_days", 720))
			_set_cooldown(state, b, a, MAPS, days("maps_cooldown_days", 720))
			state.add_chronicle("%s et %s échangent leurs cartes. Chacun découvre que l'autre dessine très mal les comètes." % [
					ea.display_name(), eb.display_name()], Espionage.private_to(state, [a, b]))


static func _drop_proposals(state: GameState, a: int, b: int, treaty: String) -> void:
	var kept: Array[Dictionary] = []
	for p in state.proposals:
		var pair := (int(p["from"]) == a and int(p["to"]) == b) or (int(p["from"]) == b and int(p["to"]) == a)
		if not (pair and String(p["treaty"]) == treaty):
			kept.append(p)
	state.proposals = kept


## Chacun reçoit les systèmes explorés par l'autre, et ses relevés plus récents (voir Intel).
static func share_maps(state: GameState, a: int, b: int) -> void:
	var ea := state.get_empire(a)
	var eb := state.get_empire(b)
	for sid in ea.explored:
		eb.explored[sid] = true
	for sid in eb.explored:
		ea.explored[sid] = true
	Intel.share(ea, eb)


## Fin d'une guerre (par la paix) : plus aucune hostilité, les sièges se lèveront d'eux-mêmes.
static func end_war(state: GameState, a: int, b: int) -> void:
	state.get_empire(a).wars.erase(b)
	state.get_empire(b).wars.erase(a)
	Stability.on_peace(state, a, b)
	var kept: Array[Dictionary] = []
	for p in state.proposals:
		var pair := (int(p["from"]) == a and int(p["to"]) == b) or (int(p["from"]) == b and int(p["to"]) == a)
		if not pair:
			kept.append(p)
	state.proposals = kept


## Rompre un traité : "alliance" (retour à la guerre froide, comme dans Endless Space 2), "peace"
## (dénonciation, seulement après la trêve) ou "trade".
static func check_cancel(state: GameState, player: int, target: int, treaty: String) -> String:
	var e := state.get_empire(player)
	if e == null or state.get_empire(target) == null or player == target:
		return "empire inconnu"
	match treaty:
		ALLIANCE:
			if not allied(state, player, target):
				return "aucune alliance avec cet empire"
			if team_of(state, player, target) > 0:
				return "alliance d'équipe : elle dure toute la partie"
		PEACE:
			if pact(state, player, target) != PEACE:
				return "aucun traité de paix avec cet empire"
			if in_truce(state, player, target):
				return "la trêve court encore %d jours" % truce_left(state, player, target)
		TRADE:
			if not has_trade(state, player, target):
				return "aucun accord commercial avec cet empire"
		_:
			return "traité inconnu : %s" % treaty
	return ""


static func cancel(state: GameState, player: int, target: int, treaty: String) -> void:
	var r := _rel_w(state, player, target)
	var ep := state.get_empire(player)
	var et := state.get_empire(target)
	match treaty:
		ALLIANCE:
			r["pact"] = COLD
			r["trade"] = 0
			r["since"] = state.tick
			remember(state, target, player, "left_alliance")
			state.add_chronicle("%s quitte son alliance avec %s. On se serre encore la main, mais avec des gants." % [
					ep.display_name(), et.display_name()], Espionage.public_to(state, [player, target]))
		PEACE:
			r["pact"] = COLD
			r["trade"] = 0
			r["since"] = state.tick
			remember(state, target, player, "denounced")
			state.add_chronicle("%s dénonce son traité de paix avec %s. Rien n'est encore tiré, mais les tourelles pivotent." % [
					ep.display_name(), et.display_name()], Espionage.public_to(state, [player, target]))
		TRADE:
			r["trade"] = 0
			state.add_chronicle("%s met fin à son accord commercial avec %s. Les cargos rentrent à vide." % [
					ep.display_name(), et.display_name()], Espionage.public_to(state, [player, target]))


## Influence, énergie… versées chaque mois par les traités en vigueur (comptées dans Economy.empire_income).
static func treaty_income(state: GameState, empire_id: int) -> Dictionary:
	var out := {}
	var e := state.get_empire(empire_id)
	if e == null:
		return out
	for other in e.contacts:
		var p := pact(state, empire_id, other)
		var o := state.get_empire(other)
		if o == null or o.eliminated:
			continue
		if p != COLD:
			_add(out, treaty_info(p).get("income", {}))
		if has_trade(state, empire_id, other):
			# Compagnies marchandes : chaque accord commercial rapporte plus.
			_add(out, Research.scaled_amounts(treaty_info(TRADE).get("income", {}), Research.fx_int(state, empire_id, "trade_income_pct")))
	# Contrats de flotte : le client paie, le mercenaire encaisse.
	var c := contract_of(state, empire_id)
	if not c.is_empty():
		_add(out, c["fee"])
	for cc in contracts_of_client(state, empire_id):
		for r in cc["fee"]:
			out[r] = int(out.get(r, 0)) - int(cc["fee"][r])
	return out


static func _add(into: Dictionary, amounts: Dictionary) -> void:
	for r in amounts:
		into[r] = int(into.get(r, 0)) + int(amounts[r])


# --- Guerre ------------------------------------------------------------------------------------

## Ce qui s'ajoute à Combat.check_declare_war : trêve, alliance.
static func check_war(state: GameState, a: int, b: int) -> String:
	if in_truce(state, a, b):
		return "une trêve court encore %d jours" % truce_left(state, a, b)
	if team_of(state, a, b) > 0:
		return "même équipe : vous êtes alliés toute la partie"
	if allied(state, a, b):
		return "quittez d'abord l'alliance"
	return ""


## Conséquences d'une déclaration de guerre (appelé par Combat.start_war, après l'avoir enregistrée) :
## rupture du traité (parjure), griefs, croisade, et entrée en guerre des alliés des deux camps.
## joined : l'empire a entre en guerre aux côtés d'un allié (pas d'appel en chaîne).
static func on_war_declared(state: GameState, a: int, b: int, by_nature: bool, joined := false) -> void:
	var r := _rel_w(state, a, b)
	var broke := String(r["pact"]) != COLD
	r["pact"] = COLD
	r["trade"] = 0
	r["since"] = state.tick
	r["trust"] = 0
	r["score"] = [0, 0]
	_drop_all_proposals(state, a, b)
	if by_nature:
		return
	remember(state, b, a, "declared_war")
	if broke and Espionage.has_grief(state, a, b):
		# Grief : l'autre a été pris à espionner, la rupture n'est pas un parjure.
		state.add_chronicle("%s rompt son traité avec %s, et brandit le dossier de ses espions démasqués. Les juristes, pour une fois, approuvent." % [
				state.get_empire(a).display_name(), state.get_empire(b).display_name()], Espionage.public_to(state, [a, b]))
	elif broke:
		remember(state, b, a, "broke_treaty")
		for e in state.empires:
			if e.id != a and e.id != b and not e.eliminated and e.contacts.has(a):
				remember(state, e.id, a, "oathbreaker")
		state.add_chronicle("%s rompt son traité avec %s. Les juristes parlent de parjure, les amiraux d'occasion." % [
				state.get_empire(a).display_name(), state.get_empire(b).display_name()], Espionage.public_to(state, [a, b]))
	var cr := ability("crusade")
	var ea := state.get_empire(a)
	if has_ability(state, a, "crusade") and FactionTraits.has_fervor(ea.faction()) \
			and String(_species(state, a).get("credo", "")) != String(_species(state, b).get("credo", "")):
		ea.fervor = mini(int(ea.faction()["fervor"]["max"]), ea.fervor + int(cr.get("war_fervor", 0)))
	if joined:
		return
	# Les alliés partagent les guerres (Endless Space 2) : ceux de la cible défendent, ceux de
	# l'agresseur suivent. Un allié lié par un traité avec l'autre camp reste en dehors.
	for side in [[b, a], [a, b]]:
		var friend := int(side[0])
		var foe := int(side[1])
		for ally in allies(state, friend):
			if ally == foe or Combat.at_war(state, ally, foe):
				continue
			var ae := state.get_empire(ally)
			if not ae.contacts.has(foe) or has_pact(state, ally, foe):
				if has_pact(state, ally, foe):
					state.add_chronicle("%s, alliée de %s, reste en dehors : elle a signé avec %s." % [
							ae.display_name(), state.get_empire(friend).display_name(), state.get_empire(foe).display_name()], Espionage.public_to(state, [ally, friend, foe]))
				continue
			Combat.start_war(state, ally, foe, false, true)
			remember(state, friend, ally, "ally_joined")
			state.add_chronicle("%s honore son alliance et entre en guerre contre %s aux côtés de %s." % [
					ae.display_name(), state.get_empire(foe).display_name(), state.get_empire(friend).display_name()], Espionage.public_to(state, [ally, foe, friend]))


## Un allié pris à espionner : l'alliance est rompue, avec le souvenir d'un traité rompu.
static func break_alliance_for_spying(state: GameState, victim: int, spy: int) -> void:
	var r := _rel_w(state, victim, spy)
	r["pact"] = COLD
	r["trade"] = 0
	r["since"] = state.tick
	remember(state, victim, spy, "broke_treaty")
	state.add_chronicle("%s rompt son alliance avec %s : on n'espionne pas ses amis, ou alors on ne se fait pas prendre." % [
			state.get_empire(victim).display_name(), state.get_empire(spy).display_name()], Espionage.public_to(state, [victim, spy]))


static func _drop_all_proposals(state: GameState, a: int, b: int) -> void:
	var kept: Array[Dictionary] = []
	for p in state.proposals:
		var pair := (int(p["from"]) == a and int(p["to"]) == b) or (int(p["from"]) == b and int(p["to"]) == a)
		if not pair or String(p["treaty"]) == PEACE:
			kept.append(p)
	state.proposals = kept


# --- Talent : l'héritier (dynasties féodales, Lignées d'Ossarane) ------------------------------

static func has_heir(state: GameState, empire_id: int) -> bool:
	var e := state.get_empire(empire_id)
	return e != null and e.heir_loyalty >= 0 and has_ability(state, empire_id, "heir")


## Variation mensuelle de la loyauté de l'héritier, détaillée : [{label, value}].
static func heir_trend(state: GameState, empire_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var e := state.get_empire(empire_id)
	var h := ability("heir")
	if e.heir_loyalty < int(h["rest"]):
		_part(out, "Le temps apaise", int(h["regen"]))
	if e.dissent:
		_part(out, "Dissidence des fiefs", int(h["dissent"]))
	_part(out, "Guerres en cours (%d)" % e.wars.size(), int(h["per_war"]) * e.wars.size())
	if e.wars.is_empty():
		var pacts := 0
		for o in e.contacts:
			if has_pact(state, empire_id, o):
				pacts += 1
		_part(out, "Traités en vigueur", mini(2, pacts) * int(h["treaty_bonus"]))
	return out


static func check_bribe(state: GameState, player: int, target: int) -> String:
	var e := state.get_empire(player)
	var t := state.get_empire(target)
	if e == null or t == null or player == target:
		return "empire inconnu"
	if e.eliminated or t.eliminated:
		return "cet empire a disparu"
	if not e.contacts.has(target):
		return "vous n'avez jamais rencontré cet empire"
	if not has_heir(state, target):
		return "cet empire n'a pas d'héritier à acheter"
	if no_treaties(state, player):
		return "l'Essaim n'achète personne : il mange"
	if allied(state, player, target):
		return "on ne trahit pas un allié (pas comme ça)"
	if not Economy.can_afford(e, ability("heir")["bribe_cost"]):
		return "pas assez d'influence (%s)" % GameData.format_amounts(ability("heir")["bribe_cost"])
	return ""


static func bribe(state: GameState, player: int, target: int) -> void:
	var h := ability("heir")
	var e := state.get_empire(player)
	var t := state.get_empire(target)
	Economy.pay(e, h["bribe_cost"])
	t.heir_loyalty = maxi(0, t.heir_loyalty - int(h["bribe_loss"]))
	t.heir_suitor = player
	remember(state, target, player, "bribed_heir")
	state.add_chronicle("Des émissaires de %s glissent une bourse à l'héritier de %s. Il jure qu'il ne l'a pas ouverte ; elle est pourtant vide." % [
			e.display_name(), t.display_name()], Espionage.private_to(state, [player, target]))


static func check_banquet(state: GameState, player: int) -> String:
	var e := state.get_empire(player)
	if e == null or e.eliminated:
		return "empire inconnu"
	if not has_heir(state, player):
		return "votre empire n'a pas d'héritier"
	if e.heir_loyalty >= 100:
		return "l'héritier est déjà d'une loyauté sans faille"
	if not Economy.can_afford(e, ability("heir")["banquet_cost"]):
		return "pas assez de ressources (%s)" % GameData.format_amounts(ability("heir")["banquet_cost"])
	return ""


static func banquet(state: GameState, player: int) -> void:
	var h := ability("heir")
	var e := state.get_empire(player)
	Economy.pay(e, h["banquet_cost"])
	e.heir_loyalty = mini(100, e.heir_loyalty + int(h["banquet_gain"]))
	state.add_chronicle("Banquet des lignées chez %s : l'héritier reçoit une coupe de cristal chantant et la place d'honneur. Il sourit. Pour l'instant." % e.display_name(), Espionage.private_to(state, [player]))


## Bilan mensuel de l'héritier : loyauté, puis trahison si elle tombe à zéro. Renvoie la chronique.
static func heir_month(state: GameState, empire_id: int) -> void:
	if not has_heir(state, empire_id):
		return
	var e := state.get_empire(empire_id)
	var delta := 0
	for p in heir_trend(state, empire_id):
		delta += int(p["value"])
	e.heir_loyalty = clampi(e.heir_loyalty + delta, 0, 100)
	if e.heir_loyalty > 0:
		return
	_betrayal(state, empire_id)


## Le fief que l'héritier livrerait : la colonie (hors système capital) la plus éloignée de la capitale.
static func heir_fief(state: GameState, empire_id: int) -> int:
	var e := state.get_empire(empire_id)
	if e.capital_planet < 0:
		return -1
	var cap := state.galaxy.get_planet(e.capital_planet).system_id
	var dist := FactionTraits.jumps_from(state.galaxy, cap)
	var best := -1
	var best_d := -1
	for sid in EmpireReport.owned_systems(state, empire_id):
		if sid == cap:
			continue
		var d := int(dist.get(sid, 0))
		if d > best_d:
			best_d = d
			best = sid
	return best


## Qui recevrait le fief : celui qui a acheté l'héritier, sinon un ennemi (le premier), sinon personne.
static func heir_recipient(state: GameState, empire_id: int) -> int:
	var e := state.get_empire(empire_id)
	var s := state.get_empire(e.heir_suitor)
	if s != null and not s.eliminated and s.contacts.has(empire_id):
		return s.id
	for w in e.wars:
		if not state.get_empire(w).eliminated:
			return w
	return -1


static func _betrayal(state: GameState, empire_id: int) -> void:
	var e := state.get_empire(empire_id)
	var h := ability("heir")
	var fief := heir_fief(state, empire_id)
	var to := heir_recipient(state, empire_id)
	e.heir_loyalty = int(h["after_betrayal"])
	e.heir_suitor = -1
	if fief < 0 or to < 0:
		var inf := int(e.resources.get("influence", 0))
		@warning_ignore("integer_division")
		e.resources["influence"] = inf - maxi(0, inf / 2)
		state.add_chronicle("L'héritier de %s s'enfuit sans prévenir, avec la moitié du trésor d'influence et le meilleur navigateur. Un cousin éloigné prend sa place, ravi." % e.display_name(), Espionage.private_to(state, [e.id]))
		return
	var sname := state.galaxy.systems[fief].system_name
	state.add_chronicle("Trahison chez %s ! L'héritier livre le fief de %s à %s, avec les clés, la garnison et le blason retourné." % [
			e.display_name(), sname, state.get_empire(to).display_name()], Espionage.public_to(state, [e.id, to]))
	remember(state, to, empire_id, "heir_gift")
	var at_war := Combat.at_war(state, empire_id, to)
	Combat.capture_system(state, fief, to)
	if not at_war:
		state.garrisons.erase(fief)  # un fief livré n'a pas été assiégé : sa garnison est entière


# --- Talent : l'arbitrage (républiques, Concorde de Vael) --------------------------------------

static func check_mediate(state: GameState, player: int, a: int, b: int) -> String:
	var e := state.get_empire(player)
	if e == null or state.get_empire(a) == null or state.get_empire(b) == null:
		return "empire inconnu"
	if not has_ability(state, player, "mediation"):
		return "seule une république peut arbitrer une guerre"
	if a == b or a == player or b == player:
		return "on n'arbitre que la guerre des autres"
	if not e.contacts.has(a) or not e.contacts.has(b):
		return "il faut connaître les deux camps"
	if not Combat.at_war(state, a, b):
		return "ces deux empires ne sont pas en guerre"
	if no_treaties(state, a) or no_treaties(state, b):
		return "l'Essaim n'écoute pas les arbitres"
	if Combat.at_war(state, player, a) or Combat.at_war(state, player, b):
		return "un belligérant ne peut pas arbitrer"
	var mab := ability("mediation")
	var left := e.mediation_tick + int(mab["cooldown_days"]) - state.tick
	if left > 0:
		return "les Veilleurs se reposent encore %d jours" % left
	if pact_days(state, a, b) < days("min_war_days", 60):
		return "la guerre vient de commencer : laissez-les se fatiguer"
	if opinion(state, a, player) < 0 or opinion(state, b, player) < 0:
		return "les deux camps doivent vous respecter (opinion positive)"
	if not Economy.can_afford(e, mab["cost"]):
		return "pas assez d'influence (%s)" % GameData.format_amounts(mab["cost"])
	return ""


static func mediate(state: GameState, player: int, a: int, b: int) -> void:
	var e := state.get_empire(player)
	Economy.pay(e, ability("mediation")["cost"])
	e.mediation_tick = state.tick
	state.add_chronicle("Les Veilleurs du Seuil de %s descendent entre les flottes de %s et de %s. Personne n'ose tirer à travers une robe de cérémonie." % [
			e.display_name(), state.get_empire(a).display_name(), state.get_empire(b).display_name()], Espionage.public_to(state, [player, a, b]))
	sign_treaty(state, a, b, PEACE)
	remember(state, a, player, "mediated")
	remember(state, b, player, "mediated")


# --- Talent : flottes à louer (syndicats, Syndicat Brisecomète) -------------------------------
## Contrat : rangé dans la relation mercenaire-client, {"merc", "client", "target", "fee", "since", "until"}.
## Inspiration : les enclaves de mercenaires de Stellaris (une flotte louée à qui peut payer, pour un
## temps donné) ; le prix suit la flotte louée, fixé à la signature.

const CONTRACT := "contract"


## Contrat en cours où empire_id est le mercenaire ({} sinon).
static func contract_of(state: GameState, merc: int) -> Dictionary:
	var keys := state.relations.keys()
	keys.sort()
	for k in keys:
		var c: Dictionary = state.relations[k].get("contract", {})
		if not c.is_empty() and int(c["merc"]) == merc:
			return c
	return {}


## Contrats où empire_id est le client.
static func contracts_of_client(state: GameState, client: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var keys := state.relations.keys()
	keys.sort()
	for k in keys:
		var c: Dictionary = state.relations[k].get("contract", {})
		if not c.is_empty() and int(c["client"]) == client:
			out.append(c)
	return out


## Vaisseaux armés d'un empire.
static func warships(state: GameState, empire_id: int) -> int:
	var n := 0
	for f in Fleets.empire_fleets(state, empire_id):
		for sid in f.ships:
			if Combat.is_armed_ship(sid):
				n += 1
	return n


## Prix mensuel d'un contrat avec ce mercenaire, aujourd'hui.
static func contract_fee(state: GameState, merc: int) -> Dictionary:
	var ab := ability("mercenary")
	var fee := int(ab["fee_base"]) + int(ab["fee_per_ship"]) * warships(state, merc)
	@warning_ignore("integer_division")
	return {"energy": fee * (100 + Reputation.fee_pct(state, merc)) / 100}


## Le contrat merc -> client contre target est-il possible ? "" si oui.
static func check_contract(state: GameState, merc: int, client: int, target: int) -> String:
	var em := state.get_empire(merc)
	var ec := state.get_empire(client)
	var et := state.get_empire(target)
	if em == null or ec == null or et == null or merc == client or merc == target or client == target:
		return "empire inconnu"
	if em.eliminated or ec.eliminated or et.eliminated:
		return "cet empire a disparu"
	if not has_ability(state, merc, "mercenary"):
		return "seul un syndicat loue ses flottes"
	if not em.contacts.has(client) or not em.contacts.has(target):
		return "les mercenaires doivent connaître le client et sa cible"
	if no_treaties(state, client):
		return "l'Essaim ne signe rien : il digère"
	if not Combat.at_war(state, client, target):
		return "%s n'est pas en guerre contre %s" % [ec.short_name(), et.short_name()]
	if Combat.at_war(state, merc, client):
		return "on ne loue pas ses flottes à un ennemi"
	if Combat.at_war(state, merc, target):
		return "déjà en guerre contre %s" % et.short_name()
	if has_pact(state, merc, target) or in_truce(state, merc, target):
		return "un traité ou une trêve lie les mercenaires à %s" % et.short_name()
	if not contract_of(state, merc).is_empty():
		return "les flottes sont déjà louées"
	if warships(state, merc) < int(ability("mercenary")["min_warships"]):
		return "il faut au moins %d vaisseaux armés à louer" % int(ability("mercenary")["min_warships"])
	var left := int(rel(state, merc, client).get("contract_cool", 0)) - state.tick
	if left > 0:
		return "les mercenaires rentrent à peine (%d jours)" % left
	return ""


## Signe le contrat (conditions vérifiées) : les mercenaires entrent en guerre contre la cible.
static func sign_contract(state: GameState, merc: int, client: int, target: int) -> void:
	var r := _rel_w(state, merc, client)
	r["contract"] = {"merc": merc, "client": client, "target": target, "fee": contract_fee(state, merc),
			"since": state.tick, "until": state.tick + int(ability("mercenary")["max_days"])}
	_drop_contract_proposals(state, merc, client)
	state.add_chronicle("%s loue ses flottes à %s contre %s, pour %s par mois. Les canons sont neutres ; les factures, beaucoup moins." % [
			state.get_empire(merc).display_name(), state.get_empire(client).display_name(),
			state.get_empire(target).display_name(), GameData.format_amounts(r["contract"]["fee"])], Espionage.public_to(state, [merc, client, target]))
	Combat.start_war(state, merc, target, false, true)


## Fin d'un contrat. reason : "done" (guerre finie ou terme), "unpaid" (le client ne paie plus),
## "broken" (les mercenaires ont signé avec la cible ou attaqué leur client), "gone" (un empire a disparu).
static func end_contract(state: GameState, merc: int, reason: String) -> void:
	var c := contract_of(state, merc)
	if c.is_empty():
		return
	var client := int(c["client"])
	var target := int(c["target"])
	var r := _rel_w(state, merc, client)
	r.erase("contract")
	r["contract_cool"] = state.tick + int(ability("mercenary")["cooldown_days"])
	var em := state.get_empire(merc)
	var ec := state.get_empire(client)
	match reason:
		"unpaid":
			remember(state, merc, client, "contract_unpaid")
			state.add_chronicle("%s ne paie plus : les flottes de %s font demi-tour en envoyant la facture." % [ec.display_name(), em.display_name()], Espionage.public_to(state, [merc, client]))
		"broken":
			state.add_chronicle("%s abandonne le contrat de %s avant la fin de sa guerre." % [em.display_name(), ec.display_name()], Espionage.public_to(state, [merc, client]))
		"done":
			remember(state, client, merc, "contract_honored")
			Reputation.gain(state, merc, "contract_done")
			Reputation.exploit(state, merc, "contrat")
			state.add_chronicle("Fin du contrat entre %s et %s. Les mercenaires repartent, payés et presque polis." % [em.display_name(), ec.display_name()], Espionage.public_to(state, [merc, client]))
	# Les mercenaires rentrent : la paix avec leur ancienne cible, sans rancune de métier.
	if reason != "gone" and Combat.at_war(state, merc, target) and not state.get_empire(target).eliminated \
			and not no_treaties(state, target) and not em.eliminated:
		sign_treaty(state, merc, target, PEACE)


## Bilan mensuel d'un contrat (le paiement passe par treaty_income) : le contrat prend fin quand la
## guerre du client est finie, à son terme, si un empire a disparu, si le client n'a plus d'énergie,
## ou si les mercenaires ont fait la paix avec la cible.
static func contract_month(state: GameState, merc: int) -> void:
	var c := contract_of(state, merc)
	if c.is_empty():
		return
	var em := state.get_empire(merc)
	var ec := state.get_empire(int(c["client"]))
	var et := state.get_empire(int(c["target"]))
	if em.eliminated or ec.eliminated:
		end_contract(state, merc, "gone")
	elif Combat.at_war(state, merc, ec.id):
		end_contract(state, merc, "broken")
	elif int(ec.resources.get("energy", 0)) < 0:
		end_contract(state, merc, "unpaid")
	elif et.eliminated or not Combat.at_war(state, ec.id, et.id) or state.tick >= int(c["until"]):
		end_contract(state, merc, "done")
	elif not Combat.at_war(state, merc, et.id):
		end_contract(state, merc, "broken")


## Propositions de contrat : {"treaty": "contract", "from", "to", "merc", "client", "target"}.
static func propose_contract(state: GameState, player: int, merc: int, client: int, target: int) -> bool:
	var other := client if player == merc else merc
	var eo := state.get_empire(other)
	if eo.is_ai():
		var ev := AiDiplomacy.evaluate_contract(state, other, merc, client, target)
		if int(ev["score"]) >= int(data()["ai"]["accept_at"]):
			sign_contract(state, merc, client, target)
			return true
		_set_cooldown(state, player, other, CONTRACT, days("refusal_cooldown_days", 60))
		state.add_chronicle("%s décline le contrat de flotte contre %s." % [eo.display_name(), state.get_empire(target).display_name()], Espionage.private_to(state, [player, other]))
		return false
	state.proposals.append({"id": state.next_proposal_id, "from": player, "to": other, "treaty": CONTRACT,
			"merc": merc, "client": client, "target": target, "tick": state.tick})
	state.next_proposal_id += 1
	_set_cooldown(state, player, other, CONTRACT, days("proposal_days", 30))
	state.add_chronicle("%s propose un contrat de flotte à %s, contre %s." % [
			state.get_empire(player).display_name(), eo.display_name(), state.get_empire(target).display_name()], Espionage.private_to(state, [player, other]))
	return false


static func check_propose_contract(state: GameState, player: int, merc: int, client: int, target: int) -> String:
	if player != merc and player != client:
		return "un contrat se signe entre le syndicat et son client"
	var why := check_contract(state, merc, client, target)
	if why != "":
		return why
	var other := client if player == merc else merc
	for p in state.proposals:
		if String(p["treaty"]) == CONTRACT and ((int(p["from"]) == player and int(p["to"]) == other) or (int(p["from"]) == other and int(p["to"]) == player)):
			return "un contrat est déjà proposé"
	var left := cooldown_left(state, player, other, CONTRACT)
	if left > 0:
		return "trop tôt pour reproposer (%d jours)" % left
	return ""


static func _drop_contract_proposals(state: GameState, a: int, b: int) -> void:
	_drop_proposals(state, a, b, CONTRACT)


# --- Bilan mensuel -----------------------------------------------------------------------------

## Effet mensuel de la croisade : chaque traité de paix avec un autre credo coûte de la ferveur.
static func crusade_month(state: GameState, empire_id: int) -> void:
	var e := state.get_empire(empire_id)
	if not has_ability(state, empire_id, "crusade") or not FactionTraits.has_fervor(e.faction()):
		return
	var n := 0
	var credo := String(_species(state, empire_id).get("credo", ""))
	for o in e.contacts:
		var oe := state.get_empire(o)
		if oe != null and not oe.eliminated and has_pact(state, empire_id, o) and String(_species(state, o).get("credo", "")) != credo:
			n += 1
	if n > 0:
		e.fervor = maxi(0, e.fervor + n * int(ability("crusade").get("treaty_fervor", 0)))
