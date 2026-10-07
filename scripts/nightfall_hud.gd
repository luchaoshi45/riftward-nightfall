extends Control
## Compact dark-fantasy HUD for the outpost loop.
const Layout = preload("res://scripts/outpost_layout.gd")
const CleanHud = preload("res://scripts/nightfall_clean_hud.gd")
const Catalog = preload("res://scripts/outpost_catalog.gd")
const CATALOG_PAGE_SIZE := 3
const CONSTRUCTION_PANEL_RECT := Rect2(435,642,570,140)
const DEMOLITION_BUTTON_RECT := Rect2(870,748,119,26)
const REPAIR_BUTTON_RECT := Rect2(746,748,112,26)
const RALLY_SELECTOR_RECT := Rect2(46,422,188,27)
const RALLY_SET_RECT := Rect2(245,422,136,27)
const RALLY_RESET_RECT := Rect2(392,422,140,27)
const RALLY_PROMPT_RECT := Rect2(435,674,570,84)
const RALLY_CANCEL_RECT := Rect2(870,726,119,26)
const SALVAGE_NAV_RECT := Rect2(46,692,190,30)
const HELP_TOGGLE_RECT := Rect2(46,692,190,30)
const SALVAGE_DRAW_RECT := Rect2(46,418,496,38)
const SALVAGE_SAFE_MODE_RECT := Rect2(46,464,250,34)
const SALVAGE_JACKPOT_MODE_RECT := Rect2(302,464,240,34)
const BONUS_RETURN_RECT := Rect2(46,244,496,32)
const BONUS_CONFIRM_RECT := Rect2(46,568,496,34)
const SQUAD_PANEL_RECT := CleanHud.DRAWER_RECT
const RESULT_RETRY_RECT := Rect2(397,648,304,52)
const RESULT_NEW_RECT := Rect2(739,648,304,52)
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
var blueprint_rects: Array[Rect2] = []
var training_cancel_buttons: Array[Dictionary] = []
var training_page := 0
var construction_page := 0
var troop_page := 0
const BOSS_PANEL_RECT := Rect2(457,24,570,110)
const WAVE_WAGER_TARGET_WIDTH := 158.0
const WAVE_WAGER_TARGET_HEIGHT := 48.0
const WAVE_WAGER_TARGET_GAP := 4.0
const WAVE_WAGER_RISK_RECT := Rect2(46,0,158,36)
const EXPLORATION_PANEL_RECT := Rect2(24,197,340,244)
const EXPLORATION_TOAST_TOP := 451.0
const GROWTH_PANEL_RECT := Rect2(1050,732,365,111)
const GROWTH_MEMORY_RECT := CleanHud.MEMORY_RECT
const MEMORY_BUTTON_RECT := CleanHud.MEMORY_RECT
const TACTICS_BUTTON_RECT := CleanHud.TACTICS_RECT
const MAP_BUTTON_RECT := CleanHud.MAP_BUTTON_RECT
const BUILD_BUTTON_RECT := CleanHud.BUILD_BUTTON_RECT
const DETAIL_CLOSE_RECT := CleanHud.DRAWER_CLOSE_RECT
const HAUL_BUTTON_RECT := Rect2(356,628,176,32)
const MEDIC_BUTTON_RECT := Rect2(356,662,176,26)
const SELECTED_SQUAD_RECT := Rect2(24,762,300,54)
# Keep transient world text subordinate to the battlefield; rings and urgent
# hero warnings remain visible even when secondary labels are capped.
const MAX_RENDERED_COMBAT_FLOATS := 6
const MAX_RENDERED_WORLD_LABELS := 3
var detail_tab := ""
var salvage_draw_open := false
var help_details_open := false
var map_expanded := false
var contract_primary_budget: Dictionary = {}
var contract_return_budget: Dictionary = {}
var bonus_route_budgets: Array[Dictionary] = []
var budget_refresh_time := 0.0
var world_warning_rects: Array[Rect2] = []
var rally_feedback := ""

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
	var actual_font: Font=display_font if latin else font
	# A one-pixel dark edge keeps the cardless HUD legible over pale ground and
	# moving buildings without bringing back opaque panels or changing layout.
	draw_string_outline(actual_font,point,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px,1,Color(.015,.022,.023,color.a*.88))
	draw_string(actual_font,point,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px,color)

func box(rect: Rect2,fill: Color=Color(.022,.035,.045,.88),outline: Color=Color("435455")) -> void:
	var style:=StyleBoxFlat.new()
	style.bg_color=fill
	# Low-alpha cards are part of the quiet live rail. Keep the same logical
	# hitbox while removing the heavy shadow/border treatment that made the
	# battlefield look like a stack of opaque windows.
	var quiet:=fill.a<0.55
	style.border_color=Color(outline,outline.a*(0.42 if quiet else 1.0))
	style.set_border_width_all(1 if not quiet else 0)
	style.set_corner_radius_all(5 if quiet else 6)
	style.shadow_color=Color(0,0,0,.02 if quiet else .16)
	style.shadow_size=0 if quiet else 3
	style.shadow_offset=Vector2(0,1 if quiet else 2)
	draw_style_box(style,rect)

func alarm_outline_alpha() -> float:
	# Read the same simulation clock as world lights: no wall-clock flashing
	# behind pause/cards, and reduced effects retain a steady readable warning.
	if not is_instance_valid(game) or not is_instance_valid(game.world):return .76
	if game.combat and game.combat.reduced_effects:return .76
	return .76+.08*sin(game.world.light_time*2.4)

func progress(rect: Rect2,ratio: float,color: Color) -> void:
	draw_rect(rect,Color("202c32"))
	draw_rect(Rect2(rect.position,Vector2(rect.size.x*clampf(ratio,0,1),rect.size.y)),color)

func _process(delta: float) -> void:
	if not is_instance_valid(game):return
	if game.construction.active:construction_page=maxi(0,Catalog.BUILDING_IDS.find(String(game.construction.kind)))/CATALOG_PAGE_SIZE
	if game.construction.active and (not detail_tab.is_empty() or map_expanded):dismiss_details()
	if detail_tab != "contract":return
	budget_refresh_time-=delta
	if budget_refresh_time<=0.0:
		refresh_contract_budgets()
		budget_refresh_time=.28

func refresh_contract_budgets() -> void:
	if not is_instance_valid(game) or not is_instance_valid(game.contracts):return
	if game.phase not in ["day","paused"]:return
	if game.phase=="paused" and game.paused_from!="day":return
	if game.contracts.status=="active":contract_primary_budget=game.contracts.primary_budget()
	elif game.contracts.status in ["bonus_offer","bonus_active","returning"]:contract_return_budget=game.contracts.return_budget()
	bonus_route_budgets.clear()
	if game.contracts.status=="bonus_offer":bonus_route_budgets.assign(game.contracts.bonus_route_options())

func bonus_route_rect(slot: int) -> Rect2:
	return Rect2(46,288+90*slot,496,82)

func dismiss_details() -> void:
	detail_tab=""
	salvage_draw_open=false
	help_details_open=false
	map_expanded=false
	training_cancel_buttons.clear()
	queue_redraw()

func toggle_details(tab: String = "") -> void:
	if game.phase not in ["day","night","paused"] or game.music_credits_open or game.construction.active:return
	if game.rally:game.rally.cancel_setting()
	var target: String="contract" if tab.is_empty() else tab
	if target not in CleanHud.TAB_IDS:return
	if (tab.is_empty() and not detail_tab.is_empty()) or detail_tab==target:
		dismiss_details()
		return
	detail_tab=target
	salvage_draw_open=false
	help_details_open=false
	map_expanded=false
	training_cancel_buttons.clear()
	game.selection_dragging=false
	budget_refresh_time=.28
	refresh_contract_budgets()
	queue_redraw()

func toggle_map() -> void:
	if game.phase not in ["day","night","paused"] or game.music_credits_open or game.construction.active:return
	if game.rally:game.rally.cancel_setting()
	map_expanded=not map_expanded
	detail_tab=""
	salvage_draw_open=false
	help_details_open=false
	training_cancel_buttons.clear()
	game.selection_dragging=false
	queue_redraw()

func details_tab_rect(index: int) -> Rect2:
	return Rect2(36+index*104,124,100,34)

func minimap_rect() -> Rect2:
	return Rect2(1162,106,254,252) if map_expanded else Rect2(1252,106,164,164)

func countermeasure_rect(index: int) -> Rect2:
	return Rect2(44+index*168,280,160,62)

func bounty_rect() -> Rect2:
	return Rect2(46,352,496,30)

func wave_wager_visible() -> bool:
	if not is_instance_valid(game) or game.phase != "day" or not game.has_method("wave_wager_snapshot"):return false
	var state: Dictionary=game.wave_wager_snapshot()
	return bool(state.get("enabled",false)) and String(state.get("state", "")) in ["offered", "selected"]

func wave_wager_origin_y() -> float:
	var bounty_state: Dictionary=game.bounty_snapshot()
	return 466.0 if game.day_number==2 and String(bounty_state.get("state", "")) in ["offered", "selected"] else 394.0

func wave_wager_target_rect(index: int) -> Rect2:
	var row: int=index/3
	var column: int=index%3
	return Rect2(46+column*(WAVE_WAGER_TARGET_WIDTH+WAVE_WAGER_TARGET_GAP),wave_wager_origin_y()+28+row*(WAVE_WAGER_TARGET_HEIGHT+WAVE_WAGER_TARGET_GAP),WAVE_WAGER_TARGET_WIDTH,WAVE_WAGER_TARGET_HEIGHT)

func wave_wager_risk_rect(index: int) -> Rect2:
	return Rect2(46+index*168,wave_wager_origin_y()+139,158,36)

