class_name NightCombatFeedback
extends Node
## Ordinary attacks use short, layered feedback without changing combat simulation.

const MAX_EFFECTS := 14
const MAX_FLOATS := 16
const MAX_VOICES := 6
const SAMPLE_RATE := 32000
const GOLD := Color("ffcd75")
const CYAN := Color("8de7de")

var reduced_effects := false
var floats: Array[Dictionary] = []
var game: Node
var effects: Array[Dictionary] = []
var players: Array[AudioStreamPlayer] = []
var sounds: Dictionary = {}
var trauma := 0.0
var shake_age := 0.0
var voice_cursor := 0
var kill_sound_lock := 0.0
var rng := RandomNumberGenerator.new()

func setup(owner_game: Node) -> void:
	game=owner_game
	rng.seed=471009
	if not players.is_empty():return
	for key in ["swing","heavy_swing","hit","hurt","critical","finisher","kill","milestone"]:
		sounds[key]=make_sound(key)
	for i in MAX_VOICES:
		var player:=AudioStreamPlayer.new()
		player.name="CombatVoice%d" % i
		player.volume_db=-15.0
		add_child(player);players.append(player)

func active() -> bool:
	if not is_instance_valid(game):return false
	var phase: String=game.phase
	return phase=="day" or phase=="night"

func tick(delta: float) -> void:
	if not active():
		clear_transients()
		return
	var elapsed:=maxf(delta,0.0)
	shake_age+=elapsed
	trauma=maxf(0.0,trauma-elapsed*2.8)
	kill_sound_lock=maxf(0.0,kill_sound_lock-elapsed)
	for i in range(floats.size()-1,-1,-1):
		floats[i].time=maxf(0.0,float(floats[i].time)-elapsed)
		if floats[i].time<=0:floats.remove_at(i)
	for i in range(effects.size()-1,-1,-1):
		var effect: Dictionary=effects[i]
		effect.time=float(effect.time)+elapsed
		var duration: float=effect.duration
		if effect.time>=duration or not is_instance_valid(effect.node):
			if is_instance_valid(effect.node):effect.node.queue_free()
			effects.remove_at(i)
			continue
		var age: float=effect.time
		var progress:=clampf(age/duration,0.0,1.0)
		var root:=effect.node as Node3D
		if effect.kind=="slash":
			root.rotation.y=float(effect.yaw)+(progress-.5)*float(effect.turn)
			root.scale=Vector3.ONE*(.82+.18*(1.0-pow(1.0-progress,3.0)))*(.86 if reduced_effects else 1.0)
			var travel:=clampf(age/float(effect.travel_duration),0.0,1.0)
			root.global_position=(effect.start as Vector3).lerp(effect.end,1.0-pow(1.0-travel,2.0))
		for shard: Dictionary in effect.parts:
			var mesh:=shard.node as MeshInstance3D
			mesh.position=shard.origin+shard.velocity*age+Vector3(0,-2.8*age*age,0)
			mesh.rotation+=shard.spin*elapsed
			mesh.scale=Vector3.ONE*maxf(.05,1.0-progress*progress)
		for material: StandardMaterial3D in effect.materials:
			var base: Color=material.get_meta("feedback_color",Color.WHITE)
			var alpha: float=base.a*pow(1.0-progress,1.45)
			if effect.kind=="slash":alpha*=smoothstep(0.0,.09,age)
			material.albedo_color=Color(base.r,base.g,base.b,alpha)
		if effect.has("flash"):
			var flare:=effect.flash as MeshInstance3D
			flare.visible=not reduced_effects
			flare.scale=Vector3.ONE*maxf(.03,1.0-progress*3.5)
		if effect.has("ring"):
			var ring:=effect.ring as MeshInstance3D
			ring.visible=not reduced_effects
			var expansion:=.32+.68*(1.0-pow(1.0-progress,3.0))
			ring.scale=Vector3(expansion,1.0,expansion)
		if effect.has("light"):
			var light:=effect.light as OmniLight3D
			light.light_energy=0.0 if reduced_effects else float(effect.energy)*light_envelope(age)

