class_name FaithNatures
extends RefCounted
## Les 9 natures classiques de foi (étude « Religion » v2, lot 3). Règles : bloc "classic" de
## data/faiths.json. Chaque nature a sa mécanique propre, en plus des doctrines et des préceptes :
##
## - Église universelle : Collège de 12 sièges achetés en influence, Primat élu tous les 10 ans (le
##   chef de foi), bulles de 5 ans, désir de réforme qui finit en schisme ;
## - Patriarcats : autorité patriarcale par empire (temples, monde saint, conversions forcées),
##   icônes de 20 ans, métropolite (petit monde saint) ;
## - Voie de la Loi et de l'Extase : piété de -100 à +100 par empire, bonus aux extrêmes, écoles ;
## - Roue du karma : karma de -100 à +100 par empire, l'équilibre est le meilleur état ;
## - Harmonie : harmonie de 0 à 100 par empire, harmonisation des fois présentes (préceptes en plus) ;
## - Panthéon : 4 dieux parmi 8 domaines, présages, dieux accueillis, apothéose des héros ;
## - Culte des ancêtres : héros morts devenus ancêtres (3 actifs), mausolée, profanation ;
## - Dette de sang : dette qui monte chaque mois, payée par le sang ;
## - Dieu présent : le dieu sur la carte, son dominion, sa mort et son retour.
##
## state.faiths["nat"] = {"emp": {empire (texte): {"karma", "piety", "school", "school_at", "harmony",
##   "authority", "icon": {"kind", "end"}, "metro" (planète), "harm": [{"fid", "pid", "end"}], "harmed": [fois],
##   "ancestors": [{"name", "cls", "trait"}]}},
##   "faith": {foi: {"seats": {empire: n}, "primat", "term_end", "bull": {"kind", "end"}, "free_crusade",
##   "reform", "gods": [domaines], "omen": {"kind", "end"}, "omen_next", "welcome": [fois], "hero_god":
##   {"name", "cls"}, "extra": [préceptes], "debt", "god": {"sid", "target", "next", "dead_until", "name"},
##   "profaned": {empire: fin}}}}
##
## Une seule commande, faith_nat, porte toutes les actions (check / apply ci-dessous).

const CLASSIC := ["eglise_universelle", "patriarcats", "loi_extase", "karma", "harmonie", "pantheon", "ancetres", "dette_sang", "dieu_present"]


static func cd() -> Dictionary:
	return GameData.faiths()["classic"]


static func _nat(state: GameState) -> Dictionary:
	if not state.faiths.has("nat") or not (state.faiths["nat"] is Dictionary):
		state.faiths["nat"] = {}
	var n: Dictionary = state.faiths["nat"]
	if not n.has("emp"):
		n["emp"] = {}
	if not n.has("faith"):
		n["faith"] = {}
	return n


static func emp(state: GameState, eid: int) -> Dictionary:
	var e: Dictionary = _nat(state)["emp"]
	var k := str(eid)
	if not e.has(k):
		e[k] = {}
	return e[k]


static func fdat(state: GameState, fid: String) -> Dictionary:
	var f: Dictionary = _nat(state)["faith"]
	if not f.has(fid):
		f[fid] = {}
	return f[fid]


static func _peek_emp(state: GameState, eid: int) -> Dictionary:
	return state.faiths.get("nat", {}).get("emp", {}).get(str(eid), {})


static func _peek_faith(state: GameState, fid: String) -> Dictionary:
	return state.faiths.get("nat", {}).get("faith", {}).get(fid, {})


## Nature de la foi d'État d'un empire ("" s'il n'en a pas).
static func emp_nature(state: GameState, eid: int) -> String:
	if not state.faith_on or GameState.is_npc(eid):
		return ""
	var sf := Faiths.state_faith(state, eid)
	if Faiths.faith(state, sf).is_empty():
		return ""
	return FaithWars.nature(state, sf)


static func follows(state: GameState, eid: int, nature: String) -> bool:
	return emp_nature(state, eid) == nature


## Empires (vivants, non ruche) qui ont cette foi pour foi d'État, triés.
static func members(state: GameState, fid: String) -> Array[int]:
	var out: Array[int] = []
	for e in state.empires:
		if not e.eliminated and not GameState.is_npc(e.id) and Faiths.state_faith(state, e.id) == fid and not Faiths.closed(state, e.id):
			out.append(e.id)
	return out


static func _afford(state: GameState, eid: int, cost: Dictionary) -> String:
	return FaithWars._afford(state, eid, cost)


static func _pay(state: GameState, eid: int, cost: Dictionary) -> void:
	FaithWars._pay(state, eid, cost)


static func _clamp100(v: int, lo := -100) -> int:
	return clampi(v, lo, 100)


# --- Contraintes de doctrine -------------------------------------------------------------------

## "" si la nature permet cette position de doctrine, sinon la raison.
static func doctrine_block(nature: String, axis: String, opt: String) -> String:
	var nd: Dictionary = FaithWars.nature_def(nature)
	var forced := String(nd.get("forces", {}).get(axis, ""))
	if forced != "" and forced != opt:
		return "la nature %s impose « %s »" % [String(nd["label"]), String(Faiths.doctrine_def(axis, forced).get("label", forced))]
	if (nd.get("forbids", {}).get(axis, []) as Array).has(opt):
		return "la nature %s interdit « %s »" % [String(nd["label"]), String(Faiths.doctrine_def(axis, opt).get("label", opt))]
	return ""


## Doctrines corrigées selon la nature (positions imposées ; position interdite remplacée par Juste).
static func apply_forces(nature: String, dc: Dictionary) -> void:
	var nd: Dictionary = FaithWars.nature_def(nature)
	for a in nd.get("forces", {}):
		dc[a] = String(nd["forces"][a])
	for a in nd.get("forbids", {}):
		if (nd["forbids"][a] as Array).has(String(dc.get(a, ""))):
			dc[a] = String(Faiths.DEFAULT_DOCTRINES.get(a, ""))
			if (nd["forbids"][a] as Array).has(String(dc[a])):
				dc[a] = "juste"


# --- Mise en place d'une foi qui vient de fixer sa nature --------------------------------------

static func on_chosen(state: GameState, fid: String) -> void:
	var f := Faiths.faith(state, fid)
	if f.is_empty():
		return
	var nat := String(f["nature"])
	apply_forces(nat, f["doctrines"])
	var d := fdat(state, fid)
	match nat:
		"eglise_universelle":
			if not d.has("seats"):
				d["seats"] = {str(int(f["founder"])): 1}
				d["primat"] = int(f["founder"])
				d["term_end"] = state.tick + int(cd()["eglise"]["term_days"])
				d["reform"] = 0
		"pantheon":
			if not d.has("gods"):
				d["gods"] = _ai_gods(state, int(f["founder"]))
				d["omen_next"] = 0
				d["welcome"] = []
		"dette_sang":
			if not d.has("debt"):
				d["debt"] = int(cd()["dette"]["start"])
		"dieu_present":
			if not d.has("god"):
				d["god"] = _new_god(state, fid)
	FaithHeavy.on_chosen(state, fid)
	Relics.touch(state)


static func _new_god(state: GameState, fid: String) -> Dictionary:
	var f := Faiths.faith(state, fid)
	var sid := state.galaxy.get_planet(int(f["holy"])).system_id
	var nm := "le Dieu de %s" % Faiths.name_of(state, fid)
	if String(f.get("via", "")) == "gardien":
		nm = "le Gardien vénéré de %s" % Faiths.name_of(state, fid)
	return {"sid": sid, "target": sid, "next": state.tick + int(cd()["dieu"]["move_days"]), "dead_until": 0, "name": nm}


# --- Chef de foi --------------------------------------------------------------------------------

