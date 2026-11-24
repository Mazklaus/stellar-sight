class_name PortsUi
extends RefCounted
## Onglet « Réseau » de l'écran Commerce (C ; voir Ports, étude « Spatioports », prop. 18 et 34).
## Tableau d'approvisionnement à la Distant Worlds 2 (colonies Desservies / Limite / Isolées /
## Enclaves pour Construction, Luxe, Nourriture), fret du réseau, liste des ports (niveau, portée,
## relié ou coupé, réserve, blocus) et des colonies mal desservies avec leurs causes. Lecture seule :
## on agit en construisant des ports (vue système) ; aucun ordre propre.

const W := 760.0
const STATE_COLORS := [Color(0.42, 0.75, 0.55), Color(0.86, 0.76, 0.36), Color(0.88, 0.5, 0.3), Color(0.85, 0.33, 0.31)]


static func build(es: EmpireScreens, col: VBoxContainer) -> void:
	var state := es._state
	var player := es._player
	if not Ports.enabled(state) or state.get_empire(player) == null:
		col.add_child(UiTheme.dim("Les spatioports ne sont pas en jeu dans cette partie.", 14))
		return
	col.add_child(_summary_block(es))
	col.add_child(_ports_block(es))
	col.add_child(_colonies_block(es))


static func signature(es: EmpireScreens) -> String:
	var state := es._state
	if state.ports.is_empty():
		return ""
	return str(hash([state.ports.get("nodes", {}), state.ports.get("st", {}), state.ports.get("fr", {}).get(str(es._player), [])]))


static func _label(text: String, width := 0.0, color := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	if width > 0:
		l.custom_minimum_size = Vector2(width, 0)
	if color.a > 0:
		l.add_theme_color_override("font_color", color)
	return l


static func _summary_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var label := String(Ports.mode_defs().filter(func(m: Dictionary) -> bool: return String(m["id"]) == Ports.mode(state))[0]["label"])
	var b := Widgets.Block.new("Réseau de distribution (%s)" % label.to_lower())
	b.body.add_child(UiTheme.paragraph("La production matérielle (énergie, matériaux, nourriture, cristaux) d'une colonie ne rejoint le stock de l'empire qu'à hauteur de sa desserte : 100 %% dans la portée d'un port relié à la capitale, puis -%d %% par saut, jamais sous %d %%. Savoir et Influence ne passent pas par les ports." % [
			Ports.c_int("service", "per_jump"), Ports.c_int("service", "floor")], W, 13))
	# Tableau d'approvisionnement (DW2) : une ligne par flux, une colonne par état.
	var g := GridContainer.new()
	g.columns = 5
	g.add_theme_constant_override("h_separation", 28)
	b.body.add_child(g)
	g.add_child(_label("Approvisionnement", 0, UiTheme.TEXT_DIM))
	for i in 4:
		g.add_child(_label(Ports.state_label(i), 0, STATE_COLORS[i]))
	var counts := Ports.supply_table(state, player)
	var flows := [["Production", "Part de la production qui rejoint le stock."]]
	if Ports.full(state):
		flows.append(["Construction", "Chantiers de bâtiments : un jour sur 4 perdu en Limite, un sur 2 en Isolée ou Enclave."])
		flows.append(["Luxe", "Bonus de stabilité des luxes : moitié en Limite, rien en Isolée ou Enclave."])
		flows.append(["Nourriture", "Une enclave qui mange plus qu'elle ne produit cesse de grandir."])
	for f in flows:
		var k := _label(String(f[0]))
		k.tooltip_text = String(f[1])
		k.mouse_filter = Control.MOUSE_FILTER_STOP
		g.add_child(k)
		for i in 4:
			var v := _label(str(counts[i]))
			v.theme_type_variation = &"Numbers"
			g.add_child(v)
	if Ports.full(state):
		var fr := Ports.freight(state, player)
		var fl := _label("Fret du réseau : %d disponibles pour %d demandés (%d %%)" % [int(fr[1]), int(fr[0]), int(fr[2])],
				0, STATE_COLORS[0] if int(fr[2]) >= 100 else STATE_COLORS[2])
		fl.tooltip_text = "Disponible : %d par niveau de port relié, %d par cargo privé, technologies et talents.\nDemandé : 1 par colonie hors du système d'un port, +1 par saut au-delà de la portée.\nSous le besoin, la desserte au-dessus du plancher baisse d'autant." % [
				Ports.c_int("freight", "per_level"), Ports.c_int("freight", "per_cargo")]
		fl.mouse_filter = Control.MOUSE_FILTER_STOP
		b.body.add_child(fl)
	for t in Ports.talent_labels(state, player):
		b.body.add_child(UiTheme.dim("%s : %s" % [String(t[0]), String(t[1])], 13))
	return b


## Schéma des liaisons : les systèmes colonisés de l'empire et les voies qui les relient.
## {"nodes": [{sid, pos, name, port (niveau, 0 sans port), state (0 relié, 2 coupé, 3 non relié ou bloqué), capital}], "links": [[i, j]]}.
static func schema(state: GameState, player: int) -> Dictionary:
	var nodes: Array[Dictionary] = []
	var index := {}
	var cap := FactionTraits.capital_system(state, player)
	for sid in Stability.systems_of(state, player):
		var n := Ports.node(state, player, sid)
		var st := 0
		if not n.is_empty():
			if int(n.get("bk", 0)) == 1 or int(n.get("lk", 0)) != 1:
				st = 3
			if int(n.get("cut", 0)) == 1 and int(n.get("bk", 0)) != 1:
				st = 2
		index[sid] = nodes.size()
		nodes.append({"sid": sid, "pos": state.galaxy.systems[sid].position, "name": state.galaxy.systems[sid].system_name,
				"port": int(n.get("l", 0)) if not n.is_empty() else 0, "has_port": not n.is_empty(), "state": st, "capital": sid == cap})
	var links: Array = []
	for sid: int in index:
		for nb in state.galaxy.systems[sid].neighbors:
			if index.has(int(nb)) and int(nb) > sid:
				links.append([index[sid], index[int(nb)]])
	return {"nodes": nodes, "links": links}


## Dessin du schéma : un carré par port (couleur de son état), un point par système sans port,
## un losange doré pour la capitale.
class Schema:
	extends Control
	var data := {}

	func _init(d: Dictionary, w := 420.0, h := 240.0) -> void:
		data = d
		custom_minimum_size = Vector2(w, h)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func fitted() -> PackedVector2Array:
		var out := PackedVector2Array()
		var nodes: Array = data.get("nodes", [])
		if nodes.is_empty():
			return out
		var lo: Vector2 = nodes[0]["pos"]
		var hi := lo
		for n: Dictionary in nodes:
			lo = lo.min(n["pos"])
			hi = hi.max(n["pos"])
		var span := (hi - lo).max(Vector2(1, 1))
		var inner := size - Vector2(40, 36)
		var k := minf(inner.x / span.x, inner.y / span.y)
		var off := Vector2(20, 12) + (inner - span * k) * 0.5
		for n: Dictionary in nodes:
			out.append(off + ((n["pos"] as Vector2) - lo) * k)
		return out

	func _draw() -> void:
		var pts := fitted()
		var nodes: Array = data.get("nodes", [])
		for l: Array in data.get("links", []):
			draw_line(pts[int(l[0])], pts[int(l[1])], Color(1, 1, 1, 0.22), 1.0, true)
		var font := get_theme_default_font()
		for i in nodes.size():
			var n: Dictionary = nodes[i]
			var p := pts[i]
			if bool(n["has_port"]):
				var c: Color = PortsUi.STATE_COLORS[int(n["state"])]
				var half := 3.0 + minf(3.0, float(n["port"]))
				draw_rect(Rect2(p - Vector2(half, half), Vector2(half, half) * 2.0), c)
				draw_string(font, p + Vector2(-40, half + 12), String(n["name"]), HORIZONTAL_ALIGNMENT_CENTER, 80, 11, Color(1, 1, 1, 0.75))
			else:
				draw_circle(p, 2.5, Color(1, 1, 1, 0.45))
			if bool(n["capital"]):
				var r := 9.0
				draw_polyline(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0), p + Vector2(0, -r)]), UiTheme.GOLD, 1.5, true)


