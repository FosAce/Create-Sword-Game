class_name ForgeCanvas
extends Control
## ★ 自由锻打：坯料是一个"厚度场"，锤哪里就薄哪里，体积守恒地把材料挤向四周。
## 你要把它从一根短粗的方坯锤成图纸上的刀形；贴合度 = 与图纸的 IoU。
##
## 现实依据：锻造靠"体积不变"的塑性流动。锤子压下的地方变薄，材料必然向
## 四周流动 —— 所以想变长就往中部/末端锤，想变宽就往边缘锤。
## 料温低于可锻区间再硬砸，只会砸出裂纹（这里记 bad strike）。

signal accepted(fidelity: float, outline: PackedVector2Array)
signal cancelled()

const GX := 84
const GY := 42
const HAMMER_R := 3.3
const MIN_T := 0.16
const VIS_T := 0.10

var heat := 1.0
var strikes := 0
var reheats := 0
var bad := 0
var strength := 0.30
var iou := 0.0

var bb := Rect2()
var cells := PackedFloat32Array()
var target := PackedByteArray()
var target_poly := PackedVector2Array()

var _paper := Rect2()
var _cursor := Vector2(-9999, -9999)
var _hold := 0                    # 0 没按 / 1 左键延展 / 2 右键挤压
var _cool := 0.0
var _auto_left := 0               # 一键粗锻剩余锤数
var _auto_acc := 0.0
var _sweep_x := 0
var _sweep_quiet := 0
var _auto_strength := 0.30
var _auto_press_done := 0
var _strength_base := 0.30
var _strength_factor := 1.0
var _flash := 0.0
var _img: Image
var _tex: ImageTexture
var _preview: TextureRect
var _hint: Label
var _strength_slider: HSlider
var _sparks: Array = []          # 2D 火星粒子 {p, v, life, max}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_img = Image.create_empty(GX, GY, false, Image.FORMAT_RGBA8)
	_img.fill(Color(0, 0, 0, 0))
	_tex = ImageTexture.create_from_image(_img)
	_preview = TextureRect.new()
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.texture = _tex
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_preview)
	_build_toolbar()


func set_target(poly: PackedVector2Array) -> void:
	target_poly = poly
	if poly.size() < 4:
		return
	bb = Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		bb = bb.expand(p)
	bb = bb.grow(maxf(bb.size.y * 0.55, 0.012))
	_build_grid()


func _build_grid() -> void:
	cells.resize(GX * GY)
	cells.fill(0.0)
	target.resize(GX * GY)
	target.fill(0)
	# 目标轮廓栅格化
	var tcount := 0
	for j in GY:
		for i in GX:
			var p := _cell_world(Vector2i(i, j))
			if Geometry2D.is_point_in_polygon(p, target_poly):
				target[j * GX + i] = 1
				tcount += 1
	# 初始方坯：中间一根窄长的棒料（比刀身窄，要靠锤打延展）
	var hx := bb.size.x * 0.15
	var hy := bb.size.y * 0.12
	var c := bb.get_center()
	var bcount := 0
	for j in GY:
		for i in GX:
			var p := _cell_world(Vector2i(i, j))
			if absf(p.x - c.x) <= hx and absf(p.y - c.y) <= hy:
				cells[j * GX + i] = 1.0
				bcount += 1
	# 体积守恒：棒料的体积 = 目标面积 × 平均厚度
	var t0 := 1.0
	if bcount > 0 and tcount > 0:
		t0 = clampf(float(tcount) / float(bcount) * 0.95, 0.6, 6.0)
	for i in GX * GY:
		if cells[i] > 0.5:
			cells[i] = t0
	strikes = 0
	reheats = 0
	bad = 0
	heat = 1.0
	iou = _compute_iou()
	_update_tex()


func _cell_world(c: Vector2i) -> Vector2:
	var u := (float(c.x) + 0.5) / float(GX)
	var v := 1.0 - (float(c.y) + 0.5) / float(GY)
	return bb.position + Vector2(u, v) * bb.size


