extends "res://tests/nightfall_bonus_route_choices.gd"
## Independent production scene/input/combat acceptance. Precision explicitly
## uses5000 parts, extended phases, stationed hero/squad, paidV upgrade,
## one guard cooldown reset, low-health/shield hero and real100000-damage
## casualties; unrelated enemies may be removed. Natural branches preserve
## original90/105/90, source/actor positions, native stats and earned wallet.
## Capture lighting alone is controlled. Neither section proves human balance.

const GUARD_ROOT_OBSERVER := ROUTE_ROOT_OBSERVER+"""
var observed_creature_payments: Array[Dictionary] = []
func _on_creature_defeated(creature: BattleUnit, source: BattleUnit) -> void:
\tvar guard: bool=is_instance_valid(creature) and bool(creature.get_meta('supply_cache_guard',false))
\tvar token: int=creature.get_instance_id() if is_instance_valid(creature) else -1
\tvar before: int=scrap
\tvar old_kills: int=kills
\tvar chain: int=kill_chain
\tvar resolving: bool=player_attack_resolving
\tsuper._on_creature_defeated(creature,source)
\tif kills!=old_kills:observed_creature_payments.append({'token':token,'guard':guard,'source':source.get_instance_id() if is_instance_valid(source) else -1,'hero_source':source==hero,'resolving':resolving,'before':before,'after':scrap,'delta':scrap-before,'base':5 if phase=='day' else -1,'additional':scrap-before-5 if phase=='day' else -1,'chain_before':chain,'chain_after':kill_chain,'phase':phase,'time':phase_time,'kills_before':old_kills,'kills_after':kills})
"""

var damage_receipts: Array[Dictionary] = []
var day_guard_source: Dictionary = {}
var guard_step_max_ms := 0.0

func _initialize() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	render_test="--render-test" in args; output_dir="res://build/supply-cache-guards"
	var index: int=args.find("--output-dir")
	if index>=0:
		if index+1>=args.size():check(false,"Missing supply-cache evidence directory")
		else:
			var requested: String=ProjectSettings.globalize_path(args[index+1]).simplify_path()
			if safe_output_path(requested):output_dir=requested
			else:check(false,"Guard evidence must remain physically below local build")
	root.size=VIEWPORTS[0]; root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT; root.content_scale_size=VIEWPORTS[0]
	if DisplayServer.get_name()!="headless":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true); root.position=Vector2i(10000,10000); root.hide()
	evidence={"seed":SEED,"scope":"precision5000/extended phases/direct hero and squad positions/paidV upgrade/one guard cooldown reset/hero hp1 and shield0 fatal fixture/real100000-damage casualties/removed unrelated enemies; natural original90/105/90, native sources/actors/stats, earned wallet and realP/F/GUI; controlled capture lighting; no human or campaign balance claim","completed":[],"captures":[],"capture_receipt":[],"selection":[],"gate":[],"combat":[],"identity":[],"lifecycle":[],"hud":[],"economy":[],"encounters":[],"specialists":[],"paths":[]}
	create_timer(900.0,true,false,true).timeout.connect(watchdog); call_deferred("run")

func safe_output_path(candidate: String) -> bool:
	var allowed: String=ProjectSettings.globalize_path("res://build").simplify_path()
	if not candidate.begins_with(allowed+"/"):return false
	var current := "/"
	for part: String in candidate.split("/",false):
		var directory: DirAccess=DirAccess.open(current)
		if directory!=null and directory.is_link(part):return false
		current=current.path_join(part)
	return true

func watchdog() -> void:
	if finished:return
	check(false,"Supply-cache guard acceptance stalled in "+active_stage)
	await finalize(); finished=true; quit(1)

func fresh(is_precision: bool=true) -> void:
	await close_game(); precision=is_precision
	check(RunSession.queue_request(self,SEED,"siege"),"Guard run accepts the original fixed siege seed")
	var observer: GDScript=GDScript.new(); observer.source_code=GUARD_ROOT_OBSERVER
	check(observer.reload()==OK,"Read-only guard root observer forwards actual production death/payment handlers")
	var packed: PackedScene=load("res://scenes/nightfall.tscn").duplicate()
	var bundled: Dictionary=packed.get("_bundled").duplicate(true); var replaced := 0
	for index in bundled.variants.size():
		var value: Variant=bundled.variants[index]
		if value is Script and value.resource_path=="res://scripts/nightfall.gd":bundled.variants[index]=observer; replaced+=1
	check(replaced==1,"Observer replaces exactly one root before eager modules are constructed")
	packed.set("_bundled",bundled); game=packed.instantiate(); game.scene_file_path="res://scenes/nightfall.tscn"; root.add_child(game); current_scene=game
	for _frame in 5:await process_frame
	game.set_process(false); game.world.set_process(false); await install_route_observer(); await press(KEY_1)
	check(game.phase=="night" and game.phase_time==105.0 and game.scrap==90 and game.tower_count()==2 and game.run.seed_value==SEED,"Guard opening preserves original90 parts/two towers/105-second night")
	elapsed=0.0; hurt_events.clear(); death_events.clear(); gate_tokens.clear(); damage_receipts.clear(); day_guard_source.clear(); guard_step_max_ms=0.0
	game.hero.damage_confirmed.connect(observe_damage)
	if precision:
		game.scrap=5000; game.phase_time=10000.0; game.wave_index=game.WAVES_PER_NIGHT
		clear_enemies(); suspend_defense(); stand(HOME)
	check(is_instance_valid(game.discoveries.cache_guards),"Actual production discoveries own the guard module")

func observe_damage(victim: BattleUnit, source: BattleUnit, hp_loss: float, shield_loss: float) -> void:
	damage_receipts.append({"victim":victim.get_instance_id(),"source":source.get_instance_id() if is_instance_valid(source) else -1,"guard":is_instance_valid(source) and bool(source.get_meta("supply_cache_guard",false)),"hp":hp_loss,"shield":shield_loss,"at":elapsed,"phase":game.phase,"time":game.phase_time})

func guards() -> Array[BattleUnit]:
	var result: Array[BattleUnit]=[]
	if not is_instance_valid(game):return result
	for value: Variant in game.enemies:
		if living(value) and bool(value.get_meta("supply_cache_guard",false)) and game.discoveries.cache_guards.owns(value):result.append(value as BattleUnit)
	return result

