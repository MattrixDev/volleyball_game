class_name Ballistics
extends RefCounted
## Flugbahn-Rechnung ohne Luftwiderstand. Weil die Bahn exakt berechenbar ist,
## kann das Spiel den Landepunkt und den Moment der Ballberuehrung vorhersagen.

const G := 9.81
const BALL_R := 0.105


## Neue Position und Geschwindigkeit nach dt Sekunden (exakt fuer konstante Schwerkraft).
static func advance(pos: Vector3, vel: Vector3, dt: float) -> Array:
	var p := pos + vel * dt + Vector3(0.0, -0.5 * G * dt * dt, 0.0)
	var v := vel + Vector3(0.0, -G * dt, 0.0)
	return [p, v]


static func pos_at(pos: Vector3, vel: Vector3, t: float) -> Vector3:
	return pos + vel * t + Vector3(0.0, -0.5 * G * t * t, 0.0)


## Zeit, bis der Ball im Fallen die Hoehe h erreicht; -1, wenn er sie nie erreicht.
static func time_to_height(pos: Vector3, vel: Vector3, h: float) -> float:
	var disc := vel.y * vel.y + 2.0 * G * (pos.y - h)
	if disc < 0.0:
		return -1.0
	var t := (vel.y + sqrt(disc)) / G
	return t if t >= 0.0 else -1.0


static func apex_height(pos: Vector3, vel: Vector3) -> float:
	if vel.y <= 0.0:
		return pos.y
	return pos.y + vel.y * vel.y / (2.0 * G)


## Abwurf so, dass der Ball nach t Sekunden genau bei `to` ist.
static func launch_with_time(from: Vector3, to: Vector3, t: float) -> Vector3:
	t = maxf(t, 0.05)
	return (to - from + Vector3(0.0, 0.5 * G * t * t, 0.0)) / t


## Abwurf mit fester horizontaler Geschwindigkeit u (m/s), z. B. fuer Schmetterbaelle.
static func launch_with_speed(from: Vector3, to: Vector3, u: float) -> Vector3:
	var dist := Vector2(to.x - from.x, to.z - from.z).length()
	return launch_with_time(from, to, dist / maxf(u, 0.1))


## Abwurf ueber das Netz (Ebene x = 0): Der Ball ueberquert das Netz in Hoehe clear_h
## und landet bei `to`. Die Geschwindigkeit wird auf [u_min, u_max] begrenzt; ist u_max
## zu klein, fliegt der Ball tiefer als clear_h und kann im Netz landen.
static func launch_over_net(from: Vector3, to: Vector3, clear_h: float, u_min: float, u_max: float) -> Vector3:
	var dx := to.x - from.x
	if absf(dx) < 0.01 or signf(from.x) == signf(to.x):
		return launch_with_time(from, to, 1.0)
	var dt := Vector2(dx, to.z - from.z).length()
	var dn := dt * absf(from.x) / absf(dx)
	var num := clear_h - from.y - (dn / dt) * (to.y - from.y)
	var u := u_max
	if num > 0.0:
		var a2 := 2.0 * num / (G * dn * (dt - dn))
		u = clampf(1.0 / sqrt(a2), u_min, u_max)
	return launch_with_speed(from, to, u)
