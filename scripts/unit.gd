class_name BattleUnit
extends Node3D
## Combatant data and presentation. The match controller owns battle decisions.
signal defeated(unit: BattleUnit, source: BattleUnit)
signal damaged(unit: BattleUnit, source: BattleUnit)

var team: int = 0
var kind: String = "minion"
var title: String = "卫兵"
var hp: float = 100.0
var max_hp: float = 100.0
var damage: float = 10.0
var armor: float = 0.0
var speed: float = 3.0
var attack_range: float = 1.7
var attack_interval: float = 1.1
var attack_timer: float = 0.0
var shield: float = 0.0
var shield_time: float = 0.0
var alive: bool = true
var moving: bool = false
var target: BattleUnit
var destination := Vector3.ZERO
var visual: Node3D
var selection: MeshInstance3D
var age: float = 0.0
var attack_pose: float = 0.0
var attack_windup: float = 0.0
var attack_queued: bool = false
var attack_target_hero: bool = false
var attack_target_pad: int = -1
var attack_target_barricade: bool = false
var windup_duration: float = 0.34
var arms: Array[Node3D] = []
var legs: Array[Node3D] = []
var knees: Array[Node3D] = []
var feet: Array[Node3D] = []
var gait_blend: float = 0.0
var gait_phase: float = 0.0
var locomotion_velocity := Vector3.ZERO
var locomotion_has_sample: bool = false
var hero_upper_body: Node3D
var hero_pelvis: Node3D
var hero_sword_wrist: Node3D
var hero_sword_wrist_rest := Vector3.ZERO
var gait_turn: float = 0.0
var gait_turn_target: float = 0.0
var gait_was_moving: bool = false
var foot_rest_positions: Array[Vector3] = []
var elbows: Array[Node3D] = []
var tabards: Array[Node3D] = []
var boot_sole_points: Array[PackedVector3Array] = []
var hero_action: String = ""
var hero_action_time: float = 0.0
var hero_action_duration: float = 0.0
var hero_action_weight: float = 0.0
var hero_action_aim_yaw: float = 0.0
var hero_attack_variant: int = 0
var hero_stride_duration: float = .76
var hero_ground_offset: float = -.026
var hero_stride_distance: float = 3.4
var hero_contact_fraction: float = .28
var hero_run_intensity: float = 0.0
var hero_cloak_lag := Vector3.ZERO
var hero_tabard_lag: Array[float] = [0.0, 0.0]

# Action tracks are time and shoulder X/Y/Z, with continuous tangents.
const HERO_ATTACK_ARM: Array[Vector4] = [
	Vector4(0.00, -.42, -.25, -.26),
	Vector4(0.07, -.92, -.42, -.34),
	Vector4(0.20, -.38, .43, .15),
	Vector4(0.39, .12, .50, .26),
	Vector4(0.68, -.04, .11, .02),
	Vector4(1.00, 0, 0, 0),
]
const HERO_INFERNO_ARM: Array[Vector4] = [
	Vector4(0.00, -.55, 0, -.42),
	Vector4(0.06, -.94, -.14, -.70),
	Vector4(0.21, -.76, .13, -.64),
	Vector4(0.49, -.46, .08, -.43),
	Vector4(0.77, -.16, .02, -.15),
	Vector4(1.00, 0, 0, 0),
]
var lane: int = 1
var tier: int = 0
var route_index: int = 1
var path := PackedVector3Array()
var path_goal := Vector3.INF
var path_timer: float = 0.0
var skill_timer: float = 6.0
var respawn_timer: float = 0.0
var retreating: bool = false
var home_point := Vector3.ZERO
var camp_buff: String = ""
var resetting: bool = false
var shield_visual: MeshInstance3D
var cloak: Node3D
var stalker_head: Node3D
var hit_recoil: float=0.0
var visual_hit_stop: float=0.0
var visual_yaw_offset: float=0.0

func bind_stalker_rig() -> void:
	legs.clear()
	for part in ["FrontLeft","FrontRight","RearLeft","RearRight"]:
		var limb:=visual.find_child(part,true,false) as Node3D
		if limb:legs.append(limb)
	stalker_head=visual.find_child("StalkerHead",true,false) as Node3D

