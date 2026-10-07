extends RefCounted
## Read-only presentation for the live HUD. Route estimates are supplied by the
## owning Control; painting never asks navigation to calculate a new path.

const PHASE_RECT := Rect2(24,20,238,62)
const OBJECTIVE_RECT := Rect2(426,20,588,76)
const RESOURCE_RECT := Rect2(1080,20,336,54)
const HERO_RECT := Rect2(344,816,752,64)
const MEMORY_RECT := Rect2(1108,800,104,80)
const MEMORY_DRAW_RECT := Rect2(1108,816,104,64)
const TACTICS_RECT := Rect2(24,824,126,36)
const MAP_BUTTON_RECT := Rect2(164,824,96,36)
const BUILD_BUTTON_RECT := Rect2(272,824,64,36)
const SELECTED_SQUAD_RECT := Rect2(24,762,300,54)
const DRAWER_RECT := Rect2(24,112,540,622)
const DRAWER_CLOSE_RECT := Rect2(428,692,112,30)
const TAB_IDS := ["contract","exploration","army","defense","help"]
const TAB_TITLES := ["委托","探索","部队","防线","操作"]
const TEXT_X := 46.0
const TEXT_WIDTH := 496.0
const GREEN := Color("a3d7bd")
const BLUE := Color("8ec8d8")
const RAIL := Color("82978b")
const RAIL_FAINT := Color("82978b", .19)
const RAIL_GHOST := Color("82978b", .10)
const LIVE_INK := Color("e4e2d8")
const LIVE_MUTED := Color("9da9a2")
const LIVE_QUIET := Color("b2bcb5", .88)
const FOCUS_RAIL := Color("9bb6a6", .24)
const FOCUS_GHOST := Color("9bb6a6", .10)
# Short status groups share a quiet dark backing. Reducing the number of
# persistent sections matters more than making necessary text transparent.
const PHASE_FILL := Color(.020,.031,.033,0.0)
const OBJECTIVE_DAY_FILL := Color(.020,.035,.031,0.0)
const OBJECTIVE_NIGHT_FILL := Color(.045,.027,.026,.015)
const RESOURCE_FILL := Color(.020,.031,.033,0.0)
const HERO_FILL := Color(.015,.026,.029,0.0)
const DRAWER_FILL := Color(.021,.037,.040,.96)

static func draw_live(ui: Control) -> void:
	var game: Node3D=ui.get("game") as Node3D
	if not is_instance_valid(game) or not is_instance_valid(game.hero):return
	_draw_focus_rails(ui,game)
	var phase:=_phase(game)
	_draw_phase(ui,game,phase)
	_draw_objective(ui,game,phase)
	_draw_resources(ui,game)
	_draw_hero(ui,game)
	_draw_navigation_buttons(ui,game)
	_draw_notice(ui,game)
	if not game.construction.active and String(ui.get("detail_tab")) in TAB_IDS:
		_draw_drawer(ui,game,String(ui.get("detail_tab")))
	elif not game.construction.active:
		_draw_active_tags(ui,game)

static func _draw_focus_rails(ui: Control, game: Node3D) -> void:
	# One quiet frame replaces the old stack of independent cards. It separates
	# the playable world from the two intentional information bands without
	# adding another panel or intercepting any input.
	var phase:=_phase(game)
	var accent: Color=Color(ui.red,.48) if phase=="night" else Color(ui.amber,.42)
	ui.draw_line(Vector2(24,79),Vector2(1416,79),RAIL_GHOST,1.0)
	ui.draw_line(Vector2(24,802),Vector2(1416,802),RAIL_GHOST,1.0)
	ui.draw_line(Vector2(24,79),Vector2(24,91),Color(accent,.44),1.0)
	ui.draw_line(Vector2(1416,79),Vector2(1416,91),RAIL_FAINT,1.0)
	ui.draw_line(Vector2(344,802),Vector2(1096,802),Color(accent,.30),1.0)

static func _phase(game: Node3D) -> String:
	if game.phase=="paused":return String(game.paused_from)
	if game.phase=="draft":return String(game.return_phase)
	return String(game.phase)

static func _draw_phase(ui: Control, game: Node3D, phase: String) -> void:
	var night:=phase=="night"
	var tint: Color=ui.red if night else ui.amber
	var quiet_tint: Color=Color(LIVE_QUIET, .66) if bool(ui.get("minimal_display")) else LIVE_QUIET
	# The live view uses one quiet top rail. The rectangle remains part of the
	# logical exclusion map, but the visual layer is reduced to one phase chip,
	# one clock and a hairline timer so the battlefield stays dominant.
	ui.box(PHASE_RECT,PHASE_FILL,Color(0,0,0,0))
	ui.draw_line(Vector2(24,26),Vector2(24,70),Color(tint,.56),1.5)
	ui.draw_circle(Vector2(35,37),3.0,Color(tint,.88))
	ui.label("D%d · %s" % [game.day_number,"夜" if night else "日"],Vector2(47,41),15,tint)
	var seconds:=maxi(0,ceili(float(game.phase_time)))
	var clearance: Dictionary=game.night_clearance_snapshot() if night else {}
	var clearing:=bool(clearance.get("active",false))
	if clearing:
		var elapsed:=floori(float(clearance.elapsed))
		ui.label("清场 %02d:%02d" % [elapsed/60,elapsed%60],Vector2(116,41),15,LIVE_INK)
		ui.label("残敌%d · 飞弹%d" % [int(clearance.remaining),int(clearance.projectiles)],Vector2(47,60),11,quiet_tint)
	else:
		ui.label("%02d:%02d" % [seconds/60,seconds%60],Vector2(116,41),15,LIVE_INK)
	# In focus mode the center objective already carries the wave/contract
	# context, so the second phase line is reserved for the live clearing count.
	# The full tactical drawer still exposes the same information on demand.
	if not bool(ui.get("minimal_display")):
		if night and not clearing:
			ui.label("第%d/%d波" % [game.wave_index,game.WAVES_PER_NIGHT],Vector2(45,60),11,quiet_tint)
		elif not night:
			ui.label("整备窗口",Vector2(45,60),11,quiet_tint)
	var length: float=game.NIGHT_LENGTH if night else game.DAY_LENGTH
	ui.draw_line(Vector2(47,72),Vector2(236,72),Color(tint,.12),1.0)
	ui.draw_line(Vector2(47,72),Vector2(47+189.0*clampf(float(game.phase_time)/length,0.0,1.0),72),Color(tint,.62),1.0)

static func _draw_objective(ui: Control, game: Node3D, phase: String) -> void:
	var boss: Dictionary=game.boss_snapshot() if phase=="night" else {}
	var state:=_objective_copy(game,phase)
	var rect:=objective_rect(ui,game)
	ui.box(rect,OBJECTIVE_NIGHT_FILL if phase=="night" else OBJECTIVE_DAY_FILL,Color(0,0,0,0))
	var accent:=Color("c77c65",.82) if phase=="night" else Color("73aa92",.78)
	# The focus layout uses a single vertical marker instead of a card edge.
	# Detailed route and counter information stays in F3 so the world remains dominant.
	ui.draw_line(rect.position+Vector2(4,10),rect.position+Vector2(4,rect.size.y-8),accent,1.5)
	if not boss.is_empty():
		_draw_boss(ui,game,boss)
		return
	var title_point:=rect.position+Vector2(18,24)
	_paragraph(ui,String(state.title),title_point,552,17,ui.amber if phase=="night" else GREEN,20,1)
	if not String(state.detail).is_empty():
		_paragraph(ui,String(state.detail),rect.position+Vector2(18,48),552,12,ui.red if bool(state.urgent) else LIVE_MUTED,17,1)

