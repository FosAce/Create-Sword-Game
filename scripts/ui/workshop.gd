class_name Workshop
extends Control
## 铁匠铺工作台：9 道工序。左边是工序表与实时数据，中间是 3D 实时预览，
## 右边是当前工序的旋钮。所有选择都会立刻反映到刀上。

signal finished()
signal closed()

const STEPS := [
	{"name": "① 选料 · 叠层", "hint": "两种不同的钢叠在一起，就是花纹钢的起点。层数决定花纹的疏密。"},
	{"name": "② 折叠 · 锻合", "hint": "撒硼砂、烧到 1200℃ 上下、锤打让两片钢真正长成一块。温度不对就锻不上。"},
	{"name": "③ 扭转", "hint": "把层叠的坯料扭成麻花再磨平，层理就变成人字纹/斜纹。"},
	{"name": "④ 设计图", "hint": "画出你要的刀身形状 —— 这是唯一不会和别人重复的东西。"},
	{"name": "⑤ 锤打成型", "hint": "把方坯打成图纸上的形状。锤点越准，刀身越接近图纸。"},
	{"name": "⑥ 淬火 · 回火", "hint": "加热到奥氏体化温度后急冷，钢才变硬。先覆土烧刃可以只硬刃口、留一条软刀背。"},
	{"name": "⑦ 研磨 · 酸洗", "hint": "磨到平整，再用三氯化铁咬一层：高碳层变暗、镍钢保持银白，花纹就浮出来了。"},
	{"name": "⑧ 装柄", "hint": "挑木料、挑柄型，然后在柄上刻下你自己的图案。"},
	{"name": "⑨ 成品", "hint": "给它取个名字，挂到武器架上。"}
]

var sword: SwordData

var _step := 0
var _step_labels: Array[Label] = []
var _controls: VBoxContainer
var _step_title: Label
var _step_hint: Label
var _stat_label: Label
var _pattern_bar: Control
var _hard_bar: Control
var _tough_bar: Control
var _next_btn: Button
var _prev_btn: Button
var _preview_note: Label

var _svp: SubViewport
var _assembly: Node3D
var _blade_mat: ShaderMaterial
var _handle_mat: ShaderMaterial
var _face_tex: ImageTexture
var _carve_tex: ImageTexture
var _cam: Camera3D
var _focus := 0
var _spin := 0.0
var _time := 0.0

var _overlay: Control
var _card: PanelContainer
var _center: CenterContainer
var _clay_tex: ImageTexture
var _clay: ClayCanvas
var _forge: ForgeCanvas
var _design: DesignCanvas
var _carve: CarveCanvas
var _hammer: HammerGame
var _name_edit: LineEdit
var _rng_seed := 12345
var _published := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sword = SwordData.new()
	sword.outline = ContourTrace.preset_outlines()[0]["pts"]
	sword.design_source = "preset:0"
	_build_shell()
	_build_overlay()
	_goto(0)


# =========================================================
#  界面骨架
# =========================================================
func _build_shell() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.12, 0.11, 0.10, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_center = center

	var card := UIKit.panel(Color("f7f1e0"), 18)
	card.custom_minimum_size = Vector2(1470, 810)
	center.add_child(card)
	_card = card

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	card.add_child(hb)

	# ---------- 左：工序表 ----------
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.custom_minimum_size = Vector2(250, 0)
	hb.add_child(left)
	left.add_child(UIKit.title("锻 刀 大 赛", 24))
	left.add_child(UIKit.label("铁匠铺 · 工序", 14, Palette.UI_DIM))
	left.add_child(UIKit.gap(6))
	for i in STEPS.size():
		var l := UIKit.label(STEPS[i]["name"], 15, Palette.UI_DIM)
		l.custom_minimum_size = Vector2(0, 24)
		left.add_child(l)
		_step_labels.append(l)
	left.add_child(UIKit.gap(10))
	left.add_child(UIKit.label("刀 况", 15, Palette.UI_DIM))
	_stat_label = UIKit.label("", 14, Palette.UI_TEXT)
	_stat_label.custom_minimum_size = Vector2(230, 120)
	left.add_child(_stat_label)
	_pattern_bar = UIKit.stat_bar("花纹显现", 0.0, Palette.UI_ACCENT2, 210)
	_hard_bar = UIKit.stat_bar("硬度", 0.0, Palette.UI_ACCENT, 210)
	_tough_bar = UIKit.stat_bar("韧性", 0.0, Color("6b9e5a"), 210)
	left.add_child(_pattern_bar)
	left.add_child(_hard_bar)
	left.add_child(_tough_bar)
	var quit := UIKit.button("离开铁匠铺")
	quit.pressed.connect(_on_quit)
	left.add_child(UIKit.gap(6))
	left.add_child(quit)

	# ---------- 中：3D 预览 ----------
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 8)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(mid)
	var svc := SubViewportContainer.new()
	svc.custom_minimum_size = Vector2(720, 540)
	svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	svc.stretch = true
	mid.add_child(svc)
	_svp = SubViewport.new()
	_svp.own_world_3d = true
	_svp.msaa_3d = Viewport.MSAA_4X
	_svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(_svp)
	_build_preview_scene()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	mid.add_child(row)
	var zoom_btn := UIKit.button("花纹特写 / 整体")
	zoom_btn.pressed.connect(func() -> void: _focus = 1 - _focus)
	row.add_child(zoom_btn)
	_preview_note = UIKit.label("", 14, Palette.UI_DIM)
	row.add_child(_preview_note)

	# ---------- 右：当前工序 ----------
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.custom_minimum_size = Vector2(360, 0)
	hb.add_child(right)
	_step_title = UIKit.title("", 21)
	right.add_child(_step_title)
	_step_hint = UIKit.label("", 15, Palette.UI_ACCENT2, true)
	_step_hint.custom_minimum_size = Vector2(340, 56)
	right.add_child(_step_hint)
	right.add_child(UIKit.gap(4))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(340, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_controls = VBoxContainer.new()
	_controls.add_theme_constant_override("separation", 8)
	_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_controls)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 10)
	right.add_child(nav)
	_prev_btn = UIKit.button("◀ 上一步")
	_prev_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prev_btn.pressed.connect(_on_prev)
	nav.add_child(_prev_btn)
	_next_btn = UIKit.button("下一步 ▶", true)
	_next_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next_btn.pressed.connect(_on_next)
	nav.add_child(_next_btn)


