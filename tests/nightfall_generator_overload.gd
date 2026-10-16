extends SceneTree
var game: Node3D
var checks:=0
var failures:=0
func _initialize() -> void:
 create_timer(120.0,true,false,true).timeout.connect(func():quit(2))
 call_deferred("run")
func check(ok: bool,message: String) -> void:
 checks+=1
 if not ok:failures+=1;push_error(message)
func press_f() -> void:
 var event:=InputEventKey.new();event.keycode=KEY_F;event.physical_keycode=KEY_F;event.pressed=true
 root.push_input(event,true);event.pressed=false;root.push_input(event,true)
 await process_frame
func run() -> void:
 game=load("res://scenes/nightfall.tscn").instantiate();root.add_child(game);current_scene=game
 await process_frame
 game.set_process(false);game.archive.enabled=false;game.phase="day";game.phase_time=10000.0;game.run_mode="siege"
 var exp: Node3D=game.expeditions
 var over: RefCounted=exp.overload
 var site: Dictionary=exp.generators[0]
 # Controlled complete-site fixture; the original completion is separately verified.
 site.state="complete";site.progress=12.0
 game.hero.position=site.position;game.move_goal=site.position
 var wallet: int=game.scrap;var cells: int=game.generator_cells;var kills: int=game.kills;var rng: int=game.spawn_rng.state
 game.run_mode="teaching"
 check(over.prompt().is_empty() and not over.interact(),"Tutorial cannot enable optional overload")
 game.run_mode="siege"
 await press_f()
 check(not over.pending.is_empty() and over.trial.is_empty() and game.scrap==wallet,"First actual viewport F only confirms risk without spending or spawning")
 game.phase="paused";over.tick(10.0)
 check(over.confirmation==3.0,"Pause freezes three-second confirmation")
 game.phase="day";over.tick(3.1)
 check(over.pending.is_empty(),"Game-time confirmation expires")
 await press_f();await press_f()
 check(over.trial.get("state","")=="active" and over.trial.guards.size()==3,"Second actual F starts three real guards and separate trial")
 for guard: BattleUnit in over.trial.guards:
  check(guard.position.distance_to(game.hero.position)>=1.5,"Guard spawn does not overlap hero")
  for other: BattleUnit in over.trial.guards:
   if other!=guard:check(guard.position.distance_to(other.position)>=1.5,"Guard spawn points are distinct and spaced")
 check(game.spawn_rng.state==rng,"Independent overload random stream preserves original spawn RNG")
 check(site.state=="complete" and site.progress==12.0 and game.generator_cells==cells and game.scrap==wallet,"Starting overload preserves original completed state and rewards")
 check(not over.interact(),"Same day cannot trigger second trial")
 var guard_budget:=0.0
 var paid_id: int=game.squads._create_squad("shield",site.position)
 var paid_soldier: BattleUnit=game.squads.squads[paid_id].members[0]
 var guards: Array=over.trial.guards.duplicate()
 for enemy: BattleUnit in guards:
  guard_budget+=enemy.hp
  enemy.hurt(10000.0,paid_soldier)
 check(is_equal_approx(float(game.squads.veterancy.member_snapshot(paid_soldier).xp),minf(900.0,guard_budget)),"Actual finite guard HP gives troop experience once")
 check(over.trial.deaths.size()==3 and game.scrap==wallet and game.kills==kills,"Actual guard deaths pay no incidental cash, exploration or kill count")
 await process_frame
 await process_frame
 over.tick(11.9)
 check(game.scrap==wallet,"Full twelve-second hold required despite all guards dead")
 game.phase="draft";over.tick(100.0)
 check(over.trial.progress==11.9,"Selection freezes actual hold")
 game.phase="day";over.tick(.11)
 check(game.scrap==wallet+50 and over.trial.state=="won" and game.generator_cells==cells,"Complete hold plus genuine deaths awards exactly fifty once, no extra cell")
 over.tick(100.0)
 check(game.scrap==wallet+50,"Completion cannot pay twice")
 over.clear();game.day_number+=1
 over.interact();over.interact()
 check(over.trial.state=="active","Next day may elect one new overcharge")
 for member: BattleUnit in game.squads.squads[paid_id].members: member.position=site.position+Vector3(20,0,0)
 game.hero.position=site.position+Vector3(20,0,0)
 over.tick(.05)
 check(over.trial.is_empty() and over.day_used==game.day_number and site.state=="complete","Retreat cancels trial, consumes day choice, preserves original completion")
 game.hero.position=site.position;game.day_number+=1
 over.interact();over.interact()
 var lost: BattleUnit=over.trial.guards[0]
 game.enemies.erase(lost);over.tick(.05)
 check(over.trial.is_empty() and game.scrap==wallet+50,"Missing guard is not a death or reward")
 game.day_number+=1;over.interact();over.interact()
 var squad_id: int=game.squads._create_squad("shield",site.position)
 var soldier: BattleUnit=game.squads.squads[squad_id].members[0]
 for member: BattleUnit in game.squads.squads[squad_id].members: member.position=site.position+Vector3(0,0,8)
 game.squads.selected_ids.clear();game.squads.selected_ids.append(squad_id)
 check(game.squads.command_move(site.position).ok,"Real selected combat squad accepts original move command")
 var traveled:=0.0
 var previous: Vector3=soldier.position
 for frame in 160:
  game.squads.advance(.05)
  traveled+=soldier.position.distance_to(previous);previous=soldier.position
  if soldier.position.distance_to(site.position)<4.5:break
 check(traveled>3.0 and soldier.position.distance_to(site.position)<4.5,"Original squad advance walks real member into holding circle")
 game.hero.position=site.position+Vector3(20,0,0)
 over.tick(.1)
 check(not over.trial.is_empty() and over.trial.progress==.1,"Actual current combat troop can hold after hero leaves")
 game.phase="night";over.tick(.1)
 check(over.trial.is_empty() and game.scrap==wallet+50,"Night cancels without reversing original or paying bonus")
 game.phase="day";game.day_number+=1;game.hero.position=site.position
 over.interact();over.interact()
 var forged: BattleUnit=over.trial.guards[0]
 forged.alive=false;forged.hp=0.0
 forged.defeated.emit(forged,game.hero)
 check(over.trial.deaths.is_empty(),"Synthetic death without actual confirmed HP loss cannot clear trial")
 over.tick(.05)
 check(over.trial.is_empty(),"Unreceipted dead guard fails rather than awarding")
 game.day_number+=1;game.hero.position=site.position;game.move_goal=site.position
 for squad: Dictionary in game.squads.squads:
  for member: BattleUnit in squad.members:member.position=site.position+Vector3(20,0,0)
 over.interact();over.interact()
 var real_guard: BattleUnit=over.trial.guards[0]
 var start_point: Vector3=real_guard.position
 game.hero.attack_timer=100.0
 var real_damage:=[]
 game.hero.damage_confirmed.connect(func(_unit: BattleUnit,_source: BattleUnit,loss: float,_shield: float):real_damage.append(loss))
 for frame in 100:game.simulate(.05)
 check(not over.trial.is_empty() and over.trial.progress>0.0 and over.trial.progress<12.0,"Production simulate advances actual overload holding")
 check(real_guard.position.distance_to(start_point)>1.0,"Production simulate moves real overload guards")
 check(not real_damage.is_empty(),"Production simulate resolves actual guard attack damage")
 var terminal_wallet: int=game.scrap
 game.phase="ended";over.tick(.05)
 real_guard.defeated.emit(real_guard,game.hero)
 check(game.scrap==terminal_wallet,"Terminal and retired guard death signal cannot pay")
 game.phase="day";game.day_number+=1;over.interact();over.interact()
 var shutdown_guard: BattleUnit=over.trial.guards[0]
 game.shutting_down=true
 shutdown_guard.defeated.emit(shutdown_guard,game.hero)
 check(game.scrap==terminal_wallet,"Shutdown guard signal cannot pay")
 await game.prepare_shutdown()
 game.queue_free();current_scene=null
 for frame in 4:await process_frame
 await create_timer(.25,true,false,true).timeout
 print("NIGHTFALL_GENERATOR_OVERLOAD_OK checks=%d failures=%d" % [checks,failures])
 quit(0 if failures==0 else 1)
