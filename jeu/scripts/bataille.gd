extends Node2D
## Écran de bataille : affiche un Combat et transmet les touchers du joueur.
## Le camp joué par l'IA, la carte et les armées viennent de Donnees (menu et éditeurs).

const TAILLE_CASE := 60.0
const ORIGINE := Vector2(212, 60)
const PANNEAU_DROIT := 1064.0
const LARGEUR_PANNEAU := 200.0

const COULEURS := {"HR": Color(0.55, 0.32, 0.2), "G": Color(0.22, 0.38, 0.62)}
const NOMS_CAMPS := {"HR": "Hommes-rats", "G": "Garde"}
const NOMS_CAPACITES := {"bond": "Bond"}


const BOUTON_DEFENDRE := Rect2(8, 570, 196, 56)
const BOUTON_ATTENDRE := Rect2(8, 638, 196, 56)
const BOUTON_REJOUER := Rect2(422, 400, 200, 60)
const BOUTON_MENU := Rect2(642, 400, 200, 60)
const DELAI_IA := 0.6
# type de terrain -> [couleur, intensité du mélange avec la case, description]
const TERRAINS := {
	"mur": [Color(0.42, 0.4, 0.37), 1.0, "Mur : infranchissable, bloque la ligne de vue."],
	"obstacle": [Color(0.36, 0.27, 0.17), 0.85, "Obstacle : infranchissable, ne bloque pas les tirs."],
	"trou": [Color(0.0, 0.0, 0.0), 0.9, "Trou : infranchissable, ne bloque pas les tirs."],
	"zone": [Color(0, 0, 0), 0.0, "Zone à contrôler : une pile dessus et aucune pile ennemie adjacente. 1 point tous les 2 rounds tenus."],
	"eau": [Color(0.15, 0.32, 0.5), 0.6, "Eau : une case coûte 2 de vitesse (3 en diagonale)."],
	"toxique": [Color(0.3, 0.5, 0.12), 0.6, "Égout toxique : -5 % des PV en fin de round pour la pile qui s'y trouve."],
	"sombre": [Color(0.06, 0.03, 0.12), 0.7, "Zone sombre : tir vers ou depuis cette case x0,75."],
}
const BOUTON_LANCER := Rect2(8, 600, 196, 70)

var unites := {}
var combat: Combat
var selection = null      # pile dont on affiche les stats (sinon l'actif)
var cible = null          # ennemi visé au corps à corps : on choisit ensuite la case d'attaque
var message := ""         # retour au joueur (action impossible, etc.)
var police: Font
var camp_ia := ""         # camp joué par l'IA ("" = deux joueurs)
var attente_ia := 0.0
var a_deployer: Array = []  # camps humains qui doivent encore valider leur déploiement
# Pendant le déploiement, l'initiative adverse est cachée. Plus tard, une capacité
# spéciale de seigneur pourra la révéler : ce drapeau en tiendra lieu.
var voir_init_adverse := false


func _ready() -> void:
	police = ThemeDB.fallback_font
	unites = Donnees.unites_par_nom()
	camp_ia = Donnees.camp_ia
	nouvelle_bataille()


func _process(delta: float) -> void:
	if not a_deployer.is_empty() or combat.vainqueur != "" or not _tour_ia():
		attente_ia = 0.0
		return
	attente_ia += delta
	if attente_ia >= DELAI_IA:
		attente_ia = 0.0
		IA.jouer(combat)
		queue_redraw()


func _tour_ia() -> bool:
	return combat.actif != null and camp_ia != "" and combat.actif["camp"] == camp_ia


func nouvelle_bataille() -> void:
	var carte: Dictionary = Donnees.cartes.get(Donnees.carte_choisie, {})
	combat = Combat.new(unites, Donnees.armees["HR"], Donnees.armees["G"], "HR", "G", carte)
	a_deployer = []
	for camp in ["HR", "G"]:
		if camp != camp_ia:
			a_deployer.append(camp)
	if a_deployer.is_empty():
		combat.commencer()
	selection = null
	cible = null
	message = ""
	queue_redraw()


