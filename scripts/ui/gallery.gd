class_name Gallery
extends Control
## 收藏馆：列出 user://swords 里存过的刀，可以重新挂到展示架上。

signal closed()
signal picked(id: String)

var _list: VBoxContainer
var _title: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0.12, 0.11, 0.10, 0.60)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var card := UIKit.panel(Color("f7f1e0"), 18)
	card.custom_minimum_size = Vector2(1020, 760)
	center.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	_title = UIKit.title("收 藏 馆", 26)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close_btn := UIKit.button("关闭")
	close_btn.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	head.add_child(close_btn)

	col.add_child(UIKit.label("离开铁匠铺后刀会挂到岛上；这里也可以随时取出来重新挂。", 14, Palette.UI_DIM, true))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(980, 640)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)


func open() -> void:
	visible = true
	_rebuild()


func _rebuild() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var saves := SaveSystem.list_saves()
	_title.text = "收 藏 馆　（%d 把）" % saves.size()
	if saves.is_empty():
		_list.add_child(UIKit.label("还没有成品。去铁匠铺锻一把吧。", 16, Palette.UI_DIM, true))
		return
	var n := 0
	for e in saves:
		if n >= 24:
			break
		n += 1
		_list.add_child(_make_row(e))


func _make_row(e: Dictionary) -> Control:
	var d: Dictionary = e["data"]
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", UIKit.sb(Color("efe8d6"), 12, 1, Color(0, 0, 0, 0.06)))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	row.add_child(hb)

	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(160, 120)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var t := SaveSystem.load_thumb(str(e["thumb"]))
	if t != null:
		thumb.texture = t
	hb.add_child(thumb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)

	var nm := str(d.get("sword_name", "无名刀"))
	var score := float(d.get("final_score", 0.0))
	var title := "废铁一块"
	if score >= 88.0:
		title = "传奇名刀"
	elif score >= 76.0:
		title = "大师之作"
	elif score >= 62.0:
		title = "匠人手笔"
	elif score >= 45.0:
		title = "学徒习作"
	vb.add_child(UIKit.label("%s　—　%d 分 · %s" % [nm, int(score), title], 18, Palette.UI_TEXT))

	var layers := int(d.get("stack_layers", 9))
	var folds := int(d.get("folds", 4))
	var core := SteelDB.get_steel(str(d.get("core_id", "c1084")))
	var alt := SteelDB.get_steel(str(d.get("alt_id", "n15n20")))
	var hamon := float(d.get("hamon", 0.0))
	var meta := "%s + %s　｜　%d 层　｜　%.1f HRC　｜　韧性 %.0f%%" % [
		core["short"], alt["short"], layers * int(pow(2, folds)),
		float(d.get("hardness", 0.0)), float(d.get("toughness", 0.0)) * 100.0
	]
	vb.add_child(UIKit.label(meta, 14, Palette.UI_DIM))
	if hamon > 0.05:
		vb.add_child(UIKit.label("刃文强度 %d%%　｜　雕刻覆盖 %d%%" % [
			int(hamon * 100.0), int(float(d.get("carve_cover", 0.0)) * 100.0)],
			14, Palette.UI_ACCENT2))
	else:
		vb.add_child(UIKit.label("雕刻覆盖 %d%%" % int(float(d.get("carve_cover", 0.0)) * 100.0),
			14, Palette.UI_DIM))

	var btn := UIKit.button("挂上展示架", true)
	btn.custom_minimum_size = Vector2(150, 40)
	var id := str(e["id"])
	btn.pressed.connect(func() -> void:
		SoundKit.play("click", 1.0, -12.0)
		picked.emit(id))
	hb.add_child(btn)

	var del := UIKit.button("删除")
	del.custom_minimum_size = Vector2(70, 40)
	del.pressed.connect(func() -> void:
		SaveSystem.delete_sword(id)
		_rebuild())
	hb.add_child(del)
	return row
