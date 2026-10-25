class_name FriendsPanel
extends Control
## 好友：看对方的展示框、把自己的刀送给他，他会回赠一把。

signal closed()
signal inspect_requested(entries: Array)

var _db: Dictionary
var _cur := ""
var _friends_col: VBoxContainer
var _rack: GridContainer
var _head: Label
var _toast: Label
var _picker: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0.10, 0.09, 0.08, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := UIKit.panel(Color("f7f1e0"), 18)
	card.custom_minimum_size = Vector2(1220, 790)
	center.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	var t := UIKit.title("好 友 · 展 示 框", 24)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := UIKit.button("离开")
	close.custom_minimum_size = Vector2(96, 40)
	close.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	head.add_child(close)

	_toast = UIKit.label("选一位好友，看看他的展示框。", 15, Palette.UI_ACCENT2)
	col.add_child(_toast)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)

	# 左：好友列表
	var left := PanelContainer.new()
	left.add_theme_stylebox_override("panel", UIKit.sb(Color("efe8d6"), 12, 1, Color(0, 0, 0, 0.06)))
	left.custom_minimum_size = Vector2(300, 0)
	body.add_child(left)
	_friends_col = VBoxContainer.new()
	_friends_col.add_theme_constant_override("separation", 8)
	left.add_child(_friends_col)

	# 右：展示框
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	_head = UIKit.label("", 17, Palette.UI_TEXT)
	right.add_child(_head)
	_rack = GridContainer.new()
	_rack.columns = 3
	_rack.add_theme_constant_override("h_separation", 10)
	_rack.add_theme_constant_override("v_separation", 10)
	right.add_child(_rack)

	var gift := UIKit.button("送一把我做的刀给他 ▶", true)
	gift.custom_minimum_size = Vector2(0, 46)
	gift.pressed.connect(_open_picker)
	right.add_child(gift)


func open() -> void:
	visible = true
	_db = FriendDB.load_db()
	var fr := FriendDB.friends()
	if not fr.is_empty():
		_cur = str(fr[0].get("id", ""))
	_rebuild()


func _rebuild() -> void:
	for c in _friends_col.get_children():
		_friends_col.remove_child(c)
		c.queue_free()
	for f in _db.get("friends", []):
		var b := UIKit.button("%s\n%s　♥ %d" % [
			str(f.get("name", "?")), str(f.get("title", "")), int(f.get("likes", 0))], false)
		b.custom_minimum_size = Vector2(0, 62)
		b.pressed.connect(func() -> void:
			_cur = str(f.get("id", ""))
			_rebuild())
		_friends_col.add_child(b)

	_db = FriendDB.load_db()
	var fr := FriendDB.find(_db, _cur)
	for c in _rack.get_children():
		_rack.remove_child(c)
		c.queue_free()
	if fr.is_empty():
		_head.text = ""
		return
	var rack: Array = fr.get("rack", [])
	_head.text = "%s 的展示框（%d 把）　♥ %d" % [str(fr.get("name", "")), rack.size(),
		int(fr.get("likes", 0))]
	if rack.is_empty():
		_rack.add_child(UIKit.label("他的架子还空着。", 15, Palette.UI_DIM))
		return
	for i in rack.size():
		_rack.add_child(_card(rack[i], i))


func _card(d: Dictionary, idx: int) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIKit.sb(Color("fbf6e6"), 12, 1, Color(0, 0, 0, 0.07)))
	p.custom_minimum_size = Vector2(280, 168)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	var nm := str(d.get("sword_name", "无名刀"))
	var sc := float(d.get("final_score", 0.0))
	v.add_child(UIKit.label("%s　%d 分" % [nm, int(sc)], 17, Palette.UI_TEXT))
	v.add_child(UIKit.label("%d 层　｜　%.1f HRC　｜　刃文 %.0f%%" % [
		int(d.get("stack_layers", 9)) * int(pow(2, int(d.get("folds", 4)))),
		float(d.get("hardness", 0.0)), float(d.get("hamon", 0.0)) * 100.0],
		13, Palette.UI_DIM))
	var b := UIKit.button("细看这把刀")
	b.custom_minimum_size = Vector2(0, 34)
	var dd := d.duplicate(true)
	b.pressed.connect(func() -> void:
		inspect_requested.emit([{"name": str(dd.get("sword_name", "")), "data": dd}]))
	v.add_child(b)
	return p


func _open_picker() -> void:
	if _picker != null and is_instance_valid(_picker):
		_picker.queue_free()
	var saves := SaveSystem.list_saves()
	_picker = Control.new()
	_picker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_picker)
	_picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var d := ColorRect.new()
	d.color = Color(0.10, 0.09, 0.08, 0.55)
	_picker.add_child(d)
	d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cen := CenterContainer.new()
	_picker.add_child(cen)
	cen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := UIKit.panel(Color("f7f1e0"), 16)
	card.custom_minimum_size = Vector2(760, 560)
	cen.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)
	v.add_child(UIKit.title("选一把送给 %s" % str(FriendDB.find(_db, _cur).get("name", "")), 20))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(720, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	if saves.is_empty():
		list.add_child(UIKit.label("你还没有成品可送。", 15, Palette.UI_DIM, true))
	for e in saves:
		var dd: Dictionary = e["data"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		list.add_child(row)
		var lb := UIKit.label("%s　%d 分" % [str(dd.get("sword_name", "无名刀")),
			int(float(dd.get("final_score", 0.0)))], 16, Palette.UI_TEXT)
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lb)
		var btn := UIKit.button("送出")
		btn.custom_minimum_size = Vector2(90, 34)
		var sid := str(e["id"])
		var data := dd.duplicate(true)
		btn.pressed.connect(func() -> void:
			_do_gift(sid, data))
		row.add_child(btn)
	var cancel := UIKit.button("取消")
	cancel.pressed.connect(func() -> void:
		if _picker != null:
			_picker.queue_free()
			_picker = null)
	v.add_child(cancel)


func _do_gift(save_id: String, data: Dictionary) -> void:
	var db := FriendDB.load_db()
	var back := FriendDB.gift(db, _cur, data)
	SaveSystem.delete_sword(save_id)
	var who := str(FriendDB.find(db, _cur).get("name", "好友"))
	var msg := "把「%s」送给了 %s。" % [str(data.get("sword_name", "刀")), who]
	if not back.is_empty():
		var s := SwordData.from_dict(back)
		SaveSystem.save_sword(s)
		msg += "　他回赠了「%s」（%d 分）。" % [s.sword_name, int(s.final_score)]
	SoundKit.play("chime", 1.15, -10.0)
	if _picker != null:
		_picker.queue_free()
		_picker = null
	_toast.text = msg
	_db = FriendDB.load_db()
	_rebuild()
