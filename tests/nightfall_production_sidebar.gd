extends SceneTree
const Catalog = preload("res://scripts/outpost_catalog.gd")
var game: Node3D
var checks := 0
var failures: Array[String]=[]

func _initialize() -> void:
	if DisplayServer.get_name()!="headless":DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	call_deferred("run")

func check(value: bool, text_value: String) -> void:
	checks+=1
	if not value:failures.append(text_value);push_error(text_value)

func click(rect: Rect2, button: int=MOUSE_BUTTON_LEFT) -> void:
	var pixel: Vector2=rect.get_center()*game.hud.get_viewport_rect().size/Vector2(1440,900)
	var motion:=InputEventMouseMotion.new()
	motion.position=pixel;motion.global_position=pixel
	root.push_input(motion,true)
	await process_frame
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.position=pixel;event.global_position=pixel
		event.button_index=button;event.pressed=pressed
		event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed and button==MOUSE_BUTTON_LEFT else 0
		root.push_input(event,true)
		await process_frame

func legal(kind: String) -> Vector3:
	for z in range(-18,19):
		for x in range(-18,19):
			var valid: Dictionary=game.construction.validity(Vector3(x,5,z),-1,kind)
			if valid.valid:return valid.point
	return Vector3.INF

func capture(tag: String) -> void:
	if DisplayServer.get_name()=="headless":return
	game.hud.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/production-sidebar/"+tag+".png")

