class_name HandleBuilder
extends RefCounted
## 刀柄：把一个 (t, 半径) 剖面绕柄轴"旋切"成型（车削/lathe），
## UV 为绕周 u + 沿柄 v —— 这样玩家在平面上画的雕刻图案能完整包到柄上。

const SEG := 20
const HANDLE_LEN := 0.40

const PROFILES := [
	{
		"name": "直锥柄",
		"flat": 1.0,
		"pts": [Vector2(0.0, 0.046), Vector2(0.08, 0.047), Vector2(0.30, 0.044),
				Vector2(0.60, 0.040), Vector2(0.85, 0.037), Vector2(1.0, 0.041)]
	},
	{
		"name": "腰鼓柄",
		"flat": 1.0,
		"pts": [Vector2(0.0, 0.044), Vector2(0.10, 0.039), Vector2(0.32, 0.035),
				Vector2(0.56, 0.040), Vector2(0.82, 0.046), Vector2(1.0, 0.042)]
	},
	{
		"name": "板式柄（扁）",
		"flat": 0.52,
		"pts": [Vector2(0.0, 0.050), Vector2(0.10, 0.053), Vector2(0.50, 0.049),
				Vector2(0.90, 0.047), Vector2(1.0, 0.051)]
	},
	{
		"name": "战术柄",
		"flat": 1.0,
		"pts": [Vector2(0.0, 0.045), Vector2(0.06, 0.050), Vector2(0.26, 0.046),
				Vector2(0.62, 0.042), Vector2(0.90, 0.040), Vector2(1.0, 0.044)]
	}
]

const WOODS := [
	{"name": "黑檀", "dark": Color("171310"), "light": Color("3a2f28"), "hard": 1.0},
	{"name": "玫瑰木", "dark": Color("33170f"), "light": Color("6b341f"), "hard": 0.85},
	{"name": "硬枫木", "dark": Color("8c6136"), "light": Color("d4a970"), "hard": 0.6},
	{"name": "蛇纹木", "dark": Color("48210f"), "light": Color("8c4c26"), "hard": 0.9},
	{"name": "蓝染稳定木", "dark": Color("1e3a44"), "light": Color("4f8d9c"), "hard": 0.95},
	{"name": "鹿角", "dark": Color("b8a279"), "light": Color("efe3c6"), "hard": 0.75}
]


static func profile(index: int) -> Dictionary:
	return PROFILES[clampi(index, 0, PROFILES.size() - 1)]


## 玩家自定义柄形：用 3 个半径 + 扁度拼一条剖面
static func custom_profile(s: SwordData) -> Dictionary:
	var r0 := clampf(s.handle_r0, 0.018, 0.075)
	var r1 := clampf(s.handle_r1, 0.018, 0.075)
	var r2 := clampf(s.handle_r2, 0.018, 0.075)
	return {
		"name": "自定义", "flat": clampf(s.handle_flat, 0.35, 1.0),
		"pts": [Vector2(0.0, r0), Vector2(0.18, r1 * 1.02), Vector2(0.42, r1),
				Vector2(0.72, (r1 + r2) * 0.5), Vector2(1.0, r2)]
	}


static func profile_for(s: SwordData) -> Dictionary:
	if s.handle_custom:
		return custom_profile(s)
	return profile(s.handle_preset)


static func wood(index: int) -> Dictionary:
	return WOODS[clampi(index, 0, WOODS.size() - 1)]


## 玩家调整的刀柄角度：让柄轴对齐弯刀的刀茎
static func _dir(s: SwordData, butt_dir: Vector2) -> Vector2:
	if absf(s.handle_angle) < 0.01:
		return butt_dir
	return butt_dir.rotated(deg_to_rad(clampf(s.handle_angle, -60.0, 60.0)))