func _build_preview_scene() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("efe6d2")
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("fbf7ec")
	sky_mat.sky_horizon_color = Color("e6dcc6")
	sky_mat.ground_horizon_color = Color("cfc7b2")
	sky_mat.ground_bottom_color = Color("b8b1a0")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.sky = sky
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("fff3dd")
	e.ambient_light_energy = 0.50
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.55
	e.glow_bloom = 0.12
	e.glow_hdr_threshold = 0.95
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.environment = e
	_svp.add_child(env)

	var dl := DirectionalLight3D.new()
	dl.light_color = Color("fff6e8")
	dl.light_energy = 1.25
	dl.shadow_enabled = true
	dl.rotation_degrees = Vector3(-42, 38, 0)
	_svp.add_child(dl)

	var fill := DirectionalLight3D.new()
	fill.light_color = Color("bcd4e6")
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-18, -120, 0)
	_svp.add_child(fill)

	# 顶后方轮廓光：让刀身金属面有一道漂亮的反射光带
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("fff0d8")
	rim.light_energy = 1.30
	rim.rotation_degrees = Vector3(-72, 150, 0)
	_svp.add_child(rim)

	# 条光：掠射角照刃面，金属上会拉出一条长条高光（研磨光带）
	var strip := DirectionalLight3D.new()
	strip.light_color = Color("fff4e2")
	strip.light_energy = 0.85
	strip.shadow_enabled = false
	strip.rotation_degrees = Vector3(-84, 34, 0)
	_svp.add_child(strip)

	_cam = Camera3D.new()
	_cam.fov = 34.0
	_cam.position = Vector3(0.16, 0.62, 2.10)
	_svp.add_child(_cam)
	_cam.look_at(Vector3(0.02, 0.0, 0.0))

	_assembly = Node3D.new()
	_svp.add_child(_assembly)

	_blade_mat = ShaderMaterial.new()
	_blade_mat.shader = load("res://shaders/damascus.gdshader")
	_blade_mat.next_pass = MeshKit.outline_mat(0.0007)

	var blank := Image.create_empty(320, 480, false, Image.FORMAT_RGBA8)
	blank.fill(Color(0, 0, 0, 1))
	_carve_tex = ImageTexture.create_from_image(blank)
	var face_blank := Image.create_empty(512, 160, false, Image.FORMAT_RGBA8)
	face_blank.fill(Color(0, 0, 0, 1))
	_face_tex = ImageTexture.create_from_image(face_blank)
	if _blade_mat != null:
		_blade_mat.set_shader_parameter("face_tex", _face_tex)
	_handle_mat = ShaderMaterial.new()
	_handle_mat.shader = load("res://shaders/carve_wood.gdshader")
	_handle_mat.set_shader_parameter("carve_tex", _carve_tex)
	_handle_mat.next_pass = MeshKit.outline_mat(0.0007)
	set_wood_uniforms(0)


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.visible = false
	add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func set_wood_uniforms(index: int) -> void:
	var w := HandleBuilder.wood(index)
	_handle_mat.set_shader_parameter("wood_dark", w["dark"])
	_handle_mat.set_shader_parameter("wood_light", w["light"])


# =========================================================
#  外部接口
# =========================================================
func open() -> void:
	PlayerData.ensure_loaded()
	sword = SwordData.new()
	sword.outline = ContourTrace.preset_outlines()[0]["pts"]
	sword.design_source = "preset:0"
	sword.fidelity = 0.0
	_published = false
	_step = 0
	# 默认选一项手上有货的钢
	var owned := PlayerData.owned_ids()
	if not owned.is_empty():
		sword.core_id = owned[0]
		sword.alt_id = owned[mini(1, owned.size() - 1)]
	visible = true
	_goto(0)


func duplicate_assembly() -> Node3D:
	var n := _assembly.duplicate() as Node3D
	_deep_dup_material(n)
	return n


func _deep_dup_material(n: Node) -> void:
	var mi := n as MeshInstance3D
	if mi != null and mi.material_override != null:
		mi.material_override = mi.material_override.duplicate() as Material
	for c in n.get_children():
		_deep_dup_material(c)


func close() -> void:
	visible = false
	closed.emit()


# =========================================================
#  工序切换
# =========================================================
func _goto(i: int) -> void:
	_step = clampi(i, 0, STEPS.size() - 1)
	for k in _step_labels.size():
		var l := _step_labels[k]
		if k == _step:
			l.add_theme_color_override("font_color", Palette.UI_ACCENT)
			l.add_theme_font_size_override("font_size", 17)
		elif k < _step:
			l.add_theme_color_override("font_color", Palette.UI_TEXT)
			l.add_theme_font_size_override("font_size", 15)
		else:
			l.add_theme_color_override("font_color", Palette.UI_DIM)
			l.add_theme_font_size_override("font_size", 15)
	_step_title.text = STEPS[_step]["name"]
	_step_hint.text = STEPS[_step]["hint"]
	_prev_btn.disabled = _step == 0
	_next_btn.text = "完成锻造 ★" if _step == STEPS.size() - 1 else "下一步 ▶"
	_build_controls()
	_refresh()
	SoundKit.play("click", 1.0, -20.0)
	if _step == 5:
		SoundKit.play("hiss", 0.9, -18.0)


func _on_prev() -> void:
	if _step > 0:
		_goto(_step - 1)


func _on_next() -> void:
	if _step == 0 and not PlayerData.can_forge(sword.core_id, sword.alt_id):
		_step_hint.text = "原料不足：一把刀要消耗主钢 + 夹层钢各 1 份。去码头市场买料。"
		return
	if _step == 4 and sword.fidelity < 0.5:
		_step_hint.text = "还没锻打呢，先去锤几下。"
		return
	if _step == 3 and sword.outline.size() < 4:
		_step_hint.text = "先画一张设计图（或载入预设）再继续。"
		return
	if _step == STEPS.size() - 1:
		_finish()
		return
	_goto(_step + 1)


