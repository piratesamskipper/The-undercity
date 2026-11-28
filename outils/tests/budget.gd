# Batailles à budget égal : chaque camp dépense le même or (coût de recrutement).
# IA contre IA, cartes aléatoires, seigneurs inclus (hors budget).
# Lancer depuis la racine : godot --headless --path jeu --script ../outils/tests/budget.gd
extends SceneTree

const N := 80
var rng := RandomNumberGenerator.new()
var unites := {}


func cout(nom: String) -> int:
	return int(unites[nom].get("cout", 0))


## Met à l'échelle une composition (liste de noms de piles) pour qu'elle coûte `budget`.
func armee(noms: Array, budget: int) -> Array:
	var plein := 0
	for n in noms:
		plein += cout(n) * int(unites[n]["escouade"])
	var f := float(budget) / plein
	var res := []
	for n in noms:
		res.append({"nom": n, "nombre": clampi(roundi(unites[n]["escouade"] * f), 1, int(unites[n]["escouade"]))})
	return res


func prix(a: Array) -> int:
	var t := 0
	for p in a:
		t += cout(p["nom"]) * int(p["nombre"])
	return t


func bataille(hr: Array, g: Array, carte := {}) -> String:
	var c := Combat.new(unites, hr, g, "HR", "G", carte)
	c.commencer()
	var k := 0
	while c.vainqueur == "" and k < 3000:
		k += 1
		IA.jouer(c)
	return c.vainqueur


func serie(titre: String, fabrique: Callable) -> void:
	var v := {"HR": 0, "G": 0, "nul": 0, "": 0}
	var prix_hr := 0
	var prix_g := 0
	for i in N:
		var duo: Array = fabrique.call()
		prix_hr += prix(duo[0])
		prix_g += prix(duo[1])
		v[bataille(duo[0] + [{"nom": "Seigneur des Hommes-rats", "nombre": 1}],
				duo[1] + [{"nom": "Seigneur de la Garde", "nombre": 1}])] += 1
	print("%-42s HR %3d %% · G %3d %% · nuls %2d %%   (or dépensé : HR %d, G %d)" % [
		titre, v["HR"] * 100 / N, v["G"] * 100 / N, (v["nul"] + v[""]) * 100 / N, prix_hr / N, prix_g / N])


func _initialize():
	rng.seed = 12345
	for u in JSON.parse_string(FileAccess.get_file_as_string("res://donnees/unites.json")):
		unites[u["nom"]] = u
	var test_hr := ["Esclave du père des rats", "Esclave du père des rats", "Frondeur des égouts",
		"Frondeur des égouts", "Surineurs", "Surineurs", "Surineurs", "Rats mutés"]
	var test_g := ["Bleusaille", "Arbalétriers", "Arbalétriers", "Soldats du cru", "Soldats du cru",
		"Soldats du cru", "Vétérans", "Vétérans"]
	var troupes_hr := ["Esclave du père des rats", "Frondeur des égouts", "Surineurs", "Rats mutés"]
	var troupes_g := ["Bleusaille", "Arbalétriers", "Soldats du cru", "Vétérans"]

	print("== Armées de test, mises à l'échelle du budget ==")
	for budget in [4000, 6000, 8000]:
		serie("Budget %d or" % budget, func(): return [armee(test_hr, budget), armee(test_g, budget)])

	print("\n== Compositions tirées au hasard (8 piles), budget 6000 or ==")
	serie("Hasard", func():
		var a := []
		var b := []
		for i in 8:
			a.append(troupes_hr[rng.randi() % 4])
			b.append(troupes_g[rng.randi() % 4])
		return [armee(a, 6000), armee(b, 6000)])

	print("\n== Duels 1 pile contre 1 pile à 1000 or chacune, carte vide (%% de victoire de la ligne) ==")
	var vide := {"terrain": {}, "zones": []}
	var entete := "%-26s" % ""
	for g in troupes_g:
		entete += "%-16s" % g
	print(entete)
	for h in troupes_hr:
		var ligne := "%-26s" % h
		for g in troupes_g:
			var nh := mini(1000 / cout(h), int(unites[h]["escouade"]))
			var ng := mini(1000 / cout(g), int(unites[g]["escouade"]))
			var w := 0
			for i in 40:
				if bataille([{"nom": h, "nombre": nh}], [{"nom": g, "nombre": ng}], vide) == "HR":
					w += 1
			ligne += "%-16s" % ("%d %% (%d c. %d)" % [w * 100 / 40, nh, ng])
		print(ligne)
	quit()
