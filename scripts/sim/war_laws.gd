class_name WarLaws
extends RefCounted
## Buts de guerre et traités de paix, lot 3 : avant-guerre, lois de la guerre et ponts (propositions 19 à 29).
##
## - Ultimatums (prop. 19) : exiger un système revendiqué, un tribut ou une rupture d'alliance. Céder évite
##   la guerre (souvenir d'humiliation) ; refuser donne le motif « Ultimatum refusé » à l'exigeant.
## - Crise diplomatique (prop. 20) : 30 jours d'escalade avant la guerre ; chaque camp rallie des tiers ;
##   un camp peut reculer (le défenseur cède le but, l'agresseur abandonne ses revendications).
## - Préavis (prop. 21) : une IA masse ses flottes avant de déclarer ; les espions (ou la Prévision) le voient.
## - Kanly (prop. 22) et Droit de la guerre au Nomos (prop. 23) : guerres limitées, crimes de guerre.
## - Talents de peuple (prop. 24), Arbitre (prop. 25), sécession du Koinon (prop. 26), opérations
##   d'espionnage (prop. 27), courants politiques et guerres saintes (prop. 28), héros (prop. 29).
##
## state.wars (en plus du lot 1) : "ult": {"a>b": échéance du motif}, "inc": {"a>b": échéance du motif
## Incident}, "crises": {"a-b": crise}, "prep": {"<empire>": {"b", "t", "seen": [observateurs]}},
## "retain": {"<empire>": échéance} (retenu dans son Koinon).
## crise = {"a", "d", "t", "end", "cb", "g", "ra": [ralliés de a], "rd": [ralliés de d]}

const KINDS: Array[String] = ["wult", "wrally"]
const SPY_OPS: Array[String] = ["fabriquer_revendication", "provoquer_incident"]
const STORES: Array[String] = ["ult", "inc", "crises", "prep", "retain"]

static var _talent_cache := {}


static func _cfg(k: String) -> Dictionary:
	return Wars.data().get(k, {})


static func _w(state: GameState) -> Dictionary:
	var w := Wars._w(state)
	for k in STORES:
		if not w.has(k):
			w[k] = {}
	return w


static func _dk(a: int, b: int) -> String:
	return "%d>%d" % [a, b]


static func _name(state: GameState, eid: int) -> String:
	return Wars._name(state, eid)


static func _short(state: GameState, eid: int) -> String:
	return Wars._short(state, eid)


static func _never(state: GameState, eid: int) -> bool:
	var e := state.get_empire(eid)
	return e != null and bool(AiLevels.personality(e).get("temperament", {}).get("never_peace", false))


# --- Talents de peuple (prop. 24) ------------------------------------------------------------------

static func _talent_entries(state: GameState, eid: int) -> Array:
	var out: Array = []
	var e := state.get_empire(eid)
	if e == null or e.is_npc():
		return out
	var sp: Dictionary = e.faction().get("species", {})
	var table: Dictionary = _cfg("talents")
	for layer in TradeLinks.LAYERS:
		var t: Dictionary = (table.get(layer, {}) as Dictionary).get(String(sp.get(layer, "")), {})
		if t.is_empty():
			continue
		var ok := true
		var req: Dictionary = t.get("requires", {})
		for rk in req:
			if String(sp.get(rk, "")) != String(req[rk]):
				ok = false
		if ok:
			out.append(t)
	return out


## Talents de guerre de eid (clés fusionnées des couches de son espèce).
static func talent(state: GameState, eid: int) -> Dictionary:
	var e := state.get_empire(eid)
	if e == null or e.is_npc():
		return {}
	var ck := "%s:%d" % [e.faction_id, GameData.factions_gen]
	if _talent_cache.has(ck):
		return _talent_cache[ck]
	var out := {}
	for t: Dictionary in _talent_entries(state, eid):
		for k in t:
			if k == "label" or k == "text" or k == "requires":
				continue
			var v: Variant = t[k]
			out[k] = v if v is bool else int(out.get(k, 0)) + int(v)
	_talent_cache[ck] = out
	return out


static func has_talent(state: GameState, eid: int, k: String) -> bool:
	return bool(talent(state, eid).get(k, false))


static func talent_labels(state: GameState, eid: int) -> Array:
	var out := []
	for t: Dictionary in _talent_entries(state, eid):
		out.append([String(t["label"]), String(t["text"])])
	return out


## Prix d'une revendication modulé par le talent (féodalité : moitié prix).
static func claim_pct(state: GameState, eid: int) -> int:
	return clampi(100 + int(talent(state, eid).get("claim_pct", 0)), 0, 300)


# --- Motifs du lot 3 --------------------------------------------------------------------------------

static func has_ult_casus(state: GameState, a: int, b: int) -> bool:
	return int((_w(state)["ult"] as Dictionary).get(_dk(a, b), 0)) > state.tick


static func has_incident(state: GameState, a: int, b: int) -> bool:
	return int((_w(state)["inc"] as Dictionary).get(_dk(a, b), 0)) > state.tick


static func kanly_ok(state: GameState, a: int, b: int) -> bool:
	if not has_talent(state, a, "kanly") or Diplomacy.no_treaties(state, b):
		return false
	return Diplomacy.opinion(state, a, b) < int(_cfg("kanly").get("max_opinion", 25))


