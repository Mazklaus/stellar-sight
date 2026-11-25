#!/usr/bin/env python3
"""Atelier des fichiers son du jeu (étude des outils du son, P4 à P6).

  python3 tools/audio/son.py mesurer fichier.wav [...]        durée, niveau (LUFS), crête
  python3 tools/audio/son.py tempo morceau.wav                tempo estimé
  python3 tools/audio/son.py boucler source.wav carte/etoile_jaune --debut 12.5 --duree 16
  python3 tools/audio/son.py boucler morceau.wav musique/paix_1 --debut 8 --mesures 8 [--bpm 76]
  python3 tools/audio/son.py poser source.wav ui/ui_valider   son court, sans bouclage
  python3 tools/audio/son.py verifier                         tout assets/sounds

« boucler » et « poser » écrivent assets/sounds/<dossier>/<id>.ogg au niveau de référence du dossier
(bloc "levels" de data/audio.json) et inscrivent le son dans assets/sounds/origines.json : outil,
consigne, licence, date, niveau mesuré. Options d'origine : --outil, --consigne, --licence.
Une boucle se raccorde par un fondu : la fin du passage se prolonge dans son début, donc la reprise
ne claque pas. Dépendances : Python 3, numpy, ffmpeg.
"""
import argparse, datetime, json, pathlib, re, subprocess, sys
import numpy as np

RACINE = pathlib.Path(__file__).resolve().parents[2]
SONS = RACINE / "assets" / "sounds"
ORIGINES = SONS / "origines.json"
TAUX = 44100


def config():
    return json.loads((RACINE / "data" / "audio.json").read_text(encoding="utf-8"))


def niveau_cible(dossier):
    niveaux = config().get("levels", {})
    return float(niveaux.get(dossier, niveaux.get("default", -20.0)))


def lire(chemin):
    """Échantillons stéréo en flottants, forme (n, 2)."""
    brut = subprocess.run(["ffmpeg", "-v", "error", "-i", str(chemin), "-f", "f32le", "-ac", "2", "-ar", str(TAUX), "-"],
                          capture_output=True, check=True).stdout
    return np.frombuffer(brut, dtype=np.float32).reshape(-1, 2).astype(np.float64)


def ecrire_ogg(x, chemin):
    chemin.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ac", "2", "-ar", str(TAUX), "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "5", str(chemin)],
                   input=x.astype(np.float32).tobytes(), check=True)


def lufs(x):
    """Niveau perçu (EBU R128, via ffmpeg). Pour un son trop court pour la norme, niveau efficace."""
    if len(x) >= TAUX * 0.5:
        err = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-f", "f32le", "-ac", "2", "-ar", str(TAUX), "-i", "-",
                              "-af", "ebur128", "-f", "null", "-"],
                             input=x.astype(np.float32).tobytes(), capture_output=True).stderr.decode(errors="replace")
        trouve = re.findall(r"I:\s+(-?[\d.]+) LUFS", err)
        if trouve and float(trouve[-1]) > -69.0:
            return float(trouve[-1])
    eff = float(np.sqrt(np.mean(x ** 2))) if len(x) else 0.0
    return 20.0 * np.log10(max(eff, 1e-9))


def crete(x):
    return 20.0 * np.log10(max(float(np.max(np.abs(x))) if len(x) else 0.0, 1e-9))


def plafond_crete(dossier):
    """Crête la plus haute admise pour un fichier de ce dossier (bloc ceiling de data/audio.json)."""
    garde = config().get("ceiling", {})
    haut = float(garde.get("peak_db", -3.0))
    ecart = garde.get("crest_db", {}).get(dossier)
    return haut if ecart is None else min(haut, niveau_cible(dossier) + float(ecart))


def arrondir(x, plafond_db):
    """Arrondit en douceur ce qui dépasse le plafond (genou en tangente hyperbolique à 6 dB dessous)."""
    haut = 10 ** (plafond_db / 20.0)
    genou = haut * 0.5
    a = np.abs(x)
    y = np.where(a > genou, np.sign(x) * (genou + (haut - genou) * np.tanh((a - genou) / (haut - genou))), x)
    return y


