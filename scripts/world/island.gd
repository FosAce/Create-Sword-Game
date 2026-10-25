class_name Island
extends Node3D
## 海岛箱庭：一块被"切开"的海水 + 沙滩小岛 + 小屋 + 铁匠铺 + 木栈桥。
## 全部用基础几何体与程序化高度场搭建，不需要任何外部美术资源。

const WATER_HALF := 13.0
const WATER_CORNER := 5.0
const WATER_TOP := 0.0
const WATER_BOTTOM := -1.45
const ISLAND_R := 8.6
const ISLE_TOP := 2.55
const GRID := 72
const SEABED_FLOOR := -1.38

var forge_pos := Vector3(-3.0, 0.0, 1.6)     # 铁匠铺（交互热点）
var dock_pos := Vector3(4.2, 0.0, 5.2)       # 码头上岸处（交互热点）
var rack_slots: Array[Node3D] = []           # 成品展示位
var rack_pos := Vector3(-5.4, 0.0, -1.0)   # 展示架（好友系统入口）

var _kelp: Array[Node3D] = []
var _kelp_phase: Array[float] = []
var _palms: Array[Node3D] = []
var _palm_yaw: Array[float] = []
var _palm_phase: Array[float] = []
var _chimes: Array[Node3D] = []
var _chime_timer := 3.0
var _t := 0.0

var hall_pos := Vector3.ZERO

# ---- 鱼群 ----
const FISH_R := 9.4
const FISH_Y := -0.32
var fish_center := Vector3(0.0, FISH_Y, 0.0)
var _fish_root: Node3D
var _fish: Array[Node3D] = []
var _fish_base: Array[Vector3] = []
var _fish_off: Array[Vector3] = []
var _fish_vel: Array[Vector3] = []
var _fish_phase: Array[float] = []
var _fish_orbit := 0.0

var _water_mat: ShaderMaterial
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 20240607
	_build_water()
	_build_island()
	_build_underwater()
	_build_coral()
	_build_fish()
	_build_treehouse()
	_build_forge()
	_build_pier()
	_build_dock_gate()
	_build_boat()
	_build_rack()
	_scatter()


# ---------------- 地形 ----------------
func terrain_y(x: float, z: float) -> float:
	var d := sqrt(x * x + z * z) / ISLAND_R
	var base := 0.0
	if d >= 1.0:
		base = -0.30 - (d - 1.0) * 1.8
	else:
		base = pow(1.0 - d * d, 1.15) * ISLE_TOP - 0.18
	var n := sin(x * 0.62) * cos(z * 0.57) * 0.24 + sin(x * 1.7 + z * 1.1) * 0.09
	var flat := smoothstep(0.62, 0.15, d) * 0.22
	return clampf(base + n + flat, SEABED_FLOOR, 99.0)


func _build_water() -> void:
	var poly := MeshKit.rounded_rect(WATER_HALF, WATER_CORNER, 5)

	var water := MeshInstance3D.new()
	water.name = "Water"
	water.mesh = MeshKit.extrude_polygon(poly, WATER_TOP, WATER_BOTTOM, Color.WHITE, Color.WHITE)
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = load("res://shaders/water.gdshader")
	_water_mat.set_shader_parameter("island_radius", ISLAND_R)
	_water_mat.set_shader_parameter("island_center", Vector2.ZERO)
	_water_mat.set_shader_parameter("water_top", WATER_TOP)
	_water_mat.set_shader_parameter("water_bottom", WATER_BOTTOM)
	water.material_override = _water_mat
	add_child(water)

	# 箱庭底座（剖切面）
	var base_poly := MeshKit.rounded_rect(WATER_HALF + 0.55, WATER_CORNER + 0.2, 5)
	var base := MeshInstance3D.new()
	base.name = "Base"
	base.mesh = MeshKit.extrude_polygon(base_poly, WATER_BOTTOM, WATER_BOTTOM - 0.55,
		Palette.CUT_FACE, Color("b9b6ab"))
	base.material_override = MeshKit.mat(Color("d8d4c6"), 0.95)
	add_child(base)

	# 一层更深的阴影带，让"切片"有重量感
	var rim := MeshInstance3D.new()
	rim.mesh = MeshKit.extrude_polygon(base_poly, WATER_BOTTOM - 0.55, WATER_BOTTOM - 0.78,
		Color("9a978d"), Color("8b887e"))
	rim.material_override = MeshKit.mat(Color("9a978d"), 0.95)
	add_child(rim)


func _build_island() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 覆盖整个水箱：水下部分也是这块高度场（浅水半透明后能看见海床）
	var span := WATER_HALF * 1.02
	var step := span * 2.0 / float(GRID)
	var hs := PackedFloat32Array()
	hs.resize((GRID + 1) * (GRID + 1))
	for i in GRID + 1:
		for j in GRID + 1:
			var x := -span + float(i) * step
			var z := -span + float(j) * step
			hs[i * (GRID + 1) + j] = terrain_y(x, z)

	for i in GRID:
		for j in GRID:
			var x0 := -span + float(i) * step
			var x1 := x0 + step
			var z0 := -span + float(j) * step
			var z1 := z0 + step
			var h00 := hs[i * (GRID + 1) + j]
			var h10 := hs[(i + 1) * (GRID + 1) + j]
			var h01 := hs[i * (GRID + 1) + j + 1]
			var h11 := hs[(i + 1) * (GRID + 1) + j + 1]
			if maxf(maxf(h00, h10), maxf(h01, h11)) < -1.34:
				continue
			var c00 := _terr_color(h00, x0, z0)
			var c10 := _terr_color(h10, x1, z0)
			var c01 := _terr_color(h01, x0, z1)
			var c11 := _terr_color(h11, x1, z1)
			var p00 := Vector3(x0, h00, z0)
			var p10 := Vector3(x1, h10, z0)
			var p11 := Vector3(x1, h11, z1)
			var p01 := Vector3(x0, h01, z1)
			_terr_tri(st, p00, p10, p11, c00, c10, c11, Vector3.UP,
				Vector2(x0, z0) * 0.1, Vector2(x1, z0) * 0.1, Vector2(x1, z1) * 0.1)
			_terr_tri(st, p00, p11, p01, c00, c11, c01, Vector3.UP,
				Vector2(x0, z0) * 0.1, Vector2(x1, z1) * 0.1, Vector2(x0, z1) * 0.1)
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Island"
	mi.mesh = mesh
	# 用自定义 shader：顶点色 + 水下焦散
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/sand.gdshader")
	sm.set_shader_parameter("water_y", WATER_TOP)
	sm.set_shader_parameter("caustic_strength", 1.4)
	sm.next_pass = MeshKit.outline_mat()
	mi.material_override = sm
	add_child(mi)


