
## 技能目标选择器的输入辅助Node
## RefCounted不能直接接收_input，用这个Node转发
## 只拦截滚轮和右键/中键，左键放行给按钮

extends Node

func _input(event: InputEvent) -> void:
	var selector = get_meta("selector", null)
	if not selector or not selector.is_open:
		return
	# 只处理滚轮和右键/中键（平移），左键放行给按钮
	var is_wheel = event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN)
	var is_right_mid = event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE)
	var is_pan_motion = event is InputEventMouseMotion and selector._is_panning
	if is_wheel or is_right_mid or is_pan_motion:
		selector.handle_input_event(event)
		get_viewport().set_input_as_handled()