## Une guerre déclarée : limitée (kanly, guerre réglée), modificateurs de lassitude, courants, condamnation.
static func on_declared(state: GameState, rec: Dictionary, joined: bool) -> void:
	var a := int(rec["a"])
	var b := int(rec["d"])
	var cd := Wars.casus_def(String(rec["cb"]))
	var lim := bool(cd.get("limited", false)) or bool(Wars.goal_def(String(rec["ga"])).get("limited", false))
	if not lim and Amphictyony.founded(state) and Amphictyony.is_member(state, a) and Amphictyony.is_member(state, b) \
			and Amphictyony._level_flag(state, "limited_members") and not Amphictyony.casus(state, a, b):
		lim = true
	rec["lim"] = lim
	rec["exm"] = [_ex_pct(state, rec, a), _ex_pct(state, rec, b)]
	_w(state)["prep"].erase(str(a))
	# Une crise entre eux est close par la guerre.
	(_w(state)["crises"] as Dictionary).erase(Diplomacy.key(a, b))
	if joined:
		return
	if bool(cd.get("just", false)):
		Politics.on_act(state, a, "war_just")
	elif bool(rec.get("agg", false)):
		Politics.on_act(state, a, "war_aggression")
		_condemn(state, a, b)


## Lassitude de eid dans cette guerre, en % (kanly, croisade, Raison d'État).
static func _ex_pct(state: GameState, rec: Dictionary, eid: int) -> int:
	var pct := 100
	if bool(rec.get("lim", false)):
		pct = pct * int(_cfg("kanly").get("exhaustion_pct", 50)) / 100
	if String(rec["cb"]) == "guerre_sainte" and has_talent(state, eid, "crusade"):
		pct /= 2
	if Amphictyony.founded(state) and Amphictyony.is_member(state, eid):
		pct = pct * maxi(0, 100 + Amphictyony.level_sum(state, "war_ex_pct")) / 100
	# Rayonnement : attaquer un empire dont la culture est Influente chez soi lasse plus vite.
	pct = pct * (100 + CultureLife.war_ex_pct(state, rec, eid)) / 100
	return maxi(0, pct)


static func is_limited(state: GameState, a: int, b: int) -> bool:
	return bool(Wars.war(state, a, b).get("lim", false))


static func is_kanly(state: GameState, a: int, b: int) -> bool:
	return String(Wars.war(state, a, b).get("cb", "")) == "kanly"


## Guerre limitée : on ne débarque pas sur un monde peuplé.
static func check_invade(state: GameState, eid: int, sid: int) -> String:
	if not state.wars_on:
		return ""
	var owner := state.system_owner(sid)
	if owner < 0 or not is_limited(state, eid, owner):
		return ""
	if Vassals.system_pop(state, sid, owner) > 0:
		return "guerre limitée : on ne débarque pas sur un monde peuplé (flottes et avant-postes seulement)"
	return ""


# --- Droit de la guerre et Amphictyonie (prop. 23, 25) ---------------------------------------------

## Crime de guerre de eid contre victim : hors-la-loi (s'il est membre), souvenir, session extraordinaire,
## et motif Défense commune pour tous les amphictyons.
static func war_crime(state: GameState, eid: int, victim: int, kind: String) -> void:
	if not state.wars_on or not Amphictyony.founded(state) or not Amphictyony.banned(state, kind) or GameState.is_npc(eid):
		return
	if not Amphictyony.is_member(state, victim) or Amphictyony.casus(state, eid, victim) or AmphPower.exempt_kind(state, eid, kind):
		return
	Amphictyony.breach(state, eid, kind)
	state.amph["casus"][str(eid)] = state.tick + int(Amphictyony.data()["casus_days"])
	for m in Amphictyony.members(state):
		if m != eid:
			Diplomacy.remember(state, m, eid, "war_crime")
	AmphInst.add_trig(state, "war_crime", eid, victim)
	state.add_chronicle("Crime de guerre : %s (%s). %s ouvre le dossier ; chaque amphictyon peut lui déclarer la guerre sans se parjurer." % [
			_name(state, eid), Amphictyony.breach_label(kind), Amphictyony.cap(Amphictyony.name_short())],
			Espionage.public_to(state, Amphictyony.members(state) + [eid]))


## Héros prisonnier exécuté (appelé par Heroes.prisoner).
static func on_execute(state: GameState, jailer: int, owner: int) -> void:
	war_crime(state, jailer, owner, "hero_execution")


## Système pris ou occupé pendant une guerre (appelé par Wars avant le changement).
static func on_invaded(state: GameState, sid: int, taker: int, old: int) -> void:
	if Vassals.system_pop(state, sid, old) > 0:
		war_crime(state, taker, old, "invade_populated")


## Agression sans motif contre un amphictyon, ou par un amphictyon : condamnée d'office.
static func _condemn(state: GameState, a: int, b: int) -> void:
	if not Amphictyony.founded(state) or not (Amphictyony.is_member(state, a) or Amphictyony.is_member(state, b)):
		return
	for m in Amphictyony.members(state):
		if m != a:
			Diplomacy.remember(state, m, a, "amph_condemned")
	state.add_chronicle("%s condamne l'agression de %s contre %s : guerre sans motif avouable. Le blâme est voté à main levée." % [
			Amphictyony.cap(Amphictyony.name_short()), _name(state, a), _name(state, b)], Espionage.public_to(state, Amphictyony.members(state) + [a, b]))


static func check_guarantee(state: GameState, eid: int, tid: int) -> String:
	if AmphInst.arbiter(state) != eid:
		return "seul l'Arbitre des étoiles garantit un traité"
	var t := treaty(state, tid)
	if t.is_empty():
		return "traité inconnu"
	if int(t.get("g", -1)) >= 0:
		return "ce traité est déjà garanti"
	if int(t["w"]) < 0:
		return "un statu quo n'a rien à garantir"
	var cost: Dictionary = _cfg("arbiter").get("guarantee_cost", {})
	if not Economy.can_afford(state.get_empire(eid), cost):
		return "il faut %s" % GameData.format_amounts(cost)
	return ""


