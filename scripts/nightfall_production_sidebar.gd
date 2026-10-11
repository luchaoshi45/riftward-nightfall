extends RefCounted
## A compact RTS production rail over the original paid barracks queues.
const Catalog = preload("res://scripts/outpost_catalog.gd")
const PANEL := Rect2(1160,158,256,594)
const PAGE_SIZE := 5
var page := 0
var queue_page := 0

func visible(ui: Control) -> bool:
	return ui.minimal_display and is_instance_valid(ui.game) and ui.game.phase in ["day","night"] \
		and not ui.game.music_credits_open and ui.detail_tab.is_empty() and not ui.map_expanded \
		and not ui.rally_setting()

func kinds() -> Array[String]:
	var result: Array[String]=[]
	for index in range(page*PAGE_SIZE,mini(Catalog.TROOP_IDS.size(),(page+1)*PAGE_SIZE)):
		result.append(Catalog.TROOP_IDS[index])
	return result

func kind_rect(index: int) -> Rect2:
	return Rect2(1172,258+index*62,232,56)

func page_rect(direction: int) -> Rect2:
	return Rect2(1172 if direction<0 else 1360,218,44,30)

func producer_rect() -> Rect2:
	return Rect2(1172,184,232,30)

func queue_rows(ui: Control) -> Array[Dictionary]:
	var rows: Array[Dictionary]=[]
	var snapshot: Dictionary=ui.game.squads.snapshot()
	# Current work from each base appears before waiting orders.
	for base: Dictionary in snapshot.queues:
		if not base.queue.is_empty():rows.append({"base":int(base.index),"index":0,"order":base.queue[0]})
	for base: Dictionary in snapshot.queues:
		for index in range(1,base.queue.size()):rows.append({"base":int(base.index),"index":index,"order":base.queue[index]})
	return rows

func queue_cancel_rect(slot: int) -> Rect2:
	return Rect2(1360,624+slot*48,44,28)

func queue_page_rect(direction: int) -> Rect2:
	return Rect2(1310 if direction<0 else 1360,586,44,26)

func handle(ui: Control, event: InputEvent, point: Vector2) -> bool:
	if not visible(ui) or not PANEL.has_point(point):return false
	if event is InputEventMouseButton:
		ui.game.selection_dragging=false
		ui.game.vehicle_drag_source=null
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		for direction in [-1,1]:
			if page_rect(direction).has_point(point):
				page=clampi(page+direction,0,ceili(Catalog.TROOP_IDS.size()/float(PAGE_SIZE))-1)
				ui.queue_redraw();return true
			if queue_page_rect(direction).has_point(point):
				var count:=queue_rows(ui).size()
				queue_page=clampi(queue_page+direction,0,maxi(0,ceili(count/2.0)-1))
				ui.queue_redraw();return true
		if producer_rect().has_point(point):
			ui.game.rally.cycle_selection(1);ui.queue_redraw();return true
		var available:=kinds()
		for index in available.size():
			if kind_rect(index).has_point(point):
				ui.game.train_troop(available[index]);ui.queue_redraw();return true
		var rows:=queue_rows(ui)
		queue_page=clampi(queue_page,0,maxi(0,ceili(rows.size()/2.0)-1))
		for slot in 2:
			var index:=queue_page*2+slot
			if index<rows.size() and queue_cancel_rect(slot).has_point(point):
				ui.game.cancel_troop_training(int(rows[index].base),int(rows[index].index))
				ui.queue_redraw();return true
	# Every mouse button, release, wheel and motion over the rail belongs to UI.
	return true

func draw(ui: Control) -> void:
	if not visible(ui):return
	ui.box(PANEL,Color("101b22",.94),Color("536963"))
	ui.draw_rect(Rect2(PANEL.position,Vector2(4,PANEL.size.y)),Color("b48c55"))
	ui.label("部队生产",Vector2(1180,180),20,ui.ink)
	var producer: Dictionary=ui.rally_state()
	ui.label("%s  ›" % String(producer.title),Vector2(1180,205),16,ui.amber)
	for direction in [-1,1]:
		ui.box(page_rect(direction),Color("21312f"),Color("506963"))
		ui.label("‹" if direction<0 else "›",page_rect(direction).position+Vector2(14,22),21,ui.ink)
	ui.label("兵种 %d / %d" % [page+1,ceili(Catalog.TROOP_IDS.size()/float(PAGE_SIZE))],Vector2(1232,239),16,ui.muted)
	var available:=kinds()
	var has_base: bool=not ui.game.squads.snapshot().queues.is_empty()
	var badges: Dictionary={"shield":"盾","ranged":"弩","engineer":"工","ballista":"重","hauler":"运","medic":"医","artillery":"炮","hunter":"猎","flamer":"焰","netter":"网"}
	for index in available.size():
		var kind:=available[index]
		var troop: Dictionary=Catalog.troop(kind)
		var eligible: Dictionary=ui.game.squads.training_eligibility(kind)
		var reason: String=String(eligible.reason) if not bool(eligible.available) else ""
		if reason.is_empty() and not has_base:reason="需要国旗基地"
		if reason.is_empty() and ui.game.scrap<int(troop.cost):reason="光不足"
		var active:=reason.is_empty()
		var rect:=kind_rect(index)
		ui.box(rect,Color("233b37") if active else Color("172128"),Color("698578") if active else Color("3e4e54"))
		ui.box(Rect2(rect.position+Vector2(7,8),Vector2(34,38)),Color("101b22"),ui.amber if active else ui.muted)
		ui.label(badges[kind],rect.position+Vector2(14,34),22,ui.amber if active else ui.muted)
		ui.label(String(troop.title),rect.position+Vector2(49,23),19,ui.ink if active else ui.muted)
		ui.label("%d光" % int(troop.cost),rect.position+Vector2(177,23),15,ui.amber if active else ui.muted)
		var subtitle: String="%.0f秒 · 点击训练" % float(troop.time) if active else reason
		ui.label(subtitle,rect.position+Vector2(49,46),14,ui.amber if active else ui.muted)
	var rows:=queue_rows(ui)
	queue_page=clampi(queue_page,0,maxi(0,ceili(rows.size()/2.0)-1))
	ui.label("训练队列 · %d" % rows.size(),Vector2(1178,606),17,ui.ink)
	for direction in [-1,1]:
		ui.box(queue_page_rect(direction),Color("21312f"),Color("506963"))
		ui.label("‹" if direction<0 else "›",queue_page_rect(direction).position+Vector2(14,20),19,ui.muted)
	if rows.is_empty():
		ui.label("点击兵种安排生产" if has_base else "展开国旗后即可出兵",Vector2(1178,644),16,ui.muted)
	else:
		for slot in 2:
			var index:=queue_page*2+slot
			if index>=rows.size():break
			var row: Dictionary=rows[index]
			var order: Dictionary=row.order
			var y: float=640+slot*48
			ui.label("%s · %s" % [String(order.title),"%.0f秒" % ceilf(float(order.eta)) if int(row.index)==0 else "等待"],Vector2(1178,y),15,ui.ink)
			ui.progress(Rect2(1178,y+8,170,4),1.0-float(order.remaining)/maxf(.01,float(order.total)) if int(row.index)==0 else 0.0,ui.amber)
			ui.box(queue_cancel_rect(slot),Color("21312f"),Color("506963"))
			ui.label("取消",queue_cancel_rect(slot).position+Vector2(7,20),14,ui.muted)
	ui.label("完成训练后自动出兵",Vector2(1178,735),14,ui.muted)
