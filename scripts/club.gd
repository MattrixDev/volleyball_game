## Mein Verein: Spielerkarten sammeln und daraus ein eigenes Team bauen.
## Jeder Spieler der Liga (teams/*.tres) und des Nachwuchses (club/nachwuchs.tres) ist eine Karte.
## Karten bekommt man fest, nie zufaellig: durch Aufgaben (eine bestimmte Karte je Aufgabe) oder
## mit Muenzen aus Spielen im Kartenshop (fester Preis je Wertung).
## Der Spielstand liegt in user://verein.json (Test: --club=pfad.json).
class_name Club
extends RefCounted

const ID := "mein_verein"
const YOUTH := "res://club/nachwuchs.tres"
const START_COINS := 500
## Feste Rollen der Aufstellung: Position 1 bis 6 (wie in den Team-Dateien), dann der Libero.
const SLOT_ROLES := ["S", "OH", "MB", "OP", "OH", "MB", "L"]
const SLOTS := 14  # 7 feste Plaetze + 7 Bankplaetze (beliebige Rollen)
const MIN_BENCH := 5  # mindestens 12 Spieler im Kader
## Vereinsfarben zur Auswahl: [Name, Trikot, Seitenteile/Hose-Kontrast, Nummer, Libero].
const COLORS := [
	["Waldgrün", Color(0.16, 0.33, 0.24), Color(0.92, 0.9, 0.84), Color(0.95, 0.94, 0.9), Color(0.86, 0.66, 0.24)],
	["Weinrot", Color(0.45, 0.12, 0.16), Color(0.15, 0.15, 0.16), Color(0.95, 0.93, 0.88), Color(0.85, 0.85, 0.82)],
	["Königsblau", Color(0.13, 0.27, 0.62), Color(0.95, 0.95, 0.93), Color(0.97, 0.97, 0.96), Color(0.93, 0.8, 0.25)],
	["Anthrazit", Color(0.17, 0.18, 0.2), Color(0.86, 0.36, 0.18), Color(0.95, 0.6, 0.35), Color(0.86, 0.36, 0.18)],
	["Sonnengelb", Color(0.93, 0.74, 0.2), Color(0.12, 0.13, 0.15), Color(0.12, 0.13, 0.15), Color(0.16, 0.26, 0.45)],
	["Türkis", Color(0.1, 0.5, 0.52), Color(0.95, 0.95, 0.93), Color(0.97, 0.97, 0.96), Color(0.9, 0.45, 0.3)],
	["Violett", Color(0.33, 0.2, 0.47), Color(0.93, 0.91, 0.86), Color(0.96, 0.95, 0.92), Color(0.85, 0.7, 0.3)],
	["Weiß", Color(0.94, 0.94, 0.92), Color(0.18, 0.2, 0.26), Color(0.18, 0.2, 0.26), Color(0.2, 0.4, 0.7)],
]
const NAME_IDEAS := ["VC Lindenau", "TV Rotfels", "SC Möwenkamp", "VfB Kranichfeld", "USV Heidesand",
	"TSG Falkenhorst", "VC Birkenau", "SV Weidenbrück"]

static var data := {}
static var _loaded := false
static var _style: TeamStyle
static var _cards := {}  # id -> PlayerData
static var _origin := {}  # id -> TeamStyle (Ligateam oder Nachwuchs)
static var _order: Array = []  # alle Karten-Ids, sortiert nach Team und Kaderplatz
static var _challenges: Array = []


# ------------------------------------------------------------------ Speicherstand

static func path() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--club="):
			return a.get_slice("=", 1)
	return "user://verein.json"


