class_name Combat
extends RefCounted
## Modèle d'une bataille (règles du GDD), indépendant de l'affichage.

const LIGNES := 10
const COLONNES := 14
const COUT_DIAGONALE := 1.5
const MOD_MIN := 0.3
const MOD_MAX := 3.0
const PENALITE_CAC_TIREUR := 0.7
const PENALITE_HORS_PORTEE := 0.5
const BONUS_DEFENDRE := 1.3
const SEUIL_PERTES_MORAL := 0.2
const DUREE_MALUS_MORAL := 3
const ZONE_DEPLOIEMENT := 2   # colonnes de déploiement de chaque camp
const COUT_EAU := 2.0          # multiplicateur de coût de déplacement dans l'eau
const DEGATS_TOXIQUE := 0.05   # part des PV perdus en fin de round sur un égout toxique
const PENALITE_SOMBRE := 0.75  # tir vers ou depuis une zone sombre
const ROUNDS_MAX := 8
const PV_ZONE := 1             # points par tranche de 2 rounds de contrôle d'une zone
const ROUNDS_PAR_POINT_ZONE := 2
const PV_SEIGNEUR := 2
const PV_ANNIHILATION := 10
const BONUS_REVERS := 1.2      # attaque au corps à corps par l'arrière (pas pour le tir)

var piles: Array = []
var round_num := 0
var actif = null              # pile qui joue
var tour_bonus := false       # l'actif joue son tour de moral en fin de round
var file: Array = []          # ordre normal du round
var attente: Array = []       # piles qui ont choisi Attendre
var bonus: Array = []         # piles qui rejouent grâce au moral
var debut_round := {}         # id de pile -> nombre au début du round
var journal: Array = []       # messages pour le joueur
var vainqueur := ""
var rng := RandomNumberGenerator.new()
var camps_gauche_droite: Array = []
var terrain := {}             # case -> "mur" | "obstacle" | "trou" | "eau" | "toxique" | "sombre"
var types_carte: Array = []   # types de terrain présents sur cette carte
var seigneur_mort := {}       # camp -> vrai si son seigneur est tombé
var points_victoire := {}     # camp -> points de victoire
var detail_points := {}       # camp -> {source: points}
var zones: Array = []         # [{cases: [Vector2i], compteur: {camp: rounds}, tenue_par: camp ou ""}]


func _init(unites: Dictionary, armee_a: Array, armee_b: Array, camp_a := "HR", camp_b := "G") -> void:
	rng.randomize()
	generer_terrain()
	generer_zones()
	piles = _deployer(unites, armee_a, camp_a, true) + _deployer(unites, armee_b, camp_b, false)
	for i in piles.size():
		piles[i]["id"] = i
		piles[i]["init"] = int(piles[i]["u"]["initiative"]) + rng.randi_range(1, 12)
	camps_gauche_droite = [camp_a, camp_b]


## Lance la bataille une fois le déploiement terminé.
func commencer() -> void:
	if round_num > 0:
		return
	_demarrer_round()
	_suivant()


# --- Déploiement -------------------------------------------------------------

## Colonnes de la zone de déploiement d'un camp (son bord de grille).
func zone_deploiement(camp: String) -> Array:
	if camp == camps_gauche_droite[0]:
		return range(0, ZONE_DEPLOIEMENT)
	return range(COLONNES - ZONE_DEPLOIEMENT, COLONNES)


func dans_zone(camp: String, c: Vector2i) -> bool:
	return dans_grille(c) and zone_deploiement(camp).has(c.x)


## Place une pile sur une case de sa zone ; échange avec une pile alliée déjà là.
func replacer(p: Dictionary, c: Vector2i) -> bool:
	if round_num > 0 or not dans_zone(p["camp"], c):
		return false
	var autre = pile_en(c)
	if bloquee(c) or (autre != null and autre["camp"] != p["camp"]):
		return false
	if autre != null:
		autre["pos"] = p["pos"]
	p["pos"] = c
	return true


