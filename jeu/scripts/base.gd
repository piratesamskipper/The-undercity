extends Control
## Base des Hommes-rats (prototype) : or, bâtiments, recrutement, départ au combat.
## L'or s'accumule en temps réel accéléré (1 heure de jeu = 1 minute réelle).

var etiquette_or: Label
var etiquette_prod: Label
var etiquette_msg: Label
var col_batiments: VBoxContainer
var col_armee: VBoxContainer
var minuterie := 0.0


func _ready() -> void:
	theme = Donnees.theme_tactile()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var fond := ColorRect.new()
	fond.color = Color(0.09, 0.08, 0.07)
	fond.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fond)

	var racine := VBoxContainer.new()
	racine.set_anchors_preset(Control.PRESET_FULL_RECT)
	racine.offset_left = 8
	racine.offset_top = 6
	racine.offset_right = -8
	racine.offset_bottom = -6
	add_child(racine)

	var haut := HBoxContainer.new()
	haut.add_theme_constant_override("separation", 18)
	_bouton(haut, "← Menu", func(): get_tree().change_scene_to_file("res://scenes/menu.tscn"), 130)
	var titre := Label.new()
	titre.text = "Base des Hommes-rats"
	titre.add_theme_font_size_override("font_size", 24)
	titre.add_theme_color_override("font_color", Color(0.85, 0.6, 0.45))
	haut.add_child(titre)
	etiquette_or = Label.new()
	etiquette_or.add_theme_font_size_override("font_size", 24)
	etiquette_or.add_theme_color_override("font_color", Color(0.95, 0.8, 0.3))
	haut.add_child(etiquette_or)
	etiquette_prod = Label.new()
	etiquette_prod.add_theme_color_override("font_color", Color(0.65, 0.65, 0.6))
	etiquette_prod.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	haut.add_child(etiquette_prod)
	_bouton(haut, "Nouvelle partie", _nouvelle_partie, 0)
	racine.add_child(haut)

	etiquette_msg = Label.new()
	etiquette_msg.add_theme_color_override("font_color", Color(0.95, 0.8, 0.3))
	etiquette_msg.text = Donnees.dernier_resultat
	Donnees.dernier_resultat = ""
	racine.add_child(etiquette_msg)

	var corps := HBoxContainer.new()
	corps.size_flags_vertical = Control.SIZE_EXPAND_FILL
	corps.add_theme_constant_override("separation", 16)
	racine.add_child(corps)
	var defil_b := ScrollContainer.new()
	defil_b.custom_minimum_size.x = 470
	col_batiments = VBoxContainer.new()
	col_batiments.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	defil_b.add_child(col_batiments)
	corps.add_child(defil_b)
	var defil_a := ScrollContainer.new()
	defil_a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_armee = VBoxContainer.new()
	col_armee.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	defil_a.add_child(col_armee)
	corps.add_child(defil_a)

	Donnees.maj_or()
	reconstruire()


func _process(delta: float) -> void:
	minuterie += delta
	if minuterie >= 1.0:   # l'or monte chaque seconde
		minuterie = 0.0
		Donnees.maj_or()
		_maj_entete()


func _maj_entete() -> void:
	etiquette_or.text = "%d or" % int(Donnees.partie["or"])
	etiquette_prod.text = "+%d or / h  (prototype : 1 h = 1 min)" % int(Donnees.production_horaire())


func reconstruire() -> void:
	_maj_entete()
	for n in col_batiments.get_children() + col_armee.get_children():
		n.queue_free()
	_batiments()
	_armee()


func _dire(t: String) -> void:
	etiquette_msg.text = t


# --- Bâtiments ---------------------------------------------------------------

func _batiments() -> void:
	var t := Label.new()
	t.text = "Salles"
	t.add_theme_font_size_override("font_size", 22)
	col_batiments.add_child(t)
	for b in Donnees.batiments:
		var id: String = b["id"]
		var cadre := PanelContainer.new()
		var v := VBoxContainer.new()
		cadre.add_child(v)
		var nom := Label.new()
		var niv := Donnees.niveau(id)
		nom.text = "%s — niveau %d / %d" % [b["nom"], niv, b["max"]]
		nom.add_theme_color_override("font_color", Color.WHITE if niv > 0 else Color(0.6, 0.6, 0.55))
		v.add_child(nom)
		var effet := Label.new()
		effet.text = b["effet"]
		effet.add_theme_font_size_override("font_size", 15)
		effet.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65))
		v.add_child(effet)
		var cout := Donnees.cout_amelioration(id)
		var texte := "Niveau maximum"
		if cout > 0:
			texte = ("Construire" if niv == 0 else "Améliorer") + " (%d or)" % cout
		var bt := _bouton(v, texte, func():
			if Donnees.ameliorer(id):
				_dire("%s : niveau %d." % [b["nom"], Donnees.niveau(id)])
			else:
				_dire("Pas assez d'or.")
			reconstruire(), 0)
		bt.disabled = cout <= 0
		col_batiments.add_child(cadre)


