class_name Empire
extends RefCounted
## Un empire (joueur humain ou IA). Son identifiant est aussi celui du joueur dans les ordres.

## Couleurs proposées aux empires (Nouvelle partie, et automatique quand deux empires se ressemblent).
const PALETTE := ["#e8b44a", "#c0392b", "#4a90e2", "#6fcf3a", "#9b59b6", "#e67e22", "#1abc9c", "#e84393",
		"#ecf0f1", "#8d6e63", "#95a5a6", "#c8d64a"]
## Écart (somme des écarts RVB) sous lequel deux couleurs d'empire se confondent sur la carte.
const COLOR_MIN_GAP := 0.35

var id: int = -1
var faction_id: String = ""
## Couleur propre à cet empire (code html) ; "" = celle de son peuple. Sert quand deux empires partagent
## un peuple, ou quand le joueur choisit une couleur dans Nouvelle partie.
var color_hex: String = ""
## Complément de nom quand plusieurs empires partagent un peuple (« II », « III »…) ; "" sinon.
var name_suffix: String = ""
## Départ avancé choisi dans Nouvelle partie (affiché dans le tableau des empires).
var advanced_start := false
## Stocks : {"energy": int, "materials": int, ...}.
var resources: Dictionary = {}
var capital_planet: int = -1
## Capitale d'origine (planète du monde natal), qui compte pour la victoire par conquête même perdue.
var home_planet: int = -1
## Pénuries constatées au dernier bilan mensuel.
var starving: bool = false
var blackout: bool = false
## Systèmes explorés (vus au moins une fois) : id -> true. Le reste de la galaxie est dans le brouillard.
var explored: Dictionary = {}
## Dernière information connue (voir Intel) : système -> {"day": jour du relevé, "info": relevé}.
var intel: Dictionary = {}
## Plus courts chemins par les routes connues, depuis chaque système déjà demandé (Fleets._dijkstra) :
## donnée dérivée, non sauvegardée, valable tant que explored n'a pas grandi.
var path_cache: Dictionary = {}
var path_cache_explored := -1
var _faction_cache: Dictionary = {}
var _faction_gen := -1
var _faction_id_cached := ""
## Empires rencontrés (identifiants, triés).
var contacts: Array[int] = []
## Empires avec qui il est en guerre (identifiants, triés). La guerre vaut dans les deux sens.
var wars: Array[int] = []
## Plus aucune revendication : l'empire a disparu de la galaxie (ses flottes avec lui).
var eliminated: bool = false
## Vaisseaux sortis des chantiers, par classe (sert à numéroter les nouvelles flottes).
var ships_built: Dictionary = {}
## Traits de faction (voir FactionTraits) : ferveur du Chœur Éternel, dissidence des fiefs lointains
## d'Ossarane (cristaux manquants au dernier bilan), matériaux digérés en biomasse par l'Essaim.
var fervor: int = 0
var dissent: bool = false
var biomass: int = 0
## Diplomatie (voir Diplomacy) : loyauté de l'héritier d'une dynastie féodale (-1 = pas d'héritier),
## dernier empire qui l'a soudoyé (-1 = aucun), dernier arbitrage d'une république (jour).
var heir_loyalty: int = -1
var heir_suitor: int = -1
var mediation_tick: int = -100000
## Niveau de l'IA qui dirige cet empire (voir AiLevels) ; "" = un joueur humain.
var ai_level: String = ""
## Tempérament de l'IA (voir AiLevels.temperament) : son attitude envers les autres empires.
var ai_temperament: String = ""
## Dernière intention notable de l'IA, pour le mode spectateur. Simple affichage : jamais sauvegardée,
## jamais lue par la simulation (elle ne peut donc pas casser le déterminisme).
var ai_intent: String = ""
## Recherche (voir Research) : technologies découvertes (id -> true), file de recherche (la première
## est en cours), Savoir déjà investi dans la recherche en cours, et travail mis de côté quand une
## recherche a été interrompue (id -> Savoir investi).
var techs: Dictionary = {}
var research_queue: Array[String] = []
var research_progress: int = 0
var research_shelf: Dictionary = {}
## États successifs des marques d'armes et de défenses ({famille: marque}) : les vaisseaux y renvoient
## par indice (Fleet.gen). Une entrée s'ajoute quand une marque change.
var marks_log: Array[Dictionary] = []
## Faits d'armes et de règne comptés pour les eurêkas : kills, ships_lost, battles_won, conquests,
## besieged, wars, built, sacrifices.
var stats: Dictionary = {}
## Eurêkas déjà obtenus (id de technologie -> true).
var eurekas: Dictionary = {}
## Victoires (voir VictorySystem) : id de victoire -> {"pct": avancée au dernier bilan, "held": jours
## de compte à rebours déjà tenus, "warn": dernière alerte donnée}.
var victory: Dictionary = {}
## Espionnage (voir Espionage) : dossiers de renseignement {empire visé: dossier}, tenus par les
## réseaux au palier Comptables ou plus ; sondes prêtes et jour de la dernière sonde rendue.
var dossiers: Dictionary = {}
var probes: int = 0
var probe_day: int = 0
## Effets cumulés des technologies, recalculés quand tech_fx_n ne correspond plus (jamais sauvegardés).
var tech_fx: Dictionary = {}
var tech_fx_exalted: Dictionary = {}
var tech_fx_n: int = -1
## Marques actuelles {famille: marque}, recalculées avec tech_fx.
var tech_marks: Dictionary = {}
## Une technologie connue change-t-elle d'effet quand le peuple est exalté ?
var tech_fx_has_exalted: bool = false
## Population logeable par type de planète (pourcentage d'habitabilité, 0 si aucune), même règle.
var hab_cache: Dictionary = {}
var hab_cache_n: int = -1


