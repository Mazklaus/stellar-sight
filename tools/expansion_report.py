"""Agrège la sortie de tools/expansion_bench.gd (lignes « EXP {json} ») par peuple et par année.

    python3 tools/expansion_report.py sortie1.txt [sortie2.txt ...]
"""
import json
import sys
from collections import defaultdict

data = defaultdict(lambda: defaultdict(list))  # faction -> année -> [mois]
for path in sys.argv[1:]:
    for line in open(path, encoding="utf-8"):
        if line.startswith("EXP "):
            g = json.loads(line[4:])
            for e in g["empires"]:
                for i, m in enumerate(e["months"]):
                    data[e["faction"]][i // 12 + 1].append(m)


def pct(ms, f):
    return 100 * sum(1 for m in ms if f(m)) / max(1, len(ms))


def avg(ms, k):
    return sum(m[k] for m in ms) / max(1, len(ms))


cols = ("an", "sys", "col", "out", "inf", "+inf", "mat", "+mat", "+nour", "inf<40", "mat<100", "chant.pleins",
        "colon", "constr", "attend", "guerre", "vaiss.", "cibles")
for f in sorted(data):
    print("\n== %s ==" % f)
    print(" ".join("%7s" % c for c in cols))
    for y in sorted(data[f]):
        ms = data[f][y]
        print(" ".join("%7s" % v for v in (
            y, "%.1f" % avg(ms, "sys"), "%.1f" % avg(ms, "col"), "%.1f" % avg(ms, "out"),
            "%.0f" % avg(ms, "inf"), "%.1f" % avg(ms, "ninf"), "%.0f" % avg(ms, "mat"), "%.1f" % avg(ms, "nmat"),
            "%.1f" % avg(ms, "nfood"),
            "%.0f%%" % pct(ms, lambda m: m["inf"] < 40), "%.0f%%" % pct(ms, lambda m: m["mat"] < 100),
            "%.0f%%" % pct(ms, lambda m: m["proj"] >= m["maxproj"]),
            "%.2f" % avg(ms, "colonizers"), "%.2f" % avg(ms, "building"), "%.0f%%" % pct(ms, lambda m: m["waiting"] > 0),
            "%.0f%%" % pct(ms, lambda m: m["war"]), "%.1f" % avg(ms, "warships"),
            "%.0f%%" % pct(ms, lambda m: m["targets"]))))
