extends Control
## Menu principal : choix du camp, de la carte, et accès aux éditeurs (versions de test).

var choix_carte: OptionButton


func _ready() -> void:
	theme = Donnees.theme_tactile()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var fond := ColorRect.new()
	fond.color = Color(0.07, 0.07, 0.08)
	fond.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fond)

	var boite := VBoxContainer.new()
	boite.set_anchors_preset(Control.PRESET_CENTER)
	boite.custom_minimum_size = Vector2(420, 0)
	boite.position = Vector2(-210, -290)
	boite.add_theme_constant_override("separation", 14)
	add_child(boite)

	var titre := Label.new()
	titre.text = "The Undercity"
	titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titre.add_theme_font_size_override("font_size", 44)
	titre.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	boite.add_child(titre)
	var sous := Label.new()
	sous.text = "Prototype du combat en grille"
	sous.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sous.add_theme_color_override("font_color", Color(0.65, 0.65, 0.6))
	boite.add_child(sous)

	_bouton(boite, "Jouer les Hommes-rats", func(): _lancer("G"))
	_bouton(boite, "Jouer la Garde", func(): _lancer("HR"))
	_bouton(boite, "Deux joueurs", func(): _lancer(""))

	var ligne := HBoxContainer.new()
	var l := Label.new()
	l.text = "Carte :"
	ligne.add_child(l)
	choix_carte = OptionButton.new()
	choix_carte.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choix_carte.custom_minimum_size.y = 52
	choix_carte.add_item("Aléatoire")
	var noms := Donnees.cartes.keys()
	noms.sort()
	for nom in noms:
		choix_carte.add_item(nom)
	for i in choix_carte.item_count:
		if choix_carte.get_item_text(i) == Donnees.carte_choisie:
			choix_carte.select(i)
	ligne.add_child(choix_carte)
	boite.add_child(ligne)

	if Donnees.editeurs_disponibles():
		var b := _bouton(boite, "Éditeurs", func(): get_tree().change_scene_to_file("res://scenes/editeurs.tscn"))
		b.add_theme_color_override("font_color", Color(0.95, 0.8, 0.3))


func _bouton(parent: Control, texte: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = texte
	b.custom_minimum_size = Vector2(0, 64)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _lancer(camp_ia: String) -> void:
	Donnees.camp_ia = camp_ia
	Donnees.carte_choisie = "" if choix_carte.selected <= 0 else choix_carte.get_item_text(choix_carte.selected)
	get_tree().change_scene_to_file("res://scenes/bataille.tscn")