## 柄轴原点 = 刀柄端中心；方向 = 向外（通常 -X）
static func build(s: SwordData, butt: Vector2, butt_dir: Vector2) -> ArrayMesh:
	var prof := profile_for(s)
	var pts: Array = prof["pts"]
	var flat: float = prof["flat"]
	var origin := Vector3(butt.x, butt.y, 0.0)
	var d := _dir(s, butt_dir)
	var axis := Vector3(d.x, d.y, 0.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	_lathe(st, origin, axis, pts, HANDLE_LEN, flat, SEG, true, true)
	st.generate_normals()
	return st.commit()


## 护手 / 尾铁
## part: 0 = 全部（旧行为） / 1 = 只护手 / 2 = 只尾铁 —— 分开建才能给两份材质
static func build_fittings(s: SwordData, butt: Vector2, butt_dir: Vector2, part: int = 0) -> ArrayMesh:
	if s.guard_style == 0 and s.pommel_style == 0:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var origin := Vector3(butt.x, butt.y, 0.0)
	var d2 := _dir(s, butt_dir)
	var axis := Vector3(d2.x, d2.y, 0.0)

	if part != 2 and s.guard_style > 0:
		var base_r := 0.085 if s.guard_style == 1 else 0.070
		var thick := 0.016 if s.guard_style == 1 else 0.020
		match s.guard_shape:
			1:
				# 十字横条：垂直于柄轴的一根长条 + 两端小球（长剑那种）
				var perp := Vector3(-axis.y, axis.x, 0.0).normalized()
				var gc := origin + axis * 0.012
				_box(st, gc, perp, axis, Vector3(0, 0, 1), 0.135, 0.024, 0.020)
				for sd in [-1.0, 1.0]:
					_sphere(st, gc + perp * (0.135 * sd), 0.028, 6, 4)
			2:
				# 弧形护手：5 段短条沿一段圆弧排（日式的"杏叶锷"那种弧度）
				var dir2 := axis.normalized()
				var perp2 := Vector3(-dir2.y, dir2.x, 0.0).normalized()
				for i in 5:
					var t := (float(i) / 4.0 - 0.5) * 1.55
					var off := perp2 * (sin(t) * 0.155) + dir2 * (cos(t) * 0.030 - 0.030)
					_box(st, origin + off, perp2, dir2, Vector3(0, 0, 1),
						0.040, 0.020, 0.018, t * 0.55)
			3:
				# 碗形（护手杯）
				var cpts: Array = [
					Vector2(0.0, base_r * 0.30), Vector2(0.30, base_r * 0.72),
					Vector2(0.70, base_r * 0.98), Vector2(1.0, base_r * 0.86)
				]
				_lathe(st, origin + axis * 0.001, axis, cpts, thick * 2.6, 0.95, SEG, true, false)
			4:
				# 宽圆盘
				var wpts: Array = [
					Vector2(0.0, base_r * 0.7), Vector2(0.4, base_r * 1.32),
					Vector2(0.7, base_r * 1.30), Vector2(1.0, base_r * 0.9)
				]
				_lathe(st, origin + axis * 0.001, axis, wpts, thick, 0.85, SEG, true, true)
			5:
				# 西欧 1440-80：平直臂 + 球端 + 中央菱形板
				var p5 := Vector3(-axis.y, axis.x, 0.0).normalized()
				var a5 := axis.normalized()
				var gc5 := origin + a5 * 0.012
				_box(st, gc5, p5, a5, Vector3(0, 0, 1), 0.115, 0.018, 0.014)
				_box(st, gc5, p5, a5, Vector3(0, 0, 1), 0.032, 0.036, 0.018, 0.0)
				for sd5 in [-1.0, 1.0]:
					_sphere(st, gc5 + p5 * (0.115 * sd5), 0.022, 6, 4)
			6:
				# 南德 Katzbalger 1520-50：S 形护手
				# 关键：沿横臂走一整周 sin(u*2π)，两端才会朝"相反方向"弯成 S
				# （旧写法用 sin(k*π)，k 从 -1 到 +1 时两端同号，只会鼓成一道弧）
				var p6 := Vector3(-axis.y, axis.x, 0.0).normalized()
				var a6 := axis.normalized()
				var n6 := 19
				var span6 := 0.32
				var amp6 := 0.058
				for i6 in n6:
					var u6 := float(i6) / float(n6 - 1)
					var x6 := (u6 - 0.5) * span6
					var y6 := sin(u6 * TAU) * amp6
					var u2 := minf(u6 + 0.008, 1.0)
					var x2 := (u2 - 0.5) * span6
					var y2 := sin(u2 * TAU) * amp6
					var ang6 := atan2(y2 - y6, x2 - x6)
					_box(st, origin + p6 * x6 + a6 * (y6 + 0.022), p6, a6,
						Vector3(0, 0, 1), 0.017, 0.013, 0.012, ang6)
				# 两端小圆头
				for sd6 in [-1.0, 1.0]:
					_sphere(st, origin + p6 * (span6 * 0.5 * sd6) + a6 * 0.022, 0.019, 6, 4)
			7:
				# 意大利 1530-1620：单侧长弯护手 + 侧环
				var p7 := Vector3(-axis.y, axis.x, 0.0).normalized()
				var a7 := axis.normalized()
				for i7 in 8:
					var t7 := float(i7) / 7.0
					var ang7 := lerpf(-0.15, 2.35, t7)
					var off7 := p7 * (sin(ang7) * 0.145) + a7 * (cos(ang7) * 0.145 - 0.015)
					_box(st, origin + off7, p7, a7, Vector3(0, 0, 1), 0.025, 0.013, 0.012, ang7 * 0.55)
				_ring(st, origin + a7 * 0.02, p7, a7, 0.085, 0.012, 10)
			8:
				# 西欧 1550-1650：直臂 + 侧环
				var p8 := Vector3(-axis.y, axis.x, 0.0).normalized()
				var a8 := axis.normalized()
				var gc8 := origin + a8 * 0.012
				_box(st, gc8, p8, a8, Vector3(0, 0, 1), 0.105, 0.016, 0.013)
				for sd8 in [-1.0, 1.0]:
					_sphere(st, gc8 + p8 * (0.105 * sd8), 0.020, 6, 4)
				_ring(st, gc8 + a8 * 0.008, p8, a8, 0.078, 0.011, 10)
			_:
				# 圆盘（经典）
				var gpts: Array = [
					Vector2(0.0, base_r * 0.62), Vector2(0.35, base_r * 0.98),
					Vector2(0.65, base_r * 1.0), Vector2(1.0, base_r * 0.70)
				]
				_lathe(st, origin + axis * 0.001, axis, gpts, thick, 0.55, SEG, true, true)

	if part != 1 and s.pommel_style > 0:
		var ppts: Array = [
			Vector2(0.0, 0.030), Vector2(0.35, 0.046), Vector2(0.70, 0.048), Vector2(1.0, 0.034)
		]
		_lathe(st, origin + axis * (HANDLE_LEN - 0.030), axis, ppts, 0.032, 1.0, SEG, true, true)

	st.generate_normals()
	return st.commit()


## 一个盒子（用于十字护手这类非旋转体）：u/v/n 是三个轴，hu/hv/hn 是半边长
static func _box(st: SurfaceTool, c: Vector3, u: Vector3, v: Vector3, n: Vector3,
		hu: float, hv: float, hn: float, tilt: float = 0.0) -> void:
	var uu := u
	var vv := v
	if absf(tilt) > 0.0001:
		uu = u * cos(tilt) + v * sin(tilt)
		vv = v * cos(tilt) - u * sin(tilt)
	var axes: Array[Vector3] = [uu, vv, n]
	var halves: Array[float] = [hu, hv, hn]
	for i in 3:
		var ax: Vector3 = axes[i]
		var e1: Vector3 = axes[(i + 1) % 3]
		var e2: Vector3 = axes[(i + 2) % 3]
		var h1: float = halves[(i + 1) % 3]
		var h2: float = halves[(i + 2) % 3]
		for sd in [-1.0, 1.0]:
			var fc := c + ax * (float(sd) * halves[i])
			var want := ax * float(sd)
			var q0 := fc - e1 * h1 - e2 * h2
			var q1 := fc + e1 * h1 - e2 * h2
			var q2 := fc + e1 * h1 + e2 * h2
			var q3 := fc - e1 * h1 + e2 * h2
			_tri(st, q0, q1, q2, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), want)
			_tri(st, q0, q2, q3, Vector2(0, 0), Vector2(1, 1), Vector2(0, 1), want)


