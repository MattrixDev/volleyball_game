class_name AiPlan
extends RefCounted
## Spielplan eines KI-Teams (K1) und sein Gedaechtnis fuer den Gegner (K2).
##
## K1: Jedes Team hat einen Charakter, der aus seinen Spielerwerten folgt (Aufschlagdruck,
## Tempo, Wucht, Sicherheit). Er bestimmt, wie riskant es aufschlaegt, wie schnell es spielt,
## wen es anspielt und wie es angreift. So spielt sich jeder Gegner anders.
##
## K2: Das Team merkt sich, wie der Gegner angreift (pro Angriffsbahn: Linie, Diagonale,
## Leger/Gefuehl), welche Bahnen er bevorzugt und welcher Annahmespieler schwach annimmt.
## Daraus stellt es Block und Abwehr ein. Wer abwechselt, wird nicht gelesen. Das Gedaechtnis
## verblasst, damit ein Wechsel schnell wirkt. Eigene Angriffe, die geblockt oder abgewehrt
## wurden, versucht es seltener wieder.

const ARCHETYPES := {
	"druck": {"title": "Aufschlagdruck", "desc": "Riskante Sprungaufschläge, zielt auf den schwächsten Annahmespieler"},
	"tempo": {"title": "Tempo-Spiel", "desc": "Schnelle Bälle und viel über die Mitte, der Zuspieler legt auch mal selbst"},
	"wucht": {"title": "Wucht", "desc": "Hohe Bälle nach außen, harte Angriffe, großer Block"},
	"sicher": {"title": "Sicherheit", "desc": "Wenig Fehler, sichere Aufschläge, viele Leger und Gefühlsschläge"},
}

var archetype := "sicher"
var second := ""
var title := ""
var desc := ""

# Aufschlag
var serve_jump := 0.55     ## Anteil Sprungaufschlaege
var serve_power := Vector2(0.7, 0.95)
var serve_weak := 0.25     ## wie oft gezielt auf den schwaechsten Annahmespieler
var serve_short := 0.08    ## kurze Aufschlaege
# Zuspiel
var tempo_fast := 0.55     ## schneller Ball nach guter Annahme
var quick_bias := 0.3      ## davon Schnellangriff Mitte
var dump_rate := 0.07
var lane_w := {"left": 0.4, "right": 0.3, "mid": 0.3}
# Angriff
var attack_power := Vector2(0.6, 1.0)
var finesse := 0.25        ## Gefuehlsschlag, wenn der Block steht
var tip := 0.1             ## Leger
var block_read := 0.65     ## sucht eine Richtung am Block vorbei

# K2: Gedaechtnis ueber den Gegner. Schluessel "<bahn>|<richtung>" bzw. "<bahn>" -> Gewicht.
const DECAY := 0.85
var dirs := {}             ## Angriffsrichtung je Bahn: line / cross / soft
var lanes := {}            ## welche Bahn der Gegner anspielt
var lane_total := 0.0
var recv := {}             ## Annahmespieler-Name -> [Summe Qualitaet, Anzahl]
var fails := {}            ## eigene Angriffe "<bahn>|<richtung>" -> Gewicht (geblockt/abgewehrt)
var shown := {}            ## schon angezeigte Lesehinweise
var adapt := 0.7           ## wie stark die KI sich anpasst (Gegner-Block-Regler)


## Charakter aus den Spielerwerten: der hoechste Wert gewinnt, der zweite faerbt mit.
## datas = PlayerData der Mannschaft (ohne null), seed = fester Wert je Team (Gleichstand).
func build(datas: Array, seed: int) -> void:
	var avg := func(key: String, roles: Array) -> float:
		var s := 0.0
		var n := 0
		for d in datas:
			if roles.is_empty() or d.role in roles:
				s += d.f(key)
				n += 1
		return s / maxf(n, 1)
	var traits := func(t: String) -> float:
		var n := 0.0
		for d in datas:
			if d.has_trait(t):
				n += 1.0
		return n
	var h := 0.0
	for d in datas:
		h += d.height_m
	h /= maxf(datas.size(), 1)
	var score := {
		"druck": avg.call("serve", []) + 0.35 * (traits.call("kanone") + traits.call("flatter")),
		"tempo": avg.call("setting", ["S"]) * 0.7 + avg.call("speed", ["MB", "S"]) * 0.5 + 0.4 * traits.call("spielmacher"),
		"wucht": avg.call("power", ["OH", "OP", "MB"]) * 0.7 + (h - 1.98) * 6.0 + 0.3 * traits.call("kraftpaket"),
		"sicher": avg.call("receive", []) * 0.6 + avg.call("defense", []) * 0.6 + 0.3 * traits.call("katze"),
	}
	var keys := ["druck", "tempo", "wucht", "sicher"]
	# Kleiner fester Versatz je Team, damit gleich starke Teams nicht alle gleich wirken.
	for i in keys.size():
		score[keys[i]] += 0.04 * float((seed >> (i * 3)) & 7) / 7.0
	keys.sort_custom(func(a, b): return score[a] > score[b])
	archetype = keys[0]
	second = keys[1]
	title = ARCHETYPES[archetype].title
	desc = ARCHETYPES[archetype].desc
	_apply(archetype, 1.0)
	_apply(second, 0.4)