## Chef de foi imposé par la nature (-2 : pas d'avis, la doctrine décide).
static func head_override(state: GameState, fid: String) -> int:
	match FaithWars.nature(state, fid):
		"eglise_universelle":
			var p := int(_peek_faith(state, fid).get("primat", -1))
			var pe := state.get_empire(p)
			if pe != null and not pe.eliminated and Faiths.state_faith(state, p) == fid:
				return p
			return -2
		"dieu_present":
			var g: Dictionary = _peek_faith(state, fid).get("god", {})
			if g.is_empty() or int(g.get("dead_until", 0)) > state.tick:
				return -1
			var o := state.system_owner(int(g["sid"]))
			if o >= 0 and not GameState.is_npc(o) and Faiths.state_faith(state, o) == fid:
				return o
			return -1
	return -2


# --- Effets (fusionnés dans Faiths.effects) ----------------------------------------------------

static func fx(state: GameState, eid: int, sf: String) -> Dictionary:
	var out := {}
	var c := cd()
	var ed := _peek_emp(state, eid)
	var fd := _peek_faith(state, sf)
	match FaithWars.nature(state, sf):
		"patriarcats":
			var ic: Dictionary = ed.get("icon", {})
			if not ic.is_empty() and int(ic["end"]) > state.tick:
				Research._merge(out, c["patriarcats"]["icons"].get(String(ic["kind"]), {}).get("fx", {}))
		"loi_extase":
			var p := piety(state, eid)
			var le: Dictionary = c["loi_extase"]
			if p >= int(le["threshold"]):
				Research._merge(out, le["loi_fx"])
		"karma":
			if karma(state, eid) < -int(c["karma"]["balance"]):
				Research._merge(out, c["karma"]["low_fx"])
		"harmonie":
			for pid in fd.get("extra", []):
				Research._merge(out, Faiths.precept_def(String(pid)).get("fx", {}))
		"pantheon":
			var pd: Dictionary = c["pantheon"]
			var om: Dictionary = fd.get("omen", {})
			for g in fd.get("gods", []):
				var gfx: Dictionary = pd["domains"].get(String(g), {}).get("fx", {})
				var times := int(pd["omen_x"]) if not om.is_empty() and String(om["kind"]) == String(g) and int(om["end"]) > state.tick else 1
				for _i in times:
					Research._merge(out, gfx)
			var hg: Dictionary = fd.get("hero_god", {})
			if not hg.is_empty():
				Research._merge(out, pd["hero_fx"].get(String(hg["cls"]), {}))
		"ancetres":
			if has_mausoleum(state, eid):
				for a in active_ancestors(state, eid):
					Research._merge(out, ancestor_fx(a, int(FaithHeavy.talent(state, eid).get("ancestor_pct", cd()["ancetres"]["trait_pct"]))))
		"dette_sang":
			if int(fd.get("debt", 0)) <= int(c["dette"]["low"]):
				Research._merge(out, c["dette"]["low_fx"])
	FaithHeavy.fx(state, eid, sf, out)
	return out


## Lignes de stabilité d'un système (Faiths.stability_parts).
static func stability_parts(state: GameState, sid: int, owner: int) -> Array:
	var out := []
	var sf := Faiths.state_faith(state, owner)
	var nat := emp_nature(state, owner)
	var c := cd()
	var ed := _peek_emp(state, owner)
	match nat:
		"eglise_universelle":
			var b: Dictionary = _peek_faith(state, sf).get("bull", {})
			if not b.is_empty() and String(b["kind"]) == "indulgence" and int(b["end"]) > state.tick:
				out.append(["Bulle d'indulgence", int(c["eglise"]["indulgence_stab"])])
		"patriarcats":
			var ic: Dictionary = ed.get("icon", {})
			if not ic.is_empty() and int(ic["end"]) > state.tick and String(ic["kind"]) == "stabilite":
				out.append(["Icône de paix", int(c["patriarcats"]["icons"]["stabilite"]["stab"])])
		"loi_extase":
			if piety(state, owner) >= int(c["loi_extase"]["threshold"]):
				out.append(["Voie de la Loi", int(c["loi_extase"]["loi_stab"])])
		"karma":
			var k := karma(state, owner)
			var kd: Dictionary = c["karma"]
			if absi(k) <= int(kd["balance"]):
				out.append(["Karma en équilibre", int(kd["balance_stab"])])
			elif k > int(kd["balance"]) and Combat.has_live_war(state, owner):
				out.append(["Karma trahi par la guerre", int(kd["high_war_stab"])])
	# Profanation du mausolée, dette effondrée : lignes temporaires (FaithWars.add_stab).
	FaithHeavy.stability_parts(state, sid, owner, out)
	return out


## Lignes d'opinion de a envers b (Faiths.opinion_parts).
static func opinion_parts(state: GameState, a: int, b: int) -> Array:
	var out := []
	var c := cd()
	var fa := Faiths.state_faith(state, a)
	var fb := Faiths.state_faith(state, b)
	# Karma de b vu par les fidèles d'une foi du karma, ou par tous (karma haut ou bas).
	if follows(state, b, "karma"):
		var k := karma(state, b)
		var kd: Dictionary = c["karma"]
		if absi(k) <= int(kd["balance"]) and fa == fb:
			out.append(["Karma en équilibre", int(kd["balance_op"])])
		elif k > int(kd["balance"]):
			out.append(["Karma lumineux", int(kd["high_op"])])
		elif k < -int(kd["balance"]):
			out.append(["Karma sombre", int(kd["low_op"])])
	# Écoles d'interprétation (Loi et Extase).
	if fa == fb and follows(state, a, "loi_extase"):
		var sa := school(state, a)
		var sb := school(state, b)
		var sd: Dictionary = c["loi_extase"]["schools"].get(sa, {})
		if sb != "" and String(sd.get("esteems", "")) == sb:
			out.append(["École estimée (%s)" % String(c["loi_extase"]["schools"][sb]["label"]), int(c["loi_extase"]["school_op"])])
		elif sb != "" and String(sd.get("rejects", "")) == sb:
			out.append(["École rejetée (%s)" % String(c["loi_extase"]["schools"][sb]["label"]), -int(c["loi_extase"]["school_op"])])
	FaithHeavy.opinion_parts(state, a, b, out)
	FaithBridges.opinion_parts(state, a, b, out)
	return out


## Pas d'hostilité religieuse de a envers la foi fb (harmonisée chez a).
static func no_hostility(state: GameState, a: int, fb: String) -> bool:
	return follows(state, a, "harmonie") and (_peek_emp(state, a).get("harmed", []) as Array).has(fb)


## Une autre foi majoritaire ne coûte pas de stabilité (harmonie haute, foi harmonisée, dieu accueilli).
static func minor_exempt(state: GameState, owner: int, m: String) -> bool:
	var nat := emp_nature(state, owner)
	if nat == "harmonie":
		return harmony(state, owner) >= int(cd()["harmonie"]["threshold"]) or (_peek_emp(state, owner).get("harmed", []) as Array).has(m)
	if nat == "pantheon":
		return (_peek_faith(state, Faiths.state_faith(state, owner)).get("welcome", []) as Array).has(m)
	return false


## Seuil de conversion vers fid sur une colonie (Panthéon : les fidèles d'un dieu accueilli résistent).
static func threshold_pct(state: GameState, c: Colony, fid: String) -> int:
	if FaithWars.nature(state, fid) != "pantheon":
		return 0
	var wl: Array = _peek_faith(state, fid).get("welcome", [])
	for w in wl:
		if int(c.faith.get(String(w), 0)) > 0:
			return int(cd()["pantheon"]["welcome_threshold_pct"])
	return 0


## Pression en plus pour une foi (Église universelle : mandat missionnaire), en %.
static func pressure_pct(state: GameState, fid: String) -> int:
	if FaithWars.nature(state, fid) == "eglise_universelle":
		var b: Dictionary = _peek_faith(state, fid).get("bull", {})
		if not b.is_empty() and String(b["kind"]) == "mandat" and int(b["end"]) > state.tick:
			return int(cd()["eglise"]["mandat_pct"])
	return 0


