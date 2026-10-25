class_name BladeBuilder
extends RefCounted
## 由玩家画的 2D 轮廓 → 真正的 3D 刀身网格。
##
## 做法：把轮廓按刀尖/刀柄端切成两条边界链（刀背链、刀刃链），各自按弧长
## 重采样成 N 段，然后把两链对应点连成"横截面"，沿横截面给出厚度剖面：
##   刀背最厚 = 刀背厚度，向刀刃按 (1-t)^1.35 迅速收薄 → 真实的楔形刃口。
## UV: u = 沿刀身(0 柄端 → 1 刀尖), v = 刀背(0) → 刀刃(1)。
## 这个 UV 正是大马士革纹路着色器需要的东西。

const N_SEG := 76
const M_SEG := 8

## 分析轮廓：刀柄端中心、向外的方向、刀尖、最大宽度
static func analyze(poly: PackedVector2Array) -> Dictionary:
	var res := {
		"ok": false, "butt": Vector2(-0.5, 0.0), "butt_dir": Vector2.LEFT,
		"tip": Vector2(0.5, 0.0), "width": 0.12, "length": 1.0
	}
	if poly.size() < 4:
		return res
	var n := poly.size()
	var i_min := 0
	var i_max := 0
	for i in n:
		if poly[i].x < poly[i_min].x:
			i_min = i
		if poly[i].x > poly[i_max].x:
			i_max = i
	var prev := (i_min - 1 + n) % n
	var nxt := (i_min + 1) % n
	var b1 := nxt
	if absf(poly[nxt].x - poly[i_min].x) > absf(poly[prev].x - poly[i_min].x):
		b1 = prev
	var butt := (poly[i_min] + poly[b1]) * 0.5
	var edge := (poly[b1] - poly[i_min])
	if edge.length() < 0.0001:
		edge = Vector2.UP
	edge = edge.normalized()
	var centroid := Vector2.ZERO
	for p in poly:
		centroid += p
	centroid /= float(n)
	var outward := Vector2(edge.y, -edge.x)
	if outward.dot(butt - centroid) < 0.0:
		outward = -outward
	var width := 0.0
	for i in n:
		width = maxf(width, absf(poly[i].y - butt.y))
	res["ok"] = true
	res["butt"] = butt
	res["butt_dir"] = outward
	res["tip"] = poly[i_max]
	res["width"] = width * 2.0
	res["length"] = 1.0
	res["i_min"] = i_min
	res["i_max"] = i_max
	res["b1"] = b1
	return res


