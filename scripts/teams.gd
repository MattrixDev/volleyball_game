## Alle Teams aus res://teams/*.tres. Welche zwei gerade spielen, steht in home/away.
class_name Teams
extends RefCounted

const DIR := "res://teams/"
static var _all: Array = []
static var home := "nordhafen"
static var away := "eichenberg"
## Nach einem Teamwechsel im Startmenue wird die Szene neu geladen und das Spiel startet sofort.
static var autostart := false


static func all() -> Array:
	if _all.is_empty():
		for f in DirAccess.get_files_at(DIR):
			# Im exportierten Spiel heissen die Dateien *.tres.remap
			f = f.trim_suffix(".remap")
			if f.ends_with(".tres"):
				var t := load(DIR + f) as TeamStyle
				if t:
					_all.append(t)
		_all.sort_custom(func(a, b): return a.name < b.name)
	return _all


static func by_id(id: String) -> TeamStyle:
	for t in all():
		if t.id == id:
			return t
	return all()[0]


## Die beiden Teams des aktuellen Spiels (0 = links, 1 = rechts).
static func playing() -> Array:
	return [by_id(home), by_id(away)]


## Naechstes Team in der Liste nach id, das nicht skip ist (fuer die Auswahl im Startmenue).
static func next_id(id: String, skip: String, step := 1) -> String:
	var ids: Array = all().map(func(t): return t.id)
	var i := ids.find(id)
	for k in ids.size():
		i = posmod(i + step, ids.size())
		if ids[i] != skip:
			return ids[i]
	return id
