extends Resource
class_name CharacterClass
## Definition of a playable character class.

@export var class_id:      String
@export var class_name:    String
@export var description:   String = ""
@export_multiline
@export var starting_items: Array[String] = []   # item ids
@export var bonuses:       Dictionary = {}        # stat → value