static func build(s: SwordData) -> ArrayMesh:
	# 用"设计图 + 锻打偏差"融合后的轮廓，而不是纯设计图
	var poly := s.mesh_outline()
	var info := analyze(poly)
	if not info["ok"]:
		return null
	var n := poly.size()
	var i_min: int = info["i_min"]
	var i_max: int = info["i_max"]
	var b1: int = info["b1"]
	var vertical_next := (b1 == (i_min + 1) % n)

	var chain_a := _walk(poly, i_min, i_max, -1 if vertical_next else 1)
	var chain_b := _walk(poly, b1, i_max, 1 if vertical_next else -1)
	if chain_a.size() < 2 or chain_b.size() < 2:
		return null

	# 更平直的一条当刀背
	var ca_curv := _curvature(chain_a)
	var cb_curv := _curvature(chain_b)
	var spine_raw := chain_a
	var edge_raw := chain_b
	if cb_curv < ca_curv:
		spine_raw = chain_b
		edge_raw = chain_a

	var spine := _resample(spine_raw, N_SEG + 1)
	var edge := _resample(edge_raw, N_SEG + 1)
	if spine.size() != edge.size():
		return null

	var half := maxf(s.thickness, 0.002) * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = int(abs(hash(s.design_source + str(poly.size())))) + 11

	# ---- 生成中面网格 + 厚度 ----
	var mids: Array = []
	var hh: Array = []
	for i in N_SEG + 1:
		var u := float(i) / float(N_SEG)
		var a: Vector2 = spine[i]
		var b: Vector2 = edge[i]
		var taper := lerpf(1.0, 0.58, u)                                  # 远端渐薄
		var hammer := 1.0 + rng.randf_range(-0.05, 0.05) * (1.0 - s.fidelity) * 4.0
		var bend := sin(u * PI) * s.warp * 0.045
		var row_m := []
		var row_h := []
		for j in M_SEG + 1:
			var t := float(j) / float(M_SEG)
			var p2 := a.lerp(b, t)
			var w := _section_w(t, s)
			row_m.append(Vector3(p2.x, p2.y, bend * (0.35 + t * 0.6)))
			row_h.append(half * taper * w * hammer)
		mids.append(row_m)
		hh.append(row_h)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)   # 0 = 平滑组：刀身需要连续法线才有金属反光

	# ---- 上表面 / 下表面 ----
	for side in [1.0, -1.0]:
		var want := Vector3.BACK * signf(side)
		for i in N_SEG:
			var u0 := float(i) / float(N_SEG)
			var u1 := float(i + 1) / float(N_SEG)
			for j in M_SEG:
				var v0 := float(j) / float(M_SEG)
				var v1 := float(j + 1) / float(M_SEG)
				var p00: Vector3 = mids[i][j] + Vector3(0.0, 0.0, hh[i][j] * side)
				var p10: Vector3 = mids[i + 1][j] + Vector3(0.0, 0.0, hh[i + 1][j] * side)
				var p11: Vector3 = mids[i + 1][j + 1] + Vector3(0.0, 0.0, hh[i + 1][j + 1] * side)
				var p01: Vector3 = mids[i][j + 1] + Vector3(0.0, 0.0, hh[i][j + 1] * side)
				_strip4(st, p00, p10, p11, p01,
					Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1), want)

	# ---- 刀背侧壁 ----
	for i in N_SEG:
		var want := Vector3(spine[i].x - edge[i].x, spine[i].y - edge[i].y, 0.0).normalized()
		if want.length() < 0.5:
			want = Vector3.UP
		var u0 := float(i) / float(N_SEG)
		var u1 := float(i + 1) / float(N_SEG)
		var pt0: Vector3 = mids[i][0] + Vector3(0.0, 0.0, hh[i][0])
		var pt1: Vector3 = mids[i + 1][0] + Vector3(0.0, 0.0, hh[i + 1][0])
		var pb0: Vector3 = mids[i][0] - Vector3(0.0, 0.0, hh[i][0])
		var pb1: Vector3 = mids[i + 1][0] - Vector3(0.0, 0.0, hh[i + 1][0])
		_strip4(st, pt0, pt1, pb1, pb0,
			Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, 0.28), Vector2(u0, 0.28), want)

	# ---- 刀柄端封口（实际会被护手遮住）----
	var cap_want := Vector3(-info["butt_dir"].x, -info["butt_dir"].y, 0.0)
	for j in M_SEG:
		var v0 := float(j) / float(M_SEG)
		var v1 := float(j + 1) / float(M_SEG)
		var a_t: Vector3 = mids[0][j] + Vector3(0.0, 0.0, hh[0][j])
		var b_t: Vector3 = mids[0][j + 1] + Vector3(0.0, 0.0, hh[0][j + 1])
		var a_b: Vector3 = mids[0][j] - Vector3(0.0, 0.0, hh[0][j])
		var b_b: Vector3 = mids[0][j + 1] - Vector3(0.0, 0.0, hh[0][j + 1])
		_strip4(st, a_t, b_t, b_b, a_b,
			Vector2(0.0, v0), Vector2(0.0, v1), Vector2(0.02, v1), Vector2(0.02, v0), cap_want)

	# ---- 刀茎（穿进刀柄里的舌头）----
	_add_tang(st, info, half, s)

	st.generate_normals()
	return st.commit()


