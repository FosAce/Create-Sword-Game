class_name CarveCanvas
extends Control
## 刀柄雕刻：平面展开图上的"画画"。R 通道 = 雕刻深度，G 通道 = 填漆/镶嵌。
## 画的东西会实时同时出现在 2D 预览和 3D 刀柄上（共用同一张高度图）。

signal accepted(img: Image, cover: float, ink: float)
signal cancelled()

var IW := 320
var IH := 480

enum Mode { CARVE, INLAY, ERASE }

var mask: Image
var tex: ImageTexture
var preview_mat: ShaderMaterial
var brush: float = 9.0
var mode: int = Mode.CARVE
var face_mode := false
var inlay_idx: int = 0
const INLAY_NAMES := ["金", "银", "钻石", "铜", "黑漆", "朱漆"]
var _inlay_opt: OptionButton
var strength: float = 0.8
var mirror: bool = false
var wood_index: int = 0

var _paper := Rect2()
var _preview: ColorRect
var _undo: Image = null
var _painting := false
var _dirty := false
var _last := Vector2(-9999, -9999)
var _cursor := Vector2(-9999, -9999)
var _hint: Label
var _brush_slider: HSlider
var _strength_slider: HSlider


func _ready() -> void:
	if face_mode:
		IW = 512
		IH = 160
	mouse_filter = Control.MOUSE_FILTER_STOP
	mask = Image.create_empty(IW, IH, false, Image.FORMAT_RGBA8)
	mask.fill(Color(0, 0, 0, 1))
	tex = ImageTexture.create_from_image(mask)

	preview_mat = ShaderMaterial.new()
	preview_mat.shader = load("res://shaders/carve_preview.gdshader")
	preview_mat.set_shader_parameter("carve_tex", tex)

	_preview = ColorRect.new()
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.material = preview_mat
	_preview.color = Color.WHITE
	add_child(_preview)

	_build_toolbar()
	set_wood(wood_index)


## 刃面模式：把预览换成钢铁色
func set_steel() -> void:
	if preview_mat == null:
		return
	preview_mat.set_shader_parameter("wood_dark", Color("7c848d"))
	preview_mat.set_shader_parameter("wood_light", Color("dfe6ec"))
	preview_mat.set_shader_parameter("grain_scale", 3.0)


func set_wood(index: int) -> void:
	wood_index = index
	if preview_mat == null:
		return
	var w := HandleBuilder.wood(index)
	preview_mat.set_shader_parameter("wood_dark", w["dark"])
	preview_mat.set_shader_parameter("wood_light", w["light"])


func _build_toolbar() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UIKit.sb(Color("f6efdd"), 12, 2, Color(0, 0, 0, 0.05)))
	bar.anchor_right = 1.0
	bar.offset_bottom = 56
	add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	bar.add_child(h)

	var carve_btn := UIKit.button("雕刻刀")
	carve_btn.toggle_mode = true
	carve_btn.button_pressed = true
	carve_btn.toggled.connect(func(on: bool) -> void:
		if on:
			mode = Mode.CARVE)
	h.add_child(carve_btn)

	var ink_btn := UIKit.button("填漆")
	ink_btn.toggle_mode = true
	ink_btn.toggled.connect(func(on: bool) -> void:
		if on:
			mode = Mode.INLAY)
	h.add_child(ink_btn)

	var er_btn := UIKit.button("修掉")
	er_btn.toggle_mode = true
	er_btn.toggled.connect(func(on: bool) -> void:
		if on:
			mode = Mode.ERASE)
	h.add_child(er_btn)

	h.add_child(UIKit.label("刀宽", 14, Palette.UI_DIM))
	_brush_slider = UIKit.slider(4.0, 24.0, 1.0, brush)
	_brush_slider.custom_minimum_size = Vector2(110, 26)
	_brush_slider.value_changed.connect(func(v: float) -> void: brush = v)
	h.add_child(_brush_slider)

	h.add_child(UIKit.label("力度", 14, Palette.UI_DIM))
	_strength_slider = UIKit.slider(0.2, 1.0, 0.05, strength)
	_strength_slider.custom_minimum_size = Vector2(90, 26)
	_strength_slider.value_changed.connect(func(v: float) -> void: strength = v)
	h.add_child(_strength_slider)

	var mir := UIKit.button("镜像")
	mir.toggle_mode = true
	mir.toggled.connect(func(on: bool) -> void: mirror = on)
	h.add_child(mir)

	# 镶嵌材料（画笔颜色）：金 / 银 / 钻石 / 铜 / 黑漆 / 朱漆
	h.add_child(UIKit.label("镶嵌", 14, Palette.UI_DIM))
	_inlay_opt = OptionButton.new()
	for n in INLAY_NAMES:
		_inlay_opt.add_item(n)
	_inlay_opt.selected = inlay_idx
	UIKit.apply_font(_inlay_opt)
	_inlay_opt.custom_minimum_size = Vector2(96, 30)
	_inlay_opt.item_selected.connect(func(i: int) -> void:
		inlay_idx = i
		if _hint:
			_hint.text = "填漆模式：%s —— 在刻好的凹槽里填这个颜色。" % INLAY_NAMES[i])
	h.add_child(_inlay_opt)

	var undo := UIKit.button("撤销")
	undo.pressed.connect(func() -> void:
		if _undo != null:
			mask = _undo.duplicate() as Image
			_undo = null
			_dirty = true)
	h.add_child(undo)

	var clear := UIKit.button("刮平")
	clear.pressed.connect(func() -> void:
		_undo = mask.duplicate() as Image
		mask.fill(Color(0, 0, 0, 1))
		_dirty = true)
	h.add_child(clear)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	if face_mode:
		var tpl := OptionButton.new()
		tpl.add_item("画板模板 ▾")
		for nm2 in ["矩形", "椭圆", "盾形", "波浪"]:
			tpl.add_item(nm2)
		UIKit.apply_font(tpl)
		tpl.custom_minimum_size = Vector2(118, 30)
		tpl.item_selected.connect(func(i: int) -> void:
			if i > 0:
				stamp_template(i))
		h.add_child(tpl)

	var back := UIKit.button("放弃")
	back.pressed.connect(func() -> void: cancelled.emit())
	h.add_child(back)

	var ok := UIKit.button("完成刃面 ▶" if face_mode else "装柄完成 ▶", true)
	ok.pressed.connect(_on_accept)
	h.add_child(ok)

	_hint = UIKit.label("在木料展开图上直接画——曲线会绕到刀柄背面。", 15, Palette.UI_ACCENT2)
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_top = -28
	_hint.offset_left = 8
	add_child(_hint)