## Multiplicateur de prêche d'une colonie source (métropolite des Patriarcats).
static func source_x(state: GameState, c: Colony, fid: String) -> int:
	var x := FaithBridges.source_x(state, c, fid)
	if FaithWars.nature(state, fid) == "patriarcats" and int(_peek_emp(state, c.owner).get("metro", -1)) == c.planet_id:
		return maxi(x, int(cd()["patriarcats"]["metro_x"]))
	return x


## Pression du dominion d'un dieu présent (Faiths.pressures, via FaithWars.extra_pressures).
static func extra_pressures(state: GameState, out: Dictionary, targets_by_sys: Dictionary) -> void:
	FaithHeavy.extra_pressures(state, out, targets_by_sys)
	var dd: Dictionary = cd()["dieu"]
	for fid in Faiths.ids(state):
		var g := live_god(state, fid)
		if g.is_empty():
			continue
		var dist := FactionTraits.jumps_from(state.galaxy, int(g["sid"]))
		for t in targets_by_sys:
			if int(dist.get(t, 99)) > int(dd["dominion"]):
				continue
			for pid in targets_by_sys[t]:
				var pm: Dictionary = out.get(pid, {})
				pm[fid] = int(pm.get(fid, 0)) + int(dd["pressure"]) * 100
				out[pid] = pm


## Dégâts d'une flotte dans un système (CombatSystem) : affaiblie dans le dominion d'un dieu ennemi.
static func damage_pct(state: GameState, f: Fleet, sid: int) -> int:
	if not state.faith_on or GameState.is_npc(f.owner):
		return 0
	var v := 0
	for fid in Faiths.ids(state):
		var g := live_god(state, fid)
		if g.is_empty() or Faiths.state_faith(state, f.owner) == fid:
			continue
		var host := head_override(state, fid) if FaithWars.nature(state, fid) == "dieu_present" else Faiths.head(state, fid)
		if FaithHeavy.disobeys(state, fid) or host < 0 or not Combat.at_war(state, host, f.owner):
			continue
		if int(FactionTraits.jumps_from(state.galaxy, int(g["sid"])).get(sid, 99)) <= int(cd()["dieu"]["dominion"]):
			v += int(cd()["dieu"]["enemy_damage_pct"])
	return v


# --- Jauges ---------------------------------------------------------------------------------------

static func karma(state: GameState, eid: int) -> int:
	return int(_peek_emp(state, eid).get("karma", 0))


static func piety(state: GameState, eid: int) -> int:
	return int(_peek_emp(state, eid).get("piety", 0))


static func harmony(state: GameState, eid: int) -> int:
	return int(_peek_emp(state, eid).get("harmony", int(cd()["harmonie"]["start"])))


static func authority(state: GameState, eid: int) -> int:
	return int(_peek_emp(state, eid).get("authority", int(cd()["patriarcats"]["start"])))


static func school(state: GameState, eid: int) -> String:
	return String(_peek_emp(state, eid).get("school", ""))


static func debt(state: GameState, fid: String) -> int:
	return int(_peek_faith(state, fid).get("debt", int(cd()["dette"]["start"])))


static func reform(state: GameState, fid: String) -> int:
	return int(_peek_faith(state, fid).get("reform", 0))


static func add_karma(state: GameState, eid: int, v: int) -> void:
	if v == 0 or not follows(state, eid, "karma"):
		return
	var e := emp(state, eid)
	var before := karma(state, eid)
	e["karma"] = _clamp100(before + v)
	_touch_if_band(before, int(e["karma"]), int(cd()["karma"]["balance"]), state)


static func add_piety(state: GameState, eid: int, v: int) -> void:
	if v == 0 or not follows(state, eid, "loi_extase"):
		return
	var e := emp(state, eid)
	var before := piety(state, eid)
	e["piety"] = _clamp100(before + v)
	_touch_if_band(before, int(e["piety"]), int(cd()["loi_extase"]["threshold"]), state)


static func add_authority(state: GameState, eid: int, v: int) -> void:
	if v == 0 or not follows(state, eid, "patriarcats"):
		return
	emp(state, eid)["authority"] = clampi(authority(state, eid) + v, 0, 100)


static func add_debt(state: GameState, fid: String, v: int) -> void:
	if v == 0 or FaithWars.nature(state, fid) != "dette_sang":
		return
	var d := fdat(state, fid)
	var low := int(cd()["dette"]["low"])
	var before := debt(state, fid)
	d["debt"] = clampi(before + v, 0, int(cd()["dette"]["max"]))
	if (before <= low) != (int(d["debt"]) <= low):
		Relics.touch(state)


## Les effets dépendent de la jauge : on vide le cache des effets quand elle change de bande.
static func _touch_if_band(before: int, after: int, band: int, state: GameState) -> void:
	var bb := 0 if absi(before) <= band else (1 if before > 0 else -1)
	var ba := 0 if absi(after) <= band else (1 if after > 0 else -1)
	if bb != ba:
		Relics.touch(state)


# --- Événements du reste du jeu ----------------------------------------------------------------

## Traité signé (Diplomacy.sign_treaty).
static func on_treaty(state: GameState, a: int, b: int, treaty: String) -> void:
	if not state.faith_on:
		return
	var kd: Dictionary = cd()["karma"]
	var v := int(kd["peace"]) if treaty == "peace" else (int(kd["alliance"]) if treaty == "alliance" else 0)
	add_karma(state, a, v)
	add_karma(state, b, v)


## Guerre déclarée (Diplomacy.on_war_declared) : joined = un allié entre en guerre à vos côtés.
static func on_war(state: GameState, a: int, b: int, joined: bool) -> void:
	if not state.faith_on:
		return
	var kd: Dictionary = cd()["karma"]
	add_karma(state, a, int(kd["honor"]) if joined else int(kd["war"]))
	if FaithWars.casus(state, a, b) != "" and not joined:
		add_piety(state, a, int(cd()["loi_extase"]["holy_war"]))


## Système pris (Combat.capture_system), après le changement de maître.
static func on_capture(state: GameState, sid: int, old: int, new_owner: int, added: Array[Dictionary]) -> void:
	if not state.faith_on:
		return
	add_karma(state, new_owner, int(cd()["karma"]["conquest"]))
	var nf := Faiths.state_faith(state, new_owner)
	var pop := false
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == new_owner and c.is_colony() and c.population > 0:
			pop = true
		# Profanation : le mausolée d'un empire des ancêtres tombe aux mains d'un autre.
		if c != null and c.buildings.has("mausolee") and follows(state, old, "ancetres") and c.owner == new_owner:
			_profane(state, old, new_owner, pid, added)
	if pop:
		add_debt(state, nf, int(cd()["dette"]["invasion"]))
		FaithHeavy.on_capture(state, new_owner)


static func _profane(state: GameState, victim: int, by: int, pid: int, added: Array[Dictionary]) -> void:
	var ad: Dictionary = cd()["ancetres"]
	var sf := Faiths.state_faith(state, victim)
	FaithWars.add_zeal(state, sf, int(ad["profane_zeal"]))
	for s in state.galaxy.systems.size():
		if state.system_owner(s) == victim:
			FaithWars.add_stab(state, s, "Mausolée profané", int(ad["profane_stab"]), int(ad["profane_days"]))
	var fd := fdat(state, sf)
	if not fd.has("profaned"):
		fd["profaned"] = {}
	fd["profaned"][str(by)] = state.tick + int(ad["profane_casus_days"])
	added.append(state.add_chronicle("Profanation ! %s s'empare du mausolée de %s sur %s. Les ancêtres de %s ne dorment plus, et leurs descendants non plus." % [
			state.get_empire(by).display_name(), state.get_empire(victim).display_name(), state.galaxy.get_planet(pid).display_name(state.galaxy),
			Faiths.name_of(state, sf)]))


