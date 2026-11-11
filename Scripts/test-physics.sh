#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
# Also works with Command Line Tools alone, where XCTest is not shipped.
xcrun swiftc -D STANDALONE_TESTS Sources/SnowCore/*.swift Tests/SnowCoreTests/*.swift -o build/PhysicsTests
build/PhysicsTests
