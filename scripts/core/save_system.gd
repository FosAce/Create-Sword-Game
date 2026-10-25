class_name SaveSystem
extends RefCounted
## 存档：把一把刀存成 user://swords/<id>.json + 三张 PNG（雕刻/覆土/缩略图）

const DIR := "user://swords"


static func ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		DirAccess.make_dir_recursive_absolute(DIR)


static func new_id() -> String:
	var t := Time.get_datetime_string_from_system(false, true)
	t = t.replace(":", "-").replace("T", "_").replace(" ", "_")
	return "sword_%s_%d" % [t, Time.get_ticks_usec()]


## 返回存下来的 id（失败返回空串）
static func save_sword(s: SwordData, thumb: Image = null) -> String:
	ensure_dir()
	var id := new_id()
	var d := s.to_dict()
	d["id"] = id
	var f := FileAccess.open("%s/%s.json" % [DIR, id], FileAccess.WRITE)
	if f == null:
		push_warning("存档失败：无法写入 %s" % DIR)
		return ""
	f.store_string(JSON.stringify(d, "\t"))
	f.close()
	if s.face_mask != null:
		s.face_mask.save_png("%s/%s_face.png" % [DIR, id])
	if s.carve_mask != null:
		s.carve_mask.save_png("%s/%s_carve.png" % [DIR, id])
	if s.clay_mask != null:
		s.clay_mask.save_png("%s/%s_clay.png" % [DIR, id])
	if thumb != null:
		thumb.save_png("%s/%s_thumb.png" % [DIR, id])
	return id


## 列出所有存档（新的在前）：[{id, data:Dictionary, thumb_path, ...}]
static func list_saves() -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(DIR):
		return out
	var da := DirAccess.open(DIR)
	if da == null:
		return out
	var names := da.get_files()
	names.sort()
	names.reverse()
	for n in names:
		if not n.ends_with(".json"):
			continue
		var id := n.get_basename()
		var f := FileAccess.open("%s/%s" % [DIR, n], FileAccess.READ)
		if f == null:
			continue
		var txt := f.get_as_text()
		f.close()
		var d: Variant = JSON.parse_string(txt)
		if typeof(d) != TYPE_DICTIONARY:
			continue
		out.append({
			"id": id,
			"data": d,
			"thumb": "%s/%s_thumb.png" % [DIR, id],
			"has_carve": FileAccess.file_exists("%s/%s_carve.png" % [DIR, id]),
			"has_clay": FileAccess.file_exists("%s/%s_clay.png" % [DIR, id])
		})
	return out


static func load_sword(id: String) -> SwordData:
	var f := FileAccess.open("%s/%s.json" % [DIR, id], FileAccess.READ)
	if f == null:
		return null
	var txt := f.get_as_text()
	f.close()
	var d: Variant = JSON.parse_string(txt)
	if typeof(d) != TYPE_DICTIONARY:
		return null
	var s := SwordData.from_dict(d)
	if FileAccess.file_exists("%s/%s_carve.png" % [DIR, id]):
		var img := Image.load_from_file("%s/%s_carve.png" % [DIR, id])
		if img != null:
			s.carve_mask = img
	if FileAccess.file_exists("%s/%s_face.png" % [DIR, id]):
		var img3 := Image.load_from_file("%s/%s_face.png" % [DIR, id])
		if img3 != null:
			s.face_mask = img3
	if FileAccess.file_exists("%s/%s_clay.png" % [DIR, id]):
		var img2 := Image.load_from_file("%s/%s_clay.png" % [DIR, id])
		if img2 != null:
			s.clay_mask = img2
	return s


static func load_thumb(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)


static func delete_sword(id: String) -> void:
	for suffix in [".json", "_carve.png", "_clay.png", "_thumb.png"]:
		var p := "%s/%s%s" % [DIR, id, suffix]
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
