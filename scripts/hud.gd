extends Control
## Resolution-independent vector HUD. All labels and controls are Chinese.
var game: Node3D
var font: SystemFont
var display_font: SystemFont
var buttons: Array[Dictionary] = []
var hide_pause: bool = false
var ink := Color("e7efe9")
var muted := Color("839b9d")
var cyan := Color("67dce5")
var gold := Color("d5b57b")
var panel := Color(0.025, 0.055, 0.074, 0.95)
var mouse := Vector2.ZERO
var menu_art: Texture2D
const SKILLS := ["裂光", "星环", "瞬步", "星陨", "复苏"]
const KEYS := ["Q", "W", "E", "R", "D"]
const DESCRIPTIONS := ["向鼠标方向释放穿透光刃，射程 13 米", "震击周围 4.2 米，并获得持续 4 秒的护盾", "向鼠标方向闪进，最远 6.2 米", "轰击鼠标区域，4 级解锁，射程 11 米", "立即恢复 35% 最大生命值"]

func _ready() -> void:
	if ResourceLoader.exists("res://assets/art/menu_v03.png"): menu_art=load("res://assets/art/menu_v03.png")
	mouse_filter = Control.MOUSE_FILTER_PASS
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	display_font = SystemFont.new()
	display_font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI"])

func virtual_mouse() -> Vector2:
	return get_global_mouse_position() * Vector2(1440, 900) / get_viewport_rect().size

