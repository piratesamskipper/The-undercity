extends Node2D
## Écran de bataille du prototype : grille 8x10 et deux armées déployées.
## Étape 1 : affichage seulement. Toucher une pile affiche ses stats.

const LIGNES := 8
const COLONNES := 10
const TAILLE_CASE := 80.0
const ORIGINE := Vector2(240, 40)

const COULEURS := {
	"HR": Color(0.55, 0.32, 0.2),
	"G": Color(0.22, 0.38, 0.62),
}

# Compositions de test (identiques à la simulation équilibrée).
const ARMEE_HR := [["Esclave du père des rats", 2], ["Frondeur des égouts", 2],
		["Surineurs", 3], ["Rats mutés", 1]]
const ARMEE_G := [["Bleusaille", 1], ["Arbalétriers", 2], ["Soldats du cru", 3], ["Vétérans", 2]]

var unites := {}        # nom -> données de l'unité
var piles: Array = []   # chaque pile : {u, camp, pos: Vector2i, nombre}
var selection = null
var police: Font


func _ready() -> void:
	police = ThemeDB.fallback_font
	_charger_unites()
	piles = _deployer(ARMEE_HR, "HR") + _deployer(ARMEE_G, "G")
	queue_redraw()


func _charger_unites() -> void:
	var texte := FileAccess.get_file_as_string("res://donnees/unites.json")
	for u in JSON.parse_string(texte):
		unites[u["nom"]] = u


func _deployer(compo: Array, camp: String) -> Array:
	var arriere := 0 if camp == "HR" else COLONNES - 1
	var avant := 1 if camp == "HR" else COLONNES - 2
	var tireurs := []
	var melee := []
	for entree in compo:
		var u: Dictionary = unites[entree[0]]
		for i in entree[1]:
			(tireurs if u["portee"] > 0 else melee).append(u)
	# Mêlée en première ligne, tireurs (et surplus de mêlée) derrière, chaque colonne centrée.
	var ligne_avant := melee.slice(0, LIGNES)
	var ligne_arriere := tireurs + melee.slice(LIGNES)
	var res := []
	for colonne in [[ligne_avant, avant], [ligne_arriere, arriere]]:
		var liste: Array = colonne[0]
		var debut := (LIGNES - liste.size()) / 2
		for i in liste.size():
			res.append(_pile(liste[i], camp, Vector2i(colonne[1], debut + i)))
	return res


func _pile(u: Dictionary, camp: String, pos: Vector2i) -> Dictionary:
	return {"u": u, "camp": camp, "pos": pos, "nombre": int(u["escouade"])}


func _case_vers_ecran(c: Vector2i) -> Vector2:
	return ORIGINE + Vector2(c.x, c.y) * TAILLE_CASE


func _ecran_vers_case(p: Vector2) -> Vector2i:
	var r := (p - ORIGINE) / TAILLE_CASE
	return Vector2i(floori(r.x), floori(r.y))


func _abreviation(nom: String) -> String:
	var mots := nom.split(" ")
	return (mots[0].substr(0, 3) + (mots[-1].substr(0, 1) if mots.size() > 1 else "")).to_upper()


func _draw() -> void:
	# Grille
	for l in LIGNES:
		for c in COLONNES:
			var fond := Color(0.16, 0.16, 0.15) if (l + c) % 2 == 0 else Color(0.19, 0.19, 0.18)
			draw_rect(Rect2(_case_vers_ecran(Vector2i(c, l)), Vector2.ONE * TAILLE_CASE), fond)
	draw_rect(Rect2(ORIGINE, Vector2(COLONNES, LIGNES) * TAILLE_CASE), Color(0.4, 0.4, 0.38), false, 2.0)
	# Piles
	for p in piles:
		var coin := _case_vers_ecran(p["pos"]) + Vector2(6, 6)
		var taille := Vector2.ONE * (TAILLE_CASE - 12)
		draw_rect(Rect2(coin, taille), COULEURS[p["camp"]])
		if p == selection:
			draw_rect(Rect2(coin - Vector2(3, 3), taille + Vector2(6, 6)), Color(1, 0.85, 0.3), false, 3.0)
		draw_string(police, coin + Vector2(0, 28), _abreviation(p["u"]["nom"]),
				HORIZONTAL_ALIGNMENT_CENTER, taille.x, 18, Color.WHITE)
		draw_string(police, coin + Vector2(0, 54), str(p["nombre"]),
				HORIZONTAL_ALIGNMENT_CENTER, taille.x, 20, Color(1, 1, 0.8))
	_dessiner_panneau()


func _dessiner_panneau() -> void:
	var x := 12.0
	var y := 60.0
	draw_string(police, Vector2(x, y - 24), "The Undercity — prototype", HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
			Color(0.8, 0.8, 0.75))
	if selection == null:
		draw_string(police, Vector2(x, y + 10), "Touche une pile", HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
				Color(0.6, 0.6, 0.55))
		return
	var u: Dictionary = selection["u"]
	var lignes := [
		u["nom"],
		"Faction %s · Tier %d" % [selection["camp"], u["tier"]],
		"Créatures %d / %d" % [selection["nombre"], u["escouade"]],
		"PV %d · Att %d · Déf %d" % [u["pv"], u["att"], u["def"]],
		"Dégâts %d-%d" % [u["deg"][0], u["deg"][1]],
		"Vitesse %d · Init %d" % [u["vitesse"], u["initiative"]],
		"Moral %d · Chance %d" % [u["moral"], u["chance"]],
	]
	if u["portee"] > 0:
		lignes.append("Portée %d · Munitions %d" % [u["portee"], u["munitions"]])
	for i in lignes.size():
		draw_string(police, Vector2(x, y + 10 + i * 28), lignes[i], HORIZONTAL_ALIGNMENT_LEFT, 220,
				20 if i == 0 else 17, Color.WHITE if i == 0 else Color(0.85, 0.85, 0.8))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var c := _ecran_vers_case(event.position)
		selection = null
		for p in piles:
			if p["pos"] == c:
				selection = p
		queue_redraw()