func guard_snapshot(index: int=-1) -> Dictionary:
	if index>=0:return game.discoveries.cache_guards.snapshot(index)
	for candidate in game.discoveries.items.size():
		var info: Dictionary=game.discoveries.cache_guards.snapshot(candidate)
		if bool(info.get("guarded",false)):return info
	return game.discoveries.cache_guards.snapshot(-1)

func guarded_item() -> Dictionary:
	var info: Dictionary=guard_snapshot()
	if not bool(info.get("guarded",false)):return {}
	var index: int=int(info.get("index",-1))
	return game.discoveries.items[index] if index>=0 and index<game.discoveries.items.size() else {}

func require_guards(expected: int, label: String) -> bool:
	var count: int=guards().size()
	check(count==expected,label+" requires exactly"+str(expected)+" living registered actors; actual="+str(count))
	return count==expected

func state() -> Dictionary:
	var result: Dictionary=super.state()
	result.cache_guards=plain(guard_snapshot())
	return result

func remove_unrelated_enemies() -> void:
	game.clear_lobbers(); game.clear_summoners(); game.clear_warders(); game.clear_focus(); game.cancel_hero_attack()
	for value: Variant in game.enemies.duplicate():
		if not is_instance_valid(value):continue
		if game.discoveries.cache_guards.owns(value):continue
		game.enemies.erase(value); value.queue_free()

func ready_guards(with_ranged: bool=false) -> Dictionary:
	await fresh()
	var group: Dictionary={}
	if with_ranged:
		await build_gui("barracks",BARRACKS); group=await train("ranged")
	game.finish_night(); await press(KEY_1)
	check(game.phase=="day" and game.day_number==2 and game.phase_time==90.0,"Actual dawn deploys guards in the original first ninety-second daylight")
	game.phase_time=10000.0; remove_unrelated_enemies(); suspend_defense(); stand(HOME)
	var info: Dictionary=guard_snapshot(); var item: Dictionary=guarded_item()
	check(not item.is_empty() and guards().size()==2 and bool(info.get("blocked",false)),"Actual original seeded dawn selects one real cache and registers exactly two live guards")
	day_guard_source=item
	return group

func step(delta: float=STEP, _freeze_enemy: bool=true) -> void:
	var previous: Dictionary={}
	for unit: BattleUnit in guards():previous[unit.get_instance_id()]={"position":unit.position,"speed":unit.speed}
	if precision:suspend_defense()
	var start: int=Time.get_ticks_usec(); game.simulate(delta); guard_step_max_ms=maxf(guard_step_max_ms,float(Time.get_ticks_usec()-start)/1000.0); elapsed+=delta
	for unit: BattleUnit in guards():
		if not previous.has(unit.get_instance_id()):continue
		var before: Dictionary=previous[unit.get_instance_id()]
		check(unit.position.is_finite() and game.outpost_walkable(unit.position) and absf(unit.position.y-game.outpost_height(unit.position))<.001 and game.can_traverse(before.position,unit.position) and planar(before.position,unit.position)<=maxf(float(before.speed),unit.speed)*delta+.002,"Every actual guard step is finite, grounded, walkable and native-speed bounded")

func selection_case() -> void:
	await ready_guards()
	var info: Dictionary=guard_snapshot(); var item: Dictionary=guarded_item()
	if item.is_empty() or not require_guards(2,"Selection fixture"):return
	for key: String in ["guarded","blocked","remaining","killed","lost","cleared","anchor","index","serial"]:check(info.has(key),"Guard snapshot exposes "+key)
	check(String(item.kind)=="supply_cache" and String(item.state)=="ready" and int(item.serial)==int(info.serial) and item.position==info.anchor,"Guard anchor binds the authoritative original ready cache generation")
	var return_point := Vector3(0,5,4.6)
	var selected_distance: float=game.discoveries.route_distance(return_point,item.position); var farthest := -1.0
	for candidate: Dictionary in game.discoveries.items:
		if String(candidate.kind)!="supply_cache" or String(candidate.state)!="ready":continue
		var distance: float=game.discoveries.route_distance(return_point,candidate.position)
		if is_finite(distance) and distance>=30.0 and distance<=90.0:farthest=maxf(farthest,distance)
	check(selected_distance>=30.0 and selected_distance<=90.0 and is_equal_approx(selected_distance,farthest),"Dawn selects the farthest actually reachable existing cache in the30–90-metre home route band")
	for unit: BattleUnit in guards():
		check(unit.hp==137.0 and unit.max_hp==137.0 and unit.damage==13.0 and unit.speed==2.3 and unit.armor==0.0 and unit.attack_range==1.6 and unit.attack_interval==1.1,"Each real guard retains first-day native day-creature health/damage/speed/armor/range/cooldown")
		check(planar(unit.position,item.position)<=4.5 and game.outpost_walkable(unit.position) and not bool(unit.get_meta("day_hunter",false)),"Guard visibly starts on real nearby walkable ground without global day-hunter pursuit")
	var before: Dictionary=state()
	for _read in 30:
		guard_snapshot(); game.discoveries.cache_guards.target_for(guards()[0]); game.contracts.bonus_route_options()
	check(state()==before,"Repeated snapshot/target/budget reads preserve clocks, wallet, all RNG streams and actors")
	game.discoveries.cache_guards.begin_day()
	check(guards().size()==2 and state()==before,"A repeated same-day begin cannot clone guards or consume extra random/wallet state")
	evidence.selection.append({"guard":plain(info),"distance":selected_distance,"farthest":farthest,"members":plain(guards())})
	await camera_cache(); await capture("guarded-cache-deployed")
	stage_returned=true

func camera_cache() -> void:
	var item: Dictionary=guarded_item()
	if not item.is_empty():camera_at(item.position)

