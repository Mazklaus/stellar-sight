# Cuisson d'un vaisseau pour Stellar Sight (scénario 2 de l'étude des vaisseaux 3D).
#
# Prend la version HD et la version basse d'un vaisseau (exports Tripo), refait les UV de la
# version basse, y cuit les cartes de la HD (couleur, normale OpenGL, ORM), pose les points
# d'attache, puis exporte un .glb prêt pour Godot, son masque de couleur d'empire et un rapport.
# Les règles (nommage, tailles, budgets, axes) sont dans docs/vaisseaux-3d.md.
#
# Lancement (Blender 4.2 ou plus, sans interface) :
#   blender -b --python tools/vaisseaux/cuire_vaisseau.py -- \
#       --hd sources/ossarane_fregate_hd.glb --basse sources/ossarane_fregate_basse.fbx \
#       --nom ossarane_fregate --taille medium
# Options : --sortie DIR (défaut sources, ignoré par git et par Godot), --points FICHIER.json, --tourner DEGRES,
#           --resolution N, --masque-tolerance T (0 à 1), --sans-masque.

import argparse
import json
import math
import os
import sys

import bpy
import mathutils
import numpy as np

# Longueur en unités Godot, résolution des cartes et budget de triangles par taille de coque
# (tailles de data/designs.json). Budgets : estimation de l'étude, à ajuster en jeu.
TAILLES = {
	"small": {"longueur": 1.0, "resolution": 1024, "budget": (1500, 5000)},
	"medium": {"longueur": 1.6, "resolution": 2048, "budget": (5000, 15000)},
	"large": {"longueur": 2.5, "resolution": 2048, "budget": (15000, 40000)},
	"titan": {"longueur": 5.0, "resolution": 4096, "budget": (40000, 100000)},
}
PREFIXES_POINTS = ("slot_", "fx_", "centre")


def lire_arguments():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	p = argparse.ArgumentParser(prog="cuire_vaisseau.py")
	p.add_argument("--hd", required=True, help="version HD (.glb), source des cartes")
	p.add_argument("--basse", required=True, help="version basse (.fbx ou .glb), géométrie finale")
	p.add_argument("--nom", required=True, help="<peuple>_<coque>[_<variante>], ex. ossarane_fregate")
	p.add_argument("--taille", required=True, choices=sorted(TAILLES))
	p.add_argument("--sortie", default="sources")
	p.add_argument("--points", help="points d'attache (.json), voir docs/vaisseaux-3d.md")
	p.add_argument("--tourner", type=float, default=0.0,
		help="rotation autour de la verticale (degrés) si le nez ne pointe pas vers l'avant")
	p.add_argument("--resolution", type=int, default=0)
	p.add_argument("--masque-tolerance", type=float, default=0.18)
	p.add_argument("--sans-masque", action="store_true")
	return p.parse_args(argv)


def importer(chemin):
	avant = set(bpy.data.objects)
	if chemin.lower().endswith(".fbx"):
		bpy.ops.import_scene.fbx(filepath=chemin)
	else:
		bpy.ops.import_scene.gltf(filepath=chemin)
	maillages = [o for o in bpy.data.objects if o not in avant and o.type == "MESH"]
	if not maillages:
		raise SystemExit("aucun maillage dans " + chemin)
	bpy.ops.object.select_all(action="DESELECT")
	for o in maillages:
		o.select_set(True)
	bpy.context.view_layer.objects.active = maillages[0]
	if len(maillages) > 1:
		bpy.ops.object.join()
	obj = bpy.context.view_layer.objects.active
	# Détache des parents éventuels et applique les transformations.
	bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	for o in [o for o in bpy.data.objects if o not in avant and o.type != "MESH"]:
		bpy.data.objects.remove(o)
	return obj


def boite(obj):
	pts = [obj.matrix_world @ mathutils.Vector(c) for c in obj.bound_box]
	mn = mathutils.Vector([min(p[i] for p in pts) for i in range(3)])
	mx = mathutils.Vector([max(p[i] for p in pts) for i in range(3)])
	return mn, mx


