class_name FriendDB
extends RefCounted
## 好友系统（本地）：每位好友有自己的展示框和好感度。
## 送刀给好友 → 好友好感 +1，并回赠一把他做的刀。

const PATH := "user://friends.json"
const RACK_MAX := 6

const SEED_FRIENDS := [
	{"id": "f_lin", "name": "林 砚", "title": "山里来的刀匠"},
	{"id": "f_ling", "name": "阿 绫", "title": "只买不做的收藏家"},
	{"id": "f_bai", "name": "白 鹭", "title": "游历中的浪人"},
]

const NAME_A := ["月", "霜", "松", "岚", "雪", "潮", "玄", "曦", "暮", "绯"]
const NAME_B := ["影", "切", "丸", "牙", "鸣", "灵", "彻", "鳞", "羽", "歌"]


static func load_db() -> Dictionary:
	if FileAccess.file_exists(PATH):
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f != null:
			var txt := f.get_as_text()
			f.close()
			var parsed: Variant = JSON.parse_string(txt)
			if parsed is Dictionary and (parsed as Dictionary).has("friends"):
				return parsed as Dictionary
	return _seed()


static func save_db(db: Dictionary) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(db, "\t"))
	f.close()


static func friends() -> Array:
	return load_db().get("friends", [])


static func find(db: Dictionary, id: String) -> Dictionary:
	for f in db.get("friends", []):
		if str(f.get("id", "")) == id:
			return f
	return {}


## 送一把刀给好友：进他的展示框、好感 +1，然后他回赠一把
static func gift(db: Dictionary, friend_id: String, sword: Dictionary) -> Dictionary:
	var fr := find(db, friend_id)
	if fr.is_empty():
		return {}
	var rack: Array = fr.get("rack", [])
	rack.append(sword)
	while rack.size() > RACK_MAX:
		rack.pop_front()
	fr["rack"] = rack
	fr["likes"] = int(fr.get("likes", 0)) + 1
	# 回礼：从他手里挑一把（优先挑早期收到的）
	var back: Dictionary = {}
	if rack.size() >= 2:
		back = rack[rack.size() - 2]
	var out := {}
	if not back.is_empty():
		out = back.duplicate(true)
	save_db(db)
	return out


## 直接生成一把"好友做的刀"（用来给初始展示框填充）
static func make_friend_sword(rng: RandomNumberGenerator) -> Dictionary:
	var s := SwordData.new()
	var presets := ContourTrace.preset_outlines()
	var p: Dictionary = presets[rng.randi() % presets.size()]
	s.outline = p["pts"]
	s.core_id = ["c1084", "c1095", "5160"][rng.randi() % 3]
	s.alt_id = "n15n20"
	s.stack_layers = rng.randi_range(7, 15)
	s.folds = rng.randi_range(3, 5)
	s.weld_quality = rng.randf_range(0.78, 1.0)
	s.pattern_style = rng.randi() % 8
	s.twist_turns = rng.randf_range(1.2, 3.4)
	s.thickness = rng.randf_range(0.012, 0.020)
	s.fidelity = rng.randf_range(0.80, 1.0)
	s.hardness = rng.randf_range(54.0, 62.5)
	s.toughness = rng.randf_range(0.36, 0.78)
	s.grind = rng.randf_range(0.65, 1.0)
	s.polish = rng.randf_range(0.55, 0.98)
	s.etch_minutes = rng.randf_range(3.6, 5.4)
	s.handle_preset = rng.randi() % HandleBuilder.PROFILES.size()
	s.handle_wood = rng.randi() % HandleBuilder.WOODS.size()
	s.guard_style = rng.randi_range(0, 3)
	s.guard_shape = rng.randi() % 5
	s.pommel_style = rng.randi_range(0, 2)
	s.sword_name = "%s%s" % [NAME_A[rng.randi() % NAME_A.size()],
		NAME_B[rng.randi() % NAME_B.size()]]
	s.final_score = rng.randf_range(58.0, 92.0)
	return s.to_dict()


static func _seed() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 778899
	var arr: Array = []
	for i in SEED_FRIENDS.size():
		var f: Dictionary = SEED_FRIENDS[i].duplicate(true)
		var rack: Array = []
		for k in rng.randi_range(2, 3):
			rack.append(make_friend_sword(rng))
		f["rack"] = rack
		f["likes"] = rng.randi_range(0, 4)
		arr.append(f)
	var db := {"friends": arr}
	save_db(db)
	return db