func gate_case() -> void:
	await ready_guards(); var item: Dictionary=guarded_item()
	if item.is_empty() or not require_guards(2,"Opening fixture"):return
	var index: int=int(guard_snapshot().index); stand(item.position)
	var before: int=game.scrap; var count: int=game.exploration_count
	check(game.discoveries.interaction_prompt().contains("守卫"),"Local realF prompt explains that the guarded cache is locked")
	check(not game.discoveries.interact_index(index) and item.state=="ready" and item.progress==0.0,"Direct index interaction cannot bypass the two living guards")
	await press(KEY_F)
	check(item.state=="ready" and game.scrap==before and game.exploration_count==count,"ActualF cannot start or pay a locked cache")
	var first: BattleUnit=guards()[0]; first.hurt(100000.0,game.hero)
	check(int(guard_snapshot().killed)==1 and int(guard_snapshot().remaining)==1 and bool(guard_snapshot().blocked) and game.scrap==before+5,"One genuine precision death pays original5 but keeps the box locked")
	var one_death: Dictionary=state(); game._on_creature_defeated(first,game.hero)
	check(state()==one_death and game.observed_creature_payments.size()==1,"A duplicate callback for the genuinely defeated first guard cannot replay5, kill credit or lock progress")
	check(not game.discoveries.interact_index(index) and item.state=="ready","One true casualty cannot open the box")
	if not require_guards(1,"After one genuine defeat"):return
	var second: BattleUnit=guards()[0]; second.hurt(100000.0,game.hero)
	check(int(guard_snapshot().killed)==2 and int(guard_snapshot().remaining)==0 and bool(guard_snapshot().cleared) and not bool(guard_snapshot().blocked) and game.scrap==before+10,"Only two real deaths clear the exact box and pay two original5 rewards")
	var payments: Array=game.observed_creature_payments.duplicate(true)
	check(payments.size()==2 and int(payments[0].delta)==5 and int(payments[1].delta)==5 and int(payments[0].additional)==0 and int(payments[1].additional)==0,"Precision actual death receipts separate day5 from hero chain credit")
	await press(KEY_F); check(item.state=="channel" and item.progress==0.0,"ActualF begins original three-second work after both guards are truly defeated")
	step(1.4); var opening: float=item.progress
	stand(item.position+Vector3(0,0,5)); step(.001)
	check(item.state=="ready" and item.progress==0.0 and game.scrap==before+10,"Leaving original four-metre channel range cancels partial opening without paying")
	stand(item.position); await press(KEY_F); step(2.99)
	check(item.state=="channel" and is_equal_approx(float(item.progress),2.99) and game.exploration_count==count and game.scrap==before+10,"A restarted cleared box still requires the complete original three seconds")
	step(.011)
	check(item.state=="cooling" and game.exploration_count==count+1,"Real full opening consumes exactly one source generation")
	var exploration: Array=game.observed_exploration_payments.duplicate(true)
	check(exploration.size()==1 and int(exploration[0].base)==46 and String(exploration[0].category)=="supply_cache" and game.scrap==before+10+int(exploration[0].delta),"Actual ordinary box base remains46 with separate exploration additions and guard5+5 ledger")
	var paid: int=game.scrap
	check(not game.discoveries.interact_index(index) and game.scrap==paid,"Direct repeat cannot pay the consumed same-generation cache twice")
	evidence.gate.append({"index":index,"serial":item.serial,"interrupted_progress":opening,"guard_payments":payments,"exploration":exploration,"before":before,"after":game.scrap})
	await camera_cache(); await capture("guarded-cache-cleared")
	# A cache outside the one selected guard generation keeps original rules.
	await ready_guards(); var selected: int=int(guard_snapshot().index); var unguarded := -1
	for candidate_index in game.discoveries.items.size():
		var candidate: Dictionary=game.discoveries.items[candidate_index]
		if candidate_index!=selected and candidate.kind=="supply_cache" and candidate.state=="ready":unguarded=candidate_index; break
	check(unguarded>=0,"Seeded precision scene contains another genuine unguarded cache")
	if unguarded<0:return
	item=game.discoveries.items[unguarded]; stand(item.position)
	check(game.discoveries.interact_index(unguarded) and item.state=="channel","Unselected original cache is still available without defeating remote guards")
	stage_returned=true

func combat_case() -> void:
	var group: Dictionary=await ready_guards(true); var item: Dictionary=guarded_item()
	if item.is_empty() or group.is_empty() or not require_guards(2,"Native combat fixture"):return
	var unit: BattleUnit=guards()[0]; var others: Array[BattleUnit]=guards()
	var origin: Vector3=unit.position
	stand(origin+Vector3(0,0,1.0)); await station_group(group,origin+Vector3(0,0,4.0))
	for member: BattleUnit in group.members:
		if living(member):member.attack_timer=100000.0; member.damage_confirmed.connect(observe_damage)
	var target: Dictionary=game.discoveries.cache_guards.target_for(unit)
	check(String(target.get("kind",""))=="hero","Guard selects the real nearest hero inside its fixed eight-metre cache anchor")
	await station_group(group,origin+Vector3(0,0,.6)); stand(origin+Vector3(0,0,4.0))
	target=game.discoveries.cache_guards.target_for(unit)
	check(String(target.get("kind",""))=="squad" and living(target.get("unit")),"Moving genuine paid members closer makes the guard select the nearest living squad member")
	var victim: BattleUnit=target.get("unit") as BattleUnit
	check(victim in group.members,"Guard never fabricates a troop target outside the actual paid roster")
	# The other native guard may prepare too; attribution filters this actor.
	step(.001,false)
	check(unit.attack_queued and is_equal_approx(unit.attack_windup,.34),"Actual root enemy loop starts the original full.34-second preparation")
	var hp: float=victim.hp; var source_token: int=unit.get_instance_id(); damage_receipts.clear()
	step(.338,false)
	var matching: Array=[]
	for row: Dictionary in damage_receipts:
		if int(row.source)==source_token:matching.append(row)
	check(unit.attack_queued and unit.attack_windup>0.0 and matching.is_empty(),"That guard cannot damage its real victim before the full native preparation")
	step(.003,false); matching.clear()
	for row: Dictionary in damage_receipts:
		if int(row.source)==source_token:matching.append(row)
	check(matching.size()==1 and int(matching[0].victim)==victim.get_instance_id() and is_equal_approx(float(matching[0].hp),13.0/(1.0+victim.armor*.01)) and float(matching[0].shield)==0.0 and unit.attack_timer>1.09,"Native guard commits one original13-damage hit after victim armor with real source attribution and cooldown")
	check(victim.hp<hp,"Actual guard combat reduces real paid troop health")
	# Move every real target beyond the fixed box anchor during a new preparation.
	unit.attack_timer=0.0; step(.001,false)
	check(unit.attack_queued,"Precision cooldown reset creates a real second full preparation for leash cancellation")
	var anchor: Vector3=guard_snapshot().anchor
	stand(anchor+Vector3(0,0,9.5)); await station_group(group,anchor+Vector3(0,0,11.0))
	var receipt_count: int=damage_receipts.size(); step(.001,false)
	check(not unit.attack_queued and unit.attack_windup==0.0 and String(game.discoveries.cache_guards.target_for(unit).get("kind","")) not in ["hero","squad"],"Crossing the fixed eight-metre box anchor cancels the incomplete attack and releases all real targets")
	await advance(1.0,false)
	check(damage_receipts.size()==receipt_count and planar(unit.position,anchor)<8.0 and game.beacon_hp==1200.0,"Native walkable return cannot hit a withdrawn unit or acquire the distant core")
	evidence.combat.append({"guard":source_token,"victim":victim.get_instance_id(),"native_hit":matching,"anchor":anchor,"returned_position":unit.position,"max_simulate_ms":guard_step_max_ms,"others":plain(others)})
	await camera_cache(); await capture("guard-targets-paid-troop")
	stage_returned=true