static func load_data() -> void:
	if _loaded:
		return
	_loaded = true
	data = {}
	if FileAccess.file_exists(path()):
		var f := FileAccess.open(path(), FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			data = d
	if exists():
		_sanitize()


static func save() -> void:
	var f := FileAccess.open(path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
	_style = null


static func exists() -> bool:
	load_data()
	return data.has("name")


## Neuer Verein: 14 Nachwuchs-Karten in fester Aufstellung, etwas Startgeld.
static func create(club_name: String, color: int) -> void:
	var youth: Array = (load(YOUTH) as TeamStyle).players.map(func(p): return p.id)
	data = {
		"name": club_name.strip_edges() if club_name.strip_edges() != "" else NAME_IDEAS[0],
		"color": clampi(color, 0, COLORS.size() - 1),
		"coins": START_COINS,
		"owned": youth.duplicate(),
		"lineup": youth.duplicate(),
		"done": [],
		"count": {},
		"matches": 0, "wins": 0,
	}
	_loaded = true
	save()


static func _sanitize() -> void:
	_index()
	var owned: Array = data.get("owned", []).filter(func(i): return _cards.has(i))
	data.owned = owned
	var lu: Array = data.get("lineup", [])
	lu.resize(SLOTS)
	for i in SLOTS:
		if lu[i] == null or not owned.has(lu[i]):
			lu[i] = ""
	data.lineup = lu
	for k in ["done"]:
		if not data.has(k):
			data[k] = []
	if not data.has("count"):
		data.count = {}
	data.coins = int(data.get("coins", 0))


# ------------------------------------------------------------------ Karten

static func _index() -> void:
	if not _order.is_empty():
		return
	var teams: Array = Teams.all().duplicate()
	teams.append(load(YOUTH))
	for t in teams:
		for p in t.players:
			_cards[p.id] = p
			_origin[p.id] = t
			_order.append(p.id)


static func all_ids() -> Array:
	_index()
	return _order


static func card(id: String) -> PlayerData:
	_index()
	return _cards.get(id)


static func origin(id: String) -> TeamStyle:
	_index()
	return _origin.get(id)


static func owns(id: String) -> bool:
	return exists() and data.owned.has(id)


## Kartenstufe nach Wertung: 0 Bronze (bis 64), 1 Silber (65 bis 74), 2 Gold (ab 75).
static func tier(pd: PlayerData) -> int:
	var o := pd.overall()
	return 2 if o >= 75 else (1 if o >= 65 else 0)


## Fester Preis im Kartenshop: steigt mit der Wertung (60 -> 300, 70 -> 850, 80 -> 2400, 90 -> 6850).
static func price(pd: PlayerData) -> int:
	return int(round(300.0 * pow(1.11, float(pd.overall() - 60)) / 50.0)) * 50


## Kaufen. Gibt einen Fehlertext zurueck (leer = gekauft).
static func buy(id: String) -> String:
	var pd := card(id)
	if pd == null or owns(id):
		return "Die Karte hast du schon."
	if challenge_for(id) != {} and not is_done(challenge_for(id).id):
		return "Diese Karte gibt es nur über die Aufgabe: " + challenge_for(id).text
	var p := price(pd)
	if data.coins < p:
		return "Dir fehlen noch %s Münzen." % fmt(p - data.coins)
	data.coins -= p
	data.owned.append(id)
	save()
	return ""


static func fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


# ------------------------------------------------------------------ Aufstellung

## Passt die Karte auf diesen Platz? Plaetze 0 bis 6 brauchen die feste Rolle, die Bank nimmt alle.
static func fits(slot: int, id: String) -> bool:
	if id == "":
		return slot >= 7
	var pd := card(id)
	return pd != null and (slot >= 7 or pd.role == SLOT_ROLES[slot])


## Karte auf einen Platz legen. Steht sie schon woanders, tauschen die beiden die Plaetze
## (wenn der andere Spieler dort hinpasst, sonst wird sein alter Platz leer).
static func place(slot: int, id: String) -> void:
	var lu: Array = data.lineup
	var old := lu.find(id) if id != "" else -1
	var prev: String = lu[slot]
	lu[slot] = id
	if old >= 0 and old != slot:
		lu[old] = prev if fits(old, prev) else ""
	data.lineup = lu
	save()


static func missing() -> String:
	var lu: Array = data.lineup
	for i in 7:
		if lu[i] == "":
			return "Position %s ist frei." % slot_name(i)
	var bench := 0
	for i in range(7, SLOTS):
		if lu[i] != "":
			bench += 1
	if bench < MIN_BENCH:
		return "Auf der Bank brauchst du mindestens %d Spieler." % MIN_BENCH
	return ""


static func can_play() -> bool:
	return exists() and missing() == ""


static func slot_name(i: int) -> String:
	if i < 6:
		return "%d (%s)" % [i + 1, TeamRoster.ROLE_TEXT[SLOT_ROLES[i]]]
	return "Libero" if i == 6 else "Bank"


## Wertung des Teams: Mittel der sechs Starter und des Liberos.
static func team_overall() -> int:
	var s := 0
	var n := 0
	for i in 7:
		var pd := card(data.lineup[i])
		if pd:
			s += pd.overall()
			n += 1
	return roundi(float(s) / maxi(n, 1))


## Das Team als TeamStyle fuer das Spiel (Trikotfarben + Kader aus der Aufstellung).
static func style() -> TeamStyle:
	if _style:
		return _style
	var c: Array = COLORS[int(data.get("color", 0))]
	var t := TeamStyle.new()
	t.id = ID
	t.name = data.get("name", "Mein Verein")
	t.short_name = t.name.substr(0, 3).to_upper()
	t.jersey = c[1]
	t.panel = c[2]
	t.collar = c[2]
	t.logo = c[2]
	t.number = c[3]
	t.shorts = c[1].darkened(0.35) if c[1].get_luminance() > 0.6 else c[1]
	t.socks = c[2]
	t.shoes = Color(0.92, 0.92, 0.9)
	t.accent = c[1]
	t.libero_jersey = c[4]
	t.libero_panel = c[1]
	t.libero_number = c[1] if c[4].get_luminance() > 0.5 else Color(0.97, 0.97, 0.96)
	var used := {}
	var players: Array[PlayerData] = []
	for id in data.lineup:
		if id == "":
			continue
		var pd: PlayerData = card(id).duplicate()
		# Gleiche Rueckennummern aus verschiedenen Teams: der spaetere bekommt die naechste freie.
		while used.has(pd.number):
			pd.number = pd.number % 99 + 1
		used[pd.number] = true
		players.append(pd)
	t.players = players
	_style = t
	return t


## Wertung eines Teams: Mittel der sechs Starter und des Liberos (ohne Daten: 70).
static func team_rating(t: TeamStyle) -> float:
	if t == null or t.players.size() < 7:
		return 70.0
	var s := 0.0
	for i in 7:
		s += t.players[i].overall()
	return s / 7.0


# ------------------------------------------------------------------ Aufgaben

## Feste Aufgaben, jede schaltet genau eine Karte frei.
## kind: beat (Team schlagen), aces/blocks/wucht (in einem Spiel), wins/matches (insgesamt),
## clean (Spiel ohne Satzverlust, mindestens 2 Gewinnsaetze), margin (Satz mit 10 Punkten Vorsprung).
static func challenges() -> Array:
	if not _challenges.is_empty():
		return _challenges
	_index()
	var taken := {}
	var best := func(filter: Callable, key: String) -> String:
		var pick := ""
		var top := -1.0
		for id in _order:
			var pd: PlayerData = _cards[id]
			if taken.has(id) or _origin[id].id == "nachwuchs" or not filter.call(pd):
				continue
			var v := float(pd.get(key)) if key != "overall" else float(pd.overall())
			if v > top:
				top = v
				pick = id
		taken[pick] = true
		return pick
	var list := []
	# Erst die Einzelleistungen (so bekommen sie die passenden Spezialisten), dann die Teams.
	list.append({"id": "aces3", "kind": "aces", "need": 3, "text": "Schlage 3 Asse in einem Spiel",
		"card": best.call(func(p): return p.has_trait("kanone") and p.overall() < 80, "serve")})
	list.append({"id": "blocks5", "kind": "blocks", "need": 5, "text": "Mache 5 Blockpunkte in einem Spiel",
		"card": best.call(func(p): return p.role == "MB" and (p.has_trait("blockleser") or p.has_trait("lange_arme")) and p.overall() < 80, "block")})
	list.append({"id": "wucht3", "kind": "wucht", "need": 3, "text": "Schlage 3 Wuchtschläge in einem Spiel",
		"card": best.call(func(p): return p.has_trait("kraftpaket") and p.overall() < 80, "power")})
	list.append({"id": "wins3", "kind": "wins", "need": 3, "text": "Gewinne 3 Spiele",
		"card": best.call(func(p): return p.role == "L" and p.overall() < 78, "overall")})
	list.append({"id": "margin10", "kind": "margin", "need": 1, "text": "Gewinne einen Satz mit 10 Punkten Vorsprung",
		"card": best.call(func(p): return p.has_trait("linkshaender") and p.role == "OP" and p.overall() < 80, "overall")})
	list.append({"id": "clean", "kind": "clean", "need": 1, "text": "Gewinne ein Match ohne Satzverlust (nicht das kurze Match)",
		"card": best.call(func(p): return p.role == "S" and p.has_trait("spielmacher") and p.overall() < 80, "setting")})
	list.append({"id": "wins10", "kind": "wins", "need": 10, "text": "Gewinne 10 Spiele",
		"card": best.call(func(p): return p.has_trait("sprungwunder") and p.role == "OH", "overall")})
	var roles := {"nordhafen": "OH", "eichenberg": "MB", "seewald": "L", "sturmhafen": "OP",
		"bernsteinbucht": "S", "graufelden": "MB", "morgental": "OH", "ostergrund": "OH"}
	var teams: Array = Teams.all().duplicate()
	teams.sort_custom(func(a, b): return team_rating(a) < team_rating(b))
	for t in teams:
		var role: String = roles.get(t.id, "OH")
		var tid: String = t.id
		list.append({"id": "beat_" + tid, "kind": "beat", "team": tid, "need": 1, "text": "Besiege " + t.name,
			"card": best.call(func(p): return _origin[p.id].id == tid and p.role == role, "overall")})
	_challenges = list.filter(func(c): return c.card != "")
	return _challenges


static func challenge_for(card_id: String) -> Dictionary:
	for c in challenges():
		if c.card == card_id:
			return c
	return {}


static func is_done(cid: String) -> bool:
	return exists() and data.done.has(cid)


## Stand einer Aufgabe fuer die Anzeige (0 bis need).
static func progress(c: Dictionary) -> int:
	if is_done(c.id):
		return c.need
	if c.kind in ["wins"]:
		return mini(int(data.get("wins", 0)), c.need)
	return int(data.count.get(c.id, 0))


## Nach jedem eigenen Spiel: Muenzen und Aufgaben. `m` enthaelt fuer das menschliche Team:
## won, points, opp_points, aces, blocks, wucht, sets_won, sets_lost, best_margin, quick, opp (id),
## club (true = mit Mein Verein gespielt). Gibt Zeilen fuer die Anzeige zurueck.
static func record_match(m: Dictionary) -> Array:
	if not exists():
		return []
	var lines := []
	var opp := Teams.by_id(m.opp)
	var k := clampf(team_rating(opp) / 70.0, 0.8, 1.3)
	var coins := (80 if m.quick else 150) + 5 * int(m.points) + 20 * (int(m.aces) + int(m.blocks)) + 30 * int(m.wucht)
	if m.won:
		coins += int((100 if m.quick else 220) * k)
	coins = int(round(coins / 10.0)) * 10
	data.coins += coins
	lines.append("+%s Münzen" % fmt(coins))
	if m.club:
		data.matches = int(data.get("matches", 0)) + 1
		if m.won:
			data.wins = int(data.get("wins", 0)) + 1
		for c in challenges():
			if is_done(c.id):
				continue
			var ok := false
			match c.kind:
				"beat": ok = m.won and m.opp == c.team
				"aces": ok = int(m.aces) >= c.need
				"blocks": ok = int(m.blocks) >= c.need
				"wucht": ok = int(m.wucht) >= c.need
				"wins": ok = int(data.wins) >= c.need
				"clean": ok = m.won and not m.quick and int(m.sets_lost) == 0
				"margin": ok = int(m.best_margin) >= 10
			if c.kind in ["aces", "blocks", "wucht"]:
				data.count[c.id] = maxi(int(data.count.get(c.id, 0)), int(m.get(c.kind, 0)))
			if ok:
				data.done.append(c.id)
				var pd := card(c.card)
				if owns(c.card):
					var bonus := price(pd) / 2
					data.coins += bonus
					lines.append("Aufgabe geschafft: %s (+%s Münzen, die Karte hattest du schon)" % [c.text, fmt(bonus)])
				else:
					data.owned.append(c.card)
					lines.append("Aufgabe geschafft: %s · neue Karte: %s (%d)" % [c.text, pd.full_name(), pd.overall()])
	save()
	return lines
