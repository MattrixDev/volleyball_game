extends SceneTree
## Timing-Test mit echten Eingaben (Input.action_press) statt Testmodus: spielt als Mensch
## schnelle Zuspiele mit gehaltenem R2 und schlaegt danach genau im idealen Moment.
## Zaehlt die Bewertungen je Ballberuehrung (PERFEKT, Gut, Zu spaet ...).
##   godot --headless --fixed-fps 60 --disable-vsync -s res://tools/tempo_test.gd -- --play --quit-after=300


func _init() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var drv = load("res://tools/tempo_driver.gd").new()
	drv._main = main
	drv.process_physics_priority = -100  # vor dem Spiel, damit die Eingaben im selben Takt gelten
	root.add_child(drv)