func station_group(group: Dictionary, point: Vector3) -> void:
	place_group(group,point); await select_group(group)
	var outcome: Dictionary=game.squads.command_guard(point)
	check(bool(outcome.get("ok",false)) and group.order=="guard","Paid precision members receive a real productionGUARD command at their explicit stationed center")

func identity_case() -> void:
	await ready_guards(); var item: Dictionary=guarded_item()
	if item.is_empty() or not require_guards(2,"Identity fixture"):return
	var index: int=int(guard_snapshot().index); var before: int=game.scrap
	var alive_actor: BattleUnit=guards()[0]; var live_state: Dictionary=state(); var old_payment_count: int=game.observed_creature_payments.size()
	game._on_creature_defeated(alive_actor,game.hero)
	check(state()==live_state and game.observed_creature_payments.size()==old_payment_count,"A forged defeat callback while a registered guard is still alive cannot grant5, run kills, or clear its box")
	await process_frame
	check(living(alive_actor) and not alive_actor.is_queued_for_deletion(),"The rejected live-guard callback cannot secretly queue its actor for removal on the next real frame")
	if not living(alive_actor) or not require_guards(2,"After rejected live callback"):return
	stand(alive_actor.position+Vector3(0,0,1)); step(.001,false)
	check(living(alive_actor) and alive_actor.attack_queued and is_equal_approx(alive_actor.attack_windup,.34) and game.scrap==before and int(guard_snapshot().killed)==0 and int(guard_snapshot().lost)==0,"After rejection and actual simulation the original living guard remains capable of a real full native preparation without rewards or lost credit")
	var vanished: BattleUnit=guards()[0]; var vanished_token: int=vanished.get_instance_id()
	game.enemies.erase(vanished); vanished.queue_free(); await process_frame; step(.001)
	check(not is_instance_id_valid(vanished_token) and int(guard_snapshot().lost)==1 and int(guard_snapshot().killed)==0 and int(guard_snapshot().remaining)==2 and bool(guard_snapshot().blocked),"Removing a registered actor without a true death records lost and leaves both required kills outstanding")
	stand(item.position); check(not game.discoveries.interact_index(index) and game.scrap==before,"Lost actor cannot be reinterpreted as a cleared guarded box or generate a reward")
	if not require_guards(1,"After genuine actor disappearance"):return
	var survivor: BattleUnit=guards()[0]; survivor.hurt(100000.0,game.hero)
	check(int(guard_snapshot().killed)==1 and int(guard_snapshot().lost)==1 and bool(guard_snapshot().blocked) and game.scrap==before+5,"The one remaining true death still cannot make a lost actor count as the second defeat")
	evidence.identity.append({"tag":"lost-not-dead","snapshot":plain(guard_snapshot()),"before":before,"after":game.scrap})
	await ready_guards(); item=guarded_item(); index=int(guard_snapshot().index)
	var old_guards: Array[BattleUnit]=guards(); var old_serial: int=item.serial; var old_position: Vector3=item.position
	item.serial+=1; game.discoveries.motivation_revision+=1; step(.001)
	check(not bool(guard_snapshot(index).get("guarded",false)) and guards().is_empty(),"A new serial at exactly the same cache position cannot inherit the old generation's guard lock")
	stand(item.position); check(game.discoveries.interact_index(index) and item.state=="channel","Authoritative new generation retains ordinary opening rules after old guard identity retires")
	var paid: int=game.scrap; var kills: int=game.kills
	for actor: BattleUnit in old_guards:
		if is_instance_valid(actor):game._on_creature_defeated(actor,game.hero)
	check(game.scrap==paid and game.kills==kills,"A retired guard callback cannot replay day income or run kill credit against its replacement")
	evidence.identity.append({"tag":"same-place-new-serial","index":index,"old_serial":old_serial,"new_serial":item.serial,"position":old_position})
	await ready_guards(); item=guarded_item(); index=int(guard_snapshot().index)
	var replacement: Dictionary=item.duplicate(false); game.discoveries.items[index]=replacement; step(.001)
	check(not bool(guard_snapshot(index).get("guarded",false)) and guards().is_empty(),"A different sourceDictionary with identical fields cannot adopt registered guard ownership")
	stage_returned=true