# --- Conversions -------------------------------------------------------------

func _case_vers_ecran(c: Vector2i) -> Vector2:
	return ORIGINE + Vector2(c.x, c.y) * TAILLE_CASE


func _ecran_vers_case(p: Vector2) -> Vector2i:
	var r := (p - ORIGINE) / TAILLE_CASE
	return Vector2i(floori(r.x), floori(r.y))


func _abreviation(nom: String) -> String:
	if nom.begins_with("Seigneur"):
		return "SEIGN."
	var mots := nom.split(" ")
	return (mots[0].substr(0, 3) + (mots[-1].substr(0, 1) if mots.size() > 1 else "")).to_upper()


# --- Dessin ------------------------------------------------------------------

func _draw() -> void:
	var actif = combat.actif
	var reach := {}
	var cibles := {}     # id de pile -> "cac" | "tir" | "loin"
	if actif != null:
		reach = combat.accessibles(actif)
		if combat.peut_tirer(actif):
			for e in combat.cibles_tir(actif):
				cibles[e["id"]] = "loin" if combat.mult_tir(actif, e) < 1.0 else "tir"
		else:
			for e in combat.ennemis_de(actif):
				if combat.case_attaque(actif, e, reach) != null:
					cibles[e["id"]] = "cac"
	var cases_cible := []
	if cible != null and actif != null:
		cases_cible = combat.cases_attaque(actif, cible, reach)

	# Grille et cases accessibles
	for l in Combat.LIGNES:
		for c in Combat.COLONNES:
			var case := Vector2i(c, l)
			var fond := Color(0.16, 0.16, 0.15) if (l + c) % 2 == 0 else Color(0.19, 0.19, 0.18)
			var type: String = combat.terrain.get(case, "")
			if TERRAINS.has(type):
				fond = fond.lerp(TERRAINS[type][0], TERRAINS[type][1])
			if reach.has(case):
				fond = fond.lerp(COULEURS[actif["camp"]], 0.35)
			if not a_deployer.is_empty() and combat.dans_zone(a_deployer[0], case):
				fond = fond.lerp(COULEURS[a_deployer[0]], 0.3)
			if cases_cible.has(case):
				fond = Color(0.75, 0.6, 0.15) if Combat.a_revers(cible, case) else Color(0.25, 0.55, 0.3)
			draw_rect(Rect2(_case_vers_ecran(case), Vector2.ONE * TAILLE_CASE), fond)
			_dessiner_terrain(case, type)
			var z = combat.zone_en(case)
			if z != null:
				var r := Rect2(_case_vers_ecran(case), Vector2.ONE * TAILLE_CASE).grow(-3)
				var tenue: String = z["tenue_par"]
				var col: Color = COULEURS[tenue].lightened(0.3) if tenue != "" else Color(0.95, 0.8, 0.3)
				draw_rect(r, col, false, 3.0)
				# petit drapeau dans le coin
				var b := r.position + Vector2(6, 6)
				draw_line(b, b + Vector2(0, 16), col, 2.0)
				draw_colored_polygon(PackedVector2Array([b, b + Vector2(11, 4), b + Vector2(0, 8)]), col)
			if cases_cible.has(case) and Combat.a_revers(cible, case):
				draw_string(police, _case_vers_ecran(case) + Vector2(0, 36), "dos", HORIZONTAL_ALIGNMENT_CENTER,
						TAILLE_CASE, 14, Color(0.1, 0.08, 0.02))
	draw_rect(Rect2(ORIGINE, Vector2(Combat.COLONNES, Combat.LIGNES) * TAILLE_CASE),
			Color(0.4, 0.4, 0.38), false, 2.0)

	# Piles
	for p in combat.piles:
		if not Combat.vivante(p):
			continue
		var coin := _case_vers_ecran(p["pos"]) + Vector2(5, 5)
		var taille := Vector2.ONE * (TAILLE_CASE - 10)
		draw_rect(Rect2(coin, taille), COULEURS[p["camp"]])
		# orientation : petit triangle sur le bord vers lequel la pile regarde
		var centre := coin + taille / 2
		var o := Vector2(p["orient"]).normalized()
		var pointe := centre + o * (taille.x / 2 + 4)
		var base := centre + o * (taille.x / 2 - 6)
		var perp := Vector2(-o.y, o.x) * 6
		draw_colored_polygon(PackedVector2Array([pointe, base + perp, base - perp]), Color(0.95, 0.95, 0.85))
		if actif != null and p["id"] == actif["id"]:
			draw_rect(Rect2(coin - Vector2(4, 4), taille + Vector2(8, 8)), Color(1, 0.85, 0.3), false, 4.0)
		elif selection != null and p["id"] == selection["id"]:
			draw_rect(Rect2(coin - Vector2(3, 3), taille + Vector2(6, 6)), Color(0.9, 0.9, 0.9), false, 2.0)
		if cible != null and p["id"] == cible["id"]:
			draw_rect(Rect2(coin - Vector2(4, 4), taille + Vector2(8, 8)), Color(1, 1, 1), false, 4.0)
		elif cibles.has(p["id"]):
			var col := Color(0.95, 0.25, 0.2) if cibles[p["id"]] != "loin" else Color(0.95, 0.6, 0.2)
			draw_rect(Rect2(coin - Vector2(3, 3), taille + Vector2(6, 6)), col, false, 3.0)
		draw_string(police, coin + Vector2(0, 16), _abreviation(p["u"]["nom"]),
				HORIZONTAL_ALIGNMENT_CENTER, taille.x, 13, Color.WHITE)
		if Combat.seigneur(p):
			draw_rect(Rect2(coin + Vector2(2, 2), taille - Vector2(4, 4)), Color(0.95, 0.8, 0.3), false, 2.0)
		draw_string(police, coin + Vector2(0, 34), str(p["pv_total"]) if Combat.seigneur(p) else str(Combat.nombre(p)),
				HORIZONTAL_ALIGNMENT_CENTER, taille.x, 16, Color(1, 1, 0.8))
		var marques := ""
		if p["defend"]:
			marques += "DÉF "
		if Combat.tireur(p):
			marques += "♦%d" % p["munitions"]
		if marques != "":
			draw_string(police, coin + Vector2(0, 47), marques, HORIZONTAL_ALIGNMENT_CENTER,
					taille.x, 10, Color(0.85, 0.85, 0.85))

	_dessiner_panneau_gauche()
	_dessiner_panneau_droit()
	if combat.vainqueur != "":
		_dessiner_fin()