func _on_quit() -> void:
	close()


func _finish() -> void:
	if _published:
		return
	_published = true
	if _name_edit and _name_edit.text.strip_edges() != "":
		sword.sword_name = _name_edit.text.strip_edges()
	else:
		sword.sword_name = "无名刀"
	var r := ForgeSim.evaluate(sword)
	sword.final_score = r["total"]
	sword.score_breakdown = r
	_build_controls()
	_next_btn.disabled = true
	_refresh()

	# 抓一张 3D 预览当缩略图，然后存档
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var thumb: Image = null
	if _svp != null:
		var img := _svp.get_texture().get_image()
		if img != null and img.get_width() > 8:
			img.resize(480, 360, Image.INTERPOLATE_LANCZOS)
			thumb = img
	SaveSystem.save_sword(sword, thumb)
	# 消耗原料
	PlayerData.consume(sword.core_id, 1)
	if sword.alt_id != sword.core_id:
		PlayerData.consume(sword.alt_id, 1)
	SoundKit.play("chime", 1.0, -8.0)
	finished.emit()


# =========================================================
#  每道工序的控件
# =========================================================
func _build_controls() -> void:
	for c in _controls.get_children():
		_controls.remove_child(c)
		c.queue_free()
	_next_btn.disabled = false
	_name_edit = null
	match _step:
		0:
			_build_steel_controls()
		1:
			_build_fold_controls()
		2:
			_build_twist_controls()
		3:
			_build_design_controls()
		4:
			_build_hammer_controls()
		5:
			_build_heat_controls()
		6:
			_build_finish_controls()
		7:
			_build_handle_controls()
		8:
			_build_review_controls()


func _option_row(label_text: String, items: Array, selected: int, cb: Callable) -> void:
	_controls.add_child(UIKit.label(label_text, 14, Palette.UI_DIM))
	var o := UIKit.option(items)
	o.selected = clampi(selected, 0, maxi(0, items.size() - 1))
	o.item_selected.connect(cb)
	_controls.add_child(o)


func _fmt_val(v: float, st: float) -> String:
	if st >= 1.0:
		return "%d" % int(round(v))
	if st >= 0.1:
		return "%.1f" % v
	return "%.2f" % v


func _slider_row(label_text: String, mn: float, mx: float, st: float, v: float,
		cb: Callable) -> HSlider:
	var head := UIKit.label("%s：%s" % [label_text, _fmt_val(v, st)], 14, Palette.UI_DIM)
	_controls.add_child(head)
	var s := UIKit.slider(mn, mx, st, v)
	s.value_changed.connect(func(val: float) -> void:
		head.text = "%s：%s" % [label_text, _fmt_val(val, st)]
		cb.call(val))
	_controls.add_child(s)
	return s


func _build_steel_controls() -> void:
	PlayerData.ensure_loaded()
	var ids := PlayerData.owned_ids()
	var names: Array = []
	for id in ids:
		var st := SteelDB.get_steel(id)
		names.append("%s（存量 %d）" % [st["name"], PlayerData.count(id)])
	if names.is_empty():
		_controls.add_child(UIKit.label("手上一点钢坯都没有了 —— 去码头市场买料。",
			15, Palette.UI_ACCENT, true))
		return
	var ci := ids.find(sword.core_id)
	if ci < 0:
		ci = 0
		sword.core_id = ids[0]
	_option_row("主钢（决定硬度）", names, ci, func(i: int) -> void:
		sword.core_id = ids[i]
		_refresh())
	var ai := ids.find(sword.alt_id)
	if ai < 0:
		ai = mini(1, ids.size() - 1)
		sword.alt_id = ids[ai]
	_option_row("夹层钢（决定反差）", names, ai, func(i: int) -> void:
		sword.alt_id = ids[i]
		_refresh())
	_slider_row("初始叠层（块）", 3, 21, 2, sword.stack_layers, func(v: float) -> void:
		sword.stack_layers = int(v)
		_refresh())
	var info := UIKit.label("", 14, Palette.UI_TEXT)
	info.name = "SteelInfo"
	_controls.add_child(info)
	_controls.add_child(UIKit.label(
		"现实提示：15N20 含 2% 镍，抗酸洗腐蚀，是花纹钢里「亮层」的最佳选择；"
		+ "1095 / 1084 腐蚀快、变深灰，做「暗层」。两者叠在一起，反差最大。"
		+ "每把刀消耗主钢 + 夹层钢各 1 份。",
		14, Palette.UI_DIM, true))


func _build_fold_controls() -> void:
	_slider_row("折叠次数", 0, 6, 1, sword.folds, func(v: float) -> void:
		sword.folds = int(v)
		_refresh())
	_slider_row("锻接温度 (℃)", 980, 1320, 10, 1220.0, func(v: float) -> void:
		_weld_temp = v
		_refresh())
	var chk := CheckBox.new()
	chk.text = "撒硼砂（防氧化、助熔）"
	chk.button_pressed = true
	chk.toggled.connect(func(on: bool) -> void:
		_weld_flux = on
		_refresh())
	_controls.add_child(chk)
	var info := UIKit.label("", 14, Palette.UI_TEXT)
	info.name = "FoldInfo"
	_controls.add_child(info)
	_controls.add_child(UIKit.label(
		"每折一次层数翻倍。现实中超过 ~400 层后，氧化脱碳会让层界变糊，"
		+ "所以层数不是越多越好。", 14, Palette.UI_DIM, true))


var _weld_temp := 1220.0
var _weld_flux := true