func _w2s(p: Vector2) -> Vector2:
	var u := (p.x - bb.position.x) / maxf(bb.size.x, 0.0001)
	var v := (p.y - bb.position.y) / maxf(bb.size.y, 0.0001)
	return _paper.position + Vector2(u, 1.0 - v) * _paper.size


func _s2cell(pos: Vector2) -> Vector2i:
	var t := (pos - _paper.position) / _paper.size
	return Vector2i(
		clampi(int(t.x * float(GX)), 0, GX - 1),
		clampi(int(t.y * float(GY)), 0, GY - 1))


func _build_toolbar() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UIKit.sb(Color("f6efdd"), 12, 2, Color(0, 0, 0, 0.05)))
	bar.anchor_right = 1.0
	bar.offset_bottom = 56
	add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	bar.add_child(h)

	h.add_child(UIKit.label("锤击力度", 15, Palette.UI_DIM))
	_strength_slider = UIKit.slider(0.10, 0.45, 0.02, strength)
	_strength_slider.custom_minimum_size = Vector2(150, 26)
	_strength_slider.value_changed.connect(func(v: float) -> void: strength = v)
	h.add_child(_strength_slider)

	var re := UIKit.button("回炉加热 (R)")
	re.pressed.connect(_reheat)
	h.add_child(re)

	# 一键粗锻：自动锤出个大概，剩下的自己修
	var press := UIKit.button("展平辊压 (F)")
	press.tooltip_text = "把坯料辊压成图纸的宽度 —— 长度还得自己锤"
	press.pressed.connect(roll_press)
	h.add_child(press)

	var auto := UIKit.button("一键粗锻 ✦")
	auto.tooltip_text = "自动锤到接近图纸，不会刚刚好 —— 还得你自己修"
	auto.pressed.connect(start_auto_forge)
	h.add_child(auto)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)

	var back := UIKit.button("放弃")
	back.pressed.connect(func() -> void: cancelled.emit())
	h.add_child(back)

	var ok := UIKit.button("收工 ▶", true)
	ok.pressed.connect(_on_accept)
	h.add_child(ok)

	_hint = UIKit.label("左键按住＝延展（材料往外挤）　｜　右键按住＝挤压（把边缘收进来）　｜　R＝回炉",
		15, Palette.UI_ACCENT2)
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_top = -28
	_hint.offset_left = 8
	add_child(_hint)


func _layout_paper() -> void:
	var area := Rect2(Vector2(60, 82), size - Vector2(120, 215))
	# 画布比例跟着图纸走：bb 是图纸的包围盒，2.3 这种写死值会让细长的太刀
	# 在屏幕上被纵向拉伸 3~4 倍，看起来像一条"胖船"（数据其实是对的）
	var aspect := 2.3
	if bb.size.y > 0.0001:
		aspect = clampf(bb.size.x / bb.size.y, 2.2, 4.6)
	var w := area.size.x
	var hh := w / aspect
	if hh > area.size.y:
		hh = area.size.y
		w = hh * aspect
	_paper = Rect2(area.position + (area.size - Vector2(w, hh)) * 0.5, Vector2(maxf(w, 1.0), maxf(hh, 1.0)))


func _process(dt: float) -> void:
	_layout_paper()
	if _preview:
		_preview.position = _paper.position
		_preview.size = _paper.size
	_flash = maxf(0.0, _flash - dt * 4.0)
	_cool = maxf(0.0, _cool - dt)
	if _hold != 0 and _cool <= 0.0 and _paper.has_point(_cursor):
		_strike(_s2cell(_cursor), _hold == 2)
	if _auto_left > 0:
		_auto_acc += dt
		var per := 0.016
		while _auto_acc >= per and _auto_left > 0:
			_auto_acc -= per
			for k in 6:
				if _auto_left <= 0:
					break
				_auto_left -= 1
				heat = maxf(heat, 0.82)
				_cool = 0.0
				if not _auto_tick():
					_auto_left = 0
					break
		if _auto_left == 0:
			strength = _strength_base
			_update_tex()
	_update_sparks(dt)
	queue_redraw()


