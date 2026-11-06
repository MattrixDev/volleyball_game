extends Node3D
## Ein Satz Hallenvolleyball, 6 gegen 6. Steuert Ball, Spielablauf, KI und Eingaben.
##
## Koordinaten: Netz bei x = 0, Team 0 (Heim, Mensch) spielt auf x < 0, Team 1 auf x > 0.
## "Lokal" heisst aus Sicht eines Teams: x = Abstand zum Netz, y = seitlich (+ = rechts).
##
## Steuerung 2.0: Baggern und Pritschen auf zwei Tasten, Schlagen durch Aufladen und
## Loslassen, Trefferpunkt am Ball mit dem rechten Stick, Block mit dem linken Stick.

signal big_hit(strength: float)
## Fuer Geraeusche und Effekte: Ballkontakt (serve, bump, set, spike, tip, block, net, floor).
signal contact(kind: String, pos: Vector3, strength: float)
signal point_won(winner: int, reason: String, highlight: bool)
## Jede Ballberuehrung mit Ergebnis (fuer den Debug-Modus): Art, Team, Mensch?, Qualitaet, Timing (s),
## Ballgeschwindigkeit danach und davor (m/s).
signal touch_result(kind: String, team: int, human: bool, q: int, e: float, speed: float, speed_in: float)
## Skill-Gap (Arbeitsplan): erkannte Technik nach einem Kontakt (Schluessel wie in TechNames),
## Technik ist in dieser Lage gerade moeglich (fuer den einmaligen Tastenhinweis) und
## jeder Kontakt mit kind, key, lane, target, tempo, quality (fuer die KI, die mitzaehlt).
signal technique_done(player: VPlayer, key: String)
signal technique_available(key: String)
signal touch_logged(team: int, info: Dictionary)
## Dein eigener Block (fuer Klang, Halle und Controller-Rumpeln): full = voller Block.
signal own_block(full: bool, pos: Vector3)
signal play_called(team: int, call: String)  # V-1: Spielzug angesagt ("" = zurueckgenommen)

const G := 9.81
const R := Ballistics.BALL_R
const NET_H := 2.43  # Maenner
const NET_BOTTOM := 1.43
const HALF_L := 9.0
const HALF_W := 4.5
const H_PASS := 0.85
const H_SET := 2.1
const H_ATTACK := 3.25
const JUMP_RISE := 0.404
const SET_POINTS := 25
const DECIDING_POINTS := 15

const SLOW := 0.35  # Tempo in der Zeitlupe
const CHARGE_FULL := 0.6  # Sekunden (Echtzeit) bis zur vollen Kraft
const OVERCHARGE := 1.25  # ab hier ist der Schlag ueberzogen
## Schmale Zone im Kraftbalken: wer hier loslaesst und perfekt trifft, schlaegt mit voller Wucht.
const SUPER_LO := 0.93
const SUPER_HI := 1.07
const SUPER_SPIKE_U := 34.5  # m/s, etwa 124 km/h
const OVER_OK := 12.0  # bis zu dieser Ballgeschwindigkeit (m/s) ist Pritschen sicher
const OVER_RISKY := 17.0  # darueber droht "Ball gehalten"

## Namen und Trikots kommen aus teams/*.tres (siehe Teams, TeamStyle).
var TEAM_NAMES: Array = Teams.playing().map(func(t): return t.name)
var TEAM_COLORS: Array = Teams.playing().map(func(t): return t.jersey)
var LIBERO_COLORS: Array = Teams.playing().map(func(t): return t.libero_jersey)
## Positionen je Spielsituation (lokal: Abstand zum Netz, seitlich; negativ = links).
## Beim Aufschlag und der Annahme stehen alle in Rotationsreihenfolge (Position 1 bis 6),
## damit die Aufstellung regelgerecht ist (keine Ueberlappung). Danach laufen die
## Vorderspieler auf ihre Angriffsbahn (links Aussen, Mitte, rechts Diagonal/Zuspieler).
const GRID := {
	"serve": {1: Vector2(10.0, 2.5), 2: Vector2(2.0, 3.0), 3: Vector2(2.0, 0.0), 4: Vector2(2.0, -3.0), 5: Vector2(6.5, -3.0), 6: Vector2(7.0, 0.0)},
	"receive": {1: Vector2(6.0, 3.0), 2: Vector2(1.8, 3.4), 3: Vector2(1.6, -0.4), 4: Vector2(3.0, -3.4), 5: Vector2(6.0, -3.0), 6: Vector2(6.4, 0.0)},
}
const FORM := {
	"defense": {"front": {"left": Vector2(0.6, -3.0), "mid": Vector2(0.6, 0.0), "right": Vector2(0.6, 3.0)},
		"back": {5: Vector2(6.5, -3.2), 6: Vector2(7.8, 0.0), 1: Vector2(6.5, 3.2)}},
	"build": {"front": {"left": Vector2(3.5, -3.8), "mid": Vector2(2.6, 0.2), "right": Vector2(3.5, 3.8)},
		"back": {5: Vector2(5.5, -2.0), 6: Vector2(5.5, 0.8), 1: Vector2(5.5, 3.0)}, "S": Vector2(0.9, 1.0)},
	"cover": {"front": {"left": Vector2(2.5, -3.0), "mid": Vector2(2.2, 0.0), "right": Vector2(2.5, 3.0)},
		"back": {5: Vector2(4.2, -2.0), 6: Vector2(4.6, 0.0), 1: Vector2(4.2, 2.0)}, "S": Vector2(1.6, 1.0)},
}
const LANE_PREF := {"OH": -1.0, "MB": 0.0, "OP": 1.0, "S": 2.0, "L": 0.5}
const SETTER_TARGET := Vector2(1.2, 1.0)

enum Phase { INTRO, PRE_SERVE, TOSS, RALLY, POINT_PAUSE, TIMEOUT, SET_OVER, MATCH_OVER, REPLAY }
enum Q { PERFECT, GOOD, WEAK, MISS }
const Q_TEXT := ["PERFEKT!", "Gut", "Schwach", "Daneben"]
const Q_COLOR := [Color(1.0, 0.85, 0.1), Color(0.55, 1.0, 0.55), Color(1.0, 0.6, 0.3), Color(1.0, 0.3, 0.3)]
const SERVE_KIND_TEXT := ["Stand", "Sprung"]


## Die naechste Ballberuehrung, die ansteht.
class Opp:
	var team := 0
	var trick := ""  ## 5-Sterne-Move (Y gehalten): offhand, cutback, jumpset, one_arm
	var t0 := 0.0  ## Spielzeit, als dieser Kontakt geplant wurde
	var player: VPlayer = null
	var kind := ""  # pass, dig, set, attack, free
	var t := 0.0  # idealer Zeitpunkt der Beruehrung
	var point := Vector3.ZERO  # Ballposition in diesem Moment
	var speed := 0.0  # Ballgeschwindigkeit in diesem Moment
	var done := false
	var human := false
	var ai_e := 0.0
	var pending := false  # frueh gedrueckt: Beruehrung passiert im idealen Moment
	var press_e := 0.0
	var press_choice := ""
	var tech := "bump"  # bump = Baggern, over = Pritschen
	var rs := Vector2.ZERO  # Trefferpunkt am Ball (y + = oben)
	var power := 0.8
	var over := 0.0  # Aufladung beim Loslassen (> 1 = ueberzogen)
	var win_scale := 1.0  # Timing-Fenster groesser (> 1) oder kleiner (< 1)
	var no_reach := false  # KI-Abwehr kommt nicht mehr rechtzeitig hin
	var start_pos := Vector3.ZERO
	var max_run := 0.0
	var style := ""  # Technik (Technique), z. B. sprawl, dive_side, overhead, cross
	var style_locked := false  # kurz vor dem Kontakt steht die Technik fest
	var slack := 0.0  # Zuspiel: so viel Weg (m) hatte der Zuspieler uebrig, als der Ball kam
	var emergency := false  # Angriff aus schlechter Lage: weniger Kraft
	var pressure := 0.0  # Annahme/Abwehr: noetiger Weg / moeglicher Weg bei der Planung
	var move_dir := Vector3.ZERO  # ... und in welche Richtung er dafuer musste
	var tech_key := ""  # erkannte Technik dieses Kontakts (TechNames), "" = keine
	var finesse := false  # Angriff: L2 gehalten = Gefuehlsschlag (Roll-Shot, tiefe Ecke, Luecke)
	var approach := ""  # Angriff: Anlauf wide, tight, delay ("" = automatisch wie bisher)
	var approach_z := 0.0  # seitlicher Versatz des Anlaufstarts (Welt-z)
	var delayed := false  # Anlauf schon verzoegert
	var offered := false  # Tastenhinweise fuer diesen Kontakt schon angeboten
	# Annahme steuerbar (Reception): rechter Stick, frontal, Hecht von Hand
	var aim := Vector2.ZERO  # rechter Stick bei der Annahme (x seitlich, y Richtung Netz)
	var dove := false  # mit B gehechtet
	var launched := false  # echter Hechtflug zu diesem Ball laeuft (Reichweite = Arme aus dem Flug)
	var dive_e := 0.0  # Timing des Hechts (s, < 0 = frueh)
	var square := false  # frontal hinter dem Ball
	var recv_keys: Array = []  # erkannte Annahme-Techniken (pass_flat, square, dive, ...)
	var hinted := false  # Tastenhinweis fuer diese Annahme schon gemeldet


var phase := Phase.INTRO
var clock := 0.0
var players: Array = [[], []]
var ball: Node3D
var ball_mesh: MeshInstance3D
var _replay_jump := false
var ball_shadow: MeshInstance3D
var ball_vel := Vector3.ZERO
var ball_g := G
var flutter := 0.0
var last_shot_style := ""
var score := [0, 0]
var serving_team := 0
var possession := 0
var touches := 0
var last_toucher: VPlayer = null
var last_touch_team := -1
var last_action := ""
var net_touched := false
var opp: Opp = null
var blockers: Array = [[], []]
var block_dirs: Array = [[], []]
var block_err := [0.0, 0.0]  # wie genau der Hauptblocker zum Angreifer steht
var pass_quality := Q.GOOD
var pause_until := 0.0
var toss_time := -1.0
var serve_done := false
var serve_time := -1.0
var serve_ideal := 0.0
var serve_kind := 1  # 0 Stand, 1 Sprung
var serve_contact := Vector2.ZERO
var ai_serve_e := 0.0
var serve_aim := Vector2(5.5, 0.0)
## Laufhilfe (Hilfe-Bereich "run"): an = der Spieler laeuft von selbst zum Ball.
var assist: bool:
	get:
		return cfg.assisted("run")
	set(v):
		cfg.set_assisted("run", v)
var slowmo_on := true
var zoom_on := true
var human_team := 0
var rosters: Array = []  # TeamRoster je Team
var sets_to_win := 2
var set_no := 0
var sets_won := [0, 0]
var set_scores: Array = []  # fertige Saetze, z.B. [[25, 21], [22, 25]]
var sides := [-1.0, 1.0]  # Spielhaelfte je Team (x-Richtung), wechselt nach jedem Satz
var match_first_server := 0
var deciding := false
var quick := false  # Schnellspiel: ein Satz bis 15
var side_change_pending := false
var side_changed_deciding := false
var streak := [0, 0]  # Punkte in Folge
## K1/K2: Spielplan und Gedaechtnis je Team (siehe ai_plan.gd); wird zu Spielbeginn gebaut.
var plans: Array = [null, null]
var _r1_down_at := -10.0  # R1 zuletzt gedrueckt (Annahme nutzt R1 auch; schnelles Zuspiel nur nach neuem Druck)
var _l1_down_at := -10.0  # L1 zuletzt gedrueckt (ebenso fuer das hohe, sichere Zuspiel)
var _easy_serve := false
var _skyball := false  # 5-Sterne-Move: Skyball-Aufschlag (Y + A, Aufschlagtaktiker)
## V-1 Spielzuege: welche Angreifer laufen an und mit welchem Tempo. Der Zuspieler waehlt mit dem
## Steuerkreuz, wer den Ball bekommt; alle anderen laufen als Taeuscher mit an.
const PLAYS := {
	"quick": {"mid": "quick", "left": "high", "right": "high", "back": "high"},
	"slide": {"slide": "fast", "left": "high", "back": "high"},
	"pipe": {"pipe": "fast", "mid": "quick", "left": "high", "right": "high"},
	"combo": {"mid": "quick", "left": "fast", "right": "fast", "back": "high"},
}
const PLAY_KEYS := ["quick", "slide", "pipe", "combo"]
var play_call := ["", ""]  # angesagter Spielzug je Team ("" = keiner)
var _decoys: Array = [[], []]  # je Team: Taeuscher {pl, goal, jump_at, until, jumped}
var _net_joust := {}  # V-2: geplanter Netzkampf bei einem flachen Ball uebers Netz {a, b}
var _play_info := [{}, {}]  # letztes Zuspiel je Team: call, geo, quick_z (Taeuscher Mitte) fuer den Block
var last_trick := ""  # 5-Sterne-Move des letzten Kontakts (fuer Block und Abwehr)
var y_used := false  # Y gehalten und Spielzug angesagt (trainer.gd oeffnet dann nicht)
var _dpad_y := false  # Steuerkreuz gehoert gerade zur Spielzug-Ansage (Y gehalten)  # A beim Aufschlag: sicherer Aufschlag, das Spiel trifft selbst
var _human_stuff := false  # dein voller Block in diesem Ballwechsel: immer Wiederholung
var _block_auto_style := {}  # B1: Block-Technik vor dem weichen Block (L2)
var _soft_hint_opp: Opp = null
var _last_attack := {}  # letzter Angriff fuer das Gedaechtnis: team, lane, dir
var _rally_pattern: Array = []  # Ablauf des Ballwechsels (nur Messung im Autoplay)
var timeout_team := -1
var ai_timeout_wanted := [false, false]
var whistle_done := false
var serve_deadline := -1.0
var commit_miss := [false, false]  # Block falsch gelesen: kommt zu spaet
var commit_block := [false, false]  # Mensch hat vor dem Zuspiel den Block gestellt (Lesen)
var read_hit := [false, false]  # Block richtig gelesen: mehr Kill-Chance
var read_z := 0.0  # Netzposition (z), auf die der Mensch seinen Mittelblocker gestellt hat
var _stick_lock_until := -1.0  # nach dem Wechsel vom Blocker zum Abwehrspieler: Stick kurz gesperrt
var _need_neutral := false  # ... bis der linke Stick einmal losgelassen wurde
var set_q := [Q.GOOD, Q.GOOD]  # Qualitaet des letzten Zuspiels je Team (fuer den Notangriff)
var set_tempo := ["", ""]  # Tempo des letzten Zuspiels je Team (high, fast, quick)
var libero_set_front := [false, false]  # Libero hat vor der 3-m-Linie gepritscht
var trainer_wanted := false
var notice := ""  # kurzer Hinweis fuer die Anzeige (z.B. "Libero muss raus")
var notice_until := 0.0
var match_wins := [0, 0]
var matches_done := 0
var autoplay := false
var show_popups := false  # Test/Debug: --popups zeigt die alten Texte im Spiel wieder
var attract := false  # Startmenue: im Hintergrund spielt KI gegen KI
## Wiederholung: die letzten Sekunden werden aufgezeichnet (Ball, Spieler, Kontakte).
const REC_SECONDS := 5.0
var _rec: Array = []  # [clock, Ballposition, [Spielerzustaende]]
var _rec_events: Array = []  # [clock, Art, Position, Staerke]
var _rally_end := -100.0
var replay_pending := false
var _replay: Array = []
var _replay_ev: Array = []
var _replay_i := 0
var _replay_ev_i := 0
var _replay_t := 0.0
var _replay_live: Array = []
var rally_touches := 0
var points_since_replay := 99
var last_attack_speed := 0.0
var last_super := false  # letzter Angriff / Aufschlag war ein Wuchtschlag (Super-Zone)
var autoplay_rallies := 200
var trace := false
var test_score := []  # Test: Startstand des ersten Satzes, z.B. --score=24:10
var test_rot := -1  # Test: --rot=N dreht das Heimteam N-mal weiter, Gegner schlaegt auf
var check_rules := false  # Test: prueft bei jedem Aufschlag die Aufstellung
var autopress := false  # Test: drueckt fuer den Menschen automatisch
var skilled := false  # Test (mit --autopress): Koenner statt Einsteiger
var _auto_fin := false
var _auto_mv := Vector2.ZERO
var drill = null  # Debug-Modus: laufende Uebung (DebugDrill), sonst null
var recv: Reception  # Annahme steuerbar (A1, A2, A4), siehe reception.gd
var pass_kind := ["", ""]  # wie die letzte Annahme je Team gespielt wurde (pass_flat, pass_high, ...)
var pro_bot := false  # Test: --pro, der simulierte Spieler nutzt die neuen Annahme-Techniken
var hud = null
var cfg := GameSettings.new()
var rng := RandomNumberGenerator.new()

# Eingabe-Zustand des Menschen
var rs := Vector2.ZERO
var mouse_rs := Vector2.ZERO
var charging := false
var charge := 0.0
var preview_target := Vector3.ZERO
var preview_valid := false

# Kamera (wird von main.gd gelesen)
var cam_mode := ""
var block_at := -10.0  # Spielzeit der letzten Blockberuehrung (Kamera geht danach in die Weite)
var cam_subject: VPlayer = null
var _slow_tail_until := 0.0
var _hitstop_left := 0.0
var _hitstop_scale := SLOW  # wie langsam der Treffer-Stopp ist
var _after_stop := false  # nach dem Treffer-Stopp schnell (nicht gummiartig) zurueck zum Tempo
var _time_scale := 1.0  # gleitet weich zur gewuenschten Zeitlupe

var _ring_target: MeshInstance3D
var _ring_target_mat: StandardMaterial3D
var _ring_timer: MeshInstance3D
var _ring_timer_mat: StandardMaterial3D
var _aim_marker: MeshInstance3D
var _shadow_mesh: ImmediateMesh
var _shadow_node: MeshInstance3D

# Statistik fuer den automatischen Test
var stats := {}
## Pro Team in diesem Spiel: Asse, Blockpunkte, Wuchtschlaege, groesster Satzvorsprung (fuer Mein Verein).
var mstat := [{}, {}]
var rally_count := 0
var touch_total := 0


func _ready() -> void:
	rng.randomize()
	recv = Reception.new(self)
	if not OS.get_cmdline_user_args().has("--autoplay"):
		cfg.load_file()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--home="):
			Teams.home = a.get_slice("=", 1)  # Test: Teams waehlen
		elif a.begins_with("--away="):
			Teams.away = a.get_slice("=", 1)
	HumanFigure.preload_data()
	for t in 2:
		_spawn_team(t)
	_make_ball()
	_make_markers()
	for a in OS.get_cmdline_user_args():
		if a == "--autoplay":
			autoplay = true
		elif a.begins_with("--rallies="):
			autoplay_rallies = int(a.get_slice("=", 1))
		elif a == "--demo":
			human_team = -1
		elif a == "--autopress":
			autopress = true
			autoplay = true
		elif a == "--skilled":
			skilled = true  # Test (mit --autopress): simulierter Koenner (genaues Timing, Anlauf, Gefuehlsschlaege)
		elif a == "--botplay":
			autopress = true  # wie --autopress, aber mit Kamera, Zeitlupe und Anzeigen
		elif a == "--trace":
			trace = true
		elif a == "--popups":
			show_popups = true
		elif a == "--pro":
			pro_bot = true
		elif a.begins_with("--rot="):
			test_rot = int(a.get_slice("=", 1))
		elif a == "--check":
			check_rules = true
		elif a.begins_with("--seed="):
			rng.seed = int(a.get_slice("=", 1))
		elif a.begins_with("--score="):
			test_score = [int(a.get_slice("=", 1).get_slice(":", 0)), int(a.get_slice("=", 1).get_slice(":", 1))]
		elif a.begins_with("--sets="):
			cfg.sets_to_win = clampi(int(a.get_slice("=", 1)), 1, 3)
		elif a.begins_with("--stufe="):
			cfg.apply_preset(a.get_slice("=", 1))
	if autoplay:
		human_team = 0 if autopress else -1
		Engine.time_scale = 12.0
		Engine.max_physics_steps_per_frame = 64
		new_match()
	elif human_team < 0 or autopress:
		new_match()
	else:
		# Startmenue: dahinter laeuft ein Spiel KI gegen KI, bis du "Spielen" waehlst.
		attract = true
		human_team = -1
		new_match()


func _input(event: InputEvent) -> void:
	# Maus als rechter Stick: Bewegung verschiebt den Trefferpunkt.
	if event is InputEventMouseMotion:
		mouse_rs += Vector2(event.relative.x, -event.relative.y) * 0.008
		mouse_rs = mouse_rs.limit_length(1.0)


# ---------------------------------------------------------------- Aufbau

func _spawn_team(team: int) -> void:
	var r := TeamRoster.new(team)
	rosters.append(r)
	for i in 6:
		var mm: Dictionary = r.m(r.lineup[i])
		var pl := VPlayer.new()
		_apply_data(pl, mm)
		pl.setup(team, mm.role, TeamRoster.ROLE_TAG[mm.role], mm.number, _jersey(team, mm.role))
		pl.member_id = mm.id
		pl.slot = i + 1
		pl.set_side(side_of(team))
		add_child(pl)
		players[team].append(pl)
		var p := court_pos(team, GRID["receive"][i + 1])
		pl.position = p
		pl.target = p
	_assign_lanes(team)


func _jersey(team: int, role: String) -> Color:
	return LIBERO_COLORS[team] if role == "L" else TEAM_COLORS[team]


## Spielerdaten der Figur (null: Spieler ohne Daten, verhaelt sich in allem wie Staerke 70).
func pdata(pl: VPlayer) -> PlayerData:
	if pl == null or pl.member_id < 0 or pl.team >= rosters.size():
		return null
	return rosters[pl.team].m(pl.member_id).get("data")


## Staerke als Abweichung vom normalen Spieler (-1 schwach, 0 normal, +1 Weltklasse).
func pf(pl: VPlayer, key: String) -> float:
	var d := pdata(pl)
	return d.f(key) if d else 0.0


func ptrait(pl: VPlayer, t: String) -> bool:
	var d := pdata(pl)
	return d != null and d.has_trait(t)


## 5-Sterne-Moves: welcher PlayStyle gehoert zu welchem Move.
const TRICK_STYLE := {"offhand": "beidhaender", "cutback": "winkel", "jumpset": "sprungzuspiel", "skyball": "taktiker", "one_arm": "hecht"}


func _trick_ok(pl: VPlayer, trick: String) -> bool:
	return pl != null and pls(pl, TRICK_STYLE[trick]) > 0.0


## Trick vormerken: engeres Timing-Fenster (mit Plus weniger eng), eigene Bewegung.
func _set_trick(o: Opp, trick: String) -> void:
	o.trick = trick
	o.player.anim_style = trick
	if o.kind != "attack":
		o.win_scale *= _trick_window(o)
	stats["Move " + trick] = stats.get("Move " + trick, 0) + 1
	if trace or autoplay:
		print("MOVE %s %s tick=%d" % [trick, o.player.name, Engine.get_physics_frames()])


func _trick_window(o: Opp) -> float:
	if o.trick == "":
		return 1.0
	return 0.78 if pls(o.player, TRICK_STYLE[o.trick]) < 2.0 else 0.9


## PlayStyle-Stufe eines Spielers (0 = keiner, 1 = PlayStyle, 2 = PlayStyle+), siehe play_styles.gd.
func pls(pl: VPlayer, id: String) -> float:
	var d := pdata(pl)
	return float(d.style(id)) if d != null else 0.0


## Zeit vom Absprung bis zum hoechsten Punkt (haengt von der Sprungkraft ab).
func rise(pl: VPlayer) -> float:
	return pl.jump_v0 / G if pl else JUMP_RISE


## Groesse und Sprungkraft auf die Figur uebertragen, vor setup / change_identity.
func _apply_data(pl: VPlayer, mm: Dictionary) -> void:
	var d: PlayerData = mm.get("data")
	pl.reach_add = d.reach_add() if d else 0.0
	pl.jump_v0 = d.jump_v() if d else VPlayer.JUMP_V
	pl.movement_style = (d.movement_style if d.movement_style != "" else d.id) if d else ""
	pl.height_m = d.height_m if d else 0.0
	pl.left_handed = d.left_handed if d else false


## Spielerfigur bekommt einen anderen Spieler aus dem Kader (Wechsel, Libero).
func _apply_identity(pl: VPlayer, member_id: int) -> void:
	var mm: Dictionary = rosters[pl.team].m(member_id)
	pl.member_id = member_id
	_apply_data(pl, mm)
	pl.change_identity(mm.role, TeamRoster.ROLE_TAG[mm.role], mm.number, _jersey(pl.team, mm.role))


## Positionsnummern und Angriffsbahnen aus der Aufstellung uebernehmen.
func _sync_slots(t: int) -> void:
	for pl in players[t]:
		pl.slot = rosters[t].slot_of(pl.member_id)
	_assign_lanes(t)


## Vorderspieler von links nach rechts: Aussen, Mitte, Diagonal. Der Zuspieler hat eine eigene
## Bahn. Hinterfeldspieler (ausser Libero) koennen aus dem Hinterfeld angreifen.
func _assign_lanes(t: int) -> void:
	var r: TeamRoster = rosters[t]
	var front: Array = []
	for pl in players[t]:
		pl.lane = ""
		if r.is_front(pl.slot):
			front.append(pl)
	front.sort_custom(func(a, b): return LANE_PREF[a.role] < LANE_PREF[b.role])
	var hitters: Array = front.filter(func(p): return p.role != "S")
	var names := ["left", "mid", "right"] if hitters.size() >= 3 else ["left", "mid"]
	for i in hitters.size():
		hitters[i].lane = names[mini(i, names.size() - 1)]
	for pl in players[t]:
		if pl.role == "S":
			pl.lane = "setter"
		elif pl.lane == "" and pl.role != "L" and not r.is_front(pl.slot):
			pl.lane = "back"


func player_at_slot(team: int, slot: int) -> VPlayer:
	for pl in players[team]:
		if pl.slot == slot:
			return pl
	return null


func _lane_player(team: int, lane: String) -> VPlayer:
	var best: VPlayer = null
	for pl in players[team]:
		if pl.lane == lane and (best == null or (lane == "back" and pl.role == "OP")):
			best = pl
	return best


func is_front_row(pl: VPlayer) -> bool:
	return rosters[pl.team].is_front(pl.slot)


func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _make_ball() -> void:
	ball = Node3D.new()
	add_child(ball)
	VPlayer.ball_node = ball
	# Ball aus Blender (assets/models/ball.glb, r = 10,5 cm), etwas groesser gezeichnet,
	# damit man ihn gut sieht
	var src: Node3D = preload("res://assets/models/ball.glb").instantiate()
	var bm := src.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	ball_mesh = MeshInstance3D.new()
	ball_mesh.mesh = bm.mesh
	ball_mesh.scale = Vector3.ONE * (0.14 / 0.105)
	src.free()
	ball.add_child(ball_mesh)

	ball_shadow = MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.16
	c.bottom_radius = 0.16
	c.height = 0.004
	ball_shadow.mesh = c
	ball_shadow.material_override = _unshaded(Color(0, 0, 0, 0.45))
	add_child(ball_shadow)


