extends Control
## Éditeurs réservés aux versions de test : unités, cartes, armées.
## Tout est enregistré sur le téléphone dès qu'on modifie quelque chose ;
## « Exporter » copie les données dans le presse-papiers pour les intégrer au jeu.

const COULEURS := {"HR": Color(0.55, 0.32, 0.2), "G": Color(0.22, 0.38, 0.62)}

var info: Label   # bandeau de messages en bas


func _ready() -> void:
	theme = Donnees.theme_tactile()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var fond := ColorRect.new()
	fond.color = Color(0.09, 0.09, 0.1)
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
	var retour := Button.new()
	retour.text = "← Menu"
	retour.custom_minimum_size = Vector2(130, 48)
	retour.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	haut.add_child(retour)
	info = Label.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_color_override("font_color", Color(0.95, 0.8, 0.3))
	info.text = "  Les modifications sont enregistrées sur ce téléphone et utilisées par les batailles."
	haut.add_child(info)
	racine.add_child(haut)

	var onglets := TabContainer.new()
	onglets.size_flags_vertical = Control.SIZE_EXPAND_FILL
	racine.add_child(onglets)
	var eu := EditeurUnites.new(self)
	eu.name = "Unités"
	onglets.add_child(eu)
	var ec := EditeurCartes.new(self)
	ec.name = "Cartes"
	onglets.add_child(ec)
	var ea := EditeurArmees.new(self)
	ea.name = "Armées"
	onglets.add_child(ea)
	onglets.tab_changed.connect(func(_i): ea.reconstruire())


func dire(texte: String) -> void:
	info.text = "  " + texte


func exporter(titre: String, donnees) -> void:
	DisplayServer.clipboard_set(Donnees.exporter(donnees))
	dire("%s copiées dans le presse-papiers : colle-les dans la conversation avec Claude." % titre)


# --- Petits outils d'interface -----------------------------------------------

static func bouton(parent: Control, texte: String, action: Callable, largeur := 0.0) -> Button:
	var b := Button.new()
	b.text = texte
	b.custom_minimum_size = Vector2(largeur, 46)
	b.pressed.connect(action)
	parent.add_child(b)
	return b


## Ligne « libellé  [-10] [-1] valeur [+1] [+10] ». `changer` reçoit la nouvelle valeur.
static func ligne_nombre(parent: Control, libelle: String, valeur: int, mini: int, maxi: int,
		changer: Callable, gros_pas := 10) -> void:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = libelle
	l.custom_minimum_size.x = 210
	h.add_child(l)
	var champ := LineEdit.new()
	champ.text = str(valeur)
	champ.custom_minimum_size = Vector2(90, 46)
	champ.alignment = HORIZONTAL_ALIGNMENT_CENTER
	champ.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	var appliquer := func(v: int):
		v = clampi(v, mini, maxi)
		champ.text = str(v)
		changer.call(v)
	var pas_moins := [-gros_pas, -1] if gros_pas > 1 else [-1]
	var pas_plus := [1, gros_pas] if gros_pas > 1 else [1]
	for pas in pas_moins:
		bouton(h, str(pas), func(): appliquer.call(int(champ.text) + pas), 56)
	champ.text_submitted.connect(func(t): appliquer.call(int(t)))
	champ.focus_exited.connect(func(): appliquer.call(int(champ.text)))
	h.add_child(champ)
	for pas in pas_plus:
		bouton(h, "+" + str(pas), func(): appliquer.call(int(champ.text) + pas), 56)
	parent.add_child(h)