func setup(unit_kind: String, faction: int) -> void:
	kind = unit_kind
	team = faction
	match kind:
		"hero":
			max_hp = 850.0; damage = 58.0; speed = 6.0; attack_range = 5.2; attack_interval = 0.8
			title = "苍曜 · 星刃" if team == 0 else "绯烬 · 破誓者"
		"minion":
			max_hp = 185.0; damage = 17.0; speed = 2.6; attack_range = 1.6; attack_interval = 1.2
		"tower":
			max_hp = 1250.0; damage = 88.0; speed = 0.0; attack_range = 8.0; attack_interval = 1.1
			title = "苍穹守塔" if team == 0 else "绯红守塔"
		"core":
			max_hp = 2200.0; damage = 46.0; speed = 0.0; attack_range = 7.0; attack_interval = 1.0
			title = "苍穹核心" if team == 0 else "绯红核心"
		"monster":
			max_hp=650; damage=38; speed=3.2; attack_range=2.4; attack_interval=1.2
			title="裂岩守卫"
	hp = max_hp
	var model_path := "res://assets/models/%s_%s.glb" % [kind, "blue" if team == 0 else "red"]
	if kind == "monster": model_path="res://assets/models/golem.glb"
	if kind == "hero": model_path="res://assets/models/hero_ashwarden_%s.glb" % ("blue" if team == 0 else "red")
	if kind == "tower" or kind == "core": model_path="res://assets/models/%s_%s_v2.glb" % [kind, "blue" if team == 0 else "red"]
	var scene := load(model_path) as PackedScene
	visual = scene.instantiate() as Node3D
	add_child(visual)
	if kind == "minion" or kind == "monster": BattleVisuals.paint_model(visual)
	if kind == "hero":
		visual.scale = Vector3.ONE * 1.25
		# glTF converts Blender's -Y front to Godot's +Z front.
		visual_yaw_offset = PI
		cloak = visual.find_child("Tailored_pleated_cape", true, false) as Node3D
		if not cloak: cloak = visual.find_child("Tailored pleated cape", true, false) as Node3D
		for part in ["ArmL", "ArmR"]:
			var limb := visual.find_child(part, true, false) as Node3D
			if limb: arms.append(limb)
		for part in ["LegL", "LegR"]:
			var limb := visual.find_child(part, true, false) as Node3D
			if limb: legs.append(limb)
		for part in ["KneeL", "KneeR"]:
			var joint := visual.find_child(part, true, false) as Node3D
			if joint: knees.append(joint)
		for part in ["FootL", "FootR"]:
			var joint := visual.find_child(part, true, false) as Node3D
			if joint: feet.append(joint)
		bind_hero_gait()
	if kind == "minion":
		attach_minion_gear()
	selection = BattleVisuals.ring(self, Vector3(0, 0.06, 0), 0.7 if kind == "hero" else 0.4, Color("ee8061") if kind == "monster" else faction_color())
	selection.visible = kind == "hero"
	if kind=="hero":
		shield_visual=BattleVisuals.ring(self,Vector3(0,1,0),.85,Color("7be5f4"),.035)
		shield_visual.rotation.z=PI*.5
		shield_visual.visible=false

func attach_minion_gear() -> void:
	var left_arm := visual.find_child("ArmL", true, false) as Node3D
	var right_arm := visual.find_child("ArmR", true, false) as Node3D
	if not left_arm or not right_arm: return
	for part in visual.find_children("*", "MeshInstance3D", true, false):
		var item := part as Node3D
		var label := item.name.to_lower()
		var parent_arm: Node3D
		if "shield" in label or "shoulder" in label:
			parent_arm = left_arm if item.global_position.x < 0.0 or "shield" in label else right_arm
		elif "polearm" in label or "spear" in label:
			parent_arm = right_arm
		if parent_arm:
			var world_transform := item.global_transform
			item.reparent(parent_arm, true)
			item.global_transform = world_transform

func faction_color() -> Color:
	if team==2: return Color("e7bb68")
	return Color("57d8ec") if team == 0 else Color("ff6377")

func is_structure() -> bool:
	return kind == "tower" or kind == "core"

