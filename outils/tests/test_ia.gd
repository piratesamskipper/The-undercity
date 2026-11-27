# Test de l'IA : IA contre IA, puis IA contre un joueur qui joue au hasard.
# Lancer depuis la racine : godot --headless --path jeu --script ../outils/tests/test_ia.gd
extends SceneTree

var rng := RandomNumberGenerator.new()


func coup_hasard(c: Combat) -> void:
	var a = c.actif
	var reach := c.accessibles(a)
	var cibles := []
	for e in c.ennemis_de(a):
		if (c.peut_tirer(a) and c.ligne_de_vue(a["pos"], e["pos"])) or (not c.peut_tirer(a) and c.case_attaque(a, e, reach) != null):
			cibles.append(e)
	if not cibles.is_empty() and rng.randf() < 0.7:
		c.attaquer(cibles[rng.randi() % cibles.size()])
	elif not reach.is_empty():
		c.deplacer(reach.keys()[rng.randi() % reach.size()])
	else:
		c.defendre()


func serie(unites: Dictionary, ia_hr: bool, ia_g: bool, n: int) -> String:
	var hr := [["Esclave du père des rats", 2], ["Frondeur des égouts", 2], ["Surineurs", 3], ["Rats mutés", 1], ["Seigneur des Hommes-rats", 1]]
	var g := [["Bleusaille", 1], ["Arbalétriers", 2], ["Soldats du cru", 3], ["Vétérans", 2], ["Seigneur de la Garde", 1]]
	var v := {"HR": 0, "G": 0, "nul": 0, "": 0}
	var annihilations := 0
	var pts_zones := 0
	var rounds := 0
	var ms := 0
	for i in n:
		var c := Combat.new(unites, hr, g)
		c.commencer()
		var k := 0
		while c.vainqueur == "" and k < 3000:
			k += 1
			var ia: bool = ia_hr if c.actif["camp"] == "HR" else ia_g
			if ia:
				var t := Time.get_ticks_usec()
				IA.jouer(c)
				ms = maxi(ms, Time.get_ticks_usec() - t)
			else:
				coup_hasard(c)
		v[c.vainqueur] += 1
		rounds += c.round_num
		for camp in c.detail_points:
			annihilations += 1 if c.detail_points[camp].has("annihilation") else 0
			pts_zones += c.detail_points[camp].get("zones", 0)
	return "HR %d %% · G %d %% · nuls %d · %.1f rounds · annihilations %d %% · points de zone/bataille %.1f · coup IA max %d ms" % [
		v["HR"] * 100 / n, v["G"] * 100 / n, v["nul"] + v[""], rounds / float(n), annihilations * 100 / n,
		pts_zones / float(n), ms / 1000]


func _initialize():
	var unites := {}
	for u in JSON.parse_string(FileAccess.get_file_as_string("res://donnees/unites.json")):
		unites[u["nom"]] = u
	print("IA contre IA      : ", serie(unites, true, true, 60))
	print("IA HR vs hasard G : ", serie(unites, true, false, 30))
	print("hasard HR vs IA G : ", serie(unites, false, true, 30))
	quit()
