"""Simulateur de duels entre piles pour The Undercity (règles du GDD).

Usage : python3 simulation.py [nb_combats_par_duel]

Modèle simplifié : deux piles pleines face à face sur une ligne, à DISTANCE_DEPART
cases l'une de l'autre. Pas d'obstacles, pas de capacités spéciales, pas d'action
Défendre ni Attendre : chaque pile avance et attaque, chaque tireur tire tant qu'il
a des munitions et n'est pas au contact.
"""

import json
import math
import random
import sys
from pathlib import Path

DISTANCE_DEPART = 13  # grille de 14 de large, piles aux deux bords
ROUNDS_MAX = 30
MOD_MIN, MOD_MAX = 0.3, 3.0
PENALITE_CAC_TIREUR = 0.7
PENALITE_HORS_PORTEE = 0.5
SEUIL_PERTES_MORAL = 0.20
DUREE_MALUS_MORAL = 3


class Pile:
    def __init__(self, u):
        self.u = u
        self.pv_total = u["pv"] * u["escouade"]
        self.munitions = u["munitions"]
        self.malus = []          # rounds restants pour chaque malus de moral
        self.a_riposte = False

    @property
    def nombre(self):
        return math.ceil(self.pv_total / self.u["pv"]) if self.pv_total > 0 else 0

    @property
    def vivante(self):
        return self.pv_total > 0

    @property
    def tireur(self):
        return self.u["portee"] > 0

    def moral(self):
        m = self.u["moral"]
        remplissage = self.nombre / self.u["escouade"]
        if remplissage >= 1:
            m += 2
        elif remplissage >= 0.75:
            m += 1
        m -= len(self.malus)
        return max(0, min(10, m))


def degats(att, cible, rng, mult=1.0):
    u = att.u
    lo, hi = u["deg"]
    c = u["chance"]
    r = rng.random()
    if c > 5 and r < (c - 5) * 0.1:
        base = hi * att.nombre
    elif c < 5 and r < (5 - c) * 0.1:
        base = lo * att.nombre
    else:
        base = sum(rng.randint(lo, hi) for _ in range(att.nombre))
    mod = 1 + (u["att"] - cible.u["def"]) / 10
    mod = max(MOD_MIN, min(MOD_MAX, mod))
    return max(1, int(base * mod * mult))


def frapper(att, cible, rng, distance):
    """Une action d'attaque. Renvoie True si c'était un corps à corps."""
    if att.tireur and distance > 1 and att.munitions > 0:
        mult = PENALITE_HORS_PORTEE if distance > att.u["portee"] else 1.0
        att.munitions -= 1
        cible.pv_total -= degats(att, cible, rng, mult)
        return False
    mult = PENALITE_CAC_TIREUR if att.tireur else 1.0
    cible.pv_total -= degats(att, cible, rng, mult)
    if cible.vivante and not cible.a_riposte:
        cible.a_riposte = True
        m2 = PENALITE_CAC_TIREUR if cible.tireur else 1.0
        att.pv_total -= degats(cible, att, rng, m2)
    return True


def tour(pile, cible, etat, rng):
    d = etat["distance"]
    if pile.tireur and d > 1 and pile.munitions > 0:
        frapper(pile, cible, rng, d)
        return
    pas = min(pile.u["vitesse"], d - 1)
    etat["distance"] = d - pas
    if etat["distance"] == 1:
        frapper(pile, cible, rng, 1)