static func guarantee(state: GameState, eid: int, tid: int) -> void:
	var t := treaty(state, tid)
	Economy.pay(state.get_empire(eid), _cfg("arbiter").get("guarantee_cost", {}))
	t["g"] = eid
	state.add_chronicle("L'Arbitre des étoiles (%s) garantit le %s : qui le violera aura toute %s contre lui." % [
			_name(state, eid), String(t["name"]), Amphictyony.name_short()], Espionage.public_to(state, [int(t["a"]), int(t["b"]), eid]))


static func treaty(state: GameState, tid: int) -> Dictionary:
	for t in state.wars.get("treaties", []):
		if int(t["id"]) == tid:
			return t
	return {}


## Un traité est violé (appelé par WarPeace._violations) : s'il est garanti, motif pour tous.
static func on_violated(state: GameState, t: Dictionary, violator: int) -> void:
	if int(t.get("g", -1)) < 0 or not Amphictyony.founded(state):
		return
	state.amph["casus"][str(violator)] = state.tick + int(Amphictyony.data()["casus_days"])
	state.add_chronicle("Le %s était garanti par l'Arbitre des étoiles : chaque amphictyon peut désormais marcher contre %s." % [
			String(t["name"]), _name(state, violator)], Espionage.public_to(state, Amphictyony.members(state) + [violator]))


# --- Ultimatums (prop. 19) --------------------------------------------------------------------------

## Exigences possibles de a envers b : "cede:<système>" (revendiqué, pas la capitale), "tribut", "rupture".
static func ult_whats(state: GameState, a: int, b: int) -> Array[String]:
	var out: Array[String] = []
	var home := FactionTraits.capital_system(state, b)
	for sid in Wars.claims_on(state, a, b):
		if sid != home:
			out.append("cede:%d" % sid)
	out.append("tribut")
	if not Diplomacy.allies(state, b).is_empty():
		out.append("rupture")
	return out


static func what_label(state: GameState, what: String) -> String:
	if what.begins_with("cede:"):
		return "céder %s" % state.galaxy.systems[int(what.substr(5))].system_name
	return String(_cfg("ultimatum").get("whats", {}).get(what, {}).get("label", what)).to_lower()


static func _base_check(state: GameState, a: int, b: int) -> String:
	var ea := state.get_empire(a)
	var eb := state.get_empire(b)
	if ea == null or eb == null or eb.eliminated or eb.is_npc() or a == b:
		return "empire inconnu"
	if not ea.contacts.has(b):
		return "vous ne l'avez pas rencontré"
	if Combat.at_war(state, a, b):
		return "vous êtes déjà en guerre"
	if Diplomacy.allied(state, a, b) or Diplomacy.team_of(state, a, b) > 0:
		return "on ne menace pas un allié"
	if Vassals.lord_of(state, a) == b or Vassals.lord_of(state, b) == a:
		return "pas entre suzerain et sujet"
	if Diplomacy.no_treaties(state, a) or Diplomacy.no_treaties(state, b):
		return "l'Essaim ne négocie pas"
	return ""


static func check_ultimatum(state: GameState, a: int, b: int, what: String) -> String:
	var why := _base_check(state, a, b)
	if why != "":
		return why
	if not ult_whats(state, a, b).has(what):
		return "exigence impossible"
	if not Diplomacy.pending(state, a, b, "wult").is_empty():
		return "ultimatum déjà envoyé"
	var left := Diplomacy.cooldown_left(state, a, b, "wult")
	if left > 0:
		return "trop tôt pour un nouvel ultimatum (%d jours)" % left
	var cost: Dictionary = _cfg("ultimatum").get("cost", {})
	if not Economy.can_afford(state.get_empire(a), cost):
		return "il faut %s" % GameData.format_amounts(cost)
	return ""


static func ultimatum(state: GameState, a: int, b: int, what: String) -> void:
	var c := _cfg("ultimatum")
	Economy.pay(state.get_empire(a), c.get("cost", {}))
	Diplomacy._set_cooldown(state, a, b, "wult", int(c.get("cd_days", 720)))
	if state.get_empire(b).is_ai():
		_ult_resolve(state, a, b, what, ai_accepts_ult(state, a, b))
		return
	state.proposals.append({"id": state.next_proposal_id, "from": a, "to": b, "treaty": "wult", "tick": state.tick, "terms": {"what": what}})
	state.next_proposal_id += 1
	state.add_chronicle("%s adresse un ultimatum à %s : %s, ou la guerre." % [_name(state, a), _name(state, b), what_label(state, what)],
			Espionage.private_to(state, [a, b]))


static func ai_accepts_ult(state: GameState, a: int, b: int) -> bool:
	if _never(state, b):
		return false
	return Vassals.power_pct(state, a, b) >= int(_cfg("ultimatum").get("ai_power_pct", 150))


static func _ult_resolve(state: GameState, a: int, b: int, what: String, accept: bool) -> void:
	if not accept:
		_w(state)["ult"][_dk(a, b)] = state.tick + int(_cfg("ultimatum").get("casus_days", 1800))
		state.add_chronicle("%s repousse l'ultimatum de %s (%s). La galaxie trouve sa colère légitime : il a désormais un motif de guerre." % [
				_name(state, b), _name(state, a), what_label(state, what)], Espionage.public_to(state, [a, b]))
		return
	if what.begins_with("cede:"):
		var sid := int(what.substr(5))
		if state.system_owner(sid) == b and sid != FactionTraits.capital_system(state, b):
			Combat.capture_system(state, sid, a)
	elif what == "tribut":
		var c := _cfg("ultimatum")
		if not state.vassals.has("trib"):
			state.vassals["trib"] = []
		(state.vassals["trib"] as Array).append({"from": b, "to": a, "until": state.tick + int(c.get("tribute_days", 1800)), "pct": int(c.get("tribute_pct", 10))})
	elif what == "rupture":
		_break_alliances(state, b)
	Diplomacy.remember(state, b, a, "ultimatum_yielded")
	WarPeace.register(state, a, b, a, "ultimatum : " + what_label(state, what), {}, "ultimatum")
	state.add_chronicle("%s plie devant l'ultimatum de %s : %s. Pas un coup de feu ; beaucoup de rancune." % [
			_name(state, b), _name(state, a), what_label(state, what)], Espionage.public_to(state, [a, b]))