func _layout_paper() -> void:
	var area := Rect2(Vector2(40, 70), size - Vector2(80, 110))
	var aspect := float(IW) / float(IH)
	var hh := area.size.y
	var w := hh * aspect
	if w > area.size.x:
		w = area.size.x
		hh = w / aspect
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
	draw_rect(_paper, Color("6b4a2e"))
	draw_rect(_paper, Color("c9bda0"), false, 2.0)
	# 展开图上的中缝提示
	draw_line(Vector2(_paper.position.x + _paper.size.x * 0.5, _paper.position.y),
		Vector2(_paper.position.x + _paper.size.x * 0.5, _paper.end.y),
		Color(1, 1, 1, 0.10), 1.0)
	if _paper.size.x > 0.0 and _paper.size.y > 0.0 and _paper.has_point(_cursor):
		draw_arc(_cursor, brush * (_paper.size.x / float(IW)), 0.0, TAU, 24,
			Color(1.0, 0.92, 0.65, 0.8), 2.0)


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
		var t := float(i) / float(n)
		_dab(ia.lerp(ib, t))
	_dirty = true


func _dab(c: Vector2) -> void:
	_stamp(c)
	if mirror:
		_stamp(Vector2(IW - c.x, c.y))


func _stamp(c: Vector2) -> void:
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
			var col := mask.get_pixel(x, y)
			match mode:
				Mode.CARVE:
					col.r = minf(1.0, col.r + strength * a * 0.6)
				Mode.INLAY:
					col.g = minf(1.0, col.g + a * 0.95)
					col.r = minf(1.0, col.r + a * 0.22)
					# B 通道记录这块是哪种镶嵌材料
					col.b = float(inlay_idx) / 8.0
				Mode.ERASE:
					col.r = maxf(0.0, col.r - a)
					col.g = maxf(0.0, col.g - a)
			mask.set_pixel(x, y, col)


## 刃面画板的形状模板：一次性铺出「面板底 + 金框」
func stamp_template(kind: int) -> void:
	if not face_mode:
		return
	var cx := float(IW) * 0.5
	var cy := float(IH) * 0.5
	var rx := float(IW) * 0.42
	var ry := float(IH) * 0.40
	for y in IH:
		for x in IW:
			var dx := (float(x) - cx) / rx
			var dy := (float(y) - cy) / ry
			var d := 0.0
			match kind:
				1:
					d = maxf(absf(dx), absf(dy))                     # 矩形
				2:
					d = sqrt(dx * dx + dy * dy)                      # 椭圆
				3:
					dx *= 1.0 + dy * 0.35                            # 盾形（下窄）
					d = sqrt(dx * dx + dy * dy)
				4:
					var wob := 1.0 + 0.14 * sin(dy * 9.0)            # 波浪边
					d = sqrt(dx * dx * wob + dy * dy)
				_:
					return
			if d < 1.0:
				mask.set_pixel(x, y, Color(0.34, 0.0, float(inlay_idx) / 8.0, 1.0))
			elif d < 1.06:
				mask.set_pixel(x, y, Color(0.48, 1.0, 0.0, 1.0))
	_dirty = true
	_undo = null

func _on_accept() -> void:
	var cover := 0.0
	var ink := 0.0
	var total := float(IW * IH)
	for y in range(0, IH, 2):
		for x in range(0, IW, 2):
			var col := mask.get_pixel(x, y)
			if col.r > 0.15:
				cover += 1.0
			if col.g > 0.4:
				ink += 1.0
	cover = cover / (total * 0.25)
	ink = ink / (total * 0.25)
	accepted.emit(mask.duplicate() as Image, cover, ink)
