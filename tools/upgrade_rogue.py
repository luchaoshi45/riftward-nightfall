from pathlib import Path
p=Path(__file__).resolve().parents[1]
f=p/'scripts/game.gd'
s=f.read_text(encoding='utf8')
s=s.replace('var gold: float = 300.0','var essence: float = 0.0')
s=s.replace('var shop_open: bool = false','var build_open: bool = false')
s=s.replace('var upgrades: Array[int] = [0, 0, 0]','''var run := RunBuild.new()
var encounter_rng := RandomNumberGenerator.new()
var attack_count: int = 0
var next_evolution: float = 90.0
var evolution: int = 0
var resurrection_left: int = 3
var guardian_timer: float = 0.0
var draft_scheduled: bool = false''')
s=s.replace('shop_open','build_open')
s=s.replace('func _ready() -> void:\n','func _ready() -> void:\n\tencounter_rng.seed=run.seed_value+913\n')
s=s.replace('for tone in [390.0, 620.0, 210.0]: sounds.append(make_tone(tone))','for tone in [390.0, 620.0, 210.0]: sounds.append(make_tone(tone))\n\tapply_build()')
s=s.replace('func start_match() -> void:\n\tmode = "playing"','''func start_match() -> void:
	mode = "playing"
	run.grant("启程赐福 · 选择首张命运卡")
	open_draft()''')
s=s.replace('if mode != "playing" or auto_test or help_open: return','if mode != "playing" or auto_test or help_open or build_open: return')
s=s.replace('func simulate(delta: float) -> void:\n','func simulate(delta: float) -> void:\n\tif mode!="playing": return\n')
s=s.replace('\tgold += delta * 3.0','''	if elapsed>=next_evolution:
		evolution+=1
		next_evolution+=90
		for hero in heroes:
			if hero==player: continue
			hero.damage+=9
			hero.max_hp+=90
			hero.hp=minf(hero.max_hp,hero.hp+90)
		run.grant("第 %d 次裂隙异变 · 战场英雄与兵线强化" % evolution)
		schedule_draft()
	guardian_timer=maxf(0,guardian_timer-delta)
	if run.school_count(2)>=6 and guardian_timer<=0 and player.alive:
		player.shield=maxf(player.shield,player.max_hp*.12*run.stats.shield)
		player.shield_time=5
		guardian_timer=12''')
s=s.replace('delta * (13 if vigor_time>0 else 7)','delta * ((13 if vigor_time>0 else 7)+run.stats.mana_regen)')
s=s.replace('2.0 + upgrades[1]','2.0 + run.stats.regen')
s=s.replace('minf(20, wave_number * .8)','minf(35, wave_number * .8)+evolution*3')
s=s.replace('minf(120, wave_number * 5)','minf(200, wave_number * 5)+evolution*35')
# Basic attacks use rolled crits; actual damage can heal, chain hits never recurse.
old='\tdeal_damage(victim, attacker.damage * (0.62 if victim.is_structure() and attacker.kind == "hero" else 1.0), attacker)'
s=s.replace(old,'''	var amount := attacker.damage * (0.62 if victim.is_structure() and attacker.kind == "hero" else 1.0)
	if attacker==player and encounter_rng.randf()<run.stats.crit:
		amount*=1.75
		BattleVisuals.sparks(effects,victim.position+Vector3.UP,Color("ffd784"),7)
	var dealt := deal_damage(victim,amount,attacker)
	if attacker==player:
		attack_count+=1
		if not victim.is_structure(): player.hp=minf(player.max_hp,player.hp+dealt*run.stats.lifesteal)
		if run.count("chain")>0 and attack_count%3==0:
			var hit:=0
			for other in units:
				if other==victim or not valid_target(other,0) or other.is_structure(): continue
				if other.position.distance_to(victim.position)>5: continue
				BattleVisuals.beam(effects,victim.position+Vector3.UP,other.position+Vector3.UP,Color("e5c778"),.07)
				deal_damage(other,player.damage*.55,player)
				hit+=1
				if hit>=2: break
	if victim==player and player.alive and run.count("thorns")>0 and attacker.alive:
		deal_damage(attacker,18+player.armor*.25,player)''')
