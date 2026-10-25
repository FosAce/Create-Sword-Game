class_name ForgeSim
extends RefCounted
## 锻造规则与数值模型。目标不是物理精确，而是"手感真实"：
## 每一步的选择都要能在最终评分里找到因果。

const QUENCH_NAMES := ["空冷（正火）", "油淬", "水淬"]
const QUENCH_SEVERITY := [0.30, 1.00, 1.55]
const QUENCH_HARD_FACTOR := [0.52, 0.95, 1.00]

# ---------- 锻接（叠层锻合） ----------
## 真实锻接需要 1150~1280℃、撒硼砂防氧化、锤击让两片金属原子互扩散。
static func weld_quality(temp: float, flux: bool, carbon: float, fold_index: int) -> float:
	var t := 1.0 - clampf(absf(temp - 1220.0) / 140.0, 0.0, 1.0)   # 温度窗口
	var q := 0.30 + t * 0.55
	if flux:
		q += 0.16
	q -= maxf(0.0, carbon - 0.85) * 0.55        # 高碳钢更易脱碳/过烧
	q -= float(fold_index) * 0.012              # 层数越多越难锻透
	return clampf(q, 0.05, 1.0)


## 一次完整的加热循环：氧化皮厚度 / 碳烧损
static func scale_loss(minutes: float, temp: float) -> float:
	return clampf(minutes * 0.006 * maxf(0.0, (temp - 1000.0) / 300.0), 0.0, 0.12)


# ---------- 热处理 ----------
static func heat_treatment(s: SwordData, rng: RandomNumberGenerator) -> void:
	var carbon := SteelDB.mix_carbon(s.core_id, s.alt_id)
	var harden := SteelDB.mix_harden(s.core_id, s.alt_id)
	var carbon_equiv := carbon - scale_loss(s.temper_time * 0.05, s.aus_temp)

	# 可达到的最高硬度（碳含量 + 淬透性）
	var max_hrc := clampf(40.0 + carbon_equiv * 30.0 * harden, 18.0, 68.0)

	# 奥氏体化温度窗口
	var band: Vector2 = SteelDB.OPTIMAL_AUS.get(s.core_id, Vector2(790.0, 840.0))
	var mid := (band.x + band.y) * 0.5
	var temp_ok := 1.0 - clampf(absf(s.aus_temp - mid) / 95.0, 0.0, 1.0)

	# 介质索引做一次夹紧，避免以后加介质时数组越界
	var qm := clampi(s.quench_medium, 0, QUENCH_HARD_FACTOR.size() - 1)
	var qf: float = QUENCH_HARD_FACTOR[qm]

	# ---- 覆土烧刃：刀背厚土 → 冷却慢 → 不形成马氏体（软而韧）；
	#      刃口裸奔 → 全硬化。两者交界就是"刃文"(hamon)。----
	var diff := clampf(s.clay_spine - s.clay_edge, 0.0, 1.0)
	var edge_soft := clampf(s.clay_edge, 0.0, 1.0)
	s.hamon = diff * (1.0 if qm >= 1 else 0.30)   # 空冷本来就不硬化，没有刃文

	var hrc := max_hrc * qf * (0.78 + 0.22 * temp_ok)
	hrc *= 1.0 - diff * 0.12        # 刀背变软，平均硬度降一点
	hrc -= edge_soft * 9.0          # 刃口覆土 = 淬不硬，切开东西会卷刃

	# 回火：温度换韧性，硬度按经验每 100℃ 掉 1.5~2 HRC
	hrc -= maxf(0.0, s.temper_temp - 20.0) * 0.0165
	hrc -= maxf(0.0, s.temper_time - 90.0) * 0.004
	# 镦锻/正火次数带来一点组织细化补偿
	hrc += minf(float(s.normalized_cycles) * 0.4, 1.2)

	# 没淬上火（空冷 + 低碳钢）
	if qf < 0.6 and harden < 0.6:
		hrc *= 0.72

	s.hardness = clampf(hrc, 12.0, 68.0)

	# ---- 韧性 ----
	var t := SteelDB.mix_tough(s.core_id, s.alt_id)
	t *= lerpf(0.55, 1.18, clampf((s.temper_temp - 120.0) / 220.0, 0.0, 1.0))
	t *= 1.0 - clampf((carbon - 0.70) * 0.95, 0.0, 0.45)
	t *= 1.0 - float(qm) * 0.06
	t += minf(float(s.normalized_cycles) * 0.03, 0.09)
	t += diff * 0.24                # 软刀背 = 抗折断能力大幅提升

	# ---- 形变（淬火应力 / 形状不对称 / 冷却烈度）----
	var asym := geometry_asymmetry(s.outline)
	var wobble := rng.randf_range(-0.15, 0.15)
	s.warp = clampf(
		QUENCH_SEVERITY[qm] * (0.10 + asym * 0.42) * (1.0 + wobble)
		+ (1.0 - temp_ok) * 0.20
		- float(s.normalized_cycles) * 0.05
		- diff * 0.12,
		0.0, 0.85)

	# ---- 开裂 ----
	var risk := 0.02
	risk += float(qm) * 0.055
	risk -= diff * 0.08            # 覆土降低淬火应力、减少开裂
	risk += maxf(0.0, carbon - 0.88) * 0.55
	risk += maxf(0.0, s.aus_temp - 870.0) * 0.0022
	risk -= clampf(s.temper_temp / 500.0, 0.0, 0.20)
	risk += maxf(0.0, 0.010 - s.thickness) * 22.0
	risk += maxf(0.0, 0.55 - s.fidelity) * 0.30
	s.cracked = rng.randf() < clampf(risk, 0.0, 0.8)

	if s.cracked:
		t *= 0.35
		s.hardness *= 0.85
	s.toughness = clampf(t, 0.02, 1.0)