# ---------------- 水下：石子 + 水草 ----------------
func _build_underwater() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	# 石子（透过浅水能看到，焦散会从上面扫过去）
	for k in 46:
		var a := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(8.4, 12.6)
		var x := cos(a) * r
		var z := sin(a) * r
		var y := terrain_y(x, z)
		if y > -0.06:
			continue
		var s := rng.randf_range(0.09, 0.28)
		MeshKit.add_sphere(self, s, Vector3(x, y + s * 0.25, z),
			Palette.STONE.lerp(Palette.STONE_DARK, rng.randf()).darkened(0.08),
			Vector3(1.0, rng.randf_range(0.45, 0.8), rng.randf_range(0.8, 1.25)), 5, 3)
	# 水草（成丛，随水流摆）
	for k in 22:
		var a := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(8.9, 12.2)
		var x := cos(a) * r
		var z := sin(a) * r
		var y := terrain_y(x, z)
		if y > -0.12 or y < -1.2:
			continue
		var g := Node3D.new()
		g.position = Vector3(x, y, z)
		g.rotation_degrees.y = rng.randf_range(0.0, 360.0)
		add_child(g)
		_kelp.append(g)
		_kelp_phase.append(rng.randf_range(0.0, TAU))
		var blades := rng.randi_range(3, 5)
		for i in blades:
			var ang := TAU * float(i) / float(blades) + rng.randf_range(-0.3, 0.3)
			var h := rng.randf_range(0.45, 1.15)
			var pm := PlaneMesh.new()
			pm.size = Vector2(rng.randf_range(0.12, 0.2), h)
			pm.orientation = PlaneMesh.FACE_Z
			var mi2 := MeshInstance3D.new()
			mi2.mesh = pm
			mi2.position = Vector3(cos(ang) * 0.05, h * 0.5, sin(ang) * 0.05)
			mi2.rotation_degrees = Vector3(rng.randf_range(-8.0, 8.0), rad_to_deg(-ang),
				rng.randf_range(-12.0, 12.0))
			mi2.material_override = MeshKit.leaf_mat(
				Palette.LEAF_DARK.lerp(Palette.GRASS_DARK, rng.randf() * 0.6).darkened(0.10))
			g.add_child(mi2)


func _process(dt: float) -> void:
	_t += dt
	for i in _kelp.size():
		var g := _kelp[i]
		var ph := _kelp_phase[i]
		g.rotation_degrees = Vector3(
			sin(_t * 1.15 + ph) * 7.0,
			g.rotation_degrees.y,
			sin(_t * 1.65 + ph * 1.7) * 12.0)
	# 海风：棕榈整体轻摆
	for i in _palms.size():
		var p := _palms[i]
		var ph2 := _palm_phase[i]
		p.rotation_degrees = Vector3(
			sin(_t * 1.05 + ph2) * 2.2,
			_palm_yaw[i],
			sin(_t * 0.85 + ph2 * 1.4) * 2.8)
	# 风铃：摆动 + 偶尔响一声
	for i in _chimes.size():
		var c := _chimes[i]
		var ph3 := float(i) * 1.7
		c.rotation_degrees = Vector3(sin(_t * 2.3 + ph3) * 7.5, 0.0, sin(_t * 1.9 + ph3) * 5.5)
	_chime_timer -= dt
	if _chime_timer <= 0.0:
		_chime_timer = randf_range(3.2, 8.0)
		SoundKit.play("chime", randf_range(1.7, 2.5), -25.0)
	_update_fish(dt)


# ---------------- 珊瑚 ----------------
func _build_coral() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var cols := [Palette.CORAL, Palette.PINK, Color("efa9a0"), Color("b98ad8")]
	for k in 18:
		var a := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(8.6, 12.4)
		var x := cos(a) * r
		var z := sin(a) * r
		var y := terrain_y(x, z)
		if y > -0.12:
			continue
		var col: Color = cols[rng.randi() % cols.size()]
		var g := Node3D.new()
		g.position = Vector3(x, y, z)
		g.rotation_degrees.y = rng.randf_range(0.0, 360.0)
		add_child(g)
		var kind := rng.randi() % 3
		if kind == 0:
			# 脑珊瑚：压扁的球
			MeshKit.add_sphere(g, rng.randf_range(0.26, 0.44), Vector3(0, 0.08, 0),
				col, Vector3(1.0, 0.5, 1.0), 7, 5)
		elif kind == 1:
			# 枝状珊瑚：几根小锥
			for i in 4:
				var ang := TAU * float(i) / 4.0 + rng.randf_range(-0.4, 0.4)
				var h := rng.randf_range(0.34, 0.78)
				MeshKit.add_cyl(g, 0.02, 0.06, h,
					Vector3(cos(ang) * 0.08, h * 0.5, sin(ang) * 0.08), col,
					Vector3(rng.randf_range(-26.0, 26.0), 0.0, rng.randf_range(-26.0, 26.0)), 5)
		else:
			# 扇珊瑚：压扁的一片
			MeshKit.add_sphere(g, 0.36, Vector3(0, 0.24, 0), col,
				Vector3(1.25, 1.0, 0.22), 6, 4)


# ---------------- 鱼群 ----------------
func _build_fish() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	_fish_root = Node3D.new()
	_fish_root.name = "FishSchool"
	add_child(_fish_root)
	var cols := [Color("4f9fc4"), Color("3d8fb0"), Color("e8934a"), Color("7fbdd8")]
	for i in 16:
		var a := TAU * float(i) / 16.0 + rng.randf_range(-0.25, 0.25)
		var rr := rng.randf_range(0.35, 1.55)
		var base := Vector3(FISH_R + cos(a) * rr, FISH_Y + rng.randf_range(-0.16, 0.16),
			sin(a) * rr * 0.8)
		var g := Node3D.new()
		g.position = base
		g.rotation_degrees = Vector3(0, rng.randf_range(-30.0, 30.0), 0)
		_fish_root.add_child(g)
		_fish.append(g)
		_fish_base.append(base)
		_fish_off.append(Vector3.ZERO)
		_fish_vel.append(Vector3.ZERO)
		_fish_phase.append(rng.randf_range(0.0, TAU))
		var col: Color = cols[rng.randi() % cols.size()]
		var m := MeshKit.mat(col, 0.42, 0.25, col, 0.85)
		var body := SphereMesh.new()
		body.radius = 0.22
		body.height = 0.44
		body.radial_segments = 7
		body.rings = 4
		var mi := MeshInstance3D.new()
		mi.mesh = body
		mi.scale = Vector3(1.15, 0.40, 0.52)
		mi.material_override = m
		g.add_child(mi)
		var tail := PrismMesh.new()
		tail.size = Vector3(0.22, 0.17, 0.025)
		var ti := MeshInstance3D.new()
		ti.mesh = tail
		ti.position = Vector3(0.26, 0.0, 0.0)
		ti.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		ti.material_override = m
		g.add_child(ti)