func _bouton(r: Rect2, texte: String, actif: bool) -> void:
	draw_rect(r, Color(0.28, 0.27, 0.24) if actif else Color(0.17, 0.17, 0.16))
	draw_rect(r, Color(0.5, 0.48, 0.42) if actif else Color(0.25, 0.25, 0.24), false, 2.0)
	draw_string(police, r.position + Vector2(0, r.size.y / 2 + 7), texte, HORIZONTAL_ALIGNMENT_CENTER,
			r.size.x, 20, Color.WHITE if actif else Color(0.45, 0.45, 0.42))


func _dessiner_panneau_gauche() -> void:
	var x := 8.0
	var w := LARGEUR_PANNEAU - 4
	var actif = combat.actif
	if not a_deployer.is_empty():
		var camp: String = a_deployer[0]
		draw_string(police, Vector2(x, 30), NOMS_CAMPS[camp] + " : placement",
				HORIZONTAL_ALIGNMENT_LEFT, w, 14, COULEURS[camp].lightened(0.4))
		if selection != null:
			_dessiner_stats(selection, x, w)
		draw_multiline_string(police, Vector2(x, 400),
				"Touche une de tes piles, puis une case de ta zone (teintée) pour l'y placer. Sur une autre de tes piles, elles échangent leur place.",
				HORIZONTAL_ALIGNMENT_LEFT, w, 13, -1, Color(0.6, 0.6, 0.55))
		var dernier := a_deployer.size() == 1
		_bouton(BOUTON_LANCER, "Lancer le combat" if dernier else "Valider", true)
		return
	if actif != null:
		var qui: String = NOMS_CAMPS[actif["camp"]] + (" (IA)" if actif["camp"] == camp_ia else "")
		draw_string(police, Vector2(x, 30), "Au tour : " + qui,
				HORIZONTAL_ALIGNMENT_LEFT, w, 16, COULEURS[actif["camp"]].lightened(0.4))
	var p = selection if selection != null else actif
	if p != null:
		_dessiner_stats(p, x, w)
	if message != "":
		draw_multiline_string(police, Vector2(x, 330), message, HORIZONTAL_ALIGNMENT_LEFT, w, 14, -1,
				Color(1, 0.6, 0.4))
	if actif != null and not _tour_ia():
		var aide := "Touche une case pour bouger.\nTouche un ennemi encadré pour le viser, puis la case d'où frapper (dorée = de dos), ou l'ennemi à nouveau pour frapper au plus court."
		if combat.peut_tirer(actif):
			aide = "Touche une case pour bouger.\nTouche un ennemi encadré pour tirer (orange = tir affaibli : hors de portée ou zone sombre). Les murs bloquent la vue."
		draw_multiline_string(police, Vector2(x, 430), aide, HORIZONTAL_ALIGNMENT_LEFT, w, 13, -1,
				Color(0.6, 0.6, 0.55))
		_bouton(BOUTON_DEFENDRE, "Défendre", true)
		_bouton(BOUTON_ATTENDRE, "Attendre", combat.peut_attendre())


