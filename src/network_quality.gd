extends RefCounted

const MAX_PING_MS = 8000
const FRESH_MS = 12000
const SAMPLE_COUNT = 20

var samples: Array[bool] = []
var last_ping = -1
var last_ping_at = 0

static func valid_ping(value: Variant) -> bool:
	return value is int and value >= 0 and value <= MAX_PING_MS

func record(milliseconds: int, now: int) -> void:
	var received := valid_ping(milliseconds)
	samples.append(received)
	if samples.size() > SAMPLE_COUNT: samples.pop_front()
	if received:
		last_ping = milliseconds
		last_ping_at = now

func ping_ms(now: int) -> int:
	return last_ping if now - last_ping_at <= FRESH_MS else -1

func failure_percent() -> int:
	return roundi(100.0 * samples.count(false) / samples.size()) if not samples.is_empty() else -1