func is_ai() -> bool:
	return ai_level != ""


func faction() -> Dictionary:
	# Fiche gardée tant que les peuples créés ne changent pas (appelée sans cesse par la simulation).
	if _faction_gen != GameData.factions_gen or _faction_id_cached != faction_id:
		_faction_cache = GameData.faction(faction_id)
		_faction_gen = GameData.factions_gen
		_faction_id_cached = faction_id
	return _faction_cache


func display_name() -> String:
	return _with_suffix(String(faction().get("name", faction_id)))


func short_name() -> String:
	return _with_suffix(String(faction().get("short", faction_id)))


func _with_suffix(base: String) -> String:
	return base if name_suffix == "" else "%s %s" % [base, name_suffix]


func color() -> Color:
	if color_hex != "" and Color.html_is_valid(color_hex):
		return Color.html(color_hex)
	return Color.html(String(faction().get("color", "#ffffff")))


## Cette couleur se confond-elle avec l'une de celles déjà prises ?
static func color_taken(c: Color, used: Array[Color]) -> bool:
	for u in used:
		if absf(c.r - u.r) + absf(c.g - u.g) + absf(c.b - u.b) < COLOR_MIN_GAP:
			return true
	return false


func to_dict() -> Dictionary:
	return {
		"id": id,
		"faction": faction_id,
		"color": color_hex,
		"suffix": name_suffix,
		"advanced": advanced_start,
		"resources": resources.duplicate(),
		"capital": capital_planet,
		"home": home_planet,
		"starving": starving,
		"blackout": blackout,
		"explored": sorted_explored(),
		"intel": Intel.to_list(self),
		"contacts": Array(contacts),
		"ships_built": ships_built.duplicate(),
		"fervor": fervor,
		"dissent": dissent,
		"biomass": biomass,
		"ai": ai_level,
		"temper": ai_temperament,
		"wars": Array(wars),
		"eliminated": eliminated,
		"heir": heir_loyalty,
		"suitor": heir_suitor,
		"mediation": mediation_tick,
		"techs": sorted_techs(),
		"queue": Array(research_queue),
		"progress": research_progress,
		"shelf": _sorted_shelf(),
		"marks_log": marks_log.duplicate(true),
		"stats": stats.duplicate(),
		"eurekas": sorted_eurekas(),
		"victory": _sorted_victory(),
		"dossiers": _sorted_dossiers(),
		"probes": probes,
		"probe_day": probe_day,
	}