func draw_wave_wager() -> void:
	if not wave_wager_visible():return
	var state: Dictionary=game.wave_wager_snapshot()
	var origin:=wave_wager_origin_y()
	var title_y:=origin+18
	label("夜战押注 · 选一波，再选风险档",Vector2(46,title_y),17,amber)
	label("天黑锁定投入 · 目标波完整清除才派彩 · 失败不退款",Vector2(46,title_y+20),12,muted)
	var targets: Array=state.get("targets",[])
	for index in targets.size():
		var target: Dictionary=targets[index]
		var rect:=wave_wager_target_rect(index)
		var selected:=int(state.get("target_index",-1))==index
		box(rect,Color(.08,.13,.105,.96) if selected else Color(.032,.052,.048,.94),CleanHud.GREEN if selected else Color("4e6559"))
		label("%d波 · %d只" % [index+1,int(target.get("count",0))],rect.position+Vector2(10,19),14,CleanHud.GREEN if selected else ink)
		label("%.0f秒到达" % float(target.get("time",0.0)),rect.position+Vector2(10,38),12,amber if selected else muted)
	var risks: Array=game.wave_wager.risk_options()
	for index in risks.size():
		var risk: Dictionary=risks[index]
		var rect:=wave_wager_risk_rect(index)
		var selected:=String(state.get("selected_tier", ""))==String(risk.get("id", ""))
		box(rect,Color(.12,.09,.05,.98) if selected else Color(.035,.052,.048,.96),amber if selected else Color("586756"))
		label("%s · 投%d / 回%d" % [String(risk.get("label", "风险")),int(risk.get("stake",0)),int(risk.get("reward",0))],rect.position+Vector2(9,23),13,amber if selected else ink)
	label("点目标绑定波次 · 点风险档完成下注",Vector2(46,origin+191),12,Color("a3c7b7"))

func visible_hud_rects() -> Array[Rect2]:
	return live_panel_rects()

func rally_setting() -> bool:
	return is_instance_valid(game) and game.rally!=null and bool(game.rally.active)

func rally_state() -> Dictionary:
	if is_instance_valid(game) and game.rally:return game.rally.snapshot()
	return {"barracks_id":-1,"configured":false,"point":Vector3.INF,"active":false,"title":"自动择营"}

func begin_rally_setting() -> void:
	if not game.rally or game.phase not in ["day","night"]:return
	var result: Dictionary=game.rally.begin_setting()
	if bool(result.ok):
		game.selection_dragging=false
		rally_feedback=""
		dismiss_details()
	game.notify(String(result.reason),3)
	queue_redraw()

func draw_rally_setting() -> void:
	if not rally_setting() or game.phase not in ["day","night"]:return
	var state:=rally_state()
	box(RALLY_PROMPT_RECT,Color(.025,.052,.046,.95),Color("85bfb7"))
	label("%s · 设置集结点" % String(state.title),Vector2(453,700),17,Color("a9d8cf"))
	label("左键确认 · 右键/Esc取消",Vector2(453,724),14,amber)
	CleanHud._paragraph(self,"抵达后驻守 · 工队等待采运命令 · 医护停疗" if rally_feedback.is_empty() else rally_feedback,Vector2(453,747),396,12,muted if rally_feedback.is_empty() else red,17,1)
	box(RALLY_CANCEL_RECT,panel,muted)
	label("取消选点",RALLY_CANCEL_RECT.position+Vector2(22,19),13,ink)

func live_panel_rects() -> Array[Rect2]:
	var areas: Array[Rect2]=[]
	if not is_instance_valid(game) or game.phase not in ["day","night","paused"]:return areas
	var objective:=CleanHud.objective_rect(self,game)
	areas.assign([CleanHud.PHASE_RECT,objective,CleanHud.RESOURCE_RECT,CleanHud.HERO_RECT,
		MEMORY_BUTTON_RECT,TACTICS_BUTTON_RECT,MAP_BUTTON_RECT,BUILD_BUTTON_RECT,minimap_rect()])
	if game.construction.active and game.phase in ["day","night"]:areas.append(CONSTRUCTION_PANEL_RECT)
	elif rally_setting() and game.phase in ["day","night"]:areas.append(RALLY_PROMPT_RECT)
	elif not detail_tab.is_empty():areas.append(CleanHud.DRAWER_RECT)
	var active_tags:=CleanHud.active_tags_rect(self,game)
	if active_tags.has_area():areas.append(active_tags)
	if game.squads.selected_count()>0:areas.append(SELECTED_SQUAD_RECT)
	var event_priority:=_event_priority()
	var notice_area:=CleanHud.notice_rect(self,game)
	# Conditional event copy is painted through the same priority rail as its
	# hitbox.  When a higher-priority warning suppresses a notice or prompt,
	# release that covered space for world input instead of leaving an invisible
	# interceptor behind.
	if event_priority==2 and notice_area.has_area():areas.append(notice_area)
	if event_priority<=1 and game.phase in ["day","night"] and not game.construction.active and not rally_setting() and detail_tab.is_empty() and not game.interaction_prompt().is_empty():areas.append(context_prompt_rect())
	if event_priority==0 and game.kill_chain>0 and game.kill_chain_time>0.0 and detail_tab.is_empty() and not game.construction.active:areas.append(Rect2(24,724,300,30))
	if event_priority==0 and game.combat_milestone_time>0.0:areas.append(Rect2(566,142,530,36))
	if game.hero_damage_flash_time>0.0:areas.append(Rect2(558,773,530,24))
	for warning: Dictionary in _visible_target_warnings():
		if warning.target==game.hero:
			areas.append(Rect2(566,606,530,32))
			break
	return areas

func context_prompt_rect() -> Rect2:
	if game.districts.nearest()>=0:return Rect2(435,642,570,84)
	var pad: int=game.nearest_tower_pad()
	if pad>=0 and game.world.tower_pads[pad].level>=2:return Rect2(435,642,570,84)
	return Rect2(435,682,570,40)

# The live HUD has several short-lived messages that are useful in isolation
# but noisy when they arrive on the same frame. Paint and hitboxes share one
# priority rail so suppressed copy never leaves an invisible input blocker.
func _has_event_warning() -> bool:
	if not is_instance_valid(game):return false
	if float(game.hero_damage_flash_time)>0.0 or float(game.beacon_alarm_time)>0.0:return true
	if not _visible_target_warnings().is_empty():return true
	if game.has_method("lobber_warning_snapshot") and not game.lobber_warning_snapshot().is_empty():return true
	if game.has_method("summoner_warning_snapshot") and not game.summoner_warning_snapshot().is_empty():return true
	if game.has_method("warder_warning_snapshot") and not game.warder_warning_snapshot().is_empty():return true
	return false

func _has_event_prompt() -> bool:
	return game.phase in ["day","night"] and not game.construction.active and not rally_setting() \
		and detail_tab.is_empty() and not game.interaction_prompt().is_empty()

func _has_event_notice() -> bool:
	return CleanHud.notice_rect(self,game).has_area()

func _event_priority() -> int:
	if _has_event_warning():return 3
	if _has_event_notice():return 2
	if _has_event_prompt():return 1
	return 0

func _draw_live_with_event_priority() -> void:
	# Mirror CleanHud.draw_live so notice painting can participate in the same
	# priority rail without changing notice_rect(), notice text, or hit areas.
	var phase: String=String(game.phase)
	if game.phase=="paused":phase=String(game.paused_from)
	elif game.phase=="draft":phase=String(game.return_phase)
	CleanHud._draw_phase(self,game,phase)
	CleanHud._draw_objective(self,game,phase)
	CleanHud._draw_resources(self,game)
	CleanHud._draw_hero(self,game)
	CleanHud._draw_navigation_buttons(self,game)
	var warning:=_has_event_warning()
	# Urgent warnings win over ordinary notices, and notices win over the
	# contextual interaction copy. The notice state itself remains untouched for
	# resumption, while draw_context_prompt() yields when a notice is painted.
	if not warning:CleanHud._draw_notice(self,game)
	if not game.construction.active and detail_tab in CleanHud.TAB_IDS:
		CleanHud._draw_drawer(self,game,detail_tab)
	elif not game.construction.active:
		CleanHud._draw_active_tags(self,game)

func draw_context_prompt() -> void:
	if game.phase not in ["day","night"] or game.construction.active or rally_setting() or not detail_tab.is_empty():return
	if _has_event_warning():return
	if _has_event_notice():return
	var prompt: String=game.interaction_prompt()
	if prompt.is_empty():return
	var rect:=context_prompt_rect()
	draw_line(rect.position,rect.position+Vector2(minf(rect.size.x,110.0),0),Color("c19a5f",.72),1.0)
	CleanHud._paragraph(self,prompt,rect.position+Vector2(0,24),534,15,amber,20,2)
	if rect.size.y<80:return
	var district_index: int=game.districts.nearest()
	if district_index>=0:
		for district: Dictionary in game.districts.snapshots():
			if int(district.index)!=district_index:continue
			CleanHud._paragraph(self,String(district.title)+" · "+String(district.benefit),rect.position+Vector2(0,64),534,13,muted,18,1)
			break
	else:
		var pad: Dictionary=game.world.tower_pads[game.nearest_tower_pad()]
		var hint: String="J 破甲 / K 牵制 · 45零件 · 每座只能改装一次" if game.specializations.branch(pad)=="standard" else "H 修复 · G 目标模式 · C 指定集火"
		label(hint,rect.position+Vector2(0,64),13,muted)

func _draw() -> void:
	world_warning_rects.clear()
	if not is_instance_valid(game) or not is_instance_valid(game.hero):return
	draw_set_transform(Vector2.ZERO,0,get_viewport_rect().size/Vector2(1440,900))
	card_rects.clear()
	mode_rects.clear()
	blueprint_rects.clear()
	training_cancel_buttons.clear()
	if game.music_credits_open:
		draw_music_credits()
		return
	if game.phase=="draft":
		draw_draft()
		return
	if game.phase=="ended":
		draw_result()
		return
	draw_combat_floats()
	_draw_live_with_event_priority()
	draw_minimap()
	draw_context_prompt()
	draw_construction()
	draw_rally_setting()
	draw_selection_rect()
	draw_combat_rewards()
	draw_hero_damage_feedback()
	draw_target_warnings()
	draw_lobber_warnings()
	draw_summoner_warnings()
	draw_warder_warnings()
	draw_shellguard_armor()
	draw_building_repairs()
	if game.phase=="paused":
		if not detail_tab.is_empty() or map_expanded:
			box(Rect2(584,742,352,40),panel,amber)
			label("已暂停 · Esc 先收起详情",Vector2(626,768),16,amber)
		else:draw_pause()

