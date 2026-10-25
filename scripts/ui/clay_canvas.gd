class_name ClayCanvas
extends Control
## 覆土烧刃：在刀身的(展开)平面图上刷一层耐火泥。
## 上方 v=0 是刀背，下方 v=1 是刀刃。
## 刀背糊厚土 → 冷却慢 → 不硬化（软而韧）；刃口留空 → 全硬化。
## 两者交界就是"刃文"(hamon)。

signal accepted(img: Image, spine: float, edge: float)
signal cancelled()

const IW := 512
const IH := 160

var mask: Image
var tex: ImageTexture
var preview_mat: ShaderMaterial
var brush: float = 14.0
var erasing: bool = false

var _paper := Rect2()
var _preview: ColorRect
var _undo: Image = null
var _painting := false
var _dirty := false
var _last := Vector2(-9999, -9999)
var _cursor := Vector2(-9999, -9999)
var _hint: Label
var _brush_slider: HSlider


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mask = Image.create_empty(IW, IH, false, Image.FORMAT_RGBA8)
	mask.fill(Color(0, 0, 0, 1))
	tex = ImageTexture.create_from_image(mask)

	preview_mat = ShaderMaterial.new()
	preview_mat.shader = load("res://shaders/clay_preview.gdshader")
	preview_mat.set_shader_parameter("clay_tex", tex)

	_preview = ColorRect.new()
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.material = preview_mat
	_preview.color = Color.WHITE
	add_child(_preview)

	_build_toolbar()
	_stamp_preset(2)   # 默认给一条波浪刃文，玩家再改


func _build_toolbar() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UIKit.sb(Color("f6efdd"), 12, 2, Color(0, 0, 0, 0.05)))
	bar.anchor_right = 1.0
	bar.offset_bottom = 56
	add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	bar.add_child(h)

	h.add_child(UIKit.label("刷泥", 15, Palette.UI_DIM))
	_brush_slider = UIKit.slider(6.0, 40.0, 1.0, brush)
	_brush_slider.custom_minimum_size = Vector2(120, 26)
	_brush_slider.value_changed.connect(func(v: float) -> void: brush = v)
	h.add_child(_brush_slider)

	var er := UIKit.button("刮掉")
	er.toggle_mode = true
	er.toggled.connect(func(on: bool) -> void: erasing = on)
	h.add_child(er)

	var spacer0 := Control.new()
	spacer0.custom_minimum_size = Vector2(16, 0)
	h.add_child(spacer0)

	var p0 := UIKit.button("不覆土")
	p0.pressed.connect(func() -> void: _stamp_preset(0))
	h.add_child(p0)
	var p1 := UIKit.button("直刃文")
	p1.pressed.connect(func() -> void: _stamp_preset(1))
	h.add_child(p1)
	var p2 := UIKit.button("波浪刃文")
	p2.pressed.connect(func() -> void: _stamp_preset(2))
	h.add_child(p2)
	var p3 := UIKit.button("乱刃文")
	p3.pressed.connect(func() -> void: _stamp_preset(3))
	h.add_child(p3)

	var undo := UIKit.button("撤销")
	undo.pressed.connect(func() -> void:
		if _undo != null:
			mask = _undo.duplicate() as Image
			_undo = null
			_dirty = true)
	h.add_child(undo)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)

	var back := UIKit.button("放弃")
	back.pressed.connect(func() -> void: cancelled.emit())
	h.add_child(back)

	var ok := UIKit.button("入炉淬火 ▶", true)
	ok.pressed.connect(_on_accept)
	h.add_child(ok)

	_hint = UIKit.label("上方是刀背、下方是刀刃：把土刷在刀背上，刃口留空。", 15, Palette.UI_ACCENT2)
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_top = -28
	_hint.offset_left = 8
	add_child(_hint)


## 0 = 清空，1 = 直，2 = 波浪，3 = 乱
func _stamp_preset(kind: int) -> void:
	_undo = mask.duplicate() as Image
	mask.fill(Color(0, 0, 0, 1))
	if kind > 0:
		var soft := 3
		for x in IW:
			var u := float(x) / float(IW - 1)
			var b := 0.48
			if kind == 1:
				b = 0.46 + sin(u * 6.0) * 0.015
			elif kind == 2:
				b = 0.44 + sin(u * TAU * 2.2) * 0.10 + sin(u * TAU * 5.3) * 0.025
			else:
				b = 0.40 + sin(u * TAU * 1.3) * 0.09 + sin(u * TAU * 4.1) * 0.055
			var yb := clampi(int(b * float(IH)), 2, IH - 2)
			mask.fill_rect(Rect2i(x, 0, 1, yb), Color(1, 1, 1, 1))
			for k in soft:
				var yy := yb + k
				if yy < IH:
					mask.set_pixel(x, yy, Color(1.0 - float(k) / float(soft), 0, 0, 1))
	_dirty = true
	queue_redraw()