func light_envelope(age: float) -> float:
	# A rounded onset and longer, quiet tail keep repeated impacts local and
	# avoid a full-bright one-frame pop across the nearby floor.
	var rise:=lerpf(.04,1.0,smoothstep(0.0,.035,age))
	return rise*pow(maxf(0.0,1.0-age/.24),2.0)

func swing(origin: Vector3, direction: Vector3, step: int, contact_delay: float=.14) -> void:
	if not active():return
	var forward:=flat_direction(direction)
	var heavy:=step>=2
	var color:=GOLD if heavy else CYAN
	var mat:=glow_material(Color(color.r,color.g,color.b,.76),1.8 if heavy else 1.2)
	var core:=glow_material(Color(1.0,.96,.82,.85),1.5)
	var root:=Node3D.new()
	root.name="HeavySwordArc" if heavy else "SwordArc"
	add_child(root)
	var yaw:=atan2(forward.x,forward.z)
	root.rotation.y=yaw
	var side: float=-1.0 if step==1 else 1.0
	var radius: float=1.65 if heavy else 1.40
	var width: float=.22 if heavy else .14
	var start:=origin+forward*.25+Vector3(0,1.05,0)
	var endpoint:=origin+direction-forward*minf(radius,Vector2(direction.x,direction.z).length()*.8)+Vector3(0,1.05,0)
	root.global_position=start
	root.add_child(arc_mesh(radius,width,1.3 if heavy else 1.13,mat))
	root.add_child(arc_mesh(radius+.012,.038,1.08 if heavy else .94,core))
	root.rotation.z=.16*side
	if reduced_effects:root.scale=Vector3.ONE*.86
	var travel_duration:=maxf(.03,contact_delay)
	add_effect({"node":root,"kind":"slash","time":0.0,"duration":travel_duration+(.12 if heavy else .08),"travel_duration":travel_duration,"materials":[mat,core],"parts":[],"yaw":yaw,"turn":side*.36,"start":start,"end":endpoint})
	play_sound("heavy_swing" if heavy else "swing",-1.5,1.0+float(step-1)*.025)

func impact(point: Vector3, direction: Vector3, amount: float, critical: bool, finisher: bool) -> void:
	if not active():return
	var strong:=critical or finisher
	var tier: int=2 if finisher else (1 if critical else 0)
	var forward:=flat_direction(direction)
	var root:=Node3D.new()
	root.name="FinisherImpact" if finisher else ("CriticalImpact" if critical else "SwordImpact")
	# Put contact sparks on the facing surface rather than inside the chest,
	# where the opaque creature mesh would hide them at the normal game zoom.
	add_child(root);root.global_position=point-forward*.55+Vector3(0,.95,0)
	var gold:=glow_material(Color(GOLD.r,GOLD.g,GOLD.b,.91),1.5 if strong else 1.1)
	var cyan:=glow_material(Color(CYAN.r,CYAN.g,CYAN.b,.88),1.0)
	var white:=glow_material(Color(1.0,.96,.79,.68),1.15)
	var count: int=(10+4*tier) if not reduced_effects else 5
	var parts:=shards(root,forward,count,[gold,cyan],2.6+.55*float(tier))
	var flare:=MeshInstance3D.new()
	var sphere:=SphereMesh.new()
	sphere.radius=.13 if not strong else .21;sphere.height=sphere.radius*2.0
	sphere.radial_segments=12;sphere.rings=6
	flare.mesh=sphere;flare.material_override=white;root.add_child(flare)
	flare.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flare.visible=not reduced_effects
	var light:=OmniLight3D.new()
	light.name="MeleeImpactLight";light.light_color=GOLD
	light.omni_range=3.0 if strong else 2.0
	light.shadow_enabled=false
	var energy: float=.55+float(tier)*.30
	light.light_energy=0.0 if reduced_effects else energy*light_envelope(0.0)
	root.add_child(light)
	add_effect({"node":root,"kind":"impact","time":0.0,"duration":.39 if strong else .30,"materials":[gold,cyan,white],"parts":parts,"flash":flare,"light":light,"energy":energy})
	var label: String=str(maxi(0,roundi(amount)))
	if critical:label="暴击 "+label
	elif finisher:label="重击 "+label
	add_float(point+Vector3(0,1.7,0),label,GOLD if strong else Color("eee5ce"),.80 if strong else .63,1.18 if strong else .98)
	trauma=clampf(trauma+(.31 if finisher else (.25 if critical else .12)),0.0,.50)
	play_sound("finisher" if finisher else ("critical" if critical else "hit"),0.0,rng.randf_range(.965,1.035))
	duck_music(.22 if not strong else .36)