static func _break_alliances(state: GameState, eid: int) -> void:
	for ally in Diplomacy.allies(state, eid):
		if Diplomacy.team_of(state, eid, ally) <= 0:
			var r := Diplomacy._rel_w(state, eid, ally)
			r["pact"] = Diplomacy.COLD
			r["since"] = state.tick


# --- Crise diplomatique (prop. 20) ------------------------------------------------------------------

static func crisis_between(state: GameState, a: int, b: int) -> Dictionary:
	return (_w(state)["crises"] as Dictionary).get(Diplomacy.key(a, b), {})


## La crise où eid est l'un des deux camps principaux ({} sinon).
static func crisis_of(state: GameState, eid: int) -> Dictionary:
	var cr: Dictionary = _w(state)["crises"]
	var keys := cr.keys()
	keys.sort()
	for k in keys:
		if int(cr[k]["a"]) == eid or int(cr[k]["d"]) == eid:
			return cr[k]
	return {}


static func check_crisis(state: GameState, a: int, b: int, s: String) -> String:
	var p := s.split("|")
	if p.size() != 2:
		return "motif et but attendus"
	var why := Combat.check_declare_war(state, a, b, false)
	if why != "":
		return why
	why = Wars.check_choice(state, a, b, p[0], p[1])
	if why != "":
		return why
	if p[0] == "totale" or p[0] == "kanly" or p[0] == "":
		return "pas de crise pour cette guerre : on la déclare"
	if not crisis_of(state, a).is_empty() or not crisis_of(state, b).is_empty():
		return "l'un de vous est déjà pris dans une crise"
	var cost: Dictionary = _cfg("crisis").get("cost", {})
	if not Economy.can_afford(state.get_empire(a), cost):
		return "il faut %s" % GameData.format_amounts(cost)
	return ""


static func open_crisis(state: GameState, a: int, b: int, s: String) -> void:
	var c := _cfg("crisis")
	var p := s.split("|")
	Economy.pay(state.get_empire(a), c.get("cost", {}))
	var rec := {"a": a, "d": b, "t": state.tick, "end": state.tick + int(c.get("days", 30)), "cb": p[0], "g": p[1], "ra": [], "rd": []}
	_w(state)["crises"][Diplomacy.key(a, b)] = rec
	state.add_chronicle("Crise diplomatique : %s somme %s (motif : %s ; but : %s). Trente jours pour reculer, ou ce sera la guerre." % [
			_name(state, a), _name(state, b), Wars.casus_label(p[0]).to_lower(), Wars.goal_label(p[1]).to_lower()], Espionage.public_to(state, [a, b]))
	_auto_rallies(state, rec)


static func _side_list(rec: Dictionary, side: int) -> Array:
	return rec["ra"] if int(rec["a"]) == side else rec["rd"]


static func _enemy(rec: Dictionary, side: int) -> int:
	return int(rec["d"]) if int(rec["a"]) == side else int(rec["a"])


## Tiers que side peut rallier dans cette crise.
static func rally_candidates(state: GameState, rec: Dictionary, side: int) -> Array[int]:
	var out: Array[int] = []
	if rec.is_empty() or _side_list(rec, side).size() >= int(_cfg("crisis").get("rally_max", 3)):
		return out
	var foe := _enemy(rec, side)
	var es := state.get_empire(side)
	for e in state.empires:
		var t := e.id
		if t == side or t == foe or e.eliminated or e.is_npc() or (rec["ra"] as Array).has(t) or (rec["rd"] as Array).has(t):
			continue
		if not es.contacts.has(t) or not e.contacts.has(foe) or Combat.at_war(state, t, side):
			continue
		if Diplomacy.check_war(state, t, foe) != "" or Diplomacy.no_treaties(state, t):
			continue
		out.append(t)
	return out


static func check_rally(state: GameState, side: int, third: int, other: int) -> String:
	var rec := crisis_between(state, side, other)
	if rec.is_empty():
		return "aucune crise entre vous"
	if not rally_candidates(state, rec, side).has(third):
		return "il ne peut pas se ranger à vos côtés"
	if not Diplomacy.pending(state, side, third, "wrally").is_empty():
		return "demande déjà envoyée"
	return ""


static func rally(state: GameState, side: int, third: int, other: int) -> void:
	var rec := crisis_between(state, side, other)
	if state.get_empire(third).is_ai():
		_rally_resolve(state, Diplomacy.key(side, other), side, third, ai_rally_accepts(state, rec, side, third))
		return
	state.proposals.append({"id": state.next_proposal_id, "from": side, "to": third, "treaty": "wrally", "tick": state.tick,
			"terms": {"k": Diplomacy.key(side, other)}})
	state.next_proposal_id += 1
	state.add_chronicle("%s demande à %s de se ranger à ses côtés contre %s." % [_name(state, side), _name(state, third), _name(state, other)],
			Espionage.private_to(state, [side, third]))


static func _crusaders(state: GameState, rec: Dictionary, side: int, third: int) -> bool:
	return state.faith_on and String(rec["cb"]) == "guerre_sainte" and has_talent(state, side, "crusade") \
			and Faiths.has_state_faith(state, side) and Faiths.state_faith(state, side) == Faiths.state_faith(state, third)


