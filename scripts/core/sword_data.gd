class_name SwordData
extends RefCounted
## 一把刀的全部"记忆"：原料 → 层数 → 扭转 → 设计图 → 锻打 → 热处理 → 研磨 → 柄
## 所有数值都会被 ForgeSim 换算成真实感很强的性能/外观参数。

# ---------------- 原料与花纹钢 ----------------
var core_id: String = "c1084"      # 主钢（决定硬度）
var alt_id: String = "n15n20"      # 夹层钢（决定反差）
var stack_layers: int = 9          # 初始叠层数（块数）
var folds: int = 4                 # 折叠次数
var weld_quality: float = 1.0      # 锻合质量 0..1（温度、硼砂、锤击决定）
var twist_turns: float = 2.0       # 扭转圈数
var twist_sign: int = 1            # 扭转方向
var pattern_style: int = 1         # 0直纹 1扭转 2雨滴 3羽纹 4火焰
var cheat_induce_defect: bool = false

# ---------------- 设计（最重要的一环） ----------------
var outline: PackedVector2Array = PackedVector2Array()   # 归一化轮廓，刀尖在 +X
var design_source: String = "preset"
var fidelity: float = 1.0          # 锻打贴合度 0.6..1.0
var forged_outline: PackedVector2Array = PackedVector2Array()  # 锻打后的真实轮廓
var forged_dev: float = 0.0        # 锻造偏差（设计图 vs 实际锻出的形状）
var blade_width: float = 0.16      # 最大宽度（世界单位，1.0 = 刀长）
var thickness: float = 0.0125      # 刀背厚度（世界单位）
# ---- 横截面（P1）----
var xs_ridge: float = 0.0          # 中脊高度 0=平磨 1=高脊
var xs_fuller_w: float = 0.0       # 血槽宽度
var xs_fuller_d: float = 0.0       # 血槽深度
var xs_edge_angle: float = 0.5     # 刃口角度（0.5 = 旧造型）
var xs_secondary: float = 0.0      # 二次斜面

# ---------------- 热处理 ----------------
var quench_medium: int = 1         # 0 空冷 1 油淬 2 水淬
var aus_temp: float = 810.0        # 奥氏体化温度
var temper_temp: float = 200.0     # 回火温度
var temper_time: float = 60.0      # 回火分钟
var normalized_cycles: int = 1     # 正火次数
var hardness: float = 0.0
var toughness: float = 0.0
var warp: float = 0.0
var cracked: bool = false

# ---------------- 覆土烧刃 ----------------
var clay_mask: Image = null        # R = 覆土厚度（1=厚土不硬化）
var clay_spine: float = 0.0        # 刀背覆土量
var clay_edge: float = 0.0         # 刃口覆土量（刃口覆土 = 淬不硬）
var hamon: float = 0.0             # 刃文强度 0..1（刀背与刃口覆土差）

# ---------------- 表面处理 ----------------
var grind: float = 0.0             # 研磨完成度 0..1
var etch_minutes: float = 0.0      # 酸洗时间
var polish: float = 0.0            # 抛光 0..1

# ---------------- 柄 ----------------
var handle_preset: int = 0
var handle_wood: int = 0
var handle_custom: bool = false     # 自定义柄形（用下面四个参数而不是预设剖面）
var handle_r0: float = 0.046        # 柄前端半径
var handle_r1: float = 0.038        # 中段半径
var handle_r2: float = 0.044        # 尾端半径
var handle_flat: float = 1.0        # 1 = 圆柄, 0.5 = 扁柄
var handle_angle: float = 0.0       # 刀柄相对刀茎的旋转（度），用来对齐弯刀
var guard_style: int = 0           # 0 无护手 1 铁护手 2 铜护手 3 木护手
var guard_shape: int = 0           # 0 圆盘 1 十字横条 2 弧形 3 碗形 4 宽圆盘
var inlay_style: int = 0           # 镶嵌材料 0金 1银 2钻石 3铜 4黑漆 5朱漆
var pommel_style: int = 0          # 0 无 1 铆钉 2 金属尾铁
var face_mask: Image = null       # 刃面：R=浮雕深度 G=镶嵌 B=材料号
var face_rect: Rect2 = Rect2(0, 0, 1, 1)   # 画布覆盖的 UV 区域
var gem_style: int = 0             # 护手宝石 0无 1红 2蓝 3绿
var gem_shape: int = 0             # 宝石形状 0圆磨 1棱形
var guard_color: Color = Color("8a8f96")   # 护手/尾铁颜色
var guard_metal: float = 1.0               # 金属度：1 金属 / 0 磨砂
var guard_rough: float = 0.30              # 粗糙度：越小越亮
var pommel_color: Color = Color("8a8f96")  # 尾铁颜色（独立于护手）
var pommel_metal: float = 1.0
var pommel_rough: float = 0.30
var face_cover: float = 0.0
var carve_mask: Image = null       # R=雕刻深度 G=填漆
var carve_ink: float = 0.0         # 填漆覆盖量（统计）
var carve_cover: float = 0.0       # 雕刻覆盖率（统计）