func damage_confirmed(point: Vector3, hp_loss: float, shield_loss: float, source_title: String = "") -> void:
	if not active():return
	var parts: Array[String]=[]
	if shield_loss>0.0:parts.append("护盾 -%d" % maxi(1,roundi(shield_loss)))
	if hp_loss>0.0:parts.append("生命 -%d" % maxi(1,roundi(hp_loss)))
	if parts.is_empty():return
	var root:=Node3D.new()
	root.name="HeroDamageConfirmed"
	add_child(root)
	root.global_position=point+Vector3(0,.08,0)
	var color:=Color("e97870") if hp_loss>0.0 else Color("75cdd5")
	var mat:=glow_material(Color(color.r,color.g,color.b,.82),1.65)
	var ring:=BattleVisuals.ring(root,Vector3.ZERO,1.0,color,.07 if hp_loss>0.0 else .055)
	ring.material_override=mat
	var light:=OmniLight3D.new()
	light.name="HeroDamageFlashLight"
	light.light_color=color
	light.omni_range=2.4
	light.shadow_enabled=false
	light.light_energy=0.0 if reduced_effects else .45*light_envelope(0.0)
	root.add_child(light)
	add_effect({"node":root,"kind":"damage_confirmed","time":0.0,"duration":.34,"materials":[mat],"parts":[],"ring":ring,"light":light,"energy":.45})
	add_float(point+Vector3(0,2.15,0)," · ".join(parts),color,.78,1.05)
	trauma=clampf(trauma+.16,0.0,.50)
	if not reduced_effects:
		BattleVisuals.sparks(game.effects,point+Vector3.UP*.95,color,5)
	play_sound("hurt",-.5,.88)
	duck_music(.18)

func kill(point: Vector3, scrap_gain: int) -> void:
	if not active():return
	var reward_point:=point+Vector3(0,2.35,0)
	var merged:=false
	for i in range(floats.size()-1,-1,-1):
		var item: Dictionary=floats[i]
		if item.get("kind","")!="kill":continue
		if float(item.duration)-float(item.time)>.35:continue
		if (item.point as Vector3).distance_to(reward_point)>3.0:continue
		item.count=int(item.count)+1
		item.scrap=int(item.scrap)+scrap_gain
		item.text=kill_reward_text(item.count,item.scrap)
		item.time=item.duration;item.scale=minf(1.12,1.0+float(item.count-1)*.025)
		merged=true;break
	if not merged:
		add_float(reward_point,kill_reward_text(1,scrap_gain),Color("91dfbf"),1.13,1.0)
		var item: Dictionary=floats.back()
		item.kind="kill";item.count=1;item.scrap=scrap_gain
	var root:=Node3D.new()
	root.name="KillEmbers";add_child(root);root.global_position=point+Vector3(0,.55,0)
	var mat:=glow_material(Color(.56,.90,.73,.87),1.4)
	var parts:=shards(root,Vector3.UP,4 if reduced_effects else 7,[mat],1.55)
	add_effect({"node":root,"kind":"kill","time":0.0,"duration":.48,"materials":[mat],"parts":parts})
	# Area attacks can defeat many enemies together: one clear chime, no sound pile-up.
	if kill_sound_lock<=0:
		play_sound("kill",-1.5,1.0);kill_sound_lock=.12
		duck_music(.3)

