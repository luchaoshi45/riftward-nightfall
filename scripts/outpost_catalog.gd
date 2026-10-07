class_name OutpostCatalog
extends RefCounted
## The shared playable building and troop definitions used by costs and technology.
const BUILDING_IDS := ["tower", "barracks", "workshop", "recycler", "laboratory", "depot", "infirmary", "armory", "command_relay", "signal_beacon"]
const TROOP_IDS := ["shield", "ranged", "engineer", "ballista", "hauler", "medic", "artillery", "hunter", "flamer"]
const BUILDINGS := {
	"tower": {"title": "防御塔", "cost": 60, "size": Vector2i(3, 3), "hp": 280.0, "requires": []},
	"barracks": {"title": "兵营", "cost": 60, "size": Vector2i(4, 3), "hp": 600.0, "requires": []},
	"workshop": {"title": "工坊", "cost": 60, "size": Vector2i(3, 2), "hp": 450.0, "requires": []},
	"recycler": {"title": "回收站", "cost": 90, "size": Vector2i(3, 3), "hp": 500.0, "requires": ["workshop"]},
	"laboratory": {"title": "研究所", "cost": 120, "size": Vector2i(4, 3), "hp": 550.0, "requires": ["barracks", "workshop"]},
	"depot": {"title": "中转站", "cost": 100, "size": Vector2i(3, 3), "hp": 500.0, "requires": ["workshop"]},
	"infirmary": {"title": "救护站", "cost": 100, "size": Vector2i(3, 3), "hp": 480.0, "requires": ["barracks"]},
	"armory": {"title": "军械厂", "cost": 140, "size": Vector2i(4, 3), "hp": 600.0, "requires": ["laboratory", "workshop"]},
	"command_relay": {"title": "指挥中继站", "cost": 130, "size": Vector2i(3, 2), "hp": 520.0, "requires": ["armory"]},
	"signal_beacon": {"title": "曙光信标", "cost": 110, "size": Vector2i(3, 2), "hp": 520.0, "requires": ["workshop"]},
}
const TROOPS := {
	"shield": {"title": "盾卫", "cost": 70, "time": 6.0, "hp": 200.0, "requires": []},
	"ranged": {"title": "弩手", "cost": 80, "time": 8.0, "hp": 110.0, "requires": []},
	"engineer": {"title": "工程员", "cost": 65, "time": 7.0, "hp": 90.0, "requires": []},
	"ballista": {"title": "重弩组", "cost": 110, "time": 10.0, "hp": 150.0, "requires": ["laboratory"]},
	"hauler": {"title": "采运工队", "cost": 70, "time": 8.0, "hp": 120.0, "requires": ["depot"]},
	"medic": {"title": "医护队", "cost": 90, "time": 9.0, "hp": 100.0, "requires": ["infirmary"]},
	"artillery": {"title": "迫击炮队", "cost": 150, "time": 12.0, "hp": 130.0, "requires": ["armory"]},
	"hunter": {"title": "猎手", "cost": 110, "time": 10.0, "hp": 125.0, "requires": ["workshop"]},
	"flamer": {"title": "喷火队", "cost": 125, "time": 11.0, "hp": 150.0, "requires": ["armory"]},
}

static func building(kind: String) -> Dictionary:
	return (BUILDINGS.get(kind, {}) as Dictionary).duplicate(true)

static func troop(kind: String) -> Dictionary:
	return (TROOPS.get(kind, {}) as Dictionary).duplicate(true)
