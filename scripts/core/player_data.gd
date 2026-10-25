class_name PlayerData
extends RefCounted
## 铁匠的家底：金币 + 钢材库存。存在 user://profile.json

const PROFILE := "user://profile.json"
const START_MONEY := 180

static var money: int = -1            # -1 = 还没加载
static var stock: Dictionary = {}     # steel_id -> 份数


static func ensure_loaded() -> void:
	if money >= 0:
		return
	money = START_MONEY
	stock = {"c1084": 3, "n15n20": 3, "c1095": 1, "iron": 2}
	if FileAccess.file_exists(PROFILE):
		var f := FileAccess.open(PROFILE, FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(d) == TYPE_DICTIONARY:
				money = int(d.get("money", START_MONEY))
				var st: Variant = d.get("stock", {})
				var out: Dictionary = {}
				if typeof(st) == TYPE_DICTIONARY:
					for k in st:
						out[str(k)] = int(st[k])
				if not out.is_empty():
					stock = out
	save()


static func save() -> void:
	var f := FileAccess.open(PROFILE, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"money": money, "stock": stock}, "\t"))
	f.close()


static func count(id: String) -> int:
	ensure_loaded()
	return int(stock.get(id, 0))


static func add_steel(id: String, n: int = 1) -> void:
	ensure_loaded()
	stock[id] = count(id) + n
	save()


static func consume(id: String, n: int = 1) -> bool:
	ensure_loaded()
	if count(id) < n:
		return false
	stock[id] = count(id) - n
	save()
	return true


static func can_forge(core: String, alt: String) -> bool:
	ensure_loaded()
	if core == alt:
		return count(core) >= 1
	return count(core) >= 1 and count(alt) >= 1


static func owned_ids() -> Array:
	ensure_loaded()
	var out: Array = []
	for st in SteelDB.STEELS:
		if count(str(st["id"])) > 0:
			out.append(str(st["id"]))
	return out


static func spend(v: int) -> bool:
	ensure_loaded()
	if money < v:
		return false
	money -= v
	save()
	return true


static func add_money(v: int) -> void:
	ensure_loaded()
	money += v
	save()


## 一份钢坯的价格
static func price_of(id: String) -> int:
	return int(SteelDB.get_steel(id)["price"]) * 10


## 一把刀的卖价：评分 + 刃文 + 层数
static func sell_price(d: Dictionary) -> int:
	var score := float(d.get("final_score", 0.0))
	var hamon := float(d.get("hamon", 0.0))
	var layers := int(d.get("stack_layers", 9)) * int(pow(2, int(d.get("folds", 4))))
	var p := int(score * 1.6) + 15
	p += int(hamon * 25.0)
	p += int(layers / 40) * 5
	if bool(d.get("cracked", false)):
		p = int(p * 0.45)
	return maxi(p, 8)


## 兜底：身无分文又没料时，市场给你一份零活
static func emergency_grant() -> void:
	ensure_loaded()
	add_steel("c1084", 1)
	add_steel("n15n20", 1)
