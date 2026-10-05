extends Control
## Compact dark-fantasy HUD for the outpost loop.
const Layout = preload("res://scripts/outpost_layout.gd")
const CONSTRUCTION_PANEL_RECT := Rect2(435,548,570,110)
var game: Node3D
var font: SystemFont
var display_font: SystemFont
var ink:=Color("e7e1d3")
var muted:=Color("a5aaa5")
var amber:=Color("e2a960")
var red:=Color("db756c")
var panel:=Color(.022,.035,.045,.88)
var card_rects: Array[Rect2] = []
var mode_rects: Array[Rect2] = []
const BOSS_PANEL_RECT := Rect2(457,24,570,110)
const EXPLORATION_PANEL_RECT := Rect2(24,197,340,244)
const EXPLORATION_TOAST_TOP := 451.0
const GROWTH_PANEL_RECT := Rect2(1050,620,365,111)
const GROWTH_MEMORY_RECT := Rect2(1050,620,365,46)

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_PASS
	font=SystemFont.new()
	font.font_names=PackedStringArray(_ui_font_names())
	font.allow_system_fallback=true
	display_font=SystemFont.new()
	display_font.font_names=PackedStringArray(_display_font_names())
	display_font.allow_system_fallback=true

func _ui_font_names() -> Array[String]:
	match OS.get_name():
		"macOS": return ["Hiragino Sans GB", "Heiti SC", "Arial Unicode MS"]
		"Windows": return ["Microsoft YaHei UI", "Microsoft YaHei"]
		_: return ["Noto Sans CJK SC", "DejaVu Sans"]

func _display_font_names() -> Array[String]:
	match OS.get_name():
		"macOS": return ["Helvetica"]
		"Windows": return ["Bahnschrift", "Segoe UI"]
		_: return ["DejaVu Sans"]

func label(value: String,point: Vector2,size_px: int,color: Color=Color("e7e1d3"),latin: bool=false) -> void:
	draw_string(display_font if latin else font,point,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px,color)

func box(rect: Rect2,fill: Color=Color(.022,.035,.045,.88),outline: Color=Color("435455")) -> void:
	var style:=StyleBoxFlat.new()
	style.bg_color=fill
	style.border_color=outline
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	draw_style_box(style,rect)

func progress(rect: Rect2,ratio: float,color: Color) -> void:
	draw_rect(rect,Color("202c32"))
	draw_rect(Rect2(rect.position,Vector2(rect.size.x*clampf(ratio,0,1),rect.size.y)),color)

