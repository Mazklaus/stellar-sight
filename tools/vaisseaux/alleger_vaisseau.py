# Version « jeu » d'un vaisseau cuit (docs/vaisseaux-3d.md) : mêmes maillage et points d'attache,
# textures réduites et compressées en JPEG, pour que le jeu charge le modèle 3D (cinématique de
# bataille) sans alourdir le dépôt. Le masque d'empire est réduit à la même taille.
#
# Lancement (Blender 4.2 ou plus, sans interface) :
#   blender -b --python tools/vaisseaux/alleger_vaisseau.py -- sources/ossarane_fregate.glb
# Options : --sortie DIR (défaut assets/ships), --resolution N (défaut 1024).

import argparse
import os
import sys

import bpy


def lire_arguments():
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	p = argparse.ArgumentParser(prog="alleger_vaisseau.py")
	p.add_argument("glb", help="vaisseau cuit par cuire_vaisseau.py")
	p.add_argument("--sortie", default="assets/ships")
	p.add_argument("--resolution", type=int, default=1024)
	return p.parse_args(argv)


def principal():
	a = lire_arguments()
	nom = os.path.splitext(os.path.basename(a.glb))[0]
	os.makedirs(a.sortie, exist_ok=True)
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.gltf(filepath=a.glb)
	for im in list(bpy.data.images):
		if im.size[0] > a.resolution:
			im.scale(a.resolution, a.resolution)
	sortie = os.path.join(a.sortie, nom + ".glb")
	bpy.ops.export_scene.gltf(filepath=sortie, export_format="GLB", export_image_format="JPEG",
		export_jpeg_quality=88, export_extras=False, export_yup=True)

	masque = os.path.splitext(a.glb)[0] + "_masque.png"
	if os.path.exists(masque):
		im = bpy.data.images.load(masque)
		if im.size[0] > a.resolution:
			im.scale(a.resolution, a.resolution)
		im.filepath_raw = os.path.join(a.sortie, nom + "_masque.png")
		im.file_format = "PNG"
		im.save()
	print("VAISSEAU_JEU %s (%d Ko)" % (sortie, os.path.getsize(sortie) // 1024))


principal()