def transformer(objs, matrice):
	for o in objs:
		o.matrix_world = matrice @ o.matrix_world
	bpy.ops.object.select_all(action="DESELECT")
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = objs[0]
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def aligner(basse, hd, avertissements):
	# Les exports Tripo d'une même tâche sont déjà alignés ; sinon, on cale la basse sur la HD.
	mn_b, mx_b = boite(basse)
	mn_h, mx_h = boite(hd)
	taille_h = mx_h - mn_h
	ecart = max(abs((mx_b - mn_b)[i] - taille_h[i]) / max(taille_h[i], 1e-6) for i in range(3))
	decalage = ((mn_b + mx_b) - (mn_h + mx_h)).length / 2 / max(taille_h)
	if ecart > 0.05 or decalage > 0.05:
		echelle = max(taille_h) / max(mx_b - mn_b)
		centre_b = (mn_b + mx_b) / 2
		centre_h = (mn_h + mx_h) / 2
		m = mathutils.Matrix.Translation(centre_h) @ mathutils.Matrix.Scale(echelle, 4) \
			@ mathutils.Matrix.Translation(-centre_b)
		transformer([basse], m)
		avertissements.append("version basse recalée sur la HD (écart %.0f %%) : vérifier qu'elles viennent de la même génération" % (100 * max(ecart, decalage)))


def normaliser(objs, longueur, tourner):
	# Nez vers +Y de Blender (= -Z de Godot, l'avant), dessus vers +Z, centre de la boîte à l'origine,
	# plus grande dimension horizontale = longueur demandée.
	if tourner:
		transformer(objs, mathutils.Matrix.Rotation(math.radians(tourner), 4, "Z"))
	mn, mx = boite(objs[0])
	taille = mx - mn
	if taille.x > taille.y:
		transformer(objs, mathutils.Matrix.Rotation(math.radians(90), 4, "Z"))
		mn, mx = boite(objs[0])
		taille = mx - mn
	echelle = longueur / max(taille.x, taille.y)
	m = mathutils.Matrix.Scale(echelle, 4) @ mathutils.Matrix.Translation(-(mn + mx) / 2)
	transformer(objs, m)


def refaire_uv(obj):
	me = obj.data
	while me.uv_layers:
		me.uv_layers.remove(me.uv_layers[0])
	me.uv_layers.new(name="UVMap")
	bpy.ops.object.select_all(action="DESELECT")
	obj.select_set(True)
	bpy.context.view_layer.objects.active = obj
	bpy.ops.object.mode_set(mode="EDIT")
	bpy.ops.mesh.select_all(action="SELECT")
	bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.003)
	bpy.ops.uv.pack_islands(margin=0.003)
	bpy.ops.object.mode_set(mode="OBJECT")


def image(nom, res, couleur):
	im = bpy.data.images.new(nom, res, res, alpha=False)
	im.colorspace_settings.name = "sRGB" if couleur else "Non-Color"
	return im


def source(socket):
	return socket.links[0].from_socket if socket.links else None


