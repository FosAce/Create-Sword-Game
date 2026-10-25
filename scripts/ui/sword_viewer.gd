class_name SwordViewer
extends Control
## 樱花屋 · 赏刀：把做过的刀放进一个独立视口里，
## 鼠标拖动旋转、滚轮缩放，左右切换不同成品。

signal closed()

var _viewport: SubViewport
var _holder: Node3D
var _cam: Camera3D
var _saves: Array = []
var _idx := 0
var _yaw := -0.38
var _pitch := 0.16
var _dist := 1.95
var _drag := false

var _name: Label
var _info: Label
var _page: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0.10, 0.09, 0.08, 0.74)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var card := UIKit.panel(Color("f7f1e0"), 18)
	card.custom_minimum_size = Vector2(1180, 772)
	center.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	_name = UIKit.title("樱 花 屋 · 赏 刀", 24)
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_name)
	var prev := UIKit.button("◀")
	prev.custom_minimum_size = Vector2(54, 40)
	prev.pressed.connect(func() -> void: _step(-1))
	head.add_child(prev)
	_page = UIKit.label("", 15, Palette.UI_DIM)
	head.add_child(_page)
	var nxt := UIKit.button("▶")
	nxt.custom_minimum_size = Vector2(54, 40)
	nxt.pressed.connect(func() -> void: _step(1))
	head.add_child(nxt)
	var close := UIKit.button("离开")
	close.custom_minimum_size = Vector2(96, 40)
	close.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	head.add_child(close)

	_info = UIKit.label("", 15, Palette.UI_DIM)
	col.add_child(_info)

	var svc := SubViewportContainer.new()
	svc.custom_minimum_size = Vector2(1130, 580)
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_STOP
	col.add_child(svc)
	svc.gui_input.connect(_on_view_input)

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1130, 580)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(_viewport)
	_build_scene()

	col.add_child(UIKit.label("按住左键拖动 = 转动　｜　滚轮 = 缩放　｜　◀ ▶ = 换一把",
		14, Palette.UI_ACCENT2))


func _build_scene() -> void:
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
	_viewport.add_child(env)

	var dl := DirectionalLight3D.new()
	dl.light_color = Color("fff6e8")
	dl.light_energy = 1.25
	dl.shadow_enabled = true
	dl.rotation_degrees = Vector3(-42, 38, 0)
	_viewport.add_child(dl)

	var rim := DirectionalLight3D.new()
	rim.light_color = Color("fff0d8")
	rim.light_energy = 1.30
	rim.rotation_degrees = Vector3(-72, 150, 0)
	_viewport.add_child(rim)

	# 条光：掠射角照刃面 → 拉出一条研磨高光带
	var strip2 := DirectionalLight3D.new()
	strip2.light_color = Color("fff4e2")
	strip2.light_energy = 0.85
	strip2.shadow_enabled = false
	strip2.rotation_degrees = Vector3(-84, 34, 0)
	_viewport.add_child(strip2)

	var fill := DirectionalLight3D.new()
	fill.light_color = Color("bcd4e6")
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-18, -120, 0)
	_viewport.add_child(fill)

	_cam = Camera3D.new()
	_cam.fov = 34.0
	_cam.position = Vector3(0, 0, _dist)
	_viewport.add_child(_cam)

	_holder = Node3D.new()
	_viewport.add_child(_holder)


func _on_view_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_dist = clampf(_dist - 0.11, 0.90, 3.30)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_dist = clampf(_dist + 0.11, 0.90, 3.30)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = mb.pressed
	elif ev is InputEventMouseMotion and _drag:
		var mm := ev as InputEventMouseMotion
		_yaw += mm.relative.x * 0.0075
		_pitch = clampf(_pitch + mm.relative.y * 0.0060, -1.15, 1.15)


func _process(_dt: float) -> void:
	if not visible:
		return
	_holder.rotation = Vector3(_pitch, _yaw, 0.0)
	_cam.position = Vector3(0.0, 0.0, _dist)


func open() -> void:
	open_list(SaveSystem.list_saves())


## 用外部给的列表打开（好友展示框用这个）
func open_list(entries: Array) -> void:
	_saves = entries
	_idx = 0
	visible = true
	_refresh()


func _step(d: int) -> void:
	if _saves.is_empty():
		return
	_idx = wrapi(_idx + d, 0, _saves.size())
	SoundKit.play("click", 1.05, -14.0)
	_refresh()


func _refresh() -> void:
	for c in _holder.get_children():
		_holder.remove_child(c)
		c.queue_free()
	if _saves.is_empty():
		_name.text = "樱 花 屋 · 赏 刀"
		_info.text = "还没有成品 —— 先去铁匠铺锻一把。"
		_page.text = "0 / 0"
		return
	_page.text = "%d / %d" % [_idx + 1, _saves.size()]
	var e: Dictionary = _saves[_idx]
	var d: Dictionary = e["data"]
	var nm := str(d.get("sword_name", "无名刀"))
	var score := float(d.get("final_score", 0.0))
	var title := "废铁一块"
	if score >= 88.0:
		title = "传奇名刀"
	elif score >= 76.0:
		title = "大师之作"
	elif score >= 62.0:
		title = "匠人手笔"
	elif score >= 45.0:
		title = "学徒习作"
	_name.text = "%s　—　%d 分 · %s" % [nm, int(score), title]

	# 注意：from_dict() 只还原数值，雕刻/覆土/刃面这些 PNG 是独立文件，
	# 必须走 load_sword(id) 才会读回来 —— 否则这里看到的是一把"没有纹身的"刀
	var s: SwordData = null
	if e.has("id"):
		s = SaveSystem.load_sword(str(e["id"]))
	if s == null:
		s = SwordData.from_dict(d)
	var core := SteelDB.get_steel(s.core_id)
	var alt := SteelDB.get_steel(s.alt_id)
	_info.text = "%s + %s　｜　%d 层　｜　%.1f HRC　｜　韧性 %.0f%%　｜　刃文 %.0f%%" % [
		core["short"], alt["short"], s.layer_count(), s.hardness, s.toughness * 100.0,
		s.hamon * 100.0]

	var node := SwordAssembler.build_node(s)
	_holder.add_child(node)
	# 把刀居中（刀身长度 1.5 左右，重心偏刀柄侧）
	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := Vector3(-1e9, -1e9, -1e9)
	var any := false
	for c in node.get_children():
		if c is MeshInstance3D:
			var bb: AABB = (c as MeshInstance3D).get_aabb()
			mn = mn.min(bb.position)
			mx = mx.max(bb.position + bb.size)
			any = true
	if any:
		node.position = -(mn + mx) * 0.5
	# 刀身最长约 1.5，按长度自动定一个合适的初始距离
	var span := maxf((mx - mn).length(), 0.8) if any else 1.6
	_dist = clampf(span * 1.02, 1.05, 3.10)
	_yaw = -0.38
	_pitch = 0.16
