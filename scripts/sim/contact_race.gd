class_name ContactRace
extends RefCounted
## La course au Signal (lot 2 du Contact, prop. 15, 18, 20-27, 31) : l'Écho qui ressort une vieille
## émission, les lectures menaçantes, les fragments et leur échange, le Consortium du Signal, trois
## opérations d'espionnage, la famille « Signal » de l'Amphictyonie, le casus belli « Faire taire »,
## le brouillage des Affamés et la menace de la Forêt sombre. Voir Contact ; données : data/contact.json.
##
## Sous-états : "frag" {"eid": [empires dont on tient le fragment]}, "cons" {"eid": fondateur du
## Consortium}, "offers" {"eid": [{"kind": "trade"|"cons", "from": eid}]}, "echo_hit" {"eid": [{"k",
## "until", "by"}]}, "threats" {"eid": menaçant}.


static func full(state: GameState) -> bool:
	return Contact.full(state)


static func _ok_pair(state: GameState, a: int, b: int) -> String:
	if a == b or not Contact.applies(state, b):
		return "empire inconnu"
	if not state.get_empire(a).contacts.has(b):
		return "vous ne l'avez pas rencontré"
	if Combat.at_war(state, a, b):
		return "vous êtes en guerre"
	return ""


## L'empire détient son propre fragment (il a capté le Signal, même partiellement).
static func has_own(state: GameState, eid: int) -> bool:
	return Contact.route_count(state, eid) > 0


static func no_trade(state: GameState, eid: int) -> bool:
	return Contact.t_int(state, eid, "no_trade") > 0


# --- Fragments (prop. 20-21) -------------------------------------------------------------------

## Empires dont l'empire tient un fragment : reçus, volés, ceux du Consortium et des Fragments communs.
static func held_from(state: GameState, eid: int) -> Array[int]:
	var out: Array[int] = []
	if not Contact.enabled(state):
		return out
	for x in Contact.sub(state, "frag").get(str(eid), []):
		if int(x) != eid and not out.has(int(x)) and has_own(state, int(x)):
			out.append(int(x))
	for m in partners(state, eid):
		if not out.has(m) and has_own(state, m):
			out.append(m)
	if shared_fragments(state) and Amphictyony.is_member(state, eid):
		for o in state.empires:
			if o.id != eid and not out.has(o.id) and Amphictyony.is_member(state, o.id) and has_own(state, o.id):
				out.append(o.id)
	out.sort()
	return out


static func foreign_count(state: GameState, eid: int) -> int:
	return held_from(state, eid).size()


static func holds(state: GameState, eid: int, from: int) -> bool:
	return held_from(state, eid).has(from)


static func give_fragment(state: GameState, from: int, to: int) -> void:
	if from == to or not has_own(state, from):
		return
	var l: Array = Contact.sub(state, "frag").get(str(to), []).duplicate()
	if not l.has(from):
		l.append(from)
		l.sort()
		Contact.sub(state, "frag")[str(to)] = l
		Contact._stat(state, to, "frags", 1)
		state.relic_rev += 1


## L'IA accepte-t-elle un échange ou un Consortium avec a ?
static func ai_accepts(state: GameState, b: int, a: int, kind: String) -> bool:
	var need := Contact.c_int("fragments", "min_opinion", -10) if kind == "trade" else Contact.c_int("consortium", "min_opinion", 0)
	if kind == "demand":
		need = 30
	return Diplomacy.opinion(state, b, a) >= need


static func gauge_pct_parts(state: GameState, eid: int) -> Array:
	var out := []
	var n := foreign_count(state, eid)
	if n > 0:
		out.append(["Fragments étrangers (%d)" % n, mini(n * Contact.c_int("gauge", "foreign_pct", 20), Contact.c_int("gauge", "foreign_max", 60))])
	var m := partners(state, eid).size()
	if m > 0:
		out.append(["Consortium (%d)" % m, m * Contact.c_int("consortium", "per_member_pct", 10)])
	var l := Amphictyony.level_sum(state, "ct_listen") if state.amph_on and Amphictyony.is_member(state, eid) else 0
	if l > 0:
		out.append(["Programme commun d'écoute", l])
	return out


# --- Consortium du Signal (prop. 22) -----------------------------------------------------------

