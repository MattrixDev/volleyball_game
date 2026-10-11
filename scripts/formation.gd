class_name Formation
extends RefCounted
## Aufstellung bei der Annahme und die Ueberlappungsregeln (FIVB 7.4).
## Lokale Koordinaten wie in match.gd: x = Abstand zum Netz, y = seitlich (+ = rechts).
## Positionen: 1 rechts hinten, 2 rechts vorn, 3 Mitte vorn, 4 links vorn, 5 links hinten, 6 Mitte hinten.

## Regelpaare: [a, b, "lat"] heisst a steht links von b; [a, b, "depth"] heisst a (vorn) steht
## naeher am Netz als b (hinten). Bewertet wird im Moment des Aufschlags.
const PAIRS := [
	[4, 3, "lat"], [3, 2, "lat"], [5, 6, "lat"], [6, 1, "lat"],
	[4, 5, "depth"], [3, 6, "depth"], [2, 1, "depth"],
]
const MARGIN := 0.55

## Annahme-Raute (W): links, Mitte, rechts.
const W_SPOTS := [Vector2(5.2, -3.0), Vector2(6.4, 0.0), Vector2(5.2, 3.0)]
const HOME := {1: Vector2(6.0, 3.0), 2: Vector2(1.8, 3.4), 3: Vector2(1.6, -0.4), 4: Vector2(3.0, -3.4), 5: Vector2(6.0, -3.0), 6: Vector2(6.4, 0.0)}
const NET_Y := {4: -2.8, 3: 0.0, 2: 3.0}
const DEEP_Y := {5: -3.4, 6: 0.0, 1: 3.4}


static func is_front(slot: int) -> bool:
	return slot >= 2 and slot <= 4


static func _lateral(slot: int) -> int:
	return -1 if slot == 4 or slot == 5 else (1 if slot == 1 or slot == 2 else 0)


## Wer nimmt an? Libero und Aussenangreifer; fehlt einer, hilft ein Hinterspieler (nie der Zuspieler).
static func passer_slots(roles: Dictionary) -> Array:
	var res: Array = []
	for s in roles:
		if roles[s] == "L" or roles[s] == "OH":
			res.append(s)
	var extra: Array = []
	for s in roles:
		if not is_front(s) and roles[s] != "S" and not res.has(s):
			extra.append(s)
	extra.sort_custom(func(a, b): return (0 if roles[a] == "OP" else 1) < (0 if roles[b] == "OP" else 1))
	while res.size() < 3 and not extra.is_empty():
		res.append(extra.pop_front())
	return res


## Ziel-Position jedes Spielers bei der Annahme, bereits regelgerecht (keine Ueberlappung).
## roles: Position -> Rolle ("S", "OH", "MB", "OP", "L").
static func receive_spots(roles: Dictionary) -> Dictionary:
	var spots := {}
	var passers := passer_slots(roles)
	var cand: Array = W_SPOTS if passers.size() >= 3 else [Vector2(5.4, -2.4), Vector2(5.4, 2.4)]
	var best_cost := 1e9
	var best: Array = []
	for perm in _perms(passers.size()):
		var cost := 0.0
		for i in passers.size():
			var s: int = passers[i]
			var sp: Vector2 = cand[perm[i]]
			if is_front(s):
				sp.x = maxf(sp.x - 2.0, 3.0)
			cost += (HOME[s] - sp).length()
			if roles[s] == "L":
				cost += 1.5 * absf(sp.y)
		if cost < best_cost:
			best_cost = cost
			best = perm
	for i in passers.size():
		var s: int = passers[i]
		var sp: Vector2 = cand[best[i]]
		if is_front(s):
			sp.x = maxf(sp.x - 2.0, 3.0)
		spots[s] = sp
	for s in roles:
		if spots.has(s):
			continue
		if roles[s] == "S":
			spots[s] = Vector2(0.9, 2.2) if is_front(s) else Vector2(2.8, 2.4)
		elif is_front(s):
			spots[s] = Vector2(1.1, NET_Y[s])
		else:
			spots[s] = Vector2(8.0, DEEP_Y[s])
	return resolve(spots)