## Motif de guerre sainte propre à une nature (FaithWars.casus) ; "" s'il n'y en a pas.
static func casus(state: GameState, a: int, b: int) -> String:
	var fa := Faiths.state_faith(state, a)
	if FaithWars.nature(state, fa) == "ancetres" and int(_peek_faith(state, fa).get("profaned", {}).get(str(b), 0)) > state.tick:
		return "il a profané le mausolée de nos ancêtres"
	return FaithHeavy.casus(state, a, b)


## Statut d'un peuple changé (Peoples.set_status).
static func on_status(state: GameState, eid: int, old: String, now: String) -> void:
	if not state.faith_on or old == now:
		return
	var kd: Dictionary = cd()["karma"]
	if now == "extermines":
		add_karma(state, eid, int(kd["exterminate"]))
	elif now == "citoyens" and (old == "assujettis" or old == "expulses" or old == "extermines"):
		add_karma(state, eid, int(kd["liberate"]))


## Fin de bataille (CombatSystem) : la Dette de sang se paie en vaisseaux ennemis détruits.
static func on_battle(state: GameState, b: Dictionary) -> void:
	if not state.faith_on:
		return
	FaithHeavy.on_battle(state, b)
	var paid := {}
	for s: Dictionary in b["sides"]:
		var eid := int(s["empire"])
		var sf := Faiths.state_faith(state, eid)
		if FaithWars.nature(state, sf) != "dette_sang":
			continue
		var n := 0
		for o: Dictionary in b["sides"]:
			if int(o["empire"]) != eid and Combat.at_war(state, eid, int(o["empire"])):
				n += Combat.count_ships(o["lost"])
		paid[sf] = int(paid.get(sf, 0)) + n
	var dd: Dictionary = cd()["dette"]
	for sf in paid:
		add_debt(state, String(sf), maxi(int(dd["battle_max"]), int(paid[sf]) * int(dd["ship"])))


## Offrande d'une théocratie (SimCommands « sacrifice ») : elle paie aussi la dette.
static func on_offering(state: GameState, eid: int) -> void:
	if state.faith_on and follows(state, eid, "dette_sang"):
		add_debt(state, Faiths.state_faith(state, eid), int(cd()["dette"]["offer"]))


## Conversions forcées de l'Inquisition (FaithWars._cult_month) : autorité en baisse, piété vers la Loi.
static func on_inquisition(state: GameState, eid: int) -> void:
	add_authority(state, eid, int(cd()["patriarcats"]["forced"]))
	add_piety(state, eid, int(cd()["loi_extase"]["inquisition"]))


static func on_mission(state: GameState, eid: int) -> void:
	add_piety(state, eid, int(cd()["loi_extase"]["mission"]))


static func on_ward(state: GameState, eid: int) -> void:
	add_piety(state, eid, int(cd()["loi_extase"]["ward"]))


static func on_prophecy(state: GameState, eid: int) -> void:
	add_piety(state, eid, int(cd()["loi_extase"]["prophecy"]))


## Mission moins chère (Extase), en %.
static func mission_pct(state: GameState, eid: int) -> int:
	if follows(state, eid, "loi_extase") and piety(state, eid) <= -int(cd()["loi_extase"]["threshold"]):
		return int(cd()["loi_extase"]["extase_mission_pct"])
	return 0


## Expérience des héros en plus (Extase), en %.
static func hero_xp_pct(state: GameState, eid: int) -> int:
	if state.faith_on and follows(state, eid, "loi_extase") and piety(state, eid) <= -int(cd()["loi_extase"]["threshold"]):
		return int(cd()["loi_extase"]["extase_xp_pct"])
	return 0


## Croisade gratuite (bulle d'appel à la croisade) ?
static func free_crusade(state: GameState, fid: String) -> bool:
	return bool(_peek_faith(state, fid).get("free_crusade", false))


static func use_free_crusade(state: GameState, fid: String) -> void:
	if free_crusade(state, fid):
		fdat(state, fid)["free_crusade"] = false


## Hérésies (FaithWars._heresy_month) : chance en %, Patriarcats plus rares.
static func heresy_pct(state: GameState, fid: String) -> int:
	return int(cd()["patriarcats"]["heresy_pct"]) if FaithWars.nature(state, fid) == "patriarcats" else 100


## Mort d'un héros (Heroes.die) : ancêtre, apothéose, tueur détesté par les fidèles.
static func on_hero_death(state: GameState, h: Dictionary, killer: int, out: Array[Dictionary]) -> void:
	if not state.faith_on:
		return
	FaithBridges.on_hero_death(state, h, killer, out)
	var owner := int(h.get("owner", -1))
	var nat := emp_nature(state, owner)
	var sf := Faiths.state_faith(state, owner)
	var tr: Array = h.get("traits", [])
	if nat == "ancetres":
		var e := emp(state, owner)
		if not e.has("ancestors"):
			e["ancestors"] = []
		(e["ancestors"] as Array).append({"name": String(h["name"]), "cls": String(h.get("cls", "")), "trait": String(tr[0]) if not tr.is_empty() else ""})
		Relics.touch(state)
		out.append(state.add_chronicle("%s rejoint les ancêtres de %s. Son nom est gravé au mausolée ; sa voix, dit-on, s'y entend encore." % [
				String(h["name"]), state.get_empire(owner).display_name()], Espionage.private_to(state, [owner])))
		if killer >= 0 and killer != owner:
			for m in members(state, sf):
				if m != killer:
					Diplomacy.remember(state, m, killer, String(cd()["ancetres"]["slain_memory"]))
	if nat == "pantheon" and int(h.get("lvl", 1)) >= int(cd()["pantheon"]["apotheosis_lvl"]):
		fdat(state, sf)["hero_god"] = {"name": String(h["name"]), "cls": String(h.get("cls", ""))}
		Relics.touch(state)
		out.append(state.add_chronicle("Apothéose : %s monte au panthéon de %s. Les prêtres ajoutent une statue ; les sculpteurs, une facture." % [
				String(h["name"]), Faiths.name_of(state, sf)]))


# --- Ancêtres -----------------------------------------------------------------------------------

static func active_ancestors(state: GameState, eid: int) -> Array:
	var all: Array = _peek_emp(state, eid).get("ancestors", [])
	var n := int(FaithHeavy.talent(state, eid).get("ancestors", cd()["ancetres"]["active"]))
	return all.slice(maxi(0, all.size() - n))


static func has_mausoleum(state: GameState, eid: int) -> bool:
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		if c.owner == eid and c.buildings.has("mausolee"):
			return true
	return false


## Effet d'un ancêtre : son premier trait étendu à l'empire, à moitié (production d'un système →
## production de l'empire ; dégâts de flotte → toutes les flottes), sinon un effet de sa classe.
static func ancestor_fx(a: Dictionary, pct := -1) -> Dictionary:
	if pct < 0:
		pct = int(cd()["ancetres"]["trait_pct"])
	var tfx: Dictionary = Heroes.trait_def(String(a.get("trait", ""))).get("fx", {})
	var out := {}
	for k in tfx:
		match String(k):
			"res_pct":
				var pr := {}
				for r in tfx[k]:
					pr[r] = int(tfx[k][r]) * pct / 100
				out["production_pct"] = pr
			"damage_pct", "first_day_pct", "home_damage_pct", "fauna_damage_pct":
				out["damage_pct"] = int(out.get("damage_pct", 0)) + maxi(1, int(tfx[k]) * pct / 100)
			"growth":
				out["growth_pct"] = 5
	if out.is_empty():
		out = (cd()["pantheon"]["hero_fx"].get(String(a.get("cls", "")), {}) as Dictionary).duplicate(true)
	return out