func bind_hero_gait() -> void:
	# The imported model has real hip, knee and ankle pivots. A waist pivot lets
	# its rigid chest counter the hips without moving the simulated unit.
	hero_upper_body = Node3D.new()
	hero_upper_body.name = "GaitUpperBody"
	hero_upper_body.position = Vector3(0, 1.08, 0)
	visual.add_child(hero_upper_body)
	for part in visual.get_children():
		if part is Node3D and part != hero_upper_body and part not in legs:
			part.reparent(hero_upper_body, true)
	foot_rest_positions.clear()
	for i in mini(legs.size(), mini(knees.size(), feet.size())):
		foot_rest_positions.append(legs[i].position + knees[i].position + feet[i].position)
	for label in ["ElbowL", "ElbowR"]:
		var elbow := visual.find_child(label, true, false) as Node3D
		if elbow: elbows.append(elbow)
	hero_sword_wrist = visual.find_child("Sword_wrist", true, false) as Node3D
	if not hero_sword_wrist: hero_sword_wrist = visual.find_child("Sword wrist", true, false) as Node3D
	if hero_sword_wrist: hero_sword_wrist_rest = hero_sword_wrist.rotation
	# Each split tabard pivots at the belt and clears the leading thigh.
	# Keeping it under the waist also prevents shoulder counter-rotation from
	# dragging the hem through the upper legs.
	for side in [-1, 1]:
		var flap := Node3D.new()
		flap.name = "GaitTabardL" if side < 0 else "GaitTabardR"
		flap.position = Vector3(side * .105, 1.155, .205)
		visual.add_child(flap)
		for item in hero_upper_body.get_children():
			var label := str(item.name)
			if "Weathered_split_tabard" not in label and "Weathered split tabard" not in label and "Tabard_seam" not in label and "Tabard seam" not in label: continue
			var mesh := item as MeshInstance3D
			if not mesh: continue
			var center := visual.to_local(mesh.to_global(mesh.get_aabb().get_center()))
			if signf(center.x) == side: item.reparent(flap, true)
		tabards.append(flap)
	# Separate pelvic roll from the chest: the shoulders counter the planted
	# leg instead of rotating the armored silhouette as a single stiff block.
	hero_pelvis = Node3D.new()
	hero_pelvis.name = "GaitPelvis"
	hero_pelvis.position = Vector3(0, 1.0, 0)
	visual.add_child(hero_pelvis)
	for part in legs + tabards:
		part.reparent(hero_pelvis, true)
	boot_sole_points.clear()
	for foot in feet:
		var sole := PackedVector3Array()
		for item in foot.find_children("*", "MeshInstance3D", true, false):
			if not "Broad_toe_boot" in str(item.name) and not "Broad toe boot" in str(item.name): continue
			var boot := item as MeshInstance3D
			var bounds := boot.get_aabb()
			for x in [bounds.position.x, bounds.end.x]:
				for z in [bounds.position.z, bounds.end.z]:
					sole.append(foot.to_local(boot.to_global(Vector3(x, bounds.position.y, z))))
		boot_sole_points.append(sole)

func set_locomotion_velocity(velocity: Vector3) -> void:
	locomotion_velocity = Vector3(velocity.x, 0, velocity.z)
	locomotion_has_sample = true

func sample_hero_track(track: Array[Vector4], time: float, cyclic: bool = false) -> Vector3:
	time = fposmod(time, 1.0) if cyclic else clampf(time, 0.0, 1.0)
	for i in range(track.size() - 1):
		var a := track[i]
		var b := track[i + 1]
		if time > b.x: continue
		var before := track[i - 1] if i > 0 else (track[-2] - Vector4(1, 0, 0, 0) if cyclic else a)
		var after := track[i + 2] if i + 2 < track.size() else (track[1] + Vector4(1, 0, 0, 0) if cyclic else b)
		var span := b.x - a.x
		var t := clampf((time - a.x) / span, 0, 1)
		var av := Vector3(a.y, a.z, a.w)
		var bv := Vector3(b.y, b.z, b.w)
		var tangent_a := (bv - Vector3(before.y, before.z, before.w)) * span / maxf(.001, b.x - before.x)
		var tangent_b := (Vector3(after.y, after.z, after.w) - av) * span / maxf(.001, after.x - a.x)
		return (2*t*t*t-3*t*t+1)*av + (t*t*t-2*t*t+t)*tangent_a + (-2*t*t*t+3*t*t)*bv + (t*t*t-t*t)*tangent_b
	return Vector3(track[-1].y, track[-1].z, track[-1].w)

