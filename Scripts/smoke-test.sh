#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun swiftc Tools/WindowFixture.swift -o build/WindowFixture
build/WindowFixture
