extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node3D=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	var runners:=0
	var breakers:=0
	var sappers:=0
	for i in range(45):
		var enemy: BattleUnit=game.spawn_creature(true)
		var threat: String=enemy.get_meta("threat","")
		if threat=="runner":
			runners+=1
			assert(enemy.speed>5.0 and enemy.hp<200)
		elif threat=="breaker":
			breakers+=1
			assert(enemy.speed<3.0 and enemy.hp>350)
		elif threat=="sapper":
			sappers+=1
			assert(enemy.speed>4.0 and enemy.hp>190)
	assert(runners>0 and breakers>0 and sappers>0,"Night waves need fast, armored and tower-hunting threats")
	print("NIGHTFALL_ENEMY_TYPES_OK ",runners," runners, ",breakers," breakers, ",sappers," sappers")
	quit()