func _torus(inner: float, outer: float, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	mi.mesh = t
	mi.material_override = _unshaded(c)
	mi.visible = false
	add_child(mi)
	return mi


## Regellinien zwischen den Spielern (nur vor dem Aufschlag, nur fuer das Team des Menschen).
var _form_lines: Array = []


func _make_form_lines() -> void:
	for i in Formation.PAIRS.size():
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		var m := _unshaded(Color(1, 1, 1, 0.85))
		m.no_depth_test = false
		mi.material_override = m
		mi.visible = false
		add_child(mi)
		_form_lines.append(mi)


func _update_form_lines() -> void:
	var show := human_team >= 0 and (phase == Phase.PRE_SERVE or phase == Phase.TOSS)
	if show:
		var t := human_team
		var serving := t == serving_team
		var spots: Dictionary = {}
		for pl in players[t]:
			spots[pl.slot] = team_local(t, pl.position)
		var ls := Formation.links(spots, [1] if serving else [])
		for i in _form_lines.size():
			var mi: MeshInstance3D = _form_lines[i]
			if i >= ls.size():
				mi.visible = false
				continue
			var l: Dictionary = ls[i]
			var a := court_pos(t, l.a)
			var b := court_pos(t, l.b)
			var mid := (a + b) * 0.5
			var len := a.distance_to(b)
			var dir := (b - a).normalized()
			mi.position = Vector3(mid.x, 0.025, mid.z)
			mi.rotation = Vector3(0, atan2(-dir.z, dir.x), 0)
			mi.scale = Vector3(len, 0.01, 0.13)
			var col := Color(1.0, 0.82, 0.2, 0.9) if l.kind == "lat" else Color(0.45, 0.92, 1.0, 0.9)
			(mi.material_override as StandardMaterial3D).albedo_color = col
			mi.visible = true
	else:
		for mi in _form_lines:
			mi.visible = false


func _make_markers() -> void:
	_make_form_lines()
	_ring_target = _torus(0.42, 0.5, Color(1, 1, 1, 0.9))
	_ring_target_mat = _ring_target.material_override
	_ring_timer = _torus(0.44, 0.52, Color(1.0, 0.85, 0.1))
	_ring_timer_mat = _ring_timer.material_override
	_aim_marker = _torus(0.25, 0.4, Color(1.0, 0.3, 0.25, 0.9))
	_shadow_mesh = ImmediateMesh.new()
	_shadow_node = MeshInstance3D.new()
	_shadow_node.mesh = _shadow_mesh
	var sm := _unshaded(Color(0.05, 0.1, 0.35, 0.42))
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shadow_node.material_override = sm
	add_child(_shadow_node)


# ---------------------------------------------------------------- Hilfen

func side_of(team: int) -> float:
	return sides[team]


## Auf welcher Seite die Kamera steht: hinter dem Team des Spielers.
func camera_side() -> float:
	return side_of(human_team if human_team >= 0 else 0)


## Welches Team spielt auf der Seite, auf der x liegt?
func team_at_x(x: float) -> int:
	return 0 if (x < 0.0) == (sides[0] < 0.0) else 1


func court_pos(team: int, v: Vector2) -> Vector3:
	var s := side_of(team)
	return Vector3(s * v.x, 0.0, -s * v.y)


func team_local(team: int, p: Vector3) -> Vector2:
	var s := side_of(team)
	return Vector2(s * p.x, -s * p.z)


func player_by_role(team: int, role: String) -> VPlayer:
	for pl in players[team]:
		if pl.role == role:
			return pl
	return null


func server() -> VPlayer:
	return player_at_slot(serving_team, 1)


func flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Timing-Fehler als Richtung: -1 = ganz zu frueh, 0 = genau, +1 = ganz zu spaet (Rand des Fensters).
## Daraus folgt, wohin ein ungenauer Ball geht: kein Wuerfeln, sondern aus dem eigenen Timing.
func _err_dir(e: float, kind: String, scale := 1.0) -> float:
	return clampf(e / (windows(kind)[2] * scale), -1.0, 1.0)


## Liegt nach Hecht, Sprawl oder Pancake noch am Boden bzw. steht gerade auf.
func is_down(pl: VPlayer) -> bool:
	return pl.down_until > clock


func windows(kind: String) -> Array:
	if kind == "dig":
		return [0.065, 0.13, 0.2]
	if kind == "serve":
		return [0.06, 0.11, 0.18]
	return [0.055, 0.1, 0.16]


## Timing-Fehler ausserhalb des Perfekt-Fensters; nur der verschiebt den Ball.
func excess(e: float, kind: String, scale := 1.0) -> float:
	var w0: float = windows(kind)[0] * scale
	return signf(e) * maxf(0.0, absf(e) - w0)


## Zeitpunkt eines Tastendrucks des Menschen: Bildschirm und Controller zeigen alles etwas
## spaeter, als es passiert. Der Timing-Ausgleich (Menue) rechnet diese Verzoegerung heraus.
func human_clock() -> float:
	return clock - lag_game()


## Eingabe-Verzoegerung in Spielzeit (in der Zeitlupe entsprechend kleiner).
func lag_game() -> float:
	if autopress:
		return 0.0  # Testmodus: simulierte Eingaben haben keine Verzoegerung
	return cfg.get_v("input_lag") / 1000.0 * Engine.time_scale


## Kurzer Hinweis, ob zu frueh oder zu spaet (damit man sein Timing lernt).
func timing_hint(e: float, q: int) -> String:
	if q == Q.PERFECT or q == Q.MISS:
		return ""
	return " · früh" if e < 0.0 else " · spät"


func classify(e: float, kind: String, scale := 1.0) -> int:
	var w := windows(kind)
	var a := absf(e) / scale
	if a <= w[0]:
		return Q.PERFECT
	if a <= w[1]:
		return Q.GOOD
	if a <= w[2]:
		return Q.WEAK
	return Q.MISS


## Mehr Kraft und ein Trefferpunkt weit weg von der Mitte machen das Timing-Fenster enger.
func hit_window_scale(power: float, contact: Vector2, jump: bool) -> float:
	var s := lerpf(1.35, 0.95, clampf(power, 0.0, 1.0))
	s *= 1.0 - 0.12 * minf(contact.length(), 1.0)
	if jump:
		s *= 0.95
	return s


## Zufaelliger Timing-Fehler fuer die KI.
func ai_e(kind: String) -> float:
	var p := [0.4, 0.85, 0.98]
	match kind:
		"serve":
			p = [0.3, 0.78, 0.96]
		"dig":
			p = [0.25, 0.6, 0.85]
		"attack":
			p = [0.4, 0.85, 0.97]
		"set":
			p = [0.45, 0.9, 0.99]
	var w := windows(kind)
	var r := rng.randf()
	var lo := 0.0
	var hi: float = w[0]
	if r >= p[2]:
		lo = w[2] + 0.01
		hi = w[2] + 0.1
	elif r >= p[1]:
		lo = w[1]
		hi = w[2]
	elif r >= p[0]:
		lo = w[0]
		hi = w[1]
	var mag := rng.randf_range(lo, hi)
	return mag if rng.randf() < 0.5 else -mag


var _pops: Array = []  # lebende Popup-Labels, aeltestes zuerst


func popup(pl: VPlayer, text: String, color: Color) -> void:
	if autoplay or attract:
		return
	# Kein Text im Spiel (wie bei FIFA): Timing und Technik spuert man ueber Rumble, Ton,
	# Ballflug und den Ring am Spieler. Die Texte bleiben nur fuer die Debug-Uebungen.
	if not show_popups and (drill == null or phase == Phase.RALLY):
		return
	# Lebende Popups: das alte Popup desselben Spielers weicht dem neuen, alle anderen
	# werden gestapelt, damit nie Text auf Text liegt.
	_pops = _pops.filter(func(x): return is_instance_valid(x))
	for old in _pops.duplicate():
		if old.get_meta("pl") == pl:
			_pops.erase(old)
			old.queue_free()
	while _pops.size() >= 4:
		_pops.pop_front().queue_free()
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 48
	l.outline_size = 12
	l.pixel_size = 0.005
	l.modulate = color
	l.set_meta("pl", pl)
	add_child(l)
	var slot := 0
	for o in _pops:
		if absf(o.position.x - pl.position.x) < 3.0:
			slot += 1
	_pops.append(l)
	l.position = pl.position + Vector3(0, 2.8 + 0.5 * slot, 0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y + 0.6, 0.9)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


# ---------------------------------------------------------------- Ablauf

func new_match() -> void:
	sets_to_win = 1 if quick else cfg.sets_to_win
	sets_won = [0, 0]
	set_scores = []
	set_no = 0
	mstat = [{}, {}]
	sides = [-1.0, 1.0]
	match_first_server = rng.randi() % 2  # Auslosung
	plans = [null, null]
	_start_set()
	_scouting_banner()


## Aus dem Startmenue: neues Spiel mit dir als Team 0, frische Kader.
func start_game() -> void:
	_abort_replay()
	attract = false
	human_team = 0
	quick = Teams.quick
	for t in 2:
		rosters[t] = TeamRoster.new(t)
	new_match()


func back_to_title() -> void:
	_abort_replay()
	attract = true
	human_team = -1
	quick = false
	for t in 2:
		rosters[t] = TeamRoster.new(t)
	new_match()


func set_target() -> int:
	return DECIDING_POINTS if deciding else SET_POINTS


func _start_set() -> void:
	set_no += 1
	deciding = quick or (sets_to_win >= 2 and sets_won[0] == sets_to_win - 1 and sets_won[1] == sets_to_win - 1)
	if set_no > 1:
		sides = [-sides[0], -sides[1]]  # Seitenwechsel nach jedem Satz
	var first := match_first_server if set_no % 2 == 1 else 1 - match_first_server
	if deciding:
		first = rng.randi() % 2  # neue Auslosung im Entscheidungssatz
	score = [0, 0]
	if set_no == 1 and test_score.size() == 2:
		score = test_score.duplicate()
	serving_team = first
	streak = [0, 0]
	side_change_pending = false
	side_changed_deciding = false
	ai_timeout_wanted = [false, false]
	libero_set_front = [false, false]
	for t in 2:
		rosters[t].new_set()
		if t == 0 and test_rot >= 0:
			for _i in test_rot:
				rosters[t].rotate()
			serving_team = 1
		for j in 6:
			_apply_identity(players[t][j], rosters[t].lineup[j])
			players[t][j].set_side(side_of(t))
		_sync_slots(t)
		_libero_auto_in(t)  # der Libero steht zu Satzbeginn auf dem Feld
	if hud:
		hud.clear_message()
		hud.ref_signal([["serve_" + str(first), "Aufschlag " + TEAM_NAMES[first], 1.6]])
	start_rally()


var _lines_hint_shown := false


func start_rally() -> void:
	if drill != null:
		drill.before_rally()  # Debug-Uebung: wer aufschlaegt, Rotation
	phase = Phase.PRE_SERVE
	if human_team >= 0 and not _lines_hint_shown and not autoplay:
		_lines_hint_shown = true
		_notice("Linien verbinden die Nachbarn: nicht überschreiten")
	opp = null
	blockers = [[], []]
	block_dirs = [[], []]
	play_call = ["", ""]
	_decoys = [[], []]
	_net_joust = {}
	_play_info = [{}, {}]
	touches = 0
	possession = serving_team
	last_toucher = null
	last_touch_team = serving_team
	last_action = ""
	net_touched = false
	serve_done = false
	serve_time = -1.0
	toss_time = -1.0
	charging = false
	charge = 0.0
	mouse_rs = Vector2.ZERO
	ball_g = G
	flutter = 0.0
	whistle_done = false
	serve_deadline = -1.0
	libero_set_front = [false, false]
	commit_block = [false, false]
	rally_touches = 0
	last_attack_speed = 0.0
	last_super = false
	_rec.clear()
	_rec_events.clear()
	for t in 2:
		_prepare_lineup(t)
	for t in 2:
		var form := "serve" if t == serving_team else "receive"
		for pl in players[t]:
			var p := formation_pos(t, pl, form)
			# Wer nah genug steht, laeuft in die Aufstellung, statt hinzuspringen.
			if flat_dist(pl.position, p) > 4.5 or autoplay:
				pl.position = p
			pl.target = p
			pl.reset_state()
	if check_rules:
		_check_rules()
	ball_vel = Vector3.ZERO
	_hold_ball_at_server()
	reset_physics_interpolation()
	pause_until = clock + (0.15 if autoplay else 0.9)
	if human_serves():
		serve_aim = Vector2(5.5, 0.0)
	else:
		_ai_serve_choice()
	if hud:
		hud.clear_message()
	for t in 2:
		if t != human_team and ai_timeout_wanted[t] and rosters[t].timeouts_left > 0:
			ai_timeout_wanted[t] = false
			call_timeout(t)
			break
	if drill != null:
		drill.after_rally_setup()  # Debug-Uebung: Aufschlagart, Zuwurf vom Trainer


## Testhilfe (--check): meldet jede Verletzung der Aufstellungsregeln.
func _check_rules() -> void:
	for t in 2:
		var r: TeamRoster = rosters[t]
		var bad := ""
		var ids := {}
		for id in r.lineup:
			ids[id] = true
		if ids.size() != 6:
			bad += " doppelte Spieler;"
		if r.libero_illegal():
			bad += " Libero vorn oder auf Position 1;"
		var srv := player_at_slot(t, 1)
		if srv == null or srv.role == "L":
			bad += " Aufschlaeger fehlt oder ist Libero;"
		var fronts := 0
		for pl in players[t]:
			if pl.slot != r.slot_of(pl.member_id) or pl.slot < 1:
				bad += " Figur %d hat falsche Position;" % pl.member_id
			if r.is_front(pl.slot):
				fronts += 1
				if pl.role == "L":
					bad += " Libero in der Vorderreihe;"
		if fronts != 3:
			bad += " %d Vorderspieler;" % fronts
		if _lane_player(t, "mid") == null and player_by_role(t, "S") != null:
			bad += " keine Mittelbahn;"
		var roles := {}
		for pl in players[t]:
			roles[pl.role] = roles.get(pl.role, 0) + 1
		if roles.get("S", 0) != 1 or roles.get("L", 0) > 1:
			bad += " Rollen %s;" % str(roles)
		var spots := {}
		for pl in players[t]:
			spots[pl.slot] = team_local(t, pl.target)
		var viol := Formation.violations(spots, [1] if t == serving_team else [])
		if not viol.is_empty():
			bad += " Stellungsfehler %s;" % str(viol)
		if bad != "":
			print("REGELFEHLER T%d Satz %d %d:%d:%s lineup=%s" % [t, set_no, score[0], score[1], bad, str(r.lineup)])
		if trace:
			for pl in players[t]:
				print("  POS T%d P%d %s%d z=%.1f x=%.1f" % [t, pl.slot, pl.role, pl.number, pl.target.z, pl.target.x])
			print("AUFSTELLUNG T%d Satz %d %d:%d P1..6=%s libero=%d" % [t, set_no, score[0], score[1], str(r.lineup), r.libero_on])


## Annahme-Aufstellung des Teams (Position -> lokaler Punkt), regelgerecht und je Rotation anders.
## Wird nur neu berechnet, wenn sich die Rollen auf den Positionen aendern.
var _rcv_cache := [{}, {}]


func _receive_spots(t: int) -> Dictionary:
	var roles := {}
	var sig := ""
	for pl in players[t]:
		roles[pl.slot] = pl.role
	for s in range(1, 7):
		sig += str(roles.get(s, "-"))
	var c: Dictionary = _rcv_cache[t]
	if c.get("sig", "") != sig:
		c = {"sig": sig, "spots": Formation.receive_spots(roles), "passers": Formation.passer_slots(roles)}
		_rcv_cache[t] = c
	return c["spots"]


## Annahme-Verantwortung: Libero zuerst, dann Aussenangreifer, die uebrigen nur im Notfall.
func _receiver_weight(pl: VPlayer) -> float:
	_receive_spots(pl.team)
	if pl.role == "L":
		return 0.8
	if _rcv_cache[pl.team]["passers"].has(pl.slot):
		return 1.0
	return 1.8


## Position eines Spielers in einer Spielsituation (Welt-Koordinaten).
func formation_pos(t: int, pl: VPlayer, form: String) -> Vector3:
	var v: Vector2
	if form == "serve" or form == "receive":
		v = GRID[form][pl.slot]
		if form == "receive":
			v = _receive_spots(t)[pl.slot]
	else:
		var f: Dictionary = FORM[form]
		if pl.role == "S" and f.has("S"):
			v = f["S"]
		elif rosters[t].is_front(pl.slot):
			var lane: String = pl.lane if pl.lane in ["left", "mid", "right"] else "right"
			v = f["front"][lane]
		else:
			v = f["back"][pl.slot]
	return court_pos(t, v)


# ---------------------------------------------------------------- Libero, Wechsel, Auszeit

## Vor jedem Ballwechsel: unerlaubter Libero muss raus, KI-Teams (und "automatisch") wechseln
## den Libero selbst ein, die KI wechselt gelegentlich Spieler.
func _prepare_lineup(t: int) -> void:
	var r: TeamRoster = rosters[t]
	if r.libero_illegal():
		var lib: String = r.m(r.libero_on).name
		_libero_out(t)
		if t == human_team:
			_notice("Libero %s muss raus: Er darf nur im Hinterfeld spielen und nicht aufschlagen" % lib)
	if t != human_team or cfg.libero_auto:
		_libero_auto_in(t)
	if t != human_team:
		_ai_maybe_sub(t)


func _notice(text: String) -> void:
	notice = text
	notice_until = clock + 5.0


func _figure_of(t: int, member_id: int) -> VPlayer:
	for pl in players[t]:
		if pl.member_id == member_id:
			return pl
	return null


func _libero_auto_in(t: int) -> void:
	var r: TeamRoster = rosters[t]
	var slot := r.auto_libero_slot()
	if slot > 0:
		libero_enter(t, slot, r.libero_ids()[0])


## Libero kommt fuer den Spieler auf `slot` ins Spiel. Gibt einen Fehlertext zurueck (leer = ok).
func libero_enter(t: int, slot: int, libero_id: int) -> String:
	var r: TeamRoster = rosters[t]
	if not r.can_libero_enter(slot):
		return "Der Libero kann dort nicht rein (nur Hinterfeld, nicht auf Position 1)"
	var out_id: int = r.lineup[slot - 1]
	var pl := _figure_of(t, out_id)
	r.libero_enter(slot, libero_id)
	_apply_identity(pl, libero_id)
	_sync_slots(t)
	_sub_banner(t, "Libero rein", libero_id, out_id, 3.0)
	return ""


## Einblendung unten links: wer kommt, wer geht (auch beim Gegner).
func _sub_banner(t: int, what: String, in_id: int, out_id: int, secs: float) -> void:
	if hud == null or autoplay:
		return
	var r: TeamRoster = rosters[t]
	var a: Dictionary = r.m(in_id)
	var b: Dictionary = r.m(out_id)
	hud.show_sub(t, TEAM_NAMES[t], what, "#%d %s" % [a.number, a.name], "#%d %s" % [b.number, b.name], secs)


func _libero_out(t: int) -> void:
	var r: TeamRoster = rosters[t]
	var lib_id := r.libero_on
	var back := r.libero_leave()
	_apply_identity(_figure_of(t, lib_id), back)
	_sync_slots(t)
	_sub_banner(t, "Libero raus", back, lib_id, 3.0)


func libero_leave(t: int) -> String:
	if rosters[t].libero_on < 0:
		return "Der Libero ist nicht auf dem Feld"
	_libero_out(t)
	return ""


func substitute(t: int, out_id: int, in_id: int) -> String:
	var r: TeamRoster = rosters[t]
	var err := r.sub_error(out_id, in_id)
	if err != "":
		return err
	var pl := _figure_of(t, out_id)
	r.substitute(out_id, in_id)
	stats["Wechsel " + TEAM_NAMES[t]] = stats.get("Wechsel " + TEAM_NAMES[t], 0) + 1
	_apply_identity(pl, in_id)
	_sync_slots(t)
	_sub_banner(t, "Wechsel", in_id, out_id, 5.0)
	if hud:
		hud.ref_signal([["sub", "Wechsel %s: %s kommt für %s" % [TEAM_NAMES[t], r.m(in_id).name, r.m(out_id).name], 1.6]])
		hud.whistle(false)
	return ""


## Trainerbank (Libero, Wechsel, Auszeit): nur bei toter Kugel, vor dem Anpfiff zum Aufschlag.
func can_use_trainer() -> bool:
	return human_team >= 0 and not autoplay and ((phase == Phase.PRE_SERVE and not whistle_done) or phase == Phase.TIMEOUT)


func call_timeout(t: int) -> String:
	if phase != Phase.PRE_SERVE or whistle_done:
		return "Auszeit nur vor dem Aufschlag"
	var r: TeamRoster = rosters[t]
	if r.timeouts_left <= 0:
		return "Keine Auszeiten mehr in diesem Satz"
	r.timeouts_left -= 1
	stats["Auszeit " + TEAM_NAMES[t]] = stats.get("Auszeit " + TEAM_NAMES[t], 0) + 1
	timeout_team = t
	phase = Phase.TIMEOUT
	pause_until = clock + (0.3 if autoplay else 8.0)
	if hud:
		hud.whistle(false)
		hud.ref_signal([["timeout", "Auszeit %s" % TEAM_NAMES[t], 8.0]])
	return ""


func _end_timeout() -> void:
	if timeout_team < 0:
		start_rally()  # Pause vom Seitenwechsel: danach ganz normal weiter
		return
	timeout_team = -1
	phase = Phase.PRE_SERVE
	pause_until = clock + (0.15 if autoplay else 1.0)
	if hud:
		hud.clear_message()
		hud.ref_signal([])


## KI-Trainer: wechselt gelegentlich einen Spieler gegen einen Ersatz mit gleicher Rolle.
func _ai_maybe_sub(t: int) -> void:
	var r: TeamRoster = rosters[t]
	if r.subs_used >= 3 or score[0] + score[1] < 10 or rng.randf() > 0.04:
		return
	var outs: Array = r.lineup.duplicate()
	outs.shuffle()
	for out_id in outs:
		if r.m(out_id).role == "L":
			continue
		for in_id in r.bench():
			if r.m(in_id).role == r.m(out_id).role and r.sub_error(out_id, in_id) == "":
				substitute(t, out_id, in_id)
				return


func _hold_ball_at_server() -> void:
	var s := server()
	ball.position = s.position + Vector3(-side_of(serving_team) * 0.4, 1.3, 0.0)


func _empty_input() -> Dictionary:
	return {"mv": Vector2.ZERO, "rs": Vector2.ZERO, "bump": false, "over": false, "fast": false, "quick": false, "dpad": Vector2.ZERO, "dpad_down": Vector2.ZERO, "mouse_rs": Vector2.ZERO, "dump_held": false,
		"bump_held": false, "over_held": false, "bump_up": false, "over_up": false, "dpad_up": Vector2.ZERO,
		"hit_down": false, "hit_up": false, "hit_held": false, "kind_prev": false, "kind_next": false, "finesse_held": false, "rs_pad": Vector2.ZERO, "l1_held": false, "switch": false, "play_dd": Vector2.ZERO, "trick": false}


func _read_input() -> Dictionary:
	var d := _empty_input()
	d.mv = Input.get_vector("move_left", "move_right", "move_down", "move_up")
	var stick := _held_stick(Input.get_vector("aim_left", "aim_right", "aim_down", "aim_up"))
	d.rs = stick if stick.length() > 0.15 else mouse_rs
	d.rs_pad = stick if stick.length() > 0.15 else Vector2.ZERO  # nur Stick / IJKL, ohne Maus
	d.l1_held = Input.is_action_pressed("serve_prev")  # L1: hoch und sicher (Annahme und Zuspiel)
	if Input.is_action_just_pressed("set_dump"):
		_r1_down_at = clock
	if Input.is_action_just_pressed("serve_prev"):
		_l1_down_at = clock
	d.switch = Input.is_action_just_pressed("switch_player")
	d.mouse_rs = mouse_rs
	d.dump_held = Input.is_action_pressed("set_dump")
	d.bump = Input.is_action_just_pressed("bump")
	d.over = Input.is_action_just_pressed("overhand")
	# Halten = vorbereiten (Haltung), Loslassen = Ballkontakt
	d.bump_held = Input.is_action_pressed("bump")
	d.over_held = Input.is_action_pressed("overhand")
	d.bump_up = Input.is_action_just_released("bump")
	d.over_up = Input.is_action_just_released("overhand")
	d.dpad = Input.get_vector("set_dir_left", "set_dir_right", "set_dir_down", "set_dir_up")
	# Y gehalten: das Steuerkreuz sagt einen Spielzug an und ist kein Zuspiel (bis es losgelassen ist).
	var dd_now := Vector2(
		float(Input.is_action_just_pressed("set_dir_right")) - float(Input.is_action_just_pressed("set_dir_left")),
		float(Input.is_action_just_pressed("set_dir_up")) - float(Input.is_action_just_pressed("set_dir_down")))
	if Input.is_action_just_pressed("trainer"):
		y_used = false
	if Input.is_action_pressed("trainer") and dd_now.length() > 0.5:
		_dpad_y = true
		y_used = true  # Y war fuer eine Ansage: beim Loslassen keine Trainerbank
		d.play_dd = dd_now
	d.trick = Input.is_action_pressed("trainer") and not _dpad_y  # Y gehalten = Trick-Taste (5-Sterne-Moves)
	if _dpad_y:
		if d.dpad.length() < 0.2:
			_dpad_y = false
		d.dpad = Vector2.ZERO
		_dpad_last = Vector2.ZERO
	if d.dpad.length() > 0.5:
		_dpad_last = d.dpad
	elif _dpad_last != Vector2.ZERO:
		d.dpad_up = _dpad_last  # Steuerkreuz losgelassen: Zuspiel in die zuletzt gehaltene Richtung
		_dpad_last = Vector2.ZERO
	# Steuerkreuz neu gedrueckt: das ist das Zuspiel selbst (Richtung = Taste)
	d.dpad_down = Vector2.ZERO if _dpad_y else dd_now
	d.fast = Input.is_action_just_pressed("set_fast")  # B: hechten
	d.hit_down = Input.is_action_just_pressed("hit")
	d.hit_up = Input.is_action_just_released("hit")
	d.hit_held = Input.is_action_pressed("hit")
	d.finesse_held = Input.is_action_pressed("finesse")
	d.kind_prev = Input.is_action_just_pressed("serve_prev")  # nur noch fuer Debug-Uebungen
	d.kind_next = Input.is_action_just_pressed("serve_next")
	if Input.is_action_just_pressed("toggle_assist"):
		assist = not assist
	if Input.is_action_just_pressed("toggle_slowmo"):
		slowmo_on = not slowmo_on
	if Input.is_action_just_pressed("toggle_zoom"):
		zoom_on = not zoom_on
	return d


## Der rechte Stick federt beim Loslassen zur Mitte zurueck. Damit die gewaehlte
## Schlagrichtung dabei nicht verloren geht, gilt der letzte deutliche Ausschlag
## noch eine einstellbare Zeit lang weiter ("Stick nachhalten").
var _rs_hold := Vector2.ZERO
var _rs_hold_ms := 0
var _dpad_last := Vector2.ZERO  # zuletzt gehaltene Steuerkreuz-Richtung


func _held_stick(stick: Vector2) -> Vector2:
	var now := Time.get_ticks_msec()
	var l := stick.length()
	if l >= 0.35:
		var turned := _rs_hold == Vector2.ZERO or stick.normalized().dot(_rs_hold.normalized()) < 0.8
		if turned or l >= _rs_hold.length() * 0.85:
			_rs_hold = stick
			_rs_hold_ms = now
			return stick
	if _rs_hold != Vector2.ZERO and now - _rs_hold_ms <= int(cfg.get_v("stick_hold")):
		return _rs_hold
	_rs_hold = Vector2.ZERO
	return stick


func _physics_process(delta: float) -> void:
	clock += delta
	if drill != null and drill.step(delta):
		return  # Debug: freies Laufen, die Uebung steuert alles selbst
	var real_delta := delta / maxf(Engine.time_scale, 0.01)
	var inp := _empty_input()
	if human_team >= 0:
		inp = _auto_input() if autopress else _read_input()
		rs = inp.rs
	if charging:
		charge += real_delta / CHARGE_FULL
	var start: bool = inp.bump or inp.hit_down or inp.over

	match phase:
		Phase.INTRO:
			if start:
				new_match()
		Phase.PRE_SERVE:
			_hold_ball_at_server()
			# Spielzug schon vor dem Aufschlag ansagen (wie das Handzeichen hinter dem Ruecken).
			_play_call_input(inp)
			if trainer_wanted and not whistle_done:
				trainer_wanted = false
				if hud:
					hud.open_trainer()
			if clock >= pause_until and not whistle_done:
				whistle_done = true
				serve_deadline = clock + cfg.get_v("serve_time")
				if hud:
					hud.whistle(false)
					hud.ref_signal([["serve_" + str(serving_team), "Aufschlag " + TEAM_NAMES[serving_team], 1.6]])
			if human_serves():
				serve_aim = _nudge_aim(serve_aim, inp.mv, delta)
				serve_contact = rs
				# R2 = Sprungaufschlag, L2 + R2 = Flatteraufschlag. Solange L2 gehalten wird,
				# stellt sich der Aufschlaeger schon fuer den Flatteraufschlag hin.
				if not autopress:
					serve_kind = 0 if inp.finesse_held else 1
				_easy_serve = false
				if whistle_done:
					if inp.hit_down:
						_do_toss()
						_start_charge()
					elif inp.bump:
						# A = einfacher, sicherer Aufschlag: Flatter aus dem Stand, das Spiel trifft.
						# Y + A (Aufschlagtaktiker): Skyball, ein sehr hoher Ball, der fast senkrecht faellt.
						serve_kind = 0
						_easy_serve = true
						_skyball = inp.get("trick", false) and _trick_ok(server(), "skyball")
						if _skyball:
							y_used = true
							stats["Move skyball"] = stats.get("Move skyball", 0) + 1
						_do_toss()
					elif clock > serve_deadline and not autopress:
						_end_rally(1 - serving_team, "Aufschlagzeit überschritten")
			elif whistle_done and (server()._vel.length() < 0.3 or clock > pause_until + 2.0):
				_do_toss()  # KI wirft erst, wenn der Aufschlaeger steht (sonst laeuft er vom Ball weg)
		Phase.TOSS:
			_play_call_input(inp)
			if human_serves():
				serve_aim = _nudge_aim(serve_aim, inp.mv, delta)
				serve_contact = rs
				if not serve_done:
					if _easy_serve and not charging:
						if clock >= serve_ideal:
							_serve_hit(0.0, 0.55, Vector2(0.0, 0.1), 0.55)
					elif inp.hit_down and not charging:
						_start_charge()
					elif inp.hit_up and charging:
						var c := _release_charge()
						_serve_hit(human_clock() - serve_ideal, minf(c, 1.0), serve_contact, c)
					elif clock > serve_ideal + windows("serve")[2] * 1.4 + 0.03 + lag_game():
						serve_done = true
						charging = false
						popup(server(), "Zu spät", Q_COLOR[Q.MISS])
						touch_result.emit("serve", serving_team, true, Q.MISS, 1.0, 0.0, 0.0)
			elif not serve_done and clock >= serve_ideal + ai_serve_e:
				_serve_hit(ai_serve_e, rng.randf_range(plan(serving_team).serve_power.x, plan(serving_team).serve_power.y), serve_contact, 0.9)
			_step_ball(delta)
		Phase.RALLY:
			_play_call_input(inp)
			_rally_input(inp)
			_ai_actions()
			_step_ball(delta)
		Phase.POINT_PAUSE:
			_step_dead_ball(delta)
			# A / Leertaste: gleich weiter (nach einem kurzen Moment fuer den Jubel)
			var skip: bool = start and clock >= _rally_end + 0.5
			if skip:
				replay_pending = false
			if replay_pending and clock >= _rally_end + 1.1:
				_start_replay()
			elif clock >= pause_until or skip:
				if side_change_pending:
					_do_side_change()
				else:
					start_rally()
		Phase.REPLAY:
			_step_replay(real_delta, start)
		Phase.TIMEOUT:
			if clock >= pause_until or (start and clock >= pause_until - 6.5):
				_end_timeout()
		Phase.SET_OVER:
			if autoplay or (human_team < 0 and clock >= pause_until + 3.0) or (start and clock >= pause_until - 1.5):
				_start_set()
		Phase.MATCH_OVER:
			if autoplay:
				if rally_count >= autoplay_rallies:
					_print_stats()
					get_tree().quit()
				else:
					new_match()
			elif start or (human_team < 0 and clock >= pause_until + 3.0):
				new_match()

	if phase != Phase.REPLAY:
		_update_players(delta)
		_record()
	_update_time_and_camera(real_delta)
	_update_visuals()
	_update_form_lines()
	if phase == Phase.REPLAY:
		for t in 2:
			for pl in players[t]:
				pl.set_controlled(false)
	if hud:
		hud.update_view(self)


# ---------------------------------------------------------------- Wiederholung

func _record() -> void:
	if autoplay or hud == null:
		return
	if not (phase == Phase.TOSS or phase == Phase.RALLY or (phase == Phase.POINT_PAUSE and clock < _rally_end + 0.6)):
		return
	var snaps := []
	for t in 2:
		for pl in players[t]:
			snaps.append(pl.snapshot())
	_rec.append([clock, ball.position, snaps])
	while not _rec.is_empty() and _rec[0][0] < clock - REC_SECONDS:
		_rec.pop_front()


func _start_replay() -> void:
	replay_pending = false
	var t0 := _rally_end - 2.6
	_replay = _rec.filter(func(f): return f[0] >= t0)
	_replay_ev = _rec_events.filter(func(e): return e[0] >= t0)
	if _replay.size() < 20:
		return
	_replay_live = []
	for t in 2:
		for pl in players[t]:
			_replay_live.append(pl.snapshot())
	_replay_live.append(ball.position)
	_replay_i = 0
	_replay_ev_i = 0
	_replay_t = _replay[0][0]
	_replay_jump = true
	phase = Phase.REPLAY
	points_since_replay = 0
	stats["Wiederholungen"] = stats.get("Wiederholungen", 0) + 1
	if hud:
		hud.show_replay(true)


## Spielt die Aufzeichnung ab: langsam, und um den entscheidenden Moment noch langsamer.
func _step_replay(real_delta: float, skip: bool) -> void:
	if skip and _replay_t > _replay[0][0] + 0.25:
		_end_replay()
		return
	var near := absf(_replay_t - (_rally_end - 0.35)) < 0.55
	_replay_t += real_delta * (0.33 if near else 0.6)
	while _replay_i < _replay.size() - 1 and _replay[_replay_i + 1][0] <= _replay_t:
		_replay_i += 1
	# Zwischen zwei aufgezeichneten Bildern weich mischen, damit die Zeitlupe nicht ruckelt.
	var f: Array = _replay[_replay_i]
	var g: Array = _replay[mini(_replay_i + 1, _replay.size() - 1)]
	var w := 0.0
	if g[0] > f[0]:
		w = clampf((_replay_t - f[0]) / (g[0] - f[0]), 0.0, 1.0)
	ball.position = (f[1] as Vector3).lerp(g[1], w)
	var k := 0
	for t in 2:
		for pl in players[t]:
			pl.restore_mix(f[2][k], g[2][k], w)
			k += 1
	if _replay_jump:
		_replay_jump = false
		reset_physics_interpolation()
	while _replay_ev_i < _replay_ev.size() and _replay_ev[_replay_ev_i][0] <= _replay_t:
		var e: Array = _replay_ev[_replay_ev_i]
		contact.emit(e[1], e[2], e[3])
		_replay_ev_i += 1
	if _replay_i >= _replay.size() - 1:
		_end_replay()


func _end_replay() -> void:
	var k := 0
	for t in 2:
		for pl in players[t]:
			pl.restore(_replay_live[k])
			k += 1
	ball.position = _replay_live[k]
	reset_physics_interpolation()
	_replay = []
	ball_vel = Vector3.ZERO
	phase = Phase.POINT_PAUSE
	pause_until = clock + 0.6
	if hud:
		hud.show_replay(false)


func _abort_replay() -> void:
	if phase == Phase.REPLAY:
		_end_replay()
	replay_pending = false
	timeout_team = -1


func _start_charge() -> void:
	charging = true
	charge = 0.0


func _release_charge() -> float:
	charging = false
	return minf(charge, 1.5)


## Nur fuer Tests: drueckt mit etwas Zufall nahe am idealen Moment.
var _auto_t := -1.0
var _auto_rs := Vector2.ZERO


func _auto_input() -> Dictionary:
	var d := _empty_input()
	d.rs = _auto_rs
	# Koenner-Bot: haelt bei manchen Kontakten Y fuer einen 5-Sterne-Move (wenn der Spieler ihn kann).
	if skilled and opp != null and opp.human and not opp.done:
		if _auto_trick_opp != opp:
			_auto_trick_opp = opp
			_auto_trick = rng.randf() < 0.2
		d.trick = _auto_trick
	match phase:
		Phase.SET_OVER, Phase.INTRO, Phase.MATCH_OVER, Phase.TIMEOUT:
			d.bump = true
		Phase.PRE_SERVE:
			if clock >= pause_until:
				_auto_rs = Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.2, 0.8))
				serve_kind = rng.randi() % 2
				d.rs = _auto_rs
				d.hit_down = true
		Phase.TOSS:
			if charging and _due(serve_ideal):
				d.hit_up = true
		Phase.RALLY:
			# Koenner sagt manchmal einen Spielzug an, waehrend die Annahme zum Zuspieler fliegt.
			if skilled and opp != null and opp.team == human_team and opp.kind == "set" and play_call[human_team] == "" \
					and _auto_call_opp != opp:
				_auto_call_opp = opp
				if rng.randf() < 0.6:
					d.play_dd = [Vector2(0, 1), Vector2(1, 0), Vector2(0, -1), Vector2(-1, 0)][rng.randi() % 4]
			if opp != null and not opp.done and not opp.pending and opp.team == human_team and opp.human:
				if opp.kind == "attack":
					if skilled:
						_skilled_attack(d)
					if not charging and clock >= opp.t - 0.7:
						if not skilled:
							_auto_rs = Vector2(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.5, 0.8))
						d.rs = _auto_rs
						d.hit_down = true
					elif charging and _due(opp.t):
						d.hit_up = true
				elif opp.kind == "set" and _auto_set_plan(opp) in ["dump", "attack"]:
					# Zweiter Kontakt als Angriff: R2 laden, im Treffpunkt loslassen (L2 dazu = Dump).
					d.finesse_held = _auto_set_kind == "dump"
					if not charging and clock >= opp.t - 0.5:
						d.hit_down = true
					elif charging and _due(opp.t):
						d.hit_up = true
				elif (pro_bot or skilled) and opp.kind in ["pass", "dig"] and Technique.goes_down(_defense_style(opp)) \
						and clock >= opp.t - DIVE_LEAD - 0.05:
					# Koenner hechtet mit B: Absprung kurz bevor der Ball da ist (nicht erst im Kontakt)
					if _due(opp.t - DIVE_LEAD):
						d.fast = true
				elif _due(opp.t):
					if opp.kind == "set" and opp.speed <= OVER_OK:
						var dirs := [Vector2(-1, 0), Vector2(1, 0), Vector2(0, 1), Vector2(0, -1)]
						d.dpad_up = dirs[rng.randi() % 4]
						if _auto_set_kind == "fast":
							d.dump_held = true  # R1: schnelles Zuspiel
							_r1_down_at = clock
					elif (pro_bot or skilled) and opp.kind != "free" and _pro_reception(d):
						pass
					elif opp.speed <= OVER_OK:
						d.over_up = true
					else:
						d.bump_up = true
			elif human_player() != null and opp != null and opp.kind == "attack":
				d.rs = Vector2(rng.randf_range(-1.0, 1.0), 0.0)  # zweiter Blocker per rechtem Stick
				if _due(opp.t - rise(human_player())):
					d.hit_down = true
			elif opp != null and opp.team != human_team and opp.kind == "set" and rng.randf() < 0.02:
				d.mv = Vector2(rng.randf_range(-1.0, 1.0), 0.0)  # Block lesen ausprobieren
			else:
				_auto_t = -1.0
	return d