# =============================================================================
class EditeurUnites extends HBoxContainer:
	const CHAMPS := [
		# [clé, libellé, min, max, gros pas]
		["tier", "Tier", 0, 10, 1], ["pv", "PV (par créature)", 1, 9999, 10],
		["att", "Att", 1, 20, 5], ["def", "Déf", 1, 20, 5],
		["deg0", "Dégâts min", 0, 9999, 10], ["deg1", "Dégâts max", 0, 9999, 10],
		["vitesse", "Vitesse", 0, 20, 5], ["initiative", "Initiative", 0, 50, 5],
		["moral", "Moral", 0, 10, 5], ["chance", "Chance", 0, 10, 5],
		["portee", "Portée (0 = mêlée)", 0, 20, 5], ["munitions", "Munitions", 0, 99, 5],
		["escouade", "Capacité d'escouade", 1, 999, 10], ["cout", "Coût de recrutement (or)", 0, 99999, 10],
	]
	const CHAMPS_SEIGNEUR := [
		["aura", "Aura de moral", 0, 20, 5], ["intelligence", "Intelligence", 0, 50, 5],
		["puissance", "Puissance magique", 0, 50, 5],
	]
	const CAPACITES := [["bond", "Bond (saute 1 case de trou)"]]

	var ed
	var liste: ItemList
	var fiche: VBoxContainer
	var choisie := 0

	func _init(editeur) -> void:
		ed = editeur

	func _ready() -> void:
		var gauche := VBoxContainer.new()
		gauche.custom_minimum_size.x = 330
		liste = ItemList.new()
		liste.size_flags_vertical = Control.SIZE_EXPAND_FILL
		liste.item_selected.connect(func(i): choisie = i; _remplir_fiche())
		gauche.add_child(liste)
		var b1 := HBoxContainer.new()
		ed.bouton(b1, "Nouvelle", _nouvelle).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ed.bouton(b1, "Dupliquer", _dupliquer).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ed.bouton(b1, "Supprimer", _supprimer).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gauche.add_child(b1)
		var b2 := HBoxContainer.new()
		ed.bouton(b2, "Réinitialiser", _reinitialiser).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ed.bouton(b2, "Exporter", func(): ed.exporter("Unités", Donnees.unites)).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gauche.add_child(b2)
		add_child(gauche)
		var defil := ScrollContainer.new()
		defil.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fiche = VBoxContainer.new()
		fiche.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		defil.add_child(fiche)
		add_child(defil)
		_remplir_liste()

	func _remplir_liste() -> void:
		liste.clear()
		for u in Donnees.unites:
			var i := liste.add_item("%s  (%s)" % [u["nom"], u["faction"]])
			liste.set_item_custom_fg_color(i, COULEURS.get(u["faction"], Color.WHITE).lightened(0.45))
		choisie = clampi(choisie, 0, Donnees.unites.size() - 1)
		if not Donnees.unites.is_empty():
			liste.select(choisie)
		_remplir_fiche()

	func _remplir_fiche() -> void:
		for n in fiche.get_children():
			n.queue_free()
		if Donnees.unites.is_empty():
			return
		var u: Dictionary = Donnees.unites[choisie]
		# Nom
		var h := HBoxContainer.new()
		var l := Label.new()
		l.text = "Nom"
		l.custom_minimum_size.x = 210
		h.add_child(l)
		var nom := LineEdit.new()
		nom.text = u["nom"]
		nom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nom.custom_minimum_size.y = 46
		nom.text_submitted.connect(func(t): _renommer(u, t))
		nom.focus_exited.connect(func(): _renommer(u, nom.text))
		h.add_child(nom)
		fiche.add_child(h)
		# Faction et seigneur
		var h2 := HBoxContainer.new()
		var lf := Label.new()
		lf.text = "Faction"
		lf.custom_minimum_size.x = 210
		h2.add_child(lf)
		var fac := OptionButton.new()
		fac.custom_minimum_size = Vector2(160, 46)
		fac.add_item("HR")
		fac.add_item("G")
		fac.select(0 if u["faction"] == "HR" else 1)
		fac.item_selected.connect(func(i): u["faction"] = fac.get_item_text(i); _sauver(true))
		h2.add_child(fac)
		var seig := CheckBox.new()
		seig.text = "Seigneur"
		seig.button_pressed = u.get("seigneur", false)
		seig.toggled.connect(func(v): _basculer_seigneur(u, v))
		h2.add_child(seig)
		fiche.add_child(h2)
		# Stats
		for c in CHAMPS:
			var cle: String = c[0]
			var v: int
			if cle == "deg0":
				v = int(u["deg"][0])
			elif cle == "deg1":
				v = int(u["deg"][1])
			else:
				v = int(u.get(cle, 0))
			ed.ligne_nombre(fiche, c[1], v, c[2], c[3], func(x): _changer(u, cle, x), c[4])
		if u.get("seigneur", false):
			for c in CHAMPS_SEIGNEUR:
				var cle: String = c[0]
				ed.ligne_nombre(fiche, c[1], int(u.get(cle, 0)), c[2], c[3], func(x): _changer(u, cle, x), c[4])
		# Capacités
		var titre := Label.new()
		titre.text = "Capacités spéciales"
		titre.add_theme_color_override("font_color", Color(0.95, 0.8, 0.3))
		fiche.add_child(titre)
		for cap in CAPACITES:
			var cb := CheckBox.new()
			cb.text = cap[1]
			cb.button_pressed = u.get("capacites", []).has(cap[0])
			var id: String = cap[0]
			cb.toggled.connect(func(v): _capacite(u, id, v))
			fiche.add_child(cb)

	func _changer(u: Dictionary, cle: String, v: int) -> void:
		if cle == "deg0":
			u["deg"][0] = v
			u["deg"][1] = maxi(u["deg"][1], v)
		elif cle == "deg1":
			u["deg"][1] = v
			u["deg"][0] = mini(u["deg"][0], v)
		else:
			u[cle] = v
		_sauver(false)

	func _capacite(u: Dictionary, id: String, actif: bool) -> void:
		var caps: Array = u.get("capacites", [])
		if actif and not caps.has(id):
			caps.append(id)
		elif not actif:
			caps.erase(id)
		u["capacites"] = caps
		_sauver(false)

	func _basculer_seigneur(u: Dictionary, v: bool) -> void:
		u["seigneur"] = v
		if v:
			u["escouade"] = 1
			for c in CHAMPS_SEIGNEUR:
				if not u.has(c[0]):
					u[c[0]] = 0
		_sauver(false)
		_remplir_fiche()

	func _renommer(u: Dictionary, nouveau: String) -> void:
		nouveau = nouveau.strip_edges()
		var ancien: String = u["nom"]
		if nouveau == "" or nouveau == ancien:
			return
		if Donnees.unite(nouveau) != null:
			ed.dire("Une unité s'appelle déjà « %s »." % nouveau)
			return
		u["nom"] = nouveau
		for camp in Donnees.armees:
			for p in Donnees.armees[camp]:
				if p["nom"] == ancien:
					p["nom"] = nouveau
		Donnees.sauver_armees()
		_sauver(true)

	func _nouvelle() -> void:
		var n := 1
		while Donnees.unite("Nouvelle unité %d" % n) != null:
			n += 1
		Donnees.unites.append({
			"nom": "Nouvelle unité %d" % n, "faction": "HR", "tier": 1, "pv": 5, "att": 3, "def": 3,
			"deg": [1, 3], "vitesse": 5, "initiative": 8, "moral": 5, "chance": 5, "portee": 0,
			"munitions": 0, "escouade": 30, "cout": 0})
		choisie = Donnees.unites.size() - 1
		_sauver(true)

	func _dupliquer() -> void:
		var u: Dictionary = Donnees.unites[choisie].duplicate(true)
		var base: String = u["nom"]
		var n := 2
		while Donnees.unite("%s %d" % [base, n]) != null:
			n += 1
		u["nom"] = "%s %d" % [base, n]
		Donnees.unites.append(u)
		choisie = Donnees.unites.size() - 1
		_sauver(true)

	func _supprimer() -> void:
		if Donnees.unites.size() <= 1:
			return
		var nom: String = Donnees.unites[choisie]["nom"]
		Donnees.unites.remove_at(choisie)
		for camp in Donnees.armees:
			Donnees.armees[camp] = Donnees.armees[camp].filter(func(p): return p["nom"] != nom)
		Donnees.sauver_armees()
		ed.dire("« %s » supprimée (et retirée des armées)." % nom)
		_sauver(true)

	func _reinitialiser() -> void:
		Donnees.reinitialiser_unites()
		choisie = 0
		_remplir_liste()
		ed.dire("Unités remises aux valeurs du jeu.")

	func _sauver(rafraichir_liste: bool) -> void:
		Donnees.sauver_unites()
		if rafraichir_liste:
			_remplir_liste()


