"""Lit la sortie de tools/fall_bench.gd (lignes « FALL {json} ») : géographie de départ par peuple,
comparaison morts / survivants, et récit court de chaque disparition.

    python3 tools/fall_report.py sortie1.txt [sortie2.txt ...] [--faction ossarane] [--before 120]
"""
import json
import sys
from collections import defaultdict

args = [a for a in sys.argv[1:]]
focus = None
before = 120  # « mort précoce » = avant ce mois
if "--faction" in args:
    i = args.index("--faction")
    focus = args[i + 1]
    del args[i:i + 2]
if "--before" in args:
    i = args.index("--before")
    before = int(args[i + 1])
    del args[i:i + 2]

games = []
for path in args:
    for line in open(path, encoding="utf-8"):
        if line.startswith("FALL "):
            games.append(json.loads(line[5:]))
games.sort(key=lambda g: g["seed"])


def avg(v):
    return sum(v) / len(v) if v else float("nan")


def early(e):
    return 0 < e["dead"] <= before


print("%d parties. Mort précoce = disparue avant le mois %d (an %d)." % (len(games), before, before // 12))
print()
print("Géographie de départ par peuple (moyennes) :")
print("%-9s %6s %6s %6s %8s %8s %9s %7s" % ("peuple", "morts", "centre", "routes", "territ.", "disputé", "saut min", "saut kh"))
by = defaultdict(list)
for g in games:
    for e in g["empires"]:
        by[e["faction"]].append(e)
for f, es in sorted(by.items()):
    geo = [e["geo"] for e in es]
    print("%-9s %6d %6.2f %6.1f %8.1f %8.1f %9.1f %7s" % (
        f, sum(1 for e in es if early(e)), avg([x["center"] for x in geo]), avg([x["lanes"] for x in geo]),
        avg([x["natural"] for x in geo]), avg([x["contested"] for x in geo]),
        avg([min(x["jumps"].values()) for x in geo]),
        "%.1f" % avg([x["jumps"]["khthari"] for x in geo if "khthari" in x["jumps"]]) if f != "khthari" else "-"))

print()
print("Morts précoces contre survivants (tous peuples sauf l'Essaim) :")
print("%-10s %6s %6s %8s %8s %9s %7s %6s %6s" % ("groupe", "n", "centre", "routes", "territ.", "saut min", "saut kh", "sys24", "pw24"))
for label, test in (("mortes", early), ("vivantes", lambda e: not early(e))):
    es = [e for f, l in by.items() if f != "khthari" for e in l if test(e)]
    geo = [e["geo"] for e in es]

    def at(e, k, mth=24):
        ms = e["months"]
        return ms[mth - 1][k] if len(ms) >= mth else 0

    print("%-10s %6d %6.2f %8.1f %8.1f %9.1f %7.1f %6.1f %6.0f" % (
        label, len(es), avg([x["center"] for x in geo]), avg([x["lanes"] for x in geo]),
        avg([x["natural"] for x in geo]), avg([min(x["jumps"].values()) for x in geo]),
        avg([x["jumps"].get("khthari", 0) for x in geo]),
        avg([at(e, "sys") for e in es]), avg([at(e, "pw") for e in es])))

print()
for g in games:
    for e in g["empires"]:
        if focus and e["faction"] != focus:
            continue
        if not early(e):
            continue
        geo = e["geo"]
        print("Graine %d : %s disparaît au mois %d (an %.1f), capitale prise par %s." % (
            g["seed"], e["faction"], e["dead"], e["dead"] / 12, e["killer"] or "?"))
        print("  départ : centre %.2f, %d routes, territoire %d (+%d disputé), sauts %s" % (
            geo["center"], geo["lanes"], geo["natural"], geo["contested"],
            ", ".join("%s %d" % kv for kv in sorted(geo["jumps"].items()))))
        ms = e["months"]
        pts = [m for m in (6, 12, 24, 36, 48, 60, 84, 108) if m <= len(ms)]
        print("  courbe : " + " | ".join("m%d sys %d pw %d mat %d cri %d%s" % (
            m, ms[m - 1]["sys"], ms[m - 1]["pw"], ms[m - 1]["mat"], ms[m - 1]["cry"],
            " DIS" if ms[m - 1]["dis"] else "") for m in pts))
        wins = sum(1 for ev in e["events"] if ev["k"] == "battle" and ev["res"] == "win")
        losses = sum(1 for ev in e["events"] if ev["k"] == "battle" and ev["res"] == "loss")
        print("  batailles : %d gagnées, %d perdues" % (wins, losses))
        for ev in e["events"]:
            if ev["k"] == "war":
                print("  m%d guerre avec %s (puissance %d contre %d, systèmes %d contre %d)" % (
                    ev["m"], ev["with"], ev["pw_me"], ev["pw_them"], ev["sys_me"], ev["sys_them"]))
            elif ev["k"] == "peace":
                print("  m%d paix avec %s" % (ev["m"], ev["with"]))
            elif ev["k"] == "cap_siege":
                print("  m%d siège de la capitale par %s" % (ev["m"], ev["by"]))
            elif ev["k"] == "home_lost":
                print("  m%d système d'origine perdu (%s)" % (ev["m"], ev["by"]))
        print()