## Test-Koenner: waehlt den Anlauf in die offene Richtung, zielt in die scharfen Winkel und
## spielt einen Gefuehlsschlag, wenn der Block im Weg steht.
func _skilled_attack(d: Dictionary) -> void:
	if not opp.offered:
		var hl := team_local(opp.team, opp.point).y
		_auto_mv = Vector2.ZERO
		_auto_fin = false
		if absf(hl) > 1.5:
			# Diagonale: Trefferpunkt an der Seite, die vom Feld weg zeigt; Anlauf von aussen.
			_auto_rs = Vector2(0.85 * signf(hl), 0.35) if rng.randf() < 0.6 else Vector2(0.0, 0.4)
			var away_z := signf(opp.point.z)
			_auto_mv = Vector2(-away_z * side_of(human_team), 0.0) if _auto_rs.x != 0.0 else Vector2.ZERO
		else:
			_auto_rs = Vector2(rng.randf_range(-0.6, 0.6), 0.4)
	d.mv = _auto_mv
	if clock >= opp.t - 0.25:
		_auto_fin = _shot_blocked(opp, _auto_rs) and not opp.emergency
		if _auto_fin:
			_auto_rs = Vector2(0.0, 0.2) if rng.randf() < 0.5 else Vector2(0.9 * (1.0 if rng.randf() < 0.5 else -1.0), 0.0)
	d.rs = _auto_rs
	rs = _auto_rs
	d.finesse_held = _auto_fin


## Test (--pro): ein simulierter Koenner nutzt die neuen Annahme-Techniken. Er hechtet von Hand,
## wenn der Ball weit weg ist, gleicht seitliche Baelle aus und spielt bei guter Lage flach ans Netz.
func _pro_reception(d: Dictionary) -> bool:
	var o := opp
	var side: float = team_local(o.team, o.point).y - team_local(o.team, o.player.position).y
	var sp := _stand_pos(o, Vector3(o.point.x, 0.0, o.point.z))
	if absf(side) > 0.3:
		d.rs_pad = Vector2(-signf(side), 0.0)
	elif o.kind == "pass" and o.speed < 20.0:
		d.rs_pad = Vector2(0.0, 1.0)
	d.bump_up = true
	return true


## Test: was der simulierte Spieler mit diesem Zuspiel vorhat (einmal je Ballkontakt gewuerfelt,
## gleiche Anteile wie vor dem neuen Tastenplan): high, fast, dump oder attack.
var _auto_set_opp: Opp = null
var _auto_call_opp: Opp = null
var _auto_trick_opp: Opp = null
var _auto_trick := false
var _auto_set_kind := "high"


func _auto_set_plan(o: Opp) -> String:
	if _auto_set_opp != o:
		_auto_set_opp = o
		var r := rng.randf()
		_auto_set_kind = "high"
		if o.speed <= OVER_OK:
			if (r >= 0.5 and r < 0.75) or r >= 0.9:
				_auto_set_kind = "fast"
			elif r >= 0.75 and r < 0.85:
				_auto_set_kind = "dump"
			elif r >= 0.85:
				_auto_set_kind = "attack"
	return _auto_set_kind


func _due(ideal: float) -> bool:
	if _auto_t < 0.0:
		var jit := 0.03 if skilled else 0.07
		_auto_t = ideal + rng.randf_range(-jit, jit)
	if clock >= _auto_t:
		_auto_t = -1.0
		return true
	return false


func _nudge_aim(aim: Vector2, mv: Vector2, delta: float) -> Vector2:
	aim += Vector2(mv.y, mv.x) * 5.0 * delta
	return Vector2(clampf(aim.x, 1.0, 8.8), clampf(aim.y, -4.3, 4.3))


func _do_toss() -> void:
	toss_time = clock
	phase = Phase.TOSS
	ball_g = G
	if serve_kind == 1:
		# Sprungaufschlag: hoher Wurf nach vorn, der Aufschlaeger laeuft an und springt.
		ball_vel = Vector3(-side_of(serving_team) * 0.6, 7.4, 0.0)
		# Treffhoehe nach Reichweite und Sprungkraft des Aufschlaegers (wie beim Angriff), sonst
		# kommt ein kleiner oder sprungschwacher Spieler nicht an den Ball.
		var srv := server()
		var hj := 3.2
		if srv != null:
			var jh := srv.jump_v0 * srv.jump_v0 / (2.0 * G)
			hj += clampf(srv.reach_add + jh - PlayerData.REF_JUMP_H, -0.45, 0.35)
		serve_ideal = clock + Ballistics.time_to_height(ball.position, ball_vel, hj)
	elif _skyball:
		# Skyball: kleiner Wurf, Treffpunkt von unten auf Huefthoehe.
		ball_vel = Vector3(0.0, 2.2, 0.0)
		serve_ideal = clock + Ballistics.time_to_height(ball.position, ball_vel, 1.0)
	else:
		ball_vel = Vector3(0.0, 5.0, 0.0)
		# 2,32 m: so hoch reicht der gestreckte Arm auf den Zehenspitzen.
		serve_ideal = clock + Ballistics.time_to_height(ball.position, ball_vel, 2.32)
	last_action = "toss"
	last_touch_team = serving_team
	ai_serve_e = ai_e("serve") * clampf(1.0 - 0.3 * pf(server(), "serve"), 0.55, 1.45)


## Art des Aufschlags aus dem Trefferpunkt: oben Topspin, Mitte Flatter, unten kurz.
func serve_style(contact: Vector2) -> String:
	if contact.y > 0.35:
		return "topspin"
	if contact.y < -0.35:
		return "short"
	return "float"


func serve_style_text(kind: int, contact: Vector2) -> String:
	match serve_style(contact):
		"topspin":
			return "Sprung-Topspin" if kind == 1 else "Topspin"
		"short":
			return "Kurz"
	return "Sprungflatter" if kind == 1 else "Flatter"


func _serve_hit(e: float, power: float, contact: Vector2, c: float) -> void:
	serve_done = true
	charging = false
	var srv := server()
	var jump := serve_kind == 1
	var q := classify(e, "serve", hit_window_scale(power, contact, jump))
	if q == Q.MISS:
		popup(srv, "Zu früh" if e < 0.0 else "Zu spät", Q_COLOR[Q.MISS])
		touch_result.emit("serve", serving_team, human_serves(), Q.MISS, e, 0.0, 0.0)
		return
	if c > OVERCHARGE + 0.25 and q < Q.WEAK:
		q += 1
	var style := serve_style(contact)
	var d := serve_aim.x
	var l := serve_aim.y - contact.x * 1.5
	var g := G
	var umax := 18.0
	var clear := NET_H + 0.45
	match style:
		"topspin":
			g = G * (1.6 if jump else 1.35)
			umax = 25.0 if jump else 19.0
		"float":
			umax = 22.0 if jump else 17.5
		"short":
			d = minf(d, 3.2)
			umax = 9.0
			clear = NET_H + 0.8
	# Aufschlagstaerke: schnellere Aufschlaege (Aufschlagkanone beim Sprung-Topspin noch mehr).
	# V-3: Spezialisten unterscheiden sich deutlich (Aufschlagwert und Kanone beim Sprungaufschlag).
	umax *= 1.0 + 0.1 * pf(srv, "serve") + (0.08 * pls(srv, "kanone") if jump and style == "topspin" else 0.0)
	var u := lerpf(10.0, umax, power)
	# Super-Zone beim Aufschlag: perfekt getroffen und genau dort losgelassen.
	var sup := false
	if q == Q.PERFECT and style != "short":
		if human_serves():
			sup = c >= SUPER_LO and c <= SUPER_HI
		else:
			sup = jump and rng.randf() < 0.12 * (1.0 + pf(srv, "serve") + 0.4 * pls(srv, "kanone"))
	if sup:
		u = 32.0 if (jump and style == "topspin") else umax * 1.12
	var tak := 1.0 - 0.3 * pls(srv, "taktiker")  # PlayStyle Aufschlagtaktiker: trifft genauer
	if q == Q.GOOD:
		clear += 0.3
		u = minf(u, umax * 0.85)
		d += rng.randf_range(-0.6, 0.6) * tak
		l += rng.randf_range(-0.6, 0.6) * tak
	elif q == Q.WEAK:
		clear += 1.1
		u = minf(u, umax * 0.6)
		d += rng.randf_range(-1.2, 1.2) * tak
		l += rng.randf_range(-1.2, 1.2) * tak
	# Ueberzogen: Ball wird zu lang.
	if c > OVERCHARGE:
		d += rng.randf_range(0.0, (c - OVERCHARGE) * 6.0)
	# Zu frueh getroffen: Ball fliegt zu lang. Zu spaet: Ball fliegt zu flach (Netz).
	var x := excess(e, "serve")
	if x < 0.0:
		d += -x * 30.0
	else:
		clear -= x * lerpf(4.0, 9.0, cfg.unit("faults"))
	var target := court_pos(serving_team, Vector2(-d, l))
	target.y = R
	ball_g = g
	ball_vel = Ballistics.launch_over_net(ball.position, target, clear, 8.0, u, g)
	if _skyball:
		ball_g = G
		ball_vel = Ballistics.launch_with_time(ball.position, target, 2.9)  # fast senkrecht von weit oben
		style = "skyball"
		srv.anim_style = "skyball"
	flutter = 0.0
	if style == "float" and q <= Q.GOOD:
		flutter = (0.32 if jump else 0.26) * (1.0 + 0.35 * pf(srv, "serve")) * (1.0 + 0.35 * pls(srv, "flatter"))
	if trace:
		print("AUFSCHLAG T%d %s q=%s e=%.3f p=%.2f target=%s vel=%s" % [serving_team, style, Q_TEXT[q], e, power, target, ball_vel])
	last_action = "serve"
	last_trick = "skyball" if _skyball else ""
	_skyball = false
	last_toucher = srv
	last_touch_team = serving_team
	possession = serving_team
	touches = 1
	serve_time = clock
	phase = Phase.RALLY
	popup(srv, Q_TEXT[q] + (timing_hint(e, q) if human_serves() else ""), Q_COLOR[q])
	last_super = sup
	if sup:
		mstat[serving_team]["wucht"] = mstat[serving_team].get("wucht", 0) + 1
	_fx("serve", ball.position, (1.0 if sup else power) * (1.0 if jump else 0.65))
	touch_result.emit("serve", serving_team, human_serves(), q, e, ball_vel.length(), 0.0)
	if human_serves() and sup:
		big_hit.emit(0.85)
		_hit_stop(0.06, 0.05)
	elif human_serves() and q == Q.PERFECT and power > 0.8:
		big_hit.emit(0.6)
	plan_next()


## Bestimmt, wer den Ball als Naechstes spielt und wann. Zuerst darf das Team ran,
## auf dessen Seite der Ball gerade ist; fliegt er hinueber, das andere.
func plan_next() -> void:
	opp = null
	charging = false  # eine Aufladung gilt nur fuer ihren Kontakt (R2 noch gehalten laedt neu)
	var cur := team_at_x(ball.position.x)
	# Den eigenen Aufschlag darf das aufschlagende Team nicht mehr spielen.
	var serve_ball := last_action == "serve" and cur == last_touch_team
	if not serve_ball and _try_team(cur):
		return
	_try_team(1 - cur)


func _try_team(team: int) -> bool:
	var idx := touches if team == possession else 0
	if idx >= 3:
		return false
	var apex := Ballistics.apex_height(ball.position, ball_vel, ball_g)
	var kind := "pass"
	var h := H_PASS
	if idx == 0:
		if (last_action == "attack" and ball_vel.length() > 12.0) or (last_action == "block_touch" and ball_vel.length() > 9.0):
			kind = "dig"
		elif last_action == "block":
			kind = "dig"
	elif idx == 1:
		kind = "set"
		h = H_SET if apex >= H_SET + 0.3 else H_PASS + 0.1
	elif apex >= H_ATTACK + 0.05:
		kind = "attack"
		h = H_ATTACK
	else:
		kind = "free"
	# V-2 Overpass: eine zu stramme Annahme, Abwehr oder ein freier Ball fliegt hoch und nah ans
	# Netz auf diese Seite. Der Spieler vorn am Netz darf direkt draufhauen (Mensch mit R2).
	var over_pl := _overpass_hitter(team, idx, apex)
	if over_pl != null:
		kind = "attack"
		h = H_ATTACK

	var tc := Ballistics.time_to_height(ball.position, ball_vel, h, ball_g)
	if tc < 0.0 and kind != "attack":
		# Ball kommt nicht mehr auf Bagger-Hoehe (zum Beispiel aus dem Netz): tief abwehren,
		# statt ihn niemandem zu geben und auf den Boden fallen zu lassen.
		h = 0.45
		tc = Ballistics.time_to_height(ball.position, ball_vel, h, ball_g)
		if idx == 0:
			kind = "dig"
	if tc < 0.0:
		return false
	var p := Ballistics.pos_at(ball.position, ball_vel, tc, ball_g)
	if kind == "attack" and over_pl == null and (signf(p.x) != side_of(team) or absf(p.x) > 6.0 or absf(p.x) < 0.2):
		kind = "free"
		h = H_PASS
		tc = Ballistics.time_to_height(ball.position, ball_vel, h, ball_g)
		p = Ballistics.pos_at(ball.position, ball_vel, tc, ball_g)
	# Ein Ball dicht am Netz (aus dem Netz fallend, knapp nicht rueber) gehoert der Seite, auf der
	# er ist. Frueher galt alles unter 0,2 m als "Overpass": niemand nahm ihn, er fiel auf den Boden.
	if signf(p.x) != side_of(team) or absf(p.x) < 0.03:
		return false
	if absf(p.x) > HALF_L + 4.0 or absf(p.z) > HALF_W + 3.5:
		return false

	if team != last_touch_team and team != human_team:
		# Die KI laesst Aus-Baelle fallen, verschaetzt sich aber manchmal knapp an der Linie.
		var land_t := Ballistics.time_to_height(ball.position, ball_vel, R, ball_g)
		var land := Ballistics.pos_at(ball.position, ball_vel, land_t, ball_g)
		var margin := maxf(absf(land.x) - HALF_L, absf(land.z) - HALF_W)
		if margin > R and (margin > 0.35 or rng.randf() < 0.75):
			return false

	var excluded: VPlayer = last_toucher if last_touch_team == team else null
	var pl: VPlayer = null
	if over_pl != null:
		pl = over_pl
		_hitter[team] = over_pl
		_play_info[team] = {}
	elif kind == "attack":
		pl = _chosen_hitter(team)
		if pl == excluded or (pl != null and is_down(pl)):
			pl = null
	elif kind == "set":
		var s := player_by_role(team, "S")
		if s != null and s != excluded and not is_down(s) and flat_dist(s.position, p) <= s.run_speed * tc + 0.8:
			pl = s
	if pl == null and kind == "pass" and last_action == "serve":
		pl = _receiver(team, p, excluded)
	if pl == null:
		pl = _nearest(team, p, excluded, kind == "attack", kind)
	if pl == null:
		return false
	if kind == "attack":
		# Grosse und sprungstarke Angreifer treffen den Ball hoeher (steiler ueber den Block).
		var jh := pl.jump_v0 * pl.jump_v0 / (2.0 * G)
		var h2 := H_ATTACK + clampf(pl.reach_add + jh - PlayerData.REF_JUMP_H, -0.3, 0.35)
		if absf(h2 - h) > 0.01 and apex >= h2 + 0.05:
			var tc2 := Ballistics.time_to_height(ball.position, ball_vel, h2, ball_g)
			if tc2 >= 0.0:
				tc = tc2
				p = Ballistics.pos_at(ball.position, ball_vel, tc, ball_g)

	# Harter Ball auf Kopfhoehe direkt auf den Abwehrspieler: Abwehr ueber dem Kopf (mit den Haenden),
	# getroffen dort, wo der Ball am Spieler vorbeifliegt, statt erst in Bagger-Hoehe.
	var force_style := ""
	if kind == "dig" and ball_vel.length() > 14.0:
		var head := _overhead_point(pl)
		if not head.is_empty():
			tc = head.t
			p = head.p
			force_style = "overhead"

	var o := Opp.new()
	o.team = team
	o.player = pl
	o.kind = kind
	o.t = clock + tc
	o.t0 = clock
	o.point = p
	if force_style != "":
		o.style = force_style
		o.style_locked = true
	if kind == "set":
		o.slack = pl.run_speed * tc - flat_dist(pl.position, p)
		# 5-Sterne-Move Sprungzuspiel: KI-Stars spielen ihn manchmal (Mensch: Y beim Zuspiel).
		if not (team == human_team and (drill == null or drill.human_does(kind))) and pl.role == "S" and pass_quality != Q.WEAK \
				and apex >= H_SET + 0.6 and rng.randf() < 0.05 * pls(pl, "sprungzuspiel"):
			o.trick = "jumpset"
			pl.anim_style = "jumpset"
			stats["Move jumpset"] = stats.get("Move jumpset", 0) + 1
			# Im Sprung wird der Ball hoeher gespielt.
			var tj := Ballistics.time_to_height(ball.position, ball_vel, H_SET + 0.5, ball_g)
			if tj > 0.3:
				o.t = clock + tj
				o.point = Ballistics.pos_at(ball.position, ball_vel, tj, ball_g)
	if kind in ["pass", "dig", "free"]:
		var sp0 := _stand_pos(o, Vector3(p.x, 0.0, p.z))
		o.pressure = flat_dist(pl.position, sp0) / (pl.run_speed * maxf(tc, 0.05))
		o.move_dir = Vector3(sp0.x - pl.position.x, 0.0, sp0.z - pl.position.z)
	if kind == "attack" and idx == 2 and _play_info[team].get("geo", "") == "slide":
		# Slide: Anlauf aus der Mitte, parallel zum Netz hinter den Zuspieler.
		o.approach_z = court_pos(team, Vector2(0.9, -0.6)).z - p.z
	if kind == "attack":
		# Notangriff: schlechtes Zuspiel oder Ball zu weit weg vom Netz -> kein voller Schlag.
		var far := absf(p.x) > (4.6 if not is_front_row(pl) else 3.2)
		o.emergency = (set_q[team] == Q.WEAK or far) and over_pl == null
		if over_pl != null:
			stats["Overpass-Angriff"] = stats.get("Overpass-Angriff", 0) + 1
	o.speed = Vector3(ball_vel.x, ball_vel.y - ball_g * tc, ball_vel.z).length()
	o.human = team == human_team and (drill == null or drill.human_does(kind))
	# Ein Flatterball ist schwer zu lesen: kleineres Timing-Fenster bei der Annahme.
	var calm := 1.0 - 0.4 * pls(pl, "ruhepol") if kind == "pass" else 1.0  # PlayStyle Ruhepol
	if flutter > 0.0 and last_action == "serve":
		o.win_scale = 1.0 - 0.12 * calm
	if kind == "dig" or (kind == "pass" and last_action == "serve"):
		o.win_scale *= 1.0 - 0.22 * hard_ball(o.speed) * calm
	var serve_k := 1.0  # V-3: wie schwer die Annahme wird (fuer die KI: groesserer Fehler)
	# PlayStyles Trickser (Dump) und Leger (Leger, Gefuehlsschlag): die Abwehr ist ueberrascht.
	if idx == 0 and last_touch_team != team and last_toucher != null and (last_action == "tip" or last_shot_style in ["roll", "corner", "seam"]):
		var sneaky := pls(last_toucher, "trickser") if set_tempo[last_touch_team] == "dump" else pls(last_toucher, "leger")
		serve_k *= 1.0 + 0.15 * sneaky
	if kind == "pass" and last_action == "serve":
		if last_super:
			serve_k *= 1.35  # perfekter, voller Aufschlag: echte Ass-Chance
		if last_trick == "skyball":
			serve_k *= 1.2 + 0.1 * pls(last_toucher, "taktiker")  # Skyball: schwer zu lesen
			stats["Aufschlag perfekt"] = stats.get("Aufschlag perfekt", 0) + 1
		if _serve_seam(team, p, pl):
			serve_k *= 1.25 + 0.1 * pls(last_toucher, "taktiker")  # zwischen zwei Annahmespieler: beide zoegern
			stats["Aufschlag in die Luecke"] = stats.get("Aufschlag in die Luecke", 0) + 1
		serve_k = 1.0 + (serve_k - 1.0) * calm
		o.win_scale /= serve_k
	if o.human and (kind == "pass" or kind == "dig" or kind == "free"):
		o.win_scale *= cfg.get_v("receive_help") / 100.0
	if o.human and idx == 0 and last_action == "block_touch":
		# Nach eigenem Block mit Soft-Touch: die Steuerung springt auf den Abwehrspieler. Der
		# noch gehaltene Block-Stick soll ihn nicht vom Ball weglaufen lassen, und das Fenster
		# ist etwas groesser, weil der Wechsel ueberraschend kommt.
		o.win_scale *= 1.35
		_stick_lock_until = clock + 0.45
		_need_neutral = true
	# Staerken: wer gut annimmt, abwehrt, zuspielt oder schlaegt, hat als Mensch etwas mehr Zeit
	# (groesseres Timing-Fenster) und trifft als KI genauer.
	var sk := _touch_skill(pl, kind)
	var sk_w := 0.2 if (kind == "pass" and last_action == "serve") else 0.12  # schwacher Annehmer zaehlt mehr
	if o.human:
		o.win_scale *= 1.0 + sk_w * sk
	if not o.human:
		o.ai_e = ai_e(kind) * clampf(1.0 - 2.5 * sk_w * sk, 0.5, 1.5) * serve_k
		if team == human_team and idx == 0 and last_action == "block_touch" and last_touch_team == team:
			o.ai_e *= 0.55  # nach deiner Blockberuehrung ist der Ball gebremst: deine Abwehr hat es leichter
		if kind == "dig":
			_ai_dig_limits(o, tc)
	if kind == "attack":
		pl.has_jumped = false
		pl.lean = 0.0
		_block_att = pl
		_assign_block(1 - team, p, o.t)
	else:
		blockers[1 - team] = []
	opp = o
	return true


## V-2: Kommt der Ball als Overpass hoch und nah ans Netz, wer vorn kann ihn direkt angreifen?
## Nur beim ersten Kontakt nach einem Ball, der kein Angriff war (Annahme, Abwehr, freier Ball).
func _overpass_hitter(team: int, idx: int, apex: float) -> VPlayer:
	if idx != 0 or not last_action in ["pass", "dig", "free", "set"] or last_touch_team == team:
		return null
	if apex < H_ATTACK + 0.05:
		return null
	var tc := Ballistics.time_to_height(ball.position, ball_vel, H_ATTACK, ball_g)
	if tc < 0.25:
		return null
	var p := Ballistics.pos_at(ball.position, ball_vel, tc, ball_g)
	if signf(p.x) != side_of(team) or absf(p.x) < 0.08 or absf(p.x) > 2.2 or absf(p.z) > HALF_W - 0.2:
		return null
	var best: VPlayer = null
	var bd := 1e9
	for pl in players[team]:
		if pl.role == "L" or not is_front_row(pl) or is_down(pl):
			continue
		var d := flat_dist(pl.position, p)
		if d <= pl.run_speed * tc + 0.5 and d < bd:
			bd = d
			best = pl
	return best


## V-3: Landet der Aufschlag genau zwischen zwei Annahmespielern (aehnlich weit weg, beide nah),
## zoegern beide kurz: die Annahme wird schwerer. Folgt allein aus dem Zielpunkt.
func _serve_seam(team: int, p: Vector3, taker: VPlayer) -> bool:
	var d1 := flat_dist(taker.position, p)
	var d2 := 1e9
	for pl in players[team]:
		if pl == taker or pl.role == "S" or not _rcv_cache[team].get("passers", []).has(pl.slot):
			continue
		d2 = minf(d2, flat_dist(pl.position, p))
	return d1 > 0.9 and d2 < 2.6 and absf(d2 - d1) < 0.6


## Lauftempo nach Schnelligkeit: 40 -> 8 % langsamer, 99 -> 8 % schneller.
func _speed_k(pl: VPlayer) -> float:
	return 1.0 + 0.08 * pf(pl, "speed") + 0.035 * pls(pl, "blitzstart")


## Staerke fuer eine Ballberuehrung (-1 .. +1).
func _touch_skill(pl: VPlayer, kind: String) -> float:
	match kind:
		"pass", "free":
			return pf(pl, "receive")
		"dig":
			return pf(pl, "defense") + 0.25 * pls(pl, "katze")
		"set":
			return pf(pl, "setting")
		"attack":
			return 0.5 * pf(pl, "power") + 0.5 * pf(pl, "jump")
	return 0.0


## 0 = normaler Ball, 1 = sehr harter Ball (ab ca. 16 m/s spuerbar, ab 28 m/s voll).
func hard_ball(speed: float) -> float:
	return clampf((speed - 16.0) / 12.0, 0.0, 1.0)


## KI-Abwehr: braucht eine Reaktionszeit, laeuft nicht beliebig schnell und wehrt harte
## Baelle seltener sauber ab. Wie gut, stellt "Gegner-Abwehr" ein.
func _ai_dig_limits(o: Opp, tc: float) -> void:
	var skill := cfg.unit("ai_defense")
	var react := lerpf(0.42, 0.2, skill)
	var run := lerpf(3.2, 5.5, skill) * (1.0 + 0.1 * pf(o.player, "speed"))
	var reach := lerpf(1.05, 1.6, skill) * (1.0 + 0.15 * pf(o.player, "defense") + 0.12 * pls(o.player, "katze"))
	o.start_pos = o.player.position
	o.max_run = maxf(0.0, tc - react) * run
	if flat_dist(o.player.position, o.point) > o.max_run + reach:
		o.no_reach = true
	var hard := hard_ball(o.speed) * (1.0 - 0.45 * skill)
	o.ai_e *= 1.0 + hard * 2.0
	if last_action == "block":
		# Nach einem Kill-Block faellt der Ball steil und schnell: die KI rettet ihn nur selten.
		o.max_run *= 0.5
		if rng.randf() > lerpf(0.12, 0.3, skill):
			o.no_reach = true


var _hitter := [null, null]
var _block_att: VPlayer = null  # Angreifer, gegen den gerade der Block gestellt wird


func _chosen_hitter(team: int) -> VPlayer:
	return _hitter[team]