# ---------- 几何评价 ----------
## 用主轴坐标系量一下轮廓的对称度（0 完全对称 -> 1 极不对称）
static func geometry_asymmetry(poly: PackedVector2Array) -> float:
	if poly.size() < 4:
		return 0.3
	var n := 24
	var hi := PackedFloat32Array()
	var lo := PackedFloat32Array()
	hi.resize(n)
	lo.resize(n)
	for i in n:
		hi[i] = -1e9
		lo[i] = 1e9
	var minx := 1e9
	var maxx := -1e9
	for p in poly:
		minx = minf(minx, p.x)
		maxx = maxf(maxx, p.x)
	var span := maxf(0.0001, maxx - minx)
	for p in poly:
		var b := clampi(int((p.x - minx) / span * float(n)), 0, n - 1)
		hi[b] = maxf(hi[b], p.y)
		lo[b] = minf(lo[b], p.y)
	var acc := 0.0
	var cnt := 0
	for i in n:
		if hi[i] < -1e8 or lo[i] > 1e8:
			continue
		acc += absf(hi[i] + lo[i])
		cnt += 1
	if cnt == 0:
		return 0.5
	var mean_off := acc / float(cnt)
	var width := 0.0001
	for i in n:
		if hi[i] > -1e8 and lo[i] < 1e8:
			width = maxf(width, hi[i] - lo[i])
	return clampf(mean_off / width * 1.6, 0.0, 1.0)


## 刀形几何评分：长宽比是否合理、是否对称
static func geometry_score(poly: PackedVector2Array) -> float:
	if poly.size() < 4:
		return 0.2
	var minv := Vector2(1e9, 1e9)
	var maxv := Vector2(-1e9, -1e9)
	for p in poly:
		minv = minv.min(p)
		maxv = maxv.max(p)
	var size := maxv - minv
	if size.x < 0.01 or size.y < 0.01:
		return 0.15
	var aspect := size.x / size.y
	# 合理区间放宽到 3~22：短剑/猎刀在 8 左右，长剑 15、太刀 18 都该算合格
	var asp_score := 1.0
	if aspect < 3.0:
		asp_score = clampf(aspect / 3.0, 0.15, 1.0) * 0.75
	elif aspect > 22.0:
		asp_score = clampf(1.0 - (aspect - 22.0) / 14.0, 0.35, 1.0)
	var sym := 1.0 - geometry_asymmetry(poly) * 0.55
	return clampf(asp_score * 0.55 + sym * 0.45, 0.0, 1.0)


# ---------- 总评 ----------
static func evaluate(s: SwordData) -> Dictionary:
	var pat := s.pattern_score()
	var hard_s := clampf((s.hardness - 42.0) / 22.0, 0.0, 1.0)
	var tough_s := clampf(s.toughness, 0.0, 1.0)
	var geo := geometry_score(s.outline) * lerpf(0.75, 1.0, clampf(s.fidelity, 0.0, 1.0))
	var craft := clampf(s.grind * 0.55 + s.polish * 0.30 + s.pattern_visibility() * 0.15, 0.0, 1.0)
	var handle := clampf(0.35 + s.carve_cover * 0.75 + float(s.guard_style) * 0.06, 0.0, 1.0)

	var total := pat * 30.0 + hard_s * 20.0 + tough_s * 18.0 \
			+ geo * 15.0 + craft * 10.0 + handle * 7.0
	total += clampf(s.hamon, 0.0, 1.0) * 4.0     # 漂亮的刃文加分
	if s.cracked:
		total *= 0.62
	total = clampf(total, 0.0, 100.0)

	var title := "废铁一块"
	if total >= 88.0:
		title = "传奇名刀"
	elif total >= 76.0:
		title = "大师之作"
	elif total >= 62.0:
		title = "匠人手笔"
	elif total >= 45.0:
		title = "学徒习作"

	var comments: Array[String] = []
	if pat < 0.25:
		comments.append("花纹几乎看不出来——要么层数太少，要么酸洗时间不对。")
	elif pat > 0.7:
		comments.append("层理清晰、反差漂亮，这花纹是能拿出去卖钱的。")
	if s.hardness < 48.0:
		comments.append("硬度偏低，切东西会卷刃。检查淬火介质和含碳量。")
	if s.toughness < 0.35:
		comments.append("太脆了，横着敲一下就断。回火温度可以再高一点。")
	if s.warp > 0.45:
		comments.append("淬火形变明显，刀身是弯的。下次多做正火、注意入水角度。")
	if s.cracked:
		comments.append("刃口有淬火裂纹，这把只能当装饰了。")
	if geo < 0.45:
		comments.append("刀形不太成比例，长宽比或对称度需要调整。")
	if s.carve_cover > 0.12:
		comments.append("柄上的雕刻很有味道。")
	if s.hamon > 0.45:
		comments.append("刃文很漂亮——刀背软韧、刃口坚硬，这是最考功夫的一手。")
	elif s.clay_edge > 0.25:
		comments.append("你把土糊到刃口上了：刃口没淬硬，切东西会卷。")
	if comments.is_empty():
		comments.append("挑不出大毛病，稳。")

	return {
		"total": total,
		"title": title,
		"pattern": pat,
		"hardness": hard_s,
		"toughness": tough_s,
		"geometry": geo,
		"craft": craft,
		"handle": handle,
		"comments": comments
	}