# ---------------- 结果 ----------------
var sword_name: String = ""
var final_score: float = 0.0
var score_breakdown: Dictionary = {}


func layer_count() -> int:
	var n := stack_layers
	for i in folds:
		n *= 2
	return n


## 视觉上能表现的层数：真实层数过细时肉眼只能看到"雾"，
## 这里映射成 8..46 的可见条带数（游戏里好看最重要）
func visual_layers() -> float:
	return clampf(8.0 + float(layer_count()) / 16.0, 8.0, 46.0)


func contrast() -> float:
	return SteelDB.pair_contrast(core_id, alt_id)


## 酸洗显现度：时间太短看不出、太长会糊成一团
func pattern_visibility() -> float:
	var t := etch_minutes
	if t <= 0.0:
		return 0.0
	var ideal := 4.5 + layer_count() * 0.001
	var d := absf(t - ideal) / maxf(ideal, 0.5)
	return clampf(1.0 - d * 0.85, 0.0, 1.0)


## 层数本身的"纹路细腻度"
func layer_texture_score() -> float:
	var n := float(layer_count())
	if n < 16.0:
		return 0.35
	if n < 400.0:
		return clampf(0.45 + (n - 16.0) / 384.0 * 0.55, 0.0, 1.0)
	return clampf(1.0 - (n - 400.0) / 3000.0, 0.45, 1.0)


func pattern_score() -> float:
	var c := contrast()
	var vis := pattern_visibility()
	var lt := layer_texture_score()
	var weld := lerpf(0.35, 1.0, clampf(weld_quality, 0.0, 1.0))
	return clampf(c * vis * lt * weld * 1.15, 0.0, 1.0)


## 供 damascus.gdshader 使用的 uniform 字典
func damascus_uniforms() -> Dictionary:
	var tw := twist_turns * 0.42 * float(twist_sign)
	# 直纹/雨滴/火焰/梯纹/马赛克 本身不靠扭转成形，扭转只留一点点扰动
	if pattern_style in [0, 2, 4, 5, 6]:
		tw = minf(tw, 0.12)
	var chev := 1.2 + twist_turns * 0.55
	var grain := clampf(0.18 + (1.0 - weld_quality) * 0.9, 0.0, 1.0)
	return {
		"layer_freq": visual_layers(),
		"twist": tw,
		"chevron": chev,
		"style": pattern_style,
		"contrast": clampf(0.28 + contrast() * 0.58, 0.0, 0.90),
		"etch": pattern_visibility(),
		"grain": grain, "aniso": clampf(grind * 0.85, 0.0, 1.0),
		"hamon": hamon,
		"col_dark": Color(0.40, 0.41, 0.44),
		"base_rough": lerpf(0.42, 0.09, clampf(polish, 0.0, 1.0)),
		"grind_marks": 1.0 - clampf(grind, 0.0, 1.0),
		"seed": float(abs(hash(core_id + alt_id)) % 97) + 3.0
	}


func thickness_ok() -> float:
	# 真实的刀背厚度：刃身越长越厚，但这里由玩家在锻打阶段控制
	return thickness


# ---------------- 锻打结果 → 刀身轮廓 ----------------
## 最终用于生成网格的轮廓：把设计图向"实际锻出来的形状"偏移，
## 偏移量被夹在 ±2% 刀长内，所以锤歪了刀就歪，但不会变成一坨。
func mesh_outline() -> PackedVector2Array:
	if forged_outline.size() < 4:
		return outline
	if outline.size() < 4:
		return forged_outline
	# 关键：锻打轮廓是从"锤打网格"里抠出来的，坐标系和设计图不一样（没归一到
	# 长度 1、也没按主轴摆正）。直接用会把设计图拽歪 —— 先归一化到同一套标准空间。
	var fg := ContourTrace.normalize_outline(forged_outline)
	if fg.size() < 4:
		return outline
	return _warp_toward(outline, fg, 0.60, 0.020)