func _update_sparks(dt: float) -> void:
	var i := _sparks.size() - 1
	while i >= 0:
		var s: Dictionary = _sparks[i]
		s["life"] = float(s["life"]) - dt
		if float(s["life"]) <= 0.0:
			_sparks.remove_at(i)
		else:
			var p: Vector2 = s["p"]
			var v: Vector2 = s["v"]
			v.y += 620.0 * dt
			v *= 0.985
			s["p"] = p + v * dt
			s["v"] = v
		i -= 1


func _spawn_sparks(at: Vector2, count: int, hot: bool) -> void:
	for k in count:
		var dir := Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 0.2)).normalized()
		var sp := _rng.randf_range(90.0, 320.0)
		_sparks.append({
			"p": at + dir * 6.0,
			"v": dir * sp,
			"life": _rng.randf_range(0.18, 0.45),
			"max": 0.45,
			"hot": hot
		})


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_cursor = event.position
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if _paper.has_point(mb.position):
					_hold = 1
					_cursor = mb.position
					_strike(_s2cell(mb.position), false)
					accept_event()
			else:
				_hold = 0
				accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				if _paper.has_point(mb.position):
					_hold = 2
					_cursor = mb.position
					_strike(_s2cell(mb.position), true)
					accept_event()
			else:
				_hold = 0
				accept_event()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_R:
			_reheat()


func _reheat() -> void:
	reheats += 1
	heat = 1.0
	SoundKit.play("hiss", 1.0, -14.0)
	_update_tex()


## ================= 展平辊压 =================
## 按图纸每一列的上下范围，把该列的材料重新铺平（列内总量守恒）。
## 这一步只修"宽度"，长度仍要靠锤 —— 正好补上一键粗锻缺的那一块。
func roll_press() -> void:
	if target.is_empty():
		return
	if heat < 0.28:
		if _hint:
			_hint.text = "坯料太冷了，按 R 回炉再辊压。"
		return
	for x in range(1, GX - 1):
		var t0 := 999
		var t1 := -1
		for y in GY:
			if target[y * GX + x] == 1:
				t0 = mini(t0, y)
				t1 = maxi(t1, y)
		if t1 < 0:
			continue
		# 这一列现在有多少料、铺在哪
		var total := 0.0
		var lo := 999
		var hi := -1
		for y in GY:
			var v := cells[y * GX + x]
			if v > 0.02:
				total += v
				lo = mini(lo, y)
				hi = maxi(hi, y)
		if hi < 0 or total < 0.05:
			continue
		var span := float(t1 - t0 + 1)
		var per := total / span
		# 区间内：向"均匀厚度"靠 75%（留 25% 的偏差，多辊几次才平）
		for y in range(t0, t1 + 1):
			var i := y * GX + x
			cells[i] = lerpf(cells[i], per, 0.75)
		# 区间外：料被挤回区间里，只留一点点毛边
		for y in GY:
			if y >= t0 and y <= t1:
				continue
			var i2 := y * GX + x
			if cells[i2] > 0.02:
				cells[i2] = 0.0
	heat = maxf(0.0, heat - 0.30)
	strikes += 5
	iou = _compute_iou()
	_update_tex()
	_flash = 1.0
	SoundKit.play("hammer", 0.78, -5.0)
	if _hint:
		_hint.text = "辊压完成：宽度已压到图纸，接下来锤两头把长度拉出来。"