func _sorted_dossiers() -> Array:
	var ids := dossiers.keys()
	ids.sort()
	var out := []
	for k in ids:
		var d: Dictionary = (dossiers[k] as Dictionary).duplicate(true)
		d["about"] = int(k)
		out.append(d)
	return out


func _sorted_victory() -> Array:
	var ids := victory.keys()
	ids.sort()
	var out := []
	for k in ids:
		var v: Dictionary = victory[k].duplicate()
		v["id"] = k
		out.append(v)
	return out


func sorted_eurekas() -> Array:
	var ids := eurekas.keys()
	ids.sort()
	return ids


func sorted_techs() -> Array:
	var ids := techs.keys()
	ids.sort()
	return ids


func _sorted_shelf() -> Array:
	var ids := research_shelf.keys()
	ids.sort()
	var out := []
	for k in ids:
		out.append([k, research_shelf[k]])
	return out


func sorted_explored() -> Array:
	var ids := explored.keys()
	ids.sort()
	return ids


static func from_dict(d: Dictionary) -> Empire:
	var e := Empire.new()
	e.id = int(d["id"])
	e.faction_id = String(d["faction"])
	e.color_hex = String(d.get("color", ""))
	e.name_suffix = String(d.get("suffix", ""))
	e.advanced_start = bool(d.get("advanced", false))
	for r in GameData.resource_ids():
		e.resources[r] = int(d["resources"].get(r, 0))
	e.capital_planet = int(d["capital"])
	e.home_planet = int(d.get("home", e.capital_planet))
	e.starving = bool(d["starving"])
	e.blackout = bool(d["blackout"])
	for sid in d["explored"]:
		e.explored[int(sid)] = true
	Intel.from_list(e, d.get("intel", []))
	for c in d["contacts"]:
		e.contacts.append(int(c))
	for k in d["ships_built"]:
		e.ships_built[String(k)] = int(d["ships_built"][k])
	e.fervor = int(d.get("fervor", 0))
	e.dissent = bool(d.get("dissent", false))
	e.biomass = int(d.get("biomass", 0))
	e.ai_level = String(d.get("ai", ""))
	e.ai_temperament = String(d.get("temper", ""))
	for w in d.get("wars", []):
		e.wars.append(int(w))
	e.wars.sort()
	e.eliminated = bool(d.get("eliminated", false))
	e.heir_loyalty = int(d.get("heir", -1))
	e.heir_suitor = int(d.get("suitor", -1))
	e.mediation_tick = int(d.get("mediation", -100000))
	for t in d.get("techs", []):
		e.techs[String(t)] = true
	for t in d.get("queue", []):
		e.research_queue.append(String(t))
	e.research_progress = int(d.get("progress", 0))
	for pair in d.get("shelf", []):
		e.research_shelf[String(pair[0])] = int(pair[1])
	for m in d.get("marks_log", []):
		var md := {}
		for k in m:
			md[String(k)] = int(m[k])
		e.marks_log.append(md)
	var st: Dictionary = d.get("stats", {})
	for k in st:
		e.stats[String(k)] = int(st[k])
	for t in d.get("eurekas", []):
		e.eurekas[String(t)] = true
	for v: Dictionary in d.get("victory", []):
		e.victory[String(v["id"])] = {"pct": int(v.get("pct", 0)), "held": int(v.get("held", 0)), "warn": int(v.get("warn", 0))}
	for dd: Dictionary in d.get("dossiers", []):
		var dos: Dictionary = GameData._to_ints(dd)
		var about := int(dos["about"])
		dos.erase("about")
		e.dossiers[about] = dos
	e.probes = int(d.get("probes", int(GameData.espionage()["probes"]["start"])))
	e.probe_day = int(d.get("probe_day", 0))
	return e