func _dessiner_panneau_droit() -> void:
	var x := PANNEAU_DROIT
	var w := 1280.0 - PANNEAU_DROIT - 6
	draw_string(police, Vector2(x, 30), "Round %d / %d" % [combat.round_num, Combat.ROUNDS_MAX] if combat.round_num > 0 else "Déploiement", HORIZONTAL_ALIGNMENT_LEFT, w, 17,
			Color(0.85, 0.85, 0.8))
	var pts: Dictionary = combat.points_victoire
	draw_string(police, Vector2(x, 50), "Points de victoire : HR %d · G %d" % [pts.get("HR", 0), pts.get("G", 0)],
			HORIZONTAL_ALIGNMENT_LEFT, w, 12, Color(0.95, 0.8, 0.3))
	# Ordre à venir
	var ordre := []
	if combat.actif != null:
		ordre.append(combat.actif)
	ordre += combat.file + combat.attente + combat.bonus
	var y := 74.0
	for i in mini(ordre.size(), 8):
		var p: Dictionary = ordre[i]
		draw_rect(Rect2(x, y - 12, 8, 13), COULEURS[p["camp"]])
		draw_string(police, Vector2(x + 13, y), "%s (%d)" % [p["u"]["nom"], p["init"]],
				HORIZONTAL_ALIGNMENT_LEFT, w - 13, 12, Color.WHITE if i == 0 else Color(0.7, 0.7, 0.65))
		y += 19
	# Journal (plus récent en haut)
	y = 230.0
	draw_string(police, Vector2(x, y), "Journal", HORIZONTAL_ALIGNMENT_LEFT, w, 14, Color(0.85, 0.85, 0.8))
	y += 8
	var journal: Array = combat.journal
	for i in range(journal.size() - 1, -1, -1):
		var h := police.get_multiline_string_size(journal[i], HORIZONTAL_ALIGNMENT_LEFT, w, 12).y
		if y + h > 714:
			break
		draw_multiline_string(police, Vector2(x, y + 13), journal[i], HORIZONTAL_ALIGNMENT_LEFT, w, 12, -1,
				Color(0.8, 0.8, 0.75))
		y += h + 4