static func ai_rally_accepts(state: GameState, rec: Dictionary, side: int, third: int) -> bool:
	var foe := _enemy(rec, side)
	if _crusaders(state, rec, side, third) or Diplomacy.allied(state, third, side) or Vassals.lord_of(state, third) == side:
		return true
	return Diplomacy.opinion(state, third, side) >= int(_cfg("crisis").get("rally_opinion", 25)) and Diplomacy.opinion(state, third, foe) <= 0


static func _rally_resolve(state: GameState, k: String, side: int, third: int, accept: bool) -> void:
	var rec: Dictionary = (_w(state)["crises"] as Dictionary).get(k, {})
	if rec.is_empty():
		return
	if not accept:
		state.add_chronicle("%s décline : il ne se mêlera pas de la crise entre %s et %s." % [_name(state, third), _name(state, int(rec["a"])), _name(state, int(rec["d"]))],
				Espionage.private_to(state, [side, third]))
		return
	if not rally_candidates(state, rec, side).has(third):
		return
	_side_list(rec, side).append(third)
	Diplomacy.remember(state, side, third, "rallied")
	state.add_chronicle("%s se range aux côtés de %s dans la crise qui l'oppose à %s." % [_name(state, third), _name(state, side), _name(state, _enemy(rec, side))],
			Espionage.public_to(state, [side, third, _enemy(rec, side)]))


## Les IA de la crise rallient ceux qui accepteraient ; une croisade rallie d'elle-même les mêmes fidèles.
static func _auto_rallies(state: GameState, rec: Dictionary) -> void:
	for side in [int(rec["a"]), int(rec["d"])]:
		var es := state.get_empire(side)
		for t in rally_candidates(state, rec, side):
			if es.is_ai() or _crusaders(state, rec, side, t):
				var et := state.get_empire(t)
				if et.is_ai() and ai_rally_accepts(state, rec, side, t):
					_rally_resolve(state, Diplomacy.key(int(rec["a"]), int(rec["d"])), side, t, true)


static func check_backdown(state: GameState, eid: int, other: int) -> String:
	if crisis_between(state, eid, other).is_empty():
		return "aucune crise entre vous"
	return ""


## eid recule : défenseur, il cède le but principal ; agresseur, il abandonne ses revendications.
static func backdown(state: GameState, eid: int, other: int) -> void:
	var rec := crisis_between(state, eid, other)
	var a := int(rec["a"])
	var d := int(rec["d"])
	(_w(state)["crises"] as Dictionary).erase(Diplomacy.key(a, d))
	var c := _cfg("crisis")
	if eid == d:
		var got := _concede(state, a, d, String(rec["g"]))
		Diplomacy.remember(state, d, a, "crisis_backdown")
		Wars.set_truce(state, a, d, 0)
		WarPeace.register(state, a, d, a, "crise : %s recule" % _short(state, d), {}, "crise")
		state.add_chronicle("%s recule devant %s : %s.%s" % [_name(state, d), _name(state, a), Wars.goal_label(String(rec["g"])).to_lower(),
				(" Cédé : %s." % ", ".join(got)) if not got.is_empty() else ""], Espionage.public_to(state, [a, d]))
	else:
		var ea := state.get_empire(a)
		ea.resources["influence"] = int(ea.resources.get("influence", 0)) - mini(maxi(0, int(ea.resources.get("influence", 0))), int(c.get("backdown_influence", 50)))
		for sid in Wars.claims_on(state, a, d):
			(Wars._map(state, "claims", a) as Dictionary).erase(str(sid))
		Diplomacy.remember(state, a, d, "crisis_backdown")
		Wars.set_truce(state, a, d, 0)
		WarPeace.register(state, a, d, d, "crise : %s recule" % _short(state, a), {}, "crise")
		state.add_chronicle("%s recule et abandonne ses prétentions sur %s. Les chancelleries sourient ; ses amiraux, beaucoup moins." % [
				_name(state, a), _name(state, d)], Espionage.public_to(state, [a, d]))


## Ce que cède le défenseur qui recule (sans guerre) : revendications, puis l'effet principal du but.
static func _concede(state: GameState, a: int, d: int, gid: String) -> Array[String]:
	var got: Array[String] = []
	var home := FactionTraits.capital_system(state, d)
	for sid in Wars.claims_on(state, a, d):
		if sid != home:
			Combat.capture_system(state, sid, a)
			got.append(state.galaxy.systems[sid].system_name)
	var ea := state.get_empire(a)
	var ed := state.get_empire(d)
	match gid:
		"humiliation":
			var n := mini(maxi(0, int(ed.resources.get("influence", 0))), int(Wars._cfg("humiliation").get("influence", 100)))
			ed.resources["influence"] = int(ed.resources.get("influence", 0)) - n
			ea.resources["influence"] = int(ea.resources.get("influence", 0)) + n
			Diplomacy.remember(state, d, a, "humiliated")
		"rancon":
			for r in ["materials", "energy", "influence"]:
				@warning_ignore("integer_division")
				var n := maxi(0, int(ed.resources.get(r, 0))) * int(_cfg("crisis").get("repar_pct", 20)) / 100
				ed.resources[r] = int(ed.resources.get(r, 0)) - n
				ea.resources[r] = int(ea.resources.get(r, 0)) + n
		"soumission":
			if state.vassals_on and not Vassals.is_subject(state, d) and not Vassals.is_subject(state, a):
				Vassals.bind(state, a, d, "vassal", Vassals.preset_clauses("vassal"), int(Vassals.data()["loyalty"].get("start_terms", 0)), true)
		"liberer":
			for sid in Wars._liberable(state, a, d):
				var to := Wars._liberable_owner(state, a, sid)
				if to >= 0 and state.system_owner(sid) == d and sid != home:
					Combat.capture_system(state, sid, to)
					got.append(state.galaxy.systems[sid].system_name)
		"demanteler":
			_break_alliances(state, d)
			if Koinon.league_of(state, d) >= 0:
				Koinon._leave_now(state, Koinon.league_of(state, d), d)
		"independance":
			if Vassals.lord_of(state, a) == d:
				Vassals.unbind(state, a, "son suzerain a reculé")
	return got


