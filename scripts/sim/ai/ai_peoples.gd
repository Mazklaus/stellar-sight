class_name AiPeoples
extends RefCounted
## Peuples mêlés des empires IA (étude « Populations mixtes et migrations », lot 2, proposition 24) :
## une fois par mois, décalé selon l'empire, elle revoit le statut des autres espèces qui vivent chez
## elle. Belliqueuse (agressivité 2 ou plus) : elle assujettit quand elle le peut ; pacifique (-2 ou
## moins) : citoyens ; entre les deux : résidents tant qu'ils sont mal intégrés, puis citoyens, et elle
## cède à une doléance « Des droits pour mon peuple » si elle n'est pas belliqueuse. La Recrue laisse
## le statut par défaut. L'IA n'expulse ni n'extermine jamais (choix réservés aux joueurs et, plus
## tard, aux peuples dont la vision du monde l'exige).
## Lois : Hospitalité si elle est pacifique et compte d'autres peuples, Préférence native si elle est
## belliqueuse et que son peuple domine ses systèmes.


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	if not Peoples.enabled(state):
		return
	var e: Empire = ctx["e"]
	var every := maxi(1, int(ctx["lv"].get("think_days", 10)))
	if posmod(state.tick + e.id * 7 + 5, 30) >= every:
		return
	var skill := int(ctx["lv"].get("faction_use", 1))
	if skill <= 0:
		return
	var ag := AiLevels.aggression(e)
	var demand := Peoples.rights_demand(state, e.id)
	var fp := Peoples.foreign_pop(state, e.id)
	var keys := fp.keys()
	keys.sort()
	for fid in keys:
		var want := desired(state, e, String(fid), ag, demand)
		if want != "" and want != Peoples.status(state, e.id, String(fid)):
			AiPlayer._issue(ctx, SimCommands.peoples_status(e.id, String(fid), want))


## Statut voulu pour une espèce ("" = ne rien changer).
static func desired(state: GameState, e: Empire, fid: String, ag: int, demand: Dictionary) -> String:
	var ok := Peoples.allowed_statuses(state, e.id, fid)
	if ag >= 2 and ok.has("assujettis"):
		return "assujettis"
	if not ok.has("citoyens"):
		return Peoples.default_status(state, e.id, fid)
	if ag <= -2 or String(demand.get("fid", "")) == fid:
		return "citoyens"
	if Peoples.status(state, e.id, fid) == "citoyens" and Peoples.next_change(state, e.id, fid) > 0:
		return ""  # déjà promus : on ne revient pas en arrière
	var integ := Peoples.empire_integration(state, e.id, fid)
	if integ >= 0 and integ < int(Peoples.data().get("integration", {}).get("low_below", 50)) and ok.has("residents"):
		return "residents"
	return "citoyens"


## Score d'une loi des peuples pour AiPolitics._laws (-1 : jamais).
static func law_score(state: GameState, e: Empire, id: String, ag: int) -> int:
	if not Peoples.enabled(state):
		return -1
	var fp := Peoples.foreign_pop(state, e.id)
	var foreign := 0
	for fid in fp:
		foreign += int(fp[fid])
	var pop := maxi(1, Laws.empire_pop(state, e.id))
	if id == "hospitalite":
		return 20 if ag <= -1 and foreign * 10 >= pop else -1
	if id == "preference_native":
		return 15 if ag >= 2 and foreign * 10 < pop else -1
	return -1