## Fliegt der Ball auf Kopf- bis Reichhoehe dicht am Spieler vorbei? Dann {t, p}, sonst leer.
func _overhead_point(pl: VPlayer) -> Dictionary:
	var t := 0.05
	var best := {}
	var bd := 0.45
	while t < 1.2:
		var q := Ballistics.pos_at(ball.position, ball_vel, t, ball_g)
		if q.y < 1.2:
			break
		var d := flat_dist(q, pl.position)
		if d < bd and q.y >= 1.35 and q.y <= 2.3 and signf(q.x) == signf(pl.position.x):
			bd = d
			best = {"t": t, "p": q}
		t += 0.02
	return best


## Annahme, Abwehr, freier Ball: Technik aus der Lage (siehe Technique.defense_style).
func _defense_style(o: Opp) -> String:
	var pl := o.player
	var goal := _stand_pos(o, Vector3(o.point.x, 0.0, o.point.z))
	var dv := Vector3(goal.x - pl.position.x, 0.0, goal.z - pl.position.z)
	var t_left := maxf(0.0, o.t - clock)
	var short := dv.length() - pl.run_speed * maxf(0.0, t_left - 0.05)
	var to_net := -side_of(o.team)
	var dir := o.move_dir if o.move_dir.length() > 0.2 else dv  # Richtung, in die er los musste
	var hard := hard_ball(o.speed)
	return Technique.defense_style(short, dir.x * to_net, dir.z, t_left, hard, o.kind == "dig", o.pressure)


## Angriff: Technik aus Schlag, Zuspiel-Tempo, Bahn und Lage.
func _attack_style(o: Opp) -> String:
	var info := attack_shot(o.team, o.point, o.rs, o.power, o.finesse)
	var lateral: float = (info.target as Vector3).z - o.point.z
	return Technique.attack_style(info.style, o.power, lateral, set_tempo[o.team], o.player.lane, o.emergency)


## Annahme nach dem Aufschlag: Naehe zaehlt, aber der Libero nimmt bevorzugt an,
## die Annahmespieler vor den uebrigen.
func _receiver(team: int, p: Vector3, excluded: VPlayer) -> VPlayer:
	var best: VPlayer = null
	var bs := 1e9
	for pl in players[team]:
		if pl == excluded or is_down(pl):
			continue
		var sc := flat_dist(pl.position, p) * _receiver_weight(pl)
		if sc < bs:
			bs = sc
			best = pl
	return best


## Wer den Ball nimmt: wer am schnellsten hinkommt (Weg durch Lauftempo), nicht nur wer am
## naechsten steht. Den zweiten Ball nimmt, wenn der Zuspieler nicht kann, bevorzugt der Libero,
## dann der Diagonalspieler (wie im echten Spiel).
func _nearest(team: int, p: Vector3, excluded: VPlayer, no_libero: bool, kind := "") -> VPlayer:
	var best: VPlayer = null
	var bd := 1e9
	for pl in players[team]:
		if pl == excluded or is_down(pl):
			continue
		if no_libero and pl.role == "L":
			continue
		var d := _reach_time(pl, p)
		if kind == "set":
			d *= {"L": 0.8, "OP": 0.9}.get(pl.role, 1.0)
		if d < bd:
			bd = d
			best = pl
	return best


func _reach_time(pl: VPlayer, p: Vector3) -> float:
	return flat_dist(pl.position, p) / maxf(pl.run_speed, 1.0)


## R3: Du uebernimmst den Mitspieler, der am schnellsten am Ball ist (ausser dem jetzigen).
## Nur fuer Annahme, Abwehr, freien Ball und Zuspiel; nicht mehr, wenn die Beruehrung schon laeuft.
func _switch_player() -> void:
	var o := opp
	if o == null or o.done or o.pending or o.team != human_team or not o.human or o.kind == "attack":
		return
	if o.launched or o.t - clock < 0.12:
		return
	var cur := o.player
	var excluded: VPlayer = last_toucher if last_touch_team == o.team else null
	var best: VPlayer = null
	var bd := 1e9
	for pl in players[o.team]:
		if pl == cur or pl == excluded or is_down(pl) or pl.airborne:
			continue
		var d := _reach_time(pl, o.point)
		if d < bd:
			bd = d
			best = pl
	if best == null:
		return
	cur.prep = ""
	cur.contact_on = false
	cur.anim_kind = ""
	cur.manual_dir = Vector3.ZERO
	o.player = best
	o.style = ""
	o.style_locked = false
	var tc := maxf(o.t - clock, 0.05)
	if o.kind == "set":
		o.slack = best.run_speed * tc - flat_dist(best.position, o.point)
	else:
		var sp0 := _stand_pos(o, Vector3(o.point.x, 0.0, o.point.z))
		o.pressure = flat_dist(best.position, sp0) / (best.run_speed * tc)
		o.move_dir = Vector3(sp0.x - best.position.x, 0.0, sp0.z - best.position.z)
	_need_neutral = false
	stats["Spielerwechsel R3"] = stats.get("Spielerwechsel R3", 0) + 1


## Stellt den Block: der naechste Vorderspieler blockt, der Mittelblocker laeuft zum
## Doppelblock dazu. Bei Angriffen ueber die Mitte schliessen beide Aussenblocker (Dreierblock).
## Ob die Helfer rechtzeitig ankommen, haengt vom Tempo des Zuspiels ab.
func _assign_block(def: int, p: Vector3, t_contact: float) -> void:
	if drill != null and drill.no_block(def):
		blockers[def] = []
		return
	var front: Array = []
	for pl in players[def]:
		if is_front_row(pl) and not is_down(pl):
			front.append(pl)
	if front.is_empty():
		blockers[def] = []
		return
	var mb := _lane_player(def, "mid")
	if mb == null or is_down(mb):
		mb = front[0]
	# V-1: Gegen einen Spielzug mit Schnellangriff muss der Mittelblocker raten. Springt er mit dem
	# Taeuscher, fehlt er im Block; ist der Schnelle wirklich dran und er hat richtig geraten, steht
	# der Block. Wer gut liest (Gegner-Block, Blockleser), raet oefter richtig. Hat der Mensch seinen
	# Mittelblocker vorher selbst hingestellt (Block lesen), entscheidet das wie bisher.
	var info: Dictionary = _play_info[1 - def]
	var guess_bonus := 0
	if not commit_block[def] and not info.is_empty() and (info.quick_z != null or info.set_quick) and mb != null and is_front_row(mb):
		var read_p := lerpf(0.15, 0.45, cfg.unit("ai_block")) if def != human_team else 0.3
		read_p += 0.12 * pls(mb, "blockleser")
		var guess_quick: bool = rng.randf() < 0.5
		if rng.randf() < read_p:
			guess_quick = info.set_quick  # richtig gelesen
		if guess_quick and not info.set_quick:
			# Mit dem Taeuscher gesprungen: der Mittelblocker ist raus.
			front.erase(mb)
			mb.target = Vector3(side_of(def) * 0.45, 0.0, float(info.quick_z) if info.quick_z != null else mb.position.z)
			mb.block_pose = true
			mb.jump()
			stats["Block auf Taeuscher"] = stats.get("Block auf Taeuscher", 0) + 1
			mb = front[0] if not front.is_empty() else null
			if front.is_empty():
				blockers[def] = []
				return
		elif guess_quick and info.set_quick:
			guess_bonus = 1
			stats["Schnellangriff gelesen"] = stats.get("Schnellangriff gelesen", 0) + 1
		elif info.set_quick:
			guess_bonus = -1
			stats["Schnellangriff nicht gelesen"] = stats.get("Schnellangriff nicht gelesen", 0) + 1
	var list: Array = []
	var dirs: Array = []
	# Mensch hat den Mittelblocker vorher hingestellt: nah am Angriffspunkt = gelesen,
	# weit daneben = falsch gelesen, dazwischen ganz normaler Block.
	var committed: bool = commit_block[def]
	commit_block[def] = false
	var commit_hit := guess_bonus > 0
	commit_miss[def] = guess_bonus < 0
	read_hit[def] = commit_hit
	if committed and mb != null:
		var miss_by := absf(mb.position.z - p.z)
		commit_hit = miss_by < 1.0
		read_hit[def] = commit_hit
		commit_miss[def] = miss_by > 2.2
		if commit_hit:
			popup(mb, "Gelesen!", Color(1.0, 0.85, 0.3))
		elif commit_miss[def]:
			popup(mb, "Falsch gelesen", Q_COLOR[Q.WEAK])
	if absf(p.z) < 1.5 or commit_hit:
		list = [mb]
		dirs = [0.0]
		var t_left := t_contact - clock
		for pl in front:
			if pl != mb and (t_left > 0.9 or commit_hit or rng.randf() < 0.5):
				list.append(pl)
				dirs.append(signf(pl.position.z - mb.position.z))
	else:
		var best: VPlayer = null
		var bd := 1e9
		for pl in front:
			var dz := absf(pl.position.z - p.z)
			if dz < bd:
				bd = dz
				best = pl
		list = [best]
		dirs = [0.0]
		var partner: VPlayer = mb
		if best == mb:
			partner = null
			for pl in front:
				if pl != mb and (partner == null or absf(pl.position.z - p.z) < absf(partner.position.z - p.z)):
					partner = pl
		list.append(partner)
		dirs.append(-signf(p.z))
	for i in list.size():
		var pl: VPlayer = list[i]
		var base_jump := t_contact - rise(pl)
		pl.has_jumped = false
		pl.hand_shift = 0.0
		pl.hand_reach = 0.0
		pl.block_pose = true
		pl.block_jump_at = base_jump + rng.randf_range(-0.05, 0.09) + (0.03 if i > 0 else 0.0)
		if commit_hit:
			pl.block_jump_at = base_jump + rng.randf_range(-0.03, 0.02)  # Block steht schon, Sprung sitzt
		elif commit_miss[def]:
			pl.block_jump_at += 0.12  # falsch geraten: kommt zu spaet
	blockers[def] = list
	_block_auto_style.clear()
	block_dirs[def] = dirs
	block_err[def] = rng.randf_range(-0.4, 0.4)
	var pz = _predicted_cross_z(def, _block_att, p)
	if pz != null:
		block_err[def] = clampf(float(pz) - p.z, -0.6, 0.6)  # Block stellt die Lieblingsrichtung zu
	# Block-Technik je Blocker: kommt er rechtzeitig hin, reicht er ueber den Ball?
	var att: VPlayer = _block_att
	var att_top := (att.jump_v0 * att.jump_v0 / (2.0 * G) + VPlayer.SPIKE_REACH + att.reach_add) if att != null else 3.3
	for i in list.size():
		var b: VPlayer = list[i]
		var goal_z := p.z if i == 0 else p.z + float(dirs[i]) * 0.85
		var t_go := maxf(0.05, b.block_jump_at - clock)
		var late: bool = commit_miss[def] or absf(b.position.z - goal_z) > 4.5 * _speed_k(b) * t_go + 0.3
		var top := b.jump_v0 * b.jump_v0 / (2.0 * G) + VPlayer.BLOCK_REACH + b.reach_add
		b.anim_style = Technique.block_style(committed and b == mb, late, att_top - top)
		stats["Block " + b.anim_style] = stats.get("Block " + b.anim_style, 0) + 1


## Schlaegt der Mensch auf? (Im Debug-Modus kann die KI fuer dein Team aufschlagen.)
func human_serves() -> bool:
	return serving_team == human_team and (drill == null or drill.human_does("serve"))


func human_player() -> VPlayer:
	if human_team < 0:
		return null
	if opp != null and not opp.done and opp.team == human_team and opp.human:
		return opp.player
	if opp != null and opp.team != human_team and opp.kind == "attack" and not blockers[human_team].is_empty() \
			and (drill == null or drill.human_does("block")):
		return blockers[human_team][0]
	return null


# ---------------------------------------------------------------- Eingaben und KI

func _stick_dir(mv: Vector2) -> Vector3:
	var s := side_of(human_team)
	return Vector3(-s, 0, 0) * mv.y + Vector3(0, 0, -s) * mv.x


## Zuspielrichtung aus dem linken Stick: links Aussen, rechts Diagonal, vorn Mitte, hinten Hinterfeld.
func _set_choice(mv: Vector2) -> String:
	if mv.length() < 0.4:
		return "auto"
	if absf(mv.x) >= absf(mv.y):
		return "left" if mv.x < 0.0 else "right"
	return "mid" if mv.y > 0.0 else "back"


func _rally_input(inp: Dictionary) -> void:
	if human_team < 0:
		return
	for pl in players[human_team]:
		pl.manual_dir = Vector3.ZERO
		pl.prep = ""
	if inp.get("switch", false):
		_switch_player()
	var mv: Vector2 = inp.mv
	var hp := human_player()
	# Block lesen: Solange der gegnerische Zuspieler den Ball noch bekommt, stellst du den
	# Mittelblocker mit dem linken Stick am Netz hin. Wo er steht, wenn der Ball gespielt wird,
	# entscheidet ueber den Block (richtig gelesen = starker Block, falsch = zu spaet).
	if opp != null and not opp.done and opp.team != human_team and opp.kind == "set" and (drill == null or drill.human_does("block")):
		var rp := _lane_player(human_team, "mid")
		if rp != null and is_front_row(rp) and mv.length() > 0.3:
			rp.manual_dir = Vector3(0, 0, _stick_dir(mv).z)
			read_z = rp.position.z
			commit_block[human_team] = true
	if opp != null and not opp.done and opp.team == human_team and opp.human:
		match opp.kind:
			"attack":
				_attack_input(inp)
			"set":
				_set_input(inp, hp)
			_:
				if mv.length() < 0.3:
					_need_neutral = false
				if _need_neutral and clock < _stick_lock_until + 0.5:
					hp.manual_dir = Vector3.ZERO  # laeuft von selbst zum Ball, bis du den Stick neu ansetzt
				else:
					hp.manual_dir = _stick_dir(mv)
				# A = annehmen, das Spiel waehlt die Technik (weicher Ball: pritschen, sonst baggern);
				# X = bewusst pritschen.
				var a_tech := _auto_defense_tech(opp)
				hp.prep = a_tech if inp.bump_held else ("over" if inp.over_held else "")
				_reception_hints(opp)
				if recv.input(opp, inp):
					pass  # B: Hecht von Hand, der Druck ist der Kontakt
				elif inp.bump_up:
					_human_touch(a_tech, "")
				elif inp.over_up:
					_human_touch("over", "")
	elif hp != null and not blockers[human_team].is_empty() and hp == blockers[human_team][0]:
		# Einzel- und Dreierblock: beide Sticks steuern den ganzen Block. Doppelblock: der linke
		# Stick gehoert dem Blocker, der aus deiner Sicht links steht, der rechte dem rechten.
		var team_block: Array = []
		for b in blockers[human_team]:
			if b != null:
				team_block.append(b)
		var s := side_of(human_team)
		var rs_on: bool = inp.rs.length() > 0.3
		var both := mv
		if inp.rs.length() > mv.length():
			both = inp.rs
		var ctl: Dictionary = {}  # Blocker -> Stickrichtung (Vector2) oder null = KI
		if team_block.size() == 2:
			var left_b: VPlayer = team_block[0]
			var right_b: VPlayer = team_block[1]
			if -s * left_b.position.z > -s * right_b.position.z:
				left_b = team_block[1]
				right_b = team_block[0]
			ctl[left_b] = mv
			ctl[right_b] = inp.rs if rs_on else null
		else:
			for b in team_block:
				ctl[b] = both
		# B1: L2 gehalten = weicher Block (Haende schraeg nach hinten, Ball bremsen statt abblocken).
		var want_soft: bool = inp.get("finesse_held", false)
		for b in team_block:
			if want_soft and b.anim_style != "soft":
				_block_auto_style[b] = b.anim_style
				b.anim_style = "soft"
			elif not want_soft and _block_auto_style.has(b):
				b.anim_style = _block_auto_style[b]
				_block_auto_style.erase(b)
		if _soft_hint_opp != opp:
			_soft_hint_opp = opp
			technique_available.emit("block_soft")
		var dt := get_physics_process_delta_time()
		var any_jump := false
		for b in team_block:
			var c = ctl[b]
			var cd := Vector3.ZERO
			var cy := 0.0
			if c != null:
				cd = _stick_dir(c)
				cy = c.y
			if not b.airborne:
				if c != null:
					b.manual_dir = Vector3(0, 0, cd.z)
			else:
				if c != null:
					# In der Luft: Haende mit dem Stick verschieben, Stick nach vorn = ueber das Netz greifen.
					b.hand_shift = move_toward(b.hand_shift, cd.z * 0.45, 3.0 * dt)
					b.hand_reach = 0.12 if cy > 0.5 else 0.0
		if inp.hit_down and not hp.airborne and not hp.has_jumped:
			for b in team_block:
				if not b.has_jumped:
					b.jump()
					if b != hp:
						_ai_block_hands(human_team, b)


## A in der Annahme und Abwehr: was ein guter Spieler hier nehmen wuerde. Weiche Baelle oben
## (genauer), harte Baelle mit dem Bagger (sicher).
func _auto_defense_tech(o: Opp) -> String:
	return "over" if o.speed <= OVER_OK else "bump"


## Zuspiel (zweiter Kontakt), wenn du am Ball bist.
## Steuerkreuz = Zuspiel in diese Richtung (links Aussen, rechts Diagonal, oben Mitte, unten
## Hinterfeld), A = Zuspiel (Richtung vom Steuerkreuz, sonst waehlt das Spiel), X = bewusst pritschen.
## R1 gehalten = schnell (Mitte: Schnellangriff), L1 gehalten = extra hoch und sicher.
## R2 = der zweite Kontakt wird ein Angriff wie der dritte (rechter Stick, Kraft, Timing),
## L2 + R2 = Dump, der Gefuehlsschlag des Zuspielers.
func _set_input(inp: Dictionary, hp: VPlayer) -> void:
	var mv: Vector2 = inp.mv
	# Haelst du das Steuerkreuz (linker Daumen), laeuft der Zuspieler von selbst.
	if not assist and inp.dpad.length() < 0.5:
		hp.manual_dir = _stick_dir(mv)
	if opp.pending:
		return
	var lane := _set_choice(inp.dpad if inp.dpad.length() > 0.5 else inp.mouse_rs)
	var lib_front: bool = opp.player.role == "L" and absf(opp.point.x) < 3.0
	var auto_tech := "over" if (opp.speed <= OVER_OK and not lib_front) else "bump"
	if inp.hit_down and not charging:
		_start_charge()
	if charging:
		hp.prep = "over"
		if not inp.hit_up:
			return
		var e := human_clock() - opp.t
		var c := _release_charge()
		if e < -0.45:
			return  # viel zu frueh losgelassen: neu aufladen
		opp.rs = rs
		opp.power = clampf(c, 0.3, 1.0)
		opp.over = c
		opp.finesse = inp.finesse_held
		opp.tech = "over"
		opp.win_scale = hit_window_scale(0.45 if opp.finesse else opp.power, rs, false)
		var k2 := "dump" if opp.finesse else "attack"
		stats["Mensch 2. Ball " + k2] = stats.get("Mensch 2. Ball " + k2, 0) + 1
		_press(opp, e, lane + "|" + k2)
		return
	# Halten = Zuspieler stellt sich hin und geht in die Haltung, Loslassen = Zuspiel
	if inp.dpad.length() > 0.5 or inp.bump_held:
		hp.prep = auto_tech
	elif inp.over_held:
		hp.prep = "over"
	var trig := ""
	if inp.dpad_up.length() > 0.5:
		lane = _set_choice(inp.dpad_up)
		trig = auto_tech
	elif inp.bump_up:
		trig = auto_tech
	elif inp.over_up:
		trig = "over"
	if trig == "":
		return
	var tempo := "high"
	# Noch von der Annahme gehalten zaehlt nicht: R1 / L1 muessen fuer das Zuspiel neu gedrueckt sein.
	var r1: bool = inp.dump_held and _r1_down_at >= opp.t0 - 0.05
	var l1: bool = inp.l1_held and _l1_down_at >= opp.t0 - 0.05
	if r1:
		tempo = "quick" if lane == "mid" else "fast"
	elif l1:
		tempo = "safe"
	opp.rs = rs  # rechter Stick: Feinsteuerung (naeher ans Netz, weiter weg, zur Antenne)
	if inp.get("trick", false) and _trick_ok(opp.player, "jumpset"):
		_set_trick(opp, "jumpset")
	_human_touch(trig, lane + "|" + tempo)


func _attack_input(inp: Dictionary) -> void:
	opp.rs = rs
	_offer_attack_hints()
	_approach_input(inp.mv)
	# A / X = sicherer Ball rueber (kein Schlag), solange R2 nicht laedt.
	if not charging and not opp.pending and (inp.bump_up or inp.over_up):
		_human_touch("over", "free")
		return
	if not opp.pending:
		opp.finesse = inp.finesse_held  # vorher schon, damit Schulter und Block den Schlag lesen
	# R2 noch vom schnellen Zuspiel gedrueckt: zaehlt direkt als Aufladen, sonst muesste man
	# erst loslassen und neu druecken, und der Schlag kaeme immer zu spaet.
	if (inp.hit_down or inp.hit_held) and not charging and not opp.pending:
		_start_charge()
	elif inp.hit_up and charging and not opp.pending:
		var e := human_clock() - opp.t
		if e < -0.45:
			charging = false  # viel zu frueh losgelassen: neu aufladen
			return
		var c := _release_charge()
		opp.power = clampf(c, 0.15, 1.0)
		opp.over = c
		opp.finesse = inp.finesse_held
		if inp.get("trick", false) and not opp.finesse:
			# Y + R2: Stick zur Anlaufseite = Dreh-Schlag hinter dem Kopf, sonst Schwachhand-Angriff.
			var hl0 := team_local(opp.team, opp.point).y
			var cut := absf(rs.x) > 0.5 and absf(hl0) > 1.0 and signf(-rs.x) == signf(hl0)
			var tk := "cutback" if cut else "offhand"
			if _trick_ok(opp.player, tk):
				_set_trick(opp, tk)
		# Gefuehlsschlag: weniger Kraft, daher etwas mehr Zeit; die Genauigkeit haengt am Timing.
		opp.win_scale = hit_window_scale(0.45 if opp.finesse else opp.power, rs, false) * (0.92 if opp.delayed else 1.0) * _trick_window(opp)
		_press(opp, e, "spike")


func _human_touch(tech: String, choice: String, t_press := -1.0) -> void:
	if opp == null or opp.pending:
		return
	var e := (t_press if t_press >= 0.0 else human_clock()) - opp.t
	if e < -maxf(0.35, windows(opp.kind)[2] * opp.win_scale + 0.05):
		return  # viel zu frueh gedrueckt: ignorieren
	opp.tech = tech
	_press(opp, e, choice)


## Frueher Druck wird gemerkt und im idealen Moment ausgefuehrt, spaeter sofort.
func _press(o: Opp, e: float, choice: String) -> void:
	if e < 0.0:
		o.pending = true
		o.press_e = e
		o.press_choice = choice
	else:
		execute_touch(o, e, choice)


func _ai_actions() -> void:
	_plan_dive()
	if opp != null and not opp.done:
		# Die Flugbahn weicht etwas von der Vorausberechnung ab (Flatterball, Bildrate): ist der Ball
		# schon fast am Boden, kommt der Kontakt jetzt (mit dem geplanten Timing-Fehler), statt dass
		# der Ball unberuehrt aufkommt. Vorher landeten so viele gute Annahmen als Ass.
		var floor_now := clock >= opp.t - 0.25 and ball.position.y < R + 0.3 and ball_vel.y < 0.0 and opp.kind in ["pass", "dig", "free"]
		if opp.pending:
			if clock >= opp.t or floor_now:
				execute_touch(opp, opp.press_e, opp.press_choice)
		elif not opp.human and (clock >= opp.t + opp.ai_e or floor_now):
			_ai_prepare(opp)
			_press(opp, opp.ai_e, drill.ai_choice(opp) if drill != null else "auto")
		elif opp.human and clock > opp.t + windows(opp.kind)[2] * maxf(opp.win_scale, 1.35 if opp.kind == "attack" else 1.0) + 0.01 + lag_game():
			opp.done = true
			charging = false
			popup(opp.player, "Zu spät", Q_COLOR[Q.MISS])
			touch_result.emit(opp.kind, opp.team, true, Q.MISS, 1.0, 0.0, opp.speed)
	if opp == null or opp.kind != "attack":
		return
	for t in 2:
		for i in blockers[t].size():
			var b: VPlayer = blockers[t][i]
			if t == human_team and i <= 1 and (drill == null or drill.human_does("block")):
				continue  # der Mensch steuert beide Blocker im Doppelblock
			if opp.team != t and not b.has_jumped and clock >= b.block_jump_at:
				b.jump()
				_ai_block_hands(t, b)


## KI-Blocker: liest mit etwas Glueck die Schlagrichtung und schiebt die Haende dorthin.
func _ai_block_hands(t: int, b: VPlayer) -> void:
	if opp == null:
		return
	var read_p := 0.3 if t == human_team else lerpf(0.1, 0.5, cfg.unit("ai_block"))
	var read := rng.randf() < read_p
	var shift := rng.randf_range(-0.3, 0.3)
	var pz = _predicted_cross_z(t)  # K2: Lieblingsrichtung des Angreifers
	if not read and pz != null:
		shift = clampf(float(pz) - b.position.z, -0.45, 0.45)
	elif read:
		var info := attack_shot(opp.team, opp.point, opp.rs, opp.power, opp.finesse)
		var tgt: Vector3 = info.target
		# Wo kreuzt die Linie Ball -> Ziel das Netz?
		var f := absf(opp.point.x) / maxf(absf(opp.point.x - tgt.x), 0.01)
		var zc := lerpf(opp.point.z, tgt.z, f)
		shift = clampf(zc - b.position.z, -0.45, 0.45)
	b.hand_shift = shift
	if t != human_team:
		b.hand_reach = 0.12 if rng.randf() < 0.12 else 0.0


func _ai_prepare(o: Opp) -> void:
	match o.kind:
		"attack":
			_ai_attack_choice(o)
		"set":
			o.tech = "over" if o.speed <= OVER_OK else "bump"
			if o.player.role == "L" and absf(o.point.x) < 3.0:
				o.tech = "bump"  # Libero pritscht vor der 3-m-Linie nicht (Regel)
		"pass", "free":
			o.tech = "over" if o.speed <= OVER_OK and rng.randf() < 0.5 else "bump"
		_:
			o.tech = "bump"


## KI-Angreifer: waehlt Trefferpunkt und Kraft. Steht ein Block im Weg, sucht er oft
## eine andere Richtung (er "liest" den Block).
func _ai_attack_choice(o: Opp) -> void:
	var hl := team_local(o.team, o.point).y
	# Wer links steht, trifft den Ball links, damit er diagonal nach rechts fliegt.
	var cross := -0.55 if hl < 0.0 else 0.55
	if absf(hl) < 1.5:
		cross = 0.45 if rng.randf() < 0.5 else -0.45
	var options := [Vector2(0.0, 0.3), Vector2(cross, 0.4), Vector2(cross * 0.6, 0.8), Vector2(cross * 0.25, 0.5)]
	var pp: AiPlan = plan(o.team)
	# K2: Richtungen, die zuletzt geblockt oder abgewehrt wurden, kommen nach hinten.
	var lane: String = o.player.lane
	options.sort_custom(func(a, b): return pp.avoid(lane, _shot_dir(o, a)) < pp.avoid(lane, _shot_dir(o, b)))
	var r := rng.randf()
	if r < pp.tip:
		# Leger in die Luecke: dorthin, wo am wenigsten Abwehr steht.
		options.push_front(_gap_contact(o, [Vector2(-0.8, -0.7), Vector2(-0.4, -0.75), Vector2(0.0, -0.7), Vector2(0.4, -0.75), Vector2(0.8, -0.7)], false))
		stats["KI Leger in Luecke"] = stats.get("KI Leger in Luecke", 0) + 1
	elif r < pp.tip + 0.05 and not o.emergency:
		# V-2: Gefuehlsschlag in die tiefe Ecke, die frei ist (nur mit dem Hecht zu erreichen).
		o.rs = _gap_contact(o, [Vector2(-0.6, 0.8), Vector2(0.6, 0.8)], true)
		o.finesse = true
		o.power = rng.randf_range(0.5, 0.75)
		o.over = o.power
		stats["KI Ecke"] = stats.get("KI Ecke", 0) + 1
		return
	elif r < pp.tip + 0.06 + 0.05:
		options.push_front(Vector2(signf(cross) * 0.95, 0.0))  # Cut Shot
	elif r < pp.tip + 0.15 and absf(hl) > 1.5:
		options.push_front(Vector2(-signf(cross) * 0.95, 0.5))  # Block-Out
	else:
		var first: Vector2 = options[0]
		for cand in options:
			if rng.randf() >= pp.avoid(lane, _shot_dir(o, cand)):
				first = cand
				break
		if rng.randf() < 0.35:
			first = options[rng.randi() % options.size()]
		options.push_front(first)
	o.finesse = false
	# KI-Stars: manchmal ein 5-Sterne-Move (Schwachhand oder Dreh-Schlag).
	if not o.emergency and rng.randf() < 0.05 * pls(o.player, "beidhaender"):
		_set_trick(o, "offhand")
	elif not o.emergency and absf(hl) > 1.5 and rng.randf() < 0.05 * pls(o.player, "winkel"):
		_set_trick(o, "cutback")
	o.power = rng.randf_range(pp.attack_power.x, pp.attack_power.y)
	o.over = o.power
	o.rs = options[0]
	if rng.randf() < pp.block_read:
		for cand in options:
			if not _shot_blocked(o, cand):
				o.rs = cand
				break
	# Steht der Block trotzdem im Weg, spielt die KI manchmal einen Gefuehlsschlag darueber.
	if not o.emergency and _shot_blocked(o, o.rs) and rng.randf() < pp.finesse:
		o.finesse = true
		o.rs = Vector2(0.0, 0.8) if rng.randf() < 0.4 else Vector2(0.0, 0.2)
	# S3 auch fuer die KI: dichter Block und schlechtes Zuspiel, dann manchmal in den Block legen.
	if not o.finesse and not o.emergency and _shot_blocked(o, o.rs) and rng.randf() < 0.12 * (1.0 + pp.finesse):
		o.finesse = true
		o.rs = Vector2(0.0, -0.8)


## V-2: Unter mehreren Trefferpunkten den waehlen, dessen Landepunkt am weitesten von der
## naechsten Abwehrspieler entfernt ist (die KI sieht, wo Luecken sind).
func _gap_contact(o: Opp, cands: Array, finesse: bool) -> Vector2:
	var best: Vector2 = cands[0]
	var bs := -1.0
	for cv in cands:
		var c: Vector2 = cv
		var info := attack_shot(o.team, o.point, c, 0.6, finesse)
		if not info.has("target"):
			continue
		var tg: Vector3 = info.target
		var near := 1e9
		for pl in players[1 - o.team]:
			near = minf(near, flat_dist(pl.position, tg))
		var sc := near + rng.randf_range(0.0, 0.6)  # nicht immer exakt dieselbe Stelle
		if sc > bs:
			bs = sc
			best = c
	return best


# ---------------------------------------------------------------- K1/K2: Spielplan und Gedaechtnis