## Puissance d'un camp de la crise (le camp principal et ses ralliés).
static func camp_power(state: GameState, rec: Dictionary, side: int) -> int:
	var n := Vassals.power(state, side)
	for t in _side_list(rec, side):
		n += Vassals.power(state, int(t))
	return n


## Chaque jour : les crises échues mènent à la guerre (les IA reculent devant un camp bien plus fort).
static func daily(state: GameState) -> void:
	if not state.wars_on:
		return
	var cr: Dictionary = _w(state)["crises"]
	if cr.is_empty():
		return
	var keys := cr.keys()
	keys.sort()
	for k in keys:
		if not cr.has(k):
			continue
		var rec: Dictionary = cr[k]
		var a := int(rec["a"])
		var d := int(rec["d"])
		if state.get_empire(a).eliminated or state.get_empire(d).eliminated or Combat.at_war(state, a, d):
			cr.erase(k)
			continue
		if state.tick < int(rec["end"]):
			continue
		var pct := int(_cfg("crisis").get("ai_backdown_pct", 150))
		var pa := camp_power(state, rec, a)
		var pd := camp_power(state, rec, d)
		if state.get_empire(d).is_ai() and not _never(state, d) and pa * 100 >= pd * pct:
			backdown(state, d, a)
		elif state.get_empire(a).is_ai() and pd * 100 >= pa * pct:
			backdown(state, a, d)
		else:
			_escalate(state, rec)


static func _escalate(state: GameState, rec: Dictionary) -> void:
	var a := int(rec["a"])
	var d := int(rec["d"])
	(_w(state)["crises"] as Dictionary).erase(Diplomacy.key(a, d))
	if Combat.check_declare_war(state, a, d, false) != "":
		state.add_chronicle("La crise entre %s et %s retombe d'elle-même." % [_name(state, a), _name(state, d)], Espionage.public_to(state, [a, d]))
		return
	Wars.set_pending(state, a, d, String(rec["cb"]), String(rec["g"]), true)
	Combat.start_war(state, a, d)
	for pair in [[rec["ra"], d], [rec["rd"], a]]:
		for t in pair[0]:
			var foe := int(pair[1])
			var et := state.get_empire(int(t))
			if et == null or et.eliminated or Combat.at_war(state, int(t), foe) or Diplomacy.check_war(state, int(t), foe) != "":
				continue
			Combat.start_war(state, int(t), foe, false, true)
			state.add_chronicle("%s tient parole et entre en guerre contre %s." % [et.display_name(), _name(state, foe)], Espionage.public_to(state, [int(t), foe]))


# --- Préavis de guerre (prop. 21) -------------------------------------------------------------------

## Délai de préparation d'une IA selon son niveau.
static func prep_days(lvl: int) -> int:
	var days: Array = _cfg("prep").get("days", [45, 30, 20])
	return int(days[clampi(lvl, 0, days.size() - 1)])


## a prépare-t-il une guerre contre b depuis assez longtemps ?
static func prepared(state: GameState, a: int, b: int, lvl: int) -> bool:
	var p: Dictionary = (_w(state)["prep"] as Dictionary).get(str(a), {})
	return not p.is_empty() and int(p["b"]) == b and state.tick - int(p["t"]) >= prep_days(lvl)


## a commence à masser ses flottes contre b : qui a des espions chez a (ou la Prévision) le voit.
static func prepare(state: GameState, a: int, b: int) -> void:
	var w := _w(state)
	var p: Dictionary = (w["prep"] as Dictionary).get(str(a), {})
	if not p.is_empty() and int(p["b"]) == b:
		return
	var seen: Array = []
	var tier := int(_cfg("prep").get("tier", 1))
	for e in state.empires:
		if e.id == a or e.eliminated or e.is_npc() or not e.contacts.has(a):
			continue
		if Espionage.tier(state, e.id, a) >= tier or has_talent(state, e.id, "foresight"):
			seen.append(e.id)
	w["prep"][str(a)] = {"b": b, "t": state.tick, "seen": seen}
	if not seen.is_empty():
		state.add_chronicle("Préavis de guerre : %s masse ses flottes face à %s. Les rapports d'espions concordent." % [_name(state, a), _name(state, b)],
				Espionage.private_to(state, seen))


## Préparation que viewer a repérée chez a ({} sinon).
static func seen_prep(state: GameState, viewer: int, a: int) -> Dictionary:
	var p: Dictionary = (_w(state)["prep"] as Dictionary).get(str(a), {})
	if p.is_empty() or not (p.get("seen", []) as Array).has(viewer):
		return {}
	return p


## Préparations repérées par viewer : [[préparant, cible]].
static func warnings(state: GameState, viewer: int) -> Array:
	var out: Array = []
	var pr: Dictionary = _w(state)["prep"]
	var keys := pr.keys()
	keys.sort()
	for k in keys:
		if (pr[k].get("seen", []) as Array).has(viewer):
			out.append([int(k), int(pr[k]["b"])])
	return out


static func _prune_prep(state: GameState) -> void:
	var pr: Dictionary = _w(state)["prep"]
	var limit := int(_cfg("prep").get("expire_days", 150))
	for k in pr.keys():
		if state.tick - int(pr[k]["t"]) >= limit or Combat.at_war(state, int(k), int(pr[k]["b"])):
			pr.erase(k)


