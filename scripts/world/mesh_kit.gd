class_name MeshKit
extends RefCounted
## 用基础几何体快速搭箱庭的小工具：所有材质按颜色缓存，节点数不多但省 DrawCall。

static var _cache: Dictionary = {}
static var _outlines: Dictionary = {}


## 描边材质（按"屏幕比例系数"缓存）。width 越小线越细，0.0016 ≈ 2~3 px。
static func outline_mat(width: float = 0.0016) -> ShaderMaterial:
	var key := snappedf(width, 0.0001)
	if _outlines.has(key):
		return _outlines[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/outline.gdshader")
	m.set_shader_parameter("width", width)
	_outlines[key] = m
	return m


## 自己的三渲二材质（赛璐璐色阶 + 冷阴影 + 硬边高光）+ 描边
static func mat(color: Color, rough: float = 0.88, metal: float = 0.0,
		emis: Color = Color(0, 0, 0), emis_energy: float = 0.0) -> ShaderMaterial:
	var key := "%s|%.2f|%.2f|%s|%.2f" % [color.to_html(), rough, metal, emis.to_html(), emis_energy]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/toon.gdshader")
	m.set_shader_parameter("albedo_col", color)
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("metallic", metal)
	if emis_energy > 0.001:
		m.set_shader_parameter("emis_col", emis)
		m.set_shader_parameter("emis_energy", emis_energy)
	m.set_shader_parameter("spec_gain", 0.55 if rough < 0.6 else 0.3)
	m.next_pass = outline_mat()
	_cache[key] = m
	return m


static func emissive(color: Color, energy: float = 2.0) -> ShaderMaterial:
	var key := "emis|%s|%.2f" % [color.to_html(), energy]
	if _cache.has(key):
		return _cache[key]
	var m := mat(color, 0.6, 0.0, color, energy)
	_cache[key] = m
	return m


static func leaf_mat(color: Color) -> ShaderMaterial:
	var key := "leaf|%s" % color.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/toon_leaf.gdshader")
	m.set_shader_parameter("albedo_col", color)
	m.set_shader_parameter("rim", 0.28)
	_cache[key] = m
	return m


static func add_box(parent: Node, size: Vector3, pos: Vector3, col: Color,
		rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = mat(col)
	parent.add_child(mi)
	return mi


static func add_cyl(parent: Node, top_r: float, bot_r: float, h: float, pos: Vector3,
		col: Color, rot_deg: Vector3 = Vector3.ZERO, seg: int = 8) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bot_r
	cm.height = h
	cm.radial_segments = seg
	cm.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = mat(col)
	parent.add_child(mi)
	return mi


static func add_sphere(parent: Node, r: float, pos: Vector3, col: Color,
		scale: Vector3 = Vector3.ONE, seg: int = 8, rings: int = 6) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = seg
	sm.rings = rings
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.position = pos
	mi.scale = scale
	mi.material_override = mat(col)
	parent.add_child(mi)
	return mi


static func add_torus(parent: Node, inner: float, outer: float, pos: Vector3, col: Color,
		rot_deg: Vector3 = Vector3.ZERO, rings: int = 16) -> MeshInstance3D:
	var tm := TorusMesh.new()
	tm.inner_radius = inner
	tm.outer_radius = outer
	tm.rings = rings
	tm.ring_segments = 6
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = mat(col)
	parent.add_child(mi)
	return mi


static func add_leaf(parent: Node, size: Vector2, pos: Vector3, col: Color,
		rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var pm := PlaneMesh.new()
	pm.size = size
	pm.orientation = PlaneMesh.FACE_Y
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = leaf_mat(col)
	parent.add_child(mi)
	return mi


## 火星粒子（炉子/锤击）
static func add_embers(parent: Node3D, pos: Vector3, amount: int = 26,
		col: Color = Color(1.0, 0.62, 0.20)) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 1.7
	p.position = pos
	p.emitting = true
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.26
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 32.0
	pm.initial_velocity_min = 0.35
	pm.initial_velocity_max = 1.15
	pm.gravity = Vector3(0, 0.55, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.5
	pm.color = col
	pm.color_ramp = _fade_ramp(col)
	p.process_material = pm
	var mesh := SphereMesh.new()
	mesh.radius = 0.032
	mesh.height = 0.064
	mesh.radial_segments = 6
	mesh.rings = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 3.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	mesh.material = m
	p.draw_pass_1 = mesh
	parent.add_child(p)
	return p


## 蒸汽粒子（淬火桶 / 热刀）
static func add_steam(parent: Node3D, pos: Vector3, amount: int = 18) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 2.6
	p.position = pos
	p.emitting = true
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.22
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 22.0
	pm.initial_velocity_min = 0.18
	pm.initial_velocity_max = 0.55
	pm.gravity = Vector3(0, 0.35, 0)
	pm.scale_min = 1.4
	pm.scale_max = 3.2
	pm.color = Color(0.98, 0.97, 0.94, 0.55)
	pm.color_ramp = _fade_ramp(Color(0.98, 0.97, 0.94, 0.55))
	p.process_material = pm
	var mesh := SphereMesh.new()
	mesh.radius = 0.075
	mesh.height = 0.15
	mesh.radial_segments = 6
	mesh.rings = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, 1, 1, 0.5)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	mesh.material = m
	p.draw_pass_1 = mesh
	parent.add_child(p)
	return p


static func _fade_ramp(col: Color) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, 1.0))
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt


## 飘落的樱花瓣：软风 + 缓慢下坠 + 湍流打旋
static func add_petals(parent: Node, pos: Vector3, spread: Vector3,
		amount: int = 110) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Petals"
	p.amount = amount
	p.lifetime = 9.0
	p.preprocess = 7.0
	p.position = pos
	p.emitting = true
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-14, -10, -14), Vector3(28, 20, 28))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = spread
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 75.0
	pm.initial_velocity_min = 0.10
	pm.initial_velocity_max = 0.40
	pm.gravity = Vector3(0.16, -0.42, 0.08)
	pm.damping_min = 0.02
	pm.damping_max = 0.08
	pm.angular_velocity_min = -140.0
	pm.angular_velocity_max = 140.0
	pm.scale_min = 0.7
	pm.scale_max = 1.4
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.1
	pm.turbulence_noise_scale = 2.4
	pm.turbulence_influence_min = 0.06
	pm.turbulence_influence_max = 0.18
	# 花瓣颜色在粉白之间随机
	var g := Gradient.new()
	g.set_color(0, Palette.SAKURA_PETAL)
	g.set_color(1, Color("fff6f9"))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	# 画一片很小的方片：屏幕上只有几像素，看不出是方块
	var q := QuadMesh.new()
	q.size = Vector2(0.115, 0.075)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	p.draw_pass_1 = q
	parent.add_child(p)
	return p


