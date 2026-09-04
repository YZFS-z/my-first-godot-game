extends SceneTree
func _init() -> void:
	var s = load("res://scenes/main_menu.tscn")
	print("scene: ", "OK" if s else "FAIL")
	for vid in ["tank_abrams","tank_kv1","tank_t34_85","plane_a10","plane_supermarine_spitfire","heli_ah64"]:
		var v = load("res://data/vehicles/" + vid + ".json")
		print(vid, ": ", "OK" if v else "FAIL", " has_history=", (v and v.has("history")))
	quit()