def combat(ua, ub, rng):
    a, b = Pile(ua), Pile(ub)
    etat = {"distance": DISTANCE_DEPART}
    for p in (a, b):
        p.init = p.u["initiative"] + rng.randint(1, 12)  # tirée une fois par bataille
    for r in range(1, ROUNDS_MAX + 1):
        debut = {id(a): a.nombre, id(b): b.nombre}
        a.a_riposte = b.a_riposte = False
        ordre = sorted([a, b], key=lambda p: (p.init, rng.random()), reverse=True)
        bonus = []
        for p in ordre:
            if not (a.vivante and b.vivante):
                break
            if not p.vivante:
                continue
            m = p.moral()
            if m < 5 and rng.random() < (5 - m) * 0.1:
                continue  # passe son tour
            tour(p, b if p is a else a, etat, rng)
            if m > 5 and rng.random() < (m - 5) * 0.1:
                bonus.append(p)
        for p in bonus:  # deuxième tour en fin de round
            if a.vivante and b.vivante and p.vivante:
                tour(p, b if p is a else a, etat, rng)
        for p in (a, b):
            p.malus = [x - 1 for x in p.malus if x > 1]
            n0 = debut[id(p)]
            if p.vivante and n0 and (n0 - p.nombre) / n0 > SEUIL_PERTES_MORAL:
                p.malus.append(DUREE_MALUS_MORAL)
        if not (a.vivante and b.vivante):
            break
    if a.vivante and not b.vivante:
        return "A", r, a.nombre / ua["escouade"]
    if b.vivante and not a.vivante:
        return "B", r, b.nombre / ub["escouade"]
    return "N", r, 0.0


def duel(ua, ub, n, rng):
    v = nul = 0
    rounds = restant = 0.0
    for _ in range(n):
        res, r, reste = combat(ua, ub, rng)
        rounds += r
        if res == "A":
            v += 1
            restant += reste
        elif res == "N":
            nul += 1
    return {"victoire": v / n, "nul": nul / n, "rounds": rounds / n,
            "restant": (restant / v) if v else 0.0}


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 2000
    unites = json.loads((Path(__file__).resolve().parents[2] / "jeu" / "donnees" / "unites.json").read_text())
    unites = [u for u in unites if not u.get("seigneur")]  # duels entre escouades seulement
    rng = random.Random(42)
    court = lambda u: u["nom"][:14]

    print("## Puissance brute d'une pile pleine\n")
    print("| Unité | Faction | Tier | Créatures | PV totaux | Dégâts moyens (sans modif.) |")
    print("|---|---|---|---|---|---|")
    for u in unites:
        moy = (u["deg"][0] + u["deg"][1]) / 2 * u["escouade"]
        print(f"| {u['nom']} | {u['faction']} | {u['tier']} | {u['escouade']} | "
              f"{u['pv'] * u['escouade']} | {moy:.0f} |")

    hr = [u for u in unites if u["faction"] == "HR"]
    g = [u for u in unites if u["faction"] == "G"]
    print(f"\n## % de victoire de la ligne (HR) contre la colonne (G), {n} combats par duel\n")
    print("| HR \\ G | " + " | ".join(court(u) for u in g) + " |")
    print("|---" * (len(g) + 1) + "|")
    for ua in hr:
        cells = []
        for ub in g:
            s = duel(ua, ub, n, rng)
            cell = f"{s['victoire']*100:.0f} % ({s['rounds']:.1f} r)"
            if s["nul"] > 0.01:
                cell += f" nuls {s['nul']*100:.0f} %"
            cells.append(cell)
        print(f"| {court(ua)} | " + " | ".join(cells) + " |")

    print("\n## Détail : même tier, chaque camp\n")
    print("| Duel | Victoire HR | Victoire G | Rounds moyens | Reste au vainqueur HR | Reste au vainqueur G |")
    print("|---|---|---|---|---|---|")
    for ua in hr:
        for ub in g:
            if ua["tier"] != ub["tier"]:
                continue
            s = duel(ua, ub, n, rng)
            s2 = duel(ub, ua, n, rng)
            print(f"| {ua['nom']} vs {ub['nom']} | {s['victoire']*100:.0f} % | {s2['victoire']*100:.0f} % | "
                  f"{s['rounds']:.1f} | {s['restant']*100:.0f} % | {s2['restant']*100:.0f} % |")


if __name__ == "__main__":
    main()