func play_action(action_name: String, direction: Vector3 = Vector3.ZERO) -> void:
	if kind != "hero" or not alive or action_name not in ["attack", "inferno"]: return
	if hero_action == "inferno" and hero_action_time < hero_action_duration: return
	hero_action = action_name
	hero_action_time = 0.0
	hero_action_duration = .70 if action_name == "attack" else .96
	hero_action_weight = 1.0
	hero_action_aim_yaw = 0.0
	if direction.length_squared() > .001:
		var target_yaw := atan2(direction.x, direction.z)
		hero_action_aim_yaw = clampf(wrapf(target_yaw - visual.global_rotation.y, -PI, PI), -.35, .35)
		if not moving: face(position + Vector3(direction.x, 0, direction.z), .035)
	# Apply the first contact pose in the same frame as the hit/skill effect.
	animate_hero_gait(0.0)

func hero_boot_lowest(foot_index: int) -> float:
	var lowest := INF
	if foot_index >= boot_sole_points.size(): return feet[foot_index].global_position.y - position.y - .15
	for corner in boot_sole_points[foot_index]:
		lowest = minf(lowest, feet[foot_index].to_global(corner).y - position.y)
	return lowest if lowest < INF else feet[foot_index].global_position.y - position.y - .15

func hero_leg_target(phase: float, stride: float) -> Vector2:
	# X is ankle forward/back distance; Y is its height above a flat boot.
	# A contact foot retreats by precisely the unit's travelled distance. The
	# recovery interval is longer, with a distinct toe-off and knee lift.
	var sweep := hero_stride_distance * hero_contact_fraction / visual.scale.y
	var z := 0.0
	var lift := 0.0
	if phase <= hero_contact_fraction:
		z = sweep * (.5 - phase / hero_contact_fraction)
	else:
		var t := (phase - hero_contact_fraction) / (1.0 - hero_contact_fraction)
		z = sweep * (smoothstep(0.0, 1.0, t) - .5)
		lift = pow(sin(t * PI), 1.45) * lerpf(.090, .125, hero_run_intensity)
	return Vector2(z * stride + .025, lift * stride)

func pose_hero_leg(index: int, target: Vector2, phase: float, stride: float) -> void:
	# Two-link Y/Z solve for the existing rigid hip/knee pivots. This is node
	# articulation, not a skinned skeleton; the imported armor is unchanged.
	var thigh := Vector2(-knees[index].position.y, -knees[index].position.z)
	var shin := Vector2(-feet[index].position.y, -feet[index].position.z)
	var upper := thigh.length()
	var lower := shin.length()
	var hip_y := hero_pelvis.position.y + legs[index].position.y
	var sole_ankle_y := .026 / visual.scale.y + .125
	var dy := sole_ankle_y + target.y - visual.position.y / visual.scale.y - hip_y
	var dz := target.x
	var reach := clampf(Vector2(dy, dz).length(), absf(upper - lower) + .001, upper + lower - .012)
	var bend := acos(clampf((reach * reach - upper * upper - lower * lower) / (2 * upper * lower), -1, 1))
	var upper_rest := atan2(thigh.y, thigh.x)
	var lower_rest := atan2(shin.y, shin.x)
	var hip := atan2(-dz, -dy) - atan2(lower * sin(bend), upper + lower * cos(bend)) - upper_rest
	var knee := bend - (lower_rest - upper_rest)
	# During contact the broad boot remains flat. Once airborne its toe
	# tucks, then extends before landing, instead of pointing down all cycle.
	var tuck := 0.0
	if phase > hero_contact_fraction:
		var recovery := (phase - hero_contact_fraction) / (1.0 - hero_contact_fraction)
		tuck = -.20 * sin(recovery * PI) + .10 * sin(recovery * TAU)
	legs[index].rotation = Vector3(hip * stride, 0, 0)
	knees[index].rotation = Vector3(knee * stride, 0, 0)
	feet[index].rotation = Vector3((-hip - knee + tuck) * stride, 0, 0)