static func _add_tang(st: SurfaceTool, info: Dictionary, half: float, s: SwordData) -> void:
	var butt: Vector2 = info["butt"]
	var dir: Vector2 = info["butt_dir"]
	# 刀茎跟着手柄一起转：HandleBuilder 用 handle_angle 绕 butt 旋转手柄/护手，
	# 这里用同一个角度绕同一个枢轴（butt）转刀茎，两边就永远对齐。
	dir = dir.rotated(deg_to_rad(s.handle_angle))
	var side := Vector2(-dir.y, dir.x)
	var hw := maxf(float(info["width"]) * 0.18, 0.018)          # 刀茎半宽
	var th := maxf(half * 0.75, 0.003)
	var ln := 0.36
	var p0 := Vector3(butt.x, butt.y, 0.0)
	var p1 := Vector3(butt.x + dir.x * ln, butt.y + dir.y * ln, 0.0)
	var s2 := Vector3(side.x * hw, side.y * hw, 0.0)
	var shrink := 0.55
	# 六个面
	var c: Array[Vector3] = [p0 + s2, p0 - s2, p1 + s2 * shrink, p1 - s2 * shrink]
	var up := Vector3(0.0, 0.0, th)
	_strip4(st, c[0] + up, c[2] + up, c[3] + up, c[1] + up,
		Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 0.4), Vector2(0.0, 0.4), Vector3.BACK)
	_strip4(st, c[0] - up, c[2] - up, c[3] - up, c[1] - up,
		Vector2(0.0, 0.6), Vector2(1.0, 0.6), Vector2(1.0, 1.0), Vector2(0.0, 1.0), Vector3.FORWARD)
	_strip4(st, c[0] + up, c[2] + up, c[2] - up, c[0] - up,
		Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0),
		Vector3(s2.x, s2.y, 0.0).normalized())
	_strip4(st, c[1] + up, c[3] + up, c[3] - up, c[1] - up,
		Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0),
		-Vector3(s2.x, s2.y, 0.0).normalized())
	_strip4(st, c[2] + up, c[3] + up, c[3] - up, c[2] - up,
		Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0),
		Vector3(dir.x, dir.y, 0.0))


## 四个点组成两个三角形。want 是期望的法线方向，用来纠正绕序。
## 注意：Godot 的正面是"顺时针"，所以右手叉积法线必须指向 want 的反方向。
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


static func _walk(poly: PackedVector2Array, from_i: int, to_i: int, dir: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := poly.size()
	var i := from_i
	var guard := 0
	while true:
		out.append(poly[i])
		if i == to_i:
			break
		i = (i + dir + n) % n
		guard += 1
		if guard > n + 4:
			break
	return out


static func _curvature(chain: PackedVector2Array) -> float:
	if chain.size() < 3:
		return 0.0
	var acc := 0.0
	var total := 0.0
	for i in range(1, chain.size() - 1):
		var d0 := (chain[i] - chain[i - 1])
		var d1 := (chain[i + 1] - chain[i])
		total += d1.length()
		if d0.length() > 1e-6 and d1.length() > 1e-6:
			acc += absf(d0.angle_to(d1))
	return acc / maxf(total, 1e-5)


static func _resample(chain: PackedVector2Array, count: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	if chain.size() < 2 or count < 2:
		return chain
	var seg := PackedFloat32Array()
	var total := 0.0
	for i in chain.size() - 1:
		var d := chain[i].distance_to(chain[i + 1])
		seg.append(d)
		total += d
	if total < 1e-5:
		return chain
	var step := total / float(count - 1)
	var idx := 0
	var acc := 0.0
	for k in count:
		var target := step * float(k)
		while idx < seg.size() - 1 and acc + seg[idx] < target:
			acc += seg[idx]
			idx += 1
		var frac := 0.0
		if seg[idx] > 1e-6:
			frac = clampf((target - acc) / seg[idx], 0.0, 1.0)
		out.append(chain[idx].lerp(chain[idx + 1], frac))
	return out

## 横截面厚度曲线（P1）：t = 0 刀背 → 1 刃口
## 参数全为默认值时，结果与旧的 pow(1-t, 1.35) 完全一致
static func _section_w(t: float, s: SwordData) -> float:
	var a := clampf(s.xs_edge_angle, 0.0, 1.0)
	var w := pow(clampf(1.0 - t, 0.0, 1.0), 1.35 * (0.6 + 0.8 * a))
	# 二次斜面：刃口最后 38% 再做一道折面
	var sec := clampf(s.xs_secondary, 0.0, 1.0)
	if sec > 0.01 and t > 0.62:
		var k := (t - 0.62) / 0.38
		w *= 1.0 - 0.45 * sec * k * k
	# 血槽：靠刀背挖一条浅槽
	var fw := clampf(s.xs_fuller_w, 0.0, 1.0)
	var fd := clampf(s.xs_fuller_d, 0.0, 1.0)
	if fw > 0.01 and fd > 0.01:
		var c := 0.26
		var halfw := 0.05 + 0.20 * fw
		var d := absf(t - c) / halfw
		if d < 1.0:
			w *= 1.0 - fd * 0.62 * (1.0 - d * d)
	# 中脊：0 = 平磨（单楔），1 = 起身中脊（两侧对称加厚）
	var rg := clampf(s.xs_ridge, 0.0, 1.0)
	if rg > 0.01:
		w *= 1.0 + rg * 0.55 * (1.0 - absf(t - 0.42) * 2.2)
	return clampf(w, 0.0, 1.8)
