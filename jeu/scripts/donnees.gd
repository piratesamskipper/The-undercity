extends Node
## Données du jeu partagées entre les écrans (autoload « Donnees »).
## Les valeurs par défaut viennent de res://donnees/ ; les modifications faites
## dans les éditeurs sont enregistrées sur le téléphone (user://) et les remplacent.

const FICHIER_UNITES := "user://unites.json"
const FICHIER_CARTES := "user://cartes.json"
const FICHIER_ARMEES := "user://armees.json"
const FICHIER_PARTIE := "user://partie.json"
const SECONDES_PAR_HEURE := 60.0   # prototype : 1 heure de jeu = 1 minute réelle
const GAIN_VICTOIRE := 1000
const GAIN_DEFAITE := 300
const OR_DEPART := 2000

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

# Réglages de la prochaine bataille (choisis dans le menu ou la base)
var camp_ia := "G"
var carte_choisie := ""    # "" = carte aléatoire
var mode_campagne := false # bataille lancée depuis la base : les pertes et gains comptent
var armee_adverse: Array = []
var dernier_resultat := ""  # message affiché en revenant à la base

# Partie (base des Hommes-rats)
var batiments: Array = []  # définitions (res://donnees/batiments.json)
var partie := {}           # {or, temps, batiments: {id: niveau}, armee: [{nom, nombre}]}


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
	batiments = JSON.parse_string(FileAccess.get_file_as_string("res://donnees/batiments.json"))
	var pa = _lire(FICHIER_PARTIE, {})
	partie = pa if pa is Dictionary and pa.has("or") else nouvelle_partie()


var _textures := {}


## Image d'une unité (chemin relatif à res://images/), mise en cache ; null si aucune.
func texture(chemin: String) -> Texture2D:
	if chemin == "":
		return null
	if not _textures.has(chemin):
		var complet := "res://images/" + chemin
		_textures[chemin] = load(complet) if ResourceLoader.exists(complet) else null
	return _textures[chemin]


## Toutes les images disponibles pour les unités (chemins relatifs à res://images/).
func images_disponibles() -> Array:
	var res := []
	var dossiers := DirAccess.get_directories_at("res://images")
	for d in dossiers:
		for f in DirAccess.get_files_at("res://images/" + d):
			f = f.trim_suffix(".import").trim_suffix(".remap")
			if f.ends_with(".png") and not res.has(d + "/" + f):
				res.append(d + "/" + f)
	res.sort()
	return res


func unites_defaut() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://donnees/unites.json"))


func unites_par_nom() -> Dictionary:
	var d := {}
	for u in unites:
		d[u["nom"]] = u
	return d


func unite(nom: String) -> Variant:
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



# --- Partie : base, or, recrutement ------------------------------------------

func nouvelle_partie() -> Dictionary:
	var armee := []
	for p in ARMEES_DEFAUT["HR"]:
		var u = unite(p["nom"])
		if u != null and not u.get("seigneur", false):
			armee.append(p.duplicate())
	partie = {"or": float(OR_DEPART), "temps": Time.get_unix_time_from_system(),
		"batiments": {"mine": 1, "couveuse": 1, "matrones": 0, "pere": 0}, "armee": armee}
	sauver_partie()
	return partie


func sauver_partie() -> void:
	_ecrire(FICHIER_PARTIE, partie)


func niveau(id: String) -> int:
	return int(partie["batiments"].get(id, 0))


func batiment(id: String) -> Dictionary:
	for b in batiments:
		if b["id"] == id:
			return b
	return {}


## Or produit par heure de jeu (toutes les mines).
func production_horaire() -> float:
	var total := 0.0
	for b in batiments:
		if b.has("production"):
			total += float(b["production"]) * niveau(b["id"])
	return total


## Ajoute l'or produit depuis la dernière mise à jour (temps réel accéléré).
func maj_or() -> void:
	var maintenant := Time.get_unix_time_from_system()
	var ecoule := maxf(0.0, maintenant - float(partie["temps"]))
	partie["or"] = float(partie["or"]) + production_horaire() * ecoule / SECONDES_PAR_HEURE
	partie["temps"] = maintenant
	sauver_partie()


## Coût pour passer le bâtiment au niveau suivant (0 si déjà au maximum).
func cout_amelioration(id: String) -> int:
	var b := batiment(id)
	var n := niveau(id) + 1
	if n > int(b.get("max", 1)):
		return 0
	if b.has("cout_base"):
		return int(b["cout_base"]) + int(b["cout_par_niveau"]) * (n - 1)
	return int(b["cout_mult"]) * n