func _layout_paper() -> void:
	var area := Rect2(Vector2(40, 90), size - Vector2(80, 160))
	var aspect := float(IW) / float(IH)
	var w := area.size.x
	var hh := w / aspect
	if hh > area.size.y:
		hh = area.size.y
		w = hh * aspect
	if w < 0.0:
		w = 0.0
	if hh < 0.0:
		hh = 0.0
	_paper = Rect2(area.position + (area.size - Vector2(w, hh)) * 0.5, Vector2(w, hh))


func _process(_dt: float) -> void:
	_layout_paper()
	if _preview:
		_preview.position = _paper.position
		_preview.size = _paper.size
	if _dirty:
		_dirty = false
		if tex:
			tex.update(mask)
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.11, 0.10, 0.55))
	draw_rect(_paper.grow(6), Color(0, 0, 0, 0.12))
	draw_rect(_paper, Color("6b6a63"))
	draw_rect(_paper, Color("c9bda0"), false, 2.0)
	if _paper.size.x > 0.0 and _paper.size.y > 0.0:
		var f := UIKit.ensure_font()
		draw_string(f, _paper.position + Vector2(8, -8), "刀背（这里覆厚土）",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Palette.UI_TEXT)
		draw_string(f, _paper.position + Vector2(8, _paper.size.y + 22), "刀刃（这里留空，保持裸露）",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Palette.UI_TEXT)
		if _paper.has_point(_cursor):
			draw_arc(_cursor, brush * (_paper.size.x / float(IW)), 0.0, TAU, 24,
				Color(1.0, 0.85, 0.5, 0.85), 2.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_cursor = event.position
		queue_redraw()
		if _painting:
			_paint_line(_last, event.position)
			_last = event.position
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if _paper.size.x > 0.0 and _paper.has_point(mb.position):
					_undo = mask.duplicate() as Image
					_painting = true
					_last = mb.position
					_paint_line(mb.position, mb.position)
					accept_event()
			else:
				_painting = false
				accept_event()


func _to_img(p: Vector2) -> Vector2:
	return Vector2(
		(p.x - _paper.position.x) / maxf(_paper.size.x, 1.0) * float(IW),
		(p.y - _paper.position.y) / maxf(_paper.size.y, 1.0) * float(IH))


func _paint_line(a: Vector2, b: Vector2) -> void:
	var ia := _to_img(a)
	var ib := _to_img(b)
	var n := maxi(1, int(ia.distance_to(ib) / maxf(brush * 0.25, 1.5)))
	for i in n + 1:
		_dab(ia.lerp(ib, float(i) / float(n)))
	_dirty = true


func _dab(c: Vector2) -> void:
	var r := brush
	var x0 := clampi(int(c.x - r), 0, IW - 1)
	var x1 := clampi(int(c.x + r) + 1, 0, IW)
	var y0 := clampi(int(c.y - r), 0, IH - 1)
	var y1 := clampi(int(c.y + r) + 1, 0, IH)
	var r2 := r * r
	for y in range(y0, y1):
		for x in range(x0, x1):
			var dx := float(x) - c.x
			var dy := float(y) - c.y
			var d2 := dx * dx + dy * dy
			if d2 > r2:
				continue
			var a := 1.0 - sqrt(d2) / r
			if erasing:
				mask.set_pixel(x, y, Color(0, 0, 0, 1))
			else:
				var cur := mask.get_pixel(x, y)
				mask.set_pixel(x, y, Color(minf(1.0, cur.r + a * 0.55), 0, 0, 1))


func _on_accept() -> void:
	var spine := 0.0
	var edge := 0.0
	var ns := 0
	var ne := 0
	for y in range(0, IH, 3):
		var v := float(y) / float(IH - 1)
		for x in range(0, IW, 3):
			var c := mask.get_pixel(x, y).r
			if v < 0.30:
				spine += c
				ns += 1
			elif v > 0.72:
				edge += c
				ne += 1
	spine = spine / float(maxi(ns, 1))
	edge = edge / float(maxi(ne, 1))
	accepted.emit(mask.duplicate() as Image, spine, edge)