def part_grave_max(dossier):
    garde = config().get("ceiling", {})
    return float(garde.get("sub_share_by_dir", {}).get(dossier, garde.get("sub_share", 0.5)))


def coupe_bas(x, dossier=""):
    """Retire les grondements sous lowcut_hz (pente douce d'une demi-octave). Passe par le spectre
    entier : une boucle reste une boucle."""
    garde = config().get("ceiling", {})
    f0 = float(garde.get("lowcut_by_dir", {}).get(dossier, garde.get("lowcut_hz", 45.0)))
    if f0 <= 0 or len(x) < 2048:
        return x
    spectre = np.fft.rfft(x, axis=0)
    freqs = np.fft.rfftfreq(len(x), 1.0 / TAUX)
    gain = np.clip((freqs - f0 * 0.7) / (f0 * 0.3), 0.0, 1.0)
    return np.fft.irfft(spectre * (0.5 - 0.5 * np.cos(np.pi * gain))[:, None], n=len(x), axis=0)


def part_grave(x):
    """Part de l'énergie sous 60 Hz."""
    if len(x) < 2048:
        return 0.0
    e = np.abs(np.fft.rfft(x.mean(axis=1))) ** 2
    freqs = np.fft.rfftfreq(len(x), 1.0 / TAUX)
    return float(e[freqs < 60.0].sum() / (e.sum() + 1e-18))


