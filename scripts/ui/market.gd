class_name Market
extends Control
## 码头市场：卖刀换钱 / 花钱买钢坯

signal closed()

var _money_label: Label
var _sell_list: VBoxContainer
var _buy_list: VBoxContainer
var _stock_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0.12, 0.11, 0.10, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var card := UIKit.panel(Color("f7f1e0"), 18)
	card.custom_minimum_size = Vector2(1240, 790)
	center.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	var t := UIKit.title("码 头 市 场", 26)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_money_label = UIKit.label("金币 0", 22, Palette.UI_ACCENT)
	head.add_child(_money_label)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(14, 0)
	head.add_child(sp)
	var close_btn := UIKit.button("离开码头")
	close_btn.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	head.add_child(close_btn)

	_stock_label = UIKit.label("", 14, Palette.UI_DIM, true)
	col.add_child(_stock_label)

	var hs := HBoxContainer.new()
	hs.add_theme_constant_override("separation", 14)
	hs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(hs)

	# 左：卖刀
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.custom_minimum_size = Vector2(660, 0)
	hs.add_child(left)
	left.add_child(UIKit.label("卖 刀　（卖掉后从收藏里移除）", 17, Palette.UI_TEXT))
	var ls := ScrollContainer.new()
	ls.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ls.custom_minimum_size = Vector2(650, 560)
	ls.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(ls)
	_sell_list = VBoxContainer.new()
	_sell_list.add_theme_constant_override("separation", 8)
	_sell_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ls.add_child(_sell_list)

	# 右：买料
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.custom_minimum_size = Vector2(520, 0)
	hs.add_child(right)
	right.add_child(UIKit.label("买 钢 坯　（每把刀消耗主钢 1 份 + 夹层钢 1 份）", 17, Palette.UI_TEXT))
	var rs := ScrollContainer.new()
	rs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rs.custom_minimum_size = Vector2(510, 560)
	rs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(rs)
	_buy_list = VBoxContainer.new()
	_buy_list.add_theme_constant_override("separation", 8)
	_buy_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rs.add_child(_buy_list)


func open() -> void:
	visible = true
	PlayerData.ensure_loaded()
	_refresh()


func _refresh() -> void:
	_money_label.text = "金币 %d" % PlayerData.money
	var parts: Array = []
	for id in PlayerData.owned_ids():
		var st := SteelDB.get_steel(id)
		parts.append("%s×%d" % [st["short"], PlayerData.count(id)])
	_stock_label.text = "手上的料：" + ("　".join(parts) if not parts.is_empty() else "（空了）")

	for c in _sell_list.get_children():
		_sell_list.remove_child(c)
		c.queue_free()
	for c in _buy_list.get_children():
		_buy_list.remove_child(c)
		c.queue_free()

	var saves := SaveSystem.list_saves()
	if saves.is_empty():
		_sell_list.add_child(UIKit.label("还没有可以卖的刀。先去打铁铺锻一把。", 15, Palette.UI_DIM, true))
	else:
		var n := 0
		for e in saves:
			if n >= 20:
				break
			n += 1
			_sell_list.add_child(_sell_row(e))

	for st in SteelDB.STEELS:
		_buy_list.add_child(_buy_row(st))

	# 兜底零活
	if PlayerData.money < 20 and PlayerData.owned_ids().size() <= 1:
		var help := UIKit.button("接一份零活（免费领 1084 + 15N20 各一份）", true)
		help.pressed.connect(func() -> void:
			PlayerData.emergency_grant()
			_refresh())
		_buy_list.add_child(help)


func _sell_row(e: Dictionary) -> Control:
	var d: Dictionary = e["data"]
	var price := PlayerData.sell_price(d)
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UIKit.sb(Color("efe8d6"), 12, 1, Color(0, 0, 0, 0.06)))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	row.add_child(hb)

	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(128, 96)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var tx := SaveSystem.load_thumb(str(e["thumb"]))
	if tx != null:
		thumb.texture = tx
	hb.add_child(thumb)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 2)
	hb.add_child(vb)
	vb.add_child(UIKit.label("%s　%d 分%s" % [
		str(d.get("sword_name", "无名刀")), int(float(d.get("final_score", 0.0))),
		"　（已断裂）" if bool(d.get("cracked", false)) else ""], 17, Palette.UI_TEXT))
	var layers := int(d.get("stack_layers", 9)) * int(pow(2, int(d.get("folds", 4))))
	vb.add_child(UIKit.label("%d 层　｜　刃文 %d%%　｜　硬度 %.1f HRC" % [
		layers, int(float(d.get("hamon", 0.0)) * 100.0),
		float(d.get("hardness", 0.0))], 14, Palette.UI_DIM))

	var pl := UIKit.label("%d 金" % price, 20, Palette.UI_ACCENT2)
	pl.custom_minimum_size = Vector2(90, 0)
	hb.add_child(pl)

	var btn := UIKit.button("出售", true)
	btn.custom_minimum_size = Vector2(100, 40)
	var id := str(e["id"])
	btn.pressed.connect(func() -> void:
		PlayerData.add_money(PlayerData.sell_price(d))
		SaveSystem.delete_sword(id)
		SoundKit.play("chime", 1.1, -10.0)
		_refresh())
	hb.add_child(btn)
	return row


func _buy_row(st: Dictionary) -> Control:
	var id := str(st["id"])
	var price := PlayerData.price_of(id)
	var owned := PlayerData.count(id)
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UIKit.sb(Color("efe8d6"), 12, 1, Color(0, 0, 0, 0.06)))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	row.add_child(hb)

	var sw := ColorRect.new()
	sw.color = st["color"]
	sw.custom_minimum_size = Vector2(28, 56)
	hb.add_child(sw)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 2)
	hb.add_child(vb)
	vb.add_child(UIKit.label("%s　（持有 %d 份）" % [st["name"], owned], 16, Palette.UI_TEXT))
	vb.add_child(UIKit.label("碳 %.2f%%　%s" % [
		float(st["carbon"]) * 100.0,
		"亮层（抗酸洗）" if float(st["tone"]) > 0.7 else "暗层（易腐蚀）"], 13, Palette.UI_DIM))

	var pl := UIKit.label("%d 金" % price, 18, Palette.UI_ACCENT2)
	pl.custom_minimum_size = Vector2(80, 0)
	hb.add_child(pl)

	var btn := UIKit.button("买 1 份")
	btn.custom_minimum_size = Vector2(100, 38)
	btn.disabled = PlayerData.money < price
	btn.pressed.connect(func() -> void:
		if PlayerData.spend(PlayerData.price_of(id)):
			PlayerData.add_steel(id, 1)
			SoundKit.play("click", 1.0, -12.0)
		else:
			SoundKit.play("hammer", 0.75, -16.0)
		_refresh())
	hb.add_child(btn)
	return row