def cuire(basse, hd, res, longueur):
	me = basse.data
	me.materials.clear()
	mat = bpy.data.materials.new("vaisseau")
	mat.use_nodes = True
	me.materials.append(mat)
	nt = mat.node_tree
	cible = nt.nodes.new("ShaderNodeTexImage")

	hm = hd.data.materials[0]
	hn = hm.node_tree
	hb = next(n for n in hn.nodes if n.type == "BSDF_PRINCIPLED")
	hout = next(n for n in hn.nodes if n.type == "OUTPUT_MATERIAL" and n.is_active_output)
	surface = source(hout.inputs["Surface"])
	emis = hn.nodes.new("ShaderNodeEmission")
	canaux = {
		"couleur": source(hb.inputs["Base Color"]) or tuple(hb.inputs["Base Color"].default_value)[:3],
		"rugosite": source(hb.inputs["Roughness"]) or (hb.inputs["Roughness"].default_value,) * 3,
		"metal": source(hb.inputs["Metallic"]) or (hb.inputs["Metallic"].default_value,) * 3,
	}

	sc = bpy.context.scene
	sc.render.engine = "CYCLES"
	sc.cycles.device = "CPU"
	sc.cycles.samples = 1
	bk = sc.render.bake
	bk.use_selected_to_active = True
	# Distances proportionnelles à la taille : 1 % et 2 % de la longueur.
	bk.cage_extrusion = 0.01 * longueur
	bk.max_ray_distance = 0.02 * longueur
	bk.margin = max(4, res // 256)

	def lancer(type_cuisson, im):
		cible.image = im
		nt.nodes.active = cible
		bpy.ops.object.select_all(action="DESELECT")
		hd.select_set(True)
		basse.select_set(True)
		bpy.context.view_layer.objects.active = basse
		bpy.ops.object.bake(type=type_cuisson)

	def brancher(socket):
		for lien in list(hout.inputs["Surface"].links):
			hn.links.remove(lien)
		hn.links.new(socket, hout.inputs["Surface"])

	cartes = {}
	bk.normal_space = "TANGENT"
	bk.normal_g = "POS_Y"  # convention OpenGL, celle de Godot
	cartes["normale"] = image("normale", res, False)
	lancer("NORMAL", cartes["normale"])

	brancher(emis.outputs[0])
	for nom, src in canaux.items():
		for lien in list(emis.inputs["Color"].links):
			hn.links.remove(lien)
		if hasattr(src, "node"):
			hn.links.new(src, emis.inputs["Color"])
		else:
			emis.inputs["Color"].default_value = (*src, 1.0)
		cartes[nom] = image(nom, res, nom == "couleur")
		lancer("EMIT", cartes[nom])

	# Occlusion ambiante calculée sur la HD, avec son matériau d'origine.
	if surface:
		brancher(surface)
	sc.cycles.samples = 32
	cartes["ao"] = image("ao", res, False)
	lancer("AO", cartes["ao"])
	sc.cycles.samples = 1
	nt.nodes.remove(cible)
	return mat, cartes


def pixels(im):
	return np.array(im.pixels[:], dtype=np.float32).reshape(-1, 4)


def assembler_orm(cartes, res):
	orm = image("orm", res, False)
	o = np.ones((res * res, 4), dtype=np.float32)
	o[:, 0] = pixels(cartes["ao"])[:, 0]
	o[:, 1] = pixels(cartes["rugosite"])[:, 0]
	o[:, 2] = pixels(cartes["metal"])[:, 0]
	orm.pixels[:] = o.ravel()
	return orm


def masque_empire(couleur, res, tolerance):
	# Premier jet automatique : la teinte de coque dominante devient la zone peinte aux couleurs
	# de l'empire (blanc = peint). À retoucher à la main si besoin, voir docs/vaisseaux-3d.md.
	px = pixels(couleur)[:, :3]
	utiles = px[px.sum(1) > 0.03]  # écarte le fond hors des îlots UV
	if len(utiles) == 0:
		return None, 0.0
	q = np.floor(np.clip(utiles, 0, 0.999) * 8).astype(int)
	codes = q[:, 0] * 64 + q[:, 1] * 8 + q[:, 2]
	dominante = np.bincount(codes).argmax()
	ref = utiles[codes == dominante].mean(0)
	dist = np.linalg.norm(px - ref, axis=1) / math.sqrt(3)
	m = np.clip(1.0 - (dist - tolerance) / max(tolerance, 1e-3), 0, 1)
	m[px.sum(1) <= 0.03] = 0
	im = image("masque", res, False)
	o = np.ones((res * res, 4), dtype=np.float32)
	o[:, 0] = o[:, 1] = o[:, 2] = m
	im.pixels[:] = o.ravel()
	part = float((m[px.sum(1) > 0.03] > 0.5).mean())
	return im, part


def materiau_final(mat, couleur, orm, normale):
	nt = mat.node_tree
	bsdf = nt.nodes["Principled BSDF"]

	def noeud(im):
		n = nt.nodes.new("ShaderNodeTexImage")
		n.image = im
		return n

	nt.links.new(noeud(couleur).outputs[0], bsdf.inputs["Base Color"])
	sep = nt.nodes.new("ShaderNodeSeparateColor")
	nt.links.new(noeud(orm).outputs[0], sep.inputs[0])
	nt.links.new(sep.outputs[1], bsdf.inputs["Roughness"])
	nt.links.new(sep.outputs[2], bsdf.inputs["Metallic"])
	# L'exporteur glTF range le canal R (occlusion) de la même image comme occlusion.
	gltf = bpy.data.node_groups.get("glTF Material Output") or bpy.data.node_groups.get("glTF Settings")
	if gltf is None:
		gltf = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
		gltf.interface.new_socket("Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
	grp = nt.nodes.new("ShaderNodeGroup")
	grp.node_tree = gltf
	nt.links.new(sep.outputs[0], grp.inputs[0])
	nn = noeud(normale)
	nm = nt.nodes.new("ShaderNodeNormalMap")
	nt.links.new(nn.outputs[0], nm.inputs["Color"])
	nt.links.new(nm.outputs[0], bsdf.inputs["Normal"])


def poser_points(obj, fichier, avertissements):
	# Points en fractions de la boîte du vaisseau : x de -1 (gauche) à 1 (droite), y de -1 (arrière)
	# à 1 (nez), z de -1 (dessous) à 1 (dessus). Sans fichier : centre et un réacteur à l'arrière.
	mn, mx = boite(obj)
	points = {"centre": [0, 0, 0], "fx_reacteur_1": [0, -1, 0]}
	if fichier:
		with open(fichier, encoding="utf-8") as f:
			points = json.load(f)
	poses = []
	for nom, (x, y, z) in points.items():
		if not nom.startswith(PREFIXES_POINTS):
			avertissements.append("point « %s » ignoré : il doit commencer par slot_, fx_ ou centre" % nom)
			continue
		pos = mathutils.Vector([(mn[i] + mx[i]) / 2 + v * (mx[i] - mn[i]) / 2 for i, v in enumerate((x, y, z))])
		e = bpy.data.objects.new(nom, None)
		e.empty_display_type = "PLAIN_AXES"
		e.empty_display_size = 0.05 * (mx - mn).length
		e.location = pos
		bpy.context.scene.collection.objects.link(e)
		e.parent = obj
		poses.append(nom)
	return poses


def principal():
	a = lire_arguments()
	reglage = TAILLES[a.taille]
	res = a.resolution or reglage["resolution"]
	avertissements = []
	os.makedirs(a.sortie, exist_ok=True)
	if os.path.basename(os.path.normpath(a.sortie)) == "sources":
		# Godot n'importe pas ce dossier (fichiers de 10 à 70 Mo, inutiles au jeu).
		open(os.path.join(a.sortie, ".gdignore"), "a").close()

	bpy.ops.wm.read_factory_settings(use_empty=True)
	basse = importer(a.basse)
	hd = importer(a.hd)
	if not hd.data.materials or not hd.data.materials[0].use_nodes:
		raise SystemExit("la version HD n'a pas de matériau à cuire")
	aligner(basse, hd, avertissements)
	normaliser([basse, hd], reglage["longueur"], a.tourner)
	basse.name = basse.data.name = a.nom

	refaire_uv(basse)
	mat, cartes = cuire(basse, hd, res, reglage["longueur"])
	orm = assembler_orm(cartes, res)
	bpy.data.objects.remove(hd)

	masque, part_masque = (None, 0.0) if a.sans_masque else masque_empire(cartes["couleur"], res, a.masque_tolerance)
	materiau_final(mat, cartes["couleur"], orm, cartes["normale"])
	points = poser_points(basse, a.points, avertissements)

	tris = sum(len(p.vertices) - 2 for p in basse.data.polygons)
	bas, haut = reglage["budget"]
	if not bas <= tris <= haut:
		avertissements.append("%d triangles, hors du budget %d-%d de la taille %s" % (tris, bas, haut, a.taille))

	base = os.path.join(a.sortie, a.nom)
	for nom, im in (("couleur", cartes["couleur"]), ("orm", orm), ("normale", cartes["normale"])):
		im.name = "%s_%s" % (a.nom, nom)
	bpy.ops.object.select_all(action="DESELECT")
	bpy.ops.export_scene.gltf(filepath=base + ".glb", export_format="GLB", export_image_format="AUTO",
		export_extras=False, export_yup=True)
	if masque:
		masque.filepath_raw = base + "_masque.png"
		masque.file_format = "PNG"
		masque.save()

	mn, mx = boite(basse)
	rapport = {
		"nom": a.nom,
		"taille": a.taille,
		"triangles": tris,
		"budget": [bas, haut],
		"resolution": res,
		"dimensions_godot": {"largeur": round(mx.x - mn.x, 3), "hauteur": round(mx.z - mn.z, 3), "longueur": round(mx.y - mn.y, 3)},
		"points": points,
		"masque_part_peinte": round(part_masque, 2) if masque else None,
		"avertissements": avertissements,
	}
	with open(base + ".rapport.json", "w", encoding="utf-8") as f:
		json.dump(rapport, f, ensure_ascii=False, indent="\t")
	print("VAISSEAU " + json.dumps(rapport, ensure_ascii=False))


principal()
