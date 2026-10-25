class_name ContourTrace
extends RefCounted
## 把玩家在图纸上画出来的像素团，变成一条可用的刀身轮廓。
## 思路：alpha 蒙版 → BitMap 轮廓提取 → 取最大一块 → 简化 → 归一化到
## "刀身长度 = 1.0、刀尖朝 +X、中心在原点" 的标准空间。

static func mask_to_outline(img: Image, epsilon: float = 1.6) -> PackedVector2Array:
	if img == null or img.is_empty():
		return PackedVector2Array()
	var bm := BitMap.new()
	bm.create_from_image_alpha(img, 0.5)
	var rect := Rect2(Vector2.ZERO, Vector2(img.get_size()))
	var polys := bm.opaque_to_polygons(rect, 2.0)
	if polys.is_empty():
		return PackedVector2Array()

	# 只保留面积最大的一块（忽略噪点、飞白）
	# 注意：闭合多边形最少 3 个点，简化后可能只剩 4 个 —— 门槛用 4，不能用 6，
	# 否则玩家画一个方头刀身会被当成"没画东西"。
	var best: PackedVector2Array = PackedVector2Array()
	var best_area := -1.0
	for p in polys:
		if p.size() < 4:
			continue
		var a := absf(_area(p))
		if a > best_area:
			best_area = a
			best = p
	if best.size() < 4:
		return PackedVector2Array()

	# 图像坐标 Y 向下 → 世界坐标 Y 向上
	var flipped := PackedVector2Array()
	for p in best:
		flipped.append(Vector2(p.x, -p.y))

	var simple := _simplify_closed(flipped, maxf(epsilon, 0.5))
	if simple.size() < 4:
		simple = flipped

	return normalize_outline(simple)


## 闭合折线简化（Douglas–Peucker）。Godot 4 的 Geometry2D 没有 simplify_polygon，
## 所以这里自己实现一份，避免依赖版本差异。
static func _simplify_closed(poly: PackedVector2Array, eps: float) -> PackedVector2Array:
	var n := poly.size()
	if n < 8:
		return poly
	var far := 0
	var best := -1.0
	for i in n:
		var d := poly[0].distance_squared_to(poly[i])
		if d > best:
			best = d
			far = i
	if far < 2 or far > n - 2:
		return poly
	var part_a := PackedVector2Array()
	for i in range(0, far + 1):
		part_a.append(poly[i])
	var part_b := PackedVector2Array()
	for i in range(far, n):
		part_b.append(poly[i])
	part_b.append(poly[0])
	var sa := _dp(part_a, eps)
	var sb := _dp(part_b, eps)
	var out := PackedVector2Array()
	for i in sa.size() - 1:
		out.append(sa[i])
	for i in sb.size() - 1:
		out.append(sb[i])
	if out.size() < 6:
		return poly
	return out


static func _dp(pts: PackedVector2Array, eps: float) -> PackedVector2Array:
	var m := pts.size()
	if m < 3:
		return pts
	var keep := PackedByteArray()
	keep.resize(m)
	keep[0] = 1
	keep[m - 1] = 1
	var stack: Array[Vector2] = [Vector2(0.0, float(m - 1))]
	while not stack.is_empty():
		var seg: Vector2 = stack.pop_back()
		var i0 := int(seg.x)
		var i1 := int(seg.y)
		if i1 <= i0 + 1:
			continue
		var a := pts[i0]
		var b := pts[i1]
		var ab := b - a
		var len2 := ab.length_squared()
		var dmax := -1.0
		var idx := -1
		for i in range(i0 + 1, i1):
			var p := pts[i]
			var d := 0.0
			if len2 < 1e-12:
				d = p.distance_to(a)
			else:
				var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
				d = p.distance_to(a + ab * t)
			if d > dmax:
				dmax = d
				idx = i
		if dmax > eps and idx > i0:
			keep[idx] = 1
			stack.append(Vector2(float(i0), float(idx)))
			stack.append(Vector2(float(idx), float(i1)))
	var out := PackedVector2Array()
	for i in m:
		if keep[i] == 1:
			out.append(pts[i])
	return out