func _update_fish(dt: float) -> void:
	if _fish_root == null or _fish.is_empty():
		return
	_fish_orbit += dt * 0.15
	_fish_root.rotation_degrees.y = rad_to_deg(_fish_orbit)
	var center := Vector3.ZERO
	for i in _fish.size():
		var g := _fish[i]
		# 散开后回弹
		var off := _fish_off[i] + _fish_vel[i] * dt
		var vel := _fish_vel[i] * 0.92
		off = off.lerp(Vector3.ZERO, clampf(dt * 0.55, 0.0, 1.0))
		_fish_off[i] = off
		_fish_vel[i] = vel
		var p := _fish_base[i] + off
		p.y += sin(_t * 2.2 + _fish_phase[i]) * 0.035
		p.y = minf(p.y, -0.05)   # 别跳出水面
		g.position = p
		g.rotation_degrees.z = sin(_t * 3.0 + _fish_phase[i]) * 9.0
		center += g.global_position
	fish_center = center / float(_fish.size())


## 点一下鱼群 → 惊散（过两三秒自己聚回来）
func scatter_fish() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in _fish.size():
		var dir := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.5, 0.8),
			rng.randf_range(-1.0, 1.0))
		if dir.length() < 0.001:
			dir = Vector3.RIGHT
		_fish_vel[i] = dir.normalized() * rng.randf_range(2.4, 4.6) + Vector3(0, 0.7, 0)


func _terr_color(h: float, x: float, z: float) -> Color:
	var tint := sin(x * 2.3 + z * 1.7) * 0.5 + 0.5
	if h < -0.05:
		return Palette.SAND_WET.lerp(Palette.SAND_DEEP, clampf(-h, 0.0, 1.0) * 0.7)
	if h < 0.42:
		return Palette.SAND_WET.lerp(Palette.SAND, clampf((h + 0.05) / 0.5, 0.0, 1.0))
	if h < 0.85:
		return Palette.SAND.lerp(Palette.GRASS, smoothstep(0.42, 0.85, h))
	if h < 1.15:
		return Palette.GRASS.lerp(Palette.GRASS_MID, smoothstep(0.85, 1.15, h))
	var g := Palette.GRASS_MID.lerp(Palette.GRASS_DARK, clampf(tint * 0.55 + (h - 1.15) * 0.12, 0.0, 1.0))
	return g


func _terr_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ca: Color, cb: Color, cc: Color, want: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	var nrm := (b - a).cross(c - a)
	if nrm.length() < 1e-9:
		return
	# Godot 正面为顺时针：叉积法线需与 want 反向
	if nrm.normalized().dot(want) > 0.0:
		var tp := b
		b = c
		c = tp
		var tc := cb
		cb = cc
		cc = tc
		var tu := ub
		ub = uc
		uc = tu
	st.set_color(ca)
	st.set_uv(ua)
	st.add_vertex(a)
	st.set_color(cb)
	st.set_uv(ub)
	st.add_vertex(b)
	st.set_color(cc)
	st.set_uv(uc)
	st.add_vertex(c)


# ---------------- 弥尔丹之屋（精灵工匠行会） ----------------
var _blossom: ShaderMaterial = null


## 花朵材质：三渲二 + 逐实例颜色，不加描边（几千朵花加线会糊成一片）
func _blossom_mat() -> ShaderMaterial:
	if _blossom != null:
		return _blossom
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/toon.gdshader")
	m.set_shader_parameter("albedo_col", Color(0.90, 0.79, 0.84))
	m.set_shader_parameter("use_vcolor", true)
	m.set_shader_parameter("roughness", 0.90)
	m.set_shader_parameter("spec_gain", 0.15)
	_blossom = m
	return m

var _crown_cache := {}


## 沿折线堆出渐细的树干/树枝：每段一个圆柱，按段方向旋转
func _limb(parent: Node3D, pts: Array, r0: float, r1: float, col: Color) -> void:
	var n := pts.size()
	for i in n - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var ta := float(i) / float(n - 1)
		var tb := float(i + 1) / float(n - 1)
		var ra := lerpf(r0, r1, ta)
		var rb := lerpf(r0, r1, tb)
		var d := b - a
		var mi := MeshKit.add_cyl(parent, rb, ra, d.length() + 0.06, (a + b) * 0.5, col,
			Vector3.ZERO, 8)
		if d.length() > 0.001:
			mi.basis = Basis(Quaternion(Vector3.UP, d.normalized()))