static func objective_rect(ui: Control, game: Node3D) -> Rect2:
	if _phase(game)=="night" and not game.boss_snapshot().is_empty():
		return Rect2(OBJECTIVE_RECT.position,Vector2(OBJECTIVE_RECT.size.x,110))
	var state:=_objective_copy(game,_phase(game))
	var actual_font: Font=ui.get("font") as Font
	var width:=actual_font.get_string_size(String(state.title),HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
	var detail:=String(state.detail)
	if not detail.is_empty():width=maxf(width,actual_font.get_string_size(detail,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x)
	# Painting and input exclusion share the same content-sized rectangle.
	return Rect2(OBJECTIVE_RECT.position,Vector2(clampf(ceilf(width)+36.0,200.0,OBJECTIVE_RECT.size.x),60.0 if not detail.is_empty() else 44.0))

static func _objective_copy(game: Node3D, phase: String) -> Dictionary:
	var title:="守住南门"
	var detail:=""
	var urgent:=false
	if phase=="night":
		var preview: Dictionary=game.wave_preview()
		if not preview.is_empty():
			title="下一波 · %s · %d只 · %.0f秒" % [String(preview.title),int(preview.count),float(preview.remaining)]
			urgent=float(preview.remaining)<=10.0
			detail=String(preview.advice) if urgent else ""
			if int(preview.get("warder_count",0))>0:detail="织壳1秒 · 32盾/4秒 · 最多3次 · 击杀或牵制打断 · F3 防线"
			if int(preview.get("shellguard_count",0))>0:detail="甲壳卫60甲 · 二级塔J破甲忽略半甲 · C集火 · F3 防线"
			if int(preview.get("burstling_count",0))>0:detail="爆裂1.4秒 · 固定圈2.4米 · 分兵撤离 / 击杀 / 牵制或投网打断"
			if String(preview.get("bounty_id",""))=="shellguard_pack":
				# Keep real population and arrival time in the one-line budget.
				title="下一波 · 甲壳悬赏 · %d只 · %.0f秒" % [int(preview.count),float(preview.remaining)]
				detail="全清+48 · 甲壳60甲/J破甲 · 投蚀落点2米 · F3 防线"
		elif bool(game.night_clearance_active):
			var clearance: Dictionary=game.night_clearance_snapshot()
			title="%s · 残敌%d" % ["末夜清场" if bool(clearance.final) else "夜袭清场",int(clearance.remaining)]
			detail="清除残敌后结算" if bool(clearance.final) else "五波已抵达 · 清除残敌后迎来黎明"
			if int(clearance.projectiles)>0:detail="飞弹%d枚仍在途中 · 落地后才可完成清场" % int(clearance.projectiles)
		else:
			title="最后一波已抵达 · 守住南门"
			detail="处理主要威胁，保护灯塔与受压防线"
		urgent=true
	elif phase=="day":
		var contract: Node=game.contracts
		title=_contract_objective(contract)
		if String(contract.status)=="active":
			var remaining:=maxf(0.0,float(game.phase_time)-contract.selected_risk_seconds())
			urgent=remaining<=10.0
			detail="目标余时 %.0f秒 · F3 查看方案" % remaining if urgent else ""
		elif String(contract.status)=="bonus_offer":detail="4 返家 / 5 追加 · F3 战术"
		elif String(contract.status) in ["bonus_active","returning"]:detail="P 前往目标 · 日落前回灯塔"
		else:detail=""
	if float(game.beacon_alarm_time)>0.0:
		detail="灯塔受到攻击 -%d · 立即回防" % ceili(float(game.beacon_alarm_damage))
		urgent=true
	return {"title":title,"detail":detail,"urgent":urgent}

static func _draw_boss(ui: Control, game: Node3D, boss: Dictionary) -> void:
	var state:=String(boss.get("phase","approach"))
	if state=="dead":
		ui.label("末夜首领 · 已击破",Vector2(444,47),18,GREEN)
		var clearance: Dictionary=game.night_clearance_snapshot()
		if bool(clearance.active):
			ui.label("清场中 · 残敌%d · 飞弹%d · 全部清除后结算" % [int(clearance.remaining),int(clearance.projectiles)],Vector2(444,79),15,ui.amber)
		else:
			ui.label("首领威胁已解除 · 守住剩余波次",Vector2(444,79),15,ui.muted)
		return
	var hp:=maxf(0.0,float(boss.get("hp",0.0)))
	var maximum:=maxf(1.0,float(boss.get("max_hp",1.0)))
	ui.label("灯噬巨兽 · 生命%d/%d" % [roundi(hp),roundi(maximum)],Vector2(444,46),18,ui.amber)
	ui.progress(Rect2(444,56,552,7),hp/maximum,ui.red)
	var detail:="正在接近 · 增援%d/6" % int(boss.get("adds",0))
	if state=="windup":
		detail="蓄力%.1f秒 · 打断%.0f/%.0f" % [float(boss.get("windup",0)),float(boss.get("interrupt_damage",0)),float(boss.get("interrupt_threshold",220))]
		ui.progress(Rect2(444,88,552,5),float(boss.get("interrupt_progress",0)),BLUE)
	elif state=="exposed":detail="护甲破绽%.1f秒 · 立即集火" % float(boss.get("exposed",0))
	ui.label(detail,Vector2(444,81),15,BLUE if state in ["windup","exposed"] else ui.muted)
	ui.label("先打断蓄力，再清理残敌",Vector2(444,115),13,ui.muted)

static func _draw_resources(ui: Control, game: Node3D) -> void:
	var threatened:=float(game.beacon_alarm_time)>0.0
	var tint: Color=ui.red if threatened else Color(ui.amber,.92)
	ui.box(RESOURCE_RECT,RESOURCE_FILL,Color(0,0,0,0))
	ui.draw_line(Vector2(1080,26),Vector2(1080,58),Color(tint,.28),1.0)
	ui.draw_circle(Vector2(1091,37),3.0,Color(ui.amber,.88))
	ui.label("零件 %d" % int(game.scrap),Vector2(1103,41),15,ui.ink)
	ui.label("灯塔 %d/%d" % [ceili(float(game.beacon_hp)),int(game.BEACON_MAX)],Vector2(1214,41),13,tint)
	ui.draw_line(Vector2(1214,52),Vector2(1390,52),FOCUS_GHOST,1.0)
	ui.draw_line(Vector2(1214,52),Vector2(1214+176.0*clampf(float(game.beacon_hp)/float(game.BEACON_MAX),0.0,1.0),52),Color(tint,.68),1.0)

static func _draw_hero(ui: Control, game: Node3D) -> void:
	# One compact dock groups health, skills and the optional upgrade. These
	# backings stay inside the established input areas, leaving the world free.
	ui.box(HERO_RECT,HERO_FILL,Color(0,0,0,0))
	ui.box(MEMORY_DRAW_RECT,HERO_FILL,Color(0,0,0,0))
	ui.draw_line(Vector2(360,878),Vector2(1096,878),FOCUS_RAIL,1.0)
	ui.label("生命 %d" % ceili(float(game.hero.hp)),Vector2(360,832),12,LIVE_INK)
	ui.progress(Rect2(360,840,168,3),float(game.hero.hp)/maxf(1.0,float(game.hero.max_hp)),ui.red)
	ui.label("法力 %d" % floori(float(game.mana)),Vector2(360,862),11,BLUE)
	ui.progress(Rect2(360,870,168,2),float(game.mana)/maxf(1.0,float(game.max_mana)),BLUE)
	var keys:=["Q","W","E","R","X"]
	var names:=["斩光","屏障","突进","灯焰","治疗"]
	for index in 5:
		var x:=558.0+index*105.0
		var status: String=game.skill_status(index)
		var ready:=status=="就绪"
		var tint: Color=ui.red if status=="法力不足" else (ui.amber if ready else ui.muted)
		var center:=Vector2(x+20,838)
		ui.draw_arc(center,15.0,0.0,TAU,24,Color(tint,.42),1.0,true)
		ui.draw_circle(center,2.0,Color(tint,.52))
		_draw_skill_symbol(ui,index,center,Color(tint,.76) if not ready else tint)
		var cooldown: float=float(game.cooldowns[index])
		if cooldown>0.0:
			# A stable scale prevents later haste upgrades from making a running
			# cooldown ring grow backwards; the number shows exact seconds left.
			var duration: float=maxf(.001,float(game.COOLDOWNS[index]))
			ui.draw_arc(center,18.0,-PI*.5,-PI*.5+TAU*clampf(cooldown/duration,0.0,1.0),32,Color(tint,.7),1.5)
		ui.label(keys[index],Vector2(x+16,873),10,LIVE_QUIET,true)
		ui.label(names[index],Vector2(x+42,837),12,LIVE_INK if ready else LIVE_MUTED)
		ui.draw_line(Vector2(x+38,868),Vector2(x+88,868),Color(tint,.26),1.0)
		if not ready:ui.label(status,Vector2(x+42,859),11,tint)
	var pending:=int(game.run.pending)
	var available: bool=game.run.has_available_upgrade()
	var affordable: bool=available and int(game.scrap)>=game.run.memory_cost()
	var ready: bool=pending>0 or affordable
	# In the scene-priority layout the upgrade affordance is only painted when
	# it can be acted on. The F3 drawer still exposes the same upgrade details,
	# while an unavailable hint no longer competes with the skill strip.
	if bool(ui.get("minimal_display")) and not ready:return
	ui.draw_circle(Vector2(1120,833),3.0,Color(ui.amber,.85) if ready else RAIL)
	ui.label("V",Vector2(1130,837),13,ui.amber if ready else ui.muted,true)
	ui.label("强化",Vector2(1147,837),12,ui.amber if ready else ui.muted)
	var memory_text:="可选%d张" % pending if pending>0 else ("%d零件" % game.run.memory_cost() if affordable else "差%d零件" % maxi(0,game.run.memory_cost()-int(game.scrap)))
	if pending<=0 and not available:memory_text="强化已满"
	if ready:
		_paragraph(ui,memory_text,Vector2(1117,857),86,11,GREEN,15,2)
	else:
		ui.label("F3 查看",Vector2(1147,859),10,Color(ui.muted,.76))

static func _draw_skill_symbol(ui: Control, index: int, center: Vector2, tint: Color) -> void:
	# Native geometry stays crisp at Retina scale and needs no imported font
	# glyphs or animated textures. Each skill has a distinct silhouette.
	match index:
		0:
			ui.draw_line(center+Vector2(-7,7),center+Vector2(7,-7),tint,2.0,true)
			ui.draw_line(center+Vector2(-7,0),center+Vector2(0,7),tint,2.0,true)
			ui.draw_line(center+Vector2(3,-7),center+Vector2(7,-7),tint,1.5,true)
			ui.draw_line(center+Vector2(7,-7),center+Vector2(7,-3),tint,1.5,true)
		1:
			var shield:=PackedVector2Array([Vector2(-7,-7),Vector2(7,-7),Vector2(6,2),Vector2(0,9),Vector2(-6,2),Vector2(-7,-7)])
			for point in shield.size():shield[point]+=center
			ui.draw_polyline(shield,tint,1.7,true)
			ui.draw_line(center+Vector2(0,-4),center+Vector2(0,5),Color(tint,.48),1.0,true)
		2:
			for offset in [-6.0,2.0]:
				ui.draw_polyline(PackedVector2Array([center+Vector2(offset-3,-6),center+Vector2(offset+3,0),center+Vector2(offset-3,6)]),tint,2.0,true)
		3:
			var flame:=PackedVector2Array([Vector2(0,-9),Vector2(-2,-3),Vector2(-6,0),Vector2(-5,6),Vector2(0,9),Vector2(5,5),Vector2(6,0),Vector2(2,-4),Vector2(2,2)])
			for point in flame.size():flame[point]+=center
			ui.draw_colored_polygon(flame,Color(tint,.18))
			var outline:=flame.duplicate()
			outline.append(outline[0])
			ui.draw_polyline(outline,tint,1.5,true)
		4:
			ui.draw_line(center+Vector2(-7,0),center+Vector2(7,0),tint,3.0,true)
			ui.draw_line(center+Vector2(0,-7),center+Vector2(0,7),tint,3.0,true)

static func _draw_navigation_buttons(ui: Control, game: Node3D) -> void:
	var open:=String(ui.get("detail_tab")) in TAB_IDS
	ui.box(TACTICS_RECT,PHASE_FILL,Color(0,0,0,0))
	ui.box(MAP_BUTTON_RECT,PHASE_FILL,Color(0,0,0,0))
	ui.box(BUILD_BUTTON_RECT,PHASE_FILL,Color(0,0,0,0))
	ui.draw_line(Vector2(24,860),Vector2(336,860),RAIL_GHOST,1.0)
	var nav_tint: Color=GREEN if open else ui.muted
	ui.label("F3",Vector2(43,848),13,nav_tint,true)
	ui.label("详情" if not open else "收起",Vector2(66,848),12,nav_tint)
	ui.label("地图",Vector2(189,848),12,LIVE_MUTED)
	var build_tint: Color=GREEN if game.construction.active else ui.muted
	ui.label("Y 建造",Vector2(278,848),12,build_tint)
	if not is_instance_valid(game.squads):return
	var snapshot: Dictionary=game.squads.snapshot()
	if int(snapshot.get("selected",0))<=0:return
	var advancing:=0
	var escorting:=0
	var recalling:=0
	var capturing:=0
	for row: Dictionary in snapshot.squads:
		if bool(row.selected) and int(row.alive)>0 and String(row.order)=="attack_move":advancing+=1
		if bool(row.selected) and int(row.alive)>0 and String(row.order)=="escort":escorting+=1
		if bool(row.selected) and int(row.alive)>0 and bool(row.get("manual_recall",false)):recalling+=1
		if bool(row.selected) and int(row.alive)>0 and String(row.order)=="capture":capturing+=1
	var command_active:=advancing+escorting+recalling+capturing>0
	if is_instance_valid(game.logistics) and game.logistics.selected_hauler_count()>0:command_active=true
	# Idle selection is useful for control groups but should not create a
	# permanent status card in the default battlefield view.
	if bool(ui.get("minimal_display")) and not command_active:return
	var title: String="已选%d队 · 推进%d队" % [int(snapshot.selected),advancing] if advancing>0 else "已选%d队 · 全军%d人" % [int(snapshot.selected),int(snapshot.alive)]
	if escorting>0:title="已选%d队 · 护航%d队" % [int(snapshot.selected),escorting]
	if recalling>0:title="已选%d队 · 撤回%d队" % [int(snapshot.selected),recalling]
	if capturing>0:title="已选%d队 · 夺取%d队" % [int(snapshot.selected),capturing]
	ui.box(SELECTED_SQUAD_RECT,PHASE_FILL,Color(0,0,0,0))
	ui.draw_line(SELECTED_SQUAD_RECT.position,SELECTED_SQUAD_RECT.position+Vector2(78,0),Color(GREEN,.42),1.0)
	ui.label(title,Vector2(38,783),14,GREEN)
	ui.label(selected_command_hint(ui,game),Vector2(38,808),13,ui.muted)

static func selected_command_hint(ui: Control, game: Node3D) -> String:
	if ui.rally_setting():return "选点中 · 原部队命令保留"
	if is_instance_valid(game.squads):
		for squad: Dictionary in game.squads.squads:
			if String(squad.order)=="capture" and game.squads.selected_ids.has(int(squad.id)):
				return "夺取中 · 右键改令 / Alt+O撤回"
		for squad: Dictionary in game.squads.squads:
			if bool(squad.get("manual_recall",false)) and game.squads.selected_ids.has(int(squad.id)):
				return "撤回中 · 右键改令 · Alt+O撤回所选"
		for squad: Dictionary in game.squads.squads:
			if String(squad.order)=="escort" and game.squads.selected_ids.has(int(squad.id)):
				return "护航中 · 右键改令 · Alt+右键工队"
	var hauling: bool=is_instance_valid(game.logistics) and game.logistics.selected_hauler_count()>0
	return "工队右键采运 · Shift+右键推进" if hauling else "右键指挥 · Shift+右键推进"

static func selected_command_active(game: Node3D) -> bool:
	if not is_instance_valid(game) or not is_instance_valid(game.squads):return false
	for squad: Dictionary in game.squads.squads:
		if not bool(squad.get("selected",false)) or int(squad.get("alive",0))<=0:continue
		if String(squad.get("order","")) in ["attack_move","escort","capture"] or bool(squad.get("manual_recall",false)):
			return true
	return is_instance_valid(game.logistics) and game.logistics.selected_hauler_count()>0

static func notice_rect(ui: Control, game: Node3D) -> Rect2:
	if not is_instance_valid(game) or game.phase not in ["day","night"]:return Rect2()
	if game.music_credits_open or game.construction.active or ui.rally_setting() or float(game.hero_damage_flash_time)>0.0:return Rect2()
	if float(game.notice_time)<=0.0 or String(game.notice).strip_edges().is_empty():return Rect2()
	var lines:=_wrap(ui,String(game.notice),716,15)
	var count:=mini(2,lines.size())
	var font: Font=ui.get("font") as Font
	var width:=152.0
	for index in count:
		width=maxf(width,font.get_string_size(lines[index],HORIZONTAL_ALIGNMENT_LEFT,-1,15).x+36.0)
	width=minf(752.0,width)
	var height:=34.0+(count-1)*20.0
	return Rect2(720.0-width*.5,788.0-height,width,height)

static func _draw_notice(ui: Control, game: Node3D) -> void:
	var rect:=notice_rect(ui,game)
	if not rect.has_area():return
	var lines:=_wrap(ui,String(game.notice),716,15)
	# Keep the existing logical footprint for click interception and recorder
	# coverage while leaving the visual layer cardless.
	ui.box(rect,Color(0,0,0,0),Color(0,0,0,0))
	ui.draw_line(rect.position,rect.position+Vector2(minf(rect.size.x,96.0),0),Color("b18c59",.64),1.0)
	for index in mini(2,lines.size()):
		ui.label(lines[index],rect.position+Vector2(18,22+index*20),15,ui.ink)

static func _active_tags_text(game: Node3D) -> String:
	if not is_instance_valid(game.exploration):return ""
	var exploration: Node=game.exploration
	var labels: Array[String]=[]
	if int(exploration.streak)>0 and float(exploration.streak_time)>0.0:
		labels.append("换类%d连 · %.0f秒" % [int(exploration.streak),ceilf(float(exploration.streak_time))])
	if exploration.affinity_active():labels.append("共鸣 +8零件 · %.0f秒" % ceilf(float(exploration.affinity_time)))
	return " · ".join(labels)

static func active_tags_rect(ui: Control, game: Node3D) -> Rect2:
	if not is_instance_valid(game) or game.phase not in ["day","night","paused"]:return Rect2()
	if game.music_credits_open or game.construction.active or ui.rally_setting() or not String(ui.get("detail_tab")).is_empty():return Rect2()
	var text:=_active_tags_text(game)
	if text.is_empty():return Rect2()
	var font: Font=ui.get("font") as Font
	var width:=minf(380.0,font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x+26.0)
	return Rect2(24,100,width,29)

static func _draw_active_tags(ui: Control, game: Node3D) -> void:
	var rect:=active_tags_rect(ui,game)
	if not rect.has_area():return
	# Retain the transparent logical footprint for the recorder and input
	# exclusion checks; the tag itself remains a single lightweight line.
	ui.box(rect,Color(0,0,0,0),Color(0,0,0,0))
	ui.draw_line(rect.position,rect.position+Vector2(minf(rect.size.x,72.0),0),Color("6f927f",.22),1.0)
	ui.label(_active_tags_text(game),rect.position+Vector2(0,20),13,Color(GREEN,.82))

static func _draw_drawer(ui: Control, game: Node3D, tab: String) -> void:
	ui.box(DRAWER_RECT,DRAWER_FILL,Color("62776a"))
	ui.draw_line(Vector2(46,166),Vector2(542,166),RAIL_FAINT,1.0)
	for index in TAB_IDS.size():
		var rect: Rect2=ui.details_tab_rect(index)
		var selected: bool=tab==TAB_IDS[index]
		ui.box(rect,Color(GREEN,.09) if selected else Color(0,0,0,0),Color(0,0,0,0))
		ui.draw_line(rect.position+Vector2(8,31),rect.position+Vector2(92,31),Color(GREEN if selected else Color("3e5148"),.72 if selected else .22),2.0 if selected else 1.0)
		ui.label(TAB_TITLES[index],rect.position+Vector2(32,23),16,GREEN if selected else ui.muted)
	match tab:
		"contract":_draw_contract(ui,game)
		"exploration":_draw_exploration(ui,game)
		"army":ui.draw_squads()
		"defense":_draw_defense(ui,game)
		"help":_draw_help(ui)
	ui.box(DRAWER_CLOSE_RECT,Color(0,0,0,0),Color(0,0,0,0))
	ui.draw_line(DRAWER_CLOSE_RECT.position+Vector2(10,29),DRAWER_CLOSE_RECT.end-Vector2(10,1),Color("52695c",.34),1.0)
	ui.label("F3 收起",DRAWER_CLOSE_RECT.position+Vector2(22,21),14,ui.muted)
	if tab=="exploration":
		var nav: Rect2=ui.SALVAGE_NAV_RECT
		ui.box(nav,Color(0,0,0,0),Color(0,0,0,0))
		ui.draw_line(nav.position+Vector2(10,29),nav.end-Vector2(10,1),Color("52695c",.34),1.0)
		ui.label("探索记录" if bool(ui.get("salvage_draw_open")) else "补给抽取",nav.position+Vector2(58,21),14,GREEN)
	elif tab=="help":
		var toggle: Rect2=ui.HELP_TOGGLE_RECT
		ui.box(toggle,Color(GREEN,.08),Color(0,0,0,0))
		ui.label("返回快捷操作" if bool(ui.get("help_details_open")) else "查看详细说明",toggle.position+Vector2(51,21),14,GREEN)

static func _contract_objective(contract: Node) -> String:
	var status:=String(contract.status)
	var title: String=contract.TITLES.get(String(contract.kind),"自由探索")
	match status:
		"active":return "%s · %d/%d" % [title,contract.done.size(),contract.targets.size()]
		"bonus_offer":return "主委托完成 · 返家还是再搜一处"
		"bonus_active":return "追加补给 · 采集后返回灯塔"
		"returning":return "返回灯塔 · 交付本次委托"
		"completed":return "委托已交回 · 整备或继续探索"
		"expired":return "委托已截止 · 自由探索与布防"
		_:return "白昼90秒 · 建设或外出搜寻"

static func _draw_contract(ui: Control, game: Node3D) -> void:
	var contract: Node=game.contracts
	var status:=String(contract.status)
	if status=="bonus_offer":
		_draw_bonus_routes(ui,game,contract)
		return
	var y:=_paragraph(ui,_contract_objective(contract),Vector2(TEXT_X,183),TEXT_WIDTH,18,GREEN,24)
	if status=="active":
		var budget:=_dictionary_property(ui,"contract_primary_budget")
		if not budget.is_empty():
			y=_paragraph(ui,contract.primary_travel_text(budget),Vector2(TEXT_X,y+6),TEXT_WIDTH,15,ui.ink,21)
			y=_paragraph(ui,contract.primary_timing_text(budget),Vector2(TEXT_X,y),TEXT_WIDTH,15,_budget_color(ui,budget),21)
		else:y=_paragraph(ui,"路线预算更新中",Vector2(TEXT_X,y+6),TEXT_WIDTH,15,ui.muted,21)
		var condition: String=contract.primary_condition_text(budget) if not budget.is_empty() else "估时不含战斗 · 主目标完成后仍须返家交付"
		y=_paragraph(ui,condition,Vector2(TEXT_X,y+2),TEXT_WIDTH,14,ui.muted,20)
		y+=12
		for index in contract.offers.size():
			var offer: Dictionary=contract.offers[index]
			var choice: Dictionary=contract.offer_choice_state(index)
			var selected: bool=index==int(contract.selected_offer)
			var fill:=Color(.050,.092,.073,.95) if selected else Color(.032,.051,.047,.93)
			var tint: Color=GREEN if selected else (ui.ink if bool(choice.available) else ui.muted)
			ui.box(Rect2(TEXT_X-8,y-16,TEXT_WIDTH+16,87),fill,GREEN if selected else Color("45584c"))
			var name: String=contract.TITLES.get(String(offer.kind),String(offer.kind))
			ui.label("%d %s · %s" % [4+index,name,String(choice.tag)],Vector2(TEXT_X,y+3),16,tint)
			ui.label("+%d零件 · %s" % [int(offer.scrap),String(offer.name)],Vector2(TEXT_X,y+26),15,ui.amber)
			var risk:="无额外追猎" if int(offer.risk_hunters)==0 else "额外追猎%d · 提前%d秒截止" % [int(offer.risk_hunters),int(offer.risk_seconds)]
			ui.label(risk,Vector2(TEXT_X,y+47),14,ui.muted)
			_paragraph(ui,String(choice.reason),Vector2(TEXT_X,y+67),TEXT_WIDTH,14,tint,20,1)
			y+=91
		_paragraph(ui,"先选方案再行动 · 首次真实行动锁定方案并触发追猎一次。",Vector2(TEXT_X,y+8),TEXT_WIDTH,14,ui.muted,20)
		_paragraph(ui,"P 指路 / F 行动 · 交回时提前15秒再+10零件。",Vector2(TEXT_X,y+51),TEXT_WIDTH,14,GREEN,20)
	elif status in ["bonus_active","returning"]:
		var budget:=_dictionary_property(ui,"contract_return_budget")
		var reward: Dictionary=contract.selected_reward
		y=_paragraph(ui,"主委托保底 +%d零件" % int(reward.scrap),Vector2(TEXT_X,y+8),TEXT_WIDTH,16,ui.amber,23)
		var bonus: Dictionary=contract.bonus_target
		if bonus.is_empty():bonus=budget.get("candidate",{})
		if status=="bonus_active":
			y=_paragraph(ui,"P 前往追加目标 · F 采集后再 P 返家",Vector2(TEXT_X,y+18),TEXT_WIDTH,16,GREEN,23)
		else:y=_paragraph(ui,"P 回灯塔 · 到家才兑现返家与追加奖励",Vector2(TEXT_X,y+18),TEXT_WIDTH,16,GREEN,23)
		if not budget.is_empty():y=_paragraph(ui,contract.return_budget_text(budget),Vector2(TEXT_X,y+20),TEXT_WIDTH,15,_budget_color(ui,budget),22)
		else:y=_paragraph(ui,"路线预算更新中",Vector2(TEXT_X,y+20),TEXT_WIDTH,15,ui.muted,22)
		y=_paragraph(ui,"估时不含战斗。日落前未返家仍保留已完成的主委托保底，追加奖励放弃。",Vector2(TEXT_X,y+18),TEXT_WIDTH,15,ui.muted,22)
		_paragraph(ui,"提前15秒交回，再获得10零件整备奖励。",Vector2(TEXT_X,y+18),TEXT_WIDTH,15,GREEN,22)
	else:
		var text:="今日没有可用委托目标，可以建设防线或自由探索。"
		if status=="completed":text="奖励已交回。继续搜寻新的发现，或用零件建设、训练和维修。"
		elif status=="expired":text="主目标没有在截止前完成，委托无奖且无额外惩罚；普通探索的真实收益继续有效。"
		y=_paragraph(ui,text,Vector2(TEXT_X,y+18),TEXT_WIDTH,16,ui.ink,24)
		_paragraph(ui,"白昼委托可用4/5/6在首次行动前选择。先探索过的目标当天不能补接高奖方案。",Vector2(TEXT_X,y+22),TEXT_WIDTH,15,ui.muted,22)

static func _draw_bonus_routes(ui: Control, game: Node3D, contract: Node) -> void:
	# The owning Control refreshes these real-route snapshots. Drawing stays
	# read-only and never recomputes navigation or changes the selected source.
	ui.label("主委托已完成 · 再探索还是返家",Vector2(TEXT_X,183),18,GREEN)
	ui.label("主委托保底 +%d零件 · 到家兑现" % int(contract.selected_reward.scrap),Vector2(TEXT_X,220),16,ui.amber)
	var can_act: bool=game.phase=="day" and float(game.phase_time)>0.0 and not game.quitting and not game.restart_pending and game.hero.alive and float(game.hero.hp)>0.0 and float(game.beacon_hp)>0.0
	ui.box(ui.BONUS_RETURN_RECT,Color(.035,.068,.054,.96),GREEN if can_act else ui.muted)
	ui.label("4 立即返家 · 保留时间整备防线",Vector2(TEXT_X+14,266),15,GREEN if can_act else ui.muted)
	var rows: Array=ui.bonus_route_budgets
	var selected: Dictionary={}
	if rows.is_empty():
		_paragraph(ui,"暂时没有可达追加补给 · 可直接返家",Vector2(TEXT_X,316),TEXT_WIDTH,16,ui.muted,23)
	for slot in mini(3,rows.size()):
		var row: Dictionary=rows[slot]
		var chosen: bool=bool(row.get("selected",false))
		if chosen:selected=row
		var budget: Dictionary=row.get("budget",{})
		var available: bool=bool(row.get("available",false))
		var rect: Rect2=ui.bonus_route_rect(slot)
		var tint: Color=GREEN if chosen else ui.ink
		if not available:tint=ui.muted
		ui.box(rect,Color(.045,.085,.068,.96) if chosen else Color(.030,.048,.043,.93),GREEN if chosen and available else Color("45584c"))
		var title: String=contract.BONUS_TITLES.get(String(row.kind),"追加补给")
		ui.label("%s · %s · 返家加奖%d零件" % ["已选" if chosen else "选择",title,int(row.scrap)],rect.position+Vector2(12,21),15,tint)
		var base: int={"ember_bloom":12,"memory_crystal":12,"supply_cache":46,"waylight":0}.get(String(row.kind),0)
		ui.label("普通采集基础+%d零件 · 探索加成另算" % base,rect.position+Vector2(12,40),13,ui.amber if available else ui.muted)
		if not budget.is_empty() and bool(budget.get("available",false)):
			var speed: float=maxf(1.0,float(budget.get("speed",1.0)))
			var outbound: float=float(budget.outbound_distance)
			var returning: float=float(budget.return_distance)
			ui.label("去程%.0f米/%.0f秒 · 回程%.0f米/%.0f秒 · 行动%.0f秒" % [outbound,ceilf(outbound/speed),returning,ceilf(returning/speed),ceilf(float(budget.action_seconds))],rect.position+Vector2(12,58),13,ui.muted)
			var spare: int=floori(float(budget.spare_seconds))
			var timing: String="日落前难返家" if spare<0 else "余%d秒整备%s" % [spare," · 时间紧" if String(budget.risk)=="tight" else ""]
			if bool(budget.get("guard_blocked",false)):
				timing=("守卫离场 · 箱仍锁 · " if int(budget.get("guard_lost",0))>0 else "守卫%d · 战斗另计 · " % int(budget.get("guard_remaining",0)))+timing
			if not can_act:timing+=" · 当前仅查看"
			ui.label(timing,rect.position+Vector2(12,76),13,_budget_color(ui,budget))
		else:
			_paragraph(ui,String(row.get("reason","路线不可用 · 请重选或4返家")),rect.position+Vector2(12,63),TEXT_WIDTH-24,13,ui.muted,18,1)
	var confirm: bool=can_act and not selected.is_empty() and bool(selected.get("available",false))
	ui.box(ui.BONUS_CONFIRM_RECT,Color(.072,.088,.055,.97),ui.amber if confirm else ui.muted)
	var confirmation_text: String="5 确认所选追加 · 锁定目标后 P 指路 / F 行动" if confirm else "所选路线不可用 · 重选路线或4返家"
	if game.phase=="paused":confirmation_text="暂停中 · 可查看路线，恢复后选择或确认"
	ui.label(confirmation_text,Vector2(TEXT_X+14,591),14,ui.amber if confirm else ui.muted)
	_paragraph(ui,"默认选择最近一处 · 点击路线比较后，再按5确认。",Vector2(TEXT_X,627),TEXT_WIDTH,14,ui.muted,20)
	_paragraph(ui,"估时不含战斗；日落未归仅保主委托，追加放弃。",Vector2(TEXT_X,648),TEXT_WIDTH,14,ui.muted,20)
	_paragraph(ui,"提前15秒交回，再获得10零件整备奖励。",Vector2(TEXT_X,669),TEXT_WIDTH,14,GREEN,20)

static func _draw_exploration(ui: Control, game: Node3D) -> void:
	if not is_instance_valid(game.exploration):return
	var draw_open: bool=bool(ui.get("salvage_draw_open"))
	if draw_open:
		_draw_salvage_supply(ui,game)
		return
	var exploration: Node=game.exploration
	var y:=_paragraph(ui,exploration.route_text(),Vector2(TEXT_X,183),TEXT_WIDTH,18,GREEN,24)
	y=_paragraph(ui,"探索%d次 · 里程碑%d · %d/5：+55零件" % [game.exploration_count,game.exploration_milestones,game.exploration_count%5],Vector2(TEXT_X,y+4),TEXT_WIDTH,14,ui.amber,20)
	y=_paragraph(ui,exploration.collection_reward_text(),Vector2(TEXT_X,y+6),TEXT_WIDTH,14,ui.ink,20)
	y=_paragraph(ui,exploration.streak_text()+" · "+exploration.streak_reward_text(),Vector2(TEXT_X,y+6),TEXT_WIDTH,15,ui.amber,21)
	var affinity: String=exploration.affinity_text()
	if not affinity.is_empty():y=_paragraph(ui,affinity,Vector2(TEXT_X,y+4),TEXT_WIDTH,15,GREEN,21)
	var buffs: Array[String]=[]
	if float(exploration.speed_time)>0.0:
		buffs.append("加速+%.1f米/秒 · %.0f秒" % [float(exploration.speed_bonus),ceilf(float(exploration.speed_time))])
	if exploration.network_active():buffs.append("灯网共鸣 · 灯碑外额外+2零件")
	if not buffs.is_empty():y=_paragraph(ui," · ".join(buffs),Vector2(TEXT_X,y+4),TEXT_WIDTH,15,BLUE,21)
	y=_paragraph(ui,"P 前往共鸣/发现 · 白昼主委托优先",Vector2(TEXT_X,y+6),TEXT_WIDTH,14,ui.muted,20)
	y=_draw_generator_tasks(ui,game,y+6)
	y=_paragraph(ui,"最近收益",Vector2(TEXT_X,y+8),TEXT_WIDTH,16,GREEN,23)
	var toasts: Array=game.reward_toasts
	for index in mini(2,toasts.size()):
		var toast: Dictionary=toasts[index]
		y=_paragraph(ui,String(toast.title)+"："+String(toast.detail),Vector2(TEXT_X,y+6),TEXT_WIDTH,14,toast.get("color",ui.ink),20)
	if toasts.is_empty():_paragraph(ui,"采集或互动后，实际奖励与全部加成来源显示在这里。",Vector2(TEXT_X,y+8),TEXT_WIDTH,15,ui.muted,22)

static func _draw_generator_tasks(ui: Control, game: Node3D, y: float) -> float:
	var tasks: Dictionary=game.expeditions.capture_snapshot()
	y=_paragraph(ui,"地图争夺 · 白昼选队右键发电机",Vector2(TEXT_X,y),TEXT_WIDTH,15,GREEN,20,1)
	for site: Dictionary in tasks.sites:
		var status: String="待夺取" if site.assigned_ids.is_empty() else "部队行军中"
		if String(site.state)=="complete":status="已夺取 · 能源芯入账"
		elif String(site.state)=="active":status="充能%d%% · 圈内%d人 · 守卫%d" % [roundi(float(site.ratio)*100),int(site.holders),int(site.guards_alive)]
		if bool(site.guards_lost):status="守卫失联 · 次日重试"
		y=_paragraph(ui,"%d号 · %s" % [int(site.index)+1,status],Vector2(TEXT_X,y+2),TEXT_WIDTH,13,ui.ink,18,1)
	return _paragraph(ui,"守圈12秒并清守 · 多队不加速 · 日落中断",Vector2(TEXT_X,y+3),TEXT_WIDTH,12,ui.muted,18,1)

static func _draw_salvage_supply(ui: Control, game: Node3D) -> void:
	var state: Dictionary=game.salvage_draw_snapshot()
	var selected_mode: String=String(state.get("selected_mode","safe"))
	var selected_label: String="押大" if selected_mode=="jackpot" else "稳妥"
	ui.label("废墟补给 · 可选抽取",Vector2(TEXT_X,184),18,GREEN)
	_paragraph(ui,"当天完成一次探索并返回灯塔 · 第一次稳妥，第二次可押大。",Vector2(TEXT_X,215),TEXT_WIDTH,15,ui.ink,22)
	ui.label("概率",Vector2(TEXT_X,249),14,ui.muted)
	ui.label("回款",Vector2(230,249),14,ui.muted)
	ui.label("扣除费用后",Vector2(380,249),14,ui.muted)
	var y:=280.0
	for result: Dictionary in state.results:
		var net: int=int(result.net)
		var net_text: String="+%d" % net if net>=0 else str(net)
		ui.label("%d%%" % int(result.probability),Vector2(TEXT_X,y),17,ui.ink)
		ui.label("%d零件" % int(result.payout),Vector2(230,y),17,ui.ink)
		ui.label(net_text+"零件",Vector2(380,y),17,GREEN if net>=0 else ui.amber)
		y+=40.0
	_paragraph(ui,"当前%s档 · 每白昼最多2次 · 已用%d/2 · 不参与也可正常建设守夜。" % [selected_label,int(state.used)],Vector2(TEXT_X,393),TEXT_WIDTH,14,ui.muted,20)
	var available: bool=bool(state.available)
	var button: Rect2=ui.SALVAGE_DRAW_RECT
	ui.box(button,Color(.075,.13,.105,.98) if available else Color(.033,.047,.043,.98),GREEN if available else Color("52695c"))
	var action_text: String="支付%d零件 · 抽取%s档" % [int(state.stake),selected_label] if available else "暂不可抽取"
	ui.label(action_text,button.position+Vector2(135 if available else 206,25),16,GREEN if available else ui.muted)
	var safe_rect: Rect2=ui.SALVAGE_SAFE_MODE_RECT
	var jackpot_rect: Rect2=ui.SALVAGE_JACKPOT_MODE_RECT
	var safe_selected: bool=selected_mode=="safe"
	var jackpot_unlocked: bool=int(state.used)>=1
	ui.box(safe_rect,Color(.075,.13,.105,.98) if safe_selected else Color(.033,.047,.043,.98),GREEN if safe_selected else Color("52695c"))
	ui.label("稳妥 · 30零件 · 60/30/10",safe_rect.position+Vector2(16,23),14,GREEN if safe_selected else ui.muted)
	ui.box(jackpot_rect,Color(.13,.085,.045,.98) if selected_mode=="jackpot" and jackpot_unlocked else Color(.033,.047,.043,.98),ui.amber if jackpot_unlocked else Color("52695c"))
	ui.label("押大 · 60零件 · 70/25/5" if jackpot_unlocked else "押大 · 第二抽解锁",jackpot_rect.position+Vector2(16,23),14,ui.amber if jackpot_unlocked else ui.muted)
	var reason: String=String(state.reason)
	var status_text: String=game.salvage_draw_reason(reason)
	if game.phase=="paused":status_text="暂停中 · 恢复白昼后可抽取"
	_paragraph(ui,status_text,Vector2(TEXT_X,510),TEXT_WIDTH,15,GREEN if available else ui.amber,22)
	var last: Dictionary=state.last
	if not last.is_empty():
		var net: int=int(last.net)
		var net_text: String="+%d" % net if net>=0 else str(net)
		ui.label("最近结果 · %s档 · 第%d日第%d次" % ["押大" if String(last.get("mode","safe"))=="jackpot" else "稳妥",int(last.day_id),int(last.draw_number)],Vector2(TEXT_X,550),16,GREEN)
		_paragraph(ui,"支付%d · 回款%d · 净%s零件" % [int(last.cost),int(last.payout),net_text],Vector2(TEXT_X,578),TEXT_WIDTH,16,ui.ink,23)
	else:_paragraph(ui,"尚未抽取 · 先探索，再回家整备。",Vector2(TEXT_X,550),TEXT_WIDTH,15,ui.muted,22)
	_paragraph(ui,"稳妥净变化−20/+10/+90；押大净变化−60/+60/+540。第二抽再决定是否加注。",Vector2(TEXT_X,628),TEXT_WIDTH,14,ui.muted,20)

static func _draw_defense(ui: Control, game: Node3D) -> void:
	var bounty: Dictionary=game.bounty_snapshot()
	var bounty_state:=String(bounty.state)
	var heading_y:=388.0
	if _phase(game)=="day":
		ui.draw_day_forecast()
		if ui.wave_wager_visible():
			ui.draw_wave_wager()
			return
	else:
		ui.label("清场 · 清除残敌与飞弹" if bool(game.night_clearance_active) else "守夜防线",Vector2(TEXT_X,184),18,GREEN)
		var title: String="未选择额外反制" if int(game.countermeasure_selected)<0 else game.countermeasure_title(int(game.countermeasure_selected))
		_paragraph(ui,"本夜反制 · "+title,Vector2(TEXT_X,215),TEXT_WIDTH,16,ui.ink,23)
		if int(game.countermeasure_selected)>=0:
			_paragraph(ui,game.countermeasure_summary(int(game.countermeasure_selected)),Vector2(TEXT_X,248),TEXT_WIDTH,15,ui.muted,22)
		var reinforcement_cap:=0
		var shield_cast_cap:=0
		var shellguard_count:=0
		var burstling_count:=0
		for entry: Dictionary in game.night_plan:
			reinforcement_cap+=int(entry.get("reinforcement_cap",0))
			shield_cast_cap+=int(entry.get("shield_cast_cap",0))
			shellguard_count+=int(entry.get("shellguard_count",0))
			burstling_count+=int(entry.get("burstling_count",0))
		var advice:="反制在白昼按7/8/9选择，天黑前可更换。"
		if reinforcement_cap>0:advice="召潮者引导2.4秒，单源最多2援军；击杀或牵制可打断。"
		if shield_cast_cap>0:
			advice="织壳1秒→32盾/4秒，每源最多3次；击杀或牵制可打断。"
			if reinforcement_cap>0:advice="召潮2.4秒/最多2援军；织壳1秒/32盾4秒/最多3次；击杀或牵制打断。"
		if shellguard_count>0:
			var armor_advice:="甲壳60甲，J破甲忽略半甲/C集火。"
			if reinforcement_cap==0 and shield_cast_cap==0:advice="甲壳卫60护甲；二级塔J破甲重敌×1.65、忽略半甲；C集火/盾卫挡线。"
			else:advice+=armor_advice
		if burstling_count>0:
			advice="爆裂1.4秒/2.4米：撤离、击杀或牵制/投网打断。"
			var support: Array[String]=[]
			if reinforcement_cap>0:support.append("召潮2.4秒/2援")
			if shield_cast_cap>0:support.append("织壳1秒/32盾4秒/最多3次")
			if shellguard_count>0:support.append("甲壳60甲/J破甲/C集火")
			if not support.is_empty():advice+="\n"+"；".join(support)+"。"
		_paragraph(ui,advice,Vector2(TEXT_X,286),TEXT_WIDTH,15,ui.muted,22,2)
		var gate:="路障%d耐久" % ceili(float(game.gate_barricade_hp)) if float(game.gate_barricade_hp)>0.0 else "路障未部署"
		_paragraph(ui,"%s · 机关%d/%d · C集火%s" % [gate,game.gate_trap_charges,game.GATE_TRAP_MAX,"冷却%.0f秒" % ceilf(float(game.focus_cooldown)) if float(game.focus_cooldown)>0.0 else "就绪"],Vector2(TEXT_X,336),TEXT_WIDTH,15,ui.ink,22)
	if game.day_number==2:
		if _phase(game)=="day" and bounty_state in ["offered","selected"]:heading_y=478.0
		elif _phase(game)=="night" and bounty_state in ["active","won","expired"]:
			var bounty_title:="甲壳悬赏 · 第三波尚未抵达"
			if int(bounty.count)>0:bounty_title="甲壳悬赏 · 第三波已清%d/%d" % [int(bounty.kills),int(bounty.count)]
			if bounty_state=="won":bounty_title="甲壳悬赏完成 · 额外+48零件已入账"
			elif bounty_state=="expired":bounty_title="甲壳悬赏结束 · 未获额外奖励"
			_paragraph(ui,bounty_title,Vector2(TEXT_X,370),TEXT_WIDTH,16,GREEN if bounty_state=="won" else ui.amber,22,1)
			_paragraph(ui,"本夜不获得免费反制；第三波须在夜间倒计时结束前全清。",Vector2(TEXT_X,398),TEXT_WIDTH,14,ui.muted,20,2)
			heading_y=450.0
	ui.label("整备建议",Vector2(TEXT_X,heading_y),17,GREEN)
	var growth: Dictionary=game.growth_snapshot()
	var y:=heading_y+24.0
	for line: String in ui.growth_lines(growth):y=_paragraph(ui,line,Vector2(TEXT_X,y),TEXT_WIDTH,15,ui.ink,22)
	y=_paragraph(ui,ui.growth_memory_text(growth),Vector2(TEXT_X,y+8),TEXT_WIDTH,15,ui.amber,22)
	y=_paragraph(ui,"防御塔%d座 · 通信塔%d/8 · 清除%d只" % [game.tower_count(),game.relay_count(),game.kills],Vector2(TEXT_X,y+14),TEXT_WIDTH,14,ui.muted,20)
	_paragraph(ui,"灯下同伴%d/2 · 修灯%d零件 · 南门机关%d/%d" % [game.survivors_rescued,game.beacon_repair_cost(),game.gate_trap_charges,game.GATE_TRAP_MAX],Vector2(TEXT_X,y+3),TEXT_WIDTH,14,ui.muted,20)

static func _draw_help(ui: Control) -> void:
	if not bool(ui.get("help_details_open")):
		ui.label("常用操作",Vector2(TEXT_X,184),18,GREEN)
		ui.label("先玩起来 · 科技与规则需要时再查看",Vector2(TEXT_X,216),14,ui.muted)
		var shortcuts: Array[String]=[
			"移动   ZASD / 方向键 · 未选部队时右键寻路",
			"探索   P 指路 · F 互动 · 4/5/6 委托",
			"建造   Y 选址 · 1/2/3 切建筑 · H 维修",
			"英雄   Q / W / E / R / X 技能 · V 强化",
			"生产   U 盾卫 · I 弩手 · N 工程员 · F3 更多",
			"编队   Ctrl+1/2/3 保存 · 数字召回 · Tab 全选",
			"指挥   O 驻守 · Alt+O 撤回 · Shift+右键推进",
			"远征   白昼选队右键发电机 · Alt+右键工队护航",
			"撤销   Esc 收起 / 取消建造 / 取消选队 / 暂停",
			"声音   M 配乐 · F2 减弱震动和闪光",
		]
		for index in shortcuts.size():
			var y:=254.0+index*36.0
			ui.label(shortcuts[index],Vector2(TEXT_X,y),15,ui.ink)
			if index in [1,4,7]:ui.draw_line(Vector2(TEXT_X,y+14),Vector2(TEXT_X+TEXT_WIDTH,y+14),RAIL_GHOST,1.0)
		return
	var y:=183.0
	var groups: Array[String]=[
		"移动：ZASD / 方向键；未选部队时右键寻路。W 用于屏障。",
		"技能：Q 斩光 / W 屏障 / E 突进 / R 灯焰 / X 治疗。",
		"建设：Y打开；1/2/3选建筑；PgUp/Dn翻页。\n左键/F确认；H维修；Del拆卖；右键/Esc/Y退出。",
		"科技：工坊→回收/中转；兵营+工坊→研究所。\n研究所→重弩；研究所+工坊→军械厂→迫击炮/指挥中继站。\n中转→采运；兵营→救护站→医护；中继站训练时长×0.9/×0.8。",
		"互动：F搜集、修灯、升级与重建；普通H修近塔。",
		"塔防：G 目标模式，C 集火，J/K 二级塔专精；T 机关，B 路障。",
		"探索：P路线；4/5/6委托；追加4返家/5加码；7/8/9反制。\n白昼选队右键发电机：守圈12秒并清守；日落中断。",
		"部队：U盾卫 / I弩手 / N工程员；F3训练其余兵种。\n医护默认停疗，每次2零件，可开关；迫击炮近敌停火。\nF3选生产营和集结点；集结工队需恢复自动采运。",
		"编组：Ctrl+1/2/3保存；数字召回，Shift+数字追加。\n点选/框选/Shift追加；Tab全选，O驻守，Alt+O撤回。\n右键指挥/工队采运；Shift+右键推进；撤回不改工队。\nAlt+右键活工队：护航往返；右键改令。",
		"整备：白昼L补员，V铭刻；Esc依次关闭详情、建设、部队选择，最后暂停。",
		"界面：F3 战术详情；点击上方标签切页，地图按钮展开地图。",
		"声音：M 配乐开关，[ / ] 音量，F1 来源；F2 减弱震动与闪光。",
	]
	for text: String in groups:y=_paragraph(ui,text,Vector2(TEXT_X,y),TEXT_WIDTH,15,ui.ink,20)+5.0

static func _dictionary_property(object: Object, property_name: String) -> Dictionary:
	var value: Variant=object.get(property_name)
	return value if value is Dictionary else {}

static func _budget_color(ui: Control, budget: Dictionary) -> Color:
	var risk:=String(budget.get("risk","ready"))
	if risk in ["late","unreachable","unavailable_offer"]:return ui.red
	return ui.amber if risk=="tight" else GREEN

static func _paragraph(ui: Control, value: String, position: Vector2, width: float,
		size_px: int, color: Color, line_height: float=21.0, max_lines: int=0) -> float:
	var lines:=_wrap(ui,value,width,size_px)
	var count:=lines.size() if max_lines<=0 else mini(max_lines,lines.size())
	for index in count:ui.label(lines[index],position+Vector2(0,index*line_height),size_px,color)
	return position.y+count*line_height

static func _wrap(ui: Control, value: String, width: float, size_px: int) -> Array[String]:
	var font: Font=ui.get("font") as Font
	var result: Array[String]=[]
	if value.is_empty():return result
	for paragraph: String in value.split("\n",true):
		var line:=""
		for index in paragraph.length():
			var character:=paragraph.substr(index,1)
			var candidate:=line+character
			if not line.is_empty() and font.get_string_size(candidate,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px).x>width:
				result.append(line.rstrip(" "))
				line="" if character==" " else character
			else:line=candidate
		result.append(line)
	return result
