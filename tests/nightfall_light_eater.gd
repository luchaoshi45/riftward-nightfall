extends SceneTree

const LIGHT_EATER_SCENE: PackedScene = preload("res://assets/models/night_light_eater.glb")
const LIGHT_EATER_COMPONENT = preload("res://scripts/light_eater.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var game: Node3D = load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	game.world.set_process(false)
	for enemy in game.enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	game.enemies.clear()
	var moth := BattleUnit.new()
	game.add_child(moth)
	moth.setup("monster", 2)
	moth.visual.queue_free()
	moth.visual = LIGHT_EATER_SCENE.instantiate() as Node3D
	moth.add_child(moth.visual)
	moth.position = Vector3(25, 0, 35)
	moth.visual_yaw_offset = PI
	var aura: NightLightEater = LIGHT_EATER_COMPONENT.new()
	moth.add_child(aura)
	aura.setup(moth)
	assert(aura.wing_left.get_child_count() > 0 and aura.wing_right.get_child_count() > 0)
	assert(aura.drain_at(moth.position + Vector3(2, 0, 0)) > 0.65,
		"The moth must strongly suppress a nearby lamp")
	assert(aura.drain_at(moth.position + Vector3(16, 0, 0)) == 0.0,
		"Distant lamps must remain unaffected")
	moth.moving = true
	aura.tick(0.16)
	assert(absf(aura.wing_left.rotation.z) > 0.1 and
		absf(aura.wing_right.rotation.z) > 0.1, "Both wings must flap")
	aura.tick(.24)
	moth.face(moth.position + Vector3(0, 0, -3), 1.0)
	game.world.set_night(true)
	game.world._process(6.0)
	game.hero.visible = false
	game.hud.visible = false
	game.camera.size = 7.4
	game.camera.position = moth.position + Vector3(0, 4, -9)
	game.camera.look_at(moth.position + Vector3(0, 1.4, 0))
	game.camera.current = true
	if DisplayServer.get_name() != "headless":
		await create_timer(.18).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/night-light-eater-close.png")
		moth.position = Vector3(0, game.world.terrain_height(Vector3(0, 0, 15)), 15)
		game.camera.size = 20.0
		game.camera.position = moth.position + Vector3(0, 25, 29)
		game.camera.look_at(moth.position + Vector3(0, 1.0, 0))
		await create_timer(.18).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/night-light-eater-game.png")
	moth.alive = false
	assert(aura.drain_at(moth.position) == 0.0,
		"Killing the moth must restore affected lamps next lighting update")
	aura.tick(.1)
	assert(aura.cold_glow.light_energy == 0.0)
	print("NIGHTFALL_LIGHT_EATER_OK")
	quit()
