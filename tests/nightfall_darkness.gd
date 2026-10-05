extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	assert(game.choose_card(0))
	game.set_process(false)
	game.world.set_process(false)
	game.start_night()
	game.world._process(6.0)
	var env: Environment=game.world.environment.environment
	assert(env.ambient_light_energy<.04 and game.world.sun.light_energy<.03,"Night must have almost no global illumination")
	assert(game.world.beacon_light.light_energy>8.0 and game.world.hero_lantern.light_energy>3.0,"Beacon and carried lantern must remain local light sources")
	assert(game.world.hero_lantern.omni_range<game.world.beacon_light.omni_range,"Carried lantern should reveal only the nearby ground")
	var pad: Dictionary=game.world.tower_pads[0]
	assert((pad.light as OmniLight3D).light_energy>1.0,"Opening defenses are already built")
	pad.level=1
	game.world.apply_lighting()
	assert((pad.light as OmniLight3D).light_energy>1.0,"Built towers should reveal their immediate surroundings")
	var relay: Dictionary=game.world.relays[0]
	relay.activated=true
	game.world.apply_lighting()
	assert((relay.light as OmniLight3D).light_energy>3.0,"Activated relays should create distant islands of light")
	var gate_before: float=game.world.gate_spots[0].light_energy
	game.world.gate_light_drain[0]=.8
	game.world._process(.7)
	assert(game.world.gate_spots[0].light_energy<gate_before*.25,"Light-eating enemies must noticeably darken the gate")
	game.world.gate_light_drain[0]=0.0
	game.world._process(.7)
	assert(game.world.gate_spots[0].light_energy>gate_before*.95,"Gate lighting must recover smoothly after the drain ends")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	print("NIGHTFALL_DARKNESS_OK")
	quit()
