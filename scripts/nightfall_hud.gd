extends Control
## Compact dark-fantasy HUD for the outpost loop.
var game: Node3D
var font: SystemFont
var display_font: SystemFont
var ink:=Color("e7e1d3")
var muted:=Color("a5aaa5")
var amber:=Color("e2a960")
var red:=Color("db756c")
var panel:=Color(.022,.035,.045,.88)
var card_rects: Array[Rect2] = []

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_PASS
	font=SystemFont.new()
	font.font_names=PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei","Noto Sans CJK SC"])
	display_font=SystemFont.new()
	display_font.font_names=PackedStringArray(["Bahnschrift","Segoe UI"])

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
	draw_combat_floats()
	box(Rect2(24,22,405,160),panel,Color("6c654f"))
	label("余烬哨站",Vector2(45,57),27,ink)
	label("最后的灯火  /  THE LAST LIGHT",Vector2(46,80),13,amber,true)
	var display_night: bool=game.phase=="night" or (game.phase=="draft" and game.return_phase=="night") or (game.phase=="paused" and game.paused_from=="night")
	var phase_name:="第 %d 夜 · 守卫" % game.day_number if display_night else "第 %d 日 · 搜寻" % game.day_number
	label(phase_name,Vector2(46,114),19,red if display_night else amber)
	label("距阶段结束  %02d:%02d" % [int(game.phase_time)/60,int(game.phase_time)%60],Vector2(46,147),17,muted)
	if game.phase=="night":
		var wave_text: String="夜袭 %d/%d 波" % [game.wave_index,game.WAVES_PER_NIGHT]
		if game.wave_index<game.WAVES_PER_NIGHT:wave_text+=" · 下一波 %02d 秒" % ceili(game.spawn_timer)
		label(wave_text,Vector2(46,166),13,red if game.world.wave_warning else amber)
	elif game.expeditions:
		label(game.expeditions.objective_text(),Vector2(46,170),13,Color("8dcfc3"))
	progress(Rect2(235,126,173,8),game.phase_time/(game.NIGHT_LENGTH if display_night else game.DAY_LENGTH),red if display_night else amber)
	draw_exploration_rewards()
	box(Rect2(1050,22,365,157),panel,Color("665343"))
	label("灯塔耐久",Vector2(1071,55),17,ink)
	label("%d / %d" % [int(game.beacon_hp),int(game.BEACON_MAX)],Vector2(1261,55),16,amber)
	progress(Rect2(1071,70,322,10),game.beacon_hp/game.BEACON_MAX,amber)
	label("零件  %d" % game.scrap,Vector2(1071,109),18,ink)
	label("清除夜行体  %d" % game.kills,Vector2(1247,109),14,muted)
	label("战斗记忆 %d / 100" % game.essence,Vector2(1071,146),14,muted)
	label("南门机关 %d / %d" % [game.gate_trap_charges,game.GATE_TRAP_MAX],Vector2(1244,146),14,amber)
	label("C 塔群集火  %s" % ("进行中 %.0fs" % game.focus_time if game.focus_time>0 else ("就绪" if game.focus_cooldown<=0 else "冷却 %.0fs" % game.focus_cooldown)),Vector2(1071,168),12,amber if game.focus_time>0 else muted)
	if game.beacon_alarm_time>0:
		var flash:=.72+.22*sin(float(Time.get_ticks_msec())*.018)
		draw_rect(Rect2(1051,23,363,155),Color("ef6b56",flash),false,2.4)
		box(Rect2(500,25,440,54),Color(.14,.025,.024,.93),Color("c46c58"))
		var alarm_text: String="灯塔遭攻击  -%d  ·  立即回防" % int(game.beacon_alarm_damage)
		var alarm_width:=font.get_string_size(alarm_text,HORIZONTAL_ALIGNMENT_LEFT,-1,20).x
		label(alarm_text,Vector2(720-alarm_width*.5,60),20,Color("ff9d80"))
	draw_minimap()
	if game.notice_time>0:
		box(Rect2(368,192,704,48),Color(.035,.046,.050,.86),Color("9a7051"))
		var width:=font.get_string_size(game.notice,HORIZONTAL_ALIGNMENT_LEFT,-1,19).x
		label(game.notice,Vector2(720-width*.5,224),19,ink)
	var prompt: String=game.interaction_prompt()
	if prompt!="" and game.phase!="draft":
		box(Rect2(492,670,456,48),Color(.032,.048,.050,.91),Color("b39761"))
		var width:=font.get_string_size(prompt,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x
		label(prompt,Vector2(720-width*.5,701),17,amber)
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
	label("ZASD/方向键移动  ·  右键移动  ·  F 搜集/建塔/升级/修灯  ·  H 修塔  ·  G 塔目标  ·  C 集火  ·  T 机关  ·  B 路障  ·  ESC 暂停",Vector2(323,863),12,muted)
	draw_combat_rewards()
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

func draw_combat_floats() -> void:
	if game.phase!="day" and game.phase!="night":return
	if game.music_credits_open or not is_instance_valid(game.combat) or not is_instance_valid(game.camera):return
	var canvas_size: Vector2=get_viewport_rect().size
	if canvas_size.x<=0.0 or canvas_size.y<=0.0:return
	var occupied: Array[Rect2]=[
		Rect2(24,22,405,160),Rect2(1050,22,365,157),
		Rect2(24,197,340,108+game.reward_toasts.size()*70),
		Rect2(1161,195,254,373),Rect2(300,746,840,129),Rect2(492,670,456,48)
	]
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
	label("防御塔 %d/8  ·  通信塔 %d/8" % [game.tower_count(),game.relay_count()],Vector2(1174,218),13,ink)
	var center:=Vector2(1288,319)
	var scale:=.86
	draw_rect(Rect2(center-Vector2(108,89),Vector2(216,178)),Color(.075,.085,.079,.84))
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
		draw_circle(center+Vector2(p.x,p.z)*scale,3.2,Color("ed945b") if pad.level>0 and pad.mode=="breaker" else (amber if pad.level>0 else Color("697473")))
	if game.expeditions:
		for site in game.expeditions.generators:
			var p: Vector3=site.position
			draw_rect(Rect2(center+Vector2(p.x,p.z)*scale-Vector2(3,3),Vector2(6,6)),Color("72dbb9") if site.state=="active" else (Color("536d64") if site.state=="complete" else Color("9bd3c4")))
		for camp in game.expeditions.camps:
			var p: Vector3=camp.npc.position if camp.state=="escort" else camp.position
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

func draw_exploration_rewards() -> void:
	if not game.discoveries:return
	var ready:=0
	for item in game.discoveries.items:
		if item.state=="ready" or item.state=="channel":ready+=1
	box(Rect2(24,197,322,108),panel,Color("497467"))
	label("荒原发现",Vector2(43,224),17,Color("a6decb"))
	label("探索 %d 次 · 里程碑 %d" % [game.exploration_count,game.exploration_milestones],Vector2(43,247),13,ink)
	var collected: int=game.exploration_count%5
	for i in 5:
		draw_circle(Vector2(49+i*20,272),4.5,Color("e8bc70") if i<collected else Color("3f5b55"))
	label("%d/5 · +35零件 +20记忆" % collected,Vector2(151,277),12,amber)
	label("荧光互动点 %d · 采集后会刷新" % ready,Vector2(43,298),11,muted)
	for i in game.reward_toasts.size():
		var reward: Dictionary=game.reward_toasts[game.reward_toasts.size()-1-i]
		var fade: float=minf(1.0,reward.time/.45)
		var y:=320.0+float(i)*70.0
		box(Rect2(24,y,340,62),Color(.026,.067,.060,.92*fade),Color("527c6b",fade))
		var tint: Color=reward.color;tint.a=fade
		label(reward.title,Vector2(42,y+24),15,tint)
		label(reward.detail,Vector2(42,y+47),12,Color(.89,.92,.85,fade))

func draw_draft() -> void:
	draw_rect(Rect2(0,0,1440,900),Color(.008,.016,.024,.68))
	box(Rect2(157,133,1126,631),Color(.025,.039,.048,.96),Color("b08a57"))
	label("灰烬中的记忆",Vector2(205,203),30,ink)
	label("%s · 选择一项守夜能力" % game.run.reason,Vector2(205,244),16,amber)
	for i in range(game.run.offer.size()):
		var card: Dictionary=game.run.offer[i]
		var rect:=Rect2(198+i*349,292,315,372)
		card_rects.append(rect)
		var color: Color=RunBuild.COLORS[card.school]
		box(rect,Color(.046,.066,.075,.97),color.darkened(.36))
		label("%d" % (i+1),rect.position+Vector2(22,40),24,color,true)
		label(RunBuild.SCHOOLS[card.school]+" · "+RunBuild.RARITIES[card.rarity],rect.position+Vector2(58,39),14,color)
		label(card.name,rect.position+Vector2(23,117),23,ink)
		var lines:=String(card.desc).split("\n")
		for j in range(lines.size()):label(lines[j],rect.position+Vector2(23,168+j*29),15,muted)
		label("按 %d / 点击 铭刻" % (i+1),rect.position+Vector2(22,330),16,amber)
	label("开局与每夜幸存后选卡 · F 重抽 %d 次 · 本局无装备" % game.run.rerolls,Vector2(205,722),14,muted)

func draw_result() -> void:
	draw_rect(Rect2(0,0,1440,900),Color(.005,.012,.020,.71))
	var signal_ending: bool=game.victory and game.ending_key=="signal"
	var border:=Color("76bcb8") if signal_ending else (Color("b08a57") if game.victory else Color("b7655e"))
	box(Rect2(340,215,760,468),panel,border)
	var title: String="第四次日出" if signal_ending else ("灯火未灭" if game.victory else "哨站失守")
	var title_width:=font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,36).x
	label(title,Vector2(720-title_width*.5,300),36,Color("a5dfda") if signal_ending else (amber if game.victory else red))
	label("守住 %d 夜  ·  清除 %d 只夜行体  ·  封闭夜巢 %d/3" % [game.day_number if game.victory else game.day_number-1,game.kills,game.cleansed_nests()],Vector2(425,362),18,ink)
	if signal_ending:
		label("林舟把三夜的回声叠在一起，找到了曙光阵列的入口。",Vector2(425,425),17,ink)
		label("哨站的人开始准备远行，而不再只是等待黑夜过去。",Vector2(425,464),16,muted)
	elif game.victory:
		label("灯塔撑过了第三夜，但荒原仍有 %d 处夜巢在呼吸。" % game.remaining_nests(),Vector2(425,425),17,ink)
		label("许弦将零件留给下一次远征：先清理黑夜的源头。",Vector2(425,464),16,muted)
	else:
		label("灯塔熄灭后，南门的哨灯也一盏盏暗了下去。",Vector2(425,425),17,ink)
		label("下一次出城，需要更早回防或修复据点。",Vector2(425,464),16,muted)
	label("按 Enter 重新开始一局",Vector2(611,606),18,muted)

func _gui_input(event: InputEvent) -> void:
	if game.music_credits_open:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index==MOUSE_BUTTON_LEFT:
				var point: Vector2=event.position*Vector2(1440,900)/get_viewport_rect().size
				var sources:=["https://rustedstudio.itch.io/free-music-dark-ambient-piano","https://rustedstudio.itch.io/free-music-apocalypse-z","https://rustedstudio.itch.io/free-music-orchestral-fantasy-war","https://creativecommons.org/licenses/by/4.0/"]
				for i in sources.size():
					if Rect2(300+i*210,527,190,44).has_point(point):OS.shell_open(sources[i]);break
			accept_event()
		return
	if game.phase!="draft":return
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var point: Vector2=event.position*Vector2(1440,900)/get_viewport_rect().size
		for i in card_rects.size():
			if card_rects[i].has_point(point):game.choose_card(i);accept_event();return