# --- Médiation (talent, prop. 24) -------------------------------------------------------------------

static func check_mediate(state: GameState, eid: int, a: int, b: int) -> String:
	if not has_talent(state, eid, "mediate"):
		return "votre peuple n'a pas le talent de la médiation"
	if eid == a or eid == b or a == b:
		return "un médiateur ne se mêle pas de ses propres guerres"
	var rec := Wars.war(state, a, b)
	if rec.is_empty() or not Combat.at_war(state, a, b):
		return "ces deux empires ne sont pas en guerre"
	if Combat.at_war(state, eid, a) or Combat.at_war(state, eid, b):
		return "vous êtes en guerre avec l'un d'eux"
	var e := state.get_empire(eid)
	if not e.contacts.has(a) or not e.contacts.has(b):
		return "vous ne les connaissez pas tous les deux"
	var m := _cfg("mediation")
	if state.tick - int(rec["t"]) < int(m.get("min_days", 180)):
		return "trop tôt : la guerre doit durer au moins %d jours" % int(m.get("min_days", 180))
	if absi(Wars.score(state, a, b)) > int(m.get("max_score", 30)):
		return "l'un des camps gagne trop nettement (score au-delà de %d %%)" % int(m.get("max_score", 30))
	if Diplomacy.no_treaties(state, a) or Diplomacy.no_treaties(state, b):
		return "l'Essaim ne signe rien"
	var left := Diplomacy.cooldown_left(state, eid, eid, "mediate")
	if left > 0:
		return "votre dernière médiation est trop récente (%d jours)" % left
	if not Economy.can_afford(e, m.get("cost", {})):
		return "il faut %s" % GameData.format_amounts(m.get("cost", {}))
	return ""


static func mediate(state: GameState, eid: int, a: int, b: int) -> void:
	var m := _cfg("mediation")
	Economy.pay(state.get_empire(eid), m.get("cost", {}))
	Diplomacy._set_cooldown(state, eid, eid, "mediate", int(m.get("cd_days", 720)))
	state.add_chronicle("%s offre sa médiation entre %s et %s : on signe le statu quo dans ses salons, devant un buffet remarquable." % [
			_name(state, eid), _name(state, a), _name(state, b)], Espionage.public_to(state, [eid, a, b]))
	Diplomacy.sign_treaty(state, a, b, Diplomacy.PEACE)
	Diplomacy.remember(state, a, eid, "mediated")
	Diplomacy.remember(state, b, eid, "mediated")


## Guerres que eid pourrait arbitrer : [[a, b]] triées.
static func mediable(state: GameState, eid: int) -> Array:
	var out: Array = []
	if not state.wars_on or not has_talent(state, eid, "mediate"):
		return out
	var keys: Array = (Wars._w(state)["list"] as Dictionary).keys()
	keys.sort()
	for k in keys:
		var r: Dictionary = Wars._w(state)["list"][k]
		if check_mediate(state, eid, int(r["a"]), int(r["d"])) == "":
			out.append([int(r["a"]), int(r["d"])])
	return out


# --- Koinon : sécession (prop. 26) ------------------------------------------------------------------

## Le Stratège refuse la sortie : la guerre de sécession a pour buts Quitter / Retenir.
static func on_secession(state: GameState, eid: int, strat: int) -> void:
	if state.wars_on:
		Wars.set_pending(state, eid, strat, "secession", "quitter", true)


## Victoire dans une guerre de sécession.
static func apply_secession(state: GameState, winner: int, loser: int, gid: String) -> void:
	var sc := _cfg("secession")
	match gid:
		"quitter":
			var e := state.get_empire(winner)
			e.resources["influence"] = int(e.resources.get("influence", 0)) + int(sc.get("influence", 50))
		"retenir":
			var lid := Koinon.league_of(state, winner)
			if lid >= 0 and Koinon.league_of(state, loser) < 0:
				var l := Koinon.league(state, lid)
				(l["members"] as Array).append(loser)
				l["joined"][str(loser)] = state.tick
				_w(state)["retain"][str(loser)] = state.tick + int(sc.get("retain_days", 1800))
				state.relic_rev += 1


## Retenu par son Koinon après une sécession manquée : ne peut le quitter avant l'échéance.
static func retained_left(state: GameState, eid: int) -> int:
	return maxi(0, int((_w(state)["retain"] as Dictionary).get(str(eid), 0)) - state.tick)


# --- Espionnage (prop. 27) --------------------------------------------------------------------------

static func spy_check(state: GameState, a: int, b: int, op_id: String) -> String:
	if not state.wars_on:
		return "les buts de guerre ne sont pas actifs dans cette partie"
	match op_id:
		"fabriquer_revendication":
			if _fabricable(state, a, b) < 0:
				return "aucun de ses systèmes n'est à portée d'une revendication"
		"provoquer_incident":
			if has_incident(state, a, b):
				return "vous avez déjà un incident contre lui"
	return ""


static func _fabricable(state: GameState, a: int, b: int) -> int:
	if Diplomacy.allied(state, a, b) or Diplomacy.team_of(state, a, b) > 0 or Vassals.lord_of(state, a) == b or Vassals.lord_of(state, b) == a:
		return -1
	var home := FactionTraits.capital_system(state, b)
	for cand in Wars.claim_candidates(state, a, b, 8):
		if int(cand[0]) != home:
			return int(cand[0])
	return -1