static func cons_id(state: GameState, eid: int) -> int:
	return int(Contact.sub(state, "cons").get(str(eid), -1))


static func members(state: GameState, cid: int) -> Array[int]:
	var out: Array[int] = []
	if cid < 0:
		return out
	for k in Contact.sub(state, "cons"):
		if int(Contact.sub(state, "cons")[k]) == cid:
			out.append(int(k))
	out.sort()
	return out


## Les autres membres du Consortium de l'empire (ils gagnent avec lui).
static func partners(state: GameState, eid: int) -> Array[int]:
	var out: Array[int] = []
	if not Contact.enabled(state):
		return out
	for m in members(state, cons_id(state, eid)):
		if m != eid and not state.get_empire(m).eliminated:
			out.append(m)
	return out


## Pour un membre qui a gagné avec le Consortium : celui qui a transmis (-1 s'il a transmis lui-même).
static func winner_host(state: GameState, eid: int) -> int:
	if Contact.stat(state, eid, "won") > 0:
		return -1
	for m in partners(state, eid):
		if Contact.stat(state, m, "won") > 0:
			return m
	return -1


static func _join(state: GameState, a: int, b: int, added: Array[Dictionary]) -> void:
	var cid := cons_id(state, b)
	if cid < 0:
		cid = cons_id(state, a)
	if cid < 0:
		cid = a
	Contact.sub(state, "cons")[str(a)] = cid
	Contact.sub(state, "cons")[str(b)] = cid
	state.relic_rev += 1
	var names := PackedStringArray()
	for m in members(state, cid):
		names.append(state.get_empire(m).short_name())
	added.append(state.add_chronicle("Consortium du Signal : %s mettent en commun leurs fragments et leurs relevés. Ils répondront ensemble." % ", ".join(names),
			Espionage.public_to(state, members(state, cid))))


