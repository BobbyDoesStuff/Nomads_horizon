extends Resource
class_name ItemBase
## Base resource definition for every item in the game.

@export var id:         String
@export var item_name:  String          # "name" shadows Resource.name
@export var item_type:  int             # ItemType enum value
@export var stack_size: int   = 64
@export var base_value: int   = 1
@export var icon:       Texture2D
@export var description: String = ""