## Spielplan eines Teams (beim ersten Gebrauch im Spiel aus den Spielerwerten gebaut).
func plan(t: int) -> AiPlan:
	if plans[t] == null:
		var pp := AiPlan.new()
		var datas: Array = []
		for pl in players[t]:
			var d := pdata(pl)
			if d != null:
				datas.append(d)
		pp.build(datas, absi(hash(str(TEAM_NAMES[t]))))
		pp.adapt = lerpf(0.3, 1.0, cfg.unit("ai_block"))  # leichter Gegner passt sich weniger an
		plans[t] = pp
		if autoplay or trace:
			print("Spielplan T%d %s: %s (+%s) Sprung %.2f Kraft %s schwach %.2f Tempo %.2f" % [t, TEAM_NAMES[t], pp.archetype, pp.second, pp.serve_jump, pp.serve_power, pp.serve_weak, pp.tempo_fast])
	return plans[t]


## Vor dem Spiel: was fuer ein Gegner wartet (K1, Scouting).
func _scouting_banner() -> void:
	return  # Spielplan des Gegners: keine Einblendung mehr (kein Text im Spiel), steht im Pausenmenue


## Kurzer Text fuer die Anzeige "Gegner" im Pausenmenue oder in Hinweisen.
func scouting_text(t: int) -> String:
	var pp := plan(t)
	return "%s: %s" % [pp.title, pp.desc]


## KI-Aufschlag nach Spielplan: Art, Risiko und Ziel (oft der schwaechste Annahmespieler).
func _ai_serve_choice() -> void:
	var pp := plan(serving_team)
	var rt := 1 - serving_team
	serve_kind = 1 if rng.randf() < pp.serve_jump else 0
	_skyball = false
	var r := rng.randf()
	if serve_kind == 1:
		serve_contact = Vector2(rng.randf_range(-0.3, 0.3), 0.7) if r < 0.6 else Vector2(rng.randf_range(-0.2, 0.2), 0.0)
	else:
		serve_contact = Vector2(rng.randf_range(-0.2, 0.2), 0.0)
		if rng.randf() < pp.serve_short:
			serve_contact = Vector2(0.0, -0.7)
	serve_aim = Vector2(rng.randf_range(4.0, 7.5), rng.randf_range(-3.2, 3.2))
	if rng.randf() < pp.serve_weak:
		var wk := _weak_receiver(rt, pp)
		if wk != null:
			var tl := team_local(serving_team, wk.target)
			serve_aim = Vector2(clampf(-tl.x + rng.randf_range(-0.7, 0.7), 3.5, 8.2), clampf(tl.y + rng.randf_range(-0.6, 0.6), -3.9, 3.9))
			stats["KI-Aufschlag auf Schwaechsten"] = stats.get("KI-Aufschlag auf Schwaechsten", 0) + 1
	if rng.randf() < 0.04 * pls(server(), "taktiker"):
		serve_kind = 0
		_skyball = true  # KI-Star: Skyball
		stats["Move skyball"] = stats.get("Move skyball", 0) + 1
	elif rng.randf() < 0.3 + 0.4 * cfg.unit("ai_block"):
		# V-5: in die Luecke zwischen zwei Annahmespieler.
		var gap := _ai_serve_gap(rt)
		if gap != Vector2.INF:
			serve_aim = gap
			stats["KI-Aufschlag in Luecke"] = stats.get("KI-Aufschlag in Luecke", 0) + 1
	# V-5: steht die Annahme weit hinten, kommt oefter ein kurzer Aufschlag.
	if serve_kind == 0 and serve_contact.y > -0.5 and _rcv_depth(rt) > 6.3 and rng.randf() < 0.25:
		serve_contact = Vector2(0.0, -0.7)
		stats["KI-Aufschlag kurz (Annahme tief)"] = stats.get("KI-Aufschlag kurz (Annahme tief)", 0) + 1


## Mitte zwischen zwei benachbarten Annahmespielern (als Aufschlagziel des Gegners), sonst INF.
func _ai_serve_gap(rt: int) -> Vector2:
	var ps: Array = []
	for pl in players[rt]:
		if pl.role != "S" and _rcv_cache[rt].get("passers", []).has(pl.slot):
			ps.append(team_local(rt, pl.target))
	if ps.size() < 2:
		return Vector2.INF
	var best := Vector2.INF
	var bd := 1e9
	for i in ps.size():
		for j in range(i + 1, ps.size()):
			var a: Vector2 = ps[i]
			var b: Vector2 = ps[j]
			var dd := a.distance_to(b)
			if dd < 1.8 or dd > 4.5:
				continue
			var m := (a + b) * 0.5
			var sc := absf(dd - 3.0) + rng.randf_range(0.0, 1.0)
			if sc < bd:
				bd = sc
				best = Vector2(clampf(m.x, 3.5, 8.2), clampf(m.y, -3.9, 3.9))
	return best


## Mittlere Tiefe der Annahmespieler (Abstand zum Netz).
func _rcv_depth(rt: int) -> float:
	var s := 0.0
	var n := 0
	for pl in players[rt]:
		if pl.role != "S" and _rcv_cache[rt].get("passers", []).has(pl.slot):
			s += team_local(rt, pl.target).x
			n += 1
	return s / n if n > 0 else 0.0


## Schwaechster Annahmespieler (kein Libero, kein Zuspieler): Annahmewert, und wer in diesem
## Spiel schon oft schlecht angenommen hat (Gedaechtnis), zaehlt doppelt.
func _weak_receiver(rt: int, pp: AiPlan) -> VPlayer:
	var bad := pp.weakest_receiver()
	var best: VPlayer = null
	var bs := 1e9
	for pl in players[rt]:
		if pl.role in ["L", "S"]:
			continue
		if not _rcv_cache[rt].get("passers", []).has(pl.slot):
			continue
		var s := pf(pl, "receive")
		if bad == str(pl.get_instance_id()):
			s -= 1.0
		if s < bs:
			bs = s
			best = pl
	return best


## Richtung eines moeglichen Angriffs (line / cross / soft) aus Sicht des Angreifers.
func _shot_dir(o: Opp, contact: Vector2) -> String:
	var info := attack_shot(o.team, o.point, contact, o.power, o.finesse)
	return AiPlan.attack_dir(info.style, team_local(o.team, o.point).y, team_local(o.team, info.target).y)


var _k2_att: VPlayer = null
var _k2_time := -10.0
var _k2_pred = null  # Weltkoordinate z, wo der Block die Lieblingsrichtung zustellt, oder null
var _k2_soft := 0.0  # wie stark die Abwehr den Leger erwartet


## K2: Liest der Block die Lieblingsrichtung des Angreifers? Einmal je Angriff entschieden
## (Block und Haende sind sich einig), nur fuer KI-Teams.
func _predicted_cross_z(def: int, att: VPlayer = null, point = null):
	if def == human_team:
		return null
	if att == null and opp != null and opp.kind == "attack" and opp.team != def:
		att = opp.player
		point = opp.point
	if att == null or point == null:
		return null
	if att == _k2_att and clock - _k2_time < 2.5:
		return _k2_pred
	_k2_att = att
	_k2_time = clock
	_k2_pred = null
	_k2_soft = 0.0
	var pp := plan(def)
	var lane: String = att.lane
	var tend := pp.tendency(lane)
	var s := pp.read_strength(lane)
	for d in ["line", "cross", "soft"]:
		if d != tend[0] or s < 0.35:
			pp.should_show(lane + "|" + d, false)
	if s <= 0.0 or rng.randf() >= s:
		return null
	var dir: String = tend[0]
	var mb := _lane_player(def, "mid")
	if pp.should_show(lane + "|" + dir, s >= 0.35) and mb != null:
		popup(mb, ("Abwehr erwartet Leger" if dir == "soft" else "Block stellt %s zu" % AiPlan.dir_text(dir)), Color(0.85, 0.85, 1.0))
	stats["KI liest " + dir] = stats.get("KI liest " + dir, 0) + 1
	if dir == "soft":
		_k2_soft = 1.0
		return null
	var p3: Vector3 = point
	var hl := team_local(att.team, p3).y
	var side := signf(hl) if absf(hl) > 0.5 else 1.0
	var l := side * 3.6 if dir == "line" else -side * 3.0
	if absf(hl) < 1.5:
		l = hl if dir == "line" else -side * 3.4
	var tgt := court_pos(att.team, Vector2(-7.0, l))
	var f := absf(p3.x) / maxf(absf(p3.x - tgt.x), 0.01)
	_k2_pred = lerpf(p3.z, tgt.z, f)
	return _k2_pred


## K2 in der Abwehr: Hinterspieler ruecken zur erwarteten Richtung, beim erwarteten Leger kommt
## ein Spieler nach vorn. Vor dem gegnerischen Zuspiel lauert der Mittelblocker auf der
## Lieblingsbahn des Gegners.
func _k2_defense(t: int) -> void:
	if t == human_team or opp == null or opp.team == t:
		return
	if opp.kind == "set":
		var lean := plan(t).lane_lean()
		if lean[1] > 0.0 and lean[0] in ["left", "right"]:
			var mb := _lane_player(t, "mid")
			if mb != null and not mb.airborne:
				var lz := court_pos(opp.team, Vector2(1.0, -3.6 if lean[0] == "left" else 3.6)).z
				mb.target.z = lerpf(mb.target.z, lz, 0.4 * float(lean[1]))
				if plan(t).should_show("lane|" + str(lean[0]), float(lean[1]) > 0.5):
					popup(mb, "Block erwartet " + ("Außen" if lean[0] == "left" else "Diagonal"), Color(0.85, 0.85, 1.0))
					stats["KI lauert Bahn"] = stats.get("KI lauert Bahn", 0) + 1
		return
	if opp.kind != "attack":
		return
	var pz = _predicted_cross_z(t)
	for pl in players[t]:
		if pl in blockers[t] or is_front_row(pl) or is_down(pl):
			continue
		if pz != null:
			# Die Lieblingsrichtung geht hinter dem Block weiter: dorthin ruecken.
			var tz: float = lerpf(opp.point.z, float(pz), 2.2)
			pl.target.z = lerpf(pl.target.z, clampf(tz, -4.2, 4.2), 0.3)
		elif _k2_soft > 0.0 and pl.slot == 6:
			pl.target = pl.target.lerp(court_pos(t, Vector2(4.0, team_local(t, opp.point).y * 0.5)), 0.7)


## Gedaechtnis fuettern: Angriffe, Bahnen, Annahmen; eigene Angriffe, die abgewehrt wurden.
func _observe_touch(o: Opp, q: int, tgt: Vector3) -> void:
	var other := 1 - o.team
	match o.kind:
		"attack":
			var key := last_shot_style if o.tech_key == "" or o.tech_key == "clean" else o.tech_key
			var dir := AiPlan.attack_dir(key, team_local(o.team, o.point).y, team_local(o.team, tgt).y)
			plan(other).observe_attack(o.player.lane, dir)
			_last_attack = {"team": o.team, "lane": o.player.lane, "dir": dir, "call": _play_info[o.team].get("call", "")}
			_rally_pattern.append("%s-%s-%s" % [set_tempo[o.team], o.player.lane, dir])
		"pass":
			plan(other).observe_reception(str(o.player.get_instance_id()), q)
		"dig":
			if not _last_attack.is_empty() and _last_attack.team != o.team and q <= Q.GOOD:
				plan(_last_attack.team).observe_own(_last_attack.lane, _last_attack.dir, true)
				if _last_attack.get("call", "") != "":
					plan(_last_attack.team).observe_own("play", _last_attack.call, true)
				_last_attack = {}


func _observe_rally_end(winner: int, reason: String) -> void:
	if not _last_attack.is_empty():
		plan(_last_attack.team).observe_own(_last_attack.lane, _last_attack.dir, winner != _last_attack.team)
		if _last_attack.get("call", "") != "":
			plan(_last_attack.team).observe_own("play", _last_attack.call, winner != _last_attack.team)
	_last_attack = {}
	# Messung gegen "Schema F": Ablauf des Ballwechsels (erster Angriff und Zahl der Angriffe).
	if autoplay or trace:
		var first: String = _rally_pattern[0] if not _rally_pattern.is_empty() else "ohne Angriff"
		var key := "Muster %s |%d" % [first, mini(_rally_pattern.size(), 3)]
		stats[key] = stats.get(key, 0) + 1
	_rally_pattern = []


func _shot_blocked(o: Opp, contact: Vector2) -> bool:
	var info := attack_shot(o.team, o.point, contact, o.power, o.finesse)
	var tgt: Vector3 = info.target
	var f := absf(o.point.x) / maxf(absf(o.point.x - tgt.x), 0.01)
	var zc := lerpf(o.point.z, tgt.z, f)
	for b in blockers[1 - o.team]:
		# Noch nicht abgesprungen: dort, wo der Blocker gerade hinlaeuft.
		var bz: float = b.hands_z() if b.airborne else b.target.z
		if absf(zc - bz) < 0.5:
			return true
	return false


# ---------------------------------------------------------------- Ballberuehrungen

## Hecht: so weit reichen die gestreckten Arme aus dem Flug (Koerper -> Ball, m).
const DIVE_ARM := 1.15
const DIVE_LEAD := 0.3
static var _dive_trace := OS.get_cmdline_user_args().has("--dive-trace")  # Test: Hechte ausgeben  # so lange vor dem Kontakt springt ein Spieler zum Hecht ab


func dive_arm(o: Opp) -> float:
	return DIVE_ARM + 0.12 * pf(o.player, "defense") + 0.08 * pls(o.player, "katze") + 0.18 * pls(o.player, "hecht") \
			+ (0.45 if o.trick == "one_arm" else 0.0)  # einarmige Rettung


## Weitester Hechtflug der Technik (m), gute Abwehrspieler fliegen weiter.
func dive_max(o: Opp) -> float:
	var base := {"sprawl": 1.6, "dive_side": 1.8, "pancake": 2.1}.get(o.style, 1.6) as float
	return base + 0.3 * pf(o.player, "defense")


## Den Hecht zu diesem Ball wirklich starten: Abdruck jetzt, Kontakt zum geplanten Zeitpunkt.
func launch_dive(o: Opp) -> void:
	var pl := o.player
	if o.launched or pl.dive_timer > 0.0 or pl.airborne:
		return  # in der Luft (Block) kein Abdruck moeglich: dann wie frueher ohne Flug
	pl.anim_t = o.t
	pl.anim_style = o.trick if o.trick != "" else o.style
	pl.start_dive(Vector3(o.point.x, 0.0, o.point.z), dive_arm(o) * 0.95, dive_max(o))
	o.launched = true
	if _dive_trace:
		print("START %s t_left=%.3f T=%.2f D=%.2f v0=%.2f clock=%.3f" % [pl.role, o.t - clock, pl._dv_T, pl._dv_D.length(), pl._dv_v0.length(), clock])
	stats["Hecht geflogen"] = stats.get("Hecht geflogen", 0) + 1


## Vorausgeplanter Hecht (KI und Hechthilfe): kurz vor dem Kontakt pruefen, ob der Spieler nur
## mit einem Hecht hinkommt, und dann rechtzeitig abspringen statt erst im Kontakt umzufallen.
func _plan_dive() -> void:
	var o := opp
	if o == null or o.done or o.launched or o.dove or not (o.kind in ["pass", "dig", "free"]):
		return
	var pl := o.player
	if pl.dive_timer > 0.0 or pl.airborne or is_down(pl):
		return
	if o.human and not cfg.assisted("dive"):
		return
	var t_left := o.t - clock
	if t_left > DIVE_LEAD or t_left < 0.08:
		return
	var st := recv.filter_style(o, _defense_style(o)) if o.human else _defense_style(o)
	if not Technique.goes_down(st):
		return
	o.style = st
	o.style_locked = true
	launch_dive(o)


func execute_touch(o: Opp, e: float, choice: String) -> void:
	o.done = true
	last_trick = o.trick
	if o.trick != "" and (trace or autoplay):
		print("MOVE-KONTAKT %s style=%s tick=%d" % [o.trick, str(o.player.anim_style), Engine.get_physics_frames()])
	var pl := o.player
	if o.human and o.kind in ["pass", "dig", "free"]:
		recv.before_touch(o)
	var q := classify(e, o.kind, o.win_scale)
	var reach := 1.25
	match o.kind:
		"dig":
			reach = 1.7
		"set":
			reach = 1.1
		"attack":
			reach = 1.0
	var horiz := flat_dist(pl.position, o.point)
	var defense := o.kind in ["pass", "dig", "free"]
	if defense:
		# Die Technik bestimmt die Reichweite: wer zu weit weg ist, muss sich strecken oder hechten.
		if not o.style_locked or horiz > Technique.reach(o.style):
			var st := recv.filter_style(o, _defense_style(o))
			if Technique.reach(st) > Technique.reach(o.style):
				o.style = st
		var cap := {"pass": 1.25, "free": 1.4, "dig": 2.0}[o.kind] as float
		reach = minf(Technique.reach(o.style), cap) if o.style != "" else 0.75
		reach = recv.reach(o, maxf(reach, 0.75))
		if o.launched:
			# Echter Hecht: der Koerper ist hingeflogen, es zaehlt der Abstand der gestreckten Arme.
			reach = dive_arm(o)
		pl.anim_style = o.trick if o.trick != "" else o.style
	if o.no_reach and pl.dive_timer <= 0.0:
		pl.dive()
	if o.launched and _dive_trace:
		print("HECHT clock=%.3f dt=%.2f %s %s q=%s e=%.3f horiz=%.2f reach=%.2f style=%s dist0=%.2f" % [clock, pl.dive_timer, pl.role, o.kind, Q_TEXT[q], e, horiz, reach, o.style, pl._dv_from.distance_to(Vector3(o.point.x, 0, o.point.z))])
	if q == Q.MISS or horiz > reach or o.no_reach:
		if o.launched:
			stats["Hecht verfehlt"] = stats.get("Hecht verfehlt", 0) + 1
		if trace:
			print("  T%d %s %s VERFEHLT q=%s e=%.3f horiz=%.2f" % [o.team, pl.role, o.kind, Q_TEXT[q], e, horiz])
		var txt := "Zu früh" if e < 0.0 else "Zu spät"
		if q != Q.MISS:
			txt = "Nicht erreicht"
		popup(pl, txt, Q_COLOR[Q.MISS])
		touch_result.emit(o.kind, o.team, o.human, Q.MISS, e, 0.0, o.speed)
		return
	# Pritschen: genau, aber nur bei Baellen, die nicht zu hart kommen.
	if o.kind != "attack" and o.tech == "over":
		# Fehler nur aus dem eigenen Spiel: einen sehr harten Ball pritschen und nicht genau treffen
		# = gehalten; einen Ball weit neben dem Timing pritschen = Doppelberuehrung. Baggern ist sicher.
		var fk := cfg.unit("faults")
		if o.speed > OVER_RISKY:
			if fk > 0.0 and q != Q.PERFECT and o.speed > OVER_RISKY + 6.0 * (1.0 - fk):
				_fault(o, "Ball gehalten (zu hart zum Pritschen)")
				return
			q = mini(q + 2, Q.WEAK)
		elif o.speed > OVER_OK:
			q = mini(q + 1, Q.WEAK)
		var w := windows(o.kind)
		if o.kind == "set" and q == Q.WEAK and fk > 0.0 and absf(e) > lerpf(w[1], w[2], 0.75 + 0.25 * (1.0 - fk)) * o.win_scale:
			_fault(o, "Doppelberührung (Timing)")
			return
	# Regeln: Hinterspieler duerfen nicht aus der Vorderzone angreifen, und nach einem Libero-
	# Zuspiel (Pritschen vor der 3-m-Linie) darf nicht ueber Netzhoehe angegriffen werden.
	var libero_flag: bool = libero_set_front[o.team]
	libero_set_front[o.team] = false
	var safe_over: bool = o.kind == "attack" and choice == "free"
	if o.kind == "attack" and not safe_over:
		if not is_front_row(pl) and pl.takeoff_x < 2.95:
			_fault(o, "Hinterspielerfehler")
			return
		if libero_flag:
			_fault(o, "Liberofehler")
			return
	elif o.kind == "set" and pl.role == "L" and o.tech == "over" and absf(o.point.x) < 3.0:
		libero_set_front[o.team] = true
	if defense:
		# Folgen der Technik: nach Hecht oder Sprawl liegt der Spieler kurz, der Ball wird ungenauer.
		if Technique.goes_down(o.style) and pl.dive_timer <= 0.0:
			pl.dive()  # nur noch, wenn der Hecht nicht schon vorher angesetzt wurde
		pl.down_until = clock + Technique.recovery(o.style)
		q = maxi(q, Technique.best_quality(o.style))
		if o.style != "":
			stats["Technik " + o.style] = stats.get("Technik " + o.style, 0) + 1
		if trace or autoplay:
			var bk := "Druck %s %.1f" % [o.kind, minf(floorf(o.pressure * 10.0) / 10.0, 1.2)]
			stats[bk] = stats.get(bk, 0) + 1
	if o.kind == "dig" and last_touch_team != o.team:
		var dk: String = "Abgewehrt nach " + ("Block" if last_action == "block" else ("Angriff" if last_action == "attack" else last_action))
		stats[dk] = stats.get(dk, 0) + 1
	if possession != o.team:
		possession = o.team
		touches = 0
	touches += 1
	touch_total += 1
	last_toucher = pl
	last_touch_team = o.team
	net_touched = false
	var label: String = Q_TEXT[q]
	if o.human and o.kind != "attack":
		label = ("Pritschen · " if o.tech == "over" else "Baggern · ") + label
	if defense:
		pass_kind[o.team] = ""
	if defense and o.human:
		recv.done(o, q)
	if o.human:
		label += timing_hint(e, q)
	popup(pl, label, Q_COLOR[q])
	var before := ball.position
	var was_flutter := flutter > 0.0 and last_action == "serve"
	flutter = 0.0
	ball_g = G
	match o.kind:
		"pass", "dig":
			_do_pass(o, q, e, was_flutter)
		"set":
			_do_set(o, q, e, choice)
		"attack":
			if safe_over:
				_do_free(o, q)
				stats["Sicher rüber"] = stats.get("Sicher rüber", 0) + 1
			else:
				_do_attack(o, q, e)
		"free":
			_do_free(o, q)
	rally_touches += 1
	if o.kind == "attack" and not safe_over:
		var kind_fx := "tip" if last_action == "tip" else "spike"
		if kind_fx == "spike" and last_super:
			kind_fx = "spike_super"  # Wuchtschlag: noch tieferer Knall, Controller vibriert
		elif kind_fx == "spike" and o.human and q == Q.PERFECT and o.power > 0.75:
			kind_fx = "spike_perfect"  # lauter, tiefer Knall
		_fx(kind_fx, before, clampf(ball_vel.length() / 30.0, 0.3, 1.0))
	else:
		_fx("set" if o.tech == "over" else "bump", before, clampf(o.speed / 20.0, 0.25, 1.0))
	stats["Technik " + ("Pritschen" if o.tech == "over" else "Baggern")] = stats.get("Technik " + ("Pritschen" if o.tech == "over" else "Baggern"), 0) + (1 if o.kind != "attack" else 0)
	if trace:
		print("  T%d %s %s %s q=%s e=%.3f pos=%s vel=%s" % [o.team, pl.role, o.kind, o.tech, Q_TEXT[q], e, before, ball_vel])
	_log_touch(o, q)
	touch_result.emit(o.kind, o.team, o.human, q, e, ball_vel.length(), o.speed)
	plan_next()


## Nach jedem Kontakt: Technik melden (Name in der Anzeige) und den Kontakt fuer die KI loggen.
func _log_touch(o: Opp, q: int) -> void:
	if o.tech_key != "":
		technique_done.emit(o.player, o.tech_key)
	var lt := Ballistics.time_to_height(ball.position, ball_vel, R, ball_g)
	var tgt := Ballistics.pos_at(ball.position, ball_vel, lt, ball_g) if lt > 0.0 else ball.position
	touch_logged.emit(o.team, {"kind": o.kind, "key": o.tech_key, "lane": o.player.lane, "target": tgt,
		"tempo": set_tempo[o.team], "quality": q, "approach": o.approach, "human": o.human})
	_observe_touch(o, q, tgt)


## Tastenhinweis: einmal pro Annahme melden, welche neuen Techniken gerade gehen.
func _reception_hints(o: Opp) -> void:
	if o.hinted or o.t - clock > 1.2:
		return
	o.hinted = true
	for k in recv.available(o):
		technique_available.emit(k)


func _fault(o: Opp, reason: String) -> void:
	popup(o.player, reason, Q_COLOR[Q.MISS])
	last_touch_team = o.team
	_end_rally(1 - o.team, reason)


func _do_pass(o: Opp, q: int, e: float, was_flutter: bool) -> void:
	pass_quality = q
	# Zu frueh: Ball geht Richtung Netz (oder sogar rueber). Zu spaet: zu weit nach hinten.
	# V-2: eine harte Annahme zu frueh genommen springt weiter Richtung Netz, auch mal rueber.
	var ex0 := excess(e, o.kind, o.win_scale)
	var d := SETTER_TARGET.x + ex0 * 8.0 * (1.0 + (0.8 * hard_ball(o.speed) if ex0 < 0.0 else 0.0))
	var l := SETTER_TARGET.y
	var spread := 0.0
	if q == Q.GOOD:
		spread = 0.7
	elif q == Q.WEAK:
		spread = 1.8
	if o.kind == "dig":
		var hb := hard_ball(o.speed)
		spread += 0.8 + 1.2 * hb
		d += 1.2 + 1.0 * hb
	if was_flutter:
		spread += 0.4
	if o.tech == "over" and o.speed <= OVER_OK:
		spread *= 0.6
	spread *= clampf(1.0 - 0.25 * _touch_skill(o.player, o.kind), 0.6, 1.4)
	# Ungenau, aber nicht zufaellig: zu frueh = Ball naeher ans Netz, zu spaet = weiter weg; seitlich
	# dorthin, wohin die Arme gekippt waren (Ball neben dem Koerper getroffen).
	var ed := _err_dir(e, o.kind, o.win_scale)
	var side := clampf(team_local(o.team, o.point).y - team_local(o.team, o.player.position).y, -0.6, 0.6) / 0.6
	# Annahme gelenkt (A1) oder frontal (A2): Ziel, Hoehe und Streuung anpassen.
	var mods := recv.pass_mods(o, {"d": d, "l": l, "spread": spread, "side": side, "T_mul": 1.0, "h": H_SET, "ex_mul": 1.0})
	d = mods.d + excess(e, o.kind, o.win_scale) * 8.0 * (mods.ex_mul - 1.0)
	l = mods.l
	spread = mods.spread
	side = mods.side
	var off := Vector2(ed * spread * 0.6, side * spread * 0.8)
	var target := court_pos(o.team, Vector2(d + off.x, l + off.y))
	target.y = mods.h
	if o.trick == "one_arm":
		target.y += 1.0  # einarmig gerettet: der Ball geht hoch, damit das Team Zeit hat
	if signf(target.x) != side_of(o.team):
		stats["Overpass"] = stats.get("Overpass", 0) + 1
	var dist := flat_dist(target, ball.position)
	var T: float = clampf(0.9 + dist / 7.0, 1.0, 1.8) * float(mods.T_mul)
	if q == Q.WEAK:
		T *= 0.85
	ball_vel = Ballistics.launch_with_time(ball.position, target, T)
	last_action = "pass"


