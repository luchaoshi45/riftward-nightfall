extends SceneTree

func _initialize() -> void:
	call_deferred("inspect_asset")

func inspect_asset() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	for team in ["blue", "red"]:
		var packed := load("res://assets/models/hero_ashwarden_%s.glb" % team) as PackedScene
		var hero := packed.instantiate() as Node3D
		scene.add_child(hero)
		for side in ["L", "R"]:
			var arm := hero.find_child("Arm" + side, true, false) as Node3D
			var elbow := hero.find_child("Elbow" + side, true, false) as Node3D
			var forearm := hero.find_child("Forearm armor " + side, true, false) as Node3D
			assert(elbow != null and elbow.get_parent() == arm)
			assert(forearm != null and forearm.get_parent() == elbow)
			assert(elbow.position.distance_to(Vector3(0.0, -0.395, 0.012)) < 0.001)
			var wrist: Node3D
			for child in elbow.get_children():
				if str(child.name).begins_with("Gauntlet"):
					wrist = child as Node3D
			assert(wrist != null)
			var hand_center := (wrist as MeshInstance3D).get_aabb().get_center()
			var before := wrist.global_transform * hand_center
			var shoulder_before := arm.global_transform
			elbow.rotation.x = -0.8
			var after := wrist.global_transform * hand_center
			assert(after.z > before.z + 0.20)
			assert(after.y > before.y + 0.07)
			assert(arm.global_transform.is_equal_approx(shoulder_before))
			print("ELBOW_CHECK ", team, " ", side, " local=", elbow.position, " forward_delta=", after - before)
			elbow.rotation.x = 0.0
		var weapon := hero.find_child("Sword wrist", true, false)
		assert(weapon != null and weapon.get_parent().name == "ElbowR")
		if team == "red":
			hero.queue_free()
		elif DisplayServer.get_name() != "headless":
			var camera := Camera3D.new()
			scene.add_child(camera)
			camera.position = Vector3(3.6, 2.5, 4.8)
			camera.look_at(Vector3(0.0, 1.1, 0.0))
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = 3.5
			var light := DirectionalLight3D.new()
			scene.add_child(light)
			light.rotation_degrees = Vector3(-38.0, -30.0, 0.0)
			light.light_energy = 1.7
			var env := WorldEnvironment.new()
			env.environment = Environment.new()
			env.environment.background_mode = Environment.BG_COLOR
			env.environment.background_color = Color(0.04, 0.055, 0.065)
			env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.environment.ambient_light_color = Color(0.54, 0.65, 0.70)
			env.environment.ambient_light_energy = 0.65
			scene.add_child(env)
			root.size = Vector2i(960, 640)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/hero-elbow-rest-check.png")
			(hero.find_child("ElbowR", true, false) as Node3D).rotation.x = -0.85
			(hero.find_child("ElbowL", true, false) as Node3D).rotation.x = -0.45
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/hero-elbow-flex-check.png")
	scene.queue_free()
	await process_frame
	print("HERO_ARM_ART_CHECK_OK")
	quit()
