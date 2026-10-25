extends Node3D
## 游戏入口：搭出光照与海岛箱庭，放好相机和 UI。

var island: Island
var cam: OrbitCamera
var workshop: Workshop
var marker: HotspotMarker
var dock_marker: HotspotMarker
var hall_marker: HotspotMarker
var viewer: SwordViewer
var rack_marker: HotspotMarker
var friends_panel: FriendsPanel
var gallery: Gallery
var gallery_btn: Button
var market: Market
var ui: CanvasLayer


func _ready() -> void:
	_build_environment()
	island = Island.new()
	island.name = "Island"
	add_child(island)

	cam = OrbitCamera.new()
	cam.target = Vector3(0.2, 1.7, 0.6)
	cam.distance = 39.5
	add_child(cam)
	cam.make_current()
	cam.tapped.connect(_on_tap)

	_build_ui()


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("efe2c8")          # 夏日傍晚的米色天光
	# 天空：上方冷、地平线暖 —— 金属/水面反射出的就是这种暖冷分层
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("a6bad6")
	sky_mat.sky_horizon_color = Color("f0cd9a")
	sky_mat.ground_horizon_color = Color("e8cfae")
	sky_mat.ground_bottom_color = Color("b9a98f")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.sky = sky
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("b6cbe4")       # 冷环境光
	e.ambient_light_energy = 0.30
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	e.ssao_radius = 1.6
	e.ssao_intensity = 1.2
	e.glow_enabled = true
	e.glow_intensity = 0.14
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.12
	we.environment = e
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color("ffc98a")             # 低角度的暖阳
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.shadow_bias = 0.03
	sun.light_angular_distance = 1.0
	sun.directional_shadow_max_distance = 70.0
	sun.rotation_degrees = Vector3(-32, 46, 0)
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.light_color = Color("9ec2ff")            # 背面的冷补光，勾出轮廓
	fill.light_energy = 0.42
	fill.rotation_degrees = Vector3(-14, -120, 0)
	add_child(fill)


func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)

	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	marker = HotspotMarker.new()
	marker.camera = cam
	marker.text = "铁匠铺 · 点这里锻刀"
	marker.world_pos = island.forge_pos + Vector3(0.0, 2.4, 0.0)
	root.add_child(marker)
	marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	dock_marker = HotspotMarker.new()
	dock_marker.camera = cam
	dock_marker.text = "码头 · 交易市场"
	dock_marker.world_pos = island.dock_pos
	root.add_child(dock_marker)
	dock_marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	hall_marker = HotspotMarker.new()
	hall_marker.camera = cam
	hall_marker.text = "樱 花 屋 · 赏刀"
	hall_marker.world_pos = island.hall_pos + Vector3(0.0, 4.4, 0.0)
	root.add_child(hall_marker)
	hall_marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	rack_marker = HotspotMarker.new()
	rack_marker.camera = cam
	rack_marker.text = "展 示 架 · 好 友"
	rack_marker.world_pos = island.rack_pos + Vector3(0.0, 2.5, 0.0)
	root.add_child(rack_marker)
	rack_marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


	workshop = Workshop.new()
	root.add_child(workshop)
	workshop.finished.connect(_on_sword_finished)
	workshop.closed.connect(_on_workshop_closed)

	var gal_btn := UIKit.button("收藏馆")
	gal_btn.custom_minimum_size = Vector2(150, 40)
	root.add_child(gal_btn)
	gal_btn.anchor_left = 1.0
	gal_btn.anchor_right = 1.0
	gal_btn.offset_left = -180.0
	gal_btn.offset_right = -30.0
	gal_btn.offset_top = 24.0
	gal_btn.offset_bottom = 64.0
	gal_btn.pressed.connect(func() -> void: gallery.open())
	gallery_btn = gal_btn

	gallery = Gallery.new()
	root.add_child(gallery)
	gallery.picked.connect(_on_gallery_pick)
	gallery.closed.connect(func() -> void: pass)

	market = Market.new()
	root.add_child(market)
	market.closed.connect(_restore_ui)

	viewer = SwordViewer.new()
	root.add_child(viewer)
	viewer.closed.connect(_restore_ui)

	friends_panel = FriendsPanel.new()
	root.add_child(friends_panel)
	friends_panel.closed.connect(_restore_ui)
	friends_panel.inspect_requested.connect(func(entries: Array) -> void:
		viewer.open_list(entries))

	# 背景音乐：三首随机播放
	var music: Node = preload("res://scripts/core/music_player.gd").new()
	music.name = "Music"
	add_child(music)

	_load_display_swords()


## 启动时把最近做的三把刀挂回展示架
func _load_display_swords() -> void:
	var saves := SaveSystem.list_saves()
	var n := 0
	for e in saves:
		if n >= 3:
			break
		var s := SaveSystem.load_sword(str(e["id"]))
		if s == null:
			continue
		island.hang_sword_node(SwordAssembler.build_node(s))
		n += 1


func _on_gallery_pick(id: String) -> void:
	var s := SaveSystem.load_sword(id)
	if s == null:
		return
	island.hang_sword_node(SwordAssembler.build_node(s))
	gallery.visible = false


func _on_tap(pos: Vector2) -> void:
	if workshop.visible or market.visible or gallery.visible or viewer.visible or friends_panel.visible:
		return
	if marker.hit_test(pos):
		workshop.open()
		_set_ui_visible(false)
		return
	if dock_marker.hit_test(pos):
		market.open()
		_set_ui_visible(false)
		return
	if hall_marker.hit_test(pos):
		viewer.open()
		_set_ui_visible(false)
		return
	if rack_marker.hit_test(pos):
		friends_panel.open()
		_set_ui_visible(false)
		return
	# 点鱼群：惊散
	if cam.unproject_position(island.fish_center).distance_to(pos) < 95.0:
		island.scatter_fish()
		SoundKit.play("plop", randf_range(0.92, 1.10), -5.0)


func _set_ui_visible(on: bool) -> void:
	marker.enabled = on
	dock_marker.enabled = on
	hall_marker.enabled = on
	rack_marker.enabled = on
	gallery_btn.visible = on


func _restore_ui() -> void:
	if friends_panel != null and friends_panel.visible:
		return
	_set_ui_visible(true)


func _on_sword_finished() -> void:
	island.hang_sword_node(workshop.duplicate_assembly())


func _on_workshop_closed() -> void:
	_set_ui_visible(true)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_ESCAPE and workshop.visible:
			workshop.close()
