class_name Technique
extends RefCounted
## Welche Technik ein Spieler in einer Lage waehlt (Varianz aus der Situation, nicht aus Zufall).
## Das Spiel setzt den Namen als VPlayer.anim_style; wie die Technik aussieht, entscheidet die
## Figur (leer oder unbekannt = die normale Bewegung). Gleiche Lage -> gleiche Technik.

## Annahme und Abwehr: wie weit der Spieler vom Ball weg ist, wenn er nur noch laufen kann.
## short = Strecke, die ihm bis zum Treffpunkt fehlt (m, <= 0: kommt rechtzeitig hin),
## fwd/lat = Richtung zum Treffpunkt (vorn Richtung Netz, seitlich), t_left = Zeit bis zum Kontakt,
## hard = wie hart der Ball kommt (0..1), dig = Abwehr eines Angriffs (sonst Annahme/freier Ball).
## pressure = wie knapp es von Anfang an war (noetiger Weg / moeglicher Weg; ab ca. 0,55 muss er
## sich am Ende strecken, auch wenn er hinkommt; seitlich schon ab 0,35).
static func defense_style(short: float, fwd: float, lat: float, t_left: float, hard: float, dig: bool, pressure := 0.0) -> String:
	var lateral := absf(lat) > absf(fwd)
	var behind := fwd < -0.3 and not lateral
	if short <= 0.0:
		if pressure > 0.55:
			if behind:
				return "one_arm"
			return "side" if lateral else "low"
		if pressure > 0.35 and lateral:
			return "side"  # zur Seite gelaufen: Ausfallschritt, Arme gekippt
		return "low" if dig and hard > 0.6 else ""
	if short <= 0.45:
		if behind:
			return "one_arm"
		return "side" if lateral else "low"
	if short <= 0.9:
		if t_left < 0.4 or behind:
			return "one_arm"
		return "dive_side" if lateral else "sprawl"
	if behind:
		return "chase_back"
	if not dig:
		return "dive_side" if lateral else "sprawl"  # Annahme: kein Pancake, der Ball kommt nicht steil
	if lateral:
		return "dive_side" if short < 1.6 else "pancake"
	return "sprawl" if short < 1.4 else "pancake"


## Wie weit die Technik reicht (Abstand Koerper -> Ball beim Kontakt, m).
static func reach(style: String) -> float:
	match style:
		"side":
			return 1.0
		"one_arm":
			return 1.3
		"sprawl":
			return 1.75
		"dive_side":
			return 1.9
		"pancake":
			return 2.2
		"chase_back":
			return 1.4
		"overhead":
			return 0.7
	return 0.75


## Beste Qualitaet, die mit dieser Technik moeglich ist (Match.Q: 0 perfekt .. 2 schwach).
static func best_quality(style: String) -> int:
	match style:
		"pancake", "chase_back":
			return 2
		"sprawl", "dive_side", "one_arm", "overhead":
			return 1
	return 0


## Wie lange der Spieler danach am Boden liegt bzw. braucht, um wieder spielbereit zu sein (s).
static func recovery(style: String) -> float:
	match style:
		"sprawl", "dive_side":
			return 1.1
		"pancake":
			return 1.3
		"chase_back":
			return 0.6
		"one_arm", "low":
			return 0.45
	return 0.0


## Liegt der Spieler danach auf dem Boden (Hecht-Pose der Figur)?
static func goes_down(style: String) -> bool:
	return style in ["sprawl", "dive_side", "pancake"]


## Angriff: Bewegung aus Schlagart und Lage. shot = attack_shot().style, lateral = seitlicher Weg
## des Balls (m), tempo = Tempo des Zuspiels, lane = Angriffsbahn, emergency = Notangriff.
static func attack_style(shot: String, power: float, lateral: float, tempo: String, lane: String, emergency: bool) -> String:
	if emergency:
		return "emergency"
	if shot == "tip":
		return "tip"
	if shot == "cut":
		return "cut"
	if shot == "blockout":
		return "tool"
	if tempo == "quick":
		return "quick"
	if lane == "back":
		return "pipe"
	if shot == "topspin" and power < 0.6:
		return "roll"
	return "cross" if absf(lateral) > 2.5 else "line"


## Zuspiel: im Stand, als Sprungzuspiel (gute Annahme, Zuspieler steht rechtzeitig), mit dem
## Bagger (Ball zu hart oder zu tief zum Pritschen). Rueckwaerts entscheidet das Ziel (back).
static func set_style(is_setter: bool, pass_q: int, slack: float, over_ok: bool) -> String:
	if not over_ok:
		return "bump"
	if is_setter and pass_q <= 1 and slack >= 0.6:
		return "jump"
	return ""


## Block: commit = frueh festgelegt (gelesen), late = kommt nicht rechtzeitig an, soft = kommt
## nicht ueber den Ball und stellt die Haende schraeg nach hinten, read = liest und springt mit.
static func block_style(committed: bool, late: bool, reach_gap: float) -> String:
	if late:
		return "late"
	if reach_gap > 0.25:
		return "soft"
	return "commit" if committed else "read"


## Hechten von Hand (B): seitlich = Hecht zur Seite, sonst nach vorn (Sprawl); sehr weit bei
## einer Abwehr = Pancake. fwd/lat = Richtung zum Treffpunkt, dist = Abstand (m).
static func manual_dive(fwd: float, lat: float, dist: float, dig: bool) -> String:
	if dig and dist > 1.9:
		return "pancake"
	if absf(lat) > absf(fwd) and dist > 0.3:
		return "dive_side"
	return "sprawl"
