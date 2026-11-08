extends SceneTree

func _initialize() -> void:
	var game = preload("res://src/game.gd").new()
	var atlas = []
	for country in game.atlas:
		atlas.append({"name": country.name, "neighbors": country.neighbors.map(func(n): return int(n)), "enclave_hosts": country.enclave_hosts.map(func(n): return int(n))})
	var file = FileAccess.open("res://hosting/data.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"balance": int(game.military.balance_version), "countries": game.countries, "atlas": atlas}))
	file.close()
	assert(DirAccess.copy_absolute("res://assets/balance.json", "res://hosting/balance.json") == OK, "Cannot prepare PHP balance")
	quit()
