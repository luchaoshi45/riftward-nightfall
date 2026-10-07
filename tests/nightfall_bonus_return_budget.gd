extends SceneTree
## Artificial phase setup only; natural clearance and victory use real combat.
const TransitionFixture := preload("res://tests/nightfall_transition_fixture.gd")
## Actual scene/actions: asymmetric south-gate return, live ETA and honest rewards.
const Layout = preload("res://scripts/outpost_layout.gd")
const OUTER_HERO_X := Layout.FORT_TERRAIN_EDGE + .9
const OUTER_CACHE_X := OUTER_HERO_X + .5
## Actual graphics: -- --render-test (hidden window and Dummy audio).
const HOME := Vector3(0,5,3.1)
const STEP := 0.05
const HUD_CONTENT_WIDTH := 530.0
var game: Node3D
var failures: Array[String] = []
var render_test := false
var observed_ratio := 0.0
var observed_queries := 0
var observed_full_pool_queries := 0
var observed_travel := 0.0

func _initialize() -> void:
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
		root.hide()
	render_test="--render-test" in OS.get_cmdline_user_args()
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if condition:return
	failures.append(message)
	push_error(message)

func press(code: int) -> void:
	var event:=InputEventKey.new()
	event.keycode=code;event.pressed=true
	game._unhandled_input(event)
	event.pressed=false
	game._unhandled_input(event)

func clear_enemies() -> void:
	for unit in game.enemies:
		if is_instance_valid(unit):unit.queue_free()
	game.enemies.clear()

func put_hero(point: Vector3) -> void:
	point.y=game.outpost_height(point)
	game.hero.position=point
	game.hero_path.clear()
	game.move_goal=point

func boot_day() -> bool:
	game=load("res://scenes/nightfall.tscn").instantiate()
	root.add_child(game);current_scene=game
	await process_frame
	game.set_process(false)
	game.world.set_process(false)
	check(game.choose_card(0) and game.phase=="night", "The actual opening choice must enter night")
	clear_enemies()
	game.run.seed_value=0
	game.contracts.setup(game,0)
	TransitionFixture.finish_for_fixture(game)
	check(game.phase=="draft" and game.day_number==2, "The first night must reach the real dawn draft")
	check(game.choose_card(0) and game.phase=="day", "The actual dawn choice must create the production day")
	clear_enemies()
	check(game.contracts.has_method("return_budget"), "Production contracts must provide return_budget")
	return game.phase=="day" and game.contracts.has_method("return_budget")

func close_game() -> void:
	if not is_instance_valid(game):return
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await create_timer(0.5).timeout

func only_discovery(kind: String, point: Vector3) -> Dictionary:
	# Reserve one authoritative scene resource, with a real channel/model, rather
	# than a stand-in reward or a mocked navigation service.
	for item: Dictionary in game.discoveries.items:
		game.discoveries.begin_cooling(item,600.0)
	var source: Dictionary=game.discoveries.items[0]
	point.y=game.outpost_height(point)
	source.kind=kind;source.position=point;source.node.position=point
	source.state="ready";source.progress=0.0;source.serial+=1
	game.discoveries.replace_model(source)
	game.discoveries.motivation_revision+=1
	return source

func budget() -> Dictionary:
	var result: Dictionary=game.contracts.return_budget()
	for key: String in ["available","candidate","outbound_distance","return_distance","action_seconds","total_seconds","spare_seconds","risk"]:
		check(result.has(key), "Return budget must expose its %s field" % key)
	return result

func assert_hud_width(value: Dictionary) -> void:
	var text: String=game.contracts.return_budget_text(value)
	var width: float=game.hud.font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x
	check(not text.is_empty() and width<=HUD_CONTENT_WIDTH, "Budget text must fit the 570px HUD panel with its 20px side margins: %.1fpx / %s" % [width,text])

