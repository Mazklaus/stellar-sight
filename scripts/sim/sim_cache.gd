class_name SimCache
extends RefCounted
## Mode vérifié des caches gardés d'un jour à l'autre.
##
## Un cache qui survit au jour n'est admis dans la simulation que si l'on peut dire, en lisant l'état,
## qu'il est encore juste (voir Ground._sorted : même table, même compteur d'identifiants, même taille).
## Le mode vérifié en est le garde-fou : chaque valeur relue dans un tel cache est recalculée et
## comparée. Un écart est compté par nom dans SimCache.bad, signalé une fois en erreur, et la valeur
## fraîche est rendue (la partie reste juste). Variable d'environnement SS_CACHE_VERIFY=1, ou
## SimCache.verify = true dans un test (tests/endgame_perf_tests.gd).
static var verify := OS.get_environment("SS_CACHE_VERIFY") != ""
static var bad := {}
static var hits := {}
static var log: Array[String] = []
## Système du jour en cours (posé par Simulation.step et les outils), pour situer un écart.
static var where := ""


static func mismatch(name: String, detail: String) -> void:
	if not bad.has(name):
		push_error("SimCache : le cache « %s » a rendu une valeur périmée (%s)" % [name, detail])
	bad[name] = int(bad.get(name, 0)) + 1
	if log.size() < 200:
		log.append("%s : %s" % [name, detail])


static func count(d: Dictionary, name: String) -> void:
	d[name] = int(d.get(name, 0)) + 1