## 树冠专用材质：三渲二 + 极细描边（叶球之间不要出现粗黑线）
func _crown_mat(col: Color) -> ShaderMaterial:
	var key := col.to_html()
	if _crown_cache.has(key):
		return _crown_cache[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/toon.gdshader")
	m.set_shader_parameter("albedo_col", col)
	m.set_shader_parameter("roughness", 0.88)
	m.set_shader_parameter("spec_gain", 0.20)
	m.next_pass = MeshKit.outline_mat(0.0006)
	_crown_cache[key] = m
	return m

# ---------------- 童话树屋（弥尔丹之屋） ----------------
## 一棵巨大的老树：树干挖出空心拱洞，树腰搭木屋、带栏杆阳台和盘旋楼梯，
## 树冠是紫绿相间的叶团，檐下挂灯笼和风铃。
func _build_treehouse() -> void:
	var cx := 1.5
	var cz := -3.0
	var y := terrain_y(cx, cz)
	var g := Node3D.new()
	g.name = "Treehouse"
	g.position = Vector3(cx, y, cz)
	g.rotation_degrees.y = -7.0
	g.scale = Vector3(0.84, 0.84, 0.84)
	add_child(g)
	hall_pos = Vector3(cx, y, cz)

	# ================= 大树 =================
	# 主干：一条微微弯曲、逐渐收细的折线（每段一个圆柱、按方向旋转）
	_limb(g, [Vector3(0.00, 0.00, 0.00), Vector3(0.22, 1.05, 0.08),
		Vector3(0.10, 2.15, 0.02), Vector3(-0.22, 3.25, -0.06),
		Vector3(-0.34, 4.35, -0.10), Vector3(-0.18, 5.35, -0.04)],
		1.55, 0.66, Palette.BARK)
	# 树皮竖向棱（几块薄板，增加体量感）
	for i in 7:
		var a := TAU * float(i) / 7.0 + 0.3
		var px := cos(a) * 1.26
		var pz := sin(a) * 1.26
		MeshKit.add_box(g, Vector3(0.20, 3.9, 0.15), Vector3(px, 2.1, pz), Palette.BARK_DARK,
			Vector3(0, -rad_to_deg(a) + 90.0, 0))
	# 盘根（6 条向外张开的粗根）
	for i in 6:
		var a2 := TAU * float(i) / 6.0 + 0.22
		var rx := cos(a2) * 1.15
		var rz := sin(a2) * 1.15
		MeshKit.add_cyl(g, 0.10, 0.52, 1.55,
			Vector3(rx * 1.5, 0.42, rz * 1.5), Palette.BARK,
			Vector3(rad_to_deg(sin(a2) * 0.90), 0.0, -rad_to_deg(cos(a2) * 0.90)), 7)

	# ---- 树洞（正面拱门） ----
	MeshKit.add_box(g, Vector3(1.55, 1.95, 1.10), Vector3(0, 0.98, 0.85), Palette.BARK_DARK)
	MeshKit.add_box(g, Vector3(1.20, 1.62, 0.80), Vector3(0, 0.82, 1.02), Color("2a1d18"))
	# 洞里的暖光（里面像是有人住）
	var inner := MeshKit.add_box(g, Vector3(0.95, 1.30, 0.06), Vector3(0, 0.74, 0.86),
		Palette.WINDOW_GLOW)
	inner.material_override = MeshKit.emissive(Palette.WINDOW_GLOW, 0.55)
	# 拱券：7 块石头沿半圆排
	for i in 7:
		var t := -PI * 0.5 + PI * float(i) / 6.0
		MeshKit.add_box(g, Vector3(0.36, 0.26, 0.34),
			Vector3(sin(t) * 0.92, 1.62 + cos(t) * 0.92, 1.12), Palette.BARK_LIGHT,
			Vector3(0, 0, -rad_to_deg(t)))

	# ================= 树腰木屋 =================
	var fy := 3.05      # 阳台地板高度
	# 阳台地板 + 托梁
	MeshKit.add_box(g, Vector3(3.30, 0.14, 1.60), Vector3(0.15, fy, 1.30), Palette.TIMBER)
	for i in 5:
		MeshKit.add_box(g, Vector3(0.12, 0.30, 1.70),
			Vector3(-1.35 + float(i) * 0.75, fy - 0.22, 1.30), Palette.TIMBER_DARK,
			Vector3(14, 0, 0))
	# 栏杆
	MeshKit.add_box(g, Vector3(3.30, 0.08, 0.08), Vector3(0.15, fy + 0.62, 2.02), Palette.TIMBER)
	for i in 9:
		MeshKit.add_cyl(g, 0.022, 0.022, 0.60,
			Vector3(-1.35 + float(i) * 0.375, fy + 0.32, 2.02), Palette.TIMBER_DARK, Vector3.ZERO, 4)
	MeshKit.add_box(g, Vector3(0.10, 0.70, 0.10), Vector3(-1.50, fy + 0.36, 2.02), Palette.TIMBER)
	MeshKit.add_box(g, Vector3(0.10, 0.70, 0.10), Vector3(1.80, fy + 0.36, 2.02), Palette.TIMBER)

	# 屋体（背靠在树干上）
	MeshKit.add_box(g, Vector3(2.45, 1.75, 1.55), Vector3(0.10, fy + 0.95, 0.62), Palette.TIMBER)
	# 木构架（深色细梁，童话屋的关键）
	for sx in [-1.05, 1.05]:
		MeshKit.add_box(g, Vector3(0.09, 1.80, 0.09), Vector3(0.10 + sx, fy + 0.95, 1.42),
			Palette.TIMBER_DARK)
	MeshKit.add_box(g, Vector3(2.30, 0.09, 0.09), Vector3(0.10, fy + 1.72, 1.42), Palette.TIMBER_DARK)
	MeshKit.add_box(g, Vector3(0.09, 1.10, 0.09), Vector3(0.10, fy + 1.15, 1.42), Palette.TIMBER_DARK)
	MeshKit.add_box(g, Vector3(0.09, 2.10, 0.09), Vector3(-0.72, fy + 1.15, 1.42), Palette.TIMBER_DARK,
		Vector3(0, 0, 32))
	MeshKit.add_box(g, Vector3(0.09, 2.10, 0.09), Vector3(0.92, fy + 1.15, 1.42), Palette.TIMBER_DARK,
		Vector3(0, 0, -32))

	# 大拱窗（暖光）
	var bigwin := MeshKit.add_sphere(g, 0.62, Vector3(0.10, fy + 1.02, 1.40), Palette.WINDOW_GLOW,
		Vector3(1.05, 1.15, 0.08), 10, 6)
	bigwin.material_override = MeshKit.emissive(Palette.WINDOW_GLOW, 1.5)
	# 窗棂
	MeshKit.add_box(g, Vector3(0.05, 1.35, 0.05), Vector3(0.10, fy + 1.02, 1.46), Palette.TIMBER_DARK)
	MeshKit.add_box(g, Vector3(1.25, 0.05, 0.05), Vector3(0.10, fy + 1.02, 1.46), Palette.TIMBER_DARK)
	MeshKit.add_box(g, Vector3(1.25, 0.05, 0.05), Vector3(0.10, fy + 1.52, 1.46), Palette.TIMBER_DARK)
	# 侧墙圆窗
	for sx2 in [-0.78, 0.98]:
		var sw := MeshKit.add_sphere(g, 0.20, Vector3(0.10 + sx2, fy + 1.28, 1.41),
			Palette.WINDOW_GLOW, Vector3(1.0, 1.0, 0.10), 8, 5)
		sw.material_override = MeshKit.emissive(Palette.WINDOW_GLOW, 1.2)

	# 陡坡屋顶
	MeshKit.add_box(g, Vector3(2.95, 0.15, 1.60), Vector3(0.10, fy + 2.30, 1.02), Palette.SHINGLE,
		Vector3(41, 0, 0))
	MeshKit.add_box(g, Vector3(2.95, 0.15, 1.60), Vector3(0.10, fy + 2.30, 0.22), Palette.SHINGLE,
		Vector3(-41, 0, 0))
	MeshKit.add_box(g, Vector3(3.05, 0.14, 0.26), Vector3(0.10, fy + 2.68, 0.62),
		Palette.SHINGLE_DARK)
	# 山墙（前后的三角面用两块斜板收）
	MeshKit.add_box(g, Vector3(2.45, 0.62, 0.10), Vector3(0.10, fy + 2.05, 1.40), Palette.TIMBER)
	# 屋顶上的青苔
	for i in 5:
		MeshKit.add_sphere(g, 0.16, Vector3(-0.9 + float(i) * 0.5, fy + 2.46,
			0.55 + float(i % 2) * 0.42), Palette.MOSS, Vector3(1.5, 0.5, 1.2), 6, 4)
	# 烟囱
	MeshKit.add_cyl(g, 0.13, 0.16, 0.75, Vector3(-0.85, fy + 2.75, 0.20),
		Palette.BARK_DARK, Vector3.ZERO, 6)
	MeshKit.add_steam(g, Vector3(-0.85, fy + 3.15, 0.20), 10)

	# ---- 盘旋楼梯（从地面绕到阳台） ----
	for i in 11:
		var t2 := float(i) / 10.0
		var a3 := -0.35 + t2 * 1.95
		var rad := 2.05 - t2 * 0.18
		MeshKit.add_box(g, Vector3(0.62, 0.10, 0.46),
			Vector3(cos(a3) * rad, 0.35 + t2 * (fy - 0.35), sin(a3) * rad),
			Palette.TIMBER, Vector3(0, -rad_to_deg(a3) + 90.0, 0))
	# 楼梯扶手柱
	for i in 5:
		var t3 := float(i) / 4.0
		var a4 := -0.35 + t3 * 1.95
		MeshKit.add_cyl(g, 0.035, 0.04, 0.85,
			Vector3(cos(a4) * 2.22, 0.75 + t3 * (fy - 0.30), sin(a4) * 2.22),
			Palette.TIMBER_DARK, Vector3.ZERO, 4)

		# ================= 樱花冠（MultiMesh 千朵花） =================
	# 思路：花冠不是一个"粉色体积"，而是几千朵小花堆出来的。
	# 每朵花 = 一个压扁的小球实例（MultiMesh），逐实例颜色 → 层次和颗粒感。
	var brng := RandomNumberGenerator.new()
	brng.seed = 20250601
	var crown_c := Vector3(0.0, 6.95, 0.0)
	# 额外四根枝：伸到花冠外侧，让深色枝干能在花间露出来
	var extra: Array = [
		[[Vector3(-0.30, 5.10, 0.10), Vector3(-1.60, 5.90, -0.90), Vector3(-2.60, 6.55, -1.50)],
			0.30, 0.06],
		[[Vector3(-0.20, 5.30, 0.00), Vector3(1.50, 6.00, 0.90), Vector3(2.60, 6.45, 1.40)],
			0.28, 0.06],
		[[Vector3(-0.30, 5.40, 0.00), Vector3(0.20, 6.40, 1.40), Vector3(0.60, 6.90, 2.50)],
			0.26, 0.05],
		[[Vector3(-0.30, 5.20, 0.00), Vector3(-1.20, 6.20, 1.20), Vector3(-2.00, 6.70, 2.10)],
			0.26, 0.05],
	]
	for eb in extra:
		_limb(g, eb[0], float(eb[1]), float(eb[2]), Palette.BARK_DARK)

	# 花簇中心：扁球壳上分布（偏上半球），36 个簇
	var lobes: Array = []
	for i in 42:
		var a9 := brng.randf_range(0.0, TAU)
		var e9 := brng.randf_range(-0.42, 1.15)
		var rr9 := brng.randf_range(0.45, 1.0)
		var dir9 := Vector3(cos(a9) * cos(e9), sin(e9) * 0.68, sin(a9) * cos(e9))
		lobes.append([crown_c + dir9 * (2.95 * rr9), brng.randf_range(0.44, 0.92)])

	# ---- 撒花 ----
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var bloom := SphereMesh.new()
	bloom.radius = 1.0
	bloom.height = 2.0
	bloom.radial_segments = 6
	bloom.rings = 3
	mm.mesh = bloom
	var xf: Array[Transform3D] = []
	var cols: Array[Color] = []
	for lb in lobes:
		var lc: Vector3 = lb[0]
		var lr: float = lb[1]
		var n := brng.randi_range(48, 78)
		for k in n:
			var o := Vector3(brng.randf_range(-1.0, 1.0), brng.randf_range(-1.0, 1.0),
				brng.randf_range(-1.0, 1.0))
			if o.length() > 1.0:
				o = o.normalized()
			var pos := lc + o * lr
			var s := brng.randf_range(0.105, 0.225)
			var b := Basis(Vector3.UP, brng.randf_range(0.0, TAU)).scaled(
				Vector3(s, s * 0.85, s))
			xf.append(Transform3D(b, pos))
			# 逐实例颜色：上亮下暗，三档粉随机
			var col := Color("f4b6cc")
			var roll := brng.randf()
			if roll < 0.38:
				col = Color("f9d2e1")
			elif roll < 0.64:
				col = Color("e9a0bc")
			if pos.y > crown_c.y + 0.45:
				col = col.lightened(0.05)
			elif pos.y < crown_c.y - 0.55:
				col = col.darkened(0.07)
			cols.append(col)
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Blossoms"
	mmi.multimesh = mm
	mmi.material_override = _blossom_mat()
	g.add_child(mmi)

	# ---- 边缘的半透明花瓣（逆光会亮） ----
	var petal_mat := ShaderMaterial.new()
	petal_mat.shader = load("res://shaders/petal.gdshader")
	var prng := RandomNumberGenerator.new()
	prng.seed = 4477
	for i in 44:
		var a8 := prng.randf_range(0.0, TAU)
		var e8 := prng.randf_range(-0.45, 1.10)
		var rad8 := prng.randf_range(2.95, 3.95)
		var ppos := Vector3(cos(a8) * cos(e8) * rad8, crown_c.y + sin(e8) * rad8 * 0.70,
			sin(a8) * cos(e8) * rad8)
		var q := QuadMesh.new()
		q.size = Vector2(prng.randf_range(0.85, 1.35), prng.randf_range(0.62, 0.98))
		var pmi := MeshInstance3D.new()
		pmi.mesh = q
		pmi.position = ppos
		pmi.rotation_degrees = Vector3(prng.randf_range(-75.0, 75.0),
			prng.randf_range(0.0, 360.0), prng.randf_range(-75.0, 75.0))
		pmi.material_override = petal_mat
		g.add_child(pmi)

	# ---- 飘落的花瓣 ----
	MeshKit.add_petals(g, Vector3(0.0, 6.8, 0.0), Vector3(3.6, 1.2, 3.6), 220)

	# ---- 灯笼 ----
	for lp in [Vector3(-1.95, 1.95, 1.75), Vector3(2.05, 1.55, 1.35),
			Vector3(0.85, fy + 1.55, 2.10), Vector3(-1.15, fy + 1.70, 2.10)]:
		MeshKit.add_cyl(g, 0.012, 0.012, 0.34, lp + Vector3(0, 0.24, 0), Palette.BARK_DARK,
			Vector3.ZERO, 4)
		MeshKit.add_box(g, Vector3(0.17, 0.22, 0.17), lp + Vector3(0, 0.02, 0),
			Palette.LANTERN).material_override = MeshKit.emissive(Palette.LANTERN, 1.9)

	# ---- 阳台下挂风铃 ----
	for cp in [Vector3(-1.28, fy + 0.62, 2.04), Vector3(1.55, fy + 0.62, 2.04)]:
		var ch := Node3D.new()
		ch.position = cp
		g.add_child(ch)
		_chimes.append(ch)
		MeshKit.add_cyl(ch, 0.006, 0.006, 0.42, Vector3(0, -0.21, 0), Palette.SILVER, Vector3.ZERO, 4)
		for i in 3:
			var a7 := TAU * float(i) / 3.0
			MeshKit.add_cyl(ch, 0.014, 0.014, 0.20 + float(i) * 0.05,
				Vector3(cos(a7) * 0.055, -0.46 - float(i) * 0.02, sin(a7) * 0.055),
				Palette.GOLD, Vector3.ZERO, 5)
		MeshKit.add_cyl(ch, 0.0, 0.055, 0.07, Vector3(0, -0.62, 0), Palette.GOLD, Vector3.ZERO, 6)




# ---------------- 铁匠铺 ----------------
func _build_forge() -> void:
	var x := forge_pos.x
	var z := forge_pos.z
	var y := terrain_y(x, z)
	forge_pos = Vector3(x, y, z)
	var g := Node3D.new()
	g.name = "Forge"
	g.position = Vector3(x, y, z)
	g.rotation_degrees.y = 24.0
	add_child(g)

	# 工作台
	MeshKit.add_box(g, Vector3(1.9, 0.13, 0.95), Vector3(0, 0.86, 0), Palette.WOOD)
	for sx in [-0.8, 0.8]:
		for sz in [-0.35, 0.35]:
			MeshKit.add_box(g, Vector3(0.1, 0.86, 0.1), Vector3(sx, 0.43, sz), Palette.WOOD_DARK)
	# 台面上的锤子
	MeshKit.add_cyl(g, 0.035, 0.045, 0.55, Vector3(0.55, 0.98, 0.2), Palette.WOOD_DARK, Vector3(0, 0, 78), 6)
	MeshKit.add_box(g, Vector3(0.26, 0.13, 0.13), Vector3(0.78, 1.05, 0.2), Palette.STEEL_DARK)

	# 铁砧
	var anvil := Node3D.new()
	anvil.position = Vector3(-1.45, 0, 0.35)
	anvil.rotation_degrees.y = -18.0
	g.add_child(anvil)
	MeshKit.add_cyl(anvil, 0.26, 0.32, 0.5, Vector3(0, 0.25, 0), Palette.WOOD_DEEP, Vector3.ZERO, 7)
	MeshKit.add_box(anvil, Vector3(0.62, 0.20, 0.3), Vector3(0, 0.6, 0), Palette.STEEL_DARK)
	MeshKit.add_box(anvil, Vector3(0.34, 0.14, 0.24), Vector3(-0.1, 0.74, 0), Palette.STEEL)
	MeshKit.add_cyl(anvil, 0.02, 0.10, 0.34, Vector3(0.42, 0.7, 0), Palette.STEEL, Vector3(0, 0, -90), 6)

	# 炭炉
	var furn := Node3D.new()
	furn.position = Vector3(1.5, 0, -0.7)
	g.add_child(furn)
	MeshKit.add_box(furn, Vector3(1.0, 0.95, 0.95), Vector3(0, 0.47, 0), Palette.STONE_DARK)
	MeshKit.add_box(furn, Vector3(1.06, 0.12, 1.0), Vector3(0, 0.98, 0), Palette.STONE)
	var ember := MeshKit.add_box(furn, Vector3(0.72, 0.34, 0.72), Vector3(0, 1.02, 0), Palette.EMBER)
	ember.material_override = MeshKit.emissive(Palette.EMBER, 2.6)
	MeshKit.add_embers(furn, Vector3(0, 1.12, 0), 30)
	MeshKit.add_cyl(furn, 0.1, 0.12, 0.9, Vector3(0.3, 1.6, -0.3), Palette.STONE_DARK, Vector3.ZERO, 6)
	var ol := OmniLight3D.new()
	ol.light_color = Palette.EMBER
	ol.light_energy = 3.0
	ol.omni_range = 3.2
	ol.position = Vector3(1.5, 1.3, -0.7)
	g.add_child(ol)

	# 淬火油桶
	var barrel := Node3D.new()
	barrel.position = Vector3(-1.9, 0, -1.5)
	g.add_child(barrel)
	MeshKit.add_cyl(barrel, 0.36, 0.33, 0.75, Vector3(0, 0.38, 0), Palette.WOOD_DARK, Vector3.ZERO, 9)
	MeshKit.add_cyl(barrel, 0.30, 0.30, 0.06, Vector3(0, 0.72, 0), Color("7a5a2c"), Vector3.ZERO, 9)
	for k in 2:
		MeshKit.add_cyl(barrel, 0.375, 0.375, 0.06, Vector3(0, 0.2 + k * 0.34, 0), Palette.STEEL_DARK, Vector3.ZERO, 9)
	MeshKit.add_steam(barrel, Vector3(0, 0.82, 0), 16)

	# 砂轮机
	var gs := Node3D.new()
	gs.position = Vector3(0.1, 0, -1.55)
	gs.rotation_degrees.y = 15.0
	g.add_child(gs)
	MeshKit.add_cyl(gs, 0.28, 0.28, 0.12, Vector3(0, 0.42, 0), Palette.STONE, Vector3(0, 0, 90), 10)
	MeshKit.add_cyl(gs, 0.03, 0.03, 0.7, Vector3(0, 0.42, 0), Palette.WOOD_DARK, Vector3(0, 0, 90), 5)
	MeshKit.add_box(gs, Vector3(0.12, 0.5, 0.4), Vector3(-0.3, 0.2, 0), Palette.WOOD_DARK)
	MeshKit.add_box(gs, Vector3(0.12, 0.5, 0.4), Vector3(0.3, 0.2, 0), Palette.WOOD_DARK)

	# 工具架
	for k in 4:
		MeshKit.add_cyl(g, 0.02, 0.02, 0.6, Vector3(-2.2 + k * 0.16, 0.5, -0.4),
			Palette.STONE, Vector3(0, 0, 12 - k * 8), 5)


# ---------------- 木栈桥 + 码头 ----------------
func _build_pier() -> void:
	var g := Node3D.new()
	g.name = "Pier"
	add_child(g)
	# 从沙滩下到水面的斜坡栈道
	var xr := 4.2
	var z0 := 4.9
	var z1 := 7.3
	var n := 5
	var y_start := terrain_y(xr, z0) + 0.14
	for k in n:
		var t := float(k) / float(n - 1)
		var z := lerpf(z0, z1, t)
		var y := lerpf(y_start, 0.40, t)
		MeshKit.add_box(g, Vector3(1.6, 0.12, 0.62), Vector3(xr, y, z),
			Palette.WOOD.lerp(Palette.WOOD_DARK, t * 0.5))
		if k == 0 or k == n - 1:
			for sx in [-0.7, 0.7]:
				MeshKit.add_cyl(g, 0.08, 0.09, 2.0, Vector3(xr + sx, y - 1.0, z),
					Palette.WOOD_DARK, Vector3.ZERO, 6)

	# 水里的码头平台
	var px := 4.9
	var pz := 8.5
	var py := 0.34
	for i in 4:
		for j in 3:
			MeshKit.add_box(g, Vector3(0.74, 0.12, 0.86),
				Vector3(px - 1.15 + float(i) * 0.78, py, pz - 0.9 + float(j) * 0.92),
				Palette.WOOD.lerp(Palette.WOOD_DARK, float((i + j) % 2) * 0.35))
	for sx in [-1.5, 1.5]:
		for sz in [-1.2, 1.2]:
			MeshKit.add_cyl(g, 0.1, 0.12, 2.6, Vector3(px + sx, py - 1.3, pz + sz),
				Palette.WOOD_DARK, Vector3.ZERO, 6)

	# 系船柱
	MeshKit.add_cyl(g, 0.09, 0.10, 0.42, Vector3(px + 1.35, py + 0.2, pz + 0.9),
		Palette.WOOD_DEEP, Vector3.ZERO, 7)
	MeshKit.add_sphere(g, 0.11, Vector3(px + 1.35, py + 0.45, pz + 0.9),
		Palette.WOOD_DEEP, Vector3.ONE, 6, 4)

	# 码头上的货箱 / 木桶（市场的感觉）
	MeshKit.add_box(g, Vector3(0.52, 0.44, 0.52), Vector3(px - 1.1, py + 0.28, pz + 0.6),
		Palette.WOOD_DARK, Vector3(0, 14, 0))
	MeshKit.add_box(g, Vector3(0.42, 0.34, 0.42), Vector3(px - 1.05, py + 0.72, pz - 0.35),
		Palette.WOOD, Vector3(0, -22, 0))
	MeshKit.add_cyl(g, 0.22, 0.2, 0.5, Vector3(px + 0.45, py + 0.31, pz - 0.95),
		Palette.WOOD_DEEP, Vector3.ZERO, 8)

	# 灯柱
	MeshKit.add_cyl(g, 0.055, 0.065, 1.75, Vector3(px - 1.35, py + 0.95, pz + 1.1),
		Palette.WOOD_DARK, Vector3.ZERO, 6)
	var lamp := MeshKit.add_sphere(g, 0.13, Vector3(px - 1.35, py + 1.9, pz + 1.1),
		Palette.EMBER_HOT, Vector3.ONE, 7, 5)
	lamp.material_override = MeshKit.emissive(Palette.EMBER_HOT, 1.8)
	var ol := OmniLight3D.new()
	ol.light_color = Palette.EMBER_HOT
	ol.light_energy = 2.2
	ol.omni_range = 4.0
	ol.position = Vector3(px - 1.35, py + 1.9, pz + 1.1)
	g.add_child(ol)


## 码头入口：两根柱子 + 招牌（交互热点在这里）
func _build_dock_gate() -> void:
	var x := 4.2
	var z := 4.9
	var y := terrain_y(x, z)
	dock_pos = Vector3(x, y + 2.3, z)
	var g := Node3D.new()
	g.name = "DockGate"
	g.position = Vector3(x, y, z)
	g.rotation_degrees.y = 6.0
	add_child(g)
	for sx in [-1.05, 1.05]:
		MeshKit.add_cyl(g, 0.09, 0.11, 2.3, Vector3(sx, 1.15, 0), Palette.WOOD_DARK, Vector3.ZERO, 6)
	MeshKit.add_box(g, Vector3(2.5, 0.16, 0.2), Vector3(0, 2.26, 0), Palette.WOOD)
	MeshKit.add_box(g, Vector3(1.56, 0.52, 0.08), Vector3(0, 1.92, 0.13), Palette.WOOD_DEEP)
	for k in 2:
		MeshKit.add_box(g, Vector3(1.1, 0.05, 0.1), Vector3(0, 2.02 - float(k) * 0.16, 0.19),
			Palette.SAND)


## 停靠在码头边的小船（程序化船壳）
func _build_boat() -> void:
	var g := Node3D.new()
	g.name = "Boat"
	g.position = Vector3(6.66, 0.03, 8.15)
	g.rotation_degrees.y = -90.0   # 船头朝 +Z，靠向系船柱
	add_child(g)

	var L := 1.15
	var n := 14
	var segs := 6
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	var floors: Array = []
	for i in n + 1:
		var t := float(i) / float(n)
		var x := lerpf(-L, L, t)
		var k := clampf(1.0 - pow(absf(x / L), 1.7), 0.0, 1.0)
		var w := 0.42 * pow(k, 0.55)
		var depth := 0.26 * pow(k, 0.45) + 0.05
		var ring: Array[Vector3] = []
		for j in segs + 1:
			var a := PI * float(j) / float(segs)
			ring.append(Vector3(x, 0.10 - depth * sin(a), w * cos(a)))
		rings.append(ring)
		floors.append([
			Vector3(x, 0.10 - depth * 0.55, -w * 0.80),
			Vector3(x, 0.10 - depth * 0.55, w * 0.80)
		])

	for i in n:
		var cx := lerpf(-L, L, (float(i) + 0.5) / float(n))
		for j in segs:
			var a0: Vector3 = rings[i][j]
			var a1: Vector3 = rings[i][j + 1]
			var b0: Vector3 = rings[i + 1][j]
			var b1: Vector3 = rings[i + 1][j + 1]
			var ctr := Vector3(cx, 0.10, 0.0)
			var want := ((a0 + a1 + b0 + b1) * 0.25) - ctr
			_boat_tri(st, a0, b0, b1, want)
			_boat_tri(st, a0, b1, a1, want)

	for i in n:
		var f0: Array = floors[i]
		var f1: Array = floors[i + 1]
		_boat_tri(st, f0[0], f1[0], f1[1], Vector3.UP)
		_boat_tri(st, f0[0], f1[1], f0[1], Vector3.UP)

	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = MeshKit.mat(Palette.WOOD, 0.82)
	g.add_child(mi)

	# 船内横板
	for bx in [-0.45, 0.15, 0.62]:
		MeshKit.add_box(g, Vector3(0.12, 0.06, 0.62), Vector3(bx, 0.02, 0), Palette.WOOD_DARK)
	# 桨
	MeshKit.add_box(g, Vector3(1.5, 0.05, 0.09), Vector3(-0.1, 0.12, 0.3),
		Palette.TRUNK_DARK, Vector3(0, 8, 4))
	# 软垫
	MeshKit.add_box(g, Vector3(0.34, 0.1, 0.5), Vector3(-0.72, 0.08, 0),
		Palette.CORAL, Vector3(0, 4, 0))

	# 缆绳：船头 → 系船柱
	var bow := g.position + Vector3(0.0, 0.14, 1.05)
	var post := Vector3(6.25, 0.52, 9.4)
	var rope := MeshKit.add_box(self, Vector3(0.035, 0.035, 1.0),
		bow.lerp(post, 0.5), Color("d9c9a6"))
	rope.scale = Vector3(1.0, 1.0, bow.distance_to(post))
	rope.look_at(post, Vector3.UP)


func _boat_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, want: Vector3) -> void:
	var nrm := (b - a).cross(c - a)
	if nrm.length() < 1e-9:
		return
	if nrm.normalized().dot(want.normalized()) > 0.0:
		var tp := b
		b = c
		c = tp
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


