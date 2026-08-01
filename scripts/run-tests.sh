#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
TEST_BINARY="$PROJECT_DIR/.build/standalone-tests"

mkdir -p "$PROJECT_DIR/.build"
swiftc -parse-as-library \
    "$PROJECT_DIR/Sources/PingPong/Models.swift" \
    "$PROJECT_DIR/Sources/PingPong/Services.swift" \
    "$PROJECT_DIR/Tests/PingPongTests/StandaloneTests.swift" \
    -o "$TEST_BINARY"
"$TEST_BINARY"