## ================= 一键粗锻 =================
## 不是"一键完美"：贪心地补缺料 / 收多料，锤到差不多就停，
## 留下 10~25% 的偏差给玩家自己修。
func start_auto_forge() -> void:
	if _auto_left > 0 or target.is_empty():
		return
	# 先用辊压把宽度压到图纸（两遍足够收敛），再去锤长度
	roll_press()
	roll_press()

	# 薄刀（每列平均格数少）自动减小锤击力度，否则一锤就跨过目标宽度
	var tt := _target_extent()
	var avg_h := 9.0
	if not tt.is_empty():
		var span_x: int = maxi(1, int(tt[1]) - int(tt[0]) + 1)
		var tcount := 0
		for i in target.size():
			if target[i] == 1:
				tcount += 1
		avg_h = float(tcount) / float(span_x)
	_strength_base = strength
	_strength_factor = clampf(avg_h / 9.0, 0.42, 1.0)
	_auto_strength = strength * _strength_factor
	strength = _auto_strength
	_auto_left = 1400
	_sweep_x = 0
	_sweep_quiet = 0
	_auto_acc = 0.0
	SoundKit.play("hammer", 1.2, -8.0)


func _auto_tick() -> bool:
	if _sweep_quiet > GX * 2:
		return false
	# ---------- 扫掠式粗锻 ----------
	# 不再"只锤差距最大的那一格"（那样材料会堆在局部，坯料长不大），
	# 而是沿刀身长度方向一列一列扫过去，每列把"多出来的收掉 / 缺的挤出来"，
	# 像真人来回锤。扫完一轮再从最难的那一列重新扫。
	var m := _mass_extent()
	var t := _target_extent()
	if m.is_empty() or t.is_empty():
		return false

	# 1) 长度阶段：不够长就抽长、冲过头就收回来（谁差得多先处理谁）
	var left_gap: int = int(m[0]) - int(t[0])      # >1 表示左端不够长
	var right_gap: int = int(t[1]) - int(m[1])     # >1 表示右端不够长
	var over_l: int = int(t[0]) - int(m[0])        # >1 表示左端冲过头
	var over_r: int = int(m[1]) - int(t[1])        # >1 表示右端冲过头
	var cy0: int = (int(m[2]) + int(m[3])) / 2
	if over_l > 1 and over_l >= right_gap:
		var tl := Vector2i(int(m[0]) + 1, cy0)
		_aim(tl)
		_strike(tl, true)
		return true
	if over_r > 1 and over_r >= left_gap:
		var tr := Vector2i(int(m[1]) - 1, cy0)
		_aim(tr)
		_strike(tr, true)
		return true
	if left_gap > 1 or right_gap > 1:
		var cy: int = (int(m[2]) + int(m[3])) / 2
		if left_gap >= right_gap and left_gap > 1:
			var lc := _thickest_in(int(m[0]), int(m[0]) + 12, cy - 4, cy + 4)
			if lc.x >= 0:
				_aim(lc)
				_sweep_quiet = 0
				_strike(lc, false)
				return true
		if right_gap > 1:
			var rc := _thickest_in(int(m[1]) - 12, int(m[1]), cy - 4, cy + 4)
			if rc.x >= 0:
				_aim(rc)
				_sweep_quiet = 0
				_strike(rc, false)
				return true

	# 长度够了 → 再辊两遍，把中段的宽度压到位（这时每一列都有料了）
	if _auto_press_done < 2:
		_auto_press_done += 1
		roll_press()
		return true

	# 2) 逐列扫：从上次的位置继续往右扫（扫到头就回到左端）
	var x0: int = maxi(2, int(t[0]))
	var x1: int = mini(GX - 3, int(t[1]))
	_sweep_quiet += 1
	_sweep_x += 1
	if _sweep_x < x0 or _sweep_x > x1:
		_sweep_x = x0
	var x: int = _sweep_x
	var tmin := 999
	var tmax := -1
	for y in GY:
		if target[y * GX + x] == 1:
			tmin = mini(tmin, y)
			tmax = maxi(tmax, y)
	var cmin := 999
	var cmax := -1
	for y in GY:
		if cells[y * GX + x] > VIS_T:
			cmin = mini(cmin, y)
			cmax = maxi(cmax, y)

	# 图纸这一列没有料，但我们有 → 整列多余，收掉
	if tmax < 0:
		if cmax >= 0:
			var cell_g := Vector2i(x, cmax)
			_aim(cell_g)
			_sweep_quiet = 0
			_strike(cell_g, true)
			return true
		return true   # 两边都空，跳过去
	if cmax < 0:
		# 这一列完全没料：从左右最近有料的列往这边挤
		var src := _nearest_mass_column(x, x0, x1)
		if src >= 0:
			_aim(Vector2i(src, (tmin + tmax) / 2))
			_sweep_quiet = 0
			_strike(Vector2i(src, (tmin + tmax) / 2), false)
			return true
		return true

	# 上边：多则收、少则挤
	if cmin < tmin - 1:
		_aim(Vector2i(x, cmin))
		_sweep_quiet = 0
		_strike(Vector2i(x, cmin), true)
		return true
	if tmin < cmin - 1:
		var up := _thickest_in(x - 1, x + 1, cmin, cmin + 3)
		if up.x >= 0:
			_aim(up)
			_sweep_quiet = 0
			_strike(up, false)
			return true
	# 下边同理
	if cmax > tmax + 1:
		_aim(Vector2i(x, cmax))
		_sweep_quiet = 0
		_strike(Vector2i(x, cmax), true)
		return true
	if tmax > cmax + 1:
		var dn := _thickest_in(x - 1, x + 1, cmax - 3, cmax)
		if dn.x >= 0:
			_aim(dn)
			_sweep_quiet = 0
			_strike(dn, false)
			return true
	return true   # 这一列没事，下一帧扫下一列


