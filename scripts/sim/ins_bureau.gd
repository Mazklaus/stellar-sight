class_name InsBureau
extends RefCounted
## Bureau des Affaires Courantes (props 42 à 47 ; voir Insolites, data/insolites.json "bureau").
## Le Bureau publie des Normes (catalogue ouvert, en données) : deux au départ, une de plus tous les
## quatre ans. Tout empire qui l'a rencontré peut en signer une : il gagne son petit avantage et verse au
## Bureau une redevance mensuelle. Ne pas signer, c'est la Non-conformité : commerce et chantiers
## ralentis, d'autant plus qu'il y a de signataires. Le Bureau pose des Guichets (implants) chez les
## signataires avec qui il commerce. Il ne déclare jamais de guerre : il adresse une Mise en demeure à
## un non-conforme ; six mois plus tard, si rien n'a changé et que les signataires l'emportent, une
## Procédure sanctionne (revenus -10 % pendant deux ans) et les Huissiers (sa flotte) troublent les
## systèmes du sanctionné. Chaque nouvelle colonie du Bureau attend un an son dossier ; en échange,
## capacité administrative très haute et aucune corruption (talent de gouvernement, data/administration).
## Le Bureau perd parfois un dossier. Victoire : l'Administration totale.
##
## État (Insolites.emp) : "norms": [publiées], "pub_next": jour, "sign": {"eid": [normes signées]},
## "summon": {"eid": échéance}, "sanc": {"eid": fin}, "dossier": numéro du prochain formulaire.


static func _c(key: String, def := 0) -> int:
	return Insolites.c_int("bureau", key, def)


static func norm_defs() -> Array:
	return Insolites.cfg("bureau").get("norms", [])


static func norm_def(id: String) -> Dictionary:
	for n: Dictionary in norm_defs():
		if String(n["id"]) == id:
			return n
	return {}


static func found(state: GameState, _e: Empire, _sid: int, ed: Dictionary) -> void:
	var norms := []
	for n: Dictionary in norm_defs():
		if norms.size() < _c("start_norms", 2):
			norms.append(String(n["id"]))
	ed["norms"] = norms
	ed["pub_next"] = state.tick + _c("publish_every_days", 1440)
	ed["sign"] = {}
	ed["summon"] = {}
	ed["sanc"] = {}
	ed["dossier"] = 4812


