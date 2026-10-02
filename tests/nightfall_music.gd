extends SceneTree

class MusicGame extends Node:
	var phase:="draft"
	var return_phase:="night"
	var hero:=Node3D.new()
	var enemies: Array[Node3D]=[]
	var wave_warning_issued:=false
	var pressure:=0
	func gate_pressure() -> int:return pressure

class Threat extends Node3D:
	var alive:=true

func _initialize() -> void:call_deferred("run")

func advance(music: Node, game: Node, seconds: float) -> void:
	for i in roundi(seconds*60):music.update_game(game,1.0/60.0)

func run() -> void:
	var game:=MusicGame.new();root.add_child(game);game.add_child(game.hero)
	var baseline:=AudioServer.bus_count
	var music: Node=load("res://scripts/music_director.gd").new()
	music.persist_settings=false;game.add_child(music)
	assert(music.missing_tracks.is_empty() and music.streams.size()==3,"All three licensed OGG streams must load")
	for stream in music.streams.values():assert(stream.loop and stream.get_length()>180,"Use actual long loops, not a short beep placeholder")
	advance(music,game,3)
	assert(music.active_track=="night" and music.players[music.target_player].playing)
	assert(is_equal_approx(music.context_gain,.42),"Opening card selection must have quiet night ambience")
	game.phase="day";advance(music,game,3)
	assert(music.active_track=="day" and is_equal_approx(music.gains[music.target_player],1))
	assert(not music.players[1-music.target_player].playing,"Completed crossfade must release the old voice")
	var enemy:=Threat.new();game.add_child(enemy);enemy.position=Vector3(8,0,0);game.enemies.append(enemy)
	advance(music,game,1)
	assert(music.active_track=="combat" and music.gains[0]>0 and music.gains[1]>0,"An approaching enemy must crossfade into combat")
	enemy.position=Vector3(30,0,0);advance(music,game,5)
	assert(music.active_track=="combat","Do not flicker to exploration whenever a target exits range")
	advance(music,game,1.2);assert(music.active_track=="day")
	game.phase="night";game.wave_warning_issued=true;advance(music,game,3)
	assert(music.active_track=="combat","South-gate warning must bring in the siege score before the wave")
	music.set_muted(true);game.wave_warning_issued=false;advance(music,game,8)
	assert(music.active_track=="night" and music.muted)
	assert(AudioServer.is_bus_mute(AudioServer.get_bus_index(music.bus_name)),"Track switching must never cancel manual mute")
	music.set_volume(2);assert(music.get_volume()==1 and music.muted)
	music.set_volume(-2);assert(music.get_volume()==0)
	music.set_volume(.65);music.set_muted(false)
	var before: Array=music.gains.duplicate();var before_hold: float=music.combat_hold
	game.phase="paused";advance(music,game,3)
	assert(music.gains==before and music.combat_hold==before_hold)
	for player in music.players:assert(player.stream_paused)
	game.phase="night";advance(music,game,.1)
	for player in music.players:assert(not player.stream_paused)
	music.duck(1);advance(music,game,.3)
	assert(music.context_gain<.65,"Pickup rewards must briefly lower only the music")
	advance(music,game,2);assert(music.context_gain>.99)
	game.phase="ended";advance(music,game,3)
	assert(music.context_gain==0 and not music.players[0].playing and not music.players[1].playing)
	music.free();assert(AudioServer.bus_count==baseline,"Scene teardown must not leave an extra audio bus")
	print("NIGHTFALL_MUSIC_OK three_real_loops quiet_draft adaptive_siege hysteresis crossfade pause mute volume duck teardown")
	game.queue_free()
	await process_frame
	await create_timer(.15).timeout
	quit()