## choice = "<Richtung>|<Tempo>": Richtung auto/left/right/mid/back (rechter Stick),
## Tempo high (hoher Ball), fast (schneller Ball), quick (Schnellangriff) oder dump
## (der Zuspieler spielt den Ball selbst ueber das Netz).
func _do_set(o: Opp, q: int, e: float, choice: String) -> void:
	var setter := o.player
	var parts := choice.split("|")
	var lane_choice: String = parts[0]
	var tempo: String = parts[1] if parts.size() > 1 else "auto"
	if tempo == "auto":
		tempo = _ai_set_tempo(o, q)
	tempo = recv.set_tempo_after_pass(o, tempo)
	var bump_set := o.tech != "over"
	if tempo in ["fast", "quick"] and (bump_set or q == Q.WEAK):
		if o.human:
			popup(setter, "Nur hoher Ball" if bump_set else "Ball zu schlecht", Q_COLOR[Q.WEAK])
		tempo = "high"
	# Folgen der Annahme: Wer nicht der Zuspieler ist oder erst im letzten Moment ankommt, spielt
	# nur einen hohen Ball nach aussen; wer gerade noch angekommen ist, schafft keinen Schnellangriff.
	var out_of_system := setter.role != "S" or o.slack < 0.2
	if out_of_system and tempo in ["fast", "quick"]:
		if o.human:
			popup(setter, "Keine Zeit: hoher Ball", Q_COLOR[Q.WEAK])
		tempo = "high"
	elif o.slack < 0.6 and tempo == "quick":
		if o.human:
			popup(setter, "Zu spät für Schnellangriff", Q_COLOR[Q.WEAK])
		tempo = "fast"
	if out_of_system and lane_choice == "mid":
		lane_choice = "left"
	set_q[o.team] = q
	if (tempo == "dump" or tempo == "attack") and o.human:
		stats["Mensch 2. Ball moeglich" if _can_dump(o) else "Mensch 2. Ball nicht moeglich"] = stats.get("Mensch 2. Ball moeglich" if _can_dump(o) else "Mensch 2. Ball nicht moeglich", 0) + 1
	if (tempo == "dump" or tempo == "attack") and not _can_dump(o):
		if o.human:
			popup(setter, "Dump nicht möglich" if tempo == "dump" else "Schlag nicht möglich", Q_COLOR[Q.WEAK])
		tempo = "high"
	if tempo == "dump":
		_do_dump(o, q, lane_choice if not o.human else _dump_lane(o))
		return
	if tempo == "attack":
		_do_setter_attack(o, q, e, lane_choice)
		return
	var sl := team_local(o.team, setter.position)
	# V-1 Spielzug: angesagt (Y + Steuerkreuz) oder von der KI gewaehlt. Nur aus einer guten Lage
	# (Zuspieler da, Annahme nicht schwach, gepritscht); sonst gibt es nur den hohen Ball.
	var call: String = play_call[o.team]
	play_call[o.team] = ""
	var in_sys: bool = not out_of_system and not bump_set and q != Q.WEAK and pass_quality != Q.WEAK
	if call == "" and not o.human and in_sys and tempo in ["high", "fast", "quick"] \
			and rng.randf() < 0.25 + 0.4 * plan(o.team).tempo_fast:
		call = _ai_pick_play(o.team)
	if not in_sys:
		call = ""
	var play: Dictionary = PLAYS.get(call, {})
	if not play.is_empty():
		lane_choice = _play_lane(o, call, lane_choice)
		if tempo == "high" or not o.human:
			tempo = play[lane_choice]
		stats["Spielzug " + call] = stats.get("Spielzug " + call, 0) + 1
	if tempo == "quick" and (lane_choice == "auto" or lane_choice == ""):
		lane_choice = "mid"
	var hitter := _pick_hitter(o.team, setter, lane_choice, sl)
	plan(1 - o.team).observe_set(hitter.lane)
	var d := 1.0
	var l := -3.6
	var T := 1.15
	var geo: String = hitter.lane
	if lane_choice == "slide" and hitter == _lane_player(o.team, "mid"):
		geo = "slide"
	elif lane_choice == "pipe" and hitter == _pipe_player(o.team):
		geo = "pipe"
	_set_play_info(o.team, call, geo, hitter, setter, sl)
	match geo:
		"slide":
			# Slide: der Mittelblocker laeuft hinter den Zuspieler und springt einbeinig auf Position 2.
			d = 0.8
			l = clampf(sl.y + 1.8, 1.6, 3.4)
			T = 0.8
		"pipe":
			# Pipe: Hinterfeldangriff durch die Mitte, schnell.
			d = 3.6
			l = 0.0
			T = 1.0
		"mid":
			l = sl.y - 1.0
			T = 0.6 if sl.x < 2.0 else 0.85
		"right":
			l = 3.6
			T = 0.95
		"left":
			l = -3.6
		_:
			d = 3.8  # Hinterfeldangriff hinter der 3-m-Linie
			l = -0.5
			T = 1.1
	# Tempo: hoch = viel Zeit fuer den Angreifer, aber der Block steht. Schnell und
	# Schnellangriff = der Block kommt oft zu spaet, dafuer ungenauer.
	var tempo_spread := 0.0
	var safe := tempo == "safe"
	match tempo:
		"high":
			T = maxf(T, 1.0) * 1.15
		"safe":
			# L1: extra hoch und sicher (nach schlechter Annahme), der Angreifer hat viel Zeit.
			T = maxf(T, 1.0) * 1.4
			tempo = "high"
		"fast":
			T = maxf(T * 0.82, 0.62)
			tempo_spread = 0.25
		"quick":
			T = maxf(T * 0.62, 0.5)
			tempo_spread = 0.5
	if tempo in ["fast", "quick"]:
		T *= 1.0 - 0.06 * pls(setter, "sprungzuspiel")  # PlayStyle Sprungzuspieler: Ball kommt frueher
	if o.trick == "jumpset":
		T *= 0.85
		setter.jump()  # nur falls er noch nicht abgesprungen ist (Absprung siehe _update_players)
		_play_info[o.team]["jumpset"] = true
	if bump_set:
		T = maxf(T, 0.9)  # gebaggert gibt es keinen schnellen Ball
	set_tempo[o.team] = tempo
	stats["Zuspiel " + tempo] = stats.get("Zuspiel " + tempo, 0) + 1
	if o.human and tempo != "high":
		popup(setter, "Schneller Ball" if tempo == "fast" else "Schnellangriff", Color(0.6, 0.9, 1.0))
	if o.human and o.rs.length() > 0.3:
		# Z1 Feinsteuerung mit dem rechten Stick, in Blickrichtung der Kamera gelesen.
		var k := 0.7 if not cfg.assisted("set_aim") else 0.4
		var p0 := court_pos(o.team, Vector2(d, l))
		var dl := team_local(o.team, p0 + _stick_dir(o.rs.limit_length(1.0))) - team_local(o.team, p0)
		d = maxf(d + dl.x * k, 0.35)
		l += dl.y * k
	l += excess(e, "set") * 10.0
	var spread: float = [0.15, 0.45, 1.2][q] + tempo_spread
	spread *= clampf(1.0 - 0.3 * pf(o.player, "setting"), 0.6, 1.45) * (1.0 - 0.2 * pls(o.player, "spielmacher"))
	if bump_set:
		spread = spread * 1.8 + 0.2
	if safe:
		spread *= 0.7
	# Ungenau aus dem Timing: zu frueh = enger ans Netz und kuerzer, zu spaet = weiter weg und laenger.
	var sed := _err_dir(e, "set", o.win_scale)
	l += sed * spread * signf(l if absf(l) > 0.1 else 1.0)
	d += sed * spread * 0.75
	if q != Q.WEAK:
		l = clampf(l, -4.1, 4.1)
	if d < 0.6 and _joust(o, hitter, l):
		return
	var target := court_pos(o.team, Vector2(maxf(d, 0.3), l))
	target.y = H_ATTACK + 0.1
	ball_vel = Ballistics.launch_with_time(ball.position, target, T)
	_hitter[o.team] = hitter
	last_action = "set"
	# Rueckwaerts-Zuspiel: Ziel liegt hinter dem Zuspieler (er schaut zur linken Seite).
	var behind_setter := team_local(o.team, target).y > sl.y + 1.0
	var sst := "bump" if bump_set else ("back" if behind_setter else o.style)
	setter.anim_style = o.trick if o.trick != "" else sst
	stats["Zuspiel-Technik " + (sst if sst != "" else "stand")] = stats.get("Zuspiel-Technik " + (sst if sst != "" else "stand"), 0) + 1


## Zuspiel zu eng ans Netz: Angreifer und gegnerischer Blocker springen gleichzeitig zum Ball
## (Netzkampf). Wer hoeher hinkommt, drueckt ihn auf die andere Seite. Kein Wuerfeln: Sprungkraft,
## Groesse und Reichweite entscheiden, bei Gleichstand der Blocker (er steht schon am Netz).
func _joust(o: Opp, hitter: VPlayer, l: float) -> bool:
	if hitter == null or not is_front_row(hitter):
		return false
	var z := court_pos(o.team, Vector2(0.4, l)).z
	var rival: VPlayer = null
	for pl in players[1 - o.team]:
		if is_front_row(pl) and not is_down(pl) and (rival == null or absf(pl.position.z - z) < absf(rival.position.z - z)):
			rival = pl
	if rival == null or absf(rival.position.z - z) > 2.5:
		return false
	hitter.jump()
	rival.jump()
	_net_fight(hitter, rival, Vector3(side_of(o.team) * 0.15, NET_H + 0.35, z))
	_hitter[o.team] = null
	set_q[o.team] = Q.WEAK
	return true


## Netzkampf entscheiden: wer hoeher hinkommt (Sprungkraft, Groesse, Reichweite), drueckt den Ball
## auf die andere Seite. Bei Gleichstand gewinnt b (der schon am Netz steht).
func _net_fight(a: VPlayer, b: VPlayer, from: Vector3) -> void:
	var hitter := a
	var rival := b
	var z := from.z
	var reach_h := hitter.jump_v0 * hitter.jump_v0 / (2.0 * G) + VPlayer.SPIKE_REACH + hitter.reach_add + 0.04 * pf(hitter, "power")
	var reach_r := rival.jump_v0 * rival.jump_v0 / (2.0 * G) + VPlayer.BLOCK_REACH + rival.reach_add + 0.04 * pf(rival, "block")
	var winner := hitter if reach_h > reach_r + 0.02 else rival
	var loser_team := 1 - winner.team
	hitter.anim_style = "joust"
	rival.anim_style = "joust"
	popup(winner, "Netzkampf gewonnen!", Q_COLOR[Q.GOOD])
	stats["Netzkampf"] = stats.get("Netzkampf", 0) + 1
	var target := court_pos(loser_team, Vector2(1.6, 0.0))
	target.z = clampf(z, -HALF_W + 0.5, HALF_W - 0.5)
	target.y = R
	ball.position = from
	ball_vel = Ballistics.launch_with_time(from, target, 0.75)
	possession = loser_team
	touches = 0
	last_touch_team = winner.team
	last_toucher = null
	last_action = "joust"
	block_at = clock


## Dump nur vom Zuspieler selbst: vorn am Netz, kein Libero, Ball nicht schlecht.
func _can_dump(o: Opp) -> bool:
	var pl := o.player
	return pl.role != "L" and is_front_row(pl) and absf(ball.position.x) < 2.6 and ball.position.y > NET_H - 0.7


## Setter-Dump: der Zuspieler spielt den zweiten Ball mit einer Hand ueber das Netz,
## wenn der Gegner auf die Angreifer schaut. Die Richtung kommt vom Stick.
func _do_dump(o: Opp, q: int, lane_choice: String) -> void:
	var setter := o.player
	var d := rng.randf_range(2.2, 4.0)
	var l := 0.0
	match lane_choice:
		"left":
			l = -3.2
		"right":
			l = 3.2
		"back":
			d = rng.randf_range(5.5, 7.0)
		"mid":
			d = rng.randf_range(2.0, 3.0)
		_:
			l = rng.randf_range(-3.0, 3.0)
	var spread := (0.4 if q == Q.PERFECT else (0.9 if q == Q.GOOD else 1.6)) * (1.0 - 0.25 * pls(setter, "trickser"))
	l = clampf(l + rng.randf_range(-spread, spread), -4.4, 4.4)
	d += rng.randf_range(-spread * 0.5, spread * 0.5)
	var target := court_pos(o.team, Vector2(-d, l))
	target.y = R
	ball_vel = Ballistics.launch_over_net(ball.position, target, NET_H + 0.3, 4.0, 11.0)
	_hitter[o.team] = null
	set_tempo[o.team] = "dump"
	last_action = "tip"
	setter.jump()
	popup(setter, "Dump!", Color(1.0, 0.85, 0.3))
	stats["Dump"] = stats.get("Dump", 0) + 1


## Zuspieler schlaegt den zweiten Ball selbst (R1 + R2): hart, aber weniger stark als ein
## Angreifer, und ein Mittelblocker kann ihn stoppen.
func _do_setter_attack(o: Opp, q: int, e: float, lane_choice: String) -> void:
	var setter := o.player
	if not o.human:
		var cx := 0.0
		var cy := 0.45
		match lane_choice:
			"left":
				cx = 0.5
			"right":
				cx = -0.5
			"back":
				cy = 0.85
		o.rs = Vector2(cx, cy)
		o.power = 0.78
		o.over = 0.78
	else:
		# Mensch (R2 beim zweiten Kontakt): Stick, Kraft und Timing wie bei jedem Angriff. Der
		# Zuspieler springt aus dem Stand, deshalb etwas weniger Wucht als ein Angreifer mit Anlauf.
		o.power = minf(o.power, 0.9)
	set_tempo[o.team] = "attack"
	setter.jump()
	# Schlaganimation statt Zuspiel-Haltung: Kontakt ist jetzt, der Arm schlaegt zum Ziel im Gegnerfeld.
	setter.anim_kind = "attack"
	setter.anim_tech = ""
	setter.anim_t = clock
	setter.contact_pt = ball.position
	setter.contact_aim = attack_shot(o.team, ball.position, o.rs, o.power).target
	setter.contact_on = true
	popup(setter, "Zuspieler schlägt!", Color(1.0, 0.85, 0.3))
	stats["Zuspieler-Schlag"] = stats.get("Zuspieler-Schlag", 0) + 1
	var rb := _lane_player(1 - o.team, "mid")
	var stop_p := lerpf(0.15, 0.4, cfg.unit("ai_block")) if (1 - o.team) != human_team else 0.3
	if rb != null and is_front_row(rb) and rng.randf() < stop_p:
		# Mittelblocker steht richtig: Ball wird auf die Seite des Zuspielers gedrueckt.
		var s_att := side_of(o.team)
		ball.position = Vector3(s_att * (R + 0.05), ball.position.y, ball.position.z)
		ball_vel = Vector3(s_att * rng.randf_range(1.0, 3.0), -rng.randf_range(7.0, 10.0), ball_vel.z * 0.1)
		possession = 1 - o.team
		touches = 0
		last_action = "block"
		block_at = clock
		last_touch_team = 1 - o.team
		last_toucher = null
		popup(rb, "BLOCK!", Q_COLOR[Q.PERFECT])
		stats["BLOCK!"] = stats.get("BLOCK!", 0) + 1
		_fx("block", ball.position, 1.0)
		return
	_do_attack(o, q, e)


## V-5: KI waehlt einen Spielzug; was zuletzt gelesen (geblockt, abgewehrt) wurde, kommt seltener.
func _ai_pick_play(team: int) -> String:
	var pp := plan(team)
	var ws: Array = []
	var tot := 0.0
	for k in PLAY_KEYS:
		var w := 1.0 - pp.avoid("play", k)
		ws.append(w)
		tot += w
	var r := rng.randf() * tot
	for i in PLAY_KEYS.size():
		r -= ws[i]
		if r <= 0.0:
			return PLAY_KEYS[i]
	return PLAY_KEYS[0]


## Spielzug: Richtung vom Steuerkreuz -> Position im Spielzug. Ohne Richtung (A) waehlt der
## Zuspieler selbst, meist die Hauptoption des Spielzugs.
func _play_lane(o: Opp, call: String, lane_choice: String) -> String:
	var play: Dictionary = PLAYS[call]
	var want := lane_choice
	if call == "slide" and want in ["mid", "right"]:
		want = "slide"
	elif call == "pipe" and want == "back":
		want = "pipe"
	if play.has(want):
		return want
	var keys: Array = play.keys()
	var main: String = keys[0]
	if want != "auto" and want != "":
		return main  # Richtung gehoert nicht zum Spielzug: Hauptoption
	# Automatisch: die Hauptoption, sonst eine der anderen (die Taeuscher machen es offen).
	if rng.randf() < 0.45:
		return main
	return keys[1 + rng.randi() % (keys.size() - 1)]


## Pipe-Angreifer: Aussenangreifer aus dem Hinterfeld, sonst wer hinten angreifen darf.
func _pipe_player(team: int) -> VPlayer:
	for pl in players[team]:
		if pl.role == "OH" and not is_front_row(pl) and not is_down(pl):
			return pl
	return _lane_player(team, "back")


## Nach dem Zuspiel aus einem Spielzug: alle anderen Angreifer des Spielzugs laufen als Taeuscher
## an (schnelle springen auch), und der Block muss raten, wer den Ball hat.
func _set_play_info(team: int, call: String, geo: String, hitter: VPlayer, setter: VPlayer, sl: Vector2) -> void:
	_decoys[team] = []
	_play_info[team] = {"call": call, "geo": geo, "quick_z": null, "set_quick": geo == "mid" and set_tempo_guess(call, geo) == "quick"}
	if call == "":
		return
	for lane in PLAYS[call]:
		var pl: VPlayer = _pick_lane_exact(team, lane)
		if pl == null or pl == hitter or pl == setter or is_down(pl) or pl.role == "L":
			continue
		var tmp: String = PLAYS[call][lane]
		var dl := Vector2(1.0, -3.6)
		var T := 1.2
		match lane:
			"mid":
				dl = Vector2(0.9, sl.y - 1.0)
				T = 0.55
			"slide":
				dl = Vector2(0.9, clampf(sl.y + 1.8, 1.6, 3.4))
				T = 0.75
			"right":
				dl = Vector2(1.0, 3.6)
				T = 0.75 if tmp == "fast" else 1.1
			"left":
				T = 0.75 if tmp == "fast" else 1.2
			"pipe", "back":
				dl = Vector2(3.8, 0.0 if lane == "pipe" else -0.5)
				T = 0.9
		var goal := court_pos(team, dl)
		goal.y = 0.0
		var jump: bool = tmp in ["quick", "fast"] or lane == "pipe"
		_decoys[team].append({"pl": pl, "goal": goal, "jump_at": clock + T - rise(pl) if jump else 1e9, "until": clock + T + 0.6, "jumped": false})
		if lane == "mid" and tmp == "quick":
			_play_info[team].quick_z = goal.z


func set_tempo_guess(call: String, geo: String) -> String:
	return PLAYS[call].get(geo, "") if PLAYS.has(call) else ""


func _pick_lane_exact(team: int, lane: String) -> VPlayer:
	match lane:
		"slide":
			return _lane_player(team, "mid")
		"pipe":
			return _pipe_player(team)
		"back":
			var b := _lane_player(team, "back")
			return b if b != _pipe_player(team) else null
	return _lane_player(team, lane)


## Taeuscher laufen an und springen (ohne Ball), danach zurueck in die Formation.
func _update_decoys() -> void:
	for t in 2:
		var keep: Array = []
		for dc in _decoys[t]:
			var pl: VPlayer = dc.pl
			if clock > dc.until or not is_instance_valid(pl) or phase != Phase.RALLY:
				if is_instance_valid(pl) and pl.anim_kind == "attack" and (opp == null or opp.player != pl):
					pl.anim_kind = ""
				continue
			keep.append(dc)
			if opp != null and opp.player == pl:
				continue
			pl.target = dc.goal
			pl.run_speed = 6.5 * _speed_k(pl)
			if clock >= dc.jump_at and not dc.jumped and not pl.airborne:
				dc.jumped = true
				pl.jump()
				pl.block_pose = false
				pl.anim_kind = "attack"
				pl.anim_tech = ""
				pl.anim_t = clock + rise(pl)
				pl.contact_pt = dc.goal + Vector3(0.0, H_ATTACK, 0.0)
				pl.contact_aim = Vector3(-side_of(t) * 5.0, 0.0, dc.goal.z)
				pl.contact_on = false
		_decoys[t] = keep


## Y halten + Steuerkreuz: Spielzug ansagen (oben Schnell Mitte, rechts Slide, unten Pipe, links Kombi).
## Gleicher Druck nochmal nimmt ihn zurueck. Geht, bis dein Zuspieler den Ball spielt.
func _play_call_input(inp: Dictionary) -> void:
	var dd: Vector2 = inp.get("play_dd", Vector2.ZERO)
	if dd.length() < 0.5 or human_team < 0:
		return
	if drill != null and not drill.human_does("set"):
		return
	var call := "combo"
	if absf(dd.y) >= absf(dd.x):
		call = "quick" if dd.y > 0.0 else "pipe"
	elif dd.x > 0.0:
		call = "slide"
	play_call[human_team] = "" if play_call[human_team] == call else call
	play_called.emit(human_team, play_call[human_team])
	stats["Ansage " + call] = stats.get("Ansage " + call, 0) + 1


## Dump-Richtung aus dem rechten Stick, gleich gelesen wie beim Angriff: der Ball geht dorthin,
## wohin ein Schlag mit diesem Trefferpunkt ginge. Oben = tief ins Feld, unten = kurz hinters Netz.
func _dump_lane(o: Opp) -> String:
	if o.rs.length() < 0.35:
		return "auto"
	if absf(o.rs.y) > absf(o.rs.x):
		return "back" if o.rs.y > 0.0 else "mid"
	var tgt: Vector3 = attack_shot(o.team, ball.position, Vector2(o.rs.x, 0.0), 0.5).target
	return "left" if team_local(o.team, tgt).y < 0.0 else "right"


## KI-Zuspieler: waehlt das Tempo nach Annahme und Block des Gegners.
func _ai_set_tempo(o: Opp, q: int) -> String:
	if q == Q.WEAK or o.tech != "over":
		return "high"
	var pp: AiPlan = plan(o.team)
	var mid_blocker := _lane_player(1 - o.team, "mid")
	var leaning := mid_blocker != null and absf(mid_blocker.position.z) > 2.0  # Block steht aussen: Mitte/Dump offen
	if _can_dump(o) and o.player.role == "S" and rng.randf() < pp.dump_rate * (2.5 if leaning else 1.0):
		return "dump"
	if pass_quality <= Q.GOOD and rng.randf() < pp.tempo_fast:
		return "quick" if rng.randf() < pp.quick_bias * (1.6 if leaning else 1.0) else "fast"
	return "fast" if rng.randf() < 0.2 * pp.tempo_fast else "high"


func _pick_hitter(team: int, setter: VPlayer, choice: String, sl: Vector2) -> VPlayer:
	var lane := choice
	if choice == "auto" or choice == "":
		var r := rng.randf()
		var lw: Dictionary = plan(team).lane_w  # K1: Spielplan bestimmt, wen das Team anspielt
		var wl: float = lw.left
		var wr: float = lw.right
		# Steht der menschliche Mittelblocker aussen, spielt die KI eher dorthin, wo er nicht ist.
		var rb := _lane_player(1 - team, "mid")
		if rb != null and (1 - team) == human_team:
			var zl := court_pos(team, Vector2(1.0, -3.6)).z
			var zr := court_pos(team, Vector2(1.0, 3.6)).z
			var dl := absf(rb.position.z - zl)
			var dr := absf(rb.position.z - zr)
			wl = lw.left * (0.75 + 0.9 * dl / (dl + dr + 0.01))
			wr = lw.right * (0.75 + 0.9 * dr / (dl + dr + 0.01))
		if pass_quality <= Q.GOOD and sl.x < 2.5:
			var wsum: float = wl + wr + float(lw.mid)
			lane = "left" if r < wl / wsum else ("right" if r < (wl + wr) / wsum else "mid")
		else:
			lane = "left" if r < wl / (wl + wr) else "right"
	var h: VPlayer = null
	if lane == "slide":
		h = _lane_player(team, "mid")
	elif lane == "pipe":
		h = _pipe_player(team)
	else:
		h = _lane_player(team, lane)
	if h == null and lane == "right":
		h = _lane_player(team, "back")  # kein Diagonalangreifer vorn: Hinterfeldangriff
	if h == null or h == setter or is_down(h):
		for alt in ["left", "right", "mid", "back"]:
			var c := _lane_player(team, alt)
			if c != null and c != setter and not is_down(c):
				return c
	return h


## Was ein Schlag mit diesem Trefferpunkt machen wuerde (ohne Timing-Fehler und Zufall).
## Rechter Stick: oben Topspin, Mitte flach und hart, unten Leger. Wer den Ball rechts
## trifft, schlaegt ihn nach links. Ganz aussen: Cut Shot (kurz diagonal) oder Block-Out.
func attack_shot(team: int, bp: Vector3, contact: Vector2, power: float, finesse := false) -> Dictionary:
	var hl := team_local(team, bp).y
	if finesse and contact.y >= -0.35:
		return _finesse_shot(team, bp, contact, power, hl)
	if finesse and contact.y < -0.35:
		var rb := _rebound_point(team, bp)
		if not rb.is_empty():
			# S3: Ball weich in den Block legen, damit er zurueckkommt und neu aufgebaut wird.
			return {"style": "rebound", "g": G, "u": 10.0, "clear": 0.0, "target": rb.p, "d": 0.3, "l": hl, "blocker": rb.b}
	var res := {"style": "spike", "g": G, "u": lerpf(16.0, 30.0, clampf(power, 0.0, 1.0)), "clear": 0.0}
	var d := 7.8
	var l := hl
	if contact.y < -0.35:
		res.style = "tip"
		d = lerpf(1.5, 3.2, clampf(contact.y + 1.0, 0.0, 1.0) / 0.65)
		l = _aim_lateral(hl, contact.x, 4.0)
		res.clear = 3.6
	elif absf(contact.x) > 0.85:
		var toward := -signf(contact.x)  # Richtung (lokal), in die der Ball fliegt
		if absf(hl) > 1.5 and toward == signf(hl) and contact.y > 0.2:
			res.style = "blockout"  # gegen die Aussenhand, knapp neben die Seitenlinie
			d = 4.0
			l = signf(hl) * 4.9
			# S2: steht ein Block, zielt der Schlag genau auf dessen Aussenhand.
			var oz = _outer_hand_z(team, toward)
			if oz != null:
				var tx := court_pos(team, Vector2(-d, 0.0)).x
				var k := (tx - bp.x) / -bp.x if absf(bp.x) > 0.05 else 30.0
				var tz := bp.z + (float(oz) - bp.z) * k
				l = clampf(team_local(team, Vector3(tx, 0.0, tz)).y, -6.0, 6.0)
		else:
			res.style = "cut"
			d = 2.8
			l = toward * 4.0
			res.u = lerpf(12.0, 19.0, power)
	else:
		var top := clampf(contact.y, 0.0, 1.0)
		d = 7.3 - top * 2.2
		l = _aim_lateral(hl, contact.x, 4.8)
		res.g = G * (1.08 + 0.62 * top)
		if top > 0.3:
			res.style = "topspin"
	var target := court_pos(team, Vector2(-d, l))
	target.y = R
	res.target = target
	res.d = d
	res.l = l
	return res


## S3: Wohin ein in den Block gelegter Ball zielt: auf die Haende des naechsten Blockers am Netz
## (Hoehe = sein hoechster Punkt minus 0,6 m, also in die Handflaechen). Leer, wenn kein Block steht.
func _rebound_point(team: int, bp: Vector3) -> Dictionary:
	var best: VPlayer = null
	var bd := 1e9
	for b in blockers[1 - team]:
		if b == null:
			continue
		var bz: float = b.hands_z() if b.airborne else b.target.z
		if absf(bz - bp.z) < bd:
			bd = absf(bz - bp.z)
			best = b
	if best == null or bd > 2.0:
		return {}
	var top := best.jump_v0 * best.jump_v0 / (2.0 * G) + VPlayer.BLOCK_REACH + best.reach_add
	var bz2: float = best.hands_z() if best.airborne else best.target.z
	return {"p": Vector3(0.0, top - 0.6, bz2), "b": best}


## S2: Aussenhand des gegnerischen Blocks auf der Seite toward_local (Welt-z, knapp aussen), oder null.
func _outer_hand_z(team: int, toward_local: float):
	var dirw := -side_of(team) * toward_local
	var out = null
	for b in blockers[1 - team]:
		if b == null:
			continue
		var bz: float = b.hands_z() if b.airborne else b.target.z
		if out == null or (bz - float(out)) * dirw > 0.0:
			out = bz
	if out == null:
		return null
	return float(out) + dirw * 0.42


## S3 ausfuehren: weicher, flacher Ball in die Blockhaende. Timing-Fehler lassen ihn neben die
## Hand (zu frueh/zu spaet) oder zu tief ins Netz gehen.
func _do_rebound(o: Opp, q: int, e: float, info: Dictionary, bp: Vector3) -> void:
	var tgt: Vector3 = info.target
	var aed := _err_dir(e, "attack", o.win_scale)
	var err: float = [0.0, 0.25, 0.6, 0.6][q] * clampf(1.0 - 0.3 * _touch_skill(o.player, "attack"), 0.6, 1.45)
	tgt.z += aed * err * side_of(o.team)
	if aed > 0.0:
		tgt.y -= err * 0.5  # zu spaet: Ball geht tiefer, Richtung Netzkante
	var T := clampf(bp.distance_to(tgt) / 9.0, 0.08, 0.45)
	ball_g = G
	ball_vel = Ballistics.launch_with_time(bp, tgt, T)
	last_action = "attack"
	last_attack_speed = ball_vel.length()
	last_super = false
	o.tech_key = "rebound"
	o.player.anim_style = "rebound"
	stats["Schlag rebound"] = stats.get("Schlag rebound", 0) + 1


## Seitliches Ziel: Stick in der Mitte = gerade (Linie), voll zur Seite = bis zur
## Seitenlinie. Nach aussen geht es bis knapp ins Aus (out_edge), nach innen bis 4 m.
func _aim_lateral(hl: float, x: float, out_edge: float) -> float:
	var base := clampf(hl, -3.9, 3.9)
	var dir := -signf(x)
	if dir == 0.0:
		return base
	var outward := absf(base) > 0.5 and dir == signf(base)
	var extreme := dir * (out_edge if outward else 4.0)
	return lerpf(base, extreme, clampf(absf(x) / 0.85, 0.0, 1.0))


# ---------------------------------------------------------------- Angriff mit Gefuehl (S1, S4, S5)

var seam_half := 0.5  # Schlag in die Luecke: so nah (m) muss eine Blockhand am Ball sein, um ihn zu beruehren


## S1: Gefuehlsschlag mit L2. Rechter Stick: Mitte = Roll-Shot mit halber Kraft und Topspin hinter
## den Block, oben = platziert in die tiefe Ecke, zur Seite = in die Luecke zwischen zwei Blockern.
## (Stick unten bleibt der Leger.) Wie beim normalen Schlag gilt: Trefferpunkt rechts = Ball nach links.
func _finesse_shot(team: int, bp: Vector3, contact: Vector2, power: float, hl: float) -> Dictionary:
	var res := {"style": "roll", "g": G * 1.35, "u": 12.0, "clear": 3.8, "finesse": true}
	var d := 4.8
	var l := _aim_lateral(hl, contact.x * 0.7, 3.8)
	if absf(contact.x) > 0.5 and absf(contact.y) < 0.5:
		res.style = "seam"
		res.g = G * 1.15
		res.u = lerpf(19.0, 25.0, clampf(power, 0.0, 1.0))
		res.clear = 0.0
		var zc := _seam_z(team, bp, -signf(contact.x))
		d = 6.5
		var tx := court_pos(team, Vector2(-d, 0.0)).x
		var k := (tx - bp.x) / -bp.x if absf(bp.x) > 0.05 else 30.0
		var tz := clampf(bp.z + (zc - bp.z) * k, -4.1, 4.1)
		l = team_local(team, Vector3(tx, 0.0, tz)).y
	elif contact.y > 0.5:
		res.style = "corner"
		res.g = G * 1.12
		res.u = 17.0
		res.clear = 3.7
		d = 8.2
		var toward := -signf(contact.x) if absf(contact.x) > 0.15 else (-signf(hl) if absf(hl) > 0.5 else 1.0)
		l = toward * 3.8
	var target := court_pos(team, Vector2(-d, l))
	target.y = R
	res.target = target
	res.d = d
	res.l = l
	return res


## Netzposition (Welt-z) der Luecke im gegnerischen Block, die auf der Seite dir_local liegt.
## Ohne zweiten Blocker: neben den einen Blocker, ohne Block: einfach etwas zur Seite.
func _seam_z(team: int, bp: Vector3, dir_local: float) -> float:
	var dirw := -side_of(team) * dir_local
	var zs: Array = []
	for b in blockers[1 - team]:
		if b != null:
			zs.append(b.hands_z() if b.airborne else b.target.z)
	if zs.is_empty():
		return bp.z + dirw * 1.0
	zs.sort()
	if zs.size() == 1:
		return zs[0] + dirw * 0.8
	var best := 0.0
	var best_score := 1e9
	for i in zs.size() - 1:
		var mid: float = (zs[i] + zs[i + 1]) * 0.5
		var score := absf(mid - bp.z) + (0.0 if signf(mid - bp.z) == dirw else 3.0)
		if score < best_score:
			best_score = score
			best = mid
	return best


## Laeuft der Schlag in Richtung des Anlaufs (+1), dagegen (-1) oder ist er neutral (0)?
func _along_run(o: Opp, l: float) -> int:
	if o.approach != "wide" and o.approach != "tight":
		return 0
	var run := -signf(o.approach_z)
	var heading := -side_of(o.team) * l - o.point.z
	if absf(heading) < 0.8 or run == 0.0:
		return 0
	return 1 if signf(heading) == run else -1


## S5: Sauber getroffen (perfektes Timing) erreicht die Linie entlang der Seitenlinie und die
## scharfe Diagonale. Mit gutem Timing geht das nur in Richtung des Anlaufs (S4). Assistiert
## bleibt alles andere wie bisher; manuell zieht ein nicht sauber getroffener Ball zur Mitte.
func _angle_shape(o: Opp, q: int, hl: float, d: float, l: float, manual: bool) -> Dictionary:
	var res := {"d": d, "l": l, "key": "clean" if q == Q.PERFECT else ""}
	var along := _along_run(o, l)
	var open := q == Q.PERFECT or (q == Q.GOOD and (along > 0 or pls(o.player, "winkel") > 0.0))  # PlayStyle Winkelkuenstler
	var sx := absf(o.rs.x)
	var cross := absf(hl) <= 1.5 or signf(l) != signf(hl)
	if open:
		if not cross and absf(hl) > 2.5 and sx < 0.25:
			res.l = signf(hl) * (4.35 if manual else 4.25)  # Linie entlang der Seitenlinie
		elif cross and sx > 0.7 and absf(l) > 2.0:
			res.l = signf(l) * maxf(absf(l), 4.2)  # scharfe Diagonale, kurz hinter dem Block
			res.d = minf(d, 4.7 if manual else 5.2)
	elif manual and absf(l) > 2.6:
		var f := (0.6 if q == Q.GOOD else 0.35) + 0.12 * _touch_skill(o.player, "attack")
		if along > 0:
			f += 0.25
		elif along < 0:
			f -= 0.1
		f = clampf(f, 0.15, 1.0)
		res.l = signf(l) * (2.6 + (absf(l) - 2.6) * f)
	return res