static func _perms(n: int) -> Array:
	if n == 3:
		return [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
	if n == 2:
		return [[0, 1], [1, 0]]
	var r: Array = []
	for i in n:
		r.append(i)
	return [r]


## Schiebt Spieler gegenseitig auseinander, bis alle Regelpaare mit Abstand MARGIN eingehalten sind.
static func resolve(spots: Dictionary) -> Dictionary:
	var sp := spots.duplicate()
	for _it in 80:
		var changed := false
		for pr in PAIRS:
			var a: int = pr[0]
			var b: int = pr[1]
			if not sp.has(a) or not sp.has(b):
				continue
			var va: Vector2 = sp[a]
			var vb: Vector2 = sp[b]
			if pr[2] == "lat":
				var gap := vb.y - va.y
				if gap < MARGIN:
					var d := (MARGIN - gap) * 0.5 + 0.001
					va.y -= d
					vb.y += d
					changed = true
			else:
				var gap2 := vb.x - va.x
				if gap2 < MARGIN:
					var d2 := (MARGIN - gap2) * 0.5 + 0.001
					va.x -= d2
					vb.x += d2
					changed = true
			sp[a] = va
			sp[b] = vb
		for s in sp:
			var v: Vector2 = sp[s]
			sp[s] = Vector2(clampf(v.x, 0.5, 8.6), clampf(v.y, -4.2, 4.2))
		if not changed:
			break
	return sp


## Liste der verletzten Regelpaare (leer = alles in Ordnung). `skip` = Positionen ohne Regelpruefung.
static func violations(spots: Dictionary, skip: Array = []) -> Array:
	var bad: Array = []
	for pr in PAIRS:
		var a: int = pr[0]
		var b: int = pr[1]
		if skip.has(a) or skip.has(b) or not spots.has(a) or not spots.has(b):
			continue
		var va: Vector2 = spots[a]
		var vb: Vector2 = spots[b]
		if (pr[2] == "lat" and va.y >= vb.y) or (pr[2] == "depth" and va.x >= vb.x):
			bad.append(pr)
	return bad


## Linien zwischen den Spielern: je Regelpaar ein Strich auf der Grenze (Mitte zwischen beiden).
## Rueckgabe: Liste von {a: Vector2, b: Vector2, kind: "lat"/"depth"} in lokalen Koordinaten.
static func lines(spots: Dictionary, skip: Array = []) -> Array:
	var res: Array = []
	for pr in PAIRS:
		var a: int = pr[0]
		var b: int = pr[1]
		if skip.has(a) or skip.has(b) or not spots.has(a) or not spots.has(b):
			continue
		var va: Vector2 = spots[a]
		var vb: Vector2 = spots[b]
		var mid := (va + vb) * 0.5
		if pr[2] == "lat":
			res.append({"a": Vector2(mid.x - 1.7, mid.y), "b": Vector2(mid.x + 1.7, mid.y), "kind": "lat"})
		else:
			res.append({"a": Vector2(mid.x, mid.y - 1.7), "b": Vector2(mid.x, mid.y + 1.7), "kind": "depth"})
	return res


## Verbindungslinien von Spieler zu Spieler: ein Ring ueber alle Nachbarn (4-3-2-1-6-5-4) plus die
## Mittellinie 3-6. Ein Spieler darf nicht auf die andere Seite der Linie zu seinem Nachbarn.
static func links(spots: Dictionary, skip: Array = []) -> Array:
	var res: Array = []
	for pr in PAIRS:
		var a: int = pr[0]
		var b: int = pr[1]
		if skip.has(a) or skip.has(b) or not spots.has(a) or not spots.has(b):
			continue
		res.append({"a": spots[a], "b": spots[b], "kind": pr[2]})
	return res
