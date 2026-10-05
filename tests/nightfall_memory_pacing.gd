extends SceneTree
## Income stays spendable until the player explicitly buys a local upgrade.
var game: Node3D
var checks := 0
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks+=1
	if condition:return
	failures+=1
	push_error(message)

func press(code: int) -> void:
	var event:=InputEventKey.new()
	event.keycode=code;event.physical_keycode=code;event.pressed=true
	root.push_input(event,true)
	event.pressed=false;root.push_input(event,true)

func run() -> void:
	game=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	for i in 8:await process_frame
	game.set_process(false);press(KEY_1)
	for enemy in game.enemies:enemy.queue_free()
	game.enemies.clear();await process_frame
	check(game.run.memory_level==0 and game.run.memory_cost()==120,"The initial paid fee is independent of the free core")
	var attack_target: BattleUnit=game.spawn_creature(false)
	attack_target.position=game.hero.position+Vector3.RIGHT
	attack_target.hp=3000;attack_target.max_hp=3000
	game.auto_attack()
	game.scrap=112
	var victim: BattleUnit=game.spawn_creature(false)
	victim.hp=1;victim.hurt(50,null)
	check(game.phase=="night" and game.run.pending==0 and game.scrap==120,"A kill adds its real eight scrap without automatic card payments")
	check(game.run.memory_cost()==120 and game.hero_attack_target==attack_target,"Income must not interrupt a pending real attack")
	game.update_hero_attack(1)
	check(attack_target.hp<3000,"The real attack continues while income becomes affordable")
	press(KEY_V)
	check(game.phase=="draft" and game.scrap==0 and game.run.pending==1,"V purchases one 120-scrap upgrade")
	var remaining: float=game.phase_time
	var chain: float=game.attack_chain_time
	game.simulate(5)
	press(KEY_V)
	check(game.phase_time==remaining and game.attack_chain_time==chain and game.scrap==0,"Selection and repeated V freeze the simulation and cannot purchase twice")
	press(KEY_1)
	check(game.phase=="night" and game.phase_time==remaining and game.run.memory_level==1,"Choosing the paid card resumes the interrupted night")
	game.run.memory_level=0;game.scrap=4200
	game.phase="paused";press(KEY_V)
	check(game.run.pending==0 and game.scrap==4200,"Paused input cannot purchase")
	game.phase="night"
	for i in 5:
		var before: int=game.scrap
		var cost: int=game.run.memory_cost()
		press(KEY_V)
		check(game.phase=="draft" and game.run.pending==1 and game.scrap==before-cost,"Each deliberate purchase opens exactly one card")
		press(KEY_1)
	check(game.run.memory_level==5 and game.scrap==2780 and game.phase=="night","Five deliberate fees leave the correct common balance")
	game.finish_night()
	check(game.run.memory_level==5 and game.run.pending==1 and game.scrap==2780,"Dawn gifts do not purchase another inscription")
	press(KEY_1)
	check(game.phase=="day" and game.phase_time==90 and game.scrap==2780,"The free dawn card resumes a fresh day without changing the balance")
	await game.prepare_shutdown();game.queue_free()
	for i in 4:await process_frame
	print("NIGHTFALL_MEMORY_PACING_OK checks=%d failures=%d" % [checks,failures]);quit(failures)
