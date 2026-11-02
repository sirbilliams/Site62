extends TestCase

func test_true() -> void:
	assert_eq(1 + 1, 2)

func test_fail_reports() -> void:
	var tc := TestCase.new()
	tc.assert_eq(1, 2, "expected")
	assert_eq(tc.failures.size(), 1)