func _warp_toward(base: PackedVector2Array, target: PackedVector2Array,
		blend: float, cap: float) -> PackedVector2Array:
	var n := base.size()
	var c := Vector2.ZERO
	for p in base:
		c += p
	c /= float(n)
	# 目标多边形的最长边当作距离归一化的参考
	var out := PackedVector2Array()
	var dev_sum := 0.0
	for i in n:
		var v := base[i]
		var prev := base[(i - 1 + n) % n]
		var nxt := base[(i + 1) % n]
		var tan := (nxt - prev)
		if tan.length() < 0.000001:
			tan = Vector2.RIGHT
		tan = tan.normalized()
		var nrm := Vector2(tan.y, -tan.x)
		if nrm.dot(v - c) < 0.0:
			nrm = -nrm          # 确保朝外
		var d := _dist_to_poly(v, target)
		if not Geometry2D.is_point_in_polygon(v, target):
			d = -d
		dev_sum += absf(d)
		out.append(v + nrm * clampf(d, -cap, cap) * blend)
		# 记录偏差（在 mesh_outline 里也算一次，代价很小）
		if i == 0:
			pass
	forged_dev = dev_sum / float(maxf(1.0, float(n)))
	return out


static func _dist_to_poly(p: Vector2, poly: PackedVector2Array) -> float:
	var best := 1e9
	var m := poly.size()
	for i in m:
		var a := poly[i]
		var b := poly[(i + 1) % m]
		var ab := b - a
		var l2 := ab.length_squared()
		var q := a
		if l2 > 0.0000001:
			q = a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0)
		best = minf(best, p.distance_to(q))
	return best


func summary() -> String:
	var s := ""
	s += "%s + %s，叠 %d 层，折 %d 次 → %d 层\n" % [
		SteelDB.get_steel(core_id)["short"], SteelDB.get_steel(alt_id)["short"],
		stack_layers, folds, layer_count()
	]
	s += "硬度 %.1f HRC ｜ 韧性 %.0f%% ｜ 形变 %.2f ｜ %s\n" % [
		hardness, toughness * 100.0, warp, "已断裂" if cracked else "完好"
	]
	return s


# ---------------- 存档 ----------------
func to_dict() -> Dictionary:
	var pts: Array = []
	for p in outline:
		pts.append(snappedf(p.x, 0.000001))
		pts.append(snappedf(p.y, 0.000001))
	return {
		"version": 2,
		"core_id": core_id, "alt_id": alt_id,
		"stack_layers": stack_layers, "folds": folds, "weld_quality": weld_quality,
		"twist_turns": twist_turns, "twist_sign": twist_sign, "pattern_style": pattern_style,
		"design_source": design_source, "fidelity": fidelity,
		"forged_dev": forged_dev,
		"blade_width": blade_width, "thickness": thickness, "xs_ridge": xs_ridge, "xs_fuller_w": xs_fuller_w, "xs_fuller_d": xs_fuller_d, "xs_edge_angle": xs_edge_angle, "xs_secondary": xs_secondary,
		"quench_medium": quench_medium, "aus_temp": aus_temp,
		"temper_temp": temper_temp, "temper_time": temper_time,
		"normalized_cycles": normalized_cycles,
		"hardness": hardness, "toughness": toughness, "warp": warp, "cracked": cracked,
		"clay_spine": clay_spine, "clay_edge": clay_edge, "hamon": hamon,
		"grind": grind, "etch_minutes": etch_minutes, "polish": polish,
		"handle_preset": handle_preset, "handle_wood": handle_wood,
		"handle_custom": handle_custom, "handle_r0": handle_r0,
		"handle_r1": handle_r1, "handle_r2": handle_r2, "handle_flat": handle_flat,
		"guard_style": guard_style, "pommel_style": pommel_style, "handle_angle": handle_angle,
		"guard_shape": guard_shape, "inlay_style": inlay_style, "gem_style": gem_style, "gem_shape": gem_shape, "guard_color": guard_color.to_html(), "guard_metal": guard_metal, "guard_rough": guard_rough, "pommel_color": pommel_color.to_html(), "pommel_metal": pommel_metal, "pommel_rough": pommel_rough, "face_rect": [face_rect.position.x, face_rect.position.y, face_rect.size.x, face_rect.size.y],
		"carve_cover": carve_cover, "carve_ink": carve_ink,
		"sword_name": sword_name, "final_score": final_score,
		"outline": pts,
		"forged": _poly_to_array(forged_outline)
	}


static func _poly_to_array(poly: PackedVector2Array) -> Array:
	var arr: Array = []
	for p in poly:
		arr.append(snappedf(p.x, 0.00001))
		arr.append(snappedf(p.y, 0.00001))
	return arr


