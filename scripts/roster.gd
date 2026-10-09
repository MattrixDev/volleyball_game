class_name TeamRoster
extends RefCounted
## Kader eines Teams (12 Spieler), Aufstellung auf dem Feld, Rotation, Libero, Wechsel und
## Auszeiten. Reine Daten und Regeln, keine Grafik. Position 1 = rechts hinten (Aufschlag),
## 2 = rechts vorn, 3 = Mitte vorn, 4 = links vorn, 5 = links hinten, 6 = Mitte hinten.

const SUBS_PER_SET := 6
const TIMEOUTS_PER_SET := 2

const ROLE_TEXT := {"S": "Zuspieler", "OH": "Außenangreifer", "MB": "Mittelblocker", "OP": "Diagonalangreifer", "L": "Libero"}
const ROLE_TAG := {"S": "Z", "OH": "A", "MB": "M", "OP": "D", "L": "L"}

## Kader je Team: [Rolle, Trikotnummer, Name]. Die ersten sechs sind die Startsechs in
## der Reihenfolge der Positionen 1 bis 6 (Zuspieler und Diagonal stehen sich gegenueber).
const SQUADS := [
	[["S", 7, "Jonas Brandt"], ["OH", 10, "Felix Ahrens"], ["MB", 14, "Tobias Lund"], ["OP", 3, "Marten Voss"],
		["OH", 5, "Ole Petersen"], ["MB", 8, "Niklas Wendt"], ["L", 1, "Henrik Sander"],
		["S", 12, "Lasse Krüger"], ["OH", 11, "Jannik Mohr"], ["MB", 15, "Finn Ostermann"], ["OP", 9, "Paul Rieck"], ["L", 17, "Mats Lorenz"]],
	[["S", 9, "Lukas Ebert"], ["OH", 4, "Moritz Kern"], ["MB", 12, "David Schaaf"], ["OP", 18, "Simon Falk"],
		["OH", 11, "Jonathan Roth"], ["MB", 6, "Elias Bender"], ["L", 2, "Max Hartung"],
		["S", 14, "Tim Vogler"], ["OH", 7, "Benno Keller"], ["MB", 16, "Carl Zander"], ["OP", 10, "Rafael Lenz"], ["L", 13, "Nils Gerber"]],
]

var team := 0
## Je Spieler: {id, role, number, name}
var members: Array = []
## Spieler-Ids auf den Positionen 1 bis 6 (Index 0 = Position 1).
var lineup: Array = []
var start_lineup: Array = []
## Libero: Id des Liberos, der gerade auf dem Feld steht (-1 = keiner), und wen er ersetzt.
var libero_on := -1
var libero_for := -1
var subs_used := 0
var timeouts_left := TIMEOUTS_PER_SET
## ausgewechselter Spieler -> sein Ersatz (Wiedereintritt nur fuer den Ersatz).
var replaced_by := {}
var spent: Array = []


func _init(p_team: int = 0) -> void:
	team = p_team
	for i in 12:
		var s: Array = SQUADS[team][i]
		members.append({"id": i, "role": s[0], "number": s[1], "name": s[2]})
	start_lineup = [0, 1, 2, 3, 4, 5]
	new_set()


func new_set() -> void:
	lineup = start_lineup.duplicate()
	libero_on = -1
	libero_for = -1
	subs_used = 0
	timeouts_left = TIMEOUTS_PER_SET
	replaced_by = {}
	spent = []


func m(id: int) -> Dictionary:
	return members[id]


func libero_ids() -> Array:
	var r := []
	for mm in members:
		if mm.role == "L":
			r.append(mm.id)
	return r


func slot_of(id: int) -> int:
	var i := lineup.find(id)
	return i + 1 if i >= 0 else 0


func on_court(id: int) -> bool:
	return lineup.has(id)


func is_front(slot: int) -> bool:
	return slot >= 2 and slot <= 4