def recoudre(x):
    """Si la reprise d'une boucle claque, une rampe sur les derniers millièmes de seconde la referme."""
    if raccord(x) <= 1.2:
        return x
    n = min(2048, len(x) // 4)
    y = x.copy()
    y[-n:] += (x[0] - x[-1]) * np.linspace(0.0, 1.0, n)[:, None]
    return y


def niveler(x, cible, plafond_db=-3.0):
    """Ramène au niveau cible ; les crêtes au-delà du plafond sont arrondies, puis le niveau repris.
    Un décibel de marge sous le plafond : l'encodage en OGG remonte un peu les crêtes."""
    plafond_db -= 1.5
    y = x * 10 ** ((cible - lufs(x)) / 20.0)
    for _ in range(3):
        if crete(y) <= plafond_db:
            break
        y = arrondir(y, plafond_db)
        y = y * 10 ** (min(0.0, cible - lufs(y)) / 20.0)
    return y


def tempo(x):
    """Tempo estimé : autocorrélation de l'enveloppe des attaques, entre 50 et 190 à la minute."""
    mono = x.mean(axis=1)
    pas, fen = 512, 1024
    n = (len(mono) - fen) // pas
    if n < 200:
        return 0.0
    fenetre = np.hanning(fen)
    spectres = np.abs(np.fft.rfft(np.stack([mono[i * pas:i * pas + fen] * fenetre for i in range(n)]), axis=1))
    flux = np.maximum(np.diff(spectres, axis=0), 0).sum(axis=1)
    flux -= flux.mean()
    auto = np.correlate(flux, flux, mode="full")[len(flux) - 1:]
    par_seconde = TAUX / pas
    lo, hi = int(par_seconde * 60 / 190), int(par_seconde * 60 / 50)
    k = lo + int(np.argmax(auto[lo:hi]))
    return 60.0 * par_seconde / k


def boucle(x, debut, duree, fondu):
    """Passage [debut, debut+duree) dont le début reçoit, en fondu, la suite de la fin."""
    a, n, f = int(debut * TAUX), int(duree * TAUX), int(fondu * TAUX)
    if a + n + f > len(x):
        sys.exit("Passage trop long : il faut %.2f s de source après le début, il y en a %.2f." % (duree + fondu, len(x) / TAUX - debut))
    f = min(f, n // 2)
    out = x[a:a + n].copy()
    t = np.linspace(0.0, np.pi / 2, f)[:, None]
    out[:f] = x[a + n:a + n + f] * np.cos(t) + x[a:a + f] * np.sin(t)
    return out


def raccord(x):
    """Saut entre le dernier et le premier échantillon, rapporté aux plus grands sauts que le son fait
    de lui-même juste avant et juste après (au-dessus de 1,5, la reprise claque)."""
    if len(x) < 4096:
        return 0.0
    autour = np.concatenate([np.abs(np.diff(x[-1024:], axis=0)), np.abs(np.diff(x[:1024], axis=0))])
    return float(np.abs(x[0] - x[-1]).max() / (autour.max() + 1e-9))


def inscrire(ident, fiche):
    tout = json.loads(ORIGINES.read_text(encoding="utf-8")) if ORIGINES.exists() else {}
    tout[ident] = fiche
    ORIGINES.write_text(json.dumps(dict(sorted(tout.items())), ensure_ascii=False, indent="\t") + "\n", encoding="utf-8")


def poser(x, ident, args, en_boucle):
    dossier = ident.split("/")[0]
    y = niveler(coupe_bas(x, dossier), niveau_cible(dossier), plafond_crete(dossier))
    ecrire_ogg(y, SONS / (ident + ".ogg"))
    fiche = {"outil": args.outil, "consigne": args.consigne, "licence": args.licence, "date": datetime.date.today().isoformat(),
             "source": pathlib.Path(args.source).name, "duree": round(len(y) / TAUX, 3), "lufs": round(lufs(y), 1),
             "crete": round(crete(y), 1), "grave": round(part_grave(y), 2), "boucle": en_boucle}
    inscrire(ident, fiche)
    print("%s.ogg : %.2f s, %.1f LUFS (cible %.1f), crête %.1f dB%s" % (ident, fiche["duree"], fiche["lufs"], niveau_cible(dossier), fiche["crete"],
                                                                      ", raccord %.2f" % raccord(y) if en_boucle else ""))


def verifier():
    """Chaque fichier son a sa fiche, sa licence, et ne dépasse pas le niveau de son dossier."""
    tout = json.loads(ORIGINES.read_text(encoding="utf-8")) if ORIGINES.exists() else {}
    fautes = 0
    fichiers = sorted(p for p in SONS.rglob("*") if p.suffix in (".ogg", ".wav"))
    for p in fichiers:
        ident = str(p.relative_to(SONS).with_suffix("")).replace("\\", "/")
        fiche, x = tout.get(ident), lire(p)
        mesure, cible = lufs(x), niveau_cible(ident.split("/")[0])
        notes = []
        if fiche is None:
            notes.append("pas de fiche d'origine")
        elif not fiche.get("licence") or not fiche.get("outil"):
            notes.append("fiche sans outil ou sans licence")
        if mesure > cible + 1.5:
            notes.append("trop fort de %.1f dB" % (mesure - cible))
        if crete(x) > plafond_crete(ident.split("/")[0]) + 0.5:
            notes.append("crête trop haute (%.1f dB pour %.1f)" % (crete(x), plafond_crete(ident.split("/")[0])))
        if part_grave(x) > part_grave_max(ident.split("/")[0]):
            notes.append("trop de grondement sous 60 Hz (%d %%)" % round(part_grave(x) * 100))
        if fiche and fiche.get("boucle") and raccord(x) > 1.5:
            notes.append("la boucle claque au raccord")
        fautes += bool(notes)
        print("%-36s %6.1f LUFS (cible %5.1f)  %s" % (ident, mesure, cible, " ; ".join(notes) or "bon"))
    for ident in tout:
        if not any((SONS / (ident + ext)).exists() for ext in (".ogg", ".wav")):
            print("%-36s fiche sans fichier" % ident)
            fautes += 1
    print("%d fichier(s), %d à reprendre." % (len(fichiers), fautes))
    return 1 if fautes else 0


def renormer():
    """Reprend chaque fichier trop fort ou à la crête trop haute : même son, niveau et crêtes ramenés."""
    tout = json.loads(ORIGINES.read_text(encoding="utf-8")) if ORIGINES.exists() else {}
    repris = 0
    for p in sorted(SONS.rglob("*.ogg")):
        ident = str(p.relative_to(SONS).with_suffix("")).replace("\\", "/")
        dossier = ident.split("/")[0]
        x = lire(p)
        cible, haut = niveau_cible(dossier), plafond_crete(dossier)
        trop_grave = part_grave(x) > part_grave_max(dossier)
        fiche = tout.get(ident, {})
        claque = bool(fiche.get("boucle")) and raccord(x) > 1.5
        if lufs(x) <= cible + 1.5 and crete(x) <= haut + 0.5 and not trop_grave and "grave" in fiche and not claque:
            continue
        y = niveler(coupe_bas(x, dossier) if trop_grave or "grave" not in fiche else x, cible, haut)
        if fiche.get("boucle"):
            y = recoudre(y)
        ecrire_ogg(y, p)
        y = lire(p)
        fiche.update({"lufs": round(lufs(y), 1), "crete": round(crete(y), 1), "grave": round(part_grave(y), 2)})
        inscrire(ident, fiche)
        tout[ident] = fiche
        repris += 1
        print("%-36s repris : %.1f LUFS, crête %.1f dB" % (ident, fiche["lufs"], fiche["crete"]))
    print("%d fichier(s) repris." % repris)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = ap.add_subparsers(dest="cmd", required=True)
    sp.add_parser("mesurer").add_argument("fichiers", nargs="+")
    sp.add_parser("tempo").add_argument("source")
    sp.add_parser("verifier")
    sp.add_parser("renormer")
    for nom in ("boucler", "poser"):
        p = sp.add_parser(nom)
        p.add_argument("source")
        p.add_argument("ident", help="dossier/identifiant, sans extension (carte/etoile_jaune)")
        p.add_argument("--outil", default="inconnu")
        p.add_argument("--consigne", default="")
        p.add_argument("--licence", default="")
        if nom == "boucler":
            p.add_argument("--debut", type=float, default=0.0)
            p.add_argument("--duree", type=float, default=0.0)
            p.add_argument("--mesures", type=int, default=0)
            p.add_argument("--bpm", type=float, default=0.0)
            p.add_argument("--temps", type=int, default=4, help="temps par mesure")
            p.add_argument("--fondu", type=float, default=0.0, help="secondes (défaut : 0,05 pour une boucle mesurée, 1 pour une ambiance)")
    args = ap.parse_args()
    if args.cmd == "mesurer":
        for f in args.fichiers:
            x = lire(f)
            print("%-40s %7.2f s  %6.1f LUFS  crête %5.1f dB" % (pathlib.Path(f).name, len(x) / TAUX, lufs(x), crete(x)))
    elif args.cmd == "tempo":
        print("%.1f à la minute" % tempo(lire(args.source)))
    elif args.cmd == "verifier":
        sys.exit(verifier())
    elif args.cmd == "renormer":
        renormer()
    elif args.cmd == "poser":
        poser(lire(args.source), args.ident, args, False)
    elif args.cmd == "boucler":
        x = lire(args.source)
        duree, fondu = args.duree, args.fondu or 1.0
        if args.mesures:
            bpm = args.bpm or tempo(x)
            if bpm <= 0:
                sys.exit("Tempo introuvable : donnez --bpm.")
            duree, fondu = args.mesures * args.temps * 60.0 / bpm, args.fondu or 0.05
            print("Tempo %.1f, %d mesures : %.3f s." % (bpm, args.mesures, duree))
        if duree <= 0:
            sys.exit("Donnez --duree ou --mesures.")
        poser(boucle(x, args.debut, duree, fondu), args.ident, args, True)


if __name__ == "__main__":
    main()
