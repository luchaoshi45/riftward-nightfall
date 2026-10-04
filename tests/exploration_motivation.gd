extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var owner := Node3D.new()
	root.add_child(owner)
	var motivation=load("res://scripts/exploration_motivation.gd").new()
	root.add_child(motivation)
	motivation.setup(owner)
	var first: Dictionary=motivation.record("ember_bloom",Vector3(12,0,0),"day")
	assert(first.scrap==0 and first.memory==0,"First route item keeps its base reward")
	var second: Dictionary=motivation.record("memory_crystal",Vector3(12,0,0),"day")
	assert(second.memory==4 and motivation.streak==2,"Two different discoveries create a route streak")
	var third: Dictionary=motivation.record("supply_cache",Vector3(12,0,0),"day")
	assert(third.scrap==12 and third.memory==6 and motivation.best_streak==3,"Three-item route pays the mid bonus")
	motivation.set_waylight_count(2)
	var fourth: Dictionary=motivation.record("waylight",Vector3(50,0,0),"night")
	assert(fourth.scrap>=48 and fourth.memory>=12,"Full set and deep route bonuses are paid once")
	assert(motivation.night_discoveries==1 and motivation.deep_discoveries==1)
	assert(motivation.route_text().contains("完整搜寻"))
	var repeat: Dictionary=motivation.record("waylight",Vector3(12,0,0),"day")
	assert(repeat.scrap==0 and repeat.memory==0,"Repeating a type does not replay the full set reward")
	var network: Dictionary=motivation.record("ember_bloom",Vector3(12,0,0),"day")
	assert(network.memory>=2,"A two-lantern network adds a small route bonus")
	assert(motivation.run_summary().contains("最长连段 4"))
	print("EXPLORATION_MOTIVATION_OK route streak, full set, deep/night risk, light network and recap")
	owner.queue_free();motivation.queue_free()
	await process_frame
	quit()
