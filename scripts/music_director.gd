class_name NightMusicDirector
extends Node
## Local, licensed music: no streaming or network access during gameplay.

const TRACK_PATHS := {
	"day": "res://assets/audio/music/day_exploration.ogg",
	"night": "res://assets/audio/music/night_watch.ogg",
	"combat": "res://assets/audio/music/siege_combat.ogg",
}
const CROSSFADE_SECONDS := 2.4
const COMBAT_HOLD := 6.0
const SETTINGS_PATH := "user://audio_settings.cfg"
var persist_settings := true
var muted := false
var user_volume := .65
var active_track := ""
var streams: Dictionary = {}
var missing_tracks: Array[String] = []
var players: Array[AudioStreamPlayer] = []
var track_keys: Array[String] = ["", ""]
var gains: Array[float] = [0.0, 0.0]
var target_player := -1
var combat_hold := 0.0
var last_world_phase := ""
var context_gain := .0
var duck_timer := 0.0
var paused := false
var bus_name := ""

func _ready() -> void:
	if persist_settings:
		var settings:=ConfigFile.new()
		if settings.load(SETTINGS_PATH)==OK:
			user_volume=clampf(float(settings.get_value("music","volume",.65)),0.0,1.0)
			muted=bool(settings.get_value("music","muted",false))
	bus_name="NightMusic_%d" % get_instance_id()
	AudioServer.add_bus()
	AudioServer.set_bus_name(AudioServer.bus_count-1,bus_name)
	AudioServer.set_bus_send(AudioServer.get_bus_index(bus_name),"Master")
	for key in TRACK_PATHS:
		if ResourceLoader.exists(TRACK_PATHS[key]):
			var stream:=load(TRACK_PATHS[key]) as AudioStreamOggVorbis
			if stream:
				stream.loop=true
				streams[key]=stream
		if not streams.has(key):missing_tracks.append(key)
	for i in 2:
		var player:=AudioStreamPlayer.new()
		player.name="MusicA" if i==0 else "MusicB"
		player.bus=bus_name;player.volume_db=-80.0
		add_child(player);players.append(player)
	apply_bus_settings()

func get_volume() -> float:
	return user_volume

func set_volume(value: float) -> void:
	user_volume=clampf(value,0.0,1.0)
	apply_bus_settings();save_settings()

func set_muted(value: bool) -> void:
	muted=value
	apply_bus_settings();save_settings()

func toggle_mute() -> void:
	set_muted(not muted)

func save_settings() -> void:
	if not persist_settings:return
	var settings:=ConfigFile.new()
	settings.set_value("music","volume",user_volume)
	settings.set_value("music","muted",muted)
	settings.save(SETTINGS_PATH)

func apply_bus_settings() -> void:
	var index:=AudioServer.get_bus_index(bus_name)
	if index<0:return
	# Prepared tracks are -18 LUFS; normal play is about -30 LUFS.
	AudioServer.set_bus_volume_db(index,-8.0+linear_to_db(maxf(user_volume,.0001)))
	AudioServer.set_bus_mute(index,muted or user_volume<=0.0)

func duck(duration: float=.65) -> void:
	duck_timer=maxf(duck_timer,duration)

func select_track(key: String) -> void:
	if key==active_track:return
	if not streams.has(key):return
	var index:=track_keys.find(key)
	if index<0:
		index=0 if gains[0]<=gains[1] else 1
		players[index].stop();gains[index]=0.0
		players[index].stream=streams[key]
		players[index].volume_db=-80.0
		players[index].play()
		track_keys[index]=key
	active_track=key;target_player=index

func update_game(game: Node, delta: float) -> void:
	if players.size()!=2:return
	var phase: String=game.phase
	paused=phase=="paused"
	for player in players:player.stream_paused=paused
	if paused:return
	var desired:=active_track
	var level:=1.0
	if phase=="ended":
		target_player=-1;level=0.0
	elif phase=="draft":
		level=.42
		if desired=="":desired="night" if game.return_phase=="night" else "day"
	elif phase=="day" or phase=="night":
		if last_world_phase!=phase:
			combat_hold=0.0;last_world_phase=phase
		var threatened:=false
		if phase=="night":threatened=game.gate_pressure()>0 or game.wave_warning_issued
		for enemy in game.enemies:
			if is_instance_valid(enemy) and enemy.alive and enemy.position.distance_to(game.hero.position)<9.5:
				threatened=true;break
		combat_hold=COMBAT_HOLD if threatened else maxf(0.0,combat_hold-delta)
		desired="combat" if combat_hold>0 else phase
	if phase!="ended" and desired!="":select_track(desired)
	duck_timer=maxf(0.0,duck_timer-delta)
	if duck_timer>0:level*=.58
	context_gain=move_toward(context_gain,level,delta*1.6)
	for i in players.size():
		gains[i]=move_toward(gains[i],1.0 if i==target_player else 0.0,delta/CROSSFADE_SECONDS)
		# Square roots produce equal-power overlap instead of a hollow dip.
		players[i].volume_db=linear_to_db(maxf(.0001,sqrt(gains[i])*context_gain))
		if gains[i]==0.0 and i!=target_player and players[i].playing:
			players[i].stop();track_keys[i]=""

func _exit_tree() -> void:
	for player in players:
		player.stop()
		player.stream=null
	players.clear()
	streams.clear()
	var index:=AudioServer.get_bus_index(bus_name)
	if index>=0:AudioServer.remove_bus(index)