## 找离 x 最近、且这一列有料的列
func _nearest_mass_column(x: int, x0: int, x1: int) -> int:
	for d in range(1, 14):
		for sx in [x - d, x + d]:
			if sx < x0 or sx > x1:
				continue
			for y in GY:
				if cells[y * GX + sx] > VIS_T:
					return sx
	return -1

## 在给定矩形里找最厚的一格（用来决定往哪儿锤最有效）
func _thickest_in(x0: int, x1: int, y0: int, y1: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bt := 0.0
	for y in range(maxi(0, y0), mini(GY, y1 + 1)):
		for x in range(maxi(0, x0), mini(GX, x1 + 1)):
			var v := cells[y * GX + x]
			if v > bt:
				bt = v
				best = Vector2i(x, y)
	if bt <= MIN_T + 0.02:
		return Vector2i(-1, -1)
	return best


func _mass_extent() -> Array:
	var x0 := 9999
	var x1 := -1
	var y0 := 9999
	var y1 := -1
	for y in GY:
		for x in GX:
			if cells[y * GX + x] > VIS_T:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	if x1 < 0:
		return []
	return [x0, x1, y0, y1]


func _target_extent() -> Array:
	var x0 := 9999
	var x1 := -1
	var y0 := 9999
	var y1 := -1
	for y in GY:
		for x in GX:
			if target[y * GX + x] == 1:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	if x1 < 0:
		return []
	return [x0, x1, y0, y1]


## 让锤击光圈跟着自动锤走（火星位置也用它）
func _aim(cell: Vector2i) -> void:
	_cursor = _paper.position + Vector2((float(cell.x) + 0.5) / float(GX),
		(float(cell.y) + 0.5) / float(GY)) * _paper.size
	_flash = 1.0


func _strike(cell: Vector2i, gather: bool = false) -> void:
	if _cool > 0.0:
		return
	_cool = 0.065
	_flash = 1.0
	if heat < 0.24:
		# 冷砸：打不动还砸出裂纹
		bad += 1
		_spawn_sparks(_cursor, 3, false)
		SoundKit.play("hammer", _rng.randf_range(0.85, 1.0), -12.0)
		_update_tex()
		return

	var od := (Vector2(cell) - Vector2(float(GX) * 0.5, float(GY) * 0.5))
	if od.length() > 0.001:
		od = od.normalized()
	else:
		od = Vector2.RIGHT

	# ---- 挤压（右键）：把最近的边缘"收"进锤点 → 形状变窄变短 ----
	if gather:
		var inlet := _find_boundary(cell, od)
		if inlet >= 0:
			var take := clampf((cells[inlet] - VIS_T * 0.4) * strength * 1.3 * (0.70 + 0.30 * heat),
				0.0, 0.50)
			if take > 0.003:
				cells[inlet] -= take
				cells[cell.y * GX + cell.x] += take
				heat = maxf(0.0, heat - 0.022)
				strikes += 1
				_spawn_sparks(_cursor, 3, false)
				SoundKit.play("hammer", _rng.randf_range(0.95, 1.10), -10.0)
				if strikes % 4 == 0:
					iou = _compute_iou()
				_update_tex()
				return
		heat = maxf(0.0, heat - 0.010)
		_update_tex()
		return

	# 1) 锤头覆盖 3x3：每格只减薄它的"多余量"，永远不会砸穿
	var block: Array[int] = []
	var total := 0.0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var nx := cell.x + dx
			var ny := cell.y + dy
			if nx < 0 or ny < 0 or nx >= GX or ny >= GY:
				continue
			var i2 := ny * GX + nx
			var dd := clampf((cells[i2] - MIN_T) * strength * (0.70 + 0.30 * heat), 0.0, 0.32)
			if dd <= 0.0005:
				continue
			cells[i2] -= dd
			total += dd
			block.append(i2)
	if total <= 0.003:
		heat = maxf(0.0, heat - 0.010)
		_update_tex()
		return

	# 2) 找最佳出口：朝外、离锤点最近的自由表面格子
	var best := -1
	var best_score := -1.0
	for dy in range(-7, 8):
		for dx in range(-7, 8):
			var bx := cell.x + dx
			var by := cell.y + dy
			if bx < 0 or by < 0 or bx >= GX or by >= GY:
				continue
			var bi := by * GX + bx
			if cells[bi] > 0.03:
				continue
			if not _touches_mass(bx, by):
				continue
			var dl := Vector2(float(dx), float(dy)).length()
			var dirn := Vector2(float(dx), -float(dy)) / maxf(dl, 0.001)
			var sc := (0.30 + maxf(0.0, dirn.dot(od))) / (1.0 + dl * 0.75)
			if sc > best_score:
				best_score = sc
				best = bi

	if best >= 0:
		cells[best] += total * 0.70
		total *= 0.30

	# 3) 剩下的就近撑厚（体积守恒，料子显得"流动"）
	var idxs: Array[int] = []
	var ws: Array[float] = []
	var wsum := 0.0
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var nx2 := cell.x + dx
			var ny2 := cell.y + dy
			if nx2 < 0 or ny2 < 0 or nx2 >= GX or ny2 >= GY:
				continue
			var dl2 := Vector2(float(dx), float(dy)).length()
			if dl2 < 0.5 or dl2 > 3.3:
				continue
			var w := (1.0 + 1.4 * maxf(0.0, (Vector2(float(dx), -float(dy)) / dl2).dot(od))) / (dl2 * dl2)
			idxs.append(ny2 * GX + nx2)
			ws.append(w)
			wsum += w
	if wsum > 0.0:
		for k in idxs.size():
			cells[idxs[k]] += total * ws[k] / wsum
	heat = maxf(0.0, heat - 0.022)
	strikes += 1
	_spawn_sparks(_cursor, 7, true)
	SoundKit.play("clink", _rng.randf_range(0.90, 1.12), -10.0)
	if strikes % 4 == 0:
		iou = _compute_iou()
	_update_tex()


## 挤压用：找离锤点最近、且"靠着自由面"的实体格子（也就是边缘）
func _find_boundary(cell: Vector2i, od: Vector2) -> int:
	var best := -1
	var best_score := -1.0
	for dy in range(-7, 8):
		for dx in range(-7, 8):
			var nx := cell.x + dx
			var ny := cell.y + dy
			if nx < 0 or ny < 0 or nx >= GX or ny >= GY:
				continue
			var i := ny * GX + nx
			if cells[i] <= VIS_T:
				continue
			var is_edge := false
			if nx > 0 and cells[i - 1] < 0.03:
				is_edge = true
			if not is_edge and nx < GX - 1 and cells[i + 1] < 0.03:
				is_edge = true
			if not is_edge and ny > 0 and cells[i - GX] < 0.03:
				is_edge = true
			if not is_edge and ny < GY - 1 and cells[i + GX] < 0.03:
				is_edge = true
			if not is_edge:
				continue
			var dl := Vector2(float(dx), float(dy)).length()
			var dirn := Vector2(float(dx), -float(dy)) / maxf(dl, 0.001)
			var sc := (0.30 + maxf(0.0, dirn.dot(od))) / (1.0 + dl * 0.75)
			if sc > best_score:
				best_score = sc
				best = i
	return best


func _touches_mass(x: int, y: int) -> bool:
	var i := y * GX + x
	if x > 0 and cells[i - 1] > 0.05:
		return true
	if x < GX - 1 and cells[i + 1] > 0.05:
		return true
	if y > 0 and cells[i - GX] > 0.05:
		return true
	if y < GY - 1 and cells[i + GX] > 0.05:
		return true
	return false


func _compute_iou() -> float:
	var inter := 0
	var uni := 0
	for i in GX * GY:
		var sh := cells[i] > VIS_T
		var tg := target[i] == 1
		if sh and tg:
			inter += 1
		if sh or tg:
			uni += 1
	return float(inter) / float(maxi(uni, 1))


func _update_tex() -> void:
	var warm := clampf((heat - 0.15) / 0.85, 0.0, 1.0)
	for j in GY:
		for i in GX:
			var idx := j * GX + i
			var t := cells[idx]
			var c := Color(0, 0, 0, 0)
			if t > 0.004:
				var k := clampf(t * 1.25, 0.0, 1.0)
				# 热态：暗红 → 亮橙；冷态：深灰 → 亮钢
				var hotc := Color(0.10 + 0.92 * k, 0.02 + 0.34 * k * k, 0.01 + 0.05 * k, 1.0)
				var coldc := Color(0.26 + 0.50 * k, 0.27 + 0.50 * k, 0.30 + 0.48 * k, 1.0)
				c = coldc.lerp(hotc, warm)
				c.a = 1.0
			_img.set_pixel(i, j, c)
	_tex.update(_img)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.11, 0.10, 0.60))
	draw_rect(_paper.grow(6), Color(0, 0, 0, 0.14))
	draw_rect(_paper, Color("2a2622"))
	draw_rect(_paper, Color("c9bda0"), false, 2.0)

	# 图纸轮廓
	if target_poly.size() > 2:
		var pts := PackedVector2Array()
		for p in target_poly:
			pts.append(_w2s(p))
		pts.append(pts[0])
		for i in pts.size() - 1:
			draw_line(pts[i], pts[i + 1], Color(0.55, 0.95, 1.0, 0.85), 3.0)

	# 锤击光圈（蓝色 = 挤压模式）
	var f := UIKit.ensure_font()
	if _paper.has_point(_cursor):
		var r := (HAMMER_R / float(GY)) * _paper.size.y + 6.0
		var ring := Color(1.0, 0.85, 0.4, 0.55)
		if _hold == 2:
			ring = Color(0.55, 0.92, 1.0, 0.8)
		draw_arc(_cursor, r, 0.0, TAU, 28, ring, 2.0)
		if _flash > 0.0:
			draw_circle(_cursor, r * _flash * 0.8, Color(1, 0.9, 0.6, 0.35 * _flash))

	# 火星
	for s in _sparks:
		var p: Vector2 = s["p"]
		var life := float(s["life"])
		var k := clampf(life / float(s["max"]), 0.0, 1.0)
		var col := Color(1.0, 0.85 + 0.15 * k, 0.45 * k, k)
		if not bool(s["hot"]):
			col = Color(0.7, 0.7, 0.72, k * 0.8)
		var v: Vector2 = s["v"]
		draw_line(p, p - v * 0.012, col, 2.0)
		draw_circle(p, 1.8, col)

	# 温度条
	var tpos := _paper.position + Vector2(0, _paper.size.y + 16)
	draw_rect(Rect2(tpos, Vector2(_paper.size.x, 12)), Color(0.2, 0.18, 0.16))
	var warm := clampf((heat - 0.0) / 1.0, 0.0, 1.0)
	draw_rect(Rect2(tpos, Vector2(_paper.size.x * warm, 12)),
		Color(1.0, 0.35, 0.1).lerp(Color(1.0, 0.85, 0.4), warm))
	draw_string(f, tpos + Vector2(0, 34),
		"料温 %d%%　%s　｜　锤击 %d 次　｜　回炉 %d 次　｜　贴合度 %d%%" % [
			int(heat * 100.0),
			"（太冷！按 R 回炉）" if heat < 0.24 else "（可锻）",
			strikes, reheats, int(iou * 100.0)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
		Palette.UI_ACCENT if heat < 0.24 else Palette.UI_TEXT)
	if bad > 0:
		draw_string(f, tpos + Vector2(0, 56), "冷砸 %d 次 → 内部裂纹" % bad,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Palette.UI_ACCENT)


func _on_accept() -> void:
	iou = _compute_iou()
	var fid := 0.55 + 0.45 * iou
	fid -= float(reheats) * 0.012
	fid -= float(bad) * 0.010
	accepted.emit(clampf(fid, 0.45, 1.0), get_forged_outline())


## 从厚度场里提出真正锤出来的轮廓（世界坐标，和设计图同一套归一化空间）
func get_forged_outline() -> PackedVector2Array:
	var img := Image.create_empty(GX, GY, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	for j in GY:
		for i in GX:
			if cells[j * GX + i] > VIS_T:
				img.set_pixel(i, j, Color(1, 1, 1, 1))
	var bm := BitMap.new()
	bm.create_from_image_alpha(img, 0.5)
	var polys := bm.opaque_to_polygons(Rect2(Vector2.ZERO, Vector2(GX, GY)), 1.0)
	if polys.is_empty():
		return PackedVector2Array()
	var best: PackedVector2Array = polys[0]
	var best_a := 0.0
	for p in polys:
		var a := absf(_shoelace(p))
		if a > best_a:
			best_a = a
			best = p
	if best.size() < 4:
		return PackedVector2Array()
	# 网格坐标 → 世界坐标，并平滑掉格子锯齿
	var out := PackedVector2Array()
	for p in best:
		out.append(Vector2(p.x / float(GX), 1.0 - p.y / float(GY)))
	out = _chaikin(out, 2)
	var res := PackedVector2Array()
	for p in out:
		res.append(bb.position + p * bb.size)
	return res


static func _shoelace(p: PackedVector2Array) -> float:
	var s := 0.0
	var n := p.size()
	for i in n:
		s += p[i].x * p[(i + 1) % n].y - p[(i + 1) % n].x * p[i].y
	return s * 0.5


static func _chaikin(poly: PackedVector2Array, iters: int) -> PackedVector2Array:
	var cur := poly
	for k in iters:
		var out := PackedVector2Array()
		var n := cur.size()
		for i in n:
			var a := cur[i]
			var b := cur[(i + 1) % n]
			out.append(a.lerp(b, 0.25))
			out.append(a.lerp(b, 0.75))
		cur = out
	return cur
