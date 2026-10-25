class_name HammerGame
extends Control
## 锻打小游戏：锤点落在"贴合区"里越多，刀身越接近图纸。
## 铁料温度会随锤击下降，太冷必须回炉（真实锻造中最忌讳在低温下硬砸）。

signal finished(fidelity: float)

const STRIKES := 6

var _pos := 0.0
var _dir := 1.0
var _speed := 0.75
var _zone_c := 0.5
var _zone_h := 0.11
var _strikes := 0
var _hits := 0
var _temp := 1200.0
var _reheats := 0
var _done := false
var _flash := 0.0
var _msg := "点 击 / 空 格 落 锤"
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_rng.randomize()
	set_process(true)


func _process(dt: float) -> void:
	if _done:
		return
	_pos += _dir * _speed * dt
	if _pos > 1.0:
		_pos = 1.0
		_dir = -1.0
	elif _pos < 0.0:
		_pos = 0.0
		_dir = 1.0
	_temp = maxf(700.0, _temp - dt * 14.0)
	_flash = maxf(0.0, _flash - dt * 3.0)
	queue_redraw()


func _hit_bar_rect() -> Rect2:
	var w := minf(size.x - 120.0, 760.0)
	return Rect2(Vector2((size.x - w) * 0.5, size.y * 0.5 + 20.0), Vector2(w, 54.0))


func _draw() -> void:
	var font := UIKit.ensure_font()
	var bar := _hit_bar_rect()
	# 面板
	draw_rect(Rect2(Vector2(0, 0), size), Color(0.16, 0.14, 0.12, 0.55))
	draw_rect(Rect2(bar.position + Vector2(-30, -120), Vector2(bar.size.x + 60, 285)),
		Color("fbf6e8"))
	# 标题
	draw_string(font, bar.position + Vector2(-20, -78), "锻 打 · 把坯料打成图纸上的形状",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Palette.UI_TEXT)
	draw_string(font, bar.position + Vector2(-20, -46), _msg,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Palette.UI_ACCENT2)

	# 轨道
	draw_rect(bar, Color("e4dcc7"))
	# 目标区
	var zx := bar.position.x + bar.size.x * (_zone_c - _zone_h)
	var zw := bar.size.x * _zone_h * 2.0
	draw_rect(Rect2(Vector2(zx, bar.position.y), Vector2(zw, bar.size.y)), Color(0.42, 0.72, 0.52))
	# 中心线
	draw_line(Vector2(bar.position.x + bar.size.x * _zone_c, bar.position.y),
		Vector2(bar.position.x + bar.size.x * _zone_c, bar.end.y), Color(1, 1, 1, 0.7), 2.0)
	# 锤头
	var mx := bar.position.x + bar.size.x * _pos
	var hot := clampf((_temp - 700.0) / 500.0, 0.0, 1.0)
	var mcol := Color(1.0, 0.55 + 0.35 * (1.0 - hot), 0.2, 1.0).lerp(Color("8e9aa1"), hot * 0.8)
	draw_rect(Rect2(Vector2(mx - 6, bar.position.y - 12), Vector2(12, bar.size.y + 24)), mcol)
	if _flash > 0.0:
		draw_circle(Vector2(mx, bar.position.y + bar.size.y * 0.5), 40.0 * _flash,
			Color(1, 0.85, 0.4, _flash))

	# 温度条
	var tpos := bar.position + Vector2(0, bar.size.y + 26)
	var tw := bar.size.x
	draw_rect(Rect2(tpos, Vector2(tw, 14)), Color("e4dcc7"))
	draw_rect(Rect2(tpos, Vector2(tw * clampf((_temp - 700.0) / 560.0, 0.0, 1.0), 14)),
		Color(1.0, 0.45, 0.15).lerp(Color("6b3a1a"), 1.0 - hot))
	draw_string(font, tpos + Vector2(0, 34), "料温 %d ℃  %s" % [int(_temp),
		"（太冷了！按 R 回炉）" if _temp < 960.0 else "（可锻区间 1000~1250℃，黄橙色最佳）"],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Palette.UI_TEXT)

	# 锤击计数
	for i in STRIKES:
		var c := Color(0.45, 0.72, 0.52) if i < _hits else Color("d8cfb8")
		draw_circle(bar.position + Vector2(bar.size.x - 10.0 - i * 26.0, bar.size.y + 80.0), 8.0, c)
	draw_string(font, bar.position + Vector2(0, bar.size.y + 88),
		"命中 %d / %d   ·   回炉 %d 次" % [_hits, STRIKES, _reheats],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Palette.UI_DIM)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_strike()
		accept_event()


func _input(event: InputEvent) -> void:
	if not visible or _done:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_SPACE or k == KEY_ENTER:
			_strike()
		elif k == KEY_R:
			_reheat()


func _reheat() -> void:
	_reheats += 1
	_temp = 1230.0
	_msg = "回炉升温 —— 但每烧一次都会掉碳、长氧化皮。"
	queue_redraw()


func _strike() -> void:
	if _done:
		return
	if _temp < 960.0:
		_strikes += 1
		_msg = "料太冷了！这一锤打不出形状，只留下裂纹。"
		_flash = 1.0
		_check_end()
		return
	var dist := absf(_pos - _zone_c)
	if dist <= _zone_h:
		_hits += 1
		_msg = "正中！料子服帖地流动开。"
	else:
		_msg = "打偏了，形状走样了一点。"
	_flash = 1.0
	_temp -= 62.0
	_strikes += 1
	_zone_c = clampf(_zone_c + _rng.randf_range(-0.18, 0.18), 0.18, 0.82)
	_zone_h = maxf(0.055, _zone_h - 0.009)
	_speed += 0.06
	_check_end()


func _check_end() -> void:
	if _strikes >= STRIKES and not _done:
		_done = true
		var f := 0.62 + 0.38 * (float(_hits) / float(STRIKES))
		f -= float(_reheats) * 0.02
		f = clampf(f, 0.55, 1.0)
		_msg = "锻打结束：贴合度 %d%%" % int(f * 100.0)
		queue_redraw()
		await get_tree().create_timer(0.75).timeout
		finished.emit(f)
	else:
		queue_redraw()
