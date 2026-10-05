extends RefCounted
## Read-only presentation for the live HUD. Route estimates are supplied by the
## owning Control; painting never asks navigation to calculate a new path.

const PHASE_RECT := Rect2(24,20,238,62)
const OBJECTIVE_RECT := Rect2(426,20,588,76)
const RESOURCE_RECT := Rect2(1080,20,336,70)
const HERO_RECT := Rect2(344,800,752,80)
const MEMORY_RECT := Rect2(1108,800,104,80)
const TACTICS_RECT := Rect2(24,824,126,36)
const MAP_BUTTON_RECT := Rect2(164,824,96,36)
const DRAWER_RECT := Rect2(24,112,540,622)
const DRAWER_CLOSE_RECT := Rect2(428,692,112,30)
const TAB_IDS := ["contract","exploration","army","defense","help"]
const TAB_TITLES := ["委托","探索","部队","防线","操作"]
const TEXT_X := 46.0
const TEXT_WIDTH := 496.0
const GREEN := Color("a3d7bd")
const BLUE := Color("8ec8d8")

static func draw_live(ui: Control) -> void:
	var game: Node3D=ui.get("game") as Node3D
	if not is_instance_valid(game) or not is_instance_valid(game.hero):return
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

static func _phase(game: Node3D) -> String:
	if game.phase=="paused":return String(game.paused_from)
	if game.phase=="draft":return String(game.return_phase)
	return String(game.phase)

static func _draw_phase(ui: Control, game: Node3D, phase: String) -> void:
	var night:=phase=="night"
	var tint: Color=ui.red if night else ui.amber
	ui.box(PHASE_RECT,ui.panel,Color("645e4c"))
	ui.label("第%d%s · %s" % [game.day_number,"夜" if night else "日","守卫" if night else "搜寻"],Vector2(40,45),18,tint)
	var seconds:=maxi(0,ceili(float(game.phase_time)))
	ui.label("%02d:%02d" % [seconds/60,seconds%60],Vector2(185,45),17,ui.ink)
	var detail: String=game.run_mode_title()
	if night:detail="第%d/%d波 · %s" % [game.wave_index,game.WAVES_PER_NIGHT,game.run_mode_title()]
	ui.label(detail,Vector2(40,68),13,ui.muted)
	var length: float=game.NIGHT_LENGTH if night else game.DAY_LENGTH
	ui.progress(Rect2(40,75,206,3),float(game.phase_time)/length,tint)

static func _draw_objective(ui: Control, game: Node3D, phase: String) -> void:
	var boss: Dictionary=game.boss_snapshot() if phase=="night" else {}
	var rect:=OBJECTIVE_RECT
	if not boss.is_empty():rect.size.y=110
	ui.box(rect,ui.panel,Color("815e4b") if phase=="night" else Color("587768"))
	if not boss.is_empty():
		_draw_boss(ui,game,boss)
		return
	var title:="守住南门"
	var detail:="F3 查看战术详情"
	if phase=="night":
		var preview: Dictionary=game.wave_preview()
		if not preview.is_empty():
			title="下一波 · %s · %d只 · %.0f秒" % [String(preview.title),int(preview.count),float(preview.remaining)]
			detail=String(preview.advice)
		elif bool(game.final_clearance_active):
			title="末夜清场 · 清除剩余威胁"
			detail="首领与残敌全部清除后结算"
		else:
			title="最后一波已抵达 · 守住南门"
			detail="处理主要威胁，保护灯塔与受压防线"
	elif phase=="day":
		var contract: Node=game.contracts
		title=_contract_objective(contract)
		if String(contract.status)=="active":
			var remaining:=maxf(0.0,float(game.phase_time)-contract.selected_risk_seconds())
			detail="目标余时 %.0f秒 · P 指路 / F 行动 · F3 查看方案" % remaining
		elif String(contract.status)=="bonus_offer":detail="4 返家保底 / 5 追加 · F3 查看真实返家估时"
		elif String(contract.status) in ["bonus_active","returning"]:detail="P 前往当前目标 · 日落前返回灯塔交付"
		else:detail="Y 城内建设 · 或外出搜寻 · F3 查看详情"
	if float(game.beacon_alarm_time)>0.0:
		detail="灯塔受到攻击 -%d · 立即回防" % ceili(float(game.beacon_alarm_damage))
	_paragraph(ui,title,Vector2(444,46),552,18,ui.amber if phase=="night" else GREEN,22,1)
	_paragraph(ui,detail,Vector2(444,72),552,14,ui.red if float(game.beacon_alarm_time)>0.0 else ui.muted,20,1)