func run() -> void:
	game=load("res://scenes/nightfall.tscn").instantiate()
	game.archive.enabled=false
	root.add_child(game);current_scene=game
	await process_frame
	game.set_process(false)
	check(game.camera.size==45,"Default view must be wider than the old 38")
	while game.phase=="draft":game.choose_card(0)
	game.phase="day"
	var sidebar=game.hud.production_sidebar
	check(sidebar.visible(game.hud),"Default battlefield exposes production")
	check(game.hud.visible_hud_rects().has(sidebar.PANEL),"Drawn rail participates in world-input shielding")
	var wallet: int=game.scrap
	var goal: Vector3=game.move_goal
	await click(sidebar.kind_rect(0))
	check(game.scrap==wallet and sidebar.queue_rows(game.hud).is_empty(),"No base means no payment or free unit")
	check(game.move_goal==goal and not game.selection_dragging,"Actual rail click cannot issue hero orders")
	game.scrap=1000
	check(game.build_structure_at(legal("barracks"),"barracks"),"Fixture pays for a real legal flag base")
	game.scrap=0
	await click(sidebar.kind_rect(0))
	check(sidebar.queue_rows(game.hud).is_empty() and game.scrap==0,"Insufficient light cannot create a queue")
	game.scrap=500
	wallet=game.scrap
	await click(sidebar.kind_rect(3))
	check(game.scrap==wallet and sidebar.queue_rows(game.hud).is_empty(),"Locked research troop cannot bypass live tech")
	var count: int=game.squads.squads.size()
	await click(sidebar.kind_rect(0))
	var rows: Array=sidebar.queue_rows(game.hud)
	check(rows.size()==1 and game.scrap==wallet-int(Catalog.troop("shield").cost),"Actual shield button pays exact catalog cost")
	check(game.squads.squads.size()==count,"Training click does not spawn a free squad")
	check(rows.size()==1 and float(rows[0].order.remaining)==float(Catalog.troop("shield").time),"Queue keeps real training duration")
	var paid: int=game.scrap
	game.selection_dragging=true
	await click(sidebar.kind_rect(0),MOUSE_BUTTON_RIGHT)
	await click(sidebar.kind_rect(0),MOUSE_BUTTON_WHEEL_DOWN)
	check(game.scrap==paid and sidebar.queue_rows(game.hud).size()==1 and game.move_goal==goal and not game.selection_dragging,"Right-click and wheel neither purchase nor move")
	game.phase="paused"
	check(not sidebar.visible(game.hud),"Pause hides the rail under settings")
	game.squads.advance(10)
	check(game.squads.squads.size()==count,"Pause cannot complete training")
	game.phase="day"
	game.squads.advance(5.9)
	check(game.squads.squads.size()==count,"No premature squad before six seconds")
	game.squads.advance(.2)
	check(game.squads.squads.size()==count+1 and sidebar.queue_rows(game.hud).is_empty(),"Paid queue delivers real squad after training")
	await click(sidebar.kind_rect(0))
	await click(sidebar.kind_rect(2))
	check(sidebar.queue_rows(game.hud).size()==2,"Two buttons create two real orders")
	paid=game.scrap
	await click(sidebar.queue_cancel_rect(1))
	check(sidebar.queue_rows(game.hud).size()==1 and game.scrap==paid+int(Catalog.troop("engineer").cost),"Cancel refunds exactly the chosen order")
	await click(sidebar.page_rect(1))
	check(sidebar.kinds().size()==5 and sidebar.kinds()[0]=="medic" and sidebar.kinds()[4]=="netter","Second page contains all remaining catalog troops")
	await click(sidebar.page_rect(1))
	check(sidebar.page==1,"Paging is bounded")
	await click(sidebar.page_rect(-1))
	await click(sidebar.producer_rect())
	check(game.rally.selection_id()>=0,"Sidebar cycles to a real production base")
	paid=game.scrap
	await click(sidebar.rally_rect())
	check(game.rally.active and not sidebar.visible(game.hud),"Actual set-rally button enters existing world selection")
	var committed:=false
	for z in range(-12,13,3):
		for x in range(-12,13,3):
			if bool(game.rally.commit(Vector3(x,5,z)).ok):
				committed=true;break
		if committed:break
	check(committed and bool(game.rally.snapshot().configured),"Rally accepts a reachable real destination")
	var destination: Vector3=game.rally.snapshot().point
	game.rally.tick(0)
	check(is_instance_valid(game.rally._marker) and game.rally._marker.visible,"Production rail shows the selected base destination")
	await click(sidebar.rally_rect())
	check(game.rally.active,"Configured base can re-enter selection")
	check(not bool(game.rally.commit(Vector3.INF).ok),"Invalid world destination cannot replace rally")
	game.rally.cancel_setting()
	check(game.rally.snapshot().point==destination,"Cancelling re-selection preserves existing destination")
	var old_destination: Vector3=game.squads.squads[0].destination
	var before_training: int=game.squads.squads.size()
	game.squads.advance(6.1)
	check(game.squads.squads.size()==before_training+1 and game.squads.squads[-1].destination==destination,"Paid pending training reads selected base rally when completed")
	check(game.squads.squads[0].destination==old_destination,"Setting rally preserves existing squad orders")
	await click(sidebar.rally_rect(true))
	check(game.squads.squads[-1].destination==destination,"Reset does not redirect already deployed troops")
	check(not bool(game.rally.snapshot().configured) and game.scrap==paid,"Reset uses original binding and does not charge light")
	game.rally.tick(0)
	check(not game.rally._marker.visible,"Default rally hides old destination marker")
	await click(sidebar.producer_rect())
	await click(sidebar.rally_rect())
	check(not game.rally.active and game.scrap==paid,"Automatic producer cannot set or charge a rally destination")
	await click(sidebar.producer_rect())
	for reset in [false,true]:
		check(sidebar.PANEL.encloses(sidebar.rally_rect(reset)),"Rally controls remain within protected sidebar")
	game.hud.toggle_details("army")
	check(not sidebar.visible(game.hud) and not game.hud.visible_hud_rects().has(sidebar.PANEL),"Details hide rail and its input footprint")
	game.hud.dismiss_details();game.hud.toggle_map()
	check(not sidebar.visible(game.hud),"Map hides production overlay")
	game.hud.toggle_map()
	var reward: Node3D=game.supply_crates[0]
	check(not reward.revealed and not reward.caption.text.contains(reward.display_name),"Sealed box still conceals its reward")
	reward.reveal()
	check(reward.caption.transparency==1.0,"Revealed label uses a screen font instead of tiny world text")
	reward.position=Vector3(8,5,2)
	for camera_size in [21,45,52]:
		game.camera.size=camera_size
		var labels: Array=game.hud.supply_reward_labels()
		check(not labels.is_empty(),"Reward title stays readable at zoom %d" % camera_size)
		for row: Dictionary in labels:
			check(not sidebar.PANEL.intersects(row.rect),"Reward caption does not overlap production")
	for size in [Vector2i(1440,900),Vector2i(1920,1080),Vector2i(1920,1200)]:
		root.size=size;root.content_scale_size=size
		game.camera.size=45
		await process_frame
		await capture("default-%dx%d" % [size.x,size.y])
	game.camera.size=45
	sidebar.page=1
	await capture("troops-page-two")
	for phase in ["draft","ended","paused"]:
		game.phase=phase
		check(not sidebar.visible(game.hud),"No production during %s" % phase)
	game.queue_free()
	await process_frame
	await create_timer(.5).timeout
	print("NIGHTFALL_PRODUCTION_SIDEBAR_%s checks=%d failures=%d" % ["OK" if failures.is_empty() else "FAILED",checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
