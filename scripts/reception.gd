class_name Reception
extends RefCounted
## Annahme und Abwehr fuer den Menschen steuerbar (Skill-Gap, Schritt 1):
##  A1 Annahme lenken beim Kontakt: R1 = flach ans Netz, L1 = hoch zur 3-m-Linie, linker Stick
##     seitlich = Ball neben dem Koerper ausgleichen (rechter Stick geht auch).
##  A2 Frontal hinter dem Ball: wer manuell laeuft und rechtzeitig hinter dem Ball steht, hat
##     ein groesseres Timing-Fenster und nimmt genauer an.
##  A4 Hechten von Hand (B): frueh hechten reicht weiter, danach liegt man am Boden.
## Grundregel: ohne Stick, mit Laufhilfe und ohne B laeuft alles wie bisher.
## Das Match ruft die Funktionen hier an wenigen Stellen auf; die Regeln stehen alle hier.

const STICK_MIN := 0.4  # ab diesem Ausschlag zaehlt der Stick als Absicht
const SQUARE_DIST := 0.32  # so nah am idealen Standpunkt (m) = frontal hinter dem Ball
const SIDE_DIST := 0.6  # ab hier: seitlich angenommen
const DIVE_EARLY := 0.25  # so viel frueher (s) gehechtet = volle Zusatzreichweite

var m  # Match


func _init(match_node) -> void:
	m = match_node


func _skill01(o) -> float:
	return clampf(0.5 + 0.5 * m._touch_skill(o.player, o.kind), 0.0, 1.0)


## Rechter Stick in Spielrichtung: x = seitlich (+ rechts), y = vorn (Richtung Netz).
## Der Stick ist schon aus Sicht der Kamera hinter dem eigenen Team gemessen, passt also direkt.
static func aim_key(aim: Vector2) -> String:
	if aim.length() < STICK_MIN:
		return ""
	if absf(aim.y) >= absf(aim.x):
		return "pass_flat" if aim.y > 0.0 else "pass_high"
	return "pass_fix"


## Eingabe waehrend einer eigenen Annahme / Abwehr (vor dem Kontakt). Merkt sich den Stick und
## loest auf B den Hechtsprung aus. true = B hat den Kontakt ausgeloest.
func input(o, inp: Dictionary) -> bool:
	if o.pending:
		return false
	# Lenken ohne den rechten Daumen (der drueckt A/X oder B): R1 halten = flach ans Netz,
	# L1 halten = hoch und sicher, linker Stick seitlich im Kontakt = seitlich ausgleichen.
	# Der rechte Stick geht weiter (Tastatur IJKL, wer lieber so spielt).
	var a: Vector2 = inp.get("rs_pad", Vector2.ZERO)
	if a.length() < STICK_MIN:
		var fwd := (1.0 if inp.get("dump_held", false) else 0.0) - (1.0 if inp.get("l1_held", false) else 0.0)
		var mv: Vector2 = inp.get("mv", Vector2.ZERO)
		a = Vector2(mv.x if absf(mv.x) > 0.6 and fwd == 0.0 else 0.0, fwd)
	o.aim = a if o.kind != "free" else Vector2.ZERO
	o.player.platform_tilt = o.aim if o.aim.length() >= STICK_MIN else Vector2.ZERO
	if inp.get("fast", false):
		return _start_dive(o)
	return false


## B: Hechten. Der Druck ist zugleich der Ballkontakt (Timing wie beim Baggern).
func _start_dive(o) -> bool:
	var e: float = m.human_clock() - o.t
	if e < -0.6:
		return false  # viel zu frueh: zaehlt nicht
	var pl = o.player
	var goal: Vector3 = m._stand_pos(o, Vector3(o.point.x, 0.0, o.point.z))
	var dv := Vector3(goal.x - pl.position.x, 0.0, goal.z - pl.position.z)
	var to_net: float = -m.side_of(o.team)
	o.dove = true
	o.dive_e = e
	o.style = Technique.manual_dive(dv.x * to_net, dv.z, dv.length(), o.kind == "dig")
	o.style_locked = true
	o.tech = "bump"
	o.win_scale *= 1.3  # der Hecht ueberbrueckt Raum: das Timing ist etwas gnaediger
	if pl.dive_timer <= 0.0:
		pl.anim_t = o.t  # die Figur plant den Hecht so, dass sie im Kontakt voll gestreckt ist
		pl.dive()
	m._press(o, e, "")
	return true


## Kurz vor dem Kontakt (vor der Bewertung des Timings): Fenster fuer A1, A2 und A4 anpassen.
func before_touch(o) -> void:
	o.recv_keys = []
	var sk := _skill01(o)
	# A2: nur wer selbst laeuft, bekommt den Bonus. Die Laufhilfe stellt dich hin wie bisher.
	if not m.cfg.assisted("run") and not o.dove:
		var sp: Vector3 = m._stand_pos(o, Vector3(o.point.x, 0.0, o.point.z))
		var d: float = m.flat_dist(o.player.position, sp)
		if d <= SQUARE_DIST + 0.1 * sk:
			o.square = true
			o.win_scale *= 1.2 + 0.1 * sk
			o.recv_keys.append("square")
		elif d >= SIDE_DIST:
			o.recv_keys.append("side_taken")
	var k := aim_key(o.aim)
	if k == "pass_flat":
		# Flach ans Netz: kleineres Fenster (gute Annehmer verlieren weniger).
		o.win_scale *= lerpf(0.78, 0.92, sk)
	elif k == "pass_high":
		o.win_scale *= 1.1
	if k != "":
		o.recv_keys.append(k)
	if o.dove:
		o.recv_keys.append("dive")