func lifecycle_case() -> void:
	await fresh(); game.finish_night()
	var first_spawn_state: int=game.spawn_rng.state
	await press(KEY_1)
	check(game.phase=="day" and guards().size()==2 and game.spawn_rng.state==first_spawn_state,"The first real begin_day deploys two native guard actors while restoring the existing spawn RNG stream exactly")
	evidence.lifecycle.append({"tag":"first-day-rng-preserved","spawn_state_before":first_spawn_state,"spawn_state_after":game.spawn_rng.state,"guard":plain(guard_snapshot())})
	await ready_guards(); var item: Dictionary=guarded_item()
	if item.is_empty() or not require_guards(2,"Lifecycle fixture"):return
	var unit: BattleUnit=guards()[0]; stand(unit.position+Vector3(0,0,1)); step(.001,false)
	check(unit.attack_queued,"Real guard has an incomplete attack before freezing")
	await press(KEY_ESCAPE); check(game.phase=="paused","ActualEscape pauses the original guarded daylight")
	var frozen: Dictionary=state(); game.simulate(2.0)
	check(state()==frozen,"Pause freezes exact guard attack preparation, movement, source lock, wallet and clock")
	await press(KEY_ESCAPE); check(game.phase=="day","ActualEscape resumes the same guard generation")
	var before_card_parts: int=game.scrap; await press(KEY_V)
	check(game.phase=="draft" and game.return_phase=="day" and game.scrap<before_card_parts,"ActualV spends the precision wallet on a legitimate upgrade and opens real selection cards")
	if game.phase!="draft":return
	evidence.lifecycle.append({"tag":"real-paid-selection-freeze","before":before_card_parts,"after":game.scrap,"paid":before_card_parts-game.scrap,"guard":plain(guard_snapshot())})
	frozen=state(); game.simulate(2.0)
	check(state()==frozen,"The real selection-card phase freezes guard preparation and source lock")
	await press(KEY_1); check(game.phase=="day","Actual selection key returns to the same daylight phase")
	var index: int=int(guard_snapshot().index); var before: int=game.scrap; var kills: int=game.kills
	game.phase_time=.01; step(.02,false)
	check(game.phase=="night" and guards().is_empty() and bool(guard_snapshot(index).blocked) and int(guard_snapshot(index).killed)==0 and not bool(guard_snapshot(index).cleared) and game.scrap==before and game.kills==kills,"Actual sunset retires living guards without paying, clearing, or unlocking the original uncompleted box")
	stand(item.position); check(not game.discoveries.interact_index(index),"Night interaction cannot bypass the same-generation box lock left by uncompleted guards")
	evidence.lifecycle.append({"tag":"sunset","snapshot":plain(guard_snapshot(index)),"before":before,"after":game.scrap})
	game.finish_night(); await press(KEY_1)
	check(game.phase=="day" and guards().size()==2,"The next actual dawn may select a fresh daily guarded challenge")
	var old_root: int=game.get_instance_id(); var tokens: Array=[]
	for actor: BattleUnit in guards():tokens.append(actor.get_instance_id())
	game.end_defeat("Explicit guard retry boundary"); check(guards().is_empty(),"Real defeat clears registered guarded actors immediately")
	await press(KEY_ENTER)
	for _frame in 240:
		if current_scene!=null and current_scene.get_instance_id()!=old_root:break
		await create_timer(.02,true,false,true).timeout
	check(current_scene!=null and current_scene.get_instance_id()!=old_root,"ActualEnter creates a new same-seed game root")
	if current_scene==null or current_scene.get_instance_id()==old_root:return
	game=current_scene as Node3D; game.set_process(false); game.world.set_process(false)
	for _frame in 5:await process_frame
	check(not is_instance_id_valid(old_root) and game.run.seed_value==SEED and game.scrap==90 and game.phase=="draft" and not bool(guard_snapshot().get("guarded",false)),"Real retry releases the old guard lock and preserves seed/original opening wallet")
	for token: int in tokens:check(not is_instance_id_valid(token),"Real retry releases each old registered guard actor")
	evidence.lifecycle.append({"tag":"same-seed-retry","parts":game.scrap,"phase":game.phase,"seed":game.run.seed_value})
	# A true native hit can synchronously clear the very binding advance() is
	# using. The precision hero health/shield fixture does not alter the guard.
	await ready_guards()
	if not require_guards(2,"Native fatal reentry fixture"):return
	unit=guards()[0]
	var lethal_tokens: Array=[]
	for actor: BattleUnit in guards():lethal_tokens.append(actor.get_instance_id())
	stand(unit.position+Vector3(0,0,1)); game.hero.hp=1.0; game.hero.shield=0.0
	var lethal_parts: int=game.scrap; var lethal_kills: int=game.kills; var lethal_source: int=unit.get_instance_id()
	step(.001,false); check(unit.attack_queued and is_equal_approx(unit.attack_windup,.34),"Real unmodified day guard begins its complete native preparation against the precision low-health hero")
	damage_receipts.clear(); step(.341,false)
	check(game.phase=="ended" and not game.hero.alive and guards().is_empty() and not bool(guard_snapshot().get("guarded",false)),"A real complete guard hit invokes synchronous end_defeat and releases the currently advancing binding without a stale access")
	check(game.scrap==lethal_parts and game.kills==lethal_kills,"Lethal hero shutdown cannot create an extra guard5 reward or run kill count")
	var lethal_hit := false
	for row: Dictionary in damage_receipts:
		if int(row.source)==lethal_source and int(row.victim)==game.hero.get_instance_id() and float(row.hp)>0.0:lethal_hit=true
	check(lethal_hit,"Fatal boundary is witnessed by actual native damage_confirmed attribution")
	for _frame in 4:await process_frame
	for token: int in lethal_tokens:check(not is_instance_id_valid(token),"Synchronous real hero defeat ultimately frees every retired guard actor")
	evidence.lifecycle.append({"tag":"native-guard-fatal-reentry","parts":game.scrap,"kills":game.kills,"phase":game.phase,"damage":damage_receipts.duplicate(true)})
	stage_returned=true

func select_guard_route() -> Dictionary:
	var index: int=int(guard_snapshot().get("index",-1)); var serial: int=int(guard_snapshot().get("serial",-1))
	for row: Dictionary in game.contracts.bonus_route_options():
		if int(row.index)==index and int(row.serial)==serial:return row
	return {}

func precision_primary() -> bool:
	await ready_guards()
	var found := false
	for seed_value in 200:
		game.contracts.setup(game,seed_value); game.contracts.on_day()
		if game.contracts.kind=="salvage":found=true; break
	check(found,"Explicit precision seed fixture finds an actual salvage primary without changing the guarded source")
	if not found:return false
	for target: Dictionary in game.contracts.targets.duplicate():
		stand(target.position); await press(KEY_F)
		check(bool(target.source.collected),"Precision primary still requires actualF on real authoritative salvage")
	check(game.contracts.status=="bonus_offer","Actual primary work opens the real optional route drawer")
	# Precision-only route fixture: keep the hero at a genuine walkable point
	# beside the authoritative guarded source so the existing three-card
	# shortlist observes its production distance. Natural economy never uses
	# this direct station; it walks from the original seeded actor position.
	var guarded: Dictionary=guarded_item()
	if not guarded.is_empty():
		stand(guarded.position+Vector3(0,0,3.0)); await redraw()
	game.contracts.clear_budget_cache(); return game.contracts.status=="bonus_offer"

