# Test : 300 batailles jouées au hasard, vérifie qu’aucune action légale n’est refusée.
# Lancer depuis la racine : godot --headless --path jeu --script ../outils/tests/test_combat.gd
extends SceneTree
func _initialize():
	var unites := {}
	for u in JSON.parse_string(FileAccess.get_file_as_string("res://donnees/unites.json")):
		unites[u["nom"]] = u
	var hr := [["Esclave du père des rats", 2], ["Frondeur des égouts", 2], ["Surineurs", 3], ["Rats mutés", 1]]
	var g := [["Bleusaille", 1], ["Arbalétriers", 2], ["Soldats du cru", 3], ["Vétérans", 2]]
	var rng := RandomNumberGenerator.new()
	var victoires := {"HR": 0, "G": 0, "": 0}
	var rounds := 0
	var erreurs := 0
	var revers := 0
	for n in 300:
		var c := Combat.new(unites, hr, g)
		c.commencer()
		var actions := 0
		while c.vainqueur == "" and actions < 3000:
			actions += 1
			var a = c.actif
			if a == null:
				erreurs += 1
				break
			# invariants
			var cases := {}
			for p in c.piles:
				if Combat.vivante(p):
					if cases.has(p["pos"]): erreurs += 1; print("deux piles sur une case")
					cases[p["pos"]] = true
					if not Combat.dans_grille(p["pos"]): erreurs += 1
			var reach := c.accessibles(a)
			var cibles := []
			for e in c.ennemis_de(a):
				if c.peut_tirer(a) or c.case_attaque(a, e, reach) != null:
					cibles.append(e)
			var r := rng.randf()
			if not cibles.is_empty() and r < 0.75:
				var e = cibles[rng.randi() % cibles.size()]
				var cases_a: Array = c.cases_attaque(a, e, reach)
				var depuis = null
				if not c.peut_tirer(a) and rng.randf() < 0.5:
					depuis = cases_a[rng.randi() % cases_a.size()]
					if Combat.a_revers(e, depuis): revers += 1
				if not c.attaquer(e, depuis): erreurs += 1; print("attaque refusée")
			elif r < 0.8:
				c.defendre()
			elif r < 0.85 and c.peut_attendre():
				c.attendre()
			elif not reach.is_empty():
				var ks := reach.keys()
				# avancer vers l'ennemi le plus souvent
				if not c.deplacer(ks[rng.randi() % ks.size()]): erreurs += 1; print("déplacement refusé")
			else:
				c.defendre()
		victoires[c.vainqueur] += 1
		rounds += c.round_num
	print("victoires ", victoires, " rounds moyens ", rounds / 300.0, " erreurs ", erreurs, " attaques de dos ", revers)
	quit()
