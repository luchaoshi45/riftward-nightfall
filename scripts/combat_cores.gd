extends RefCounted
## Run-local behaviour cores. Mark timers use simulation time, never wall time.
var game: Node3D
var marks: Array[Dictionary] = []
var guard_ready: bool = false
var guard_time: float = 0.0

func setup(owner_game: Node3D) -> void:
	game=owner_game

func advance(delta: float) -> void:
	guard_time=maxf(0,guard_time-delta)
	for i in range(marks.size()-1,-1,-1):
		var enemy: BattleUnit=marks[i].enemy.get_ref()
		marks[i].time-=delta
		if not is_instance_valid(enemy) or not enemy.alive or marks[i].time<=0:
			if is_instance_valid(marks[i].ring):marks[i].ring.queue_free()
			marks.remove_at(i)
	if guard_time<=0 or game.hero.shield<=0 or game.hero.shield_time<=0:guard_ready=false

func mark(enemy: BattleUnit) -> void:
	if game.run.count("core_flame")==0 or not enemy.alive:return
	for item in marks:
		if item.enemy.get_ref()==enemy:item.time=4.0;return
	var ring:=BattleVisuals.ring(enemy,Vector3(0,.14,0),.7,Color("efae66"),.065)
	marks.append({"enemy":weakref(enemy),"time":4.0,"ring":ring})

func consume(enemy: BattleUnit) -> float:
	for i in marks.size():
		if marks[i].enemy.get_ref()==enemy:
			if is_instance_valid(marks[i].ring):marks[i].ring.queue_free()
			marks.remove_at(i)
			BattleVisuals.sparks(game.effects,enemy.position+Vector3.UP,Color("ffc46d"),9)
			return 60.0
	return 0.0

func arm_guard() -> void:
	guard_ready=game.run.count("core_guard")>0
	guard_time=4.0 if guard_ready else 0.0

func absorbed(amount: float) -> void:
	if not guard_ready or amount<=0 or game.phase not in ["day","night"]:return
	guard_ready=false
	game.hit_area(game.hero.position,4.2,50.0)
	BattleVisuals.burst(game.effects,game.hero.position,4.2,Color("86d7ba"),.32)
	game.notify("守灯反震 · 屏障吸收了攻击",1.5)

func clear() -> void:
	for item in marks:
		if is_instance_valid(item.ring):item.ring.queue_free()
	marks.clear();guard_ready=false;guard_time=0.0