# =============================================================================
class EditeurCartes extends HBoxContainer:
	const OUTILS := [
		["mur", "Mur"], ["obstacle", "Obstacle"], ["trou", "Trou"], ["eau", "Eau"],
		["toxique", "Égout toxique"], ["sombre", "Zone sombre"], ["zone", "Zone à contrôler"], ["", "Gomme"],
	]
	var ed
	var grille: GrilleCarte
	var nom: LineEdit
	var choix: OptionButton
	var miroir: CheckBox
	var outil := "mur"
	var boutons_outils := {}

	func _init(editeur) -> void:
		ed = editeur

	func _ready() -> void:
		grille = GrilleCarte.new()
		grille.peindre = _peindre
		add_child(grille)
		var droite := VBoxContainer.new()
		droite.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var palette := GridContainer.new()
		palette.columns = 2
		for o in OUTILS:
			var id: String = o[0]
			var b := Button.new()
			b.text = o[1]
			b.toggle_mode = true
			b.custom_minimum_size = Vector2(0, 44)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.pressed.connect(func(): _choisir_outil(id))
			palette.add_child(b)
			boutons_outils[id] = b
		droite.add_child(palette)
		miroir = CheckBox.new()
		miroir.text = "Miroir (symétrie gauche-droite)"
		miroir.button_pressed = true
		droite.add_child(miroir)
		var h := HBoxContainer.new()
		nom = LineEdit.new()
		nom.placeholder_text = "Nom de la carte"
		nom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nom.custom_minimum_size.y = 46
		h.add_child(nom)
		ed.bouton(h, "Enregistrer", _enregistrer)
		droite.add_child(h)
		var h2 := HBoxContainer.new()
		choix = OptionButton.new()
		choix.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choix.custom_minimum_size.y = 46
		h2.add_child(choix)
		ed.bouton(h2, "Ouvrir", _ouvrir)
		ed.bouton(h2, "Supprimer", _supprimer)
		droite.add_child(h2)
		var h3 := HBoxContainer.new()
		ed.bouton(h3, "Carte vide", func(): grille.vider(); nom.text = "").size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ed.bouton(h3, "Exporter", func(): ed.exporter("Cartes", Donnees.cartes)).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		droite.add_child(h3)
		var aide := Label.new()
		aide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		aide.add_theme_font_size_override("font_size", 15)
		aide.add_theme_color_override("font_color", Color(0.6, 0.6, 0.55))
		aide.text = "Peins au doigt. Les 2 colonnes de chaque bord (teintées) sont les zones de déploiement : on ne peut rien y poser. Des cases de zone voisines forment une seule zone."
		droite.add_child(aide)
		add_child(droite)
		_choisir_outil("mur")
		_remplir_choix()

	func _choisir_outil(id: String) -> void:
		outil = id
		for k in boutons_outils:
			boutons_outils[k].button_pressed = k == id

	func _peindre(c: Vector2i) -> void:
		var cases := [c]
		if miroir.button_pressed:
			cases.append(Vector2i(Combat.COLONNES - 1 - c.x, c.y))
		for x in cases:
			grille.poser(x, outil)

	func _remplir_choix() -> void:
		choix.clear()
		var noms := Donnees.cartes.keys()
		noms.sort()
		for n in noms:
			choix.add_item(n)

	func _enregistrer() -> void:
		var n := nom.text.strip_edges()
		if n == "":
			ed.dire("Donne un nom à la carte avant de l'enregistrer.")
			return
		var carte := grille.vers_donnees()
		Donnees.cartes[n] = carte
		Donnees.sauver_cartes()
		_remplir_choix()
		var test := Combat.new({}, [], [], "HR", "G", carte)
		if test._carte_connexe():
			ed.dire("Carte « %s » enregistrée. Elle est proposée dans le menu." % n)
		else:
			ed.dire("Carte « %s » enregistrée, mais certaines cases sont inaccessibles !" % n)

	func _ouvrir() -> void:
		if choix.selected < 0:
			return
		var n := choix.get_item_text(choix.selected)
		grille.depuis_donnees(Donnees.cartes[n])
		nom.text = n
		ed.dire("Carte « %s » ouverte." % n)

	func _supprimer() -> void:
		if choix.selected < 0:
			return
		var n := choix.get_item_text(choix.selected)
		Donnees.cartes.erase(n)
		Donnees.sauver_cartes()
		if Donnees.carte_choisie == n:
			Donnees.carte_choisie = ""
		_remplir_choix()
		ed.dire("Carte « %s » supprimée." % n)


