class_name OrbitCamera
extends Camera3D
## 箱庭用轨道相机：拖拽旋转、滚轮缩放，静止时缓慢自转（像展示柜）。

signal tapped(pos: Vector2)

var target := Vector3(0.0, 0.8, 0.0)
var yaw := deg_to_rad(26.0)
var pitch := deg_to_rad(36.0)
var distance := 35.0
var min_distance := 16.0
var max_distance := 58.0
var auto_rotate := 0.035

var _dragging := false
var _travel := 0.0


func _ready() -> void:
	fov = 30.0
	near = 0.5
	far = 200.0
	_apply()


func _process(dt: float) -> void:
	if not _dragging:
		yaw += auto_rotate * dt
	_apply()


func _apply() -> void:
	var cp := cos(pitch)
	var p := Vector3(sin(yaw) * cp, sin(pitch), cos(yaw) * cp) * distance + target
	position = p
	look_at(target, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_travel = 0.0
			else:
				if _dragging and _travel < 9.0:
					tapped.emit(mb.position)
				_dragging = false
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			distance = clampf(distance * 0.92, min_distance, max_distance)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			distance = clampf(distance / 0.92, min_distance, max_distance)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * 0.006
		pitch = clampf(pitch + mm.relative.y * 0.005,
			deg_to_rad(8.0), deg_to_rad(72.0))
		_travel += mm.relative.length()