static func _draw_boss(ui: Control, game: Node3D, boss: Dictionary) -> void:
	var state:=String(boss.get("phase","approach"))
	if state=="dead":
		ui.label("末夜首领 · 已击破",Vector2(444,47),18,GREEN)
		var remaining:=0
		for creature in game.enemies:
			if is_instance_valid(creature) and not creature.is_queued_for_deletion() and creature.alive:remaining+=1
		ui.label("清场中 · 残敌%d · 全部清除后结算" % remaining,Vector2(444,79),15,ui.amber)
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
	ui.box(RESOURCE_RECT,ui.panel,ui.red if threatened else Color("665b45"))
	ui.label("零件 %d" % int(game.scrap),Vector2(1097,45),18,ui.ink)
	ui.label("灯塔 %d/%d" % [ceili(float(game.beacon_hp)),int(game.BEACON_MAX)],Vector2(1246,44),14,ui.red if threatened else ui.amber)
	ui.progress(Rect2(1097,56,302,5),float(game.beacon_hp)/float(game.BEACON_MAX),ui.red if threatened else ui.amber)
	ui.label("铭刻 %d零件" % game.run.memory_cost(),Vector2(1097,79),14,ui.muted)
	if threatened:ui.label("受击 -%d" % ceili(float(game.beacon_alarm_damage)),Vector2(1286,79),13,ui.red)
	elif int(game.run.pending)>0:ui.label("可铭刻 %d 张" % int(game.run.pending),Vector2(1286,79),13,GREEN)

static func _draw_hero(ui: Control, game: Node3D) -> void:
	ui.box(HERO_RECT,Color(.022,.038,.044,.94),Color("53635d"))
	ui.label("生命 %d/%d" % [ceili(float(game.hero.hp)),int(game.hero.max_hp)],Vector2(360,826),14,ui.ink)
	ui.progress(Rect2(360,835,178,7),float(game.hero.hp)/maxf(1.0,float(game.hero.max_hp)),ui.red)
	ui.label("法力 %d/%d" % [floori(float(game.mana)),int(game.max_mana)],Vector2(360,860),13,BLUE)
	ui.progress(Rect2(360,868,178,4),float(game.mana)/maxf(1.0,float(game.max_mana)),BLUE)
	var names:=["Q 斩光","W 屏障","E 突进","R 灯焰","X 治疗"]
	for index in 5:
		var x:=558.0+index*105.0
		var status: String=game.skill_status(index)
		var tint: Color=ui.red if status=="法力不足" else (ui.amber if float(game.cooldowns[index])<=0.0 else ui.muted)
		ui.box(Rect2(x,810,99,61),Color(.052,.072,.069,.9),tint if status=="法力不足" else Color("52695e"))
		ui.label(names[index],Vector2(x+11,834),14,ui.ink)
		ui.label(status,Vector2(x+11,858),13,tint)
	var pending:=int(game.run.pending)
	var available: bool=game.run.has_available_upgrade()
	var affordable: bool=available and int(game.scrap)>=game.run.memory_cost()
	var ready: bool=pending>0 or affordable
	ui.box(MEMORY_RECT,Color(.034,.069,.060,.94),ui.amber if ready else Color("527568"))
	ui.label("V 铭刻",Vector2(1125,828),16,ui.amber if ready else ui.muted)
	var memory_text:="可选%d张" % pending if pending>0 else ("%d零件" % game.run.memory_cost() if affordable else "差%d零件" % maxi(0,game.run.memory_cost()-int(game.scrap)))
	if pending<=0 and not available:memory_text="强化已满"
	_paragraph(ui,memory_text,Vector2(1117,853),86,13,GREEN if ready else ui.muted,18,2)

static func _draw_navigation_buttons(ui: Control, game: Node3D) -> void:
	var open:=String(ui.get("detail_tab")) in TAB_IDS
	ui.box(TACTICS_RECT,Color(.027,.053,.048,.94),GREEN if open else Color("617364"))
	ui.label("F3 战术" if not open else "F3 收起",Vector2(43,848),16,GREEN if open else ui.ink)
	ui.box(MAP_BUTTON_RECT,ui.panel,Color("617364"))
	ui.label("地图",Vector2(195,848),16,ui.ink)
	if not is_instance_valid(game.squads):return
	var snapshot: Dictionary=game.squads.snapshot()
	if int(snapshot.get("selected",0))<=0:return
	ui.box(Rect2(24,762,300,54),Color(.027,.047,.042,.93),Color("52695c"))
	ui.label("已选%d队 · 全军%d人" % [int(snapshot.selected),int(snapshot.alive)],Vector2(38,783),14,GREEN)
	ui.label("右键移动/攻击 · O 驻守",Vector2(38,808),13,ui.muted)