func draw_pause() -> void:
	draw_rect(Rect2(0,0,1440,900),Color(.01,.018,.022,.58))
	box(Rect2(440,258,560,394),panel,Color("b78c57"))
	label("守夜暂停",Vector2(637,319),28,ink)
	label("ESC 继续 · F3 战术详情",Vector2(600,365),18,amber)
	if game.music:
		label("配乐  %s  ·  音量 %d%%" % ["静音" if game.music.muted else "开启",roundi(game.music.get_volume()*100)],Vector2(526,415),18,ink)
		label("M 开关配乐  ·  [ 降低音量  ·  ] 提高音量",Vector2(502,452),16,muted)
	if is_instance_valid(game.combat):label("F2  震动与闪光：%s" % ("已减弱" if game.combat.reduced_effects else "完整反馈"),Vector2(570,494),16,Color("8dcfc3"))
	label("F1  配乐来源与许可",Vector2(603,543),16,amber)
	label("Music by Rusted Music Studio / Fabien C.",Vector2(497,600),14,muted,true)

func construction_kind_rect(index: int) -> Rect2:
	return Rect2(457+index*175,658,166,31)

func training_kind_rect(index: int) -> Rect2:
	return Rect2(44+index*168,230,160,32)

func construction_page_rect(direction: int) -> Rect2:
	return Rect2(922 if direction<0 else 960,696,29,26)

func troop_page_rect(direction: int) -> Rect2:
	return Rect2(456 if direction<0 else 493,267,29,26)

func visible_construction_kinds() -> Array[String]:
	var kinds: Array[String]=[]
	var page: int=maxi(0,Catalog.BUILDING_IDS.find(String(game.construction.kind)))/CATALOG_PAGE_SIZE
	for index in range(page*CATALOG_PAGE_SIZE,mini((page+1)*CATALOG_PAGE_SIZE,Catalog.BUILDING_IDS.size())):
		kinds.append(Catalog.BUILDING_IDS[index])
	return kinds

func visible_training_kinds() -> Array[String]:
	var kinds: Array[String]=[]
	var page:=clampi(troop_page,0,ceili(Catalog.TROOP_IDS.size()/float(CATALOG_PAGE_SIZE))-1)
	for index in range(page*CATALOG_PAGE_SIZE,mini((page+1)*CATALOG_PAGE_SIZE,Catalog.TROOP_IDS.size())):
		kinds.append(Catalog.TROOP_IDS[index])
	return kinds

func select_construction_slot(index: int) -> bool:
	if not is_instance_valid(game) or game.phase not in ["day","night"]:return false
	var kinds:=visible_construction_kinds()
	if not game.construction.active:kinds.assign(Catalog.BUILDING_IDS.slice(0,CATALOG_PAGE_SIZE))
	if index<0 or index>=kinds.size():return false
	if not game.construction.select_kind(kinds[index]):return false
	construction_page=Catalog.BUILDING_IDS.find(kinds[index])/CATALOG_PAGE_SIZE
	game.selection_dragging=false
	dismiss_details()
	return true

func change_construction_page(direction: int) -> void:
	if not game.construction.active or game.phase not in ["day","night"]:return
	var page: int=maxi(0,Catalog.BUILDING_IDS.find(String(game.construction.kind)))/CATALOG_PAGE_SIZE
	var next:=clampi(page+direction,0,ceili(Catalog.BUILDING_IDS.size()/float(CATALOG_PAGE_SIZE))-1)
	if next==page:return
	if game.construction.select_kind(Catalog.BUILDING_IDS[next*CATALOG_PAGE_SIZE]):
		construction_page=next
		queue_redraw()

func change_troop_page(direction: int) -> void:
	if detail_tab!="army" or game.phase not in ["day","night","paused"]:return
	troop_page=clampi(troop_page+direction,0,ceili(Catalog.TROOP_IDS.size()/float(CATALOG_PAGE_SIZE))-1)
	queue_redraw()

func draw_construction() -> void:
	if not game.construction.active or game.phase not in ["day","night"]:return
	var placement: Dictionary=game.construction.snapshot()
	var selling: bool=game.construction.sell_mode
	var repairing: bool=game.construction.repair_mode
	var tint:=Color("85d5a5") if bool(placement.valid) else red
	if not bool(placement.valid) and bool(placement.space_valid):tint=amber if bool(placement.tech_valid) else Color("aca0e8")
	if selling:tint=red if bool(placement.valid) else muted
	if repairing:tint=Color("85d5a5") if bool(placement.valid) else muted
	box(CONSTRUCTION_PANEL_RECT,Color(.025,.052,.046,.95),tint)
	var kinds:=visible_construction_kinds()
	for index in kinds.size():
		var kind: String=kinds[index]
		var rect:=construction_kind_rect(index)
		var selected: bool=not selling and not repairing and kind==String(game.construction.kind)
		box(rect,Color(.06,.15,.12,.95) if selected else panel,tint if selected else muted)
		label("%d %s" % [index+1,String(Catalog.building(kind).title)],rect.position+Vector2(14,22),14,ink)
	var grid_size: Vector2i=placement.size
	if repairing:
		if bool(placement.valid):
			label("%s · %d/%d · %s" % [String(placement.title),ceili(float(placement.hp)),ceili(float(placement.max_hp)),"停止维修" if bool(placement.repairing) else "点击维修"],Vector2(457,714),18,ink)
		else:label("维修模式 · 指向受损建筑",Vector2(457,714),18,ink)
	elif selling:
		label("%s%s · 返还%d零件" % ["拆卖" if bool(placement.get("live",false)) else "清除",String(placement.title),int(placement.refund)] if bool(placement.valid) else "拆卖模式 · 指向建筑查看退款",Vector2(457,714),18,red if bool(placement.valid) else ink)
	else:
		label("%s · %d×%d格 · %d零件" % [placement.title,grid_size.x,grid_size.y,int(placement.cost)],Vector2(457,714),18,ink)
	var page: int=maxi(0,Catalog.BUILDING_IDS.find(String(game.construction.kind)))/CATALOG_PAGE_SIZE
	var pages:=ceili(Catalog.BUILDING_IDS.size()/float(CATALOG_PAGE_SIZE))
	label("%d/%d" % [page+1,pages],Vector2(877,716),13,muted,true)
	for direction in [-1,1]:
		var rect:=construction_page_rect(direction)
		var available: bool=page+direction>=0 and page+direction<pages
		box(rect,panel,muted)
		label("<" if direction<0 else ">",rect.position+Vector2(8,18),14,amber if available else muted)
	label(String(placement.reason),Vector2(457,740),15,tint)
	label("左键/F确认 · 右键/Esc/Y退出",Vector2(457,766),13,amber)
	box(REPAIR_BUTTON_RECT,Color(.045,.13,.09,.95) if repairing else panel,Color("85d5a5") if repairing else muted)
	label("H 建造" if repairing else "H 维修",REPAIR_BUTTON_RECT.position+Vector2(17,18),13,Color("85d5a5") if repairing else ink)
	box(DEMOLITION_BUTTON_RECT,Color(.13,.045,.035,.95) if selling else panel,red if selling else muted)
	label("Del 建造" if selling else "Del 拆卖",DEMOLITION_BUTTON_RECT.position+Vector2(17,18),13,red if selling else ink)

func draw_building_repairs() -> void:
	if game.phase not in ["day","night"] or not is_instance_valid(game.camera):return
	var occupied: Array[Rect2]=live_panel_rects()
	occupied.append_array(world_warning_rects)
	var scale_factor:=Vector2(1440,900)/get_viewport_rect().size
	for target: Dictionary in game.repairs.snapshot().targets:
		var point: Vector3=target.point+Vector3.UP*2.8
		if game.camera.is_position_behind(point):continue
		var anchor: Vector2=game.camera.unproject_position(point)*scale_factor
		var rect:=Rect2(anchor-Vector2(38,24),Vector2(76,24))
		if not Rect2(0,0,1440,900).encloses(rect):continue
		var covered:=false
		for area: Rect2 in occupied:
			if area.intersects(rect):covered=true;break
		if covered:continue
		var waiting: bool=String(target.status)=="waiting"
		var tint:=amber if waiting else Color("85d5a5")
		box(rect,panel,tint)
		label("待零件" if waiting else "维修",rect.position+Vector2(15 if waiting else 25,16),12,tint)
		if not waiting:
			draw_line(rect.position+Vector2(5,22),rect.position+Vector2(5+66*clampf(float(target.elapsed),0,1),22),tint,2)
		occupied.append(rect)

func draw_selection_rect() -> void:
	if not game.selection_dragging or game.phase not in ["day","night"]:return
	var factor:=Vector2(1440,900)/get_viewport_rect().size
	var rect:=Rect2(game.selection_start*factor,(game.selection_end-game.selection_start)*factor).abs()
	if rect.size.length()<8.0:return
	draw_rect(rect,Color(.3,.8,.6,.12))
	draw_rect(rect,Color("86d9b2"),false,1.5)

