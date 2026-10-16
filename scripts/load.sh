#!/bin/bash
# Validates the extensions and loads them into the local base, one by one, never touching others.
# Usage: scripts/load.sh [ExtensionName ...]  (default: both extensions of this project).
# Base path, user and platform come from .v8-project.json (the first base).
# Must run outside the Claude Code sandbox: 1C exits with 134 inside it.

set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGISTRY="$ROOT/.v8-project.json"
SKILLS="$ROOT/.claude/skills"
cd "$ROOT"

json() { plutil -extract "$1" raw -o - "$REGISTRY"; }
BASE_PATH="$(json databases.0.path)"
BASE_USER="$(json databases.0.user)"

if [ "$#" -eq 0 ]; then
  set -- МгновеннаяОтправкаПисем МгновеннаяОтправкаПисемТесты
fi

for EXT in "$@"; do
  DIR="src/$EXT"
  echo "=== $EXT"
  # Module files must start with exactly one UTF-8 BOM.
  python3 - "$DIR" <<'PY'
import pathlib, sys
BOM = b'\xef\xbb\xbf'
for p in pathlib.Path(sys.argv[1]).rglob('*.bsl'):
    data = p.read_bytes()
    body = data
    while body.startswith(BOM):
        body = body[3:]
    if data != BOM + body:
        p.write_bytes(BOM + body)
        print('BOM fixed:', p)
PY
  python3 "$SKILLS/cfe-validate/scripts/cfe-validate.py" -ExtensionPath "$DIR" -ConfigPath .local/ka-config
  python3 "$SKILLS/db-load-xml/scripts/db-load-xml.py" -InfoBasePath "$BASE_PATH" -UserName "$BASE_USER" \
    -ConfigDir "$DIR" -Extension "$EXT"
  python3 "$SKILLS/db-update/scripts/db-update.py" -InfoBasePath "$BASE_PATH" -UserName "$BASE_USER" -Extension "$EXT"
done