# --- Piles -------------------------------------------------------------------

func _deployer(unites: Dictionary, compo: Array, camp: String, gauche: bool) -> Array:
	var arriere := 0 if gauche else COLONNES - 1
	var avant := 1 if gauche else COLONNES - 2
	var tireurs := []
	var melee := []
	var seigneurs := []
	for entree in compo:
		var u: Dictionary = unites[entree[0]]
		for i in entree[1]:
			if u.get("seigneur", false):
				seigneurs.append(u)
			else:
				(tireurs if u["portee"] > 0 else melee).append(u)
	var res := []
	var ligne_avant := melee.slice(0, LIGNES)
	# le seigneur se place au milieu de la ligne arrière, entre les tireurs
	var ligne_arriere := tireurs.slice(0, tireurs.size() / 2) + seigneurs \
		+ tireurs.slice(tireurs.size() / 2) + melee.slice(LIGNES)
	for colonne in [[ligne_avant, avant], [ligne_arriere, arriere]]:
		var liste: Array = colonne[0]
		var debut := (LIGNES - liste.size()) / 2
		for i in liste.size():
			var u: Dictionary = liste[i]
			res.append({
				"u": u, "camp": camp, "pos": Vector2i(colonne[1], debut + i),
				"pv_total": int(u["pv"]) * int(u["escouade"]),
				"munitions": int(u["munitions"]), "malus": [], "a_riposte": false,
				"defend": false, "a_attendu": false,
				"orient": Vector2i(1, 0) if gauche else Vector2i(-1, 0),
				"mana": int(u.get("intelligence", 0)) * 10,
			})
	return res


static func nombre(p: Dictionary) -> int:
	return ceili(float(p["pv_total"]) / p["u"]["pv"]) if p["pv_total"] > 0 else 0


static func vivante(p: Dictionary) -> bool:
	return p["pv_total"] > 0


static func tireur(p: Dictionary) -> bool:
	return p["u"]["portee"] > 0


static func pv_dessus(p: Dictionary) -> int:
	var reste: int = p["pv_total"] % int(p["u"]["pv"])
	return reste if reste > 0 else int(p["u"]["pv"])


static func a_capacite(p: Dictionary, capacite: String) -> bool:
	return p["u"].get("capacites", []).has(capacite)


static func seigneur(p: Dictionary) -> bool:
	return p["u"].get("seigneur", false)


## Multiplicateur des sorts : puissance magique / 10 + 1.
static func mult_magie(p: Dictionary) -> float:
	return float(p["u"].get("puissance", 0)) / 10.0 + 1.0


func moral(p: Dictionary) -> int:
	var m: int = p["u"]["moral"]
	if not seigneur(p):   # le seigneur n'est pas une escouade
		var remplissage: float = float(nombre(p)) / float(p["u"]["escouade"])
		if remplissage >= 1.0:
			m += 2
		elif remplissage >= 0.75:
			m += 1
		if dans_aura(p):
			m += 1
	m -= p["malus"].size()
	if seigneur_mort.get(p["camp"], false):
		m -= 1
	return clampi(m, 0, 10)


## Vrai si la pile est dans l'aura de moral d'un seigneur allié vivant.
func dans_aura(p: Dictionary) -> bool:
	for s in piles:
		if vivante(s) and seigneur(s) and s["camp"] == p["camp"] and s["id"] != p["id"] \
				and distance_tir(s["pos"], p["pos"]) <= s["u"].get("aura", 0):
			return true
	return false


func pile_en(c: Vector2i):
	for p in piles:
		if vivante(p) and p["pos"] == c:
			return p
	return null


func ennemis_de(p: Dictionary) -> Array:
	return piles.filter(func(e): return vivante(e) and e["camp"] != p["camp"])


# --- Géométrie ---------------------------------------------------------------