class GrilleCarte extends Control:
	const TAILLE := 44.0
	const TEINTES := {
		"mur": Color(0.42, 0.4, 0.37), "obstacle": Color(0.45, 0.33, 0.2), "trou": Color(0, 0, 0),
		"eau": Color(0.15, 0.32, 0.55), "toxique": Color(0.3, 0.55, 0.12), "sombre": Color(0.12, 0.06, 0.2),
	}
	var terrain := {}     # Vector2i -> type
	var zones := {}       # Vector2i -> true
	var peindre: Callable

	func _init() -> void:
		custom_minimum_size = Vector2(Combat.COLONNES, Combat.LIGNES) * TAILLE + Vector2(4, 4)

	func vider() -> void:
		terrain.clear()
		zones.clear()
		queue_redraw()

	func poser(c: Vector2i, outil: String) -> void:
		if c.x < Combat.ZONE_DEPLOIEMENT or c.x >= Combat.COLONNES - Combat.ZONE_DEPLOIEMENT:
			return
		if outil == "zone":
			terrain.erase(c)
			zones[c] = true
		elif outil == "":
			terrain.erase(c)
			zones.erase(c)
		else:
			zones.erase(c)
			terrain[c] = outil
		queue_redraw()

	func vers_donnees() -> Dictionary:
		var t := {}
		for c in terrain:
			t["%d,%d" % [c.x, c.y]] = terrain[c]
		var z := []
		for c in zones:
			z.append([c.x, c.y])
		return {"terrain": t, "zones": z}

	func depuis_donnees(d: Dictionary) -> void:
		vider()
		for cle in d.get("terrain", {}):
			var xy: PackedStringArray = str(cle).split(",")
			terrain[Vector2i(int(xy[0]), int(xy[1]))] = d["terrain"][cle]
		for xy in d.get("zones", []):
			zones[Vector2i(int(xy[0]), int(xy[1]))] = true
		queue_redraw()

	func _draw() -> void:
		for y in Combat.LIGNES:
			for x in Combat.COLONNES:
				var c := Vector2i(x, y)
				var r := Rect2(Vector2(x, y) * TAILLE + Vector2(2, 2), Vector2.ONE * (TAILLE - 2))
				var fond := Color(0.17, 0.17, 0.16) if (x + y) % 2 == 0 else Color(0.2, 0.2, 0.19)
				if x < Combat.ZONE_DEPLOIEMENT:
					fond = fond.lerp(COULEURS["HR"], 0.35)
				elif x >= Combat.COLONNES - Combat.ZONE_DEPLOIEMENT:
					fond = fond.lerp(COULEURS["G"], 0.35)
				if terrain.has(c):
					fond = TEINTES[terrain[c]]
				draw_rect(r, fond)
				if terrain.get(c, "") == "obstacle":
					draw_line(r.position + Vector2(10, 10), r.end - Vector2(10, 10), Color(0.7, 0.55, 0.3), 3)
					draw_line(Vector2(r.end.x - 10, r.position.y + 10), Vector2(r.position.x + 10, r.end.y - 10),
							Color(0.7, 0.55, 0.3), 3)
				elif terrain.get(c, "") == "trou":
					draw_arc(r.get_center(), TAILLE * 0.35, 0, TAU, 20, Color(0.4, 0.35, 0.3), 2)
				if zones.has(c):
					draw_rect(r.grow(-2), Color(0.95, 0.8, 0.3), false, 3)
		# ligne médiane
		var xm := Combat.COLONNES / 2 * TAILLE + 2
		draw_line(Vector2(xm, 2), Vector2(xm, Combat.LIGNES * TAILLE + 2), Color(1, 1, 1, 0.25), 1)

	func _gui_input(event: InputEvent) -> void:
		var appui: bool = (event is InputEventMouseButton and event.pressed) \
				or (event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT)
		if appui:
			var c := Vector2i(floori((event.position.x - 2) / TAILLE), floori((event.position.y - 2) / TAILLE))
			if Combat.dans_grille(c):
				peindre.call(c)
			accept_event()


