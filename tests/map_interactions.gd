extends SceneTree

func _initialize() -> void:
	call_deferred("inspect")

func inspect() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.auto_test = true
	game.start_match()
	game.select_card(0)
	assert(game.mode == "playing")
	assert(game.interactables.size() == 6)
	game.player.position = Vector3(-19, 0, -13.5)
	game.player.destination = game.player.position
	game.player.hp = 200
	game.mana = 0
	assert(game.interaction_prompt().begins_with("F 交互"))
	game.camera.size = 11
	game.camera.position = Vector3(-13, 9, -5)
	game.camera.look_at(Vector3(-19, 0.4, -15))
	game.camera.current = true
	await create_timer(.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/map-interactive-ingame.png")
	assert(game.interact_nearby())
	assert(game.player.hp > 200 and game.mana > 0)
	assert(not game.interact_nearby())
	game.player.position = Vector3(-8, 0, 7.5)
	game.power_time = 0
	assert(game.interact_nearby() and game.power_time >= 18)
	game.player.position = Vector3(-30, 0, 9.0)
	var before: float = game.essence
	assert(game.interact_nearby())
	assert(game.essence == before + 45.0)
	assert(not game.interact_nearby())
	game.mode = "paused"
	assert(not game.interact_nearby())
	print("MAP_INTERACTIONS_OK")
	quit()
