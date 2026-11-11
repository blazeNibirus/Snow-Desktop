#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/render-probe
# Compile the real app renderer with the core in one test module (no XCTest required).
python3 - <<'PY'
from pathlib import Path
for name in ['Settings', 'SnowView']:
    text = Path(f'Sources/SnowDesktop/{name}.swift').read_text().replace('import SnowCore\n', '')
    Path(f'build/render-probe/{name}.swift').write_text(text)
PY
xcrun swiftc Sources/SnowCore/*.swift build/render-probe/*.swift Tools/RenderProbe.swift -o build/RenderProbe
build/RenderProbe "$PWD/build/RenderProbe.png"
