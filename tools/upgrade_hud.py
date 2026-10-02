from pathlib import Path
p=Path(__file__).resolve().parents[1]/'scripts/hud.gd'
s=p.read_text(encoding='utf8').replace('shop_open','build_open').replace('draw_shop','draw_build').replace('"shop"','"build"')
s=s.replace('var mouse := Vector2.ZERO','var mouse := Vector2.ZERO\nvar menu_art: Texture2D')
s=s.replace('func _ready() -> void:\n','func _ready() -> void:\n\tif ResourceLoader.exists("res://assets/art/menu_v03.png"): menu_art=load("res://assets/art/menu_v03.png")\n')
s=s.replace('\tif game.mode == "ended":','\tif game.mode=="draft":\n\t\tbuttons.clear()\n\t\tdraw_draft()\n\tif game.mode == "ended":',1)
a=s.index('func draw_menu()');b=s.index('func draw_unit_bars()',a)
s=s[:a]+'''func draw_menu() -> void:
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

'''.replace('+\t','\t').replace('\n+','\n')+s[b:]
s=s.replace('"单机对局"','"命运对局"')
s=s.replace('text_at("Y 镜头切换  ·  空格回到英雄",Vector2(39,235),12,muted)','text_at("异变 %d · 下次 %ds · 重生 %d" % [game.evolution,ceili(game.next_evolution-game.elapsed),game.resurrection_left],Vector2(39,235),12,gold)')
s=s.replace('game.level * 90.0','game.level * 65.0')
s=s.replace('text_at("%d G" % game.gold, Vector2(853, 792), 23, gold, true)','text_at("%d /100" % game.essence, Vector2(853, 792), 22, gold, true)')
s=s.replace('"装备  TAB"','"构筑  TAB"')
s=s.replace('text_at("B 回城  ·  M 声音", Vector2(849, 864), 11, muted)','text_at("星尘 · 满值抽卡", Vector2(849, 864), 11, muted)')
s=s.replace('"%s  [%s]    冷却 %ds · 能量 %d" % [SKILLS[i], KEYS[i], game.COOLDOWNS[i], game.COSTS[i]]','"%s  [%s]    冷却 %.1fs · 能量 %d" % [SKILLS[i], KEYS[i], game.COOLDOWNS[i]*game.run.cooldown_factor(), game.COSTS[i]]')
a=s.index('func draw_build()');b=s.index('func draw_pause()',a)
s=s[:a]+'''func draw_draft() -> void:
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
		var lines: PackedStringArray=card.desc.split("\\n")
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
			row+=1
	button("build",Rect2(1020,742,260,47),"返回战场 [TAB]",true)
	text_at("种子 %d   ·   当前构筑仅在本局生效" % game.run.seed_value,Vector2(154,774),12,muted)

'''.replace('+\t','\t').replace('\n+','\n')+s[b:]
s=s.replace('"TAB 装备 / 滚轮缩放 / ESC 暂停 / M 音效"','"TAB 构筑 / 滚轮缩放 / ESC 暂停 / M 音效"')
s=s.replace('"野怪脱战归位回血，击败后 45 秒刷新"','"升级 / 星尘 / 推塔获得选卡，第四次阵亡结束本局"')
s=s.replace('centered("等级 %d    卫兵击败 %d    总波次 %d" % [game.level,game.last_hits,game.wave_number]','centered("等级 %d    铭刻卡牌 %d    裂隙异变 %d" % [game.level,game.run.selections,game.evolution]')
s=s.replace('if id.begins_with("buy"): game.buy(int(id.trim_prefix("buy")))','''if id.begins_with("pick"): game.select_card(int(id.trim_prefix("pick")))
			elif id=="reroll": game.run.redraw()
			elif id.begins_with("focus"): game.run.focus=int(id.trim_prefix("focus"))'''.replace('+\t','\t'))
p.write_text(s,encoding='utf8')