func capture(name: String, value: Dictionary) -> void:
	assert_hud_width(value)
	if not render_test:return
	if DisplayServer.get_name()=="headless":
		check(false, "--render-test requires actual graphics, not headless")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
	game.world.night_mix=0.0;game.world.apply_lighting()
	game.camera.size=31.0
	game.camera.position=game.hero.position+Vector3(0,25,29)
	game.camera.look_at(game.hero.position)
	game.hud.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var path: String="res://build/nightfall-bonus-budget-%s.png" % name
	check(root.get_texture().get_image().save_png(path)==OK, "The actual %s budget HUD screenshot must save" % name)

func check_geometry_and_live_state() -> void:
	if not await boot_day():await close_game();return
	game.contracts.status="bonus_offer"
	for side: float in [-1.0,1.0]:
		put_hero(Vector3(side*OUTER_HERO_X,0,-6.0))
		only_discovery("supply_cache",Vector3(side*OUTER_CACHE_X,0,-6.0))
		game.contracts.bonus_candidate(true)
		var value:=budget()
		check(bool(value.get("available",false)), "The adjacent exterior cache must be a real available bonus")
		var outward: float=float(value.get("outbound_distance",INF))
		var inward: float=float(value.get("return_distance",0.0))
		check(outward>0.0 and outward<0.6, "The exterior discovery must be only half a metre from the hero")
		observed_ratio=maxf(observed_ratio,inward/maxf(outward,0.001))
		check(inward>=outward*32.0, "Return must follow the south gate rather than duplicating the short outbound leg")
		check(not game.can_traverse(game.discoveries.items[0].position,HOME), "The asymmetric fixture must really be separated from home by fortress walls")
		check(is_equal_approx(float(value.get("action_seconds",-1.0)),3.0), "A ready supply cache must count its actual three-second channel once")
		check(absf(float(value.get("total_seconds",0.0))-(outward+inward)/game.hero.speed-3.0)<0.01, "Total ETA must combine actual outward and home paths with one cache action")
	for kind: String in ["ember_bloom","memory_crystal","waylight"]:
		only_discovery(kind,Vector3(OUTER_CACHE_X,0,-6.0))
		game.contracts.bonus_candidate(true)
		check(is_zero_approx(float(budget().get("action_seconds",-1.0))), "Instant %s discovery must not invent a channel delay" % kind)
	var cache:=only_discovery("supply_cache",Vector3(OUTER_CACHE_X,0,-6.0))
	game.contracts.bonus_candidate(true)
	press(KEY_5)
	check(game.contracts.status=="bonus_active", "The real 5 input must bind the selected bonus")
	put_hero(cache.position)
	press(KEY_F)
	check(cache.state=="channel", "The real F input must start the selected cache's actual channel")
	for _step in 20:game.simulate(STEP)
	var opened:=budget()
	check(absf(float(opened.get("action_seconds",-1.0))-2.0)<0.02, "One second of real opening must leave two seconds in the budget")
	var normal_speed: float=game.hero.speed
	var normal_total: float=float(opened.get("total_seconds",0.0))
	var remaining_action: float=float(opened.get("action_seconds",0.0))
	game.hero.speed=normal_speed*2.0
	var faster:=budget()
	check(absf(float(faster.get("total_seconds",0.0))-(normal_total-remaining_action)*0.5-remaining_action)<0.01, "Live speed changes must affect the cached travel estimate immediately")
	game.hero.speed=normal_speed
	var total: float=float(budget().get("total_seconds",0.0))
	game.phase_time=total+20.0
	var safe:=budget()
	check(String(safe.get("risk",""))=="ready", "Twenty spare seconds must show a safe return")
	await capture("safe",safe)
	game.phase_time=total+4.0
	var tight:=budget()
	check(String(tight.get("risk",""))=="tight", "Four spare seconds must warn that preparation time is tight")
	await capture("tight",tight)
	game.phase_time=maxf(0.1,total-0.5)
	var late:=budget()
	check(String(late.get("risk",""))=="late" and float(late.get("spare_seconds",1.0))<0.0, "A shorter day clock must warn that the extra reward cannot return before dusk")
	await capture("late",late)
	game.phase_time=90.0
	for phase: String in ["paused","draft"]:
		var frozen_progress: float=cache.progress
		var frozen_clock: float=game.phase_time
		var frozen_queries: int=game.contracts.budget_route_queries
		game.phase=phase
		game.simulate(10.0);game.contracts.tick(10.0)
		var frozen:=budget()
		check(game.phase_time==frozen_clock and cache.progress==frozen_progress, "%s must freeze real opening and the daylight clock" % phase)
		check(game.contracts.budget_route_queries==frozen_queries and is_equal_approx(float(frozen.get("total_seconds",0.0)),total), "%s must preserve the cached path and return estimate" % phase)
		game.phase="day"
	# No remaining target is reachable; this is not a zero-cost safe excursion.
	game.contracts.status="bonus_offer";game.contracts.bonus_target.clear()
	only_discovery("supply_cache",Vector3(180,0,180))
	game.contracts.bonus_candidate(true)
	var blocked:=budget()
	check(not bool(blocked.get("available",true)) and String(blocked.get("risk",""))=="unreachable", "An unreachable source must never advertise a safe zero-second budget")
	assert_hud_width(blocked)
	await close_game()