func ameliorer(id: String) -> bool:
	var c := cout_amelioration(id)
	if c <= 0 or partie["or"] < c:
		return false
	partie["or"] -= c
	partie["batiments"][id] = niveau(id) + 1
	sauver_partie()
	return true


## Vrai si un bâtiment construit permet de recruter ce tier.
func tier_recrutable(tier: int) -> bool:
	for b in batiments:
		if int(b.get("debloque_tier", -1)) == tier and niveau(b["id"]) >= 1:
			return true
	return false


## Recrute jusqu'à `n` créatures dans la pile `i` (limité par l'or et la capacité). Renvoie le nombre recruté.
func recruter(i: int, n: int) -> int:
	var p: Dictionary = partie["armee"][i]
	var u = unite(p["nom"])
	if u == null or not tier_recrutable(int(u["tier"])):
		return 0
	var prix := maxi(1, int(u.get("cout", 0)))
	n = mini(n, int(u["escouade"]) - int(p["nombre"]))
	n = mini(n, int(floor(partie["or"] / prix)))
	if n <= 0:
		return 0
	p["nombre"] = int(p["nombre"]) + n
	partie["or"] -= n * prix
	sauver_partie()
	return n


## Ajoute une nouvelle pile (une créature, payée) si l'armée a de la place.
func nouvelle_pile(nom: String) -> bool:
	var u = unite(nom)
	if u == null or partie["armee"].size() >= MAX_PILES or not tier_recrutable(int(u["tier"])):
		return false
	if partie["or"] < int(u.get("cout", 0)):
		return false
	partie["or"] -= int(u.get("cout", 0))
	partie["armee"].append({"nom": nom, "nombre": 1})
	sauver_partie()
	return true


## Valeur en or d'une armée (troupes seulement).
func valeur_armee(armee: Array) -> int:
	var t := 0
	for p in armee:
		var u = unite(p["nom"])
		if u != null and not u.get("seigneur", false):
			t += int(u.get("cout", 0)) * int(p["nombre"])
	return t


func seigneur_de(camp: String) -> String:
	for u in unites:
		if u["faction"] == camp and u.get("seigneur", false):
			return u["nom"]
	return ""


## Armée de l'IA d'environ `budget` or : 6 à 8 piles tirées au hasard, plus son seigneur.
func armee_ia(camp: String, budget: int) -> Array:
	var troupes := unites.filter(func(u): return u["faction"] == camp and not u.get("seigneur", false))
	var noms := []
	for i in randi_range(6, MAX_PILES):
		noms.append(troupes[randi() % troupes.size()]["nom"])
	var plein := 0
	for n in noms:
		plein += int(unite(n).get("cout", 1)) * int(unite(n)["escouade"])
	var f := float(budget) / maxf(1.0, plein)
	var res := []
	for n in noms:
		var u = unite(n)
		res.append({"nom": n, "nombre": clampi(roundi(u["escouade"] * f), 1, int(u["escouade"]))})
	var s := seigneur_de(camp)
	if s != "":
		res.append({"nom": s, "nombre": 1})
	return res


## Prépare une bataille depuis la base.
func preparer_bataille_campagne() -> void:
	maj_or()
	mode_campagne = true
	camp_ia = "G"
	var budget := int(valeur_armee(partie["armee"]) * randf_range(0.9, 1.1))
	armee_adverse = armee_ia("G", maxi(budget, 1500))


## Armée du joueur pour la bataille (troupes de la partie + seigneur).
func armee_joueur() -> Array:
	var a: Array = partie["armee"].duplicate(true)
	var s := seigneur_de("HR")
	if s != "":
		a.append({"nom": s, "nombre": 1})
	return a


## Applique le résultat d'une bataille de campagne : pertes et or gagné.
func fin_bataille_campagne(combat: Combat) -> void:
	var survivants := {}
	for p in combat.piles:
		if p["camp"] == "HR" and not Combat.seigneur(p):
			survivants[int(p["origine"])] = Combat.nombre(p)
	var armee := []
	var pertes := 0
	for i in partie["armee"].size():
		var p: Dictionary = partie["armee"][i]
		var n: int = survivants.get(i, int(p["nombre"]))
		pertes += int(p["nombre"]) - n
		if n > 0:
			armee.append({"nom": p["nom"], "nombre": n})
	partie["armee"] = armee
	var gain := GAIN_VICTOIRE if combat.vainqueur == "HR" else GAIN_DEFAITE
	maj_or()
	partie["or"] += gain
	sauver_partie()
	var issue := "Victoire" if combat.vainqueur == "HR" else ("Égalité" if combat.vainqueur == "nul" else "Défaite")
	dernier_resultat = "%s : +%d or, %d créatures perdues." % [issue, gain, pertes]
	mode_campagne = false
