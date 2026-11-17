class_name KardashevWorld
extends RefCounted
## Le mode Complète de l'échelle de Kardashev (voir Kardashev, data/kardashev.json) : prérogatives à
## chaque demi-palier (prop. 12, dormantes sous leur palier, prop. 24), rattrapage par l'Émulation
## (prop. 15), signature thermique, Sobriété et Voile stellaire (prop. 21-22), Âge sombre et Âge
## héroïque (prop. 25), Allumeur d'étoiles. Tout est déterministe (entiers, ordre des empires).


# --- Passages de palier ------------------------------------------------------------------------

## Après le calcul du mois : nouveaux demi-paliers (une prérogative à choisir par niveau atteint pour
## la première fois), Âge sombre quand on retombe sous son meilleur type, Âge héroïque quand on y revient.
static func on_update(state: GameState, eid: int, before: int, t: int, half_before: int, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	var hl := Kardashev.half_level(state, eid)
	if hl > half_before:
		var pend: Array = Kardashev.pending(state, eid).duplicate()
		for lv in range(half_before + 1, hl + 1):
			pend.append(lv)
		Kardashev.sub(state, "pend")[str(eid)] = pend
		Kardashev.sub(state, "half")[str(eid)] = hl
		Kardashev.touch(state)
		added.append(state.add_chronicle("%s atteint %s sur l'échelle de Kardashev : une prérogative est à choisir (écran des Victoires, onglet L'Échelle)." % [
				e.short_name(), Kardashev.value_text(int(Kardashev.data().get("levels", [100, 150, 200, 250, 300])[hl - 1]))], Espionage.private_to(state, [eid])))
	var best := Kardashev._gi(state, "best", eid)
	var dark := Kardashev.sub(state, "dark")
	if t < before and t < best and not dark.has(str(eid)):
		dark[str(eid)] = best
		Kardashev.touch(state)
		Announce.next(state, "kardashev", {"actor": eid})
		added.append(state.add_chronicle("%s retombe au type %s : c'est l'Âge sombre. On parle de l'ancien temps à voix basse, et les ingénieurs ressortent les vieux plans pour relever ce qui est tombé." % [
				e.short_name(), Kardashev.roman(t)]))
	elif dark.has(str(eid)) and t >= int(dark[str(eid)]):
		dark.erase(str(eid))
		var pend2: Array = Kardashev.pending(state, eid).duplicate()
		pend2.append(0)  # Âge héroïque : une prérogative de plus, au choix parmi les paliers atteints
		Kardashev.sub(state, "pend")[str(eid)] = pend2
		Kardashev.touch(state)
		Announce.next(state, "kardashev", {"actor": eid})
		added.append(state.add_chronicle("%s remonte au type %s : l'Âge sombre s'achève, et c'est un Âge héroïque. On en tirera une prérogative de plus, et beaucoup de chansons." % [
				e.short_name(), Kardashev.roman(t)]))


static func dark_age(state: GameState, eid: int) -> bool:
	return Kardashev.full(state) and Kardashev.sub(state, "dark").has(str(eid))


# --- Effets ------------------------------------------------------------------------------------

static func effects(state: GameState, eid: int, out: Dictionary) -> void:
	for pid in Kardashev.awake_perks(state, eid):
		var fx: Dictionary = Kardashev.perk_def(pid).get("fx", {})
		for k in fx:
			out[k] = int(out.get(k, 0)) + int(fx[k])
	if dark_age(state, eid):
		out["stability"] = int(out.get("stability", 0)) + Kardashev.c_int("dark", "stability", -2)


static func fx(state: GameState, eid: int, key: String) -> int:
	if not Kardashev.full(state) or eid < 0 or GameState.is_npc(eid):
		return 0
	return Research.fx_int(state, eid, key)


## Plancher de pénurie d'énergie (prérogative Réseau planétaire) : pénurie si le stock passe sous -n.
static func blackout_floor(state: GameState, eid: int) -> int:
	return fx(state, eid, "kard_blackout_floor")


## Archives de pierre : on ne vole pas les technologies de cet empire.
static func no_theft(state: GameState, eid: int) -> bool:
	return fx(state, eid, "kard_no_theft") > 0


## Techniquement immortels : les crises visent cet empire en dernier.
static func crisis_last(state: GameState, eid: int) -> bool:
	return fx(state, eid, "kard_crisis_last") > 0


## Réparations et relèvement des mégastructures pendant l'Âge sombre (pour cent ajouté).
static func repair_pct(state: GameState, eid: int) -> int:
	return Kardashev.c_int("dark", "repair_pct", -50) if dark_age(state, eid) else 0


# --- Émulation (prop. 15) ----------------------------------------------------------------------

## Rabais d'Émulation (pour cent, positif) sur le type t pour cet empire : un autre l'a franchi avant lui.
@warning_ignore("integer_division")
static func emulation_pct(state: GameState, eid: int, t: int) -> int:
	if not Kardashev.full(state) or Kardashev.tier(state, eid) >= t:
		return 0
	var order: Array = Kardashev.sub(state, "first").get(str(t), [])
	if order.is_empty():
		return 0
	var em := Kardashev.cfg("emulation")
	return mini(int(em.get("max_pct", 55)), int(em.get("base_pct", 25)) + (order.size() - 1) * int(em.get("per_empire_pct", 10)))


## Pour cent de coût d'une technologie (négatif = rabais).
static func tech_cost_pct(state: GameState, eid: int, tid: String) -> int:
	if not Kardashev.full(state):
		return 0
	var techs: Dictionary = Kardashev.cfg("emulation").get("techs", {})
	for t in techs:
		if (techs[t] as Array).has(tid):
			return -emulation_pct(state, eid, int(t))
	return 0


## Pour cent de coût d'une étape de mégastructure (négatif = rabais).
static func mega_cost_pct(state: GameState, eid: int, k: String) -> int:
	if not Kardashev.full(state):
		return 0
	var kinds: Dictionary = Kardashev.cfg("emulation").get("kinds", {})
	var era := int(Megastructures.kind_def(k).get("era", 1))
	for t in kinds:
		for x in kinds[t]:
			if String(x) == k or (String(x) == "*era4" and era >= 4):
				return -emulation_pct(state, eid, int(t))
	return 0


# --- Signature thermique (prop. 21-22) ----------------------------------------------------------

## Signature ×100 : l'indice, moins la Sobriété ; 0 sous le Voile stellaire.
static func signature(state: GameState, eid: int) -> int:
	if not Kardashev.full(state) or not Kardashev.applies(state, eid):
		return 0
	if veiled(state, eid):
		return 0
	var s := Kardashev.index100(state, eid)
	if Kardashev.sober(state, eid):
		s -= Kardashev.c_int("signature", "sober_minus", 50)
	return maxi(0, s)


static func veiled(state: GameState, eid: int) -> bool:
	return Kardashev._gi(state, "veil", eid) > state.tick


## Ce que la chaleur révèle de cet empire à tous : la capitale et les mégastructures (capital_at),
## puis tous les systèmes peuplés (all_at).
static func revealed_systems(state: GameState, eid: int) -> Array[int]:
	var out: Array[int] = []
	var s := signature(state, eid)
	if s < Kardashev.c_int("signature", "capital_at", 150):
		return out
	var seen := {}
	var cap := FactionTraits.capital_system(state, eid)
	if cap >= 0:
		seen[cap] = true
	if not state.megas.is_empty():
		for m in Megastructures.owned_by(state, eid):
			seen[int(m["s"])] = true
	if s >= Kardashev.c_int("signature", "all_at", 250):
		for pid in state.sorted_colony_ids():
			var c: Colony = state.colonies[pid]
			if c.owner == eid and c.is_colony():
				seen[state.galaxy.get_planet(pid).system_id] = true
	for sid in seen:
		out.append(int(sid))
	out.sort()
	return out


## Bonus de cible pour les crises (prop. 22) : plus la signature est forte, plus tôt on est visé.
## Négatif = visé plus tôt (le score de Crisis._target est « plus petit = préféré »).
@warning_ignore("integer_division")
static func crisis_score(state: GameState, eid: int) -> int:
	if not Kardashev.full(state):
		return 0
	if crisis_last(state, eid):
		return 50000
	return -signature(state, eid) * Kardashev.c_int("signature", "crisis_weight", 20) / 4  # type III : 1,5 saut


static func monthly(state: GameState, _added: Array[Dictionary]) -> void:
	# La chaleur trahit les puissants : chaque empire connaît leurs systèmes révélés.
	for e in state.empires:
		if e.is_npc() or e.eliminated:
			continue
		var sids := revealed_systems(state, e.id)
		if sids.is_empty():
			continue
		for o in state.empires:
			if o.id != e.id and not o.is_npc() and not o.eliminated:
				Intel.record_systems(state, o, sids)
	_relight(state, _added)


# --- Voile stellaire, Allumeur d'étoiles --------------------------------------------------------

static func check(state: GameState, eid: int, act: String, d: Dictionary) -> String:
	match act:
		"veil":
			if not Kardashev.awake(state, eid, "voile_stellaire"):
				return "il faut la prérogative Voile stellaire, éveillée"
			if veiled(state, eid):
				return "le Voile est déjà tiré"
			if Kardashev._gi(state, "veil_cd", eid) > state.tick:
				return "le Voile n'est pas encore prêt (%d jours)" % (Kardashev._gi(state, "veil_cd", eid) - state.tick)
			return ""
		"relight":
			if not Kardashev.awake(state, eid, "allumeur_etoiles"):
				return "il faut la prérogative Allumeur d'étoiles, éveillée"
			if Kardashev.sub(state, "relight").has(str(eid)):
				return "une étoile est déjà en train de se rallumer"
			var sid := int(d.get("s", -1))
			if sid < 0 or sid >= state.galaxy.systems.size():
				return "système inconnu"
			if state.system_owner(sid) != eid:
				return "il faut tenir ce système"
			var rl := Kardashev.cfg("relight")
			if not (rl.get("from", ["red", "white"]) as Array).has(star_type(state, sid)):
				return "seules une naine rouge ou une naine blanche se rallument"
			return ""
	return "action inconnue"


static func apply(state: GameState, eid: int, act: String, d: Dictionary, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	match act:
		"veil":
			Kardashev.sub(state, "veil")[str(eid)] = state.tick + Kardashev.c_int("signature", "veil_days", 120)
			Kardashev.sub(state, "veil_cd")[str(eid)] = state.tick + Kardashev.c_int("signature", "veil_cooldown", 360)
			added.append(state.add_chronicle("%s tire le Voile stellaire : sa chaleur s'éteint, et les télescopes voisins cherchent en vain où sont passés ses soleils." % e.short_name(),
					Espionage.private_to(state, [eid])))
		"relight":
			var sid := int(d["s"])
			Kardashev.sub(state, "relight")[str(eid)] = {"s": sid, "until": state.tick + Kardashev.c_int("relight", "days", 360)}
			added.append(state.add_chronicle("%s entreprend de rallumer l'étoile de %s. Les ingénieurs promettent une naine jaune dans un an ; les poètes, une aube éternelle." % [
					e.short_name(), state.galaxy.systems[sid].name], Espionage.private_to(state, [eid], sid)))


## Type d'étoile d'un système, avec les étoiles rallumées.
static func star_type(state: GameState, sid: int) -> String:
	if not state.kardashev.is_empty():
		var st: Dictionary = state.kardashev.get("stars", {})
		if st.has(str(sid)):
			return String(st[str(sid)])
	return state.galaxy.systems[sid].star_type


static func _relight(state: GameState, added: Array[Dictionary]) -> void:
	var rl := Kardashev.sub(state, "relight")
	var keys := rl.keys()
	keys.sort()
	for k in keys:
		var r: Dictionary = rl[k]
		if state.tick < int(r["until"]):
			continue
		rl.erase(k)
		var sid := int(r["s"])
		if state.system_owner(sid) != int(k):
			continue  # le système a changé de mains : le chantier est perdu
		Kardashev.sub(state, "stars")[str(sid)] = String(Kardashev.cfg("relight").get("to", "yellow"))
		Kardashev.touch(state)
		added.append(state.add_chronicle("L'étoile de %s se rallume : une naine jaune brille désormais là où couvait une braise. %s en tire déjà plus de lumière." % [
				state.galaxy.systems[sid].name, state.get_empire(int(k)).short_name()]))


# --- IA ----------------------------------------------------------------------------------------

## Une fois par mois (appelé par AiPlayer après AiMegas) : choisit ses prérogatives,
## la Sobriété en temps de crise, le Voile en guerre, rallume la première étoile possible.
static func ai(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not Kardashev.full(state) or not Kardashev.applies(state, e.id):
		return
	@warning_ignore("integer_division")
	var month := state.tick / int(GameData.rules()["month_days"]) + 1
	if Kardashev._gi(state, "ai", e.id) >= month:
		return
	Kardashev.sub(state, "ai")[str(e.id)] = month
	var off := Kardashev.offer(state, e.id)
	if not off.is_empty():
		var best := off[0]
		for pid in off:
			if int(Kardashev.perk_def(pid).get("ai", 9)) < int(Kardashev.perk_def(best).get("ai", 9)):
				best = pid
		AiPlayer._issue(ctx, SimCommands.kd_act(e.id, "perk", {"id": best}))
	if bool(Kardashev.cfg("ai").get("sober_in_crisis", true)):
		var want := Crisis.active(state) and Kardashev.index100(state, e.id) >= Kardashev.c_int("signature", "capital_at", 150)
		if want != Kardashev.sober(state, e.id):
			AiPlayer._issue(ctx, SimCommands.kd_act(e.id, "sober", {"on": want}))
	if not e.wars.is_empty() and Kardashev.check(state, e.id, "veil", {}) == "":
		AiPlayer._issue(ctx, SimCommands.kd_act(e.id, "veil"))
	if Kardashev.awake(state, e.id, "allumeur_etoiles") and not Kardashev.sub(state, "relight").has(str(e.id)) and not state.megas.is_empty():
		for m in Megastructures.owned_by(state, e.id):
			var sid := int(m["s"])
			if Kardashev.check(state, e.id, "relight", {"s": sid}) == "":
				AiPlayer._issue(ctx, SimCommands.kd_act(e.id, "relight", {"s": sid}))
				break