## Mausolée constructible ici ? "" si oui (Economy.check_build).
static func check_mausoleum(state: GameState, eid: int, pid: int) -> String:
	if not follows(state, eid, "ancetres"):
		return "il faut une foi d'État du Culte des ancêtres"
	var e := state.get_empire(eid)
	var holy := int(Faiths.faith(state, Faiths.state_faith(state, eid)).get("holy", -1))
	if pid != e.capital_planet and pid != holy:
		return "un mausolée se bâtit sur la capitale ou le monde saint"
	if has_mausoleum(state, eid):
		return "l'empire a déjà un mausolée"
	return ""


# --- Dieu présent -------------------------------------------------------------------------------

## Le dieu d'une foi, s'il est vivant ({} sinon).
static func live_god(state: GameState, fid: String) -> Dictionary:
	var nat := FaithWars.nature(state, fid)
	if nat != "dieu_present" and not (nat == "dieu_en_chantier" and FaithHeavy.stage(state, fid) >= (FaithHeavy.hd()["chantier"]["stages"] as Array).size()):
		return {}
	var g: Dictionary = _peek_faith(state, fid).get("god", {})
	if g.is_empty() or int(g.get("dead_until", 0)) > state.tick:
		return {}
	return g


static func _god_month(state: GameState, fid: String, added: Array[Dictionary]) -> void:
	var dd: Dictionary = cd()["dieu"]
	var fd := fdat(state, fid)
	if not fd.has("god"):
		fd["god"] = _new_god(state, fid)
	var g: Dictionary = fd["god"]
	if int(g["dead_until"]) > 0 and int(g["dead_until"]) <= state.tick:
		var ng := _new_god(state, fid)
		ng["name"] = String(g["name"])
		fd["god"] = ng
		added.append(state.add_chronicle("%s revient au monde saint de %s. Personne n'ose demander où il était." % [(String(g["name"]).left(1).to_upper() + String(g["name"]).substr(1)), Faiths.name_of(state, fid)]))
		return
	if int(g["dead_until"]) > state.tick:
		return
	# Déplacement : un saut par mois vers la cible.
	var sid := int(g["sid"])
	var tgt := int(g["target"])
	if tgt != sid and state.tick >= int(g["next"]):
		var dist := FactionTraits.jumps_from(state.galaxy, tgt)
		var best := sid
		var nbs: Array = state.galaxy.systems[sid].neighbors.duplicate()
		nbs.sort()
		for n in nbs:
			if int(dist.get(n, 999)) < int(dist.get(best, 999)):
				best = int(n)
		g["sid"] = best
		g["next"] = state.tick + int(dd["move_days"])
		sid = best
	# Mort : une flotte de guerre d'un ennemi de son hôte le trouve sans escorte de la foi.
	var host := head_override(state, fid) if FaithWars.nature(state, fid) == "dieu_present" else Faiths.head(state, fid)
	var guarded := false
	var killer := -1
	for fl: Fleet in _fleets_at(state, sid):
		if not Combat.is_warfleet(fl) or not fl.path.is_empty():
			continue
		if Faiths.state_faith(state, fl.owner) == fid:
			guarded = true
		elif host >= 0 and Combat.at_war(state, host, fl.owner):
			killer = fl.owner
	if killer >= 0 and not guarded:
		g["dead_until"] = state.tick + int(dd["respawn_days"])
		FaithWars.add_zeal(state, fid, int(dd["death_zeal"]))
		added.append(state.add_chronicle("Déicide à %s ! Les flottes de %s abattent %s. Les fidèles de %s portent le deuil ; on dit qu'il reviendra." % [
				state.galaxy.systems[sid].system_name, state.get_empire(killer).display_name(), String(g["name"]), Faiths.name_of(state, fid)]))


static func _fleets_at(state: GameState, sid: int) -> Array[Fleet]:
	var out: Array[Fleet] = []
	var ids := state.fleets.keys()
	ids.sort()
	for id in ids:
		var f: Fleet = state.fleets[id]
		if f.system_id == sid:
			out.append(f)
	return out


## Deux dominions qui se touchent s'usent l'un l'autre.
static func _clash_month(state: GameState) -> void:
	var dd: Dictionary = cd()["dieu"]
	var gods := []
	for fid in Faiths.ids(state):
		var g := live_god(state, fid)
		if not g.is_empty():
			gods.append([fid, int(g["sid"])])
	for i in gods.size():
		for j in range(i + 1, gods.size()):
			var d := int(FactionTraits.jumps_from(state.galaxy, int(gods[i][1])).get(int(gods[j][1]), 99))
			if d <= 2 * int(dd["dominion"]):
				FaithWars.add_zeal(state, String(gods[i][0]), int(dd["clash_zeal"]))
				FaithWars.add_zeal(state, String(gods[j][0]), int(dd["clash_zeal"]))


# --- Mois -----------------------------------------------------------------------------------------

static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	if not state.faith_on:
		return
	var c := cd()
	for fid in Faiths.ids(state):
		var f := Faiths.faith(state, fid)
		if int(f.get("pending", 0)) > 0:
			continue
		match FaithWars.nature(state, fid):
			"eglise_universelle":
				_church_month(state, fid, added)
			"dette_sang":
				_debt_month(state, fid, added)
			"dieu_present":
				_god_month(state, fid, added)
			"pantheon":
				var om: Dictionary = fdat(state, fid).get("omen", {})
				if not om.is_empty() and int(om["end"]) <= state.tick:
					fdat(state, fid).erase("omen")
					Relics.touch(state)
			_:
				FaithHeavy.monthly(state, fid, added)
	_clash_month(state)
	for e in state.empires:
		if e.eliminated or GameState.is_npc(e.id):
			continue
		match emp_nature(state, e.id):
			"karma":
				var k := karma(state, e.id)
				if k != 0:
					add_karma(state, e.id, -signi(k) * mini(absi(k), int(c["karma"]["drift"])))
			"loi_extase":
				if FaithWars.missions_by(state, e.id).size() > 0 and Research.fx_int(state, e.id, "pilgrims") > 0:
					add_piety(state, e.id, int(c["loi_extase"]["pilgrim"]))
			"harmonie":
				_harmony_month(state, e, added)
			"patriarcats":
				_authority_month(state, e)


static func _authority_month(state: GameState, e: Empire) -> void:
	var pd: Dictionary = cd()["patriarcats"]
	var temples := 0
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		if c.owner == e.id and c.buildings.has("temple"):
			temples += 1
	var v := mini(int(pd["temple_max"]), temples * int(pd["temple"]))
	var sf := Faiths.state_faith(state, e.id)
	var hc: Colony = state.colonies.get(int(Faiths.faith(state, sf).get("holy", -1)))
	if hc != null and hc.owner == e.id:
		v += int(pd["holy"])
	add_authority(state, e.id, v)
	var ic: Dictionary = emp(state, e.id).get("icon", {})
	if not ic.is_empty() and int(ic["end"]) <= state.tick:
		emp(state, e.id).erase("icon")
		Relics.touch(state)
	var m := int(emp(state, e.id).get("metro", -1))
	if m >= 0:
		var mc: Colony = state.colonies.get(m)
		if mc == null or mc.owner != e.id:
			emp(state, e.id).erase("metro")


static func _harmony_month(state: GameState, e: Empire, added: Array[Dictionary]) -> void:
	var hd: Dictionary = cd()["harmonie"]
	var ed := emp(state, e.id)
	ed["harmony"] = clampi(harmony(state, e.id) + int(hd["month"]), 0, 100)
	var sf := Faiths.state_faith(state, e.id)
	var keep: Array = []
	for h: Dictionary in ed.get("harm", []):
		if int(h["end"]) > state.tick:
			keep.append(h)
			continue
		var fd := fdat(state, sf)
		if not fd.has("extra"):
			fd["extra"] = []
		var pid := String(h["pid"])
		if (fd["extra"] as Array).size() < harm_max(state, e.id) and not (fd["extra"] as Array).has(pid) and not (Faiths.faith(state, sf)["precepts"] as Array).has(pid):
			(fd["extra"] as Array).append(pid)
		if not ed.has("harmed"):
			ed["harmed"] = []
		if not (ed["harmed"] as Array).has(String(h["fid"])):
			(ed["harmed"] as Array).append(String(h["fid"]))
		Relics.touch(state)
		added.append(state.add_chronicle("Harmonie : %s accueille %s dans sa foi et lui prend « %s ». Les théologiens des deux bords prétendent avoir gagné." % [
				e.display_name(), Faiths.name_of(state, String(h["fid"])), String(Faiths.precept_def(pid).get("label", pid))], Espionage.private_to(state, [e.id])))
	ed["harm"] = keep