func _build_twist_controls() -> void:
	_slider_row("扭转圈数", 0.0, 4.0, 0.25, sword.twist_turns, func(v: float) -> void:
		sword.twist_turns = v
		_refresh())
	var dir := UIKit.button("扭转方向：" + ("顺时针" if sword.twist_sign > 0 else "逆时针"))
	dir.pressed.connect(func() -> void:
		sword.twist_sign = -sword.twist_sign
		dir.text = "扭转方向：" + ("顺时针" if sword.twist_sign > 0 else "逆时针")
		_refresh())
	_controls.add_child(dir)
	_option_row("花纹样式", ["直纹", "扭转纹（人字）", "雨滴纹", "羽纹", "火焰纹",
		"梯纹（切锻）", "马赛克（罐锻）", "土耳其扭绞"],
		sword.pattern_style, func(i: int) -> void:
			sword.pattern_style = i
			_refresh())
	_controls.add_child(UIKit.label(
		"扭转纹是最经典的大马士革纹样。切锻（在坯料上剁槽再锻平）得到梯纹，"
		+ "碎料装罐锻合得到马赛克纹，几根方棒捆起来扭就是土耳其扭绞。",
		14, Palette.UI_DIM, true))


func _build_design_controls() -> void:
	var open_btn := UIKit.button("打开设计图纸", true)
	open_btn.pressed.connect(_open_design)
	_controls.add_child(open_btn)
	_controls.add_child(UIKit.gap(4))
	_controls.add_child(UIKit.label("预设剑身（也可以载入后继续改）", 14, Palette.UI_DIM, true))
	var presets := ContourTrace.preset_outlines()
	var names: Array = []
	for p in presets:
		names.append(p["name"])
	_option_row("预设", names, 0, func(i: int) -> void:
		sword.outline = presets[i]["pts"]
		sword.design_source = "preset:%d" % i
		_refresh())
	var info := UIKit.label("", 14, Palette.UI_TEXT)
	info.name = "DesignInfo"
	# ---- 横截面（P1）：中脊 / 血槽 / 刃角 / 二次斜面 ----
	_controls.add_child(UIKit.label("横截面", 15, Palette.UI_ACCENT2))
	_slider_row("中脊高度（0 平磨 → 1 起身）", 0.0, 1.0, 0.05, sword.xs_ridge, func(v: float) -> void:
		sword.xs_ridge = v
		_refresh())
	_slider_row("血槽宽度", 0.0, 1.0, 0.05, sword.xs_fuller_w, func(v: float) -> void:
		sword.xs_fuller_w = v
		_refresh())
	_slider_row("血槽深度", 0.0, 1.0, 0.05, sword.xs_fuller_d, func(v: float) -> void:
		sword.xs_fuller_d = v
		_refresh())
	_slider_row("刃口角度（小=薄刃，大=厚刃）", 0.0, 1.0, 0.05, sword.xs_edge_angle, func(v: float) -> void:
		sword.xs_edge_angle = v
		_refresh())
	_slider_row("二次斜面", 0.0, 1.0, 0.05, sword.xs_secondary, func(v: float) -> void:
		sword.xs_secondary = v
		_refresh())
	_controls.add_child(info)
	_controls.add_child(UIKit.label(
		"你画的是刀身的俯视轮廓：刀尖朝右。系统会自动判断哪一边是刀背、"
		+ "生成楔形刃口和刀茎。", 14, Palette.UI_DIM, true))


func _build_hammer_controls() -> void:
	_slider_row("刀背厚度 (mm)", 3.0, 9.0, 0.5, sword.thickness * 300.0, func(v: float) -> void:
		sword.thickness = v / 300.0
		_refresh())
	var btn := UIKit.button("开始锻打（真实形变）", true)
	btn.pressed.connect(_open_forge)
	_controls.add_child(btn)
	var info := UIKit.label("", 14, Palette.UI_TEXT)
	info.name = "HammerInfo"
	_controls.add_child(info)
	_controls.add_child(UIKit.label(
		"坯料是一根短粗方棒：锤哪里哪里变薄，材料必然往四周流动（体积不变）。"
		+ "想拉长就往中段/两端锤。料温掉到 24% 以下要按 R 回炉 —— 冷砸只会砸出内部裂纹。",
		14, Palette.UI_DIM, true))


func _build_heat_controls() -> void:
	_option_row("淬火介质", ForgeSim.QUENCH_NAMES, sword.quench_medium, func(i: int) -> void:
		sword.quench_medium = i
		_refresh())
	var clay_btn := UIKit.button("覆土烧刃（画一层耐火泥）", true)
	clay_btn.pressed.connect(_open_clay)
	_controls.add_child(clay_btn)
	var clay_info := UIKit.label("", 14, Palette.UI_TEXT, true)
	clay_info.name = "ClayInfo"
	_controls.add_child(clay_info)
	_slider_row("奥氏体化温度 (℃)", 740, 920, 10, sword.aus_temp, func(v: float) -> void:
		sword.aus_temp = v
		_refresh())
	_slider_row("回火温度 (℃)", 100, 400, 10, sword.temper_temp, func(v: float) -> void:
		sword.temper_temp = v
		_refresh())
	_slider_row("回火时间 (分钟)", 20, 240, 10, sword.temper_time, func(v: float) -> void:
		sword.temper_time = v
		_refresh())
	_slider_row("正火次数（消除内应力）", 0, 3, 1, sword.normalized_cycles, func(v: float) -> void:
		sword.normalized_cycles = int(v)
		_refresh())
	var info := UIKit.label("", 14, Palette.UI_TEXT)
	info.name = "HeatInfo"
	_controls.add_child(info)
	_controls.add_child(UIKit.label(
		"推荐奥氏体化温度：1095/1084 约 790~830℃，5160/52100 约 830~860℃。"
		+ "温度太低淬不上火，太高晶粒粗大、容易裂。回火温度越高越韧、越软。",
		14, Palette.UI_DIM, true))
	_controls.add_child(UIKit.label(
		"覆土烧刃：刀背糊一层耐火泥，入水时刀背冷却慢、不形成马氏体（软而韧），"
		+ "刃口裸露快速冷却（硬）。两者交界处就是日本刀那条刃文。",
		14, Palette.UI_DIM, true))