func _dessiner_fin() -> void:
	var cadre := Rect2(ORIGINE + Vector2(120, 110), Vector2(600, 340))
	draw_rect(cadre, Color(0, 0, 0, 0.85))
	var v: String = combat.vainqueur
	var titre: String = "Égalité" if v == "nul" else "Victoire : " + NOMS_CAMPS[v]
	var couleur: Color = Color(0.85, 0.85, 0.8) if v == "nul" else COULEURS[v].lightened(0.4)
	draw_string(police, cadre.position + Vector2(0, 52), titre, HORIZONTAL_ALIGNMENT_CENTER, cadre.size.x, 32, couleur)
	var y := cadre.position.y + 100
	for camp in ["HR", "G"]:
		var d: Dictionary = combat.detail_points.get(camp, {})
		var texte := "%s : %d points  (zones %d · seigneur %d · annihilation %d)" % [
			NOMS_CAMPS[camp], combat.points_victoire.get(camp, 0),
			d.get("zones", 0), d.get("seigneur", 0), d.get("annihilation", 0)]
		draw_string(police, Vector2(cadre.position.x, y), texte, HORIZONTAL_ALIGNMENT_CENTER, cadre.size.x, 17,
				COULEURS[camp].lightened(0.45))
		y += 30
	_bouton(BOUTON_REJOUER, "Rejouer", true)
	_bouton(BOUTON_MENU, "Menu", true)


# --- Entrées -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var pos: Vector2 = event.position
	message = ""
	if combat.vainqueur != "":
		if BOUTON_REJOUER.has_point(pos):
			nouvelle_bataille()
		elif BOUTON_MENU.has_point(pos):
			get_tree().change_scene_to_file("res://scenes/menu.tscn")
		return
	if not a_deployer.is_empty():
		_toucher_deploiement(pos)
		queue_redraw()
		return
	if _tour_ia():
		return
	if BOUTON_DEFENDRE.has_point(pos):
		selection = null
		cible = null
		combat.defendre()
	elif BOUTON_ATTENDRE.has_point(pos):
		if combat.peut_attendre():
			selection = null
			cible = null
			combat.attendre()
	else:
		_toucher_case(_ecran_vers_case(pos))
	queue_redraw()


func _toucher_case(c: Vector2i) -> void:
	var actif = combat.actif
	if actif == null or not Combat.dans_grille(c):
		return
	var p = combat.pile_en(c)
	# Une cible est visée : toucher une de ses cases d'attaque frappe depuis cette case.
	if cible != null:
		var reach := combat.accessibles(actif)
		if combat.cases_attaque(actif, cible, reach).has(c):
			var visee = cible
			cible = null
			selection = null
			combat.attaquer(visee, c)
			return
		if p != null and p["id"] == cible["id"]:
			cible = null
			selection = null
			combat.attaquer(p)   # deuxième toucher : frappe depuis la case par défaut
			return
		cible = null
	if p == null:
		if combat.deplacer(c):
			selection = null
		else:
			var type: String = combat.terrain.get(c, "")
			if combat.zone_en(c) != null:
				type = "zone"
			message = TERRAINS[type][2] if TERRAINS.has(type) else "Case hors d'atteinte."
	elif p["camp"] != actif["camp"]:
		if combat.peut_tirer(actif):
			if combat.attaquer(p):
				selection = null
			else:
				selection = p
				message = "Pas de ligne de vue : un mur bloque le tir."
		elif combat.case_attaque(actif, p, combat.accessibles(actif)) != null:
			cible = p
			selection = p
		else:
			selection = p
			message = "Cible hors d'atteinte ce tour-ci."
	else:
		selection = null if p["id"] == actif["id"] else p


