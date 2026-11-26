extends Node2D
## Écran de bataille : affiche un Combat et transmet les touchers du joueur.
## Pour l'instant les deux camps sont joués à la main (chacun son tour).

const TAILLE_CASE := 80.0
const ORIGINE := Vector2(240, 40)
const PANNEAU_DROIT := 1052.0

const COULEURS := {"HR": Color(0.55, 0.32, 0.2), "G": Color(0.22, 0.38, 0.62)}
const NOMS_CAMPS := {"HR": "Hommes-rats", "G": "Garde"}

# Compositions de test (identiques à la simulation équilibrée).
const ARMEE_HR := [["Esclave du père des rats", 2], ["Frondeur des égouts", 2],
		["Surineurs", 3], ["Rats mutés", 1]]
const ARMEE_G := [["Bleusaille", 1], ["Arbalétriers", 2], ["Soldats du cru", 3], ["Vétérans", 2]]

const BOUTON_DEFENDRE := Rect2(12, 560, 210, 56)
const BOUTON_ATTENDRE := Rect2(12, 628, 210, 56)
const BOUTON_REJOUER := Rect2(540, 400, 200, 60)

var unites := {}
var combat: Combat
var selection = null      # pile dont on affiche les stats (sinon l'actif)
var message := ""         # retour au joueur (action impossible, etc.)
var police: Font


func _ready() -> void:
	police = ThemeDB.fallback_font
	var texte := FileAccess.get_file_as_string("res://donnees/unites.json")
	for u in JSON.parse_string(texte):
		unites[u["nom"]] = u
	nouvelle_bataille()


func nouvelle_bataille() -> void:
	combat = Combat.new(unites, ARMEE_HR, ARMEE_G)
	selection = null
	message = ""
	queue_redraw()


# --- Conversions -------------------------------------------------------------

func _case_vers_ecran(c: Vector2i) -> Vector2:
	return ORIGINE + Vector2(c.x, c.y) * TAILLE_CASE


func _ecran_vers_case(p: Vector2) -> Vector2i:
	var r := (p - ORIGINE) / TAILLE_CASE
	return Vector2i(floori(r.x), floori(r.y))


func _abreviation(nom: String) -> String:
	var mots := nom.split(" ")
	return (mots[0].substr(0, 3) + (mots[-1].substr(0, 1) if mots.size() > 1 else "")).to_upper()


# --- Dessin ------------------------------------------------------------------

func _draw() -> void:
	var actif = combat.actif
	var reach := {}
	var cibles := {}     # id de pile -> "cac" | "tir" | "loin"
	if actif != null:
		reach = combat.accessibles(actif)
		var tir := combat.peut_tirer(actif)
		for e in combat.ennemis_de(actif):
			if tir:
				var loin: bool = Combat.distance_tir(actif["pos"], e["pos"]) > actif["u"]["portee"]
				cibles[e["id"]] = "loin" if loin else "tir"
			elif combat.case_attaque(actif, e, reach) != null:
				cibles[e["id"]] = "cac"

	# Grille et cases accessibles
	for l in Combat.LIGNES:
		for c in Combat.COLONNES:
			var case := Vector2i(c, l)
			var fond := Color(0.16, 0.16, 0.15) if (l + c) % 2 == 0 else Color(0.19, 0.19, 0.18)
			if reach.has(case):
				fond = fond.lerp(COULEURS[actif["camp"]], 0.35)
			draw_rect(Rect2(_case_vers_ecran(case), Vector2.ONE * TAILLE_CASE), fond)
	draw_rect(Rect2(ORIGINE, Vector2(Combat.COLONNES, Combat.LIGNES) * TAILLE_CASE),
			Color(0.4, 0.4, 0.38), false, 2.0)

	# Piles
	for p in combat.piles:
		if not Combat.vivante(p):
			continue
		var coin := _case_vers_ecran(p["pos"]) + Vector2(6, 6)
		var taille := Vector2.ONE * (TAILLE_CASE - 12)
		draw_rect(Rect2(coin, taille), COULEURS[p["camp"]])
		if actif != null and p["id"] == actif["id"]:
			draw_rect(Rect2(coin - Vector2(4, 4), taille + Vector2(8, 8)), Color(1, 0.85, 0.3), false, 4.0)
		elif selection != null and p["id"] == selection["id"]:
			draw_rect(Rect2(coin - Vector2(3, 3), taille + Vector2(6, 6)), Color(0.9, 0.9, 0.9), false, 2.0)
		if cibles.has(p["id"]):
			var col := Color(0.95, 0.25, 0.2) if cibles[p["id"]] != "loin" else Color(0.95, 0.6, 0.2)
			draw_rect(Rect2(coin - Vector2(3, 3), taille + Vector2(6, 6)), col, false, 3.0)
		draw_string(police, coin + Vector2(0, 24), _abreviation(p["u"]["nom"]),
				HORIZONTAL_ALIGNMENT_CENTER, taille.x, 17, Color.WHITE)
		draw_string(police, coin + Vector2(0, 47), str(Combat.nombre(p)),
				HORIZONTAL_ALIGNMENT_CENTER, taille.x, 20, Color(1, 1, 0.8))
		var marques := ""
		if p["defend"]:
			marques += "DÉF "
		if Combat.tireur(p):
			marques += "♦%d" % p["munitions"]
		if marques != "":
			draw_string(police, coin + Vector2(0, 64), marques, HORIZONTAL_ALIGNMENT_CENTER,
					taille.x, 12, Color(0.85, 0.85, 0.85))

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
	var x := 12.0
	var actif = combat.actif
	if actif != null:
		draw_string(police, Vector2(x, 30), "Au tour : " + NOMS_CAMPS[actif["camp"]],
				HORIZONTAL_ALIGNMENT_LEFT, 220, 17, COULEURS[actif["camp"]].lightened(0.4))
	var p = selection if selection != null else actif
	if p != null:
		var u: Dictionary = p["u"]
		var lignes := [
			u["nom"],
			"%s · Tier %d" % [NOMS_CAMPS[p["camp"]], u["tier"]],
			"Créatures %d / %d" % [Combat.nombre(p), u["escouade"]],
			"PV %d (dessus %d)" % [u["pv"], Combat.pv_dessus(p)],
			"Att %d · Déf %d" % [u["att"], u["def"]],
			"Dégâts %d-%d" % [u["deg"][0], u["deg"][1]],
			"Vitesse %d · Init %d" % [u["vitesse"], p["init"]],
			"Moral %d · Chance %d" % [combat.moral(p), u["chance"]],
		]
		if Combat.tireur(p):
			lignes.append("Portée %d · Munitions %d" % [u["portee"], p["munitions"]])
		for i in lignes.size():
			draw_string(police, Vector2(x, 66 + i * 27), lignes[i], HORIZONTAL_ALIGNMENT_LEFT, 220,
					19 if i == 0 else 16, Color.WHITE if i == 0 else Color(0.85, 0.85, 0.8))
	if message != "":
		draw_multiline_string(police, Vector2(x, 350), message, HORIZONTAL_ALIGNMENT_LEFT, 215, 15, -1,
				Color(1, 0.6, 0.4))
	if actif != null:
		draw_string(police, Vector2(x, 450), "Touche une case : bouger.", HORIZONTAL_ALIGNMENT_LEFT,
				220, 14, Color(0.6, 0.6, 0.55))
		draw_string(police, Vector2(x, 470), "Ennemi encadré : attaquer.", HORIZONTAL_ALIGNMENT_LEFT,
				220, 14, Color(0.6, 0.6, 0.55))
		_bouton(BOUTON_DEFENDRE, "Défendre", true)
		_bouton(BOUTON_ATTENDRE, "Attendre", combat.peut_attendre())