static func dans_grille(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < COLONNES and c.y >= 0 and c.y < LIGNES


static func voisins(c: Vector2i) -> Array:
	var res := []
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx != 0 or dy != 0:
				var v := c + Vector2i(dx, dy)
				if dans_grille(v):
					res.append(v)
	return res


static func adjacent(a: Vector2i, b: Vector2i) -> bool:
	return a != b and absi(a.x - b.x) <= 1 and absi(a.y - b.y) <= 1


static func distance_tir(a: Vector2i, b: Vector2i) -> float:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return maxi(dx, dy) + (COUT_DIAGONALE - 1.0) * mini(dx, dy)


## Cases atteignables par la pile : {case: coût}. Diagonale = 1,5 ; on ne traverse pas les piles.
func accessibles(p: Dictionary) -> Dictionary:
	var vitesse := float(p["u"]["vitesse"])
	var couts := {p["pos"]: 0.0}
	var a_traiter := [p["pos"]]
	while not a_traiter.is_empty():
		# petite file de priorité naïve (grille de 80 cases)
		var meilleur := 0
		for i in a_traiter.size():
			if couts[a_traiter[i]] < couts[a_traiter[meilleur]]:
				meilleur = i
		var c: Vector2i = a_traiter.pop_at(meilleur)
		for v in voisins(c):
			var cible_pas: Vector2i = v
			var nd: float = couts[c] + cout_pas(c, v)
			# Bond : franchir une seule case de trou, en ligne droite ou en diagonale
			if terrain.get(v, "") == "trou" and a_capacite(p, "bond"):
				cible_pas = v + (v - c)
				nd += cout_pas(v, cible_pas)
				if not dans_grille(cible_pas):
					continue
			if pile_en(cible_pas) != null or bloquee(cible_pas):
				continue
			if nd <= vitesse and nd < couts.get(cible_pas, INF):
				couts[cible_pas] = nd
				a_traiter.append(cible_pas)
	couts.erase(p["pos"])
	return couts


func peut_tirer(p: Dictionary) -> bool:
	if not tireur(p) or p["munitions"] <= 0:
		return false
	for e in ennemis_de(p):
		if adjacent(p["pos"], e["pos"]):
			return false
	return true


## Cases d'où la pile peut attaquer la cible au corps à corps ce tour-ci
## (sa case actuelle si elle est au contact, plus les cases accessibles autour de la cible).
func cases_attaque(p: Dictionary, cible: Dictionary, reach: Dictionary) -> Array:
	var res := []
	if adjacent(p["pos"], cible["pos"]):
		res.append(p["pos"])
	for v in voisins(cible["pos"]):
		if reach.has(v):
			res.append(v)
	return res


## Case d'attaque par défaut : rester sur place si possible, sinon la plus proche.
func case_attaque(p: Dictionary, cible: Dictionary, reach: Dictionary):
	if adjacent(p["pos"], cible["pos"]):
		return p["pos"]
	var meilleure = null
	for v in cases_attaque(p, cible, reach):
		if meilleure == null or reach[v] < reach[meilleure]:
			meilleure = v
	return meilleure


static func direction(de: Vector2i, vers: Vector2i) -> Vector2i:
	return Vector2i(signi(vers.x - de.x), signi(vers.y - de.y))


## Vrai si une attaque depuis la case `de` frappe la cible dans le dos
## (une des 3 cases derrière elle, selon son orientation).
static func a_revers(cible: Dictionary, de: Vector2i) -> bool:
	var d := direction(cible["pos"], de)
	var f: Vector2i = cible["orient"]
	return d.x * f.x + d.y * f.y < 0


# --- Déroulement -------------------------------------------------------------

func _demarrer_round() -> void:
	round_num += 1
	debut_round.clear()
	var vivantes := piles.filter(func(p): return vivante(p))
	for p in vivantes:
		p["a_riposte"] = false
		p["a_attendu"] = false
		p["tirage"] = rng.randf()
		debut_round[p["id"]] = nombre(p)
	vivantes.sort_custom(func(a, b):
		return a["init"] > b["init"] or (a["init"] == b["init"] and a["tirage"] > b["tirage"]))
	file = vivantes
	attente = []
	bonus = []
	_log("— Round %d —" % round_num)


func _fin_round() -> void:
	for p in piles:
		if vivante(p) and terrain.get(p["pos"], "") == "toxique":
			var perte := maxi(1, int(p["pv_total"] * DEGATS_TOXIQUE))
			var avant := nombre(p)
			p["pv_total"] = maxi(0, p["pv_total"] - perte)
			_log("%s suffoque dans l'égout toxique : %d dégâts, %d morts" % [p["u"]["nom"], perte, avant - nombre(p)])
			if not vivante(p):
				_log("%s est anéanti" % p["u"]["nom"])
				if seigneur(p):
					_seigneur_tombe(p)
	_compter_zones()
	for p in piles:
		if not vivante(p):
			continue
		var malus: Array = []
		for x in p["malus"]:
			if x > 1:
				malus.append(x - 1)
		var n0: int = debut_round.get(p["id"], 0)
		if n0 > 0 and not seigneur(p) and float(n0 - nombre(p)) / n0 > SEUIL_PERTES_MORAL:
			malus.append(DUREE_MALUS_MORAL)
			_log("%s : lourdes pertes, moral −1 pour 3 rounds" % p["u"]["nom"])
		p["malus"] = malus


## Passe à la pile suivante (saute les morts, applique le moral).
func _suivant() -> void:
	actif = null
	while vainqueur == "":
		var p = null
		tour_bonus = false
		if not file.is_empty():
			p = file.pop_front()
		elif not attente.is_empty():
			p = attente.pop_front()
		elif not bonus.is_empty():
			p = bonus.pop_front()
			tour_bonus = true
		else:
			_fin_round()
			if _verifier_fin():
				return
			if round_num >= ROUNDS_MAX:
				_fin_par_points()
				return
			_demarrer_round()
			continue
		if not vivante(p):
			continue
		p["defend"] = false
		if not tour_bonus and not p["a_attendu"]:
			var m := moral(p)
			if m < 5 and rng.randf() < (5 - m) * 0.1:
				_log("%s hésite et passe son tour (moral %d)" % [p["u"]["nom"], m])
				continue
			if m > 5 and rng.randf() < (m - 5) * 0.1:
				bonus.append(p)
				_log("%s est galvanisé : il rejouera en fin de round" % p["u"]["nom"])
		if tour_bonus:
			_log("%s rejoue (moral)" % p["u"]["nom"])
		actif = p
		return


func _verifier_fin() -> bool:
	var camps := {}
	for p in piles:
		if vivante(p):
			camps[p["camp"]] = true
	if camps.size() == 1:
		var gagnant: String = camps.keys()[0]
		_ajouter_points(gagnant, "annihilation", PV_ANNIHILATION)
		_log("Annihilation totale : +%d points" % PV_ANNIHILATION)
		_fin_par_points()
		return true
	if camps.is_empty():
		_fin_par_points()
		return true
	return false


## Fin de bataille : le camp qui a le plus de points de victoire gagne.
func _fin_par_points() -> void:
	actif = null
	var a: int = points_victoire.get(camps_gauche_droite[0], 0)
	var b: int = points_victoire.get(camps_gauche_droite[1], 0)
	if a == b:
		vainqueur = "nul"
		_log("Égalité aux points (%d à %d)" % [a, b])
	else:
		vainqueur = camps_gauche_droite[0] if a > b else camps_gauche_droite[1]
		_log("Victoire aux points (%d à %d)" % [maxi(a, b), mini(a, b)])


func camp_adverse(camp: String) -> String:
	return camps_gauche_droite[1] if camp == camps_gauche_droite[0] else camps_gauche_droite[0]


func _ajouter_points(camp: String, source: String, n: int) -> void:
	points_victoire[camp] = points_victoire.get(camp, 0) + n
	if not detail_points.has(camp):
		detail_points[camp] = {}
	detail_points[camp][source] = detail_points[camp].get(source, 0) + n


func _seigneur_tombe(s: Dictionary) -> void:
	seigneur_mort[s["camp"]] = true
	_ajouter_points(camp_adverse(s["camp"]), "seigneur", PV_SEIGNEUR)
	_log("Le seigneur est tombé : moral −1 pour toute son armée, +%d points pour l'ennemi" % PV_SEIGNEUR)


func _terminer_action() -> void:
	if not _verifier_fin():
		_suivant()


# --- Actions du joueur actif -------------------------------------------------

func deplacer(c: Vector2i) -> bool:
	if actif == null or not accessibles(actif).has(c):
		return false
	actif["orient"] = direction(actif["pos"], c)
	actif["pos"] = c
	_terminer_action()
	return true


## Attaque la cible. `depuis` = case choisie pour le corps à corps (sinon case par défaut).
func attaquer(cible: Dictionary, depuis = null) -> bool:
	if actif == null or not vivante(cible) or cible["camp"] == actif["camp"]:
		return false
	if peut_tirer(actif):
		if not ligne_de_vue(actif["pos"], cible["pos"]):
			return false
		var mult := mult_tir(actif, cible)
		actif["munitions"] -= 1
		var loin: bool = distance_tir(actif["pos"], cible["pos"]) > actif["u"]["portee"]
		_frapper(actif, cible, mult, "tire de loin sur" if loin else "tire sur")
		_terminer_action()
		return true
	var reach := accessibles(actif)
	var c = case_attaque(actif, cible, reach) if depuis == null else depuis
	if c == null or not cases_attaque(actif, cible, reach).has(c):
		return false
	actif["pos"] = c
	actif["orient"] = direction(c, cible["pos"])
	var mult := PENALITE_CAC_TIREUR if tireur(actif) else 1.0
	var verbe := "attaque"
	if a_revers(cible, c):
		mult *= BONUS_REVERS
		verbe = "attaque à revers"
	_frapper(actif, cible, mult, verbe)
	if vivante(cible) and vivante(actif) and not cible["a_riposte"]:
		cible["a_riposte"] = true
		cible["orient"] = direction(cible["pos"], actif["pos"])  # elle se tourne pour riposter
		_frapper(cible, actif, PENALITE_CAC_TIREUR if tireur(cible) else 1.0, "riposte sur")
	_terminer_action()
	return true


func defendre() -> void:
	if actif == null:
		return
	actif["defend"] = true
	_log("%s se met en défense (+30 %% Déf)" % actif["u"]["nom"])
	_suivant()


func peut_attendre() -> bool:
	return actif != null and not actif["a_attendu"] and not tour_bonus \
		and not (file.is_empty() and attente.is_empty())


func attendre() -> void:
	if not peut_attendre():
		return
	actif["a_attendu"] = true
	attente.append(actif)
	_log("%s attend" % actif["u"]["nom"])
	_suivant()


# --- Dégâts ------------------------------------------------------------------

func _frapper(att: Dictionary, cible: Dictionary, mult: float, verbe: String) -> void:
	var u: Dictionary = att["u"]
	var lo: int = u["deg"][0]
	var hi: int = u["deg"][1]
	var n := nombre(att)
	var c: int = u["chance"]
	var r := rng.randf()
	var base := 0
	var note := ""
	if c > 5 and r < (c - 5) * 0.1:
		base = hi * n
		note = " (coup critique !)"
	elif c < 5 and r < (5 - c) * 0.1:
		base = lo * n
		note = " (échec critique)"
	else:
		for i in n:
			base += rng.randi_range(lo, hi)
	var defense: float = cible["u"]["def"] * (BONUS_DEFENDRE if cible["defend"] else 1.0)
	var mod := clampf(1.0 + (u["att"] - defense) / 10.0, MOD_MIN, MOD_MAX)
	var degats := maxi(1, int(base * mod * mult))
	var avant := nombre(cible)
	cible["pv_total"] = maxi(0, cible["pv_total"] - degats)
	var tues := avant - nombre(cible)
	_log("%s %s %s : %d dégâts, %d tués%s" % [u["nom"], verbe, cible["u"]["nom"], degats, tues, note])
	if not vivante(cible):
		_log("%s est anéanti" % cible["u"]["nom"])
		if seigneur(cible):
			_seigneur_tombe(cible)


func _log(m: String) -> void:
	journal.append(m)
	if journal.size() > 60:
		journal.pop_front()



# --- Terrain -----------------------------------------------------------------

static func bloque_type(t: String) -> bool:
	return t == "mur" or t == "obstacle" or t == "trou"


func bloquee(c: Vector2i) -> bool:
	return bloque_type(terrain.get(c, ""))


## Coût pour passer de la case `de` à la case voisine `vers`.
func cout_pas(de: Vector2i, vers: Vector2i) -> float:
	var base := COUT_DIAGONALE if vers.x != de.x and vers.y != de.y else 1.0
	return base * (COUT_EAU if terrain.get(vers, "") == "eau" else 1.0)


## Vrai si aucun mur ne coupe le segment entre les centres des deux cases.
func ligne_de_vue(a: Vector2i, b: Vector2i) -> bool:
	var pa := Vector2(a) + Vector2(0.5, 0.5)
	var pb := Vector2(b) + Vector2(0.5, 0.5)
	var etapes := int(pa.distance_to(pb) * 8) + 1
	for i in range(1, etapes):
		var q := pa.lerp(pb, float(i) / etapes)
		var c := Vector2i(floori(q.x), floori(q.y))
		if c != a and c != b and terrain.get(c, "") == "mur":
			return false
	return true


## Multiplicateur d'un tir : hors de portée et zones sombres.
func mult_tir(att: Dictionary, cible: Dictionary) -> float:
	var m := 1.0
	if distance_tir(att["pos"], cible["pos"]) > att["u"]["portee"]:
		m *= PENALITE_HORS_PORTEE
	if terrain.get(att["pos"], "") == "sombre" or terrain.get(cible["pos"], "") == "sombre":
		m *= PENALITE_SOMBRE
	return m


## Ennemis que la pile peut prendre pour cible d'un tir maintenant.
func cibles_tir(p: Dictionary) -> Array:
	if not peut_tirer(p):
		return []
	return ennemis_de(p).filter(func(e): return ligne_de_vue(p["pos"], e["pos"]))


## Distance de marche depuis une case vers toutes les autres (terrain seul, piles ignorées).
func distances_depuis(depart: Vector2i) -> Dictionary:
	var d := {depart: 0.0}
	var a_traiter := [depart]
	while not a_traiter.is_empty():
		var meilleur := 0
		for i in a_traiter.size():
			if d[a_traiter[i]] < d[a_traiter[meilleur]]:
				meilleur = i
		var c: Vector2i = a_traiter.pop_at(meilleur)
		for v in voisins(c):
			if bloquee(v):
				continue
			var nd: float = d[c] + cout_pas(c, v)
			if nd < d.get(v, INF):
				d[v] = nd
				a_traiter.append(v)
	return d


## Carte au hasard, symétrique gauche-droite ; zones de déploiement dégagées.
func generer_terrain() -> void:
	for essai in 50:
		terrain.clear()
		var moitie := COLONNES / 2
		var col_min := ZONE_DEPLOIEMENT + 1
		# chaque carte n'utilise que 2 à 4 types de terrain, tirés au hasard
		var types := ["mur", "obstacle", "trou", "eau", "toxique", "sombre"]
		types.shuffle()
		types = types.slice(0, rng.randi_range(2, 4))
		types_carte = types
		for type in types:
			match type:
				"mur":   # 2 segments de 2 à 3 cases
					for i in 2:
						var c := Vector2i(rng.randi_range(col_min, moitie - 1), rng.randi_range(1, LIGNES - 2))
						var dir := Vector2i(0, 1) if rng.randf() < 0.6 else Vector2i(1, 0)
						for k in rng.randi_range(2, 3):
							_poser(c + dir * k, "mur")
				"obstacle":   # cases isolées
					for i in rng.randi_range(2, 3):
						_poser(Vector2i(rng.randi_range(col_min, moitie - 1), rng.randi_range(0, LIGNES - 1)), "obstacle")
				_:   # taches : trou, eau, égout toxique, zone sombre
					var centre := Vector2i(rng.randi_range(col_min, moitie - 1), rng.randi_range(0, LIGNES - 1))
					var taille := 4 if type == "sombre" else rng.randi_range(2, 4)
					for k in taille:
						var c: Vector2i = centre + Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
						if not terrain.has(c):
							_poser(c, type)
		# symétrie
		for c in terrain.keys():
			terrain[Vector2i(COLONNES - 1 - c.x, c.y)] = terrain[c]
		if _carte_connexe():
			return
	terrain.clear()


func _poser(c: Vector2i, type: String) -> void:
	if dans_grille(c) and c.x > ZONE_DEPLOIEMENT and c.x < COLONNES / 2:
		terrain[c] = type


func _carte_connexe() -> bool:
	var libres := 0
	for x in COLONNES:
		for y in LIGNES:
			if not bloquee(Vector2i(x, y)):
				libres += 1
	return distances_depuis(Vector2i(0, 0)).size() == libres



# --- Zones à contrôler -------------------------------------------------------

## 1 à 3 zones, symétriques : une zone centrale de 2 cases et/ou une paire en miroir.
func generer_zones() -> void:
	zones.clear()
	var n := rng.randi_range(1, 3)
	var milieu := COLONNES / 2
	if n != 2:
		var y := rng.randi_range(1, LIGNES - 2)
		_ajouter_zone([Vector2i(milieu - 1, y), Vector2i(milieu, y)])
	if n >= 2:
		for essai in 20:
			var c := Vector2i(rng.randi_range(ZONE_DEPLOIEMENT + 2, milieu - 2), rng.randi_range(0, LIGNES - 1))
			if zone_en(c) == null:
				_ajouter_zone([c])
				_ajouter_zone([Vector2i(COLONNES - 1 - c.x, c.y)])
				break


func _ajouter_zone(cases: Array) -> void:
	for c in cases:
		terrain.erase(c)   # une zone est toujours praticable (symétrie conservée)
	zones.append({"cases": cases, "compteur": {}, "tenue_par": ""})


func zone_en(c: Vector2i):
	for z in zones:
		if z["cases"].has(c):
			return z
	return null


## Camp qui tient la zone : une de ses piles dessus, aucune pile ennemie dessus ni adjacente.
func camp_tenant(z: Dictionary) -> String:
	var occupants := []
	for c in z["cases"]:
		var p = pile_en(c)
		if p != null:
			occupants.append(p)
	if occupants.is_empty():
		return ""
	var camp: String = occupants[0]["camp"]
	for p in occupants:
		if p["camp"] != camp:
			return ""
		for e in ennemis_de(p):
			if adjacent(p["pos"], e["pos"]):
				return ""
	return camp


func _compter_zones() -> void:
	for z in zones:
		var camp := camp_tenant(z)
		z["tenue_par"] = camp
		if camp == "":
			continue
		z["compteur"][camp] = z["compteur"].get(camp, 0) + 1
		if z["compteur"][camp] >= ROUNDS_PAR_POINT_ZONE:
			z["compteur"][camp] = 0
			_ajouter_points(camp, "zones", PV_ZONE)
			_log("%s tient une zone depuis 2 rounds : +%d point" % [
				"Les Hommes-rats" if camp == "HR" else "La Garde", PV_ZONE])