## 低面数球（护手两端的小球）
static func _sphere(st: SurfaceTool, c: Vector3, r: float, seg: int, rings: int) -> void:
	for j in rings:
		var t0 := float(j) / float(rings)
		var t1 := float(j + 1) / float(rings)
		var p0 := lerpf(-PI * 0.5, PI * 0.5, t0)
		var p1 := lerpf(-PI * 0.5, PI * 0.5, t1)
		for i in seg:
			var a0 := TAU * float(i) / float(seg)
			var a1 := TAU * float(i + 1) / float(seg)
			var v00 := c + Vector3(cos(p0) * cos(a0), sin(p0), cos(p0) * sin(a0)) * r
			var v01 := c + Vector3(cos(p0) * cos(a1), sin(p0), cos(p0) * sin(a1)) * r
			var v10 := c + Vector3(cos(p1) * cos(a0), sin(p1), cos(p1) * sin(a0)) * r
			var v11 := c + Vector3(cos(p1) * cos(a1), sin(p1), cos(p1) * sin(a1)) * r
			var mid := (v00 + v11) * 0.5 - c
			_tri(st, v00, v10, v11, Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), mid)
			_tri(st, v00, v11, v01, Vector2(0, 0), Vector2(1, 1), Vector2(1, 0), mid)


static func _lathe(st: SurfaceTool, origin: Vector3, axis: Vector3, pts: Array,
		length: float, flat: float, seg: int, cap_start: bool, cap_end: bool) -> void:
	var ax := axis.normalized()
	if ax.length() < 0.5:
		ax = Vector3.LEFT
	var up := Vector3(0.0, 0.0, 1.0)
	if absf(ax.dot(up)) > 0.95:
		up = Vector3.RIGHT
	var bx := ax.cross(up).normalized()
	var by := bx.cross(ax).normalized()

	var rings: Array = []
	var centers: Array = []
	for k in pts.size():
		var t: float = pts[k].x
		var r: float = pts[k].y
		var c := origin + ax * (t * length)
		centers.append(c)
		var ring: Array = []
		for i in seg:
			var a := TAU * float(i) / float(seg)
			ring.append(c + bx * (cos(a) * r) + by * (sin(a) * r * flat))
		rings.append(ring)

	for k in rings.size() - 1:
		var t0: float = pts[k].x
		var t1: float = pts[k + 1].x
		for i in seg:
			var i2 := (i + 1) % seg
			var p00: Vector3 = rings[k][i]
			var p01: Vector3 = rings[k][i2]
			var p10: Vector3 = rings[k + 1][i]
			var p11: Vector3 = rings[k + 1][i2]
			var mid: Vector3 = (p00 + p11) * 0.5
			var want: Vector3 = mid - (origin + ax * (((t0 + t1) * 0.5) * length))
			var u0 := float(i) / float(seg)
			var u1 := float(i + 1) / float(seg)
			_strip4(st, p00, p10, p11, p01,
				Vector2(u0, t0), Vector2(u0, t1), Vector2(u1, t1), Vector2(u1, t0), want)

	if cap_start:
		_cap(st, centers[0], rings[0], -ax)
	if cap_end:
		_cap(st, centers[centers.size() - 1], rings[rings.size() - 1], ax)


