class_name ContactVoices
extends RefCounted
## Les voix du Contact (lot 3, prop. 28, 32-33, 35-42) : le courant des Taiseux et les saboteurs, le
## Voyage des Cinq, les talents des huit peuples, les puissances anciennes (Ylm, Aster, Kheb), les
## crises appelées (l'Outre-Nuit, l'Hôte), les ponts (Partis, sensitifs, Précognition, Interprète,
## fois, Attendants) et les hauts faits. Voir Contact ; données : data/contact.json.
##
## Sous-états : "taiseux" {"eid": 0-100}, "voyage" {"eid": {"until", "heroes"}}, "incoming" {"k",
## "at", "by"} (crise en route), "scars" {"eid": [stabilité, jusqu'au]}, "faith_seen" {"foi": nature},
## "city_heraut" {"eid": 1}, "interp" {"eid": héros}, "ear_own" {"planète": propriétaire}.


static func t_int(state: GameState, eid: int, k: String) -> int:
	return Contact.t_int(state, eid, k)


# --- Talents de peuple (prop. 36) --------------------------------------------------------------

## Chantier d'Oreille plus court (Ossarane).
@warning_ignore("integer_division")
static func build_days(state: GameState, eid: int, bid: String, days: int) -> int:
	if bid == Contact.ear_building() and t_int(state, eid, "ear_build_pct") != 0:
		return maxi(1, days * (100 + t_int(state, eid, "ear_build_pct")) / 100)
	return days


## Oreilles en plus : fiefs de la Bordure (Ossarane, une demi-Oreille chacun), flotte-ville (Ferrocornes).
static func extra_ears(state: GameState, eid: int) -> int:
	var n := 0
	if t_int(state, eid, "fief_ear") > 0:
		var edge := 0
		var seen := {}
		for pid in state.sorted_colony_ids():
			var c: Colony = state.colonies[pid]
			if c.owner != eid:
				continue
			var sid := state.galaxy.get_planet(int(pid)).system_id
			if Contact.is_edge(state, sid) and not seen.has(sid):
				seen[sid] = true
				edge += 1
		@warning_ignore("integer_division")
		n += edge / 2
	if t_int(state, eid, "city_ear") > 0 and Contact.listens(state, eid):
		var f := FactionTraits.city_fleet(state, eid)
		if f != null and not f.is_moving() and not Contact.deaf(state, f.system_id):
			n += 1
	return n


## Kheb : ses tombeaux abritent des Échos fossiles (prop. 37).
static func kheb_sites(state: GameState) -> Array[int]:
	var out: Array[int] = []
	if state.ancients.is_empty():
		return out
	var id := Ancients.id_of_kind(state, String(Contact.cfg("ancients").get("kheb", "kheb")))
	if id < 0:
		return out
	for sid in Ancients.systems_of(state, id):
		out.append(sid)
	return out


## Fausses alertes en plus : le chant des Murmurants chez leurs voisins.
static func extra_alerts(state: GameState, eid: int) -> int:
	var e := state.get_empire(eid)
	for o in state.empires:
		if o.id != eid and t_int(state, o.id, "alert_neighbors") > 0 and e.contacts.has(o.id):
			return 1
	return 0


@warning_ignore("integer_division")
static func gauge_pct_parts(state: GameState, eid: int) -> Array:
	var out := []
	if t_int(state, eid, "exalted_pct") > 0 and FactionTraits.is_exalted(state, eid):
		out.append(["Exaltation", t_int(state, eid, "exalted_pct")])
	if t_int(state, eid, "per_species_pct") > 0:
		var n := Peoples.empire_counts(state, eid).size() if state.peoples_on else 1
		out.append(["Espèces (%d)" % n, mini(n * t_int(state, eid, "per_species_pct"), t_int(state, eid, "species_max"))])
	if t_int(state, eid, "per_colony_pct") > 0:
		var c := 0
		for pid in state.sorted_colony_ids():
			if (state.colonies[pid] as Colony).owner == eid:
				c += 1
		out.append(["Nœuds reliés (%d)" % c, mini(c * t_int(state, eid, "per_colony_pct"), t_int(state, eid, "colony_max"))])
	var br := Contact.cfg("bridges")
	if not state.psionics.is_empty() and Psionics.awake(state, eid):
		out.append(["Sensitifs éveillés", int(br.get("dream_pct", 10))])
	if not interpreter(state, eid).is_empty():
		out.append(["Interprète", int(br.get("interp_pct", 15))])
	return out


