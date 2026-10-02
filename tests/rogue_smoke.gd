extends Node
var failures: int=0

func check(value: bool, label: String) -> void:
	if value: print("PASS: ",label)
	else:
		failures+=1
		push_error("FAIL: "+label)

func settle(game: Node3D) -> void:
	await get_tree().process_frame
	while game.mode=="draft": game.select_card(0)

func run(game: Node3D) -> void:
	game.auto_test=true
	game.start_match()
	check(game.mode=="draft" and game.run.offer.size()==3,"Opening draft offers three unique cards")
	var offer_ids: Array=[]
	for card in game.run.offer: offer_ids.append(card.id)
	check(offer_ids[0]!=offer_ids[1] and offer_ids[1]!=offer_ids[2] and offer_ids[0]!=offer_ids[2],"Offer contains no duplicates")
	var elapsed: float=game.elapsed
	game.simulate(2)
	check(game.elapsed==elapsed,"Draft pauses entire simulation")
	check(game.run.redraw() and game.run.rerolls==2,"Reroll consumes a charge")
	game.select_card(0)
	check(game.run.selections==1 and game.mode=="playing","Card choice applies and resumes")
	check(not game.select_card(0),"Choice cannot be claimed twice")
	game.experience=65
	game.check_level()
	await settle(game)
	check(game.level==2 and game.run.selections==2,"Level grants one card")
	game.add_essence(210)
	await settle(game)
	check(game.run.selections==4 and game.essence==10,"Multiple essence rewards preserved in queue")
	game.run.grant("test")
	game.open_draft()
	var legendary:=false
	for card in game.run.offer:
		if card.rarity==2: legendary=true
	check(legendary,"Every fifth choice guarantees a legendary offer")
	game.select_card(0)
	# Recompute avoids multiplicative drift from repeated application.
	game.run.owned={"edge":3,"tempo":3,"critical":3,"armor":3,"vitality":3,"arcana":3,"haste":3,"split":1,"echo":1,"chain":1,"thorns":1,"drain":2}
	game.run.recalculate()
	game.apply_build()
	var damage: float=game.player.damage
	game.apply_build()
	check(game.player.damage==damage and damage>100,"Stat recomputation is idempotent")
	check(game.run.stats.crit<=.75 and game.run.stats.haste<=120,"Attribute caps respected")
	game.level=4
	game.apply_build()
	game.player.position=Vector3.ZERO
	game.player.destination=Vector3.ZERO
	game.enemy.position=Vector3(4,0,0)
	game.enemy.max_hp=5000; game.enemy.hp=5000
	game.aim=game.enemy.position
	game.mana=game.max_mana
	check(game.cast(0) and game.projectiles.size()==3,"Legendary Q emits three projectiles")
	var enemy_hp: float=game.enemy.hp
	for i in range(30): game.update_projectiles(1.0/60)
	check(game.enemy.hp<enemy_hp,"Split Q damages target")
	check(game.cast(3) and game.warnings.size()==2,"Legendary R schedules echo")
	game.update_warnings(2)
	game.player.hp=400
	game.player.attack_timer=0
	game.attack_count=2
	var neighbor: BattleUnit=game.spawn_unit("minion",1,Vector3(5,0,1))
	var neighbor_hp: float=neighbor.hp
	game.attack(game.player,game.enemy)
	check(game.player.hp>400,"Lifesteal restores actual non-building damage")
	check(neighbor.hp<neighbor_hp,"Third attack chains to nearby enemy")
	var old_hp: float=game.player.hp
	game.player.shield=0
	game.player.hurt(100,game.enemy)
	check(old_hp-game.player.hp<100,"Armor reduces incoming damage")
	# Maxed cards are never drawn, including once the entire finite pool is exhausted.
	var full := RunBuild.new(1234)
	for card in RunBuild.CARDS: full.owned[card.id]=card.cap
	full.grant("full")
	check(not full.draft() and full.pending==0,"Exhausted pool closes safely")
	var a := RunBuild.new(333)
	var b := RunBuild.new(333)
	a.grant("seed");b.grant("seed");a.draft();b.draft()
	check(a.offer==b.offer,"Same seed yields reproducible choices")
	# Real wave combat, free of player deaths, while exercising queued cards.
	game.player.revive(BattleMap.home(0)+Vector3(0,0,2))
	game.next_evolution=game.elapsed+2
	game.wave_timer=1
	for i in range(3600):
		game.simulate(1.0/30)
		if i%30==0: await settle(game)
	check(game.evolution>=1 and game.run.selections>5,"Timed evolution rewards a draft")
	check(game.wave_number>=7 and game.units.size()<180,"Two-minute lane simulation remains bounded")
	for i in range(4):
		game.mode="playing"
		game.player.hurt(999999,game.enemy)
		if i<3: game.update_respawns(30)
	check(game.mode=="ended" and game.winner==1 and game.resurrection_left==0,"Fourth death ends run")
	print("RIFTWARD_ROGUE_OK" if failures==0 else "RIFTWARD_ROGUE_FAILED: %d" % failures)
	await get_tree().process_frame
	get_tree().quit(failures)