func draw_combat_floats() -> void:
	if game.phase!="day" and game.phase!="night":return
	if game.music_credits_open or not is_instance_valid(game.combat) or not is_instance_valid(game.camera):return
	var canvas_size: Vector2=get_viewport_rect().size
	if canvas_size.x<=0.0 or canvas_size.y<=0.0:return
	var occupied: Array[Rect2]=live_panel_rects()
	occupied.append_array(world_warning_rects)
	# New contacts get their natural screen position first; older messages stack
	# above them or expire without obscuring another reward or a fixed HUD panel.
	var rendered_count := 0
	for index in range(game.combat.floats.size()-1,-1,-1):
		if rendered_count >= MAX_RENDERED_COMBAT_FLOATS:break
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
		world_warning_rects.append(footprint)
		draw_string_outline(font,position,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px,3,Color(.014,.024,.028,.84*fade))
		label(value,position,size_px,tint)
		rendered_count += 1

func _world_screen(point: Vector3) -> Variant:
	if not is_instance_valid(game.camera) or game.camera.is_position_behind(point):return null
	var viewport_size:=get_viewport_rect().size
	if viewport_size.x<=0.0 or viewport_size.y<=0.0:return null
	return game.camera.unproject_position(point)*Vector2(1440,900)/viewport_size

func _visible_target_warnings() -> Array[Dictionary]:
	var visible: Array[Dictionary]=[]
	if not is_instance_valid(game) or game.phase not in ["day","night","paused"] or not game.has_method("target_warning_snapshot"):return visible
	for warning: Dictionary in game.target_warning_snapshot():
		var source:=warning.get("source") as BattleUnit
		var target:=warning.get("target") as Node3D
		# Friendly windups and off-screen attacks do not paint a danger warning,
		# so they must not suppress feedback or reserve invisible HUD hitboxes.
		if not is_instance_valid(source) or source.team!=2 or not is_instance_valid(target):continue
		var screen: Variant=_world_screen(target.global_position+Vector3.UP*1.05)
		if screen==null:continue
		var position:=screen as Vector2
		if not Rect2(0,0,1440,900).has_point(position):continue
		var shown:=warning.duplicate()
		shown["screen"]=position
		visible.append(shown)
	return visible

