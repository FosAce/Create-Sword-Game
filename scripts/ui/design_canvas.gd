class_name DesignCanvas
extends Control
## ★ 设计图纸：玩家像在纸上画画一样画出刀身轮廓。
## 点"完成设计"后，像素被追踪成轮廓 → 生成 3D 刀身。
## 这是整个游戏"自由度"的核心。

signal accepted(outline: PackedVector2Array)
signal cancelled()

const IW := 1000
const IH := 380

var mask: Image
var tex: ImageTexture
var brush: float = 26.0
var erasing: bool = false
var mirror: bool = false
var guide: PackedVector2Array = PackedVector2Array()
var status: String = ""

var _paper := Rect2(0, 0, 100, 100)
var _painting := false
var _last := Vector2(-9999, -9999)
var _undo: Image = null
var _dirty := false
var _cursor := Vector2(-9999, -9999)
var _brush_img: Image = null
var _brush_r := 0
var _status_label: Label
var _brush_slider: HSlider
var _erase_btn: Button
var _mirror_btn: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mask = Image.create_empty(IW, IH, false, Image.FORMAT_RGBA8)
	mask.fill(Color(1, 1, 1, 0))
	tex = ImageTexture.create_from_image(mask)
	_build_toolbar()


func _build_toolbar() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UIKit.sb(Color("f6efdd"), 12, 2, Color(0, 0, 0, 0.05)))
	bar.position = Vector2(0, 0)
	bar.size = Vector2(0, 56)
	bar.anchor_right = 1.0
	bar.offset_bottom = 56
	add_child(bar)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	bar.add_child(h)

	h.add_child(UIKit.label("笔刷", 15, Palette.UI_DIM))
	_brush_slider = UIKit.slider(6.0, 56.0, 1.0, brush)
	_brush_slider.custom_minimum_size = Vector2(150, 26)
	_brush_slider.value_changed.connect(func(v: float) -> void:
		brush = v
		queue_redraw())
	h.add_child(_brush_slider)

	_erase_btn = UIKit.button("橡皮")
	_erase_btn.toggle_mode = true
	_erase_btn.toggled.connect(func(on: bool) -> void:
		erasing = on
		if on:
			_mirror_btn.button_pressed = false
			mirror = false)
	h.add_child(_erase_btn)

	_mirror_btn = UIKit.button("上下镜像")
	_mirror_btn.toggle_mode = true
	_mirror_btn.toggled.connect(func(on: bool) -> void: mirror = on)
	h.add_child(_mirror_btn)

	var undo_btn := UIKit.button("撤销")
	undo_btn.pressed.connect(func() -> void: _do_undo())
	h.add_child(undo_btn)

	var clear_btn := UIKit.button("清空")
	clear_btn.pressed.connect(func() -> void:
		_push_undo()
		mask.fill(Color(1, 1, 1, 0))
		guide = PackedVector2Array()
		_dirty = true)
	h.add_child(clear_btn)

	var fit_btn := UIKit.button("描摹预设")
	fit_btn.pressed.connect(func() -> void: _trace_default_guide())
	h.add_child(fit_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)

	var cancel := UIKit.button("放弃")
	cancel.pressed.connect(func() -> void: cancelled.emit())
	h.add_child(cancel)

	var ok := UIKit.button("完成设计 ▶", true)
	ok.pressed.connect(_on_accept)
	h.add_child(ok)

	_status_label = UIKit.label("", 15, Palette.UI_ACCENT2)
	_status_label.anchor_top = 1.0
	_status_label.anchor_bottom = 1.0
	_status_label.offset_top = -30
	_status_label.offset_left = 8
	add_child(_status_label)


func _trace_default_guide() -> void:
	var presets := ContourTrace.preset_outlines()
	guide = presets[3]["pts"]
	status = "照着灰线描一遍试试（也可以完全自己画）"
	if _status_label:
		_status_label.text = status
	queue_redraw()


## 供外部切换预设灰线
func set_guide(points: PackedVector2Array) -> void:
	guide = points
	status = "描摹中：照着虚线画完，再点完成设计"
	if _status_label:
		_status_label.text = status
	queue_redraw()


func clear_all() -> void:
	mask.fill(Color(1, 1, 1, 0))
	guide = PackedVector2Array()
	_dirty = true


func _process(_dt: float) -> void:
	if _dirty:
		_dirty = false
		if tex:
			tex.update(mask)
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.11, 0.10, 0.55))
	# 计算纸张区域（画布中心，保持 1000:380 比例）
	var area := Rect2(Vector2(40, 70), size - Vector2(80, 110))
	var aspect := float(IW) / float(IH)
	var w := area.size.x
	var hh := w / aspect
	if hh > area.size.y:
		hh = area.size.y
		w = hh * aspect
	_paper = Rect2(area.position + (area.size - Vector2(w, hh)) * 0.5, Vector2(w, hh))

	draw_rect(_paper.grow(6), Color(0, 0, 0, 0.10))
	draw_rect(_paper, Color("fbf6e8"))
	# 格线
	var grid := Color(0, 0, 0, 0.045)
	var gx := 10
	for i in range(1, gx):
		var x := _paper.position.x + _paper.size.x * float(i) / float(gx)
		draw_line(Vector2(x, _paper.position.y), Vector2(x, _paper.end.y), grid, 1.0)
	for i in range(1, 5):
		var y := _paper.position.y + _paper.size.y * float(i) / 5.0
		draw_line(Vector2(_paper.position.x, y), Vector2(_paper.end.x, y), grid, 1.0)
	# 中心线（刀身轴线）
	draw_line(Vector2(_paper.position.x, _paper.position.y + _paper.size.y * 0.5),
		Vector2(_paper.end.x, _paper.position.y + _paper.size.y * 0.5),
		Color(0.85, 0.45, 0.3, 0.25), 1.0)
	draw_rect(_paper, Color("c9bda0"), false, 2.0)

	# 灰线引导
	if guide.size() > 2:
		var pts := PackedVector2Array()
		var sc := _paper.size.x * 0.92
		for p in guide:
			pts.append(Vector2(_paper.position.x + _paper.size.x * 0.5 + p.x * sc,
				_paper.position.y + _paper.size.y * 0.5 + p.y * sc))
		pts.append(pts[0])
		draw_polyline(pts, Color(0.45, 0.55, 0.62, 0.35), 2.0)

	# 玩家画的
	if tex:
		draw_texture_rect(tex, _paper, false, Color(0.32, 0.30, 0.27, 1.0))

	# 笔刷光标
	if _paper.size.x > 0.0 and _paper.size.y > 0.0 and _paper.has_point(_cursor):
		draw_arc(_cursor, brush * (_paper.size.x / float(IW)), 0.0, TAU, 28,
			Color(0.9, 0.35, 0.2, 0.75), 2.0)


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
					_push_undo()
					_painting = true
					_last = mb.position
					_paint_line(mb.position, mb.position)
					accept_event()
			else:
				_painting = false
				accept_event()


