#!/bin/zsh
# Собирает code.js из src/_lib.js + src/<step>.js; __ASSET_<name>__ → base64 файла assets/**/<name>,
# __JSON_<name>__ → содержимое JSON-файла assets/<name> как есть
# Использование: ./build.sh 01-dump
# В Figma включён Hot reload — каждая сборка сразу запускает плагин.
set -e
cd "${0:A:h}"
step="$1"; src="src/$step.js"
[[ -f "$src" ]] || { echo "нет $src"; exit 1; }
python3 -I - "$src" src/_lib.js assets "$step" > code.js <<'PY'
import sys, re, base64, pathlib
src, lib, assets, step = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3]), sys.argv[4]
def sub(m):
    name = m.group(1); direct = assets / name
    hits = [direct] if direct.is_file() else (list(assets.rglob(name)) if assets.is_dir() else [])
    if not hits: sys.exit(f"asset not found: {name}")
    return base64.b64encode(hits[0].read_bytes()).decode()
code = lib.read_text().replace('__STEP__', step) + '\n' + src.read_text()
code = re.sub(r"__JSON_([A-Za-z0-9_.\-/]+?)__", lambda m: (assets / m.group(1)).read_text(), code)
sys.stdout.write(re.sub(r"__ASSET_([A-Za-z0-9_.\-/]+?)__", sub, code))
PY
echo "code.js ← $step ($(wc -c < code.js) bytes)"
