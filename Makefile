TEST_IMAGE ?= ghrunner-test:local

.PHONY: test test-build

test:
	@TEST_IMAGE=$(TEST_IMAGE) bash tests/run-tests.sh

test-build:
	docker build -t $(TEST_IMAGE) .