func hud_case() -> void:
	if not await precision_primary():return
	var route: Dictionary=select_guard_route(); check(not route.is_empty(),"Existing shortlist contains the actual guarded generation after primary completion")
	if route.is_empty():return
	var budget: Dictionary=route.budget
	for key: String in ["guarded","guard_remaining","guard_blocked","guard_lost"]:check(budget.has(key),"The actual cached route budget exposes real "+key)
	check(bool(budget.guarded) and bool(budget.guard_blocked) and int(budget.guard_remaining)==2 and is_equal_approx(float(budget.action_seconds),3.0),"Guard risk is real source state and does not pretend a known combat duration or change opening seconds")
	await close_drawer(); clear_transients(); await redraw(); var default_rects: Array=game.hud.visible_hud_rects().duplicate(); var default_boxes: Array=game.hud.drawn_rects.duplicate()
	check(game.hud.detail_tab.is_empty(),"Default tactical drawer stays closed despite a real guarded cache")
	await open_contract(); await measure_routes("actual-guard-risk")
	var shown := false
	for row: Dictionary in game.hud.drawn_labels:
		if String(row.text).contains("守卫2") and String(row.text).contains("战斗另计"):shown=true
	check(shown,"Existing actual F3 route card explains two guards and excludes combat from travel estimates")
	await capture("f3-guard-risk")
	game.phase_time=8.0; await redraw(); await measure_routes("late-actual-guard-risk")
	var late_shown := false
	for row: Dictionary in game.hud.drawn_labels:
		if String(row.text).contains("守卫2") and String(row.text).contains("日落前难返家"):late_shown=true
	check(late_shown,"The actual time-tight F3 card combines true guards with the real insufficient round-trip budget")
	await capture("f3-guard-late-risk"); game.phase_time=10000.0; await redraw()
	check(game.select_bonus_route(int(route.index),int(route.serial)) and game.choose_bonus_route(1),"Actual guarded route can be deliberately selected and confirmed despite its optional combat risk")
	await redraw(); await measure_routes("confirmed-guard-risk"); await capture("f3-confirmed-guard-risk")
	check(game.contracts.return_budget_text(game.contracts.return_budget()).contains("守卫2"),"Confirmed real return budget keeps uncompleted guard risk visible")
	game.phase_time=8.0; await redraw(); await measure_routes("confirmed-late-guard-risk")
	var confirmed_late: String=game.contracts.return_budget_text(game.contracts.return_budget())
	check(confirmed_late.contains("守卫2") and confirmed_late.contains("战斗另计") and confirmed_late.contains("日落前难返家"),"The actual confirmed eight-second budget preserves both native guard risk and the truthful late return condition")
	var confirmed_drawn := ""
	for row: Dictionary in game.hud.drawer_labels:confirmed_drawn+=String(row.text)
	check(confirmed_drawn.contains("守卫2") and confirmed_drawn.contains("战斗另计") and confirmed_drawn.contains("日落前难返家"),"Real F3 confirmed late drawing includes the complete guard, excluded-combat and insufficient-return explanation")
	await capture("f3-confirmed-guard-late-risk"); game.phase_time=10000.0; await redraw()
	if not require_guards(2,"Lost-guard HUD fixture"):return
	var lost_actor: BattleUnit=guards()[0]
	game.enemies.erase(lost_actor); lost_actor.queue_free(); await process_frame; step(.001)
	await redraw(); await measure_routes("confirmed-lost-guard-risk")
	var lost_text: String=game.contracts.return_budget_text(game.contracts.return_budget())
	check(int(guard_snapshot().lost)==1 and bool(guard_snapshot().blocked) and lost_text.contains("箱仍锁"),"The actual confirmed budget states that a disappeared guard leaves the same-generation box locked")
	var lost_shown := false
	for row: Dictionary in game.hud.drawn_labels:
		if String(row.text).contains("守卫") and String(row.text).contains("箱仍锁"):lost_shown=true
	check(lost_shown,"Existing real F3 drawing actually shows the lost-guard locked-box explanation")
	await capture("f3-guard-lost-risk")
	await close_drawer(); clear_transients(); await redraw()
	var fixed: Array[Rect2]=game.hud.live_panel_rects()
	check(game.hud.detail_tab.is_empty(),"Closing the existing drawer leaves the tactical detail tab closed")
	check(not fixed.has(Rect2(24,112,540,622)),"Guard risk does not add the existing detail drawer to the persistent panel set")
	for rect: Rect2 in fixed:
		check(rect!=Rect2(24,112,540,622),"No persistent panel is the large contract drawer after guarded-risk close")
	stage_returned=true

func natural_tick() -> void:
	var previous: Dictionary={}
	for unit: BattleUnit in guards():previous[unit.get_instance_id()]={"position":unit.position,"speed":unit.speed}
	super.natural_tick()
	for unit: BattleUnit in guards():
		if not previous.has(unit.get_instance_id()):continue
		var before: Dictionary=previous[unit.get_instance_id()]
		check(unit.position.is_finite() and game.outpost_walkable(unit.position) and game.can_traverse(before.position,unit.position) and planar(before.position,unit.position)<=maxf(float(before.speed),unit.speed)*STEP+.002,"Natural original-stat guards use real walkable native-speed bounded motion")