# =============================================================================
class EditeurArmees extends HBoxContainer:
	var ed

	func _init(editeur) -> void:
		ed = editeur

	func _ready() -> void:
		reconstruire()

	func reconstruire() -> void:
		for n in get_children():
			n.queue_free()
		for camp in ["HR", "G"]:
			var defil := ScrollContainer.new()
			defil.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var col := VBoxContainer.new()
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			defil.add_child(col)
			add_child(defil)
			_colonne(col, camp)

	func _colonne(col: VBoxContainer, camp: String) -> void:
		var titre := Label.new()
		titre.text = "Hommes-rats" if camp == "HR" else "Garde"
		titre.add_theme_font_size_override("font_size", 24)
		titre.add_theme_color_override("font_color", COULEURS[camp].lightened(0.45))
		col.add_child(titre)
		var armee: Array = Donnees.armees[camp]
		var seigneurs := Donnees.unites.filter(func(u): return u["faction"] == camp and u.get("seigneur", false))
		var troupes := Donnees.unites.filter(func(u): return u["faction"] == camp and not u.get("seigneur", false))
		# Seigneur
		var hs := HBoxContainer.new()
		var ls := Label.new()
		ls.text = "Seigneur"
		hs.add_child(ls)
		var choix_s := OptionButton.new()
		choix_s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choix_s.custom_minimum_size.y = 46
		choix_s.add_item("Aucun")
		var actuel := ""
		for p in armee:
			var u = Donnees.unite(p["nom"])
			if u != null and u.get("seigneur", false):
				actuel = p["nom"]
		for u in seigneurs:
			choix_s.add_item(u["nom"])
			if u["nom"] == actuel:
				choix_s.select(choix_s.item_count - 1)
		choix_s.item_selected.connect(func(i): _changer_seigneur(camp, "" if i == 0 else choix_s.get_item_text(i)))
		hs.add_child(choix_s)
		col.add_child(hs)
		# Piles
		var n_piles := 0
		for i in armee.size():
			var p: Dictionary = armee[i]
			var u = Donnees.unite(p["nom"])
			if u == null or u.get("seigneur", false):
				continue
			n_piles += 1
			var cadre := VBoxContainer.new()
			var h := HBoxContainer.new()
			var choix_u := OptionButton.new()
			choix_u.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			choix_u.custom_minimum_size.y = 46
			for t in troupes:
				choix_u.add_item(t["nom"])
				if t["nom"] == p["nom"]:
					choix_u.select(choix_u.item_count - 1)
			choix_u.item_selected.connect(func(k): _changer_unite(p, choix_u.get_item_text(k)))
			h.add_child(choix_u)
			ed.bouton(h, "✕", func(): armee.erase(p); _sauver(), 50)
			cadre.add_child(h)
			ed.ligne_nombre(cadre, "  Créatures (max %d)" % u["escouade"], int(p["nombre"]), 1, int(u["escouade"]),
					func(v): p["nombre"] = v; Donnees.sauver_armees(), 10)
			col.add_child(cadre)
			col.add_child(HSeparator.new())
		if n_piles < Donnees.MAX_PILES and not troupes.is_empty():
			ed.bouton(col, "+ Ajouter une pile (%d / %d)" % [n_piles, Donnees.MAX_PILES],
					func(): armee.append({"nom": troupes[0]["nom"], "nombre": int(troupes[0]["escouade"])}); _sauver())
		var hb := HBoxContainer.new()
		ed.bouton(hb, "Réinitialiser", func(): Donnees.reinitialiser_armees(); reconstruire())
		ed.bouton(hb, "Exporter", func(): ed.exporter("Armées", Donnees.armees))
		col.add_child(hb)

	func _changer_seigneur(camp: String, nom: String) -> void:
		var armee: Array = Donnees.armees[camp]
		Donnees.armees[camp] = armee.filter(func(p):
			var u = Donnees.unite(p["nom"])
			return u == null or not u.get("seigneur", false))
		if nom != "":
			Donnees.armees[camp].append({"nom": nom, "nombre": 1})
		_sauver()

	func _changer_unite(p: Dictionary, nom: String) -> void:
		p["nom"] = nom
		p["nombre"] = int(Donnees.unite(nom)["escouade"])
		_sauver()

	func _sauver() -> void:
		Donnees.sauver_armees()
		reconstruire()
