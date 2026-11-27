class_name IA
extends RefCounted
## IA simple pour le camp adverse : joue l'action de la pile active.
## Elle estime les dégâts moyens de chaque attaque possible, retire la riposte
## attendue, et choisit la meilleure. Sinon elle avance vers l'ennemi.


## Dégâts moyens que `att` infligerait à `cible` (sans hasard).
static func degats_moyens(att: Dictionary, cible: Dictionary, mult: float, nb := -1) -> float:
	var u: Dictionary = att["u"]
	var n := Combat.nombre(att) if nb < 0 else nb
	var defense: float = cible["u"]["def"] * (Combat.BONUS_DEFENDRE if cible["defend"] else 1.0)
	var mod: float = clampf(1.0 + (u["att"] - defense) / 10.0, Combat.MOD_MIN, Combat.MOD_MAX)
	return (u["deg"][0] + u["deg"][1]) / 2.0 * n * mod * mult


## Dangerosité d'une pile : dégâts moyens qu'elle peut infliger.
static func menace(p: Dictionary) -> float:
	var u: Dictionary = p["u"]
	var m: float = (u["deg"][0] + u["deg"][1]) / 2.0 * Combat.nombre(p) * (1.0 + u["att"] / 10.0)
	if Combat.tireur(p) and p["munitions"] > 0:
		m *= 1.3
	return m


## Valeur d'un coup : part de la menace ennemie détruite.
static func valeur_coup(degats: float, cible: Dictionary) -> float:
	var part := minf(degats, cible["pv_total"]) / float(cible["pv_total"])
	var bonus_achevement := 0.3 if degats >= cible["pv_total"] else 0.0
	var valeur := (part + bonus_achevement) * menace(cible)
	if Combat.seigneur(cible):
		# tuer le seigneur : point de victoire et moral −1 pour toute son armée
		valeur += part * 150.0 + (300.0 if degats >= cible["pv_total"] else 0.0)
	return valeur


static func jouer(c: Combat) -> void:
	var p = c.actif
	if p == null:
		return
	var ennemis := c.ennemis_de(p)
	if ennemis.is_empty():
		return
	var reach := c.accessibles(p)

	if c.peut_tirer(p):
		# Tireur libre : tirer sur la meilleure cible visible.
		var meilleure = null
		var meilleur_score := -INF
		for e in c.cibles_tir(p):
			var score := valeur_coup(degats_moyens(p, e, c.mult_tir(p, e)), e)
			if score > meilleur_score:
				meilleur_score = score
				meilleure = e
		if meilleure != null:
			c.attaquer(meilleure)
			return
		# Aucune cible visible : aller sur la case la plus proche qui en voit une.
		var case_vue = null
		for case in reach.keys():
			for e in ennemis:
				if c.ligne_de_vue(case, e["pos"]):
					if case_vue == null or reach[case] < reach[case_vue]:
						case_vue = case
					break
		if case_vue != null:
			c.deplacer(case_vue)
			return
	else:
		# Corps à corps : meilleure combinaison cible + case.
		var choix = null
		var meilleur := -INF
		var mult_base := Combat.PENALITE_CAC_TIREUR if Combat.tireur(p) else 1.0
		for e in ennemis:
			for case in c.cases_attaque(p, e, reach):
				var revers := Combat.a_revers(e, case)
				var mult := mult_base * (Combat.BONUS_REVERS if revers else 1.0)
				var deg := degats_moyens(p, e, mult)
				var score := valeur_coup(deg, e)
				# riposte attendue (si la cible survit et n'a pas encore riposté)
				if deg < e["pv_total"] and not e["a_riposte"]:
					var restants := ceili((e["pv_total"] - deg) / float(e["u"]["pv"]))
					var mult_r := Combat.PENALITE_CAC_TIREUR if Combat.tireur(e) else 1.0
					var deg_r := degats_moyens(e, p, mult_r, restants)
					score -= valeur_coup(deg_r, p) * 0.8
				# ne pas finir dans l'égout toxique sans raison
				if c.terrain.get(case, "") == "toxique":
					score -= 0.05 * menace(p)
				# préférer ne pas bouger pour rien
				if case != p["pos"]:
					score -= 0.01
				if score > meilleur:
					meilleur = score
					choix = [e, case]
		if choix != null:
			c.attaquer(choix[0], choix[1])
			return

	# Rien à faire d'ici : avancer (par le chemin réel) vers la cible la plus intéressante.
	var cible = null
	var dist_cible := {}
	var meilleur_c := -INF
	for e in ennemis:
		var dist := c.distances_depuis(e["pos"])
		var score: float = menace(e) / (1.0 + float(dist.get(p["pos"], 99.0)))
		if score > meilleur_c:
			meilleur_c = score
			cible = e
			dist_cible = dist
	var meilleure_case = null
	var dist_min: float = dist_cible.get(p["pos"], INF)
	for case in reach.keys():
		var d: float = dist_cible.get(case, INF)
		if c.terrain.get(case, "") == "toxique":
			d += 2.0
		if d < dist_min or (meilleure_case != null and d == dist_min and reach[case] < reach[meilleure_case]):
			dist_min = d
			meilleure_case = case
	if meilleure_case != null:
		c.deplacer(meilleure_case)
	else:
		c.defendre()
