extends Resource
class_name GoodType
## Definition of a trade good for the economy system.

enum Category { RAW, CRAFTED, LUXURY, CONTRABAND }

@export var good_id:   String
@export var good_name: String
@export var base_price: int    = 1
@export var category:   int    = Category.RAW
@export var weight:     float  = 1.0