## Reichweite beim Kontakt. Hecht von Hand: weiter, je frueher gehechtet; im manuellen Modus ohne B
## gibt es keinen automatischen Hecht mehr (der Spieler bleibt stehen).
func reach(o, base: float) -> float:
	if o.dove:
		var early := clampf(-o.dive_e / DIVE_EARLY, 0.0, 1.0)
		var late := clampf(o.dive_e / 0.15, 0.0, 1.0)
		var r := Technique.reach(o.style) + 0.35 * early - 0.3 * late
		r += 0.12 * m.pf(o.player, "defense") + (0.1 if m.ptrait(o.player, "katze") else 0.0)
		return maxf(r, 0.75)
	return base


## Im Modus "Hechten manuell" waehlt das Spiel keine Hecht-Techniken mehr von selbst.
func filter_style(o, st: String) -> String:
	if o.human and not o.dove and not m.cfg.assisted("dive") and Technique.goes_down(st):
		return "one_arm"
	return st


## Annahme-Ziel (A1/A2). Bekommt die Werte aus Match._do_pass und gibt sie veraendert zurueck:
## d (Abstand zum Netz), l (seitlich), spread, side (-1..1, Ball neben dem Koerper), T_mul, h, ex_mul.
func pass_mods(o, v: Dictionary) -> Dictionary:
	if not o.human:
		return v
	var sk := _skill01(o)
	var manual: bool = not m.cfg.assisted("pass_aim")
	var a: Vector2 = o.aim if o.aim.length() >= STICK_MIN else Vector2.ZERO
	var k := aim_key(a)
	if o.square:
		v.spread *= 0.6
		v.side *= 0.3
	if k == "pass_flat" or (manual and a.y > 0.0):
		var f := 1.0 if not manual else clampf(a.y, 0.0, 1.0)
		v.d -= 0.6 * f
		v.h -= 0.3 * f
		v.T_mul *= lerpf(1.0, 0.72, f)
		v.ex_mul *= lerpf(1.0, 1.35, f)  # zu frueh = eher ueber das Netz
	elif k == "pass_high" or (manual and a.y < 0.0):
		var f := 1.0 if not manual else clampf(-a.y, 0.0, 1.0)
		v.d += 1.8 * f
		v.h += 0.2 * f
		v.T_mul *= lerpf(1.0, 1.35, f)
		v.spread *= lerpf(1.0, 0.65, f)
	# Seitlich: der Stick kippt die Arme. Assistiert gleicht jede Seitwaerts-Eingabe richtig aus,
	# manuell zaehlt die Richtung: richtig gegengehalten hebt den Fehler auf, falsch verdoppelt ihn,
	# und ohne Seitenfehler lenkt der Stick den Ball entlang des Netzes.
	var comp := lerpf(0.55, 1.0, sk)  # gute Annehmer (Libero) gleichen leichter aus
	if not manual:
		if k == "pass_fix":
			v.side *= 1.0 - comp
	elif absf(a.x) >= 0.2:
		v.side = clampf(v.side + a.x * comp * 1.2, -1.5, 1.5)
		v.l += a.x * 0.9
	return v


## Folge fuer das Zuspiel: flache Annahme erlaubt den Schnellangriff auch knapp, hohe Annahme nicht.
func set_tempo_after_pass(o, tempo: String) -> String:
	var k: String = m.pass_kind[o.team]
	if k == "pass_flat":
		o.slack += 0.4  # der Ball ist schnell am Netz: der Zuspieler steht rechtzeitig, Schnellangriff geht
	if k == "pass_high" and tempo == "quick":
		if o.human:
			m.popup(o.player, "Annahme zu hoch für Schnellangriff", m.Q_COLOR[m.Q.WEAK])
		return "fast"
	return tempo


## Nach einem gelungenen Kontakt: Name der Technik fuer die Anzeige und das Signal.
func done(o, q: int) -> void:
	var keys: Array = o.recv_keys
	m.pass_kind[o.team] = ""
	for k in keys:
		if k in ["pass_flat", "pass_high", "pass_fix"]:
			m.pass_kind[o.team] = k
	if keys.is_empty():
		return
	var main := ""
	for k in ["dive", "pass_flat", "pass_high", "pass_fix", "square"]:
		if k in keys:
			main = k
			break
	o.tech_key = main  # Match._log_touch meldet ihn (technique_done)
	for k in keys:
		if k != main:
			m.technique_done.emit(o.player, k)


## Welche neuen Techniken gerade gehen (fuer den Tastenhinweis beim ersten Mal).
func available(o) -> Array:
	var list := ["pass_flat", "pass_high"]
	var sp: Vector3 = m._stand_pos(o, Vector3(o.point.x, 0.0, o.point.z))
	var side: float = absf(m.team_local(o.team, o.point).y - m.team_local(o.team, o.player.position).y)
	if side > 0.35:
		list.push_front("pass_fix")
	if o.pressure > 0.55 or Technique.goes_down(m._defense_style(o)):
		list.push_front("dive")
	if not m.cfg.assisted("run") and m.flat_dist(o.player.position, sp) > 1.0:
		list.append("square")
	return list


## Ungefaehres Ziel der gelenkten Annahme (Markierung am Boden, ohne Timing-Fehler).
func preview(o) -> Vector3:
	var v := pass_mods(o, {"d": m.SETTER_TARGET.x, "l": m.SETTER_TARGET.y, "spread": 0.0, "side": 0.0, "T_mul": 1.0, "h": m.H_SET, "ex_mul": 1.0})
	return m.court_pos(o.team, Vector2(v.d, v.l))