func animate_hero_gait(delta: float) -> void:
	var planar_speed := locomotion_velocity.length() if locomotion_has_sample else (speed if moving else 0.0)
	var walking := moving and planar_speed > .08
	if walking and not gait_was_moving and gait_blend < .03:
		gait_phase = .035 * TAU
	gait_was_moving = walking
	gait_blend = move_toward(gait_blend, 1.0 if walking else 0.0, delta * (12.5 if walking else 14.0))
	# Cadence is driven by metres travelled, never by current speed / speed
	# stat (which made every speed card keep the same sluggish walk cycle).
	hero_run_intensity = clampf((planar_speed - 2.5) / 5.9, 0.0, 1.0)
	if walking:
		hero_stride_distance = clampf(1.4 + planar_speed / 3.0, 1.6, 4.8)
		hero_contact_fraction = lerpf(.36, .18, hero_run_intensity)
		hero_stride_duration = hero_stride_distance / planar_speed
	if walking:
		gait_phase = fposmod(gait_phase + delta * planar_speed / hero_stride_distance * TAU, TAU)
	# No extra in-place step after the controller has stopped moving.
	gait_turn = lerpf(gait_turn, gait_turn_target, 1.0 - exp(-delta * 7.5))
	gait_turn_target = move_toward(gait_turn_target, 0.0, delta * 3.0)
	if hero_action != "":
		hero_action_time += delta
		if hero_action_time >= hero_action_duration:
			hero_action = ""
			hero_action_weight = 0.0
	var action_t := clampf(hero_action_time / maxf(hero_action_duration, .001), 0, 1)
	hero_action_weight = (1.0 - smoothstep(.62, 1.0, action_t)) if hero_action != "" else 0.0
	var stride := gait_blend
	if hero_sword_wrist:
		# Raise the long blade beside the running shoulder; the old display
		# wrist angle dragged its tip through the floor on every planted step.
		hero_sword_wrist.rotation = hero_sword_wrist_rest + Vector3(0, 0, .48 * stride * (1.0 - hero_action_weight))
	var sway := sin(gait_phase)
	var breath := sin(age * 1.55) * .007 * (1.0 - gait_blend)
	visual.position.x = 0.0
	visual.rotation.x = 0.0
	visual.rotation.z = -gait_turn * .028 * stride
	# A vault over the planted boot keeps the support knee nearly extended.
	# In the short flight the pelvis follows a low arc, rather than being
	# snapped to whichever toe happens to be the lowest mesh that frame.
	var half_phase := fposmod(gait_phase / TAU, .5)
	var support_target := hero_leg_target(half_phase, 1.0)
	var support_z := support_target.x
	var vault := .026 / visual.scale.y + .125 + sqrt(maxf(.01, .815 * .815 - support_z * support_z)) - 1.0
	if half_phase > hero_contact_fraction:
		var flight_t := (half_phase - hero_contact_fraction) / (.5 - hero_contact_fraction)
		var half_sweep := hero_stride_distance * hero_contact_fraction / visual.scale.y * .5
		var back_z := -half_sweep + .025
		var front_z := half_sweep + .025
		var back_height := .026 / visual.scale.y + .125 + sqrt(maxf(.01, .815 * .815 - back_z * back_z)) - 1.0
		var front_height := .026 / visual.scale.y + .125 + sqrt(maxf(.01, .815 * .815 - front_z * front_z)) - 1.0
		var flight_arc := .070 * (.5 - hero_contact_fraction) / .32
		vault = lerpf(back_height, front_height, flight_t) + sin(flight_t * PI) * flight_arc
	# Armor carries weight: share the vault with modest knee flexion so the
	# helmet travels a small arc, instead of bouncing a full foot-reach arc.
	vault = lerpf(-.055, vault, .90)
	visual.position.y = lerpf(-.030, vault * visual.scale.y, stride)
	if hero_pelvis:
		hero_pelvis.rotation = Vector3(0, sway * .047 * stride, sway * .015 * stride)
	if hero_upper_body:
		hero_upper_body.rotation = Vector3(breath + lerpf(.055, .135, hero_run_intensity) * stride, (-sway * .087 + gait_turn * .070) * stride, -sway * .030 * stride)
	if cloak:
		var cloak_target := Vector3(.025 + stride * (.125 + .042 * sin(gait_phase - .8)), 0, sin(age * 2.2) * .010 + sin(gait_phase - 1.0) * .040 * stride + gait_turn * .040)
		hero_cloak_lag = hero_cloak_lag.lerp(cloak_target, 1.0 - exp(-delta * 10.0))
		cloak.rotation = hero_cloak_lag
	for i in mini(legs.size(), mini(knees.size(), feet.size())):
		var phase := fposmod(gait_phase / TAU + float(i) * .5, 1.0)
		pose_hero_leg(i, hero_leg_target(phase, stride), phase, stride)
		if i < tabards.size():
			var thigh_clearance := minf(0.0, legs[i].rotation.x) * .95 - .035 * stride
			hero_tabard_lag[i] = lerpf(hero_tabard_lag[i], thigh_clearance, 1.0 - exp(-delta * 24.0))
			# The forward thigh may open the fabric immediately; the return
			# trails it. Delaying clearance itself would let armor pierce cloth.
			tabards[i].rotation.x = minf(thigh_clearance, hero_tabard_lag[i])
			tabards[i].rotation.z = (1 if i == 0 else -1) * .025 * stride
	for i in arms.size():
		var side := 1.0 if i == 0 else -1.0
		# The sword hand stays compact and bent; the free arm counter-drives
		# the opposite leg. Both shoulders participate without rigid symmetry.
		arms[i].rotation = Vector3((-.08 - side * sway * (.27 if i == 0 else .19)) * stride, side * .035 * stride, side * -.055 * stride)
		if i < elbows.size(): elbows[i].rotation.x = -.12 - stride * (.55 + side * sway * .11)
	if hero_action == "attack":
		var sword_track:=sample_hero_track(HERO_ATTACK_ARM, action_t)
		var sweep_sign: float=-1.0 if hero_attack_variant==1 else 1.0
		sword_track.y*=sweep_sign
		sword_track.z*=sweep_sign
		if hero_attack_variant==2:
			sword_track.x-=.20*sin(action_t*PI)
		arms[1].rotation += sword_track
		arms[0].rotation += Vector3(-.15, 0, .10) * sin(action_t * PI)
		if elbows.size() == 2:
			elbows[1].rotation.x -= (.55 * (1.0 - smoothstep(.05, .35, action_t)) + .12 * sin(action_t * PI))
		if hero_upper_body:
			hero_upper_body.rotation.y += lerpf(-.20, .25, smoothstep(.04, .22, action_t)) * (1.0 - smoothstep(.40, 1.0, action_t))*sweep_sign
			hero_upper_body.rotation.y += hero_action_aim_yaw * hero_action_weight
			hero_upper_body.rotation.x += .045 * sin(action_t * PI)
	elif hero_action == "inferno":
		var spread := sample_hero_track(HERO_INFERNO_ARM, action_t)
		for i in arms.size():
			arms[i].rotation += Vector3(spread.x, spread.y * (1 if i == 1 else -1), spread.z * (1 if i == 0 else -1))
			if i < elbows.size(): elbows[i].rotation.x -= .40 * (1.0 - smoothstep(.20, .90, action_t))
		if hero_upper_body:
			hero_upper_body.rotation.x -= .065 * (1.0 - smoothstep(.20, .80, action_t))
			hero_upper_body.rotation.y += hero_action_aim_yaw * hero_action_weight * .4
		if cloak: cloak.rotation.x += .13 * (1.0 - smoothstep(.10, .70, action_t))
	# Small safety correction uses the real broad-toe mesh corners, including
	# turn lean. The pelvis trajectory above owns the motion; this does not
	# pull the body down to an airborne boot during recovery.
	var lowest := INF
	for i in feet.size(): lowest = minf(lowest, hero_boot_lowest(i))
	if lowest < INF:
		visual.position.y += maxf(0.0, .026 - lowest)
		hero_ground_offset = visual.position.y