s=s.replace('func deal_damage(victim: BattleUnit, amount: float, source: BattleUnit) -> void:\n\tif not valid_target(victim, source.team): return','func deal_damage(victim: BattleUnit, amount: float, source: BattleUnit) -> float:\n\tif not valid_target(victim, source.team): return 0.0')
s=s.replace('\tvictim.hurt(amount, source)','\tvar before := victim.hp\n\tvictim.hurt(amount, source)')
s=s.replace('\nfunc _on_damaged(unit:', '\treturn before-victim.hp\n\nfunc _on_damaged(unit:')
s=s.replace('\t\t\tgold+=120','\t\t\tadd_essence(70)')
s=s.replace('野怪击败 +120 金币','野怪击败 +70 星尘')
s=s.replace('\t\tgold += reward','\t\tadd_essence(8 if unit.kind=="minion" else 45)')
s=s.replace('\t\tvar reward := 26 if unit.kind == "minion" else 180\n','')
s=s.replace('\t\tplayer_respawn = 8.0 + level','''		if resurrection_left<=0:
			winner=1
			mode="ended"
			run.offer.clear()
			build_open=false
			return
		resurrection_left-=1
		player_respawn = 8.0 + level''')
s=s.replace('\t\tnotify("敌方防御塔已摧毁  +180 金币" if unit.team == 1 else "我方防御塔被摧毁！", 5)','''		if unit.team==1:
			run.grant("破塔赐福 · 战场目标奖励")
			schedule_draft()
		notify("敌方守塔已摧毁 · 获得命运选卡" if unit.team==1 else "我方防御塔被摧毁！",5)''')
s=s.replace('while level < 12 and experience >= level * 90:', 'while level < 12 and experience >= level * 65:')
s=s.replace('experience -= level * 90','experience -= level * 65')
s=s.replace('''		player.max_hp += 75
		player.hp = minf(player.max_hp, player.hp + 100)
		player.damage += 7
		max_mana += 25
		mana = max_mana'''.replace('+',''),'''		apply_build()
		player.hp=minf(player.max_hp,player.hp+80)
		mana=max_mana
		run.grant("升至 %d 级 · 选择命运卡" % level)
		schedule_draft()'''.replace('+\t','\t'))
# Input modal state must come before pause handling.
s=s.replace('if event is InputEventKey and event.pressed and not event.echo:\n\t\tif event.physical_keycode', '''if event is InputEventKey and event.pressed and not event.echo:
		if mode=="draft":
			if event.physical_keycode in [KEY_1,KEY_2,KEY_3]: select_card(event.physical_keycode-KEY_1)
			elif event.physical_keycode==KEY_F: run.redraw()
			return
		if event.physical_keycode'''.replace('+\t','\t'),1)