func _draw() -> void:
	if not is_instance_valid(game) or not is_instance_valid(game.hero):return
	draw_set_transform(Vector2.ZERO,0,get_viewport_rect().size/Vector2(1440,900))
	card_rects.clear()
	mode_rects.clear()
	draw_combat_floats()
	box(Rect2(24,22,405,160),panel,Color("6c654f"))
	label("余烬哨站",Vector2(45,57),27,ink)
	label("最后的灯火  /  THE LAST LIGHT",Vector2(46,80),13,amber)
	var display_night: bool=game.phase=="night" or (game.phase=="draft" and game.return_phase=="night") or (game.phase=="paused" and game.paused_from=="night")
	var phase_name:="第 %d 夜 · 守卫" % game.day_number if display_night else "第 %d 日 · 搜寻" % game.day_number
	label(phase_name,Vector2(46,114),19,red if display_night else amber)
	label("距阶段结束  %02d:%02d" % [int(game.phase_time)/60,int(game.phase_time)%60],Vector2(46,147),17,muted)
	if game.phase=="night":
		var wave_text: String="夜袭 %d/%d 波" % [game.wave_index,game.WAVES_PER_NIGHT]
		if game.wave_index<game.WAVES_PER_NIGHT:wave_text+=" · 下一波 %02d 秒" % ceili(game.spawn_timer)
		label(wave_text+" · "+game.run_mode_title(),Vector2(46,166),13,red if game.world.wave_warning else amber)
	elif game.expeditions:
		label(game.expeditions.objective_text(),Vector2(46,170),13,Color("8dcfc3"))
	progress(Rect2(235,126,173,8),game.phase_time/(game.NIGHT_LENGTH if display_night else game.DAY_LENGTH),red if display_night else amber)
	draw_exploration_rewards()
	if game.phase=="night":
		var preview: Dictionary=game.wave_preview()
		var boss: Dictionary=game.boss_snapshot() if game.has_method("boss_snapshot") else {}
		box(BOSS_PANEL_RECT,panel,Color("9a5d4e") if not boss.is_empty() else Color("876f52"))
		if not boss.is_empty():
			draw_boss_panel(boss)
		elif not preview.is_empty():
			label("下一波 · %s · %d只 · %.0f秒" % [preview.title,preview.count,preview.remaining],Vector2(477,54),19,amber)
			label(preview.advice,Vector2(477,85),14,muted)
			label("先安排防线，再处理主要威胁",Vector2(477,114),13,Color("8dcfc3"))
		else:label("最后一波已抵达 · 守住南门",Vector2(477,66),19,amber)
	elif game.phase=="day" and game.contracts.status!="idle":
		var contract: Node=game.contracts
		box(Rect2(457,24,570,132),panel,Color("587c68"))
		var title: String=contract.TITLES.get(contract.kind,"自由探索")
		label("可选委托 · %s · 方案%d/%d · %d/%d" % [title,contract.selected_offer+1,contract.offers.size(),contract.done.size(),contract.targets.size()],Vector2(477,54),19,Color("a3d7bd"))
		if contract.status in ["bonus_offer","bonus_active","returning"]:
			var budget: Dictionary=contract.return_budget()
			var budget_color: Color=red if String(budget.risk) in ["late","unreachable"] else (amber if String(budget.risk)=="tight" else Color("a3d7bd"))
			var detail: String=contract.bonus_summary() if contract.status!="returning" else ("追加补给已带走 · 回灯塔兑现" if contract.bonus_done else "主委托已完成 · 返回灯塔领取奖励")
			label(detail,Vector2(477,84),15,ink)
			label(contract.return_budget_text(budget),Vector2(477,110),13,budget_color)
			var hint: String="4 立即返家 / 5 追加 · P 前往目标" if contract.status=="bonus_offer" else ("P 前往追加目标 · F 采集后再 P 返家" if contract.status=="bonus_active" else "P 回灯塔 · 提前15秒再+10零件")
			label(hint+" · 估时不含战斗",Vector2(477,130),12,muted)
		else:
			var goal: Vector3=game.contract_goal()
			var detail: String="日落前完成并返回灯塔"
			if contract.status=="completed":detail="已交回 · 奖励到账"
			elif contract.status=="unavailable":detail="今日无可用目标，可以自由探索"
			elif contract.status=="expired":detail="委托已截止 · 可自由探索并准备守夜"
			if goal!=Vector3.INF:detail="P 前往目标 · %.0f米 · 日落前回灯塔交付" % game.hero.position.distance_to(goal)
			label(detail,Vector2(477,84),15,ink)
			label(contract.offer_summary(contract.selected_offer),Vector2(477,110),13,amber)
			label("4/5/6 切换方案 · 完成第一项后锁定" if not contract.progress_started else "委托已开始 · 方案已锁定",Vector2(477,130),12,Color("a3c7b7"))
	if game.phase=="day":draw_day_forecast()
	box(Rect2(1050,22,365,173),panel,Color("665343"))
	label("灯塔耐久",Vector2(1071,55),17,ink)
	label("%d / %d" % [int(game.beacon_hp),int(game.BEACON_MAX)],Vector2(1261,55),16,amber)
	progress(Rect2(1071,70,322,10),game.beacon_hp/game.BEACON_MAX,amber)
	label("零件  %d" % game.scrap,Vector2(1071,109),18,ink)
	label("清除夜行体  %d" % game.kills,Vector2(1247,109),14,muted)
	label("记忆 %d / %d" % [game.essence,game.run.memory_cost()],Vector2(1071,146),14,muted)
	label("南门机关 %d / %d" % [game.gate_trap_charges,game.GATE_TRAP_MAX],Vector2(1244,146),14,amber)
	label("C 塔群集火  %s" % ("进行中 %.0fs" % game.focus_time if game.focus_time>0 else ("就绪" if game.focus_cooldown<=0 else "冷却 %.0fs" % game.focus_cooldown)),Vector2(1071,168),12,amber if game.focus_time>0 else muted)
	label("灯下同伴 %d/2 · 协作修灯 %d 零件" % [game.survivors_rescued,game.beacon_repair_cost()],Vector2(1071,188),12,Color("a3c7b7"))
	if game.beacon_alarm_time>0:
		var flash:=.72+.22*sin(float(Time.get_ticks_msec())*.018)
		draw_rect(Rect2(1051,23,363,171),Color("ef6b56",flash),false,2.4)
		box(Rect2(500,25,440,54),Color(.14,.025,.024,.93),Color("c46c58"))
		var alarm_text: String="灯塔遭攻击  -%d  ·  立即回防" % int(game.beacon_alarm_damage)
		var alarm_width:=font.get_string_size(alarm_text,HORIZONTAL_ALIGNMENT_LEFT,-1,20).x
		label(alarm_text,Vector2(720-alarm_width*.5,60),20,Color("ff9d80"))
	draw_minimap()
	draw_squads()
	draw_growth_guidance()
	if game.notice_time>0:
		box(Rect2(368,192,704,48),Color(.035,.046,.050,.86),Color("9a7051"))
		var width:=font.get_string_size(game.notice,HORIZONTAL_ALIGNMENT_LEFT,-1,19).x
		label(game.notice,Vector2(720-width*.5,224),19,ink)
	var prompt: String=game.interaction_prompt()
	var district_index: int=game.districts.nearest()
	if district_index>=0 and game.phase=="day" and not game.construction.active:
		var district: Dictionary=game.districts.snapshots()[district_index]
		box(Rect2(435,553,570,94),panel,Color("648779"))
		label("城区 · "+district.title,Vector2(457,582),18,amber)
		label("1 兵营 / 2 工坊 · 建造60零件" if district.level==0 else ("3 升至二级 · 80零件" if district.level==1 else "二级 · 本局不能更换方向"),Vector2(457,609),15,ink)
		var benefit: String="据点恢复 +%d生命/秒" % (district.level*3) if district.kind=="barracks" else district.benefit
		label("兵营：据点恢复    工坊：塔建造与维修折扣" if district.level==0 else benefit,Vector2(457,634),13,Color("a3d7bd"))
	var pad_index: int=game.nearest_tower_pad()
	if pad_index>=0 and game.world.tower_pads[pad_index].level>=2 and game.phase in ["day","night"] and not game.construction.active:
		var pad: Dictionary=game.world.tower_pads[pad_index]
		box(Rect2(435,553,570,86),panel,Color("647d78"))
		if game.specializations.branch(pad)=="standard":
			label("二级塔改装 · 每座只能选择一次 · 45零件",Vector2(457,582),16,amber)
			label("J 破甲：重敌更强 / 放弃群伤    K 牵制：降伤减速群敌",Vector2(457,614),14,ink)
		else:
			label("塔专精 · "+("重敌破甲" if game.specializations.branch(pad)=="piercing" else "范围牵制"),Vector2(457,582),17,amber)
			label("H 修复 · G 目标模式 · C 指定集火",Vector2(457,614),15,ink)
	if prompt!="" and game.phase!="draft" and not game.construction.active:
		box(Rect2(492,670,456,48),Color(.032,.048,.050,.91),Color("b39761"))
		var width:=font.get_string_size(prompt,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x
		label(prompt,Vector2(720-width*.5,701),17,amber)
	draw_construction()
	draw_hero_damage_feedback()
	draw_target_warnings()
	box(Rect2(300,746,840,129),Color(.025,.041,.047,.94),Color("53605c"))
	label("守望者",Vector2(323,776),15,muted)
	var mana_text: String="法力 %d/%d" % [floori(game.mana),int(game.max_mana)]
	var mana_width:=font.get_string_size(mana_text,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x
	label(mana_text,Vector2(507-mana_width,776),11,Color("91bdd0"))
	label("%d / %d" % [int(game.hero.hp),int(game.hero.max_hp)],Vector2(323,805),16,ink)
	progress(Rect2(323,817,184,9),game.hero.hp/game.hero.max_hp,red)
	progress(Rect2(323,835,184,6),game.mana/game.max_mana,Color("74a5bb"))
	var names:=["Q  斩光","W  屏障","E  突进","R  灯焰","X  治疗"]
	for i in range(5):
		var x:=531+i*116
		var status: String=game.skill_status(i)
		var status_color:=red if status=="法力不足" else (amber if game.cooldowns[i]<=0 else muted)
		box(Rect2(x,770,106,72),Color(.068,.087,.083,.9),Color("80524f") if status=="法力不足" else Color("59685f"))
		label(names[i],Vector2(x+11,798),14,ink)
		label(status,Vector2(x+11,824),13,status_color)
	label("ZASD移动 · 右键寻路 · Y城内建塔 · F互动/升级 · H修塔 · G塔目标 · C集火 · T机关 · B路障",Vector2(323,854),11,muted)
	label("U盾卫 · I弩手 · O驻守/撤回 · L白昼补员 · V铭刻 · Esc暂停",Vector2(323,870),10,muted)
	draw_combat_rewards()
	var core_names: Dictionary={"core_storm":"雷斩 · 第三击连锁", "core_flame":"灯焰 · Q 标记，R 引爆", "core_guard":"守灯 · W 吸收后反震"}
	for core_key in core_names:
		if game.run.count(core_key)>0:
			label(core_names[core_key],Vector2(548,737),15,Color("a3d4cb"))
	if game.phase=="draft":draw_draft()
	if game.phase=="paused":
		draw_rect(Rect2(0,0,1440,900),Color(.01,.018,.022,.58))
		box(Rect2(440,258,560,394),panel,Color("b78c57"))
		label("守夜暂停",Vector2(637,319),28,ink)
		label("按 ESC 继续",Vector2(646,365),18,amber)
		if game.music:
			label("配乐  %s  ·  音量 %d%%" % ["静音" if game.music.muted else "开启",roundi(game.music.get_volume()*100)],Vector2(526,415),18,ink)
			label("M 开关配乐  ·  [ 降低音量  ·  ] 提高音量",Vector2(502,452),16,muted)
		if is_instance_valid(game.combat):
			label("F2  震动与闪光：%s" % ("已减弱" if game.combat.reduced_effects else "完整反馈"),Vector2(570,494),16,Color("8dcfc3"))
		label("F1  配乐来源与许可",Vector2(603,543),16,amber)
		label("Music by Rusted Music Studio / Fabien C.",Vector2(497,600),14,muted,true)
	if game.phase=="ended":draw_result()
	if game.music_credits_open:draw_music_credits()

func draw_construction() -> void:
	if not game.construction.active or game.phase not in ["day","night"]:return
	var placement: Dictionary=game.construction.snapshot()
	var tint:=Color("85d5a5") if bool(placement.valid) else red
	box(CONSTRUCTION_PANEL_RECT,Color(.025,.052,.046,.95),tint)
	label("城内自由建塔 · %d零件" % int(placement.cost),Vector2(457,578),19,ink)
	label(String(placement.reason),Vector2(457,607),16,tint)
	label("移动鼠标选址 · 左键/F确认 · 右键/Esc取消 · Y退出",Vector2(457,637),14,amber)

func draw_combat_floats() -> void:
	if game.phase!="day" and game.phase!="night":return
	if game.music_credits_open or not is_instance_valid(game.combat) or not is_instance_valid(game.camera):return
	var canvas_size: Vector2=get_viewport_rect().size
	if canvas_size.x<=0.0 or canvas_size.y<=0.0:return
	var occupied: Array[Rect2]=[
		Rect2(24,22,405,160),Rect2(1050,22,365,173),
		Rect2(EXPLORATION_PANEL_RECT.position,Vector2(340,EXPLORATION_TOAST_TOP-EXPLORATION_PANEL_RECT.position.y+game.reward_toasts.size()*70)),
			Rect2(1161,195,254,373),Rect2(1050,480,365,125),GROWTH_PANEL_RECT,Rect2(300,746,840,129),Rect2(492,670,456,48)
	]
	if game.phase=="night" and game.has_method("boss_snapshot") and not game.boss_snapshot().is_empty():
		occupied.append(BOSS_PANEL_RECT)
	if game.construction.active:occupied.append(CONSTRUCTION_PANEL_RECT)
	if game.notice_time>0.0:occupied.append(Rect2(368,192,704,48))
	if game.combat_milestone_time>0.0:occupied.append(Rect2(504,259,432,65))
	if game.beacon_alarm_time>0.0:occupied.append(Rect2(500,25,440,54))
	# New contacts get their natural screen position first; older messages stack
	# above them or expire without obscuring another reward or a fixed HUD panel.
	for index in range(game.combat.floats.size()-1,-1,-1):
		var item: Dictionary=game.combat.floats[index]
		var point: Vector3=item.point
		if game.camera.is_position_behind(point):continue
		var position: Vector2=game.camera.unproject_position(point)*Vector2(1440,900)/canvas_size
		if not Rect2(-80,-60,1600,1020).has_point(position):continue
		var duration: float=maxf(.01,float(item.duration))
		var remaining: float=maxf(0.0,float(item.time))
		if remaining<=0.0:continue
		position.y-=18.0*clampf(1.0-remaining/duration,0.0,1.0)
		var fade: float=minf(1.0,remaining/.24)
		var tint: Color=item.color
		tint.a*=fade
		var size_px: int=roundi(17.0*clampf(float(item.scale),.6,1.8))
		var value: String=item.text
		var text_width: float=font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x
		position.x-=text_width*.5
		var free_position:=false
		var footprint:=Rect2()
		for attempt in 8:
			footprint=Rect2(position-Vector2(3,size_px),Vector2(text_width+6,size_px+6))
			var intersects:=false
			for area in occupied:
				if footprint.intersects(area):intersects=true;break
			if not intersects:free_position=true;break
			position.y-=size_px+6
		if not free_position or position.y<float(size_px+12):continue
		occupied.append(footprint)
		draw_string_outline(font,position,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px,3,Color(.014,.024,.028,.84*fade))
		label(value,position,size_px,tint)

func _world_screen(point: Vector3) -> Variant:
	if not is_instance_valid(game.camera) or game.camera.is_position_behind(point):return null
	var viewport_size:=get_viewport_rect().size
	if viewport_size.x<=0.0 or viewport_size.y<=0.0:return null
	return game.camera.unproject_position(point)*Vector2(1440,900)/viewport_size

func draw_target_warnings() -> void:
	if game.phase not in ["day","night","paused"] or not game.has_method("target_warning_snapshot"):return
	var hero_warning_count:=0
	var hero_remaining:=INF
	var hero_source_title: String=""
	for warning: Dictionary in game.target_warning_snapshot():
		var source:=warning.get("source") as BattleUnit
		var target:=warning.get("target") as Node3D
		# Only enemy windups are target-side danger warnings. Friendly squad
		# attacks remain visible through their existing attack pose and never tint
		# the player's target marker red.
		if not is_instance_valid(source) or source.team!=2 or not is_instance_valid(target):continue
		var point:=target.global_position+Vector3.UP*1.05
		var screen: Variant=_world_screen(point)
		if screen==null:continue
		var position:=screen as Vector2
		if position.x<0.0 or position.x>1440.0 or position.y<0.0 or position.y>900.0:continue
		var remaining:=maxf(0.0,float(warning.get("remaining",0.0)))
		var progress_value:=clampf(float(warning.get("progress",0.0)),0.0,1.0)
		var danger:=Color("f08b67") if String(warning.get("threat","stalker"))!="runner" else Color("e5bb70")
		var radius:=16.0+3.0*sin(float(Time.get_ticks_msec())*.012)
		draw_arc(position,radius,0.0,TAU,28,danger,2.4)
		draw_arc(position,radius+4.0,-PI*.5,-PI*.5+TAU*progress_value,24,Color("ffe0a1"),2.5)
		draw_line(position+Vector2(-4,-radius-8),position+Vector2(4,-radius-8),Color(.04,.02,.015,.88),5.0)
		draw_line(position+Vector2(-4,-radius-8),position+Vector2(-4+8.0*progress_value,-radius-8),danger,3.0)
		var label_text: String="蓄力 %.1f" % remaining
		if target==game.hero:
			hero_warning_count+=1
			if remaining<hero_remaining:
				hero_remaining=remaining
				hero_source_title=String(warning.get("title","敌人"))
		if target!=game.hero:
			var text_width:=font.get_string_size(label_text,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x
			label(label_text,position+Vector2(-text_width*.5,-radius-13),12,danger)
	if hero_warning_count>0 and hero_remaining<INF:
		var detail: String="被锁定 · %s · %.1f秒后命中" % [hero_source_title,hero_remaining]
		box(Rect2(520,700,600,38),Color(.12,.035,.028,.95),Color("d87961"))
		var width:=font.get_string_size(detail,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
		label(detail,Vector2(820-width*.5,725),16,Color("ffd1a0"))

func draw_hero_damage_feedback() -> void:
	if game.phase not in ["day","night","paused"]:return
	if float(game.get("hero_damage_flash_time"))<=0.0:return
	var fade:=clampf(float(game.hero_damage_flash_time)/.18,0.0,1.0)
	var border:=Color("ed756c",.75+.2*fade)
	# Keep the actual hit confirmation persistent in the HUD even when F2
	# reduces particles and camera trauma.
	draw_rect(Rect2(300,746,840,129),border,false,2.4)
	var text_value:=String(game.hero_damage_flash_text)
	if text_value!="":
		box(Rect2(520,708,600,31),Color(.13,.035,.032,.94),Color("c9665d",.9))
		var width:=font.get_string_size(text_value,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
		label(text_value,Vector2(820-width*.5,729),14,Color("ffd0bc",fade))

func draw_boss_panel(snapshot: Dictionary) -> void:
	var phase_name: String=String(snapshot.get("phase","approach"))
	var hp: float=maxf(0.0,float(snapshot.get("hp",0.0)))
	var max_hp: float=maxf(1.0,float(snapshot.get("max_hp",1.0)))
	var clearance: bool=bool(game.get("final_clearance_active"))
	if phase_name=="dead":
		label("末夜首领 · 已击破",Vector2(477,54),19,Color("8dd4c7"))
		if clearance:
			var remaining: int=0
			for enemy in game.enemies:
				if is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and enemy.alive:remaining+=1
			label("清场中 · 残敌 %d · 清除全部威胁后结算" % remaining,Vector2(477,112),14,amber)
		else:label("首领威胁已解除",Vector2(477,94),14,muted)
		return
	label("末夜首领 · 灯噬巨兽",Vector2(477,53),19,Color("f0b177"))
	progress(Rect2(477,65,530,10),hp/max_hp,Color("d7625e"))
	label("生命 %d / %d" % [roundi(hp),roundi(max_hp)],Vector2(477,91),13,ink)
	var detail: String
	match phase_name:
		"windup":
			detail="蓄力 %.1f秒 · 打断 %.0f / %.0f" % [float(snapshot.get("windup",0.0)),float(snapshot.get("interrupt_damage",0.0)),float(snapshot.get("interrupt_threshold",220.0))]
			progress(Rect2(719,84,288,8),float(snapshot.get("interrupt_progress",0.0)),Color("82ced2"))
		"exposed":
			detail="护甲破绽 %.1f秒 · 立即集火" % float(snapshot.get("exposed",0.0))
			progress(Rect2(719,84,288,8),1.0,Color("82ced2"))
		_:
			detail="正在接近 · 增援 %d / 6" % int(snapshot.get("adds",0))
	label(detail,Vector2(477,113),14,Color("82ced2") if phase_name in ["windup","exposed"] else muted)

func draw_day_forecast() -> void:
	var top: float=164.0 if game.contracts.status!="idle" else 24.0
	var rect:=Rect2(457,top,570,142)
	box(rect,panel,Color("63745f"))
	if game.night_plan.is_empty():
		label("下一夜威胁情报 · 等待计划生成",Vector2(477,top+31),18,amber)
		return
	var first: Dictionary=game.night_plan[0]
	label("下一夜威胁情报 · 第 %d 夜" % game.day_number,Vector2(477,top+29),18,Color("a3d7bd"))
	label("主威胁：%s · %d 波 · 特殊威胁约%d只" % [game.forecast_primary_threat(),game.night_plan.size(),game.forecast_specialist_count()],Vector2(477,top+53),14,ink)
	label("首波 %s · %s" % [String(first.title),String(first.advice)],Vector2(477,top+74),12,muted)
	for index in game.countermeasure_count():
		var option_x:=471.0+float(index)*185.0
		var selected: bool=game.countermeasure_selected==index
		var recommended: bool=game.countermeasure_recommended(index)
		var outline:=Color("e8bc70") if selected else (Color("82c9be") if recommended else Color("4b625d"))
		box(Rect2(option_x,top+87,176,43),Color(.10,.15,.14,.96) if selected else Color(.045,.075,.073,.92),outline)
		var marker: String=" · 已选" if selected else (" · 推荐" if recommended else "")
		label("%d  %s%s" % [index+7,game.countermeasure_title(index),marker],Vector2(option_x+9,top+106),12,amber if selected or recommended else ink)
		label(game.countermeasure_summary(index),Vector2(option_x+9,top+123),10,muted)
	label("7/8/9 选择反制 · 天黑前可更换 · 留家布防也不会获得隐藏加成",Vector2(477,top+139),10,Color("a3c7b7"))

func draw_combat_rewards() -> void:
	if game.phase!="day" and game.phase!="night":return
	if game.music_credits_open or not is_instance_valid(game.combat):return
	var step: int=clampi(int(game.attack_chain),0,2)
	var charged: bool=step==2 and game.attack_chain_time>0.0
	for i in 3:
		var point:=Vector2(390+i*14,771)
		var tint:=Color("eac279") if i==2 else Color("8bd0d0")
		draw_circle(point,4.4,tint if i<step else Color("354b4e"))
		if i==2:
			draw_arc(point,6.2,0,TAU,20,Color("eac279") if charged else Color("62746a"),1.5 if charged else 1.0)
	progress(Rect2(386,781,37,2),game.attack_chain_time/2.8,Color("eac279") if charged else Color("8bd0d0"))
	label("下一击 · 破势" if charged else "普攻 %d / 3" % step,Vector2(407,805),11,amber if charged else muted)
	if game.kill_chain>0 and game.kill_chain_time>0.0:
		var chain: int=game.kill_chain
		box(Rect2(1161,480,254,77),Color(.028,.049,.051,.9),Color("847554"))
		label("连斩",Vector2(1176,511),16,Color("a6dcd4"))
		label("%d" % chain,Vector2(1235,513),28,amber,true)
		var threshold: int=3 if chain<3 else (6 if chain<6 else 10)
		var hint: String="再斩 %d 只 · 额外零件与记忆" % (threshold-chain) if chain<10 else "继续斩击 · 保持燎原之势"
		label(hint,Vector2(1176,535),11,muted)
		progress(Rect2(1176,547,224,3),game.kill_chain_time/6.0,Color("dabb76"))
	if game.combat_milestone_time>0.0:
		var fade: float=minf(1.0,game.combat_milestone_time/.35)
		box(Rect2(504,259,432,65),Color(.073,.064,.031,.9*fade),Color("c7a56e",fade))
		var title: String=game.combat_milestone_title
		var title_width: float=font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,20).x
		label(title,Vector2(720-title_width*.5,286),20,Color("f2ce86",fade))
		var detail: String=game.combat_milestone_detail
		var detail_width: float=font.get_string_size(detail,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x
		label(detail,Vector2(720-detail_width*.5,309),13,Color("b8d8cb",fade))

func draw_music_credits() -> void:
	draw_rect(Rect2(0,0,1440,900),Color(.01,.018,.022,.91))
	box(Rect2(250,188,940,534),panel,Color("b78c57"))
	label("配乐与许可",Vector2(300,244),28,ink)
	label("Music by Rusted Music Studio — Fabien C.",Vector2(300,287),20,amber,true)
	label("白昼探索：Wet Sand · Dark Ambient Piano（作者标注 AI 辅助）",Vector2(300,333),17,ink)
	label("黑夜警戒：Perish Lane · Apocalypse Z（作者标注人工创作）",Vector2(300,370),17,ink)
	label("守城战斗：Dark Sorcery Siege · Orchestral Fantasy WAR（AI 辅助）",Vector2(300,407),17,ink)
	label("许可：Creative Commons Attribution 4.0 International（CC BY 4.0）",Vector2(300,453),16,muted)
	label("本游戏调整了音量，并剪辑、处理了循环衔接。",Vector2(300,486),16,muted)
	var buttons:=["探索曲来源","黑夜曲来源","战斗曲来源","完整许可"]
	for i in buttons.size():
		box(Rect2(300+i*210,527,190,44),Color(.06,.09,.10,1),Color("65796f"))
		label(buttons[i],Vector2(337+i*210,555),16,amber)
	label("点击按钮查看作者原页与授权；M 静音，[ / ] 调整配乐音量。",Vector2(300,619),16,muted)
	label("F1 或 ESC 返回",Vector2(629,680),18,amber)

func draw_minimap() -> void:
	var map_rect:=Rect2(1161,195,254,252)
	box(map_rect,Color(.018,.034,.041,.88),Color("66624d"))
	label("防御塔 %d座  ·  通信塔 %d/8" % [game.tower_count(),game.relay_count()],Vector2(1174,218),13,ink)
	var center:=Vector2(1288,319)
	var scale:=.86
	draw_rect(Rect2(center-Vector2(108,89),Vector2(216,178)),Color(.075,.085,.079,.84))
	for wall: Rect2 in Layout.wall_blocks():
		draw_rect(Rect2(center+wall.position*scale,wall.size*scale),Color("a0a398"))
	for item in game.world.salvage:
		if item.collected:continue
		var p: Vector3=item.position
		draw_circle(center+Vector2(p.x,p.z)*scale,1.8,Color("71b4b6"))
	if game.discoveries:
		for item in game.discoveries.items:
			if item.state=="cooling" or (item.position as Vector3).distance_to(game.hero.position)>45:continue
			var p: Vector3=item.position
			var color:=Color("f2bc6b") if item.kind=="supply_cache" else (Color("91c5f3") if item.kind=="memory_crystal" else Color("85d7ba"))
			draw_circle(center+Vector2(p.x,p.z)*scale,2.3,color)
		var target: Dictionary=game.discoveries.motivation_target()
		if not target.is_empty():
			var target_point:=center+Vector2(target.position.x,target.position.z)*scale
			draw_circle(target_point,5.5,Color("f2d28b"))
			draw_arc(target_point,8.0,0,TAU,18,Color("e8bc70"),1.5)
	if game.wildlife:
		for animal in game.wildlife.animals:
			if not animal.node.visible or (animal.position as Vector3).distance_to(game.hero.position)>45:continue
			var marker:=center+Vector2(animal.position.x,animal.position.z)*scale
			draw_arc(marker,3.8,0,TAU,12,Color("a6e0b1"),1.4)
	for relay in game.world.relays:
		var p: Vector3=relay.position
		draw_circle(center+Vector2(p.x,p.z)*scale,4.0,Color("8bd5d9") if relay.activated else Color("647877"))
	for nest in game.world.nests:
		var p: Vector3=nest.position
		if nest.cleansed:
			draw_circle(center+Vector2(p.x,p.z)*scale,3.8,Color("82c8be"))
		else:
			draw_circle(center+Vector2(p.x,p.z)*scale,5.1,Color("d75b77"))
			draw_arc(center+Vector2(p.x,p.z)*scale,7.0,0,TAU,12,Color("73384b"),1.2)
	for pad in game.world.tower_pads:
		var p: Vector3=pad.position
		var pad_color: Color=Color("78d1c2") if String(pad.get("zone","outer"))=="core" else amber
		var tower_color: Color=Color("697473")
		if pad.level>0:
			tower_color=Color("b78be8") if pad.mode=="threat" else (Color("ed945b") if pad.mode=="breaker" else pad_color)
		draw_circle(center+Vector2(p.x,p.z)*scale,3.2,tower_color)
	if game.expeditions:
		for site in game.expeditions.generators:
			var p: Vector3=site.position
			draw_rect(Rect2(center+Vector2(p.x,p.z)*scale-Vector2(3,3),Vector2(6,6)),Color("72dbb9") if site.state=="active" else (Color("536d64") if site.state=="complete" else Color("9bd3c4")))
		for camp in game.expeditions.camps:
			var p: Vector3=camp.npc.position if camp.state in ["escort","delivered"] else camp.position
			var marker:=center+Vector2(p.x,p.z)*scale
			draw_polyline(PackedVector2Array([marker+Vector2(0,-4.5),marker+Vector2(4.5,0),marker+Vector2(0,4.5),marker+Vector2(-4.5,0),marker+Vector2(0,-4.5)]),Color("59705e") if camp.state=="delivered" else amber,1.5)
			draw_line(marker-Vector2(2,0),marker+Vector2(2,0),amber,1.4)
	if game.gate_barricade_hp>0:
		var barrier_point:=center+Vector2(0,game.gate_barricade.position.z)*scale
		draw_rect(Rect2(barrier_point-Vector2(5,2),Vector2(10,4)),Color("db6959") if game.gate_barricade_hp<game.BARRICADE_MAX*.4 else amber)
	for creature in game.enemies:
		if not is_instance_valid(creature) or not creature.alive:continue
		if creature.position.distance_to(game.hero.position)>22.0 and game.phase!="night":continue
		var threat: String=creature.get_meta("threat","")
		draw_circle(center+Vector2(creature.position.x,creature.position.z)*scale,3.5 if threat=="breaker" else 2.3,Color("ed945b") if threat=="breaker" else (Color("83d8d9") if threat=="runner" else (Color("a794eb") if threat=="light_eater" else red)))
	draw_circle(center,5.0,amber)
	if game.beacon_alarm_time>0:
		draw_arc(center,11.0,0,TAU,32,Color("f16d58"),2.5)
	draw_circle(center+Vector2(game.hero.position.x,game.hero.position.z)*scale,4.1,Color("8ee0e8"))
	label("南门逼近 %d · 夜巢 %d/3" % [game.gate_pressure(),game.remaining_nests()] if game.phase=="night" else "待封闭夜巢  %d / 3" % game.remaining_nests(),Vector2(1174,410),13,red if game.phase=="night" else muted)
	if game.phase=="day":
		label("◇ 救援哨兵  ▪ 能源发电机",Vector2(1174,434),12,Color("a3c7b7"))
	else:
		label("南门路障  %d / %d" % [ceili(game.gate_barricade_hp),int(game.BARRICADE_MAX)] if game.gate_barricade_hp>0 else "南门路障  未部署",Vector2(1174,434),13,red if game.gate_barricade_hp>0 and game.gate_barricade_hp<game.BARRICADE_MAX*.4 else muted)
	if maxf(game.world.gate_light_drain[0],game.world.gate_light_drain[1])>.3:
		label("哨灯遭噬 · 击杀紫色目标恢复",Vector2(1174,456),13,Color("b7a5ee"))

func draw_squads() -> void:
	if not is_instance_valid(game.squads) or game.phase not in ["day","night","paused"]:return
	var snapshot: Dictionary=game.squads.snapshot()
	box(Rect2(1050,480,365,125),Color(.022,.045,.047,.9),Color("5c7f76"))
	label("防御小队",Vector2(1071,508),17,Color("a9d8cf"))
	if int(snapshot.count)<=0:
		label("U 盾卫 · 70零件   I 弩手 · 80零件",Vector2(1071,538),13,amber)
		label("驻守承伤/远程输出 · 白昼可付费补员",Vector2(1071,565),12,muted)
		return
	label("总计 %d/%d 人 · 补员 %d 零件" % [int(snapshot.alive),int(snapshot.capacity),int(snapshot.refill_cost)],Vector2(1071,535),13,ink)
	for index in snapshot.squads.size():
		var row: Dictionary=snapshot.squads[index]
		var order_label: String="驻守" if String(row.order)=="hold" else "撤回"
		var kind_label: String="弩手" if String(row.kind)=="ranged" else "盾卫"
		var kind_color: Color=Color("efcf86") if String(row.kind)=="ranged" else Color("e1d5b7")
		label("小队%d  ·  %s %s  ·  存活 %d/%d  ·  生命 %.0f" % [index+1,kind_label,order_label,int(row.alive),int(row.capacity),float(row.hp)],Vector2(1071,558+index*18),11,kind_color if String(row.order)=="hold" else muted)
	label("U盾卫70 · I弩手80 · O驻守/撤回 · L白昼补员",Vector2(1071,596),11,amber)

func growth_memory_text(snapshot: Dictionary) -> String:
	var memory: Dictionary=snapshot.memory
	if int(memory.pending)>0:
		return "V / 点击铭刻%d张 · 下张差%d记忆" % [int(memory.pending),int(memory.shortfall)]
	return "下一张强化还差 %d 记忆" % int(memory.shortfall)

func growth_lines(snapshot: Dictionary) -> Array[String]:
	var tower: Dictionary=snapshot.tower
	if tower.is_empty():return ["防线：暂无建造、升级或改装目标","零件可用于维修、城区或小队","塔改装与城区选择均由你决定"]
	var action: String={"build":"建造一级","place":"自由建造","upgrade":"升至%d级" % int(tower.target_level),"specialize":"选择改装"}.get(String(tower.action),"")
	var state: String="可负担" if bool(tower.affordable) else "还差%d" % int(tower.shortfall)
	var operation: String="Y 选址" if String(tower.action)=="place" else "到塔旁 %s" % String(tower.key)
	return ["防线：%s · %s" % [String(tower.label),action],
		"%d零件 · %s · %s" % [int(tower.cost),state,operation],String(tower.benefit)]

func draw_growth_guidance() -> void:
	if game.phase not in ["day","night"]:return
	var snapshot: Dictionary=game.growth_snapshot()
	var queued: bool=int(snapshot.memory.pending)>0
	box(GROWTH_PANEL_RECT,Color(.035,.073,.067,.95),amber if queued else Color("527c6b"))
	label(growth_memory_text(snapshot),Vector2(1071,649),14,amber if queued else ink)
	var lines: Array[String]=growth_lines(snapshot)
	var affordable: bool=not snapshot.tower.is_empty() and bool(snapshot.tower.affordable)
	label(lines[0],Vector2(1071,674),13,Color("a6decb"))
	label(lines[1],Vector2(1071,695),12,amber if affordable else muted)
	label(lines[2],Vector2(1071,716),11,muted)

func draw_exploration_rewards() -> void:
	if not game.discoveries:return
	var ready:=0
	for item in game.discoveries.items:
		if item.state=="ready" or item.state=="channel":ready+=1
	box(EXPLORATION_PANEL_RECT,panel,Color("497467"))
	label("荒原发现",Vector2(43,224),17,Color("a6decb"))
	label("探索 %d 次 · 里程碑 %d" % [game.exploration_count,game.exploration_milestones],Vector2(43,247),13,ink)
	var collected: int=game.exploration_count%5
	for i in 5:
		draw_circle(Vector2(49+i*20,272),4.5,Color("e8bc70") if i<collected else Color("3f5b55"))
	label("%d/5 · +35零件 +20记忆" % collected,Vector2(151,277),12,amber)
	label("荧光互动点 %d · 采集后会刷新" % ready,Vector2(43,298),11,muted)
	if game.exploration:
		label(game.exploration.route_text(),Vector2(43,317),11,amber if game.exploration.streak>1 else Color("a3c7b7"))
		var urgent: bool=game.exploration.streak>0 and game.exploration.streak_time<=5.0
		label(game.exploration.streak_text(),Vector2(43,336),12,red if urgent else ink)
		label(game.exploration.streak_reward_text(),Vector2(43,354),11,amber)
		label(game.exploration.collection_reward_text(),Vector2(43,372),11,muted)
		if game.exploration.affinity_active():
			label(game.exploration.affinity_text(),Vector2(43,408),10,Color("e8bc70"))
		if game.exploration.speed_time>0.0:
			label("探索加速 +0.8 · 剩余 %.1f秒" % game.exploration.speed_time,Vector2(43,426),10,Color("a6decb"))
		var target: Dictionary=game.discoveries.motivation_target()
		label(game.discoveries.motivation_target_text(target),Vector2(43,390),10,amber)
	for i in game.reward_toasts.size():
		var reward: Dictionary=game.reward_toasts[game.reward_toasts.size()-1-i]
		var fade: float=minf(1.0,reward.time/.45)
		var y:=EXPLORATION_TOAST_TOP+float(i)*70.0
		box(Rect2(24,y,340,62),Color(.026,.067,.060,.92*fade),Color("527c6b",fade))
		var tint: Color=reward.color;tint.a=fade
		var long_title: bool=font.get_string_size(String(reward.title),HORIZONTAL_ALIGNMENT_LEFT,-1,15).x>304.0
		if long_title:
			draw_multiline_string(font,Vector2(42,y+18),String(reward.title),HORIZONTAL_ALIGNMENT_LEFT,304,13,2,tint)
		else:label(reward.title,Vector2(42,y+24),15,tint)
		label(reward.detail,Vector2(42,y+54 if long_title else y+47),12,Color(.89,.92,.85,fade))

func draw_draft() -> void:
	draw_rect(Rect2(0,0,1440,900),Color(.008,.016,.024,.68))
	box(Rect2(157,133,1126,631),Color(.025,.039,.048,.96),Color("b08a57"))
	label("灰烬中的记忆",Vector2(205,203),30,ink)
	label("%s · 选择一项守夜能力" % game.run.reason,Vector2(205,244),16,amber)
	if game.opening_night_pending:
		label("先选本局路线（7/8/9 或点击），再用 1/2/3 铭刻核心；选卡后路线锁定。",Vector2(205,275),14,muted)
		var mode_names: Array[String]=["三夜教学","四夜·铁潮","四夜·暗翼"]
		var mode_keys: Array[String]=["7","8","9"]
		for i in mode_names.size():
			var mode_rect:=Rect2(198+i*349,286,315,54)
			mode_rects.append(mode_rect)
			var selected: bool=game.run_mode==["teaching","siege","echo"][i]
			box(mode_rect,Color(.105,.105,.078,.98) if selected else Color(.046,.066,.075,.97),amber if selected else Color("49605b"))
			label(mode_keys[i]+"  "+mode_names[i],mode_rect.position+Vector2(16,23),15,amber if selected else ink)
			label(game.run_mode_description() if selected else ["三夜入门 · 基础奖励易懂","四夜标准 · 重敌压门","四夜标准 · 灯光与快敌"][i],mode_rect.position+Vector2(16,43),11,muted)
	for i in range(game.run.offer.size()):
		var card: Dictionary=game.run.offer[i]
		var rect:=Rect2(198+i*349,355,315,330)
		card_rects.append(rect)
		var color: Color=RunBuild.COLORS[card.school]
		box(rect,Color(.046,.066,.075,.97),color.darkened(.36))
		label("%d" % (i+1),rect.position+Vector2(22,40),24,color,true)
		label(RunBuild.SCHOOLS[card.school]+" · "+RunBuild.RARITIES[card.rarity],rect.position+Vector2(58,39),14,color)
		label(card.name,rect.position+Vector2(23,117),23,ink)
		var lines:=String(card.desc).split("\n")
		for j in range(lines.size()):label(lines[j],rect.position+Vector2(23,168+j*29),15,muted)
		label("按 %d / 点击 铭刻" % (i+1),rect.position+Vector2(22,330),16,amber)
	label("世界已暂停 · 开局/黎明选卡，战斗记忆按 V 铭刻 · F 重抽 %d 次" % game.run.rerolls,Vector2(205,722),14,muted)

func draw_result() -> void:
	draw_rect(Rect2(0,0,1440,900),Color(.005,.012,.020,.71))
	var signal_ending: bool=game.victory and game.ending_key=="signal"
	var border:=Color("76bcb8") if signal_ending else (Color("b08a57") if game.victory else Color("b7655e"))
	box(Rect2(340,215,760,515),panel,border)
	var sunrise_title: String="第四次日出" if game.max_nights()==3 else "第五次日出"
	var title: String=sunrise_title if signal_ending else ("灯火未灭" if game.victory else ("哨站失守" if game.beacon_hp<=0 else "守望者倒下"))
	var title_width:=font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,36).x
	label(title,Vector2(720-title_width*.5,300),36,Color("a5dfda") if signal_ending else (amber if game.victory else red))
	label("%s  ·  守住 %d 夜  ·  清除 %d 只夜行体  ·  封闭夜巢 %d/3" % [game.run_mode_title(),game.day_number if game.victory else game.day_number-1,game.kills,game.cleansed_nests()],Vector2(425,362),18,ink)
	if signal_ending:
		label("林舟把 %d 夜的回声叠在一起，找到了曙光阵列的入口。" % game.max_nights(),Vector2(425,425),17,ink)
		label("哨站的人开始准备远行，而不再只是等待黑夜过去。",Vector2(425,464),16,muted)
	elif game.victory:
		label("灯塔撑过了 %d 夜，但荒原仍有 %d 处夜巢在呼吸。" % [game.max_nights(),game.remaining_nests()],Vector2(425,425),17,ink)
		label("许弦将零件留给下一次远征：先清理黑夜的源头。",Vector2(425,464),16,muted)
	else:
		label("灯塔的耐久归零，守夜的防线失守了。" if game.beacon_hp<=0 else "守望者没能回到灯下。哨站还在等待下一次出发。",Vector2(425,425),17,ink)
		label("下一次出城，需要更早回防或修复据点。",Vector2(425,464),16,muted)
	var home: Dictionary=game.homecoming_summary()
	label(home.record,Vector2(425,515),16,Color("a3c7b7"))
	label(home.response,Vector2(425,553),15,ink)
	if game.exploration:
		label(game.exploration.run_summary(),Vector2(425,585),14,Color("a6d9c6"))
		label(game.exploration.route_summary(),Vector2(425,610),13,Color("d6bf87"))
	label("按 Enter 重新开始一局",Vector2(611,675),18,muted)

func _gui_input(event: InputEvent) -> void:
	if game.phase in ["day","night"] and game.run.pending>0 and event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var point: Vector2=event.position*Vector2(1440,900)/get_viewport_rect().size
		if GROWTH_MEMORY_RECT.has_point(point):
			game.request_upgrade();accept_event();return
	if game.music_credits_open:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index==MOUSE_BUTTON_LEFT:
				var point: Vector2=event.position*Vector2(1440,900)/get_viewport_rect().size
				var sources:=["https://rustedstudio.itch.io/free-music-dark-ambient-piano","https://rustedstudio.itch.io/free-music-apocalypse-z","https://rustedstudio.itch.io/free-music-orchestral-fantasy-war","https://creativecommons.org/licenses/by/4.0/"]
				for i in sources.size():
					if Rect2(300+i*210,527,190,44).has_point(point):OS.shell_open(sources[i]);break
			accept_event()
		return
	if game.construction.active and game.phase in ["day","night"] and event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_LEFT:
			game.aim=game.ground_point(event.position)
			game.aim_sample_pending=false
			game.construction.confirm()
			accept_event();return
		if event.button_index==MOUSE_BUTTON_RIGHT:
			game.construction.cancel()
			accept_event();return
	if game.phase!="draft":return
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var point: Vector2=event.position*Vector2(1440,900)/get_viewport_rect().size
		for i in mode_rects.size():
			if mode_rects[i].has_point(point):game.select_run_mode(i);accept_event();return
		for i in card_rects.size():
			if card_rects[i].has_point(point):game.choose_card(i);accept_event();return
