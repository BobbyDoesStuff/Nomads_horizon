extends Node
## Static game-data registry.
##
## Holds definitions for items, character classes, trade goods, and
## other constant data that both client and server need.  Loaded once at
## startup and never written to at runtime.

# ------------------------------------------------------------------ enums
enum ItemType  { WEAPON, TOOL, RESOURCE, CONSUMABLE, ARMOR, VEHICLE }
enum GoodCategory { RAW, CRAFTED, LUXURY, CONTRABAND }

# ------------------------------------------------------------------ type defs
class ItemDef:
	var id:         String
	var name:       String
	var item_type:  ItemType
	var stack_size: int
	var base_value: int

	func _init(p_id: String, p_name: String, p_type: ItemType, p_stack: int, p_value: int) -> void:
		id = p_id; name = p_name; item_type = p_type; stack_size = p_stack; base_value = p_value


class ClassDef:
	var id:             String
	var name:           String
	var description:    String
	var starting_items: Array[String]
	var bonuses:        Dictionary  # stat_name → bonus_value

	func _init(p_id: String, p_name: String, p_desc: String, p_items: Array[String], p_bonuses: Dictionary) -> void:
		id = p_id; name = p_name; description = p_desc; starting_items = p_items; bonuses = p_bonuses


class GoodDef:
	var id:          String
	var name:        String
	var base_price:  int
	var category:    GoodCategory
	var weight:      float

	func _init(p_id: String, p_name: String, p_price: int, p_cat: GoodCategory, p_weight: float) -> void:
		id = p_id; name = p_name; base_price = p_price; category = p_cat; weight = p_weight


# ------------------------------------------------------------------ registries
var ITEMS:  Dictionary = {}
var CLASSES: Dictionary = {}
var GOODS:  Dictionary = {}


# ------------------------------------------------------------------ lifecycle
func _ready() -> void:
	_register_items()
	_register_classes()
	_register_goods()
	print("[DataManager] Loaded %d items, %d classes, %d goods" % [ITEMS.size(), CLASSES.size(), GOODS.size()])


# ------------------------------------------------------------------ lookups
func get_item(id: String) -> ItemDef:
	return ITEMS.get(id, null)


func get_class_def(id: String) -> ClassDef:
	return CLASSES.get(id, null)


func get_good(id: String) -> GoodDef:
	return GOODS.get(id, null)


# ------------------------------------------------------------------ data tables
func _register_items() -> void:
	var item_list: Array[ItemDef] = [
		# Weapons
		ItemDef.new("rusty_sword",  "Rusty Sword",   ItemType.WEAPON,     1,  25),
		ItemDef.new("hunting_bow",  "Hunting Bow",   ItemType.WEAPON,     1,  50),
		ItemDef.new("flintlock",    "Flintlock",     ItemType.WEAPON,     1, 120),
		# Tools
		ItemDef.new("pickaxe",      "Pickaxe",        ItemType.TOOL,       1,  30),
		ItemDef.new("fishing_rod",  "Fishing Rod",    ItemType.TOOL,       1,  20),
		ItemDef.new("hammer",       "Hammer",         ItemType.TOOL,       1,  15),
		# Resources
		ItemDef.new("wood",         "Wood",           ItemType.RESOURCE,  64,   2),
		ItemDef.new("stone",        "Stone",          ItemType.RESOURCE,  64,   3),
		ItemDef.new("iron_ore",     "Iron Ore",       ItemType.RESOURCE,  32,   8),
		ItemDef.new("gold_ore",     "Gold Ore",       ItemType.RESOURCE,  16,  25),
		ItemDef.new("herbs",        "Herbs",          ItemType.RESOURCE,  32,   5),
		# Consumables
		ItemDef.new("bread",        "Bread",          ItemType.CONSUMABLE, 8,   4),
		ItemDef.new("health_potion","Health Potion",  ItemType.CONSUMABLE, 4,  20),
		ItemDef.new("bandage",      "Bandage",        ItemType.CONSUMABLE, 8,   8),
		# Armor
		ItemDef.new("leather_vest", "Leather Vest",   ItemType.ARMOR,      1,  40),
		ItemDef.new("iron_plate",   "Iron Plate",     ItemType.ARMOR,      1, 100),
		# Vehicles (stub)
		ItemDef.new("rowboat",      "Rowboat",        ItemType.VEHICLE,    1, 200),
		ItemDef.new("trade_sloop",  "Trade Sloop",    ItemType.VEHICLE,    1, 800),
	]
	for item in item_list:
		ITEMS[item.id] = item


func _register_classes() -> void:
	var class_list: Array[ClassDef] = [
		ClassDef.new("nomad",   "Nomad",   "A lone wanderer, fast on foot and resourceful.",
			["rusty_sword", "bread", "bandage"],
			{"speed": 1.2, "stamina": 100}),
		ClassDef.new("merchant","Merchant","A trader who profits from moving goods between cities.",
			["hammer", "bread", "bread"],
			{"barter": 1.3, "carry_weight": 150}),
		ClassDef.new("pirate",  "Pirate",  "Rules the seas — or takes what they want from those who do.",
			["flintlock", "rowboat", "bandage"],
			{"naval_speed": 1.3, "intimidation": 1.2}),
		ClassDef.new("builder", "Builder", "Constructs fortifications, clan halls, and trade posts.",
			["hammer", "pickaxe", "stone", "wood"],
			{"build_speed": 1.5, "carry_weight": 120}),
		ClassDef.new("scout",   "Scout",   "Fast, stealthy — maps the unknown and spots danger first.",
			["hunting_bow", "bandage", "herbs"],
			{"speed": 1.4, "vision_range": 1.5}),
	]
	for cls in class_list:
		CLASSES[cls.id] = cls


func _register_goods() -> void:
	var good_list: Array[GoodDef] = [
		GoodDef.new("grain",     "Grain",      5,  GoodCategory.RAW,        2.0),
		GoodDef.new("lumber",    "Lumber",      8,  GoodCategory.RAW,        4.0),
		GoodDef.new("iron",      "Iron",       20,  GoodCategory.RAW,        3.0),
		GoodDef.new("gold",      "Gold",       50,  GoodCategory.RAW,        1.0),
		GoodDef.new("spices",    "Spices",     35,  GoodCategory.LUXURY,     0.5),
		GoodDef.new("silk",      "Silk",       45,  GoodCategory.LUXURY,     0.3),
		GoodDef.new("tools",     "Tools",      25,  GoodCategory.CRAFTED,    2.0),
		GoodDef.new("weapons",   "Weapons",    40,  GoodCategory.CRAFTED,    3.0),
		GoodDef.new("rum",       "Rum",        30,  GoodCategory.CONTRABAND, 1.0),
		GoodDef.new("opium",     "Opium",      60,  GoodCategory.CONTRABAND, 0.2),
	]
	for g in good_list:
		GOODS[g.id] = g