func _build_finish_controls() -> void:
	_slider_row("研磨进度", 0.0, 1.0, 0.05, sword.grind, func(v: float) -> void:
		sword.grind = v
		_refresh())
	_slider_row("抛光程度", 0.0, 1.0, 0.05, sword.polish, func(v: float) -> void:
		sword.polish = v
		_refresh())
	_slider_row("酸洗时间 (分钟)", 0.0, 10.0, 0.5, sword.etch_minutes, func(v: float) -> void:
		sword.etch_minutes = v
		_refresh())
	var info := UIKit.label("", 14, Palette.UI_TEXT)
	info.name = "EtchInfo"
	_controls.add_child(info)
	_controls.add_child(UIKit.label(
		"三氯化铁(FeCl3)对高碳组织腐蚀最快。时间太短什么都没有，"
		+ "时间太长会过腐蚀、把细节吃糊。", 14, Palette.UI_DIM, true))


func _build_handle_controls() -> void:
	var pnames: Array = []
	for p in HandleBuilder.PROFILES:
		pnames.append(p["name"])
	_option_row("柄型", pnames, sword.handle_preset, func(i: int) -> void:
		sword.handle_preset = i
		_refresh())
	# 弯刀（太刀/日本刀）的刀茎方向和刀身弦向不一致，柄装上去会歪 —— 这里手动对齐
	_slider_row("刀柄角度（对齐刀茎）", -30.0, 30.0, 1.0, sword.handle_angle,
		func(v: float) -> void:
			sword.handle_angle = v
			_refresh())
	var chk := CheckBox.new()
	chk.text = "自定义柄形（用下面滑条捏一个）"
	chk.button_pressed = sword.handle_custom
	UIKit.apply_font(chk)
	chk.toggled.connect(func(on: bool) -> void:
		sword.handle_custom = on
		_build_controls()
		_refresh())
	_controls.add_child(chk)
	if sword.handle_custom:
		_slider_row("前端半径", 0.020, 0.072, 0.002, sword.handle_r0, func(v: float) -> void:
			sword.handle_r0 = v
			_refresh())
		_slider_row("中段半径（手握最细处）", 0.018, 0.070, 0.002, sword.handle_r1, func(v: float) -> void:
			sword.handle_r1 = v
			_refresh())
		_slider_row("尾端半径", 0.018, 0.072, 0.002, sword.handle_r2, func(v: float) -> void:
			sword.handle_r2 = v
			_refresh())
		_slider_row("扁平度（1 = 圆柄，0.4 = 扁柄）", 0.4, 1.0, 0.05, sword.handle_flat,
			func(v: float) -> void:
				sword.handle_flat = v
				_refresh())
	var wnames: Array = []
	for w in HandleBuilder.WOODS:
		wnames.append(w["name"])
	_option_row("木料", wnames, sword.handle_wood, func(i: int) -> void:
		sword.handle_wood = i
		set_wood_uniforms(i)
		if _carve:
			_carve.set_wood(i)
		_refresh())
	_option_row("护手", ["无", "铁护手", "铜护手", "木护手"], sword.guard_style,
		func(i: int) -> void:
			sword.guard_style = i
			_build_controls()
			_refresh())
	if sword.guard_style > 0:
		var crow := HBoxContainer.new()
		crow.add_theme_constant_override("separation", 10)
		var clab := UIKit.label("护手颜色", 15, Palette.UI_TEXT)
		clab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		crow.add_child(clab)
		var pick := ColorPickerButton.new()
		pick.color = sword.guard_color
		pick.custom_minimum_size = Vector2(120, 34)
		pick.edit_alpha = false
		pick.color_changed.connect(func(c: Color) -> void:
			sword.guard_color = c
			_refresh())
		crow.add_child(pick)
		_controls.add_child(crow)
		_slider_row("护手金属度（1 金属 / 0 哑光）", 0.0, 1.0, 0.05, sword.guard_metal,
			func(v: float) -> void:
				sword.guard_metal = v
				_refresh())
		_slider_row("护手粗糙度（小 = 亮）", 0.05, 0.95, 0.05, sword.guard_rough,
			func(v: float) -> void:
				sword.guard_rough = v
				_refresh())
		_option_row("护手形状", ["圆盘（经典）", "十字横条", "弧形（杏叶）", "碗形（护手杯）", "宽圆盘",
			"球端直臂（西欧 1440-80）", "S 形（Katzbalger）", "侧环（意大利 1530-1620）", "直臂+侧环（西欧 1550-1650）"],
			sword.guard_shape, func(i: int) -> void:
				sword.guard_shape = i
				_refresh())
	_option_row("镶嵌材料（雕刻填漆用）", CarveCanvas.INLAY_NAMES, sword.inlay_style,
		func(i: int) -> void:
			sword.inlay_style = i
			_refresh())
	_option_row("尾铁", ["无", "铆钉", "金属尾铁"], sword.pommel_style,
		func(i: int) -> void:
			sword.pommel_style = i
			_build_controls()
			_refresh())
	if sword.pommel_style > 0:
		var prow := HBoxContainer.new()
		prow.add_theme_constant_override("separation", 10)
		var plab := UIKit.label("尾铁颜色（独立于护手）", 15, Palette.UI_TEXT)
		plab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		prow.add_child(plab)
		var ppick := ColorPickerButton.new()
		ppick.color = sword.pommel_color
		ppick.custom_minimum_size = Vector2(120, 34)
		ppick.edit_alpha = false
		ppick.color_changed.connect(func(c: Color) -> void:
			sword.pommel_color = c
			_refresh())
		prow.add_child(ppick)
		_controls.add_child(prow)
		_slider_row("尾铁金属度", 0.0, 1.0, 0.05, sword.pommel_metal,
			func(v: float) -> void:
				sword.pommel_metal = v
				_refresh())
		_slider_row("尾铁粗糙度", 0.05, 0.95, 0.05, sword.pommel_rough,
			func(v: float) -> void:
				sword.pommel_rough = v
				_refresh())
	var btn := UIKit.button("雕刻柄上图案", true)
	btn.pressed.connect(_open_carve)
	_controls.add_child(btn)

	var fbtn := UIKit.button("雕刃面浮雕 / 金丝镶嵌", true)
	fbtn.pressed.connect(_open_face)
	_controls.add_child(fbtn)
	_option_row("刃面画布范围", ["整条刃", "刃根（后半段）", "刃根特写", "刃中段", "刃尖"],
		_face_rect_index(), func(i: int) -> void:
			sword.face_rect = _face_rect_for(i)
			_apply_face_rect()
			_refresh())
	if sword.guard_style > 0:
		_option_row("护手宝石", ["无", "红宝石", "蓝宝石", "祖母绿"], sword.gem_style,
			func(i: int) -> void:
				sword.gem_style = i
				_build_controls()
				_refresh())
		if sword.gem_style > 0:
			_option_row("宝石形状", ["圆磨（蛋面）", "棱形（刻面）"], sword.gem_shape,
				func(i: int) -> void:
					sword.gem_shape = i
					_refresh())
	var info := UIKit.label("", 14, Palette.UI_TEXT)
	info.name = "HandleInfo"
	_controls.add_child(info)


