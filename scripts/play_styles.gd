class_name PlayStyles
extends RefCounted
## PlayStyles (wie in EA FC, Wunsch von Mattis 06.11.2026): Jeder Spieler hat 2 bis 4 Faehigkeiten,
## mit denen er bestimmte Techniken besser oder anders kann. Die Plus-Stufe (Weltklasse) hat nur
## etwa jeder zehnte Spieler. Im Ligaspiel fest pro Spieler, aus den Werten abgeleitet (die alten
## Eigenschaften bleiben erhalten); in "Mein Verein" spaeter dazulernbar.
## Im Spiel: match.gd pls(pl, id) -> 0 (keiner), 1 (PlayStyle), 2 (PlayStyle+).

const GROUPS := ["Aufschlag", "Annahme", "Zuspiel", "Angriff", "Block", "Körper"]

## id: [Name, Gruppe, Wert, erlaubte Rollen ("" = alle ausser Libero, "*" = alle), was er kann, was Plus zusaetzlich kann]
const CATALOG := {
	"kanone": ["Aufschlagkanone", 0, "serve", "", "Sprungaufschlag deutlich härter", "noch härter, öfter ein Wuchtaufschlag"],
	"flatter": ["Flatterkünstler", 0, "serve", "", "Flatterball bricht stärker aus", "Ball flattert extrem"],
	"taktiker": ["Aufschlagtaktiker", 0, "serve", "", "trifft sein Ziel genauer, Aufschlag in die Lücke wirkt stärker", "Skyball-Aufschlag möglich"],
	"katze": ["Abwehrkatze", 1, "defense", "*", "erreicht und hält harte Angriffe besser", "noch größere Reichweite in der Abwehr"],
	"ruhepol": ["Ruhepol", 1, "receive", "OH,L,OP", "Flatter- und harte Aufschläge bringen ihn kaum aus der Ruhe", "fast unbeeindruckt"],
	"hecht": ["Hechtkönig", 1, "defense", "L,OH,S,OP", "Hecht reicht weiter", "einarmige Rettung möglich"],
	"spielmacher": ["Spielmacher", 2, "setting", "S", "stellt genauer", "Zuspiel fast immer punktgenau"],
	"sprungzuspiel": ["Sprungzuspieler", 2, "setting", "S", "schnelle Bälle kommen früher, der Block ist zu spät", "Sprungzuspiel möglich"],
	"trickser": ["Trickser", 2, "setting", "S,OP", "Dump und Zuspieler-Angriff überraschen die Abwehr", "noch schwerer zu lesen"],
	"kraftpaket": ["Kraftpaket", 3, "power", "OH,OP,MB", "schlägt härter und mit mehr Winkel", "noch mehr Wucht"],
	"beidhaender": ["Beidhänder", 3, "power", "OH,OP", "von beiden Seiten gleich gefährlich, der Block tut sich schwer", "Schwachhand-Angriff möglich"],
	"winkel": ["Winkelkünstler", 3, "power", "OH,OP", "Linie und scharfe Diagonale auch ohne perfektes Timing", "Dreh-Schlag hinter dem Kopf möglich"],
	"leger": ["Leger", 3, "power", "OH,OP,MB,S", "Leger und Gefühlsschläge landen genauer und überraschen die Abwehr", "kaum zu lesen"],
	"blockleser": ["Blockleser", 4, "block", "MB,OP,S,OH", "liest den Angriff und blockt stärker", "liest fast alles"],
	"mauer": ["Mauer", 4, "block", "MB,OP", "drückt Bälle öfter direkt zurück", "fast unüberwindbar"],
	"lange_arme": ["Lange Arme", 4, "block", "MB,OP,OH", "reicht höher", "reicht noch höher"],
	"sprungwunder": ["Sprungwunder", 5, "jump", "", "springt höher", "springt noch höher"],
	"blitzstart": ["Blitzstart", 5, "speed", "*", "ist schneller am Ball", "explosiv schnell"],
}

const PLUS_AT := 95  ## ab diesem Wert (und Gesamtwertung ab PLUS_OV) wird ein PlayStyle zur Plus-Stufe
const PLUS_OV := 80


## Kurzname fuer die Plaketten auf der Spielerkarte.
const SHORT := {"kanone": "Kanone", "flatter": "Flatter", "taktiker": "Taktiker", "katze": "Katze", "ruhepol": "Ruhepol",
	"hecht": "Hecht", "spielmacher": "Regie", "sprungzuspiel": "Sprungpass", "trickser": "Trick", "kraftpaket": "Kraft",
	"beidhaender": "Beidhand", "winkel": "Winkel", "leger": "Leger", "blockleser": "Leser", "mauer": "Mauer",
	"lange_arme": "Arme", "sprungwunder": "Sprung", "blitzstart": "Blitz"}


static func short_of(id: String, level: int = 1) -> String:
	return str(SHORT.get(id, id)) + ("+" if level >= 2 else "")


static func name_of(id: String, level: int = 1) -> String:
	var c: Array = CATALOG.get(id, [id])
	return str(c[0]) + ("+" if level >= 2 else "")


static func group_of(id: String) -> int:
	return int(CATALOG[id][1]) if CATALOG.has(id) else 0


static func _allowed(roles: String, role: String) -> bool:
	if roles == "*":
		return true
	if roles == "":
		return role != "L"
	return role in roles.split(",")


static func _value(pd: PlayerData, id: String) -> float:
	var v := float(pd.get(CATALOG[id][2]))
	if id == "lange_arme":
		v += (pd.height_m - 1.95) * 15.0
	return v


## Feste PlayStyles eines Spielers aus seinen Werten: {id: Stufe}. Deterministisch (gleiche
## Werte, gleiche PlayStyles), alte Eigenschaften bleiben dabei.
static func assign(pd: PlayerData) -> Dictionary:
	var ov := pd.overall()
	var n := 2 if ov < 72 else (3 if ov < 80 else 4)
	var cands: Array = []
	for id in CATALOG:
		if not _allowed(CATALOG[id][3], pd.role):
			continue
		var v := _value(pd, id)
		var sc := v + (15.0 if id in pd.traits else 0.0) + float(absi(hash(pd.id + id)) % 400) / 100.0
		cands.append([sc, id, v])
	cands.sort_custom(func(a, b): return a[0] > b[0])
	var res := {}
	var per_group := {}
	var plus := 0
	for c in cands:
		if res.size() >= n:
			break
		var id: String = c[1]
		var g := group_of(id)
		if per_group.get(g, 0) >= 2:
			continue
		per_group[g] = per_group.get(g, 0) + 1
		var lv := 1
		if float(c[2]) >= PLUS_AT and ov >= PLUS_OV and plus < 1:
			lv = 2
			plus += 1
		res[id] = lv
	return res