func natural_begin() -> Dictionary:
	await fresh(false); await right(Vector3(0,5,10)); natural_gate_crossings.clear()
	for frame in 1100:
		if game.phase!="night":break
		natural_tick()
		if frame%100==99:await process_frame
	check(game.phase=="draft" and game.hero.alive and game.beacon_hp>0,"Natural original ninety-part105-second first night survives by the unchanged real skill policy")
	if game.phase!="draft":return {}
	var dawn: int=game.scrap; var kills: int=game.kills; await press(KEY_1)
	check(game.phase=="day" and game.phase_time==90.0 and game.scrap==dawn and guards().size()==2,"Natural dawn preserves earned wallet/ninety-second clock and actually deploys two original-stat guards")
	var info: Dictionary=guard_snapshot(); var item: Dictionary=guarded_item()
	if item.is_empty():return {}
	natural_sources.clear(); natural_primary.clear()
	for source: Dictionary in game.discoveries.items:natural_sources.append({"index":natural_sources.size(),"position":source.position,"kind":source.kind,"serial":source.serial,"node":source.node.get_instance_id()})
	var selected := -1
	for index in game.contracts.offers.size():
		if String(game.contracts.offers[index].kind)=="salvage":selected=index; break
	check(selected>=0,"Original seed offers an actual salvage primary; no fixture seed or targets are injected into natural economy")
	if selected<0:return {}
	await press(KEY_4+selected)
	for target: Dictionary in game.contracts.targets.duplicate():
		var original: Vector3=target.source.position; natural_primary.append({"index":target.index,"position":original,"collected":target.source.collected})
		check(await walk_natural_primary(original),"Natural realP reaches unchanged authoritative primary salvage")
		if game.phase!="day" or not game.hero.alive:return {}
		await press(KEY_F); check(bool(target.source.collected),"Natural realF completes the unchanged main field work")
	check(game.contracts.status=="bonus_offer","Natural main completion reaches optional exploration decision")
	if game.contracts.status!="bonus_offer":return {}
	await close_drawer(); await press(KEY_P)
	for frame in 150:
		if not select_guard_route().is_empty() or game.phase!="day":break
		natural_tick()
		if frame%50==49:await process_frame
	await right(game.hero.position)
	var route: Dictionary=select_guard_route(); check(not route.is_empty(),"Natural three-card production shortlist exposes the genuine guarded generation without adding a fourth candidate")
	if route.is_empty():return {}
	await open_contract(); var slot: int=route_slot(int(route.index),int(route.serial)); check(slot>=0,"Natural actual F3 drawer contains the guarded source identity")
	if slot<0:return {}
	await click_ui(game.hud.bonus_route_rect(slot)); await press(KEY_5)
	check(game.contracts.status=="bonus_active" and int(game.contracts.bonus_target.index)==int(info.index) and int(game.contracts.bonus_target.serial)==int(info.serial),"Natural actualGUI/5 deliberately binds the unchanged guarded source")
	return {"dawn_parts":dawn,"night_kills":kills,"guard":plain(info),"route":plain(route),"source":item,"source_position":item.position,"source_serial":item.serial,"decision_at":90.0-game.phase_time,"decision_parts":game.scrap,"primary_reward":int(game.contracts.selected_reward.scrap),"death_start":game.observed_creature_payments.size(),"exploration_start":game.observed_exploration_payments.size()}

func natural_guard_branch(retreat: bool) -> void:
	var context: Dictionary=await natural_begin()
	if context.is_empty():return
	var item: Dictionary=context.source; var original: Vector3=context.source_position; var old_serial: int=context.source_serial
	damage_receipts.clear(); var reached := false
	await close_drawer(); await press(KEY_P)
	for frame in 900:
		if game.phase!="day" or not game.hero.alive:break
		if planar(game.hero.position,original)<3.0:reached=true; break
		natural_tick()
		if frame%100==99:await process_frame
	check(reached and item.position==original and item.node.position==original and int(item.serial)==old_serial,"Natural realP reaches the original guarded box without source relocation or generation replacement")
	if not reached:return
	await right(game.hero.position); await camera_cache(); await capture("natural-retreat-arrival" if retreat else "natural-clear-arrival")
	var real_hit := false
	for frame in 250:
		if game.phase!="day" or not game.hero.alive:break
		for row: Dictionary in damage_receipts:
			if bool(row.guard) and float(row.hp)+float(row.shield)>0.0:real_hit=true
		if retreat and real_hit:break
		if not retreat and bool(guard_snapshot().get("cleared",false)):break
		if not retreat:
			var alive: Array[BattleUnit]=guards()
			if not alive.is_empty():game.aim=alive[0].position; game.cast(0)
		natural_tick()
		if frame%100==99:await process_frame
	var at_decision: Dictionary=plain(guard_snapshot()); var after_fight: int=game.scrap
	if retreat:
		check(real_hit and bool(guard_snapshot().blocked),"Natural retreat is triggered by a real guarded attack while the original box remains locked")
		check(not game.discoveries.interact_index(int(context.guard.index)) and item.state=="ready","Actually injured retreat cannot collect the still-guarded optional cache")
		await right(ROUTE_HOME)
	else:
		check(bool(guard_snapshot().cleared) and int(guard_snapshot().killed)==2 and int(guard_snapshot().lost)==0,"Natural combat clears both real guards through genuine defeats without removal or attribute changes")
		if not bool(guard_snapshot().cleared):return
		await press(KEY_F); check(item.state=="channel","Natural realF starts the original full cache opening only after actual combat clears it")
		var started: float=game.phase_time
		while game.phase=="day" and item.state=="channel":natural_tick()
		check(game.contracts.bonus_done and item.state=="cooling" and started-game.phase_time>=2.999,"Natural collected source completes three actual seconds and becomes the real contract return payload")
		await press(KEY_P)
	var returned := false
	for frame in 900:
		if game.phase!="day" or not game.hero.alive:break
		if planar(game.hero.position,ROUTE_HOME)<.25:returned=true; break
		natural_tick()
		if frame%100==99:await process_frame
	check(returned and game.hero.alive and game.beacon_hp>0,"Natural original-stat hero returns through the real south gate after the chosen risk response")
	if retreat:
		check(game.observed_contract_payments.is_empty() and not game.contracts.bonus_done,"Confirmed unfinished optional mission does not pay the main guarantee immediately upon retreating home")
		await right(game.hero.position)
		for frame in 1000:
			if game.phase!="day":break
			natural_tick()
			if frame%100==99:await process_frame
		check(game.phase=="night" and game.contracts.status=="completed","Natural untouched original ninety-second day reaches sunset settlement after retreat")
	else:
		for _frame in 5:
			if game.contracts.status=="completed":break
			natural_tick()
		check(game.contracts.status=="completed","Natural return actually settles the completed optional delivery")
	var combat: Array=[]; var guard_base := 0; var chain_income := 0; var other_combat := 0
	for index in range(int(context.death_start),game.observed_creature_payments.size()):
		var payment: Dictionary=game.observed_creature_payments[index]; combat.append(payment)
		if bool(payment.guard):guard_base+=5; chain_income+=int(payment.additional)
		else:other_combat+=int(payment.delta)
	var discoveries: Array=[]; var field_income := 0; var box_base := 0
	for index in range(int(context.exploration_start),game.observed_exploration_payments.size()):
		var payment: Dictionary=game.observed_exploration_payments[index]; discoveries.append(payment); field_income+=int(payment.delta)
		if String(payment.category)=="supply_cache" and planar(payment.position,original)<.001:box_base+=int(payment.base)
	var contracts: Array=game.observed_contract_payments.duplicate(true); var contract_income := 0
	for payment: Dictionary in contracts:contract_income+=int(payment.delta)
	check(contracts.size()==1,"Each natural risk response receives one genuine authoritative contract settlement")
	if retreat:check(box_base==0 and contract_income==int(context.primary_reward) and not bool(contracts[0].request.bonus) and contracts[0].phase=="day","Natural sunset retreat pays only original main guarantee, with no box46 or optional31")
	else:
		check(guard_base==10 and box_base==46 and bool(contracts[0].request.bonus) and contract_income==int(context.primary_reward)+31+(10 if bool(contracts[0].request.early_return) else 0),"Natural successful route retains guard5+5, ordinary box46 and separate actual optional31 plus eligible original early10")
	check(game.scrap==int(context.decision_parts)+guard_base+chain_income+other_combat+field_income+contract_income,"Natural final wallet reconciles every observed guard base, hero chain, other combat, field discovery and contract payment separately")
	evidence.economy.append({"retreat":retreat,"seed":SEED,"opening":90,"night_seconds":105,"day_seconds":90,"dawn_parts":context.dawn_parts,"night_kills":context.night_kills,"decision_parts":context.decision_parts,"decision_at":context.decision_at,"source_position":original,"source_serial":old_serial,"original_sources":natural_sources.duplicate(true),"primary":natural_primary.duplicate(true),"guard_at_decision":at_decision,"after_fight_parts":after_fight,"real_guard_hit":real_hit,"damage_receipts":damage_receipts.duplicate(true),"combat_payments":combat,"guard_base":guard_base,"hero_chain_income":chain_income,"other_combat":other_combat,"box_base":box_base,"field_income":field_income,"exploration_payments":discoveries,"contract_income":contract_income,"contract_payments":contracts,"primary_reward":context.primary_reward,"final_parts":game.scrap,"remaining":game.phase_time,"phase":game.phase,"hero_hp":game.hero.hp,"beacon_hp":game.beacon_hp,"gate_crossings":natural_gate_crossings.duplicate(true),"scope":"fixed original seed90/105/90; genuine mainP/F and actualGUI/5, guard combat/opening/return or injured retreat; no funding, source/actor placement, enemy deletion/stat changes or extended clocks; not human balance"})
	print("CACHE_GUARD_NATURAL retreat=",retreat," guard_base=",guard_base," chain=",chain_income," box_base=",box_base," contract=",contract_income," returned=",returned," parts=",game.scrap," phase=",game.phase)
	await capture("natural-retreat-settlement" if retreat else "natural-clear-delivery")