func _dessiner_stats(p: Dictionary, x: float, w: float) -> void:
	var u: Dictionary = p["u"]
	var lignes := [
		u["nom"],
		"%s · Tier %d" % [NOMS_CAMPS[p["camp"]], u["tier"]],
		"Créatures %d / %d" % [Combat.nombre(p), u["escouade"]],
		"PV %d (dessus %d)" % [u["pv"], Combat.pv_dessus(p)],
		"Att %d · Déf %d" % [u["att"], u["def"]],
		"Dégâts %d-%d" % [u["deg"][0], u["deg"][1]],
		"Vitesse %d · Init %s" % [u["vitesse"], _init_visible(p)],
		"Moral %d · Chance %d" % [combat.moral(p), u["chance"]],
	]
	if Combat.tireur(p):
		lignes.append("Portée %d · Munitions %d" % [u["portee"], p["munitions"]])
	if not u.get("capacites", []).is_empty():
		lignes.append("Capacité : " + ", ".join(u["capacites"].map(func(c): return NOMS_CAPACITES.get(c, c))))
	if Combat.seigneur(p):
		lignes[1] = "%s · Seigneur" % NOMS_CAMPS[p["camp"]]
		lignes[2] = "PV %d / %d" % [p["pv_total"], u["pv"]]
		lignes[3] = "Aura de moral %d cases" % u["aura"]
		lignes.append("Intelligence %d · Mana %d" % [u["intelligence"], p["mana"]])
		lignes.append("Puissance magique %d (x%.1f)" % [u["puissance"], Combat.mult_magie(p)])
	elif combat.dans_aura(p):
		lignes.append("Aura du seigneur : +1 moral")
	for i in lignes.size():
		draw_string(police, Vector2(x, 64 + i * 25), lignes[i], HORIZONTAL_ALIGNMENT_LEFT, w,
				17 if i == 0 else 15, Color.WHITE if i == 0 else Color(0.85, 0.85, 0.8))


func _toucher_deploiement(pos: Vector2) -> void:
	var camp: String = a_deployer[0]
	if BOUTON_LANCER.has_point(pos):
		a_deployer.pop_front()
		selection = null
		if a_deployer.is_empty():
			combat.commencer()
		return
	var c := _ecran_vers_case(pos)
	if not Combat.dans_grille(c):
		return
	var p = combat.pile_en(c)
	if selection != null and selection["camp"] == camp and combat.dans_zone(camp, c) \
			and (p == null or p["camp"] == camp) and (p == null or p["id"] != selection["id"]):
		combat.replacer(selection, c)
		selection = null
	elif p != null:
		selection = p
	else:
		selection = null


## Initiative affichée : cachée pour l'adversaire pendant le déploiement.
func _init_visible(p: Dictionary) -> String:
	if not a_deployer.is_empty() and p["camp"] != a_deployer[0] and not voir_init_adverse:
		return "?"
	return str(p["init"])


func _dessiner_terrain(case: Vector2i, type: String) -> void:
	var r := Rect2(_case_vers_ecran(case), Vector2.ONE * TAILLE_CASE)
	match type:
		"mur":
			# briques
			for k in 3:
				var y := r.position.y + 6 + k * 18
				draw_line(Vector2(r.position.x + 4, y), Vector2(r.end.x - 4, y), Color(0.3, 0.29, 0.27), 2.0)
			draw_rect(r.grow(-2), Color(0.25, 0.24, 0.22), false, 2.0)
		"obstacle":
			draw_line(r.position + Vector2(14, 14), r.end - Vector2(14, 14), Color(0.55, 0.42, 0.25), 4.0)
			draw_line(Vector2(r.end.x - 14, r.position.y + 14), Vector2(r.position.x + 14, r.end.y - 14),
					Color(0.55, 0.42, 0.25), 4.0)
		"trou":
			draw_circle(r.get_center(), TAILLE_CASE * 0.38, Color(0, 0, 0))
			draw_arc(r.get_center(), TAILLE_CASE * 0.38, 0, TAU, 24, Color(0.35, 0.3, 0.25), 2.0)
		"eau":
			for k in 2:
				var y := r.position.y + 22 + k * 16
				draw_line(Vector2(r.position.x + 10, y), Vector2(r.end.x - 10, y), Color(0.45, 0.65, 0.85, 0.7), 2.0)
		"toxique":
			draw_circle(r.position + Vector2(18, 20), 4, Color(0.6, 0.85, 0.2, 0.8))
			draw_circle(r.position + Vector2(40, 38), 5, Color(0.6, 0.85, 0.2, 0.8))