## Nach gewonnenem Rueckschlag: jeder rueckt eine Position weiter (2 -> 1 -> 6 -> 5 -> 4 -> 3 -> 2).
func rotate() -> void:
	var first = lineup[0]
	for i in 5:
		lineup[i] = lineup[i + 1]
	lineup[5] = first


## Der Aufschlaeger steht auf Position 1; ein Libero dort ist nicht erlaubt (siehe enforce_libero).
func server_id() -> int:
	return lineup[0]


# ------------------------------------------------------------------ Libero

## Darf der Libero jetzt fuer den Spieler auf diesem Platz rein? Nur auf den Hinterpositionen
## 5 und 6 (Position 1 schlaegt auf) und nur fuer einen Nicht-Libero.
func can_libero_enter(slot: int) -> bool:
	if libero_on >= 0 or slot == 1 or slot == 0 or is_front(slot):
		return false
	return m(lineup[slot - 1]).role != "L"


func libero_enter(slot: int, libero_id: int) -> int:
	var out_id: int = lineup[slot - 1]
	libero_on = libero_id
	libero_for = out_id
	lineup[slot - 1] = libero_id
	return out_id


## Libero verlaesst das Feld, der ersetzte Spieler kommt zurueck. Gibt dessen Id zurueck.
func libero_leave() -> int:
	var slot := slot_of(libero_on)
	var back := libero_for
	lineup[slot - 1] = back
	libero_on = -1
	libero_for = -1
	return back


## Steht der Libero auf einer Position, auf der er nicht sein darf (vorn oder Aufschlag)?
func libero_illegal() -> bool:
	if libero_on < 0:
		return false
	var slot := slot_of(libero_on)
	return slot == 1 or is_front(slot)


## Position fuer den automatischen Libero-Wechsel: Mittelblocker auf 5 oder 6.
func auto_libero_slot() -> int:
	if libero_on >= 0:
		return 0
	for s in [6, 5]:
		if m(lineup[s - 1]).role == "MB":
			return s
	return 0


# ------------------------------------------------------------------ Wechsel

func bench() -> Array:
	var r := []
	for mm in members:
		if not lineup.has(mm.id) and mm.id != libero_on and mm.id != libero_for:
			r.append(mm.id)
	return r


## Wechsel: Spieler `in_id` kommt fuer `out_id`. Regeln: hoechstens 6 pro Satz, Libero nur ueber
## die Liberowechsel. Ein Stammspieler darf einmal raus und nur fuer seinen Ersatz wieder rein,
## ein Ersatzspieler darf nur fuer einen Stammspieler kommen und nur von diesem abgeloest werden.
func sub_error(out_id: int, in_id: int) -> String:
	if subs_used >= SUBS_PER_SET:
		return "Keine Wechsel mehr in diesem Satz"
	if m(out_id).role == "L" or m(in_id).role == "L":
		return "Der Libero wechselt nur über den Liberowechsel"
	if not lineup.has(out_id) or lineup.has(in_id) or in_id == libero_for:
		return "Wechsel nicht möglich"
	if spent.has(in_id):
		return "Dieser Spieler wurde in diesem Satz schon eingesetzt"
	if replaced_by.has(in_id):
		if replaced_by[in_id] != out_id:
			return "%s darf nur für %s zurück" % [m(in_id).name, m(replaced_by[in_id]).name]
	elif replaced_by.values().has(out_id):
		return "%s kann nur von %s abgelöst werden" % [m(out_id).name, m(replaced_by.find_key(out_id)).name]
	return ""


func substitute(out_id: int, in_id: int) -> void:
	var slot := slot_of(out_id)
	lineup[slot - 1] = in_id
	subs_used += 1
	if replaced_by.has(in_id):
		replaced_by.erase(in_id)  # Stammspieler ist zurueck, sein Ersatz ist verbraucht
		spent.append(out_id)
	else:
		replaced_by[out_id] = in_id
