extends SceneTree

func _initialize() -> void:
	for name in ["RenderingServer", "Performance"]:
		for label in ClassDB.class_get_integer_constant_list(name):
			if "PIPELINE" in label or "FRAME_SETUP" in label:
				print(name, " ", label, "=", ClassDB.class_get_integer_constant(name, label))
	for method in ClassDB.class_get_method_list("RenderingServer"):
		if "time" in method.name or "profil" in method.name:
			print("RS_METHOD ", JSON.stringify(method))
	quit()