func _dessiner_panneau_droit() -> void:
	var x := PANNEAU_DROIT
	draw_string(police, Vector2(x, 30), "Round %d" % combat.round_num, HORIZONTAL_ALIGNMENT_LEFT, 220, 18,
			Color(0.85, 0.85, 0.8))
	# Ordre à venir
	var ordre := []
	if combat.actif != null:
		ordre.append(combat.actif)
	ordre += combat.file + combat.attente + combat.bonus
	var y := 56.0
	for i in mini(ordre.size(), 8):
		var p: Dictionary = ordre[i]
		draw_rect(Rect2(x, y - 13, 10, 14), COULEURS[p["camp"]])
		draw_string(police, Vector2(x + 16, y), "%s (%d)" % [p["u"]["nom"], p["init"]],
				HORIZONTAL_ALIGNMENT_LEFT, 210, 13, Color.WHITE if i == 0 else Color(0.7, 0.7, 0.65))
		y += 20
	# Journal (plus récent en haut)
	y = 240.0
	draw_string(police, Vector2(x, y), "Journal", HORIZONTAL_ALIGNMENT_LEFT, 220, 15, Color(0.85, 0.85, 0.8))
	y += 8
	var journal: Array = combat.journal
	for i in range(journal.size() - 1, -1, -1):
		var h := police.get_multiline_string_size(journal[i], HORIZONTAL_ALIGNMENT_LEFT, 220, 13).y
		if y + h > 712:
			break
		draw_multiline_string(police, Vector2(x, y + 14), journal[i], HORIZONTAL_ALIGNMENT_LEFT, 220, 13, -1,
				Color(0.8, 0.8, 0.75))
		y += h + 4


func _dessiner_fin() -> void:
	draw_rect(Rect2(ORIGINE + Vector2(100, 200), Vector2(600, 260)), Color(0, 0, 0, 0.8))
	draw_string(police, ORIGINE + Vector2(100, 300), "Victoire : " + NOMS_CAMPS[combat.vainqueur],
			HORIZONTAL_ALIGNMENT_CENTER, 600, 32, COULEURS[combat.vainqueur].lightened(0.4))
	_bouton(BOUTON_REJOUER, "Rejouer", true)


# --- Entrées -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var pos: Vector2 = event.position
	message = ""
	if combat.vainqueur != "":
		if BOUTON_REJOUER.has_point(pos):
			nouvelle_bataille()
		return
	if BOUTON_DEFENDRE.has_point(pos):
		selection = null
		combat.defendre()
	elif BOUTON_ATTENDRE.has_point(pos):
		if combat.peut_attendre():
			selection = null
			combat.attendre()
	else:
		_toucher_case(_ecran_vers_case(pos))
	queue_redraw()


func _toucher_case(c: Vector2i) -> void:
	var actif = combat.actif
	if actif == null or not Combat.dans_grille(c):
		return
	var p = combat.pile_en(c)
	if p == null:
		if combat.deplacer(c):
			selection = null
		else:
			message = "Case hors d'atteinte."
	elif p["camp"] != actif["camp"]:
		if combat.attaquer(p):
			selection = null
		else:
			selection = p
			message = "Cible hors d'atteinte ce tour-ci."
	else:
		selection = null if p["id"] == actif["id"] else p