static func spy_apply(state: GameState, a: int, b: int, o: Dictionary) -> String:
	match String(o["id"]):
		"fabriquer_revendication":
			var sid := _fabricable(state, a, b)
			if sid < 0:
				return "les archives ne contenaient rien d'exploitable."
			Wars._map(state, "claims", a)[str(sid)] = state.tick
			return "de vieilles chartes « retrouvées » : nous revendiquons désormais %s." % state.galaxy.systems[sid].system_name
		"provoquer_incident":
			_w(state)["inc"][_dk(a, b)] = state.tick + int(_cfg("incident").get("days", 1800))
			return "un incident de frontière éclate ; les témoins sont formels, et bien payés."
	return ""


# --- Héros (prop. 29) -------------------------------------------------------------------------------

## Héros de b que a retient prisonniers.
static func captives(state: GameState, a: int, b: int) -> int:
	var n := 0
	for id in Heroes.prisoners_of(state, a):
		if int(state.heroes[id]["owner"]) == b:
			n += 1
	return n


## Rabais sur le prix des clauses (%) : orateurs du conseil, 5 % par niveau.
static func diplomat_pct(state: GameState, eid: int) -> int:
	var c := _cfg("heroes")
	var pct := 0
	for h in Heroes.council(state, eid):
		if String(h["cls"]) == "orateur":
			@warning_ignore("integer_division")
			pct += int(c.get("diplomat_pct", 5)) * Heroes.half_levels(h, "council") / 2
	return mini(pct, int(c.get("diplomat_max", 30)))


## Héros de owner que jailer relâche (sens unique).
static func release_one_way(state: GameState, jailer: int, owner: int) -> void:
	var n := 0
	for id in Heroes.prisoners_of(state, jailer):
		var h: Dictionary = state.heroes[id]
		if int(h["owner"]) == owner:
			Heroes._free(state, h)
			n += 1
	if n > 0:
		state.add_chronicle("%s rend %d héros prisonnier%s à %s." % [_name(state, jailer), n, "s" if n > 1 else "", _name(state, owner)],
				Espionage.public_to(state, [jailer, owner]))


# --- Ordres, propositions, mois ---------------------------------------------------------------------

## Actes du lot 3 (via Wars.check_act) : "ultimatum" (x = cible, s = exigence), "crisis" (x, s = "motif|but"),
## "rally" (x = tiers, s = autre camp), "backdown" (x = autre camp), "mediate" (x, s = autre belligérant),
## "guarantee" (x = traité).
static func check_act(state: GameState, player: int, act: String, x: int, s: String) -> String:
	match act:
		"ultimatum":
			return check_ultimatum(state, player, x, s)
		"crisis":
			return check_crisis(state, player, x, s)
		"rally":
			return check_rally(state, player, x, int(s) if s.is_valid_int() else -1)
		"backdown":
			return check_backdown(state, player, x)
		"mediate":
			return check_mediate(state, player, x, int(s) if s.is_valid_int() else -1)
		"guarantee":
			return check_guarantee(state, player, x)
		"prep":
			return _base_check(state, player, x)
	return "ordre inconnu : %s" % act


static func act(state: GameState, player: int, act_id: String, x: int, s: String) -> void:
	match act_id:
		"ultimatum":
			ultimatum(state, player, x, s)
		"crisis":
			open_crisis(state, player, x, s)
		"rally":
			rally(state, player, x, int(s))
		"backdown":
			backdown(state, player, x)
		"mediate":
			mediate(state, player, x, int(s))
		"guarantee":
			guarantee(state, player, x)
		"prep":
			prepare(state, player, x)


static func kind_label(p: Dictionary) -> String:
	match String(p["treaty"]):
		"wult":
			return "Ultimatum"
		"wrally":
			return "Demande de ralliement"
	return String(p["treaty"])


static func kind_text(state: GameState, p: Dictionary) -> String:
	match String(p["treaty"]):
		"wult":
			return "Il exige : %s. Refuser lui donne un motif de guerre contre vous." % what_label(state, String(p.get("terms", {}).get("what", "")))
		"wrally":
			var rec: Dictionary = (_w(state)["crises"] as Dictionary).get(String(p.get("terms", {}).get("k", "")), {})
			if rec.is_empty():
				return "La crise est close."
			return "Vous entreriez en guerre à ses côtés contre %s si la crise tourne à la guerre (part du butin selon votre contribution)." % _name(state, _enemy(rec, int(p["from"])))
	return ""


static func check_accept(state: GameState, p: Dictionary) -> String:
	var from := int(p["from"])
	var to := int(p["to"])
	match String(p["treaty"]):
		"wult":
			if Combat.at_war(state, from, to):
				return "vous êtes déjà en guerre"
			var what := String(p.get("terms", {}).get("what", ""))
			if what.begins_with("cede:") and state.system_owner(int(what.substr(5))) != to:
				return "ce système n'est plus à vous"
		"wrally":
			var rec: Dictionary = (_w(state)["crises"] as Dictionary).get(String(p.get("terms", {}).get("k", "")), {})
			if rec.is_empty():
				return "la crise est close"
			if not rally_candidates(state, rec, from).has(to):
				return "vous ne pouvez plus vous ranger à ses côtés"
	return ""


static func answer(state: GameState, p: Dictionary, accept: bool) -> void:
	match String(p["treaty"]):
		"wult":
			_ult_resolve(state, int(p["from"]), int(p["to"]), String(p.get("terms", {}).get("what", "")), accept)
		"wrally":
			_rally_resolve(state, String(p.get("terms", {}).get("k", "")), int(p["from"]), int(p["to"]), accept)


static func monthly(state: GameState) -> void:
	_prune_prep(state)
	var w := _w(state)
	for k in ["ult", "inc", "retain"]:
		var m: Dictionary = w[k]
		for key in m.keys():
			if int(m[key]) <= state.tick:
				m.erase(key)