static func _area(p: PackedVector2Array) -> float:
	var s := 0.0
	var n := p.size()
	for i in n:
		var a := p[i]
		var b := p[(i + 1) % n]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


## 归一化：主轴对齐 X 轴，刀尖朝 +X，长度缩放到 1.0
static func normalize_outline(poly: PackedVector2Array) -> PackedVector2Array:
	var n := poly.size()
	if n < 4:
		return PackedVector2Array()

	# 1) 主轴方向：用 PCA（协方差主方向）
	#    以前用"最远点对"，对细长刀身会挑到对角线 —— 比如刀茎那端画了一条竖直边，
	#    最远点就是"上角 ↔ 刀尖下侧"，整把刀会被转歪几度。
	var cen := Vector2.ZERO
	for p in poly:
		cen += p
	cen /= float(n)
	var sxx := 0.0
	var syy := 0.0
	var sxy := 0.0
	for p in poly:
		var dv := p - cen
		sxx += dv.x * dv.x
		syy += dv.y * dv.y
		sxy += dv.x * dv.y
	var ang := -0.5 * atan2(2.0 * sxy, sxx - syy)
	var rot := PackedVector2Array()
	for p in poly:
		rot.append((p - cen).rotated(ang))

	# 2) 决定哪一头当刀尖：更"细"的那一头
	var minx := 1e9
	var maxx := -1e9
	for p in rot:
		minx = minf(minx, p.x)
		maxx = maxf(maxx, p.x)
	var span := maxf(0.0001, maxx - minx)
	var cut := span * 0.12
	var w_lo := _span_y(rot, minx, minx + cut)
	var w_hi := _span_y(rot, maxx - cut, maxx)
	var flip := w_hi > w_lo * 1.25   # 大头在 +X → 需要翻转
	var res := PackedVector2Array()
	for p in rot:
		var q := p
		if flip:
			q = Vector2(-p.x, p.y)
		res.append(q)

	# 3) 重新算包围盒，缩放到长度 1.0，居中
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for p in res:
		mn = mn.min(p)
		mx = mx.max(p)
	var size := mx - mn
	var length := maxf(size.x, 0.0001)
	var center := (mn + mx) * 0.5
	var out := PackedVector2Array()
	for p in res:
		out.append((p - center) / length)
	return out


static func _span_y(poly: PackedVector2Array, x0: float, x1: float) -> float:
	var lo := 1e9
	var hi := -1e9
	for p in poly:
		if p.x >= x0 and p.x <= x1:
			lo = minf(lo, p.y)
			hi = maxf(hi, p.y)
	if lo > hi:
		return 0.0
	return hi - lo


