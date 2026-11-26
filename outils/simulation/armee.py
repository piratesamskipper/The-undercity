"""Batailles armée contre armée sur une grille 8x10 (règles du GDD).

Usage : python3 armee.py [nb_batailles] [multiplicateur_degats]

Hypothèses du modèle (non tranchées dans le GDD) :
- déplacement en 8 directions, une diagonale coûte 1,5 ; on ne traverse pas les piles ;
- portée de tir : diagonale = 1,5 ; contact = case voisine, diagonale comprise ;
- initiative = stat + 1d12, tirée une fois par bataille ;
- pas d'obstacles ni de chef ; pas de Défendre / Attendre ;
- IA simple : les tireurs tirent sur la pile ennemie la plus dangereuse à portée
  (sinon la plus dangereuse tout court, à x0,5) ; les unités de mêlée attaquent
  la cible atteignable la plus dangereuse (tireurs en priorité), sinon avancent.
"""

import json
import random
import sys
from collections import deque
from pathlib import Path

from simulation import (Pile, degats, PENALITE_CAC_TIREUR, PENALITE_HORS_PORTEE,
                        SEUIL_PERTES_MORAL, DUREE_MALUS_MORAL)

LIGNES, COLONNES = 10, 14
ROUNDS_MAX = 30

COMPO_HR = [("Esclave du père des rats", 2), ("Frondeur des égouts", 2),
            ("Surineurs", 3), ("Rats mutés", 1)]
COMPO_G = [("Bleusaille", 2), ("Arbalétriers", 2), ("Soldats du cru", 3), ("Vétérans", 1)]
COUT_DIAGONALE = 1.5


class PileG(Pile):
    def __init__(self, u, camp, pos, mult):
        super().__init__(u)
        self.camp, self.pos, self.mult = camp, pos, mult


def dist(a, b):
    return max(abs(a[0] - b[0]), abs(a[1] - b[1]))


def dist_tir(a, b):
    """Distance de tir : diagonale = COUT_DIAGONALE."""
    dl, dc = abs(a[0] - b[0]), abs(a[1] - b[1])
    return max(dl, dc) + (COUT_DIAGONALE - 1) * min(dl, dc)


def voisins(c):
    for dl in (-1, 0, 1):
        for dc in (-1, 0, 1):
            if dl or dc:
                l, k = c[0] + dl, c[1] + dc
                if 0 <= l < LIGNES and 0 <= k < COLONNES:
                    yield (l, k)


def accessibles(p, occupees):
    """Cases atteignables : coût 1 en ligne droite, COUT_DIAGONALE en diagonale."""
    import heapq
    vu = {p.pos: 0.0}
    tas = [(0.0, p.pos)]
    while tas:
        d, c = heapq.heappop(tas)
        if d > vu[c]:
            continue
        for v in voisins(c):
            if v in occupees:
                continue
            nd = d + (COUT_DIAGONALE if v[0] != c[0] and v[1] != c[1] else 1)
            if nd <= p.u["vitesse"] and nd < vu.get(v, 99):
                vu[v] = nd
                heapq.heappush(tas, (nd, v))
    return vu


def menace(p):
    u = p.u
    return (u["deg"][0] + u["deg"][1]) / 2 * p.nombre * (1 + u["att"] / 10)


def attaque(att, cible, rng, distance_tir=None):
    """distance_tir=None -> corps à corps (avec riposte)."""
    if distance_tir is not None:
        m = PENALITE_HORS_PORTEE if distance_tir > att.u["portee"] else 1.0
        att.munitions -= 1
        cible.pv_total -= degats(att, cible, rng, m * att.mult)
        return
    m = PENALITE_CAC_TIREUR if att.tireur else 1.0
    cible.pv_total -= degats(att, cible, rng, m * att.mult)
    if cible.vivante and not cible.a_riposte:
        cible.a_riposte = True
        m2 = PENALITE_CAC_TIREUR if cible.tireur else 1.0
        att.pv_total -= degats(cible, att, rng, m2 * cible.mult)


def jouer(p, piles, rng):
    ennemis = [e for e in piles if e.vivante and e.camp != p.camp]
    if not ennemis:
        return
    adjacents = [e for e in ennemis if dist(p.pos, e.pos) == 1]
    if p.tireur:
        if adjacents:
            attaque(p, max(adjacents, key=menace), rng)
            return
        if p.munitions > 0:
            a_portee = [e for e in ennemis if dist_tir(p.pos, e.pos) <= p.u["portee"]]
            cible = max(a_portee or ennemis, key=menace)
            attaque(p, cible, rng, dist_tir(p.pos, cible.pos))
            return
    occupees = {q.pos for q in piles if q.vivante and q is not p}
    reach = accessibles(p, occupees)
    options = []
    for e in ennemis:
        cases = [c for c in voisins(e.pos) if c in reach]
        if cases:
            prio = (1 if e.tireur else 0, menace(e))
            options.append((prio, e, min(cases, key=lambda c: reach[c])))
    if options:
        _, cible, case = max(options, key=lambda o: o[0])
        p.pos = case
        attaque(p, cible, rng)
        return
    proche = min(ennemis, key=lambda e: dist(p.pos, e.pos))
    p.pos = min(reach, key=lambda c: (dist(c, proche.pos), reach[c]))


