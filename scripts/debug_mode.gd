## Debug-Modus: Uebungen (einzelne Spielsituationen immer wieder) und Abkuerzungen fuer
## Mein Verein (Muenzen, Karten, Aufgaben). Erreichbar ueber die Kachel "Debug" im Startmenue.
## Fuer Beta- und Verkaufsversionen ENABLED auf false stellen: dann gibt es weder Kachel noch Menue.
class_name DebugMode
extends RefCounted

const ENABLED := true

## Alle Uebungen. does = was du selbst spielst (der Rest macht die KI fuer dein Team),
## start = wie jede Wiederholung beginnt:
## serve_opp Gegner schlaegt auf, serve_own du schlaegst auf, serve_alt abwechselnd,
## pass_own der Ball kommt als Annahme zu deinem Zuspieler, pass_opp zum gegnerischen Zuspieler,
## free freies Laufen ohne Ball.
const DRILLS := [
	{"id": "annahme", "title": "Aufschlag annehmen", "desc": "Der Gegner schlägt auf, du nimmst an.",
		"does": ["pass"], "start": "serve_opp"},
	{"id": "zuspiel", "title": "Zuspielen", "desc": "Die Annahme kommt, du spielst zu.",
		"does": ["set"], "start": "pass_own"},
	{"id": "angriff", "title": "Angreifen", "desc": "Die KI spielt dir zu, du schlägst.",
		"does": ["attack"], "start": "pass_own"},
	{"id": "aufschlag", "title": "Aufschlagen", "desc": "Du schlägst auf, immer wieder.",
		"does": ["serve"], "start": "serve_own"},
	{"id": "block", "title": "Blocken", "desc": "Der Gegner greift an, du blockst.",
		"does": ["block"], "start": "pass_opp"},
	{"id": "abwehr", "title": "Abwehren", "desc": "Der Gegner greift an, du wehrst ab.",
		"does": ["dig", "pass", "free"], "start": "pass_opp"},
	{"id": "ballwechsel", "title": "Ganzer Ballwechsel", "desc": "Alles selbst spielen, ohne Punkte.",
		"does": ["serve", "pass", "dig", "set", "attack", "free", "block"], "start": "serve_alt"},
	{"id": "laufen", "title": "Laufen und Bewegungen", "desc": "Frei laufen, Haltungen und Sprünge.",
		"does": [], "start": "free"},
]

## Einstellungen der Uebungen: [Schluessel, Anzeige, Werte, Texte]. Die Auswahl bleibt erhalten,
## solange das Spiel laeuft (auch ueber einen Teamwechsel hinweg).
const OPTIONS := [
	["rot", "Rotation (dein Team)", [0, 1, 2, 3, 4, 5], ["1", "2", "3", "4", "5", "6"]],
	["lane", "Zuspiel auf", ["auto", "left", "mid", "right", "back"], ["Zufall", "Außen", "Mitte", "Diagonal", "Hinterfeld"]],
	["tempo", "Zuspiel-Tempo", ["high", "fast"], ["Hoch", "Schnell"]],
	["serve", "Aufschlag der KI", ["auto", "float", "jump_float", "topspin", "jump_topspin", "short"],
		["Zufall", "Flatter", "Sprungflatter", "Topspin", "Sprung-Topspin", "Kurz"]],
	["start", "Übung beginnt mit", ["toss", "serve"], ["Zuwurf (schnell)", "Echtem Aufschlag"]],
	["after", "Nach deiner Aktion", ["reset", "play"], ["Gleich neu", "Weiterspielen"]],
	["block", "Dein Block beim Abwehren", [true, false], ["KI blockt", "Kein Block"]],
]

static var opts := {"rot": 0, "lane": "auto", "tempo": "high", "serve": "auto", "start": "toss", "after": "reset", "block": true}
## Nach einem Teamwechsel wird die Halle neu geladen; danach startet diese Uebung sofort.
static var pending := ""


static func drill(id: String) -> Dictionary:
	for d in DRILLS:
		if d.id == id:
			return d
	return DRILLS[0]


static func option_text(key: String) -> String:
	for o in OPTIONS:
		if o[0] == key:
			var i: int = (o[2] as Array).find(opts[key])
			return o[3][maxi(i, 0)]
	return ""


static func cycle_option(key: String, step := 1) -> void:
	for o in OPTIONS:
		if o[0] == key:
			var vals: Array = o[2]
			opts[key] = vals[posmod(vals.find(opts[key]) + step, vals.size())]


# ------------------------------------------------------------------ Mein Verein

## Schnell einen Verein gruenden (wie im Menue, mit dem ersten Namensvorschlag).
static func club_found() -> void:
	if not Club.exists():
		Club.create(Club.NAME_IDEAS[0], 0)


static func club_add_coins(n: int) -> void:
	club_found()
	Club.data.coins = maxi(0, int(Club.data.coins) + n)
	Club.save()


static func club_set_coins(n: int) -> void:
	club_found()
	Club.data.coins = n
	Club.save()


## Alle Karten in die Sammlung (die Aufgaben bleiben offen).
static func club_all_cards() -> void:
	club_found()
	for id in Club.all_ids():
		if not Club.data.owned.has(id):
			Club.data.owned.append(id)
	Club.save()


## Nur noch die Nachwuchs-Karten und die Karten aus erledigten Aufgaben behalten.
static func club_reset_cards() -> void:
	club_found()
	var keep: Array = (load(Club.YOUTH) as TeamStyle).players.map(func(p): return p.id)
	for c in Club.challenges():
		if Club.is_done(c.id) and not keep.has(c.card):
			keep.append(c.card)
	Club.data.owned = keep
	var lu: Array = Club.data.lineup
	for i in lu.size():
		if lu[i] != "" and not keep.has(lu[i]):
			lu[i] = ""
	Club.data.lineup = lu
	Club.save()


## Aufgabe erledigen wie nach einem Spiel: Karte dazu (oder Bonusmuenzen, wenn sie schon da ist).
static func club_complete(cid: String) -> String:
	club_found()
	for c in Club.challenges():
		if c.id != cid or Club.is_done(cid):
			continue
		Club.data.done.append(cid)
		var pd := Club.card(c.card)
		var line := ""
		if Club.owns(c.card):
			Club.data.coins += Club.price(pd) / 2
			line = "%s: erledigt (+%s Münzen)" % [c.text, Club.fmt(Club.price(pd) / 2)]
		else:
			Club.data.owned.append(c.card)
			line = "%s: erledigt, neue Karte %s" % [c.text, pd.full_name()]
		Club.save()
		return line
	return ""


## Aufgabe wieder oeffnen (die Karte bleibt in der Sammlung).
static func club_reopen(cid: String) -> void:
	if not Club.exists():
		return
	Club.data.done.erase(cid)
	Club.data.count.erase(cid)
	Club.save()


static func club_complete_all() -> void:
	for c in Club.challenges():
		club_complete(c.id)


static func club_reopen_all() -> void:
	if not Club.exists():
		return
	Club.data.done = []
	Club.data.count = {}
	Club.data.wins = 0
	Club.save()


## Verein komplett loeschen: beim naechsten Oeffnen von Mein Verein wird neu gegruendet.
static func club_delete() -> void:
	Club.data = {}
	Club.save()
	if FileAccess.file_exists(Club.path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Club.path()))
	if Teams.home == Club.ID:
		Teams.home = Teams.next_id(Club.ID, Teams.away)
