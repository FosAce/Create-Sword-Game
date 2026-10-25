class_name HotspotMarker
extends Control
## 世界坐标处的一个"纸签"。平时隐形，鼠标靠近（移到铁匠铺/码头附近）才淡入。

const FONT_SIZE := 19
const PAD := Vector2(16.0, 9.0)
const HOVER_RADIUS := 150.0
const FADE_SPEED := 5.5

var world_pos := Vector3.ZERO
var camera: Camera3D
var text := ""
var enabled := true

var _alpha := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(dt: float) -> void:
	if visible != enabled:
		visible = enabled
	if not enabled:
		_alpha = 0.0
	else:
		var target := 1.0 if _near(get_local_mouse_position()) else 0.0
		_alpha = move_toward(_alpha, target, dt * FADE_SPEED)
	queue_redraw()


func _near(pos: Vector2) -> bool:
	if camera == null or camera.is_position_behind(world_pos):
		return false
	return camera.unproject_position(world_pos).distance_to(pos) < HOVER_RADIUS


## 点击判定：和"悬停出现"用同一块区域，所见即所点
func hit_test(pos: Vector2) -> bool:
	if not enabled:
		return false
	return _near(pos)


func _screen_rect() -> Rect2:
	if camera == null or camera.is_position_behind(world_pos):
		return Rect2()
	var p := camera.unproject_position(world_pos)
	var f := UIKit.ensure_font()
	var sz := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	return Rect2(p - Vector2(sz.x * 0.5 + PAD.x, -6.0), sz + PAD * 2.0)


func _draw() -> void:
	if _alpha < 0.01:
		return
	var r := _screen_rect()
	if r.size.x <= 0.0:
		return
	var e := _alpha * _alpha * (3.0 - 2.0 * _alpha)   # 平滑一点
	var sb := UIKit.sb(Color(0.99, 0.97, 0.91, 0.86 * e), 11, 1, Color(1.0, 1.0, 1.0, 0.6 * e))
	draw_style_box(sb, r)

	var f := UIKit.ensure_font()
	var asc := f.get_ascent(FONT_SIZE)
	var base := r.position + Vector2(PAD.x, PAD.y + asc)
	var ink := Palette.INK
	ink.a = e
	draw_string(f, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, ink)
