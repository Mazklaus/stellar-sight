"""Agrège la sortie de tools/balance_bench.gd (lignes « BENCH {json} ») par peuple.

    python3 tools/balance_report.py sortie1.txt [sortie2.txt ...]
"""
import json
import sys
from collections import defaultdict

games = []
for path in sys.argv[1:]:
    for line in open(path, encoding="utf-8"):
        if line.startswith("BENCH "):
            games.append(json.loads(line[6:]))

stats = defaultdict(lambda: defaultdict(list))
wins = defaultdict(list)
for g in games:
    w = g.get("winner")
    if w:
        wins[w["faction"]].append((w["victory"], w["year"]))
    for e in g["empires"]:
        s = stats[e["faction"]]
        s["dead"].append(e["dead"])
        sysy = e["systems"]
        for yr in (5, 10, 15, 20, 25):
            if len(sysy) >= yr:
                s["sys%d" % yr].append(sysy[yr - 1])
        s["peak"].append(max(sysy) if sysy else 0)
        if e["dead"] > 0:
            s["killers"].append(e.get("killer") or "?")

print("%d parties, %d avec un vainqueur, durée moyenne %.0f s" % (
    len(games), sum(1 for g in games if g.get("winner")), sum(g["ms"] for g in games) / max(1, len(games)) / 1000))
print("%-9s %5s %6s %5s %6s %6s %6s %6s %5s  %s" % ("peuple", "parts", "morts", "<an10", "sys5", "sys10", "sys15", "sys20", "pic", "victoires (type an)"))
for f, s in sorted(stats.items()):
    n = len(s["dead"])
    dead = sum(1 for d in s["dead"] if d > 0)
    early = sum(1 for d in s["dead"] if 0 < d <= 10)

    def avg(k):
        v = s[k]
        return "%.1f" % (sum(v) / len(v)) if v else "-"

    wl = ", ".join("%s %d" % (v[:4], y) for v, y in sorted(wins[f], key=lambda t: t[1]))
    print("%-9s %5d %6d %5d %6s %6s %6s %6s %5s  %d : %s" % (f, n, dead, early, avg("sys5"), avg("sys10"), avg("sys15"), avg("sys20"), avg("peak"), len(wins[f]), wl))
    if s["killers"]:
        ks = defaultdict(int)
        for k in s["killers"]:
            ks[k] += 1
        print("          capitale prise par : " + ", ".join("%s %d" % kv for kv in sorted(ks.items())))

# Cibles de l'étude d'équilibrage (conclusion 1) : chaque peuple gagne 10 à 45 % des parties
# (victoires partagées comprises) et meurt avant l'an 10 dans moins de 25 % des parties.
print()
print("Cibles : victoires 10-45 %, morts avant l'an 10 < 25 %")
for f, s in sorted(stats.items()):
    n = len(s["dead"])
    if n == 0:
        continue
    won = len(wins[f])
    for g in games:
        w = g.get("winner")
        if w and w["faction"] != f:
            ally_factions = [e["faction"] for i, e in enumerate(g["empires"]) if i in w.get("allies", [])]
            won += ally_factions.count(f)
    early = sum(1 for d in s["dead"] if 0 < d <= 10)
    wp, ep = 100.0 * won / n, 100.0 * early / n
    ok = 10 <= wp <= 45 and ep < 25
    print("%-24s victoires %4.0f %%  morts <an10 %4.0f %%  %s" % (f, wp, ep, "dans la cible" if ok else "HORS CIBLE"))

# Sujets (option VASSALS=actifs) : qui devient sujet, quand, sous quel préréglage, et qui l'est encore.
subj = defaultdict(list)
for g in games:
    for e in g["empires"]:
        if e.get("subject_year", -1) >= 0:
            subj[e["faction"]].append((e["subject_year"], e.get("subject_preset", "?"), e.get("lord_end", ""), e.get("loyalty_end")))
if subj:
    print()
    print("Sujets : peuple, nombre de parties où il l'a été, (année, préréglage, suzerain à la fin, loyauté)")
    for f, v in sorted(subj.items()):
        print("%-24s %d : %s" % (f, len(v), ", ".join("an %d %s%s" % (y, p, (" sous " + l + " %+d" % lo) if l else " (libre à la fin)") for y, p, l, lo in sorted(v))))

# Koinon (option KOINON=actif) : qui entre dans une ligue, quand, et les ligues encore debout à la fin.
koi = defaultdict(list)
for g in games:
    for e in g["empires"]:
        if e.get("koinon_year", -1) >= 0:
            koi[e["faction"]].append((e["koinon_year"], e.get("koinon_form", "?")))
if koi:
    print()
    print("Koinon : peuple, nombre de parties où il en a été membre, (année d'entrée, forme)")
    for f, v in sorted(koi.items()):
        print("%-24s %d : %s" % (f, len(v), ", ".join("an %d %s" % (y, fo) for y, fo in sorted(v))))
    print("Ligues à la fin : " + "; ".join("%s rang %d coh %+d (%s, %d ans)" % (l["form"], l["rank"], l["coh"], "/".join(l["members"]), l["age"]) for g in games for l in g.get("leagues", [])))