static func _draw_notice(ui: Control, game: Node3D) -> void:
	if game.construction.active or float(game.hero_damage_flash_time)>0.0:return
	if float(game.notice_time)<=0.0 or String(game.notice).is_empty():return
	var lines:=_wrap(ui,String(game.notice),716,15)
	var count:=mini(2,lines.size())
	ui.box(Rect2(344,740,752,48),Color(.025,.044,.044,.91),Color("827256"))
	for index in count:
		ui.label(lines[index],Vector2(362,759+index*20),15,ui.ink)

static func _draw_active_tags(ui: Control, game: Node3D) -> void:
	if not is_instance_valid(game.exploration):return
	var exploration: Node=game.exploration
	var labels: Array[String]=[]
	if int(exploration.streak)>0 and float(exploration.streak_time)>0.0:
		labels.append("换类%d连 · %.0f秒" % [int(exploration.streak),ceilf(float(exploration.streak_time))])
	if exploration.affinity_active():labels.append("共鸣 +8零件 · %.0f秒" % ceilf(float(exploration.affinity_time)))
	if labels.is_empty():return
	var text:=" · ".join(labels)
	var font: Font=ui.get("font") as Font
	var width:=minf(380.0,font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x+26.0)
	ui.box(Rect2(24,100,width,29),Color(.028,.050,.045,.80),Color("4e6b5c"))
	ui.label(text,Vector2(37,120),13,GREEN)

static func _draw_drawer(ui: Control, game: Node3D, tab: String) -> void:
	ui.box(DRAWER_RECT,Color(.021,.037,.040,.97),Color("62776a"))
	for index in TAB_IDS.size():
		var rect: Rect2=ui.details_tab_rect(index)
		var selected: bool=tab==TAB_IDS[index]
		ui.box(rect,Color(.08,.13,.11,.97) if selected else Color(.029,.046,.044,.97),GREEN if selected else Color("3e5148"))
		ui.label(TAB_TITLES[index],rect.position+Vector2(32,23),16,GREEN if selected else ui.muted)
	match tab:
		"contract":_draw_contract(ui,game)
		"exploration":_draw_exploration(ui,game)
		"army":ui.draw_squads()
		"defense":_draw_defense(ui,game)
		"help":_draw_help(ui)
	ui.box(DRAWER_CLOSE_RECT,Color(.027,.047,.042,.96),Color("52695c"))
	ui.label("F3 收起",DRAWER_CLOSE_RECT.position+Vector2(22,21),14,ui.muted)

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
	elif status in ["bonus_offer","bonus_active","returning"]:
		var budget:=_dictionary_property(ui,"contract_return_budget")
		var reward: Dictionary=contract.selected_reward
		y=_paragraph(ui,"主委托保底 +%d零件" % int(reward.scrap),Vector2(TEXT_X,y+8),TEXT_WIDTH,16,ui.amber,23)
		var bonus: Dictionary=contract.bonus_target
		if bonus.is_empty():bonus=budget.get("candidate",{})
		if status=="bonus_offer":
			y=_paragraph(ui,"4 立即返家 · 保留时间整备防线",Vector2(TEXT_X,y+18),TEXT_WIDTH,16,GREEN,23)
			if not bonus.is_empty():
				var title: String=contract.BONUS_TITLES.get(String(bonus.kind),"追加补给")
				y=_paragraph(ui,"5 追加%s · +%d零件" % [title,int(bonus.scrap)],Vector2(TEXT_X,y+14),TEXT_WIDTH,16,ui.amber,23)
			else:y=_paragraph(ui,"暂时没有可达追加补给 · 可直接返家",Vector2(TEXT_X,y+14),TEXT_WIDTH,15,ui.muted,22)
		elif status=="bonus_active":
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