func _build_review_controls() -> void:
	var r := sword.score_breakdown
	if r.is_empty():
		r = ForgeSim.evaluate(sword)
		sword.score_breakdown = r
	_controls.add_child(UIKit.label("成品评分", 15, Palette.UI_DIM))
	var big := UIKit.label("%d" % int(r["total"]), 54, Palette.UI_ACCENT)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_controls.add_child(big)
	var t := UIKit.label(str(r["title"]), 20, Palette.UI_TEXT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_controls.add_child(t)
	_controls.add_child(UIKit.gap(6))
	_controls.add_child(UIKit.stat_bar("花纹", r["pattern"], Palette.UI_ACCENT2, 320))
	_controls.add_child(UIKit.stat_bar("硬度", r["hardness"], Palette.UI_ACCENT, 320))
	_controls.add_child(UIKit.stat_bar("韧性", r["toughness"], Color("6b9e5a"), 320))
	_controls.add_child(UIKit.stat_bar("刀形", r["geometry"], Color("8a7fb0"), 320))
	_controls.add_child(UIKit.stat_bar("工艺", r["craft"], Color("b09a5a"), 320))
	_controls.add_child(UIKit.stat_bar("刀柄", r["handle"], Color("c07a4a"), 320))
	_controls.add_child(UIKit.gap(8))
	for c in r["comments"]:
		_controls.add_child(UIKit.label("· " + str(c), 14, Palette.UI_TEXT, true))
	_controls.add_child(UIKit.gap(8))
	_controls.add_child(UIKit.label("给这把刀取个名字：", 15, Palette.UI_DIM))
	_name_edit = LineEdit.new()
	_name_edit.text = sword.sword_name if sword.sword_name != "" else "黑潮"
	_name_edit.custom_minimum_size = Vector2(0, 40)
	UIKit.apply_font(_name_edit)
	_name_edit.add_theme_stylebox_override("normal", UIKit.sb(Color("eae3d0"), 9))
	_name_edit.add_theme_stylebox_override("focus", UIKit.sb(Color("f7f1e0"), 9, 2, Palette.UI_ACCENT))
	_name_edit.add_theme_color_override("font_color", Palette.UI_TEXT)
	_name_edit.add_theme_color_override("font_placeholder_color", Palette.UI_DIM)
	_name_edit.add_theme_color_override("caret_color", Palette.UI_TEXT)
	_name_edit.add_theme_color_override("selection_color", Color(0.85, 0.5, 0.3, 0.35))
	_controls.add_child(_name_edit)


# =========================================================
#  刷新数据显示与预览
# =========================================================
func _rng_for_sword() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = int(absf(sword.aus_temp * 13.0 + sword.temper_temp * 7.0
		+ float(sword.quench_medium) * 991.0 + sword.thickness * 1000.0
		+ float(sword.normalized_cycles) * 37.0))
	return r


func _refresh() -> void:
	if sword.forged_outline.size() >= 4:
		sword.mesh_outline()   # 顺手刷新锻造偏差
	if _step == 1:
		sword.weld_quality = ForgeSim.weld_quality(_weld_temp, _weld_flux,
			SteelDB.mix_carbon(sword.core_id, sword.alt_id), sword.folds)
	if _step >= 5:
		ForgeSim.heat_treatment(sword, _rng_for_sword())

	# ---- 左侧数据 ----
	var pat := sword.pattern_score()
	var hb := clampf((sword.hardness - 42.0) / 22.0, 0.0, 1.0)
	_stat_label.text = "层数 %d\n反差 %d%%\n硬度 %.1f HRC\n韧性 %d%%\n形变 %.2f%s" % [
		sword.layer_count(), int(sword.contrast() * 100.0), sword.hardness,
		int(sword.toughness * 100.0), sword.warp, "\n!! 已开裂" if sword.cracked else ""
	]
	_update_bar(_pattern_bar, pat)
	_update_bar(_hard_bar, hb)
	_update_bar(_tough_bar, sword.toughness)

	# ---- 工序内的即时提示 ----
	var info := _controls.get_node_or_null("SteelInfo")
	if info and info is Label:
		var c := SteelDB.get_steel(sword.core_id)
		var a := SteelDB.get_steel(sword.alt_id)
		(info as Label).text = "%s（碳 %.2f%%） / %s（碳 %.2f%%）\n反差 %.0f%% ｜ 预计 %d 层" % [
			c["short"], c["carbon"] * 100.0, a["short"], a["carbon"] * 100.0,
			sword.contrast() * 100.0, sword.layer_count()]
	var fi := _controls.get_node_or_null("FoldInfo")
	if fi and fi is Label:
		(fi as Label).text = "锻接质量 %.0f%% ｜ 折后 %d 层\n%s" % [
			sword.weld_quality * 100.0, sword.layer_count(),
			"温度正好" if sword.weld_quality > 0.75 else "温度偏离窗口，层间会夹渣"]
	var di := _controls.get_node_or_null("DesignInfo")
	if di and di is Label:
		(di as Label).text = "当前轮廓 %d 个点，刀身长宽比 %.1f" % [
			sword.outline.size(), _aspect()]
	var hinfo := _controls.get_node_or_null("HammerInfo")
	if hinfo and hinfo is Label:
		(hinfo as Label).text = "贴合度 %d%%　｜　锻造偏差 %.1f%%%s%s" % [
			int(sword.fidelity * 100.0), sword.forged_dev * 100.0,
			"（未锻打）" if sword.fidelity <= 0.0 else "",
			"\n锤得有点歪：刀身会照着偏掉的形状长" if sword.forged_dev > 0.012 else ""]
	var hti := _controls.get_node_or_null("HeatInfo")
	if hti and hti is Label:
		(hti as Label).text = "硬度 %.1f HRC ｜ 韧性 %.0f%% ｜ 形变 %.2f%s" % [
			sword.hardness, sword.toughness * 100.0, sword.warp,
			"\n!! 淬火开裂！" if sword.cracked else ""]
	var ci := _controls.get_node_or_null("ClayInfo")
	if ci and ci is Label:
		(ci as Label).text = "刀背覆土 %.0f%% ｜ 刃口覆土 %.0f%% ｜ 刃文 %.0f%%%s" % [
			sword.clay_spine * 100.0, sword.clay_edge * 100.0, sword.hamon * 100.0,
			"\n刃口被泥糊住了：淬不硬，会卷刃！" if sword.clay_edge > 0.25 else ""]
	var ei := _controls.get_node_or_null("EtchInfo")
	if ei and ei is Label:
		(ei as Label).text = "花纹显现度 %d%% ｜ 层理细腻度 %d%%" % [
			int(sword.pattern_visibility() * 100.0), int(sword.layer_texture_score() * 100.0)]
	var hdi := _controls.get_node_or_null("HandleInfo")
	if hdi and hdi is Label:
		(hdi as Label).text = "雕刻覆盖 %.0f%% ｜ 填漆 %.0f%%" % [
			sword.carve_cover * 100.0, sword.carve_ink * 100.0]

	_refresh_preview()


func _update_bar(node: Control, v: float) -> void:
	if node == null:
		return
	for c in node.get_children():
		if c is ProgressBar:
			(c as ProgressBar).value = clampf(v, 0.0, 1.0)
		elif c is HBoxContainer:
			var h := c as HBoxContainer
			if h.get_child_count() >= 2 and h.get_child(1) is Label:
				(h.get_child(1) as Label).text = "%d%%" % int(clampf(v, 0.0, 1.0) * 100.0)


func _aspect() -> float:
	var bb := Rect2(sword.outline[0], Vector2.ZERO)
	for p in sword.outline:
		bb = bb.expand(p)
	if bb.size.y < 0.0001:
		return 0.0
	return bb.size.x / bb.size.y


func _refresh_preview() -> void:
	var u := sword.damascus_uniforms()
	for k in u:
		_blade_mat.set_shader_parameter(k, u[k])
	# 覆土 / 刃文
	_blade_mat.set_shader_parameter("hamon", sword.hamon)
	if sword.clay_mask != null:
		if _clay_tex == null:
			_clay_tex = ImageTexture.create_from_image(sword.clay_mask)
			_blade_mat.set_shader_parameter("clay_tex", _clay_tex)
		else:
			_clay_tex.update(sword.clay_mask)

	# 网格
	for c in _assembly.get_children():
		_assembly.remove_child(c)
		c.queue_free()
	if sword.outline.size() < 4:
		return
	var bm := BladeBuilder.build(sword)
	if bm:
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = _blade_mat
		_assembly.add_child(mi)
	if _step >= 7:
		var info := BladeBuilder.analyze(sword.mesh_outline())
		var hm := HandleBuilder.build(sword, info["butt"], info["butt_dir"])
		if hm:
			var hmi := MeshInstance3D.new()
			hmi.mesh = hm
			hmi.material_override = _handle_mat
			_assembly.add_child(hmi)
		var fm := HandleBuilder.build_fittings(sword, info["butt"], info["butt_dir"], 1)
		if fm:
			var fmi := MeshInstance3D.new()
			fmi.mesh = fm
			fmi.material_override = MeshKit.mat(sword.guard_color, sword.guard_rough, sword.guard_metal)
			_assembly.add_child(fmi)
		var pm2 := HandleBuilder.build_fittings(sword, info["butt"], info["butt_dir"], 2)
		if pm2:
			var pmi2 := MeshInstance3D.new()
			pmi2.mesh = pm2
			pmi2.material_override = MeshKit.mat(sword.pommel_color, sword.pommel_rough, sword.pommel_metal)
			_assembly.add_child(pmi2)
		# 护手宝石（独立材质，所以单独挂一个节点）
		var gem := _gem_node(sword, info["butt"], info["butt_dir"])
		if gem != null:
			_assembly.add_child(gem)
	_preview_note.text = "层数 %d ｜ 当前视口 3D 实时预览" % sword.layer_count()


# =========================================================
#  子界面：设计图纸 / 锻打 / 雕刻
# =========================================================
func _open_design() -> void:
	_design = DesignCanvas.new()
	_design.accepted.connect(_on_design_accepted)
	_design.cancelled.connect(func() -> void:
		_overlay.visible = false
		_design.queue_free()
		_design = null)
	_overlay.add_child(_design)
	_design.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = true
	_design.set_guide(ContourTrace.preset_outlines()[0]["pts"])


func _on_design_accepted(outline: PackedVector2Array) -> void:
	sword.outline = outline
	sword.design_source = "hand:%d" % Time.get_ticks_msec()
	_overlay.visible = false
	if _design:
		_design.queue_free()
		_design = null
	_goto(4)


func _open_forge() -> void:
	if sword.outline.size() < 4:
		return
	_forge = ForgeCanvas.new()
	_forge.accepted.connect(func(f: float, outline: PackedVector2Array) -> void:
		sword.fidelity = f
		if outline.size() >= 4:
			sword.forged_outline = outline
		_overlay.visible = false
		_forge.queue_free()
		_forge = null
		_refresh())
	_forge.cancelled.connect(func() -> void:
		_overlay.visible = false
		_forge.queue_free()
		_forge = null)
	_overlay.add_child(_forge)
	_forge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_forge.set_target(sword.outline)
	_overlay.visible = true


func _open_hammer() -> void:
	_hammer = HammerGame.new()
	_hammer.finished.connect(func(f: float) -> void:
		sword.fidelity = f
		_overlay.visible = false
		_hammer.queue_free()
		_hammer = null
		_refresh())
	_overlay.add_child(_hammer)
	_hammer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = true


func _open_clay() -> void:
	_clay = ClayCanvas.new()
	_clay.accepted.connect(func(img: Image, spine: float, edge: float) -> void:
		sword.clay_mask = img
		sword.clay_spine = spine
		sword.clay_edge = edge
		_clay_tex = null
		_overlay.visible = false
		_clay.queue_free()
		_clay = null
		_refresh())
	_clay.cancelled.connect(func() -> void:
		_overlay.visible = false
		_clay.queue_free()
		_clay = null)
	_overlay.add_child(_clay)
	_clay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = true


## 画布覆盖的 UV 区域：范围越小，同样像素下细节越大
func _face_rect_for(i: int) -> Rect2:
	match i:
		1:
			return Rect2(0.02, 0.15, 0.40, 0.70)
		2:
			return Rect2(0.02, 0.25, 0.18, 0.50)
		3:
			return Rect2(0.35, 0.15, 0.35, 0.70)
		4:
			return Rect2(0.62, 0.20, 0.36, 0.60)
		_:
			return Rect2(0.0, 0.0, 1.0, 1.0)


func _face_rect_index() -> int:
	var r := sword.face_rect
	for i in 5:
		if _face_rect_for(i).is_equal_approx(r):
			return i
	return 0


func _apply_face_rect() -> void:
	if _blade_mat == null:
		return
	var r := sword.face_rect
	_blade_mat.set_shader_parameter("face_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))

## 护手中央的宝石 + 金托座
func _gem_node(s: SwordData, butt: Vector2, bdir: Vector2) -> Node3D:
	if s.gem_style <= 0:
		return null
	var root := Node3D.new()
	var cols := [Color("d02c2c"), Color("2f6bd0"), Color("1fa05a")]
	var col: Color = cols[clampi(s.gem_style - 1, 0, 2)]
	var axis := Vector3(bdir.x, bdir.y, 0.0).normalized()
	var base_pos := Vector3(butt.x, butt.y, 0.0) + axis * 0.024 + Vector3(0, 0, 0.026)
	var ring := MeshKit.add_torus(root, 0.020, 0.030, base_pos, Palette.GOLD, Vector3(90, 0, 0), 12)
	ring.material_override = MeshKit.mat(Palette.GOLD, 0.25, 1.0)
	var gem: MeshInstance3D
	if s.gem_shape == 1:
		# 棱形：六棱双锥（seg=6 / rings=2）
		gem = MeshKit.add_sphere(root, 0.026, base_pos, col, Vector3(1.0, 1.30, 0.80), 6, 2)
	else:
		gem = MeshKit.add_sphere(root, 0.021, base_pos, col, Vector3(1.0, 1.0, 0.55), 8, 6)
	gem.material_override = MeshKit.mat(col, 0.10, 0.05, col, 2.6)
	return root

func _open_face() -> void:
	_carve = CarveCanvas.new()
	_carve.face_mode = true
	_carve.accepted.connect(func(img: Image, cover: float, ink: float) -> void:
		sword.face_mask = img
		sword.face_cover = cover
		_face_tex.update(img)
		_overlay.visible = false
		_carve.queue_free()
		_carve = null
		_refresh())
	_carve.cancelled.connect(func() -> void:
		_overlay.visible = false
		_carve.queue_free()
		_carve = null)
	_overlay.add_child(_carve)
	_carve.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_carve.set_steel()
	_carve.inlay_idx = sword.inlay_style
	_apply_face_rect()
	_overlay.visible = true

func _open_carve() -> void:
	_carve = CarveCanvas.new()
	_carve.accepted.connect(func(img: Image, cover: float, ink: float) -> void:
		sword.carve_mask = img
		sword.carve_cover = cover
		sword.carve_ink = ink
		_carve_tex.update(img)
		_overlay.visible = false
		_carve.queue_free()
		_carve = null
		_refresh())
	_carve.cancelled.connect(func() -> void:
		_overlay.visible = false
		_carve.queue_free()
		_carve = null)
	_overlay.add_child(_carve)
	_carve.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_carve.set_wood(sword.handle_wood)   # 必须在 add_child（_ready）之后
	_carve.inlay_idx = sword.inlay_style
	if _carve._inlay_opt != null:
		_carve._inlay_opt.selected = sword.inlay_style
	_overlay.visible = true


# =========================================================
#  逐帧
# =========================================================
func _process(dt: float) -> void:
	if not visible:
		return
	_time += dt
	if _step <= 4:
		_blade_mat.set_shader_parameter("hot", 0.20 + 0.06 * sin(_time * 6.0))
	else:
		_blade_mat.set_shader_parameter("hot", 0.0)
	# 转台 / 特写
	if _focus == 0:
		_spin += dt * 0.35
		_assembly.rotation_degrees = Vector3(0.0, sin(_spin) * 26.0, 12.0)
	else:
		_assembly.rotation_degrees = Vector3(0.0, -16.0, 24.0)
	var cam_target := Vector3(0.02, 0.0, 0.0)
	var cam_pos := Vector3(0.16, 0.62, 2.10)
	if _focus == 1:
		cam_target = Vector3(0.02, 0.0, 0.0)
		cam_pos = Vector3(0.08, 0.10, 0.32)
	_cam.position = _cam.position.lerp(cam_pos, clampf(dt * 5.0, 0.0, 1.0))
	_cam.look_at(cam_target)
