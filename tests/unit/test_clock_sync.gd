extends TestCase

## Client clock = host clock + 100. One-way delay 0.05 (rtt 0.1). Frames carry client t.
func _feed(c: ClockSync, owd := 0.05) -> void:
	for i in 30:
		var host_send := 10.0 + i / 60.0
		c.observe(5, host_send + 100.0, host_send + owd + (0.01 if i % 3 == 0 else 0.0))

func test_offset_uses_least_delayed_sample() -> void:
	var c := ClockSync.new()
	c.set_rtt(5, 0.1)
	_feed(c)
	assert_near(c.offset(5), 100.0, 1e-3, "offset")

func test_rewind_time() -> void:
	var c := ClockSync.new()
	c.set_rtt(5, 0.1)
	_feed(c)
	# client fires at host-time 10.3 (client 110.3); host now = 10.35. Shooter saw world at
	# 10.3 - owd(0.05) - interp(0.1) = 10.15
	var t := c.rewind_time(5, 110.3, 10.35, 0.1)
	assert_near(t, 10.15, 2e-3, "rewind")

func test_rewind_clamped() -> void:
	var c := ClockSync.new()
	c.set_rtt(5, 0.1)
	_feed(c)
	assert_near(c.rewind_time(5, 90.0, 10.35, 0.1), 10.10, 1e-4, "too old -> now-0.25")
	assert_near(c.rewind_time(5, 999.0, 10.35, 0.1), 10.35, 1e-4, "future -> now")

func test_unknown_peer_falls_back_to_now() -> void:
	var c := ClockSync.new()
	assert_near(c.rewind_time(77, 5.0, 10.0, 0.1), 10.0, 1e-4, "no samples")

func test_offset_is_stable_when_samples_worsen() -> void:
	var c := ClockSync.new()
	c.set_rtt(5, 0.1)
	_feed(c)
	var before := c.offset(5)
	c.observe(5, 110.0, 10.0 + 0.15)           # one very late frame
	assert_true(absf(c.offset(5) - before) < 2e-3, "no jump")
	for i in 400:                               # long-running steady state: no step changes
		var prev := c.offset(5)
		c.observe(5, 110.0 + i * 0.016, 10.0 + i * 0.016 + 0.07)
		assert_true(absf(c.offset(5) - prev) < 2e-3, "smooth step %d" % i)