func milestone(kills: int, scrap_gain: int) -> void:
	if not active():return
	var point:=Vector3.ZERO
	if is_instance_valid(game.hero):point=game.hero.global_position
	var root:=Node3D.new()
	root.name="KillStreakPulse";add_child(root);root.global_position=point+Vector3(0,.12,0)
	var mat:=glow_material(Color(GOLD.r,GOLD.g,GOLD.b,.72),1.4)
	var ring:=BattleVisuals.ring(root,Vector3.ZERO,1.5,GOLD,.045)
	ring.material_override=mat
	add_effect({"node":root,"kind":"milestone","time":0.0,"duration":.52,"materials":[mat],"parts":[],"ring":ring})
	play_sound("milestone",1.0,1.0);duck_music(.55)

func kill_reward_text(count: int, scrap_gain: int) -> String:
	var text: String="击败×%d" % count
	if scrap_gain>0:text+="  +%d 零件" % scrap_gain
	return text

func camera_offset() -> Vector3:
	if reduced_effects or not active() or trauma<=0.0:return Vector3.ZERO
	var strength:=trauma*trauma
	return Vector3(sin(shake_age*25.0)*.22*strength,sin(shake_age*20.0)*.09*strength,sin(shake_age*23.0+1.8)*.15*strength)

func add_float(point: Vector3, text: String, color: Color, duration: float, scale: float) -> void:
	while floats.size()>=MAX_FLOATS:floats.pop_front()
	floats.append({"point":point,"text":text,"color":color,"time":duration,"duration":duration,"scale":scale})

func add_effect(effect: Dictionary) -> void:
	while effects.size()>=MAX_EFFECTS:
		var first: Dictionary=effects.pop_front()
		if is_instance_valid(first.node):first.node.queue_free()
	effects.append(effect)

func clear_transients() -> void:
	for player in players:
		if is_instance_valid(player):player.stop()
	for effect in effects:
		if is_instance_valid(effect.node):effect.node.queue_free()
	effects.clear();floats.clear();trauma=0.0;kill_sound_lock=0.0

func flat_direction(direction: Vector3) -> Vector3:
	var forward:=Vector3(direction.x,0,direction.z)
	return forward.normalized() if forward.length_squared()>.0001 else Vector3.FORWARD

func glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var mat:=StandardMaterial3D.new()
	mat.albedo_color=color;mat.set_meta("feedback_color",color)
	mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled=true;mat.emission=Color(color.r,color.g,color.b)
	mat.emission_energy_multiplier=energy
	return mat

func arc_mesh(radius: float, width: float, half_angle: float, mat: Material) -> MeshInstance3D:
	var vertices:=PackedVector3Array()
	var colors:=PackedColorArray()
	var indices:=PackedInt32Array()
	var steps:=28
	for i in range(steps+1):
		var fraction:=float(i)/float(steps)
		var angle:=lerpf(-half_angle,half_angle,fraction)
		var taper:=pow(sin(PI*fraction),.65)
		var band_width:=width*(.05+.95*taper)
		var vector:=Vector3(sin(angle),.08*cos(angle),cos(angle))
		vertices.append(vector*(radius-band_width));vertices.append(vector*radius)
		colors.append(Color(1,1,1,taper*.24));colors.append(Color(1,1,1,taper))
		if i<steps:
			var n:=i*2
			indices.append_array(PackedInt32Array([n,n+1,n+2,n+1,n+3,n+2]))
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node:=MeshInstance3D.new();node.mesh=mesh;node.material_override=mat
	(mat as StandardMaterial3D).vertex_color_use_as_albedo=true
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

func shards(root: Node3D, direction: Vector3, count: int, mats: Array, force: float) -> Array[Dictionary]:
	var parts: Array[Dictionary]=[]
	for i in count:
		var motion:=Vector3(rng.randf_range(-1.0,1.0),rng.randf_range(.15,1.2),rng.randf_range(-1.0,1.0)).normalized()*force
		motion+=direction*.7
		var mesh:=BoxMesh.new();mesh.size=Vector3(.055,.055,.22 if i%3==0 else .085)
		var node:=MeshInstance3D.new();node.mesh=mesh;node.material_override=mats[i%mats.size()]
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(node)
		var origin:=Vector3(rng.randf_range(-.08,.08),rng.randf_range(-.06,.06),rng.randf_range(-.08,.08))
		node.position=origin
		parts.append({"node":node,"origin":origin,"velocity":motion,"spin":Vector3(rng.randf_range(-5,5),rng.randf_range(-7,7),rng.randf_range(-5,5))})
	return parts

