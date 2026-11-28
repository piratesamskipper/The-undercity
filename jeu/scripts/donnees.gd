extends Node
## Données du jeu partagées entre les écrans (autoload « Donnees »).
## Les valeurs par défaut viennent de res://donnees/ ; les modifications faites
## dans les éditeurs sont enregistrées sur le téléphone (user://) et les remplacent.

const FICHIER_UNITES := "user://unites.json"
const FICHIER_CARTES := "user://cartes.json"
const FICHIER_ARMEES := "user://armees.json"

const ARMEES_DEFAUT := {
	"HR": [
		{"nom": "Esclave du père des rats", "nombre": 60}, {"nom": "Esclave du père des rats", "nombre": 60},
		{"nom": "Frondeur des égouts", "nombre": 60}, {"nom": "Frondeur des égouts", "nombre": 60},
		{"nom": "Surineurs", "nombre": 40}, {"nom": "Surineurs", "nombre": 40}, {"nom": "Surineurs", "nombre": 40},
		{"nom": "Rats mutés", "nombre": 20}, {"nom": "Seigneur des Hommes-rats", "nombre": 1},
	],
	"G": [
		{"nom": "Bleusaille", "nombre": 30}, {"nom": "Arbalétriers", "nombre": 20},
		{"nom": "Arbalétriers", "nombre": 20}, {"nom": "Soldats du cru", "nombre": 20},
		{"nom": "Soldats du cru", "nombre": 20}, {"nom": "Soldats du cru", "nombre": 20},
		{"nom": "Vétérans", "nombre": 15}, {"nom": "Vétérans", "nombre": 15},
		{"nom": "Seigneur de la Garde", "nombre": 1},
	],
}
const MAX_PILES := 8   # sans compter le seigneur

var unites: Array = []     # liste des unités (dictionnaires)
var cartes := {}           # nom -> {terrain: {"x,y": type}, zones: [[x, y], ...]}
var armees := {}           # camp -> [{nom, nombre}, ...]

# Réglages de la prochaine bataille (choisis dans le menu)
var camp_ia := "G"
var carte_choisie := ""    # "" = carte aléatoire


func _ready() -> void:
	charger()


## Les éditeurs ne sont disponibles que dans les versions de test (APK debug).
func editeurs_disponibles() -> bool:
	return OS.is_debug_build()


func charger() -> void:
	var u = _lire(FICHIER_UNITES, null)
	unites = u if u is Array and not u.is_empty() else unites_defaut()
	var c = _lire(FICHIER_CARTES, {})
	cartes = c if c is Dictionary else {}
	var a = _lire(FICHIER_ARMEES, {})
	armees = a if a is Dictionary else {}
	for camp in ARMEES_DEFAUT:
		if not armees.has(camp):
			armees[camp] = ARMEES_DEFAUT[camp].duplicate(true)


func unites_defaut() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://donnees/unites.json"))


func unites_par_nom() -> Dictionary:
	var d := {}
	for u in unites:
		d[u["nom"]] = u
	return d


func unite(nom: String):
	for u in unites:
		if u["nom"] == nom:
			return u
	return null


func sauver_unites() -> void:
	_ecrire(FICHIER_UNITES, unites)


func sauver_cartes() -> void:
	_ecrire(FICHIER_CARTES, cartes)


func sauver_armees() -> void:
	_ecrire(FICHIER_ARMEES, armees)


func reinitialiser_unites() -> void:
	unites = unites_defaut()
	DirAccess.remove_absolute(FICHIER_UNITES)


func reinitialiser_armees() -> void:
	armees = ARMEES_DEFAUT.duplicate(true)
	DirAccess.remove_absolute(FICHIER_ARMEES)


## Texte JSON lisible, à copier dans le presse-papiers pour l'export.
func exporter(donnees) -> String:
	return JSON.stringify(donnees, "  ")


## Thème commun : textes et boutons assez grands pour le tactile.
func theme_tactile() -> Theme:
	var t := Theme.new()
	t.default_font_size = 20
	for type in ["Button", "OptionButton", "CheckBox", "CheckButton"]:
		t.set_constant("h_separation", type, 8)
	return t


func _lire(chemin: String, defaut):
	if not FileAccess.file_exists(chemin):
		return defaut
	var v = JSON.parse_string(FileAccess.get_file_as_string(chemin))
	return defaut if v == null else v


func _ecrire(chemin: String, donnees) -> void:
	var f := FileAccess.open(chemin, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(donnees, "  "))
