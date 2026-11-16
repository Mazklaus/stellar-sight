class_name RulersBridges
extends RefCounted
## Ponts du souverain avec les autres piliers (étude « Souverain et dynastie », bloc E, prop. 33-37).
## - Politique : l'archétype du souverain pousse son courant à la capitale ; le coup d'État installe un
##   usurpateur (légitimité 20) ; la crise de régime dépose un souverain peu légitime.
## - Religion : sacre (+10 de légitimité) pour le souverain d'une foi d'État dont l'empire tient un monde
##   saint ; la nature Ancêtres accueille chaque souverain mort ; funérailles qui prolongent les souvenirs.
## - Espionnage : assassiner le souverain, soutenir un prétendant, révéler une bâtardise.
## - Guerre : « Guerre de succession » (mariage, prétendant, usurpateur), but « Imposer un héritier ».
## - Hauts faits : un titre de haut fait devient un surnom du souverain régnant (voir Deeds._award) ;
##   la frise des règnes dans les Annales (écran Trône).

static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "ponts_souverain"] + parts))


## Légitimité en plus : sacre.
static func legit_bonus(state: GameState, eid: int) -> int:
	if crowned_by_faith(state, eid):
		return 10
	return 0


static func crowned_by_faith(state: GameState, eid: int) -> bool:
	if not state.faith_on or Faiths.state_faith(state, eid) == "":
		return false
	return DeedsEval._holy_held(state, eid) > 0


## Le souverain est-il chef de sa foi (Pontife d'une théocratie) ?
static func heads_faith(state: GameState, eid: int) -> bool:
	return Rulers.kind(state, eid) == "conclave" and state.faith_on and Faiths.state_faith(state, eid) != ""


# --- Mort, funérailles -------------------------------------------------------------------------

static func on_ruler_death(state: GameState, eid: int, r: Dictionary, how: String, killer: int, added: Array[Dictionary]) -> void:
	if how == "deposed" or how == "term" or how == "abdicate" or how == "seized":
		return
	# Nature Ancêtres, Martyr, rancunes : le souverain mort passe par les mêmes portes qu'un héros.
	var cls := String(Rulers.data()["aptitudes"][_best_apt(r)].get("cls", "orateur"))
	FaithNatures.on_hero_death(state, {"id": -1, "name": Rulers.full_name(state, eid, r), "owner": eid, "cls": cls, "lvl": 5, "traits": []}, killer, added)
	if killer >= 0 and killer != eid:
		for o in state.empires:
			if o.id != eid and o.id != killer and not o.eliminated and Diplomacy.allied(state, o.id, eid):
				Diplomacy.remember(state, o.id, killer, "hero_assassinated")


static func _best_apt(r: Dictionary) -> String:
	var best := "gestion"
	for a in Rulers.APTS:
		if int(r["apt"].get(a, 0)) > int(r["apt"].get(best, 0)):
			best = a
	return best


## Funérailles : elles prolongent les souvenirs des héros morts (credo).
static func on_funeral(state: GameState, eid: int) -> void:
	var m: Dictionary = state.hero_meta.get(eid, {})
	for mem: Dictionary in m.get("memorials", []):
		if int(mem["until"]) > state.tick:
			mem["until"] = int(mem["until"]) + 360


# --- Politique ---------------------------------------------------------------------------------

## Chaque mois : le courant de l'archétype gagne un peu à la capitale.
static func monthly(state: GameState, eid: int) -> void:
	var r := Rulers.ruler(state, eid)
	if r.is_empty() or not Politics.applies(state, eid):
		return
	var cur := String(Rulers.arch_def(String(r["arch"])).get("current", ""))
	var i := Politics.index_of(cur)
	var cap := FactionTraits.capital_system(state, eid)
	if i >= 0 and cap >= 0:
		Politics.push(state, cap, i, 1)


## Crise de régime (voir Grievances.crisis) : coup d'État = usurpateur ; sinon le souverain tombe s'il
## est peu légitime.
static func on_regime_crisis(state: GameState, eid: int, why: String, new_current: int, out: Array[Dictionary]) -> void:
	if not Rulers.mortal(state) or Rulers.immortal_kind(state, eid) or not Rulers.has_ruler(state, eid):
		return
	var coup := why.contains("coup")
	if not coup and Rulers.legitimacy(state, eid) >= 50:
		return
	var cur := Politics.current_id(new_current)
	var arch := Rulers._pick_arch(state, eid, ["coup", eid, state.tick], cur)
	var nr := Rulers.make_ruler(state, eid, ["coup", eid, state.tick], "usurpateur", -1, arch)
	Rulers.die(state, eid, "est renversé par %s" % ("un coup d'État" if coup else "la crise de régime"), out, "deposed", -1, nr)