static func leave(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var cid := cons_id(state, eid)
	if cid < 0:
		return
	var rest := partners(state, eid)
	Contact.sub(state, "cons").erase(str(eid))
	for m in rest:
		Diplomacy.remember(state, m, eid, "ct_cons_quit")
	if rest.size() <= 1:
		for m in rest:
			Contact.sub(state, "cons").erase(str(m))
	state.relic_rev += 1
	added.append(state.add_chronicle("%s quitte le Consortium du Signal avant la Réponse. Ses anciens partenaires ne l'oublieront pas." % state.get_empire(eid).display_name(),
			Espionage.public_to(state, rest + [eid])))


## Les membres d'un Consortium sont tirés vers le plus avancé.
static func _pull(state: GameState, added: Array[Dictionary]) -> void:
	var done_c := {}
	for k in Contact.sub(state, "cons").keys():
		var cid := int(Contact.sub(state, "cons")[k])
		if done_c.has(cid):
			continue
		done_c[cid] = true
		var ms := members(state, cid)
		var best := 0
		for m in ms:
			best = maxi(best, Contact.gauge(state, m))
		for m in ms:
			var diff := best - Contact.gauge(state, m)
			@warning_ignore("integer_division")
			var n := diff * Contact.c_int("consortium", "pull_pct", 50) / 100
			if n > 0 and Contact.applies(state, m):
				Contact.add_gauge(state, m, n, added)


# --- L'Écho et les lectures (prop. 15, 18) -----------------------------------------------------

## L'Écho : la plus vieille émission d'un autre empire, tirée au sort.
static func on_echo(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var cand: Array[int] = []
	for o in state.empires:
		if o.id != eid and not o.is_npc() and not o.eliminated:
			cand.append(o.id)
	if cand.is_empty():
		return
	var target := cand[Contact._h(state, ["echo_who", eid]) % cand.size()]
	var draws: Array = Contact.cfg("echo").get("draws", [])
	var total := 0
	for d: Dictionary in draws:
		total += maxi(0, int(d.get("w", 0)))
	if total <= 0:
		return
	var roll := Contact._h(state, ["echo_kind", eid]) % total
	var pick: Dictionary = draws[0]
	for d: Dictionary in draws:
		roll -= maxi(0, int(d.get("w", 0)))
		if roll < 0:
			pick = d
			break
	var te := state.get_empire(target)
	if int(pick.get("influence", 0)) != 0:
		te.resources["influence"] = maxi(0, int(te.resources.get("influence", 0)) + int(pick["influence"]))
	var hits: Array = Contact.sub(state, "echo_hit").get(str(target), []).duplicate()
	hits.append({"k": String(pick["id"]), "until": state.tick + Contact.c_int("echo", "days", 1800), "by": eid})
	Contact.sub(state, "echo_hit")[str(target)] = hits
	added.append(state.add_chronicle(String(pick.get("text", "L'Écho rapporte une vieille émission de %s.")) % te.display_name()))


static func echo_label(k: String) -> String:
	for d: Dictionary in Contact.cfg("echo").get("draws", []):
		if String(d["id"]) == k:
			return String(d.get("label", k))
	return k


static func _echo_opinion(k: String) -> int:
	for d: Dictionary in Contact.cfg("echo").get("draws", []):
		if String(d["id"]) == k:
			return int(d.get("opinion", 0))
	return 0


static func on_menace(state: GameState, eid: int) -> void:
	Contact._stat(state, eid, "menace", 1)


## Opinion de a envers b (Diplomacy.opinion_parts).
static func opinion_parts(state: GameState, a: int, b: int) -> Array:
	var out := []
	if not Contact.enabled(state) or not Contact.applies(state, a) or not Contact.applies(state, b):
		return out
	for h: Dictionary in Contact.sub(state, "echo_hit").get(str(b), []):
		var v := _echo_opinion(String(h.get("k", "")))
		if v != 0 and state.tick < int(h.get("until", 0)):
			out.append(["L'Écho : %s" % echo_label(String(h["k"])), v])
	var m := Contact.readings(state, b, "menace")
	if m > 0:
		out.append(["Lit le Signal comme une arme", m * int((Contact.cfg("readings").get("menace", {}) as Dictionary).get("opinion", -10))])
	if Contact.has_layer(state, b, "abecedaire"):
		out.append(["La Langue universelle", Contact.c_int("abecedaire", "opinion", 10)])
	return out


# --- Brouillage (prop. 26) ---------------------------------------------------------------------

## Avec des Affamés, le plus avancé dans le déchiffrement (égalité : le plus petit numéro).
static func jammed(state: GameState) -> int:
	if Contact.nature(state) != "affames" or not full(state):
		return -1
	var best := -1
	var bg := 0
	for e in state.empires:
		if Contact.applies(state, e.id) and Contact.gauge(state, e.id) > bg:
			bg = Contact.gauge(state, e.id)
			best = e.id
	return best if Contact.layers(state, best) > 0 else -1


static func effects(state: GameState, eid: int) -> Dictionary:
	if jammed(state) == eid:
		return {"production_pct": {"knowledge": -Contact.c_int("jamming", "pct_per_layer", 10) * Contact.layers(state, eid)}}
	return {}


# --- La Forêt sombre (prop. 27) ----------------------------------------------------------------

static func check_dark_forest(state: GameState, eid: int, target: int) -> String:
	if not full(state):
		return "seulement en mode Complet"
	var w := _ok_pair(state, eid, target)
	if w != "":
		return w
	if not (Contact.knows_nature(state, eid) and Contact.nature(state) == "affames"):
		return "il faut savoir que les Lointains sont des Affamés"
	if not Contact.has_heraut(state, eid):
		return "il faut un Héraut pour diffuser des coordonnées"
	if int(Contact.sub(state, "threats").get(str(target), -1)) == eid:
		return "vous le menacez déjà"
	return ""


static func dark_forest(state: GameState, eid: int, target: int, added: Array[Dictionary]) -> void:
	var te := state.get_empire(target)
	var trib: Dictionary = Contact.cfg("dark_forest").get("tribute", {})
	var can := true
	for r in trib:
		if int(te.resources.get(r, 0)) < int(trib[r]):
			can = false
	Diplomacy.remember(state, target, eid, "ct_dark_forest")
	Contact._stat(state, eid, "dark_forest", 1)
	var e := state.get_empire(eid)
	if can:
		for r in trib:
			te.resources[r] = int(te.resources.get(r, 0)) - int(trib[r])
			e.resources[r] = int(e.resources.get(r, 0)) + int(trib[r])
		added.append(state.add_chronicle("Forêt sombre : %s menace de diffuser vers les Affamés les coordonnées de %s. %s cède et paie (%s)." % [e.display_name(), te.display_name(), te.short_name(), GameData.format_amounts(trib)],
				Espionage.public_to(state, [eid, target])))
	else:
		Contact.sub(state, "threats")[str(target)] = eid
		added.append(state.add_chronicle("Forêt sombre : %s ne peut pas payer. %s diffuse ses coordonnées ; si les Affamés viennent, ils iront d'abord chez %s." % [te.display_name(), e.short_name(), te.short_name()],
				Espionage.public_to(state, [eid, target])))


## Empire désigné aux Affamés (crise de l'Outre-Nuit), -1 sinon.
static func marked_target(state: GameState) -> int:
	var ks := Contact.sub(state, "threats").keys()
	ks.sort()
	for k in ks:
		var e := state.get_empire(int(k))
		if e != null and not e.eliminated:
			return int(k)
	return -1


# --- Transmission : Amphictyonie et objecteurs (prop. 24-25) -----------------------------------

static func shared_fragments(state: GameState) -> bool:
	return state.amph_on and full(state) and Amphictyony.level_sum(state, "ct_shared") > 0


static func on_transmit(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	if not full(state):
		return
	if state.amph_on and Amphictyony.is_member(state, eid) and (Amphictyony.banned(state, "ct_silence") or Amphictyony.banned(state, "ct_armed")):
		Amphictyony.on_atrocity(state, eid)
		Contact._stat(state, eid, "silence_broken", 1)
		added.append(state.add_chronicle("%s répond aux Lointains malgré la loi du Silence. L'Amphictyonie y voit une atrocité." % state.get_empire(eid).display_name()))


## Casus belli « Faire taire » (Wars._req_ok) : contre un empire qui transmet.
static func silence_casus(state: GameState, a: int, b: int) -> bool:
	return full(state) and a != b and Contact.transmitting(state, b) and not partners(state, b).has(a)


## But « Faire taire » appliqué : le Héraut du vaincu est démoli, la Transmission retombe.
static func silence(state: GameState, winner: int, loser: int) -> String:
	var p := Contact.heraut_planet(state, loser)
	if p >= 0:
		(state.colonies[p] as Colony).buildings.erase(Contact.heraut_building())
	Contact._stat(state, winner, "silenced", 1)
	return "son Héraut"


## L'IA est-elle objectrice face à une Transmission ?
static func objector(state: GameState, eid: int) -> bool:
	if state.amph_on and Amphictyony.is_member(state, eid) and Amphictyony.banned(state, "ct_armed"):
		return true
	if Contact.fears(state, eid) and Contact.route_count(state, eid) > 0:
		return true
	var oc := Contact.cfg("objectors")
	var pct := int(oc.get("credo_pct", 50)) if (oc.get("credos", []) as Array).has(Contact.credo(state, eid)) else int(oc.get("base_pct", 25))
	return Contact._h(state, ["objector", eid]) % 100 < pct


# --- Espionnage (prop. 23) ---------------------------------------------------------------------

static func spy_check(state: GameState, a: int, b: int, op_id: String) -> String:
	if not full(state) or not Contact.applies(state, a) or not Contact.applies(state, b):
		return "le Contact n'est pas en jeu (mode Complet)"
	match op_id:
		"copier_releves":
			if not has_own(state, b):
				return "il n'a pas capté le Signal"
			if holds(state, a, b):
				return "vous avez déjà son fragment"
		"fragment_empoisonne":
			if Contact.gauge(state, b) <= 0:
				return "il n'a rien déchiffré"
		"saboter_heraut":
			if not Contact.transmitting(state, b):
				return "il ne transmet pas"
	return ""


static func spy_apply(state: GameState, a: int, b: int, o: Dictionary) -> String:
	var be := state.get_empire(b)
	match String(o.get("id", "")):
		"copier_releves":
			give_fragment(state, b, a)
			return "nous avons copié les relevés du Signal de %s : son fragment est à nous." % be.display_name()
		"fragment_empoisonne":
			Contact.sub(state, "gauge")[str(b)] = maxi(0, Contact.gauge(state, b) - 100)
			return "un faux fragment est parvenu à %s : son déchiffrement recule de 10 %%." % be.display_name()
		"saboter_heraut":
			var t := Contact.tx(state, b)
			var cut := 90 + Contact._h(state, ["sab", a, b, state.tick]) % 91
			t["prog"] = maxi(0, int(t.get("prog", 0)) - cut)
			t["start"] = int(t.get("start", 0)) + cut
			return "le Héraut de %s a sauté : sa Transmission perd %s." % [be.display_name(), Victory._days_text(cut)]
	return ""


# --- Commandes ---------------------------------------------------------------------------------

static func pending_offers(state: GameState, eid: int) -> Array:
	return Contact.sub(state, "offers").get(str(eid), [])


static func _has_offer(state: GameState, to: int, kind: String, from: int) -> bool:
	for o: Dictionary in pending_offers(state, to):
		if String(o["kind"]) == kind and int(o["from"]) == from:
			return true
	return false


## "?" : acte inconnu ici (Contact passe la main à ContactVoices).
static func check(state: GameState, eid: int, act: String, d: Dictionary) -> String:
	var t := int(d.get("to", -1))
	match act:
		"frag_give", "frag_trade", "frag_demand":
			if not full(state):
				return "seulement en mode Complet"
			var w := _ok_pair(state, eid, t)
			if w != "":
				return w
			if no_trade(state, eid) or no_trade(state, t):
				return "les Kh'thari ne négocient pas leur fragment"
			if act != "frag_demand" and not has_own(state, eid):
				return "vous n'avez pas encore capté le Signal"
			if act != "frag_give" and not has_own(state, t):
				return "il n'a pas capté le Signal"
			if act == "frag_give" and holds(state, t, eid):
				return "il a déjà votre fragment"
			if act != "frag_give" and holds(state, eid, t):
				return "vous avez déjà son fragment"
			if _has_offer(state, t, act, eid):
				return "offre déjà faite"
			return ""
		"cons_invite":
			if not full(state):
				return "seulement en mode Complet"
			var w2 := _ok_pair(state, eid, t)
			if w2 != "":
				return w2
			if no_trade(state, eid) or no_trade(state, t):
				return "les Kh'thari n'entrent dans aucun Consortium"
			if not has_own(state, eid) or not has_own(state, t):
				return "il faut que les deux aient capté le Signal"
			if cons_id(state, eid) >= 0 and cons_id(state, eid) == cons_id(state, t):
				return "déjà ensemble"
			if cons_id(state, t) >= 0 and cons_id(state, eid) >= 0:
				return "il est déjà dans un autre Consortium"
			var cid := cons_id(state, eid) if cons_id(state, eid) >= 0 else cons_id(state, t)
			if members(state, cid).size() >= Contact.c_int("consortium", "max_members", 4):
				return "Consortium complet"
			if Contact.done(state, t) or Contact.failed(state, t) or (Contact.transmitting(state, t) and cons_id(state, t) < 0):
				return "il a déjà répondu seul"
			if _has_offer(state, t, act, eid):
				return "offre déjà faite"
			return ""
		"cons_leave":
			if cons_id(state, eid) < 0:
				return "vous n'êtes dans aucun Consortium"
			return ""
		"accept", "decline":
			if not _has_offer(state, eid, String(d.get("kind", "")), int(d.get("from", -1))):
				return "aucune offre de ce genre"
			return ""
		"dark_forest":
			return check_dark_forest(state, eid, t)
	return "?"


static func apply(state: GameState, eid: int, act: String, d: Dictionary, added: Array[Dictionary]) -> bool:
	var t := int(d.get("to", -1))
	match act:
		"frag_give":
			give_fragment(state, eid, t)
			added.append(state.add_chronicle("%s offre son fragment du Signal à %s." % [state.get_empire(eid).display_name(), state.get_empire(t).short_name()], Espionage.public_to(state, [eid, t])))
		"frag_trade", "frag_demand", "cons_invite":
			var te := state.get_empire(t)
			if te.is_ai():
				if ai_accepts(state, t, eid, {"frag_trade": "trade", "frag_demand": "demand", "cons_invite": "cons"}[act]):
					_settle(state, act, eid, t, added)
				else:
					added.append(state.add_chronicle("%s refuse l'offre de %s au sujet du Signal." % [te.display_name(), state.get_empire(eid).short_name()], Espionage.private_to(state, [eid, t])))
			else:
				var l: Array = pending_offers(state, t).duplicate()
				l.append({"kind": act, "from": eid})
				Contact.sub(state, "offers")[str(t)] = l
		"accept", "decline":
			var kind := String(d["kind"])
			var from := int(d["from"])
			var l2: Array = pending_offers(state, eid).duplicate()
			for i in l2.size():
				if String(l2[i]["kind"]) == kind and int(l2[i]["from"]) == from:
					l2.remove_at(i)
					break
			Contact.sub(state, "offers")[str(eid)] = l2
			if act == "accept" and check(state, from, kind, {"to": eid}) == "":
				_settle(state, kind, from, eid, added)
		"cons_leave":
			leave(state, eid, added)
		"dark_forest":
			dark_forest(state, eid, t, added)
		_:
			return false
	return true


static func _settle(state: GameState, act: String, a: int, b: int, added: Array[Dictionary]) -> void:
	match act:
		"frag_trade":
			give_fragment(state, a, b)
			give_fragment(state, b, a)
			added.append(state.add_chronicle("%s et %s échangent leurs fragments du Signal." % [state.get_empire(a).display_name(), state.get_empire(b).short_name()], Espionage.public_to(state, [a, b])))
		"frag_demand":
			give_fragment(state, b, a)
			added.append(state.add_chronicle("%s cède son fragment du Signal à %s, qui l'exigeait." % [state.get_empire(b).display_name(), state.get_empire(a).short_name()], Espionage.public_to(state, [a, b])))
		"cons_invite":
			_join(state, a, b, added)


# --- IA de la course ---------------------------------------------------------------------------

## IA (AiContact) : échanges de fragments, Consortium avec un allié, objecteurs.
static func ai(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not full(state):
		return
	# Offres reçues : accepter si l'IA y consent.
	for o: Dictionary in pending_offers(state, e.id).duplicate():
		var kind := "trade" if String(o["kind"]) == "frag_trade" else ("demand" if String(o["kind"]) == "frag_demand" else "cons")
		var act := "accept" if ai_accepts(state, e.id, int(o["from"]), kind) else "decline"
		AiPlayer._issue(ctx, SimCommands.ct_act(e.id, act, {"kind": String(o["kind"]), "from": int(o["from"])}))
	if has_own(state, e.id):
		for oid in e.contacts:
			var other := state.get_empire(oid)
			if other == null or not other.is_ai():
				continue
			if Contact.check(state, e.id, "frag_trade", {"to": oid}) == "" and ai_accepts(state, e.id, oid, "trade"):
				if AiPlayer._issue(ctx, SimCommands.ct_act(e.id, "frag_trade", {"to": oid})):
					break
		if cons_id(state, e.id) < 0:
			for oid in e.contacts:
				if Diplomacy.allied(state, e.id, oid) and Contact.check(state, e.id, "cons_invite", {"to": oid}) == "":
					if AiPlayer._issue(ctx, SimCommands.ct_act(e.id, "cons_invite", {"to": oid})):
						break
	# Objecteurs : « Faire taire » contre un émetteur.
	if objector(state, e.id):
		for o in state.empires:
			if o.id == e.id or not Contact.transmitting(state, o.id) or not e.contacts.has(o.id) or Combat.at_war(state, e.id, o.id):
				continue
			if silence_casus(state, e.id, o.id):
				AiPlayer._issue(ctx, SimCommands.declare_war(e.id, o.id, "faire_taire", "faire_taire"))
				break


static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	if not full(state):
		return
	_pull(state, added)
	# Les offres à un empire qui a disparu tombent.
	for k in Contact.sub(state, "offers").keys():
		var l: Array = Contact.sub(state, "offers")[k]
		Contact.sub(state, "offers")[k] = l.filter(func(o: Dictionary) -> bool: return not state.get_empire(int(o["from"])).eliminated)
	for k in Contact.sub(state, "echo_hit").keys():
		var l2: Array = Contact.sub(state, "echo_hit")[k]
		Contact.sub(state, "echo_hit")[k] = l2.filter(func(h: Dictionary) -> bool: return state.tick < int(h.get("until", 0)))
