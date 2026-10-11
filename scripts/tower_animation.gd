extends Node3D
## Game-time-only mechanical ornament; no combat or independent timers.
const Visuals = preload("res://scripts/visuals.gd")
var rotor: Node3D
var core: MeshInstance3D
var elapsed := 0.0
var recoil := 0.0
var tier := 1
var variant := "standard"

func configure(level: int, branch: String) -> void:
	tier=clampi(level,1,3)
	variant=branch
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var tint: Color={"standard":Color("ffd086"),"piercing":Color("d791ff"),"control":Color("79ccff"),"flame":Color("ff824e"),"chain":Color("a1f5e4")}.get(branch,Color("ffd086"))
	var steel:=Visuals.material(Color("344958"))
	var brass:=Visuals.material(Color("af8552"))
	Visuals.box(self,Vector3(0,.22,0),Vector3(1.9,.26,1.9),steel)
	Visuals.box(self,Vector3(0,.42,0),Vector3(1.55,.14,1.55),brass)
	for x in [-1,1]:
		for z in [-1,1]:
			Visuals.box(self,Vector3(x*.78,.62,z*.78),Vector3(.19,.55,.19),steel)
	rotor=Node3D.new()
	add_child(rotor)
	rotor.position.y=2.05
	Visuals.ring(rotor,Vector3.ZERO,.65,tint,.045)
	for index in tier+1:
		var angle:=TAU*index/(tier+1)
		Visuals.box(rotor,Vector3(cos(angle)*.65,.08,sin(angle)*.65),Vector3(.13,.22,.13),brass)
	core=Visuals.box(self,Vector3(0,2.27,0),Vector3(.24,.4,.24),Visuals.material(tint,1.2))
	core.rotation.z=PI/4

func advance(delta: float) -> void:
	elapsed+=maxf(delta,0.0)
	recoil=move_toward(recoil,0.0,maxf(delta,0.0)*2.8)
	rotor.rotation.y=elapsed*(.22+tier*.06)
	core.position.y=2.27+sin(elapsed*1.8)*.035-recoil*.18
	core.scale=Vector3.ONE*(1.0+recoil*.3)

func fire() -> void:
	recoil=1.0