# ---------------- 成品展示架 ----------------
func _build_rack() -> void:
	var x := -5.4
	var z := -1.0
	var y := terrain_y(x, z)
	var g := Node3D.new()
	g.name = "Rack"
	g.position = Vector3(x, y, z)
	rack_pos = Vector3(x, y, z)
	g.rotation_degrees.y = 28.0
	add_child(g)
	MeshKit.add_box(g, Vector3(3.0, 0.14, 0.16), Vector3(0, 1.55, 0), Palette.WOOD_DARK)
	MeshKit.add_box(g, Vector3(3.0, 0.14, 0.16), Vector3(0, 0.25, 0), Palette.WOOD_DARK)
	for sx in [-1.4, 1.4]:
		MeshKit.add_box(g, Vector3(0.16, 1.7, 0.16), Vector3(sx, 0.85, 0), Palette.WOOD)
	# 三个刀位
	for k in 3:
		var slot := Node3D.new()
		slot.position = Vector3(-0.95 + k * 0.95, 0.95, 0.02)
		g.add_child(slot)
		rack_slots.append(slot)


# ---------------- 植被与石头 ----------------
func _scatter() -> void:
	# 棕榈树（刻意避开铁匠铺和展示架，让它们露出来）
	var palm_spots := [
		Vector3(-6.6, 0, 3.6), Vector3(-6.0, 0, -3.8), Vector3(4.6, 0, 1.4),
		Vector3(3.4, 0, -4.4), Vector3(-0.6, 0, 4.9), Vector3(5.4, 0, -1.6),
		Vector3(1.4, 0, 5.2), Vector3(0.6, 0, -5.2)
	]
	for p in palm_spots:
		_palm(Vector3(p.x, terrain_y(p.x, p.z), p.z), _rng.randf_range(0.85, 1.15))

	# 灌木
	for k in 22:
		var a := _rng.randf_range(0.0, TAU)
		var r := _rng.randf_range(0.15, 0.92) * ISLAND_R
		var x := cos(a) * r
		var z := sin(a) * r
		var y := terrain_y(x, z)
		if y < 0.5:
			continue
		var s := _rng.randf_range(0.22, 0.46)
		MeshKit.add_sphere(self, s, Vector3(x, y + s * 0.5, z),
			Palette.LEAF_DARK.lerp(Palette.LEAF, _rng.randf()), Vector3(1.0, 0.75, 1.0), 7, 5)

	# 沙滩石
	for k in 26:
		var a := _rng.randf_range(0.0, TAU)
		var r := _rng.randf_range(0.86, 1.06) * ISLAND_R
		var x := cos(a) * r
		var z := sin(a) * r
		var y := terrain_y(x, z)
		var s := _rng.randf_range(0.14, 0.38)
		MeshKit.add_sphere(self, s, Vector3(x, y + s * 0.25, z),
			Palette.STONE.lerp(Palette.STONE_DARK, _rng.randf()),
			Vector3(1.0, _rng.randf_range(0.5, 0.85), _rng.randf_range(0.8, 1.2)), 5, 3)

	# 小花
	for k in 30:
		var a := _rng.randf_range(0.0, TAU)
		var r := _rng.randf_range(0.1, 0.75) * ISLAND_R
		var x := cos(a) * r
		var z := sin(a) * r
		var y := terrain_y(x, z)
		if y < 0.9:
			continue
		var col := Palette.PINK if _rng.randf() < 0.6 else Palette.CORAL
		MeshKit.add_sphere(self, _rng.randf_range(0.05, 0.09),
			Vector3(x, y + 0.12, z), col, Vector3.ONE, 5, 3)