static func _array_to_poly(arr: Array) -> PackedVector2Array:
	var poly := PackedVector2Array()
	var i := 0
	while i + 1 < arr.size():
		poly.append(Vector2(float(arr[i]), float(arr[i + 1])))
		i += 2
	return poly


static func from_dict(d: Dictionary) -> SwordData:
	var s := SwordData.new()
	s.core_id = str(d.get("core_id", "c1084"))
	s.alt_id = str(d.get("alt_id", "n15n20"))
	s.stack_layers = int(d.get("stack_layers", 9))
	s.folds = int(d.get("folds", 4))
	s.weld_quality = float(d.get("weld_quality", 1.0))
	s.twist_turns = float(d.get("twist_turns", 2.0))
	s.twist_sign = int(d.get("twist_sign", 1))
	s.pattern_style = int(d.get("pattern_style", 1))
	s.design_source = str(d.get("design_source", "saved"))
	s.fidelity = float(d.get("fidelity", 1.0))
	s.forged_dev = float(d.get("forged_dev", 0.0))
	s.blade_width = float(d.get("blade_width", 0.16))
	s.thickness = float(d.get("thickness", 0.0125))
	s.xs_ridge = float(d.get("xs_ridge", 0.0))
	s.xs_fuller_w = float(d.get("xs_fuller_w", 0.0))
	s.xs_fuller_d = float(d.get("xs_fuller_d", 0.0))
	s.xs_edge_angle = float(d.get("xs_edge_angle", 0.5))
	s.xs_secondary = float(d.get("xs_secondary", 0.0))
	s.quench_medium = int(d.get("quench_medium", 1))
	s.aus_temp = float(d.get("aus_temp", 810.0))
	s.temper_temp = float(d.get("temper_temp", 200.0))
	s.temper_time = float(d.get("temper_time", 60.0))
	s.normalized_cycles = int(d.get("normalized_cycles", 1))
	s.hardness = float(d.get("hardness", 0.0))
	s.toughness = float(d.get("toughness", 0.0))
	s.warp = float(d.get("warp", 0.0))
	s.cracked = bool(d.get("cracked", false))
	s.clay_spine = float(d.get("clay_spine", 0.0))
	s.clay_edge = float(d.get("clay_edge", 0.0))
	s.hamon = float(d.get("hamon", 0.0))
	s.grind = float(d.get("grind", 0.0))
	s.etch_minutes = float(d.get("etch_minutes", 0.0))
	s.polish = float(d.get("polish", 0.0))
	s.handle_preset = int(d.get("handle_preset", 0))
	s.handle_wood = int(d.get("handle_wood", 0))
	s.handle_custom = bool(d.get("handle_custom", false))
	s.handle_r0 = float(d.get("handle_r0", 0.046))
	s.handle_r1 = float(d.get("handle_r1", 0.038))
	s.handle_r2 = float(d.get("handle_r2", 0.044))
	s.handle_flat = float(d.get("handle_flat", 1.0))
	s.handle_angle = float(d.get("handle_angle", 0.0))
	s.guard_style = int(d.get("guard_style", 0))
	s.guard_shape = int(d.get("guard_shape", 0))
	s.inlay_style = int(d.get("inlay_style", 0))
	s.gem_style = int(d.get("gem_style", 0))
	s.gem_shape = int(d.get("gem_shape", 0))
	s.guard_color = Color(str(d.get("guard_color", "8a8f96")))
	s.guard_metal = float(d.get("guard_metal", 1.0))
	s.guard_rough = float(d.get("guard_rough", 0.30))
	s.pommel_color = Color(str(d.get("pommel_color", "8a8f96")))
	s.pommel_metal = float(d.get("pommel_metal", 1.0))
	s.pommel_rough = float(d.get("pommel_rough", 0.30))
	var fr: Array = d.get("face_rect", [0.0, 0.0, 1.0, 1.0])
	if fr.size() >= 4:
		s.face_rect = Rect2(float(fr[0]), float(fr[1]), float(fr[2]), float(fr[3]))
	s.pommel_style = int(d.get("pommel_style", 0))
	s.carve_cover = float(d.get("carve_cover", 0.0))
	s.carve_ink = float(d.get("carve_ink", 0.0))
	s.sword_name = str(d.get("sword_name", ""))
	s.final_score = float(d.get("final_score", 0.0))
	var arr: Array = d.get("outline", [])
	var poly := PackedVector2Array()
	var i := 0
	while i + 1 < arr.size():
		poly.append(Vector2(float(arr[i]), float(arr[i + 1])))
		i += 2
	s.outline = poly
	var farr: Array = d.get("forged", [])
	s.forged_outline = _array_to_poly(farr)
	return s
