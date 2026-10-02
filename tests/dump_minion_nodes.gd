extends SceneTree
func _initialize():
 var s=load('res://assets/models/minion_blue.glb').instantiate()
 root.add_child(s)
 _print_names(s)
 quit()
func _print_names(n):
 print(n.name,' ',n.position,' ',n.get_class())
 for c in n.get_children():_print_names(c)