func _apply(kind: String, w: float) -> void:
	match kind:
		"druck":
			serve_jump = lerpf(serve_jump, 0.85, w)
			serve_power = serve_power.lerp(Vector2(0.82, 1.0), w)
			serve_weak = lerpf(serve_weak, 0.75, w)
			serve_short = lerpf(serve_short, 0.04, w)
		"tempo":
			tempo_fast = lerpf(tempo_fast, 0.8, w)
			quick_bias = lerpf(quick_bias, 0.55, w)
			dump_rate = lerpf(dump_rate, 0.16, w)
			lane_w = _mix(lane_w, {"left": 0.32, "right": 0.25, "mid": 0.43}, w)
		"wucht":
			tempo_fast = lerpf(tempo_fast, 0.3, w)
			attack_power = attack_power.lerp(Vector2(0.8, 1.0), w)
			finesse = lerpf(finesse, 0.1, w)
			tip = lerpf(tip, 0.04, w)
			lane_w = _mix(lane_w, {"left": 0.5, "right": 0.38, "mid": 0.12}, w)
			block_read = lerpf(block_read, 0.45, w)
		"sicher":
			serve_jump = lerpf(serve_jump, 0.3, w)
			serve_power = serve_power.lerp(Vector2(0.62, 0.82), w)
			serve_short = lerpf(serve_short, 0.15, w)
			finesse = lerpf(finesse, 0.45, w)
			tip = lerpf(tip, 0.18, w)
			attack_power = attack_power.lerp(Vector2(0.5, 0.85), w)
			block_read = lerpf(block_read, 0.85, w)


static func _mix(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	var r := {}
	for k in a:
		r[k] = lerpf(a[k], b[k], w)
	return r


## Richtung eines Angriffs aus Sicht des Angreifers: line, cross oder soft (Leger/Gefuehl).
## hl = seitliche Lage des Angreifers (lokal), tl = seitliche Lage des Ziels (lokal, gleiche Achse).
static func attack_dir(key: String, hl: float, tl: float) -> String:
	if key in ["tip", "roll", "corner", "seam", "rebound"] or key.begins_with("finesse"):
		return "soft"
	if absf(hl) < 1.5:
		return "line" if absf(tl - hl) < 1.6 else "cross"  # Mitte: gerade = Linie
	return "line" if signf(tl) == signf(hl) and absf(tl) > 1.8 else "cross"


## K2: gegnerischen Angriff merken.
func observe_attack(lane: String, dir: String) -> void:
	for k in dirs.keys():
		dirs[k] *= DECAY
	var key := lane + "|" + dir
	dirs[key] = dirs.get(key, 0.0) + 1.0


func observe_set(lane: String) -> void:
	for k in lanes.keys():
		lanes[k] *= DECAY
	lane_total = lane_total * DECAY + 1.0
	lanes[lane] = lanes.get(lane, 0.0) + 1.0


func observe_reception(player_name: String, q: int) -> void:
	var r: Array = recv.get(player_name, [0.0, 0.0])
	r[0] += float(q)
	r[1] += 1.0
	recv[player_name] = r


## Eigener Angriff ging schief (geblockt, abgewehrt) oder hat gepunktet.
func observe_own(lane: String, dir: String, failed: bool) -> void:
	for k in fails.keys():
		fails[k] *= DECAY
	var key := lane + "|" + dir
	fails[key] = maxf(0.0, fails.get(key, 0.0) + (1.0 if failed else -0.6))


## Bevorzugte Richtung des Gegners auf dieser Bahn: [richtung, anteil, stichproben].
func tendency(lane: String) -> Array:
	var best := ""
	var bw := 0.0
	var tot := 0.0
	for d in ["line", "cross", "soft"]:
		var w: float = dirs.get(lane + "|" + d, 0.0)
		tot += w
		if w > bw:
			bw = w
			best = d
	if tot <= 0.0:
		return ["", 0.0, 0.0]
	return [best, bw / tot, tot]


## Wie sicher die KI eine Richtung vorhersagt (0 = gar nicht). Erst ab etwa drei gleichen
## Angriffen und nur, wenn eine Richtung klar vorn liegt.
func read_strength(lane: String) -> float:
	var t := tendency(lane)
	if t[0] == "":
		return 0.0
	var share: float = t[1]
	var n: float = t[2]
	return clampf((share - 0.45) / 0.4, 0.0, 1.0) * clampf((n - 1.5) / 2.0, 0.0, 1.0) * adapt


## Anteil der Lieblingsbahn des Gegners (0 = keine Vorliebe).
func lane_lean() -> Array:
	var best := ""
	var bw := 0.0
	for k in lanes:
		if lanes[k] > bw:
			bw = lanes[k]
			best = k
	if lane_total < 2.5:
		return ["", 0.0]
	return [best, clampf((bw / lane_total - 0.4) / 0.35, 0.0, 1.0) * adapt]


## Schwaechster Annahmespieler (Name), wenn es genug Annahmen gibt.
func weakest_receiver() -> String:
	var best := ""
	var bq := -1.0
	for n in recv:
		var r: Array = recv[n]
		if r[1] < 2.0:
			continue
		var q: float = r[0] / r[1]
		if q > bq:
			bq = q
			best = n
	return best


## Wie sehr die KI einen eigenen Angriff meidet, der zuletzt schiefging (0..1).
func avoid(lane: String, dir: String) -> float:
	return clampf(fails.get(lane + "|" + dir, 0.0) / 2.5, 0.0, 0.8)


## Einmalige Anzeige je Lesart; erneut erst, wenn sie zwischendurch verschwunden war.
func should_show(key: String, on: bool) -> bool:
	if not on:
		shown.erase(key)
		return false
	if shown.has(key):
		return false
	shown[key] = true
	return true


static func dir_text(dir: String) -> String:
	match dir:
		"line":
			return "Linie"
		"cross":
			return "Diagonale"
	return "Leger"