func economy_case() -> void:
	await natural_guard_branch(false); await natural_guard_branch(true)
	check((evidence.economy as Array).size()==2,"Both original-seed natural risk responses produce complete real ledgers")
	stage_returned=true

func finalize() -> void:
	await close_game(); await create_timer(.5,true,false,true).timeout; evidence.shutdown_audio_drain_seconds=.5
	check(not is_instance_valid(game) and current_scene==null,"Final guard scene cleanup completes before publishing suite success")
	var folder: String=ProjectSettings.globalize_path(output_dir).simplify_path()
	check(safe_output_path(folder),"Final evidence directory still remains physically below local build")
	if not safe_output_path(folder):return
	check(DirAccess.make_dir_recursive_absolute(folder)==OK,"Actual local guard evidence directory is available")
	var file: FileAccess=FileAccess.open(folder.path_join("nightfall-supply-cache-guards.json"),FileAccess.WRITE)
	check(file!=null,"Guard result opens below local build")
	var receipt: FileAccess=FileAccess.open(folder.path_join("capture-receipt.json"),FileAccess.WRITE)
	check(receipt!=null,"Guard capture receipt opens below local build")
	evidence.checks=checks; evidence.failures=failures
	if file!=null:file.store_string(JSON.stringify(evidence,"\t")); file.close()
	if receipt!=null:receipt.store_string(JSON.stringify({"captures":evidence.capture_receipt,"completed":evidence.completed,"checks":checks,"failures":failures},"\t")); receipt.close()

func run() -> void:
	var cases: Dictionary={"selection":selection_case,"gate":gate_case,"combat":combat_case,"identity":identity_case,"lifecycle":lifecycle_case,"hud":hud_case,"economy":economy_case}
	var args: PackedStringArray=OS.get_cmdline_user_args(); var selected: Array=cases.keys(); var index: int=args.find("--case")
	if index>=0:
		if index+1<args.size():selected=[args[index+1]]
		else:check(false,"Missing supply-cache case after --case"); selected=[]
	for name: String in selected:
		if not cases.has(name):check(false,"Unknown supply-cache case "+name); break
		active_stage=name; stage_returned=false; print("CACHE_GUARD_STAGE_BEGIN ",name)
		await (cases[name] as Callable).call()
		check(stage_returned,"Guard stage "+name+" reaches its explicit full-body completion marker")
		print("CACHE_GUARD_STAGE_END ",name," checks=",checks," failures=",failures.size()); evidence.completed.append(name)
		if not failures.is_empty():break
	if index<0:check((evidence.completed as Array)==cases.keys(),"The complete guard suite finishes all seven expected production stages")
	await finalize(); finished=true; print("CACHE_GUARD_RESULT checks=",checks," failures=",failures.size())
	if index<0 and (evidence.completed as Array)==cases.keys() and failures.is_empty():print("NIGHTFALL_SUPPLY_CACHE_GUARDS_OK checks=",checks)
	quit(0 if failures.is_empty() else 1)
