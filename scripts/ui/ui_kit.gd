class_name UIKit
extends RefCounted
## 一套极简的"纸感"UI 组件，保证所有面板/按钮风格统一。

static var _font: Font = null


## 中文字体：Godot 内置默认字体没有 CJK 字形，必须显式指定系统字体
static func ensure_font() -> Font:
	if _font != null:
		return _font
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "SimSun",
		"Noto Sans CJK SC", "Source Han Sans SC", "PingFang SC", "sans-serif"
	])
	_font = sf
	return _font


static func apply_font(c: Control) -> void:
	if c != null:
		c.add_theme_font_override("font", ensure_font())


static func sb(color: Color, radius: int = 10, border: int = 0,
		border_color: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	if border > 0:
		s.set_border_width_all(border)
		s.border_color = border_color
	s.set_content_margin_all(8)
	return s


static func label(text: String, size: int = 17, col: Color = Palette.UI_TEXT,
		wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", ensure_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func title(text: String, size: int = 26) -> Label:
	var l := label(text, size, Palette.UI_TEXT)
	l.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


static func button(text: String, accent: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	var base := Palette.UI_ACCENT if accent else Color("eae3d0")
	var hover := Palette.UI_ACCENT.lightened(0.12) if accent else Color("f2ecdb")
	var press := Palette.UI_ACCENT.darkened(0.12) if accent else Color("dcd4bd")
	b.add_theme_stylebox_override("normal", sb(base, 9))
	b.add_theme_stylebox_override("hover", sb(hover, 9))
	b.add_theme_stylebox_override("pressed", sb(press, 9))
	b.add_theme_stylebox_override("disabled", sb(Color("ddd8c9"), 9))
	b.add_theme_stylebox_override("focus", sb(Color(0, 0, 0, 0), 9))
	var fg := Color.WHITE if accent else Palette.UI_TEXT
	b.add_theme_font_override("font", ensure_font())
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", Palette.UI_DIM)
	b.add_theme_font_size_override("font_size", 17)
	b.custom_minimum_size = Vector2(0, 38)
	return b


static func panel(color: Color = Palette.UI_PANEL, radius: int = 16) -> PanelContainer:
	var p := PanelContainer.new()
	var s := sb(color, radius, 2, Color(0, 0, 0, 0.06))
	s.set_content_margin_all(14)
	p.add_theme_stylebox_override("panel", s)
	return p


static func slider(min_v: float, max_v: float, step_v: float, value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step_v
	s.value = value
	s.custom_minimum_size = Vector2(0, 26)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s


static func option(items: Array) -> OptionButton:
	var o := OptionButton.new()
	for i in items.size():
		o.add_item(str(items[i]), i)
	o.custom_minimum_size = Vector2(0, 36)
	o.add_theme_font_override("font", ensure_font())
	o.add_theme_font_size_override("font_size", 16)
	o.add_theme_stylebox_override("normal", sb(Color("eae3d0"), 9))
	o.add_theme_stylebox_override("hover", sb(Color("f2ecdb"), 9))
	o.add_theme_stylebox_override("pressed", sb(Color("dcd4bd"), 9))
	o.add_theme_stylebox_override("focus", sb(Color(0, 0, 0, 0), 9))
	o.add_theme_stylebox_override("disabled", sb(Color("ddd8c9"), 9))
	o.add_theme_color_override("font_color", Palette.UI_TEXT)
	o.add_theme_color_override("font_hover_color", Palette.UI_TEXT)
	o.add_theme_color_override("font_pressed_color", Palette.UI_TEXT)
	o.add_theme_color_override("font_focus_color", Palette.UI_TEXT)
	var pop := o.get_popup()
	if pop:
		pop.add_theme_stylebox_override("panel", sb(Color("f7f1e0"), 8, 2, Color(0, 0, 0, 0.10)))
		pop.add_theme_stylebox_override("hover", sb(Palette.UI_ACCENT, 6))
		pop.add_theme_font_override("font", ensure_font())
		pop.add_theme_font_size_override("font_size", 16)
		pop.add_theme_color_override("font_color", Palette.UI_TEXT)
		pop.add_theme_color_override("font_hover_color", Color.WHITE)
	return o


static func row(children: Array, sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	for c in children:
		h.add_child(c)
	return h


static func col(children: Array, sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	for c in children:
		v.add_child(c)
	return v


static func gap(h: int = 10) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


## 一条"数值条"：用于展示硬度/韧性/花纹等
static func stat_bar(name: String, value: float, col: Color,
		width: float = 240.0) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var head := HBoxContainer.new()
	var nl := label(name, 14, Palette.UI_DIM)
	nl.custom_minimum_size = Vector2(96, 0)
	var vl := label("%d%%" % int(clampf(value, 0.0, 1.0) * 100.0), 14, Palette.UI_TEXT)
	head.add_child(nl)
	head.add_child(vl)
	v.add_child(head)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = clampf(value, 0.0, 1.0)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(width, 10)
	var bg := sb(Color("ded6c2"), 5)
	var fg := sb(col, 5)
	fg.set_content_margin_all(0)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	v.add_child(bar)
	return v