func draw_target_warnings() -> void:
	if game.phase not in ["day","night","paused"] or not game.has_method("target_warning_snapshot"):return
	var hero_warning_count:=0
	var hero_remaining:=INF
	var hero_source_title: String=""
	var rendered_labels := 0
	for warning: Dictionary in _visible_target_warnings():
		var target:=warning.get("target") as Node3D
		var position:=warning.screen as Vector2
		var remaining:=maxf(0.0,float(warning.get("remaining",0.0)))
		var progress_value:=clampf(float(warning.get("progress",0.0)),0.0,1.0)
		var danger:=Color("f08b67") if String(warning.get("threat","stalker"))!="runner" else Color("e5bb70")
		var radius:=16.0+1.5*progress_value
		# Reserve the rings and short progress bar as well as their text. A
		# building's optional maintenance label must leave the danger visible.
		var extent:=radius+6.5
		world_warning_rects.append(Rect2(position-Vector2.ONE*extent,Vector2.ONE*extent*2))
		world_warning_rects.append(Rect2(position+Vector2(-6.5,-radius-10.5),Vector2(13,5)))
		draw_arc(position,radius,0.0,TAU,48,danger,2.4,true)
		draw_arc(position,radius+4.0,-PI*.5,-PI*.5+TAU*progress_value,48,Color("ffe0a1"),2.5,true)
		draw_line(position+Vector2(-4,-radius-8),position+Vector2(4,-radius-8),Color(.04,.02,.015,.88),5.0)
		draw_line(position+Vector2(-4,-radius-8),position+Vector2(-4+8.0*progress_value,-radius-8),danger,3.0)
		var label_text: String="蓄力 %.1f" % remaining
		if target==game.hero:
			hero_warning_count+=1
			if remaining<hero_remaining:
				hero_remaining=remaining
				hero_source_title=String(warning.get("title","敌人"))
		if target!=game.hero:
			if rendered_labels >= MAX_RENDERED_WORLD_LABELS:continue
			var text_width:=font.get_string_size(label_text,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x
			var label_point:=position+Vector2(-text_width*.5,-radius-13)
			# Later support/armor labels must respect this actual target-side text.
			world_warning_rects.append(Rect2(label_point-Vector2(3,font.get_ascent(12)+3),Vector2(text_width+6,font.get_ascent(12)+font.get_descent(12)+6)))
			label(label_text,label_point,12,danger)
			rendered_labels += 1
	if hero_warning_count>0 and hero_remaining<INF:
		var detail: String="被锁定 · %s · %.1f秒后命中" % [hero_source_title,hero_remaining]
		box(Rect2(566,606,530,32),Color(.12,.035,.028,.95),Color("d87961"))
		var width:=font.get_string_size(detail,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
		label(detail,Vector2(831-width*.5,628),16,Color("ffd1a0"))

func draw_lobber_warnings() -> void:
	if game.phase not in ["night","paused"]:return
	var occupied: Array[Rect2]=live_panel_rects()
	occupied.append_array(world_warning_rects)
	var rendered_labels := 0
	for warning: Dictionary in game.lobber_warning_snapshot():
		if rendered_labels >= MAX_RENDERED_WORLD_LABELS:break
		var point: Vector3=warning.position
		var screen: Variant=_world_screen(point+Vector3.UP*.18)
		if screen==null:continue
		var center: Vector2=screen as Vector2
		if center.x<0 or center.x>1440 or center.y<0 or center.y>900:continue
		# Label the fixed landing point, never the target's new position. F2
		# reduces world decoration while this essential timer stays readable.
		var text_value: String="投蚀 %.1f秒" % maxf(0.0,float(warning.remaining))
		var width: float=font.get_string_size(text_value,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x
		var position:=Vector2(clampf(center.x-width*.5,10,1430-width),clampf(center.y-28,110,790))
		var free_position:=false
		var footprint: Rect2
		for _attempt in 10:
			footprint=Rect2(position-Vector2(3,14),Vector2(width+6,19))
			var overlaps:=false
			for rect: Rect2 in occupied:
				if rect.intersects(footprint):overlaps=true;break
			if not overlaps:free_position=true;break
			position.y-=22
		if not free_position or position.y<96:continue
		occupied.append(footprint)
		world_warning_rects.append(footprint)
		draw_string_outline(font,position,text_value,HORIZONTAL_ALIGNMENT_LEFT,-1,13,3,Color(.02,.025,.012,.94))
		label(text_value,position,13,Color("eed897"))
		rendered_labels += 1

func draw_summoner_warnings() -> void:
	if game.phase not in ["night","paused"]:return
	var occupied: Array[Rect2]=live_panel_rects()
	occupied.append_array(world_warning_rects)
	var rendered_labels := 0
	for warning: Dictionary in game.summoner_warning_snapshot():
		if rendered_labels >= MAX_RENDERED_WORLD_LABELS:break
		var screen: Variant=_world_screen((warning.position as Vector3)+Vector3.UP*2.1)
		if screen==null:continue
		var center: Vector2=screen as Vector2
		if center.x<0 or center.x>1440 or center.y<0 or center.y>900:continue
		var text_value: String="召援 %.1f秒 · 可打断" % maxf(0.0,float(warning.remaining))
		var width: float=font.get_string_size(text_value,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x
		var position:=Vector2(clampf(center.x-width*.5,10,1430-width),clampf(center.y-10,110,790))
		var free_position:=false
		for _attempt in 10:
			var footprint:=Rect2(position-Vector2(3,14),Vector2(width+6,19))
			var overlaps:=false
			for rect: Rect2 in occupied:
				if rect.intersects(footprint):overlaps=true;break
			if not overlaps:
				occupied.append(footprint)
				world_warning_rects.append(footprint)
				free_position=true
				break
			position.y-=22
		if not free_position or position.y<96:continue
		draw_string_outline(font,position,text_value,HORIZONTAL_ALIGNMENT_LEFT,-1,13,3,Color(.02,.025,.012,.94))
		label(text_value,position,13,Color("c4a9e5"))
		rendered_labels += 1

func draw_warder_warnings() -> void:
	if game.phase not in ["night","paused"]:return
	var occupied: Array[Rect2]=live_panel_rects()
	occupied.append_array(world_warning_rects)
	var rendered_labels := 0
	for warning: Dictionary in game.warder_warning_snapshot():
		if rendered_labels >= MAX_RENDERED_WORLD_LABELS:break
		var text_value:="织壳 %.1f秒 · 余%d/3" % [maxf(0.0,float(warning.remaining)),maxi(0,int(warning.max_casts)-int(warning.casts))]
		_draw_shell_label((warning.position as Vector3)+Vector3.UP*2.1,text_value,Color("d4dec3"),occupied)
		rendered_labels += 1
	# Read the recipient's real shield, even after the source has been killed.
	for value: Variant in game.enemies:
		if rendered_labels >= MAX_RENDERED_WORLD_LABELS:break
		if not is_instance_valid(value) or value.is_queued_for_deletion() or not value.alive:continue
		if not bool(value.get_meta("warder_shield",false)) or value.shield<=0.0 or value.shield_time<=0.0:continue
		var text_value:="护盾%d · %.1f秒" % [ceili(float(value.shield)),float(value.shield_time)]
		_draw_shell_label(value.position+Vector3.UP*1.65,text_value,Color("b8dcd3"),occupied)
		rendered_labels += 1

func draw_shellguard_armor() -> void:
	if game.phase not in ["night","paused"]:return
	var occupied: Array[Rect2]=live_panel_rects()
	occupied.append_array(world_warning_rects)
	var rendered_labels := 0
	for value: Variant in game.enemies:
		if rendered_labels >= MAX_RENDERED_WORLD_LABELS:break
		if not is_instance_valid(value) or value.is_queued_for_deletion() or not value.alive:continue
		if value.get_meta("threat","")!="shellguard" or float(value.armor)<=0.0:continue
		# The local label reads actual armor; support timers take placement priority.
		_draw_shell_label(value.position+Vector3.UP*2.1,"甲%d" % ceili(float(value.armor)),Color("d8cda3"),occupied)
		rendered_labels += 1

func _draw_shell_label(point: Vector3, text_value: String, tint: Color, occupied: Array[Rect2]) -> void:
	var screen: Variant=_world_screen(point)
	if screen==null:return
	var center: Vector2=screen as Vector2
	if center.x<0 or center.x>1440 or center.y<0 or center.y>900:return
	var width: float=font.get_string_size(text_value,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x
	var position:=Vector2(clampf(center.x-width*.5,10,1430-width),clampf(center.y-10,110,790))
	for _attempt in 10:
		if position.y<96:return
		var footprint:=Rect2(position-Vector2(3,14),Vector2(width+6,19))
		var overlaps:=false
		for rect: Rect2 in occupied:
			if rect.intersects(footprint):overlaps=true;break
		if not overlaps:
			occupied.append(footprint)
			world_warning_rects.append(footprint)
			draw_string_outline(font,position,text_value,HORIZONTAL_ALIGNMENT_LEFT,-1,13,3,Color(.02,.025,.012,.94))
			label(text_value,position,13,tint)
			return
		position.y-=22

func draw_hero_damage_feedback() -> void:
	if game.phase not in ["day","night","paused"]:return
	if float(game.get("hero_damage_flash_time"))<=0.0:return
	var fade:=clampf(float(game.hero_damage_flash_time)/.18,0.0,1.0)
	var border:=Color("ed756c",.75+.2*fade)
	# Keep the actual hit confirmation persistent in the HUD even when F2
	# reduces particles and camera trauma.
	draw_rect(CleanHud.HERO_RECT,border,false,2.4)
	var text_value:=String(game.hero_damage_flash_text)
	if text_value!="":
		box(Rect2(558,773,530,24),Color(.13,.035,.032,.94),Color("c9665d",.9))
		var width:=font.get_string_size(text_value,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
		label(text_value,Vector2(823-width*.5,790),14,Color("ffd0bc",fade))

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
	if game.night_plan.is_empty():
		label("下一夜威胁情报 · 等待计划生成",Vector2(46,184),18,amber)
		return
	var first: Dictionary=game.night_plan[0]
	label("下一夜 · 第%d夜" % game.day_number,Vector2(46,184),18,Color("a3d7bd"))
	var reinforcement_cap:=0
	for entry: Dictionary in game.night_plan:reinforcement_cap+=int(entry.get("reinforcement_cap",0))
	var composition: String="主威胁 %s · %d波 · 特殊约%d只" % [game.forecast_primary_threat(),game.night_plan.size(),game.forecast_specialist_count()]
	if reinforcement_cap>0:composition+=" · 潜在增援%d" % reinforcement_cap
	label(composition,Vector2(46,212),15,ink)
	CleanHud._paragraph(self,"首波 "+String(first.title)+" · "+String(first.advice),Vector2(46,240),496,14,muted,20,2)
	for index in game.countermeasure_count():
		var rect:=countermeasure_rect(index)
		var selected: bool=game.countermeasure_selected==index
		var recommended: bool=game.countermeasure_recommended(index)
		var outline:=amber if selected else (Color("82c9be") if recommended else Color("4b625d"))
		box(rect,Color(.10,.15,.14,.96) if selected else Color(.045,.075,.073,.92),outline)
		var marker: String="已选" if selected else ("推荐" if recommended else "")
		label("%d %s %s" % [index+7,game.countermeasure_title(index),marker],rect.position+Vector2(8,21),12,amber if selected or recommended else ink)
		var summary: String=game.countermeasure_summary(index).replace("防御塔伤害提高","塔伤提升")
		CleanHud._paragraph(self,summary,rect.position+Vector2(8,41),144,12,muted,16,2)
	var bounty_state: Dictionary=game.bounty_snapshot()
	if game.day_number==2 and String(bounty_state.state) in ["offered","selected"]:
		var selected: bool=String(bounty_state.state)=="selected"
		var rect:=bounty_rect()
		box(rect,Color(.12,.09,.055,.95) if selected else panel,amber if selected else Color("665b45"))
		label("甲壳悬赏 · 清波额外+48零件"+(" · 已选" if selected else ""),rect.position+Vector2(10,21),15,amber if bool(bounty_state.available) or selected else muted)
		label("放弃免费反制 · 第三波两名普通随从换成甲壳卫",Vector2(46,405),14,ink)
		label("该波须在夜间倒计时结束前全部击败；未清无额外奖。",Vector2(46,426),14,muted)
		label("7/8/9 切回免费反制 · 天黑前可更换" if game.phase=="day" else "暂停中 · 恢复后可更换",Vector2(46,448),13,Color("a3c7b7"))
	else:
		label("点击 / 7/8/9 选择 · 天黑前可更换",Vector2(46,364),14,Color("a3c7b7"))

func draw_combat_rewards() -> void:
	if game.phase not in ["day","night","paused"] or not is_instance_valid(game.combat):return
	var transient_priority:=_event_priority()
	var step: int=clampi(int(game.attack_chain),0,2)
	var charged: bool=step==2 and game.attack_chain_time>0.0
	for index in 3:
		var point:=Vector2(489+index*16,819)
		draw_circle(point,3.5,amber if index<step else Color("354b4e"))
		if index==2:draw_arc(point,5,0,TAU,20,amber if charged else muted,1.0,true)
	# The three-hit dots are persistent combat state. The textual streak and
	# milestone share one quiet slot so they never compete with each other or
	# with an interaction/notice rail.
	if transient_priority==0 and game.kill_chain>0 and game.kill_chain_time>0.0 and game.combat_milestone_time<=0.0 and detail_tab.is_empty() and not game.construction.active:
		draw_line(Vector2(24,724),Vector2(104,724),Color("c19a5f",.68),1.0)
		label("连斩%d · %.1f秒" % [game.kill_chain,game.kill_chain_time],Vector2(24,744),14,amber)
		progress(Rect2(24,749,220,2),game.kill_chain_time/6.0,Color(amber,.65))
	if transient_priority==0 and game.combat_milestone_time>0.0:
		var fade: float=minf(1.0,game.combat_milestone_time/.35)
		var message: String=game.combat_milestone_title+" · "+game.combat_milestone_detail
		draw_line(Vector2(566,142),Vector2(662,142),Color("c7a56e",fade),1.0)
		CleanHud._paragraph(self,message,Vector2(566,165),500,14,Color("f2ce86",fade),18,1)

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
	var map_rect:=minimap_rect()
	var compact:=not map_expanded
	if compact:
		# Compact radar is a navigation glyph, not another opaque card. Keep a
		# faint ring and corner marks so it remains discoverable without pulling
		# attention away from the battlefield.
		var compact_center:=map_rect.get_center()+Vector2(0,2)
		draw_circle(compact_center,58.0,Color(.018,.034,.041,.025))
		draw_arc(compact_center,58.0,0,TAU,48,Color("66624d",.20),1.0)
		draw_line(map_rect.position+Vector2(0,1),map_rect.position+Vector2(26,1),Color("66624d",.52),1.0)
		draw_line(map_rect.position+Vector2(map_rect.size.x-26,1),map_rect.position+Vector2(map_rect.size.x,1),Color("66624d",.52),1.0)
		draw_line(map_rect.position+Vector2(0,map_rect.size.y-1),map_rect.position+Vector2(26,map_rect.size.y-1),Color("66624d",.34),1.0)
		draw_line(map_rect.position+Vector2(map_rect.size.x-26,map_rect.size.y-1),map_rect.position+Vector2(map_rect.size.x,map_rect.size.y-1),Color("66624d",.34),1.0)
		label("地图 · 点击展开",map_rect.position+Vector2(9,18),11,Color(muted,.86))
	else:
		box(map_rect,Color(.018,.034,.041,.72),Color("66624d",.82))
		label("地图 · 点击收起",map_rect.position+Vector2(12,21),12,Color(muted,.86))
	var center:=map_rect.get_center()+Vector2(0,2)
	var scale:=.86 if map_expanded else .52
	if map_expanded:
		draw_rect(Rect2(center-Vector2(Layout.MAP_HALF_X,Layout.MAP_HALF_Z)*scale,Vector2(Layout.MAP_HALF_X,Layout.MAP_HALF_Z)*scale*2),Color(.075,.085,.079,.72))
		for wall: Rect2 in Layout.wall_blocks():
			draw_rect(Rect2(center+wall.position*scale,wall.size*scale),Color("a0a398",.82))
	if compact:
		# The collapsed radar is intentionally sparse: beacon, hero, active nests
		# and nearby threats are enough for orientation. F3/map expands the full
		# logistics and construction map when the player needs exact locations.
		for nest in game.world.nests:
			var nest_point: Vector3=nest.position
			var nest_marker:=center+Vector2(nest_point.x,nest_point.z)*scale
			if nest.cleansed:
				draw_circle(nest_marker,3.0,Color("82c8be",.65))
			else:
				draw_circle(nest_marker,4.2,Color("d75b77",.78))
		var shown_threats:=0
		var threat_cap: int=1 if game.phase=="day" else 2
		for creature in game.enemies:
			if shown_threats>=threat_cap:break
			if not is_instance_valid(creature) or not creature.alive:continue
			if creature.position.distance_to(game.hero.position)>22.0 and game.phase!="night":continue
			var threat: String=creature.get_meta("threat","")
			var enemy_marker:=center+Vector2(creature.position.x,creature.position.z)*scale
			draw_circle(enemy_marker,2.8,Color("ed945b",.68) if threat=="breaker" else Color("d7a4d9",.60))
			shown_threats+=1
		draw_circle(center,5.0,Color(amber,.9))
		if game.beacon_alarm_time>0:
			draw_arc(center,10.0,0,TAU,24,Color("f16d58",.9),2.2)
		draw_circle(center+Vector2(game.hero.position.x,game.hero.position.z)*scale,3.6,Color("8ee0e8",.95))
		return
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
		if bool(pad.get("removed",false)):continue
		var p: Vector3=pad.position
		var pad_color: Color=Color("78d1c2") if String(pad.get("zone","outer"))=="core" else amber
		var tower_color: Color=Color("697473")
		if pad.level>0:
			tower_color=Color("b78be8") if pad.mode=="threat" else (Color("ed945b") if pad.mode=="breaker" else pad_color)
		draw_circle(center+Vector2(p.x,p.z)*scale,3.2,tower_color)
	for plot: Dictionary in game.districts.plots:
		if int(plot.level)<=0:continue
		var p: Vector3=plot.position
		var color: Color={"barracks":Color("a9d8cf"),"workshop":Color("d6b777"),"recycler":Color("9fc47b"),"laboratory":Color("9baee0"),"depot":Color("c9be89"),"command_relay":Color("b789d5"),"holdfast_beacon":Color("e2b56c")}.get(String(plot.kind),muted)
		draw_rect(Rect2(center+Vector2(p.x,p.z)*scale-Vector2(2.5,2.5),Vector2(5,5)),color)
	if is_instance_valid(game.logistics):
		for field: Dictionary in game.logistics.snapshot().fields:
			var p: Vector3=field.position
			var marker:=center+Vector2(p.x,p.z)*scale
			draw_rect(Rect2(marker-Vector2(2.5,2.5),Vector2(5,5)),Color("c6b586") if int(field.remaining)>0 else Color("62685c"))
	if is_instance_valid(game.squads):
		for squad: Dictionary in game.squads.squads:
			for member: BattleUnit in squad.members:
				if not is_instance_valid(member) or member.hp<=0:continue
				var marker:=center+Vector2(member.position.x,member.position.z)*scale
				draw_circle(marker,2.1,Color("b6ffc8") if game.squads.selected_ids.has(int(squad.id)) else Color("83aaa6"))
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
		var enemy_marker:=center+Vector2(creature.position.x,creature.position.z)*scale
		if threat=="summoner":
			draw_polyline(PackedVector2Array([enemy_marker+Vector2(0,-4),enemy_marker+Vector2(4,0),enemy_marker+Vector2(0,4),enemy_marker+Vector2(-4,0),enemy_marker+Vector2(0,-4)]),Color("c4a9e5"),1.8)
		elif threat=="warder":
			draw_polyline(PackedVector2Array([enemy_marker+Vector2(-3,-3),enemy_marker+Vector2(3,-3),enemy_marker+Vector2(3,1),enemy_marker+Vector2(0,4),enemy_marker+Vector2(-3,1),enemy_marker+Vector2(-3,-3)]),Color("d4dec3") if bool(creature.get_meta("warder_active",false)) else muted,1.6)
		elif threat=="shellguard":
			draw_polyline(PackedVector2Array([enemy_marker+Vector2(-2,-3.5),enemy_marker+Vector2(2,-3.5),enemy_marker+Vector2(4,0),enemy_marker+Vector2(2,3.5),enemy_marker+Vector2(-2,3.5),enemy_marker+Vector2(-4,0),enemy_marker+Vector2(-2,-3.5)]),Color("d8cda3"),1.7)
		elif threat=="lobber":
			draw_polyline(PackedVector2Array([enemy_marker+Vector2(0,-3.5),enemy_marker+Vector2(3.5,3),enemy_marker+Vector2(-3.5,3),enemy_marker+Vector2(0,-3.5)]),Color("ced78b"),1.8)
		else:
			draw_circle(enemy_marker,3.5 if threat=="breaker" else 2.3,Color("ed945b") if threat=="breaker" else (Color("83d8d9") if threat=="runner" else (Color("a794eb") if threat=="light_eater" else red)))
	draw_circle(center,5.0,amber)
	if game.beacon_alarm_time>0:
		draw_arc(center,11.0,0,TAU,32,Color("f16d58"),2.5)
	draw_circle(center+Vector2(game.hero.position.x,game.hero.position.z)*scale,4.1,Color("8ee0e8"))
	if not map_expanded:return
	label("南门逼近%d · 夜巢%d/3" % [game.gate_pressure(),game.remaining_nests()],map_rect.position+Vector2(12,230),12,red if game.phase=="night" else muted)
func training_page_rect(direction: int) -> Rect2:
	return Rect2(456 if direction<0 else 493,188,29,26)

func selected_hauler_ids() -> Array[int]:
	var ids: Array[int]=[]
	if not is_instance_valid(game.squads):return ids
	for squad: Dictionary in game.squads.squads:
		if String(squad.kind)!="hauler" or not game.squads.selected_ids.has(int(squad.id)):continue
		for member: BattleUnit in squad.members:
			if is_instance_valid(member) and member.alive and not member.is_queued_for_deletion():
				ids.append(int(squad.id));break
	return ids

func haul_button_visible() -> bool:
	return detail_tab=="army" and troop_page==1 and not game.construction.active and not selected_hauler_ids().is_empty() and is_instance_valid(game.logistics)

func selected_medic_ids() -> Array[int]:
	var ids: Array[int]=[]
	if not is_instance_valid(game.squads):return ids
	for squad: Dictionary in game.squads.squads:
		if String(squad.kind)!="medic" or not game.squads.selected_ids.has(int(squad.id)):continue
		for member: BattleUnit in squad.members:
			if is_instance_valid(member) and member.alive and not member.is_queued_for_deletion():
				ids.append(int(squad.id));break
	return ids

func medic_button_visible() -> bool:
	return detail_tab=="army" and troop_page==1 and not game.construction.active and not selected_medic_ids().is_empty()

func selected_hunter_ids() -> Array[int]:
	var ids: Array[int]=[]
	if not is_instance_valid(game.squads):return ids
	for squad: Dictionary in game.squads.squads:
		if String(squad.kind)!="hunter" or not game.squads.selected_ids.has(int(squad.id)):continue
		for member: BattleUnit in squad.members:
			if is_instance_valid(member) and member.alive and not member.is_queued_for_deletion():
				ids.append(int(squad.id));break
	return ids

func selected_medics_enabled() -> bool:
	var ids:=selected_medic_ids()
	if ids.is_empty():return false
	for squad: Dictionary in game.squads.squads:
		if ids.has(int(squad.id)) and not bool(squad.get("therapy_enabled",false)):return false
	return true

func toggle_selected_medics() -> void:
	if game.phase not in ["day","night"] or not medic_button_visible():return
	var enabled:=not selected_medics_enabled()
	var changed:=0
	var reason:="请先选择存活医护队"
	for id in selected_medic_ids():
		var result: Dictionary=game.squads.set_medic_enabled(id,enabled)
		if bool(result.ok):changed+=1
		reason=String(result.reason)
	if changed>0:reason="医护%d队 · %s" % [changed,"开启治疗，每次2零件" if enabled else "停止治疗"]
	game.notify(reason,3)
	queue_redraw()

func control_group_hint() -> String:
	var counts: Array[int]=[0,0,0]
	if is_instance_valid(game) and game.control_groups:
		for row: Dictionary in game.control_groups.snapshot().groups:
			var index:=int(row.slot)-1
			if index>=0 and index<counts.size():counts[index]=int(row.count)
	return "Ctrl+数字存组 · 数字召回 · Shift追加 · 1:%d 2:%d 3:%d" % counts

func draw_squads() -> void:
	training_cancel_buttons.clear()
	if not is_instance_valid(game.squads) or game.phase not in ["day","night","paused"]:return
	var snapshot: Dictionary=game.squads.snapshot()
	label("部队 · 已选%d队 / 共%d队" % [int(snapshot.selected),int(snapshot.count)],Vector2(46,184),17,Color("a9d8cf"))
	label("存活 %d/%d人 · L白昼补员%d零件" % [int(snapshot.alive),int(snapshot.capacity),int(snapshot.refill_cost)],Vector2(46,212),13,ink)
	var kinds:=visible_training_kinds()
	for index in kinds.size():
		var kind:=kinds[index]
		var definition:=Catalog.troop(kind)
		var eligibility: Dictionary=game.squads.training_eligibility(kind)
		var rect:=training_kind_rect(index)
		box(rect,panel,Color("668a78") if bool(eligibility.available) else muted)
		var hotkey: String={"shield":"U","ranged":"I","engineer":"N"}.get(kind,"")
		label("%s%s%d" % [hotkey,definition.title,int(definition.cost)],rect.position+Vector2(9,22),14,amber if bool(eligibility.available) else muted)
	label("兵种 %d/%d · PgUp/PgDn翻页" % [troop_page+1,ceili(Catalog.TROOP_IDS.size()/float(CATALOG_PAGE_SIZE))],Vector2(46,285),12,muted)
	for direction in [-1,1]:
		var rect:=troop_page_rect(direction)
		box(rect,panel,muted)
		label("<" if direction<0 else ">",rect.position+Vector2(8,18),14,amber)
	var rows: Array[Dictionary]=[]
	var total_orders:=0
	# First show one current order per barracks, then pending orders. Each
	# cancellation button retains its exact barracks and queue index.
	for barracks: Dictionary in snapshot.queues:
		total_orders+=barracks.queue.size()
		if barracks.queue.is_empty():continue
		rows.append({"barracks":int(barracks.index),"queue_index":0,"order":barracks.queue[0]})
	for barracks: Dictionary in snapshot.queues:
		for queue_index in range(1,barracks.queue.size()):
			rows.append({"barracks":int(barracks.index),"queue_index":queue_index,"order":barracks.queue[queue_index]})
	var pages:=maxi(1,ceili(rows.size()/3.0))
	training_page=clampi(training_page,0,pages-1)
	for direction in [-1,1]:
		var rect:=training_page_rect(direction)
		box(rect,panel,muted)
		label("<" if direction<0 else ">",rect.position+Vector2(8,18),14,amber)
	for index in mini(3,maxi(0,rows.size()-training_page*3)):
		var row: Dictionary=rows[index+training_page*3]
		var order: Dictionary=row.order
		var name:=String(Catalog.troop(String(order.kind)).get("title","部队"))
		var eta: float=float(order.get("eta",order.remaining))
		label("营%d %s · %s" % [int(row.barracks)+1,name,"%.1f秒" % eta if int(row.queue_index)==0 else "等待"],Vector2(46,321+index*44),13,ink)
		var rect:=Rect2(422,300+index*44,110,28)
		box(rect,panel,muted)
		label("取消退%d" % int(order.cost),rect.position+Vector2(6,17),11,amber)
		training_cancel_buttons.append({"rect":rect,"barracks":row.barracks,"queue_index":row.queue_index})
	if rows.is_empty():label("暂无训练订单 · 点击兵种安排生产" if not snapshot.queues.is_empty() else "先自由建兵营 · 每营独立队列",Vector2(46,325),13,muted)
	var production:=rally_state()
	var has_barracks: bool=int(production.barracks_id)>=0
	box(RALLY_SELECTOR_RECT,panel,Color("668a78"))
	label("生产：%s >" % String(production.title),RALLY_SELECTOR_RECT.position+Vector2(10,19),13,ink)
	for rect: Rect2 in [RALLY_SET_RECT,RALLY_RESET_RECT]:box(rect,panel,Color("668a78") if has_barracks and game.phase!="paused" else muted)
	label("设置集结",RALLY_SET_RECT.position+Vector2(34,19),13,amber if has_barracks and game.phase!="paused" else muted)
	label("恢复默认",RALLY_RESET_RECT.position+Vector2(36,19),13,amber if has_barracks and game.phase!="paused" else muted)
	var rally_hint: String=" · 集结%s" % ("已设" if bool(production.configured) else "默认") if has_barracks else ""
	var duration_multiplier: float=float(snapshot.get("training_duration_multiplier",1.0))
	var relay_hint: String=" · 中继时长×%.1f" % duration_multiplier if duration_multiplier < .999 else ""
	label("兵营%d · 训练%d组 · 页%d/%d%s%s" % [snapshot.queues.size(),total_orders,training_page+1,pages,rally_hint,relay_hint],Vector2(46,465),12,muted)
	label(control_group_hint(),Vector2(46,494),13,amber)
	label("Shift+右键攻击推进 · Alt+右键工队护航",Vector2(46,522),14,muted)
	if troop_page==1:
		label("重弩12.8米/46伤/3.2秒 · 医护4.8米/36治疗/2零件",Vector2(46,553),14,ink)
		var eligibility: Dictionary=game.squads.training_eligibility("hauler")
		var medics:=selected_medic_ids()
		var support_hint:="工队右键废料堆指定采运 · 采尽后自动" if bool(eligibility.available) else "采运 · "+String(eligibility.reason)
		if not medics.is_empty():support_hint="医护默认停疗 · 驻定治疗 · 前摇0.65秒 / 间隔4秒"
		CleanHud._paragraph(self,support_hint,Vector2(46,580),496,14,amber,21,1)
		if is_instance_valid(game.logistics):
			var transport: Dictionary=game.logistics.snapshot()
			label("废料%d · 在途%d · 送达%d · 丢失%d" % [int(transport.remaining),int(transport.cargo),int(transport.delivered),int(transport.lost)],Vector2(46,609),13,muted)
			var selected:=selected_hauler_ids()
			var status:="选择工队后可指定资源线"
			for team: Dictionary in transport.teams:
				if selected.has(int(team.id)):
					var route:="指定堆%d" % (int(team.preferred_field)+1) if int(team.preferred_field)>=0 else "自动" if bool(team.automatic) else "手动"
					status="工队%d · %s · %s · 货%d" % [int(team.id)+1,route,String(team.state_title),int(team.cargo)]
					break
			if selected.is_empty() and not medics.is_empty():status="已选医护%d队 · %s" % [medics.size(),"治疗全开" if selected_medics_enabled() else "尚未全部开启"]
			CleanHud._paragraph(self,status,Vector2(46,648),296,13,ink,20,1)
			if haul_button_visible():
				box(HAUL_BUTTON_RECT,panel,Color("668a78") if game.phase in ["day","night"] else muted)
				label("恢复自动采运" if game.phase!="paused" else "暂停 · 自动采运",HAUL_BUTTON_RECT.position+Vector2(12,21),13,amber if game.phase!="paused" else muted)
		if medic_button_visible():
			var medical: Dictionary=game.squads.medic_snapshot()
			CleanHud._paragraph(self,"医护合计%d次 · 恢复%.0f · 花费%d" % [int(medical.treatments),float(medical.healed_hp),int(medical.spent)],Vector2(46,681),296,12,muted,18,1)
			box(MEDIC_BUTTON_RECT,panel,Color("668a78") if game.phase in ["day","night"] else muted)
			var caption:="停止治疗" if selected_medics_enabled() else "开启治疗 · 每次2零件"
			label("暂停 · 医护保持" if game.phase=="paused" else caption,MEDIC_BUTTON_RECT.position+Vector2(9,18),12,muted if game.phase=="paused" else amber)
	elif troop_page==2:
		if not selected_hunter_ids().is_empty():
			label("猎手 · 近战2.3米 / 移速5.4 · 无护甲",Vector2(46,553),14,ink)
			label("未耗尽召潮/织壳、疾行/噬灯/投蚀30伤；其余12",Vector2(46,580),14,amber)
			CleanHud._paragraph(self,"前摇0.22秒 · 间隔1.4秒 · 需活工坊",Vector2(46,609),496,14,muted,21,1)
			CleanHud._paragraph(self,"驻守追击8米 · 指定敌越出落点8米就返回",Vector2(46,648),496,13,ink,20,1)
			CleanHud._paragraph(self,"普通移动/召回不追敌 · Shift右键沿途迎击",Vector2(46,681),496,12,muted,18,1)
		else:
			label("迫击炮 · 射程5.5–16米 · 半径2.2米 / 32伤",Vector2(46,553),14,ink)
			label("前摇1秒 + 飞行0.8秒 · 发射后间隔4.8秒",Vector2(46,580),14,amber)
			CleanHud._paragraph(self,"近敌停火 · 固定落点，仅伤敌 · 开火不另收费",Vector2(46,609),496,14,muted,21,1)
			CleanHud._paragraph(self,"猎手 · 近战2.3米 / 移速5.4 · 专职敌30伤",Vector2(46,648),496,13,ink,20,1)
			var footer:="猎手需活工坊 · 驻守追击8米 · 无护甲 · 喷火队需活军械厂"
			if game.squads.has_method("artillery_snapshot"):
				var barrage: Dictionary=game.squads.artillery_snapshot()
				if int(barrage.get("casting",0))+int(barrage.get("flight",0))>0:
					footer="炮兵准备%d · 在途%d · 命中%d次" % [int(barrage.get("casting",0)),int(barrage.get("flight",0)),int(barrage.get("hits",0))]
			CleanHud._paragraph(self,"喷火队 · 射程2.5–6.5米 / 22伤 · 扇形32° · 最多4目标 · 前摇0.55秒 · %s" % footer,Vector2(46,681),496,12,muted,18,1)
	elif troop_page==3:
		label("投网队 · 需存活研究所 · 100零件 / 9秒",Vector2(46,553),14,ink)
		label("射程2.5–9米 · 10伤 · 前摇0.6秒",Vector2(46,580),14,amber)
		CleanHud._paragraph(self,"网控2秒 · 普通减速45% / 重敌20% · 间隔4秒",Vector2(46,609),496,14,muted,21,1)
		CleanHud._paragraph(self,"配合固定落点炮击与近程喷火 · 不直接打断首领拍击",Vector2(46,648),496,13,ink,20,1)
		CleanHud._paragraph(self,"与牵制塔取最强，分别到期 · 改令取消未命中前摇",Vector2(46,681),496,12,muted,18,1)

func growth_memory_text(snapshot: Dictionary) -> String:
	var memory: Dictionary=snapshot.memory
	if int(memory.pending)>0:
		return "V / 点击领取%d张 · 下张%d零件" % [int(memory.pending),int(memory.cost)]
	if not bool(memory.available):return "当前强化已全部铭刻"
	return "V 铭刻%d零件 · 还差%d" % [int(memory.cost),int(memory.shortfall)]

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
	label(growth_memory_text(snapshot),Vector2(1071,761),14,amber if queued else ink)
	var lines: Array[String]=growth_lines(snapshot)
	var affordable: bool=not snapshot.tower.is_empty() and bool(snapshot.tower.affordable)
	label(lines[0],Vector2(1071,786),13,Color("a6decb"))
	label(lines[1],Vector2(1071,807),12,amber if affordable else muted)
	label(lines[2],Vector2(1071,828),11,muted)

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
	label("%d/5 · +55零件" % collected,Vector2(151,277),12,amber)
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
	if game.opening_night_pending:
		label("守望编号 %d" % game.run.seed_value,Vector2(890,202),12,muted)
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
		label("永久蓝图 · 只解锁付费建筑许可，不免费赠送",Vector2(205,353),13,Color("a3c7b7"))
		var blueprint_options: Array[Dictionary] = game.available_blueprints() if game.has_method("available_blueprints") else [{"id":"","title":"无蓝图","detail":"基础开局"}]
		for i in blueprint_options.size():
			var blueprint: Dictionary = blueprint_options[i]
			var blueprint_rect:=Rect2(198+i*349,362,315,36)
			blueprint_rects.append(blueprint_rect)
			var blueprint_selected: bool=String(blueprint.get("id", ""))==String(game.selected_blueprint)
			box(blueprint_rect,Color(.105,.105,.078,.98) if blueprint_selected else Color(.039,.061,.067,.97),Color("b08a57") if blueprint_selected else Color("49605b"))
			label(String(blueprint.get("title","无蓝图")),blueprint_rect.position+Vector2(14,23),14,amber if blueprint_selected else ink)
			label(String(blueprint.get("detail","")),blueprint_rect.position+Vector2(120,23),11,muted)
	for i in range(game.run.offer.size()):
		var card: Dictionary=game.run.offer[i]
		var rect:=Rect2(198+i*349,410,315,275)
		card_rects.append(rect)
		var color: Color=RunBuild.COLORS[card.school]
		box(rect,Color(.046,.066,.075,.97),color.darkened(.36))
		label("%d" % (i+1),rect.position+Vector2(22,40),24,color,true)
		label(RunBuild.SCHOOLS[card.school]+" · "+RunBuild.RARITIES[card.rarity],rect.position+Vector2(58,39),14,color)
		label(card.name,rect.position+Vector2(23,105),23,ink)
		var lines:=String(card.desc).split("\n")
		for j in range(lines.size()):label(lines[j],rect.position+Vector2(23,150+j*25),15,muted)
		label("按 %d / 点击 铭刻" % (i+1),rect.position+Vector2(22,252),16,amber)
	label("世界已暂停 · 开局/黎明赠卡，V 消耗零件铭刻 · F 重抽 %d 次" % game.run.rerolls,Vector2(205,722),14,muted)

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
	label("守望编号 %d" % game.run.seed_value,Vector2(425,634),12,muted)
	var archive_text := "档案 · 已解锁0项"
	if is_instance_valid(game.archive):
		var archive_profile: Dictionary = game.archive.snapshot()
		var unlocked_blueprints: Variant = archive_profile.get("unlocked_blueprints", [])
		var unlocked_count: int = unlocked_blueprints.size() if unlocked_blueprints is Array else 0
		archive_text = "档案 · 已解锁%d项" % unlocked_count
		var new_unlocks: Array = game.archive_result.get("unlocked", [])
		if not new_unlocks.is_empty():
			var catalog: Dictionary = game.archive.blueprint_catalog()
			var titles: Array[String] = []
			for blueprint_id: Variant in new_unlocks:
				var item: Dictionary = catalog.get(String(blueprint_id), {})
				if not item.is_empty():titles.append(String(item.get("title", blueprint_id)))
			if not titles.is_empty():archive_text = "新解锁 · " + "、".join(titles)
	label(archive_text,Vector2(715,634),12,Color("a3c7b7") if "新解锁" in archive_text else muted)
	box(RESULT_RETRY_RECT,Color(.080,.112,.103,.97),Color("82bbae"))
	box(RESULT_NEW_RECT,Color(.046,.066,.075,.97),Color("66766c"))
	label("Enter · 同一守望再挑战",RESULT_RETRY_RECT.position+Vector2(37,32),16,Color("bce2d3"))
	label("R · 全新守望",RESULT_NEW_RECT.position+Vector2(78,32),16,ink)
	if game.restart_pending:
		label("正在准备下一场守望…",Vector2(630,723),12,amber)

func _gui_input(event: InputEvent) -> void:
	if not is_instance_valid(game):return
	var point:=Vector2.ZERO
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		point=event.position*Vector2(1440,900)/get_viewport_rect().size
	if game.music_credits_open:
		if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
			var sources:=["https://rustedstudio.itch.io/free-music-dark-ambient-piano","https://rustedstudio.itch.io/free-music-apocalypse-z","https://rustedstudio.itch.io/free-music-orchestral-fantasy-war","https://creativecommons.org/licenses/by/4.0/"]
			for index in sources.size():
				if Rect2(300+index*210,527,190,44).has_point(point):OS.shell_open(sources[index]);break
		if event is InputEventMouseButton:accept_event()
		return
	if game.phase=="ended":
		if event is InputEventMouseButton:
			if event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
				if RESULT_RETRY_RECT.has_point(point):game.request_run_restart(true)
				elif RESULT_NEW_RECT.has_point(point):game.request_run_restart(false)
			accept_event()
		return
	if game.phase=="draft":
		if event is InputEventMouseButton:
			if event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
				for index in blueprint_rects.size():
					if blueprint_rects[index].has_point(point):
						var options: Array[Dictionary] = game.available_blueprints() if game.has_method("available_blueprints") else []
						if index<options.size():game.select_blueprint(String(options[index].get("id", "")))
						accept_event();return
				for index in mode_rects.size():
					if mode_rects[index].has_point(point):game.select_run_mode(index);accept_event();return
				for index in card_rects.size():
					if card_rects[index].has_point(point):game.choose_card(index);accept_event();return
			accept_event()
		return
	if game.phase not in ["day","night","paused"]:return
	if event is InputEventMouseButton:
		if event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
			if rally_setting() and RALLY_CANCEL_RECT.has_point(point):
				game.rally.cancel_setting();queue_redraw();accept_event();return
			if TACTICS_BUTTON_RECT.has_point(point):toggle_details();accept_event();return
			if MAP_BUTTON_RECT.has_point(point) or minimap_rect().has_point(point):toggle_map();accept_event();return
			if BUILD_BUTTON_RECT.has_point(point):
				if game.phase in ["day","night"]:game.toggle_tower_construction()
				accept_event();return
			if not detail_tab.is_empty() and not game.construction.active:
				if DETAIL_CLOSE_RECT.has_point(point):dismiss_details();accept_event();return
				for index in CleanHud.TAB_IDS.size():
					if details_tab_rect(index).has_point(point):toggle_details(CleanHud.TAB_IDS[index]);accept_event();return
				if detail_tab=="help" and HELP_TOGGLE_RECT.has_point(point):
					help_details_open=not help_details_open;queue_redraw();accept_event();return
				if detail_tab=="exploration":
					if SALVAGE_NAV_RECT.has_point(point):
						salvage_draw_open=not salvage_draw_open;queue_redraw();accept_event();return
					if salvage_draw_open and SALVAGE_DRAW_RECT.has_point(point):
						game.draw_salvage_supply(String(game.salvage_draw_snapshot().get("selected_mode","safe")));queue_redraw();accept_event();return
					if salvage_draw_open and SALVAGE_SAFE_MODE_RECT.has_point(point):
						game.select_salvage_draw_mode("safe");queue_redraw();accept_event();return
					if salvage_draw_open and SALVAGE_JACKPOT_MODE_RECT.has_point(point):
						game.select_salvage_draw_mode("jackpot");queue_redraw();accept_event();return
				if detail_tab=="contract" and game.phase=="day" and game.contracts.status=="bonus_offer":
					if BONUS_RETURN_RECT.has_point(point):game.choose_bonus_route(0);accept_event();return
					if BONUS_CONFIRM_RECT.has_point(point):game.choose_bonus_route(1);accept_event();return
					for slot in mini(3,bonus_route_budgets.size()):
						if bonus_route_rect(slot).has_point(point):
							var route: Dictionary=bonus_route_budgets[slot]
							game.select_bonus_route(int(route.index),int(route.serial),route);accept_event();return
				if detail_tab=="army":
					if RALLY_SELECTOR_RECT.has_point(point) and game.rally:
						game.rally.cycle_selection(1);queue_redraw();accept_event();return
					for direction in [-1,1]:
						if troop_page_rect(direction).has_point(point):change_troop_page(direction);accept_event();return
						if training_page_rect(direction).has_point(point):training_page=maxi(0,training_page+direction);queue_redraw();accept_event();return
			if game.phase in ["day","night"]:
				if MEMORY_BUTTON_RECT.has_point(point):
					if not rally_setting():game.request_upgrade()
					accept_event();return
				if game.construction.active:
					if REPAIR_BUTTON_RECT.has_point(point):game.construction.toggle_repair();accept_event();return
					if DEMOLITION_BUTTON_RECT.has_point(point):game.construction.toggle_sell();accept_event();return
					for direction in [-1,1]:
						if construction_page_rect(direction).has_point(point):change_construction_page(direction);accept_event();return
					for index in visible_construction_kinds().size():
						if construction_kind_rect(index).has_point(point):select_construction_slot(index);accept_event();return
				elif detail_tab=="army":
					if RALLY_SET_RECT.has_point(point):begin_rally_setting();accept_event();return
					if RALLY_RESET_RECT.has_point(point) and game.rally:
						var result: Dictionary=game.rally.reset_selected()
						game.notify(String(result.reason),3);queue_redraw();accept_event();return
					if medic_button_visible() and MEDIC_BUTTON_RECT.has_point(point):toggle_selected_medics();accept_event();return
					if haul_button_visible() and HAUL_BUTTON_RECT.has_point(point):
						var result: Dictionary=game.logistics.start_selected_hauling()
						game.notify(String(result.reason),3)
						queue_redraw();accept_event();return
					var kinds:=visible_training_kinds()
					for index in kinds.size():
						if training_kind_rect(index).has_point(point):game.train_troop(kinds[index]);accept_event();return
					for button: Dictionary in training_cancel_buttons:
						if (button.rect as Rect2).has_point(point):game.cancel_troop_training(int(button.barracks),int(button.queue_index));training_cancel_buttons.clear();queue_redraw();accept_event();return
				elif detail_tab=="defense" and game.phase=="day":
					if wave_wager_visible():
						var wager_targets: Array=game.wave_wager_target_options()
						for index in wager_targets.size():
							if wave_wager_target_rect(index).has_point(point):
								game.select_wave_wager_target(index);queue_redraw();accept_event();return
						for index in game.wave_wager.risk_options().size():
							if wave_wager_risk_rect(index).has_point(point):
								game.place_wave_wager(index);queue_redraw();accept_event();return
					var bounty_state: Dictionary=game.bounty_snapshot()
					if String(bounty_state.state) in ["offered","selected"] and game.day_number==2 and bounty_rect().has_point(point):
						if not game.select_bounty():game.notify(String(bounty_state.reason),2)
						accept_event();return
					for index in game.countermeasure_count():
						if countermeasure_rect(index).has_point(point):game.select_countermeasure(index);accept_event();return
		for rect in live_panel_rects():
			if rect.has_point(point):
				game.selection_dragging=false
				accept_event()
				return
		if game.phase=="paused":accept_event();return
	if game.handle_strategy_mouse(event):accept_event()
