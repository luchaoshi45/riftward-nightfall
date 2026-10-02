extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func capture(path: String) -> void:
	await create_timer(.35).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	game.choose_card(0);game.set_process(false)
	game.begin_day();game.world.night_mix=0;game.world.apply_lighting()
	var site: Dictionary=game.expeditions.generators[0]
	game.hero.position=site.position+Vector3(0,0,2.5);game.move_goal=game.hero.position
	game.interact();game.expeditions.tick(6.2)
	game.camera.size=24
	game.camera.position=site.position+Vector3(0,24,28)
	game.camera.look_at(site.position)
	game.hud.queue_redraw()
	await capture("res://build/day-generator-event.png")
	var camp: Dictionary=game.expeditions.camps[0]
	game.hero.position=camp.position+Vector3(0,0,2.2);game.move_goal=game.hero.position
	game.interact()
	game.camera.position=camp.position+Vector3(0,22,25)
	game.camera.look_at(camp.position)
	game.hud.queue_redraw()
	await capture("res://build/day-scout-rescue.png")
	print("NIGHTFALL_DAY_EXPEDITIONS_VISUAL_OK")
	quit()
