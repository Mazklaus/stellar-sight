class_name WindowsFirewall
extends RefCounted
## Pare-feu Windows : vérifie et crée la règle qui laisse entrer les joueurs. La règle est étroite :
## entrées UDP sur le port de la partie, pour ce programme seulement. Si Windows a créé des règles de
## blocage pour ce programme (fenêtre « Autoriser l'accès » refusée ou fermée), elles passent avant
## toute autorisation : on les retire, sur ce programme seulement. Créer la règle demande les droits
## administrateur (fenêtre de Windows « Voulez-vous autoriser… ? »).

const RULE_NAME := "Stellar Sight"
## Nom de la règle créée avant la correction du nom du jeu : retirée quand on recrée la règle.
const LEGACY_RULE_NAME := "Stellar Sigth"
const MANUAL := "À la main : menu Démarrer → « Autoriser une application via le pare-feu Windows » → « Modifier les paramètres », cochez Privé et Public sur chaque ligne Godot (« Autoriser une autre application » si elle manque)."


static func available() -> bool:
	return OS.get_name() == "Windows"


## Chemin de ce programme tel que Windows le range (barres inverses).
static func program() -> String:
	return OS.get_executable_path().replace("/", "\\")


## Chemin du programme, entre apostrophes PowerShell.
static func _ps_quote(s: String) -> String:
	return "'" + s.replace("'", "''") + "'"


## Script de lecture (sans droits) : affiche « allow=N block=N ». Une autorisation compte si c'est
## notre règle (UDP sur le port) ou une règle de Windows qui laisse entrer ce programme en UDP
## (celle que crée la fenêtre « Autoriser l'accès » quand on accepte).
static func check_script(program: String, port: int) -> String:
	return ("$p = %s; $a = @(Get-NetFirewallRule -DisplayName %s -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq 'True' -and $_.Action -eq 'Allow' -and $_.Direction -eq 'Inbound' } | Get-NetFirewallPortFilter | Where-Object { $_.Protocol -eq 'UDP' -and $_.LocalPort -eq '%d' }).Count; "
			+ "$a += @(Get-NetFirewallApplicationFilter -Program $p -ErrorAction SilentlyContinue | Get-NetFirewallRule | Where-Object { $_.Enabled -eq 'True' -and $_.Action -eq 'Allow' -and $_.Direction -eq 'Inbound' } | Get-NetFirewallPortFilter | Where-Object { $_.Protocol -eq 'UDP' -or $_.Protocol -eq 'Any' }).Count; "
			+ "$b = @(Get-NetFirewallApplicationFilter -Program $p -ErrorAction SilentlyContinue | Get-NetFirewallRule | Where-Object { $_.Enabled -eq 'True' -and $_.Action -eq 'Block' -and $_.Direction -eq 'Inbound' }).Count; "
			+ "Write-Output \"allow=$a block=$b\"") % [_ps_quote(program), _ps_quote(RULE_NAME), port]


## Script administrateur : retire les blocages de ce programme et (re)crée la règle.
static func fix_script(program: String, port: int) -> String:
	return ("$p = %s; Get-NetFirewallApplicationFilter -Program $p -ErrorAction SilentlyContinue | Get-NetFirewallRule | Where-Object { $_.Action -eq 'Block' -and $_.Direction -eq 'Inbound' } | Remove-NetFirewallRule; "
			+ "Remove-NetFirewallRule -DisplayName %s -ErrorAction SilentlyContinue; "
			+ "Remove-NetFirewallRule -DisplayName %s -ErrorAction SilentlyContinue; "
			+ "New-NetFirewallRule -DisplayName %s -Direction Inbound -Action Allow -Protocol UDP -LocalPort %d -Program $p -Profile Any | Out-Null") % [
			_ps_quote(program), _ps_quote(LEGACY_RULE_NAME), _ps_quote(RULE_NAME), _ps_quote(RULE_NAME), port]


## Commande encodée pour powershell -EncodedCommand (UTF-16LE en base64 : aucun souci de guillemets).
static func encode(script: String) -> String:
	return Marshalls.raw_to_base64(script.to_utf16_buffer())


## État : {"ok": règle présente et aucun blocage, "allow": n, "block": n, "error": ""}.
static func status(port: int) -> Dictionary:
	if not available():
		return {"ok": false, "allow": 0, "block": 0, "error": "pas sous Windows"}
	var out := []
	var code := OS.execute("powershell", ["-NoProfile", "-NonInteractive", "-EncodedCommand", encode(check_script(program(), port))], out, true)
	var text := "".join(PackedStringArray(out))
	var allow := -1
	var block := -1
	for part in text.strip_edges().split(" "):
		if part.begins_with("allow="):
			allow = int(part.trim_prefix("allow="))
		elif part.begins_with("block="):
			block = int(part.trim_prefix("block="))
	if code != 0 or allow < 0 or block < 0:
		return {"ok": false, "allow": 0, "block": 0, "error": "lecture du pare-feu impossible (%s)" % text.strip_edges().substr(0, 120)}
	return {"ok": allow > 0 and block == 0, "allow": allow, "block": block, "error": ""}


## Crée la règle (fenêtre administrateur de Windows). Bloque jusqu'à la réponse du joueur.
static func fix(port: int) -> Dictionary:
	if not available():
		return status(port)
	var inner := encode(fix_script(program(), port))
	OS.execute("powershell", ["-NoProfile", "-NonInteractive", "-Command",
			"Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList '-NoProfile -NonInteractive -EncodedCommand %s'" % inner], [], true)
	var st := status(port)
	st["tried"] = true
	return st


## Texte pour le joueur.
static func describe(st: Dictionary) -> String:
	if String(st.get("error", "")) != "":
		return "Pare-feu Windows : %s. %s" % [st["error"], MANUAL]
	if bool(st.get("ok", false)):
		return "Pare-feu Windows : les joueurs peuvent entrer (règle « %s » ou autorisation donnée à ce programme), rien à faire." % RULE_NAME
	if bool(st.get("tried", false)):
		return "Pare-feu Windows : la règle n'a pas pu être créée (accord administrateur refusé, ou compte sans droits d'administrateur). " + MANUAL
	if int(st.get("block", 0)) > 0:
		return "Pare-feu Windows : des règles BLOQUENT ce programme (fenêtre « Autoriser l'accès » refusée). Cliquez « Autoriser dans le pare-feu »."
	return "Pare-feu Windows : rien ne laisse entrer les joueurs. Cliquez « Autoriser dans le pare-feu »."