func text_at(value: String, point: Vector2, size_px: int = 16, color: Color = Color("e7efe9"), display: bool = false) -> void:
	draw_string(display_font if display else font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

func centered(value: String, point: Vector2, size_px: int, color: Color) -> void:
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	text_at(value, point - Vector2(width * .5, 0), size_px, color)

func frame(rect: Rect2, color: Color = Color(0.025, 0.055, 0.074, 0.95), outline: Color = Color("30474d")) -> void:
	draw_style_box(style(color, outline), rect)

func style(color: Color, outline: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = outline
	box.set_border_width_all(1)
	box.set_corner_radius_all(5)
	return box

func button(id: String, rect: Rect2, label: String, primary: bool = false) -> void:
	var hover := rect.has_point(mouse)
	frame(rect, Color("294b51") if hover else (Color("163740") if primary else panel), gold if primary else Color("3c5960"))
	centered(label, rect.get_center() + Vector2(0, 7), 20 if primary else 16, ink if hover else (gold if primary else ink))
	buttons.append({"id": id, "rect": rect})

func _draw() -> void:
	if not is_instance_valid(game) or not is_instance_valid(game.player): return
	draw_set_transform(Vector2.ZERO, 0, get_viewport_rect().size / Vector2(1440, 900))
	mouse = virtual_mouse()
	buttons.clear()
	if game.mode == "menu":
		draw_menu()
		return
	draw_unit_bars()
	draw_match_hud()
	if game.build_open:
		buttons.clear()
		draw_build()
	if game.help_open:
		buttons.clear()
		draw_help()
	if game.mode == "paused" and not hide_pause:
		buttons.clear()
		draw_pause()
	if game.mode=="draft":
		buttons.clear()
		draw_draft()
	if game.mode == "ended":
		buttons.clear()
		draw_result()

func draw_menu() -> void:
	if menu_art:
		draw_texture_rect(menu_art,Rect2(0,0,1440,900),false)
	else: draw_rect(Rect2(0,0,1440,900),Color(.01,.025,.035,.45))
	frame(Rect2(57,53,590,795),Color(.02,.045,.055,.88),Color("52645e"))
	text_at("ROGUELITE  /  MOBA",Vector2(98,114),15,gold,true)
	draw_line(Vector2(98,135),Vector2(151,135),gold,2)
	text_at("RIFTWARD",Vector2(93,238),65,ink,true)
	text_at("裂 隙 守 望",Vector2(99,297),32,gold)
	text_at("每一次命运，都是新的战法。",Vector2(99,357),20,ink)
	text_at("抽取赐福，构筑英雄，攻破三路战场。",Vector2(99,394),16,muted)
	text_at("无装备 · 三选一卡牌 · 三次重生 · 局内构筑",Vector2(99,423),14,muted)
	text_at("选择命运倾向",Vector2(99,479),14,gold)
	for i in range(3):
		var rect:=Rect2(99+i*166,497,150,68)
		button("focus%d" % i,rect,RunBuild.SCHOOLS[i],game.run.focus==i)
	text_at("倾向卡牌权重 +60%，仍可自由混搭三个流派",Vector2(99,593),13,muted)
	button("start",Rect2(99,628,482,64),"开启命运之战   →",true)
	text_at("右键移动 / 攻击   ·   QWER 技能   ·   TAB 构筑",Vector2(99,738),14,muted)
	text_at("三路 3v3 · 18 张命运卡 · 全程离线",Vector2(99,771),14,muted)
	text_at("CHAPTER 01  /  THE AETHER GARDEN",Vector2(99,819),11,gold,true)
	text_at("0.3  ·  命运回响",Vector2(1220,854),14,gold)

func draw_unit_bars() -> void:
	var viewport_scale := Vector2(1440, 900) / get_viewport_rect().size
	for unit in game.units:
		if not unit.alive or game.camera.is_position_behind(unit.position): continue
		var height: float = 3.9 if unit.is_structure() else (3.0 if unit.kind in ["hero","monster"] else 1.6)
		var screen: Vector2 = game.camera.unproject_position(unit.position + Vector3.UP * height) * viewport_scale
		if screen.x < -100 or screen.x > 1540 or screen.y < 0 or screen.y > 745: continue
		var width := 84.0 if unit.kind == "hero" else (100.0 if unit.is_structure() else 38.0)
		var rect := Rect2(screen - Vector2(width / 2, 0), Vector2(width, 6))
		draw_rect(rect.grow(2), Color("071319"))
		draw_rect(Rect2(rect.position, Vector2(width * unit.hp / unit.max_hp, 6)), unit.faction_color())
		if unit.shield > 0:
			draw_rect(Rect2(rect.position - Vector2(0, 3), Vector2(width * minf(1, unit.shield / unit.max_hp), 2)), Color("ffffff"))
		if unit.kind in ["hero","monster"]: centered(unit.title, screen - Vector2(0, 10), 12, ink if unit.kind=="hero" else gold)
		if game.protected_structure(unit): centered("护盾保护", screen - Vector2(0, 9), 11, muted)
	for number in game.damage_numbers:
		var screen: Vector2 = game.camera.unproject_position(number.point) * viewport_scale
		screen.y -= (0.85 - number.ttl) * 48
		text_at(str(number.value), screen, 20, gold if number.team == 0 else Color("ff8390"), true)

func draw_match_hud() -> void:
	frame(Rect2(22, 20, 263, 64))
	text_at("RIFTWARD", Vector2(39, 47), 20, gold, true)
	text_at("裂隙守望   /   苍穹裂谷", Vector2(39, 69), 12, muted)
	frame(Rect2(490, 16, 460, 63))
	text_at("苍穹", Vector2(510, 53), 16, cyan)
	text_at("%02d" % game.team_scores[0], Vector2(570, 57), 27, cyan, true)
	centered("%02d : %02d" % [int(game.elapsed) / 60, int(game.elapsed) % 60], Vector2(720, 44), 22, ink)
	centered("第 %d 波  ·  下波 %ds" % [game.wave_number, ceili(game.wave_timer)], Vector2(720, 66), 11, muted)
	text_at("%02d" % game.team_scores[1], Vector2(830, 57), 27, Color("ee7c88"), true)
	text_at("绯红", Vector2(886, 53), 16, Color("ee7c88"))
	frame(Rect2(1205, 20, 212, 64))
	draw_circle(Vector2(1225, 43), 4, cyan)
	text_at("命运对局", Vector2(1240, 49), 15, ink)
	text_at("F1 帮助  /  ESC 暂停", Vector2(1224, 71), 12, muted)
	frame(Rect2(22, 99, 263, 158), Color(.03, .065, .08, .84))
	text_at("当前目标", Vector2(39, 126), 12, gold)
	var tower_count := 0
	for unit in game.units:
		if unit.team == 1 and unit.kind == "tower" and unit.alive: tower_count += 1
	text_at("推通任意一路" if game.protected_structure(game.cores[1]) else "摧毁绯红核心", Vector2(39, 154), 20, ink)
	text_at("敌方守塔 %d / 6   ·   野怪 %d" % [tower_count, game.jungle_kills], Vector2(39, 178), 12, muted)
	for lane in range(3):
		var remaining := 0
		for unit in game.units:
			if unit.alive and unit.team==1 and unit.kind=="tower" and unit.lane==lane: remaining+=1
		text_at("%s %d/2" % [BattleMap.LANE_NAMES[lane],remaining],Vector2(39+lane*79,205),12,cyan if remaining==0 else muted)
	text_at("异变 %d · 下次 %ds · 重生 %d" % [game.evolution,ceili(game.next_evolution-game.elapsed),game.resurrection_left],Vector2(39,235),12,gold)
	if game.vigor_time>0 or game.power_time>0:
		frame(Rect2(22,270,263,54))
		text_at("恢复 %ds   ·   强攻 %ds" % [ceili(game.vigor_time),ceili(game.power_time)],Vector2(39,303),15,gold)
	if game.notice_time > 0:
		var width := font.get_string_size(game.notice, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 58
		frame(Rect2(720 - width / 2, 106, width, 45), Color(.025, .055, .074, .92), Color("52665c"))
		centered(game.notice, Vector2(720, 135), 18, gold)
	var interaction: String = game.interaction_prompt()
	if interaction != "":
		var width := font.get_string_size(interaction, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 44
		frame(Rect2(720-width*.5,691,width,38),Color(.03,.065,.07,.90),Color("759688"))
		centered(interaction,Vector2(720,716),16,gold)
	# Bottom character panel.
	frame(Rect2(22, 754, 345, 124))
	frame(Rect2(37, 770, 66, 86), Color("143440"), gold)
	icon(Vector2(70, 806), 0, cyan, 1.2)
	centered("Lv.%d" % game.level, Vector2(70, 846), 14, gold)
	text_at("苍曜 · 星刃", Vector2(117, 783), 17, ink)
	bar(Rect2(117, 798, 231, 13), game.player.hp / game.player.max_hp, Color("46c4aa"))
	centered("%d / %d" % [game.player.hp, game.player.max_hp], Vector2(232, 809), 10, ink)
	bar(Rect2(117, 817, 231, 7), game.mana / game.max_mana, Color("58a9d0"))
	text_at("攻击 %d  ·  移速 %.1f" % [game.player.damage, game.player.speed], Vector2(117, 848), 12, muted)
	bar(Rect2(117, 860, 231, 3), game.experience / (game.level * 65.0), gold)
	# Ability bar and item access.
	frame(Rect2(385, 754, 608, 124))
	for i in range(5):
		var rect := Rect2(403 + i * 86, 769, 73, 73)
		var locked: bool = i == 3 and game.level < 4
		frame(rect, Color("102c37"), Color("38575f") if not locked else Color("343e45"))
		icon(rect.get_center() - Vector2(0, 4), i, muted if locked else (gold if i == 3 else cyan))
		if game.cooldowns[i] > 0:
			draw_rect(rect, Color(0, .025, .035, .74))
			centered(str(ceili(game.cooldowns[i])), rect.get_center() + Vector2(0, 4), 26, ink)
		if locked: centered("4 级", rect.get_center() + Vector2(0, 4), 17, gold)
		frame(Rect2(rect.position + Vector2(3, 3), Vector2(19, 18)), Color("081921"), Color("38575f"))
		text_at(KEYS[i], rect.position + Vector2(7, 17), 13, ink, true)
		centered(SKILLS[i], Vector2(rect.get_center().x, 864), 13, muted)
		if rect.has_point(mouse) and not game.build_open and not game.help_open:
			frame(Rect2(402, 668, 540, 68))
			text_at("%s  [%s]    冷却 %.1fs · 能量 %d" % [SKILLS[i], KEYS[i], game.COOLDOWNS[i]*game.run.cooldown_factor(), game.COSTS[i]], Vector2(419, 694), 14, gold)
			text_at(DESCRIPTIONS[i], Vector2(419, 720), 13, ink)
		buttons.append({"id": "skill%d" % i, "rect": rect})
	text_at("%d /100" % game.essence, Vector2(853, 792), 22, gold, true)
	button("build", Rect2(848, 803, 127, 40), "构筑  TAB")
	text_at("星尘 · 满值抽卡", Vector2(849, 864), 11, muted)
	draw_minimap()
	if not game.player.alive:
		frame(Rect2(538, 574, 364, 96), panel, Color("77545e"))
		centered("等待重生  %d" % ceili(game.player_respawn), Vector2(720, 615), 26, ink)
		centered("泉水将恢复全部生命与能量", Vector2(720, 647), 14, muted)
	if game.recall_time > 0:
		frame(Rect2(559, 668, 322, 58))
		centered("正在回城  %.1fs" % game.recall_time, Vector2(720, 694), 16, cyan)
		bar(Rect2(575, 707, 290, 4), 1 - game.recall_time / 4.0, cyan)
	if game.muted: text_at("静音", Vector2(1150, 52), 13, muted)

func bar(rect: Rect2, ratio: float, color: Color) -> void:
	draw_rect(rect, Color("11252e"))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(ratio, 0, 1), rect.size.y)), color)

func draw_minimap() -> void:
	var rect := Rect2(1185, 676, 233, 202)
	frame(rect)
	text_at("战术地图", Vector2(1200, 700), 13, gold)
	text_at("左看 / 右走", Vector2(1340, 700), 10, muted)
	var area := Rect2(1200, 715, 203, 143)
	draw_rect(area, Color("19362f"))
	draw_rect(Rect2(1293, 715, 18, 143), Color("205261"))
	for lane in range(3):
		var line := PackedVector2Array()
		for point in BattleMap.route(lane): line.append(BattleMap.minimap_position(point,area))
		draw_polyline(line,Color("657468"),8,true)
	for forest in BattleMap.FORESTS: draw_circle(BattleMap.minimap_position(forest,area),6,Color("0e2820"))
	for unit in game.units:
		if not unit.alive:
			if unit.kind=="monster":
				var camp_point := BattleMap.minimap_position(unit.home_point,area)
				text_at(str(ceili(unit.respawn_timer)),camp_point+Vector2(-4,3),8,muted)
			continue
		var pos := BattleMap.minimap_position(unit.position,area)
		var color: Color = unit.faction_color()
		if unit.is_structure(): draw_rect(Rect2(pos - Vector2(4, 4), Vector2(8, 8)), color)
		else: draw_circle(pos, 4 if unit.kind == "hero" else 1.8, color)
		if unit == game.player: draw_arc(pos, 7, 0, TAU, 20, Color.WHITE, 1.5)
	var center := BattleMap.minimap_position(game.camera.position-Vector3(0,26,22),area)
	var camera_rect := Rect2(center-Vector2(34,23),Vector2(68,46)).intersection(area)
	draw_rect(camera_rect,Color(1,1,1,.3),false,1)

func icon(center: Vector2, index: int, color: Color, scale_factor: float = 1.0) -> void:
	var r := 19.0 * scale_factor
	match index:
		0:
			draw_colored_polygon(PackedVector2Array([center+Vector2(-r*.7,r*.7),center+Vector2(-r*.1,-r*.6),center+Vector2(r*.8,-r),center+Vector2(r*.6,r*.1)]),color)
			draw_line(center+Vector2(-r,r*.3),center+Vector2(-r*.2,r),gold,3)
		1:
			draw_arc(center, r, 0, TAU, 32, color, 2.5)
			draw_arc(center, r*.58, -.7, 4.7, 24, color, 2)
			draw_circle(center, 3, color)
		2:
			for j in range(3):
				var p := center + Vector2((j-1)*12, 0)
				draw_polyline(PackedVector2Array([p+Vector2(-6,-13),p+Vector2(5,0),p+Vector2(-6,13)]),color,2.5)
		3:
			var points := PackedVector2Array()
			for i in range(8): points.append(center + Vector2(cos(i*PI/4),sin(i*PI/4)) * (r if i%2 == 0 else r*.33))
			draw_colored_polygon(points,color)
			draw_arc(center,r*1.2,0,TAU,32,color,1)
		4:
			draw_line(center-Vector2(0,r*.7),center+Vector2(0,r*.7),Color("8ae6af"),5)
			draw_line(center-Vector2(r*.7,0),center+Vector2(r*.7,0),Color("8ae6af"),5)

func draw_draft() -> void:
	draw_rect(Rect2(0,0,1440,900),Color(.006,.015,.026,.90))
	centered("FATE   AWAKENS",Vector2(720,103),18,gold)
	centered("命 运 赐 福",Vector2(720,159),39,ink)
	centered(game.run.reason,Vector2(720,200),16,muted)
	centered("战场已暂停  ·  三选一立即生效  ·  本局保留，重开重置",Vector2(720,233),13,muted)
	for i in game.run.offer.size():
		var card: Dictionary=game.run.offer[i]
		var rect:=Rect2(195+i*358,271,334,405)
		var color: Color=RunBuild.COLORS[card.school]
		var hover:=rect.has_point(mouse)
		frame(rect,Color("112935") if hover else Color("0b1c28"),color if hover else color.darkened(.4))
		draw_line(rect.position+Vector2(20,2),rect.position+Vector2(314,2),color,3)
		centered(RunBuild.RARITIES[card.rarity]+"  /  "+RunBuild.SCHOOLS[card.school],Vector2(rect.get_center().x,307),13,color)
		card_emblem(Vector2(rect.get_center().x,380),card.school,card.rarity,color)
		centered(card.name,Vector2(rect.get_center().x,468),25,ink)
		var lines: PackedStringArray=card.desc.split("\n")
		for j in lines.size(): centered(lines[j],Vector2(rect.get_center().x,516+j*25),14,muted)
		centered("当前 %d / %d  →  %d / %d" % [game.run.count(card.id),card.cap,game.run.count(card.id)+1,card.cap],Vector2(rect.get_center().x,597),12,color)
		centered("[ %d ]    铭刻此命运" % (i+1),Vector2(rect.get_center().x,642),17,ink)
		buttons.append({"id":"pick%d" % i,"rect":rect})
	button("reroll",Rect2(542,716,356,47),"重抽 [F]  ·  剩余 %d 次" % game.run.rerolls)
	centered("第 %d 次选卡  ·  每第 5 次选卡保证出现传奇  ·  待选 %d 次" % [game.run.selections+1,game.run.pending],Vector2(720,802),13,muted)
	centered("强袭 3/6：暴击与汲取   /   秘术 3/6：急速与法强   /   守御 3/6：护甲与周期护盾",Vector2(720,838),12,gold)

func card_emblem(center: Vector2, school: int, rarity: int, color: Color) -> void:
	for i in range(3):
		draw_arc(center,43+i*8,-PI*.88,PI*.88,48,Color(color,.18+i*.10),1)
	draw_colored_polygon(PackedVector2Array([center+Vector2(0,-47),center+Vector2(36,0),center+Vector2(0,47),center+Vector2(-36,0)]),Color(color,.10))
	icon(center,[0,3,1][school],color,1.65)
	for i in range(rarity+1): draw_circle(center+Vector2((i-rarity*.5)*12,68),2.5,color)

func draw_build() -> void:
	draw_rect(Rect2(0,0,1440,900),Color(.005,.015,.024,.9))
	frame(Rect2(116,77,1208,747),panel,gold)
	text_at("命运构筑",Vector2(151,128),31,ink)
	text_at("战场已暂停 · 卡牌强化即为本局成长",Vector2(151,162),14,muted)
	text_at("铭刻 %d 张 / 重生 %d 次" % [game.run.selections,game.resurrection_left],Vector2(940,126),17,gold)
	var values: Array[String]=[
		"生命  %d" % game.player.max_hp,"攻击  %.0f" % game.player.damage,
		"法强  %.0f" % game.run.stats.spell,"护甲  %.0f" % game.player.armor,
		"攻速  %.2f /秒" % (1/game.player.attack_interval),"暴击  %.0f%%" % (game.run.stats.crit*100),
		"汲取  %.0f%%" % (game.run.stats.lifesteal*100),"急速  %.0f" % game.run.stats.haste,
		"移速  %.2f" % game.player.speed,"生命恢复  %.0f /秒" % (2+game.run.stats.regen),
		"能量  %d" % game.max_mana,"范围倍率  %.2f" % game.run.stats.area]
	for i in values.size(): text_at(values[i],Vector2(154+(i%4)*285,212+(i/4)*35),16,ink)
	for school in range(3):
		var x:=153+school*386
		var color: Color=RunBuild.COLORS[school]
		text_at("%s   %d 层" % [RunBuild.SCHOOLS[school],game.run.school_count(school)],Vector2(x,350),21,color)
		text_at(["3层：暴击+10% / 6层：汲取+10%","3层：急速+15 / 6层：法强+45","3层：护甲+15 / 6层：回血与周期护盾"][school],Vector2(x,382),12,muted)
		var row:=0
		for card in RunBuild.CARDS:
			if card.school!=school: continue
			var count: int=game.run.count(card.id)
			text_at(card.name,Vector2(x,429+row*42),16,color if count else muted.darkened(.30))
			text_at("%d / %d" % [count,card.cap],Vector2(x+266,429+row*42),14,gold if count else muted)
			if Rect2(x,409+row*42,330,32).has_point(mouse):
				frame(Rect2(365,650,710,71),Color("142b35"),color)
				var lines: PackedStringArray=card.desc.split("\n")
				for j in lines.size(): centered(lines[j],Vector2(720,678+j*24),14,ink)
			row+=1
	button("build",Rect2(1020,742,260,47),"返回战场 [TAB]",true)
	text_at("种子 %d   ·   当前构筑仅在本局生效" % game.run.seed_value,Vector2(154,774),12,muted)

func draw_pause() -> void:
	draw_rect(Rect2(0, 0, 1440, 900), Color(.01, .025, .035, .72))
	frame(Rect2(493, 279, 454, 339), panel, gold)
	centered("战场已暂停", Vector2(720, 339), 32, ink)
	centered("稍作休整，下一次出击由你决定。", Vector2(720, 375), 15, muted)
	button("resume", Rect2(551, 410, 338, 54), "继续战斗", true)
	button("restart", Rect2(551, 482, 160, 45), "重新开始")
	button("quit", Rect2(729, 482, 160, 45), "退出游戏")
	centered("ESC 继续  ·  M 切换音效", Vector2(720, 581), 13, muted)

func draw_help() -> void:
	draw_rect(Rect2(0, 0, 1440, 900), Color(.01, .025, .035, .7))
	frame(Rect2(390, 169, 660, 537), panel, gold)
	text_at("战场指南", Vector2(428, 224), 30, ink)
	var rows := ["右键移动 / 攻击；方向键移动；S 停止", "Q 光刃 / W 护盾 / E 瞬步 / R 星陨（4 级）", "D 治疗 / B 回城；回城会被移动或攻击打断", "TAB 构筑 / 滚轮缩放 / ESC 暂停 / M 音效", "左键小地图看战场，右键小地图移动", "Y 切换跟随镜头；空格回到英雄", "上中下三路各两塔，推通任意一路解锁敌方核心", "友方两名 AI 分别支援上下路，敌方三名 AI 出战", "右键野怪开战；击败获得金币、经验和 45 秒增益", "升级 / 星尘 / 推塔获得选卡，第四次阵亡结束本局"]
	for i in rows.size(): text_at(rows[i], Vector2(428, 268+i*33), 15, muted if i<7 else gold)
	button("help", Rect2(820, 633, 189, 45), "明白，继续战斗", true)

func draw_result() -> void:
	draw_rect(Rect2(0, 0, 1440, 900), Color(.01, .025, .035, .76))
	frame(Rect2(450, 247, 540, 394), panel, gold)
	centered("VICTORY" if game.winner == 0 else "DEFEAT", Vector2(720, 316), 44, gold if game.winner == 0 else Color("ff8297"))
	centered("裂隙，重归宁静。" if game.winner == 0 else "星火未熄，再战一局。", Vector2(720, 366), 25, ink)
	centered("用时 %02d:%02d    击败 %d    倒下 %d" % [int(game.elapsed)/60,int(game.elapsed)%60,game.kills,game.deaths], Vector2(720, 424), 17, muted)
	centered("等级 %d    铭刻卡牌 %d    裂隙异变 %d" % [game.level,game.run.selections,game.evolution], Vector2(720, 460), 15, muted)
	button("restart", Rect2(523, 510, 394, 55), "再来一局", true)
	button("quit", Rect2(620, 583, 200, 37), "退出游戏")

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var point: Vector2 = event.position * Vector2(1440, 900) / get_viewport_rect().size
		if event.button_index == MOUSE_BUTTON_LEFT:
			for entry in buttons:
				if entry.rect.has_point(point):
					activate(entry.id)
					accept_event()
					return
			if game.mode=="playing" and not game.build_open and not game.help_open:
				var area := Rect2(1200,715,203,143)
				if area.has_point(point):
					game.camera_focus=BattleMap.minimap_world(point,area)
					game.camera_locked=false
					accept_event()
					return
		if event.button_index == MOUSE_BUTTON_RIGHT and game.mode == "playing" and not game.build_open and not game.help_open:
			var map_area := Rect2(1200, 715, 203, 143)
			if map_area.has_point(point):
				game.command_move(BattleMap.minimap_world(point,map_area))
				accept_event()
				return
		if game.mode != "playing" or game.build_open or game.help_open or point.y > 752:
			accept_event()

func activate(id: String) -> void:
	match id:
		"start": game.start_match()
		"resume":
			game.mode = "playing"
			game.open_draft()
		"restart": get_tree().reload_current_scene()
		"quit": get_tree().quit()
		"build": game.build_open = not game.build_open
		"help": game.help_open = false
		_:
			if id.begins_with("pick"): game.select_card(int(id.trim_prefix("pick")))
			elif id=="reroll": game.run.redraw()
			elif id.begins_with("focus"): game.run.focus=int(id.trim_prefix("focus"))
			elif id.begins_with("skill"): game.cast(int(id.trim_prefix("skill")))
