# Simulateur de duels

Simule des duels entre deux piles pleines avec les règles du GDD : formule d'attaque, riposte, moral, chance, tir et munitions.

```
python3 simulation.py 2000
```

Les unités sont dans `jeu/donnees/unites.json` (partagé avec le jeu), recopiées depuis le tableau du GDD.

Pour les batailles armée contre armée sur la grille 8×10 (compositions en haut du fichier) :

```
python3 armee.py 1000        # dégâts normaux
python3 armee.py 1000 0.5    # dégâts divisés par 2
```

Limites : il n'y a ni grille ni obstacles, et les capacités spéciales, Défendre et Attendre ne sont pas simulés.