func check_query_cadence() -> void:
	if not await boot_day():await close_game();return
	game.contracts.status="bonus_offer"
	put_hero(Vector3(OUTER_HERO_X,0,-6.0))
	only_discovery("supply_cache",Vector3(OUTER_CACHE_X,0,-6.0))
	game.contracts.bonus_candidate(true)
	budget()
	var before_queries: int=game.contracts.budget_route_queries
	for _frame in 120:
		game.contracts.tick(1.0/60.0)
		budget();budget()
		game.contracts.bonus_candidate()
	observed_queries=game.contracts.budget_route_queries-before_queries
	check(observed_queries<=10, "120 repeated HUD-budget frames must use at most ten A* queries for the one exterior candidate, got %d" % observed_queries)
	var expired_queries: int=game.contracts.budget_route_queries
	game.contracts.tick(0.29)
	budget()
	check(game.contracts.budget_route_queries>expired_queries, "Live simulation must refresh path geometry after the bounded cache interval")
	# Exercise the full HUD pool across the actual walls as well as the cheap
	# one-target case. Every candidate now needs an outward A* route from home.
	put_hero(HOME)
	for index in game.discoveries.items.size():
		var item: Dictionary=game.discoveries.items[index]
		var point:=Vector3(Layout.FORT_TERRAIN_EDGE+.5+index*0.4,0,-6.0-float(index%3)*2.0)
		point.y=game.outpost_height(point)
		item.position=point;item.node.position=point;item.state="ready";item.progress=0.0
	game.discoveries.motivation_revision+=1
	game.contracts.bonus_candidate(true)
	budget()
	before_queries=game.contracts.budget_route_queries
	for _frame in 120:
		game.contracts.tick(1.0/60.0)
		var value:=budget()
		game.contracts.return_budget_text(value)
		game.contracts.bonus_summary()
		budget()
	observed_full_pool_queries=game.contracts.budget_route_queries-before_queries
	var query_limit: int=(game.discoveries.items.size()+1)*9
	check(observed_full_pool_queries>0 and observed_full_pool_queries<=query_limit, "120 HUD frames with all wall-separated candidates must refresh in bounded batches: %d queries / %d allowed" % [observed_full_pool_queries,query_limit])
	await close_game()

func complete_primary_salvage() -> bool:
	var found:=false
	for seed in 200:
		game.contracts.setup(game,seed)
		game.contracts.on_day()
		if game.contracts.kind=="salvage":found=true;break
	check(found, "A production seed must expose a real two-cache primary contract")
	if not found:return false
	for target: Dictionary in game.contracts.targets.duplicate():
		put_hero(target.position)
		press(KEY_F)
		check(bool(target.source.collected), "Actual F must collect each authoritative primary cache")
	check(game.contracts.status=="bonus_offer", "Real primary field completion must open the extra-supply choice")
	return game.contracts.status=="bonus_offer"