def deployer(compo, camp, unites, mult):
    par_nom = {u["nom"]: u for u in unites}
    piles = []
    melee = [par_nom[n] for n, k in compo for _ in range(k) if par_nom[n]["portee"] == 0]
    tir = [par_nom[n] for n, k in compo for _ in range(k) if par_nom[n]["portee"] > 0]
    arriere, avant = (0, 1) if camp == "HR" else (COLONNES - 1, COLONNES - 2)
    cases = [(l, arriere) for l in range(LIGNES)]
    # tireurs à l'arrière, mêlée devant ; le surplus de mêlée complète l'arrière
    places_avant = [(l, avant) for l in range(LIGNES)]
    for u, c in zip(tir, cases):
        piles.append(PileG(u, camp, c, mult))
    reste_arriere = cases[len(tir):]
    for u, c in zip(melee, places_avant + reste_arriere):
        piles.append(PileG(u, camp, c, mult))
    return piles


def bataille(unites, rng, mult):
    piles = deployer(COMPO_HR, "HR", unites, mult) + deployer(COMPO_G, "G", unites, mult)
    for p in piles:
        p.init = p.u["initiative"] + rng.randint(1, 12)  # tirée une fois par bataille
    premier = None
    for r in range(1, ROUNDS_MAX + 1):
        debut = {id(p): p.nombre for p in piles}
        for p in piles:
            p.a_riposte = False
        ordre = sorted([p for p in piles if p.vivante],
                       key=lambda p: (p.init, rng.random()), reverse=True)
        bonus = []
        for p in ordre:
            if not p.vivante:
                continue
            m = p.moral()
            if m < 5 and rng.random() < (5 - m) * 0.1:
                continue
            avant = sum(q.pv_total for q in piles if q.camp != p.camp)
            jouer(p, piles, rng)
            if premier is None and sum(q.pv_total for q in piles if q.camp != p.camp) < avant:
                premier = p.camp
            if m > 5 and rng.random() < (m - 5) * 0.1:
                bonus.append(p)
        for p in bonus:
            if p.vivante:
                jouer(p, piles, rng)
        for p in piles:
            p.malus = [x - 1 for x in p.malus if x > 1]
            n0 = debut[id(p)]
            if p.vivante and n0 and (n0 - p.nombre) / n0 > SEUIL_PERTES_MORAL:
                p.malus.append(DUREE_MALUS_MORAL)
        camps = {p.camp for p in piles if p.vivante}
        if len(camps) < 2:
            break
    camps = {p.camp for p in piles if p.vivante}
    vainqueur = camps.pop() if len(camps) == 1 else "N"
    survivants = sum(1 for p in piles if p.vivante and p.camp == vainqueur)
    return vainqueur, r, survivants, premier


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 1000
    mult = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0
    unites = json.loads((Path(__file__).resolve().parents[2] / "jeu" / "donnees" / "unites.json").read_text())
    rng = random.Random(7)
    res = {"HR": 0, "G": 0, "N": 0}
    rounds = 0
    surv = {"HR": 0, "G": 0}
    prem = {"HR": [0, 0], "G": [0, 0]}  # [batailles où ce camp frappe en premier, victoires dans ce cas]
    durees = {}
    for _ in range(n):
        v, r, s, premier = bataille(unites, rng, mult)
        res[v] += 1
        rounds += r
        durees[r] = durees.get(r, 0) + 1
        if v in surv:
            surv[v] += s
        if premier:
            prem[premier][0] += 1
            prem[premier][1] += v == premier
    nb_hr = sum(k for _, k in COMPO_HR)
    nb_g = sum(k for _, k in COMPO_G)
    print(f"Dégâts x{mult} — {n} batailles — HR {nb_hr} piles contre G {nb_g} piles")
    print(f"Victoires : HR {res['HR']/n*100:.0f} %, G {res['G']/n*100:.0f} %, nuls {res['N']/n*100:.0f} %")
    print(f"Durée moyenne : {rounds/n:.1f} rounds ; répartition : "
          + ", ".join(f"{k} r : {v/n*100:.0f} %" for k, v in sorted(durees.items())))
    for c, tot in (("HR", nb_hr), ("G", nb_g)):
        if res[c]:
            print(f"Piles restantes quand {c} gagne : {surv[c]/res[c]:.1f} / {tot}")
    for c in ("HR", "G"):
        a, b = prem[c]
        if a:
            print(f"{c} porte le premier coup dans {a/n*100:.0f} % des batailles et gagne alors {b/a*100:.0f} %")


if __name__ == "__main__":
    main()
