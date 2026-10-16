extends SceneTree
const Mender = preload("res://scripts/nightfall_mender.gd")
var game: Node3D
var checks := 0
var failures := 0
func _initialize() -> void:
 create_timer(90.0,true,false,true).timeout.connect(func(): quit(2))
 call_deferred("run")
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok:
  failures += 1
  push_error(message)
func spawn(role: String, point: Vector3) -> BattleUnit:
 var unit: BattleUnit = game.spawn_creature(true,role)
 unit.position = point
 unit.speed = 0.0
 unit.attack_timer = 100000.0
 return unit
func clean() -> void:
 game.clear_menders(); game.clear_warders(); game.clear_summoners(); game.clear_burstlings()
 for enemy: BattleUnit in game.enemies:
  if is_instance_valid(enemy): enemy.queue_free()
 game.enemies.clear()
func pack() -> Dictionary:
 clean()
 game.phase = "night"
 var source := spawn("mender",Vector3(0,0,32))
 var target := spawn("basic",Vector3(2,0,32))
 target.max_hp = 100.0
 target.hp = 60.0
 var control: Node3D = game.menders[0]
 source.position.y = game.outpost_height(source.position)
 target.position.y = game.outpost_height(target.position)
 return {"source":source,"target":target,"control":control}
func run() -> void:
 game = load("res://scenes/nightfall.tscn").instantiate()
 root.add_child(game); current_scene = game
 await process_frame
 game.set_process(false)
 game.archive.enabled = false
 game.phase = "night"
 var p := pack()
 var hp: float = p.target.hp
 var wallet: int = game.scrap
 var kills: int = game.kills
 var wave: int = game.wave_index
 check(p.source.title == "缝合者" and p.source.has_meta("mender_active"),"Production spawn identifies finite mender")
 p.control.advance(.001)
 check(p.control.snapshot().target == p.target and p.control.snapshot().phase == "windup", "Actual injured enemy locked by object")
 check(game.mender_warning_snapshot().size() == 1,"HUD reads actual channel")
 check(game.pending_mender_actions().get(p.source.get_instance_id(),false),"Windup blocks ordinary melee")
 p.control.advance(1.59)
 check(p.target.hp == hp and not p.source.moving,"No heal before full stationary windup")
 game.phase = "paused"
 p.control.advance(100.0)
 check(p.target.hp == hp and p.control.snapshot().casts == 0,"Pause freezes channel")
 game.phase = "draft"; p.control.advance(100.0)
 check(p.target.hp == hp,"Draft freezes channel")
 game.phase = "night"; p.control.advance(.02)
 check(game.scrap == wallet and game.kills == kills and game.wave_index == wave,"Healing neither pays currency nor changes deaths or wave accounting")
 check(is_equal_approx(p.target.hp,hp+24.0) and p.control.snapshot().casts == 1,"Completed channel writes actual 24 HP once")
 p.control.advance(7.9)
 check(p.control.snapshot().phase == "cooldown","Eight-second successful cooldown")
 p.control.advance(.11); p.control.advance(1.6)
 check(p.target.hp == p.target.max_hp and p.control.snapshot().casts == 2,"Second heal clamps to actual max HP")
 p.target.hp -= 30.0
 p.control.advance(100.0)
 check(p.target.hp == p.target.max_hp-30.0 and not p.source.get_meta("mender_active"),"Lifetime cap prevents third heal")
 p.control.setup(game,p.source); p.control.advance(100.0)
 check(p.control.snapshot().casts == 2 and p.control.snapshot().phase == "exhausted","Controller rebuild cannot replenish host budget")
 for rejection in ["range","height","roster","dead","full","control"]:
  p = pack(); hp = p.target.hp
  p.control.advance(.001)
  match rejection:
   "range": p.target.position.x = 8.0
   "height": p.target.position.y += 3.0
   "roster": game.enemies.erase(p.target)
   "dead": p.target.alive = false; p.target.hp = 0.0
   "full": p.target.hp = p.target.max_hp
   "control": game.specializations._nets[p.source.get_instance_id()] = {"unit":weakref(p.source),"remaining":2.0,"strength":.8}
  var before: float = p.target.hp
  p.control.revalidate_cast(); p.control.advance(1.6)
  check(p.target.hp == before and p.control.snapshot().casts == 0,"Interrupted "+rejection+" does not heal/debit")
  game.specializations.reset_effects()
  if rejection == "roster": p.target.queue_free()
 p = pack()
 p.target.set_meta("siege_boss",true)
 p.control.advance(.01)
 check(p.control.snapshot().phase == "idle","No healing boss")
 p.target.set_meta("siege_boss",false); p.target.set_meta("threat","mender")
 p.control.advance(.01)
 check(p.control.snapshot().phase == "idle","No mender mutual healing")
 p.target.set_meta("threat","basic"); p.target.hp=p.target.max_hp
 p.source.hp-=30
 p.control.advance(.01)
 check(p.control.snapshot().phase == "idle","No self healing")
 p = pack(); p.control.advance(.001)
 game.enemies.erase(p.source); p.control.advance(2.0)
 check(p.control.snapshot().casts == 0 and p.target.hp == p.target.max_hp-40,"Removed source cannot finish")
 p.source.queue_free()
 p = pack(); p.control.advance(.001)
 game.phase="day"; p.control.advance(2.0)
 check(p.control.host == null and not p.source.attack_queued,"Day clears incomplete cast")
 p = pack()
 var squad_id: int = game.squads._create_squad("shield",Vector3(0,5,3))
 var soldier: BattleUnit = game.squads.squads[squad_id].members[0]
 p.target.hp = p.target.max_hp
 game.squads.veterancy.observe_enemy(p.target)
 # Precision spawn observed original HP before its explicit max-HP fixture;
 # keep that original registered budget as the authoritative cap.
 var token: int = p.target.get_instance_id()
 var registered: Dictionary = game.squads.veterancy._enemies[token]
 var budget: float = registered.budget
 p.target.max_hp = budget
 p.target.hp = budget
 p.target.hurt(40.0,soldier)
 p.control.advance(.001); p.control.advance(1.6)
 check(is_equal_approx(p.target.hp,budget-16.0),"Real healing follows actual credited troop damage")
 p.target.hurt(10000.0,soldier)
 var xp: float = game.squads.veterancy.member_snapshot(soldier).xp
 check(is_equal_approx(xp,budget),"Real mender healing cannot enlarge original enemy XP budget")
 p = pack()
 p.source.position = Vector3(preload("res://scripts/outpost_layout.gd").FORT_INNER-.5,5,0)
 p.target.position = Vector3(preload("res://scripts/outpost_layout.gd").FORT_INNER+1.5,0,0)
 p.control.advance(.001)
 check(p.control.snapshot().phase == "idle" and p.target.hp == 60.0,"Real castle wall blocks healing despite planar range")
 p = pack()
 var hunter: Node3D = game.squads.hunters
 var summoner := spawn("summoner",p.source.position+Vector3(0,0,1))
 var warder := spawn("warder",p.source.position+Vector3(0,0,-1))
 check(hunter.bonus_target(p.source) and hunter._priority(summoner) < hunter._priority(p.source) and hunter._priority(p.source) < hunter._priority(warder),"Live mender hunter rank lies strictly between summoner and warder")
 p.source.set_meta("mender_active",false)
 check(not hunter.bonus_target(p.source) and hunter._priority(p.source) > hunter._priority(warder),"Spent mender loses hunter bonus and specialist priority")
 p = pack()
 p.control.advance(.001)
 p.source.hurt(10000.0,game.hero)
 p.control.advance(2.0)
 check(p.target.hp == 60.0 and p.control.snapshot().casts == 0,"Killed source cancels real channel without consuming budget")
 p = pack()
 p.target.hp = 90.0
 var second := spawn("mender",p.source.position+Vector3(0,0,1))
 var second_control: Node3D = game.menders[1]
 p.control.advance(.001); second_control.advance(.001)
 p.control.advance(1.6); second_control.advance(1.6)
 check(p.target.hp == 100.0 and p.control.snapshot().casts == 1 and second_control.snapshot().casts == 0,"Two actual sources recheck first completion; full target consumes no second cast")
 p = pack()
 game.hero.position = Vector3(0,5,3)
 game.hero.attack_timer = 100000.0; game.pulse_timer = 100000.0
 game.wave_index = game.WAVES_PER_NIGHT; game.phase_time = 10000.0
 game.gate_trap_charges = 0
 for pad: Dictionary in game.world.tower_pads: pad.cooldown = 100000.0
 for frame in 34: game.simulate(.05)
 check(is_equal_approx(p.target.hp,84.0) and p.control.snapshot().casts == 1,"Full production simulate advances actual channel and HP once")
 check(p.source.position == Vector3(0,game.outpost_height(Vector3(0,0,32)),32),"Full simulation channel keeps source stationary")
 clean()
 check(game.menders.is_empty() and game.mender_warning_snapshot().is_empty(),"Actual cleanup empties controller roster and warnings")
 await game.prepare_shutdown()
 game.queue_free(); current_scene=null
 for frame in 4: await process_frame
 await create_timer(.25,true,false,true).timeout
 print("NIGHTFALL_MENDER_OK checks=%d failures=%d" % [checks,failures])
 quit(0 if failures == 0 else 1)