## Gefuehlsschlag ausfuehren: genau bei sauberem Timing, sonst ungenauer (zu frueh = zu lang,
## zu spaet = zu kurz). Gute Angreifer streuen weniger.
func _do_finesse(o: Opp, q: int, e: float, info: Dictionary, bp: Vector3) -> void:
	var style: String = info.style
	var sk := _touch_skill(o.player, "attack")
	var err := 0.0
	if q == Q.GOOD:
		err = 0.6
	elif q == Q.WEAK:
		err = 1.4
	err *= clampf(1.0 - 0.3 * sk, 0.6, 1.45)
	var aed := _err_dir(e, "attack", o.win_scale)
	var hl0 := team_local(o.team, bp).y
	var line_dir := signf(hl0) if absf(hl0) > 0.5 else 1.0
	var d: float = info.d
	var l: float = info.l
	var u: float = info.u
	var g: float = info.g
	if o.emergency:
		u *= 0.85
		err += 0.4
		stats["Notangriff"] = stats.get("Notangriff", 0) + 1
	if style == "seam":
		l += aed * err * 0.45 * line_dir
		seam_half = [0.22, 0.3, 0.5, 0.5][q]
	else:
		d += aed * err * 1.3
		l += aed * err * 0.7 * line_dir
	if q == Q.WEAK:
		u *= 0.85
	d = clampf(d, 2.0, 9.6)
	var target := court_pos(o.team, Vector2(-d, l))
	target.y = R
	ball_g = g
	var vel: Vector3
	if style == "seam":
		vel = Ballistics.launch_with_speed(bp, target, u, g)
		var tries := 0
		while _net_cross_y(bp, vel) < NET_H + 0.15 and tries < 8:
			tries += 1
			d += 0.4
			target = court_pos(o.team, Vector2(-d, l))
			target.y = R
			vel = Ballistics.launch_with_speed(bp, target, u, g)
	else:
		vel = Ballistics.launch_over_net(bp, target, info.clear, u * 0.55, u, g)
	ball_vel = vel
	last_action = "attack"
	last_attack_speed = vel.length()
	last_super = false
	_slow_tail_until = clock + 0.12
	o.tech_key = style
	o.player.anim_style = o.trick if o.trick != "" else style  # roll, corner, seam (Visual Overhaul; unbekannt = normale Bewegung)
	stats["Schlag " + style] = stats.get("Schlag " + style, 0) + 1
	if o.human:
		big_hit.emit(0.3)


## S4: Anlauf mit dem linken Stick, solange der Angreifer noch nicht abgesprungen ist.
## Zur Seitenlinie = Anlauf von aussen (Diagonale offen), zur Feldmitte = enger Anlauf
## (Linie offen), vom Netz weg = verzoegern (der Block springt zu frueh). Assistiert rastet der
## Stick auf diese drei Arten ein, manuell bestimmt der Ausschlag, wie stark.
func _approach_input(mv: Vector2) -> void:
	var pl := opp.player
	if pl == null or pl.airborne or pl.has_jumped:
		return
	if clock > opp.t - rise(pl) - 0.18:
		return  # Absprung steht schon
	if mv.length() < 0.35:
		return
	var manual := not cfg.assisted("approach")
	var d := _stick_dir(mv)
	var away := d.x * side_of(opp.team)  # > 0: vom Netz weg
	if away > 0.6 and absf(d.z) < 0.6:
		_approach_delay(lerpf(0.06, 0.14, clampf((away - 0.6) / 0.4, 0.0, 1.0)) if manual else 0.1)
		return
	if absf(d.z) > 0.4 and not opp.delayed:
		var zs := signf(opp.point.z) if absf(opp.point.z) > 1.2 else 0.0
		opp.approach = "wide" if (zs == 0.0 or signf(d.z) == zs) else "tight"
		var amount := clampf(absf(d.z), 0.4, 1.0) if manual else 1.0
		opp.approach_z = signf(d.z) * 1.7 * amount


func _approach_delay(dt: float) -> void:
	if opp.delayed:
		return
	var t2 := opp.t + dt
	var p2 := Ballistics.pos_at(ball.position, ball_vel, t2 - clock, ball_g)
	if p2.y < NET_H + 0.55:
		return  # Ball waere zu tief: kein Verzoegern moeglich
	opp.delayed = true
	opp.approach = "delay"
	opp.approach_z = 0.0
	opp.t = t2
	opp.point = p2
	# Die KI-Blocker haben auf den alten Zeitpunkt geplant; nur wer gut liest, wartet mit.
	for b in blockers[1 - opp.team]:
		if b == null or b.team == human_team or b.has_jumped:
			continue
		if rng.randf() < lerpf(0.15, 0.45, cfg.unit("ai_block")) * (1.0 + 0.3 * pf(b, "block")):
			b.block_jump_at += dt


## Einmal pro Angriff: welche Techniken jetzt gehen (fuer den Tastenhinweis beim ersten Mal).
func _offer_attack_hints() -> void:
	if opp.offered:
		return
	opp.offered = true
	technique_available.emit("clean")
	if not opp.emergency:
		for k in ["roll", "corner", "seam"]:
			technique_available.emit(k)
	if not blockers[1 - opp.team].is_empty():
		technique_available.emit("rebound")
		if absf(team_local(opp.team, opp.point).y) > 1.5:
			technique_available.emit("tool_hand")
	if clock < opp.t - rise(opp.player) - 0.45:
		for k in ["approach_wide", "approach_tight", "approach_delay"]:
			technique_available.emit(k)


func _do_attack(o: Opp, q: int, e: float) -> void:
	var bp := ball.position
	_hitter[o.team] = null
	# 5-Sterne-Moves: Schwachhand (Ball geht anders, als der Koerper es zeigt), Dreh-Schlag
	# hinter dem Kopf (scharf zurueck zur eigenen Anlaufseite).
	if o.trick == "offhand":
		o.rs.x = -o.rs.x if absf(o.rs.x) > 0.2 else -signf(team_local(o.team, bp).y + 0.01) * 0.5
	elif o.trick == "cutback":
		o.rs = Vector2(-signf(team_local(o.team, bp).y) * 0.95, 0.0)
	var info := attack_shot(o.team, bp, o.rs, o.power, o.finesse)
	last_shot_style = info.style
	var g: float = info.g
	ball_g = g
	if info.style == "tip":
		ball_vel = Ballistics.launch_over_net(bp, info.target, info.clear, 4.0, 10.0, g)
		last_action = "tip"
		return
	if info.style == "rebound":
		_do_rebound(o, q, e, info, bp)
		return
	if info.get("finesse", false):
		_do_finesse(o, q, e, info, bp)
		return
	var d: float = info.d
	var l: float = info.l
	var u: float = info.u
	if o.emergency:
		# Notangriff: Ball zu weit weg oder schlecht zugespielt, der Angreifer kommt nicht voll durch.
		u *= 0.72
		stats["Notangriff"] = stats.get("Notangriff", 0) + 1
		if o.human:
			popup(o.player, "Notangriff", Q_COLOR[Q.WEAK])
	# Super-Zone: perfekt getimt und genau im schmalen Bereich losgelassen. Die KI schafft
	# das bei guten Zuspielen gelegentlich auch.
	var sup := false
	if q == Q.PERFECT and not o.emergency and (info.style == "spike" or info.style == "topspin"):
		var wide := 0.025 * pls(o.player, "kraftpaket")
		if o.human:
			sup = o.over >= SUPER_LO - wide and o.over <= SUPER_HI + wide
		else:
			sup = o.power > 0.85 and rng.randf() < lerpf(0.1, 0.3, cfg.unit("ai_block")) * (1.0 + 0.6 * pf(o.player, "power") + wide * 10.0)
	# Schlagkraft: harte Angreifer schlagen schneller (Kraftpaket noch etwas mehr).
	var pk := 1.0 + 0.07 * pf(o.player, "power") + 0.035 * pls(o.player, "kraftpaket")
	u *= pk
	if sup:
		u = SUPER_SPIKE_U * (1.0 + 0.5 * (pk - 1.0))
		g *= 1.1
		ball_g = g
	# Zu frueh: Ball fliegt zu lang (Aus). Zu spaet: Ball geht zu steil (Netz).
	var x := excess(e, "attack", o.win_scale)
	if x < 0.0:
		d += -x * 45.0
	else:
		d -= x * 25.0
	# Ungenau aus dem Timing: zu frueh zieht der Ball diagonal, zu spaet geht er die Linie entlang.
	var aed := _err_dir(e, "attack", o.win_scale)
	var hl0 := team_local(o.team, bp).y
	var line_dir := signf(hl0) if absf(hl0) > 0.5 else 1.0
	# S5: sauber getroffen (perfektes Timing) oeffnet die scharfen Winkel; der Anlauf bestimmt,
	# welcher Winkel auch mit nur gutem Timing offen ist.
	var manual_aim := o.human and not cfg.assisted("attack_aim")
	if not o.emergency and (info.style == "spike" or info.style == "topspin"):
		var sh := _angle_shape(o, q, hl0, d, l, manual_aim)
		d = sh.d
		l = sh.l
		o.tech_key = sh.key
	if q == Q.GOOD:
		u *= 0.88
		if not manual_aim:
			l += aed * 0.8 * line_dir  # manuell gezielt: kein Abdriften, dafuer bleiben die Winkel zu
	elif q == Q.WEAK:
		u *= 0.62
		l += aed * 1.5 * line_dir
		d -= aed * 1.0
	if o.over > OVERCHARGE:
		# Ueberzogen: der Ball geht lang und nach aussen.
		var k := (o.over - OVERCHARGE) * 4.0
		l += k * 0.6 * line_dir
		d += k
	var target := court_pos(o.team, Vector2(-d, l))
	target.y = R
	var vel := Ballistics.launch_with_speed(bp, target, u, g)
	# Ein schwacher, zu spaeter Schlag geht ins Netz; sonst passt der Angreifer die Flugbahn an.
	if not (q == Q.WEAK and e > 0.0 and cfg.unit("faults") > 0.0):
		# Gute Angreifer passen die Flugbahn an, damit der Ball ueber das Netz geht.
		while _net_cross_y(bp, vel) < NET_H + 0.15 and d < 8.6:
			d += 0.5
			target = court_pos(o.team, Vector2(-d, l))
			target.y = R
			vel = Ballistics.launch_with_speed(bp, target, u, g)
		if _net_cross_y(bp, vel) < NET_H + 0.15:
			vel = Ballistics.launch_over_net(bp, target, NET_H + 0.25, 6.0, u, g)
		# ... und schlagen von aussen schraeg ins Feld, damit der Ball zwischen den Antennen kreuzt.
		var tries := 0
		while absf(_net_cross_z(bp, vel)) > HALF_W - 0.25 and tries < 12:
			tries += 1
			l *= 0.8
			l -= signf(bp.z) * 0.4 * -side_of(o.team)
			target = court_pos(o.team, Vector2(-d, l))
			target.y = R
			vel = Ballistics.launch_with_speed(bp, target, u, g)
	ball_vel = vel
	last_action = "attack"
	last_attack_speed = vel.length()
	last_super = sup
	_slow_tail_until = clock + 0.12
	stats["Schlag " + info.style] = stats.get("Schlag " + info.style, 0) + 1
	var ast := _attack_style(o)
	o.player.anim_style = o.trick if o.trick != "" else ast
	stats["Angriff " + ast] = stats.get("Angriff " + ast, 0) + 1
	if sup:
		stats["Wuchtschlag"] = stats.get("Wuchtschlag", 0) + 1
		mstat[o.team]["wucht"] = mstat[o.team].get("wucht", 0) + 1
	if o.human:
		var perfect := q == Q.PERFECT and o.power > 0.75
		big_hit.emit(1.0 if perfect else 0.4)
		if sup:
			# Wuchtschlag: etwas laengerer Mini-Stopp, dann gleitet das Spiel weich weiter.
			_hit_stop(0.06, 0.05)
		elif perfect:
			# Kurzer Mini-Stopp beim perfekten Schlag, danach gleitet das Spiel weich weiter.
			_hit_stop(0.05, 0.06)
	elif sup:
		big_hit.emit(0.55)
	elif last_attack_speed > 24.0:
		big_hit.emit(0.35)


## Hoehe, in der der Ball die Netzebene kreuzt (99, wenn er nicht hinkommt).
func _net_cross_y(from: Vector3, vel: Vector3) -> float:
	if absf(vel.x) < 0.01 or signf(vel.x) == signf(from.x):
		return 99.0
	var t := -from.x / vel.x
	return from.y + vel.y * t - 0.5 * ball_g * t * t


func _net_cross_z(from: Vector3, vel: Vector3) -> float:
	if absf(vel.x) < 0.01:
		return from.z
	return from.z + vel.z * (-from.x / vel.x)


func _do_free(o: Opp, q: int) -> void:
	var target := court_pos(o.team, Vector2(-rng.randf_range(4.5, 7.0), rng.randf_range(-2.5, 2.5)))
	target.y = R
	var clear := NET_H + (1.5 if q != Q.WEAK else 0.5)
	ball_vel = Ballistics.launch_over_net(ball.position, target, clear, 5.0, 11.0)
	last_action = "free"


# ---------------------------------------------------------------- Ballflug

func _step_ball(delta: float) -> void:
	var prev := ball.position
	var spin_axis := Vector3.UP.cross(ball_vel)
	if spin_axis.length() > 0.05:
		ball_mesh.rotate(spin_axis.normalized(), ball_vel.length() * delta / 0.14 * 0.4)
	var res := Ballistics.advance(prev, ball_vel, delta, ball_g)
	var nxt: Vector3 = res[0]
	ball_vel = res[1]
	_watch_net_fight(prev)
	if prev.x != 0.0 and signf(prev.x) != signf(nxt.x):
		var f := prev.x / (prev.x - nxt.x)
		var c := prev.lerp(nxt, f)
		if absf(c.z) > HALF_W:
			_end_rally(1 - last_touch_team, "Ball außerhalb der Antenne")
			return
		if c.y < NET_H + R and c.y > NET_BOTTOM - R:
			var net_speed := ball_vel.length()
			ball.position = Vector3(signf(prev.x) * (R + 0.02), c.y, c.z)
			ball_vel = Vector3(-ball_vel.x * 0.15, minf(ball_vel.y, 0.0) * 0.3 - 0.5, ball_vel.z * 0.3)
			ball_g = G
			flutter = 0.0
			net_touched = true
			_net_joust = {}
			_fx("net", c, clampf(net_speed / 22.0, 0.25, 1.0))
			if possession != last_touch_team:
				possession = last_touch_team
			plan_next()
			return
		if c.y <= NET_BOTTOM - R:
			_end_rally(1 - last_touch_team, "Unter dem Netz durch")
			return
		if not _net_joust.is_empty():
			var ja: VPlayer = _net_joust.a
			var jb: VPlayer = _net_joust.b
			_net_joust = {}
			if is_instance_valid(ja) and is_instance_valid(jb):
				_net_fight(ja, jb, Vector3(signf(prev.x) * 0.15, c.y, c.z))
				stats["Netzkampf aus Overpass"] = stats.get("Netzkampf aus Overpass", 0) + 1
				plan_next()
				return
		if _try_block(c, prev):
			return
		var t_new := team_at_x(nxt.x)
		if t_new != possession:
			possession = t_new
			touches = 0
	ball.position = nxt
	if nxt.y <= R:
		ball.position.y = R
		_on_ball_landed()


## V-2: Fliegt ein Ball (keine Angriffsaktion) knapp ueber das Netz, springen die beiden Spieler
## vorn an dieser Stelle gleichzeitig hin: Netzkampf statt glatter Overpass. Die Sprungkraft und
## Reichweite entscheiden; die Spieler springen rechtzeitig vorher ab.
func _watch_net_fight(prev: Vector3) -> void:
	if not _net_joust.is_empty() or not last_action in ["pass", "dig", "free", "set"]:
		return
	if absf(ball_vel.x) < 1.0 or signf(ball_vel.x) == signf(prev.x) or absf(prev.x) < 0.05:
		return
	var t := absf(prev.x) / absf(ball_vel.x)
	if t > 0.4:
		return
	var c := Ballistics.pos_at(prev, ball_vel, t, ball_g)
	if c.y < NET_H + R + 0.02 or c.y > NET_H + 0.85 or absf(c.z) > HALF_W - 0.3:
		return
	var own := team_at_x(prev.x)
	var a := _net_player(own, c.z)
	var b := _net_player(1 - own, c.z)
	if a == null or b == null or a == last_toucher:
		return
	a.jump()
	b.jump()
	_net_joust = {"a": a, "b": b}
	if opp != null and not opp.done and (opp.player == a or opp.player == b):
		opp.pending = false


func _net_player(team: int, z: float) -> VPlayer:
	var best: VPlayer = null
	for pl in players[team]:
		if pl.role == "L" or not is_front_row(pl) or is_down(pl) or pl.airborne:
			continue
		if absf(pl.position.x) > 2.2 or absf(pl.position.z - z) > 2.2:
			continue
		if best == null or absf(pl.position.z - z) < absf(best.position.z - z):
			best = pl
	return best


## Nach dem Punkt rollt und springt der Ball weiter, statt auf dem Boden festzukleben.
func _step_dead_ball(delta: float) -> void:
	var grounded := ball.position.y <= R + 0.001
	if grounded and ball_vel.length() < 0.05:
		ball_vel = Vector3.ZERO
		return
	var res := Ballistics.advance(ball.position, ball_vel, delta, G)
	var pos: Vector3 = res[0]
	var vel: Vector3 = res[1]
	if prev_cross_net(ball.position.x, pos.x) and pos.y < NET_H + R:
		vel.x = -vel.x * 0.2
		pos.x = signf(ball.position.x) * (R + 0.02)
	if absf(pos.x) > 14.0:
		pos.x = signf(pos.x) * 14.0
		vel.x = -vel.x * 0.4
	if absf(pos.z) > 8.5:
		pos.z = signf(pos.z) * 8.5
		vel.z = -vel.z * 0.4
	if pos.y <= R:
		pos.y = R
		if vel.y < -1.5:
			_fx("floor", pos, clampf(-vel.y / 14.0, 0.15, 0.6))
		vel.y = minf(-vel.y * 0.62, 7.0)
		if vel.y < 1.3:
			vel.y = 0.0
		vel.x *= 0.82
		vel.z *= 0.82
		if vel.y == 0.0:
			var k := maxf(0.0, 1.0 - 2.2 * delta)
			vel.x *= k
			vel.z *= k
	ball.position = pos
	ball_vel = vel
	ball_mesh.rotate(Vector3.UP.cross(vel).normalized() if Vector3.UP.cross(vel).length() > 0.05 else Vector3.RIGHT, vel.length() * delta / 0.14 * 0.4)


func prev_cross_net(x0: float, x1: float) -> bool:
	return x0 != 0.0 and signf(x0) != signf(x1)


func _try_block(c: Vector3, prev: Vector3) -> bool:
	if last_action == "serve" or last_action == "toss":
		return false  # Aufschlag blocken ist verboten
	var def := team_at_x(-prev.x)
	var hit_pl: VPlayer = null
	var hit_dz := 0.0
	var in_block := 0
	for pl in players[def]:
		if not pl.airborne or not is_front_row(pl):
			continue
		var top: float = pl.block_top()
		if c.y > top + R or c.y < top - 0.75:
			continue
		var dz: float = c.z - pl.hands_z()
		if absf(dz) < 1.4:
			in_block += 1
		if absf(dz) > (seam_half if last_shot_style == "seam" else 0.5) + R:
			continue  # Schlag in die Luecke: nur eine Hand genau am Ball beruehrt ihn
		if hit_pl == null or absf(dz) < absf(hit_dz):
			hit_pl = pl
			hit_dz = dz
	if hit_pl == null:
		return false
	var pl := hit_pl
	var top2: float = pl.block_top()
	# Ueber das Netz greifen (Stick nach vorn) macht den Block staerker. Netzfehler beim Block gibt
	# es nicht (Mattis, 05.11.2026: "Bitte mach einfach den Netzfehler raus").
	var s_att := signf(prev.x)
	ball_g = G
	# Wie gut steht der Block? Haende ganz oben, ueber das Netz gegriffen, mehrere Blocker.
	# Der Mensch blockt immer gleich stark; die Staerke des KI-Blocks stellt "Gegner-Block" ein.
	var base := 0.34 if def == human_team else lerpf(0.1, 0.34, cfg.unit("ai_block"))
	var stuff_p := base + (0.2 if pl.hand_reach > 0.0 else 0.0) + (0.15 if in_block >= 2 else 0.0) + (0.1 if in_block >= 3 else 0.0)
	# Blockstaerke des Blockers (Blockleser etwas mehr); ein Linkshaender von der rechten Seite
	# schlaegt aus ungewohntem Winkel und ist schwerer zu blocken.
	stuff_p *= 1.0 + 0.35 * pf(pl, "block")
	stuff_p += 0.05 * pls(pl, "blockleser")
	stuff_p *= 1.0 + 0.12 * pls(pl, "mauer")  # PlayStyle Mauer
	if last_trick in ["offhand", "cutback"]:
		stuff_p *= 0.55  # 5-Sterne-Move: der Block steht auf der falschen Seite
	if last_touch_team >= 0 and _play_info[last_touch_team].get("jumpset", false):
		stuff_p *= 0.75  # nach Sprungzuspiel kommt der Block zu spaet
	var att: VPlayer = last_toucher
	if att and ptrait(att, "linkshaender") and team_local(att.team, att.position).y > 1.5:
		stuff_p *= 0.85
	elif att and pls(att, "beidhaender") > 0.0 and absf(team_local(att.team, att.position).y) > 1.5:
		stuff_p *= 1.0 - 0.08 * pls(att, "beidhaender")  # PlayStyle Beidhaender: von beiden Seiten unbequem
	if read_hit[def]:
		stuff_p += 0.2  # richtig gelesen
	elif commit_miss[def]:
		stuff_p *= 0.6
	if pl.jump_h < 0.6:
		stuff_p *= 0.4
	if pl.anim_style == "soft":
		stuff_p *= 0.5  # Haende schraeg nach hinten: bremst den Ball, drueckt ihn aber selten zurueck
	elif pl.anim_style == "late":
		stuff_p *= 0.6
	# Abpraller aus der Physik: die Haende sind eine schraege Flaeche am Netz. Wie der Ball
	# zurueckkommt, folgt aus Handstellung (ueber das Netz gegriffen, weich nach hinten, schon auf
	# dem Weg nach unten), Trefferhoehe (Fingerspitzen bremsen wenig), Trefferpunkt (Aussenhand
	# wischt seitlich ab), Blockstaerke und Wucht des Balls. Kein Wuerfel.
	var firm := clampf(stuff_p / 0.45, 0.25, 1.4)
	var soft: bool = pl.anim_style == "soft"
	# Dein Block, perfekt gemacht: am hoechsten Punkt (kaum noch Steig- oder Fallgeschwindigkeit)
	# und die Haende mittig am Ball. Das ist fast immer ein voller Block, Koennen entscheidet.
	var perfect: bool = def == human_team and not soft and absf(pl.jump_v) < 1.1 and absf(hit_dz) < 0.22
	var v_in := ball_vel
	var v_out := _block_bounce(pl, c, v_in, hit_dz, firm, soft, s_att, perfect)
	if perfect:
		stats["Block perfekt"] = stats.get("Block perfekt", 0) + 1
	var back := signf(v_out.x) == s_att
	ball.position = Vector3((s_att if back else -s_att) * (R + 0.05), c.y, c.z)
	ball_vel = v_out
	touches = 0
	var att_was: String = last_action
	stats["Block Kontakte"] = stats.get("Block Kontakte", 0) + 1
	if back:
		possession = 1 - def
		last_action = "block"
		block_at = clock
		if v_out.y < -4.0 and absf(v_out.x) > 0.8:
			# Kompletter Block: Ball wird nach unten auf die Seite des Angreifers gedrueckt.
			var txt := "BLOCK!"
			if in_block >= 3:
				txt = "DREIERBLOCK!"
			elif in_block == 2:
				txt = "DOPPELBLOCK!"
			popup(pl, txt, Q_COLOR[Q.PERFECT])
			stats[txt] = stats.get(txt, 0) + 1
			if def == human_team:
				big_hit.emit(1.0 if in_block >= 2 else 0.8)  # Halt/Kamera entscheidet die Zeitlupen-Einstellung
				_human_stuff = true
				if in_block >= 2:
					_hit_stop(0.06, 0.1)
		else:
			# Abpraller: der Ball springt zurueck, das angreifende Team kann neu aufbauen.
			popup(pl, "Abpraller", Q_COLOR[Q.GOOD])
			stats["Block Abpraller"] = stats.get("Block Abpraller", 0) + 1
			if last_shot_style == "rebound" and att != null:
				technique_done.emit(att, "rebound")
				popup(att, "Neuer Angriff", Q_COLOR[Q.GOOD])
	else:
		possession = def
		last_action = "block_touch"
		block_at = clock
		if absf(v_out.z) > 3.0 and absf(hit_dz) > 0.25:
			popup(pl, "Blockberührung", Q_COLOR[Q.GOOD])
			stats["Block abgewischt"] = stats.get("Block abgewischt", 0) + 1
			if last_shot_style == "blockout" and att != null:
				technique_done.emit(att, "tool_hand")
		elif v_out.length() > 11.0 and att_was == "attack":
			popup(pl, "Durch den Block!", Q_COLOR[Q.WEAK])
			stats["Durch den Block"] = stats.get("Durch den Block", 0) + 1
		else:
			popup(pl, "Soft-Touch", Q_COLOR[Q.GOOD])
			stats["Block Soft-Touch"] = stats.get("Block Soft-Touch", 0) + 1
	if soft and def == human_team:
		technique_done.emit(pl, "block_soft")
	var full: bool = last_action == "block" and ball_vel.y < -4.0
	_fx("block", c, 1.0 if full else 0.55)
	if def == human_team and not autoplay:
		# Dein Block: voller Block = harter Doppelknall, Halle, kraeftiges Rumpeln; Beruehrung = dumpf, leicht.
		own_block.emit(full, c)
	last_touch_team = def
	last_toucher = null
	plan_next()
	return true


## Ball prallt von den Blockhaenden ab (Weltkoordinaten). n = Flaechennormale der Haende,
## zeigt zum Angreifer; a = wie weit die Haende ueber das Netz nach unten gekippt sind.
func _block_bounce(pl: VPlayer, c: Vector3, v: Vector3, dz: float, firm: float, soft: bool, s_att: float, perfect := false) -> Vector3:
	var top := pl.block_top()
	var a := 0.05 + 0.15 * firm + (0.25 if pl.hand_reach > 0.0 else 0.0)
	if perfect:
		# Perfekt: die Haende sind schon ueber dem Netz und druecken den Ball steil auf die Seite
		# des Angreifers. Das ist die Belohnung fuer Timing und Stellung.
		var sp := v.length()
		return Vector3(s_att * clampf(0.18 * sp, 2.5, 5.0), -clampf(0.4 * sp, 7.0, 12.0), v.z * 0.15)
	if pl.jump_v < -1.0:
		a -= 0.3  # schon auf dem Weg nach unten: Haende kippen nach hinten
	if soft:
		a = -0.55  # weicher Block: Haende schraeg nach hinten, Ball geht hoch auf die eigene Seite
	var n := Vector3(s_att * cos(a), -sin(a), 0.0)
	# Aussenhand: je weiter aussen getroffen, desto mehr wischt der Ball seitlich ab.
	var edge := clampf((absf(dz) - 0.22) / 0.3, 0.0, 1.0)
	n.z = signf(dz) * edge * 1.55  # V-2: Aussenhand wischt weiter ab (manchmal nur mit Hecht)
	n = n.normalized()
	# Fingerspitzen bremsen wenig, die ganze Hand viel.
	var frac := clampf((top - c.y) / 0.6, 0.15, 1.0) * (1.0 - 0.6 * edge)
	var e := 0.06 if soft else 0.08 + 0.08 * firm
	var vn := v.dot(n)
	if vn >= 0.0:
		return v
	var vt := v - vn * n
	var out := v - frac * ((1.0 + e) * vn * n + 0.3 * vt)
	if frac < 0.6:
		out.y += (0.6 - frac) * v.length() * 0.36  # ueber die Fingerspitzen: Ball springt hoch und weit
	if not soft:
		out += n * 2.0 * frac * minf(firm, 1.2)  # der Blocker drueckt die Haende zum Angreifer
	return out


func _on_ball_landed() -> void:
	_fx("floor", ball.position, clampf(ball_vel.length() / 22.0, 0.2, 1.0))
	var side_team := team_at_x(ball.position.x)
	var inside := absf(ball.position.x) <= HALF_L + R and absf(ball.position.z) <= HALF_W + R
	var winner: int
	var reason: String
	if inside:
		winner = 1 - side_team
		if last_touch_team == side_team:
			if last_action == "toss" or last_action == "serve":
				reason = "Aufschlagfehler"
			elif last_action == "block_touch":
				reason = "Angriffspunkt!"
			elif net_touched:
				reason = "Netz!"
			else:
				reason = "Ball nicht rübergebracht"
		else:
			match last_action:
				"serve":
					reason = "Ass!"
				"attack":
					reason = "Angriffspunkt!"
				"tip":
					reason = "Gelegt!"
				"block":
					reason = "Block-Punkt!"
				"joust":
					reason = "Netzkampf!"
				_:
					reason = "Ball im Feld"
	elif last_action == "toss":
		winner = 1 - serving_team
		reason = "Aufschlagfehler"
	else:
		winner = 1 - last_touch_team
		if last_action == "block_touch":
			reason = "Block-Aus!"
		elif last_action == "serve":
			reason = "Aufschlag im Aus"
		else:
			reason = "Aus!"
	_end_rally(winner, reason)


func _fx(kind: String, pos: Vector3, strength: float) -> void:
	_body_hit(kind, pos, strength)
	if autoplay:
		return
	_rec_events.append([clock, kind, pos, strength])
	contact.emit(kind, pos, strength)


## Starke Punkte bekommen eine Wiederholung: Ass, Blockpunkt, sehr harter Angriff, langer
## Ballwechsel. Damit es nicht nervt, kommt nach einer Wiederholung fruehestens 4 Punkte
## spaeter die naechste.
func _is_highlight(reason: String) -> bool:
	points_since_replay += 1
	if reason == "Block-Punkt!" and _human_stuff:
		_human_stuff = false
		return true  # dein voller Block: immer zeigen
	_human_stuff = false
	var strong := false
	match reason:
		"Ass!", "Block-Punkt!":
			strong = true
		"Angriffspunkt!", "Block-Aus!":
			strong = last_attack_speed >= 28.0 or rally_touches >= 20
		"Gelegt!", "Ball im Feld":
			strong = rally_touches >= 20
	return strong and points_since_replay >= 4