# --- Guerre ------------------------------------------------------------------------------------

## Revendiquer coûte moins cher contre une Couronne vacillante.
static func wobbly_claim_pct(state: GameState, owner: int) -> int:
	if int(Rulers.entry(state, owner).get("wobbly", 0)) > state.tick:
		return Rulers.r_int("wobbly_war_cost_pct")
	return 0


static func wobbly(state: GameState, eid: int) -> bool:
	return int(Rulers.entry(state, eid).get("wobbly", 0)) > state.tick


## Motif de guerre de succession : mariage, prétendant né de notre empire, trône usurpé chez un voisin.
static func succession_casus(state: GameState, a: int, b: int) -> bool:
	var ea := Rulers.entry(state, a)
	var eb := Rulers.entry(state, b)
	if ea.is_empty() or eb.is_empty() or (eb["r"] as Dictionary).is_empty():
		return false
	if int(ea.get("spouse", -1)) == b:
		return true
	if int(eb.get("parent", -1)) == a:
		return true
	return String(eb["r"].get("how", "")) == "usurpateur" and Rulers.hereditary(state, a)


## But « Imposer un héritier » : un candidat de la maison du vainqueur monte sur le trône du vaincu.
static func impose_heir(state: GameState, winner: int, loser: int) -> void:
	var el := Rulers.entry(state, loser)
	if el.is_empty():
		return
	var added: Array[Dictionary] = []
	var r := Rulers.make_ruler(state, loser, ["impose", winner, loser, state.tick], "usurpateur")
	r["house"] = String(Rulers.entry(state, winner).get("house", ""))
	if Rulers.has_ruler(state, loser):
		Rulers.die(state, loser, "doit céder le trône au candidat du vainqueur", added, "deposed", -1, r)
	else:
		Rulers.crown(state, loser, r, added, false)
	el["parent"] = winner
	if state.vassals_on and not Vassals.is_subject(state, loser) and not Vassals.is_subject(state, winner):
		Vassals.bind(state, winner, loser, "vassal", Vassals.preset_clauses("vassal"), 40, true)
	Diplomacy.remember(state, winner, loser, "union")


# --- Espionnage --------------------------------------------------------------------------------

static func spy_check(state: GameState, _a: int, b: int, op_id: String) -> String:
	if state.rulers.is_empty():
		return "pas de souverain dans cette partie"
	if not Rulers.has_ruler(state, b):
		return "son trône est vacant"
	match op_id:
		"assassiner_souverain":
			if not Rulers.mortal(state) or Rulers.immortal_kind(state, b):
				return "son souverain ne peut pas mourir"
		"reveler_batardise":
			var hs := RulersDynasty.heirs(state, b)
			if hs.is_empty():
				return "il n'a pas d'héritier à salir"
			if int((hs[0] as Dictionary).get("bastard", 0)) > 0:
				return "le scandale a déjà éclaté"
	return ""


static func spy_apply(state: GameState, a: int, b: int, o: Dictionary) -> String:
	var added: Array[Dictionary] = []
	match String(o["id"]):
		"assassiner_souverain":
			var nm := Rulers.full_name(state, b)
			Rulers.die(state, b, "est assassiné", added, "murdered", a)
			return "%s est mort. Personne ne sait d'où venait le poison, et c'est très bien ainsi." % nm
		"soutenir_pretendant":
			Rulers.adjust(state, b, -15)
			var en := Rulers.entry(state, b)
			if int(en.get("low_since", 0)) > 0:
				en["low_since"] = int(en["low_since"]) - 180
			return "des pamphlets fleurissent pour un prétendant : la légitimité de %s tombe à %d." % [Rulers.full_name(state, b), Rulers.legitimacy(state, b)]
		"reveler_batardise":
			var hs := RulersDynasty.heirs(state, b)
			if not hs.is_empty():
				hs[0]["bastard"] = 1
				return "on murmure que %s n'est pas du sang de la maison %s. Les preuves sont fausses ; le doute, lui, est vrai." % [
						String(hs[0]["name"]), String(Rulers.entry(state, b).get("house", ""))]
	return "rien ne se passe."


static func spy_exposed(state: GameState, a: int, b: int, op_id: String, ok: bool) -> void:
	if op_id == "assassiner_souverain":
		Diplomacy.remember(state, b, a, "hero_assassinated")
		if ok:
			Diplomacy.remember(state, b, a, "war_crime")
	elif op_id == "reveler_batardise" and ok:
		var hs := RulersDynasty.heirs(state, b)
		if not hs.is_empty():
			hs[0].erase("bastard")
