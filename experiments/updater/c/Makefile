CC ?= cc
CFLAGS ?= -std=c11 -O2 -Wall -Wextra -Wpedantic
BUILD := build

BIN := $(BUILD)/downgrade-guard
TEST_BIN := $(BUILD)/guard_test

.PHONY: all test clean

all: $(BIN)

$(BUILD):
	mkdir -p $@

$(BIN): src/main.c src/guard.c src/guard.h | $(BUILD)
	$(CC) $(CFLAGS) -o $@ src/main.c src/guard.c

$(TEST_BIN): tests/guard_test.c src/guard.c src/guard.h | $(BUILD)
	$(CC) $(CFLAGS) -o $@ tests/guard_test.c src/guard.c

test: $(TEST_BIN)
	./$(TEST_BIN)

clean:
	rm -rf $(BUILD)
