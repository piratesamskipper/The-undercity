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
	return (part + bonus_achevement) * menace(cible)


static func jouer(c: Combat) -> void:
	var p = c.actif
	if p == null:
		return
	var ennemis := c.ennemis_de(p)
	if ennemis.is_empty():
		return

	# Tireur libre : tirer sur la meilleure cible.
	if c.peut_tirer(p):
		var meilleure = null
		var meilleur_score := -INF
		for e in ennemis:
			var loin: bool = Combat.distance_tir(p["pos"], e["pos"]) > p["u"]["portee"]
			var mult := Combat.PENALITE_HORS_PORTEE if loin else 1.0
			var score := valeur_coup(degats_moyens(p, e, mult), e)
			if score > meilleur_score:
				meilleur_score = score
				meilleure = e
		c.attaquer(meilleure)
		return

	# Corps à corps : meilleure combinaison cible + case.
	var reach := c.accessibles(p)
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
			# préférer ne pas bouger pour rien
			if case != p["pos"]:
				score -= 0.01
			if score > meilleur:
				meilleur = score
				choix = [e, case]
	if choix != null:
		c.attaquer(choix[0], choix[1])
		return

	# Rien à portée : avancer vers la cible la plus intéressante.
	var cible = null
	var meilleur_c := -INF
	for e in ennemis:
		var d := Combat.distance_tir(p["pos"], e["pos"])
		var score := menace(e) / (1.0 + d)
		if score > meilleur_c:
			meilleur_c = score
			cible = e
	var meilleure_case = null
	var dist_min := Combat.distance_tir(p["pos"], cible["pos"])
	for case in reach.keys():
		var d := Combat.distance_tir(case, cible["pos"])
		if d < dist_min or (meilleure_case != null and d == dist_min and reach[case] < reach[meilleure_case]):
			dist_min = d
			meilleure_case = case
	if meilleure_case != null:
		c.deplacer(meilleure_case)
	else:
		c.defendre()
