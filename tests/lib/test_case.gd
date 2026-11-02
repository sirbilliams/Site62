class_name TestCase
extends RefCounted

var failures: Array[String] = []

func assert_eq(a, b, msg := "") -> void:
	if typeof(a) != typeof(b) or a != b:
		failures.append("%s expected %s got %s" % [msg, str(b), str(a)])

func assert_true(c, msg := "") -> void:
	if not c:
		failures.append("%s expected true" % msg)

func assert_near(a: float, b: float, eps := 1e-4, msg := "") -> void:
	if absf(a - b) > eps:
		failures.append("%s expected %s ~ %s (eps %s)" % [msg, str(a), str(b), str(eps)])