static func _ports_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var ids := Ports.nodes_of(state, player)
	var b := Widgets.Block.new("Vos ports (%d)" % ids.size())
	if ids.is_empty():
		b.body.add_child(UiTheme.dim("Aucun port : bâtissez un Comptoir, puis améliorez-le en Spatioport.", 13))
		return b
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 30)
	b.body.add_child(split)
	var g := GridContainer.new()
	g.columns = 5
	g.add_theme_constant_override("h_separation", 22)
	g.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	split.add_child(g)
	var draw := Schema.new(schema(state, player))
	draw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(draw)
	b.body.add_child(UiTheme.dim("Schéma : un carré par port, à la couleur de son état ; un point par système sans port ; le losange marque la capitale.", 12))
	for h in ["Système", "Port", "Portée", "État", "Réserve"]:
		g.add_child(_label(h, 0, UiTheme.TEXT_DIM))
	for sid in ids:
		var n := Ports.node(state, player, sid)
		var lvl := int(n["l"])
		g.add_child(_label(state.galaxy.systems[sid].system_name, 160))
		g.add_child(_label(Ports.level_label(lvl)))
		g.add_child(_label("%d saut%s" % [int(n["r"]), "s" if int(n["r"]) > 1 else ""]))
		var stt := "Relié"
		var color: Color = STATE_COLORS[0]
		if int(n.get("bk", 0)) == 1:
			stt = "Bloqué"
			color = STATE_COLORS[3]
		elif int(n.get("cut", 0)) == 1:
			stt = "Coupé (sur réserve)"
			color = STATE_COLORS[2]
		elif int(n.get("lk", 0)) != 1:
			stt = "Non relié"
			color = STATE_COLORS[3]
		g.add_child(_label(stt, 0, color))
		var mx := Ports.warehouse_max(state, player, lvl)
		g.add_child(_label("%d / %d j" % [int(n["res"]), mx] if Ports.full(state) and lvl >= 1 else "-"))
	return b


static func _colonies_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var b := Widgets.Block.new("Colonies mal desservies")
	var n := 0
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != player or not c.is_established():
			continue
		var cs := Ports.colony_state(state, pid)
		if cs == Ports.OK:
			continue
		n += 1
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		b.body.add_child(row)
		row.add_child(_label(state.galaxy.get_planet(pid).display_name(state.galaxy), 200))
		row.add_child(_label("%d %%" % Ports.service_pct(state, c), 60))
		var sl := _label(Ports.state_label(cs), 90, STATE_COLORS[cs])
		row.add_child(sl)
		var parts := PackedStringArray()
		for p in Ports.service_parts(state, pid):
			if int(p[1]) < 0:
				parts.append("%s (%d %%)" % [String(p[0]), int(p[1])])
			elif int(p[1]) == 0:
				parts.append(String(p[0]))
		row.add_child(_label(", ".join(parts), 0, UiTheme.TEXT_DIM))
	if n == 0:
		b.body.add_child(UiTheme.dim("Toutes vos colonies sont desservies.", 13))
	return b
