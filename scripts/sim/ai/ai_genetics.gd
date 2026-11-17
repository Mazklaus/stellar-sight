class_name AiGenetics
extends RefCounted
## IA et ingénierie des espèces (prop. 40 ; voir Genetics, data/genetics.json « ai »).
## Une fois par mois, si l'option est en jeu, qu'aucun programme ne tourne et que le Savoir en stock
## dépasse le plancher : l'IA façonne son espèce fondatrice (le trait le plus cher que sa marge
## permet, son point fort d'abord), choisit une voie d'élévation après trois programmes (synthétique
## pour un corps de métal, cybernétique si elle a les implants, génétique sinon) ou jure la Pureté
## avant tout programme si son credo le veut. La Recrue oublie souvent (erreurs de niveau).

static func cfg() -> Dictionary:
	return Genetics.cfg("ai")


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not Genetics.applies(state, e.id):
		return
	if posmod(state.tick + e.id * 7, int(GameData.rules()["month_days"])) != 0:
		return
	if AiPlayer._skill(ctx) < int(cfg().get("min_skill", 0)) or AiPlayer._forgets(ctx):
		return
	_path(ctx)
	if e.gene_path == "purete" or not Genetics.programs(state, e.id).is_empty():
		return
	if int(e.resources.get(Genetics.resource_for(state, e.id, e.faction_id), 0)) < int(cfg().get("knowledge_floor", 150)):
		return
	var tid := best_trait(state, e.id, e.faction_id)
	if tid != "":
		AiPlayer._issue(ctx, SimCommands.gen_act(e.id, "mod", {"fid": e.faction_id, "add": [tid]}))
		AiPlayer._intent(ctx, "façonner son espèce (%s)" % Genetics.trait_label(tid))
	elif Genetics.check_cyber(state, e.id, e.faction_id) == "":
		AiPlayer._issue(ctx, SimCommands.gen_act(e.id, "cyber", {"fid": e.faction_id}))


static func _path(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if e.gene_path != "":
		return
	var credo := String(FactionTraits.species(e.faction()).get("credo", ""))
	if (cfg().get("path_purete_credo", []) as Array).has(credo) and Genetics.check_path(state, e.id, "purete") == "":
		AiPlayer._issue(ctx, SimCommands.gen_act(e.id, "path", {"path": "purete"}))
		return
	var want := "genetique"
	if not Genetics.is_organic(e.faction()):
		want = "synthetique"
	elif Genetics.has_power(state, e.id, "cyber"):
		want = "cybernetique"
	if Genetics.check_path(state, e.id, want) == "":
		AiPlayer._issue(ctx, SimCommands.gen_act(e.id, "path", {"path": want}))


## Trait à ajouter : le plus cher que la marge permet ; à coût égal, celui qui sert le point fort.
static func best_trait(state: GameState, eid: int, fid: String) -> String:
	var f := Genetics.fiche(state, eid, fid)
	var strong := Genetics.strong_of(f)
	var best := ""
	var best_score := -1
	for t: Dictionary in Genetics.catalogue():
		var c := int(t.get("cost", 0))
		if c <= 0:
			continue
		var tid := String(t["id"])
		var score := c * 10
		if (t.get("fields", {}).get("production_pct", {}) as Dictionary).has(strong):
			score += 5
		if score <= best_score:
			continue
		if Genetics.check_mod(state, eid, fid, [tid], [], "") != "":
			continue
		best = tid
		best_score = score
	return best