# --- Armée et recrutement ----------------------------------------------------

func _armee() -> void:
	var armee: Array = Donnees.partie["armee"]
	var t := Label.new()
	t.text = "Armée — %d / %d piles — valeur %d or" % [armee.size(), Donnees.MAX_PILES, Donnees.valeur_armee(armee)]
	t.add_theme_font_size_override("font_size", 22)
	col_armee.add_child(t)
	for i in armee.size():
		var p: Dictionary = armee[i]
		var u = Donnees.unite(p["nom"])
		if u == null:
			continue
		var h := HBoxContainer.new()
		var img := TextureRect.new()
		img.custom_minimum_size = Vector2(40, 56)
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.texture = Donnees.texture(u.get("image", ""))
		h.add_child(img)
		var l := Label.new()
		l.text = "%s\n%d / %d  ·  %d or l'unité" % [u["nom"], p["nombre"], u["escouade"], u.get("cout", 0)]
		l.add_theme_font_size_override("font_size", 16)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		if Donnees.tier_recrutable(int(u["tier"])):
			var plein: bool = int(p["nombre"]) >= int(u["escouade"])
			for n in [1, 10, 9999]:
				var b := _bouton(h, "Max" if n == 9999 else "+%d" % n, func(): _recruter(i, n), 64)
				b.disabled = plein
		else:
			var r := Label.new()
			r.text = "Salle du tier %d requise" % u["tier"]
			r.add_theme_color_override("font_color", Color(0.8, 0.5, 0.4))
			h.add_child(r)
		col_armee.add_child(h)
	# Nouvelle pile
	if armee.size() < Donnees.MAX_PILES:
		var h := HBoxContainer.new()
		var choix := OptionButton.new()
		choix.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choix.custom_minimum_size.y = 46
		for u in Donnees.unites:
			if u["faction"] == "HR" and not u.get("seigneur", false) and Donnees.tier_recrutable(int(u["tier"])):
				choix.add_item("%s (%d or)" % [u["nom"], u.get("cout", 0)])
				choix.set_item_metadata(choix.item_count - 1, u["nom"])
		h.add_child(choix)
		_bouton(h, "Nouvelle pile", func():
			if choix.selected >= 0 and Donnees.nouvelle_pile(choix.get_item_metadata(choix.selected)):
				_dire("Nouvelle pile créée : recrute des créatures pour la remplir.")
			else:
				_dire("Impossible : pas assez d'or.")
			reconstruire(), 0)
		col_armee.add_child(h)
	var combat := _bouton(col_armee, "Partir au combat", _combattre, 0)
	combat.custom_minimum_size.y = 64
	combat.add_theme_color_override("font_color", Color(0.95, 0.8, 0.3))
	combat.disabled = armee.is_empty()


func _recruter(i: int, n: int) -> void:
	var r := Donnees.recruter(i, n)
	_dire("%d créatures recrutées." % r if r > 0 else "Pas assez d'or.")
	reconstruire()


func _combattre() -> void:
	Donnees.preparer_bataille_campagne()
	get_tree().change_scene_to_file("res://scenes/bataille.tscn")


var confirmer_raz := false


func _nouvelle_partie() -> void:
	if not confirmer_raz:   # deux appuis pour éviter d'effacer sa partie par erreur
		confirmer_raz = true
		_dire("Touche encore « Nouvelle partie » pour tout effacer et recommencer.")
		return
	confirmer_raz = false
	Donnees.nouvelle_partie()
	_dire("Nouvelle partie : %d or, Mine d'or et Couveuse au niveau 1." % Donnees.OR_DEPART)
	reconstruire()


func _bouton(parent: Control, texte: String, action: Callable, largeur: float) -> Button:
	var b := Button.new()
	b.text = texte
	b.custom_minimum_size = Vector2(largeur, 46)
	b.pressed.connect(action)
	parent.add_child(b)
	return b