static func _draw_exploration(ui: Control, game: Node3D) -> void:
	if not is_instance_valid(game.exploration):return
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
	y=_paragraph(ui,"最近收益",Vector2(TEXT_X,y+8),TEXT_WIDTH,16,GREEN,23)
	var toasts: Array=game.reward_toasts
	for index in mini(4,toasts.size()):
		var toast: Dictionary=toasts[index]
		y=_paragraph(ui,String(toast.title)+"："+String(toast.detail),Vector2(TEXT_X,y+6),TEXT_WIDTH,14,toast.get("color",ui.ink),20)
	if toasts.is_empty():_paragraph(ui,"采集或互动后，实际奖励与全部加成来源显示在这里。",Vector2(TEXT_X,y+8),TEXT_WIDTH,15,ui.muted,22)

static func _draw_defense(ui: Control, game: Node3D) -> void:
	if _phase(game)=="day":ui.draw_day_forecast()
	else:
		ui.label("守夜防线",Vector2(TEXT_X,184),18,GREEN)
		var title: String="未选择额外反制" if int(game.countermeasure_selected)<0 else game.countermeasure_title(int(game.countermeasure_selected))
		_paragraph(ui,"本夜反制 · "+title,Vector2(TEXT_X,215),TEXT_WIDTH,16,ui.ink,23)
		if int(game.countermeasure_selected)>=0:
			_paragraph(ui,game.countermeasure_summary(int(game.countermeasure_selected)),Vector2(TEXT_X,248),TEXT_WIDTH,15,ui.muted,22)
		_paragraph(ui,"反制在白昼按7/8/9选择，天黑前可更换。",Vector2(TEXT_X,286),TEXT_WIDTH,15,ui.muted,22)
		var gate:="路障%d耐久" % ceili(float(game.gate_barricade_hp)) if float(game.gate_barricade_hp)>0.0 else "路障未部署"
		_paragraph(ui,"%s · 机关%d/%d · C集火%s" % [gate,game.gate_trap_charges,game.GATE_TRAP_MAX,"冷却%.0f秒" % ceilf(float(game.focus_cooldown)) if float(game.focus_cooldown)>0.0 else "就绪"],Vector2(TEXT_X,336),TEXT_WIDTH,15,ui.ink,22)
	ui.label("整备建议",Vector2(TEXT_X,388),17,GREEN)
	var growth: Dictionary=game.growth_snapshot()
	var y:=412.0
	for line: String in ui.growth_lines(growth):y=_paragraph(ui,line,Vector2(TEXT_X,y),TEXT_WIDTH,15,ui.ink,22)
	y=_paragraph(ui,ui.growth_memory_text(growth),Vector2(TEXT_X,y+8),TEXT_WIDTH,15,ui.amber,22)
	y=_paragraph(ui,"防御塔%d座 · 通信塔%d/8 · 清除%d只" % [game.tower_count(),game.relay_count(),game.kills],Vector2(TEXT_X,y+14),TEXT_WIDTH,14,ui.muted,20)
	_paragraph(ui,"灯下同伴%d/2 · 修灯%d零件 · 南门机关%d/%d" % [game.survivors_rescued,game.beacon_repair_cost(),game.gate_trap_charges,game.GATE_TRAP_MAX],Vector2(TEXT_X,y+3),TEXT_WIDTH,14,ui.muted,20)

static func _draw_help(ui: Control) -> void:
	var y:=183.0
	var groups: Array[String]=[
		"移动：ZASD / 方向键；未选部队时右键寻路。W 用于屏障。",
		"技能：Q 斩光 / W 屏障 / E 突进 / R 灯焰 / X 治疗。",
		"建设：Y 选址；1 塔3×3 / 2 兵营4×3 / 3 工坊3×2。左键/F 连续确认，右键/Esc/Y 退出。",
		"互动：F 搜集、修灯、升级与重建；H 修塔。",
		"塔防：G 目标模式，C 集火，J/K 二级塔专精；T 机关，B 路障。",
		"探索：P 前往当前路线；4/5/6 选委托，追加阶段4 返家 / 5 追加；7/8/9 选战前反制。",
		"部队：U 盾卫 / I 弩手 / N 工程员；每座兵营独立队列。",
		"指挥：点选/框选，Shift 追加，Tab 全选；右键移动/攻击，O 驻守或召回。",
		"整备：白昼L 付费补员；V 用零件铭刻。Esc先收起详情/地图，再取消建设或部队选择，最后暂停。",
		"界面：F3 战术详情；点击上方标签切页，地图按钮展开地图。",
		"声音：M 配乐开关，[ / ] 音量，F1 来源；F2 减弱震动与闪光。",
	]
	for text: String in groups:y=_paragraph(ui,text,Vector2(TEXT_X,y),TEXT_WIDTH,15,ui.ink,21)+7.0

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