## 把闭合多边形沿 Y 挤出成实体（用于水体、底板这类"切片"）
static func extrude_polygon(poly: PackedVector2Array, y_top: float, y_bottom: float,
		col_top: Color, col_side: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.size() >= 3 and idx[0] >= 0:
		var i := 0
		while i + 2 < idx.size():
			var a := Vector3(poly[idx[i]].x, y_top, poly[idx[i]].y)
			var b := Vector3(poly[idx[i + 1]].x, y_top, poly[idx[i + 1]].y)
			var c := Vector3(poly[idx[i + 2]].x, y_top, poly[idx[i + 2]].y)
			_tri_c(st, a, b, c, col_top, col_top, col_top, Vector3.UP, Vector2(a.x, a.z) * 0.1)
			i += 3
	var n := poly.size()
	for k in n:
		var p0 := poly[k]
		var p1 := poly[(k + 1) % n]
		var nrm := Vector3(p1.y - p0.y, 0.0, -(p1.x - p0.x)).normalized()
		var a0 := Vector3(p0.x, y_top, p0.y)
		var a1 := Vector3(p1.x, y_top, p1.y)
		var b1 := Vector3(p1.x, y_bottom, p1.y)
		var b0 := Vector3(p0.x, y_bottom, p0.y)
		_tri_c(st, a0, a1, b1, col_side, col_side, col_side, nrm, Vector2(0, 0))
		_tri_c(st, a0, b1, b0, col_side, col_side, col_side, nrm, Vector2(0, 1))
	st.generate_normals()
	return st.commit()


static func _tri_c(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ca: Color, cb: Color, cc: Color, want: Vector3, uv: Vector2) -> void:
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
	st.set_color(ca)
	st.set_uv(uv)
	st.add_vertex(a)
	st.set_color(cb)
	st.set_uv(uv)
	st.add_vertex(b)
	st.set_color(cc)
	st.set_uv(uv)
	st.add_vertex(c)


## 圆角矩形轮廓（箱庭水体的外形）
static func rounded_rect(half: float, radius: float, segments: int = 8) -> PackedVector2Array:
	var out := PackedVector2Array()
	var r := clampf(radius, 0.01, half * 0.99)
	var inner := half - r
	var corners := [
		Vector2(inner, inner), Vector2(-inner, inner), Vector2(-inner, -inner), Vector2(inner, -inner)
	]
	var start := [0.0, PI * 0.5, PI, PI * 1.5]
	for ci in 4:
		var c: Vector2 = corners[ci]
		for s in segments + 1:
			var a: float = float(start[ci]) + (PI * 0.5) * float(s) / float(segments)
			out.append(c + Vector2(cos(a), sin(a)) * r)
	return out