s=s.replace('cooldowns[slot] = COOLDOWNS[slot] * (0.90 if upgrades[2] >= 2 else 1.0)','cooldowns[slot] = COOLDOWNS[slot] * run.cooldown_factor()')
start=s.index('\t\t0:\n\t\t\tvar orb',s.index('func cast('))
end=s.index('\t\t1:',start)
s=s[:start]+'''		0:
			var spread := [-.20,0.0,.20] if run.count("split")>0 else [0.0]
			for angle in spread:
				var dir := direction.rotated(Vector3.UP,angle)
				var orb := BattleVisuals.ring(effects, player.position + Vector3.UP * 0.75, 0.35, BLUE, 0.12)
				var amount: float=(115.0+level*12+run.stats.spell*.85)*(.7 if spread.size()==3 else 1.0)
				projectiles.append({"node":orb,"direction":dir,"distance":0.0,"hits":[],"damage":amount})
'''.replace('+\t','\t')+s[end:]
s=s.replace('player.shield = 140 + level * 18','player.shield = (140 + level * 18 + run.stats.spell*.5)*run.stats.shield')
s=s.replace('player.position, 4.2, BLUE','player.position, 4.2*run.stats.area, BLUE')
s=s.replace('< 4.2:', '< 4.2*run.stats.area:')
s=s.replace('75 + level * 12, player','75 + level * 12 + run.stats.spell*.65, player')
s=s.replace('minf(6.2, player.position.distance_to(aim))','minf(6.2+run.count("stride")*.8, player.position.distance_to(aim))')
s=s.replace('telegraph(player, point, 4.0, 290 + level * 22, 0.7)','''telegraph(player, point, 4.0*run.stats.area, 290 + level * 22+run.stats.spell*1.25, 0.7)
			if run.count("echo")>0: telegraph(player,point,4.0*run.stats.area,(290+level*22+run.stats.spell*1.25)*.5,1.25)'''.replace('+\t','\t'))
start=s.index('func buy(');end=s.index('func notify(',start)
s=s[:start]+'''func apply_build() -> void:
	var old_max := player.max_hp
	player.max_hp=850+(level-1)*65+run.stats.health
	player.hp=minf(player.max_hp,player.hp+maxf(0,player.max_hp-old_max))
	player.damage=58+(level-1)*6+run.stats.attack
	player.attack_interval=.8/(1+run.stats.attack_speed)
	player.attack_range=5.2+run.stats.range
	player.speed=minf(9,6+run.stats.speed)
	player.armor=10+run.stats.armor
	var previous_mana := max_mana
	max_mana=300+(level-1)*20+run.stats.mana
	mana=minf(max_mana,mana+maxf(0,max_mana-previous_mana))

func add_essence(amount: float) -> void:
	essence+=amount
	while essence>=100:
		essence-=100
		run.grant("100 星尘共鸣 · 选择命运卡")
		schedule_draft()

func schedule_draft() -> void:
	if draft_scheduled: return
	draft_scheduled=true
	call_deferred("open_draft")

func open_draft() -> void:
	draft_scheduled=false
	if mode!="playing" or not player.alive: return
	if run.draft():
		mode="draft"
		build_open=false
		help_open=false

func select_card(index: int) -> bool:
	if mode!="draft": return false
	var selected := run.choose(index)
	if selected.is_empty(): return false
	apply_build()
	sound(1)
	BattleVisuals.burst(effects,player.position,2.0,RunBuild.COLORS[selected.school],.6)
	mode="playing"
	notify("命运已铭刻："+selected.name,3)
	if run.pending>0: open_draft()
	return true

'''.replace('+\t','\t').replace('\n+','\n')+s[end:]
s=s.replace('\t\t\tnotify("重返战场")','\t\t\tnotify("重返战场")\n\t\t\tif run.pending>0: schedule_draft()')
s=s.replace('\t\t\telif mode == "paused": mode = "playing"','\t\t\telif mode == "paused":\n\t\t\t\tmode = "playing"\n\t\t\t\tif run.pending>0: schedule_draft()')
# Old smoke suite delegates to the new suite; no obsolete equipment code retained.
s=s[:s.index('func run_smoke_test()')]+'''func run_smoke_test() -> void:
	var suite=load("res://tests/rogue_smoke.gd").new()
	add_child(suite)
	await suite.run(self)
'''.replace('+\t','\t')
f.write_text(s,encoding='utf8')
u=p/'scripts/unit.gd';s=u.read_text(encoding='utf8').replace('var damage: float = 10.0','var damage: float = 10.0\nvar armor: float = 0.0')
s=s.replace('\tvar absorbed := minf(shield, amount)','\tamount*=100.0/(100.0+armor)\n\tvar absorbed := minf(shield, amount)')
u.write_text(s,encoding='utf8')
