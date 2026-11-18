class_name AiCapture
extends RefCounted
## IA et prises de guerre (voir Capture, CaptureLore, data/capture.json). Une fois tous les 10 jours, si
## le pilier est complet : ses flottes de guerre prennent la posture d'abordage (Normal et au-dessus, ou
## toujours chez un peuple à trophées), elle choisit sa politique d'épaves (les deux si elle le peut,
## sinon étudier ; ferrailler quand elle manque de matériaux), puis, dans ses chantiers, elle remet en état
## les prises abîmées qu'elle peut payer, revend celles qu'un peuple de profit sait vendre et démantèle les
## épaves flottantes (3 avaries ou plus) qu'elle ne peut pas réparer. Elle garde toujours grands et titans.
## Son butin suit la politique automatiquement (CaptureLore._auto_choice) ; elle accepte les redditions ;
## Vétéran et au-dessus, une flotte bien garnie aborde le Vaisseau-tombe quand elle le croise.

const PERIOD := 10


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not Capture.full(state) or e.is_npc() or e.eliminated:
		return
	@warning_ignore("integer_division")
	var slot := state.tick / PERIOD + 1
	if Capture.stat(state, e.id, "ai_slot") >= slot:
		return
	Capture.note_stat(state, e.id, "ai_slot", slot - Capture.stat(state, e.id, "ai_slot"))
	if AiPlayer._forgets(ctx):
		return
	var skill := AiPlayer._skill(ctx)
	var want_board := skill >= 1 or Capture.layer(state, e.id, "trophies")
	for f in AiPlayer._warfleets(ctx):
		if Capture.posture_open(state, f) and Capture.posture(state, f) != want_board:
			AiPlayer._issue(ctx, SimCommands.cap_act(e.id, "posture", {"fleet": f.id, "on": want_board}))
	_policy(ctx, e)
	for f in Fleets.empire_fleets(state, e.id):
		_prizes(ctx, state, e, f, skill)
		# Vaisseau-tombe : une flotte assez garnie qui passe par là tente sa chance (Vétéran et au-dessus).
		if skill >= 2 and CaptureTomb.system(state) == f.system_id \
				and AiPlayer._issue(ctx, SimCommands.cap_act(e.id, "tomb", {"fleet": f.id})):
			AiPlayer._intent(ctx, "Abordage du Vaisseau-tombe")


static func _policy(ctx: Dictionary, e: Empire) -> void:
	var state: GameState = ctx["state"]
	var want := "etudier"
	if CaptureLore.check_policy(state, e.id, "both") == "":
		want = "both"
	elif int(e.resources.get("materials", 0)) < 50:
		want = "ferrailler"
	if String(Capture.sub(state, "pol").get(str(e.id), "etudier")) != want:
		AiPlayer._issue(ctx, SimCommands.cap_act(e.id, "policy", {"x": want}))


static func _prizes(ctx: Dictionary, state: GameState, e: Empire, f: Fleet, skill: int) -> void:
	var done := {}
	for ship in f.ships.duplicate():
		if not Capture.is_prize(ship) or done.has(ship) or not f.ships.has(ship):
			continue
		done[ship] = true
		var d := {"fleet": f.id, "ship": ship}
		var n := Capture.avarie_count(ship)
		var big := ["large", "titan"].has(Combat.ship_size(ship))
		if Capture.layer(state, e.id, "scrappers") and not big \
				and AiPlayer._issue(ctx, SimCommands.cap_act(e.id, "sell", {"fleet": f.id, "ship": ship, "x": "market"})):
			AiPlayer._intent(ctx, "Revente d'une prise")
			continue
		if n > 0 and (n >= 2 or skill >= 2) and AiPlayer._issue(ctx, SimCommands.cap_act(e.id, "repair", d)):
			continue
		if n >= 3 and not big:
			AiPlayer._issue(ctx, SimCommands.cap_act(e.id, "scrap", d))
