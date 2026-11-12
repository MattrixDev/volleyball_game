extends Node
## Laeuft auch bei pausiertem Spiel und treibt dann die Kamera und die Lautstaerken von main.gd
## weiter. So sieht man im Einstellungsmenue sofort, was ein Kamerawert bewirkt.

var target


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if get_tree().paused and is_instance_valid(target):
		target._process(delta)