static func _debt_month(state: GameState, fid: String, added: Array[Dictionary]) -> void:
	var dd: Dictionary = cd()["dette"]
	add_debt(state, fid, int(dd["month"]))
	if debt(state, fid) <= int(dd["low"]):
		FaithWars.add_zeal(state, fid, int(dd["low_zeal"]))
	if debt(state, fid) < int(dd["max"]):
		return
	# Dette échue : un héros du chef de foi est sacrifié, la stabilité s'effondre.
	var h := Faiths.head(state, fid)
	fdat(state, fid)["debt"] = int(dd["reset"])
	Relics.touch(state)
	if h < 0:
		return
	for s in state.galaxy.systems.size():
		if state.system_owner(s) == h:
			FaithWars.add_stab(state, s, "Dette de sang échue", int(dd["crash_stab"]), int(dd["crash_days"]))
	var ids := Heroes.ids_of(state, h)
	var text := "La Dette de sang de %s est échue. " % Faiths.name_of(state, fid)
	if not ids.is_empty():
		var hero: Dictionary = state.heroes[ids[FaithWars._h(state, ["debt", fid, state.tick]) % ids.size()]]
		text += "%s monte à l'autel ; le dieu est payé, pour cette fois." % String(hero["name"])
		Heroes.die(state, hero, "est offert au dieu pour éteindre la Dette de sang", added)
	else:
		text += "Faute de héros à offrir, c'est le peuple qui paie."
	added.append(state.add_chronicle(text, Espionage.private_to(state, [h])))


static func _church_month(state: GameState, fid: String, added: Array[Dictionary]) -> void:
	var ed: Dictionary = cd()["eglise"]
	var fd := fdat(state, fid)
	if not fd.has("seats"):
		on_chosen(state, fid)
	# Les sièges des empires sortis de la foi sont perdus.
	var seats: Dictionary = fd["seats"]
	for k in seats.keys():
		if Faiths.state_faith(state, int(k)) != fid or state.get_empire(int(k)).eliminated:
			seats.erase(k)
	# Élection du Primat.
	if state.tick >= int(fd.get("term_end", 0)) or head_override(state, fid) == -2:
		var best := -1
		var bn := -1
		var keys := seats.keys()
		keys.sort_custom(func(x, y): return int(x) < int(y))
		for k in keys:
			if int(seats[k]) > bn:
				bn = int(seats[k])
				best = int(k)
		if best < 0:
			var mem := members(state, fid)
			best = mem[0] if not mem.is_empty() else -1
		var old := int(fd.get("primat", -1))
		fd["primat"] = best
		fd["term_end"] = state.tick + int(ed["term_days"])
		if best >= 0 and best != old:
			added.append(state.add_chronicle("Fumée blanche : %s est élu Primat de %s pour dix ans. Les cardinaux des autres empires comptent déjà les voix de la prochaine fois." % [
					state.get_empire(best).display_name(), Faiths.name_of(state, fid)]))
	# Dîme de la bulle.
	var b: Dictionary = fd.get("bull", {})
	if not b.is_empty() and int(b["end"]) <= state.tick:
		fd.erase("bull")
		Relics.touch(state)
	elif not b.is_empty() and String(b["kind"]) == "dime":
		var p := int(fd.get("primat", -1))
		var pe := state.get_empire(p)
		if pe != null:
			pe.resources["influence"] = int(pe.resources.get("influence", 0)) + int(ed["dime_influence"]) * maxi(0, members(state, fid).size() - 1)
	# Désir de réforme.
	@warning_ignore("integer_division")
	var r := reform(state, fid) + mini(int(ed["reform_month_max"]), Faiths.followers(state, fid) / int(ed["reform_per_followers"]))
	fd["reform"] = mini(int(ed["reform_max"]), r)
	if int(fd["reform"]) >= int(ed["reform_max"]):
		_reformation(state, fid, added)


## La Réforme : un schisme certain, sur la colonie fidèle la plus peuplée loin du monde saint.
static func _reformation(state: GameState, fid: String, added: Array[Dictionary]) -> void:
	var f := Faiths.faith(state, fid)
	var best: Colony = null
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if pid == int(f["holy"]) or GameState.is_npc(c.owner) or int(c.faith.get(fid, 0)) < 2:
			continue
		if best == null or int(c.faith[fid]) > int(best.faith[fid]):
			best = c
	fdat(state, fid)["reform"] = 0
	if best == null:
		return
	var hid := make_schism(state, fid, best.planet_id, added, "patriarcats")
	if hid == "":
		return
	added.append(state.add_chronicle("La Réforme ! Sur %s, les fidèles de %s clouent leurs thèses à la porte du Collège : %s naît. Le Primat excommunie, les imprimeurs se frottent les mains." % [
			state.galaxy.get_planet(best.planet_id).display_name(state.galaxy), Faiths.name_of(state, fid), Faiths.name_of(state, hid)]))


## Schisme immédiat sur une colonie (Réforme, prophétie empêchée) : une hérésie qui devient tout de
## suite une grande foi sœur et choisit sa nature parmi 3 (with : nature toujours proposée).
static func make_schism(state: GameState, fid: String, pid: int, added: Array[Dictionary], with := "") -> String:
	var hid := FaithWars.spawn_heresy(state, fid, pid, added)
	if hid == "":
		return ""
	var c: Colony = state.colonies[pid]
	var h := Faiths.faith(state, hid)
	h.erase("parent")
	h["via"] = "schisme"
	h["schism_of"] = fid
	h["founder"] = c.owner
	var off := Faiths.offer_natures(state, c.owner, hid, "schisme")
	if with != "" and not off.has(with):
		off[0] = with
	h["offer"] = off
	h["pending"] = state.tick + int(Faiths.data()["choice"]["days"])
	var fe := state.get_empire(c.owner)
	if fe == null or fe.is_ai():
		Faiths.choose(state, hid, with if with != "" else String(off[0]), {}, "")
	FaithBridges.on_schism(state, fid, hid)
	Relics.touch(state)
	return hid


# --- Actions (commande faith_nat) --------------------------------------------------------------

