extends SceneTree
## Testet die Annahme-Aufstellung in allen sechs Rotationen (mit und ohne Libero).
## Aufruf: godot --headless --script tools/formation_test.gd


func _init() -> void:
	var base := ["S", "OH", "MB", "OP", "OH", "MB"]
	var bad := 0
	for k in 6:
		for lib in [false, true]:
			var roles := {}
			for slot in range(1, 7):
				roles[slot] = base[(slot - 1 + k) % 6]
			if lib:
				if roles[6] == "MB":
					roles[6] = "L"
				elif roles[5] == "MB":
					roles[5] = "L"
				else:
					continue
			var sp := Formation.receive_spots(roles)
			var v := Formation.violations(sp)
			bad += v.size()
			var line := "Rot %d%s Zuspieler auf %d |" % [k, " +Libero" if lib else "", roles.find_key("S")]
			for s in range(1, 7):
				line += " P%d %s (%.1f/%.1f)" % [s, roles[s], sp[s].x, sp[s].y]
			print(line, "  FEHLER " + str(v) if not v.is_empty() else "")
	print("Verletzungen gesamt: ", bad)
	quit()