static func _cap(st: SurfaceTool, center: Vector3, ring: Array, want: Vector3) -> void:
	var seg := ring.size()
	for i in seg:
		var i2 := (i + 1) % seg
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[i2]
		_tri(st, center, a, b, Vector2(0.5, 0.5),
			Vector2(float(i) / float(seg), 0.0), Vector2(float(i + 1) / float(seg), 0.0), want)


static func _strip4(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, want: Vector3) -> void:
	_tri(st, a, b, c, ua, ub, uc, want)
	_tri(st, a, c, d, ua, uc, ud, want)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, want: Vector3) -> void:
	var nrm := (b - a).cross(c - a)
	if nrm.length() < 1e-12:
		return
	if nrm.normalized().dot(want.normalized()) > 0.0:
		var tp := b
		b = c
		c = tp
		var tu := ub
		ub = uc
		uc = tu
	st.set_uv(ua)
	st.add_vertex(a)
	st.set_uv(ub)
	st.add_vertex(b)
	st.set_uv(uc)
	st.add_vertex(c)

## 用一圈小方块拼一个环（侧环护手用）
static func _ring(st: SurfaceTool, c: Vector3, u: Vector3, v: Vector3, radius: float,
		thick: float, segs: int) -> void:
	for i in segs:
		var a := TAU * float(i) / float(segs)
		var pos := c + u * (cos(a) * radius) + v * (sin(a) * radius)
		_box(st, pos, u, v, Vector3(0, 0, 1), thick, thick * 1.6, thick * 0.8, a)