func tick(delta: float) -> void:
	path_timer=maxf(0,path_timer-delta)
	attack_timer = maxf(0.0, attack_timer - delta)
	shield_time = maxf(0.0, shield_time - delta)
	if shield_time == 0.0: shield = 0.0
	attack_windup = maxf(0.0, attack_windup - delta)
	# Freeze only the impact pose for a few milliseconds. Movement, cooldowns
	# and attack telegraphs still advance; no global time-scale or input stall.
	if visual_hit_stop>0.0:
		visual_hit_stop=maxf(0.0,visual_hit_stop-delta)
		return
	age += delta
	attack_pose = maxf(0.0, attack_pose - delta * 5)
	hit_recoil=maxf(0.0,hit_recoil-delta*4.0)
	if not alive: return
	if kind == "hero":
		shield_visual.visible=shield>0
		animate_hero_gait(delta)
		shield_visual.rotation.y+=delta*2
	elif kind == "minion":
		visual.position.y = absf(sin(age * 9)) * 0.10 if moving else 0.0
	elif kind == "monster":
		var is_breaker: bool=get_meta("threat","")=="breaker"
		var gait_rate:=clampf(speed*2.6,6.0,14.0)
		var stride:=1.0 if moving else .08
		var winding:=attack_queued and attack_windup>0
		var readiness:=1.0-attack_windup/maxf(.01,windup_duration) if winding else 0.0
		selection.visible=attack_queued
		selection.scale=Vector3.ONE*(1.25+readiness*1.55)
		visual.position.y=(absf(sin(age*gait_rate))*.085 if moving else sin(age*2.0)*.018)-attack_pose*(.26 if is_breaker else .16)-readiness*(.24 if is_breaker else .15)
		visual.position.z=readiness*(.38 if is_breaker else .24)-attack_pose*(.84 if is_breaker else .58)+hit_recoil*.12
		visual.rotation.x=attack_pose*(.66 if is_breaker else .44)-hit_recoil*.22-readiness*(.38 if is_breaker else .28)
		visual.rotation.z=(sin(age*gait_rate*.5)*.045 if moving else 0.0)+hit_recoil*.09
		for i in legs.size():
			var phase:=age*gait_rate+(PI if i==1 or i==2 else 0.0)+(-.65 if i>=2 else 0.0)
			legs[i].rotation.x=sin(phase)*stride*.6+(-readiness*(.56 if is_breaker else .42)+attack_pose*(.4 if is_breaker else .28) if i<2 else readiness*(.36 if is_breaker else .26)-attack_pose*(.25 if is_breaker else .16))
			legs[i].rotation.z=(1.0 if i%2==0 else -1.0)*maxf(0.0,cos(phase))*stride*.15
		if stalker_head:
			stalker_head.rotation.x=-attack_pose*(.8 if is_breaker else .55)+readiness*(.62 if is_breaker else .42)+sin(age*2.6)*.035
			stalker_head.rotation.z=sin(age*gait_rate*.5)*.07 if moving else 0.0

