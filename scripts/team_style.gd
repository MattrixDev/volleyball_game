## Trikot und Name eines Teams. Neue Teams: eine .tres-Datei in res://teams/ anlegen
## (im Godot-Editor: Neue Ressource -> TeamStyle), Farben einstellen, fertig.
class_name TeamStyle
extends Resource

@export var id := "team"
@export var name := "Team"
@export var short_name := "TEA"
@export_group("Trikot")
@export var jersey := Color(0.15, 0.19, 0.32)
@export var panel := Color(0.9, 0.9, 0.88)    ## Seitenteile des Trikots
@export var collar := Color(0.9, 0.9, 0.88)
@export var logo := Color(0.9, 0.9, 0.88)
@export var number := Color(0.95, 0.95, 0.93)
@export_group("Hose und Schuhe")
@export var shorts := Color(0.15, 0.19, 0.32)
@export var socks := Color(0.9, 0.9, 0.88)
@export var shoes := Color(0.9, 0.9, 0.88)
@export var accent := Color(0.15, 0.19, 0.32)  ## Streifen und Ferse am Schuh
@export var sole := Color(0.85, 0.85, 0.84)
@export var pads := Color(0.1, 0.1, 0.11)
@export_group("Libero")
@export var libero_jersey := Color(0.78, 0.64, 0.25)
@export var libero_panel := Color(0.15, 0.19, 0.32)
@export var libero_number := Color(0.15, 0.19, 0.32)


## Farben fuer HumanFigure.build (Schluessel = Materialnamen im Modell).
func colors(libero := false) -> Dictionary:
	return {
		"jersey": libero_jersey if libero else jersey,
		"panel": libero_panel if libero else panel,
		"collar": libero_panel if libero else collar,
		"logo": libero_panel if libero else logo,
		"shorts": shorts, "socks": socks, "shoes": shoes,
		"accent": accent, "sole": sole, "pads": pads,
	}


func number_color(libero := false) -> Color:
	return libero_number if libero else number