func _to_img(p: Vector2) -> Vector2:
	# 注意：x/y 必须各自用自己的边长归一化，否则纵向会被压扁
	return Vector2(
		(p.x - _paper.position.x) / maxf(_paper.size.x, 1.0) * float(IW),
		(p.y - _paper.position.y) / maxf(_paper.size.y, 1.0) * float(IH))


func _paint_line(a: Vector2, b: Vector2) -> void:
	var ia := _to_img(a)
	var ib := _to_img(b)
	var dist := ia.distance_to(ib)
	# 步长要远小于笔尖半径，笔迹才会连成片而不是一串圆圈
	var step := maxf(brush * 0.10, 1.2)
	var n := maxi(1, int(dist / step))
	for i in n + 1:
		var t := float(i) / float(n)
		_paint_dab(ia.lerp(ib, t))
	_dirty = true


func _paint_dab(c: Vector2) -> void:
	_stamp(c)
	if mirror:
		_stamp(Vector2(c.x, IH - c.y))


## 预生成一支"软笔尖"：中心实、边缘渐隐，用 blend_rect 叠上去
func _ensure_brush() -> void:
	var r := clampi(int(brush), 2, 128)
	if _brush_img != null and r == _brush_r:
		return
	_brush_r = r
	var s := r * 2 + 1
	_brush_img = Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	_brush_img.fill(Color(1, 1, 1, 0))
	for y in s:
		for x in s:
			var dx := float(x) - float(r)
			var dy := float(y) - float(r)
			var d := sqrt(dx * dx + dy * dy) / float(r)
			if d >= 1.0:
				continue
			# 中间 60% 实心，之后平滑收边 —— 像毛笔/水笔
			var a := 1.0 - smoothstep(0.60, 1.0, d)
			_brush_img.set_pixel(x, y, Color(1, 1, 1, a * 0.50))


func _stamp(c: Vector2) -> void:
	_ensure_brush()
	var sz := _brush_img.get_size()
	var dst := Vector2i(int(round(c.x)) - _brush_r, int(round(c.y)) - _brush_r)
	var dst_rect := Rect2i(dst, sz)
	var clip := dst_rect.intersection(Rect2i(0, 0, IW, IH))
	if clip.size.x <= 0 or clip.size.y <= 0:
		return
	if not erasing:
		var src_rect := Rect2i(clip.position - dst, clip.size)
		mask.blend_rect(_brush_img, src_rect, clip.position)
		return
	# 橡皮：按笔尖强度扣 alpha（隔行采样，够快也看不出方格）
	for y in range(clip.position.y, clip.end.y, 2):
		for x in range(clip.position.x, clip.end.x, 2):
			var s := _brush_img.get_pixel(x - dst.x, y - dst.y).a
			if s <= 0.01:
				continue
			var cur := mask.get_pixel(x, y)
			cur.a = maxf(0.0, cur.a - s * 2.2)
			mask.set_pixel(x, y, cur)


func _push_undo() -> void:
	_undo = mask.duplicate() as Image


func _do_undo() -> void:
	if _undo != null:
		mask = _undo.duplicate() as Image
		_undo = null
		_dirty = true


func _on_accept() -> void:
	var outline := ContourTrace.mask_to_outline(mask, 1.8)
	if outline.size() < 4:
		status = "还没画出个形状来 —— 画一条闭合的刀身轮廓吧"
		if _status_label:
			_status_label.text = status
		return
	var bb := Rect2(outline[0], Vector2.ZERO)
	for p in outline:
		bb = bb.expand(p)
	if bb.size.y < 0.01:
		status = "太细了，画粗一点"
		if _status_label:
			_status_label.text = status
		return
	accepted.emit(outline)


## 把一条轮廓光栅化回蒙版（暂不使用：返回上一步时画布实例会保留原图）
func rasterize(poly: PackedVector2Array) -> void:
	if poly.size() < 3:
		return
	mask.fill(Color(1, 1, 1, 0))
	var sc := 0.92
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var pa := Vector2(IW * 0.5 + a.x * sc * float(IW) * 0.5,
			IH * 0.5 + a.y * sc * float(IW) * 0.5)
		var pb := Vector2(IW * 0.5 + b.x * sc * float(IW) * 0.5,
			IH * 0.5 + b.y * sc * float(IW) * 0.5)
		var steps := maxi(2, int(pa.distance_to(pb) / 3.0))
		for s in steps:
			_paint_dab(pa.lerp(pb, float(s) / float(steps)))
	_dirty = true
	queue_redraw()
