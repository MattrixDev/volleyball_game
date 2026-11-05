extends Node
## Test: Bildzeit messen (--perf=Sekunden). Gibt Physik- und Prozesszeit pro Bild aus.
var t := 0.0
var dur := 30.0
var frames: Array = []
var last_us := 0

func _ready() -> void:
	process_priority = 1000
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--perf="):
			dur = float(a.get_slice("=", 1))
	last_us = Time.get_ticks_usec()

func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	frames.append([(now - last_us) / 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Engine.time_scale])
	last_us = now
	t += delta / maxf(Engine.time_scale, 0.01)
	if t > dur:
		var ph := []
		var pr := []
		var ft := []
		for f in frames.slice(30):
			ft.append(f[0]); ph.append(f[1]); pr.append(f[2])
		ph.sort(); pr.sort(); ft.sort()
		var n := ph.size()
		print("PERF frames=%d  frame ms p50=%.2f p95=%.2f p99=%.2f max=%.2f" % [n, ft[n/2], ft[int(n*0.95)], ft[int(n*0.99)], ft[n-1]])
		print("PERF physics ms p50=%.2f p95=%.2f p99=%.2f max=%.2f" % [ph[n/2], ph[int(n*0.95)], ph[int(n*0.99)], ph[n-1]])
		print("PERF process ms p50=%.2f p95=%.2f p99=%.2f max=%.2f" % [pr[n/2], pr[int(n*0.95)], pr[int(n*0.99)], pr[n-1]])
		print("frames ", frames.size())
		get_tree().quit()