## "" si l'action est possible, sinon la raison. args : selon l'action.
static func check(state: GameState, player: int, act: String, args: Dictionary) -> String:
	if not state.faith_on:
		return "les religions ne sont pas actives dans cette partie"
	var e := state.get_empire(player)
	if e == null or e.eliminated:
		return "empire inconnu"
	var sf := Faiths.state_faith(state, player)
	var nat := emp_nature(state, player)
	var c := cd()
	match act:
		"seat":
			if nat != "eglise_universelle":
				return "il faut une foi d'État de l'Église universelle"
			if seats_taken(state, sf) >= int(c["eglise"]["seats"]):
				return "les 12 sièges du Collège sont pris"
			return _afford(state, player, seat_cost(state, sf, player))
		"bull":
			if nat != "eglise_universelle":
				return "il faut une foi d'État de l'Église universelle"
			if Faiths.head(state, sf) != player:
				return "seul le Primat émet des bulles"
			if not c["eglise"]["bulls"].has(String(args.get("kind", ""))):
				return "bulle inconnue"
			var b: Dictionary = _peek_faith(state, sf).get("bull", {})
			if not b.is_empty() and int(b["end"]) > state.tick:
				return "une bulle est déjà en vigueur (jusqu'au %s)" % GameCalendar.date_string(int(b["end"]))
			return ""
		"icon":
			if nat != "patriarcats":
				return "il faut une foi d'État des Patriarcats"
			if not c["patriarcats"]["icons"].has(String(args.get("kind", ""))):
				return "icône inconnue"
			var ic: Dictionary = _peek_emp(state, player).get("icon", {})
			if not ic.is_empty() and int(ic["end"]) > state.tick:
				return "une icône est déjà vénérée (jusqu'au %s)" % GameCalendar.date_string(int(ic["end"]))
			if authority(state, player) < int(c["patriarcats"]["icon_cost"]):
				return "il faut %d d'autorité" % int(c["patriarcats"]["icon_cost"])
			return ""
		"metro":
			if nat != "patriarcats":
				return "il faut une foi d'État des Patriarcats"
			var col: Colony = state.colonies.get(int(args.get("planet", -1)))
			if col == null or col.owner != player or not col.is_colony() or Faiths.majority(col) != sf:
				return "il faut une de vos colonies où la foi domine"
			if col.planet_id == int(Faiths.faith(state, sf)["holy"]):
				return "c'est déjà le monde saint"
			if int(_peek_emp(state, player).get("metro", -1)) == col.planet_id:
				return "c'est déjà votre métropolite"
			if authority(state, player) < int(c["patriarcats"]["metro_cost"]):
				return "il faut %d d'autorité" % int(c["patriarcats"]["metro_cost"])
			return ""
		"school":
			if nat != "loi_extase":
				return "il faut une foi d'État de la Voie de la Loi et de l'Extase"
			var s := String(args.get("school", ""))
			if not c["loi_extase"]["schools"].has(s):
				return "école inconnue"
			if school(state, player) == s:
				return "c'est déjà votre école"
			var at := int(_peek_emp(state, player).get("school_at", -100000))
			if school(state, player) != "" and state.tick - at < int(c["loi_extase"]["school_change_days"]):
				return "on ne change d'école qu'une fois tous les dix ans"
			return ""
		"harmonize":
			if nat != "harmonie":
				return "il faut une foi d'État de l'Harmonie"
			var tf := String(args.get("faith", ""))
			var pid := String(args.get("precept", ""))
			if Faiths.faith(state, tf).is_empty() or tf == sf:
				return "foi inconnue"
			if int(Faiths.followers_by_owner(state, tf).get(player, 0)) <= 0:
				return "cette foi n'a pas de fidèles chez vous"
			if not (Faiths.faith(state, tf)["precepts"] as Array).has(pid):
				return "ce précepte n'est pas celui de cette foi"
			var ed := _peek_emp(state, player)
			if (ed.get("harmed", []) as Array).has(tf):
				return "cette foi est déjà harmonisée"
			for h: Dictionary in ed.get("harm", []):
				if String(h["fid"]) == tf:
					return "harmonisation déjà en cours"
			var extra: Array = _peek_faith(state, sf).get("extra", [])
			if extra.size() + (ed.get("harm", []) as Array).size() >= harm_max(state, player):
				return "au plus %d préceptes harmonisés" % harm_max(state, player)
			if (Faiths.faith(state, sf)["precepts"] as Array).has(pid) or extra.has(pid):
				return "votre foi suit déjà ce précepte"
			if harmony(state, player) < harm_cost(state, player):
				return "il faut %d d'harmonie" % harm_cost(state, player)
			return ""
		"god_swap":
			if nat != "pantheon":
				return "il faut une foi d'État du Panthéon"
			if Faiths.head(state, sf) != player:
				return "seul le chef de foi change les dieux"
			var gods: Array = _peek_faith(state, sf).get("gods", [])
			var old := String(args.get("old", ""))
			var nw := String(args.get("new", ""))
			if not gods.has(old) or gods.has(nw) or not c["pantheon"]["domains"].has(nw):
				return "échange de dieux impossible"
			return ""
		"omen":
			if nat != "pantheon":
				return "il faut une foi d'État du Panthéon"
			if Faiths.head(state, sf) != player:
				return "seul le chef de foi invoque un présage"
			if not (_peek_faith(state, sf).get("gods", []) as Array).has(String(args.get("kind", ""))):
				return "ce dieu n'est pas au panthéon"
			if int(_peek_faith(state, sf).get("omen_next", 0)) > state.tick:
				return "le prochain présage viendra le %s" % GameCalendar.date_string(int(_peek_faith(state, sf)["omen_next"]))
			if FaithWars.zeal(state, sf) < -int(c["pantheon"]["omen_zeal"]):
				return "pas assez de zèle"
			return ""
		"welcome":
			if nat != "pantheon":
				return "il faut une foi d'État du Panthéon"
			if Faiths.head(state, sf) != player:
				return "seul le chef de foi accueille un dieu étranger"
			var tf := String(args.get("faith", ""))
			var wl: Array = _peek_faith(state, sf).get("welcome", [])
			if Faiths.faith(state, tf).is_empty() or tf == sf or wl.has(tf):
				return "foi inconnue ou déjà accueillie"
			if int(Faiths.followers_by_owner(state, tf).get(player, 0)) <= 0:
				return "cette foi n'a pas de fidèles chez vous"
			if wl.size() >= int(c["pantheon"]["welcome_max"]):
				return "au plus %d dieux accueillis" % int(c["pantheon"]["welcome_max"])
			return ""
		"offer":
			if nat != "dette_sang":
				return "il faut une foi d'État de la Dette de sang"
			var col: Colony = state.colonies.get(int(args.get("planet", -1)))
			if col == null or col.owner != player or not col.is_colony() or col.population < 2:
				return "il faut une de vos colonies d'au moins 2 habitants"
			if debt(state, sf) <= 0:
				return "la dette est payée"
			return ""
		"god_move":
			if nat != "dieu_present" and nat != "dieu_en_chantier":
				return "il faut une foi d'État du Dieu présent ou d'un dieu achevé"
			var g := live_god(state, sf)
			if g.is_empty():
				return "le dieu n'est pas parmi nous"
			if Faiths.head(state, sf) != player:
				return "seul l'empire où réside le dieu le guide"
			var t := int(args.get("system", -1))
			if t < 0 or t >= state.galaxy.systems.size():
				return "destination inconnue"
			if not e.explored.has(t):
				return "système inexploré"
			if FaithHeavy.disobeys(state, sf):
				return "le dieu n'obéit plus : il faut ranimer le zèle (30 ou plus)"
			return ""
	return FaithHeavy.check(state, player, act, args)


