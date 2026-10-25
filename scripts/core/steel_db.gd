class_name SteelDB
extends RefCounted
## 钢材数据库（尽量贴近现实）
##  tone    : 三氯化铁(FeCl3)酸洗后的明暗。高碳层腐蚀快→暗，镍钢/低碳铁→亮。
##  carbon  : 含碳量，决定可达到的最高硬度。
##  harden  : 淬透性/可硬化性(0..1)，空气淬硬的钢这里没有，所以都要油或水。
##  tough   : 固有韧性
##  price   : 每份价格（海岛币）

const STEELS := [
	{
		"id": "c1095", "name": "1095 高碳钢", "short": "1095",
		"carbon": 0.95, "ni": 0.0, "cr": 0.0,
		"tone": 0.16, "harden": 1.0, "tough": 0.25, "price": 3,
		"color": Color("6b7076"),
		"note": "最经典的刀刃钢，能淬到 66HRC，酸洗后变深灰，是暗色层的担当。"
	},
	{
		"id": "c1084", "name": "1084 高碳钢", "short": "1084",
		"carbon": 0.84, "ni": 0.0, "cr": 0.0,
		"tone": 0.24, "harden": 0.95, "tough": 0.35, "price": 3,
		"color": Color("77818a"),
		"note": "和 15N20 是公认的黄金搭档，韧性比 1095 稍好，好锻。"
	},
	{
		"id": "n15n20", "name": "15N20 镍钢", "short": "15N20",
		"carbon": 0.75, "ni": 2.0, "cr": 0.0,
		"tone": 0.93, "harden": 0.85, "tough": 0.75, "price": 5,
		"color": Color("d9e2e6"),
		"note": "含 2% 镍，抗酸洗腐蚀，层间保持银白——反差全指望它。"
	},
	{
		"id": "iron", "name": "熟铁 / 软铁", "short": "熟铁",
		"carbon": 0.05, "ni": 0.0, "cr": 0.0,
		"tone": 0.86, "harden": 0.0, "tough": 1.0, "price": 1,
		"color": Color("b9bcc0"),
		"note": "几乎没有碳，淬不上火。便宜、好锻，能做出漂亮的亮层但会拉低硬度。"
	},
	{
		"id": "c5160", "name": "5160 弹簧钢", "short": "5160",
		"carbon": 0.60, "ni": 0.0, "cr": 0.80,
		"tone": 0.46, "harden": 0.8, "tough": 0.95, "price": 4,
		"color": Color("8e969a"),
		"note": "含铬，韧性极佳，耐冲击。做长刀/砍刀的安全牌，硬度略低。"
	},
	{
		"id": "c52100", "name": "52100 轴承钢", "short": "52100",
		"carbon": 1.00, "ni": 0.0, "cr": 1.45,
		"tone": 0.34, "harden": 0.9, "tough": 0.40, "price": 6,
		"color": Color("7d858b"),
		"note": "铬轴承钢，硬度刃口保持性极强，但难锻、易裂。"
	}
]

const OPTIMAL_AUS := {  # 推荐奥氏体化温度区间（℃，简化成单段）
	"c1095": Vector2(790, 830),
	"c1084": Vector2(790, 830),
	"n15n20": Vector2(800, 840),
	"iron": Vector2(900, 1000),
	"c5160": Vector2(830, 860),
	"c52100": Vector2(830, 860)
}

static func get_steel(id: String) -> Dictionary:
	for s in STEELS:
		if s["id"] == id:
			return s
	return STEELS[0]

static func index_of(id: String) -> int:
	for i in STEELS.size():
		if STEELS[i]["id"] == id:
			return i
	return 0

## 两种钢的腐蚀反差 0..1：碳差 + 镍差
static func pair_contrast(a_id: String, b_id: String) -> float:
	var a := get_steel(a_id)
	var b := get_steel(b_id)
	var dt := absf(float(a["tone"]) - float(b["tone"]))          # 明暗差
	var dn := absf(float(a["ni"]) - float(b["ni"])) / 2.0         # 镍含量差
	var dc := absf(float(a["carbon"]) - float(b["carbon"])) * 0.5 # 碳差
	return clampf(dt * 0.8 + dn * 0.45 + dc * 0.25, 0.05, 1.0)

## 一团料里的平均含碳量（按层数加权：主钢占厚度的 2/3）
static func mix_carbon(core_id: String, alt_id: String, core_ratio: float = 0.66) -> float:
	var c := get_steel(core_id)
	var a := get_steel(alt_id)
	return float(c["carbon"]) * core_ratio + float(a["carbon"]) * (1.0 - core_ratio)

## 混料后的韧性基准
static func mix_tough(core_id: String, alt_id: String, core_ratio: float = 0.66) -> float:
	var c := get_steel(core_id)
	var a := get_steel(alt_id)
	return float(c["tough"]) * core_ratio + float(a["tough"]) * (1.0 - core_ratio)

static func mix_harden(core_id: String, alt_id: String, core_ratio: float = 0.66) -> float:
	var c := get_steel(core_id)
	var a := get_steel(alt_id)
	return float(c["harden"]) * core_ratio + float(a["harden"]) * (1.0 - core_ratio)