func travel(destination: Vector3) -> bool:
	check(game.contract_goal().is_equal_approx(destination), "P must follow the actual accepted target or home")
	press(KEY_P)
	check(not game.hero_path.is_empty(), "Actual P input must create a traversable route")
	var elapsed:=0.0
	var stopped:=0
	while Vector2(game.hero.position.x-destination.x,game.hero.position.z-destination.z).length()>0.18:
		if game.phase!="day" or elapsed>30.0:
			check(false, "The real bonus route must arrive before dusk without endless movement")
			return false
		var before: Vector3=game.hero.position
		game.simulate(STEP)
		elapsed+=STEP
		check(game.can_traverse(before,game.hero.position), "Production movement must not cut across fortress walls")
		check(absf(game.hero.position.y-game.outpost_height(game.hero.position))<0.01, "Production movement must follow the south ramp's actual height")
		stopped=stopped+1 if before.distance_squared_to(game.hero.position)<0.000001 else 0
		if stopped>30:
			check(false, "The real bonus route must not stall at a fortress wall")
			return false
	game.move_goal=game.hero.position;game.hero_path.clear()
	observed_travel+=elapsed
	return true

func check_actual_delivery(dusk: bool) -> void:
	if not await boot_day():await close_game();return
	if not complete_primary_salvage():await close_game();return
	put_hero(Vector3(OUTER_HERO_X,0,-6.0))
	var cache:=only_discovery("supply_cache",Vector3(OUTER_CACHE_X,0,-6.0))
	game.contracts.bonus_candidate(true)
	press(KEY_5)
	check(game.contracts.status=="bonus_active", "Actual 5 must accept the extra cache after a real primary completion")
	var estimate:=budget()
	var predicted: float=float(estimate.get("total_seconds",0.0))
	var initial_clock: float=game.phase_time
	if not travel(cache.position):await close_game();return
	var before_open_scrap: int=game.scrap
	press(KEY_F)
	check(cache.state=="channel", "Actual F must open the marked extra cache")
	for _step in 62:game.simulate(STEP)
	check(game.contracts.bonus_done and game.contracts.status=="returning", "A genuinely opened extra cache must change P guidance to home")
	check(game.scrap>=before_open_scrap+40, "The real cache must retain its ordinary field supply reward")
	var before_reward: int=game.scrap
	var primary_scrap: int=game.contracts.selected_reward.scrap
	var extra_scrap: int=game.contracts.bonus_target.scrap
	if dusk:
		game.phase_time=0.01
		game.simulate(0.02)
		check(game.phase=="night" and game.contracts.status=="completed", "Actual dusk must preserve the completed primary contract")
		check(game.scrap==before_reward+primary_scrap, "Dusk must pay only the primary guarantee: an opened extra cache outside home earns no extra contract reward")
	else:
		if not travel(HOME):await close_game();return
		var actual: float=initial_clock-game.phase_time
		check(absf(actual-predicted)<=maxf(1.5,predicted*0.25), "Without combat, conservative path ETA must predict the actual P/F/gate return: %.2fs estimated, %.2fs actual" % [predicted,actual])
		check(game.contracts.status=="completed" and game.contracts.pending_reward.is_empty(), "Only genuine raised-ground home arrival may consume the extra payout")
		check(game.scrap==before_reward+primary_scrap+10+extra_scrap, "Early genuine delivery must pay primary, early return, and selected extra reward once")
		var returned:=budget()
		check(is_zero_approx(float(returned.get("action_seconds",-1.0))), "A delivered extra cache must not keep an opening delay")
	var paid_scrap: int=game.scrap
	for _repeat in 20:game.update_day_contracts(0.05);game.settle_contract_reward()
	check(game.scrap==paid_scrap, "Repeated production updates may never duplicate primary or extra payouts")
	await close_game()

func run() -> void:
	await check_geometry_and_live_state()
	await check_query_cadence()
	await check_actual_delivery(false)
	await check_actual_delivery(true)
	print("NIGHTFALL_BONUS_RETURN_BUDGET_", "OK" if failures.is_empty() else "FAILED", " asymmetric_ratio=",observed_ratio," queries_120_frames=",observed_queries," full_pool_queries=",observed_full_pool_queries," actual_travel=",observed_travel," live_speed channel_pause tight_late real_P_F_return dusk_guarantee", " rendered" if render_test else "")
	quit(0 if failures.is_empty() else 1)