## 预设剑身：直接给出归一化轮廓，玩家可以在此基础上描摹 / 修改
## 注意：这里必须是 PackedVector2Array，Array 不能隐式赋给 PackedVector2Array
static func preset_outlines() -> Array:
	return [
		{
			"name": "经典直刀（Drop Point）",
			"pts": PackedVector2Array([
				Vector2(-0.50, 0.045), Vector2(-0.18, 0.052), Vector2(0.16, 0.050),
				Vector2(0.38, 0.040), Vector2(0.50, 0.004), Vector2(0.46, -0.020),
				Vector2(0.20, -0.042), Vector2(-0.12, -0.052), Vector2(-0.50, -0.048)
			])
		},
		{
			"name": "猎刀（Hunter）",
			"pts": PackedVector2Array([
				Vector2(-0.50, 0.030), Vector2(-0.10, 0.050), Vector2(0.22, 0.045),
				Vector2(0.42, 0.020), Vector2(0.50, -0.010), Vector2(0.30, -0.030),
				Vector2(0.02, -0.070), Vector2(-0.24, -0.060), Vector2(-0.50, -0.040)
			])
		},
		{
			"name": "砍刀（Chopper）",
			"pts": PackedVector2Array([
				Vector2(-0.50, 0.075), Vector2(-0.10, 0.085), Vector2(0.26, 0.080),
				Vector2(0.48, 0.050), Vector2(0.50, 0.000), Vector2(0.42, -0.060),
				Vector2(0.10, -0.080), Vector2(-0.20, -0.078), Vector2(-0.50, -0.070)
			])
		},
		{
			"name": "日本刀（Katana）",
			"pts": PackedVector2Array([
				Vector2(-0.50, 0.028), Vector2(-0.20, 0.030), Vector2(0.10, 0.032),
				Vector2(0.34, 0.028), Vector2(0.46, 0.018), Vector2(0.50, 0.000),
				Vector2(0.42, -0.022), Vector2(0.16, -0.040), Vector2(-0.16, -0.048),
				Vector2(-0.50, -0.042)
			])
		},
		{
			"name": "短剑（Dagger）",
			"pts": PackedVector2Array([
				Vector2(-0.50, 0.036), Vector2(-0.24, 0.044), Vector2(0.06, 0.040),
				Vector2(0.34, 0.024), Vector2(0.50, 0.000), Vector2(0.34, -0.024),
				Vector2(0.06, -0.040), Vector2(-0.24, -0.044), Vector2(-0.50, -0.036)
			])
		},
		{
			"name": "太刀（Tachi）",
			# 真实太刀是一条连续弧：刀茎也在弧上，刀尖再向上翘。
			# 手调折线画不出这种曲率，所以用圆弧程序化生成。
			"pts": _arc_blade(0.050, 0.021, 18),		},
		{
			"name": "长剑（Longsword）",
			"pts": PackedVector2Array([
				Vector2(-0.50, 0.030), Vector2(-0.28, 0.034), Vector2(0.18, 0.030),
				Vector2(0.34, 0.022), Vector2(0.50, 0.000), Vector2(0.34, -0.022),
				Vector2(0.18, -0.030), Vector2(-0.28, -0.034), Vector2(-0.50, -0.030)
			])
		},
		{
			"name": "弯刀（Khopesh 式）",
			"pts": PackedVector2Array([
				Vector2(-0.50, 0.030), Vector2(-0.16, 0.058), Vector2(0.10, 0.072),
				Vector2(0.36, 0.062), Vector2(0.49, 0.020), Vector2(0.46, -0.026),
				Vector2(0.22, -0.044), Vector2(-0.08, -0.052), Vector2(-0.34, -0.046),
				Vector2(-0.50, -0.034)
			])
		}
	]

## 用抛物线弧生成太刀刀身（不含刀茎 —— 手柄由 HandleBuilder 另外生成）
## sori = 弧高，w = 刀身半宽，n = 采样段数
static func _arc_blade(sori: float, w: float, n: int) -> PackedVector2Array:
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	var tilt := sori * 0.85                                    # 刀尖整体上翘
	for i in n + 1:
		var u := float(i) / float(n)                           # 0 = 刀根，1 = 刀尖
		var x := lerpf(-0.5, 0.5, u)
		var arc := sori * (1.0 - pow(2.0 * u - 1.0, 2.0))      # 中间最高的弧
		var y := arc * 0.55 + tilt * u
		# 刀身几乎等宽：只有最后 28% 才收细成尖，根部只略窄一丁点
		var half := w
		if u > 0.72:
			var k := (u - 0.72) / 0.28
			half = w * (1.0 - 0.88 * pow(k, 1.7))
		elif u < 0.05:
			half = w * lerpf(0.86, 1.0, u / 0.05)
		top.append(Vector2(x, y + half))
		bot.append(Vector2(x, y - half * 0.55))                # 刃口侧略薄
	return _join(top, bot)

static func _join(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	var r := a
	for i in range(b.size() - 1, -1, -1):
		r.append(b[i])
	return r