## Les Bureaux de la partie (en général un seul).
static func bureaus(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for eid in Insolites.nomad_ids(state):
		if Insolites.kind(state, eid) == "bureau":
			out.append(eid)
	return out


static func published(state: GameState, b: int) -> Array:
	return Insolites.emp(state, b).get("norms", [])


static func signed(state: GameState, b: int, eid: int) -> Array:
	return (Insolites.emp(state, b).get("sign", {}) as Dictionary).get(str(eid), [])


## Normes publiées par b que eid n'a pas signées.
static func unsigned(state: GameState, b: int, eid: int) -> Array:
	var out := []
	var s := signed(state, b, eid)
	for n in published(state, b):
		if not s.has(n):
			out.append(n)
	return out


static func conforms(state: GameState, b: int, eid: int) -> bool:
	return unsigned(state, b, eid).is_empty()


static func signers_of(state: GameState, b: int, norm: String) -> int:
	var n := 0
	var sg: Dictionary = Insolites.emp(state, b).get("sign", {})
	for k in sg:
		var o := state.get_empire(int(k))
		if o != null and not o.eliminated and (sg[k] as Array).has(norm):
			n += 1
	return n


## Somme d'un effet des normes signées par un empire (tous Bureaux confondus).
static func norm_fx(state: GameState, eid: int, key: String) -> int:
	var n := 0
	for b in bureaus(state):
		for id in signed(state, b, eid):
			n += int(norm_def(String(id)).get("fx", {}).get(key, 0))
	return n


## Malus de Non-conformité (%, négatif) : pour chaque norme publiée et non signée, d'autant plus fort
## qu'elle a de signataires ; seulement chez qui a rencontré le Bureau.
static func nonconf_pct(state: GameState, eid: int) -> int:
	var pct := 0
	var e := state.get_empire(eid)
	if e == null or e.is_npc():
		return 0
	for b in bureaus(state):
		if b == eid or not e.contacts.has(b):
			continue
		for norm in unsigned(state, b, eid):
			pct += _c("nonconf_pct", -5) - _c("nonconf_per_signer", 1) * signers_of(state, b, String(norm))
	return maxi(_c("nonconf_max_pct", -25), pct)


static func sanctioned(state: GameState, eid: int) -> bool:
	for b in bureaus(state):
		if int((Insolites.emp(state, b).get("sanc", {}) as Dictionary).get(str(eid), 0)) > state.tick:
			return true
	return false


static func _form(state: GameState, b: int) -> String:
	var ed := Insolites.emp(state, b)
	ed["dossier"] = int(ed.get("dossier", 4812)) + 1 + posmod(state.tick, 97)
	var n := int(ed["dossier"])
	@warning_ignore("integer_division")
	return "%d %03d" % [n / 1000, n % 1000] if n >= 1000 else str(n)


# --- Ordres ---------------------------------------------------------------------------------------

static func check_sign(state: GameState, eid: int, b: int, norm: String) -> String:
	if Insolites.kind(state, b) != "bureau":
		return "aucun Bureau des Affaires Courantes"
	if b == eid:
		return "le Bureau ne se signe pas ses propres formulaires (il les tamponne)"
	var e := state.get_empire(eid)
	if e == null or e.is_npc() or not e.contacts.has(b):
		return "vous n'avez jamais rencontré le Bureau"
	if not published(state, b).has(norm):
		return "norme inconnue ou pas encore publiée"
	if signed(state, b, eid).has(norm):
		return "déjà signée (exemplaire jaune conservé)"
	return ""


static func sign(state: GameState, eid: int, b: int, norm: String, added: Array[Dictionary]) -> void:
	var sg: Dictionary = Insolites.emp(state, b)["sign"]
	var list: Array = (sg.get(str(eid), []) as Array).duplicate()
	list.append(norm)
	list.sort()
	sg[str(eid)] = list
	(Insolites.emp(state, b)["summon"] as Dictionary).erase(str(eid))
	added.append(state.add_chronicle("%s signe la norme « %s ». Votre adhésion a été enregistrée sous le numéro %s ; veuillez conserver ce numéro, il ne vous servira à rien." % [
			state.get_empire(eid).short_name(), String(norm_def(norm).get("label", norm)), _form(state, b)], Espionage.private_to(state, [eid, b])))


static func check_summon(state: GameState, b: int, target: int) -> String:
	if Insolites.kind(state, b) != "bureau":
		return "seul le Bureau adresse des Mises en demeure"
	var t := state.get_empire(target)
	if t == null or t.is_npc() or t.eliminated or target == b:
		return "destinataire inconnu"
	if not state.get_empire(b).contacts.has(target):
		return "le Bureau n'a pas l'adresse de cet empire"
	if conforms(state, b, target):
		return "cet empire est en règle"
	var ed := Insolites.emp(state, b)
	if int((ed["summon"] as Dictionary).get(str(target), 0)) > state.tick:
		return "une Mise en demeure est déjà en cours"
	if int((ed["sanc"] as Dictionary).get(str(target), 0)) > state.tick:
		return "cet empire est déjà sanctionné"
	return ""


static func summon(state: GameState, b: int, target: int, added: Array[Dictionary]) -> void:
	(Insolites.emp(state, b)["summon"] as Dictionary)[str(target)] = state.tick + _c("summon_days", 180)
	added.append(state.add_chronicle("MISE EN DEMEURE n° %s : %s est prié de se conformer aux normes en vigueur sous %d jours. Tout recours doit être déposé au guichet 12, ouvert le troisième mardi des années bissextiles." % [
			_form(state, b), state.get_empire(target).display_name(), _c("summon_days", 180)], Espionage.public_to(state, [b, target])))


# --- Chaque jour ----------------------------------------------------------------------------------

static func daily(state: GameState, eid: int, ed: Dictionary, month: bool, added: Array[Dictionary]) -> void:
	if state.tick >= int(ed.get("pub_next", 0)):
		ed["pub_next"] = state.tick + _c("publish_every_days", 1440)
		for n: Dictionary in norm_defs():
			if not (ed["norms"] as Array).has(String(n["id"])):
				(ed["norms"] as Array).append(String(n["id"]))
				added.append(state.add_chronicle("Le Bureau des Affaires Courantes publie la norme « %s ». %s Les non-signataires sont priés de se sentir en tort." % [
						String(n["label"]), String(n.get("text", ""))], Espionage.public_to(state, [eid])))
				break
	var summons: Dictionary = ed["summon"]
	var ks := summons.keys()
	ks.sort()
	for k in ks:
		if int(summons[k]) > state.tick:
			continue
		summons.erase(k)
		_procedure(state, eid, int(k), added)
	if month:
		_month(state, eid, ed, added)


## Échéance d'une Mise en demeure : les signataires votent la sanction.
static func _procedure(state: GameState, b: int, target: int, added: Array[Dictionary]) -> void:
	var t := state.get_empire(target)
	if t == null or t.eliminated or conforms(state, b, target):
		return
	var yes := 0
	var no := 0
	for o in state.empires:
		if o.id == b or o.id == target or o.is_npc() or o.eliminated or not o.contacts.has(b):
			continue
		if conforms(state, b, o.id):
			yes += 1
		else:
			no += 1
	if yes >= 1 and yes >= no:
		(Insolites.emp(state, b)["sanc"] as Dictionary)[str(target)] = state.tick + Insolites.tuned(state, b, "bureau", "sanction_days", _c("sanction_days", 720))
		added.append(state.add_chronicle("PROCÉDURE : par %d voix contre %d, les signataires sanctionnent %s (revenus %d %% pendant %d ans). Les Huissiers du Bureau sont en route, avec des formulaires en triple exemplaire." % [
				yes, no, t.display_name(), _c("sanction_income_pct", -10), _c("sanction_days", 720) / GameCalendar.DAYS_PER_YEAR], Espionage.public_to(state, [b, target])))
	else:
		added.append(state.add_chronicle("La Procédure contre %s est classée sans suite, faute de quorum (%d voix contre %d). Le Bureau ouvre un dossier sur le quorum." % [
				t.short_name(), yes, no], Espionage.public_to(state, [b, target])))


static func _month(state: GameState, b: int, ed: Dictionary, added: Array[Dictionary]) -> void:
	var e := state.get_empire(b)
	var sg: Dictionary = ed["sign"]
	var ks := sg.keys()
	ks.sort_custom(func(x, y): return int(x) < int(y))
	var guichets := Insolites.implants_of(state, b, "guichet").size()
	for k in ks:
		var o := state.get_empire(int(k))
		if o == null or o.eliminated:
			continue
		# Redevance : quelques crédits par norme signée.
		Insolites.learn(state, b, "learn_norm", (sg[k] as Array).size())  # Normes techniques
		var fee := mini((sg[k] as Array).size() * _c("fee", 2), maxi(0, int(o.resources.get("energy", 0))))
		if fee > 0:
			o.resources["energy"] = int(o.resources.get("energy", 0)) - fee
			e.resources["energy"] = int(e.resources.get("energy", 0)) + fee
		# Guichet : un comptoir chez un signataire avec qui le Bureau commerce.
		if guichets < _c("guichet_max", 12) and Diplomacy.has_trade(state, b, o.id):
			var best := -1
			for pid in state.sorted_colony_ids():
				var c: Colony = state.colonies[pid]
				if c.owner != o.id or not c.is_colony() or not c.is_established() or not Insolites.implant(state, int(pid), "guichet").is_empty():
					continue
				if best < 0 or c.population > (state.colonies[best] as Colony).population:
					best = int(pid)
			if best >= 0:
				Insolites.add_implant(state, best, "guichet", b)
				guichets += 1
	# Un dossier perdu (prop. 47).
	if posmod(hash([state.seed_value, state.tick, b, "dossier"]), 1000) < _c("lost_file_chance_pmille", 30):
		_lose_file(state, b, ed, added)


static func _lose_file(state: GameState, b: int, ed: Dictionary, added: Array[Dictionary]) -> void:
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == b and c.days_left > 0:
			c.days_left += 180
			added.append(state.add_chronicle("Le dossier de fondation de %s a été égaré entre deux services. Il faudra six mois de plus ; le Bureau a ouvert une enquête, sous le numéro %s." % [
					state.galaxy.get_planet(int(pid)).display_name(state.galaxy), _form(state, b)], Espionage.private_to(state, [b])))
			return
	var sg: Dictionary = ed["sign"]
	var ks := sg.keys()
	ks.sort_custom(func(x, y): return int(x) < int(y))
	for k in ks:
		var list: Array = sg[k]
		if list.is_empty():
			continue
		var lost := String(list[posmod(state.tick, list.size())])
		var nl := list.duplicate()
		nl.erase(lost)
		sg[k] = nl
		added.append(state.add_chronicle("Le Bureau a perdu la signature de %s sur la norme « %s ». Le signataire est prié de signer à nouveau, sans quoi il sera considéré comme n'ayant jamais signé, ce qui est techniquement exact." % [
				state.get_empire(int(k)).short_name(), String(norm_def(lost).get("label", lost))], Espionage.private_to(state, [b, int(k)])))
		return


## Huissiers : une flotte armée du Bureau à l'arrêt dans un système d'un empire sanctionné.
static func bailiffs(state: GameState, sid: int, owner: int) -> bool:
	if owner < 0 or not sanctioned(state, owner):
		return false
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.system_id == sid and not f.is_moving() and Insolites.kind(state, f.owner) == "bureau" and Combat.is_armed(f):
			return true
	return false


# --- Victoire : l'Administration totale (prop. 46) ---------------------------------------------------

static func victory(state: GameState, e: Empire, out: Dictionary) -> void:
	var total := 0
	var ok := 0
	for o in state.empires:
		if o.id == e.id or o.is_npc() or o.eliminated:
			continue
		total += 1
		if conforms(state, e.id, o.id):
			ok += 1
		else:
			out["lines"].append("%s : %d norme(s) à signer" % [o.short_name(), unsigned(state, e.id, o.id).size()])
	# Équilibrage, lot 6 : deux normes signées par tous ne font pas une galaxie administrée. Il faut un
	# vrai corpus (total_min_norms normes en vigueur), et chaque norme de plus se signe moins volontiers.
	var need := int(Insolites.cfg("bureau").get("total_min_norms", 0))
	var have := published(state, e.id).size()
	out["lines"].insert(0, "Empires en règle : %d / %d (normes en vigueur : %d sur %d requises)" % [ok, total, have, need])
	out["cond"] = total > 0 and ok >= total and have >= need
	Victory._timed(out, ok, maxi(1, total))


static func status_lines(state: GameState, eid: int, ed: Dictionary) -> Array[String]:
	var out: Array[String] = []
	out.append("Normes en vigueur : %d (prochaine publication dans %d jours)" % [(ed.get("norms", []) as Array).size(), maxi(0, int(ed.get("pub_next", 0)) - state.tick)])
	var conf := 0
	var tot := 0
	for o in state.empires:
		if o.id != eid and not o.is_npc() and not o.eliminated and o.contacts.has(eid):
			tot += 1
			if conforms(state, eid, o.id):
				conf += 1
	out.append("Empires en règle : %d / %d ; Guichets : %d" % [conf, tot, Insolites.implants_of(state, eid, "guichet").size()])
	var sc := 0
	for k in (ed.get("sanc", {}) as Dictionary):
		if int(ed["sanc"][k]) > state.tick:
			sc += 1
	if sc > 0 or not (ed.get("summon", {}) as Dictionary).is_empty():
		out.append("Mises en demeure en cours : %d ; empires sanctionnés : %d" % [(ed.get("summon", {}) as Dictionary).size(), sc])
	return out