func _palm(pos: Vector3, sc: float) -> void:
	var g := Node3D.new()
	g.position = pos
	var yaw := _rng.randf_range(0.0, 360.0)
	g.rotation_degrees.y = yaw
	add_child(g)
	_palms.append(g)
	_palm_yaw.append(yaw)
	_palm_phase.append(_rng.randf_range(0.0, TAU))
	var h := 2.5 * sc
	var lean := Vector3(_rng.randf_range(-7.0, 7.0), 0, _rng.randf_range(-7.0, 7.0))
	var trunk := MeshKit.add_cyl(g, 0.06 * sc, 0.12 * sc, h, Vector3(0, h * 0.5, 0),
		Palette.TRUNK.lerp(Palette.TRUNK_DARK, 0.35), lean, 7)
	trunk.rotation_degrees = lean
	# 树干环
	for k in 4:
		MeshKit.add_cyl(g, 0.075 * sc, 0.085 * sc, 0.06 * sc,
			Vector3(0, 0.35 * sc + k * h * 0.2, 0), Palette.TRUNK_DARK, lean, 7)
	var top := h * 0.98
	for i in 7:
		var ang := TAU * float(i) / 7.0 + _rng.randf_range(-0.18, 0.18)
		var leaf := MeshKit.add_leaf(g, Vector2(1.75 * sc, 0.5 * sc),
			Vector3(cos(ang) * 0.8 * sc, top + 0.1 * sc, sin(ang) * 0.8 * sc),
			Palette.LEAF.lerp(Palette.LEAF_DARK, _rng.randf() * 0.5))
		leaf.rotation_degrees = Vector3(0.0, rad_to_deg(-ang), _rng.randf_range(-26.0, -8.0))
	for i in 4:
		var ang := TAU * float(i) / 4.0 + 0.4
		var leaf2 := MeshKit.add_leaf(g, Vector2(1.2 * sc, 0.36 * sc),
			Vector3(cos(ang) * 0.55 * sc, top + 0.35 * sc, sin(ang) * 0.55 * sc),
			Palette.LEAF_DARK)
		leaf2.rotation_degrees = Vector3(0.0, rad_to_deg(-ang), _rng.randf_range(8.0, 26.0))
	# 椰子
	for i in 3:
		var ang := TAU * float(i) / 3.0
		MeshKit.add_sphere(g, 0.1 * sc,
			Vector3(cos(ang) * 0.16 * sc, top - 0.1 * sc, sin(ang) * 0.16 * sc),
			Palette.WOOD_DEEP, Vector3.ONE, 5, 3)


## 把做好的刀（一整棵节点）挂到展示架上
func hang_sword_node(src: Node3D) -> void:
	var slot: Node3D = null
	for s in rack_slots:
		if s.get_child_count() == 0:
			slot = s
			break
	if slot == null:
		slot = rack_slots[0]
		for c in slot.get_children():
			slot.remove_child(c)
			c.queue_free()
	var holder := Node3D.new()
	holder.scale = Vector3(0.62, 0.62, 0.62)
	holder.rotation_degrees = Vector3(0.0, 0.0, 74.0)
	holder.position = Vector3(0.14, 0.0, 0.0)
	src.position = Vector3.ZERO
	src.rotation_degrees = Vector3.ZERO
	holder.add_child(src)
	slot.add_child(holder)