func _end_rally(winner: int, reason: String) -> void:
	if autoplay:
		stats["Punkte Team %d" % winner] = stats.get("Punkte Team %d" % winner, 0) + 1
		if last_action == "attack" or last_action == "tip":
			stats["Angriffsende Team %d: %s" % [last_touch_team, "Punkt" if winner == last_touch_team else "Fehler/Block"]] = stats.get("Angriffsende Team %d: %s" % [last_touch_team, "Punkt" if winner == last_touch_team else "Fehler/Block"], 0) + 1
	if phase != Phase.RALLY and phase != Phase.TOSS and phase != Phase.PRE_SERVE:
		return
	if drill != null:
		drill.rally_ended(winner, reason)  # Debug-Uebung: kein Punkt, gleich wiederholen
		return
	opp = null
	blockers = [[], []]
	_hitter = [null, null]
	charging = false
	flutter = 0.0
	_observe_rally_end(winner, reason)
	score[winner] += 1
	streak[winner] += 1
	streak[1 - winner] = 0
	var side_out := winner != serving_team
	serving_team = winner
	if side_out:
		rosters[winner].rotate()  # Rueckschlagteam gewinnt den Ballwechsel: es rotiert
		_sync_slots(winner)
	rally_count += 1
	if trace:
		print("ENDE: %s -> T%d   ball=%s" % [reason, winner, ball.position])
	stats[reason] = stats.get(reason, 0) + 1
	var mk: String = {"Ass!": "aces", "Block-Punkt!": "blocks"}.get(reason, "")
	if mk != "":
		mstat[winner][mk] = mstat[winner].get(mk, 0) + 1
	var key: String = "Punkte " + TEAM_NAMES[winner]
	stats[key] = stats.get(key, 0) + 1
	var over: bool = score[winner] >= set_target() and score[winner] - score[1 - winner] >= 2
	if over and trace:
		print("SATZENDE Satz %d: %d:%d (deciding=%s)" % [set_no, score[0], score[1], deciding])
	for pl in players[winner]:
		pl.celebrate_until = clock + 1.6
	var highlight := _is_highlight(reason)
	_rally_end = clock
	point_won.emit(winner, reason, highlight)
	if hud:
		hud.whistle(true)
		hud.ref_signal(_ref_sequence(winner, reason, over))
		hud.flash_score(winner)
	if over:
		_finish_set(winner)
	else:
		phase = Phase.POINT_PAUSE
		pause_until = clock + (0.2 if autoplay else 1.6)
		if deciding and not side_changed_deciding and maxi(score[0], score[1]) >= 8:
			side_change_pending = true  # im Entscheidungssatz wird bei 8 Punkten gewechselt
			side_changed_deciding = true
		_ai_coach_after_point()
		replay_pending = highlight and cfg.replays and hud != null and not autoplay


func _finish_set(winner: int) -> void:
	sets_won[winner] += 1
	set_scores.append(score.duplicate())
	mstat[winner]["margin"] = maxi(mstat[winner].get("margin", 0), score[winner] - score[1 - winner])
	stats["Sätze"] = stats.get("Sätze", 0) + 1
	pause_until = clock + (0.2 if autoplay else 4.0)
	var history := ""
	for sc in set_scores:
		history += "%s%d:%d" % [", " if history != "" else "", sc[0], sc[1]]
	if sets_won[winner] >= sets_to_win:
		phase = Phase.MATCH_OVER
		matches_done += 1
		match_wins[winner] += 1
		stats["Spiele " + TEAM_NAMES[winner]] = stats.get("Spiele " + TEAM_NAMES[winner], 0) + 1
		_club_reward(winner)  # Muenzen und Aufgaben gibt es weiter, nur ohne Einblendung
		if hud:
			# Nur das Ergebnis, ohne Erklaertext (A startet wie bisher das naechste Spiel).
			hud.show_banner("%d : %d" % [sets_won[0], sets_won[1]], history)
	else:
		phase = Phase.SET_OVER
		if hud:
			hud.show_banner("%d : %d" % [score[0], score[1]])


## Mein Verein: nach jedem eigenen Spiel Muenzen und Aufgaben (nicht im Zuschauermodus oder Test).
func _club_reward(winner: int) -> Array:
	if human_team < 0 or autoplay or attract:
		return []
	var t := human_team
	var pts := 0
	var opp_pts := 0
	for sc in set_scores:
		pts += sc[t]
		opp_pts += sc[1 - t]
	var ms: Dictionary = mstat[t]
	return Club.record_match({
		"won": winner == t, "points": pts, "opp_points": opp_pts,
		"aces": ms.get("aces", 0), "blocks": ms.get("blocks", 0), "wucht": ms.get("wucht", 0),
		"sets_won": sets_won[t], "sets_lost": sets_won[1 - t], "best_margin": ms.get("margin", 0),
		"quick": quick, "opp": Teams.playing()[1 - t].id, "club": Teams.playing()[t].id == Club.ID,
	})


## Seitenwechsel im Entscheidungssatz bei 8 Punkten: alle gehen auf die andere Seite.
func _do_side_change() -> void:
	side_change_pending = false
	stats["Seitenwechsel im Entscheidungssatz"] = stats.get("Seitenwechsel im Entscheidungssatz", 0) + 1
	if trace:
		print("SEITENWECHSEL bei %d:%d" % [score[0], score[1]])
	sides = [-sides[0], -sides[1]]
	for t in 2:
		for pl in players[t]:
			pl.set_side(side_of(t))
			pl.position = Vector3(-pl.position.x, 0.0, -pl.position.z)
			pl.target = pl.position
	reset_physics_interpolation()
	phase = Phase.TIMEOUT
	timeout_team = -1
	pause_until = clock + (0.3 if autoplay else 3.5)
	if hud:
		hud.ref_signal([["sidechange", "Seitenwechsel", 3.5]])
		hud.whistle(false)


## Schiedsrichter-Zeichen nach einem Ballwechsel: erst der Grund, dann Aufschlag fuer das Team.
func _ref_sequence(winner: int, reason: String, set_end: bool) -> Array:
	var seq := []
	var sig := "in"
	match reason:
		"Netz!", "Netzberührung beim Block":
			sig = "net"
		"Doppelberührung":
			sig = "double"
		"Ball gehalten":
			sig = "held"
		"Aus!", "Block-Aus!", "Aufschlag im Aus", "Ball außerhalb der Antenne":
			sig = "out"
		"Aufschlagfehler", "Unter dem Netz durch", "Aufschlagzeit überschritten", "Hinterspielerfehler", "Liberofehler":
			sig = "fault"
	seq.append([sig, reason, 1.2])
	if set_end:
		seq.append(["setend", "Satzende", 2.5])
	else:
		seq.append(["serve_" + str(winner), "Aufschlag " + TEAM_NAMES[winner], 1.6])
	return seq


## KI-Trainer nach jedem Punkt: Auszeit bei einer Serie des Gegners.
func _ai_coach_after_point() -> void:
	for t in 2:
		if t == human_team:
			continue
		var r: TeamRoster = rosters[t]
		if r.timeouts_left > 0 and streak[1 - t] >= 3 and maxi(score[0], score[1]) >= 6 and rng.randf() < 0.6:
			ai_timeout_wanted[t] = true
		elif r.timeouts_left > 0 and score[1 - t] - score[t] >= 5 and rng.randf() < 0.25:
			ai_timeout_wanted[t] = true


func _print_stats() -> void:
	print("Ballwechsel: %d, Beruehrungen im Schnitt: %.2f, Spiele: %d (%d : %d)" % [rally_count, float(touch_total) / maxf(rally_count, 1), matches_done, match_wins[0], match_wins[1]])
	var keys := stats.keys()
	keys.sort()
	for k in keys:
		print("  %s: %d (%.0f %%)" % [k, stats[k], 100.0 * stats[k] / rally_count])


# ---------------------------------------------------------------- Laufwege und Anzeige

func _formation(t: int) -> String:
	match phase:
		Phase.PRE_SERVE, Phase.TOSS:
			return "serve" if t == serving_team else "receive"
		Phase.RALLY:
			if opp == null:
				return ""
			if opp.team == t:
				if opp.kind == "pass" and last_action == "serve":
					return "receive"  # Annahmeformation bleibt stehen, bis der Ball gespielt ist
				return "cover" if opp.kind == "attack" else "build"
			return "defense"
	return ""


func _update_players(delta: float) -> void:
	for t in 2:
		var form := _formation(t)
		if form != "":
			# Im Ballwechsel verschieben sich alle ein Stueck zur Ballseite (wie echte Abwehr).
			var shade := 0.0
			if phase == Phase.RALLY:
				shade = clampf((ball.position.z) * 0.2, -0.8, 0.8)
			for pl in players[t]:
				if not ((phase == Phase.PRE_SERVE or (phase == Phase.TOSS and not serve_done)) and pl == server()):
					pl.target = formation_pos(t, pl, form) + Vector3(0.0, 0.0, shade)
			# Gelesener Block: der Mittelblocker bleibt dort stehen, wo der Mensch ihn hingestellt hat.
			if t == human_team and commit_block[t]:
				var rp := _lane_player(t, "mid")
				if rp != null and opp != null and opp.team != t and opp.kind == "set":
					rp.target = Vector3(rp.target.x, 0.0, read_z)
		for pl in players[t]:
			pl.run_speed = 6.0 * _speed_k(pl)
		if opp != null and opp.team != t and opp.kind == "attack" and not blockers[t].is_empty():
			var list: Array = blockers[t]
			var prim: VPlayer = list[0]
			for pl in list:
				pl.run_speed = (3.0 if commit_miss[t] else 4.5) * _speed_k(pl)
			prim.target = Vector3(side_of(t) * 0.45, 0.0, clampf(opp.point.z + (block_err[t] if t != human_team else 0.0), -4.1, 4.1))
			# Helfer schliessen neben dem Hauptblocker (der Mensch kann ihn verschieben).
			for i in range(1, list.size()):
				var dir: float = block_dirs[t][i]
				if dir == 0.0:
					dir = 1.0 if i == 1 else -1.0
				var z := clampf(prim.position.z + dir * 0.85, -4.3, 4.3)
				list[i].target = Vector3(side_of(t) * 0.45, 0.0, z)
			for pl in players[t]:
				if not (pl in list) and is_front_row(pl):
					var lane: Vector2 = FORM["defense"]["front"][pl.lane if pl.lane in ["left", "mid", "right"] else "right"]
					pl.target = court_pos(t, Vector2(3.0, lane.y))
	if phase == Phase.RALLY:
		for t2 in 2:
			_k2_defense(t2)
	_update_decoys()
	# Vor dem Aufschlag: Sprungaufschlaeger steht weiter hinten (Platz zum Anlauf).
	if phase == Phase.PRE_SERVE:
		var srv0 := server()
		var back := 11.4 if serve_kind == 1 else 10.0
		srv0.target = Vector3(side_of(serving_team) * back, 0.0, srv0.position.z)
	# Standaufschlag: der Aufschlaeger bleibt waehrend des Wurfs stehen (sonst lief er zur Formationsposition).
	if phase == Phase.TOSS and serve_kind == 0 and not serve_done:
		var srv_stand := server()
		srv_stand.target = srv_stand.position
	# Sprungaufschlag: Anlauf unter den Ball und Absprung hinter der Grundlinie.
	if phase == Phase.TOSS and serve_kind == 1 and not serve_done:
		var srv := server()
		var bx := ball.position.x - side_of(serving_team) * 0.2
		bx = side_of(serving_team) * maxf(absf(bx), HALF_L + 0.1)
		var goal := Vector3(bx, 0.0, ball.position.z)
		# Anlauf aus dem Stand: der Aufschlaeger startet so, dass er genau zum Absprung ankommt.
		var run_dur := flat_dist(srv.position, goal) / 5.0
		# 0,35 s Vorlauf zum Beschleunigen (Laufen beginnt nicht mit voller Geschwindigkeit).
		if clock < serve_ideal - rise(srv) - run_dur - 0.35:
			goal = srv.position
		srv.target = goal
		srv.run_speed = 5.0 * _speed_k(srv)
		if clock >= serve_ideal - rise(srv) and not srv.has_jumped:
			srv.jump()
	if opp != null and not opp.done and opp.kind == "set" and opp.trick == "jumpset" and not opp.player.airborne \
			and clock >= opp.t - rise(opp.player) * 0.85:
		opp.player.jump()  # Sprungzuspiel: Absprung so, dass der Kontakt nahe am hoechsten Punkt liegt
	if opp != null and not opp.done:
		var pl := opp.player
		var p := _stand_pos(opp, Vector3(opp.point.x, 0.0, opp.point.z))
		if opp.kind == "attack":
			var t_jump := opp.t - rise(pl)
			var t_go := t_jump - flat_dist(pl.position, p) / pl.run_speed - 0.25  # Zeit zum Beschleunigen
			# Anlauf (S4): von aussen oder eng startet der Angreifer seitlich versetzt und laeuft schraeg an.
			var start := p + Vector3(side_of(opp.team) * 2.2, 0.0, opp.approach_z)
			start.z = clampf(start.z, -HALF_W - 0.8, HALF_W + 0.8)
			pl.target = p if clock >= t_go else start
			pl.approach_style = opp.approach
			if clock >= t_jump and not pl.has_jumped:
				pl.jump()
				pl.block_pose = false
				if opp.human and opp.approach != "":
					technique_done.emit(pl, "approach_" + opp.approach)
				if not opp.human:
					_ai_attack_choice(opp)  # Entscheidung faellt im Absprung
			# Schulter zeigt die Schlagrichtung an, damit der Blocker lesen kann.
			if pl.airborne:
				var info := attack_shot(opp.team, opp.point, opp.rs, opp.power, opp.finesse)
				var tz: float = (info.target as Vector3).z
				pl.lean = clampf((tz - pl.position.z) / 4.0, -1.0, 1.0)
		elif opp.human and not assist and not (_need_neutral and clock < _stick_lock_until + 0.5):
			pl.target = pl.position
		elif opp.no_reach:
			pl.target = opp.start_pos + (p - opp.start_pos).limit_length(opp.max_run)
		else:
			pl.target = p
	# Posen: wer gerade den Ball spielt, wer aufschlaegt, wohin alle schauen.
	var rally_on := phase == Phase.RALLY or phase == Phase.TOSS or phase == Phase.PRE_SERVE
	for t in 2:
		for pl in players[t]:
			pl.now = clock
			pl.look_target = ball.position
			pl.alert = rally_on
	if opp != null and not opp.done:
		opp.player.anim_kind = opp.kind
		opp.player.anim_tech = opp.tech
		# Technik aus der Lage; kurz vor dem Kontakt steht sie fest (die Bewegung laeuft schon).
		if not opp.style_locked:
			if opp.kind in ["pass", "dig", "free"]:
				opp.style = recv.filter_style(opp, _defense_style(opp))
			elif opp.kind == "attack":
				opp.style = _attack_style(opp)
			elif opp.kind == "set":
				var over_ok := opp.speed <= OVER_OK and not (opp.pending and opp.tech != "over")
				opp.style = Technique.set_style(opp.player.role == "S", pass_quality, opp.slack, over_ok)
			if opp.t - clock < 0.3 and opp.kind != "attack":
				opp.style_locked = true
		opp.player.anim_style = opp.trick if opp.trick != "" else opp.style  # 5-Sterne-Move behaelt seine Bewegung
		# Zuspiel, bevor gedrueckt ist: der Zuspieler geht schon in die Pritschhaltung, wenn der
		# Ball pritschbar ist (wie im Spiel: die Haende sind frueh oben). Gebaggert wird nur, wenn es so gedrueckt wird.
		# (Auch kurz nach dem geplanten Treffpunkt noch, sonst springen die Haende fuer ein, zwei Takte in
		# die Baggerhaltung, bis der Druck auf dem Steuerkreuz verarbeitet ist.)
		if opp.kind == "set" and not opp.pending and opp.tech == "bump" and opp.speed <= OVER_OK \
				and not (opp.player.role == "L" and absf(opp.point.x) < 3.0) and clock < opp.t + 0.15:
			opp.player.anim_tech = "over"
		# Zu spaet dran: die Bewegung haelt kurz im Treffpunkt an, bis der Ball wirklich gespielt wird
		opp.player.anim_t = maxf(opp.t, minf(clock, opp.t + 0.12))
		# Zu spaet dran: Arme und Haende gehen dem Ball nach, statt am geplanten Punkt zu warten.
		opp.player.contact_pt = opp.point.lerp(ball.position, smoothstep(0.0, 0.05, clock - opp.t))
		opp.player.contact_aim = _contact_aim(opp)
		opp.player.contact_on = true
	if phase == Phase.PRE_SERVE or (phase == Phase.TOSS and not serve_done):
		var sv := server()
		sv.anim_kind = "serve_hold" if phase == Phase.PRE_SERVE else "serve"
		sv.anim_tech = "jump" if serve_kind == 1 else "stand"
		sv.anim_t = serve_ideal if phase == Phase.TOSS else clock + 5.0
		sv.contact_pt = ball.position   # der Ball der Aufschlaghand (Wurf)
		sv.contact_aim = Vector3(-side_of(serving_team) * 4.0, 0.0, 0.0)
		sv.contact_on = phase == Phase.TOSS
	for t in 2:
		for pl in players[t]:
			if is_down(pl):
				pl.target = pl.position  # liegt noch am Boden oder steht gerade auf
			pl.urgent = opp != null and not opp.done and pl == opp.player
			pl.blocking = not blockers[t].is_empty() and pl in blockers[t]
			if pl.blocking:
				pl.urgent = true
			pl.tick(delta)
	VPlayer.separate(players[0] + players[1], delta)


## Wohin der Spieler den Ball spielt: Annahme zum Zuspieler, Zuspiel zum Angreifer, Angriff
## auf das Ziel im gegnerischen Feld. Der Koerper dreht sich beim Kontakt dorthin.
func _contact_aim(o: Opp) -> Vector3:
	var sd := side_of(o.team)
	match o.kind:
		"pass", "dig":
			var st := player_by_role(o.team, "S")
			if st != null and st != o.player:
				return Vector3(st.position.x, 0.0, st.position.z)
			return Vector3(sd * 1.5, 0.0, 0.5)
		"set":
			var h: VPlayer = _hitter[o.team]
			if h != null and h != o.player:
				return Vector3(h.position.x, 0.0, h.position.z)
			return Vector3(sd * 0.5, 0.0, o.point.z)
		"attack":
			var info := attack_shot(o.team, o.point, o.rs, o.power, o.finesse)
			return info.target
	return Vector3(-sd * 4.0, 0.0, 0.0)


## Wo der Spieler beim Kontakt steht: der Ball trifft vor dem Koerper auf (Baggern ca. 45 cm,
## Pritschen 15 cm vor dem Rumpf in Spielrichtung); beim Angriff steht der Spieler hinter dem Ball.
func _stand_pos(o: Opp, p: Vector3) -> Vector3:
	if o.kind == "attack":
		return p + Vector3(side_of(o.team) * 0.3, 0.0, 0.0)
	var aim := _contact_aim(o)
	var dv := Vector3(aim.x - p.x, 0.0, aim.z - p.z)
	if dv.length() < 0.1:
		return p
	var off := 0.15 if (o.kind == "set" or o.tech == "over") else 0.38
	return p - dv.normalized() * off


## Zeitlupe und Kamera: In jeder Spielphase gilt das eingestellte Tempo (Menue), die
## Kamera rueckt beim eigenen Aufschlag, Angriff und Block naeher.
## Kurzer Treffer-Stopp (Mini-Stopp). Nur wenn die Zeitlupe an ist: ohne Zeitlupe soll das Spiel
## ohne Unterbrechung durchlaufen. Hoechstens 60 ms, danach geht es sofort im alten Tempo weiter.
func _hit_stop(seconds: float, scale: float) -> void:
	if not slow_active():
		return
	_hitstop_left = minf(seconds, 0.06)
	_hitstop_scale = scale
	_after_stop = true


## Ist irgendeine Zeitlupe eingeschaltet (Schalter an und mindestens ein Regler ueber 0)?
func slow_active() -> bool:
	if not slowmo_on:
		return false
	for k in ["slow_serve", "slow_receive", "slow_set", "slow_attack", "slow_block"]:
		if cfg.get_v(k) > 0.0:
			return true
	return false


func _update_time_and_camera(real_delta: float) -> void:
	var want := 1.0
	cam_mode = ""
	cam_subject = null
	if human_team >= 0 and not autoplay:
		if (phase == Phase.PRE_SERVE or phase == Phase.TOSS) and human_serves() and not serve_done:
			cam_mode = "serve"
			cam_subject = server()
			if phase == Phase.TOSS and ((serve_kind == 1 and cam_subject.airborne) or (serve_kind == 0 and ball_vel.y < 1.5)):
				want = minf(want, cfg.time_scale("slow_serve"))
		elif phase == Phase.RALLY and opp != null and opp.kind == "attack":
			if opp.team == human_team:
				cam_mode = "attack"
				cam_subject = opp.player
				if opp.player.airborne and (not opp.done or clock < _slow_tail_until):
					want = minf(want, cfg.time_scale("slow_attack"))
			elif not blockers[human_team].is_empty():
				cam_mode = "block"
				cam_subject = blockers[human_team][0]
				if (opp.player.airborne or cam_subject.airborne) and not opp.done:
					want = minf(want, cfg.time_scale("slow_block"))
		elif phase == Phase.RALLY and opp != null and not opp.done and opp.human:
			var remain := opp.t - clock
			if remain < 0.45 and remain > -0.15:
				want = minf(want, cfg.time_scale("slow_set" if opp.kind == "set" else "slow_receive"))
		if phase == Phase.RALLY and last_action == "attack" and clock < _slow_tail_until:
			if opp == null or opp.team != human_team:
				want = minf(want, cfg.time_scale("slow_block"))
	if not slowmo_on:
		want = 1.0
	if _hitstop_left > 0.0:
		_hitstop_left -= real_delta
		want = minf(want, _hitstop_scale)
	if not zoom_on:
		cam_mode = ""
	if phase == Phase.REPLAY:
		cam_mode = "replay"
	if phase != Phase.RALLY and phase != Phase.TOSS:
		want = 1.0
	# Weich in die Zeitlupe hinein (schnell, damit das Timing nicht leidet) und langsamer
	# wieder heraus, statt hart zu springen. Der Treffer-Stopp greift sofort.
	want = clampf(want, 0.05, 1.0)
	if _hitstop_left > 0.0 and want <= _hitstop_scale + 0.001:
		_time_scale = want
	elif want < _time_scale:
		_time_scale = maxf(want, _time_scale - real_delta * 6.0)
		_after_stop = false
	else:
		# Nach dem Treffer-Stopp in gut 0,1 s zurueck, sonst wirkt der Ablauf wie Gummi.
		_time_scale = minf(want, _time_scale + real_delta * (9.0 if _after_stop else 1.8))
		if _time_scale >= want:
			_after_stop = false
	Engine.time_scale = _time_scale


func _update_visuals() -> void:
	# Flatterball: der Ball wackelt sichtbar, die echte Flugbahn bleibt berechenbar.
	var wob := Vector3.ZERO
	if flutter > 0.0 and last_action == "serve" and opp != null:
		var total := maxf(opp.t - serve_time, 0.1)
		var k := clampf((clock - serve_time) / total, 0.0, 1.0)
		var env := sin(k * PI)
		wob = Vector3(0.0, sin(clock * 11.0) * 0.06, sin(clock * 7.3 + 1.0)) * flutter * env
	ball_mesh.position = wob
	var vis := ball.position + wob
	ball_shadow.position = Vector3(vis.x, 0.008, vis.z)
	var k2 := clampf(1.0 - ball.position.y / 12.0, 0.4, 1.0)
	ball_shadow.scale = Vector3(k2, 1.0, k2)
	var hp := human_player()
	for t in 2:
		for pl in players[t]:
			pl.set_controlled(pl == hp)

	var show_ring := opp != null and not opp.done and opp.human
	_ring_target.visible = show_ring
	_ring_timer.visible = show_ring
	if show_ring:
		var p := Vector3(opp.point.x, 0.03, opp.point.z)
		_ring_target.position = p
		_ring_timer.position = p
		var remain := clampf((opp.t - clock) / 1.0, 0.0, 1.0)
		_ring_timer.scale = Vector3.ONE * (1.0 + remain * 2.5)
		var near: bool = absf(opp.t - clock) <= windows(opp.kind)[0] * opp.win_scale
		_ring_timer_mat.albedo_color = Color(0.3, 1.0, 0.3) if near else Color(1.0, 0.85, 0.1)
		# Laufhilfe: gruen = Pritschen geht, orange = lieber baggern.
		var tint := Color(1, 1, 1, 0.9)
		if assist and opp.kind != "attack":
			tint = Color(0.4, 1.0, 0.5, 0.95) if opp.speed <= OVER_OK else Color(1.0, 0.55, 0.15, 0.95)
		_ring_target_mat.albedo_color = tint

	var aim_vis := false
	preview_valid = false
	if human_team >= 0:
		if (phase == Phase.PRE_SERVE or phase == Phase.TOSS) and human_serves() and not serve_done:
			var sa := serve_aim
			if serve_style(serve_contact) == "short":
				sa.x = minf(sa.x, 3.2)
			sa.y -= serve_contact.x * 1.5
			_aim_marker.position = court_pos(human_team, Vector2(-sa.x, sa.y)) + Vector3(0, 0.03, 0)
			aim_vis = true
		elif show_ring and opp.kind in ["pass", "dig"] and opp.aim.length() >= Reception.STICK_MIN:
			_aim_marker.position = recv.preview(opp) + Vector3(0, 0.03, 0)  # wohin die gelenkte Annahme geht
			aim_vis = true
		elif show_ring and opp.kind == "attack":
			var info := attack_shot(opp.team, opp.point, rs, clampf(charge if charging else 0.8, 0.15, 1.0), opp.finesse)
			preview_target = info.target
			preview_valid = true
			_aim_marker.position = Vector3(preview_target.x, 0.03, preview_target.z)
			aim_vis = true
	_aim_marker.visible = aim_vis
	_draw_block_shadow()


## Blockschatten: der Bereich hinter dem Block, den der Block vom Angreifer aus abdeckt.
func _draw_block_shadow() -> void:
	_shadow_mesh.clear_surfaces()
	if human_team < 0 or not assist or phase != Phase.RALLY or opp == null or opp.done or opp.kind != "attack":
		return
	var def := 1 - opp.team
	if blockers[def].is_empty():
		return
	var P := opp.point
	var s := side_of(def)
	_shadow_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in blockers[def]:
		var top: float = b.block_top() if b.airborne else VPlayer.BLOCK_REACH + 0.8
		var zc: float = b.hands_z()
		var pts: Array = []
		for dz in [-0.3, 0.3]:
			var E := Vector3(s * 0.25, top, zc + dz)
			var far: Vector3
			if top >= P.y - 0.05:
				far = P + (E - P) * 20.0
			else:
				far = P + (E - P) * (P.y / (P.y - top))
			# Auf das Feld des Verteidigers begrenzen.
			if absf(far.x) > HALF_L:
				var f := (HALF_L - absf(E.x)) / maxf(absf(far.x - E.x), 0.01)
				far = E + (far - E) * f
			pts.append(Vector3(E.x, 0.012, E.z))
			pts.append(Vector3(far.x, 0.012, far.z))
		var a: Vector3 = pts[0]
		var af: Vector3 = pts[1]
		var bq: Vector3 = pts[2]
		var bf: Vector3 = pts[3]
		for v in [a, af, bf, a, bf, bq]:
			_shadow_mesh.surface_add_vertex(v)
	_shadow_mesh.surface_end()


## Kurzer Hinweis, was der Mensch gerade tun kann.
func hint() -> String:
	match phase:
		Phase.INTRO:
			return ""
		Phase.REPLAY:
			return "Wiederholung  ·  A / Leertaste: überspringen"
		Phase.PRE_SERVE:
			if human_serves() and whistle_done:
				var left := int(ceilf(serve_deadline - clock))
				return "Noch %d s" % left if left <= 3 else ""
			return ""
		Phase.TOSS:
			return ""
		Phase.RALLY:
			if drill == null:
				return ""  # im Ballwechsel kein Text
			if opp != null and not opp.done and opp.team == human_team and opp.human:
				match opp.kind:
					"pass":
						return "Annahme: A/Leertaste (baggern) oder X/Q (pritschen) halten, loslassen wenn der Ring sich schließt"
					"dig":
						return "Abwehr! A/Leertaste halten, loslassen wenn sich der Ring schließt"
					"set":
						if opp.player.role == "L" and absf(opp.point.x) < 3.0:
							return "Libero vor der 3-m-Linie: nur baggern (A / Leertaste), Pritschen wäre ein Fehler!"
						return "Zuspiel: Steuerkreuz halten, loslassen = Zuspiel (links Außen · rechts Diagonal · oben Mitte · unten Hinterfeld) · R2 halten = schneller Ball · R1 = Dump · R1+R2 = Zuspieler schlägt"
					"attack":
						return "Angriff: R2/E halten und beim Treffpunkt loslassen · Trefferpunkt rechter Stick/Maus (oben Topspin, unten Leger) · L2/Umschalt dazu = Gefühlsschlag · linker Stick = Anlauf"
					"free":
						return "Ball rüberspielen: X/Q oder A/Leertaste halten und rechtzeitig loslassen"
			if human_player() != null:
				return "Block: linker Stick = Block, rechter Stick = zweiter Blocker · R2/E springen (beide) · in der Luft Stick = Hände"
			if opp != null and opp.team != human_team and opp.kind == "set" and (drill == null or drill.human_does("block")):
				return "Block lesen: linker Stick stellt den Mittelblocker am Netz hin, bevor der Ball zum Angreifer fliegt"
	return ""


## Ballkontakt als Stoss auf den Koerper (Semi-Ragdoll, siehe VPlayer.impact): wer den Ball
## spielt, gibt in Flugrichtung des ankommenden Balls nach; am Block alle Blocker in der Naehe.
func _body_hit(kind: String, pos: Vector3, strength: float) -> void:
	var incoming := -ball_vel if ball_vel.length() > 0.1 else Vector3.DOWN
	match kind:
		"bump", "set":
			if last_toucher:
				var k := kind
				if kind == "bump" and last_toucher.anim_kind == "dig":
					k = "dig"
				# Richtung, aus der der Ball kam: vor dem Kontakt flog er auf den Spieler zu
				var come: Vector3 = (pos - last_toucher.global_position - Vector3.UP * 1.0)
				last_toucher.impact(k, strength, -come.normalized() * 0.3 + Vector3.DOWN * 0.7 if kind == "bump" else -come)
		"spike", "spike_perfect", "spike_super", "tip":
			if last_toucher:
				last_toucher.impact("spike", strength * (0.4 if kind == "tip" else 1.0), Vector3.ZERO)
		"serve":
			var sv = last_toucher
			if sv and sv.airborne:
				sv.impact("serve", strength * 0.6, Vector3.ZERO)
		"block":
			for t in 2:
				for pl in players[t]:
					if pl.block_pose and pl.global_position.distance_to(Vector3(pos.x, 0, pos.z)) < 1.6:
						pl.impact("block", strength, Vector3(pl.side, 0.15, 0.0) - incoming.normalized() * 0.0)