static func apply(state: GameState, player: int, act: String, args: Dictionary) -> void:
	var sf := Faiths.state_faith(state, player)
	var c := cd()
	match act:
		"seat":
			_pay(state, player, seat_cost(state, sf, player))
			var seats: Dictionary = fdat(state, sf)["seats"]
			seats[str(player)] = int(seats.get(str(player), 0)) + 1
		"bull":
			var kind := String(args["kind"])
			var fd := fdat(state, sf)
			fd["bull"] = {"kind": kind, "end": state.tick + int(c["eglise"]["bull_days"])}
			fd["reform"] = mini(int(c["eglise"]["reform_max"]), reform(state, sf) + int(c["eglise"]["reform_bull"]))
			if kind == "croisade":
				fd["free_crusade"] = true
			Relics.touch(state)
			state.add_chronicle("Bulle du Primat : « %s ». Les fidèles de %s s'inclinent ; les autres lisent par-dessus leur épaule." % [
					String(c["eglise"]["bulls"][kind]["label"]), Faiths.name_of(state, sf)])
		"icon":
			add_authority(state, player, -int(c["patriarcats"]["icon_cost"]))
			emp(state, player)["icon"] = {"kind": String(args["kind"]), "end": state.tick + int(c["patriarcats"]["icon_days"])}
			Relics.touch(state)
		"metro":
			add_authority(state, player, -int(c["patriarcats"]["metro_cost"]))
			emp(state, player)["metro"] = int(args["planet"])
		"school":
			emp(state, player)["school"] = String(args["school"])
			emp(state, player)["school_at"] = state.tick
		"harmonize":
			var ed := emp(state, player)
			ed["harmony"] = harmony(state, player) - harm_cost(state, player)
			if not ed.has("harm"):
				ed["harm"] = []
			(ed["harm"] as Array).append({"fid": String(args["faith"]), "pid": String(args["precept"]), "end": state.tick + int(c["harmonie"]["days"])})
		"god_swap":
			var gods: Array = fdat(state, sf)["gods"]
			gods[gods.find(String(args["old"]))] = String(args["new"])
			for s in state.galaxy.systems.size():
				if state.system_owner(s) == player:
					FaithWars.add_stab(state, s, "Dieu détrôné", int(c["pantheon"]["swap_stab"]), 360)
			Relics.touch(state)
		"omen":
			var fd := fdat(state, sf)
			fd["omen"] = {"kind": String(args["kind"]), "end": state.tick + 360}
			fd["omen_next"] = state.tick + int(c["pantheon"]["omen_days"])
			FaithWars.add_zeal(state, sf, int(c["pantheon"]["omen_zeal"]))
			Relics.touch(state)
		"welcome":
			var fd := fdat(state, sf)
			if not fd.has("welcome"):
				fd["welcome"] = []
			(fd["welcome"] as Array).append(String(args["faith"]))
		"offer":
			var col: Colony = state.colonies[int(args["planet"])]
			col.population -= 1
			col.growth = 0
			Faiths.normalize(col)
			add_debt(state, sf, int(c["dette"]["offer"]))
			state.add_chronicle("Sur %s, un habitant est offert au dieu de %s. La Dette baisse ; les volontaires aussi." % [
					state.galaxy.get_planet(col.planet_id).display_name(state.galaxy), Faiths.name_of(state, sf)], Espionage.private_to(state, [player]))
		"god_move":
			fdat(state, sf)["god"]["target"] = int(args["system"])
		_:
			FaithHeavy.apply(state, player, act, args)
	Relics.touch(state)


## Harmonie : coût d'une harmonisation et préceptes harmonisés au plus (talent des Vael).
static func harm_cost(state: GameState, eid: int) -> int:
	return int(FaithHeavy.talent(state, eid).get("harm_cost", cd()["harmonie"]["cost"]))


static func harm_max(state: GameState, eid: int) -> int:
	return int(cd()["harmonie"]["extra_max"]) + int(FaithHeavy.talent(state, eid).get("harm_extra", 0))


static func seats_taken(state: GameState, fid: String) -> int:
	var n := 0
	var seats: Dictionary = _peek_faith(state, fid).get("seats", {})
	for k in seats:
		n += int(seats[k])
	return n


static func seat_cost(state: GameState, fid: String, eid: int) -> Dictionary:
	var ed: Dictionary = cd()["eglise"]
	var held := int(_peek_faith(state, fid).get("seats", {}).get(str(eid), 0))
	return {"influence": int(ed["seat_cost"]["influence"]) + held * int(ed["seat_cost_step"])}


# --- IA -------------------------------------------------------------------------------------------

static func _credo_pick(state: GameState, eid: int, table: Dictionary) -> Variant:
	var credo := Events.layer_value(state, eid, "credo")
	return table.get(credo, table["default"])


static func _ai_gods(state: GameState, eid: int) -> Array:
	return (_credo_pick(state, eid, GameData.faiths()["ai"]["classic"]["gods_by_credo"]) as Array).duplicate()


static func ai(state: GameState) -> void:
	if not state.faith_on:
		return
	var ac: Dictionary = GameData.faiths()["ai"]["classic"]
	var c := cd()
	for e in state.empires:
		if e.eliminated or not e.is_ai() or GameState.is_npc(e.id):
			continue
		var sf := Faiths.state_faith(state, e.id)
		var nat := emp_nature(state, e.id)
		var res := int(e.resources.get("influence", 0))
		FaithHeavy.ai(state, e)
		match nat:
			"eglise_universelle":
				if res >= int(ac["seat_reserve"]) + int(seat_cost(state, sf, e.id).get("influence", 0)) and check(state, e.id, "seat", {}) == "":
					apply(state, e.id, "seat", {})
				var kind := String(_credo_pick(state, e.id, ac["bull_by_credo"]))
				if reform(state, sf) < 70 and check(state, e.id, "bull", {"kind": kind}) == "":
					apply(state, e.id, "bull", {"kind": kind})
			"patriarcats":
				var kind := String(_credo_pick(state, e.id, ac["icon_by_credo"]))
				if check(state, e.id, "icon", {"kind": kind}) == "":
					apply(state, e.id, "icon", {"kind": kind})
				elif authority(state, e.id) >= 90:
					for pid in state.sorted_colony_ids():
						if check(state, e.id, "metro", {"planet": pid}) == "":
							apply(state, e.id, "metro", {"planet": pid})
							break
			"loi_extase":
				if school(state, e.id) == "":
					apply(state, e.id, "school", {"school": String(_credo_pick(state, e.id, ac["school_by_credo"]))})
			"harmonie":
				for fid in Faiths.ids(state):
					var pr: Array = Faiths.faith(state, fid).get("precepts", [])
					if pr.is_empty():
						continue
					var args := {"faith": fid, "precept": String(pr[0])}
					if check(state, e.id, "harmonize", args) == "":
						apply(state, e.id, "harmonize", args)
						break
			"pantheon":
				var gods: Array = _peek_faith(state, sf).get("gods", [])
				if not gods.is_empty() and Faiths.head(state, sf) == e.id and FaithWars.zeal(state, sf) >= 60 and check(state, e.id, "omen", {"kind": String(gods[0])}) == "":
					apply(state, e.id, "omen", {"kind": String(gods[0])})
			"dette_sang":
				if debt(state, sf) >= 85:
					for pid in state.sorted_colony_ids():
						var col: Colony = state.colonies[pid]
						if col.owner == e.id and col.population >= 6 and check(state, e.id, "offer", {"planet": pid}) == "":
							apply(state, e.id, "offer", {"planet": pid})
							break
			"dieu_present", "dieu_en_chantier":
				# Le dieu reste près de la capitale, à l'abri.
				var g := live_god(state, sf)
				if not g.is_empty() and Faiths.head(state, sf) == e.id:
					var cap := state.galaxy.get_planet(e.capital_planet).system_id if e.capital_planet >= 0 else -1
					if cap >= 0 and int(g["target"]) != cap:
						fdat(state, sf)["god"]["target"] = cap


# --- Sauvegarde -----------------------------------------------------------------------------------

static func fix(state: GameState) -> void:
	var n := _nat(state)
	for k in n["emp"]:
		var e: Dictionary = n["emp"][k]
		for f in ["karma", "piety", "harmony", "authority", "school_at", "metro"]:
			if e.has(f):
				e[f] = int(e[f])
		if e.has("icon"):
			e["icon"]["end"] = int(e["icon"]["end"])
		for h: Dictionary in e.get("harm", []):
			h["end"] = int(h["end"])
	for k in n["faith"]:
		var d: Dictionary = n["faith"][k]
		for f in ["primat", "term_end", "reform", "omen_next", "debt"]:
			if d.has(f):
				d[f] = int(d[f])
		for s in d.get("seats", {}):
			d["seats"][s] = int(d["seats"][s])
		for x in ["bull", "omen"]:
			if d.has(x):
				d[x]["end"] = int(d[x]["end"])
		if d.has("god"):
			for f in ["sid", "target", "next", "dead_until"]:
				d["god"][f] = int(d["god"][f])
		for p in d.get("profaned", {}):
			d["profaned"][p] = int(d["profaned"][p])
		if d.has("free_crusade"):
			d["free_crusade"] = bool(d["free_crusade"])
		FaithHeavy.fix(d)