func duck_music(duration: float) -> void:
	if game and is_instance_valid(game.music) and game.music.has_method("duck"):
		game.music.duck(duration)

func play_sound(key: String, gain_db: float, pitch: float) -> void:
	if not active() or players.is_empty() or not sounds.has(key):return
	var player: AudioStreamPlayer
	for voice in players:
		if not voice.playing:player=voice;break
	if player==null:
		player=players[voice_cursor%MAX_VOICES];voice_cursor+=1
	player.stop();player.stream=sounds[key]
	# Maximum 6 voices remain below clipping even when rewards and impacts overlap.
	player.volume_db=-15.0+minf(gain_db,1.0)
	player.pitch_scale=clampf(pitch,.88,1.12);player.play()

func make_sound(key: String) -> AudioStreamWAV:
	var duration: float=.20
	match key:
		"heavy_swing":duration=.25
		"hit":duration=.20
		"hurt":duration=.24
		"critical":duration=.30
		"finisher":duration=.33
		"kill":duration=.34
		"milestone":duration=.63
	var count:=ceili(duration*float(SAMPLE_RATE))
	var pcm:=PackedByteArray();pcm.resize(count*2)
	var sound_rng:=RandomNumberGenerator.new();sound_rng.seed=key.hash()
	var low_noise:=0.0
	for i in count:
		var t:=float(i)/float(SAMPLE_RATE)
		var p:=t/duration
		var sample:=0.0
		var noise:=sound_rng.randf_range(-1.0,1.0)
		low_noise=lerpf(low_noise,noise,.12)
		match key:
			"swing","heavy_swing":
				var pressure:=pow(sin(PI*p),1.9)
				var weight:=1.0 if key=="swing" else 1.23
				sample=pressure*((noise-low_noise)*.27+low_noise*.42)
				sample+=sin(TAU*(340.0*t-410.0*t*t))*.12*pressure*weight
			"hit","hurt","critical","finisher":
				var strength:=1.0 if key=="hit" else (1.14 if key=="critical" else 1.27)
				var attack:=smoothstep(0.0,.003,t)
				sample=(noise-low_noise)*.26*exp(-t*48.0)
				sample+=low_noise*.40*exp(-t*27.0)
				sample+=sin(TAU*(155.0*t-130.0*t*t))*.28*exp(-t*23.0)
				sample+=sin(TAU*1835.0*t)*.10*exp(-t*34.0)
				if key!="hit":sample+=sin(TAU*740.0*t)*.12*exp(-t*14.0)
				sample*=attack*strength
			"kill","milestone":
				var notes: Array[float]=[587.33,880.0]
				if key=="milestone":notes.assign([440.0,587.33,659.25,880.0])
				for n in notes.size():
					var onset:=float(n)*(.065 if key=="kill" else .087)
					var local_time:=t-onset
					if local_time>=0:
						var envelope:=smoothstep(0.0,.006,local_time)*exp(-local_time*14.0)
						sample+=(sin(TAU*notes[n]*local_time)*.22+sin(TAU*notes[n]*2.013*local_time)*.055)*envelope
				sample+=low_noise*.08*exp(-t*30.0)
		var edge_fade:=smoothstep(0.0,.004,t)*smoothstep(0.0,.012,duration-t)
		var value:=roundi(clampf(sample*edge_fade,-.66,.66)*32767.0)
		pcm.encode_s16(i*2,value)
	var stream:=AudioStreamWAV.new()
	stream.format=AudioStreamWAV.FORMAT_16_BITS;stream.mix_rate=SAMPLE_RATE
	stream.stereo=false;stream.data=pcm
	return stream

func _exit_tree() -> void:
	clear_transients()
	for player in players:
		if is_instance_valid(player):player.stream=null
	players.clear();sounds.clear();game=null