# --- Couches, Porteuse, fois (prop. 35, 40) ----------------------------------------------------

static func on_layer(state: GameState, eid: int, _id: String, _added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	if t_int(state, eid, "layer_fervor") > 0 and FactionTraits.has_fervor(e.faction()):
		e.fervor += t_int(state, eid, "layer_fervor")
	if _id == "echo":
		_precog(state, eid)


## Première Porteuse : chaque foi y voit une révélation, une hérésie ou une épreuve (prop. 40).
static func on_porteuse(state: GameState, _eid: int, added: Array[Dictionary]) -> void:
	if not state.faith_on:
		return
	var fc := Contact.cfg("faiths")
	var kinds: Array = fc.get("kinds", ["revelation", "heresie", "epreuve"])
	var labels := {"revelation": "une révélation", "heresie": "une hérésie", "epreuve": "une épreuve"}
	for fid in Faiths.ids(state):
		var k := String(kinds[Contact._h(state, ["faith", String(fid)]) % kinds.size()])
		Contact.sub(state, "faith_seen")[String(fid)] = k
		var z := int(fc.get("zeal", 10))
		if k == "revelation":
			FaithWars.add_zeal(state, String(fid), z)
		elif k == "heresie":
			FaithWars.add_zeal(state, String(fid), -z)
		added.append(state.add_chronicle("%s voit dans le Signal %s." % [String(Faiths.faith(state, String(fid)).get("name", fid)), labels.get(k, k)]))


static func faith_reaction(state: GameState, eid: int) -> String:
	if not state.faith_on:
		return ""
	return String(Contact.sub(state, "faith_seen").get(Faiths.state_faith(state, eid), ""))


## Précognition : on sait si les Lointains sont des Revenants (prop. 39).
static func _precog(state: GameState, eid: int) -> void:
	var t := String(Contact.cfg("bridges").get("precog_tech", "precognition"))
	var e := state.get_empire(eid)
	if not e.techs.has(t) or Contact.nature_mode(state) == "sans_indices" or Contact.sub(state, "st").get(str(eid), {}).has("precog"):
		return
	Contact._stat(state, eid, "precog", 1)
	if Contact.nature(state) == "revenants":
		Contact.eliminate(state, eid, 0, true)
	else:
		var el: Array = Contact.sub(state, "elim").get(str(eid), []).duplicate()
		if not el.has("revenants"):
			el.append("revenants")
		Contact.sub(state, "elim")[str(eid)] = el


# --- Aster et Ylm (prop. 37) -------------------------------------------------------------------

static func aster_id(state: GameState) -> int:
	if state.ancients.is_empty():
		return -1
	return Ancients.id_of_kind(state, String(Contact.cfg("ancients").get("aster", "bibliotheque")))


static func aster_key(state: GameState, eid: int) -> bool:
	return Contact.sub(state, "st").get(str(eid), {}).has("aster_key")


static func check_aster(state: GameState, eid: int) -> String:
	var id := aster_id(state)
	if id < 0:
		return "la Grande Bibliothèque d'Aster n'est pas dans cette galaxie"
	if not Ancients.in_contact(state, id, eid):
		return "il faut avoir rencontré la Bibliothèque"
	if aster_key(state, eid):
		return "elle vous l'a déjà prêtée"
	if Ancients.opinion(state, id, eid) < Contact.c_int("ancients", "aster_opinion", 0):
		return "la Bibliothèque ne vous fait pas confiance"
	if not Contact.has_layer(state, eid, "plans"):
		return "il faut d'abord les Plans"
	if not Economy.can_afford(state.get_empire(eid), Contact.cfg("ancients").get("aster_cost", {})):
		return "requête trop chère (%s)" % GameData.format_amounts(Contact.cfg("ancients").get("aster_cost", {}))
	return ""


static func _ylm_anger(state: GameState, eid: int) -> void:
	if state.ancients.is_empty():
		return
	var id := Ancients.id_of_kind(state, String(Contact.cfg("ancients").get("ylm", "conservatoire")))
	if id >= 0:
		Ancients.add_op(state, id, eid, -Contact.c_int("ancients", "anger", 20))


# --- Taiseux et saboteurs (prop. 28, 32) -------------------------------------------------------

static func taiseux(state: GameState, eid: int) -> int:
	return int(Contact.sub(state, "taiseux").get(str(eid), 0))


static func no_debate(state: GameState, eid: int) -> bool:
	return (Contact.cfg("taiseux").get("no_debate", []) as Array).has(Rulers.government(state, eid))


## Les Taiseux tiennent-ils le pouvoir ? Une théocratie suit sa foi, une ruche ou une conscience ne débat pas.
static func silenced(state: GameState, eid: int) -> bool:
	if not Contact.full(state):
		return false
	if no_debate(state, eid):
		return Rulers.government(state, eid) == "theocratie" and faith_reaction(state, eid) == "heresie"
	return taiseux(state, eid) >= Contact.c_int("taiseux", "block_at", 60)


static func _tick_taiseux(state: GameState, eid: int) -> void:
	if no_debate(state, eid):
		Contact.sub(state, "taiseux").erase(str(eid))
		return
	var tc := Contact.cfg("taiseux")
	var target := Contact.layers(state, eid) * int(tc.get("per_layer", 10))
	if Contact.fears(state, eid) and Contact.layers(state, eid) > 0:
		target += int(tc.get("worry", 15))
	if not Contact.sub(state, "echo_hit").get(str(eid), []).is_empty():
		target += 5
	var speed := 1 + int((tc.get("credos", {}) as Dictionary).get(Contact.credo(state, eid), 0))
	var v := taiseux(state, eid)
	if v < target:
		v = mini(target, v + speed)
	else:
		v = maxi(target, v - int(tc.get("decay", 1)))
	Contact.sub(state, "taiseux")[str(eid)] = clampi(v, 0, 100)


## Chaque année de Transmission, un attentat possible (prop. 32).
static func _saboteurs(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var t := Contact.tx(state, eid)
	if t.is_empty() or (state.tick - int(t.get("start", 0))) % 360 >= Contact.month_days() or state.tick == int(t.get("start", 0)):
		return
	var sc := Contact.cfg("saboteurs")
	@warning_ignore("integer_division")
	var pct := taiseux(state, eid) * int(sc.get("pct_per_taiseux", 3)) / 10
	if Stability.empire_value(state, eid) >= int(sc.get("safe_stab", 60)):
		@warning_ignore("integer_division")
		pct /= 2
	if pct <= 0 or Contact._h(state, ["sabo", eid, state.tick]) % 100 >= pct:
		return
	var lo := int(sc.get("delay_min", 90))
	var cut := lo + Contact._h(state, ["sabo_d", eid, state.tick]) % maxi(1, int(sc.get("delay_max", 180)) - lo + 1)
	t["prog"] = maxi(0, int(t.get("prog", 0)) - cut)
	t["start"] = int(t.get("start", 0)) + cut
	Contact._stat(state, eid, "sabotaged", 1)
	added.append(state.add_chronicle("Attentat contre le Héraut de %s : des Taiseux ont fait sauter une salle d'émission. La Transmission perd %s." % [state.get_empire(eid).display_name(), Victory._days_text(cut)],
			Espionage.public_to(state, [eid])))


static func transmit_block(state: GameState, eid: int) -> String:
	if silenced(state, eid):
		return "les Taiseux tiennent le pouvoir : votre peuple refuse de répondre" if not no_debate(state, eid) else "votre foi tient le Signal pour une hérésie"
	if not Contact.sub(state, "voyage").get(str(eid), {}).is_empty():
		return "le Voyage des Cinq est en cours"
	return ""


# --- Flotte-ville et Héraut mobile (Ferrocornes) -----------------------------------------------

static func city_heraut_system(state: GameState, eid: int) -> int:
	if not Contact.sub(state, "city_heraut").has(str(eid)):
		return -1
	var f := FactionTraits.city_fleet(state, eid)
	return f.system_id if f != null else -1


## La flotte-ville doit rester à l'arrêt pendant la Transmission.
static func tx_paused(state: GameState, eid: int) -> bool:
	if Contact.heraut_planet(state, eid) >= 0 or not Contact.sub(state, "city_heraut").has(str(eid)):
		return false
	var f := FactionTraits.city_fleet(state, eid)
	return f != null and f.is_moving()


static func check_mount(state: GameState, eid: int) -> String:
	if t_int(state, eid, "city_heraut") <= 0:
		return "seule une flotte-ville peut porter le Héraut"
	if FactionTraits.city_fleet(state, eid) == null:
		return "vous n'avez plus de flotte-ville"
	if Contact.sub(state, "city_heraut").has(str(eid)) or Contact.heraut_planet(state, eid) >= 0:
		return "vous avez déjà un Héraut"
	if not Contact.has_layer(state, eid, "plans"):
		return "il faut avoir déchiffré les Plans"
	if not Economy.can_afford(state.get_empire(eid), GameData.building(Contact.heraut_building()).get("cost", {})):
		return "pas assez de ressources"
	return ""


# --- Interprète (prop. 40) ---------------------------------------------------------------------

static func interpreter(state: GameState, eid: int) -> Dictionary:
	var hid := int(Contact.sub(state, "interp").get(str(eid), -1))
	if hid < 0:
		return {}
	for h in Heroes.council(state, eid):
		if int(h["id"]) == hid:
			return h
	return {}


## Lecture menace sans perte d'opinion : un Interprète très loyal.
static func calm_reader(state: GameState, eid: int) -> bool:
	var h := interpreter(state, eid)
	return not h.is_empty() and int(h.get("loy", 50)) >= Contact.c_int("bridges", "interp_loyal", 70)


# --- Le Voyage des Cinq (prop. 33) -------------------------------------------------------------

@warning_ignore("integer_division")
static func voyage_cost(state: GameState, eid: int) -> Dictionary:
	var out := {}
	var c: Dictionary = Contact.cfg("voyage").get("cost", {})
	for r in c:
		out[r] = int(c[r]) * (100 + t_int(state, eid, "voyage_cost_pct")) / 100
	return out


static func voyage_heroes(state: GameState, eid: int) -> Array[int]:
	var out: Array[int] = []
	for h in Heroes.council(state, eid):
		if out.size() < Contact.c_int("voyage", "five", 5):
			out.append(int(h["id"]))
	out.sort()
	return out


static func check_voyage(state: GameState, eid: int) -> String:
	if Contact.done(state, eid) or Contact.failed(state, eid):
		return "votre empire a déjà répondu"
	if not Contact.has_layer(state, eid, "plans"):
		return "il faut avoir déchiffré les Plans"
	if Contact.transmitting(state, eid):
		return "la Transmission est en cours"
	if not Contact.sub(state, "voyage").get(str(eid), {}).is_empty():
		return "la Machine est déjà partie"
	if voyage_heroes(state, eid).size() < Contact.c_int("voyage", "min_heroes", 3):
		return "il faut au moins %d héros au Conseil" % Contact.c_int("voyage", "min_heroes", 3)
	if not Economy.can_afford(state.get_empire(eid), voyage_cost(state, eid)):
		return "la Machine coûte %s" % GameData.format_amounts(voyage_cost(state, eid))
	return ""


static func start_voyage(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	Economy.pay(e, voyage_cost(state, eid))
	var hs := voyage_heroes(state, eid)
	var until := state.tick + Contact.c_int("voyage", "days", 720)
	for hid in hs:
		state.heroes[hid]["arrive"] = until
	Contact.sub(state, "voyage")[str(eid)] = {"until": until, "heroes": hs}
	Contact._stat(state, eid, "voyage", 1)
	state.relic_rev += 1
	added.append(state.add_chronicle("%s bâtit la Machine des Plans et y fait monter %d héros. Elle s'allume, et ils ne sont plus là. Retour prévu dans deux ans, si tout va bien." % [e.display_name(), hs.size()]))


static func _tick_voyage(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var v: Dictionary = Contact.sub(state, "voyage").get(str(eid), {})
	if v.is_empty() or state.tick < int(v.get("until", 0)):
		return
	Contact.sub(state, "voyage").erase(str(eid))
	var e := state.get_empire(eid)
	var n := Contact.nature(state)
	if n == "batisseurs" or n == "revenants":
		var gifts: Array = Contact.cfg("plans").get("gifts", [])
		if not gifts.is_empty():
			var have: Array = Contact.sub(state, "gifts").get(str(eid), []).duplicate()
			have.append(String(gifts[Contact._h(state, ["voyage_gift", eid]) % gifts.size()]["id"]))
			Contact.sub(state, "gifts")[str(eid)] = have
		Contact.sub(state, "done")[str(eid)] = state.tick
		for m in ContactRace.partners(state, eid):
			Contact.sub(state, "done")[str(m)] = state.tick
		Contact._stat(state, eid, "won", 1)
		state.relic_rev += 1
		added.append(state.add_chronicle("La Machine des Cinq se rallume : les héros de %s reviennent. Ils n'ont pas vieilli d'un jour et ne parlent pas tout à fait comme avant. Ils ont vu %s." % [e.display_name(), Contact.nature_label(n)]))
		return
	for hid in v.get("heroes", []):
		var h: Dictionary = state.heroes.get(int(hid), {})
		if not h.is_empty():
			Heroes.die(state, h, "perdu dans la Machine des Cinq", added)
	var vc := Contact.cfg("voyage")
	_scar(state, eid, int(vc.get("fail_stab", -15)), int(vc.get("fail_days", 1080)))
	added.append(state.add_chronicle("La Machine des Cinq de %s se rallume, vide. Puis elle se met à tourner toute seule, et ce n'est plus vers les étoiles qu'elle regarde." % e.display_name()))


static func _scar(state: GameState, eid: int, stab: int, days: int) -> void:
	var l: Array = Contact.sub(state, "scars").get(str(eid), []).duplicate()
	l.append([stab, state.tick + days])
	Contact.sub(state, "scars")[str(eid)] = l


# --- Crises appelées (prop. 38) ----------------------------------------------------------------

## Réponse à des Affamés (l'Outre-Nuit, dans 3 ans) ou à des Semeurs sans audit (l'Hôte, tout de suite).
static func on_fail(state: GameState, eid: int, crisis: String, added: Array[Dictionary]) -> void:
	_ylm_anger(state, eid)
	if crisis == "":
		return
	var delay := Contact.c_int("crises", "delay_days", 1080) if crisis == "outre_nuit" else 0
	Contact.sub(state, "incoming")[crisis] = {"at": state.tick + delay, "by": eid}
	if delay <= 0:
		_tick_crises(state, added)


static func _summon(state: GameState, k: String, by: int, added: Array[Dictionary]) -> bool:
	if not Crisis.enabled(state) or not Crisis.cur(state).is_empty() or (state.crisis.get("done", []) as Array).has(k) or Crisis.kind_def(k).is_empty():
		return false
	var target := by
	var marked := ContactRace.marked_target(state)
	if k == "outre_nuit" and marked >= 0 and t_int(state, marked, "kin_affames") == 0:
		target = marked
	elif k == "outre_nuit" and t_int(state, by, "kin_affames") > 0:
		for o in state.empires:  # l'Essaim passe en dernier
			if o.id != by and not o.is_npc() and not o.eliminated:
				target = o.id
				break
	state.crisis["summoner"] = target
	Crisis.begin(state, k, added)
	return true


static func _tick_crises(state: GameState, added: Array[Dictionary]) -> void:
	var inc := Contact.sub(state, "incoming")
	for k in inc.keys():
		if k == "survive":
			continue
		var d: Dictionary = inc[k]
		if state.tick < int(d.get("at", 0)):
			continue
		var by := int(d.get("by", -1))
		inc.erase(k)
		if _summon(state, String(k), by, added):
			if String(k) == "outre_nuit":
				inc["survive"] = {"by": by}
		else:
			var cc := Contact.cfg("crises")
			_scar(state, by, int(cc.get("fallback_stab", -20)), int(cc.get("fallback_days", 1800)))
			added.append(state.add_chronicle("Ce qui a répondu à %s ne vient pas en flotte : il vient en cauchemars, en pannes et en peur. Le peuple ne dort plus." % state.get_empire(by).display_name()))
	# « On vous avait dit de ne pas répondre » : l'émetteur a survécu à l'Outre-Nuit.
	var sv: Dictionary = inc.get("survive", {})
	if not sv.is_empty() and Crisis.cur(state).is_empty():
		inc.erase("survive")
		var e := state.get_empire(int(sv.get("by", -1)))
		if e != null and not e.eliminated:
			Contact._stat(state, e.id, "survived", 1)


# --- Stabilité ---------------------------------------------------------------------------------

static func stability_parts(state: GameState, eid: int) -> Array:
	var out := []
	var s := 0
	for x in Contact.sub(state, "scars").get(str(eid), []):
		if state.tick < int(x[1]):
			s += int(x[0])
	if s != 0:
		out.append(["Ce qui a répondu", s])
	# Les Attendants : une guerre « Faire taire » en cours contre un émetteur.
	if state.wars_on and Contact.full(state):
		for k in (state.wars.get("list", {}) as Dictionary):
			var rec: Dictionary = state.wars["list"][k]
			if int(rec["a"]) == eid and String(rec.get("cb", "")) == "faire_taire" and Contact.transmitting(state, int(rec["b"])):
				out.append(["Les Attendants sabotent la guerre", Contact.c_int("attendants", "stab", -3)])
				break
	if silenced(state, eid) and Contact.transmitting(state, eid):
		out.append(["Les Taiseux contre la Transmission", -5])
	return out


# --- Amphictyonie : poids des Murmurants, refus du Chœur ---------------------------------------

static func _silence_prop(p: Dictionary) -> bool:
	return String(p.get("kind", "")) == "step" and String(p.get("fam", "")) == "signal" and int(p.get("to", 0)) < int(p.get("from", 0))


static func silence_weight(state: GameState, eid: int, p: Dictionary, v: int, w: int) -> int:
	if v != 0 and _silence_prop(p) and t_int(state, eid, "silence_weight") > 1:
		return w * t_int(state, eid, "silence_weight")
	return w


static func silence_vote_block(state: GameState, eid: int, p: Dictionary) -> String:
	if _silence_prop(p) and t_int(state, eid, "no_silence") > 0:
		return "le dieu-machine veut entendre : le Chœur ne vote jamais le Silence"
	return ""


# --- Fragments : vol à la prise (Kh'thari), lettre des Partis (prop. 36, 39) -------------------

static func _tick_ear_owners(state: GameState) -> void:
	var own := Contact.sub(state, "ear_own")
	var b := Contact.ear_building()
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if not c.buildings.has(b):
			own.erase(str(pid))
			continue
		var was := int(own.get(str(pid), c.owner))
		if was != c.owner and t_int(state, c.owner, "steal_on_capture") > 0:
			ContactRace.give_fragment(state, was, c.owner)
		own[str(pid)] = c.owner


## Lettre glissée dans le Signal par un peuple parti (Transcendance, issue Départ).
static func letter(state: GameState) -> bool:
	return not state.transcendence.is_empty() and TranscendenceWorld.has_partis(state)


# --- Commandes ---------------------------------------------------------------------------------

static func check(state: GameState, eid: int, act: String, d: Dictionary) -> String:
	match act:
		"voyage":
			return check_voyage(state, eid)
		"aster":
			return check_aster(state, eid)
		"mount_heraut":
			return check_mount(state, eid)
		"interpreter":
			var hid := int(d.get("hero", -1))
			for h in Heroes.council(state, eid):
				if int(h["id"]) == hid:
					return ""
			return "il faut un héros du Conseil"
	return "action inconnue"


static func apply(state: GameState, eid: int, act: String, d: Dictionary, added: Array[Dictionary]) -> void:
	match act:
		"voyage":
			start_voyage(state, eid, added)
		"aster":
			Economy.pay(state.get_empire(eid), Contact.cfg("ancients").get("aster_cost", {}))
			Contact._stat(state, eid, "aster_key", 1)
			state.relic_rev += 1
			added.append(state.add_chronicle("La Grande Bibliothèque d'Aster prête à %s la clé de l'Abécédaire. Elle la reprendra ; elle reprend toujours ce qu'elle prête." % state.get_empire(eid).display_name(),
					Espionage.private_to(state, [eid])))
		"mount_heraut":
			Economy.pay(state.get_empire(eid), GameData.building(Contact.heraut_building()).get("cost", {}))
			Contact.sub(state, "city_heraut")[str(eid)] = 1
			state.relic_rev += 1
		"interpreter":
			Contact.sub(state, "interp")[str(eid)] = int(d["hero"])
			state.relic_rev += 1


static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	_tick_ear_owners(state)
	for e in state.empires:
		if not Contact.applies(state, e.id):
			continue
		if t_int(state, e.id, "dream_route") > 0 and Contact.listens(state, e.id):
			Contact.add_route(state, e.id, "dream", added)
		if letter(state) and Contact.listens(state, e.id):
			Contact.add_route(state, e.id, "letter", added)
		if Contact.full(state):
			_tick_taiseux(state, e.id)
			_saboteurs(state, e.id, added)
		_tick_voyage(state, e.id, added)
		if Contact.transmitting(state, e.id) and Contact.stat(state, e.id, "ylm") == 0:
			Contact._stat(state, e.id, "ylm", 1)
			_ylm_anger(state, e.id)
	_tick_crises(state, added)
