extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.phase="night"
	var original: float=game.camera.size
	for button in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		var event:=InputEventMouseButton.new()
		event.button_index=button
		event.pressed=true
		assert(game.handle_strategy_mouse(event))
		assert(game.camera.size==original)
	game.phase="paused"
	game.hud.update_camera_slider()
	assert(game.hud.camera_slider.visible)
	assert(not game.hud.camera_slider.scrollable)
	game.hud.camera_slider.value=21
	assert(game.camera.size==21)
	game.hud.camera_slider.value=52
	assert(game.camera.size==52)
	game.hud._set_camera_view(100)
	assert(game.camera.size==52)
	var mechanism=game.world.tower_pads[0].turret.get_node("TowerMechanism")
	var before: float=mechanism.elapsed
	game._process(.2)
	assert(mechanism.elapsed==before)
	game.phase="night"
	game.update_towers(.1)
	assert(mechanism.elapsed>before)
	mechanism.fire()
	mechanism.advance(.05)
	assert(mechanism.recoil>0 and mechanism.recoil<1)
	for branch in ["standard","piercing","control","flame","chain"]:
		for tier in [1,2,3]:
			mechanism.configure(tier,branch)
			assert(mechanism.tier==tier and mechanism.variant==branch)
			assert(mechanism.rotor.get_child_count()==tier+2)
	game.hud.camera_slider.value=38
	game.phase="paused"
	game.hud.update_camera_slider()
	await process_frame
	if DisplayServer.get_name()!="headless":
		await process_frame
		root.get_texture().get_image().save_png("res://build/camera-tower-settings.png")
	if DisplayServer.get_name()!="headless":
		game.phase="night"
		game.camera.size=21
		game.camera.position=game.world.tower_pads[0].position+Vector3(0,26,20)
		game.camera.look_at(game.world.tower_pads[0].position,Vector3.UP)
		await process_frame
		await process_frame
		root.get_texture().get_image().save_png("res://build/camera-tower-detail.png")
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	print("NIGHTFALL_CAMERA_TOWER_OK")
	quit(0)