func face(point: Vector3, delta: float = 1.0) -> void:
	var direction := point - position
	if direction.length_squared() > 0.000001:
		var heading := atan2(-direction.x, -direction.z) + visual_yaw_offset
		if kind == "hero": gait_turn_target = clampf(wrapf(heading - visual.rotation.y, -PI, PI), -1.0, 1.0)
		var response := 1.0 - exp(-delta * (28.0 if kind == "hero" else 12.0))
		visual.rotation.y = lerp_angle(visual.rotation.y, heading, response)

func hurt(amount: float, source: BattleUnit) -> void:
	if not alive: return
	if kind=="monster":hit_recoil=1.0
	damaged.emit(self,source)
	amount*=100.0/(100.0+armor)
	var absorbed := minf(shield, amount)
	shield -= absorbed
	hp = maxf(0.0, hp - (amount - absorbed))
	if hp <= 0:
		alive = false
		moving = false
		attack_queued=false
		attack_target_hero=false
		defeated.emit(self, source)

func revive(point: Vector3) -> void:
	position = point
	destination = point
	hp = max_hp
	shield = 0
	alive = true
	visible = true
	target = null
	path.clear()
	path_timer=0
	attack_windup=0
	attack_queued=false
	attack_target_hero=false
	route_index=1
	retreating=false
	resetting=false
